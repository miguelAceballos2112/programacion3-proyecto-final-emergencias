defmodule EmergenciasWeb.Application do
  @moduledoc """
  Aplicación de la interfaz web.

  El núcleo (`:emergencias`) arranca antes, porque es una dependencia: su árbol de
  supervisión (Bitácora, sesiones, Usuarios, Zonas, Recursos...) ya está corriendo
  cuando esta aplicación inicia. Aquí solo se agregan los procesos de la web:

  - `Phoenix.PubSub`: lo usa Phoenix internamente.
  - `EmergenciasWeb.Endpoint`: el servidor HTTP. Por cada pestaña del navegador crea
    un proceso LiveView (`EmergenciasWeb.PanelLive`).
  """

  use Application

  @impl true
  def start(_type, _args) do
    hijos = [
      {Phoenix.PubSub, name: EmergenciasWeb.PubSub},
      EmergenciasWeb.Endpoint
    ]

    Supervisor.start_link(hijos, strategy: :one_for_one, name: EmergenciasWeb.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    EmergenciasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
