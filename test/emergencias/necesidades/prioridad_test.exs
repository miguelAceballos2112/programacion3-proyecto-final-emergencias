defmodule Emergencias.Necesidades.PrioridadTest do
  use ExUnit.Case, async: true

  alias Emergencias.Necesidades.Necesidad
  alias Emergencias.Necesidades.Prioridad

  defp necesidad(id, prioridad), do: %Necesidad{id: id, prioridad: prioridad}

  defp ids(necesidades), do: Enum.map(necesidades, fn necesidad -> necesidad.id end)

  describe "ordenar/1" do
    test "ordena de mayor a menor prioridad y, si empatan, la más antigua primero" do
      lista = [
        necesidad("N004", :baja),
        necesidad("N002", :critica),
        necesidad("N003", :media),
        necesidad("N001", :critica),
        necesidad("N005", :alta)
      ]

      assert ids(Prioridad.ordenar(lista)) == ["N001", "N002", "N005", "N003", "N004"]
    end

    test "una lista vacía o de un elemento" do
      assert Prioridad.ordenar([]) == []
      assert ids(Prioridad.ordenar([necesidad("N001", :media)])) == ["N001"]
    end
  end

  describe "mas_urgente/1" do
    test "elige la de mayor prioridad y, si empatan, la más antigua" do
      lista = [necesidad("N007", :alta), necesidad("N003", :critica), necesidad("N002", :critica)]

      assert {:ok, %Necesidad{id: "N002"}} = Prioridad.mas_urgente(lista)
      assert Prioridad.mas_urgente([]) == {:error, :sin_pendientes}
    end
  end
end
