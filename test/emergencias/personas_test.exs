defmodule Emergencias.PersonasTest do
  # async: false: Personas y Zonas son procesos con nombre que comparten todas las
  # pruebas, así que no pueden correr al mismo tiempo que otras
  use ExUnit.Case

  alias Emergencias.Personas
  alias Emergencias.Zonas

  # Todas las pruebas comparten el mismo proceso Personas (lo inicia la aplicación),
  # por eso cada una trabaja con zona y documentos de código único
  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  defp crear_zona do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona de prueba", "critico")
    zona
  end

  defp crear_persona(zona, estado \\ "reportada") do
    documento = unico("doc")
    {:ok, _persona} = Personas.registrar(documento, "Persona de prueba", zona, estado)
    documento
  end

  defp codigos(personas), do: Enum.map(personas, fn persona -> persona.documento end)

  describe "registrar/5" do
    test "registra una persona con código P y estado por defecto sin_informacion" do
      zona = crear_zona()
      documento = unico("doc")

      assert {:ok, persona} = Personas.registrar(documento, "Ana", zona)
      assert persona.id =~ ~r/^P\d{3,}$/
      assert persona.estado == :sin_informacion
      assert persona.edad == 0
      assert persona.familia == nil
      assert Personas.obtener(documento) == {:ok, persona}
      assert Personas.existe?(documento)
    end

    test "acepta el estado como texto o como átomo y la edad" do
      zona = crear_zona()
      assert {:ok, a} = Personas.registrar(unico("doc"), "Ana", zona, "Localizada", 40)
      assert a.estado == :localizada
      assert a.edad == 40
      assert {:ok, b} = Personas.registrar(unico("doc"), "Luis", zona, :trasladada)
      assert b.estado == :trasladada
    end

    test "los códigos son consecutivos" do
      zona = crear_zona()
      {:ok, primera} = Personas.registrar(unico("doc"), "Ana", zona)
      {:ok, segunda} = Personas.registrar(unico("doc"), "Luis", zona)

      numero = fn persona -> persona.id |> String.trim_leading("P") |> String.to_integer() end
      assert numero.(segunda) == numero.(primera) + 1
    end

    test "no permite repetir el documento" do
      zona = crear_zona()
      documento = crear_persona(zona)
      assert Personas.registrar(documento, "Otra", zona) == {:error, :ya_existe}
    end

    test "rechaza una zona que no existe" do
      assert Personas.registrar(unico("doc"), "Ana", "marte") == {:error, :zona_no_existe}
    end

    test "no acepta en_albergue ni reunificada como estado inicial" do
      zona = crear_zona()

      assert Personas.registrar(unico("doc"), "Ana", zona, "en_albergue") ==
               {:error, :estado_inicial_invalido}

      assert Personas.registrar(unico("doc"), "Ana", zona, :reunificada) ==
               {:error, :estado_inicial_invalido}

      assert Personas.registrar(unico("doc"), "Ana", zona, "volando") ==
               {:error, :estado_invalido}
    end

    test "valida las entradas y no deja rastro si algo falla" do
      zona = crear_zona()

      assert Personas.registrar("", "Ana", zona) == {:error, :documento_invalido}
      assert Personas.registrar("a b", "Ana", zona) == {:error, :documento_invalido}
      assert Personas.registrar(unico("doc"), "   ", zona) == {:error, :nombre_invalido}
      assert Personas.registrar(unico("doc"), "Ana", "") == {:error, :zona_invalida}

      assert Personas.registrar(unico("doc"), "Ana", zona, :reportada, -5) ==
               {:error, :edad_invalida}

      assert Personas.registrar(unico("doc"), "Ana", zona, :reportada, "10") ==
               {:error, :edad_invalida}

      assert Personas.buscar(zona: zona) == []
    end
  end

  describe "cambios de estado" do
    test "una transición válida se aplica y queda en el historial" do
      zona = crear_zona()
      documento = crear_persona(zona)

      assert {:ok, %{estado: :localizada}} =
               Personas.actualizar_estado(documento, "localizada", "La vio un voluntario")

      assert {:ok, [primera, segunda]} = Personas.historial(documento)
      assert primera.anterior == nil
      assert primera.nuevo == :reportada
      assert segunda.anterior == :reportada
      assert segunda.nuevo == :localizada
      assert segunda.detalle == "La vio un voluntario"
    end

    test "una transición que no está en la tabla se rechaza y no cambia nada" do
      zona = crear_zona()
      documento = crear_persona(zona)

      assert Personas.actualizar_estado(documento, :sin_informacion) ==
               {:error, :transicion_invalida}

      assert {:ok, %{estado: :reportada}} = Personas.obtener(documento)
      assert {:ok, [_solo_el_reporte]} = Personas.historial(documento)
    end

    test "reunificada es terminal: no se puede cerrar dos veces" do
      zona = crear_zona()
      documento = crear_persona(zona)

      assert {:ok, _} = Personas.actualizar_estado(documento, :reunificada)
      assert Personas.actualizar_estado(documento, :localizada) == {:error, :transicion_invalida}
      assert Personas.actualizar_estado(documento, :reunificada) == {:error, :transicion_invalida}
    end

    test "update_person_status rechaza en_albergue como destino y como origen" do
      zona = crear_zona()
      documento = crear_persona(zona)

      assert Personas.actualizar_estado(documento, :en_albergue) == {:error, :usar_albergue}

      assert {:ok, %{estado: :en_albergue}} =
               Personas.cambiar_estado(documento, :en_albergue, "Ingreso")

      assert Personas.actualizar_estado(documento, :trasladada) == {:error, :usar_albergue}

      assert {:ok, %{estado: :trasladada}} =
               Personas.cambiar_estado(documento, :trasladada, "Salida")
    end

    test "una persona inexistente o un estado inválido devuelven error" do
      zona = crear_zona()
      documento = crear_persona(zona)

      assert Personas.actualizar_estado("no_existe", :localizada) == {:error, :persona_no_existe}
      assert Personas.historial("no_existe") == {:error, :persona_no_existe}
      assert Personas.actualizar_estado(documento, "volando") == {:error, :estado_invalido}
    end

    test "el detalle con punto y coma se limpia para no dañar el archivo" do
      zona = crear_zona()
      documento = crear_persona(zona)

      {:ok, _} = Personas.actualizar_estado(documento, :localizada, "visto; en el parque")
      {:ok, historial} = Personas.historial(documento)
      assert List.last(historial).detalle == "visto, en el parque"
    end
  end

  describe "buscar/1" do
    setup do
      zona = crear_zona()
      {:ok, ana} = Personas.registrar(unico("doc"), "Ana María", zona, :localizada)
      {:ok, luis} = Personas.registrar(unico("doc"), "Luis", zona, :reportada)
      {:ok, maria} = Personas.registrar(unico("doc"), "María José", zona, :localizada)
      %{zona: zona, ana: ana, luis: luis, maria: maria}
    end

    test "por zona devuelve las de esa zona, ordenadas por código", %{zona: zona} = datos do
      assert codigos(Personas.buscar(zona: zona)) ==
               [datos.ana.documento, datos.luis.documento, datos.maria.documento]
    end

    test "por documento", %{zona: zona, luis: luis} do
      assert [%{nombre: "Luis"}] = Personas.buscar(documento: luis.documento, zona: zona)
    end

    test "por nombre, sin distinguir mayúsculas y por fragmento", %{zona: zona} do
      nombres = Personas.buscar(nombre: "MARÍA", zona: zona) |> Enum.map(fn p -> p.nombre end)
      assert nombres == ["Ana María", "María José"]
    end

    test "por estado y zona combinados, con el estado como texto o átomo", %{zona: zona} do
      assert length(Personas.buscar(zona: zona, estado: :localizada)) == 2
      assert length(Personas.buscar(zona: zona, estado: "reportada")) == 1
    end

    test "un filtro desconocido no devuelve nada", %{zona: zona} do
      assert Personas.buscar(zona: zona, color: "rojo") == []
    end
  end

  describe "familias" do
    test "se registra con código F y se pueden agregar miembros" do
      zona = crear_zona()
      uno = crear_persona(zona)
      dos = crear_persona(zona)

      assert {:ok, familia} = Personas.registrar_familia("Familia Gómez", zona)
      assert familia.codigo =~ ~r/^F\d{3,}$/
      assert Personas.existe_familia?(familia.codigo)
      refute Personas.existe_familia?("F-no-existe")

      assert {:ok, _} = Personas.agregar_miembro(familia.codigo, uno)
      assert {:ok, con_dos} = Personas.agregar_miembro(familia.codigo, dos)
      assert MapSet.equal?(con_dos.miembros, MapSet.new([uno, dos]))
      assert {:ok, %{familia: codigo}} = Personas.obtener(uno)
      assert codigo == familia.codigo
    end

    test "una persona no puede estar en dos familias" do
      zona = crear_zona()
      documento = crear_persona(zona)
      {:ok, primera} = Personas.registrar_familia("Primera", zona)
      {:ok, segunda} = Personas.registrar_familia("Segunda", zona)

      {:ok, _} = Personas.agregar_miembro(primera.codigo, documento)
      assert Personas.agregar_miembro(segunda.codigo, documento) == {:error, :ya_tiene_familia}
      assert Personas.agregar_miembro(primera.codigo, documento) == {:error, :ya_tiene_familia}
    end

    test "errores: familia o persona inexistente, zona inexistente, nombre vacío" do
      zona = crear_zona()
      documento = crear_persona(zona)
      {:ok, familia} = Personas.registrar_familia("Familia", zona)

      assert Personas.agregar_miembro("F-no", documento) == {:error, :familia_no_existe}
      assert Personas.agregar_miembro(familia.codigo, "no_existe") == {:error, :persona_no_existe}
      assert Personas.registrar_familia("Familia", "marte") == {:error, :zona_no_existe}
      assert Personas.registrar_familia("  ", zona) == {:error, :nombre_invalido}
    end

    test "el código de la familia se acepta en minúscula" do
      zona = crear_zona()
      {:ok, familia} = Personas.registrar_familia("Familia", zona)
      assert Personas.existe_familia?(String.downcase(familia.codigo))
    end

    test "zona_de y zona_de_familia sirven para la regla de zona del coordinador" do
      zona = crear_zona()
      documento = crear_persona(zona)
      {:ok, familia} = Personas.registrar_familia("Familia", zona)

      assert Personas.zona_de(documento) == {:ok, zona}
      assert Personas.zona_de_familia(familia.codigo) == {:ok, zona}
      assert Personas.zona_de("no_existe") == {:error, :persona_no_existe}
      assert Personas.zona_de_familia("F-no") == {:error, :familia_no_existe}
    end
  end

  describe "mensajes" do
    setup do
      zona = crear_zona()
      andres = crear_persona(zona, "localizada")
      marta = crear_persona(zona, "localizada")
      {:ok, familia} = Personas.registrar_familia("Familia Gómez", zona)
      {:ok, _} = Personas.agregar_miembro(familia.codigo, andres)
      {:ok, _} = Personas.agregar_miembro(familia.codigo, marta)
      %{zona: zona, andres: andres, marta: marta, familia: familia.codigo}
    end

    test "un mensaje a una persona queda pendiente", %{andres: andres} do
      assert {:ok, mensaje} = Personas.enviar_mensaje("laura", {:persona, andres}, "Estoy bien")
      assert mensaje.id =~ ~r/^MSG\d{3,}$/
      assert mensaje.estado == :pendiente
      assert mensaje.destino_tipo == :persona
      assert mensaje.destino_id == andres
    end

    test "el destinatario debe existir y el contenido no puede estar vacío", %{andres: andres} do
      assert Personas.enviar_mensaje("laura", {:persona, "no_existe"}, "Hola") ==
               {:error, :persona_no_existe}

      assert Personas.enviar_mensaje("laura", {:familia, "F-no"}, "Hola") ==
               {:error, :familia_no_existe}

      assert Personas.enviar_mensaje("laura", {:mascota, "1"}, "Hola") ==
               {:error, :destino_invalido}

      assert Personas.enviar_mensaje("laura", {:persona, andres}, "  ") ==
               {:error, :contenido_invalido}

      assert Personas.enviar_mensaje("", {:persona, andres}, "Hola") ==
               {:error, :remitente_invalido}
    end

    test "el mensaje a la familia lo ven todos sus miembros", %{
      andres: andres,
      marta: marta,
      familia: familia
    } do
      {:ok, _} =
        Personas.enviar_mensaje("laura", {:familia, familia}, "Estamos en el albergue norte")

      {:ok, _} = Personas.enviar_mensaje("pedro", {:persona, andres}, "Hijo, llámame")

      {:ok, de_andres} = Personas.listar_mensajes({:persona, andres})
      {:ok, de_marta} = Personas.listar_mensajes({:persona, marta})
      {:ok, de_familia} = Personas.listar_mensajes({:familia, familia})

      assert Enum.map(de_andres, fn m -> m.contenido end) == [
               "Estamos en el albergue norte",
               "Hijo, llámame"
             ]

      assert Enum.map(de_marta, fn m -> m.contenido end) == ["Estamos en el albergue norte"]
      assert Enum.map(de_familia, fn m -> m.contenido end) == ["Estamos en el albergue norte"]
    end

    test "una persona sin familia solo ve sus mensajes", %{zona: zona} do
      sola = crear_persona(zona)
      {:ok, _} = Personas.enviar_mensaje("laura", {:persona, sola}, "Hola")
      assert {:ok, [%{contenido: "Hola"}]} = Personas.listar_mensajes({:persona, sola})
    end

    test "mark_message alterna entre entregado y pendiente", %{andres: andres} do
      {:ok, mensaje} = Personas.enviar_mensaje("laura", {:persona, andres}, "Hola")

      assert {:ok, %{estado: :entregado}} = Personas.marcar_mensaje(mensaje.id, "entregado")
      assert Personas.marcar_mensaje(mensaje.id, :entregado) == {:error, :transicion_invalida}
      assert {:ok, %{estado: :pendiente}} = Personas.marcar_mensaje(mensaje.id, :pendiente)
      assert Personas.marcar_mensaje("MSG999999", :entregado) == {:error, :mensaje_no_existe}
      assert Personas.marcar_mensaje(mensaje.id, "leido") == {:error, :estado_invalido}
    end

    test "el contenido con punto y coma se guarda limpio", %{andres: andres} do
      {:ok, mensaje} =
        Personas.enviar_mensaje("laura", {:persona, andres}, "Agua; comida y mantas")

      assert mensaje.contenido == "Agua, comida y mantas"
    end

    test "zona_de_mensaje devuelve la zona del destinatario", %{
      zona: zona,
      andres: andres,
      familia: familia
    } do
      {:ok, a_persona} = Personas.enviar_mensaje("laura", {:persona, andres}, "Hola")
      {:ok, a_familia} = Personas.enviar_mensaje("laura", {:familia, familia}, "Hola")

      assert Personas.zona_de_mensaje(a_persona.id) == {:ok, zona}
      assert Personas.zona_de_mensaje(a_familia.id) == {:ok, zona}
      assert Personas.zona_de_mensaje("MSG999999") == {:error, :mensaje_no_existe}
    end
  end

  describe "persistencia y tolerancia a fallos" do
    test "si el servidor falla, el supervisor lo reinicia y recupera todo desde los archivos" do
      zona = crear_zona()
      documento = crear_persona(zona)
      {:ok, _} = Personas.actualizar_estado(documento, :localizada, "Visto en el albergue")
      {:ok, familia} = Personas.registrar_familia("Familia Gómez", zona)
      {:ok, _} = Personas.agregar_miembro(familia.codigo, documento)
      {:ok, mensaje} = Personas.enviar_mensaje("laura", {:persona, documento}, "Hola")
      anterior = Process.whereis(Personas)

      Process.exit(anterior, :kill)
      esperar_reinicio(Personas, anterior)

      assert {:ok, %{estado: :localizada, familia: codigo}} = Personas.obtener(documento)
      assert codigo == familia.codigo
      assert {:ok, historial} = Personas.historial(documento)
      assert length(historial) == 2
      assert {:ok, [recuperado]} = Personas.listar_mensajes({:persona, documento})
      assert recuperado.id == mensaje.id
    end

    test "después de reiniciar, los códigos continúan y no se repiten" do
      zona = crear_zona()
      {:ok, antes} = Personas.registrar(unico("doc"), "Ana", zona)
      anterior = Process.whereis(Personas)

      Process.exit(anterior, :kill)
      esperar_reinicio(Personas, anterior)

      {:ok, despues} = Personas.registrar(unico("doc"), "Luis", zona)
      assert despues.id != antes.id
    end
  end

  describe "funciones recursivas" do
    test "siguiente_numero toma el mayor sufijo más uno" do
      assert Personas.siguiente_numero(["P001", "P007", "P003"], "P") == 8
      assert Personas.siguiente_numero([], "P") == 1
      assert Personas.siguiente_numero(["MSG010"], "MSG") == 11
    end

    test "filtrar_historial y reunir_mensajes sobre listas armadas a mano" do
      historial = [
        %{documento: "1", nuevo: :a},
        %{documento: "2", nuevo: :b},
        %{documento: "1", nuevo: :c}
      ]

      assert Enum.map(Personas.filtrar_historial(historial, "1"), fn e -> e.nuevo end) == [:a, :c]

      mensajes = [
        %{id: "1", destino_tipo: :persona, destino_id: "10"},
        %{id: "2", destino_tipo: :familia, destino_id: "F001"},
        %{id: "3", destino_tipo: :persona, destino_id: "20"}
      ]

      reunidos = Personas.reunir_mensajes(mensajes, [{:persona, "10"}, {:familia, "F001"}])
      assert Enum.map(reunidos, fn m -> m.id end) == ["1", "2"]
    end
  end

  describe "concurrencia" do
    test "dos reportes simultáneos del mismo documento: solo uno se acepta" do
      zona = crear_zona()
      documento = unico("doc")

      resultados =
        ["Ana", "Ana Copia"]
        |> Enum.map(fn nombre ->
          Task.async(fn -> Personas.registrar(documento, nombre, zona) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, fn r -> match?({:ok, _}, r) end) == 1
      assert Enum.count(resultados, fn r -> r == {:error, :ya_existe} end) == 1
      assert length(Personas.buscar(zona: zona)) == 1
    end

    test "veinte reportes simultáneos con documentos distintos reciben códigos únicos" do
      zona = crear_zona()

      ids =
        1..20
        |> Enum.map(fn _numero ->
          Task.async(fn -> Personas.registrar(unico("doc"), "Persona", zona) end)
        end)
        |> Enum.map(&Task.await/1)
        |> Enum.map(fn {:ok, persona} -> persona.id end)

      assert length(Enum.uniq(ids)) == 20
      assert length(Personas.buscar(zona: zona)) == 20
    end

    test "diez agregados simultáneos a una familia: ninguna persona se pierde" do
      zona = crear_zona()
      {:ok, familia} = Personas.registrar_familia("Numerosa", zona)
      documentos = Enum.map(1..10, fn _numero -> crear_persona(zona) end)

      documentos
      |> Enum.map(fn doc ->
        Task.async(fn -> Personas.agregar_miembro(familia.codigo, doc) end)
      end)
      |> Enum.each(&Task.await/1)

      {:ok, final} = Personas.obtener_familia(familia.codigo)
      assert MapSet.size(final.miembros) == 10
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
