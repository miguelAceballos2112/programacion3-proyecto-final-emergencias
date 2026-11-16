defmodule EmergenciasWeb.PanelLiveTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Emergencias.Comandos
  alias Emergencias.Usuarios

  @endpoint EmergenciasWeb.Endpoint

  # ========== Ayudas ==========

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  # Abre una pestaña y se conecta con un usuario nuevo
  defp entrar(tipo, zona, seccion \\ "resumen") do
    usuario = unico("web")
    {:ok, vista, _html} = live(build_conn(), "/?seccion=#{seccion}")

    html =
      vista
      |> form("#form-conectar", %{usuario: usuario, clave: "1234", tipo: tipo, zona: zona})
      |> render_submit()

    {vista, usuario, html}
  end

  # Un coordinador con su zona, un centro de acopio y 50 de agua
  defp coordinador_con_agua(seccion) do
    zona = unico("zona")
    {vista, usuario, _html} = entrar("coordinador", zona, seccion)
    centro = unico("acopio")

    for linea <- [
          "register_zone #{zona} Zona alto",
          "register_center #{centro} Acopio acopio #{zona}",
          "register_resource #{unico("R")} agua 50 litros #{centro}"
        ] do
      assert {:ok, _texto, _usuario} = Comandos.ejecutar(usuario, linea)
    end

    {vista, usuario, zona}
  end

  # Repite hasta que la condición se cumpla (máximo 1 segundo)
  defp eventualmente(condicion, intentos \\ 50) do
    cond do
      condicion.() -> true
      intentos == 0 -> false
      true -> :timer.sleep(20) && eventualmente(condicion, intentos - 1)
    end
  end

  # ========== Pruebas ==========

  test "sin sesión se muestra la página de ingreso" do
    {:ok, _vista, html} = live(build_conn(), "/")
    assert html =~ "Conectarse"
    assert html =~ "connect usuario contraseña tipo zona"
  end

  test "al conectarse se ve el panel con el usuario, su tipo y su zona" do
    {_vista, usuario, html} = entrar("voluntario", "norte")

    assert html =~ "Conectado como voluntario de la zona norte"
    assert html =~ "Salir"
    assert {:ok, %{tipo: :voluntario}} = Usuarios.sesion(usuario)
  end

  test "un formulario arma el comando y lo ejecuta con el despachador" do
    {vista, _usuario, _html} = entrar("coordinador", "zona_web", "zonas")

    html =
      vista
      |> form("#form-register_zone", %{codigo: "zona_web", nombre: "Zona Web", nivel: "alto"})
      |> render_submit()

    assert html =~ ~s(register_zone zona_web &quot;Zona Web&quot; alto)
    assert html =~ "Zona zona_web (Zona Web) registrada con nivel alto."
  end

  test "los formularios dependen del tipo de usuario" do
    {vista, _usuario, _html} = entrar("ciudadano", "centro", "zonas")
    html = render(vista)

    refute has_element?(vista, "#form-register_zone")
    assert html =~ "no puede usar"
  end

  test "la consola usa los mismos comandos y permisos que la terminal" do
    {vista, _usuario, _html} = entrar("ciudadano", "centro", "consola")

    html = vista |> form("#form-consola", %{linea: "help register_need"}) |> render_submit()
    assert html =~ "register_need tipo cantidad prioridad zona descripcion"

    html = vista |> form("#form-consola", %{linea: "summary"}) |> render_submit()
    assert html =~ "Tu tipo de usuario no puede ejecutar ese comando."
  end

  test "otra pestaña ve el cambio al instante gracias a la Bitácora" do
    {pestana_a, usuario_a, _html} = entrar("coordinador", "zona_vivo", "zonas")
    {pestana_b, _usuario_b, _html} = entrar("ciudadano", "zona_vivo", "zonas")

    assert {:ok, _texto, _u} = Comandos.ejecutar(usuario_a, "register_zone zona_vivo Viva medio")

    assert eventualmente(fn -> render(pestana_b) =~ "Viva" end)
    assert render(pestana_a) =~ "Viva"
  end

  test "al cerrar la pestaña se cierra la sesión" do
    {vista, usuario, _html} = entrar("ciudadano", "centro")
    assert {:ok, _sesion} = Usuarios.sesion(usuario)

    # La vista está enlazada a la prueba: se atrapa la salida para que la prueba siga
    Process.flag(:trap_exit, true)
    Process.exit(vista.pid, :kill)

    assert eventualmente(fn -> Usuarios.sesion(usuario) == {:error, :no_conectado} end)
  end

  test "la demostración del conflicto nunca asigna más de lo disponible" do
    {vista, _usuario, zona} = coordinador_con_agua("conflicto")

    html =
      vista
      |> form("#form-conflicto", %{
        categoria: "agua",
        zona: zona,
        solicitudes: "10",
        cantidad: "10",
        devolver: "true"
      })
      |> render_submit()

    assert html =~ "Confirmadas"
    assert {:ok, 50} = Emergencias.Recursos.disponibilidad("agua", zona)

    confirmadas =
      ~r/<li class="ok">/
      |> Regex.scan(html)
      |> length()

    assert confirmadas == 5
  end
end
