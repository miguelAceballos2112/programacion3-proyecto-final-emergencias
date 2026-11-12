defmodule Emergencias.RecursosTest do
  use ExUnit.Case

  alias Emergencias.Recursos
  alias Emergencias.Recursos.Recurso
  alias Emergencias.Zonas

  # ========== Datos de prueba y ayudas ==========

  # Todas las pruebas comparten los mismos procesos (los inicia la aplicación), así
  # que cada una trabaja con códigos únicos
  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  defp crear_zona do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona de prueba", "medio")
    zona
  end

  defp crear_centro(zona) do
    codigo = unico("centro_")
    {:ok, _centro} = Recursos.registrar_centro(codigo, "Centro de prueba", "acopio", zona)
    codigo
  end

  defp crear_recurso(categoria, cantidad, centro) do
    codigo = unico("R")
    {:ok, _recurso} = Recursos.registrar(codigo, categoria, cantidad, "unidades", centro)
    codigo
  end

  # ========== Pruebas ==========

  describe "centros de apoyo" do
    test "registra un centro de acopio en una zona existente" do
      zona = crear_zona()
      codigo = unico("centro_")

      assert {:ok, centro} = Recursos.registrar_centro(codigo, "Centro 1", "acopio", zona)
      assert centro.tipo == :acopio
      assert Recursos.existe_centro?(codigo)
      assert Recursos.zona_de(codigo) == {:ok, zona}
    end

    test "un centro de tipo punto de atención usa el código de un punto de la zona" do
      zona = crear_zona()
      punto = unico("P")
      {:ok, _sector} = Zonas.registrar_sector(zona, "s1", "Sector 1", "alto")
      {:ok, _punto} = Zonas.registrar_punto(zona, "s1", punto, "Punto de atención")

      assert {:ok, centro} = Recursos.registrar_centro(punto, "Punto", "punto_atencion", zona)
      assert centro.tipo == :punto_atencion

      assert Recursos.registrar_centro(unico("P"), "Otro", "punto_atencion", zona) ==
               {:error, :punto_no_existe}
    end

    test "valida el código, el tipo y la zona" do
      zona = crear_zona()
      codigo = crear_centro(zona)

      assert Recursos.registrar_centro(codigo, "Otro", "acopio", zona) == {:error, :ya_existe}

      assert Recursos.registrar_centro(unico("c"), "Centro", "acopio", "no_existe") ==
               {:error, :zona_no_existe}

      assert Recursos.registrar_centro(unico("c"), "Centro", "bodega", zona) ==
               {:error, :tipo_invalido}

      assert Recursos.registrar_centro(unico("c"), "Centro", "albergue", zona) ==
               {:error, :tipo_invalido}

      assert Recursos.zona_de("no_existe") == {:error, :centro_no_existe}
    end
  end

  describe "registro de recursos" do
    test "registra un recurso con su cantidad inicial en un centro de apoyo" do
      centro = crear_centro(crear_zona())
      codigo = unico("R")

      assert {:ok, recurso} = Recursos.registrar(codigo, "agua", 200, "litros", centro)
      assert recurso.categoria == :agua
      assert recurso.nombre == "agua"
      assert Recurso.disponible(recurso, centro) == 200
    end

    test "no permite códigos repetidos" do
      centro = crear_centro(crear_zona())
      codigo = crear_recurso("agua", 10, centro)

      assert Recursos.registrar(codigo, "agua", 5, "litros", centro) == {:error, :ya_existe}
    end

    test "valida centro, categoría y cantidad antes de guardar" do
      centro = crear_centro(crear_zona())

      assert Recursos.registrar(unico("R"), "agua", 10, "l", "nada") ==
               {:error, :centro_no_existe}

      assert Recursos.registrar(unico("R"), "gasolina", 10, "l", centro) ==
               {:error, :categoria_invalida}

      assert Recursos.registrar(unico("R"), "agua", -5, "l", centro) ==
               {:error, :cantidad_invalida}

      assert Recursos.registrar(unico("R"), "agua", "10", "l", centro) ==
               {:error, :cantidad_invalida}
    end
  end

  describe "concurrencia y tolerancia a fallos" do
    test "registros simultáneos con el mismo código: solo uno se guarda" do
      centro = crear_centro(crear_zona())
      codigo = unico("R")

      resultados =
        1..5
        |> Enum.map(fn _numero ->
          Task.async(fn -> Recursos.registrar(codigo, "agua", 10, "litros", centro) end)
        end)
        |> Enum.map(fn tarea -> Task.await(tarea) end)

      assert Enum.count(resultados, fn resultado -> resultado == {:error, :ya_existe} end) == 4
    end
  end
end
