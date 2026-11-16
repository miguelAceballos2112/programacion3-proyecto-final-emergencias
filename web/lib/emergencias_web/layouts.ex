defmodule EmergenciasWeb.Layouts do
  @moduledoc """
  Plantilla HTML que envuelve la página: carga la hoja de estilos y los scripts de
  Phoenix y LiveView. El contenido del panel va en `@inner_content`.
  """

  use Phoenix.Component

  def raiz(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="es">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Emergencias · Coordinación</title>
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="stylesheet" href="/css/app.css" />
        <script defer src="/vendor/phoenix/phoenix.min.js">
        </script>
        <script defer src="/vendor/phoenix_live_view/phoenix_live_view.min.js">
        </script>
        <script defer src="/js/app.js">
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
