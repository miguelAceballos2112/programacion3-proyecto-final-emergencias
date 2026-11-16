defmodule Emergencias.Comandos.LogisticaTest do
  use ExUnit.Case

  alias Emergencias.Comandos.Logistica
  alias Emergencias.Necesidades
  alias Emergencias.Personas
  alias Emergencias.Recursos
  alias Emergencias.Zonas

  # ========== Datos de prueba y ayudas ==========

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  defp crear_zona do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona de prueba", "critico")
    zona
  end

  defp ejecutar(comando, argumentos), do: Logistica.ejecutar(comando, argumentos, "laura")

  # Ejecuta un comando que debe funcionar y devuelve sus líneas de texto
  defp lineas(comando, argumentos) do
    {:ok, texto} = ejecutar(comando, argumentos)
    String.split(texto, "\n")
  end

  # Una zona con un centro de acopio que tiene 50 litros de agua
  defp zona_con_agua do
    zona = crear_zona()
    centro = unico("acopio_")
    recurso = unico("R")
    {:ok, _texto} = ejecutar("register_center", [centro, "Centro de acopio", "acopio", zona])
    {:ok, _texto} = ejecutar("register_resource", [recurso, "agua", "50", "litros", centro])
    {zona, centro, recurso}
  end

  defp disponible(zona) do
    {:ok, cantidad} = Recursos.disponibilidad("agua", zona)
    cantidad
  end

  # Registra con el comando la única necesidad de la zona y devuelve su id
  defp nueva_necesidad(zona, cantidad) do
    {:ok, _texto} =
      ejecutar("register_need", ["agua", cantidad, "critica", zona, "Punto del sector 3"])

    [necesidad] = Necesidades.listar(zona: zona)
    necesidad.id
  end

  # ========== Pruebas ==========

  describe "comandos/0" do
    test "son los 20 comandos de logística del plan" do
      assert Enum.count(Logistica.comandos()) == 20
      assert Enum.member?(Logistica.comandos(), "cancel_need")
    end
  end

  describe "centros y recursos" do
    test "register_center y register_resource responden con un texto para el usuario" do
      zona = crear_zona()
      centro = unico("acopio_")
      recurso = unico("R")

      assert ejecutar("register_center", [centro, "Centro 1", "acopio", zona]) ==
               {:ok, "Centro #{centro} (acopio) registrado en la zona #{zona}."}

      assert ejecutar("register_resource", [recurso, "agua", "200", "litros", centro]) ==
               {:ok, "Recurso #{recurso} (agua) registrado: 200 litros en #{centro}."}
    end

    test "register_resource acepta el nombre como opción" do
      zona = crear_zona()
      centro = unico("acopio_")
      recurso = unico("R")
      {:ok, _texto} = ejecutar("register_center", [centro, "Centro 1", "acopio", zona])

      assert {:ok, _texto} =
               ejecutar("register_resource", [
                 recurso,
                 "agua",
                 "10",
                 "litros",
                 centro,
                 "nombre=Agua potable"
               ])

      assert {:ok, %{nombre: "Agua potable"}} = Recursos.consultar(recurso)
    end

    test "add_stock, remove_stock, transfer_resource y list_movements" do
      {zona, centro, recurso} = zona_con_agua()
      otro = unico("acopio_")
      {:ok, _texto} = ejecutar("register_center", [otro, "Centro 2", "acopio", zona])

      assert ejecutar("add_stock", [recurso, centro, "10"]) ==
               {:ok, "Entraron 10 litros de #{recurso} a #{centro}. Hay 60."}

      assert ejecutar("remove_stock", [recurso, centro, "5"]) ==
               {:ok, "Salieron 5 litros de #{recurso} de #{centro}. Quedan 55."}

      assert ejecutar("transfer_resource", [recurso, centro, otro, "20"]) ==
               {:ok, "Se transfirieron 20 litros de #{recurso} de #{centro} a #{otro}."}

      assert Enum.count(lineas("list_movements", [recurso])) == 4
    end

    test "list_resources filtra por zona y categoría" do
      {zona, centro, recurso} = zona_con_agua()

      assert lineas("list_resources", ["zona=#{zona}", "categoria=agua"]) == [
               "Disponible de agua en #{zona}: 50",
               "#{recurso} agua (agua): 50 litros (#{centro}: 50)"
             ]

      assert lineas("list_resources", ["zona=#{zona}", "categoria=alimentos"]) == [
               "Disponible de alimentos en #{zona}: 0"
             ]

      assert ejecutar("list_resources", ["categoria=gasolina"]) == {:error, :categoria_invalida}
    end
  end

  describe "necesidades" do
    test "register_need, assign_resource, list_needs y cancel_need" do
      {zona, _centro, _recurso} = zona_con_agua()
      id = nueva_necesidad(zona, "30")

      assert ejecutar("assign_resource", [id, "agua", "30"]) ==
               {:ok, "Se asignaron 30 de agua a #{id}: lleva 30 de 30 (asignada)."}

      assert disponible(zona) == 20

      assert lineas("list_needs", ["zona=#{zona}"]) == [
               "#{id} [critica] agua 30/30, zona #{zona}, asignada, para zona #{zona}: Punto del sector 3"
             ]

      assert ejecutar("cancel_need", [id]) == {:ok, "La necesidad #{id} fue cancelada."}
      assert disponible(zona) == 50
    end

    test "register_need con destino y next_need" do
      zona = crear_zona()
      albergue = unico("A")
      {:ok, _texto} = ejecutar("register_shelter", [albergue, "Albergue Norte", zona, "150"])

      assert {:ok, _texto} =
               ejecutar("register_need", [
                 "alimentos",
                 "40",
                 "alta",
                 zona,
                 "Cena",
                 "destino=albergue:#{albergue}"
               ])

      assert {:ok, "Siguiente: " <> _resto} = ejecutar("next_need", [zona])

      assert ejecutar("register_need", ["agua", "1", "alta", zona, "x", "destino=albergue"]) ==
               {:error, :destino_invalido}
    end

    test "update_need_status, pending_needs y critical_resources" do
      {zona, _centro, _recurso} = zona_con_agua()
      id = nueva_necesidad(zona, "80")

      assert ejecutar("update_need_status", [id, "en_atencion"]) ==
               {:ok, "La necesidad #{id} pasó a en_atencion."}

      assert {:ok, _texto} = ejecutar("pending_needs", [])

      assert Enum.member?(
               lineas("critical_resources", []),
               "Zona #{zona}, agua: faltan 30 (se piden 80, hay 50)"
             )
    end

    test "un filtro desconocido en list_needs se rechaza" do
      assert ejecutar("list_needs", ["color=rojo"]) == {:error, :opcion_invalida}
    end
  end

  describe "albergues" do
    test "register_shelter con ocupación, check_shelter y shelter_report" do
      zona = crear_zona()
      albergue = unico("A")

      assert ejecutar("register_shelter", [albergue, "Albergue Sur", zona, "150", "148"]) ==
               {:ok, "Albergue #{albergue} registrado en la zona #{zona}: 148 de 150 (98.7 %)."}

      assert lineas("check_shelter", [albergue]) == [
               "Albergue #{albergue} (Albergue Sur), zona #{zona}",
               "Ocupación: 148 de 150 (98.7 %), cupos: 2",
               "Recursos:",
               "  ninguno",
               "Necesidades:",
               "  ninguna"
             ]

      assert Enum.member?(
               lineas("shelter_report", ["1000"]),
               "#{albergue} Albergue Sur: 148 de 150 (98.7 %)"
             )
    end

    @tag :personas
    test "register_entry y register_exit" do
      zona = crear_zona()
      albergue = unico("A")
      documento = unico("doc")
      {:ok, _texto} = ejecutar("register_shelter", [albergue, "Albergue", zona, "10"])
      {:ok, _persona} = Personas.registrar(documento, "Persona de prueba", zona, "reportada")

      assert ejecutar("register_entry", [albergue, documento]) ==
               {:ok, "#{documento} ingresó a #{albergue}. Cupos: 9."}

      assert ejecutar("register_exit", [albergue, documento]) ==
               {:ok, "#{documento} salió de #{albergue}. Cupos: 10."}
    end
  end

  describe "errores" do
    test "los errores de los servidores llegan tal cual" do
      assert ejecutar("check_shelter", ["no_existe"]) == {:error, :albergue_no_existe}
      assert ejecutar("cancel_need", ["N999999"]) == {:error, :necesidad_no_existe}
    end

    test "un número mal escrito, argumentos de más y un comando desconocido" do
      {_zona, centro, recurso} = zona_con_agua()

      assert ejecutar("add_stock", [recurso, centro, "diez"]) == {:error, :numero_invalido}
      assert ejecutar("add_stock", [recurso, centro]) == {:error, :argumentos_invalidos}
      assert ejecutar("register_zone", ["centro"]) == {:error, :comando_desconocido}
    end
  end
end
