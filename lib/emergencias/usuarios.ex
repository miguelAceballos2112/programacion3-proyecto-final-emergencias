defmodule Emergencias.Usuarios do
  @moduledoc """
  Gestión de usuarios: registro, conexión, permisos y actividad.

  Es un `GenServer`. Su estado tiene dos partes:
  - `usuarios`: mapa `%{nombre_de_usuario => %Usuario{}}`, guardado en `usuarios.txt`.
  - `sesiones`: mapa `%{nombre_de_usuario => pid}` de los usuarios conectados.
  La actividad de cada usuario se registra en `actividad.txt`.
  - Integrante 1: usuarios
  """

  use GenServer

  alias Emergencias.Permisos
  alias Emergencias.Persistencia
  alias Emergencias.Sesion
  alias Emergencias.Usuarios.Usuario

  @archivo_usuarios "usuarios.txt"
  @archivo_actividad "actividad.txt"

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
  """
  def conectar(usuario, contrasena, tipo, zona) do
    GenServer.call(__MODULE__, {:conectar, usuario, contrasena, tipo, zona})
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
  Registra una acción realizada por un usuario. No espera respuesta (`cast`).
  Los demás módulos la llaman cuando un usuario modifica algo.
  """
  def registrar_actividad(usuario, accion, detalle) do
    GenServer.cast(__MODULE__, {:actividad, usuario, accion, detalle})
  end

  @doc "Actividad de un usuario, como lista de `{fecha, accion, detalle}`."
  def actividad(usuario), do: GenServer.call(__MODULE__, {:actividad, usuario})

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    # Si el servidor se reinició, las sesiones anteriores quedaron sin dueño
    cerrar_sesiones_huerfanas()
    {:ok, %{usuarios: cargar_usuarios(), sesiones: %{}}}
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
  def handle_call({:conectar, usuario, contrasena, tipo, zona}, _from, estado) do
    {respuesta, nuevo_estado} =
      case Map.get(estado.usuarios, usuario) do
        nil -> registrar_y_conectar(estado, usuario, contrasena, tipo, zona)
        existente -> autenticar_y_conectar(estado, existente, contrasena)
      end

    {:reply, respuesta, nuevo_estado}
  end

  @impl true
  def handle_call({:desconectar, usuario}, _from, estado) do
    case Map.pop(estado.sesiones, usuario) do
      {nil, _sesiones} ->
        {:reply, {:error, :no_conectado}, estado}

      {pid, sesiones} ->
        Sesion.detener(pid)
        escribir_actividad(usuario, "disconnect", "")
        {:reply, :ok, %{estado | sesiones: sesiones}}
    end
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

  @impl true
  def handle_call({:actividad, usuario}, _from, estado) do
    registros =
      @archivo_actividad
      |> Persistencia.cargar()
      |> Enum.map(&Persistencia.separar/1)
      |> Enum.filter(fn campos -> Enum.at(campos, 1) == usuario end)
      |> Enum.map(fn [fecha, _usuario, accion, detalle] -> {fecha, accion, detalle} end)

    {:reply, registros, estado}
  end

  @impl true
  def handle_cast({:actividad, usuario, accion, detalle}, estado) do
    escribir_actividad(usuario, accion, detalle)
    {:noreply, estado}
  end

  # Si el proceso de una sesión termina, se quita al usuario de los conectados
  @impl true
  def handle_info({:DOWN, _referencia, :process, pid, _razon}, estado) do
    sesiones =
      Enum.reduce(estado.sesiones, %{}, fn {usuario, pid_sesion}, acumulado ->
        if pid_sesion == pid, do: acumulado, else: Map.put(acumulado, usuario, pid_sesion)
      end)

    {:noreply, %{estado | sesiones: sesiones}}
  end

  # ========== Funciones auxiliares privadas ==========

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

  defp escribir_actividad(usuario, accion, detalle) do
    linea = Persistencia.unir([ahora(), usuario, accion, Persistencia.limpiar(detalle)])
    Persistencia.agregar(@archivo_actividad, linea)
  end

  defp ahora, do: NaiveDateTime.local_now() |> NaiveDateTime.to_string()

  defp cerrar_sesiones_huerfanas do
    for {_id, pid, _tipo, _modulos} <-
          DynamicSupervisor.which_children(Emergencias.SupervisorSesiones) do
      Sesion.detener(pid)
    end
  end
end
