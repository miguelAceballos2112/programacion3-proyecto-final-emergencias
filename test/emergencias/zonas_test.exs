defmodule Emergencias.ZonasTest do
  use ExUnit.Case

  alias Emergencias.Zonas

  # Cada prueba trabaja con una zona de código único, porque todas comparten el
  # mismo proceso Zonas (lo inicia la aplicación)
  setup do
    {:ok, codigo: "zona#{System.unique_integer([:positive])}"}
  end

  describe "registrar_zona/4" do
    test "registra una zona con su nivel y sus personas afectadas", %{codigo: codigo} do
      assert {:ok, zona} = Zonas.registrar_zona(codigo, "Centro", "critico", 120)
      assert zona.nivel == :critico
      assert zona.personas_afectadas == 120
      assert Zonas.existe?(codigo)
    end

    test "acepta el nivel con tilde y en mayúsculas", %{codigo: codigo} do
      assert {:ok, zona} = Zonas.registrar_zona(codigo, "Centro", "CRÍTICO")
      assert zona.nivel == :critico
    end

    test "no permite repetir el código", %{codigo: codigo} do
      {:ok, _} = Zonas.registrar_zona(codigo, "Centro", "alto")
      assert Zonas.registrar_zona(codigo, "Otra", "bajo") == {:error, :ya_existe}
    end

    test "rechaza datos inválidos", %{codigo: codigo} do
      assert Zonas.registrar_zona("", "Centro", "alto") == {:error, :codigo_invalido}
      assert Zonas.registrar_zona(codigo, "", "alto") == {:error, :nombre_invalido}
      assert Zonas.registrar_zona(codigo, "Centro", "extremo") == {:error, :nivel_invalido}
      assert Zonas.registrar_zona(codigo, "Centro", "alto", -1) == {:error, :personas_invalidas}
      assert Zonas.registrar_zona(codigo, "Centro", "alto", "10") == {:error, :personas_invalidas}
      refute Zonas.existe?(codigo)
    end
  end

  describe "sectores y puntos de atención" do
    test "registra un sector y un punto dentro de una zona", %{codigo: codigo} do
      {:ok, _} = Zonas.registrar_zona(codigo, "Centro", "alto")
      assert {:ok, sector} = Zonas.registrar_sector(codigo, "s1", "Sector 1", "critico", 50)
      assert sector.nivel == :critico
      assert {:ok, punto} = Zonas.registrar_punto(codigo, "s1", "p1", "Punto 1", 10)
      assert punto.personas_afectadas == 10

      {:ok, zona} = Zonas.obtener(codigo)
      assert [%{codigo: "s1", puntos: [%{codigo: "p1"}]}] = zona.sectores
    end

    test "un sector necesita una zona existente", %{codigo: codigo} do
      assert Zonas.registrar_sector(codigo, "s1", "Sector 1", "alto") == {:error, :zona_no_existe}
    end

    test "un punto necesita un sector existente", %{codigo: codigo} do
      {:ok, _} = Zonas.registrar_zona(codigo, "Centro", "alto")

      assert Zonas.registrar_punto(codigo, "s1", "p1", "Punto 1") == {:error, :sector_no_existe}
    end

    test "no permite repetir el código de un sector ni de un punto", %{codigo: codigo} do
      {:ok, _} = Zonas.registrar_zona(codigo, "Centro", "alto")
      {:ok, _} = Zonas.registrar_sector(codigo, "s1", "Sector 1", "alto")
      {:ok, _} = Zonas.registrar_punto(codigo, "s1", "p1", "Punto 1")

      assert Zonas.registrar_sector(codigo, "s1", "Otro", "bajo") == {:error, :ya_existe}
      assert Zonas.registrar_punto(codigo, "s1", "p1", "Otro") == {:error, :ya_existe}
    end

    test "el mismo código de sector se puede usar en zonas distintas", %{codigo: codigo} do
      otra = codigo <> "b"
      {:ok, _} = Zonas.registrar_zona(codigo, "Una", "alto")
      {:ok, _} = Zonas.registrar_zona(otra, "Otra", "alto")

      assert {:ok, _} = Zonas.registrar_sector(codigo, "s1", "Sector", "alto")
      assert {:ok, _} = Zonas.registrar_sector(otra, "s1", "Sector", "alto")
    end
  end

  describe "consultas" do
    test "obtener una zona que no existe devuelve un error", %{codigo: codigo} do
      assert Zonas.obtener(codigo) == {:error, :zona_no_existe}
      refute Zonas.existe?(codigo)
    end

    test "estado devuelve la zona con sus estadísticas acumuladas", %{codigo: codigo} do
      {:ok, _} = Zonas.registrar_zona(codigo, "Centro", "critico", 100)
      {:ok, _} = Zonas.registrar_sector(codigo, "s1", "Sector 1", "alto", 50)
      {:ok, _} = Zonas.registrar_punto(codigo, "s1", "p1", "Punto 1", 10)

      assert {:ok, %{zona: zona, estadisticas: estadisticas}} = Zonas.estado(codigo)
      assert zona.codigo == codigo
      assert estadisticas.personas_afectadas == 160
      assert estadisticas.sectores == 1
      assert estadisticas.puntos_atencion == 1
    end

    test "estado de una zona que no existe devuelve un error", %{codigo: codigo} do
      assert Zonas.estado(codigo) == {:error, :zona_no_existe}
    end

    test "listar devuelve las zonas ordenadas por código", %{codigo: codigo} do
      {:ok, _} = Zonas.registrar_zona(codigo <> "b", "B", "bajo")
      {:ok, _} = Zonas.registrar_zona(codigo <> "a", "A", "bajo")

      codigos = Zonas.listar() |> Enum.map(fn zona -> zona.codigo end)

      assert Enum.find_index(codigos, &(&1 == codigo <> "a")) <
               Enum.find_index(codigos, &(&1 == codigo <> "b"))
    end
  end

  describe "persistencia y tolerancia a fallos" do
    test "si el servidor falla, el supervisor lo reinicia y recupera la jerarquía", %{
      codigo: codigo
    } do
      {:ok, _} = Zonas.registrar_zona(codigo, "Centro", "critico", 100)
      {:ok, _} = Zonas.registrar_sector(codigo, "s1", "Sector 1", "alto", 50)
      {:ok, _} = Zonas.registrar_punto(codigo, "s1", "p1", "Punto 1", 10)
      pid_anterior = Process.whereis(Zonas)

      Process.exit(pid_anterior, :kill)
      esperar_reinicio(Zonas, pid_anterior)

      assert {:ok, %{estadisticas: estadisticas}} = Zonas.estado(codigo)
      assert estadisticas.personas_afectadas == 160
      assert estadisticas.puntos_atencion == 1
    end
  end

  # Espera, consultando cada 10 ms, a que el supervisor inicie un proceso nuevo
  defp esperar_reinicio(nombre, pid_anterior, intentos \\ 100)
  defp esperar_reinicio(_nombre, _pid_anterior, 0), do: flunk("El servidor no se reinició")

  defp esperar_reinicio(nombre, pid_anterior, intentos) do
    case Process.whereis(nombre) do
      nil -> reintentar(nombre, pid_anterior, intentos)
      ^pid_anterior -> reintentar(nombre, pid_anterior, intentos)
      _nuevo -> :ok
    end
  end

  defp reintentar(nombre, pid_anterior, intentos) do
    :timer.sleep(10)
    esperar_reinicio(nombre, pid_anterior, intentos - 1)
  end
end
