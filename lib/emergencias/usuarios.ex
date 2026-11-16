defmodule Emergencias.Usuarios do
  @moduledoc """
  Gestión de usuarios: registro, conexión, permisos y actividad.

  Es un `GenServer`. Su estado tiene tres partes:
  - `usuarios`: mapa `%{nombre_de_usuario => %Usuario{}}`, guardado en `usuarios.txt`.
  - `sesiones`: mapa `%{nombre_de_usuario => pid}` de los usuarios conectados.
  - `duenos`: mapa `%{pid => nombre_de_usuario}` con el proceso dueño de cada sesión
    (la consola o la pestaña del navegador desde donde se conectó). Se vigila con
    `Process.monitor`: si ese proceso termina, la sesión se cierra sola.
  La actividad de cada usuario la guarda la `Bitacora` en `actividad.txt`.
  - Integrante 1: usuarios
  """

  use GenServer

  alias Emergencias.Bitacora
  alias Emergencias.Permisos
  alias Emergencias.Persistencia
  alias Emergencias.Sesion
  alias Emergencias.Usuarios.Usuario

  @archivo_usuarios "usuarios.txt"

  # ========== API del cliente ==========

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra un usuario con todos sus datos.
  Retorna `{:ok, datos}` o `{:error, razon}`.
  """
  def registrar(usuario, contrasena, nombre_completo, tipo, zona) do
    GenServer.call(__MODULE__, {:registrar, usuario, contrasena, nombre_completo, tipo, zona})
  end

  @doc """
  Conecta a un usuario (`connect usuario contraseña tipo zona`).

  Si el usuario no existe, lo registra automáticamente con el tipo y la zona
  indicados. Si ya existe, valida la contraseña y usa los datos guardados.
  Retorna `{:ok, datos}` (con `registrado: true` si se acaba de crear) o
  `{:error, razon}`.

  `dueno` es opcional: el pid de la consola o de la pestaña que abre la sesión. Si
  se indica, cuando ese proceso termine la sesión se cierra automáticamente.
  """
  def conectar(usuario, contrasena, tipo, zona, dueno \\ nil) do
    GenServer.call(__MODULE__, {:conectar, usuario, contrasena, tipo, zona, dueno})
  end

  @doc "Desconecta a un usuario (`disconnect`). Retorna `:ok` o `{:error, :no_conectado}`."
  def desconectar(usuario), do: GenServer.call(__MODULE__, {:desconectar, usuario})

  @doc "Datos de la sesión de un usuario conectado."
  def sesion(usuario), do: GenServer.call(__MODULE__, {:sesion, usuario})

  @doc """
  Verifica que el usuario esté conectado y que su tipo pueda ejecutar la acción.
  Retorna `:ok`, `{:error, :no_conectado}` o `{:error, :sin_permiso}`.
  """
  def autorizar(usuario, accion), do: GenServer.call(__MODULE__, {:autorizar, usuario, accion})

  @doc """
  Registra una acción realizada por un usuario. No espera respuesta: se la envía a
  la `Bitacora` con `send`. El despachador de comandos la llama en cada comando.
  """
  def registrar_actividad(usuario, accion, detalle, resultado \\ :ok) do
    Bitacora.registrar(usuario, accion, detalle, resultado)
  end

  @doc "Actividad de un usuario, como lista de `{fecha, accion, detalle}`."
  def actividad(usuario) do
    usuario
    |> Bitacora.consultar()
    |> Enum.map(fn evento -> {evento.fecha, evento.accion, evento.detalle} end)
  end

  @doc "Lista los usuarios registrados (sin la huella de la contraseña), por nombre."
  def listar, do: GenServer.call(__MODULE__, :listar)

  @doc "Nombres de los usuarios conectados en este momento."
  def conectados, do: GenServer.call(__MODULE__, :conectados)

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    # Si el servidor se reinició, las sesiones anteriores quedaron sin dueño
    cerrar_sesiones_huerfanas()
    {:ok, %{usuarios: cargar_usuarios(), sesiones: %{}, duenos: %{}}}
  end

  @impl true
  def handle_call({:registrar, usuario, contrasena, nombre_completo, tipo, zona}, _from, estado) do
    with {:ok, nuevo} <- Usuario.nuevo(usuario, contrasena, nombre_completo, tipo, zona),
         :ok <- verificar_libre(estado.usuarios, usuario),
         usuarios = Map.put(estado.usuarios, usuario, nuevo),
         :ok <- guardar_usuarios(usuarios) do
      {:reply, {:ok, Usuario.publico(nuevo)}, %{estado | usuarios: usuarios}}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:conectar, usuario, contrasena, tipo, zona, dueno}, _from, estado) do
    {respuesta, nuevo_estado} =
      case Map.get(estado.usuarios, usuario) do
        nil -> registrar_y_conectar(estado, usuario, contrasena, tipo, zona)
        existente -> autenticar_y_conectar(estado, existente, contrasena)
      end

    {:reply, respuesta, vigilar_dueno(nuevo_estado, respuesta, usuario, dueno)}
  end

  @impl true
  def handle_call({:desconectar, usuario}, _from, estado) do
    {respuesta, nuevo_estado} = cerrar_sesion(estado, usuario, "")
    {:reply, respuesta, nuevo_estado}
  end

  @impl true
  def handle_call(:listar, _from, estado) do
    usuarios =
      estado.usuarios
      |> Map.values()
      |> Enum.sort_by(fn usuario -> usuario.usuario end)
      |> Enum.map(fn usuario -> Usuario.publico(usuario) end)

    {:reply, usuarios, estado}
  end

  @impl true
  def handle_call(:conectados, _from, estado) do
    {:reply, estado.sesiones |> Map.keys() |> Enum.sort(), estado}
  end

  @impl true
  def handle_call({:sesion, usuario}, _from, estado) do
    case datos_de_sesion(estado, usuario) do
      nil -> {:reply, {:error, :no_conectado}, estado}
      datos -> {:reply, {:ok, datos}, estado}
    end
  end

  @impl true
  def handle_call({:autorizar, usuario, accion}, _from, estado) do
    respuesta =
      case datos_de_sesion(estado, usuario) do
        nil -> {:error, :no_conectado}
        datos -> if Permisos.permitido?(datos.tipo, accion), do: :ok, else: {:error, :sin_permiso}
      end

    {:reply, respuesta, estado}
  end

  # Terminó un proceso vigilado. Puede ser:
  # - el dueño de una sesión (se cerró la consola o la pestaña): se cierra su sesión;
  # - el proceso de una sesión: se quita al usuario de los conectados.
  @impl true
  def handle_info({:DOWN, _referencia, :process, pid, _razon}, estado) do
    case Map.get(estado.duenos, pid) do
      nil ->
        sesiones =
          Enum.reduce(estado.sesiones, %{}, fn {usuario, pid_sesion}, acumulado ->
            if pid_sesion == pid, do: acumulado, else: Map.put(acumulado, usuario, pid_sesion)
          end)

        {:noreply, %{estado | sesiones: sesiones}}

      usuario ->
        {_respuesta, nuevo_estado} = cerrar_sesion(estado, usuario, "se cerró la ventana")
        {:noreply, nuevo_estado}
    end
  end

  # ========== Funciones auxiliares privadas ==========

  # Si la conexión funcionó y hay un proceso dueño, se vigila con un monitor
  defp vigilar_dueno(estado, {:ok, _datos}, usuario, dueno) when is_pid(dueno) do
    Process.monitor(dueno)
    %{estado | duenos: Map.put(estado.duenos, dueno, usuario)}
  end

  defp vigilar_dueno(estado, _respuesta, _usuario, _dueno), do: estado

  # Cierra la sesión de un usuario: detiene su proceso, lo registra en la Bitácora y
  # olvida a su dueño. Lo usan disconnect y el cierre de la consola o la pestaña.
  defp cerrar_sesion(estado, usuario, detalle) do
    case Map.pop(estado.sesiones, usuario) do
      {nil, _sesiones} ->
        {{:error, :no_conectado}, estado}

      {pid, sesiones} ->
        Sesion.detener(pid)
        escribir_actividad(usuario, "disconnect", detalle)

        duenos =
          Enum.reduce(estado.duenos, %{}, fn {pid_dueno, de}, acumulado ->
            if de == usuario, do: acumulado, else: Map.put(acumulado, pid_dueno, de)
          end)

        {:ok, %{estado | sesiones: sesiones, duenos: duenos}}
    end
  end

  # Usuario nuevo: se registra con su nombre de usuario como nombre completo y se conecta
  defp registrar_y_conectar(estado, usuario, contrasena, tipo, zona) do
    with {:ok, nuevo} <- Usuario.nuevo(usuario, contrasena, usuario, tipo, zona),
         usuarios = Map.put(estado.usuarios, usuario, nuevo),
         :ok <- guardar_usuarios(usuarios) do
      abrir_sesion(%{estado | usuarios: usuarios}, nuevo, true)
    else
      {:error, razon} -> {{:error, razon}, estado}
    end
  end

  # Usuario existente: se valida la contraseña antes de conectarlo
  defp autenticar_y_conectar(estado, existente, contrasena) do
    if Usuario.clave_correcta?(existente, contrasena) do
      abrir_sesion(estado, existente, false)
    else
      {{:error, :credenciales_invalidas}, estado}
    end
  end

  # Un usuario solo puede tener una sesión a la vez
  defp abrir_sesion(estado, %Usuario{} = usuario, registrado) do
    if Map.has_key?(estado.sesiones, usuario.usuario) do
      {{:error, :ya_conectado}, estado}
    else
      datos = Map.put(Usuario.publico(usuario), :conectado_desde, ahora())

      case Sesion.iniciar(datos) do
        {:ok, pid} ->
          Process.monitor(pid)
          escribir_actividad(usuario.usuario, "connect", "")
          sesiones = Map.put(estado.sesiones, usuario.usuario, pid)
          respuesta = {:ok, Map.put(Usuario.publico(usuario), :registrado, registrado)}
          {respuesta, %{estado | sesiones: sesiones}}

        {:error, razon} ->
          {{:error, {:sesion, razon}}, estado}
      end
    end
  end

  defp datos_de_sesion(estado, usuario) do
    case Map.get(estado.sesiones, usuario) do
      nil -> nil
      pid -> if Process.alive?(pid), do: Sesion.datos(pid), else: nil
    end
  end

  defp verificar_libre(usuarios, usuario) do
    if Map.has_key?(usuarios, usuario), do: {:error, :ya_existe}, else: :ok
  end

  defp cargar_usuarios do
    @archivo_usuarios
    |> Persistencia.cargar()
    |> Enum.reduce(%{}, fn linea, usuarios ->
      case Usuario.desde_linea(linea) do
        {:ok, usuario} -> Map.put(usuarios, usuario.usuario, usuario)
        {:error, _razon} -> usuarios
      end
    end)
  end

  defp guardar_usuarios(usuarios) do
    lineas = usuarios |> Map.values() |> Enum.map(&Usuario.a_linea/1)
    Persistencia.guardar(@archivo_usuarios, lineas)
  end

  # La actividad la escribe la Bitácora: aquí solo se le envía el evento
  defp escribir_actividad(usuario, accion, detalle) do
    Bitacora.registrar(usuario, accion, detalle, :ok)
  end

  defp ahora, do: NaiveDateTime.local_now() |> NaiveDateTime.to_string()

  defp cerrar_sesiones_huerfanas do
    for {_id, pid, _tipo, _modulos} <-
          DynamicSupervisor.which_children(Emergencias.SupervisorSesiones) do
      Sesion.detener(pid)
    end
  end
end
