defmodule Emergencias.Personas.Persona do
  @moduledoc """
  Persona afectada por la emergencia.

  Es un struct con funciones puras: no tiene procesos ni toca el disco. Define la
  tabla de transiciones de estado y la conversión de/hacia una fila de texto plano
  (`a_fila/1` y `desde_fila/1`).
  - Integrante 3: personas
  """

  alias Emergencias.Persistencia
  alias Emergencias.Validaciones

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @estados_iniciales [:sin_informacion, :reportada, :localizada, :trasladada]

  # Cada estado apunta a la lista de estados a los que puede pasar.
  # Una lista vacía significa estado terminal: no admite ninguna transición.
  @transiciones %{
    sin_informacion: [:reportada, :localizada, :en_albergue],
    reportada: [:localizada, :reunificada, :en_albergue],
    localizada: [:trasladada, :reunificada, :en_albergue],
    trasladada: [:localizada, :reunificada, :en_albergue],
    en_albergue: [:trasladada],
    reunificada: []
  }

  defstruct [:id, :documento, :nombre, :edad, :zona, :estado, :familia]

  @type estado ::
          :sin_informacion | :reportada | :localizada | :trasladada | :en_albergue | :reunificada

  @type t :: %__MODULE__{
          id: String.t(),
          documento: String.t(),
          nombre: String.t(),
          edad: non_neg_integer(),
          zona: String.t(),
          estado: estado(),
          familia: String.t() | nil
        }

  @doc "Todos los estados posibles de una persona."
  @spec estados() :: [estado()]
  def estados, do: @estados

  @doc "Estados con los que se puede reportar una persona por primera vez."
  @spec estados_iniciales() :: [estado()]
  def estados_iniciales, do: @estados_iniciales

  @doc """
  Un documento es válido si es un texto sin espacios y sin `,`, porque los
  albergues guardan los documentos de sus ocupantes separados por coma.

  ## Ejemplos

      iex> Emergencias.Personas.Persona.validar_documento("1094")
      :ok

      iex> Emergencias.Personas.Persona.validar_documento("10 94")
      {:error, :documento_invalido}
  """
  @spec validar_documento(term()) :: :ok | {:error, :documento_invalido}
  def validar_documento(documento) do
    with :ok <- Validaciones.texto(documento, :documento_invalido) do
      if String.contains?(documento, [" ", ","]), do: {:error, :documento_invalido}, else: :ok
    end
  end

  @doc """
  Verifica si la tabla permite pasar de `origen` a `destino`.
  Retorna `:ok` o `{:error, :transicion_invalida}`.

  ## Ejemplos

      iex> Emergencias.Personas.Persona.puede_pasar(:reportada, :localizada)
      :ok

      iex> Emergencias.Personas.Persona.puede_pasar(:reunificada, :localizada)
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

  @doc "Convierte la persona en los campos de una línea de `personas.txt`."
  @spec a_fila(t()) :: [String.t()]
  def a_fila(%__MODULE__{} = persona) do
    [
      persona.id,
      persona.documento,
      persona.nombre,
      "#{persona.edad}",
      persona.zona,
      "#{persona.estado}",
      persona.familia || ""
    ]
  end

  @doc """
  Reconstruye una persona desde los campos de una línea. Si la línea está dañada
  retorna `{:error, :fila_invalida}` en lugar de fallar: así un archivo con una
  línea mala no impide que el servidor arranque.
  """
  @spec desde_fila([String.t()]) :: {:ok, t()} | {:error, :fila_invalida}
  def desde_fila([id, documento, nombre, edad, zona, estado, familia]) do
    with {edad, ""} <- Integer.parse(edad),
         {:ok, estado} <- Validaciones.opcion(estado, @estados, :fila_invalida) do
      {:ok,
       %__MODULE__{
         id: id,
         documento: documento,
         nombre: nombre,
         edad: edad,
         zona: zona,
         estado: estado,
         familia: if(familia == "", do: nil, else: familia)
       }}
    else
      _error -> {:error, :fila_invalida}
    end
  end

  def desde_fila(_otra), do: {:error, :fila_invalida}

  @doc "Convierte una entrada del historial en los campos de `historial_personas.txt`."
  @spec entrada_a_fila(map()) :: [String.t()]
  def entrada_a_fila(entrada) do
    [
      entrada.fecha,
      entrada.documento,
      if(entrada.anterior, do: "#{entrada.anterior}", else: "-"),
      "#{entrada.nuevo}",
      Persistencia.limpiar(entrada.detalle)
    ]
  end

  @doc "Reconstruye una entrada del historial desde los campos de una línea."
  @spec entrada_desde_fila([String.t()]) :: {:ok, map()} | {:error, :fila_invalida}
  def entrada_desde_fila([fecha, documento, anterior, nuevo, detalle]) do
    with {:ok, anterior} <- estado_anterior(anterior),
         {:ok, nuevo} <- Validaciones.opcion(nuevo, @estados, :fila_invalida) do
      {:ok,
       %{fecha: fecha, documento: documento, anterior: anterior, nuevo: nuevo, detalle: detalle}}
    end
  end

  def entrada_desde_fila(_otra), do: {:error, :fila_invalida}

  # El guion "-" significa que no había estado anterior (primer reporte)
  defp estado_anterior("-"), do: {:ok, nil}
  defp estado_anterior(texto), do: Validaciones.opcion(texto, @estados, :fila_invalida)
end
