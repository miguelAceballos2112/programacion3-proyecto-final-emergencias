defmodule Emergencias.Albergues do
  @moduledoc """
  GenServer de albergues: registro, ingreso y salida de personas, cupos y reporte de
  ocupación.

  El ingreso se decide dentro de un `handle_call`, así que aunque muchas personas
  lleguen al mismo tiempo la ocupación nunca supera la capacidad máxima.

  El estado de una persona en el albergue lo cambia este módulo con
  `Personas.cambiar_estado/3` (Integrante 3).
  - Integrante 2: logística
  """

  use GenServer

  alias Emergencias.Albergues.Albergue
  alias Emergencias.Necesidades
  alias Emergencias.Persistencia
  alias Emergencias.Personas
  alias Emergencias.Recursos
  alias Emergencias.Validaciones
  alias Emergencias.Zonas

  @archivo "albergues.txt"

  # ========== API del cliente ==========

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra un albergue (`register_shelter`). `ocupacion_inicial` son las personas que ya
  están en el albergue al registrarlo. También queda como centro de apoyo de tipo
  albergue, para poder recibir recursos.
  """
  def registrar(codigo, nombre, zona, capacidad, ocupacion_inicial \\ 0) do
    GenServer.call(__MODULE__, {:registrar, codigo, nombre, zona, capacidad, ocupacion_inicial})
  end

  @doc "Ingreso de una persona registrada (`register_entry`)."
  def ingresar(codigo, documento), do: GenServer.call(__MODULE__, {:ingresar, codigo, documento})

  @doc "Salida de una persona (`register_exit`)."
  def salir(codigo, documento), do: GenServer.call(__MODULE__, {:salir, codigo, documento})

  @doc "Busca un albergue por código."
  def buscar(codigo), do: GenServer.call(__MODULE__, {:buscar, codigo})

  @doc "Indica si existe un albergue con ese código."
  def existe?(codigo), do: GenServer.call(__MODULE__, {:existe, codigo})

  @doc "Zona de un albergue, para la regla de zona del coordinador."
  def zona_de(codigo), do: GenServer.call(__MODULE__, {:zona_de, codigo})

  @doc "Todos los albergues, ordenados por código."
  def listar, do: GenServer.call(__MODULE__, :listar)

  @doc "Reporte de los albergues con mayor porcentaje de ocupación (`shelter_report`)."
  def mas_ocupados(cantidad \\ 5), do: GenServer.call(__MODULE__, {:mas_ocupados, cantidad})

  @doc "Cupos disponibles de un albergue."
  def cupos(codigo) do
    case buscar(codigo) do
      {:ok, albergue} -> {:ok, Albergue.cupos(albergue)}
      {:error, razon} -> {:error, razon}
    end
  end

  @doc """
  Estado completo de un albergue (`check_shelter`): ocupación, cupos y los recursos y
  necesidades asociados. Se arma en el proceso que llama, no dentro del servidor, para
  que Albergues no tenga que esperar a otros servidores.
  """
  def consultar(codigo) do
    case buscar(codigo) do
      {:ok, albergue} ->
        {:ok,
         %{
           albergue: albergue,
           ocupacion: Albergue.ocupacion(albergue),
           cupos: Albergue.cupos(albergue),
           porcentaje: Albergue.porcentaje(albergue),
           recursos: Recursos.por_centro(albergue.codigo),
           necesidades: Necesidades.por_albergue(albergue.codigo)
         }}

      {:error, razon} ->
        {:error, razon}
    end
  end

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok), do: {:ok, cargar()}

  @impl true
  def handle_call({:registrar, codigo, nombre, zona, capacidad, inicial}, _from, albergues) do
    with :ok <- Validaciones.texto(codigo, :codigo_invalido),
         :ok <- libre(albergues, codigo),
         :ok <- Validaciones.texto(nombre, :nombre_invalido),
         :ok <- zona_existe(zona),
         :ok <- Validaciones.entero_positivo(capacidad, :capacidad_invalida),
         :ok <- ocupacion_valida(inicial, capacidad),
         :ok <- registrar_como_centro(codigo, nombre, zona) do
      albergue = Albergue.crear(codigo, nombre, zona, capacidad, inicial)
      {:reply, {:ok, albergue}, guardar(albergues, albergue)}
    else
      {:error, razon} -> {:reply, {:error, razon}, albergues}
    end
  end

  @impl true
  def handle_call({:ingresar, codigo, documento}, _from, albergues) do
    with {:ok, albergue} <- buscar_albergue(albergues, codigo),
         :ok <- Validaciones.texto(documento, :documento_invalido),
         :ok <- sin_albergue(albergues, documento),
         {:ok, actualizado} <- Albergue.ingresar(albergue, documento),
         {:ok, _persona} <- Personas.obtener(documento),
         {:ok, _persona} <-
           Personas.cambiar_estado(documento, :en_albergue, "Ingresó a #{albergue.codigo}") do
      {:reply, {:ok, actualizado}, guardar(albergues, actualizado)}
    else
      {:error, razon} -> {:reply, {:error, razon}, albergues}
    end
  end

  @impl true
  def handle_call({:salir, codigo, documento}, _from, albergues) do
    with {:ok, albergue} <- buscar_albergue(albergues, codigo),
         {:ok, actualizado} <- Albergue.salir(albergue, documento) do
      actualizar_persona_al_salir(documento, albergue.codigo)
      {:reply, {:ok, actualizado}, guardar(albergues, actualizado)}
    else
      {:error, razon} -> {:reply, {:error, razon}, albergues}
    end
  end

  @impl true
  def handle_call({:buscar, codigo}, _from, albergues) do
    {:reply, buscar_albergue(albergues, codigo), albergues}
  end

  @impl true
  def handle_call({:existe, codigo}, _from, albergues) do
    {:reply, Map.has_key?(albergues, codigo), albergues}
  end

  @impl true
  def handle_call({:zona_de, codigo}, _from, albergues) do
    case buscar_albergue(albergues, codigo) do
      {:ok, albergue} -> {:reply, {:ok, albergue.zona}, albergues}
      {:error, razon} -> {:reply, {:error, razon}, albergues}
    end
  end

  @impl true
  def handle_call(:listar, _from, albergues) do
    lista = albergues |> Map.values() |> Enum.sort_by(fn albergue -> albergue.codigo end)
    {:reply, lista, albergues}
  end

  @impl true
  def handle_call({:mas_ocupados, cantidad}, _from, albergues) do
    lista =
      albergues
      |> Map.values()
      |> Albergue.ordenar_por_ocupacion()
      |> Enum.take(cantidad)

    {:reply, lista, albergues}
  end

  # ========== Funciones auxiliares privadas ==========

  defp libre(albergues, codigo) do
    if Map.has_key?(albergues, codigo), do: {:error, :ya_existe}, else: :ok
  end

  defp zona_existe(zona) do
    if Zonas.existe?(zona), do: :ok, else: {:error, :zona_no_existe}
  end

  # La ocupación inicial va de 0 hasta la capacidad
  defp ocupacion_valida(inicial, capacidad) do
    case Validaciones.entero_no_negativo(inicial, :ocupacion_invalida) do
      :ok -> if inicial <= capacidad, do: :ok, else: {:error, :ocupacion_invalida}
      {:error, razon} -> {:error, razon}
    end
  end

  defp buscar_albergue(albergues, codigo) do
    case Map.get(albergues, codigo) do
      nil -> {:error, :albergue_no_existe}
      albergue -> {:ok, albergue}
    end
  end

  # Una persona no puede estar en dos albergues al mismo tiempo
  defp sin_albergue(albergues, documento) do
    ocupado =
      Enum.any?(Map.values(albergues), fn albergue -> Albergue.esta?(albergue, documento) end)

    if ocupado, do: {:error, :ya_esta_en_un_albergue}, else: :ok
  end

  # Si el centro ya existía (por ejemplo, el servidor cayó después de crearlo), se usa
  defp registrar_como_centro(codigo, nombre, zona) do
    case Recursos.registrar_centro_albergue(codigo, nombre, zona) do
      {:ok, _centro} -> :ok
      {:error, :ya_existe} -> :ok
      {:error, razon} -> {:error, razon}
    end
  end

  defp actualizar_persona_al_salir(documento, codigo) do
    case Personas.obtener(documento) do
      {:ok, %{estado: :en_albergue}} ->
        Personas.cambiar_estado(documento, :trasladada, "Salió de #{codigo}")

      _otro ->
        :ok
    end
  end

  defp guardar(albergues, albergue) do
    nuevos = Map.put(albergues, albergue.codigo, albergue)

    lineas =
      nuevos
      |> Map.values()
      |> Enum.sort_by(fn albergue -> albergue.codigo end)
      |> Enum.map(fn albergue -> Persistencia.unir(Albergue.a_fila(albergue)) end)

    Persistencia.guardar(@archivo, lineas)
    nuevos
  end

  defp cargar do
    @archivo
    |> Persistencia.cargar()
    |> Enum.map(fn linea -> Albergue.desde_fila(Persistencia.separar(linea)) end)
    |> Enum.reduce(%{}, fn albergue, albergues ->
      Map.put(albergues, albergue.codigo, albergue)
    end)
  end
end
