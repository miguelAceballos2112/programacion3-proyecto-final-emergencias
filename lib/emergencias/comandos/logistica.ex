defmodule Emergencias.Comandos.Logistica do
  @moduledoc """
  Comandos de logística: centros, recursos, necesidades y albergues.

  El despachador de comandos (Integrante 1) separa la línea en palabras y, si el
  comando está en `comandos/0`, llama a `ejecutar/3` con:

  - `comando`: el nombre, por ejemplo `"register_need"`.
  - `argumentos`: lista de textos en orden; las opciones van como `"clave=valor"`.
  - `usuario`: quien está conectado; queda como responsable de las necesidades.

  Retorna `{:ok, texto}` con lo que se le muestra al usuario, o `{:error, razon}`. Los
  permisos y la regla de zona del coordinador los revisa el despachador antes de
  llamar; para eso cada servidor ofrece `zona_de/1`.
  - Integrante 2: logística
  """

  alias Emergencias.Albergues
  alias Emergencias.Albergues.Albergue
  alias Emergencias.Necesidades
  alias Emergencias.Recursos
  alias Emergencias.Recursos.Recurso

  @comandos [
    "register_center",
    "register_resource",
    "list_resources",
    "add_stock",
    "remove_stock",
    "list_movements",
    "transfer_resource",
    "register_need",
    "list_needs",
    "assign_resource",
    "update_need_status",
    "cancel_need",
    "next_need",
    "pending_needs",
    "critical_resources",
    "register_shelter",
    "check_shelter",
    "shelter_report",
    "register_entry",
    "register_exit"
  ]

  @filtros_de_necesidades ["zona", "tipo", "prioridad", "estado"]

  @doc "Nombres de los comandos de logística."
  def comandos, do: @comandos

  @doc "Ejecuta un comando de logística (ver la documentación del módulo)."
  def ejecutar(comando, argumentos, usuario)

  # ========== Centros y recursos ==========

  # register_center codigo nombre tipo zona
  def ejecutar("register_center", [codigo, nombre, tipo, zona], _usuario) do
    with {:ok, centro} <- Recursos.registrar_centro(codigo, nombre, tipo, zona) do
      {:ok, "Centro #{centro.codigo} (#{centro.tipo}) registrado en la zona #{centro.zona}."}
    end
  end

  # register_resource codigo categoria cantidad unidad centro [nombre=]
  def ejecutar(
        "register_resource",
        [codigo, categoria, cantidad, unidad, centro | opciones],
        _usuario
      ) do
    nombre = opcion(opciones, "nombre")

    with {:ok, cantidad} <- entero(cantidad),
         {:ok, recurso} <- Recursos.registrar(codigo, categoria, cantidad, unidad, centro, nombre) do
      {:ok,
       "Recurso #{recurso.codigo} (#{recurso.nombre}) registrado: #{cantidad} #{recurso.unidad} en #{centro}."}
    end
  end

  # list_resources [zona=] [categoria=]
  def ejecutar("list_resources", opciones, _usuario) do
    zona = opcion(opciones, "zona")
    categoria = opcion(opciones, "categoria")

    with {:ok, encabezado} <- encabezado_de_recursos(categoria, zona) do
      zonas = zonas_de_centros()

      lineas =
        Recursos.listar()
        |> Enum.filter(fn recurso -> de_la_categoria?(recurso, categoria) end)
        |> Enum.map(fn recurso -> {recurso, existencias_en(recurso, zona, zonas)} end)
        |> Enum.filter(fn {_recurso, existencias} -> Enum.count(existencias) > 0 end)
        |> Enum.map(fn {recurso, existencias} -> linea_de_recurso(recurso, existencias) end)

      {:ok, texto(encabezado ++ lineas, "No hay recursos.")}
    end
  end

  # add_stock codigo centro cantidad
  def ejecutar("add_stock", [codigo, centro, cantidad], _usuario) do
    with {:ok, cantidad} <- entero(cantidad),
         {:ok, recurso} <- Recursos.entrada(codigo, centro, cantidad) do
      {:ok,
       "Entraron #{cantidad} #{recurso.unidad} de #{codigo} a #{centro}. Hay #{Recurso.disponible(recurso, centro)}."}
    end
  end

  # remove_stock codigo centro cantidad
  def ejecutar("remove_stock", [codigo, centro, cantidad], _usuario) do
    with {:ok, cantidad} <- entero(cantidad),
         {:ok, recurso} <- Recursos.salida(codigo, centro, cantidad) do
      {:ok,
       "Salieron #{cantidad} #{recurso.unidad} de #{codigo} de #{centro}. Quedan #{Recurso.disponible(recurso, centro)}."}
    end
  end

  # list_movements [codigo]
  def ejecutar("list_movements", [], _usuario), do: movimientos(nil)
  def ejecutar("list_movements", [codigo], _usuario), do: movimientos(codigo)

  # transfer_resource codigo origen destino cantidad
  def ejecutar("transfer_resource", [codigo, origen, destino, cantidad], _usuario) do
    with {:ok, cantidad} <- entero(cantidad),
         {:ok, recurso} <- Recursos.transferir(codigo, origen, destino, cantidad) do
      {:ok,
       "Se transfirieron #{cantidad} #{recurso.unidad} de #{codigo} de #{origen} a #{destino}."}
    end
  end

  # ========== Necesidades ==========

  # register_need tipo cantidad prioridad zona descripcion [destino=tipo:codigo]
  def ejecutar(
        "register_need",
        [tipo, cantidad, prioridad, zona, descripcion | opciones],
        usuario
      ) do
    with {:ok, cantidad} <- entero(cantidad),
         {:ok, destino} <- destino(opcion(opciones, "destino")),
         {:ok, necesidad} <-
           Necesidades.registrar(tipo, cantidad, prioridad, zona, descripcion, usuario, destino) do
      {:ok, "Necesidad registrada: #{linea_de_necesidad(necesidad)}"}
    end
  end

  # list_needs [zona=] [tipo=] [prioridad=] [estado=]
  def ejecutar("list_needs", opciones, _usuario) do
    with {:ok, filtros} <- filtros(opciones) do
      {:ok, texto_de_necesidades(Necesidades.listar(filtros))}
    end
  end

  # assign_resource necesidad categoria cantidad
  def ejecutar("assign_resource", [id, categoria, cantidad], _usuario) do
    with {:ok, cantidad} <- entero(cantidad),
         {:ok, necesidad} <- Necesidades.asignar_recurso(id, categoria, cantidad) do
      {:ok,
       "Se asignaron #{cantidad} de #{necesidad.tipo} a #{necesidad.id}: lleva #{necesidad.asignado} de #{necesidad.cantidad} (#{necesidad.estado})."}
    end
  end

  # update_need_status necesidad estado
  def ejecutar("update_need_status", [id, estado], _usuario) do
    with {:ok, necesidad} <- Necesidades.cambiar_estado(id, estado) do
      {:ok, "La necesidad #{necesidad.id} pasó a #{necesidad.estado}."}
    end
  end

  # cancel_need necesidad
  def ejecutar("cancel_need", [id], _usuario) do
    with {:ok, necesidad} <- Necesidades.cancelar(id) do
      {:ok, "La necesidad #{necesidad.id} fue cancelada."}
    end
  end

  # next_need [zona]
  def ejecutar("next_need", [], _usuario), do: siguiente(nil)
  def ejecutar("next_need", [zona], _usuario), do: siguiente(zona)

  # pending_needs
  def ejecutar("pending_needs", [], _usuario) do
    {:ok, texto_de_necesidades(Necesidades.pendientes())}
  end

  # critical_resources
  def ejecutar("critical_resources", [], _usuario) do
    lineas =
      Enum.map(Necesidades.recursos_criticos(), fn critico ->
        "Zona #{critico.zona}, #{critico.categoria}: faltan #{critico.faltante} (se piden #{critico.demanda}, hay #{critico.disponible})"
      end)

    {:ok, texto(lineas, "No hay recursos críticos.")}
  end

  # ========== Albergues ==========

  # register_shelter codigo nombre zona capacidad [ocupacion]
  def ejecutar("register_shelter", [codigo, nombre, zona, capacidad], usuario) do
    ejecutar("register_shelter", [codigo, nombre, zona, capacidad, "0"], usuario)
  end

  def ejecutar("register_shelter", [codigo, nombre, zona, capacidad, ocupacion], _usuario) do
    with {:ok, capacidad} <- entero(capacidad),
         {:ok, ocupacion} <- entero(ocupacion),
         {:ok, albergue} <- Albergues.registrar(codigo, nombre, zona, capacidad, ocupacion) do
      {:ok,
       "Albergue #{albergue.codigo} registrado en la zona #{albergue.zona}: #{ocupacion_de(albergue)}."}
    end
  end

  # check_shelter codigo
  def ejecutar("check_shelter", [codigo], _usuario) do
    with {:ok, estado} <- Albergues.consultar(codigo) do
      albergue = estado.albergue

      recursos =
        Enum.map(estado.recursos, fn recurso ->
          "  #{recurso.codigo} #{recurso.nombre}: #{recurso.cantidad} #{recurso.unidad}"
        end)

      necesidades =
        Enum.map(estado.necesidades, fn necesidad -> "  #{linea_de_necesidad(necesidad)}" end)

      lineas =
        [
          "Albergue #{albergue.codigo} (#{albergue.nombre}), zona #{albergue.zona}",
          "Ocupación: #{ocupacion_de(albergue)}, cupos: #{estado.cupos}",
          "Recursos:"
        ] ++
          si_vacia(recursos, "  ninguno") ++
          ["Necesidades:"] ++ si_vacia(necesidades, "  ninguna")

      {:ok, Enum.join(lineas, "\n")}
    end
  end

  # shelter_report [n]
  def ejecutar("shelter_report", [], usuario), do: ejecutar("shelter_report", ["5"], usuario)

  def ejecutar("shelter_report", [cantidad], _usuario) do
    with {:ok, cantidad} <- entero(cantidad) do
      lineas =
        Enum.map(Albergues.mas_ocupados(cantidad), fn albergue ->
          "#{albergue.codigo} #{albergue.nombre}: #{ocupacion_de(albergue)}"
        end)

      {:ok, texto(lineas, "No hay albergues.")}
    end
  end

  # register_entry albergue documento
  def ejecutar("register_entry", [codigo, documento], _usuario) do
    with {:ok, albergue} <- Albergues.ingresar(codigo, documento) do
      {:ok, "#{documento} ingresó a #{codigo}. Cupos: #{Albergue.cupos(albergue)}."}
    end
  end

  # register_exit albergue documento
  def ejecutar("register_exit", [codigo, documento], _usuario) do
    with {:ok, albergue} <- Albergues.salir(codigo, documento) do
      {:ok, "#{documento} salió de #{codigo}. Cupos: #{Albergue.cupos(albergue)}."}
    end
  end

  # Un comando de la lista con otros argumentos, o un comando que no es de logística
  def ejecutar(comando, _argumentos, _usuario) do
    if Enum.member?(@comandos, comando) do
      {:error, :argumentos_invalidos}
    else
      {:error, :comando_desconocido}
    end
  end

  # ========== Funciones auxiliares privadas ==========

  # Los números llegan como texto: "30" -> 30
  defp entero(texto) do
    case Integer.parse(texto) do
      {numero, ""} -> {:ok, numero}
      _otro -> {:error, :numero_invalido}
    end
  end

  # Caso base: no quedan opciones, la clave no se dio
  defp opcion([], _clave), do: nil

  # Caso recursivo: si la primera opción es "clave=valor" devuelve el valor; si no,
  # sigue con el resto
  defp opcion([head | tail], clave) do
    case String.split(head, "=") do
      [nombre, valor] when nombre == clave -> valor
      _otra -> opcion(tail, clave)
    end
  end

  # destino=punto:P3, destino=albergue:A01, destino=persona:1094 o destino=familia:F001
  defp destino(nil), do: {:ok, nil}

  defp destino(texto) do
    case String.split(texto, ":") do
      [tipo, codigo] -> {:ok, {tipo, codigo}}
      _otro -> {:error, :destino_invalido}
    end
  end

  # Caso base: no quedan opciones por convertir
  defp filtros([]), do: {:ok, []}

  # Caso recursivo: convierte la primera opción en filtro y sigue con el resto
  defp filtros([head | tail]) do
    with {:ok, filtro} <- filtro(head),
         {:ok, resto} <- filtros(tail) do
      {:ok, [filtro | resto]}
    end
  end

  defp filtro(texto) do
    case String.split(texto, "=") do
      [clave, valor] when clave in @filtros_de_necesidades -> {:ok, {clave, valor}}
      _otro -> {:error, :opcion_invalida}
    end
  end

  defp movimientos(codigo) do
    lineas =
      Enum.map(Recursos.historial(codigo), fn movimiento ->
        "#{movimiento.fecha} #{movimiento.tipo} #{movimiento.codigo} #{movimiento.cantidad} #{ruta(movimiento.origen, movimiento.destino)}: #{movimiento.detalle}"
      end)

    {:ok, texto(lineas, "No hay movimientos.")}
  end

  defp ruta("", destino), do: "a #{destino}"
  defp ruta(origen, ""), do: "de #{origen}"
  defp ruta(origen, destino), do: "de #{origen} a #{destino}"

  defp siguiente(zona) do
    with {:ok, necesidad} <- Necesidades.siguiente(zona) do
      {:ok, "Siguiente: #{linea_de_necesidad(necesidad)}"}
    end
  end

  defp encabezado_de_recursos(nil, _zona), do: {:ok, []}

  defp encabezado_de_recursos(categoria, zona) do
    with {:ok, total} <- Recursos.disponibilidad(categoria, zona) do
      {:ok, ["Disponible de #{categoria}#{en_zona(zona)}: #{total}"]}
    end
  end

  defp en_zona(nil), do: ""
  defp en_zona(zona), do: " en #{zona}"

  defp de_la_categoria?(_recurso, nil), do: true

  defp de_la_categoria?(recurso, categoria),
    do: "#{recurso.categoria}" == String.downcase(categoria)

  # %{codigo del centro => zona}
  defp zonas_de_centros do
    Enum.reduce(Recursos.listar_centros(), %{}, fn centro, zonas ->
      Map.put(zonas, centro.codigo, centro.zona)
    end)
  end

  # Existencias del recurso con algo de cantidad, solo en los centros de la zona
  defp existencias_en(recurso, zona, zonas) do
    Enum.filter(recurso.existencias, fn {centro, cantidad} ->
      cantidad > 0 and (zona == nil or Map.get(zonas, centro) == zona)
    end)
  end

  defp linea_de_recurso(recurso, existencias) do
    total = existencias |> Enum.map(fn {_centro, cantidad} -> cantidad end) |> Enum.sum()

    detalle =
      existencias
      |> Enum.map(fn {centro, cantidad} -> "#{centro}: #{cantidad}" end)
      |> Enum.join(", ")

    "#{recurso.codigo} #{recurso.nombre} (#{recurso.categoria}): #{total} #{recurso.unidad} (#{detalle})"
  end

  defp linea_de_necesidad(necesidad) do
    {tipo_destino, codigo_destino} = necesidad.destino

    "#{necesidad.id} [#{necesidad.prioridad}] #{necesidad.tipo} #{necesidad.asignado}/#{necesidad.cantidad}, zona #{necesidad.zona}, #{necesidad.estado}, para #{tipo_destino} #{codigo_destino}: #{necesidad.descripcion}"
  end

  defp texto_de_necesidades(necesidades) do
    necesidades
    |> Enum.map(fn necesidad -> linea_de_necesidad(necesidad) end)
    |> texto("No hay necesidades.")
  end

  defp ocupacion_de(albergue) do
    "#{Albergue.ocupacion(albergue)} de #{albergue.capacidad} (#{Albergue.porcentaje(albergue)} %)"
  end

  defp si_vacia([], mensaje), do: [mensaje]
  defp si_vacia(lineas, _mensaje), do: lineas

  defp texto([], mensaje), do: mensaje
  defp texto(lineas, _mensaje), do: Enum.join(lineas, "\n")
end
