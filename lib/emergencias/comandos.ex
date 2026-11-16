defmodule Emergencias.Comandos do
  @moduledoc """
  Despachador de comandos: el único punto de entrada del sistema.

  La consola (`Emergencias.CLI`), los nodos remotos y la interfaz web llaman a
  `ejecutar/3` con la línea que escribió el usuario. El despachador:

  1. separa la línea en palabras (`Comandos.Parser`);
  2. atiende aquí `connect`, `disconnect` y `help`;
  3. busca el módulo del comando (`Comandos.Base`, `Comandos.Logistica` o
     `Comandos.Personas`);
  4. verifica que el usuario esté conectado y que su tipo pueda ejecutar el comando
     (`Usuarios.autorizar/2`), y la regla de zona del coordinador
     (`Comandos.Alcance`);
  5. ejecuta el comando y traduce los errores a texto (`Errores`);
  6. registra la acción en la Bitácora, también si fue denegada o falló.

  El tipo y la zona del usuario nunca vienen de quien llama: se leen de su sesión en
  el servidor.
  - Integrante 1: comandos
  """

  alias Emergencias.Comandos.Alcance
  alias Emergencias.Comandos.Base
  alias Emergencias.Comandos.Logistica
  alias Emergencias.Comandos.Parser
  alias Emergencias.Comandos.Personas, as: ComandosPersonas
  alias Emergencias.Errores
  alias Emergencias.Permisos
  alias Emergencias.Usuarios

  @doc """
  Ejecuta una línea de comando.

  - `usuario`: el usuario conectado en esa consola o pestaña, o `nil` si nadie se ha
    conectado todavía.
  - `linea`: el texto, por ejemplo `register_need agua 30 critica centro "Punto 3"`.
  - `dueno`: el proceso de la consola o pestaña. Solo lo usa `connect`: si ese
    proceso termina, la sesión se cierra sola.

  Retorna `{:ok, texto, usuario}` o `{:error, texto, usuario}`. El usuario devuelto es
  el que queda conectado: cambia con `connect` y `disconnect`, y vuelve a `nil` si la
  sesión ya no existe.
  """
  def ejecutar(usuario, linea, dueno \\ nil) do
    case Parser.tokenizar(linea) do
      {:ok, []} ->
        {:error, Errores.mensaje(:comando_vacio), usuario}

      {:ok, [comando | argumentos]} ->
        despachar_seguro(String.downcase(comando), argumentos, usuario, dueno)

      {:error, razon} ->
        {:error, Errores.mensaje(razon), usuario}
    end
  end

  @doc "Todos los comandos que entiende el sistema."
  def comandos do
    ["connect", "disconnect"] ++
      Base.comandos() ++ Logistica.comandos() ++ ComandosPersonas.comandos()
  end

  # Si un servidor no responde (se cayó o tardó demasiado), GenServer.call termina con
  # un exit. Se atrapa para responder un error en lugar de tumbar la consola o la web.
  defp despachar_seguro(comando, argumentos, usuario, dueno) do
    try do
      despachar(comando, argumentos, usuario, dueno)
    catch
      :exit, _razon -> {:error, Errores.mensaje(:servidor_no_responde), usuario}
    end
  end

  # ========== Comandos que se atienden aquí ==========

  # connect con una sesión ya abierta en esta consola o pestaña
  defp despachar("connect", _argumentos, usuario, _dueno) when usuario != nil do
    {:error, Errores.mensaje(:sesion_abierta), usuario}
  end

  defp despachar("connect", argumentos, nil, dueno), do: conectar(argumentos, dueno)

  # help no necesita sesión
  defp despachar("help", argumentos, usuario, _dueno) do
    responder(Base.ejecutar("help", argumentos, usuario), "help", usuario)
  end

  # Cualquier otro comando necesita una sesión
  defp despachar(comando, _argumentos, nil, _dueno) do
    if Enum.member?(comandos(), comando) do
      {:error, Errores.mensaje(:no_conectado), nil}
    else
      {:error, Errores.mensaje(:comando_desconocido), nil}
    end
  end

  defp despachar("disconnect", _argumentos, usuario, _dueno) do
    case Usuarios.desconectar(usuario) do
      :ok -> {:ok, "Sesión cerrada. Hasta pronto, #{usuario}.", nil}
      {:error, razon} -> {:error, Errores.mensaje(razon), nil}
    end
  end

  # ========== Comandos de los módulos ==========

  defp despachar(comando, argumentos, usuario, _dueno) do
    resultado =
      with {:ok, modulo} <- modulo_de(comando),
           {:ok, accion} <- Permisos.accion(comando),
           :ok <- Usuarios.autorizar(usuario, accion),
           {:ok, sesion} <- Usuarios.sesion(usuario),
           :ok <- Alcance.revisar(sesion, comando, argumentos) do
        llamar(modulo, comando, argumentos, usuario)
      end

    registrar(usuario, comando, argumentos, resultado)
    responder(resultado, comando, usuario)
  end

  # ========== Funciones auxiliares privadas ==========

  # connect usuario contraseña [tipo] [zona] [nombre="..."]
  # Para un usuario nuevo se necesitan el tipo y la zona; para uno existente bastan
  # el usuario y la contraseña.
  defp conectar(argumentos, dueno) do
    nombre = opcion(argumentos, "nombre")
    posicionales = Enum.reject(argumentos, fn argumento -> String.contains?(argumento, "=") end)

    case posicionales do
      [usuario, clave] -> abrir_sesion(usuario, clave, "", "", nombre, dueno)
      [usuario, clave, tipo] -> abrir_sesion(usuario, clave, tipo, "", nombre, dueno)
      [usuario, clave, tipo, zona] -> abrir_sesion(usuario, clave, tipo, zona, nombre, dueno)
      _otro -> responder({:error, :argumentos_invalidos}, "connect", nil)
    end
  end

  defp abrir_sesion(usuario, clave, tipo, zona, nombre, dueno) do
    # Con nombre= se registra primero con el nombre completo; si ya existía, no pasa
    # nada y la conexión valida la contraseña como siempre
    nuevo =
      nombre != nil and
        match?({:ok, _datos}, Usuarios.registrar(usuario, clave, nombre, tipo, zona))

    case Usuarios.conectar(usuario, clave, tipo, zona, dueno) do
      {:ok, datos} -> {:ok, bienvenida(%{datos | registrado: datos.registrado or nuevo}), usuario}
      {:error, razon} -> {:error, Errores.mensaje(razon), nil}
    end
  end

  defp bienvenida(datos) do
    registro = if datos.registrado, do: " Usuario nuevo registrado.", else: ""

    "Hola, #{datos.nombre_completo}. Conectado como #{datos.tipo} de la zona #{datos.zona}.#{registro}"
  end

  defp modulo_de(comando) do
    cond do
      Enum.member?(Base.comandos(), comando) -> {:ok, Base}
      Enum.member?(Logistica.comandos(), comando) -> {:ok, Logistica}
      Enum.member?(ComandosPersonas.comandos(), comando) -> {:ok, ComandosPersonas}
      true -> {:error, :comando_desconocido}
    end
  end

  # El exit se atrapa también aquí para que el fallo quede registrado en la Bitácora
  defp llamar(modulo, comando, argumentos, usuario) do
    try do
      modulo.ejecutar(comando, argumentos, usuario)
    catch
      :exit, _razon -> {:error, :servidor_no_responde}
    end
  end

  # Toda orden queda en la Bitácora con su resultado: ok, error o denegado
  defp registrar(usuario, comando, argumentos, resultado) do
    detalle = Enum.join(argumentos, " ")

    case resultado do
      {:ok, _texto} ->
        Usuarios.registrar_actividad(usuario, comando, detalle, :ok)

      {:error, razon} when razon in [:sin_permiso, :fuera_de_zona] ->
        Usuarios.registrar_actividad(usuario, comando, "#{detalle} (#{razon})", :denegado)

      {:error, razon} ->
        Usuarios.registrar_actividad(usuario, comando, "#{detalle} (#{razon})", :error)
    end
  end

  defp responder({:ok, texto}, _comando, usuario), do: {:ok, texto, usuario}

  # La sesión ya no existe (por ejemplo, se reinició el servidor de usuarios)
  defp responder({:error, :no_conectado}, _comando, _usuario) do
    {:error, Errores.mensaje(:no_conectado), nil}
  end

  # Si faltan o sobran datos, se muestra cómo se usa el comando
  defp responder({:error, :argumentos_invalidos}, comando, usuario) do
    {:error, "#{Errores.mensaje(:argumentos_invalidos)} Uso: #{Base.uso(comando)}", usuario}
  end

  defp responder({:error, razon}, _comando, usuario),
    do: {:error, Errores.mensaje(razon), usuario}

  # Caso base: no quedan argumentos, la opción no se dio
  defp opcion([], _clave), do: nil

  # Caso recursivo: si el primero es "clave=valor" devuelve el valor; si no, sigue
  defp opcion([head | tail], clave) do
    case String.split(head, "=", parts: 2) do
      [nombre, valor] when nombre == clave -> valor
      _otro -> opcion(tail, clave)
    end
  end
end
