defmodule Emergencias.Zonas.EstadisticasTest do
  use ExUnit.Case

  alias Emergencias.Zonas.Estadisticas
  alias Emergencias.Zonas.PuntoAtencion
  alias Emergencias.Zonas.Sector
  alias Emergencias.Zonas.Zona

  # Zona de 100 personas con dos sectores:
  #   norte (critico, 50) con dos puntos de 10 y 5
  #   sur   (alto, 30)    con un punto de 20
  defp zona_ejemplo do
    %Zona{
      codigo: "centro",
      nombre: "Centro",
      nivel: :critico,
      personas_afectadas: 100,
      sectores: [
        %Sector{
          codigo: "norte",
          nombre: "Norte",
          nivel: :critico,
          personas_afectadas: 50,
          puntos: [
            %PuntoAtencion{codigo: "p1", nombre: "Punto 1", personas_afectadas: 10},
            %PuntoAtencion{codigo: "p2", nombre: "Punto 2", personas_afectadas: 5}
          ]
        },
        %Sector{
          codigo: "sur",
          nombre: "Sur",
          nivel: :alto,
          personas_afectadas: 30,
          puntos: [%PuntoAtencion{codigo: "p3", nombre: "Punto 3", personas_afectadas: 20}]
        }
      ]
    }
  end

  test "total_personas acumula zona, sectores y puntos" do
    # 100 + (50 + 10 + 5) + (30 + 20)
    assert Estadisticas.total_personas(zona_ejemplo()) == 215
  end

  test "total_puntos suma recursivamente una lista de puntos" do
    puntos = [
      %PuntoAtencion{codigo: "a", nombre: "A", personas_afectadas: 3},
      %PuntoAtencion{codigo: "b", nombre: "B", personas_afectadas: 4}
    ]

    assert Estadisticas.total_puntos(puntos) == 7
    assert Estadisticas.total_puntos([]) == 0
  end

  test "contar_puntos cuenta los puntos de todos los sectores" do
    assert Estadisticas.contar_puntos(zona_ejemplo().sectores) == 3
    assert Estadisticas.contar_puntos([]) == 0
  end

  test "sectores_por_nivel cuenta los sectores de cada nivel" do
    assert Estadisticas.sectores_por_nivel(zona_ejemplo().sectores, %{}) == %{critico: 1, alto: 1}
  end

  test "totales_por_sector devuelve el total acumulado de cada sector" do
    assert Estadisticas.totales_por_sector(zona_ejemplo().sectores) == [
             {"norte", 65},
             {"sur", 50}
           ]
  end

  test "una zona sin sectores solo cuenta su propia estimación" do
    zona = %Zona{codigo: "z", nombre: "Z", nivel: :bajo, personas_afectadas: 40}

    assert Estadisticas.resumen(zona) == %{
             personas_afectadas: 40,
             sectores: 0,
             puntos_atencion: 0,
             sectores_por_nivel: %{},
             personas_por_sector: []
           }
  end

  test "resumen reúne todas las estadísticas" do
    resumen = Estadisticas.resumen(zona_ejemplo())

    assert resumen.personas_afectadas == 215
    assert resumen.sectores == 2
    assert resumen.puntos_atencion == 3
  end
end
