defmodule Emergencias.Recursos.RepartoTest do
  use ExUnit.Case, async: true

  alias Emergencias.Recursos.Reparto

  @fuentes [{"R1", "c1", 50}, {"R2", "c2", 30}]

  describe "total/1" do
    test "suma lo disponible de todas las fuentes" do
      assert Reparto.total(@fuentes) == 80
      assert Reparto.total([]) == 0
    end
  end

  describe "repartir/2" do
    test "si la primera fuente alcanza, solo se toma de ella" do
      assert Reparto.repartir(@fuentes, 30) == {:ok, [{"R1", "c1", 30}]}
    end

    test "si una fuente no alcanza, se completa con las siguientes" do
      assert Reparto.repartir(@fuentes, 60) == {:ok, [{"R1", "c1", 50}, {"R2", "c2", 10}]}
    end

    test "se puede pedir exactamente todo lo disponible" do
      assert Reparto.repartir(@fuentes, 80) == {:ok, [{"R1", "c1", 50}, {"R2", "c2", 30}]}
    end

    test "si entre todas no alcanza, no se toma nada" do
      assert Reparto.repartir(@fuentes, 81) == {:error, :stock_insuficiente}
      assert Reparto.repartir([], 1) == {:error, :stock_insuficiente}
    end
  end
end
