defmodule Emergencias.Comandos.PersonasTest do
  use ExUnit.Case

  alias Emergencias.Comandos.Personas, as: Comandos
  alias Emergencias.Mascotas
  alias Emergencias.Zonas

  # ========== Datos de prueba y ayudas ==========

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  defp crear_zona do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona de prueba", "critico")
    zona
  end

  defp ejecutar(comando, argumentos), do: Comandos.ejecutar(comando, argumentos, "laura")

  # Reporta una persona con el comando y devuelve su documento
  defp nueva_persona(zona, extras \\ []) do
    documento = unico("doc")
    {:ok, _texto} = ejecutar("report_person", [documento, "Ana Prueba", zona] ++ extras)
    documento
  end

  # El código de la familia es la segunda palabra: "Familia F001 (...) registrada ..."
  defp nueva_familia(zona) do
    {:ok, texto} = ejecutar("register_family", ["Familia Prueba", zona])
    texto |> String.split(" ") |> Enum.at(1)
  end

  # Reporta una mascota con una especie única, porque match_pets mira todos los reportes
  defp nueva_mascota(tipo, especie, zona) do
    {:ok, _texto} =
      ejecutar("report_pet", [
        tipo,
        especie,
        "Firulais",
        "cafe",
        "mediano",
        zona,
        "3001234567",
        "collar rojo"
      ])

    [reporte] = Mascotas.listar(especie: especie, tipo: tipo_atomo(tipo), estado: "activa")
    reporte.id
  end

  defp tipo_atomo("lost"), do: "perdida"
  defp tipo_atomo("found"), do: "encontrada"

  # ========== Pruebas ==========

  describe "comandos/0" do
    test "son los 14 comandos de personas y mascotas del plan" do
      assert Enum.count(Comandos.comandos()) == 14
      assert Enum.member?(Comandos.comandos(), "confirm_match")
    end
  end

  describe "report_person y find_person" do
    test "reporta una persona con el estado por defecto y la busca por documento" do
      zona = crear_zona()
      documento = nueva_persona(zona)

      {:ok, texto} = ejecutar("find_person", [documento])
      assert texto =~ documento
      assert texto =~ "sin_informacion"
      assert texto =~ "edad 0"
    end

    test "acepta estado y edad" do
      zona = crear_zona()
      documento = nueva_persona(zona, ["localizada", "edad=34"])

      {:ok, texto} = ejecutar("find_person", [documento])
      assert texto =~ "localizada"
      assert texto =~ "edad 34"
    end

    test "la edad puede ir sin estado" do
      zona = crear_zona()
      documento = nueva_persona(zona, ["edad=7"])

      {:ok, texto} = ejecutar("find_person", [documento])
      assert texto =~ "sin_informacion"
      assert texto =~ "edad 7"
    end

    test "busca por zona y por estado" do
      zona = crear_zona()
      _uno = nueva_persona(zona)
      _dos = nueva_persona(zona, ["reportada"])

      {:ok, texto} = ejecutar("find_person", ["zona=#{zona}", "estado=reportada"])
      assert Enum.count(String.split(texto, "\n")) == 1
    end

    test "una búsqueda sin resultados lo dice" do
      assert ejecutar("find_person", ["nombre=nadie_se_llama_asi_#{unico("")}"]) ==
               {:ok, "No se encontraron personas."}
    end

    test "errores: repetida, zona inexistente, edad con letras, estado no permitido y filtro desconocido" do
      zona = crear_zona()
      documento = nueva_persona(zona)

      assert ejecutar("report_person", [documento, "Otra", zona]) == {:error, :ya_existe}

      assert ejecutar("report_person", [unico("doc"), "Ana", "zona_que_no_existe"]) ==
               {:error, :zona_no_existe}

      assert ejecutar("report_person", [unico("doc"), "Ana", zona, "edad=abc"]) ==
               {:error, :numero_invalido}

      assert ejecutar("report_person", [unico("doc"), "Ana", zona, "en_albergue"]) ==
               {:error, :estado_inicial_invalido}

      assert ejecutar("find_person", ["color=rojo"]) == {:error, :opcion_invalida}
    end
  end

  describe "update_person_status y person_history" do
    test "cambia el estado y el historial lo registra" do
      zona = crear_zona()
      documento = nueva_persona(zona)

      assert {:ok, texto} =
               ejecutar("update_person_status", [
                 documento,
                 "localizada",
                 "vista",
                 "en",
                 "el",
                 "parque"
               ])

      assert texto =~ "localizada"

      {:ok, historial} = ejecutar("person_history", [documento])
      lineas = String.split(historial, "\n")
      assert Enum.count(lineas) == 3
      assert Enum.at(lineas, 2) =~ "sin_informacion -> localizada"
      assert Enum.at(lineas, 2) =~ "vista en el parque"
    end

    test "errores: transición inválida, albergue, persona inexistente" do
      zona = crear_zona()
      documento = nueva_persona(zona, ["reportada"])

      assert ejecutar("update_person_status", [documento, "sin_informacion"]) ==
               {:error, :transicion_invalida}

      assert ejecutar("update_person_status", [documento, "en_albergue"]) ==
               {:error, :usar_albergue}

      assert ejecutar("update_person_status", ["no_existe_#{unico("")}", "localizada"]) ==
               {:error, :persona_no_existe}

      assert ejecutar("person_history", ["no_existe_#{unico("")}"]) ==
               {:error, :persona_no_existe}
    end
  end

  describe "familias y mensajes" do
    test "registra la familia, agrega un miembro y evita pertenecer a dos" do
      zona = crear_zona()
      familia = nueva_familia(zona)
      documento = nueva_persona(zona)

      assert {:ok, texto} = ejecutar("add_family_member", [familia, documento])
      assert texto =~ "Miembros: 1"
      assert ejecutar("add_family_member", [familia, documento]) == {:error, :ya_tiene_familia}
      assert ejecutar("add_family_member", ["F999999", documento]) == {:error, :familia_no_existe}
    end

    test "un mensaje a la persona se lista y se marca como entregado" do
      zona = crear_zona()
      documento = nueva_persona(zona)

      assert {:ok, enviado} = ejecutar("send_family_message", [documento, "Estamos bien"])
      assert enviado =~ "MSG"

      {:ok, listado} = ejecutar("list_family_messages", [documento])
      assert listado =~ "de laura"
      assert listado =~ "pendiente"
      assert listado =~ "Estamos bien"

      id = enviado |> String.split(" ") |> Enum.at(1)
      assert {:ok, marcado} = ejecutar("mark_message", [id, "entregado"])
      assert marcado =~ "entregado"
      assert {:ok, listado} = ejecutar("list_family_messages", [documento])
      assert listado =~ "entregado"
    end

    test "un mensaje a la familia lo ve cada miembro" do
      zona = crear_zona()
      familia = nueva_familia(zona)
      documento = nueva_persona(zona)
      {:ok, _texto} = ejecutar("add_family_member", [familia, documento])

      assert {:ok, _texto} =
               ejecutar("send_family_message", ["familia=#{familia}", "Los esperamos"])

      {:ok, de_la_persona} = ejecutar("list_family_messages", [documento])
      {:ok, de_la_familia} = ejecutar("list_family_messages", ["familia=#{familia}"])
      assert de_la_persona =~ "Los esperamos"
      assert de_la_familia =~ "Los esperamos"
    end

    test "errores: destino inexistente, texto vacío, mensaje inexistente y estado inválido" do
      zona = crear_zona()
      documento = nueva_persona(zona)

      assert ejecutar("send_family_message", ["nadie_#{unico("")}", "Hola"]) ==
               {:error, :persona_no_existe}

      assert ejecutar("send_family_message", ["familia=F999999", "Hola"]) ==
               {:error, :familia_no_existe}

      assert ejecutar("send_family_message", [documento, "   "]) == {:error, :contenido_invalido}
      assert ejecutar("list_family_messages", ["familia=F999999"]) == {:error, :familia_no_existe}
      assert ejecutar("mark_message", ["MSG999999", "entregado"]) == {:error, :mensaje_no_existe}
    end

    test "una persona sin mensajes lo dice" do
      zona = crear_zona()
      documento = nueva_persona(zona)
      assert ejecutar("list_family_messages", [documento]) == {:ok, "No hay mensajes."}
    end
  end

  describe "mascotas" do
    test "reporta, lista y filtra por especie" do
      zona = crear_zona()
      especie = unico("especie")
      _id = nueva_mascota("lost", especie, zona)

      {:ok, texto} = ejecutar("list_pets", ["especie=#{especie}", "zona=#{zona}"])
      assert texto =~ "perdida"
      assert texto =~ "activa"
    end

    test "match_pets propone el par, reject_match lo libera y confirm_match lo cierra" do
      zona = crear_zona()
      especie = unico("especie")
      perdida = nueva_mascota("lost", especie, zona)
      encontrada = nueva_mascota("found", especie, zona)

      assert {:ok, propuestos} = ejecutar("match_pets", [])
      assert propuestos =~ "#{perdida} (perdida) <-> #{encontrada} (encontrada): 100 puntos"

      {:ok, texto} = ejecutar("list_pets", ["especie=#{especie}", "estado=posible_coincidencia"])
      assert Enum.count(String.split(texto, "\n")) == 2

      assert {:ok, rechazo} = ejecutar("reject_match", [perdida, encontrada])
      assert rechazo =~ "vuelven a estar activas"

      assert {:ok, confirmado} = ejecutar("confirm_match", [perdida, encontrada])
      assert confirmado =~ "resueltas"
      assert confirmado =~ "3001234567"

      assert ejecutar("confirm_match", [perdida, encontrada]) == {:error, :ya_resuelto}
    end

    test "errores: tipo inválido, tamaño inválido, reporte inexistente y filtro desconocido" do
      zona = crear_zona()

      assert ejecutar("report_pet", ["robada", "perro", "Rex", "negro", "grande", zona, "300"]) ==
               {:error, :tipo_invalido}

      assert ejecutar("report_pet", ["lost", "perro", "Rex", "negro", "enorme", zona, "300"]) ==
               {:error, :tamano_invalido}

      assert ejecutar("confirm_match", ["M999999", "M999998"]) == {:error, :reporte_no_existe}
      assert ejecutar("list_pets", ["color=negro"]) == {:error, :opcion_invalida}
    end
  end

  describe "comandos que no encajan" do
    test "un comando conocido con argumentos de menos" do
      assert ejecutar("report_person", ["solo_documento"]) == {:error, :argumentos_invalidos}
      assert ejecutar("confirm_match", ["M001"]) == {:error, :argumentos_invalidos}
    end

    test "un comando que no es de este módulo" do
      assert ejecutar("fly_to_moon", []) == {:error, :comando_desconocido}
    end
  end
end
