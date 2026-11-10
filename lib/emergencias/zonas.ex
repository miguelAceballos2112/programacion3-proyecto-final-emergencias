defmodule Emergencias.Zonas do
  @moduledoc """
  Gestión de zonas afectadas, sus sectores y sus puntos de atención.

  Es un `GenServer`. Su estado es un mapa `%{codigo => %Zona{}}`, guardado en
  `zonas.txt`. Los demás módulos asocian albergues, necesidades, recursos y reportes
  a una zona guardando su código, y usan `existe?/1` para verificar que exista.
  - Integrante 1: zonas
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Validaciones
  alias Emergencias.Zonas.Archivo
  alias Emergencias.Zonas.Estadisticas
  alias Emergencias.Zonas.PuntoAtencion
  alias Emergencias.Zonas.Sector
  alias Emergencias.Zonas.Zona

  @archivo "zonas.txt"

  # ========== API del cliente ==========

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra una zona (`register_zone codigo nombre nivel`) con su nivel de afectación
  y el número estimado de personas afectadas.
  Retorna `{:ok, zona}` o `{:error, razon}`.
  """
  def registrar_zona(codigo, nombre, nivel, personas \\ 0) do
    GenServer.call(__MODULE__, {:registrar_zona, codigo, nombre, nivel, personas})
  end

  @doc "Registra un sector dentro de una zona existente."
  def registrar_sector(codigo_zona, codigo, nombre, nivel, personas \\ 0) do
    GenServer.call(__MODULE__, {:registrar_sector, codigo_zona, codigo, nombre, nivel, personas})
  end

  @doc "Registra un punto de atención dentro de un sector existente."
  def registrar_punto(codigo_zona, codigo_sector, codigo, nombre, personas \\ 0) do
    GenServer.call(
      __MODULE__,
      {:registrar_punto, codigo_zona, codigo_sector, codigo, nombre, personas}
    )
  end

  @doc "Busca una zona por su código. Retorna `{:ok, zona}` o `{:error, :zona_no_existe}`."
  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})

  @doc "Indica si existe una zona con ese código."
  def existe?(codigo), do: GenServer.call(__MODULE__, {:existe, codigo})

  @doc "Lista todas las zonas, ordenadas por código."
  def listar, do: GenServer.call(__MODULE__, :listar)

  @doc """
  Estado general de una zona: sus datos y sus estadísticas acumuladas.
  Retorna `{:ok, %{zona: zona, estadisticas: resumen}}` o `{:error, :zona_no_existe}`.
  """
  def estado(codigo), do: GenServer.call(__MODULE__, {:estado, codigo})

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    zonas = @archivo |> Persistencia.cargar() |> Archivo.desde_lineas()
    {:ok, %{zonas: zonas}}
  end

  @impl true
  def handle_call({:registrar_zona, codigo, nombre, nivel, personas}, _from, estado) do
    with :ok <- Validaciones.texto(codigo, :codigo_invalido),
         :ok <- Validaciones.texto(nombre, :nombre_invalido),
         {:ok, nivel} <- Zona.normalizar_nivel(nivel),
         :ok <- Validaciones.entero_no_negativo(personas, :personas_invalidas),
         :ok <- verificar_zona_libre(estado.zonas, codigo),
         zona = %Zona{codigo: codigo, nombre: nombre, nivel: nivel, personas_afectadas: personas},
         zonas = Map.put(estado.zonas, codigo, zona),
         :ok <- guardar(zonas) do
      {:reply, {:ok, zona}, %{estado | zonas: zonas}}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call(
        {:registrar_sector, codigo_zona, codigo, nombre, nivel, personas},
        _from,
        estado
      ) do
    with {:ok, zona} <- buscar_zona(estado.zonas, codigo_zona),
         :ok <- Validaciones.texto(codigo, :codigo_invalido),
         :ok <- Validaciones.texto(nombre, :nombre_invalido),
         {:ok, nivel} <- Zona.normalizar_nivel(nivel),
         :ok <- Validaciones.entero_no_negativo(personas, :personas_invalidas),
         :ok <- verificar_sector_libre(zona, codigo),
         sector = %Sector{
           codigo: codigo,
           nombre: nombre,
           nivel: nivel,
           personas_afectadas: personas
         },
         zona_nueva = Zona.agregar_sector(zona, sector),
         zonas = Map.put(estado.zonas, codigo_zona, zona_nueva),
         :ok <- guardar(zonas) do
      {:reply, {:ok, sector}, %{estado | zonas: zonas}}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call(
        {:registrar_punto, codigo_zona, codigo_sector, codigo, nombre, personas},
        _from,
        estado
      ) do
    with {:ok, zona} <- buscar_zona(estado.zonas, codigo_zona),
         {:ok, sector} <- buscar_sector(zona, codigo_sector),
         :ok <- Validaciones.texto(codigo, :codigo_invalido),
         :ok <- Validaciones.texto(nombre, :nombre_invalido),
         :ok <- Validaciones.entero_no_negativo(personas, :personas_invalidas),
         :ok <- verificar_punto_libre(sector, codigo),
         punto = %PuntoAtencion{codigo: codigo, nombre: nombre, personas_afectadas: personas},
         zona_nueva = Zona.agregar_punto(zona, codigo_sector, punto),
         zonas = Map.put(estado.zonas, codigo_zona, zona_nueva),
         :ok <- guardar(zonas) do
      {:reply, {:ok, punto}, %{estado | zonas: zonas}}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:obtener, codigo}, _from, estado) do
    {:reply, buscar_zona(estado.zonas, codigo), estado}
  end

  @impl true
  def handle_call({:existe, codigo}, _from, estado) do
    {:reply, Map.has_key?(estado.zonas, codigo), estado}
  end

  @impl true
  def handle_call(:listar, _from, estado) do
    zonas = estado.zonas |> Map.values() |> Enum.sort_by(fn zona -> zona.codigo end)
    {:reply, zonas, estado}
  end

  @impl true
  def handle_call({:estado, codigo}, _from, estado) do
    respuesta =
      with {:ok, zona} <- buscar_zona(estado.zonas, codigo) do
        {:ok, %{zona: zona, estadisticas: Estadisticas.resumen(zona)}}
      end

    {:reply, respuesta, estado}
  end

  # ========== Funciones auxiliares privadas ==========

  defp buscar_zona(zonas, codigo) do
    case Map.get(zonas, codigo) do
      nil -> {:error, :zona_no_existe}
      zona -> {:ok, zona}
    end
  end

  defp buscar_sector(zona, codigo_sector) do
    case Zona.buscar_sector(zona, codigo_sector) do
      nil -> {:error, :sector_no_existe}
      sector -> {:ok, sector}
    end
  end

  defp verificar_zona_libre(zonas, codigo) do
    if Map.has_key?(zonas, codigo), do: {:error, :ya_existe}, else: :ok
  end

  defp verificar_sector_libre(zona, codigo) do
    if Zona.buscar_sector(zona, codigo), do: {:error, :ya_existe}, else: :ok
  end

  defp verificar_punto_libre(sector, codigo) do
    if Zona.buscar_punto(sector, codigo), do: {:error, :ya_existe}, else: :ok
  end

  defp guardar(zonas), do: Persistencia.guardar(@archivo, Archivo.a_lineas(zonas))
end
