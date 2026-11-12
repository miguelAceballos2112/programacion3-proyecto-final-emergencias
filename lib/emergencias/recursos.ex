defmodule Emergencias.Recursos do
  @moduledoc """
  GenServer de recursos y centros de apoyo.

  Guarda los centros de apoyo, los recursos con su inventario por centro y el historial
  de movimientos. Las operaciones que cambian el inventario se deciden dentro de un
  `handle_call`: la verificación ("¿alcanza?") y el descuento ocurren en la misma
  llamada, así que aunque lleguen muchas solicitudes al mismo tiempo la cantidad
  asignada nunca supera el inventario.
  - Integrante 2: logística
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Recursos.Centro
  alias Emergencias.Recursos.Movimiento
  alias Emergencias.Recursos.Recurso
  alias Emergencias.Validaciones
  alias Emergencias.Zonas
  alias Emergencias.Zonas.Zona

  @archivo_centros "centros.txt"
  @archivo_recursos "recursos.txt"
  @archivo_movimientos "movimientos.txt"

  # ========== API del cliente ==========

  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra un centro de apoyo (`register_center`) de tipo `acopio` o `punto_atencion`
  en una zona existente. Un punto de atención usa el código de un punto de esa zona.
  """
  def registrar_centro(codigo, nombre, tipo, zona) do
    GenServer.call(__MODULE__, {:registrar_centro, codigo, nombre, tipo, zona})
  end

  @doc "Registra un recurso con su cantidad inicial en un centro (`register_resource`)."
  def registrar(codigo, categoria, cantidad, unidad, centro, nombre \\ nil) do
    GenServer.call(__MODULE__, {:registrar, codigo, categoria, cantidad, unidad, centro, nombre})
  end

  @doc "Entrada de inventario (`add_stock`): suma unidades de un recurso en un centro."
  def entrada(codigo, centro, cantidad) do
    GenServer.call(__MODULE__, {:entrada, codigo, centro, cantidad})
  end

  @doc "Salida de inventario (`remove_stock`): resta unidades de un recurso en un centro."
  def salida(codigo, centro, cantidad) do
    GenServer.call(__MODULE__, {:salida, codigo, centro, cantidad})
  end

  @doc "Mueve unidades de un centro a otro en una sola operación (`transfer_resource`)."
  def transferir(codigo, origen, destino, cantidad) do
    GenServer.call(__MODULE__, {:transferir, codigo, origen, destino, cantidad})
  end

  @doc "Busca un recurso por código."
  def consultar(codigo), do: GenServer.call(__MODULE__, {:consultar, codigo})

  @doc "Todos los recursos, ordenados por código (`list_resources`)."
  def listar, do: GenServer.call(__MODULE__, :listar)

  @doc "Todos los centros de apoyo, ordenados por código."
  def listar_centros, do: GenServer.call(__MODULE__, :listar_centros)

  @doc "Indica si existe un centro de apoyo con ese código."
  def existe_centro?(codigo), do: GenServer.call(__MODULE__, {:existe_centro, codigo})

  @doc "Zona de un centro de apoyo, para la regla de zona del coordinador."
  def zona_de(codigo), do: GenServer.call(__MODULE__, {:zona_de, codigo})

  @doc "Recursos que hay en un centro (por ejemplo, en un albergue)."
  def por_centro(centro), do: GenServer.call(__MODULE__, {:por_centro, centro})

  @doc """
  Movimientos de un recurso (`list_movements`), del más antiguo al más reciente.
  Sin código, los movimientos de todos los recursos.
  """
  def historial(codigo \\ nil), do: GenServer.call(__MODULE__, {:historial, codigo})

  @doc """
  Indica si `punto` es el código de un punto de atención de la zona. Recorre los
  sectores de la zona que guarda `Emergencias.Zonas`.
  """
  def punto_existe?(zona, punto) do
    case Zonas.obtener(zona) do
      {:ok, encontrada} -> punto_en_sectores?(encontrada.sectores, punto)
      {:error, _razon} -> false
    end
  end

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    estado = %{
      centros: cargar_centros(),
      recursos: cargar_recursos(),
      movimientos: cargar_movimientos()
    }

    {:ok, estado}
  end

  @impl true
  def handle_call({:registrar_centro, codigo, nombre, tipo, zona}, _from, estado) do
    with {:ok, tipo} <- Validaciones.opcion(tipo, Centro.tipos(), :tipo_invalido),
         {:ok, centro, nuevo_estado} <- agregar_centro(estado, codigo, nombre, tipo, zona) do
      {:reply, {:ok, centro}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call(
        {:registrar, codigo, categoria, cantidad, unidad, codigo_centro, nombre},
        _from,
        estado
      ) do
    with :ok <- Validaciones.texto(codigo, :codigo_invalido),
         :ok <- libre(estado.recursos, codigo),
         {:ok, categoria} <-
           Validaciones.opcion(categoria, Recurso.categorias(), :categoria_invalida),
         :ok <- Validaciones.entero_no_negativo(cantidad, :cantidad_invalida),
         :ok <- Validaciones.texto(unidad, :unidad_invalida),
         {:ok, centro} <- buscar_centro(estado, codigo_centro),
         {:ok, nombre} <- nombre_del_recurso(nombre, categoria) do
      recurso = Recurso.crear(codigo, nombre, categoria, unidad, centro.codigo, cantidad)

      movimiento =
        Movimiento.crear(:registro, codigo, "", centro.codigo, cantidad, "", "Registro inicial")

      nuevo_estado = confirmar(estado, Map.put(estado.recursos, codigo, recurso), [movimiento])
      {:reply, {:ok, recurso}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:entrada, codigo, codigo_centro, cantidad}, _from, estado) do
    with {:ok, recurso} <- buscar_recurso(estado, codigo),
         {:ok, centro} <- buscar_centro(estado, codigo_centro),
         :ok <- Validaciones.entero_positivo(cantidad, :cantidad_invalida) do
      actualizado = Recurso.agregar(recurso, centro.codigo, cantidad)

      movimiento =
        Movimiento.crear(
          :entrada,
          codigo,
          "",
          centro.codigo,
          cantidad,
          "",
          "Entrada de inventario"
        )

      nuevo_estado =
        confirmar(estado, Map.put(estado.recursos, codigo, actualizado), [movimiento])

      {:reply, {:ok, actualizado}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:salida, codigo, codigo_centro, cantidad}, _from, estado) do
    with {:ok, recurso} <- buscar_recurso(estado, codigo),
         {:ok, centro} <- buscar_centro(estado, codigo_centro),
         :ok <- Validaciones.entero_positivo(cantidad, :cantidad_invalida),
         {:ok, actualizado} <- Recurso.retirar(recurso, centro.codigo, cantidad) do
      movimiento =
        Movimiento.crear(:salida, codigo, centro.codigo, "", cantidad, "", "Salida de inventario")

      nuevo_estado =
        confirmar(estado, Map.put(estado.recursos, codigo, actualizado), [movimiento])

      {:reply, {:ok, actualizado}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:transferir, codigo, codigo_origen, codigo_destino, cantidad}, _from, estado) do
    with {:ok, recurso} <- buscar_recurso(estado, codigo),
         {:ok, origen} <- buscar_centro(estado, codigo_origen),
         {:ok, destino} <- buscar_centro(estado, codigo_destino),
         :ok <- centros_distintos(origen, destino),
         :ok <- Validaciones.entero_positivo(cantidad, :cantidad_invalida),
         {:ok, retirado} <- Recurso.retirar(recurso, origen.codigo, cantidad) do
      actualizado = Recurso.agregar(retirado, destino.codigo, cantidad)

      movimiento =
        Movimiento.crear(
          :transferencia,
          codigo,
          origen.codigo,
          destino.codigo,
          cantidad,
          "",
          "Transferencia"
        )

      nuevo_estado =
        confirmar(estado, Map.put(estado.recursos, codigo, actualizado), [movimiento])

      {:reply, {:ok, actualizado}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:consultar, codigo}, _from, estado) do
    {:reply, buscar_recurso(estado, codigo), estado}
  end

  @impl true
  def handle_call(:listar, _from, estado) do
    lista = estado.recursos |> Map.values() |> Enum.sort_by(fn recurso -> recurso.codigo end)
    {:reply, lista, estado}
  end

  @impl true
  def handle_call(:listar_centros, _from, estado) do
    lista = estado.centros |> Map.values() |> Enum.sort_by(fn centro -> centro.codigo end)
    {:reply, lista, estado}
  end

  @impl true
  def handle_call({:existe_centro, codigo}, _from, estado) do
    {:reply, Map.has_key?(estado.centros, codigo), estado}
  end

  @impl true
  def handle_call({:zona_de, codigo}, _from, estado) do
    case buscar_centro(estado, codigo) do
      {:ok, centro} -> {:reply, {:ok, centro.zona}, estado}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:por_centro, centro}, _from, estado) do
    lista =
      estado.recursos
      |> Map.values()
      |> Enum.filter(fn recurso -> Recurso.disponible(recurso, centro) > 0 end)
      |> Enum.sort_by(fn recurso -> recurso.codigo end)
      |> Enum.map(fn recurso ->
        %{
          codigo: recurso.codigo,
          nombre: recurso.nombre,
          categoria: recurso.categoria,
          cantidad: Recurso.disponible(recurso, centro),
          unidad: recurso.unidad
        }
      end)

    {:reply, lista, estado}
  end

  @impl true
  def handle_call({:historial, codigo}, _from, estado) do
    lista =
      estado.movimientos
      |> Enum.filter(fn movimiento -> codigo == nil or movimiento.codigo == codigo end)
      |> Enum.reverse()

    {:reply, lista, estado}
  end

  # ========== Funciones auxiliares privadas ==========

  defp agregar_centro(estado, codigo, nombre, tipo, zona) do
    with :ok <- Validaciones.texto(codigo, :codigo_invalido),
         :ok <- libre(estado.centros, codigo),
         :ok <- Validaciones.texto(nombre, :nombre_invalido),
         :ok <- zona_existe(zona),
         :ok <- punto_valido(tipo, zona, codigo) do
      centro = Centro.crear(codigo, nombre, tipo, zona)
      nuevo_estado = %{estado | centros: Map.put(estado.centros, codigo, centro)}
      guardar_centros(nuevo_estado)
      {:ok, centro, nuevo_estado}
    end
  end

  defp libre(mapa, codigo) do
    if Map.has_key?(mapa, codigo), do: {:error, :ya_existe}, else: :ok
  end

  defp zona_existe(zona) do
    if Zonas.existe?(zona), do: :ok, else: {:error, :zona_no_existe}
  end

  # Un centro de tipo punto de atención usa el código de un punto de su zona
  defp punto_valido(:punto_atencion, zona, codigo) do
    if punto_existe?(zona, codigo), do: :ok, else: {:error, :punto_no_existe}
  end

  defp punto_valido(_tipo, _zona, _codigo), do: :ok

  # Caso base: no quedan sectores por revisar
  defp punto_en_sectores?([], _punto), do: false

  # Caso recursivo: si el primer sector tiene el punto se termina; si no, se sigue con
  # los demás sectores
  defp punto_en_sectores?([head | tail], punto) do
    if Zona.buscar_punto(head, punto), do: true, else: punto_en_sectores?(tail, punto)
  end

  defp buscar_recurso(estado, codigo) do
    case Map.get(estado.recursos, codigo) do
      nil -> {:error, :recurso_no_existe}
      recurso -> {:ok, recurso}
    end
  end

  defp buscar_centro(estado, codigo) do
    case Map.get(estado.centros, codigo) do
      nil -> {:error, :centro_no_existe}
      centro -> {:ok, centro}
    end
  end

  defp centros_distintos(origen, destino) do
    if origen.codigo == destino.codigo, do: {:error, :mismo_centro}, else: :ok
  end

  # Si no se da un nombre, el recurso se llama como su categoría
  defp nombre_del_recurso(nil, categoria), do: {:ok, "#{categoria}"}

  defp nombre_del_recurso(nombre, _categoria) do
    case Validaciones.texto(nombre, :nombre_invalido) do
      :ok -> {:ok, nombre}
      {:error, razon} -> {:error, razon}
    end
  end

  defp confirmar(estado, recursos, movimientos) do
    Enum.each(movimientos, fn movimiento ->
      Persistencia.agregar(@archivo_movimientos, Persistencia.unir(Movimiento.a_fila(movimiento)))
    end)

    nuevo_estado = %{
      estado
      | recursos: recursos,
        movimientos: Enum.reverse(movimientos) ++ estado.movimientos
    }

    guardar_recursos(nuevo_estado)
    nuevo_estado
  end

  defp cargar_centros do
    @archivo_centros
    |> Persistencia.cargar()
    |> Enum.map(fn linea -> Centro.desde_fila(Persistencia.separar(linea)) end)
    |> Enum.reduce(%{}, fn centro, centros -> Map.put(centros, centro.codigo, centro) end)
  end

  defp cargar_recursos do
    @archivo_recursos
    |> Persistencia.cargar()
    |> Enum.reduce(%{}, fn linea, recursos ->
      Recurso.cargar_fila(recursos, Persistencia.separar(linea))
    end)
  end

  defp cargar_movimientos do
    @archivo_movimientos
    |> Persistencia.cargar()
    |> Enum.map(fn linea -> Movimiento.desde_fila(Persistencia.separar(linea)) end)
    |> Enum.reverse()
  end

  defp guardar_centros(estado) do
    lineas =
      estado.centros
      |> Map.values()
      |> Enum.sort_by(fn centro -> centro.codigo end)
      |> Enum.map(fn centro -> Persistencia.unir(Centro.a_fila(centro)) end)

    Persistencia.guardar(@archivo_centros, lineas)
  end

  defp guardar_recursos(estado) do
    lineas =
      estado.recursos
      |> Map.values()
      |> Enum.sort_by(fn recurso -> recurso.codigo end)
      |> Enum.flat_map(fn recurso -> Recurso.a_filas(recurso) end)
      |> Enum.map(fn fila -> Persistencia.unir(fila) end)

    Persistencia.guardar(@archivo_recursos, lineas)
  end
end
