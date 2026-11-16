defmodule Emergencias.Mascotas do
  @moduledoc """
  GenServer de reportes de mascotas perdidas y encontradas.

  Un solo proceso guarda todos los reportes y atiende los mensajes uno a uno. Por eso
  `confirm_match` cierra los dos reportes de un par dentro de un mismo `handle_call`:
  si varias personas intentan confirmar a la vez la mascota encontrada con distintos
  reportes de mascota perdida, solo una lo logra y las demás reciben `:ya_resuelto`.

  Nivel 2 del árbol: solo llama a `Zonas`.

  Estado del servidor:

      %{
        reportes: %{"M001" => %Reporte{}},
        siguiente: 1
      }

  Archivo: `mascotas.txt` (se reescribe completo después de cada cambio).
  - Integrante 3: mascotas
  """

  use GenServer

  alias Emergencias.Mascotas.Reporte
  alias Emergencias.Mascotas.Similitud
  alias Emergencias.Persistencia
  alias Emergencias.Validaciones
  alias Emergencias.Zonas

  @archivo "mascotas.txt"

  @type par :: %{perdida: Reporte.t(), encontrada: Reporte.t(), puntaje: non_neg_integer()}

  # ========== API del cliente ==========

  @doc "Inicia el servidor registrado con el nombre del módulo."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra un reporte (`report_pet`). El tipo es `:perdida` o `:encontrada` (también
  se acepta como texto) y el tamaño `:pequeno`, `:mediano` o `:grande`. Las
  características son opcionales. El reporte queda `:activa`.
  """
  @spec registrar(
          atom() | String.t(),
          String.t(),
          String.t(),
          String.t(),
          atom() | String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: {:ok, Reporte.t()} | {:error, atom()}
  def registrar(tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas \\ "") do
    GenServer.call(
      __MODULE__,
      {:registrar, tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas}
    )
  end

  @doc "Busca un reporte por código."
  @spec obtener(String.t()) :: {:ok, Reporte.t()} | {:error, :reporte_no_existe}
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, id})

  @doc """
  Lista los reportes (`list_pets`). Los filtros son pares `{campo, valor}` con los
  campos `especie`, `zona`, `estado` y `tipo`, por ejemplo `[especie: "perro"]`.
  """
  @spec listar(list()) :: [Reporte.t()]
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc """
  Busca coincidencias entre los reportes activos (`match_pets`). Marca como
  `:posible_coincidencia` los pares con 60 puntos o más y devuelve esos pares, del
  mejor al peor. Un reporte entra en un solo par: el de mayor puntaje.
  """
  @spec buscar_coincidencias() :: {:ok, [par()]}
  def buscar_coincidencias, do: GenServer.call(__MODULE__, :buscar_coincidencias)

  @doc """
  Rechaza un par propuesto (`reject_match`): los dos reportes vuelven a `:activa`.
  """
  @spec rechazar(String.t(), String.t()) ::
          {:ok, %{perdida: Reporte.t(), encontrada: Reporte.t()}} | {:error, atom()}
  def rechazar(id_perdida, id_encontrada) do
    GenServer.call(__MODULE__, {:rechazar, id_perdida, id_encontrada})
  end

  @doc """
  Confirma un par (`confirm_match`): los dos reportes pasan a `:resuelta`. Una segunda
  confirmación responde `{:error, :ya_resuelto}`.
  """
  @spec confirmar(String.t(), String.t()) ::
          {:ok, %{perdida: Reporte.t(), encontrada: Reporte.t()}} | {:error, atom()}
  def confirmar(id_perdida, id_encontrada) do
    GenServer.call(__MODULE__, {:confirmar, id_perdida, id_encontrada})
  end

  @doc "Zona de un reporte, para la regla de zona del coordinador."
  @spec zona_de(String.t()) :: {:ok, String.t()} | {:error, :reporte_no_existe}
  def zona_de(id), do: GenServer.call(__MODULE__, {:zona_de, id})

  # ========== Funciones recursivas (puras: no usan el estado del servidor) ==========

  @doc """
  Se queda con los reportes que cumplen todos los filtros.

  Caso base: una lista vacía no tiene reportes que filtrar. Caso recursivo: se decide
  por el primer reporte y se sigue con el resto.
  """
  @spec filtrar([Reporte.t()], list()) :: [Reporte.t()]
  def filtrar([], _filtros), do: []

  def filtrar([head | tail], filtros) do
    if cumple?(head, filtros) do
      [head | filtrar(tail, filtros)]
    else
      filtrar(tail, filtros)
    end
  end

  @doc """
  Elige los pares que se marcan, de la lista de candidatos ya ordenada del mejor al
  peor puntaje. Un reporte entra en un solo par: si alguno de los dos ya fue usado
  por un par anterior, el candidato se salta. Recursiva con el conjunto de usados.

  ## Ejemplo

      iex> candidatos = [
      ...>   %{perdida: %{id: "M1"}, encontrada: %{id: "M3"}, puntaje: 100},
      ...>   %{perdida: %{id: "M2"}, encontrada: %{id: "M3"}, puntaje: 80}
      ...> ]
      iex> Emergencias.Mascotas.elegir_pares(candidatos, MapSet.new())
      [%{perdida: %{id: "M1"}, encontrada: %{id: "M3"}, puntaje: 100}]
  """
  @spec elegir_pares([map()], MapSet.t(String.t())) :: [map()]
  def elegir_pares([], _usados), do: []

  def elegir_pares([head | tail], usados) do
    if MapSet.member?(usados, head.perdida.id) or MapSet.member?(usados, head.encontrada.id) do
      elegir_pares(tail, usados)
    else
      usados = usados |> MapSet.put(head.perdida.id) |> MapSet.put(head.encontrada.id)
      [head | elegir_pares(tail, usados)]
    end
  end

  # Un reporte cumple si cumple cada uno de los filtros (recursivo sobre los filtros)
  defp cumple?(_reporte, []), do: true

  defp cumple?(reporte, [{campo, valor} | tail]) do
    coincide?(reporte, "#{campo}", "#{valor}") and cumple?(reporte, tail)
  end

  defp coincide?(reporte, "especie", valor), do: minuscula(reporte.especie) == minuscula(valor)
  defp coincide?(reporte, "zona", valor), do: reporte.zona == valor
  defp coincide?(reporte, "estado", valor), do: "#{reporte.estado}" == valor
  defp coincide?(reporte, "tipo", valor), do: "#{reporte.tipo}" == valor

  # Un filtro desconocido no coincide con nada
  defp coincide?(_reporte, _campo, _valor), do: false

  defp minuscula(texto), do: texto |> String.trim() |> String.downcase()

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    reportes = cargar()

    estado = %{
      reportes: Map.new(reportes, fn reporte -> {reporte.id, reporte} end),
      siguiente: siguiente_numero(Enum.map(reportes, fn reporte -> reporte.id end), 0)
    }

    {:ok, estado}
  end

  @impl true
  def handle_call(
        {:registrar, tipo, especie, nombre, color, tamano, zona, contacto, caracteristicas},
        _from,
        estado
      ) do
    with {:ok, tipo} <- Validaciones.opcion(tipo, Reporte.tipos(), :tipo_invalido),
         :ok <- Validaciones.texto(especie, :especie_invalida),
         :ok <- Validaciones.texto(nombre, :nombre_invalido),
         :ok <- Validaciones.texto(color, :color_invalido),
         {:ok, tamano} <-
           Validaciones.opcion(sin_enie(tamano), Reporte.tamanos(), :tamano_invalido),
         :ok <- zona_existe(zona),
         :ok <- Validaciones.texto(contacto, :contacto_invalido),
         reporte = %Reporte{
           id: formar_codigo(estado.siguiente),
           tipo: tipo,
           especie: String.trim(especie),
           nombre: String.trim(nombre),
           caracteristicas: Reporte.limpiar(caracteristicas),
           color: String.trim(color),
           tamano: tamano,
           zona: zona,
           contacto: String.trim(contacto),
           estado: :activa,
           pareja: nil
         },
         nuevo = %{
           estado
           | reportes: Map.put(estado.reportes, reporte.id, reporte),
             siguiente: estado.siguiente + 1
         },
         :ok <- guardar(nuevo) do
      {:reply, {:ok, reporte}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:obtener, id}, _from, estado) do
    {:reply, buscar_reporte(estado.reportes, id), estado}
  end

  @impl true
  def handle_call({:listar, filtros}, _from, estado) do
    reportes = estado.reportes |> Map.values() |> Enum.sort_by(fn r -> orden(r.id) end)
    {:reply, filtrar(reportes, filtros), estado}
  end

  @impl true
  def handle_call(:buscar_coincidencias, _from, estado) do
    activos = estado.reportes |> Map.values() |> Enum.filter(fn r -> r.estado == :activa end)
    perdidas = activos |> Enum.filter(fn r -> r.tipo == :perdida end) |> ordenar_por_codigo()

    encontradas =
      activos |> Enum.filter(fn r -> r.tipo == :encontrada end) |> ordenar_por_codigo()

    pares = perdidas |> candidatos(encontradas) |> elegir_pares(MapSet.new())
    reportes = marcar_pares(estado.reportes, pares)
    nuevo = %{estado | reportes: reportes}

    with :ok <- guardar(nuevo) do
      actualizados =
        Enum.map(pares, fn par ->
          %{
            par
            | perdida: Map.fetch!(reportes, par.perdida.id),
              encontrada: Map.fetch!(reportes, par.encontrada.id)
          }
        end)

      {:reply, {:ok, actualizados}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:rechazar, id_perdida, id_encontrada}, _from, estado) do
    with {:ok, perdida, encontrada} <- buscar_par(estado.reportes, id_perdida, id_encontrada),
         :ok <- sin_resolver(perdida, encontrada),
         :ok <- son_pareja(perdida, encontrada),
         {:ok, perdida} <- Reporte.liberar(perdida),
         {:ok, encontrada} <- Reporte.liberar(encontrada),
         nuevo = guardar_par(estado, perdida, encontrada),
         :ok <- guardar(nuevo) do
      {:reply, {:ok, %{perdida: perdida, encontrada: encontrada}}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  # Verificar y cerrar los dos reportes ocurre en este mismo mensaje: ningún otro
  # proceso puede confirmar la mascota encontrada entre una cosa y la otra
  @impl true
  def handle_call({:confirmar, id_perdida, id_encontrada}, _from, estado) do
    with {:ok, perdida, encontrada} <- buscar_par(estado.reportes, id_perdida, id_encontrada),
         :ok <- sin_resolver(perdida, encontrada),
         :ok <- pareja_libre(perdida, encontrada),
         {:ok, perdida} <- Reporte.resolver(perdida, encontrada.id),
         {:ok, encontrada} <- Reporte.resolver(encontrada, perdida.id),
         nuevo = guardar_par(estado, perdida, encontrada),
         :ok <- guardar(nuevo) do
      {:reply, {:ok, %{perdida: perdida, encontrada: encontrada}}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:zona_de, id}, _from, estado) do
    case buscar_reporte(estado.reportes, id) do
      {:ok, reporte} -> {:reply, {:ok, reporte.zona}, estado}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  # ========== Funciones auxiliares privadas ==========

  # Todas las combinaciones perdida-encontrada que llegan al umbral, con su puntaje,
  # del mejor al peor. A igual puntaje decide el código, para que el resultado no
  # cambie de una ejecución a otra.
  defp candidatos(perdidas, encontradas) do
    perdidas
    |> Enum.flat_map(fn perdida ->
      Enum.map(encontradas, fn encontrada ->
        %{
          perdida: perdida,
          encontrada: encontrada,
          puntaje: Similitud.puntaje(perdida, encontrada)
        }
      end)
    end)
    |> Enum.filter(fn candidato -> candidato.puntaje >= Similitud.umbral() end)
    |> Enum.sort_by(fn c -> {-c.puntaje, orden(c.perdida.id), orden(c.encontrada.id)} end)
  end

  # Caso base: no quedan pares por marcar
  defp marcar_pares(reportes, []), do: reportes

  # Caso recursivo: se marca el primer par y se sigue con el resto. Los reportes ya
  # estaban activos, por eso `proponer/2` no puede fallar aquí.
  defp marcar_pares(reportes, [par | resto]) do
    {:ok, perdida} = Reporte.proponer(par.perdida, par.encontrada.id)
    {:ok, encontrada} = Reporte.proponer(par.encontrada, par.perdida.id)

    reportes
    |> Map.put(perdida.id, perdida)
    |> Map.put(encontrada.id, encontrada)
    |> marcar_pares(resto)
  end

  # Los dos códigos deben existir: el primero de una perdida y el segundo de una encontrada
  defp buscar_par(reportes, id_perdida, id_encontrada) do
    with {:ok, perdida} <- buscar_reporte(reportes, id_perdida),
         {:ok, encontrada} <- buscar_reporte(reportes, id_encontrada) do
      if perdida.tipo == :perdida and encontrada.tipo == :encontrada do
        {:ok, perdida, encontrada}
      else
        {:error, :tipo_invalido}
      end
    end
  end

  defp sin_resolver(perdida, encontrada) do
    if perdida.estado == :resuelta or encontrada.estado == :resuelta do
      {:error, :ya_resuelto}
    else
      :ok
    end
  end

  # Para rechazar, los dos reportes deben estar marcados como pareja el uno del otro
  defp son_pareja(perdida, encontrada) do
    if perdida.pareja == encontrada.id and encontrada.pareja == perdida.id do
      :ok
    else
      {:error, :no_son_pareja}
    end
  end

  # Para confirmar, cada reporte debe estar libre (activo) o ser pareja del otro:
  # no se puede confirmar a alguien que está propuesto con otro reporte
  defp pareja_libre(perdida, encontrada) do
    if libre_o_pareja?(perdida, encontrada.id) and libre_o_pareja?(encontrada, perdida.id) do
      :ok
    else
      {:error, :no_son_pareja}
    end
  end

  defp libre_o_pareja?(reporte, otro_id), do: reporte.pareja == nil or reporte.pareja == otro_id

  defp guardar_par(estado, perdida, encontrada) do
    reportes =
      estado.reportes
      |> Map.put(perdida.id, perdida)
      |> Map.put(encontrada.id, encontrada)

    %{estado | reportes: reportes}
  end

  # El código "M001" se acepta también en minúscula
  defp buscar_reporte(reportes, id) when is_binary(id) do
    case Map.get(reportes, id |> String.trim() |> String.upcase()) do
      nil -> {:error, :reporte_no_existe}
      reporte -> {:ok, reporte}
    end
  end

  defp buscar_reporte(_reportes, _otro), do: {:error, :reporte_no_existe}

  defp zona_existe(zona) do
    with :ok <- Validaciones.texto(zona, :zona_invalida) do
      if Zonas.existe?(zona), do: :ok, else: {:error, :zona_no_existe}
    end
  end

  # "pequeño" se acepta como "pequeno"
  defp sin_enie(tamano) when is_binary(tamano), do: String.replace(tamano, "ñ", "n")
  defp sin_enie(tamano), do: tamano

  defp ordenar_por_codigo(reportes), do: Enum.sort_by(reportes, fn r -> orden(r.id) end)

  # Para ordenar M999 y M1000 por su número y no letra por letra, se compara primero
  # el largo y luego el texto
  defp orden(codigo), do: {String.length(codigo), codigo}

  defp formar_codigo(numero), do: "M" <> String.pad_leading(Integer.to_string(numero), 3, "0")

  # Siguiente número de la serie: el mayor sufijo existente más uno. Recursiva con
  # acumulador; al cargar, los códigos continúan donde iban.
  defp siguiente_numero([], mayor), do: mayor + 1

  defp siguiente_numero([head | tail], mayor) do
    numero =
      case Integer.parse(String.replace_prefix(head, "M", "")) do
        {n, ""} -> n
        _otro -> 0
      end

    siguiente_numero(tail, max(mayor, numero))
  end

  # Carga el archivo y descarta las líneas dañadas en lugar de fallar
  defp cargar do
    @archivo
    |> Persistencia.cargar()
    |> Enum.map(fn linea -> Reporte.desde_fila(Persistencia.separar(linea)) end)
    |> Enum.flat_map(fn
      {:ok, reporte} -> [reporte]
      {:error, _razon} -> []
    end)
  end

  defp guardar(estado) do
    lineas =
      estado.reportes
      |> Map.values()
      |> ordenar_por_codigo()
      |> Enum.map(fn reporte -> Persistencia.unir(Reporte.a_fila(reporte)) end)

    Persistencia.guardar(@archivo, lineas)
  end
end
