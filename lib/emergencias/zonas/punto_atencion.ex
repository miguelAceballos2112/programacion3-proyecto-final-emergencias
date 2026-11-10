defmodule Emergencias.Zonas.PuntoAtencion do
  @moduledoc """
  Punto de atención de un sector: el nivel más bajo de la jerarquía
  zona -> sectores -> puntos de atención.
  """

  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, personas_afectadas: 0]
end
