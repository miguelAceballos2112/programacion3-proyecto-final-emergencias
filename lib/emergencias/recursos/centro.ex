defmodule Emergencias.Recursos.Centro do
  @moduledoc """
  Centro de apoyo donde se guardan recursos: centro de acopio, punto de atención o
  albergue.

  Cada centro pertenece a una zona; así se sabe en qué zona está cada recurso. Un
  centro de tipo `:punto_atencion` usa el código de un punto de atención de su zona.
  Los centros de tipo `:albergue` no se registran con `register_center`: los crea
  `Emergencias.Albergues` al registrar cada albergue.
  """

  @tipos [:acopio, :punto_atencion]

  defstruct codigo: "", nombre: "", tipo: :acopio, zona: ""

  @doc "Tipos que acepta `register_center`."
  def tipos, do: @tipos

  def crear(codigo, nombre, tipo, zona) do
    %__MODULE__{codigo: codigo, nombre: nombre, tipo: tipo, zona: zona}
  end

  def a_fila(%__MODULE__{} = centro) do
    [centro.codigo, centro.nombre, "#{centro.tipo}", centro.zona]
  end

  def desde_fila([codigo, nombre, tipo, zona]) do
    crear(codigo, nombre, String.to_atom(tipo), zona)
  end
end
