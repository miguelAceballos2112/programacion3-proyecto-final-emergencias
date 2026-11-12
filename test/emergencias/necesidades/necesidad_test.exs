defmodule Emergencias.Necesidades.NecesidadTest do
  use ExUnit.Case, async: true

  alias Emergencias.Necesidades.Necesidad

  defp nueva(tipo, cantidad) do
    Necesidad.crear("N001", tipo, cantidad, :alta, "centro", "Prueba", "laura", {:zona, "centro"})
  end

  describe "cambiar_estado/2" do
    test "sigue las transiciones válidas" do
      necesidad = nueva(:rescate, 1)

      assert {:ok, en_atencion} = Necesidad.cambiar_estado(necesidad, :en_atencion)
      assert {:ok, atendida} = Necesidad.cambiar_estado(en_atencion, :atendida)
      assert atendida.estado == :atendida
      assert Necesidad.cambiar_estado(necesidad, :atendida) == {:error, :transicion_invalida}
      assert Necesidad.cambiar_estado(atendida, :cancelada) == {:error, :necesidad_cerrada}
    end
  end

  describe "asignaciones" do
    test "la primera asignación la pasa a asignada y nunca se supera lo requerido" do
      necesidad = Necesidad.registrar_asignacion(nueva(:agua, 30), 10)

      assert necesidad.estado == :asignada
      assert Necesidad.faltante(necesidad) == 20
      assert Necesidad.validar_asignacion(necesidad, 20) == :ok
      assert Necesidad.validar_asignacion(necesidad, 21) == {:error, :excede_lo_requerido}
    end

    test "solo devuelve lo reservado si se cancela antes de estar en atención" do
      necesidad = nueva(:agua, 30)
      {:ok, en_atencion} = Necesidad.cambiar_estado(necesidad, :en_atencion)

      assert Necesidad.devuelve_al_cancelar?(necesidad)
      assert Necesidad.devuelve_al_cancelar?(Necesidad.registrar_asignacion(necesidad, 5))
      refute Necesidad.devuelve_al_cancelar?(en_atencion)
    end
  end

  describe "a_fila/1 y desde_fila/1" do
    test "la fila del archivo conserva todos los campos, también el destino" do
      necesidad = %{nueva(:alimentos, 40) | destino: {:albergue, "A01"}, asignado: 10}

      assert Necesidad.desde_fila(Necesidad.a_fila(necesidad)) == necesidad
    end
  end
end
