defmodule Emergencias.Mascotas.Reporte do
  @moduledoc """
  Reporte de una mascota perdida o encontrada.

  Es un struct con funciones puras: no tiene procesos ni toca el disco. Define la
  tabla de transiciones de estado y la conversión de/hacia una fila de texto plano.
  - Integrante 3: mascotas
  """

  alias Emergencias.Persistencia
  alias Emergencias.Validaciones

  @tipos [:perdida, :encontrada]
  @tamanos [:pequeno, :mediano, :grande]
  @estados [:activa, :posible_coincidencia, :resuelta]

  # Cada estado apunta a la lista de estados a los que puede pasar.
  # Una lista vacía significa estado terminal: no admite ninguna transición.
  @transiciones %{
    activa: [:posible_coincidencia, :resuelta],
    posible_coincidencia: [:activa, :resuelta],
    resuelta: []
  }

  defstruct [
    :id,
    :tipo,
    :especie,
    :nombre,
    :caracteristicas,
    :color,
    :tamano,
    :zona,
    :contacto,
    :estado,
    :pareja
  ]

  @type tipo :: :perdida | :encontrada
  @type tamano :: :pequeno | :mediano | :grande
  @type estado :: :activa | :posible_coincidencia | :resuelta

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: tipo(),
          especie: String.t(),
          nombre: String.t(),
          caracteristicas: String.t(),
          color: String.t(),
          tamano: tamano(),
          zona: String.t(),
          contacto: String.t(),
          estado: estado(),
          pareja: String.t() | nil
        }

  @doc "Tipos de reporte: una mascota se pierde o se encuentra."
  @spec tipos() :: [tipo()]
  def tipos, do: @tipos

  @doc "Tamaños permitidos."
  @spec tamanos() :: [tamano()]
  def tamanos, do: @tamanos

  @doc "Estados posibles de un reporte."
  @spec estados() :: [estado()]
  def estados, do: @estados

  @doc """
  Verifica si la tabla permite pasar de `origen` a `destino`.
  Retorna `:ok` o `{:error, :transicion_invalida}`.

  ## Ejemplos

      iex> Emergencias.Mascotas.Reporte.puede_pasar(:activa, :posible_coincidencia)
      :ok

      iex> Emergencias.Mascotas.Reporte.puede_pasar(:resuelta, :activa)
      {:error, :transicion_invalida}
  """
  @spec puede_pasar(estado(), estado()) :: :ok | {:error, :transicion_invalida}
  def puede_pasar(origen, destino) do
    permitidos = Map.get(@transiciones, origen, [])

    if Enum.member?(permitidos, destino) do
      :ok
    else
      {:error, :transicion_invalida}
    end
  end

  @doc """
  Marca el reporte como posible coincidencia con el reporte `otro_id`
  (`match_pets`). Solo un reporte activo puede pasar a este estado.
  """
  @spec proponer(t(), String.t()) :: {:ok, t()} | {:error, :transicion_invalida}
  def proponer(%__MODULE__{} = reporte, otro_id) do
    with :ok <- puede_pasar(reporte.estado, :posible_coincidencia) do
      {:ok, %{reporte | estado: :posible_coincidencia, pareja: otro_id}}
    end
  end

  @doc "Devuelve el reporte a activo y le quita la pareja (`reject_match`)."
  @spec liberar(t()) :: {:ok, t()} | {:error, :transicion_invalida}
  def liberar(%__MODULE__{} = reporte) do
    with :ok <- puede_pasar(reporte.estado, :activa) do
      {:ok, %{reporte | estado: :activa, pareja: nil}}
    end
  end

  @doc "Cierra el reporte con su pareja (`confirm_match`). Un reporte resuelto no se vuelve a cerrar."
  @spec resolver(t(), String.t()) :: {:ok, t()} | {:error, :transicion_invalida}
  def resolver(%__MODULE__{} = reporte, otro_id) do
    with :ok <- puede_pasar(reporte.estado, :resuelta) do
      {:ok, %{reporte | estado: :resuelta, pareja: otro_id}}
    end
  end

  @doc "Convierte el reporte en los campos de una línea de `mascotas.txt`."
  @spec a_fila(t()) :: [String.t()]
  def a_fila(%__MODULE__{} = reporte) do
    [
      reporte.id,
      "#{reporte.tipo}",
      reporte.especie,
      reporte.nombre,
      reporte.caracteristicas,
      reporte.color,
      "#{reporte.tamano}",
      reporte.zona,
      reporte.contacto,
      "#{reporte.estado}",
      reporte.pareja || ""
    ]
  end

  @doc """
  Reconstruye un reporte desde los campos de una línea. Si la línea está dañada
  retorna `{:error, :fila_invalida}` en lugar de fallar.
  """
  @spec desde_fila([String.t()]) :: {:ok, t()} | {:error, :fila_invalida}
  def desde_fila([
        id,
        tipo,
        especie,
        nombre,
        caracteristicas,
        color,
        tamano,
        zona,
        contacto,
        estado,
        pareja
      ]) do
    with {:ok, tipo} <- Validaciones.opcion(tipo, @tipos, :fila_invalida),
         {:ok, tamano} <- Validaciones.opcion(tamano, @tamanos, :fila_invalida),
         {:ok, estado} <- Validaciones.opcion(estado, @estados, :fila_invalida) do
      {:ok,
       %__MODULE__{
         id: id,
         tipo: tipo,
         especie: especie,
         nombre: nombre,
         caracteristicas: caracteristicas,
         color: color,
         tamano: tamano,
         zona: zona,
         contacto: contacto,
         estado: estado,
         pareja: if(pareja == "", do: nil, else: pareja)
       }}
    end
  end

  def desde_fila(_otra), do: {:error, :fila_invalida}

  @doc "Quita el `;` y los saltos de línea de un texto libre, para no dañar el archivo."
  @spec limpiar(term()) :: String.t()
  def limpiar(texto) when is_binary(texto), do: Persistencia.limpiar(texto)
  def limpiar(_otro), do: ""
end
