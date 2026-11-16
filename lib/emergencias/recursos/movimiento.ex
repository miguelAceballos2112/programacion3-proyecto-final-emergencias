defmodule Emergencias.Recursos.Movimiento do
  @moduledoc """
  Movimiento del inventario: `:registro`, `:entrada`, `:salida`, `:transferencia`,
  `:reserva` o `:devolucion`.

  `origen` y `destino` son códigos de centro (vacíos cuando no aplican). Las reservas
  y las devoluciones llevan en `referencia` el id de la necesidad; así se sabe qué
  devolver si la necesidad se cancela.
  """

  defstruct fecha: "",
            tipo: :entrada,
            codigo: "",
            origen: "",
            destino: "",
            cantidad: 0,
            referencia: "",
            detalle: ""

  def crear(tipo, codigo, origen, destino, cantidad, referencia, detalle) do
    %__MODULE__{
      fecha: "#{NaiveDateTime.local_now()}",
      tipo: tipo,
      codigo: codigo,
      origen: origen,
      destino: destino,
      cantidad: cantidad,
      referencia: referencia,
      detalle: detalle
    }
  end

  def a_fila(%__MODULE__{} = movimiento) do
    [
      movimiento.fecha,
      "#{movimiento.tipo}",
      movimiento.codigo,
      movimiento.origen,
      movimiento.destino,
      "#{movimiento.cantidad}",
      movimiento.referencia,
      movimiento.detalle
    ]
  end

  def desde_fila([fecha, tipo, codigo, origen, destino, cantidad, referencia, detalle]) do
    %__MODULE__{
      fecha: fecha,
      tipo: String.to_atom(tipo),
      codigo: codigo,
      origen: origen,
      destino: destino,
      cantidad: String.to_integer(cantidad),
      referencia: referencia,
      detalle: detalle
    }
  end
end
