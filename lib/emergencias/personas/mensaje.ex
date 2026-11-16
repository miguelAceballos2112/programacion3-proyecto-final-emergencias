defmodule Emergencias.Personas.Mensaje do
  @moduledoc """
  Mensaje dirigido a una persona o a una familia.

  Su estado alterna entre `:pendiente` y `:entregado`, como pide el enunciado
  (`mark_message`).
  - Integrante 3: personas
  """

  alias Emergencias.Validaciones

  @tipos_de_destino [:persona, :familia]
  @estados [:pendiente, :entregado]

  defstruct [:id, :fecha, :remitente, :destino_tipo, :destino_id, :contenido, :estado]

  @type t :: %__MODULE__{
          id: String.t(),
          fecha: String.t(),
          remitente: String.t(),
          destino_tipo: :persona | :familia,
          destino_id: String.t(),
          contenido: String.t(),
          estado: :pendiente | :entregado
        }

  @doc "Estados posibles de un mensaje."
  @spec estados() :: [:pendiente | :entregado]
  def estados, do: @estados

  @doc """
  Cambia el estado del mensaje. Solo se puede pasar de `:pendiente` a `:entregado`
  y de `:entregado` a `:pendiente`; repetir el mismo estado retorna
  `{:error, :transicion_invalida}`.

  ## Ejemplos

      iex> alias Emergencias.Personas.Mensaje
      iex> {:ok, entregado} = Mensaje.cambiar_estado(%Mensaje{estado: :pendiente}, :entregado)
      iex> entregado.estado
      :entregado

      iex> alias Emergencias.Personas.Mensaje
      iex> Mensaje.cambiar_estado(%Mensaje{estado: :entregado}, :entregado)
      {:error, :transicion_invalida}
  """
  @spec cambiar_estado(t(), :pendiente | :entregado) ::
          {:ok, t()} | {:error, :transicion_invalida}
  def cambiar_estado(%__MODULE__{estado: :pendiente} = mensaje, :entregado),
    do: {:ok, %{mensaje | estado: :entregado}}

  def cambiar_estado(%__MODULE__{estado: :entregado} = mensaje, :pendiente),
    do: {:ok, %{mensaje | estado: :pendiente}}

  def cambiar_estado(%__MODULE__{}, _estado), do: {:error, :transicion_invalida}

  @doc "Convierte el mensaje en los campos de una línea de `mensajes.txt`."
  @spec a_fila(t()) :: [String.t()]
  def a_fila(%__MODULE__{} = mensaje) do
    [
      mensaje.id,
      mensaje.fecha,
      mensaje.remitente,
      "#{mensaje.destino_tipo}",
      mensaje.destino_id,
      mensaje.contenido,
      "#{mensaje.estado}"
    ]
  end

  @doc "Reconstruye un mensaje desde los campos de una línea."
  @spec desde_fila([String.t()]) :: {:ok, t()} | {:error, :fila_invalida}
  def desde_fila([id, fecha, remitente, destino_tipo, destino_id, contenido, estado]) do
    with {:ok, tipo} <- Validaciones.opcion(destino_tipo, @tipos_de_destino, :fila_invalida),
         {:ok, estado} <- Validaciones.opcion(estado, @estados, :fila_invalida) do
      {:ok,
       %__MODULE__{
         id: id,
         fecha: fecha,
         remitente: remitente,
         destino_tipo: tipo,
         destino_id: destino_id,
         contenido: contenido,
         estado: estado
       }}
    end
  end

  def desde_fila(_otra), do: {:error, :fila_invalida}
end
