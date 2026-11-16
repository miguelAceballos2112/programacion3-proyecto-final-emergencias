defmodule Emergencias.Albergues.AlbergueTest do
  use ExUnit.Case, async: true

  alias Emergencias.Albergues.Albergue

  defp con_ocupantes(codigo, capacidad, cantidad) do
    albergue = Albergue.crear(codigo, "Albergue #{codigo}", "zona", capacidad)

    Enum.reduce(1..cantidad, albergue, fn numero, acumulado ->
      {:ok, siguiente} = Albergue.ingresar(acumulado, "#{codigo}-#{numero}")
      siguiente
    end)
  end

  defp codigos(albergues), do: Enum.map(albergues, fn albergue -> albergue.codigo end)

  describe "ingresar/2 y salir/2" do
    test "ingresar ocupa un cupo y no admite a la misma persona dos veces" do
      albergue = Albergue.crear("A01", "Albergue Norte", "zona_norte", 2)

      assert {:ok, albergue} = Albergue.ingresar(albergue, "1001")
      assert Albergue.ocupacion(albergue) == 1
      assert Albergue.cupos(albergue) == 1
      assert Albergue.ingresar(albergue, "1001") == {:error, :ya_esta_en_albergue}
    end

    test "no se supera la capacidad máxima" do
      albergue = con_ocupantes("A02", 2, 2)

      assert Albergue.cupos(albergue) == 0
      assert Albergue.ingresar(albergue, "otra") == {:error, :albergue_lleno}
    end

    test "salir libera el cupo; no puede salir quien no está" do
      albergue = con_ocupantes("A03", 3, 2)

      assert {:ok, albergue} = Albergue.salir(albergue, "A03-1")
      assert MapSet.to_list(albergue.ocupantes) == ["A03-2"]
      assert Albergue.cupos(albergue) == 2
      assert Albergue.salir(albergue, "A03-1") == {:error, :no_esta_en_albergue}
    end
  end

  describe "ocupación" do
    test "la ocupación inicial cuenta para la ocupación y los cupos" do
      albergue = Albergue.crear("A04", "Albergue Sur", "zona_sur", 10, 4)

      assert Albergue.ocupacion(albergue) == 4
      assert Albergue.cupos(albergue) == 6
      assert Albergue.porcentaje(albergue) == 40.0
    end

    test "un albergue que se registró lleno no recibe a nadie" do
      albergue = Albergue.crear("A05", "Albergue Lleno", "zona", 3, 3)

      assert Albergue.ingresar(albergue, "1001") == {:error, :albergue_lleno}
    end

    test "porcentaje de ocupación con un decimal" do
      assert Albergue.porcentaje(con_ocupantes("A06", 4, 1)) == 25.0
      assert Albergue.porcentaje(con_ocupantes("A07", 3, 1)) == 33.3
    end

    test "ordena de mayor a menor ocupación" do
      a = con_ocupantes("A", 2, 2)
      b = con_ocupantes("B", 4, 1)
      c = con_ocupantes("C", 10, 5)

      assert codigos(Albergue.ordenar_por_ocupacion([b, a, c])) == ["A", "C", "B"]
      assert Albergue.ordenar_por_ocupacion([]) == []
    end
  end

  describe "a_fila/1 y desde_fila/1" do
    test "la fila del archivo conserva los ocupantes y la ocupación inicial" do
      albergue = %{con_ocupantes("A08", 5, 3) | ocupacion_inicial: 1}

      assert Albergue.desde_fila(Albergue.a_fila(albergue)) == albergue
    end
  end
end
