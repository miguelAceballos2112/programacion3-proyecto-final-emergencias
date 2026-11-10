defmodule Emergencias.PersistenciaTest do
  use ExUnit.Case

  alias Emergencias.Persistencia

  # Cada prueba usa un archivo distinto, para que no interfieran entre sí
  setup do
    {:ok, archivo: "prueba_#{System.unique_integer([:positive])}.txt"}
  end

  test "guardar y cargar devuelven las mismas líneas", %{archivo: archivo} do
    assert Persistencia.guardar(archivo, ["a;1", "b;2"]) == :ok
    assert Persistencia.cargar(archivo) == ["a;1", "b;2"]
  end

  test "guardar reemplaza el contenido anterior", %{archivo: archivo} do
    Persistencia.guardar(archivo, ["viejo"])
    Persistencia.guardar(archivo, ["nuevo"])
    assert Persistencia.cargar(archivo) == ["nuevo"]
  end

  test "agregar escribe al final sin borrar lo anterior", %{archivo: archivo} do
    Persistencia.agregar(archivo, "primera")
    Persistencia.agregar(archivo, "segunda")
    assert Persistencia.cargar(archivo) == ["primera", "segunda"]
  end

  test "cargar un archivo que no existe devuelve una lista vacía" do
    assert Persistencia.cargar("no_existe_#{System.unique_integer([:positive])}.txt") == []
  end

  test "cargar ignora las líneas en blanco", %{archivo: archivo} do
    File.mkdir_p!(Path.dirname(Persistencia.ruta(archivo)))
    File.write!(Persistencia.ruta(archivo), "a\n\n   \nb\n")
    assert Persistencia.cargar(archivo) == ["a", "b"]
  end

  test "conserva las tildes y la ñ", %{archivo: archivo} do
    Persistencia.guardar(archivo, ["Punto de atención;niña"])
    assert Persistencia.cargar(archivo) == ["Punto de atención;niña"]
  end

  test "unir y separar son operaciones inversas" do
    assert Persistencia.unir(["a", "b", "c"]) == "a;b;c"
    assert Persistencia.separar("a;b;c") == ["a", "b", "c"]
  end

  test "limpiar quita el separador y los saltos de línea" do
    assert Persistencia.limpiar("hola;\nmundo") == "hola, mundo"
  end
end
