defmodule Emergencias.Comandos.Personas do
  @moduledoc """
  Comandos de personas, familias, mensajes y mascotas.

  El despachador de comandos (Integrante 1) separa la línea en palabras y, si el
  comando está en `comandos/0`, llama a `ejecutar/3` con:

  - `comando`: el nombre, por ejemplo `"report_person"`.
  - `argumentos`: lista de textos en orden; las opciones van como `"clave=valor"`.
  - `usuario`: quien está conectado; queda como remitente de los mensajes.

  Retorna `{:ok, texto}` con lo que se le muestra al usuario, o `{:error, razon}`. Los
  permisos y la regla de zona del coordinador los revisa el despachador antes de
  llamar; para eso `Personas` ofrece `zona_de/1`, `zona_de_familia/1` y
  `zona_de_mensaje/1`, y `Mascotas` ofrece `zona_de/1`.
  - Integrante 3: personas, familias, mensajes y mascotas
  """

  alias Emergencias.Mascotas
  alias Emergencias.Personas

  @comandos [
    "report_person",
    "find_person",
    "update_person_status",
    "person_history",
    "register_family",
    "add_family_member",
    "send_family_message",
    "list_family_messages",
    "mark_message",
    "report_pet",
    "list_pets",
    "match_pets",
    "reject_match",
    "confirm_match"
  ]

  @filtros_de_personas ["documento", "nombre", "zona", "estado"]
  @filtros_de_mascotas ["especie", "zona", "estado"]

  @doc "Nombres de los comandos de personas y mascotas."
  @spec comandos() :: [String.t()]
  def comandos, do: @comandos

  @doc "Ejecuta un comando de personas o mascotas (ver la documentación del módulo)."
  @spec ejecutar(String.t(), [String.t()], String.t()) :: {:ok, String.t()} | {:error, atom()}
  def ejecutar(comando, argumentos, usuario)

  # ========== Personas ==========

  # report_person documento nombre zona [estado] [edad=]
  def ejecutar("report_person", [documento, nombre, zona | resto], _usuario) do
    {estado, opciones} = estado_y_opciones(resto)

    with {:ok, edad} <- edad(opcion(opciones, "edad")),
         {:ok, persona} <- Personas.registrar(documento, nombre, zona, estado, edad) do
      {:ok,
       "Persona #{persona.documento} (#{persona.nombre}) reportada en la zona #{persona.zona} con estado #{persona.estado}."}
    end
  end

  # find_person [documento] o [nombre=] [zona=] [estado=]
  def ejecutar("find_person", argumentos, _usuario) do
    with {:ok, filtros} <- filtros_de_busqueda(argumentos) do
      lineas = Enum.map(Personas.buscar(filtros), fn persona -> linea_de_persona(persona) end)
      {:ok, texto(lineas, "No se encontraron personas.")}
    end
  end

  # update_person_status documento estado [detalle...]
  def ejecutar("update_person_status", [documento, estado | detalle], _usuario) do
    with {:ok, persona} <- Personas.actualizar_estado(documento, estado, Enum.join(detalle, " ")) do
      {:ok, "La persona #{persona.documento} ahora está #{persona.estado}."}
    end
  end

  # person_history documento
  def ejecutar("person_history", [documento], _usuario) do
    with {:ok, entradas} <- Personas.historial(documento) do
      lineas = Enum.map(entradas, fn entrada -> linea_de_historial(entrada) end)
      {:ok, texto(["Historial de #{documento}:" | lineas], "")}
    end
  end

  # ========== Familias y mensajes ==========

  # register_family nombre zona
  def ejecutar("register_family", [nombre, zona], _usuario) do
    with {:ok, familia} <- Personas.registrar_familia(nombre, zona) do
      {:ok, "Familia #{familia.codigo} (#{familia.nombre}) registrada en la zona #{zona}."}
    end
  end

  # add_family_member familia documento
  def ejecutar("add_family_member", [codigo, documento], _usuario) do
    with {:ok, familia} <- Personas.agregar_miembro(codigo, documento) do
      {:ok,
       "La persona #{documento} es miembro de la familia #{familia.codigo}. Miembros: #{MapSet.size(familia.miembros)}."}
    end
  end

  # send_family_message documento "texto"  o  familia=F001 "texto"
  def ejecutar("send_family_message", [destino, contenido], usuario) do
    with {:ok, destino} <- destino_de_mensaje(destino),
         {:ok, mensaje} <- Personas.enviar_mensaje(usuario, destino, contenido) do
      {:ok, "Mensaje #{mensaje.id} enviado a #{mensaje.destino_id}."}
    end
  end

  # list_family_messages documento  o  familia=F001
  def ejecutar("list_family_messages", [destino], _usuario) do
    with {:ok, destino} <- destino_de_mensaje(destino),
         {:ok, mensajes} <- Personas.listar_mensajes(destino) do
      lineas = Enum.map(mensajes, fn mensaje -> linea_de_mensaje(mensaje) end)
      {:ok, texto(lineas, "No hay mensajes.")}
    end
  end

  # mark_message mensaje estado
  def ejecutar("mark_message", [id, estado], _usuario) do
    with {:ok, mensaje} <- Personas.marcar_mensaje(id, estado) do
      {:ok, "El mensaje #{mensaje.id} quedó #{mensaje.estado}."}
    end
  end

  # ========== Mascotas ==========

  # report_pet lost|found especie nombre color tamano zona contacto [caracteristicas...]
  def ejecutar(
        "report_pet",
        [tipo, especie, nombre, color, tamano, zona, contacto | caracteristicas],
        _usuario
      ) do
    with {:ok, tipo} <- tipo_de_reporte(tipo),
         {:ok, reporte} <-
           Mascotas.registrar(
             tipo,
             especie,
             nombre,
             color,
             tamano,
             zona,
             contacto,
             Enum.join(caracteristicas, " ")
           ) do
      {:ok,
       "Reporte #{reporte.id} (#{reporte.tipo}) registrado: #{reporte.especie} #{reporte.nombre}."}
    end
  end

  # list_pets [especie=] [zona=] [estado=]
  def ejecutar("list_pets", opciones, _usuario) do
    with {:ok, filtros} <- filtros(opciones, @filtros_de_mascotas) do
      lineas = Enum.map(Mascotas.listar(filtros), fn reporte -> linea_de_reporte(reporte) end)
      {:ok, texto(lineas, "No hay reportes de mascotas.")}
    end
  end

  # match_pets
  def ejecutar("match_pets", [], _usuario) do
    with {:ok, pares} <- Mascotas.buscar_coincidencias() do
      lineas = Enum.map(pares, fn par -> linea_de_par(par) end)
      {:ok, texto(lineas, "No hay coincidencias nuevas.")}
    end
  end

  # reject_match perdida encontrada
  def ejecutar("reject_match", [perdida, encontrada], _usuario) do
    with {:ok, par} <- Mascotas.rechazar(perdida, encontrada) do
      {:ok,
       "Coincidencia rechazada: #{par.perdida.id} y #{par.encontrada.id} vuelven a estar activas."}
    end
  end

  # confirm_match perdida encontrada
  def ejecutar("confirm_match", [perdida, encontrada], _usuario) do
    with {:ok, par} <- Mascotas.confirmar(perdida, encontrada) do
      {:ok,
       "Coincidencia confirmada: #{par.perdida.id} y #{par.encontrada.id} quedaron resueltas. Contacto: #{par.perdida.contacto} y #{par.encontrada.contacto}."}
    end
  end

  # Un comando conocido con argumentos que no encajan, o un comando que no es de este módulo
  def ejecutar(comando, _argumentos, _usuario) do
    if Enum.member?(@comandos, comando) do
      {:error, :argumentos_invalidos}
    else
      {:error, :comando_desconocido}
    end
  end

  # ========== Ayudas para leer los argumentos ==========

  # Convierte un texto a entero; si no es un número exacto, es un error
  defp entero(texto) do
    case Integer.parse(texto) do
      {numero, ""} -> {:ok, numero}
      _otro -> {:error, :numero_invalido}
    end
  end

  # La edad es opcional: sin la opción vale 0
  defp edad(nil), do: {:ok, 0}
  defp edad(texto), do: entero(texto)

  # Busca "clave=valor" en la lista y devuelve el valor, o nil si no está (recursiva)
  defp opcion([], _clave), do: nil

  defp opcion([head | tail], clave) do
    case String.split(head, "=") do
      [nombre, valor] when nombre == clave -> valor
      _otra -> opcion(tail, clave)
    end
  end

  # En report_person el estado es una palabra suelta y la edad una opción.
  # Si lo primero que sobra tiene "=", no hay estado y se usa el de por defecto.
  defp estado_y_opciones([]), do: {:sin_informacion, []}

  defp estado_y_opciones([head | tail] = todo) do
    if String.contains?(head, "=") do
      {:sin_informacion, todo}
    else
      {head, tail}
    end
  end

  # find_person acepta un documento suelto o una lista de filtros "clave=valor"
  defp filtros_de_busqueda([documento]) do
    if String.contains?(documento, "=") do
      filtros([documento], @filtros_de_personas)
    else
      {:ok, [{"documento", documento}]}
    end
  end

  defp filtros_de_busqueda(opciones), do: filtros(opciones, @filtros_de_personas)

  # Caso base: no quedan opciones por convertir
  defp filtros([], _validas), do: {:ok, []}

  # Caso recursivo: convierte la primera opción en filtro y sigue con el resto
  defp filtros([head | tail], validas) do
    with {:ok, filtro} <- filtro(head, validas),
         {:ok, resto} <- filtros(tail, validas) do
      {:ok, [filtro | resto]}
    end
  end

  defp filtro(texto, validas) do
    case String.split(texto, "=") do
      [clave, valor] ->
        if Enum.member?(validas, clave),
          do: {:ok, {clave, valor}},
          else: {:error, :opcion_invalida}

      _otro ->
        {:error, :opcion_invalida}
    end
  end

  # "familia=F001" es una familia; cualquier otro texto es el documento de una persona
  defp destino_de_mensaje(texto) do
    case String.split(texto, "=") do
      ["familia", codigo] -> {:ok, {:familia, codigo}}
      [documento] -> {:ok, {:persona, documento}}
      _otro -> {:error, :destino_invalido}
    end
  end

  defp tipo_de_reporte("lost"), do: {:ok, :perdida}
  defp tipo_de_reporte("found"), do: {:ok, :encontrada}
  defp tipo_de_reporte(_otro), do: {:error, :tipo_invalido}

  # Une las líneas con saltos de línea; si no hay líneas, devuelve el mensaje
  defp texto([], mensaje), do: mensaje
  defp texto(lineas, _mensaje), do: Enum.join(lineas, "\n")

  # ========== Ayudas para mostrar los resultados ==========

  defp linea_de_persona(persona) do
    familia = if persona.familia, do: persona.familia, else: "sin familia"

    "#{persona.documento} | #{persona.nombre} | zona #{persona.zona} | #{persona.estado} | edad #{persona.edad} | #{familia}"
  end

  defp linea_de_historial(entrada) do
    anterior = if entrada.anterior, do: entrada.anterior, else: "-"
    "#{entrada.fecha} | #{anterior} -> #{entrada.nuevo} | #{entrada.detalle}"
  end

  defp linea_de_mensaje(mensaje) do
    "#{mensaje.id} | #{mensaje.fecha} | de #{mensaje.remitente} | #{mensaje.estado} | #{mensaje.contenido}"
  end

  defp linea_de_reporte(reporte) do
    "#{reporte.id} | #{reporte.tipo} | #{reporte.especie} #{reporte.nombre} | #{reporte.color} | #{reporte.tamano} | zona #{reporte.zona} | #{reporte.estado}"
  end

  defp linea_de_par(par) do
    "#{par.perdida.id} (perdida) <-> #{par.encontrada.id} (encontrada): #{par.puntaje} puntos"
  end
end
