defmodule Emergencias.Comandos.Base do
  @moduledoc """
  Comandos de la base del sistema: sesión, zonas, resumen, actividad y ayuda.

  `connect` y `disconnect` los atiende directamente el despachador
  (`Emergencias.Comandos`), porque cambian quién está conectado. Los demás siguen el
  mismo contrato que `Comandos.Logistica` y `Comandos.Personas`: `ejecutar/3` recibe
  el nombre del comando, la lista de argumentos y el usuario, y retorna
  `{:ok, texto}` o `{:error, razon}`.
  - Integrante 1: comandos, zonas y resumen
  """

  alias Emergencias.Albergues.Albergue
  alias Emergencias.Bitacora
  alias Emergencias.Reportes
  alias Emergencias.Usuarios
  alias Emergencias.Zonas

  @comandos [
    "help",
    "show_activity",
    "list_users",
    "register_zone",
    "register_sector",
    "register_point",
    "list_zones",
    "zone_status",
    "summary"
  ]

  # Ayuda: {grupo, [{comando, uso, descripción}]}. La usan help y la interfaz web.
  @ayuda [
    {"Sesión",
     [
       {"connect", "connect usuario contraseña tipo zona [nombre=\"Nombre completo\"]",
        "Conecta al usuario; si no existe, lo registra."},
       {"disconnect", "disconnect", "Cierra la sesión."},
       {"show_activity", "show_activity [usuario]",
        "Actividad propia (o de otro, si eres administrador)."},
       {"list_users", "list_users", "Usuarios registrados y conectados (administrador)."},
       {"help", "help [comando]", "Lista de comandos o el uso de uno."}
     ]},
    {"Zonas y resumen",
     [
       {"register_zone", "register_zone codigo nombre nivel [personas]",
        "Registra una zona afectada."},
       {"register_sector", "register_sector zona codigo nombre nivel [personas]",
        "Registra un sector de una zona."},
       {"register_point", "register_point zona sector codigo nombre [personas]",
        "Registra un punto de atención de un sector."},
       {"list_zones", "list_zones", "Lista las zonas con su nivel y personas afectadas."},
       {"zone_status", "zone_status zona", "Estado general de una zona y todo lo asociado."},
       {"summary", "summary", "Resumen global del sistema."}
     ]},
    {"Recursos",
     [
       {"register_center", "register_center codigo nombre tipo zona",
        "Registra un centro de apoyo (acopio o punto_atencion)."},
       {"register_resource",
        "register_resource codigo categoria cantidad unidad centro [nombre=]",
        "Registra un recurso en un centro."},
       {"list_resources", "list_resources [zona=] [categoria=]",
        "Disponibilidad por zona y categoría."},
       {"add_stock", "add_stock codigo centro cantidad", "Entrada de inventario."},
       {"remove_stock", "remove_stock codigo centro cantidad", "Salida de inventario."},
       {"transfer_resource", "transfer_resource codigo origen destino cantidad",
        "Transfiere entre centros."},
       {"list_movements", "list_movements [codigo]", "Historial de movimientos."},
       {"critical_resources", "critical_resources", "Recursos cuya demanda supera lo disponible."}
     ]},
    {"Necesidades",
     [
       {"register_need",
        "register_need tipo cantidad prioridad zona descripcion [destino=tipo:codigo]",
        "Registra una necesidad."},
       {"list_needs", "list_needs [zona=] [tipo=] [prioridad=] [estado=]",
        "Necesidades ordenadas por prioridad."},
       {"assign_resource", "assign_resource necesidad categoria cantidad",
        "Asigna recursos a una necesidad."},
       {"update_need_status", "update_need_status necesidad estado",
        "Cambia el estado de una necesidad."},
       {"cancel_need", "cancel_need necesidad", "Cancela y devuelve lo reservado."},
       {"next_need", "next_need [zona]", "La necesidad más urgente."},
       {"pending_needs", "pending_needs", "Necesidades abiertas por prioridad."}
     ]},
    {"Albergues",
     [
       {"register_shelter", "register_shelter codigo nombre zona capacidad [ocupacion]",
        "Registra un albergue."},
       {"check_shelter", "check_shelter codigo", "Cupos, recursos y necesidades del albergue."},
       {"register_entry", "register_entry albergue documento", "Ingreso de una persona."},
       {"register_exit", "register_exit albergue documento", "Salida de una persona."},
       {"shelter_report", "shelter_report [n]", "Albergues con mayor ocupación."}
     ]},
    {"Personas y mensajes",
     [
       {"report_person", "report_person documento nombre zona [estado] [edad=]",
        "Reporta una persona afectada."},
       {"find_person", "find_person documento | [nombre=] [zona=] [estado=]", "Busca personas."},
       {"update_person_status", "update_person_status documento estado [detalle]",
        "Cambia el estado de una persona."},
       {"person_history", "person_history documento", "Historial de estados de una persona."},
       {"register_family", "register_family nombre zona", "Registra una familia."},
       {"add_family_member", "add_family_member familia documento",
        "Agrega una persona a una familia."},
       {"send_family_message", "send_family_message documento|familia=F001 \"texto\"",
        "Deja un mensaje."},
       {"list_family_messages", "list_family_messages documento|familia=F001",
        "Mensajes de una persona o familia."},
       {"mark_message", "mark_message mensaje entregado|pendiente", "Marca un mensaje."}
     ]},
    {"Mascotas",
     [
       {"report_pet",
        "report_pet lost|found especie nombre color tamano zona contacto [caracteristicas]",
        "Reporta una mascota perdida o encontrada."},
       {"list_pets", "list_pets [especie=] [zona=] [estado=]", "Reportes de mascotas."},
       {"match_pets", "match_pets", "Busca posibles coincidencias con puntaje."},
       {"confirm_match", "confirm_match perdida encontrada", "Confirma y cierra ambos reportes."},
       {"reject_match", "reject_match perdida encontrada", "Descarta una posible coincidencia."}
     ]}
  ]

  @doc "Nombres de los comandos de este módulo."
  def comandos, do: @comandos

  @doc "Tabla de ayuda agrupada: `[{grupo, [{comando, uso, descripcion}]}]`."
  def ayuda, do: @ayuda

  @doc "Uso de un comando, por ejemplo `\"cancel_need necesidad\"`, o `nil`."
  def uso(comando) do
    case buscar_ayuda(@ayuda, comando) do
      nil -> nil
      {_comando, uso, _descripcion} -> uso
    end
  end

  @doc "Ejecuta un comando de la base (ver la documentación del módulo)."
  def ejecutar(comando, argumentos, usuario)

  # ========== Ayuda y actividad ==========

  # help [comando]
  def ejecutar("help", [], _usuario) do
    lineas =
      Enum.flat_map(@ayuda, fn {grupo, comandos} ->
        [
          "",
          "#{grupo}:" | Enum.map(comandos, fn {_comando, uso, _descripcion} -> "  " <> uso end)
        ]
      end)

    {:ok, Enum.join(["Comandos disponibles (escribe help comando para ver uno):" | lineas], "\n")}
  end

  def ejecutar("help", [comando], _usuario) do
    case buscar_ayuda(@ayuda, comando) do
      nil -> {:error, :comando_desconocido}
      {_comando, uso, descripcion} -> {:ok, "#{uso}\n  #{descripcion}"}
    end
  end

  # show_activity [usuario]
  def ejecutar("show_activity", [], usuario), do: actividad(usuario)

  def ejecutar("show_activity", [otro], usuario) do
    if otro == usuario or administrador?(usuario) do
      actividad(otro)
    else
      {:error, :sin_permiso}
    end
  end

  # list_users
  def ejecutar("list_users", [], _usuario) do
    conectados = Usuarios.conectados()

    lineas =
      Enum.map(Usuarios.listar(), fn datos ->
        marca = if Enum.member?(conectados, datos.usuario), do: " (conectado)", else: ""
        "#{datos.usuario} | #{datos.nombre_completo} | #{datos.tipo} | zona #{datos.zona}#{marca}"
      end)

    {:ok, texto(lineas, "No hay usuarios.")}
  end

  # ========== Zonas ==========

  # register_zone codigo nombre nivel [personas]
  def ejecutar("register_zone", [codigo, nombre, nivel], usuario) do
    ejecutar("register_zone", [codigo, nombre, nivel, "0"], usuario)
  end

  def ejecutar("register_zone", [codigo, nombre, nivel, personas], _usuario) do
    with {:ok, personas} <- entero(personas),
         {:ok, zona} <- Zonas.registrar_zona(codigo, nombre, nivel, personas) do
      {:ok, "Zona #{zona.codigo} (#{zona.nombre}) registrada con nivel #{zona.nivel}."}
    end
  end

  # register_sector zona codigo nombre nivel [personas]
  def ejecutar("register_sector", [zona, codigo, nombre, nivel], usuario) do
    ejecutar("register_sector", [zona, codigo, nombre, nivel, "0"], usuario)
  end

  def ejecutar("register_sector", [zona, codigo, nombre, nivel, personas], _usuario) do
    with {:ok, personas} <- entero(personas),
         {:ok, sector} <- Zonas.registrar_sector(zona, codigo, nombre, nivel, personas) do
      {:ok, "Sector #{sector.codigo} (#{sector.nombre}) registrado en la zona #{zona}."}
    end
  end

  # register_point zona sector codigo nombre [personas]
  def ejecutar("register_point", [zona, sector, codigo, nombre], usuario) do
    ejecutar("register_point", [zona, sector, codigo, nombre, "0"], usuario)
  end

  def ejecutar("register_point", [zona, sector, codigo, nombre, personas], _usuario) do
    with {:ok, personas} <- entero(personas),
         {:ok, punto} <- Zonas.registrar_punto(zona, sector, codigo, nombre, personas) do
      {:ok,
       "Punto de atención #{punto.codigo} (#{punto.nombre}) registrado en #{zona}/#{sector}."}
    end
  end

  # list_zones
  def ejecutar("list_zones", [], _usuario) do
    lineas =
      Enum.map(Zonas.listar(), fn zona ->
        {:ok, %{estadisticas: estadisticas}} = Zonas.estado(zona.codigo)

        "#{zona.codigo} | #{zona.nombre} | nivel #{zona.nivel} | #{estadisticas.personas_afectadas} personas afectadas | #{estadisticas.sectores} sectores, #{estadisticas.puntos_atencion} puntos"
      end)

    {:ok, texto(lineas, "No hay zonas registradas.")}
  end

  # zone_status zona
  def ejecutar("zone_status", [codigo], _usuario) do
    with {:ok, estado} <- Reportes.estado_zona(codigo) do
      {:ok, texto_de_zona(estado)}
    end
  end

  # ========== Resumen ==========

  # summary
  def ejecutar("summary", [], _usuario), do: {:ok, texto_de_resumen(Reportes.resumen())}

  # Un comando de la lista con otros argumentos, o un comando que no es de este módulo
  def ejecutar(comando, _argumentos, _usuario) do
    if Enum.member?(@comandos, comando) do
      {:error, :argumentos_invalidos}
    else
      {:error, :comando_desconocido}
    end
  end

  # ========== Textos ==========

  @doc "Texto del resumen global, el que muestra `summary` en la consola."
  def texto_de_resumen(resumen) do
    recursos =
      Enum.map(resumen.recursos, fn recurso ->
        "  #{recurso.codigo} #{recurso.nombre} (#{recurso.categoria}): #{recurso.total} #{recurso.unidad}"
      end)

    pendientes =
      resumen.necesidades_pendientes
      |> Enum.take(5)
      |> Enum.map(fn necesidad ->
        "  #{necesidad.id} [#{necesidad.prioridad}] #{necesidad.tipo} #{necesidad.asignado}/#{necesidad.cantidad}, zona #{necesidad.zona}, #{necesidad.estado}"
      end)

    criticos =
      Enum.map(resumen.recursos_criticos, fn critico ->
        "  zona #{critico.zona}, #{critico.categoria}: faltan #{critico.faltante}"
      end)

    albergues = resumen.albergues

    mas_ocupados =
      Enum.map(albergues.mas_ocupados, fn albergue ->
        "  #{albergue.codigo} #{albergue.nombre}: #{Albergue.ocupacion(albergue)} de #{albergue.capacidad} (#{Albergue.porcentaje(albergue)} %)"
      end)

    lineas =
      [
        "=== Resumen global ===",
        "Zonas: #{resumen.zonas} | Usuarios conectados: #{Enum.count(resumen.conectados)}",
        "",
        "Recursos restantes:"
      ] ++
        si_vacia(recursos, "  ninguno") ++
        [
          "",
          "Necesidades: #{resumen.necesidades} (#{conteo(resumen.necesidades_por_estado)})",
          "Pendientes más urgentes:"
        ] ++
        si_vacia(pendientes, "  ninguna") ++
        ["Recursos críticos:"] ++
        si_vacia(criticos, "  ninguno") ++
        [
          "",
          "Albergues: #{albergues.cantidad}, ocupación #{albergues.ocupacion} de #{albergues.capacidad}, cupos #{albergues.cupos}"
        ] ++
        mas_ocupados ++
        [
          "",
          "Personas: #{resumen.personas} | localizadas: #{resumen.personas_localizadas} (#{conteo(resumen.personas_por_estado)})",
          "Mensajes: #{resumen.mensajes} (#{conteo(resumen.mensajes_por_estado)})",
          "Mascotas: #{resumen.mascotas} (#{conteo(resumen.mascotas_por_tipo)}; #{conteo(resumen.mascotas_por_estado)})"
        ]

    Enum.join(lineas, "\n")
  end

  @doc "Texto del estado de una zona, el que muestra `zone_status`."
  def texto_de_zona(estado) do
    zona = estado.zona
    estadisticas = estado.estadisticas

    sectores =
      Enum.map(estadisticas.personas_por_sector, fn {codigo, total} ->
        "  #{codigo}: #{total} personas"
      end)

    albergues =
      Enum.map(estado.albergues, fn albergue ->
        "  #{albergue.codigo} #{albergue.nombre}: #{Albergue.ocupacion(albergue)} de #{albergue.capacidad}"
      end)

    necesidades =
      Enum.map(estado.necesidades, fn necesidad ->
        "  #{necesidad.id} [#{necesidad.prioridad}] #{necesidad.tipo} #{necesidad.asignado}/#{necesidad.cantidad} #{necesidad.estado}"
      end)

    recursos =
      Enum.map(estado.recursos, fn recurso ->
        "  #{recurso.codigo} #{recurso.nombre}: #{recurso.total} #{recurso.unidad}"
      end)

    lineas =
      [
        "=== Zona #{zona.codigo} (#{zona.nombre}) ===",
        "Nivel: #{zona.nivel} | Personas afectadas (acumulado): #{estadisticas.personas_afectadas}",
        "Sectores: #{estadisticas.sectores} | Puntos de atención: #{estadisticas.puntos_atencion}"
      ] ++
        sectores ++
        ["Albergues:"] ++
        si_vacia(albergues, "  ninguno") ++
        ["Necesidades:"] ++
        si_vacia(necesidades, "  ninguna") ++
        ["Recursos en sus centros:"] ++
        si_vacia(recursos, "  ninguno") ++
        [
          "Personas reportadas: #{Enum.count(estado.personas)}",
          "Reportes de mascotas: #{Enum.count(estado.mascotas)}"
        ]

    Enum.join(lineas, "\n")
  end

  # ========== Funciones auxiliares privadas ==========

  # Los últimos 20 eventos del usuario, con su resultado (ok, error o denegado)
  defp actividad(usuario) do
    lineas =
      usuario
      |> Bitacora.consultar()
      |> Enum.take(-20)
      |> Enum.map(fn evento ->
        accion = String.trim("#{evento.accion} #{evento.detalle}")
        "#{evento.fecha} | #{accion} | #{evento.resultado}"
      end)

    {:ok, texto(lineas, "Sin actividad registrada.")}
  end

  defp administrador?(usuario) do
    case Usuarios.sesion(usuario) do
      {:ok, datos} -> datos.tipo == :administrador
      {:error, _razon} -> false
    end
  end

  defp buscar_ayuda(grupos, comando) do
    grupos
    |> Enum.flat_map(fn {_grupo, comandos} -> comandos end)
    |> Enum.find(fn {nombre, _uso, _descripcion} -> nombre == comando end)
  end

  # "estado: n, estado: n"
  defp conteo(mapa) when mapa == %{}, do: "ninguno"

  defp conteo(mapa) do
    mapa
    |> Enum.sort_by(fn {_clave, cantidad} -> cantidad end, :desc)
    |> Enum.map(fn {clave, cantidad} -> "#{clave}: #{cantidad}" end)
    |> Enum.join(", ")
  end

  defp entero(texto) do
    case Integer.parse(texto) do
      {numero, ""} -> {:ok, numero}
      _otro -> {:error, :numero_invalido}
    end
  end

  defp si_vacia([], mensaje), do: [mensaje]
  defp si_vacia(lineas, _mensaje), do: lineas

  defp texto([], mensaje), do: mensaje
  defp texto(lineas, _mensaje), do: Enum.join(lineas, "\n")
end
