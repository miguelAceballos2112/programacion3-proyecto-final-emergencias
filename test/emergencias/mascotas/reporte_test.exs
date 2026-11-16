defmodule Emergencias.Mascotas.ReporteTest do
  # Pruebas de funciones puras: no usan procesos ni archivos
  use ExUnit.Case, async: true

  alias Emergencias.Mascotas.Reporte

  defp reporte(estado \\ :activa, pareja \\ nil) do
    %Reporte{
      id: "M001",
      tipo: :perdida,
      especie: "perro",
      nombre: "Firulais",
      caracteristicas: "collar rojo",
      color: "café",
      tamano: :mediano,
      zona: "centro",
      contacto: "3001234567",
      estado: estado,
      pareja: pareja
    }
  end

  describe "transiciones de estado" do
    test "permite las transiciones de la tabla" do
      assert Reporte.puede_pasar(:activa, :posible_coincidencia) == :ok
      assert Reporte.puede_pasar(:activa, :resuelta) == :ok
      assert Reporte.puede_pasar(:posible_coincidencia, :activa) == :ok
      assert Reporte.puede_pasar(:posible_coincidencia, :resuelta) == :ok
    end

    test "resuelta es terminal: no admite ninguna transición" do
      for destino <- Reporte.estados() do
        assert Reporte.puede_pasar(:resuelta, destino) == {:error, :transicion_invalida}
      end
    end

    test "activa no pasa a activa" do
      assert Reporte.puede_pasar(:activa, :activa) == {:error, :transicion_invalida}
    end
  end

  describe "proponer, liberar y resolver" do
    test "proponer marca la pareja y solo sirve con un reporte activo" do
      assert {:ok, propuesto} = Reporte.proponer(reporte(), "M002")
      assert propuesto.estado == :posible_coincidencia
      assert propuesto.pareja == "M002"
      assert Reporte.proponer(propuesto, "M003") == {:error, :transicion_invalida}
    end

    test "liberar devuelve el reporte a activo y quita la pareja" do
      assert {:ok, libre} = Reporte.liberar(reporte(:posible_coincidencia, "M002"))
      assert libre.estado == :activa
      assert libre.pareja == nil
      assert Reporte.liberar(libre) == {:error, :transicion_invalida}
    end

    test "resolver cierra el reporte y no se puede cerrar dos veces" do
      assert {:ok, cerrado} = Reporte.resolver(reporte(), "M002")
      assert cerrado.estado == :resuelta
      assert cerrado.pareja == "M002"
      assert Reporte.resolver(cerrado, "M002") == {:error, :transicion_invalida}
    end
  end

  describe "a_fila y desde_fila" do
    test "un reporte sin pareja sobrevive al viaje de ida y vuelta" do
      original = reporte()
      assert {:ok, ^original} = original |> Reporte.a_fila() |> Reporte.desde_fila()
    end

    test "un reporte con pareja también" do
      original = reporte(:posible_coincidencia, "M002")
      assert {:ok, ^original} = original |> Reporte.a_fila() |> Reporte.desde_fila()
    end

    test "una fila con valores fuera del catálogo o con campos de menos se rechaza" do
      campos = Reporte.a_fila(reporte())

      assert Reporte.desde_fila(List.replace_at(campos, 1, "robada")) == {:error, :fila_invalida}
      assert Reporte.desde_fila(List.replace_at(campos, 6, "enorme")) == {:error, :fila_invalida}
      assert Reporte.desde_fila(List.replace_at(campos, 9, "perdida")) == {:error, :fila_invalida}
      assert Reporte.desde_fila(["M001", "perdida"]) == {:error, :fila_invalida}
    end
  end

  test "limpiar quita el punto y coma y deja vacío lo que no es texto" do
    assert Reporte.limpiar("collar; rojo") == "collar, rojo"
    assert Reporte.limpiar(nil) == ""
  end
end
