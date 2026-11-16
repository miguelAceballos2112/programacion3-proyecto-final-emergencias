defmodule EmergenciasWeb.Formularios do
  @moduledoc """
  Formularios de cada sección del panel.

  Un formulario no modifica nada por sí mismo: arma la línea de comando que el
  usuario escribiría en la consola (por ejemplo `register_need agua 30 critica centro
  "Punto 3"`) y la manda al despachador. Así la web no repite reglas: permisos,
  validaciones y mensajes de error son los del núcleo. Además, la web muestra la
  línea armada, para que se vea qué comando equivale a cada formulario.

  Cada campo es un mapa con:
  - `nombre`: nombre del dato en el formulario;
  - `etiqueta`: el texto que ve el usuario;
  - `tipo`: `:texto`, `:numero` o `{:lista, fuente}` (una lista fija de valores o
    `:zonas`, `:centros`, `:albergues`, que salen de los datos del sistema);
  - `opcional`: si se puede dejar vacío;
  - `clave`: si va como opción `clave=valor` en el comando.
  """

  alias Emergencias.Mascotas.Reporte
  alias Emergencias.Necesidades.Prioridad
  alias Emergencias.Personas.Persona
  alias Emergencias.Recursos.Recurso

  @niveles ["critico", "alto", "medio", "bajo"]
  @tipos_de_usuario ["ciudadano", "voluntario", "coordinador", "administrador"]

  @doc "Tipos de usuario para el formulario de conexión."
  def tipos_de_usuario, do: @tipos_de_usuario

  @doc "Formularios de una sección del panel."
  def de("zonas") do
    [
      formulario("register_zone", "Registrar zona", [
        campo("codigo", "Código", :texto),
        campo("nombre", "Nombre", :texto),
        campo("nivel", "Nivel de afectación", {:lista, @niveles}),
        campo("personas", "Personas afectadas (estimado)", :numero, opcional: true)
      ]),
      formulario("register_sector", "Registrar sector", [
        campo("zona", "Zona", {:lista, :zonas}),
        campo("codigo", "Código del sector", :texto),
        campo("nombre", "Nombre", :texto),
        campo("nivel", "Nivel", {:lista, @niveles}),
        campo("personas", "Personas afectadas", :numero, opcional: true)
      ]),
      formulario("register_point", "Registrar punto de atención", [
        campo("zona", "Zona", {:lista, :zonas}),
        campo("sector", "Código del sector", :texto),
        campo("codigo", "Código del punto", :texto),
        campo("nombre", "Nombre", :texto),
        campo("personas", "Personas afectadas", :numero, opcional: true)
      ])
    ]
  end

  def de("recursos") do
    [
      formulario("register_center", "Registrar centro de apoyo", [
        campo("codigo", "Código", :texto),
        campo("nombre", "Nombre", :texto),
        campo("tipo", "Tipo", {:lista, ["acopio", "punto_atencion"]}),
        campo("zona", "Zona", {:lista, :zonas})
      ]),
      formulario("register_resource", "Registrar recurso", [
        campo("codigo", "Código", :texto),
        campo("categoria", "Categoría", {:lista, categorias()}),
        campo("cantidad", "Cantidad", :numero),
        campo("unidad", "Unidad de medida", :texto),
        campo("centro", "Centro", {:lista, :centros}),
        campo("nombre", "Nombre (opcional)", :texto, opcional: true, clave: "nombre")
      ]),
      formulario("add_stock", "Entrada de inventario", [
        campo("codigo", "Código del recurso", :texto),
        campo("centro", "Centro", {:lista, :centros}),
        campo("cantidad", "Cantidad", :numero)
      ]),
      formulario("remove_stock", "Salida de inventario", [
        campo("codigo", "Código del recurso", :texto),
        campo("centro", "Centro", {:lista, :centros}),
        campo("cantidad", "Cantidad", :numero)
      ]),
      formulario("transfer_resource", "Transferir entre centros", [
        campo("codigo", "Código del recurso", :texto),
        campo("origen", "Desde", {:lista, :centros}),
        campo("destino", "Hacia", {:lista, :centros}),
        campo("cantidad", "Cantidad", :numero)
      ])
    ]
  end

  def de("necesidades") do
    [
      formulario("register_need", "Registrar necesidad", [
        campo("tipo", "Tipo", {:lista, categorias()}),
        campo("cantidad", "Cantidad requerida", :numero),
        campo("prioridad", "Prioridad", {:lista, prioridades()}),
        campo("zona", "Zona", {:lista, :zonas}),
        campo("descripcion", "Descripción", :texto),
        campo("destino", "Destino (opcional, p. ej. albergue:A01)", :texto,
          opcional: true,
          clave: "destino"
        )
      ])
    ]
  end

  def de("albergues") do
    [
      formulario("register_shelter", "Registrar albergue", [
        campo("codigo", "Código", :texto),
        campo("nombre", "Nombre", :texto),
        campo("zona", "Zona", {:lista, :zonas}),
        campo("capacidad", "Capacidad máxima", :numero),
        campo("ocupacion", "Ocupación actual (opcional)", :numero, opcional: true)
      ]),
      formulario("register_entry", "Registrar ingreso", [
        campo("albergue", "Albergue", {:lista, :albergues}),
        campo("documento", "Documento de la persona", :texto)
      ]),
      formulario("register_exit", "Registrar salida", [
        campo("albergue", "Albergue", {:lista, :albergues}),
        campo("documento", "Documento de la persona", :texto)
      ])
    ]
  end

  def de("personas") do
    [
      formulario("report_person", "Reportar persona", [
        campo("documento", "Documento o dato de referencia", :texto),
        campo("nombre", "Nombre", :texto),
        campo("zona", "Zona", {:lista, :zonas}),
        campo("estado", "Estado", {:lista, estados_iniciales()}, opcional: true),
        campo("edad", "Edad (opcional)", :numero, opcional: true, clave: "edad")
      ]),
      formulario("update_person_status", "Cambiar estado de una persona", [
        campo("documento", "Documento", :texto),
        campo("estado", "Nuevo estado", {:lista, estados_de_persona()}),
        campo("detalle", "Detalle (opcional)", :texto, opcional: true)
      ]),
      formulario("send_family_message", "Dejar un mensaje", [
        campo("destino", "Documento o familia=F001", :texto),
        campo("contenido", "Mensaje", :texto)
      ]),
      formulario("register_family", "Registrar familia", [
        campo("nombre", "Nombre de la familia", :texto),
        campo("zona", "Zona", {:lista, :zonas})
      ]),
      formulario("add_family_member", "Agregar miembro a una familia", [
        campo("familia", "Código de la familia (F001)", :texto),
        campo("documento", "Documento de la persona", :texto)
      ])
    ]
  end

  def de("mascotas") do
    [
      formulario("report_pet", "Reportar mascota", [
        campo("tipo", "Tipo de reporte", {:lista, ["lost", "found"]}),
        campo("especie", "Especie", :texto),
        campo("nombre", "Nombre (o desconocido)", :texto),
        campo("color", "Color", :texto),
        campo("tamano", "Tamaño", {:lista, tamanos()}),
        campo("zona", "Zona", {:lista, :zonas}),
        campo("contacto", "Contacto", :texto),
        campo("caracteristicas", "Características (opcional)", :texto, opcional: true)
      ])
    ]
  end

  def de(_seccion), do: []

  @doc """
  Arma la línea de comando de un formulario con los datos enviados.

  ## Ejemplo

      iex> formulario = EmergenciasWeb.Formularios.de("necesidades") |> hd()
      iex> datos = %{"tipo" => "agua", "cantidad" => "30", "prioridad" => "critica",
      ...>           "zona" => "centro", "descripcion" => "Punto 3", "destino" => ""}
      iex> EmergenciasWeb.Formularios.linea(formulario, datos)
      ~s(register_need agua 30 critica centro "Punto 3")
  """
  def linea(formulario, datos) do
    partes =
      formulario.campos
      |> Enum.map(fn campo -> parte(campo, valor(datos, campo.nombre)) end)
      |> Enum.reject(fn parte -> parte == nil end)

    Enum.join([formulario.comando | partes], " ")
  end

  @doc "Busca un formulario por su comando en una sección."
  def buscar(seccion, comando) do
    Enum.find(de(seccion), fn formulario -> formulario.comando == comando end)
  end

  @doc """
  Pone comillas a un valor si tiene espacios, para que el comando lo lea como una sola
  palabra. Las comillas que traiga el valor se cambian por comillas simples.
  """
  def citar(valor) do
    limpio = String.replace(valor, "\"", "'")
    if limpio == "" or String.contains?(limpio, [" ", "\t"]), do: "\"#{limpio}\"", else: limpio
  end

  # ========== Funciones auxiliares privadas ==========

  defp formulario(comando, titulo, campos),
    do: %{comando: comando, titulo: titulo, campos: campos}

  defp campo(nombre, etiqueta, tipo, opciones \\ []) do
    %{
      nombre: nombre,
      etiqueta: etiqueta,
      tipo: tipo,
      opcional: Keyword.get(opciones, :opcional, false),
      clave: Keyword.get(opciones, :clave)
    }
  end

  defp valor(datos, nombre), do: datos |> Map.get(nombre, "") |> String.trim()

  # Un campo opcional vacío no va en el comando
  defp parte(%{opcional: true}, ""), do: nil
  defp parte(%{clave: nil}, valor), do: citar(valor)
  defp parte(%{clave: clave}, valor), do: "#{clave}=#{citar(valor)}"

  defp categorias, do: Enum.map(Recurso.categorias(), fn categoria -> "#{categoria}" end)
  defp prioridades, do: Enum.map(Prioridad.lista(), fn prioridad -> "#{prioridad}" end)
  defp tamanos, do: Enum.map(Reporte.tamanos(), fn tamano -> "#{tamano}" end)

  defp estados_iniciales do
    Enum.map(Persona.estados_iniciales(), fn estado -> "#{estado}" end)
  end

  # A en_albergue solo se entra con register_entry
  defp estados_de_persona do
    Persona.estados()
    |> Enum.reject(fn estado -> estado == :en_albergue end)
    |> Enum.map(fn estado -> "#{estado}" end)
  end
end
