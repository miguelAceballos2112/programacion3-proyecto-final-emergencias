defmodule EmergenciasWeb.PanelLive do
  @moduledoc """
  Panel principal de la interfaz web.

  Cada pestaña del navegador es un proceso LiveView que vive en el servidor:

  - `mount/3` corre al abrir la página. El proceso se suscribe a la Bitácora.
  - `handle_event/3` recibe lo que hace el usuario (enviar un formulario, hacer clic).
    Todo se convierte en una línea de comando y se envía a `Emergencias.Comandos`, el
    mismo despachador que usa la consola. Por eso los permisos, validaciones y errores
    son exactamente los mismos.
  - `handle_info/2` recibe mensajes de otros procesos: la Bitácora avisa cada vez que
    alguien (en otra pestaña o en la consola) hace algo, y el panel se vuelve a dibujar
    con los datos nuevos.
  - `render/1` dibuja la página con los datos del proceso (`assigns`).

  La pestaña es la dueña de la sesión del usuario: si se cierra, `Usuarios` lo nota
  con su monitor y cierra la sesión.
  """

  use Phoenix.LiveView

  import EmergenciasWeb.Componentes

  alias Emergencias.Albergues
  alias Emergencias.Albergues.Albergue
  alias Emergencias.Bitacora
  alias Emergencias.Comandos
  alias Emergencias.Comandos.Alcance
  alias Emergencias.Comandos.Base
  alias Emergencias.Mascotas
  alias Emergencias.Necesidades
  alias Emergencias.Necesidades.Prioridad
  alias Emergencias.Permisos
  alias Emergencias.Personas
  alias Emergencias.Personas.Persona
  alias Emergencias.Recursos
  alias Emergencias.Recursos.Recurso
  alias Emergencias.Reportes
  alias Emergencias.Usuarios
  alias Emergencias.Zonas
  alias EmergenciasWeb.Formularios

  @secciones [
    {"resumen", "Resumen"},
    {"consola", "Consola de comandos"},
    {"zonas", "Zonas"},
    {"recursos", "Recursos"},
    {"necesidades", "Necesidades"},
    {"albergues", "Albergues"},
    {"personas", "Personas y mensajes"},
    {"mascotas", "Mascotas"},
    {"conflicto", "Conflicto concurrente"},
    {"actividad", "Mi actividad"}
  ]

  # Usuarios de ejemplo para entrar rápido durante la demostración.
  # La primera vez que entran se registran solos (connect registra al que no existe).
  @demostracion [
    {"laura", "1234", "coordinador", "centro", "Laura Gómez"},
    {"carlos", "5678", "coordinador", "centro", "Carlos Ruiz"},
    {"marta", "xyz9", "voluntario", "centro", "Marta Díaz"},
    {"pedro", "abcd", "ciudadano", "centro", "Pedro Pérez"},
    {"admin", "admin", "administrador", "centro", "Administración"}
  ]

  # ========== Ciclo de vida del proceso ==========

  @impl true
  def mount(_params, _session, socket) do
    # Solo el proceso conectado por websocket se suscribe (el primer dibujo es HTTP)
    if connected?(socket), do: Bitacora.suscribir(self())

    socket =
      assign(socket,
        usuario: nil,
        sesion: nil,
        seccion: "resumen",
        historial: [],
        aviso: nil,
        eventos: [],
        conectados: [],
        zona_elegida: nil,
        filtros: %{},
        conflicto: nil,
        prueba: %{"categoria" => "agua", "zona" => nil, "solicitudes" => "10", "cantidad" => nil},
        datos: %{},
        opciones: %{},
        demostracion: @demostracion,
        secciones: @secciones
      )

    {:ok, socket |> cargar_eventos() |> cargar()}
  end

  # Cambio de sección (?seccion=...) sin recargar la página
  @impl true
  def handle_params(params, _uri, socket) do
    seccion = seccion_valida(params["seccion"])

    # Al cambiar de sección se quita el aviso del último comando
    aviso = if seccion == socket.assigns.seccion, do: socket.assigns.aviso, else: nil

    {:noreply, socket |> assign(seccion: seccion, aviso: aviso) |> cargar()}
  end

  # ========== Lo que hace el usuario ==========

  @impl true
  def handle_event("conectar", datos, socket) do
    partes =
      ["usuario", "clave", "tipo", "zona"]
      |> Enum.map(fn campo -> datos |> Map.get(campo, "") |> String.trim() end)
      |> Enum.map(fn valor -> Formularios.citar(valor) end)

    nombre = datos |> Map.get("nombre", "") |> String.trim()
    opcion = if nombre == "", do: [], else: ["nombre=#{Formularios.citar(nombre)}"]

    {:noreply, ejecutar(socket, Enum.join(["connect" | partes] ++ opcion, " "))}
  end

  def handle_event("demostracion", %{"usuario" => usuario}, socket) do
    case Enum.find(@demostracion, fn {nombre, _c, _t, _z, _n} -> nombre == usuario end) do
      nil ->
        {:noreply, socket}

      {nombre, clave, tipo, zona, completo} ->
        linea = ~s(connect #{nombre} #{clave} #{tipo} #{zona} nombre="#{completo}")
        {:noreply, ejecutar(socket, linea)}
    end
  end

  def handle_event("desconectar", _datos, socket) do
    {:noreply, ejecutar(socket, "disconnect")}
  end

  # La consola: la línea se manda tal cual al despachador
  def handle_event("consola", %{"linea" => linea}, socket) do
    socket = if String.trim(linea) == "", do: socket, else: ejecutar(socket, linea)
    {:noreply, push_event(socket, "limpiar-consola", %{})}
  end

  def handle_event("limpiar_consola", _datos, socket) do
    {:noreply, assign(socket, historial: [])}
  end

  # Un formulario: se arma la línea del comando con sus campos
  def handle_event("formulario", %{"_seccion" => seccion, "_comando" => comando} = datos, socket) do
    case Formularios.buscar(seccion, comando) do
      nil -> {:noreply, socket}
      formulario -> {:noreply, ejecutar(socket, Formularios.linea(formulario, datos))}
    end
  end

  # Un botón que ya trae su comando (cancelar, confirmar, marcar...)
  def handle_event("accion", %{"linea" => linea}, socket) do
    {:noreply, ejecutar(socket, linea)}
  end

  def handle_event(
        "asignar",
        %{"necesidad" => id, "categoria" => categoria, "cantidad" => cantidad},
        socket
      ) do
    {:noreply, ejecutar(socket, "assign_resource #{id} #{categoria} #{String.trim(cantidad)}")}
  end

  def handle_event("ver_zona", %{"zona" => zona}, socket) do
    {:noreply, socket |> assign(zona_elegida: zona) |> cargar()}
  end

  def handle_event("filtrar", datos, socket) do
    filtros =
      Enum.reduce(["zona", "tipo", "prioridad", "estado", "nombre", "especie"], %{}, fn clave,
                                                                                        acumulado ->
        valor = datos |> Map.get(clave, "") |> String.trim()
        if valor == "", do: acumulado, else: Map.put(acumulado, clave, valor)
      end)

    {:noreply, socket |> assign(filtros: filtros) |> cargar()}
  end

  def handle_event("conflicto", datos, socket) do
    {:noreply,
     socket |> assign(conflicto: demostrar_conflicto(socket.assigns, datos)) |> cargar()}
  end

  # Vista previa de la prueba: al cambiar la categoría o la zona se vuelve a sugerir
  # una cantidad que produzca conflicto
  def handle_event("conflicto_previa", datos, socket) do
    prueba = Map.take(datos, ["categoria", "zona", "solicitudes", "cantidad"])

    prueba =
      if datos["_target"] in [["categoria"], ["zona"]],
        do: Map.put(prueba, "cantidad", nil),
        else: prueba

    {:noreply, socket |> assign(prueba: prueba) |> cargar()}
  end

  # ========== Mensajes de otros procesos ==========

  # La Bitácora avisa que alguien hizo algo: se agrega a "En vivo" y se recargan los datos
  @impl true
  def handle_info({:bitacora, evento}, socket) do
    eventos = Enum.take([evento | socket.assigns.eventos], 15)
    {:noreply, socket |> assign(eventos: eventos) |> cargar_sesion() |> cargar()}
  end

  def handle_info(_otro, socket), do: {:noreply, socket}

  # ========== Funciones auxiliares ==========

  # Manda la línea al despachador (con esta pestaña como dueña de la sesión) y guarda
  # el resultado para mostrarlo
  defp ejecutar(socket, linea) do
    {resultado, texto, usuario} = Comandos.ejecutar(socket.assigns.usuario, linea, self())
    entrada = %{linea: ocultar_clave(linea), resultado: resultado, texto: texto, hora: hora()}

    socket
    |> assign(
      usuario: usuario,
      aviso: entrada,
      historial: Enum.take([entrada | socket.assigns.historial], 40)
    )
    |> cargar_sesion()
    |> cargar()
  end

  # La contraseña nunca se muestra en el historial
  defp ocultar_clave(linea) do
    case String.split(linea, " ") do
      ["connect", usuario, _clave | resto] -> Enum.join(["connect", usuario, "****" | resto], " ")
      _otra -> linea
    end
  end

  defp cargar_sesion(%{assigns: %{usuario: nil}} = socket), do: assign(socket, sesion: nil)

  defp cargar_sesion(socket) do
    case Usuarios.sesion(socket.assigns.usuario) do
      {:ok, sesion} -> assign(socket, sesion: sesion)
      {:error, _razon} -> assign(socket, usuario: nil, sesion: nil)
    end
  end

  defp cargar_eventos(socket) do
    eventos = nil |> Bitacora.consultar() |> Enum.take(-15) |> Enum.reverse()
    assign(socket, eventos: eventos)
  end

  # Lee los datos de la sección actual. Si un servidor se está reiniciando, la llamada
  # termina con un exit: se muestra un aviso en lugar de cerrar la pestaña.
  defp cargar(socket) do
    try do
      assign(socket,
        datos: datos(socket.assigns.seccion, socket.assigns),
        opciones: opciones(),
        conectados: Usuarios.conectados()
      )
    catch
      :exit, _razon -> assign(socket, datos: :no_disponible)
    end
  end

  defp opciones do
    %{
      zonas:
        Enum.map(Zonas.listar(), fn zona -> {zona.codigo, "#{zona.codigo} · #{zona.nombre}"} end),
      centros:
        Enum.map(Recursos.listar_centros(), fn centro ->
          {centro.codigo, "#{centro.codigo} (#{texto(centro.tipo)}, #{centro.zona})"}
        end),
      albergues:
        Enum.map(Albergues.listar(), fn albergue ->
          {albergue.codigo, "#{albergue.codigo} · #{albergue.nombre}"}
        end)
    }
  end

  # Sin sesión no se muestran datos
  defp datos(_seccion, %{usuario: nil}), do: %{}

  defp datos("resumen", %{sesion: sesion}) do
    if puede?(sesion, "summary") do
      %{resumen: Reportes.resumen()}
    else
      %{zona: estado_de_zona(sesion.zona)}
    end
  end

  defp datos("consola", _assigns), do: %{ayuda: Base.ayuda()}

  defp datos("zonas", assigns) do
    zonas =
      Enum.map(Zonas.listar(), fn zona ->
        {:ok, %{estadisticas: estadisticas}} = Zonas.estado(zona.codigo)
        {zona, estadisticas}
      end)

    elegida =
      cond do
        assigns.zona_elegida != nil -> assigns.zona_elegida
        zonas != [] -> zonas |> hd() |> elem(0) |> Map.get(:codigo)
        true -> nil
      end

    %{zonas: zonas, elegida: elegida, estado: estado_de_zona(elegida)}
  end

  defp datos("recursos", _assigns) do
    %{
      centros: Recursos.listar_centros(),
      recursos: Recursos.listar(),
      movimientos: nil |> Recursos.historial() |> Enum.take(-12) |> Enum.reverse(),
      criticos: Necesidades.recursos_criticos()
    }
  end

  defp datos("necesidades", assigns) do
    filtros =
      Enum.filter(assigns.filtros, fn {clave, _valor} ->
        clave in ["zona", "tipo", "prioridad", "estado"]
      end)

    %{necesidades: Necesidades.listar(filtros), criticos: Necesidades.recursos_criticos()}
  end

  defp datos("albergues", _assigns) do
    %{albergues: Albergue.ordenar_por_ocupacion(Albergues.listar())}
  end

  defp datos("personas", assigns) do
    filtros =
      Enum.filter(assigns.filtros, fn {clave, _valor} -> clave in ["nombre", "zona", "estado"] end)

    %{
      personas: Personas.buscar(filtros),
      mensajes: Personas.mensajes() |> Enum.reverse() |> Enum.take(30)
    }
  end

  defp datos("mascotas", _assigns), do: %{reportes: Mascotas.listar()}

  # La prueba sugiere pedir de a una quinta parte de lo disponible: con 10 solicitudes
  # se confirman unas 5 y el resto se rechaza, como en escenarios/conflicto_concurrente.exs
  defp datos("conflicto", assigns) do
    prueba = assigns.prueba
    zona = prueba["zona"] || assigns.sesion.zona
    disponible = disponible(prueba["categoria"], zona)
    solicitudes = entero(prueba["solicitudes"], 10)
    sugerida = max(div(disponible + 4, 5), 1)
    cantidad = entero(prueba["cantidad"], sugerida) |> max(1)

    %{
      zona: zona,
      disponible: disponible,
      solicitudes: solicitudes,
      cantidad: cantidad,
      maximo: min(div(disponible, cantidad), solicitudes)
    }
  end

  defp datos("actividad", assigns) do
    %{eventos: assigns.usuario |> Bitacora.consultar() |> Enum.reverse() |> Enum.take(40)}
  end

  defp estado_de_zona(nil), do: nil

  defp estado_de_zona(zona) do
    case Reportes.estado_zona(zona) do
      {:ok, estado} -> estado
      {:error, _razon} -> nil
    end
  end

  # Demostración del conflicto concurrente: varias solicitudes asignan el mismo recurso
  # al mismo tiempo, cada una desde su propio proceso (Task).
  defp demostrar_conflicto(assigns, datos) do
    sesion = assigns.sesion
    categoria = Map.get(datos, "categoria", "agua")
    zona = Map.get(datos, "zona", "")
    solicitudes = entero(datos["solicitudes"], 10) |> max(2) |> min(20)
    cantidad = entero(datos["cantidad"], 10) |> max(1)
    devolver = datos["devolver"] == "true"

    cond do
      not puede?(sesion, "assign_resource") ->
        %{error: "La demostración asigna recursos: entra como coordinador o administrador."}

      Alcance.revisar(sesion, "register_need", [categoria, "1", "media", zona]) != :ok ->
        %{error: "Como coordinador solo puedes usar tu zona (#{sesion.zona})."}

      true ->
        usuario = assigns.usuario
        antes = disponible(categoria, zona)

        # 1. Una necesidad por solicitud (se registran una tras otra)
        ids =
          Enum.flat_map(1..solicitudes, fn numero ->
            linea =
              ~s(register_need #{categoria} #{cantidad} media #{zona} "Prueba de concurrencia #{numero}")

            case Comandos.ejecutar(usuario, linea) do
              {:ok, texto, _usuario} -> Regex.run(~r/N\d+/, texto)
              {:error, _texto, _usuario} -> []
            end
          end)

        # 2. Todas las asignaciones salen al mismo tiempo: cada Task es un proceso
        resultados =
          ids
          |> Enum.map(fn id ->
            Task.async(fn ->
              {id, Comandos.ejecutar(usuario, "assign_resource #{id} #{categoria} #{cantidad}")}
            end)
          end)
          |> Enum.map(fn tarea -> Task.await(tarea, 10_000) end)
          |> Enum.map(fn {id, {resultado, texto, _usuario}} ->
            %{id: id, ok: resultado == :ok, texto: texto}
          end)

        despues = disponible(categoria, zona)

        # 3. Si se pidió, se cancelan las necesidades de prueba: lo reservado vuelve
        if devolver,
          do: Enum.each(ids, fn id -> Comandos.ejecutar(usuario, "cancel_need #{id}") end)

        %{
          categoria: categoria,
          zona: zona,
          solicitudes: solicitudes,
          cantidad: cantidad,
          antes: antes,
          despues: despues,
          final: disponible(categoria, zona),
          devolver: devolver,
          resultados: resultados,
          confirmadas: Enum.count(resultados, fn resultado -> resultado.ok end)
        }
    end
  end

  defp disponible(categoria, zona) do
    case Recursos.disponibilidad(categoria, zona) do
      {:ok, cantidad} -> cantidad
      {:error, _razon} -> 0
    end
  end

  defp entero(nil, defecto), do: defecto

  defp entero(texto, defecto) do
    case Integer.parse(String.trim(texto)) do
      {numero, ""} -> numero
      _otro -> defecto
    end
  end

  # ¿El tipo de usuario de la sesión puede ejecutar este comando?
  defp puede?(nil, _comando), do: false

  defp puede?(sesion, comando) do
    case Permisos.accion(comando) do
      {:ok, accion} -> Permisos.permitido?(sesion.tipo, accion)
      {:error, _razon} -> false
    end
  end

  defp seccion_valida(seccion) do
    if Enum.any?(@secciones, fn {clave, _titulo} -> clave == seccion end),
      do: seccion,
      else: "resumen"
  end

  defp hora, do: NaiveDateTime.local_now() |> NaiveDateTime.to_time() |> Time.to_string()

  defp hora_de(fecha), do: fecha |> String.split(" ") |> List.last()

  # ========== Vista ==========

  @impl true
  def render(%{usuario: nil} = assigns) do
    ~H"""
    <div class="ingreso">
      <div class="ingreso-marca">
        <.logo />
        <div>
          <h1>Coordinación de Emergencias</h1>
          <p>Sistema distribuido para la atención posterior a un terremoto · Programación III</p>
        </div>
      </div>

      <div class="ingreso-rejilla">
        <.tarjeta titulo="Conectarse">
          <form id="form-conectar" class="formulario" phx-submit="conectar">
            <p class="uso"><code>connect usuario contraseña tipo zona</code></p>
            <div class="campos">
              <label class="campo">
                <span>Usuario</span>
                <input type="text" name="usuario" required autocomplete="username" />
              </label>
              <label class="campo">
                <span>Contraseña</span>
                <input type="password" name="clave" required autocomplete="current-password" />
              </label>
              <label class="campo">
                <span>Tipo (si es nuevo)</span>
                <select name="tipo">
                  <option :for={tipo <- Formularios.tipos_de_usuario()} value={tipo}>{tipo}</option>
                </select>
              </label>
              <label class="campo">
                <span>Zona principal (si es nuevo)</span>
                <input type="text" name="zona" value="centro" />
              </label>
              <label class="campo campo-ancho">
                <span>Nombre completo (opcional)</span>
                <input type="text" name="nombre" />
              </label>
            </div>
            <button type="submit" class="boton">Conectarse</button>
            <p class="nota">
              Si el usuario no existe se registra automáticamente; si existe, se valida la contraseña.
            </p>
          </form>
          <.aviso aviso={@aviso} />
        </.tarjeta>

        <.tarjeta titulo="Entrada rápida para la demostración">
          <p class="nota">
            Abre varias pestañas y entra con un usuario distinto en cada una: cada pestaña es un
            proceso del servidor y todas ven los cambios de las demás al instante.
          </p>
          <div class="demostracion">
            <button
              :for={{usuario, _clave, tipo, zona, nombre} <- @demostracion}
              class="boton-usuario"
              phx-click="demostracion"
              phx-value-usuario={usuario}
            >
              <strong>{nombre}</strong>
              <span>{usuario} · {tipo} · {zona}</span>
            </button>
          </div>
        </.tarjeta>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="app">
      <header class="barra-superior">
        <div class="marca">
          <.logo />
          <span>Coordinación de Emergencias</span>
        </div>
        <div class="usuario-actual">
          <span class="conectados" title={Enum.join(@conectados, ", ")}>
            <span class="punto-vivo"></span> {length(@conectados)} conectados
          </span>
          <span class="quien">
            <strong>{@sesion && @sesion.nombre_completo}</strong>
            <.insignia valor={@sesion && @sesion.tipo} />
            <span class="zona">zona {@sesion && @sesion.zona}</span>
          </span>
          <button class="boton boton-secundario" phx-click="desconectar">Salir</button>
        </div>
      </header>

      <nav class="menu" aria-label="Secciones">
        <.link
          :for={{clave, titulo} <- @secciones}
          patch={"/?seccion=#{clave}"}
          class={["menu-enlace", clave == @seccion && "activo"]}
        >
          {titulo}
        </.link>
      </nav>

      <main class="contenido">
        <.aviso aviso={@aviso} />
        <.contenido {assigns} />
      </main>

      <aside class="en-vivo" aria-label="Actividad en vivo">
        <h3><span class="punto-vivo"></span> En vivo</h3>
        <p class="nota">
          Lo que hacen todos los usuarios, desde la web o la consola (lo envía la Bitácora).
        </p>
        <ul>
          <li :for={evento <- @eventos} class={"evento evento-#{evento.resultado}"}>
            <span class="evento-hora">{hora_de(evento.fecha)}</span>
            <strong>{evento.usuario}</strong>
            <span class="evento-accion">{evento.accion}</span>
            <span :if={evento.detalle != ""} class="evento-detalle">{evento.detalle}</span>
          </li>
        </ul>
      </aside>
    </div>
    """
  end

  # ---------- Piezas comunes ----------

  defp logo(assigns) do
    ~H"""
    <svg class="logo" viewBox="0 0 32 32" aria-hidden="true">
      <rect x="1" y="1" width="30" height="30" rx="8" />
      <path d="M13 7h6v6h6v6h-6v6h-6v-6H7v-6h6z" />
    </svg>
    """
  end

  attr :aviso, :map, default: nil

  defp aviso(%{aviso: nil} = assigns), do: ~H""

  defp aviso(assigns) do
    ~H"""
    <div class={["aviso", "aviso-#{@aviso.resultado}"]} role="status">
      <div class="aviso-linea"><span>Comando</span> <code>{@aviso.linea}</code></div>
      <pre>{@aviso.texto}</pre>
    </div>
    """
  end

  # ---------- Secciones ----------

  defp contenido(%{datos: :no_disponible} = assigns) do
    ~H"""
    <.tarjeta titulo="Datos no disponibles">
      <p>Un servidor se está reiniciando. Los datos se recargan en un momento.</p>
    </.tarjeta>
    """
  end

  defp contenido(%{seccion: "resumen", datos: %{resumen: _}} = assigns) do
    ~H"""
    <h2>Resumen global <small><code>summary</code></small></h2>
    <div class="indicadores">
      <.indicador etiqueta="Zonas" valor={@datos.resumen.zonas} />
      <.indicador
        etiqueta="Necesidades abiertas"
        valor={length(@datos.resumen.necesidades_pendientes)}
        detalle={"de #{@datos.resumen.necesidades} registradas"}
        tono="alerta"
      />
      <.indicador
        etiqueta="Personas localizadas"
        valor={@datos.resumen.personas_localizadas}
        detalle={"con paradero conocido, de #{@datos.resumen.personas}"}
      />
      <.indicador
        etiqueta="Mensajes pendientes"
        valor={Map.get(@datos.resumen.mensajes_por_estado, :pendiente, 0)}
        detalle={"de #{@datos.resumen.mensajes}"}
      />
      <.indicador
        etiqueta="Mascotas"
        valor={@datos.resumen.mascotas}
        detalle={"#{Map.get(@datos.resumen.mascotas_por_estado, :resuelta, 0)} resueltas"}
      />
      <.indicador
        etiqueta="Ocupación de albergues"
        valor={"#{@datos.resumen.albergues.ocupacion}/#{@datos.resumen.albergues.capacidad}"}
        detalle={"#{@datos.resumen.albergues.cupos} cupos libres"}
      />
    </div>

    <div class="rejilla">
      <.tarjeta titulo="Recursos restantes">
        <.vacio :if={@datos.resumen.recursos == []} texto="No hay recursos registrados." />
        <table :if={@datos.resumen.recursos != []}>
          <thead>
            <tr>
              <th>Código</th><th>Recurso</th><th>Categoría</th><th class="num">Disponible</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={recurso <- @datos.resumen.recursos}>
              <td>{recurso.codigo}</td>
              <td>{recurso.nombre}</td>
              <td>{texto(recurso.categoria)}</td>
              <td class="num">{recurso.total} {recurso.unidad}</td>
            </tr>
          </tbody>
        </table>
      </.tarjeta>

      <.tarjeta titulo="Necesidades pendientes (por prioridad)">
        <.vacio
          :if={@datos.resumen.necesidades_pendientes == []}
          texto="No hay necesidades abiertas."
        />
        <table :if={@datos.resumen.necesidades_pendientes != []}>
          <thead>
            <tr>
              <th>Id</th><th>Prioridad</th><th>Tipo y zona</th><th class="num">Asignado</th><th>
                Estado
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={necesidad <- Enum.take(@datos.resumen.necesidades_pendientes, 8)}>
              <td>{necesidad.id}</td>
              <td><.insignia valor={necesidad.prioridad} /></td>
              <td>{texto(necesidad.tipo)} <small>· {necesidad.zona}</small></td>
              <td class="num">{necesidad.asignado}/{necesidad.cantidad}</td>
              <td><.insignia valor={necesidad.estado} /></td>
            </tr>
          </tbody>
        </table>
      </.tarjeta>

      <.tarjeta titulo="Recursos críticos">
        <.vacio
          :if={@datos.resumen.recursos_criticos == []}
          texto="Lo disponible alcanza para la demanda pendiente."
        />
        <ul class="lista">
          <li :for={critico <- @datos.resumen.recursos_criticos}>
            Zona <strong>{critico.zona}</strong>, {texto(critico.categoria)}: faltan
            <strong class="texto-alerta">{critico.faltante}</strong>
            (se piden {critico.demanda}, hay {critico.disponible})
          </li>
        </ul>
      </.tarjeta>

      <.tarjeta titulo="Albergues con mayor ocupación">
        <.vacio :if={@datos.resumen.albergues.mas_ocupados == []} texto="No hay albergues." />
        <div :for={albergue <- @datos.resumen.albergues.mas_ocupados} class="fila-albergue">
          <span>{albergue.codigo} · {albergue.nombre}</span>
          <.barra porcentaje={Albergue.porcentaje(albergue)} />
          <span class="num">{Albergue.ocupacion(albergue)}/{albergue.capacidad}</span>
        </div>
      </.tarjeta>

      <.tarjeta titulo="Personas por estado">
        <.conteo mapa={@datos.resumen.personas_por_estado} vacio="No hay personas reportadas." />
      </.tarjeta>

      <.tarjeta titulo="Mascotas y mensajes">
        <h4>Reportes de mascotas</h4>
        <.conteo mapa={@datos.resumen.mascotas_por_estado} vacio="No hay reportes." />
        <h4>Mensajes</h4>
        <.conteo mapa={@datos.resumen.mensajes_por_estado} vacio="No hay mensajes." />
      </.tarjeta>
    </div>
    <p class="nota">
      Para armar este resumen, <code>Reportes.resumen/0</code>
      consulta a los servidores al mismo tiempo,
      con una tarea (<code>Task.async</code>) por cada uno.
    </p>
    """
  end

  defp contenido(%{seccion: "resumen"} = assigns) do
    ~H"""
    <h2>Mi zona <small><code>zone_status {@sesion.zona}</code></small></h2>
    <p class="nota">
      El resumen global (<code>summary</code>) es para coordinadores y administradores. Aquí ves el
      estado de tu zona principal.
    </p>
    <.estado_zona estado={@datos.zona} />
    """
  end

  defp contenido(%{seccion: "consola"} = assigns) do
    ~H"""
    <h2>Consola de comandos</h2>
    <.tarjeta titulo="Escribe los mismos comandos que en la terminal">
      <:acciones>
        <button class="boton boton-secundario" phx-click="limpiar_consola">Limpiar</button>
      </:acciones>
      <div id="historial-consola" class="consola" phx-hook="Abajo">
        <p :if={@historial == []} class="consola-ayuda">
          Prueba: help · list_needs · summary · register_need agua 30 critica centro "Punto 3"
        </p>
        <div
          :for={entrada <- Enum.reverse(@historial)}
          class={["consola-entrada", "consola-#{entrada.resultado}"]}
        >
          <div class="consola-linea">
            <span class="consola-hora">{entrada.hora}</span> &gt; {entrada.linea}
          </div>
          <pre>{entrada.texto}</pre>
        </div>
      </div>
      <form id="form-consola" class="consola-formulario" phx-submit="consola">
        <span class="consola-indicador">{@usuario}&gt;</span>
        <input
          type="text"
          name="linea"
          autocomplete="off"
          autofocus
          placeholder="Escribe un comando y pulsa Enter"
        />
        <button type="submit" class="boton">Ejecutar</button>
      </form>
    </.tarjeta>

    <.tarjeta titulo="Comandos disponibles">
      <div class="ayuda">
        <div :for={{grupo, comandos} <- @datos.ayuda} class="ayuda-grupo">
          <h4>{grupo}</h4>
          <ul>
            <li
              :for={{comando, uso, descripcion} <- comandos}
              class={not permitido?(@sesion, comando) && "bloqueado"}
            >
              <code>{uso}</code>
              <span>{descripcion}</span>
              <small :if={not permitido?(@sesion, comando)}>(no disponible para {texto(@sesion.tipo)})</small>
            </li>
          </ul>
        </div>
      </div>
    </.tarjeta>
    """
  end

  defp contenido(%{seccion: "zonas"} = assigns) do
    ~H"""
    <h2>Zonas afectadas</h2>
    <div class="rejilla">
      <.tarjeta titulo="Zonas registradas" class="ancho">
        <.vacio :if={@datos.zonas == []} texto="No hay zonas. Registra la primera con el formulario." />
        <table :if={@datos.zonas != []}>
          <thead>
            <tr>
              <th>Código</th><th>Nombre</th><th>Nivel</th><th class="num">Personas (acumulado)</th><th class="num">
                Sectores
              </th><th class="num">Puntos</th><th></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{zona, estadisticas} <- @datos.zonas}
              class={zona.codigo == @datos.elegida && "fila-elegida"}
            >
              <td>{zona.codigo}</td>
              <td>{zona.nombre}</td>
              <td><.insignia valor={zona.nivel} /></td>
              <td class="num">{estadisticas.personas_afectadas}</td>
              <td class="num">{estadisticas.sectores}</td>
              <td class="num">{estadisticas.puntos_atencion}</td>
              <td>
                <button class="boton-mini" phx-click="ver_zona" phx-value-zona={zona.codigo}>Ver estado</button>
              </td>
            </tr>
          </tbody>
        </table>
        <p class="nota">
          Las personas afectadas se suman con funciones recursivas sobre zona → sectores → puntos de atención.
        </p>
      </.tarjeta>
    </div>
    <h3 :if={@datos.estado}>
      Estado de la zona {@datos.elegida} <small><code>zone_status {@datos.elegida}</code></small>
    </h3>
    <.estado_zona :if={@datos.estado} estado={@datos.estado} />
    <.formularios seccion="zonas" sesion={@sesion} opciones={@opciones} />
    """
  end

  defp contenido(%{seccion: "recursos"} = assigns) do
    ~H"""
    <h2>Recursos y centros de apoyo</h2>
    <div class="rejilla">
      <.tarjeta titulo="Inventario por centro" class="ancho">
        <.vacio :if={@datos.recursos == []} texto="No hay recursos registrados." />
        <table :if={@datos.recursos != []}>
          <thead>
            <tr>
              <th>Código</th><th>Nombre</th><th>Categoría</th><th class="num">Total</th><th>
                Existencias por centro
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={recurso <- @datos.recursos}>
              <td>{recurso.codigo}</td>
              <td>{recurso.nombre}</td>
              <td>{texto(recurso.categoria)}</td>
              <td class="num">{Recurso.total(recurso)} {recurso.unidad}</td>
              <td>
                <span :for={{centro, cantidad} <- recurso.existencias} class="ficha">{centro}: {cantidad}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </.tarjeta>

      <.tarjeta titulo="Centros de apoyo">
        <.vacio :if={@datos.centros == []} texto="No hay centros registrados." />
        <table :if={@datos.centros != []}>
          <thead>
            <tr>
              <th>Código</th><th>Nombre</th><th>Tipo</th><th>Zona</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={centro <- @datos.centros}>
              <td>{centro.codigo}</td>
              <td>{centro.nombre}</td>
              <td>{texto(centro.tipo)}</td>
              <td>{centro.zona}</td>
            </tr>
          </tbody>
        </table>
      </.tarjeta>

      <.tarjeta titulo="Últimos movimientos">
        <.vacio :if={@datos.movimientos == []} texto="Sin movimientos todavía." />
        <ul class="lista">
          <li :for={movimiento <- @datos.movimientos}>
            <.insignia valor={movimiento.tipo} />
            {movimiento.codigo} · {movimiento.cantidad}
            <span :if={movimiento.origen != ""}>de {movimiento.origen}</span>
            <span :if={movimiento.destino != ""}>a {movimiento.destino}</span>
            <small :if={movimiento.referencia != ""}>({movimiento.referencia})</small>
          </li>
        </ul>
      </.tarjeta>

      <.tarjeta titulo="Recursos críticos">
        <.vacio :if={@datos.criticos == []} texto="Lo disponible alcanza para la demanda pendiente." />
        <ul class="lista">
          <li :for={critico <- @datos.criticos}>
            Zona <strong>{critico.zona}</strong>, {texto(critico.categoria)}: faltan
            <strong class="texto-alerta">{critico.faltante}</strong>
          </li>
        </ul>
      </.tarjeta>
    </div>
    <.formularios seccion="recursos" sesion={@sesion} opciones={@opciones} />
    """
  end

  defp contenido(%{seccion: "necesidades"} = assigns) do
    ~H"""
    <h2>Necesidades <small><code>list_needs</code> ordenadas por prioridad</small></h2>
    <form id="filtro-necesidades" class="filtros" phx-change="filtrar">
      <label>
        Zona
        <select name="zona">
          <option value="">todas</option>
          <option
            :for={{codigo, _texto} <- @opciones.zonas}
            value={codigo}
            selected={@filtros["zona"] == codigo}
          >
            {codigo}
          </option>
        </select>
      </label>
      <label>
        Tipo
        <select name="tipo">
          <option value="">todos</option>
          <option
            :for={categoria <- Recurso.categorias()}
            value={categoria}
            selected={@filtros["tipo"] == "#{categoria}"}
          >
            {texto(categoria)}
          </option>
        </select>
      </label>
      <label>
        Prioridad
        <select name="prioridad">
          <option value="">todas</option>
          <option
            :for={prioridad <- Prioridad.lista()}
            value={prioridad}
            selected={@filtros["prioridad"] == "#{prioridad}"}
          >
            {texto(prioridad)}
          </option>
        </select>
      </label>
      <label>
        Estado
        <select name="estado">
          <option value="">todos</option>
          <option
            :for={estado <- ["pendiente", "asignada", "en_atencion", "atendida", "cancelada"]}
            value={estado}
            selected={@filtros["estado"] == estado}
          >
            {texto(estado)}
          </option>
        </select>
      </label>
    </form>

    <.tarjeta>
      <.vacio :if={@datos.necesidades == []} texto="No hay necesidades con esos filtros." />
      <table :if={@datos.necesidades != []} class="tabla-necesidades">
        <thead>
          <tr>
            <th>Id</th><th>Prioridad</th><th>Tipo</th><th class="num">Asignado</th><th>
              Zona / destino
            </th><th>Descripción</th><th>Estado</th><th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={necesidad <- @datos.necesidades}>
            <td>{necesidad.id}</td>
            <td><.insignia valor={necesidad.prioridad} /></td>
            <td>{texto(necesidad.tipo)}</td>
            <td class="num">{necesidad.asignado}/{necesidad.cantidad}</td>
            <td>{necesidad.zona} <small>{destino(necesidad.destino)}</small></td>
            <td>{necesidad.descripcion} <small>· {necesidad.responsable}</small></td>
            <td><.insignia valor={necesidad.estado} /></td>
            <td class="acciones">
              <form
                :if={
                  necesidad.estado in [:pendiente, :asignada] and
                    necesidad.asignado < necesidad.cantidad and permitido?(@sesion, "assign_resource")
                }
                id={"asignar-#{necesidad.id}"}
                class="en-linea"
                phx-submit="asignar"
              >
                <input type="hidden" name="necesidad" value={necesidad.id} />
                <input type="hidden" name="categoria" value={necesidad.tipo} />
                <input
                  type="number"
                  name="cantidad"
                  min="1"
                  value={necesidad.cantidad - necesidad.asignado}
                />
                <button class="boton-mini">Asignar</button>
              </form>
              <button
                :if={
                  necesidad.estado in [:pendiente, :asignada] and
                    permitido?(@sesion, "update_need_status")
                }
                class="boton-mini"
                phx-click="accion"
                phx-value-linea={"update_need_status #{necesidad.id} en_atencion"}
              >En atención</button>
              <button
                :if={necesidad.estado == :en_atencion and permitido?(@sesion, "update_need_status")}
                class="boton-mini"
                phx-click="accion"
                phx-value-linea={"update_need_status #{necesidad.id} atendida"}
              >Atendida</button>
              <button
                :if={
                  necesidad.estado in [:pendiente, :asignada, :en_atencion] and
                    permitido?(@sesion, "cancel_need")
                }
                class="boton-mini boton-peligro"
                phx-click="accion"
                phx-value-linea={"cancel_need #{necesidad.id}"}
                data-confirm={"¿Cancelar #{necesidad.id}? Lo reservado vuelve a su centro."}
              >Cancelar</button>
            </td>
          </tr>
        </tbody>
      </table>
    </.tarjeta>

    <.tarjeta :if={@datos.criticos != []} titulo="Recursos críticos">
      <ul class="lista">
        <li :for={critico <- @datos.criticos}>
          Zona <strong>{critico.zona}</strong>, {texto(critico.categoria)}: faltan
          <strong class="texto-alerta">{critico.faltante}</strong>
          (se piden {critico.demanda}, hay {critico.disponible})
        </li>
      </ul>
    </.tarjeta>
    <.formularios seccion="necesidades" sesion={@sesion} opciones={@opciones} />
    """
  end

  defp contenido(%{seccion: "albergues"} = assigns) do
    ~H"""
    <h2>Albergues <small>de mayor a menor ocupación (<code>shelter_report</code>)</small></h2>
    <.vacio :if={@datos.albergues == []} texto="No hay albergues registrados." />
    <div class="albergues">
      <.tarjeta :for={albergue <- @datos.albergues} titulo={"#{albergue.codigo} · #{albergue.nombre}"}>
        <p class="nota">Zona {albergue.zona} · capacidad {albergue.capacidad}</p>
        <.barra porcentaje={Albergue.porcentaje(albergue)} />
        <p class="ocupacion">
          <strong>{Albergue.ocupacion(albergue)}</strong>
          de {albergue.capacidad} ({Albergue.porcentaje(albergue)} %) ·
          <strong>{Albergue.cupos(albergue)}</strong>
          cupos
        </p>
        <p :if={albergue.ocupacion_inicial > 0} class="nota">
          Ocupación inicial: {albergue.ocupacion_inicial}
        </p>
        <div class="fichas">
          <span :for={documento <- MapSet.to_list(albergue.ocupantes)} class="ficha">
            {documento}
            <button
              :if={permitido?(@sesion, "register_exit")}
              class="ficha-quitar"
              title="Registrar salida"
              phx-click="accion"
              phx-value-linea={"register_exit #{albergue.codigo} #{documento}"}
            >×</button>
          </span>
        </div>
        <:acciones>
          <button
            class="boton-mini"
            phx-click="accion"
            phx-value-linea={"check_shelter #{albergue.codigo}"}
          >check_shelter</button>
        </:acciones>
      </.tarjeta>
    </div>
    <.formularios seccion="albergues" sesion={@sesion} opciones={@opciones} />
    """
  end

  defp contenido(%{seccion: "personas"} = assigns) do
    ~H"""
    <h2>Personas afectadas y mensajes entre familiares</h2>
    <form id="filtro-personas" class="filtros" phx-change="filtrar">
      <label>Nombre <input type="text" name="nombre" value={@filtros["nombre"]} phx-debounce="300" /></label>
      <label>
        Zona
        <select name="zona">
          <option value="">todas</option>
          <option
            :for={{codigo, _texto} <- @opciones.zonas}
            value={codigo}
            selected={@filtros["zona"] == codigo}
          >
            {codigo}
          </option>
        </select>
      </label>
      <label>
        Estado
        <select name="estado">
          <option value="">todos</option>
          <option
            :for={estado <- Persona.estados()}
            value={estado}
            selected={@filtros["estado"] == "#{estado}"}
          >
            {texto(estado)}
          </option>
        </select>
      </label>
    </form>

    <div class="rejilla">
      <.tarjeta titulo="Personas" class="ancho">
        <.vacio :if={@datos.personas == []} texto="No hay personas con esos filtros." />
        <table :if={@datos.personas != []}>
          <thead>
            <tr>
              <th>Documento</th><th>Nombre</th><th class="num">Edad</th><th>Zona</th><th>Estado</th><th>
                Familia
              </th><th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={persona <- @datos.personas}>
              <td>{persona.documento}</td>
              <td>{persona.nombre}</td>
              <td class="num">{persona.edad}</td>
              <td>{persona.zona}</td>
              <td><.insignia valor={persona.estado} /></td>
              <td>{persona.familia || "—"}</td>
              <td class="acciones">
                <button
                  :if={permitido?(@sesion, "person_history")}
                  class="boton-mini"
                  phx-click="accion"
                  phx-value-linea={"person_history #{persona.documento}"}
                >Historial</button>
                <button
                  class="boton-mini"
                  phx-click="accion"
                  phx-value-linea={"list_family_messages #{persona.documento}"}
                >Mensajes</button>
              </td>
            </tr>
          </tbody>
        </table>
      </.tarjeta>

      <.tarjeta titulo="Mensajes recientes" class="ancho">
        <.vacio :if={@datos.mensajes == []} texto="Todavía no hay mensajes." />
        <table :if={@datos.mensajes != []}>
          <thead>
            <tr>
              <th>Id</th><th>Fecha</th><th>De</th><th>Para</th><th>Mensaje</th><th>Estado</th><th>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={mensaje <- @datos.mensajes}>
              <td>{mensaje.id}</td>
              <td><small>{mensaje.fecha}</small></td>
              <td>{mensaje.remitente}</td>
              <td>{texto(mensaje.destino_tipo)} {mensaje.destino_id}</td>
              <td>{mensaje.contenido}</td>
              <td><.insignia valor={mensaje.estado} /></td>
              <td class="acciones">
                <button
                  :if={permitido?(@sesion, "mark_message")}
                  class="boton-mini"
                  phx-click="accion"
                  phx-value-linea={"mark_message #{mensaje.id} #{if mensaje.estado == :entregado, do: "pendiente", else: "entregado"}"}
                >{if mensaje.estado == :entregado, do: "Marcar pendiente", else: "Marcar entregado"}</button>
              </td>
            </tr>
          </tbody>
        </table>
      </.tarjeta>
    </div>
    <.formularios seccion="personas" sesion={@sesion} opciones={@opciones} />
    """
  end

  defp contenido(%{seccion: "mascotas"} = assigns) do
    ~H"""
    <h2>Mascotas perdidas y encontradas</h2>
    <.tarjeta titulo="Reportes">
      <:acciones>
        <button
          :if={permitido?(@sesion, "match_pets")}
          class="boton"
          phx-click="accion"
          phx-value-linea="match_pets"
        >
          Buscar coincidencias (match_pets)
        </button>
      </:acciones>
      <.vacio :if={@datos.reportes == []} texto="No hay reportes de mascotas." />
      <table :if={@datos.reportes != []}>
        <thead>
          <tr>
            <th>Id</th><th>Tipo</th><th>Especie</th><th>Nombre</th><th>Color</th><th>Tamaño</th><th>
              Zona
            </th><th>Contacto</th><th>Estado</th><th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={reporte <- @datos.reportes}>
            <td>{reporte.id}</td>
            <td><.insignia valor={reporte.tipo} /></td>
            <td>{reporte.especie}</td>
            <td>{reporte.nombre}</td>
            <td>{reporte.color}</td>
            <td>{texto(reporte.tamano)}</td>
            <td>{reporte.zona}</td>
            <td>{reporte.contacto}</td>
            <td>
              <.insignia valor={reporte.estado} />
              <small :if={reporte.pareja}>con {reporte.pareja}</small>
            </td>
            <td class="acciones">
              <button
                :if={
                  reporte.tipo == :perdida and reporte.estado == :posible_coincidencia and
                    permitido?(@sesion, "confirm_match")
                }
                class="boton-mini"
                phx-click="accion"
                phx-value-linea={"confirm_match #{reporte.id} #{reporte.pareja}"}
              >Confirmar</button>
              <button
                :if={
                  reporte.tipo == :perdida and reporte.estado == :posible_coincidencia and
                    permitido?(@sesion, "reject_match")
                }
                class="boton-mini boton-peligro"
                phx-click="accion"
                phx-value-linea={"reject_match #{reporte.id} #{reporte.pareja}"}
              >Rechazar</button>
            </td>
          </tr>
        </tbody>
      </table>
      <p class="nota">
        El puntaje de similitud (0 a 100) compara especie, color, tamaño, zona y las palabras de las
        características. Con 60 puntos o más, el par queda como posible coincidencia.
      </p>
    </.tarjeta>
    <.formularios seccion="mascotas" sesion={@sesion} opciones={@opciones} />
    """
  end

  defp contenido(%{seccion: "conflicto"} = assigns) do
    ~H"""
    <h2>Conflicto concurrente</h2>
    <div class="rejilla">
      <.tarjeta titulo="¿Qué se demuestra?">
        <p>
          Varias solicitudes intentan tomar el mismo recurso <strong>al mismo tiempo</strong>. Cada
          solicitud corre en su propio proceso (<code>Task.async</code>) y todas le escriben al
          GenServer <code>Recursos</code>.
        </p>
        <p>
          El GenServer atiende los mensajes de su buzón <strong>uno por uno</strong>: verifica el
          inventario y lo descuenta dentro del mismo <code>handle_call</code>. Por eso nunca se
          asigna más de lo que hay y el inventario nunca queda negativo.
        </p>
        <ol class="pasos">
          <li>Se registran N necesidades iguales en la zona.</li>
          <li>Se lanzan N <code>assign_resource</code> a la vez, uno por proceso.</li>
          <li>Se cuentan las confirmadas y las rechazadas (<code>stock_insuficiente</code>).</li>
        </ol>
      </.tarjeta>

      <.tarjeta titulo="Lanzar la prueba">
        <form
          id="form-conflicto"
          class="formulario"
          phx-submit="conflicto"
          phx-change="conflicto_previa"
        >
          <div class="campos">
            <label class="campo">
              <span>Categoría</span>
              <select name="categoria">
                <option
                  :for={categoria <- Recurso.categorias()}
                  value={categoria}
                  selected={"#{categoria}" == @prueba["categoria"]}
                >
                  {texto(categoria)}
                </option>
              </select>
            </label>
            <label class="campo">
              <span>Zona</span>
              <select name="zona">
                <option
                  :for={{codigo, texto_zona} <- @opciones.zonas}
                  value={codigo}
                  selected={codigo == @datos.zona}
                >
                  {texto_zona}
                </option>
              </select>
            </label>
            <label class="campo">
              <span>Solicitudes simultáneas</span>
              <input type="number" name="solicitudes" min="2" max="20" value={@datos.solicitudes} />
            </label>
            <label class="campo">
              <span>Cantidad por solicitud</span>
              <input type="number" name="cantidad" min="1" value={@datos.cantidad} />
            </label>
            <label class="campo campo-ancho casilla">
              <input type="checkbox" name="devolver" value="true" checked />
              <span>Al terminar, cancelar las necesidades de prueba (el recurso vuelve al centro)</span>
            </label>
          </div>
          <p class="previa">
            Hay <strong>{@datos.disponible}</strong>
            de {texto(@prueba["categoria"])} en {@datos.zona}.
            Se pedirán {@datos.solicitudes} × {@datos.cantidad} = <strong>{@datos.solicitudes * @datos.cantidad}</strong>: como máximo se pueden
            confirmar <strong>{@datos.maximo}</strong>.
          </p>
          <button type="submit" class="boton boton-alerta">Lanzar al mismo tiempo</button>
        </form>
      </.tarjeta>
    </div>

    <.tarjeta :if={@conflicto && @conflicto[:error]} titulo="No se pudo lanzar">
      <p class="texto-alerta">{@conflicto.error}</p>
    </.tarjeta>

    <div :if={@conflicto && !@conflicto[:error]} class="resultado-conflicto">
      <div class="indicadores">
        <.indicador
          etiqueta="Había"
          valor={@conflicto.antes}
          detalle={"#{texto(@conflicto.categoria)} en #{@conflicto.zona}"}
        />
        <.indicador
          etiqueta="Se pidieron"
          valor={@conflicto.solicitudes * @conflicto.cantidad}
          detalle={"#{@conflicto.solicitudes} × #{@conflicto.cantidad}"}
        />
        <.indicador etiqueta="Confirmadas" valor={@conflicto.confirmadas} tono="bien" />
        <.indicador
          etiqueta="Rechazadas"
          valor={length(@conflicto.resultados) - @conflicto.confirmadas}
          tono="alerta"
        />
        <.indicador etiqueta="Quedó" valor={@conflicto.despues} detalle="nunca negativo" />
        <.indicador
          :if={@conflicto.devolver}
          etiqueta="Tras cancelar"
          valor={@conflicto.final}
          detalle="se devolvió lo reservado"
        />
      </div>
      <.tarjeta titulo="Resultado de cada proceso">
        <ul class="lista resultados">
          <li
            :for={resultado <- @conflicto.resultados}
            class={if resultado.ok, do: "ok", else: "error"}
          >
            <strong>{resultado.id}</strong> {if resultado.ok, do: "confirmada", else: "rechazada"}: {resultado.texto}
          </li>
        </ul>
      </.tarjeta>
    </div>
    """
  end

  defp contenido(%{seccion: "actividad"} = assigns) do
    ~H"""
    <h2>Mi actividad <small><code>show_activity</code></small></h2>
    <.tarjeta>
      <.vacio :if={@datos.eventos == []} texto="Sin actividad todavía." />
      <table :if={@datos.eventos != []}>
        <thead>
          <tr>
            <th>Fecha</th><th>Comando</th><th>Detalle</th><th>Resultado</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={evento <- @datos.eventos}>
            <td><small>{evento.fecha}</small></td>
            <td><code>{evento.accion}</code></td>
            <td>{evento.detalle}</td>
            <td><.insignia valor={evento.resultado} /></td>
          </tr>
        </tbody>
      </table>
      <p class="nota">
        La Bitácora (un proceso con <code>spawn</code>, <code>send</code>
        y <code>receive</code>) guarda cada comando en <code>actividad.txt</code>, también los denegados.
      </p>
    </.tarjeta>
    """
  end

  # ---------- Piezas de las secciones ----------

  attr :estado, :map, default: nil

  defp estado_zona(%{estado: nil} = assigns) do
    ~H"""
    <.tarjeta><.vacio texto="La zona todavía no está registrada." /></.tarjeta>
    """
  end

  defp estado_zona(assigns) do
    ~H"""
    <div class="indicadores">
      <.indicador
        etiqueta="Nivel"
        valor={texto(@estado.zona.nivel)}
        tono={"nivel-#{@estado.zona.nivel}"}
      />
      <.indicador
        etiqueta="Personas afectadas"
        valor={@estado.estadisticas.personas_afectadas}
        detalle="acumulado (recursivo)"
      />
      <.indicador
        etiqueta="Sectores"
        valor={@estado.estadisticas.sectores}
        detalle={"#{@estado.estadisticas.puntos_atencion} puntos de atención"}
      />
      <.indicador etiqueta="Albergues" valor={length(@estado.albergues)} />
      <.indicador etiqueta="Necesidades" valor={length(@estado.necesidades)} />
      <.indicador
        etiqueta="Personas / mascotas"
        valor={"#{length(@estado.personas)} / #{length(@estado.mascotas)}"}
      />
    </div>
    <div class="rejilla">
      <.tarjeta titulo="Sectores">
        <.vacio :if={@estado.zona.sectores == []} texto="Sin sectores." />
        <ul class="lista">
          <li :for={sector <- @estado.zona.sectores}>
            <strong>{sector.codigo}</strong> {sector.nombre} <.insignia valor={sector.nivel} />
            <ul :if={sector.puntos != []}>
              <li :for={punto <- sector.puntos}>
                Punto {punto.codigo}: {punto.nombre} ({punto.personas_afectadas} personas)
              </li>
            </ul>
          </li>
        </ul>
      </.tarjeta>
      <.tarjeta titulo="Recursos en sus centros">
        <.vacio :if={@estado.recursos == []} texto="Sin recursos en esta zona." />
        <ul class="lista">
          <li :for={recurso <- @estado.recursos}>
            {recurso.codigo} {recurso.nombre}: <strong>{recurso.total}</strong> {recurso.unidad}
          </li>
        </ul>
      </.tarjeta>
      <.tarjeta titulo="Necesidades de la zona">
        <.vacio :if={@estado.necesidades == []} texto="Sin necesidades." />
        <ul class="lista">
          <li :for={necesidad <- @estado.necesidades}>
            {necesidad.id}
            <.insignia valor={necesidad.prioridad} /> {texto(necesidad.tipo)} {necesidad.asignado}/{necesidad.cantidad}
            <.insignia valor={necesidad.estado} />
          </li>
        </ul>
      </.tarjeta>
      <.tarjeta titulo="Albergues de la zona">
        <.vacio :if={@estado.albergues == []} texto="Sin albergues." />
        <div :for={albergue <- @estado.albergues} class="fila-albergue">
          <span>{albergue.codigo} · {albergue.nombre}</span>
          <.barra porcentaje={Albergue.porcentaje(albergue)} />
          <span class="num">{Albergue.ocupacion(albergue)}/{albergue.capacidad}</span>
        </div>
      </.tarjeta>
    </div>
    """
  end

  attr :seccion, :string, required: true
  attr :sesion, :map, required: true
  attr :opciones, :map, required: true

  defp formularios(assigns) do
    formularios = Formularios.de(assigns.seccion)

    assigns =
      assign(assigns,
        permitidos: Enum.filter(formularios, fn f -> permitido?(assigns.sesion, f.comando) end),
        bloqueados: Enum.reject(formularios, fn f -> permitido?(assigns.sesion, f.comando) end)
      )

    ~H"""
    <h3 :if={@permitidos != []}>Registrar y actualizar</h3>
    <div class="formularios">
      <.formulario
        :for={formulario <- @permitidos}
        formulario={formulario}
        seccion={@seccion}
        opciones={@opciones}
      />
    </div>
    <p :if={@bloqueados != []} class="nota">
      Tu tipo de usuario ({texto(@sesion.tipo)}) no puede usar:
      <code :for={formulario <- @bloqueados}>{formulario.comando}</code>
    </p>
    """
  end

  attr :mapa, :map, required: true
  attr :vacio, :string, required: true

  defp conteo(assigns) do
    ~H"""
    <.vacio :if={@mapa == %{}} texto={@vacio} />
    <ul :if={@mapa != %{}} class="conteo">
      <li :for={
        {clave, cantidad} <- Enum.sort_by(@mapa, fn {_clave, cantidad} -> cantidad end, :desc)
      }>
        <.insignia valor={clave} /> <strong>{cantidad}</strong>
      </li>
    </ul>
    """
  end

  # connect y help son públicos: no están en la tabla de permisos
  defp permitido?(_sesion, comando) when comando in ["connect", "help"], do: true
  defp permitido?(sesion, comando), do: puede?(sesion, comando)

  defp destino({:zona, _codigo}), do: ""
  defp destino({tipo, codigo}), do: "→ #{texto(tipo)} #{codigo}"
  defp destino(_otro), do: ""
end
