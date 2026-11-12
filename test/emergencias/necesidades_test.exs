defmodule Emergencias.NecesidadesTest do
  use ExUnit.Case

  alias Emergencias.Albergues
  alias Emergencias.Necesidades
  alias Emergencias.Personas
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
  end
end
