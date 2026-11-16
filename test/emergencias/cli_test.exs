defmodule Emergencias.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Emergencias.CLI
  alias Emergencias.Usuarios

  test "la consola lee comandos, responde y cierra la sesión al salir" do
    usuario = "cli#{System.unique_integer([:positive])}"

    entrada = """
    connect #{usuario} 1234 ciudadano centro
    help register_need
    assign_resource N001 agua 5
    salir
    """

    salida = capture_io(entrada, fn -> CLI.iniciar() end)

    assert salida =~ "Conectado como ciudadano de la zona centro"
    assert salida =~ "register_need tipo cantidad prioridad zona descripcion"
    assert salida =~ "ERROR: Tu tipo de usuario no puede ejecutar ese comando."
    assert salida =~ "Hasta pronto."
    assert Usuarios.sesion(usuario) == {:error, :no_conectado}
  end
end
