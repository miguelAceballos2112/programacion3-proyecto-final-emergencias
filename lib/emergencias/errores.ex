defmodule Emergencias.Errores do
  @moduledoc """
  Traduce las razones de error (átomos) a mensajes en español para el usuario.

  Las funciones de dominio devuelven `{:error, razon}` con un átomo corto, por
  ejemplo `:stock_insuficiente`. Este es el único lugar que convierte ese átomo en
  el texto que ve el usuario, en la consola o en la web.
  - Integrante 1: base del sistema
  """

  # Razón => mensaje
  @mensajes %{
    # Sesión, usuarios y permisos
    no_conectado: "Primero conéctate: connect usuario contraseña tipo zona.",
    sesion_abierta: "Ya hay una sesión abierta aquí. Usa disconnect antes de conectar otra.",
    ya_conectado: "Ese usuario ya tiene una sesión abierta en otra consola o pestaña.",
    credenciales_invalidas: "La contraseña no es correcta.",
    sin_permiso: "Tu tipo de usuario no puede ejecutar ese comando.",
    fuera_de_zona: "Un coordinador solo puede modificar datos de su zona principal.",
    usuario_invalido:
      "El nombre de usuario no es válido (no puede estar vacío ni tener espacios).",
    contrasena_invalida: "La contraseña no puede estar vacía.",
    tipo_invalido: "El tipo no es válido.",
    # Comandos
    comando_desconocido: "Ese comando no existe. Escribe help para ver la lista.",
    comando_vacio: "Escribe un comando. Escribe help para ver la lista.",
    argumentos_invalidos: "Faltan o sobran datos en el comando.",
    comillas_sin_cerrar: "Hay unas comillas sin cerrar.",
    numero_invalido: "Se esperaba un número entero.",
    opcion_invalida: "Una de las opciones clave=valor no es válida.",
    servidor_no_responde: "El servidor no respondió a tiempo. Intenta de nuevo.",
    servidor_no_disponible: "No hay conexión con el servidor.",
    # Zonas
    zona_no_existe: "La zona no existe.",
    sector_no_existe: "El sector no existe en esa zona.",
    punto_no_existe: "El punto de atención no existe.",
    nivel_invalido: "El nivel debe ser critico, alto, medio o bajo.",
    zona_invalida: "Falta la zona o no es válida.",
    personas_invalidas: "El número de personas debe ser un entero mayor o igual a cero.",
    ya_existe: "Ya existe un registro con ese código.",
    codigo_invalido: "El código no es válido.",
    nombre_invalido: "El nombre no es válido.",
    # Recursos
    centro_no_existe: "El centro de apoyo no existe.",
    recurso_no_existe: "El recurso no existe.",
    stock_insuficiente: "No hay inventario suficiente. No se tomó nada.",
    cantidad_invalida: "La cantidad no es válida: debe ser un entero y no puede ser negativa.",
    categoria_invalida: "La categoría no es válida.",
    categoria_no_corresponde: "La categoría no corresponde al tipo de la necesidad.",
    unidad_invalida: "La unidad de medida no es válida.",
    mismo_centro: "El centro de origen y el de destino son el mismo.",
    referencia_invalida: "La referencia no es válida.",
    # Necesidades
    necesidad_no_existe: "La necesidad no existe.",
    necesidad_cerrada: "La necesidad ya está atendida o cancelada: no recibe más recursos.",
    excede_lo_requerido: "Esa cantidad supera lo que falta para la necesidad.",
    prioridad_invalida: "La prioridad debe ser critica, alta, media o baja.",
    transicion_invalida: "Ese cambio de estado no está permitido.",
    destino_invalido: "El destino no es válido. Usa destino=tipo:codigo.",
    descripcion_invalida: "La descripción no puede estar vacía.",
    responsable_invalido: "Falta el responsable.",
    sin_pendientes: "No hay necesidades pendientes.",
    # Albergues
    albergue_no_existe: "El albergue no existe.",
    albergue_lleno: "El albergue no tiene cupos disponibles.",
    capacidad_invalida: "La capacidad debe ser un entero mayor que cero.",
    ocupacion_invalida: "La ocupación inicial no es válida o supera la capacidad.",
    ya_esta_en_albergue: "La persona ya está en este albergue.",
    ya_esta_en_un_albergue: "La persona ya está en otro albergue.",
    no_esta_en_albergue: "La persona no está en ese albergue.",
    # Personas, familias y mensajes
    persona_no_existe: "No hay ninguna persona con ese documento.",
    familia_no_existe: "La familia no existe.",
    mensaje_no_existe: "El mensaje no existe.",
    documento_invalido: "El documento no es válido.",
    edad_invalida: "La edad debe ser un entero mayor o igual a cero.",
    estado_invalido: "El estado no es válido.",
    estado_inicial_invalido:
      "Una persona se reporta como sin_informacion, reportada, localizada o trasladada.",
    usar_albergue: "Para entrar o salir de un albergue usa register_entry o register_exit.",
    ya_es_miembro: "La persona ya es miembro de esa familia.",
    ya_tiene_familia: "La persona ya pertenece a otra familia.",
    contenido_invalido: "El mensaje no puede estar vacío.",
    remitente_invalido: "Falta el remitente.",
    # Mascotas
    reporte_no_existe: "El reporte de mascota no existe.",
    ya_resuelto: "Ese reporte ya fue resuelto.",
    no_son_pareja: "Esos dos reportes no están marcados como posible coincidencia.",
    especie_invalida: "La especie no es válida.",
    color_invalido: "El color no es válido.",
    tamano_invalido: "El tamaño debe ser pequeno, mediano o grande.",
    contacto_invalido: "Falta el contacto."
  }

  @doc """
  Mensaje en español para una razón de error.

  ## Ejemplos

      iex> Emergencias.Errores.mensaje(:stock_insuficiente)
      "No hay inventario suficiente. No se tomó nada."

      iex> Emergencias.Errores.mensaje(:algo_raro)
      "No se pudo completar la operación (algo_raro)."
  """
  def mensaje(razon) when is_atom(razon) do
    case Map.fetch(@mensajes, razon) do
      {:ok, texto} -> texto
      :error -> "No se pudo completar la operación (#{razon})."
    end
  end

  def mensaje({:sesion, _razon}), do: "No se pudo abrir el proceso de la sesión."
  def mensaje(otra), do: "No se pudo completar la operación (#{inspect(otra)})."
end
