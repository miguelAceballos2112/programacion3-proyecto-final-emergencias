defmodule Emergencias.Permisos do
  @moduledoc """
  Reglas que restringen cada operación según el tipo de usuario.

  Las acciones tienen el mismo nombre que los comandos. `connect` y `help` no
  aparecen porque cualquiera puede ejecutarlos, incluso sin haberse conectado.

  Los tipos van de menor a mayor: ciudadano, voluntario, coordinador y administrador.
  - Integrante 1: usuarios
  """

  @todos [:ciudadano, :voluntario, :coordinador, :administrador]
  @operativos [:voluntario, :coordinador, :administrador]
  @coordinacion [:coordinador, :administrador]
  @administracion [:administrador]

  # Acción => tipos de usuario que pueden ejecutarla
  @permisos %{
    # Cualquier usuario conectado
    disconnect: @todos,
    show_activity: @todos,
    list_zones: @todos,
    zone_status: @todos,
    register_need: @todos,
    list_needs: @todos,
    list_resources: @todos,
    check_shelter: @todos,
    report_person: @todos,
    find_person: @todos,
    register_family: @todos,
    add_family_member: @todos,
    send_family_message: @todos,
    list_family_messages: @todos,
    report_pet: @todos,
    list_pets: @todos,
    # Voluntarios en adelante
    register_resource: @operativos,
    pending_needs: @operativos,
    next_need: @operativos,
    update_need_status: @operativos,
    register_entry: @operativos,
    register_exit: @operativos,
    update_person_status: @operativos,
    person_history: @operativos,
    mark_message: @operativos,
    match_pets: @operativos,
    reject_match: @operativos,
    # Coordinadores y administradores
    register_zone: @coordinacion,
    register_sector: @coordinacion,
    register_point: @coordinacion,
    register_center: @coordinacion,
    add_stock: @coordinacion,
    remove_stock: @coordinacion,
    list_movements: @coordinacion,
    transfer_resource: @coordinacion,
    assign_resource: @coordinacion,
    cancel_need: @coordinacion,
    critical_resources: @coordinacion,
    register_shelter: @coordinacion,
    shelter_report: @coordinacion,
    confirm_match: @coordinacion,
    summary: @coordinacion,
    # Solo administradores
    list_users: @administracion
  }

  @doc """
  Indica si un tipo de usuario puede ejecutar una acción.
  Una acción desconocida no está permitida para nadie.

  ## Ejemplos

      iex> Emergencias.Permisos.permitido?(:coordinador, :register_zone)
      true

      iex> Emergencias.Permisos.permitido?(:ciudadano, :register_zone)
      false
  """
  def permitido?(tipo, accion) do
    tipos = Map.get(@permisos, accion, [])
    Enum.member?(tipos, tipo)
  end

  @doc """
  Convierte el nombre de un comando (texto) en su acción (átomo), buscándolo entre
  las acciones conocidas. Nunca crea átomos nuevos con lo que escribe el usuario.

  ## Ejemplos

      iex> Emergencias.Permisos.accion("assign_resource")
      {:ok, :assign_resource}

      iex> Emergencias.Permisos.accion("borrar_todo")
      {:error, :comando_desconocido}
  """
  def accion(comando), do: buscar_accion(Map.keys(@permisos), comando)

  @doc "Tipos de usuario que pueden ejecutar un comando (lista vacía si no existe)."
  def tipos_de(comando) do
    case accion(comando) do
      {:ok, accion} -> Map.get(@permisos, accion)
      {:error, _razon} -> []
    end
  end

  # Caso base: se revisaron todas las acciones y ninguna se llama así
  defp buscar_accion([], _comando), do: {:error, :comando_desconocido}

  # Caso recursivo: compara la primera acción con el texto y sigue con el resto
  defp buscar_accion([head | tail], comando) do
    if "#{head}" == comando, do: {:ok, head}, else: buscar_accion(tail, comando)
  end
end
