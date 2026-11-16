defmodule EmergenciasWeb.Endpoint do
  @moduledoc """
  Punto de entrada HTTP. Cada petición pasa por esta lista de `plug` en orden:
  archivos estáticos, lectura de parámetros, sesión y, al final, el router.

  `/live` es el canal (websocket) por donde cada pestaña conversa con su proceso
  LiveView en el servidor.
  """

  use Phoenix.Endpoint, otp_app: :emergencias_web

  @opciones_de_sesion [
    store: :cookie,
    key: "_emergencias_web",
    signing_salt: "emergencias-sesion",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @opciones_de_sesion]],
    longpoll: [connect_info: [session: @opciones_de_sesion]]

  # Hoja de estilos y script propios (priv/static)
  plug Plug.Static, at: "/", from: :emergencias_web, gzip: false, only: ~w(css js favicon.svg)

  # Los clientes JavaScript de Phoenix y LiveView vienen dentro de sus dependencias:
  # se sirven tal cual, sin herramientas de JavaScript (ni Node ni esbuild).
  plug Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.min.js)

  plug Plug.Static,
    at: "/vendor/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)

  plug Plug.RequestId

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @opciones_de_sesion
  plug EmergenciasWeb.Router
end
