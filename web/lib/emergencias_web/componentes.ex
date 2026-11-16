defmodule EmergenciasWeb.Componentes do
  @moduledoc """
  Piezas reutilizables de la vista (componentes de función de Phoenix): tarjetas,
  insignias de estado, barras de ocupación y el formulario genérico que arma un
  comando.
  """

  use Phoenix.Component

  alias Emergencias.Comandos.Base

  @doc "Tarjeta con título y contenido."
  attr :titulo, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true
  slot :acciones

  def tarjeta(assigns) do
    ~H"""
    <section class={["tarjeta", @class]}>
      <header :if={@titulo || @acciones != []} class="tarjeta-encabezado">
        <h3 :if={@titulo}>{@titulo}</h3>
        <div class="tarjeta-acciones">{render_slot(@acciones)}</div>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Indicador numérico grande (por ejemplo, total de necesidades)."
  attr :etiqueta, :string, required: true
  attr :valor, :any, required: true
  attr :detalle, :string, default: nil
  attr :tono, :string, default: "neutro"

  def indicador(assigns) do
    ~H"""
    <div class={["indicador", "tono-#{@tono}"]}>
      <span class="indicador-etiqueta">{@etiqueta}</span>
      <strong class="indicador-valor">{@valor}</strong>
      <span :if={@detalle} class="indicador-detalle">{@detalle}</span>
    </div>
    """
  end

  @doc "Insignia de color para un estado, prioridad o nivel."
  attr :valor, :any, required: true

  def insignia(assigns) do
    ~H"""
    <span class={["insignia", "insignia-#{@valor}"]}>{texto(@valor)}</span>
    """
  end

  @doc "Barra de porcentaje (ocupación de un albergue)."
  attr :porcentaje, :any, required: true

  def barra(assigns) do
    assigns = assign(assigns, :nivel, nivel_de_ocupacion(assigns.porcentaje))

    ~H"""
    <div
      class="barra"
      role="progressbar"
      aria-valuenow={@porcentaje}
      aria-valuemin="0"
      aria-valuemax="100"
    >
      <div class={["barra-relleno", "barra-#{@nivel}"]} style={"width: #{min(@porcentaje, 100)}%"}>
      </div>
    </div>
    """
  end

  @doc "Mensaje para listas vacías."
  attr :texto, :string, required: true

  def vacio(assigns) do
    ~H"""
    <p class="vacio">{@texto}</p>
    """
  end

  @doc """
  Formulario genérico: muestra un campo por dato y, al enviarlo, la vista arma la
  línea del comando con `EmergenciasWeb.Formularios.linea/2`.
  """
  attr :formulario, :map, required: true
  attr :seccion, :string, required: true
  attr :opciones, :map, required: true

  def formulario(assigns) do
    assigns = assign(assigns, :uso, Base.uso(assigns.formulario.comando))

    ~H"""
    <form id={"form-#{@formulario.comando}"} class="formulario" phx-submit="formulario">
      <input type="hidden" name="_seccion" value={@seccion} />
      <input type="hidden" name="_comando" value={@formulario.comando} />
      <h4>{@formulario.titulo}</h4>
      <p :if={@uso} class="uso"><code>{@uso}</code></p>
      <div class="campos">
        <label :for={campo <- @formulario.campos} class="campo">
          <span>{campo.etiqueta}</span>
          <.entrada campo={campo} opciones={@opciones} />
        </label>
      </div>
      <button type="submit" class="boton">{@formulario.titulo}</button>
    </form>
    """
  end

  attr :campo, :map, required: true
  attr :opciones, :map, required: true

  defp entrada(%{campo: %{tipo: {:lista, fuente}}} = assigns) do
    assigns = assign(assigns, :valores, valores_de(fuente, assigns.opciones))

    ~H"""
    <select name={@campo.nombre} required={not @campo.opcional}>
      <option :if={@campo.opcional} value="">(sin indicar)</option>
      <option :for={{valor, texto} <- @valores} value={valor}>{texto}</option>
    </select>
    """
  end

  defp entrada(%{campo: %{tipo: :numero}} = assigns) do
    ~H"""
    <input type="number" name={@campo.nombre} min="0" step="1" required={not @campo.opcional} />
    """
  end

  defp entrada(assigns) do
    ~H"""
    <input type="text" name={@campo.nombre} required={not @campo.opcional} autocomplete="off" />
    """
  end

  @doc "Texto legible para un átomo o texto: `:en_albergue` -> \"en albergue\"."
  def texto(nil), do: "—"
  def texto(valor), do: String.replace("#{valor}", "_", " ")

  # Una lista fija de valores o una lista que sale de los datos del sistema
  defp valores_de(fuente, opciones) when is_atom(fuente), do: Map.get(opciones, fuente, [])

  defp valores_de(valores, _opciones),
    do: Enum.map(valores, fn valor -> {valor, texto(valor)} end)

  defp nivel_de_ocupacion(porcentaje) when porcentaje >= 90, do: "alta"
  defp nivel_de_ocupacion(porcentaje) when porcentaje >= 60, do: "media"
  defp nivel_de_ocupacion(_porcentaje), do: "baja"
end
