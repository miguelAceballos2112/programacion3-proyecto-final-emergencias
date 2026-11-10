defmodule Emergencias.Zonas.Sector do
  @moduledoc """
  Sector de una zona. Contiene una lista de puntos de atención.
  """

  @enforce_keys [:codigo, :nombre, :nivel]
  defstruct [:codigo, :nombre, :nivel, personas_afectadas: 0, puntos: []]
end
