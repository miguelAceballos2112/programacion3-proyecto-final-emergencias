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

  defp total(codigo) do
    {:ok, recurso} = Recursos.consultar(codigo)
    Recurso.total(recurso)
  end

  defp tipos_de_movimiento(codigo) do
    Enum.map(Recursos.historial(codigo), fn movimiento -> movimiento.tipo end)
  end

  # Espera, consultando cada 10 ms, a que el supervisor inicie un proceso nuevo
  defp esperar_reinicio(nombre, anterior, intentos \\ 100)
  defp esperar_reinicio(_nombre, _anterior, 0), do: :sin_reinicio

  defp esperar_reinicio(nombre, anterior, intentos) do
    actual = Process.whereis(nombre)

    if actual == nil or actual == anterior do
      :timer.sleep(10)
      esperar_reinicio(nombre, anterior, intentos - 1)
    else
      :ok
    end
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

  describe "entradas, salidas y transferencias" do
    test "entradas y salidas de inventario; una salida nunca deja cantidades negativas" do
      centro = crear_centro(crear_zona())
      codigo = crear_recurso("alimentos", 20, centro)

      assert {:ok, _recurso} = Recursos.entrada(codigo, centro, 30)
      assert {:ok, _recurso} = Recursos.salida(codigo, centro, 15)
      assert total(codigo) == 35

      assert Recursos.salida(codigo, centro, 36) == {:error, :stock_insuficiente}
      assert Recursos.entrada(codigo, centro, 0) == {:error, :cantidad_invalida}
      assert total(codigo) == 35
    end

    test "transferencia entre centros: resta en el origen y suma en el destino" do
      zona = crear_zona()
      origen = crear_centro(zona)
      destino = crear_centro(zona)
      codigo = crear_recurso("agua", 200, origen)

      assert {:ok, recurso} = Recursos.transferir(codigo, origen, destino, 30)
      assert Recurso.disponible(recurso, origen) == 170
      assert Recurso.disponible(recurso, destino) == 30
      assert Recurso.total(recurso) == 200
      assert [%{codigo: ^codigo, cantidad: 30}] = Recursos.por_centro(destino)
    end

    test "una transferencia inválida no cambia nada" do
      zona = crear_zona()
      origen = crear_centro(zona)
      destino = crear_centro(zona)
      codigo = crear_recurso("agua", 200, origen)

      assert Recursos.transferir(codigo, origen, destino, 201) == {:error, :stock_insuficiente}
      assert Recursos.transferir(codigo, origen, origen, 10) == {:error, :mismo_centro}
      assert Recursos.transferir(codigo, origen, "nada", 10) == {:error, :centro_no_existe}

      {:ok, recurso} = Recursos.consultar(codigo)
      assert Recurso.disponible(recurso, origen) == 200
      assert Recurso.disponible(recurso, destino) == 0
    end

    test "conserva el historial de movimientos en orden" do
      zona = crear_zona()
      origen = crear_centro(zona)
      destino = crear_centro(zona)
      codigo = crear_recurso("medicamentos", 50, origen)

      Recursos.entrada(codigo, origen, 10)
      Recursos.salida(codigo, origen, 5)
      Recursos.transferir(codigo, origen, destino, 20)
      Recursos.salida(codigo, origen, 999)

      assert tipos_de_movimiento(codigo) == [:registro, :entrada, :salida, :transferencia]
      assert length(Recursos.historial()) >= 4
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

    test "si el servidor falla, el supervisor lo reinicia y no se pierde el inventario" do
      centro = crear_centro(crear_zona())
      codigo = crear_recurso("refugio", 12, centro)
      Recursos.salida(codigo, centro, 2)

      anterior = Process.whereis(Recursos)
      Process.exit(anterior, :kill)

      assert esperar_reinicio(Recursos, anterior) == :ok
      assert total(codigo) == 10
      assert Recursos.existe_centro?(centro)
      assert tipos_de_movimiento(codigo) == [:registro, :salida]
    end
  end
end
