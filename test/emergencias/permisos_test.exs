defmodule Emergencias.PermisosTest do
  use ExUnit.Case

  alias Emergencias.Permisos

  test "todos los tipos pueden registrar una necesidad" do
    for tipo <- [:ciudadano, :voluntario, :coordinador, :administrador] do
      assert Permisos.permitido?(tipo, :register_need)
    end
  end

  test "solo coordinadores y administradores asignan recursos" do
    assert Permisos.permitido?(:coordinador, :assign_resource)
    assert Permisos.permitido?(:administrador, :assign_resource)
    refute Permisos.permitido?(:voluntario, :assign_resource)
    refute Permisos.permitido?(:ciudadano, :assign_resource)
  end

  test "los voluntarios pueden registrar recursos, pero los ciudadanos no" do
    assert Permisos.permitido?(:voluntario, :register_resource)
    refute Permisos.permitido?(:ciudadano, :register_resource)
  end

  test "una acción desconocida no está permitida para nadie" do
    refute Permisos.permitido?(:administrador, :borrar_todo)
  end

  test "un tipo desconocido no tiene permisos" do
    refute Permisos.permitido?(:visitante, :register_need)
  end
end
