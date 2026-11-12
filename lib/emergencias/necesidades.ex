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

  @doc "Asigna recursos de una categoría a una necesidad (`assign_resource`)."
  def asignar_recurso(id, categoria, cantidad) do
    GenServer.call(__MODULE__, {:asignar, id, categoria, cantidad})
  end

  @doc """
  Cambia el estado de una necesidad respetando las transiciones válidas
  (`update_need_status`). Si pasa a cancelada, devuelve lo reservado como `cancelar/1`.
  """
  def cambiar_estado(id, estado), do: GenServer.call(__MODULE__, {:cambiar_estado, id, estado})

  @doc """
  Cancela una necesidad (`cancel_need`). Si estaba pendiente o asignada, devuelve a los
  centros lo que se le había reservado; si estaba en atención, los recursos ya se usaron.
  """
  def cancelar(id), do: cambiar_estado(id, :cancelada)

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

  @doc "Necesidades abiertas (pendientes, asignadas o en atención), por prioridad (`pending_needs`)."
  def pendientes, do: GenServer.call(__MODULE__, :pendientes)

  @doc "La necesidad sin atender más urgente, de una zona o de todas (`next_need`)."
  def siguiente(zona \\ nil), do: GenServer.call(__MODULE__, {:siguiente, zona})

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
  def handle_call({:asignar, id, categoria, cantidad}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado, id),
         {:ok, categoria} <-
           Validaciones.opcion(categoria, Recurso.categorias(), :categoria_invalida),
         :ok <- misma_categoria(necesidad, categoria),
         :ok <- Validaciones.entero_positivo(cantidad, :cantidad_invalida),
         :ok <- Necesidad.validar_asignacion(necesidad, cantidad),
         {:ok, _tomas} <- Recursos.reservar(categoria, cantidad, necesidad.zona, necesidad.id) do
      actualizada = Necesidad.registrar_asignacion(necesidad, cantidad)
      {:reply, {:ok, actualizada}, actualizar(estado, actualizada)}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  # Orden seguro: validar la transición, devolver en Recursos (si se cancela) y solo
  # entonces cambiar el estado propio y guardar
  @impl true
  def handle_call({:cambiar_estado, id, nuevo}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado, id),
         {:ok, nuevo} <- Validaciones.opcion(nuevo, Necesidad.estados(), :estado_invalido),
         {:ok, actualizada} <- Necesidad.cambiar_estado(necesidad, nuevo),
         :ok <- devolver_si_cancela(necesidad, nuevo) do
      {:reply, {:ok, actualizada}, actualizar(estado, actualizada)}
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
  def handle_call(:pendientes, _from, estado) do
    lista =
      estado.necesidades
      |> Map.values()
      |> Enum.filter(fn necesidad -> Necesidad.abierta?(necesidad) end)
      |> Prioridad.ordenar()

    {:reply, lista, estado}
  end

  @impl true
  def handle_call({:siguiente, zona}, _from, estado) do
    candidatas =
      estado.necesidades
      |> Map.values()
      |> Enum.filter(fn necesidad -> necesidad.estado in [:pendiente, :asignada] end)
      |> Enum.filter(fn necesidad -> de_la_zona?(necesidad, zona) end)

    {:reply, Prioridad.mas_urgente(candidatas), estado}
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

  defp misma_categoria(necesidad, categoria) do
    if necesidad.tipo == categoria, do: :ok, else: {:error, :categoria_no_corresponde}
  end

  defp devolver_si_cancela(necesidad, :cancelada) do
    if Necesidad.devuelve_al_cancelar?(necesidad) do
      {:ok, _lotes} = Recursos.devolver(necesidad.id)
    end

    :ok
  end

  defp devolver_si_cancela(_necesidad, _nuevo), do: :ok

  defp de_la_zona?(_necesidad, nil), do: true
  defp de_la_zona?(necesidad, zona), do: necesidad.zona == zona

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

  defp actualizar(estado, necesidad) do
    nuevo_estado = %{estado | necesidades: Map.put(estado.necesidades, necesidad.id, necesidad)}
    guardar(nuevo_estado)
    nuevo_estado
  end

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
