defmodule Emergencias.Personas do
  @moduledoc """
  GenServer de personas afectadas, familias y mensajes entre familiares.

  Un solo proceso guarda el estado y atiende los mensajes uno a uno. Por eso
  validar, modificar, guardar y responder ocurren dentro del mismo `handle_call`, y
  dos solicitudes simultáneas nunca se mezclan: si dos usuarios reportan el mismo
  documento a la vez, solo uno lo logra y el otro recibe `:ya_existe`.

  Nivel 2 del árbol: solo llama a `Zonas`. `Albergues` y `Necesidades` llaman a este
  módulo, así que nunca debe llamarlos a ellos (si dos servidores se llamaran entre sí
  quedarían esperándose).

  Estado del servidor:

      %{
        personas: %{documento => %Persona{}},
        familias: %{"F001" => %Familia{}},
        mensajes: %{"MSG001" => %Mensaje{}},
        historial: [entrada],      # la más reciente primero
        siguiente_persona: 1, siguiente_familia: 1, siguiente_mensaje: 1
      }

  Archivos: `personas.txt`, `historial_personas.txt` (solo se agregan líneas),
  `familias.txt` y `mensajes.txt`.
  - Integrante 3: personas
  """

  use GenServer

  alias Emergencias.Personas.Familia
  alias Emergencias.Personas.Mensaje
  alias Emergencias.Personas.Persona
  alias Emergencias.Persistencia
  alias Emergencias.Validaciones
  alias Emergencias.Zonas

  @archivo_personas "personas.txt"
  @archivo_historial "historial_personas.txt"
  @archivo_familias "familias.txt"
  @archivo_mensajes "mensajes.txt"

  @type destino :: {:persona, String.t()} | {:familia, String.t()}

  # ========== API del cliente ==========

  @doc "Inicia el servidor registrado con el nombre del módulo."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opciones) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registra una persona (`report_person`). El estado por defecto es `:sin_informacion`
  y solo se acepta `:sin_informacion`, `:reportada`, `:localizada` o `:trasladada`:
  a `:en_albergue` se entra con `Albergues.ingresar/2`. El estado puede llegar como
  átomo o como texto.
  """
  @spec registrar(String.t(), String.t(), String.t(), atom() | String.t(), integer()) ::
          {:ok, Persona.t()} | {:error, atom()}
  def registrar(documento, nombre, zona, estado \\ :sin_informacion, edad \\ 0) do
    GenServer.call(__MODULE__, {:registrar, documento, nombre, zona, estado, edad})
  end

  @doc "Busca una persona por documento."
  @spec obtener(String.t()) :: {:ok, Persona.t()} | {:error, :persona_no_existe}
  def obtener(documento), do: GenServer.call(__MODULE__, {:obtener, documento})

  @doc "Indica si existe una persona con ese documento."
  @spec existe?(String.t()) :: boolean()
  def existe?(documento), do: GenServer.call(__MODULE__, {:existe, documento})

  @doc """
  Busca personas (`find_person`). Los filtros son pares `{campo, valor}` con los
  campos `documento`, `nombre` (basta un fragmento), `zona` y `estado`, por ejemplo
  `[nombre: "ana", zona: "centro"]`. Sin filtros devuelve todas, ordenadas por id.
  """
  @spec buscar(list()) :: [Persona.t()]
  def buscar(filtros \\ []), do: GenServer.call(__MODULE__, {:buscar, filtros})

  @doc """
  Cambia el estado de una persona (`update_person_status`). Rechaza `:en_albergue`
  como origen y como destino con `{:error, :usar_albergue}`: a un albergue se entra
  con `register_entry` y se sale con `register_exit`.
  """
  @spec actualizar_estado(String.t(), atom() | String.t(), String.t()) ::
          {:ok, Persona.t()} | {:error, atom()}
  def actualizar_estado(documento, estado, detalle \\ "") do
    GenServer.call(__MODULE__, {:actualizar_estado, documento, estado, detalle})
  end

  @doc """
  Cambia el estado de una persona sin la restricción de `actualizar_estado/3`.
  Lo usa `Albergues` para entrar (`:en_albergue`) y salir (`:trasladada`).
  """
  @spec cambiar_estado(String.t(), atom() | String.t(), String.t()) ::
          {:ok, Persona.t()} | {:error, atom()}
  def cambiar_estado(documento, estado, detalle \\ "") do
    GenServer.call(__MODULE__, {:cambiar_estado, documento, estado, detalle})
  end

  @doc "Historial de cambios de estado de una persona (`person_history`), del más antiguo al más reciente."
  @spec historial(String.t()) :: {:ok, [map()]} | {:error, :persona_no_existe}
  def historial(documento), do: GenServer.call(__MODULE__, {:historial, documento})

  @doc "Zona de una persona, para la regla de zona del coordinador."
  @spec zona_de(String.t()) :: {:ok, String.t()} | {:error, :persona_no_existe}
  def zona_de(documento), do: GenServer.call(__MODULE__, {:zona_de, documento})

  @doc "Registra una familia (`register_family`) con código consecutivo (`F001`)."
  @spec registrar_familia(String.t(), String.t()) :: {:ok, Familia.t()} | {:error, atom()}
  def registrar_familia(nombre, zona) do
    GenServer.call(__MODULE__, {:registrar_familia, nombre, zona})
  end

  @doc "Agrega una persona (por documento) a una familia (`add_family_member`)."
  @spec agregar_miembro(String.t(), String.t()) :: {:ok, Familia.t()} | {:error, atom()}
  def agregar_miembro(codigo_familia, documento) do
    GenServer.call(__MODULE__, {:agregar_miembro, codigo_familia, documento})
  end

  @doc "Busca una familia por código."
  @spec obtener_familia(String.t()) :: {:ok, Familia.t()} | {:error, :familia_no_existe}
  def obtener_familia(codigo), do: GenServer.call(__MODULE__, {:obtener_familia, codigo})

  @doc "Indica si existe una familia con ese código."
  @spec existe_familia?(String.t()) :: boolean()
  def existe_familia?(codigo), do: GenServer.call(__MODULE__, {:existe_familia, codigo})

  @doc "Zona de una familia, para la regla de zona del coordinador."
  @spec zona_de_familia(String.t()) :: {:ok, String.t()} | {:error, :familia_no_existe}
  def zona_de_familia(codigo), do: GenServer.call(__MODULE__, {:zona_de_familia, codigo})

  @doc "Envía un mensaje a una persona o a una familia (`send_family_message`)."
  @spec enviar_mensaje(String.t(), destino(), String.t()) ::
          {:ok, Mensaje.t()} | {:error, atom()}
  def enviar_mensaje(remitente, destino, contenido) do
    GenServer.call(__MODULE__, {:enviar_mensaje, remitente, destino, contenido})
  end

  @doc """
  Lista los mensajes de un destino (`list_family_messages`). Para una persona incluye
  también los de su familia.
  """
  @spec listar_mensajes(destino()) :: {:ok, [Mensaje.t()]} | {:error, atom()}
  def listar_mensajes(destino), do: GenServer.call(__MODULE__, {:listar_mensajes, destino})

  @doc "Cambia un mensaje entre `:entregado` y `:pendiente` (`mark_message`)."
  @spec marcar_mensaje(String.t(), atom() | String.t()) :: {:ok, Mensaje.t()} | {:error, atom()}
  def marcar_mensaje(id, estado), do: GenServer.call(__MODULE__, {:marcar_mensaje, id, estado})

  @doc "Zona del destinatario de un mensaje, para la regla de zona del coordinador."
  @spec zona_de_mensaje(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def zona_de_mensaje(id), do: GenServer.call(__MODULE__, {:zona_de_mensaje, id})

  # ========== Funciones recursivas (puras: no usan el estado del servidor) ==========

  @doc """
  Se queda con las personas que cumplen todos los filtros.

  Caso base: una lista vacía no tiene personas que filtrar. Caso recursivo: se decide
  por la primera persona y se sigue con el resto.
  """
  @spec filtrar([Persona.t()], list()) :: [Persona.t()]
  def filtrar([], _filtros), do: []

  def filtrar([head | tail], filtros) do
    if cumple?(head, filtros) do
      [head | filtrar(tail, filtros)]
    else
      filtrar(tail, filtros)
    end
  end

  @doc """
  Se queda con las entradas del historial de un documento. Recursiva sobre la lista.
  """
  @spec filtrar_historial([map()], String.t()) :: [map()]
  def filtrar_historial([], _documento), do: []

  def filtrar_historial([head | tail], documento) do
    if head.documento == documento do
      [head | filtrar_historial(tail, documento)]
    else
      filtrar_historial(tail, documento)
    end
  end

  @doc """
  Reúne los mensajes cuyo destino está en la lista `destinos`: la persona y, si
  tiene, su familia. Recursiva sobre la lista de mensajes.
  """
  @spec reunir_mensajes([Mensaje.t()], [destino()]) :: [Mensaje.t()]
  def reunir_mensajes([], _destinos), do: []

  def reunir_mensajes([head | tail], destinos) do
    if Enum.member?(destinos, {head.destino_tipo, head.destino_id}) do
      [head | reunir_mensajes(tail, destinos)]
    else
      reunir_mensajes(tail, destinos)
    end
  end

  @doc """
  Siguiente número de una serie de códigos con prefijo: el mayor sufijo existente más
  uno. Se usa al cargar los archivos para que, después de un reinicio, los códigos
  continúen donde iban. Recursiva con acumulador.

  ## Ejemplos

      iex> Emergencias.Personas.siguiente_numero(["P001", "P007", "P003"], "P")
      8

      iex> Emergencias.Personas.siguiente_numero([], "P")
      1
  """
  @spec siguiente_numero([String.t()], String.t()) :: pos_integer()
  def siguiente_numero(codigos, prefijo), do: mayor_sufijo(codigos, prefijo, 0) + 1

  # Caso base: no quedan códigos, se devuelve el mayor que se vio
  defp mayor_sufijo([], _prefijo, mayor), do: mayor

  # Caso recursivo: se compara el sufijo del primero con el mayor y se sigue
  defp mayor_sufijo([head | tail], prefijo, mayor) do
    numero =
      case Integer.parse(String.replace_prefix(head, prefijo, "")) do
        {n, ""} -> n
        _otro -> 0
      end

    mayor_sufijo(tail, prefijo, max(mayor, numero))
  end

  # Una persona cumple si cumple cada uno de los filtros (recursivo sobre los filtros)
  defp cumple?(_persona, []), do: true

  defp cumple?(persona, [{campo, valor} | tail]) do
    coincide?(persona, "#{campo}", "#{valor}") and cumple?(persona, tail)
  end

  defp coincide?(persona, "documento", valor), do: persona.documento == valor
  defp coincide?(persona, "zona", valor), do: persona.zona == valor
  defp coincide?(persona, "estado", valor), do: "#{persona.estado}" == valor

  defp coincide?(persona, "nombre", valor) do
    String.contains?(String.downcase(persona.nombre), String.downcase(valor))
  end

  # Un filtro desconocido no coincide con nada
  defp coincide?(_persona, _campo, _valor), do: false

  # ========== Callbacks del servidor ==========

  @impl true
  def init(:ok) do
    personas = cargar(@archivo_personas, &Persona.desde_fila/1)
    familias = cargar(@archivo_familias, &Familia.desde_fila/1)
    mensajes = cargar(@archivo_mensajes, &Mensaje.desde_fila/1)
    historial = cargar(@archivo_historial, &Persona.entrada_desde_fila/1)

    estado = %{
      personas: Map.new(personas, fn persona -> {persona.documento, persona} end),
      familias: Map.new(familias, fn familia -> {familia.codigo, familia} end),
      mensajes: Map.new(mensajes, fn mensaje -> {mensaje.id, mensaje} end),
      # El archivo va del más antiguo al más reciente; en memoria va al revés
      historial: Enum.reverse(historial),
      siguiente_persona: siguiente_numero(Enum.map(personas, fn p -> p.id end), "P"),
      siguiente_familia: siguiente_numero(Enum.map(familias, fn f -> f.codigo end), "F"),
      siguiente_mensaje: siguiente_numero(Enum.map(mensajes, fn m -> m.id end), "MSG")
    }

    {:ok, estado}
  end

  @impl true
  def handle_call({:registrar, documento, nombre, zona, estado_inicial, edad}, _from, estado) do
    with :ok <- Persona.validar_documento(documento),
         :ok <- documento_libre(estado.personas, documento),
         :ok <- Validaciones.texto(nombre, :nombre_invalido),
         :ok <- zona_existe(zona),
         :ok <- Validaciones.entero_no_negativo(edad, :edad_invalida),
         {:ok, estado_inicial} <- estado_inicial_valido(estado_inicial),
         persona = %Persona{
           id: formar_codigo("P", estado.siguiente_persona),
           documento: documento,
           nombre: String.trim(nombre),
           edad: edad,
           zona: zona,
           estado: estado_inicial,
           familia: nil
         },
         entrada = nueva_entrada(documento, nil, estado_inicial, "Reporte inicial"),
         nuevo = %{
           estado
           | personas: Map.put(estado.personas, documento, persona),
             historial: [entrada | estado.historial],
             siguiente_persona: estado.siguiente_persona + 1
         },
         :ok <- guardar_personas(nuevo),
         :ok <- guardar_entrada(entrada) do
      {:reply, {:ok, persona}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:obtener, documento}, _from, estado) do
    {:reply, buscar_persona(estado.personas, documento), estado}
  end

  @impl true
  def handle_call({:existe, documento}, _from, estado) do
    {:reply, Map.has_key?(estado.personas, documento), estado}
  end

  @impl true
  def handle_call({:buscar, filtros}, _from, estado) do
    personas =
      estado.personas |> Map.values() |> Enum.sort_by(fn persona -> orden(persona.id) end)

    {:reply, filtrar(personas, filtros), estado}
  end

  @impl true
  def handle_call({:actualizar_estado, documento, destino, detalle}, _from, estado) do
    with {:ok, persona} <- buscar_persona(estado.personas, documento),
         {:ok, destino} <- Validaciones.opcion(destino, Persona.estados(), :estado_invalido),
         :ok <- rechazar_albergue(persona.estado, destino) do
      responder_cambio(estado, persona, destino, detalle)
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:cambiar_estado, documento, destino, detalle}, _from, estado) do
    with {:ok, persona} <- buscar_persona(estado.personas, documento),
         {:ok, destino} <- Validaciones.opcion(destino, Persona.estados(), :estado_invalido) do
      responder_cambio(estado, persona, destino, detalle)
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:historial, documento}, _from, estado) do
    case buscar_persona(estado.personas, documento) do
      {:ok, persona} ->
        entradas = estado.historial |> filtrar_historial(persona.documento) |> Enum.reverse()
        {:reply, {:ok, entradas}, estado}

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:zona_de, documento}, _from, estado) do
    case buscar_persona(estado.personas, documento) do
      {:ok, persona} -> {:reply, {:ok, persona.zona}, estado}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:registrar_familia, nombre, zona}, _from, estado) do
    with :ok <- Validaciones.texto(nombre, :nombre_invalido),
         :ok <- zona_existe(zona),
         familia =
           Familia.crear(formar_codigo("F", estado.siguiente_familia), String.trim(nombre), zona),
         nuevo = %{
           estado
           | familias: Map.put(estado.familias, familia.codigo, familia),
             siguiente_familia: estado.siguiente_familia + 1
         },
         :ok <- guardar_familias(nuevo) do
      {:reply, {:ok, familia}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:agregar_miembro, codigo, documento}, _from, estado) do
    with {:ok, familia} <- buscar_familia(estado.familias, codigo),
         {:ok, persona} <- buscar_persona(estado.personas, documento),
         :ok <- sin_familia(persona),
         {:ok, familia_nueva} <- Familia.agregar_miembro(familia, persona.documento),
         persona_nueva = %{persona | familia: familia.codigo},
         nuevo = %{
           estado
           | familias: Map.put(estado.familias, familia.codigo, familia_nueva),
             personas: Map.put(estado.personas, persona.documento, persona_nueva)
         },
         :ok <- guardar_familias(nuevo),
         :ok <- guardar_personas(nuevo) do
      {:reply, {:ok, familia_nueva}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:obtener_familia, codigo}, _from, estado) do
    {:reply, buscar_familia(estado.familias, codigo), estado}
  end

  @impl true
  def handle_call({:existe_familia, codigo}, _from, estado) do
    {:reply, match?({:ok, _familia}, buscar_familia(estado.familias, codigo)), estado}
  end

  @impl true
  def handle_call({:zona_de_familia, codigo}, _from, estado) do
    case buscar_familia(estado.familias, codigo) do
      {:ok, familia} -> {:reply, {:ok, familia.zona}, estado}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:enviar_mensaje, remitente, destino, contenido}, _from, estado) do
    contenido = limpiar_texto(contenido)

    with :ok <- Validaciones.texto(remitente, :remitente_invalido),
         :ok <- Validaciones.texto(contenido, :contenido_invalido),
         {:ok, tipo, destino_id} <- verificar_destino(estado, destino),
         mensaje = %Mensaje{
           id: formar_codigo("MSG", estado.siguiente_mensaje),
           fecha: ahora(),
           remitente: String.trim(remitente),
           destino_tipo: tipo,
           destino_id: destino_id,
           contenido: contenido,
           estado: :pendiente
         },
         nuevo = %{
           estado
           | mensajes: Map.put(estado.mensajes, mensaje.id, mensaje),
             siguiente_mensaje: estado.siguiente_mensaje + 1
         },
         :ok <- guardar_mensajes(nuevo) do
      {:reply, {:ok, mensaje}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:listar_mensajes, destino}, _from, estado) do
    case verificar_destino(estado, destino) do
      {:ok, tipo, destino_id} ->
        destinos = destinos_visibles(estado, tipo, destino_id)

        mensajes =
          estado.mensajes |> Map.values() |> Enum.sort_by(fn mensaje -> orden(mensaje.id) end)

        {:reply, {:ok, reunir_mensajes(mensajes, destinos)}, estado}

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:marcar_mensaje, id, nuevo_estado}, _from, estado) do
    with {:ok, mensaje} <- buscar_mensaje(estado.mensajes, id),
         {:ok, nuevo_estado} <-
           Validaciones.opcion(nuevo_estado, Mensaje.estados(), :estado_invalido),
         {:ok, actualizado} <- Mensaje.cambiar_estado(mensaje, nuevo_estado),
         nuevo = %{estado | mensajes: Map.put(estado.mensajes, mensaje.id, actualizado)},
         :ok <- guardar_mensajes(nuevo) do
      {:reply, {:ok, actualizado}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  @impl true
  def handle_call({:zona_de_mensaje, id}, _from, estado) do
    with {:ok, mensaje} <- buscar_mensaje(estado.mensajes, id),
         {:ok, zona} <- zona_del_destino(estado, mensaje.destino_tipo, mensaje.destino_id) do
      {:reply, {:ok, zona}, estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  # ========== Funciones auxiliares privadas ==========

  # Aplica la transición de la tabla, actualiza el estado, guarda y responde.
  # Compartida por actualizar_estado/3 y cambiar_estado/3.
  defp responder_cambio(estado, persona, destino, detalle) do
    with :ok <- Persona.puede_pasar(persona.estado, destino),
         actualizada = %{persona | estado: destino},
         entrada = nueva_entrada(persona.documento, persona.estado, destino, detalle),
         nuevo = %{
           estado
           | personas: Map.put(estado.personas, persona.documento, actualizada),
             historial: [entrada | estado.historial]
         },
         :ok <- guardar_personas(nuevo),
         :ok <- guardar_entrada(entrada) do
      {:reply, {:ok, actualizada}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp nueva_entrada(documento, anterior, nuevo, detalle) do
    %{
      fecha: ahora(),
      documento: documento,
      anterior: anterior,
      nuevo: nuevo,
      detalle: limpiar_texto("#{detalle}")
    }
  end

  defp buscar_persona(personas, documento) do
    case Map.get(personas, documento) do
      nil -> {:error, :persona_no_existe}
      persona -> {:ok, persona}
    end
  end

  # Los códigos F001 y MSG001 los genera el sistema en mayúscula; se acepta "f001"
  defp buscar_familia(familias, codigo) do
    case Map.get(familias, normalizar_codigo(codigo)) do
      nil -> {:error, :familia_no_existe}
      familia -> {:ok, familia}
    end
  end

  defp buscar_mensaje(mensajes, id) do
    case Map.get(mensajes, normalizar_codigo(id)) do
      nil -> {:error, :mensaje_no_existe}
      mensaje -> {:ok, mensaje}
    end
  end

  defp normalizar_codigo(codigo) when is_binary(codigo),
    do: codigo |> String.trim() |> String.upcase()

  defp normalizar_codigo(otro), do: otro

  defp documento_libre(personas, documento) do
    if Map.has_key?(personas, documento), do: {:error, :ya_existe}, else: :ok
  end

  defp zona_existe(zona) do
    with :ok <- Validaciones.texto(zona, :zona_invalida) do
      if Zonas.existe?(zona), do: :ok, else: {:error, :zona_no_existe}
    end
  end

  # No se puede reportar a alguien directamente como en_albergue ni reunificada
  defp estado_inicial_valido(estado_inicial) do
    with {:ok, estado_inicial} <-
           Validaciones.opcion(estado_inicial, Persona.estados(), :estado_invalido) do
      if Enum.member?(Persona.estados_iniciales(), estado_inicial) do
        {:ok, estado_inicial}
      else
        {:error, :estado_inicial_invalido}
      end
    end
  end

  # Para update_person_status: en_albergue solo lo maneja Albergues
  defp rechazar_albergue(:en_albergue, _destino), do: {:error, :usar_albergue}
  defp rechazar_albergue(_origen, :en_albergue), do: {:error, :usar_albergue}
  defp rechazar_albergue(_origen, _destino), do: :ok

  defp sin_familia(%Persona{familia: nil}), do: :ok
  defp sin_familia(%Persona{}), do: {:error, :ya_tiene_familia}

  # Verifica que el destinatario exista y devuelve su identificador tal como se guarda
  defp verificar_destino(estado, {:persona, documento}) do
    with {:ok, persona} <- buscar_persona(estado.personas, documento) do
      {:ok, :persona, persona.documento}
    end
  end

  defp verificar_destino(estado, {:familia, codigo}) do
    with {:ok, familia} <- buscar_familia(estado.familias, codigo) do
      {:ok, :familia, familia.codigo}
    end
  end

  defp verificar_destino(_estado, _otro), do: {:error, :destino_invalido}

  # Una persona ve sus mensajes y los de su familia; una familia solo los suyos
  defp destinos_visibles(estado, :persona, documento) do
    case Map.fetch!(estado.personas, documento).familia do
      nil -> [{:persona, documento}]
      codigo -> [{:persona, documento}, {:familia, codigo}]
    end
  end

  defp destinos_visibles(_estado, :familia, codigo), do: [{:familia, codigo}]

  defp zona_del_destino(estado, :persona, documento) do
    with {:ok, persona} <- buscar_persona(estado.personas, documento), do: {:ok, persona.zona}
  end

  defp zona_del_destino(estado, :familia, codigo) do
    with {:ok, familia} <- buscar_familia(estado.familias, codigo), do: {:ok, familia.zona}
  end

  # Para ordenar códigos como P999 y P1000 por su número y no letra por letra, se
  # compara primero el largo y luego el texto
  defp orden(codigo), do: {String.length(codigo), codigo}

  # Códigos con prefijo y tres dígitos: P001, F001, MSG001
  defp formar_codigo(prefijo, numero) do
    prefijo <> String.pad_leading(Integer.to_string(numero), 3, "0")
  end

  # Los textos libres no pueden llevar ";" ni saltos de línea (romperían el archivo)
  defp limpiar_texto(texto) when is_binary(texto), do: Persistencia.limpiar(texto)
  defp limpiar_texto(otro), do: otro

  defp ahora, do: "#{NaiveDateTime.local_now()}"

  # Carga un archivo y descarta las líneas dañadas en lugar de fallar
  defp cargar(archivo, convertir) do
    archivo
    |> Persistencia.cargar()
    |> Enum.map(fn linea -> convertir.(Persistencia.separar(linea)) end)
    |> Enum.flat_map(fn
      {:ok, elemento} -> [elemento]
      {:error, _razon} -> []
    end)
  end

  defp guardar_personas(estado) do
    lineas =
      estado.personas
      |> Map.values()
      |> Enum.sort_by(fn persona -> orden(persona.id) end)
      |> Enum.map(fn persona -> Persistencia.unir(Persona.a_fila(persona)) end)

    Persistencia.guardar(@archivo_personas, lineas)
  end

  defp guardar_familias(estado) do
    lineas =
      estado.familias
      |> Map.values()
      |> Enum.sort_by(fn familia -> orden(familia.codigo) end)
      |> Enum.map(fn familia -> Persistencia.unir(Familia.a_fila(familia)) end)

    Persistencia.guardar(@archivo_familias, lineas)
  end

  defp guardar_mensajes(estado) do
    lineas =
      estado.mensajes
      |> Map.values()
      |> Enum.sort_by(fn mensaje -> orden(mensaje.id) end)
      |> Enum.map(fn mensaje -> Persistencia.unir(Mensaje.a_fila(mensaje)) end)

    Persistencia.guardar(@archivo_mensajes, lineas)
  end

  # El historial solo crece: se agrega una línea al final del archivo
  defp guardar_entrada(entrada) do
    Persistencia.agregar(@archivo_historial, Persistencia.unir(Persona.entrada_a_fila(entrada)))
  end
end
