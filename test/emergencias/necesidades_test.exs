defmodule Emergencias.NecesidadesTest do
  use ExUnit.Case

  alias Emergencias.Albergues
  alias Emergencias.Necesidades
  alias Emergencias.Personas
  alias Emergencias.Recursos
  alias Emergencias.Zonas

  # ========== Datos de prueba y ayudas ==========

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  defp crear_zona do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona de prueba", "alto")
    zona
  end

  defp necesidad(tipo, cantidad, prioridad, zona) do
    {:ok, necesidad} =
      Necesidades.registrar(tipo, cantidad, prioridad, zona, "Necesidad de prueba", "laura")

    necesidad
  end

  defp ids(necesidades), do: Enum.map(necesidades, fn necesidad -> necesidad.id end)

  # Un centro de acopio en la zona con `cantidad` unidades de la categoría
  defp abastecer(zona, categoria, cantidad) do
    centro = unico("centro_")
    {:ok, _centro} = Recursos.registrar_centro(centro, "Centro de acopio", "acopio", zona)
    {:ok, _recurso} = Recursos.registrar(unico("R"), categoria, cantidad, "unidades", centro)
    centro
  end

  defp disponible(categoria, zona) do
    {:ok, cantidad} = Recursos.disponibilidad(categoria, zona)
    cantidad
  end

  defp confirmada?({:ok, _necesidad}), do: true
  defp confirmada?(_resultado), do: false

  # ========== Pruebas ==========

  describe "registro" do
    test "registra una necesidad pendiente con identificador único" do
      zona = crear_zona()
      n1 = necesidad("agua", 30, "critica", zona)
      n2 = necesidad("alimentos", 10, "baja", zona)

      assert n1.estado == :pendiente
      assert n1.tipo == :agua
      assert n1.prioridad == :critica
      assert n1.responsable == "laura"
      assert String.first(n1.id) == "N"
      refute n1.id == n2.id
      assert Necesidades.zona_de(n1.id) == {:ok, zona}
    end

    test "valida los datos antes de registrar" do
      zona = crear_zona()

      assert Necesidades.registrar("gasolina", 5, "alta", zona, "x", "u") ==
               {:error, :tipo_invalido}

      assert Necesidades.registrar("agua", 5, "urgente", zona, "x", "u") ==
               {:error, :prioridad_invalida}

      assert Necesidades.registrar("agua", 5, "alta", "no_existe", "x", "u") ==
               {:error, :zona_no_existe}

      assert Necesidades.registrar("agua", 0, "alta", zona, "x", "u") ==
               {:error, :cantidad_invalida}

      assert Necesidades.registrar("agua", 5, "alta", zona, " ", "u") ==
               {:error, :descripcion_invalida}

      assert Necesidades.registrar("agua", 5, "alta", zona, "agua; urgente", "u") ==
               {:error, :descripcion_invalida}

      assert Necesidades.zona_de("N999999") == {:error, :necesidad_no_existe}
    end
  end

  describe "destino" do
    test "sin destino, la necesidad queda asociada a su zona" do
      zona = crear_zona()

      assert necesidad("agua", 5, "media", zona).destino == {:zona, zona}
    end

    test "el destino puede ser un punto de atención de la zona" do
      zona = crear_zona()
      punto = unico("P")
      {:ok, _sector} = Zonas.registrar_sector(zona, "s3", "Sector 3", "critico")
      {:ok, _punto} = Zonas.registrar_punto(zona, "s3", punto, "Punto sector 3")

      assert {:ok, n} =
               Necesidades.registrar("agua", 30, "critica", zona, "x", "laura", {:punto, punto})

      assert n.destino == {:punto, punto}

      assert Necesidades.registrar("agua", 1, "alta", zona, "x", "u", {:punto, "P-no"}) ==
               {:error, :punto_no_existe}
    end

    test "el destino puede ser un albergue existente" do
      zona = crear_zona()
      albergue = unico("A")
      {:ok, _albergue} = Albergues.registrar(albergue, "Albergue de prueba", zona, 50)

      assert {:ok, n} =
               Necesidades.registrar("alimentos", 40, "alta", zona, "Cena", "pedro", {
                 :albergue,
                 albergue
               })

      assert ids(Necesidades.por_albergue(albergue)) == [n.id]

      assert Necesidades.registrar("agua", 1, "alta", zona, "x", "u", {:albergue, "A-no"}) ==
               {:error, :albergue_no_existe}
    end

    test "un tipo de destino desconocido se rechaza" do
      zona = crear_zona()

      assert Necesidades.registrar("agua", 1, "alta", zona, "x", "u", {:mascota, "Luna"}) ==
               {:error, :destino_invalido}

      assert Necesidades.registrar("agua", 1, "alta", zona, "x", "u", "F001") ==
               {:error, :destino_invalido}
    end

    @tag :personas
    test "el destino puede ser una persona registrada; una persona o familia inexistente se rechaza" do
      zona = crear_zona()
      documento = unico("doc")
      {:ok, _persona} = Personas.registrar(documento, "Persona de prueba", zona, "reportada")

      assert {:ok, n} =
               Necesidades.registrar(
                 "medicamentos",
                 2,
                 "alta",
                 zona,
                 "x",
                 "u",
                 {:persona, documento}
               )

      assert n.destino == {:persona, documento}

      assert Necesidades.registrar("agua", 1, "alta", zona, "x", "u", {:persona, "doc-no"}) ==
               {:error, :persona_no_existe}

      assert Necesidades.registrar("agua", 1, "alta", zona, "x", "u", {:familia, "F-no"}) ==
               {:error, :familia_no_existe}
    end
  end

  describe "consultas" do
    test "por zona, tipo, prioridad y estado, ordenadas por prioridad" do
      zona = crear_zona()
      baja = necesidad("agua", 5, "baja", zona)
      critica1 = necesidad("agua", 5, "critica", zona)
      media = necesidad("alimentos", 5, "media", zona)
      critica2 = necesidad("alimentos", 5, "critica", zona)

      assert ids(Necesidades.listar(zona: zona)) == [critica1.id, critica2.id, media.id, baja.id]

      assert ids(Necesidades.listar(zona: zona, prioridad: "critica")) == [
               critica1.id,
               critica2.id
             ]

      assert ids(Necesidades.listar(%{"zona" => zona, "tipo" => "alimentos"})) == [
               critica2.id,
               media.id
             ]

      assert ids(Necesidades.listar(zona: zona, estado: :atendida)) == []
    end

    test "siguiente devuelve la necesidad sin atender más urgente de la zona" do
      zona = crear_zona()
      baja = necesidad("transporte", 2, "baja", zona)
      alta = necesidad("transporte", 1, "alta", zona)

      assert {:ok, %{id: id}} = Necesidades.siguiente(zona)
      assert id == alta.id

      {:ok, _n} = Necesidades.cambiar_estado(alta.id, "en_atencion")
      assert {:ok, %{id: id}} = Necesidades.siguiente(zona)
      assert id == baja.id

      {:ok, _n} = Necesidades.cancelar(baja.id)
      assert Necesidades.siguiente(zona) == {:error, :sin_pendientes}
    end

    test "pendientes solo incluye necesidades abiertas" do
      zona = crear_zona()
      abierta = necesidad("refugio", 3, "media", zona)
      cerrada = necesidad("refugio", 3, "alta", zona)
      {:ok, _n} = Necesidades.cancelar(cerrada.id)

      pendientes = ids(Necesidades.pendientes())
      assert abierta.id in pendientes
      refute cerrada.id in pendientes
    end
  end

  describe "asignación de recursos" do
    test "asignar recursos descuenta del inventario y pasa la necesidad a asignada" do
      zona = crear_zona()
      abastecer(zona, "agua", 50)
      n = necesidad("agua", 30, "critica", zona)

      assert {:ok, asignada} = Necesidades.asignar_recurso(n.id, "agua", 30)
      assert asignada.estado == :asignada
      assert asignada.asignado == 30
      assert disponible("agua", zona) == 20
    end

    test "se puede asignar por partes, pero nunca más de lo requerido" do
      zona = crear_zona()
      abastecer(zona, "alimentos", 100)
      n = necesidad("alimentos", 30, "alta", zona)

      assert {:ok, _necesidad} = Necesidades.asignar_recurso(n.id, "alimentos", 10)

      assert Necesidades.asignar_recurso(n.id, "alimentos", 25) ==
               {:error, :excede_lo_requerido}

      assert {:ok, completa} = Necesidades.asignar_recurso(n.id, "alimentos", 20)
      assert completa.asignado == 30
      assert disponible("alimentos", zona) == 70
    end

    test "si no hay suficiente inventario no se asigna nada" do
      zona = crear_zona()
      abastecer(zona, "agua", 10)
      n = necesidad("agua", 30, "critica", zona)

      assert Necesidades.asignar_recurso(n.id, "agua", 30) == {:error, :stock_insuficiente}
      assert {:ok, igual} = Necesidades.consultar(n.id)
      assert igual.estado == :pendiente
      assert igual.asignado == 0
      assert disponible("agua", zona) == 10
    end

    test "la categoría debe corresponder al tipo de la necesidad" do
      zona = crear_zona()
      abastecer(zona, "alimentos", 10)
      n = necesidad("agua", 5, "media", zona)

      assert Necesidades.asignar_recurso(n.id, "alimentos", 5) ==
               {:error, :categoria_no_corresponde}

      assert Necesidades.asignar_recurso("N999999", "agua", 5) == {:error, :necesidad_no_existe}
    end

    test "una necesidad atendida o cancelada no vuelve a consumir recursos" do
      zona = crear_zona()
      abastecer(zona, "medicamentos", 100)
      atendida = necesidad("medicamentos", 20, "alta", zona)
      cancelada = necesidad("medicamentos", 20, "media", zona)

      {:ok, _n} = Necesidades.asignar_recurso(atendida.id, "medicamentos", 10)
      {:ok, _n} = Necesidades.cambiar_estado(atendida.id, "en_atencion")
      {:ok, _n} = Necesidades.cambiar_estado(atendida.id, "atendida")
      {:ok, _n} = Necesidades.cancelar(cancelada.id)

      assert Necesidades.asignar_recurso(atendida.id, "medicamentos", 5) ==
               {:error, :necesidad_cerrada}

      assert Necesidades.asignar_recurso(cancelada.id, "medicamentos", 5) ==
               {:error, :necesidad_cerrada}

      assert disponible("medicamentos", zona) == 90
    end
  end

  describe "estados y cancelación" do
    test "los estados siguen transiciones válidas y no se cierra dos veces" do
      zona = crear_zona()
      n = necesidad("rescate", 1, "critica", zona)

      assert Necesidades.cambiar_estado(n.id, "atendida") == {:error, :transicion_invalida}
      assert Necesidades.cambiar_estado(n.id, "asignada") == {:error, :transicion_invalida}
      assert Necesidades.cambiar_estado(n.id, "resuelta") == {:error, :estado_invalido}
      assert {:ok, %{estado: :en_atencion}} = Necesidades.cambiar_estado(n.id, "en_atencion")
      assert {:ok, %{estado: :atendida}} = Necesidades.cambiar_estado(n.id, "atendida")
      assert Necesidades.cambiar_estado(n.id, "atendida") == {:error, :necesidad_cerrada}
      assert Necesidades.cancelar(n.id) == {:error, :necesidad_cerrada}
    end

    test "cancelar una necesidad asignada devuelve lo reservado a sus centros" do
      zona = crear_zona()
      abastecer(zona, "agua", 50)
      n = necesidad("agua", 30, "critica", zona)
      {:ok, _n} = Necesidades.asignar_recurso(n.id, "agua", 30)

      assert {:ok, %{estado: :cancelada}} = Necesidades.cancelar(n.id)
      assert disponible("agua", zona) == 50

      assert Necesidades.cancelar(n.id) == {:error, :necesidad_cerrada}
      assert Recursos.devolver(n.id) == {:ok, []}
      assert disponible("agua", zona) == 50
    end

    test "cancelar una necesidad en atención no devuelve nada: los recursos ya se usaron" do
      zona = crear_zona()
      abastecer(zona, "alimentos", 50)
      n = necesidad("alimentos", 20, "alta", zona)
      {:ok, _n} = Necesidades.asignar_recurso(n.id, "alimentos", 20)
      {:ok, _n} = Necesidades.cambiar_estado(n.id, "en_atencion")

      assert {:ok, %{estado: :cancelada}} = Necesidades.cambiar_estado(n.id, "cancelada")
      assert disponible("alimentos", zona) == 30
    end
  end

  describe "concurrencia" do
    test "flujo del enunciado: 30 y 25 litros a la vez sobre 50 disponibles" do
      zona = crear_zona()
      abastecer(zona, "agua", 50)
      laura = necesidad("agua", 30, "critica", zona)
      pedro = necesidad("agua", 25, "alta", zona)

      resultados =
        [{laura.id, 30}, {pedro.id, 25}]
        |> Enum.map(fn {id, cantidad} ->
          Task.async(fn -> Necesidades.asignar_recurso(id, "agua", cantidad) end)
        end)
        |> Enum.map(fn tarea -> Task.await(tarea) end)

      assert Enum.count(resultados, fn resultado -> confirmada?(resultado) end) == 1
      assert Enum.member?(resultados, {:error, :stock_insuficiente})
      assert disponible("agua", zona) in [20, 25]
    end
  end
end
