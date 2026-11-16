# Escenario: carga datos de demostración en la carpeta datos/.
#
# Ejecutar desde la raíz del proyecto, con la web y la consola cerradas:
#
#     mix run escenarios/datos_demo.exs
#
# Registra zonas, sectores, puntos de atención, centros, recursos, albergues,
# necesidades, personas, familias, mensajes y mascotas, todo con líneas de comando que
# pasan por el despachador (como si un administrador las escribiera en la consola).
# Sirve para que la interfaz web y el video no empiecen vacíos.
#
# Si datos/ ya tiene información, no hace nada. Para empezar de cero, borre la carpeta
# datos/ antes de ejecutarlo.

defmodule DatosDemo do
  alias Emergencias.Comandos
  alias Emergencias.Persistencia

  @lineas [
    # Zonas, sectores y puntos de atención
    ~s(register_zone centro "Centro" critico 120),
    ~s(register_zone norte "Norte" alto 80),
    ~s(register_zone sur "Sur" medio 40),
    ~s(register_sector centro s1 "Sector 1" critico 60),
    ~s(register_sector centro s2 "Sector 2" alto 35),
    ~s(register_sector norte n1 "Sector Norte 1" alto 30),
    ~s(register_sector sur u1 "Sector Sur 1" medio 20),
    ~s(register_point centro s1 p1 "Punto de atención Parque Central" 25),
    ~s(register_point centro s2 p2 "Punto de atención Coliseo" 15),
    ~s(register_point norte n1 p3 "Punto de atención Estadio" 12),
    # Centros de apoyo y recursos
    ~s(register_center acopio_centro "Centro de acopio Centro" acopio centro),
    ~s(register_center acopio_norte "Centro de acopio Norte" acopio norte),
    ~s(register_center p1 "Punto Parque Central" punto_atencion centro),
    ~s(register_resource R001 agua 500 litros acopio_centro nombre="Agua potable"),
    ~s(register_resource R002 alimentos 300 raciones acopio_centro nombre="Raciones de comida"),
    ~s(register_resource R003 medicamentos 120 kits acopio_norte nombre="Kits de medicamentos"),
    ~s(register_resource R004 primeros_auxilios 80 botiquines acopio_centro nombre="Botiquines"),
    ~s(register_resource R005 agua 200 litros acopio_norte nombre="Agua potable Norte"),
    ~s(register_resource R006 refugio 40 carpas acopio_norte nombre="Carpas familiares"),
    # Albergues (cada albergue también es un centro que puede recibir recursos)
    ~s(register_shelter A01 "Albergue Norte" norte 150 96),
    ~s(register_shelter A02 "Albergue Coliseo" centro 80 71),
    ~s(register_shelter A03 "Albergue Sur" sur 60 12),
    "transfer_resource R001 acopio_centro A02 60",
    "transfer_resource R003 acopio_norte A01 30",
    # Necesidades con distintas prioridades y destinos
    ~s(register_need agua 120 critica centro "Punto de atención sector 1" destino=punto:p1),
    ~s(register_need alimentos 80 alta centro "Familias del sector 2"),
    ~s(register_need medicamentos 40 critica norte "Albergue Norte: enfermos crónicos" destino=albergue:A01),
    ~s(register_need rescate 1 critica centro "Edificio colapsado en el sector 1"),
    ~s(register_need refugio 25 media sur "Familias sin vivienda en el sector sur"),
    ~s(register_need primeros_auxilios 30 alta centro "Brigada del Coliseo" destino=punto:p2),
    "assign_resource N001 agua 120",
    "assign_resource N002 alimentos 50",
    "assign_resource N003 medicamentos 40",
    "update_need_status N004 en_atencion",
    "update_need_status N001 en_atencion",
    "update_need_status N001 atendida",
    # Personas, familias y mensajes
    ~s(report_person 1094 "Andrés Gómez" centro localizada edad=34),
    ~s(report_person 1095 "Ana Gómez" centro reportada edad=31),
    ~s(report_person 1096 "Luis Gómez" centro sin_informacion edad=8),
    ~s(report_person 2001 "María Restrepo" norte localizada edad=67),
    ~s(report_person 2002 "Jorge Ríos" norte trasladada edad=45),
    ~s(report_person 3001 "Camila Ortiz" sur reportada edad=22),
    "register_entry A01 2001",
    "register_entry A02 1094",
    ~s(register_family "Familia Gómez" centro),
    "add_family_member F001 1094",
    "add_family_member F001 1095",
    "add_family_member F001 1096",
    ~s(send_family_message 1094 "Estoy bien, estoy en el Albergue Coliseo"),
    ~s(send_family_message familia=F001 "Nos encontramos en el Albergue Coliseo a las 6 p. m."),
    ~s(send_family_message 2001 "Mamá, voy en camino al Albergue Norte"),
    "mark_message MSG001 entregado",
    # Mascotas
    ~s(report_pet lost perro "Luna" negra mediano centro 3001234567 collar rojo mancha blanca),
    ~s(report_pet found perro desconocido negra mediano centro 3109876543 collar rojo),
    ~s(report_pet lost gato "Michi" gris pequeno norte 3205551234 ojos verdes),
    ~s(report_pet found loro desconocido verde pequeno sur 3157778899 habla mucho),
    "match_pets"
  ]

  def main do
    if Persistencia.cargar("zonas.txt") != [] do
      IO.puts("datos/ ya tiene información: no se cargó nada. Bórrela para empezar de cero.")
    else
      cargar()
    end
  end

  defp cargar do
    {:ok, _texto, admin} =
      Comandos.ejecutar(nil, ~s(connect admin admin administrador centro nombre="Administración"))

    errores =
      Enum.reduce(@lineas, 0, fn linea, errores ->
        case Comandos.ejecutar(admin, linea) do
          {:ok, _texto, _usuario} ->
            errores

          {:error, texto, _usuario} ->
            IO.puts("ERROR en «#{linea}»: #{texto}")
            errores + 1
        end
      end)

    Comandos.ejecutar(admin, "disconnect")
    Emergencias.Bitacora.sincronizar()

    IO.puts("Datos de demostración cargados: #{length(@lineas)} comandos, #{errores} con error.")
    IO.puts("Usuarios: admin/admin (administrador). En la web hay botones de entrada rápida.")
  end
end

DatosDemo.main()
