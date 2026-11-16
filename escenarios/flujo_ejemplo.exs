# Escenario: flujo completo del enunciado (requisito 1.4.10).
#
# Ejecutar desde la raíz del proyecto:
#
#     mix run escenarios/flujo_ejemplo.exs
#
# Usa una carpeta de datos nueva cada vez, así no depende de ejecuciones anteriores
# ni toca datos/. Cada paso es una línea de comando, tal como se escribiría en la
# consola, y pasa por el despachador (Emergencias.Comandos): se revisan la sesión, los
# permisos de cada tipo de usuario y la regla de zona del coordinador.

defmodule FlujoEjemplo do
  alias Emergencias.Comandos

  def main do
    datos_limpios()

    titulo("1. Usuarios conectados")
    usuarios()

    titulo("2. Zona, sector, punto de atención, centro de acopio y agua")
    preparar_zona()

    titulo("3. Dos necesidades de agua y dos asignaciones al mismo tiempo (hay 50 litros)")
    pedir_agua()

    titulo("4. Andrés en el Albergue Norte y un mensaje de su familia")
    personas_y_familia()

    titulo("5. Albergue: ingreso, salida y reunificación")
    albergue()

    titulo("6. Mascotas perdidas y encontradas")
    mascotas()

    titulo("7. Resumen global del coordinador")
    correr("laura", "summary")
  end

  # ========== Pasos ==========

  defp usuarios do
    # connect usuario clave tipo zona: si el usuario no existe, se registra
    correr(nil, ~s(connect laura 1234 coordinador centro nombre="Laura Gómez"))
    correr(nil, ~s(connect carlos 5678 coordinador centro nombre="Carlos Ruiz"))
    correr(nil, ~s(connect pedro abcd ciudadano centro nombre="Pedro Pérez"))
    correr(nil, ~s(connect marta xyz9 voluntario centro nombre="Marta Díaz"))

    # Los permisos dependen del tipo de usuario
    correr("pedro", ~s(register_zone sur "Sur" bajo))
  end

  defp preparar_zona do
    correr("laura", ~s(register_zone centro "Centro" critico 120))
    correr("laura", ~s(register_sector centro s3 "Sector 3" alto 40))
    correr("laura", ~s(register_point centro s3 p3 "Punto de atención sector 3" 15))
    correr("laura", ~s(register_center centro_acopio_1 "Centro de acopio 1" acopio centro))
    correr("laura", "register_resource R001 agua 50 litros centro_acopio_1")
    correr("laura", "list_resources zona=centro")
  end

  # Laura registra 30 litros para el punto de atención y Pedro 25 para unas familias.
  # Laura y Carlos asignan el agua a la vez: 30 + 25 = 55 y solo hay 50. Recursos
  # atiende un mensaje a la vez, confirma la primera asignación y rechaza la otra.
  defp pedir_agua do
    correr(
      "laura",
      ~s(register_need agua 30 critica centro "Punto de atención sector 3" destino=punto:p3)
    )

    correr("pedro", ~s(register_need agua 25 alta centro "Familias del sector 5"))

    IO.puts("> laura y carlos asignan al mismo tiempo:")

    [{"laura", "assign_resource N001 agua 30"}, {"carlos", "assign_resource N002 agua 25"}]
    |> Enum.map(fn {usuario, linea} ->
      Task.async(fn -> {usuario, linea, Comandos.ejecutar(usuario, linea)} end)
    end)
    |> Enum.map(fn tarea -> Task.await(tarea) end)
    |> Enum.each(fn {usuario, linea, {resultado, texto, _usuario}} ->
      IO.puts("  #{usuario}: #{linea}")
      IO.puts(sangrar(formatear(resultado, texto), "    "))
    end)

    correr("laura", "list_resources zona=centro")
    correr("laura", "list_needs zona=centro")
  end

  defp personas_y_familia do
    correr("laura", ~s(register_shelter A01 "Albergue Norte" centro 150))
    correr("pedro", ~s(report_person 1094 "Andrés Gómez" centro localizada edad=34))
    correr("marta", "register_entry A01 1094")
    correr("pedro", ~s(report_person 1095 "Ana Gómez" centro reportada edad=30))

    correr("pedro", ~s(register_family "Familia Gómez" centro))
    correr("pedro", "add_family_member F001 1094")
    correr("pedro", "add_family_member F001 1095")

    correr(
      "pedro",
      ~s(send_family_message 1094 "Andrés, estamos bien. Te buscamos en el albergue")
    )

    correr("pedro", ~s(send_family_message familia=F001 "Nos vemos en el Albergue Norte"))
    correr("marta", "list_family_messages 1094")
    correr("marta", "mark_message MSG001 entregado")
    correr("pedro", "find_person zona=centro")
  end

  defp albergue do
    correr("pedro", "check_shelter A01")

    # A un albergue solo se entra y se sale con register_entry y register_exit
    correr("marta", "update_person_status 1094 trasladada")

    correr("marta", "register_exit A01 1094")
    correr("marta", ~s(update_person_status 1094 reunificada "Se reunió con su familia"))
    correr("marta", "person_history 1094")
  end

  defp mascotas do
    correr("pedro", ~s(report_pet lost perro "Luna" negra mediano centro 3001234567 collar rojo))

    correr(
      "marta",
      "report_pet found perro desconocido negra mediano centro 3109876543 collar rojo"
    )

    correr("marta", "match_pets")
    correr("laura", "confirm_match M001 M002")

    # Una segunda confirmación no puede cerrar de nuevo el mismo par
    correr("laura", "confirm_match M001 M002")
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

  # Muestra la línea, la ejecuta con el despachador y muestra la respuesta
  defp correr(usuario, linea) do
    quien = if usuario, do: usuario, else: "(sin sesión)"
    IO.puts("> #{quien}: #{linea}")
    {resultado, texto, _usuario} = Comandos.ejecutar(usuario, linea)
    IO.puts(sangrar(formatear(resultado, texto), "  "))
  end

  defp formatear(:ok, texto), do: texto
  defp formatear(:error, texto), do: "ERROR: #{texto}"

  defp sangrar(texto, margen) do
    texto
    |> String.split("\n")
    |> Enum.map(fn linea -> margen <> linea end)
    |> Enum.join("\n")
  end
end

FlujoEjemplo.main()
