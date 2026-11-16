defmodule Emergencias.ReportesTest do
  use ExUnit.Case

  alias Emergencias.Albergues
  alias Emergencias.Mascotas
  alias Emergencias.Necesidades
  alias Emergencias.Personas
  alias Emergencias.Recursos
  alias Emergencias.Reportes
  alias Emergencias.Zonas

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  # Una zona con un poco de todo
  defp zona_con_datos do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona", "alto", 10)
    {:ok, _sector} = Zonas.registrar_sector(zona, "s1", "Sector", "medio", 5)
    centro = unico("centro_")
    {:ok, _centro} = Recursos.registrar_centro(centro, "Acopio", "acopio", zona)
    {:ok, _recurso} = Recursos.registrar(unico("R"), "agua", 40, "litros", centro)
    {:ok, _albergue} = Albergues.registrar(unico("A"), "Albergue", zona, 20)
    {:ok, _necesidad} = Necesidades.registrar("agua", 10, "alta", zona, "Prueba", "laura")
    {:ok, _persona} = Personas.registrar(unico("doc"), "Ana", zona, :localizada)

    {:ok, _reporte} =
      Mascotas.registrar(:perdida, "perro", "Luna", "negra", :mediano, zona, "300")

    zona
  end

  test "el resumen cuenta lo de todos los servidores" do
    _zona = zona_con_datos()
    resumen = Reportes.resumen()

    assert resumen.zonas >= 1
    assert resumen.necesidades >= 1
    assert resumen.personas_localizadas >= 1
    assert resumen.mascotas >= 1
    assert resumen.albergues.capacidad >= 20
    assert Map.get(resumen.recursos_por_categoria, :agua, 0) >= 40
    assert is_map(resumen.mensajes_por_estado)
  end

  test "el estado de una zona solo incluye lo de esa zona" do
    zona = zona_con_datos()
    _otra = zona_con_datos()

    assert {:ok, estado} = Reportes.estado_zona(zona)
    assert estado.zona.codigo == zona
    assert estado.estadisticas.personas_afectadas == 15
    assert Enum.count(estado.albergues) == 1
    assert Enum.count(estado.necesidades) == 1
    assert Enum.count(estado.personas) == 1
    assert Enum.count(estado.mascotas) == 1
    assert [%{categoria: :agua, total: 40}] = estado.recursos
  end

  test "una zona que no existe" do
    assert Reportes.estado_zona(unico("nada_")) == {:error, :zona_no_existe}
  end
end
