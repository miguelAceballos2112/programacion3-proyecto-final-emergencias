defmodule Emergencias.Necesidades.Necesidad do
  @moduledoc """
  Solicitud de ayuda: qué se necesita, cuánto, dónde, con qué prioridad y en qué estado va.

  Transiciones de estado válidas:

      pendiente   --(se le asignan recursos)--> asignada
      pendiente   --> en_atencion | cancelada
      asignada    --> en_atencion | cancelada
      en_atencion --> atendida | cancelada

  `atendida` y `cancelada` son estados finales: una necesidad cerrada no vuelve a
  consumir recursos ni se puede cerrar dos veces. Un rescate o un transporte no usan
  inventario, así que pasan de pendiente a en_atencion sin asignación.

  `destino` dice a quién va la ayuda: `{:zona, codigo}` (por defecto, la zona de la
  necesidad), `{:punto, codigo}`, `{:albergue, codigo}`, `{:persona, documento}` o
  `{:familia, codigo}`.
  """

  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]
  @tipos_destino [:zona, :punto, :albergue, :persona, :familia]

  defstruct id: "",
            tipo: :otra,
            descripcion: "",
            cantidad: 0,
            asignado: 0,
            zona: "",
            prioridad: :media,
            responsable: "",
            estado: :pendiente,
            destino: nil,
            fecha: ""

  def estados, do: @estados

  def tipos_destino, do: @tipos_destino

  def crear(id, tipo, cantidad, prioridad, zona, descripcion, responsable, destino) do
    %__MODULE__{
      id: id,
      tipo: tipo,
      cantidad: cantidad,
      prioridad: prioridad,
      zona: zona,
      descripcion: descripcion,
      responsable: responsable,
      destino: destino,
      fecha: "#{NaiveDateTime.local_now()}"
    }
  end

  @doc "Lo que todavía falta por cubrir."
  def faltante(%__MODULE__{} = necesidad), do: necesidad.cantidad - necesidad.asignado

  @doc "Una necesidad está abierta mientras no esté atendida ni cancelada."
  def abierta?(%__MODULE__{estado: estado}), do: estado in [:pendiente, :asignada, :en_atencion]

  @doc """
  Al cancelarse se devuelve lo reservado solo si no estaba en atención: en atención los
  recursos ya se usaron.
  """
  def devuelve_al_cancelar?(%__MODULE__{estado: estado}), do: estado in [:pendiente, :asignada]

  @doc "Revisa si se le pueden asignar `cantidad` unidades, antes de tocar el inventario."
  def validar_asignacion(%__MODULE__{estado: estado}, _cantidad)
      when estado in [:atendida, :cancelada] do
    {:error, :necesidad_cerrada}
  end

  def validar_asignacion(%__MODULE__{} = necesidad, cantidad) do
    if cantidad > faltante(necesidad), do: {:error, :excede_lo_requerido}, else: :ok
  end

  @doc "Suma lo asignado. La primera asignación pasa la necesidad de pendiente a asignada."
  def registrar_asignacion(%__MODULE__{} = necesidad, cantidad) do
    %{
      necesidad
      | asignado: necesidad.asignado + cantidad,
        estado: estado_al_asignar(necesidad.estado)
    }
  end

  @doc "Cambia el estado solo si la transición es válida."
  def cambiar_estado(%__MODULE__{estado: estado}, _nuevo)
      when estado in [:atendida, :cancelada] do
    {:error, :necesidad_cerrada}
  end

  def cambiar_estado(%__MODULE__{} = necesidad, nuevo) do
    if Enum.member?(siguientes(necesidad.estado), nuevo) do
      {:ok, %{necesidad | estado: nuevo}}
    else
      {:error, :transicion_invalida}
    end
  end

  def a_fila(%__MODULE__{} = necesidad) do
    {tipo_destino, codigo_destino} = necesidad.destino

    [
      necesidad.id,
      "#{necesidad.tipo}",
      necesidad.descripcion,
      "#{necesidad.cantidad}",
      "#{necesidad.asignado}",
      necesidad.zona,
      "#{necesidad.prioridad}",
      necesidad.responsable,
      "#{necesidad.estado}",
      "#{tipo_destino}",
      codigo_destino,
      necesidad.fecha
    ]
  end

  def desde_fila([
        id,
        tipo,
        descripcion,
        cantidad,
        asignado,
        zona,
        prioridad,
        responsable,
        estado,
        tipo_destino,
        codigo_destino,
        fecha
      ]) do
    %__MODULE__{
      id: id,
      tipo: String.to_atom(tipo),
      descripcion: descripcion,
      cantidad: String.to_integer(cantidad),
      asignado: String.to_integer(asignado),
      zona: zona,
      prioridad: String.to_atom(prioridad),
      responsable: responsable,
      estado: String.to_atom(estado),
      destino: {String.to_atom(tipo_destino), codigo_destino},
      fecha: fecha
    }
  end

  defp estado_al_asignar(:pendiente), do: :asignada
  defp estado_al_asignar(estado), do: estado

  defp siguientes(:pendiente), do: [:en_atencion, :cancelada]
  defp siguientes(:asignada), do: [:en_atencion, :cancelada]
  defp siguientes(:en_atencion), do: [:atendida, :cancelada]
end
