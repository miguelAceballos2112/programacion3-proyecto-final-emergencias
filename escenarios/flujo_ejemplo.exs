# Escenario: flujo completo del enunciado (requisito 1.4.10).
#
# Ejecutar desde la raíz del proyecto:
#
#     mix run escenarios/flujo_ejemplo.exs
#
# Usa una carpeta de datos nueva cada vez, así no depende de ejecuciones anteriores
# ni toca datos/. Cada paso muestra el comando como se escribiría y su respuesta.
#
# Mientras el despachador de comandos (Integrante 1) no esté conectado, este script
# hace de despachador: elige entre Comandos.Personas y Comandos.Logistica según el
# nombre del comando. Los pasos de usuarios y zonas llaman directo a sus servidores.

defmodule FlujoEjemplo do
  alias Emergencias.Comandos.Logistica
  alias Emergencias.Comandos.Personas, as: ComandosPersonas
  alias Emergencias.Necesidades
  alias Emergencias.Usuarios
  alias Emergencias.Zonas

  def main do
    datos_limpios()

    titulo("1. Usuarios conectados")
    usuarios()

    titulo("2. Zona, centro de acopio y agua")
    preparar_zona()

    titulo("3. Laura y Pedro piden agua al mismo tiempo (50 litros disponibles)")
    pedir_agua()

    titulo("4. Personas, familia y mensajes")
    personas_y_familia()

    titulo("5. Albergue: ingreso y salida")
    albergue()

    titulo("6. Mascotas perdidas y encontradas")
    mascotas()

    titulo("7. Resumen final")
    resumen()
  end

  # ========== Pasos ==========

  defp usuarios do
    # connect usuario clave tipo zona: si el usuario no existe, se registra
    {:ok, _laura} = Usuarios.conectar("laura", "1234", "coordinador", "centro")
    {:ok, _pedro} = Usuarios.conectar("pedro", "abcd", "ciudadano", "centro")
    {:ok, _marta} = Usuarios.conectar("marta", "xyz9", "voluntario", "centro")
    IO.puts("  laura (coordinador), pedro (ciudadano) y marta (voluntario) conectados.")

    IO.puts("  laura puede registrar zonas? #{inspect(Usuarios.autorizar("laura", :register_zone))}")
    IO.puts("  pedro puede registrar zonas? #{inspect(Usuarios.autorizar("pedro", :register_zone))}")
    IO.puts("  pedro puede reportar personas? #{inspect(Usuarios.autorizar("pedro", :report_person))}")
  end

  defp preparar_zona do
    # register_zone centro "Centro" critico
    {:ok, _zona} = Zonas.registrar_zona("centro", "Centro", "critico")
    IO.puts("> laura: register_zone centro \"Centro\" critico\n  Zona centro registrada.")

    correr("laura", "register_center", ["centro_acopio_1", "Centro de acopio 1", "acopio", "centro"])
    correr("laura", "register_resource", ["R001", "agua", "50", "litros", "centro_acopio_1"])
    correr("laura", "list_resources", ["zona=centro"])
  end

  # Las dos solicitudes salen a la vez: 30 + 25 = 55 y solo hay 50. Se confirma la
  # primera que llega y la otra se rechaza; el inventario nunca queda en negativo.
  defp pedir_agua do
    solicitudes = [
      {"laura", 30, "critica", "Punto de atención sector 3"},
      {"pedro", 25, "alta", "Familias del sector 5"}
    ]

    resultados =
      solicitudes
      |> Enum.map(fn solicitud -> Task.async(fn -> solicitar(solicitud) end) end)
      |> Enum.map(fn tarea -> Task.await(tarea) end)

    Enum.each(resultados, fn resultado -> mostrar(resultado) end)
    correr("laura", "list_resources", ["zona=centro"])
    correr("laura", "list_needs", ["zona=centro"])
  end

  defp personas_y_familia do
    correr("pedro", "report_person", ["1094", "Ana Gómez", "centro", "reportada", "edad=30"])
    correr("pedro", "report_person", ["1095", "Luis Gómez", "centro", "edad=8"])
    correr("pedro", "find_person", ["zona=centro"])

    correr("pedro", "register_family", ["Familia Gómez", "centro"])
    correr("pedro", "add_family_member", ["F001", "1094"])
    correr("pedro", "add_family_member", ["F001", "1095"])

    correr("pedro", "send_family_message", ["1094", "Ana, estamos en el centro de acopio"])
    correr("pedro", "send_family_message", ["familia=F001", "Los esperamos en el albergue A01"])
    correr("pedro", "list_family_messages", ["1095"])
    correr("marta", "mark_message", ["MSG001", "entregado"])

    correr("marta", "update_person_status", ["1094", "localizada", "Vista en el parque"])
    correr("marta", "person_history", ["1094"])
  end

  defp albergue do
    correr("laura", "register_shelter", ["A01", "Albergue Central", "centro", "20"])
    correr("marta", "register_entry", ["A01", "1094"])

    # A un albergue se entra y se sale con register_entry y register_exit
    correr("marta", "update_person_status", ["1094", "trasladada"])

    correr("marta", "register_exit", ["A01", "1094"])
    correr("marta", "update_person_status", ["1094", "reunificada", "Se reunió con su familia"])
    correr("pedro", "check_shelter", ["A01"])
  end

  defp mascotas do
    correr("pedro", "report_pet", [
      "lost",
      "perro",
      "Firulais",
      "cafe",
      "mediano",
      "centro",
      "3001234567",
      "collar rojo manchas blancas"
    ])

    correr("marta", "report_pet", [
      "found",
      "perro",
      "Desconocido",
      "cafe",
      "mediano",
      "centro",
      "3109876543",
      "collar rojo manchas blancas"
    ])

    correr("marta", "match_pets", [])
    correr("laura", "confirm_match", ["M001", "M002"])

    # Una segunda confirmación no puede cerrar de nuevo el mismo par
    correr("laura", "confirm_match", ["M001", "M002"])
  end

  defp resumen do
    correr("laura", "list_resources", [])
    correr("laura", "list_needs", ["estado=asignada"])
    correr("laura", "find_person", ["estado=reunificada"])
    correr("laura", "list_pets", ["estado=resuelta"])
  end

  # ========== Ayudas ==========

  # Reinicia la aplicación con una carpeta de datos temporal
  defp datos_limpios do
    carpeta =
      Path.join(System.tmp_dir!(), "emergencias_flujo_#{System.unique_integer([:positive])}")

    Application.stop(:emergencias)
    Application.put_env(:emergencias, :directorio_datos, carpeta)
    {:ok, _aplicaciones} = Application.ensure_all_started(:emergencias)
  end

  defp titulo(texto), do: IO.puts("\n=== #{texto} ===")

  # Elige el módulo del comando, lo ejecuta y muestra el comando y su respuesta
  defp correr(usuario, comando, argumentos) do
    IO.puts("> #{usuario}: #{comando} #{mostrar_argumentos(argumentos)}")

    case modulo_de(comando).ejecutar(comando, argumentos, usuario) do
      {:ok, texto} -> IO.puts(sangrar(texto))
      {:error, razon} -> IO.puts("  ERROR: #{razon}")
    end
  end

  defp modulo_de(comando) do
    if Enum.member?(ComandosPersonas.comandos(), comando), do: ComandosPersonas, else: Logistica
  end

  # Los argumentos con espacios se muestran entre comillas, como se escribirían
  defp mostrar_argumentos(argumentos) do
    argumentos
    |> Enum.map(fn argumento ->
      if String.contains?(argumento, " "), do: "\"#{argumento}\"", else: argumento
    end)
    |> Enum.join(" ")
  end

  defp sangrar(texto) do
    texto
    |> String.split("\n")
    |> Enum.map(fn linea -> "  " <> linea end)
    |> Enum.join("\n")
  end

  defp solicitar({usuario, cantidad, prioridad, descripcion}) do
    {:ok, necesidad} =
      Necesidades.registrar("agua", cantidad, prioridad, "centro", descripcion, usuario)

    {usuario, necesidad.id, cantidad, Necesidades.asignar_recurso(necesidad.id, "agua", cantidad)}
  end

  defp mostrar({usuario, id, cantidad, {:ok, necesidad}}) do
    IO.puts("  #{usuario}: #{id} recibió #{cantidad} litros (estado: #{necesidad.estado})")
  end

  defp mostrar({usuario, id, cantidad, {:error, razon}}) do
    IO.puts("  #{usuario}: #{id} NO recibió #{cantidad} litros (#{razon})")
  end
end

FlujoEjemplo.main()
