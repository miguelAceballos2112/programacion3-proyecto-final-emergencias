defmodule Emergencias.Zonas.Estadisticas do
  @moduledoc """
  Estadísticas acumuladas de una zona, calculadas con funciones recursivas sobre
  la jerarquía zona -> sectores -> puntos de atención.

  Cada nivel tiene su propia estimación de personas afectadas. El total acumulado
  de un nivel es su estimación más los totales de todo lo que contiene.
  - Integrante 1: zonas
  """

  alias Emergencias.Zonas.Zona

  @doc """
  Resumen de una zona: personas afectadas acumuladas, cantidad de sectores y de
  puntos de atención, sectores por nivel y total acumulado de cada sector.
  """
  def resumen(%Zona{} = zona) do
    %{
      personas_afectadas: total_personas(zona),
      sectores: length(zona.sectores),
      puntos_atencion: contar_puntos(zona.sectores),
      sectores_por_nivel: sectores_por_nivel(zona.sectores, %{}),
      personas_por_sector: totales_por_sector(zona.sectores)
    }
  end

  @doc "Total acumulado de la zona: su estimación más la de todos sus sectores."
  def total_personas(%Zona{} = zona) do
    zona.personas_afectadas + total_sectores(zona.sectores)
  end

  @doc "Suma recursiva de los totales acumulados de una lista de sectores."
  def total_sectores([]), do: 0

  def total_sectores([sector | resto]) do
    sector.personas_afectadas + total_puntos(sector.puntos) + total_sectores(resto)
  end

  @doc "Suma recursiva de las personas afectadas de una lista de puntos de atención."
  def total_puntos([]), do: 0
  def total_puntos([punto | resto]), do: punto.personas_afectadas + total_puntos(resto)

  @doc "Cuenta recursivamente los puntos de atención de una lista de sectores."
  def contar_puntos([]), do: 0
  def contar_puntos([sector | resto]), do: length(sector.puntos) + contar_puntos(resto)

  @doc """
  Cuenta los sectores de cada nivel de afectación. Es recursiva con acumulador:
  el mapa parcial viaja de una llamada a la siguiente.
  """
  def sectores_por_nivel([], acumulado), do: acumulado

  def sectores_por_nivel([sector | resto], acumulado) do
    nuevo_acumulado = Map.update(acumulado, sector.nivel, 1, fn cantidad -> cantidad + 1 end)
    sectores_por_nivel(resto, nuevo_acumulado)
  end

  @doc "Lista de `{codigo_sector, total_acumulado}`, calculada recursivamente."
  def totales_por_sector([]), do: []

  def totales_por_sector([sector | resto]) do
    total = sector.personas_afectadas + total_puntos(sector.puntos)
    [{sector.codigo, total} | totales_por_sector(resto)]
  end
end
