defmodule Emergencias.Necesidades do
  @moduledoc """
  GenServer de necesidades puntuales.

  Registra solicitudes de ayuda, las ordena por prioridad, les asigna recursos
  (pidiéndoselos a `Emergencias.Recursos`) y controla sus cambios de estado.
  - Integrante 2: logística
  """

  use GenServer

  alias Emergencias.Albergues
  alias Emergencias.Necesidades.Necesidad
  alias Emergencias.Necesidades.Prioridad
  alias Emergencias.Persistencia
  alias Emergencias.Personas
  alias Emergencias.Recursos
  alias Emergencias.Recursos.Recurso
  alias Emergencias.Validaciones
  alias Emergencias.Zonas

  @archivo "necesidades.txt"

  # ========== API del cliente ==========

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra una necesidad (`register_need`). `responsable` es el usuario conectado.

  `destino` es opcional: `{:punto, codigo}`, `{:albergue, codigo}`,
  `{:persona, documento}`, `{:familia, codigo}` o `{:zona, codigo}`. Sin destino, la
  necesidad queda asociada a su zona.
  """
  def registrar(tipo, cantidad, prioridad, zona, descripcion, responsable, destino \\ nil) do
    GenServer.call(
      __MODULE__,
      {:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable, destino}
    )
  end

  @doc "Busca una necesidad por id."
  def consultar(id), do: GenServer.call(__MODULE__, {:consultar, id})

  @doc "Zona de una necesidad, para la regla de zona del coordinador."
  def zona_de(id), do: GenServer.call(__MODULE__, {:zona_de, id})

  @doc """
  Necesidades ordenadas por prioridad (`list_needs`).

  Filtros opcionales: `zona`, `tipo`, `prioridad` y `estado`, por ejemplo
  `[zona: "centro", prioridad: "critica"]`.
  """
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, Enum.to_list(filtros)})

  @doc "Necesidades cuyo destino es un albergue."
  def por_albergue(codigo), do: GenServer.call(__MODULE__, {:por_albergue, codigo})

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    necesidades = cargar()
    {:ok, %{necesidades: necesidades, contador: Enum.count(necesidades)}}
  end

  @impl true
  def handle_call(
        {:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable, destino},
        _from,
        estado
      ) do
    with {:ok, tipo} <- Validaciones.opcion(tipo, Recurso.categorias(), :tipo_invalido),
         :ok <- Validaciones.entero_positivo(cantidad, :cantidad_invalida),
         {:ok, prioridad} <-
           Validaciones.opcion(prioridad, Prioridad.lista(), :prioridad_invalida),
         :ok <- zona_existe(zona),
         :ok <- Validaciones.texto(descripcion, :descripcion_invalida),
         :ok <- Validaciones.texto(responsable, :responsable_invalido),
         {:ok, destino} <- validar_destino(destino, zona) do
      contador = estado.contador + 1

      necesidad =
        Necesidad.crear(
          nuevo_id(contador),
          tipo,
          cantidad,
          prioridad,
          zona,
          descripcion,
          responsable,
          destino
        )

      nuevo_estado = %{
        estado
        | necesidades: Map.put(estado.necesidades, necesidad.id, necesidad),
          contador: contador
      }

      guardar(nuevo_estado)
      {:reply, {:ok, necesidad}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:consultar, id}, _from, estado), do: {:reply, buscar(estado, id), estado}

  @impl true
  def handle_call({:zona_de, id}, _from, estado) do
    case buscar(estado, id) do
      {:ok, necesidad} -> {:reply, {:ok, necesidad.zona}, estado}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:listar, filtros}, _from, estado) do
    lista = estado.necesidades |> Map.values() |> filtrar(filtros) |> Prioridad.ordenar()
    {:reply, lista, estado}
  end

  @impl true
  def handle_call({:por_albergue, codigo}, _from, estado) do
    lista =
      estado.necesidades
      |> Map.values()
      |> Enum.filter(fn necesidad -> necesidad.destino == {:albergue, codigo} end)
      |> Prioridad.ordenar()

    {:reply, lista, estado}
  end

  # ========== Funciones auxiliares privadas ==========

  # N001, N002... con tres cifras, para que el orden por id sea el orden de llegada
  defp nuevo_id(numero) when numero < 10, do: "N00#{numero}"
  defp nuevo_id(numero) when numero < 100, do: "N0#{numero}"
  defp nuevo_id(numero), do: "N#{numero}"

  defp buscar(estado, id) do
    case Map.get(estado.necesidades, id) do
      nil -> {:error, :necesidad_no_existe}
      necesidad -> {:ok, necesidad}
    end
  end

  defp zona_existe(zona) do
    if Zonas.existe?(zona), do: :ok, else: {:error, :zona_no_existe}
  end

  # Sin destino, la necesidad queda asociada a su zona
  defp validar_destino(nil, zona), do: {:ok, {:zona, zona}}

  defp validar_destino({tipo, codigo}, zona) do
    with {:ok, tipo} <- Validaciones.opcion(tipo, Necesidad.tipos_destino(), :destino_invalido),
         :ok <- Validaciones.texto(codigo, :destino_invalido),
         :ok <- destino_existe(tipo, codigo, zona) do
      {:ok, {tipo, codigo}}
    end
  end

  defp validar_destino(_destino, _zona), do: {:error, :destino_invalido}

  # Cada destino se valida contra el módulo que lo guarda
  defp destino_existe(:zona, codigo, _zona), do: existe(Zonas.existe?(codigo), :zona_no_existe)

  defp destino_existe(:punto, codigo, zona),
    do: existe(Recursos.punto_existe?(zona, codigo), :punto_no_existe)

  defp destino_existe(:albergue, codigo, _zona),
    do: existe(Albergues.existe?(codigo), :albergue_no_existe)

  defp destino_existe(:persona, documento, _zona),
    do: existe(Personas.existe?(documento), :persona_no_existe)

  defp destino_existe(:familia, codigo, _zona),
    do: existe(Personas.existe_familia?(codigo), :familia_no_existe)

  defp existe(true, _error), do: :ok
  defp existe(false, error), do: {:error, error}

  # Caso base: no quedan filtros por aplicar
  defp filtrar(necesidades, []), do: necesidades

  # Caso recursivo: se aplica el primer filtro y se sigue con los demás
  defp filtrar(necesidades, [{campo, valor} | tail]) do
    necesidades
    |> Enum.filter(fn necesidad -> coincide?(necesidad, "#{campo}", "#{valor}") end)
    |> filtrar(tail)
  end

  defp coincide?(necesidad, "zona", valor), do: necesidad.zona == valor
  defp coincide?(necesidad, "tipo", valor), do: "#{necesidad.tipo}" == valor
  defp coincide?(necesidad, "prioridad", valor), do: "#{necesidad.prioridad}" == valor
  defp coincide?(necesidad, "estado", valor), do: "#{necesidad.estado}" == valor
  defp coincide?(_necesidad, _campo, _valor), do: false

  defp cargar do
    @archivo
    |> Persistencia.cargar()
    |> Enum.map(fn linea -> Necesidad.desde_fila(Persistencia.separar(linea)) end)
    |> Enum.reduce(%{}, fn necesidad, necesidades ->
      Map.put(necesidades, necesidad.id, necesidad)
    end)
  end

  defp guardar(estado) do
    lineas =
      estado.necesidades
      |> Map.values()
      |> Enum.sort_by(fn necesidad -> necesidad.id end)
      |> Enum.map(fn necesidad -> Persistencia.unir(Necesidad.a_fila(necesidad)) end)

    Persistencia.guardar(@archivo, lineas)
  end
end
