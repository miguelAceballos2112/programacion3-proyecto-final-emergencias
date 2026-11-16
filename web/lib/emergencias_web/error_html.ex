defmodule EmergenciasWeb.ErrorHTML do
  @moduledoc "Páginas de error (404, 500): solo el texto del estado HTTP."

  def render(plantilla, _assigns) do
    Phoenix.Controller.status_message_from_template(plantilla)
  end
end
