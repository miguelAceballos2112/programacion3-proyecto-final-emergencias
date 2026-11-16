defmodule Emergencias.Mascotas.SimilitudTest do
  # Funciones puras: no usan procesos ni archivos
  use ExUnit.Case, async: true

  alias Emergencias.Mascotas.Similitud

  defp mascota(cambios \\ []) do
    base = %{
      especie: "perro",
      color: "café",
      tamano: :mediano,
      zona: "centro",
      caracteristicas: "collar rojo manchas blancas"
    }

    Map.merge(base, Map.new(cambios))
  end

  describe "puntaje/2" do
    test "dos reportes idénticos suman 100" do
      assert Similitud.puntaje(mascota(), mascota()) == 100
    end

    test "una especie distinta descarta el par, aunque todo lo demás coincida" do
      assert Similitud.puntaje(mascota(), mascota(especie: "gato")) == 0
    end

    test "solo la especie en común aporta 30 puntos" do
      otra =
        mascota(color: "negro", tamano: :grande, zona: "norte", caracteristicas: "orejas largas")

      assert Similitud.puntaje(mascota(), otra) == 30
    end

    test "cada atributo aporta su peso: color 20, tamaño 15, zona 15" do
      sin_caracteristicas = mascota(caracteristicas: "")
      sin_color = mascota(caracteristicas: "", color: "negro")
      sin_tamano = mascota(caracteristicas: "", tamano: :grande)
      sin_zona = mascota(caracteristicas: "", zona: "norte")

      # Sin características en ninguno de los dos, esa parte aporta 0
      assert Similitud.puntaje(sin_caracteristicas, sin_caracteristicas) == 80
      assert Similitud.puntaje(sin_caracteristicas, sin_color) == 60
      assert Similitud.puntaje(sin_caracteristicas, sin_tamano) == 65
      assert Similitud.puntaje(sin_caracteristicas, sin_zona) == 65
    end

    test "las características puntúan por palabras en común sobre palabras totales" do
      # Comunes: collar, rojo. Totales: collar, rojo, manchas, blancas, orejas, largas = 6
      otra = mascota(caracteristicas: "collar rojo orejas largas")
      assert Similitud.puntaje(mascota(), otra) == 80 + 7

      # Una palabra en común de tres distintas aporta 20 / 3, redondeado a 7
      assert Similitud.puntaje(
               mascota(caracteristicas: "collar azul"),
               mascota(caracteristicas: "collar rojo")
             ) == 80 + 7

      # Dos de cuatro (la mitad) aportan la mitad de los 20 puntos
      cuatro = mascota(caracteristicas: "collar rojo azul verde")
      assert Similitud.puntaje(mascota(caracteristicas: "collar rojo"), cuatro) == 90

      # Todas en común aportan los 20 completos
      assert Similitud.puntaje(
               mascota(caracteristicas: "collar rojo"),
               mascota(caracteristicas: "collar rojo")
             ) == 100
    end

    test "no distingue mayúsculas ni espacios sobrantes" do
      otra =
        mascota(
          especie: " PERRO ",
          color: "CAFÉ",
          zona: "Centro",
          caracteristicas: "COLLAR ROJO manchas Blancas"
        )

      assert Similitud.puntaje(mascota(), otra) == 100
    end

    test "el puntaje nunca sale del rango de 0 a 100" do
      for caracteristicas <- ["", "a", "collar", "collar rojo manchas blancas", "x y z"] do
        puntaje = Similitud.puntaje(mascota(), mascota(caracteristicas: caracteristicas))
        assert puntaje >= 0 and puntaje <= 100
      end
    end
  end

  describe "puntaje/3 (recursivo sobre la lista de atributos)" do
    test "con una lista vacía solo cuenta la especie" do
      assert Similitud.puntaje(mascota(), mascota(color: "negro"), []) == 30
    end

    test "con una lista a medida solo suma esos atributos" do
      otra = mascota(zona: "norte")
      assert Similitud.puntaje(mascota(), otra, color: 20) == 50
      assert Similitud.puntaje(mascota(), otra, zona: 15) == 30
    end
  end

  test "el umbral de posible coincidencia es 60" do
    assert Similitud.umbral() == 60
  end
end
