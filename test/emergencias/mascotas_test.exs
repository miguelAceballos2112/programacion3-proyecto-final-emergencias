defmodule Emergencias.MascotasTest do
  # async: false: Mascotas y Zonas son procesos con nombre que comparten todas las
  # pruebas, así que no pueden correr al mismo tiempo que otras
  use ExUnit.Case

  alias Emergencias.Mascotas
  alias Emergencias.Zonas

  # Todas las pruebas comparten el mismo proceso Mascotas (lo inicia la aplicación).
  # match_pets mira TODOS los reportes activos, así que cada prueba usa una especie de
  # nombre único: una especie distinta descarta el par y las pruebas no se mezclan.
  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  defp crear_zona do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona de prueba", "critico")
    zona
  end

  # Un reporte con los mismos datos base; `cambios` cambia solo lo que cada prueba necesita
  defp reportar(tipo, especie, zona, cambios \\ []) do
    datos =
      Map.merge(
        %{
          nombre: "Firulais",
          color: "café",
          tamano: "mediano",
          contacto: "3001234567",
          caracteristicas: "collar rojo manchas blancas"
        },
        Map.new(cambios)
      )

    {:ok, reporte} =
      Mascotas.registrar(
        tipo,
        especie,
        datos.nombre,
        datos.color,
        datos.tamano,
        zona,
        datos.contacto,
        datos.caracteristicas
      )

    reporte
  end

  # Los pares de esta especie (match_pets devuelve los de todos)
  defp de_la_especie(pares, especie) do
    Enum.filter(pares, fn par -> par.perdida.especie == especie end)
  end

  defp estado_de(id) do
    {:ok, reporte} = Mascotas.obtener(id)
    reporte.estado
  end

  describe "registrar/8" do
    test "registra un reporte activo con código M" do
      zona = crear_zona()
      especie = unico("perro")

      assert {:ok, reporte} =
               Mascotas.registrar(
                 :perdida,
                 especie,
                 "Firulais",
                 "café",
                 :mediano,
                 zona,
                 "300",
                 "collar rojo"
               )

      assert reporte.id =~ ~r/^M\d{3,}$/
      assert reporte.tipo == :perdida
      assert reporte.estado == :activa
      assert reporte.pareja == nil
      assert Mascotas.obtener(reporte.id) == {:ok, reporte}
    end

    test "acepta el tipo y el tamaño como texto, y las características son opcionales" do
      zona = crear_zona()
      especie = unico("gato")

      assert {:ok, a} =
               Mascotas.registrar("encontrada", especie, "Michi", "negro", "pequeño", zona, "300")

      assert a.tipo == :encontrada
      assert a.tamano == :pequeno
      assert a.caracteristicas == ""
    end

    test "los códigos son consecutivos" do
      zona = crear_zona()
      primero = reportar(:perdida, unico("perro"), zona)
      segundo = reportar(:perdida, unico("perro"), zona)

      numero = fn reporte -> reporte.id |> String.trim_leading("M") |> String.to_integer() end
      assert numero.(segundo) == numero.(primero) + 1
    end

    test "rechaza datos inválidos y no deja rastro" do
      zona = crear_zona()
      especie = unico("perro")

      registrar = fn tipo, esp, nombre, color, tamano, z, contacto ->
        Mascotas.registrar(tipo, esp, nombre, color, tamano, z, contacto)
      end

      assert registrar.(:robada, especie, "A", "café", :mediano, zona, "3") ==
               {:error, :tipo_invalido}

      assert registrar.(:perdida, "", "A", "café", :mediano, zona, "3") ==
               {:error, :especie_invalida}

      assert registrar.(:perdida, especie, " ", "café", :mediano, zona, "3") ==
               {:error, :nombre_invalido}

      assert registrar.(:perdida, especie, "A", "", :mediano, zona, "3") ==
               {:error, :color_invalido}

      assert registrar.(:perdida, especie, "A", "café", :enorme, zona, "3") ==
               {:error, :tamano_invalido}

      assert registrar.(:perdida, especie, "A", "café", :mediano, "marte", "3") ==
               {:error, :zona_no_existe}

      assert registrar.(:perdida, especie, "A", "café", :mediano, "", "3") ==
               {:error, :zona_invalida}

      assert registrar.(:perdida, especie, "A", "café", :mediano, zona, "") ==
               {:error, :contacto_invalido}

      assert Mascotas.listar(especie: especie) == []
    end

    test "las características con punto y coma se guardan limpias" do
      zona = crear_zona()
      reporte = reportar(:perdida, unico("perro"), zona, caracteristicas: "collar; rojo")
      assert reporte.caracteristicas == "collar, rojo"
    end
  end

  describe "listar/1" do
    test "filtra por especie, zona, estado y tipo" do
      zona = crear_zona()
      otra_zona = crear_zona()
      especie = unico("perro")
      perdida = reportar(:perdida, especie, zona)
      encontrada = reportar(:encontrada, especie, otra_zona)

      assert Enum.map(Mascotas.listar(especie: especie), fn r -> r.id end) == [
               perdida.id,
               encontrada.id
             ]

      assert Enum.map(Mascotas.listar(especie: String.upcase(especie)), fn r -> r.id end) == [
               perdida.id,
               encontrada.id
             ]

      assert [%{id: id}] = Mascotas.listar(especie: especie, zona: otra_zona)
      assert id == encontrada.id
      assert [%{id: id}] = Mascotas.listar(especie: especie, tipo: :perdida)
      assert id == perdida.id
      assert length(Mascotas.listar(especie: especie, estado: "activa")) == 2
      assert Mascotas.listar(especie: especie, estado: :resuelta) == []
    end

    test "un filtro desconocido no devuelve nada" do
      zona = crear_zona()
      especie = unico("perro")
      reportar(:perdida, especie, zona)
      assert Mascotas.listar(especie: especie, color: "rojo") == []
    end

    test "un reporte que no existe devuelve error" do
      assert Mascotas.obtener("M999999") == {:error, :reporte_no_existe}
      assert Mascotas.obtener(nil) == {:error, :reporte_no_existe}
    end
  end

  describe "buscar_coincidencias/0 (match_pets)" do
    test "marca como posible coincidencia el par que llega al umbral" do
      zona = crear_zona()
      especie = unico("perro")
      perdida = reportar(:perdida, especie, zona)
      encontrada = reportar(:encontrada, especie, zona)

      assert {:ok, pares} = Mascotas.buscar_coincidencias()
      assert [par] = de_la_especie(pares, especie)
      assert par.puntaje == 100
      assert par.perdida.id == perdida.id
      assert par.encontrada.id == encontrada.id

      assert {:ok, %{estado: :posible_coincidencia, pareja: pareja_a}} =
               Mascotas.obtener(perdida.id)

      assert {:ok, %{estado: :posible_coincidencia, pareja: pareja_b}} =
               Mascotas.obtener(encontrada.id)

      assert pareja_a == encontrada.id
      assert pareja_b == perdida.id
    end

    test "una especie distinta o un puntaje bajo no se marcan" do
      zona = crear_zona()
      otra_zona = crear_zona()
      especie = unico("perro")

      distinta = reportar(:perdida, especie, zona)

      lejana =
        reportar(:encontrada, especie, otra_zona,
          color: "negro",
          tamano: "grande",
          caracteristicas: "orejas largas"
        )

      gato = reportar(:encontrada, unico("gato"), zona)

      assert {:ok, pares} = Mascotas.buscar_coincidencias()
      assert de_la_especie(pares, especie) == []
      assert estado_de(distinta.id) == :activa
      assert estado_de(lejana.id) == :activa
      assert estado_de(gato.id) == :activa
    end

    test "un reporte entra en un solo par: el de mayor puntaje" do
      zona = crear_zona()
      especie = unico("perro")
      mejor = reportar(:perdida, especie, zona)
      peor = reportar(:perdida, especie, zona, color: "negro")
      encontrada = reportar(:encontrada, especie, zona)

      assert {:ok, pares} = Mascotas.buscar_coincidencias()
      assert [par] = de_la_especie(pares, especie)
      assert par.perdida.id == mejor.id
      assert par.encontrada.id == encontrada.id

      assert estado_de(mejor.id) == :posible_coincidencia
      assert estado_de(peor.id) == :activa
    end

    test "un reporte que ya es posible coincidencia no se vuelve a emparejar" do
      zona = crear_zona()
      especie = unico("perro")
      reportar(:perdida, especie, zona)
      reportar(:encontrada, especie, zona)

      {:ok, primera} = Mascotas.buscar_coincidencias()
      {:ok, segunda} = Mascotas.buscar_coincidencias()
      assert length(de_la_especie(primera, especie)) == 1
      assert de_la_especie(segunda, especie) == []
    end
  end

  describe "rechazar/2 (reject_match)" do
    setup do
      zona = crear_zona()
      especie = unico("perro")
      perdida = reportar(:perdida, especie, zona)
      encontrada = reportar(:encontrada, especie, zona)
      {:ok, _pares} = Mascotas.buscar_coincidencias()
      %{zona: zona, especie: especie, perdida: perdida, encontrada: encontrada}
    end

    test "los dos reportes vuelven a activa y sin pareja", %{
      perdida: perdida,
      encontrada: encontrada
    } do
      assert {:ok, %{perdida: a, encontrada: b}} = Mascotas.rechazar(perdida.id, encontrada.id)
      assert a.estado == :activa and a.pareja == nil
      assert b.estado == :activa and b.pareja == nil
      assert estado_de(perdida.id) == :activa
      assert estado_de(encontrada.id) == :activa
    end

    test "rechazar dos veces responde que ya no son pareja", %{
      perdida: perdida,
      encontrada: encontrada
    } do
      {:ok, _} = Mascotas.rechazar(perdida.id, encontrada.id)
      assert Mascotas.rechazar(perdida.id, encontrada.id) == {:error, :no_son_pareja}
    end

    test "dos reportes que no son pareja no se pueden rechazar", %{
      zona: zona,
      especie: especie,
      perdida: perdida
    } do
      ajena = reportar(:encontrada, especie, zona)
      assert Mascotas.rechazar(perdida.id, ajena.id) == {:error, :no_son_pareja}
      assert estado_de(perdida.id) == :posible_coincidencia
    end

    test "errores: reporte inexistente y tipos al revés", %{
      perdida: perdida,
      encontrada: encontrada
    } do
      assert Mascotas.rechazar("M999999", encontrada.id) == {:error, :reporte_no_existe}
      assert Mascotas.rechazar(perdida.id, "M999999") == {:error, :reporte_no_existe}
      assert Mascotas.rechazar(encontrada.id, perdida.id) == {:error, :tipo_invalido}
    end
  end

  describe "confirmar/2 (confirm_match)" do
    setup do
      zona = crear_zona()
      especie = unico("perro")
      perdida = reportar(:perdida, especie, zona)
      encontrada = reportar(:encontrada, especie, zona)
      %{zona: zona, especie: especie, perdida: perdida, encontrada: encontrada}
    end

    test "cierra los dos reportes de un par propuesto", %{
      perdida: perdida,
      encontrada: encontrada
    } do
      {:ok, _pares} = Mascotas.buscar_coincidencias()

      assert {:ok, %{perdida: a, encontrada: b}} = Mascotas.confirmar(perdida.id, encontrada.id)
      assert a.estado == :resuelta and a.pareja == encontrada.id
      assert b.estado == :resuelta and b.pareja == perdida.id
      assert estado_de(perdida.id) == :resuelta
      assert estado_de(encontrada.id) == :resuelta
    end

    test "también se puede confirmar sin haber corrido match_pets", %{
      perdida: perdida,
      encontrada: encontrada
    } do
      assert {:ok, _} = Mascotas.confirmar(perdida.id, encontrada.id)
      assert estado_de(perdida.id) == :resuelta
    end

    test "una segunda confirmación responde ya_resuelto", %{
      perdida: perdida,
      encontrada: encontrada
    } do
      {:ok, _} = Mascotas.confirmar(perdida.id, encontrada.id)
      assert Mascotas.confirmar(perdida.id, encontrada.id) == {:error, :ya_resuelto}
    end

    test "un reporte resuelto no se puede confirmar ni rechazar con otro", %{
      zona: zona,
      especie: especie,
      perdida: perdida,
      encontrada: encontrada
    } do
      otra = reportar(:encontrada, especie, zona)
      {:ok, _} = Mascotas.confirmar(perdida.id, encontrada.id)

      assert Mascotas.confirmar(perdida.id, otra.id) == {:error, :ya_resuelto}
      assert Mascotas.rechazar(perdida.id, encontrada.id) == {:error, :ya_resuelto}
      assert estado_de(otra.id) == :activa
    end

    test "no se confirma un reporte propuesto con otro", %{
      zona: zona,
      especie: especie,
      perdida: perdida,
      encontrada: encontrada
    } do
      {:ok, _pares} = Mascotas.buscar_coincidencias()
      intrusa = reportar(:encontrada, especie, zona)

      assert Mascotas.confirmar(perdida.id, intrusa.id) == {:error, :no_son_pareja}
      assert estado_de(perdida.id) == :posible_coincidencia
      assert estado_de(encontrada.id) == :posible_coincidencia
      assert estado_de(intrusa.id) == :activa
    end

    test "errores: reporte inexistente y tipos al revés", %{
      perdida: perdida,
      encontrada: encontrada
    } do
      assert Mascotas.confirmar("M999999", encontrada.id) == {:error, :reporte_no_existe}
      assert Mascotas.confirmar(encontrada.id, perdida.id) == {:error, :tipo_invalido}
      assert Mascotas.confirmar(perdida.id, perdida.id) == {:error, :tipo_invalido}
    end

    test "el código se acepta en minúscula", %{perdida: perdida, encontrada: encontrada} do
      assert {:ok, _} =
               Mascotas.confirmar(String.downcase(perdida.id), String.downcase(encontrada.id))
    end
  end

  describe "zona_de/1" do
    test "devuelve la zona del reporte" do
      zona = crear_zona()
      reporte = reportar(:perdida, unico("perro"), zona)
      assert Mascotas.zona_de(reporte.id) == {:ok, zona}
      assert Mascotas.zona_de("M999999") == {:error, :reporte_no_existe}
    end
  end

  describe "funciones recursivas" do
    test "elegir_pares se queda con el primer par de cada reporte" do
      candidatos = [
        %{perdida: %{id: "M1"}, encontrada: %{id: "M3"}, puntaje: 100},
        %{perdida: %{id: "M2"}, encontrada: %{id: "M3"}, puntaje: 90},
        %{perdida: %{id: "M1"}, encontrada: %{id: "M4"}, puntaje: 80},
        %{perdida: %{id: "M2"}, encontrada: %{id: "M4"}, puntaje: 70}
      ]

      pares = Mascotas.elegir_pares(candidatos, MapSet.new())

      assert Enum.map(pares, fn par -> {par.perdida.id, par.encontrada.id} end) == [
               {"M1", "M3"},
               {"M2", "M4"}
             ]

      assert Mascotas.elegir_pares([], MapSet.new()) == []
    end

    test "filtrar sobre una lista armada a mano" do
      reportes = [
        %{especie: "Perro", zona: "a", estado: :activa, tipo: :perdida},
        %{especie: "gato", zona: "a", estado: :resuelta, tipo: :encontrada},
        %{especie: "perro", zona: "b", estado: :activa, tipo: :encontrada}
      ]

      assert length(Mascotas.filtrar(reportes, especie: "perro")) == 2
      assert length(Mascotas.filtrar(reportes, especie: "perro", zona: "b")) == 1
      assert length(Mascotas.filtrar(reportes, [])) == 3
    end
  end

  describe "persistencia y tolerancia a fallos" do
    test "si el servidor falla, el supervisor lo reinicia y recupera los reportes" do
      zona = crear_zona()
      especie = unico("perro")
      perdida = reportar(:perdida, especie, zona)
      encontrada = reportar(:encontrada, especie, zona)
      {:ok, _pares} = Mascotas.buscar_coincidencias()
      anterior = Process.whereis(Mascotas)

      Process.exit(anterior, :kill)
      esperar_reinicio(Mascotas, anterior)

      assert {:ok, %{estado: :posible_coincidencia, pareja: pareja}} =
               Mascotas.obtener(perdida.id)

      assert pareja == encontrada.id
      assert {:ok, _} = Mascotas.confirmar(perdida.id, encontrada.id)
    end

    test "después de reiniciar, los códigos continúan y no se repiten" do
      zona = crear_zona()
      antes = reportar(:perdida, unico("perro"), zona)
      anterior = Process.whereis(Mascotas)

      Process.exit(anterior, :kill)
      esperar_reinicio(Mascotas, anterior)

      despues = reportar(:perdida, unico("perro"), zona)
      assert despues.id != antes.id
    end
  end

  describe "concurrencia" do
    test "dos confirmaciones simultáneas del mismo par: solo una se acepta" do
      zona = crear_zona()
      especie = unico("perro")
      perdida = reportar(:perdida, especie, zona)
      encontrada = reportar(:encontrada, especie, zona)

      resultados =
        1..2
        |> Enum.map(fn _n ->
          Task.async(fn -> Mascotas.confirmar(perdida.id, encontrada.id) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, fn r -> match?({:ok, _}, r) end) == 1
      assert Enum.count(resultados, fn r -> r == {:error, :ya_resuelto} end) == 1
    end

    test "diez dueños reclaman a la vez la misma mascota encontrada: solo uno la recibe" do
      zona = crear_zona()
      especie = unico("perro")
      encontrada = reportar(:encontrada, especie, zona)
      perdidas = Enum.map(1..10, fn _n -> reportar(:perdida, especie, zona) end)

      resultados =
        perdidas
        |> Enum.map(fn perdida ->
          Task.async(fn -> Mascotas.confirmar(perdida.id, encontrada.id) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, fn r -> match?({:ok, _}, r) end) == 1
      assert Enum.count(resultados, fn r -> r == {:error, :ya_resuelto} end) == 9

      # Los otros nueve reportes siguen activos y la encontrada quedó con un solo dueño
      assert length(Mascotas.listar(especie: especie, estado: :resuelta)) == 2
      assert length(Mascotas.listar(especie: especie, estado: :activa)) == 9
    end

    test "veinte reportes simultáneos reciben códigos únicos" do
      zona = crear_zona()

      ids =
        1..20
        |> Enum.map(fn _n -> Task.async(fn -> reportar(:perdida, unico("perro"), zona) end) end)
        |> Enum.map(&Task.await/1)
        |> Enum.map(fn reporte -> reporte.id end)

      assert length(Enum.uniq(ids)) == 20
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
