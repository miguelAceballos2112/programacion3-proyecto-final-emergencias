defmodule Emergencias.BitacoraTest do
  use ExUnit.Case

  alias Emergencias.Bitacora

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  # Espera hasta que la Bitácora vuelva a estar registrada (máximo 1 segundo)
  defp esperar_registro(anterior, intentos \\ 50) do
    pid = Process.whereis(Bitacora)

    cond do
      pid != nil and pid != anterior -> pid
      intentos == 0 -> nil
      true -> :timer.sleep(20) && esperar_registro(anterior, intentos - 1)
    end
  end

  test "es un proceso independiente, no un GenServer" do
    pid = Process.whereis(Bitacora)
    assert is_pid(pid)
    {:dictionary, diccionario} = Process.info(pid, :dictionary)
    refute Keyword.get(diccionario, :"$initial_call") == {Bitacora, :init, 1}
  end

  test "guarda los eventos con su resultado y los entrega por usuario" do
    usuario = unico("u")
    Bitacora.registrar(usuario, "register_need", "agua; 30", :ok)
    Bitacora.registrar(usuario, "assign_resource", "N001 agua 30", :denegado)
    Bitacora.registrar(unico("otro"), "summary", "", :ok)

    assert [primero, segundo] = Bitacora.consultar(usuario)
    assert primero.accion == "register_need"
    assert primero.detalle == "agua, 30"
    assert primero.resultado == "ok"
    assert segundo.resultado == "denegado"
  end

  test "avisa a los procesos suscritos" do
    Bitacora.suscribir(self())
    usuario = unico("u")
    Bitacora.registrar(usuario, "report_pet", "lost perro", :ok)

    assert_receive {:bitacora, %{usuario: ^usuario, accion: "report_pet"}}
  end

  test "si falla, el supervisor la reinicia y sigue guardando" do
    anterior = Process.whereis(Bitacora)
    Process.exit(anterior, :kill)

    nuevo = esperar_registro(anterior)
    assert is_pid(nuevo)

    usuario = unico("u")
    Bitacora.registrar(usuario, "summary", "", :ok)
    assert [%{accion: "summary"}] = Bitacora.consultar(usuario)
  end
end
