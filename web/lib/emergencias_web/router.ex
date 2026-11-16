defmodule EmergenciasWeb.Router do
  @moduledoc """
  Rutas de la web. Hay una sola página, el panel (`PanelLive`); las secciones se
  eligen con `?seccion=...` sin recargar la página.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :navegador do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmergenciasWeb.Layouts, :raiz}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", EmergenciasWeb do
    pipe_through :navegador

    live "/", PanelLive, :panel
  end
end
