defmodule Emergencias.Permisos do
  @moduledoc """
  Reglas que restringen cada operación según el tipo de usuario.

  Las acciones tienen el mismo nombre que los comandos de referencia del enunciado.
  `connect` y `disconnect` no aparecen porque cualquier usuario puede ejecutarlos.
  - Integrante 1: usuarios
  """

  @todos [:ciudadano, :voluntario, :coordinador, :administrador]
  @operativos [:voluntario, :coordinador, :administrador]
  @coordinacion [:coordinador, :administrador]

  # Acción => tipos de usuario que pueden ejecutarla
  @permisos %{
    register_need: @todos,
    list_needs: @todos,
    list_resources: @todos,
    report_person: @todos,
    find_person: @todos,
    send_family_message: @todos,
    list_family_messages: @todos,
    report_pet: @todos,
    check_shelter: @todos,
    register_resource: @operativos,
    pending_needs: @operativos,
    match_pets: @operativos,
    register_entry: @operativos,
    register_exit: @operativos,
    register_zone: @coordinacion,
    assign_resource: @coordinacion,
    transfer_resource: @coordinacion,
    register_shelter: @coordinacion,
    critical_resources: @coordinacion,
    summary: @coordinacion
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
end
