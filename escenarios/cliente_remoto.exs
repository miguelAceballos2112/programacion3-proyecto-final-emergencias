# Escenario: dos nodos cliente piden agua al mismo tiempo a un nodo servidor.
#
# El servidor guarda el inventario; los clientes lo llaman con :rpc.call/5 (nodos
# distribuidos de Erlang). Se necesitan cuatro terminales abiertas en la raíz del
# proyecto, y los nombres de nodo y la cookie deben coincidir:
#
#   Terminal 1, el servidor (antes borre la carpeta de datos con `rm -rf datos`):
#       elixir --sname servidor --cookie emergencias -S mix run --no-halt
#
#   Terminal 2, prepara una zona, un centro y 50 litros de agua (se ejecuta una vez):
#       elixir --sname admin --cookie emergencias -S mix run --no-start escenarios/cliente_remoto.exs preparar
#
#   Terminales 2 y 3, los dos clientes, lanzados con pocos segundos de diferencia:
#       elixir --sname laura --cookie emergencias -S mix run --no-start escenarios/cliente_remoto.exs pedir laura 30
#       elixir --sname pedro --cookie emergencias -S mix run --no-start escenarios/cliente_remoto.exs pedir pedro 25
#
#   Para ver cómo quedó el inventario:
#       elixir --sname admin --cookie emergencias -S mix run --no-start escenarios/cliente_remoto.exs resumen
#
# Los dos clientes esperan a la misma marca del reloj (cada 20 segundos) para llamar al
# servidor a la vez. Se pidieron 55 litros y solo hay 50: el servidor atiende un pedido
# a la vez, confirma el primero que llega y rechaza el otro.
#
# Se usa --no-start para que los clientes no arranquen la aplicación: todo el estado vive
# en el nodo servidor.
#
# Si el nombre corto del equipo no se resuelve, se puede usar nombres largos:
# `--name servidor@127.0.0.1` en todas las terminales (con su propio nombre en cada una)
# y la variable SERVIDOR=servidor@127.0.0.1 al lanzar los clientes.

defmodule ClienteRemoto do
  alias Emergencias.Comandos.Logistica
  alias Emergencias.Necesidades
  alias Emergencias.Zonas

  @zona "remota"
  @espera_ms 20_000

  def main(["preparar"]) do
    servidor = conectar()

    IO.puts("> registrar zona #{@zona}")
    imprimir(llamar(servidor, Zonas, :registrar_zona, [@zona, "Zona remota", "critico"]))

    comando(servidor, "register_center", ["centro_remoto", "Centro remoto", "acopio", @zona])
    comando(servidor, "register_resource", ["RR01", "agua", "50", "litros", "centro_remoto"])
    comando(servidor, "list_resources", ["zona=#{@zona}"])
  end

  def main(["pedir", usuario, cantidad]) do
    case Integer.parse(cantidad) do
      {litros, ""} ->
        servidor = conectar()
        pedir(servidor, usuario, litros)

      _otro ->
        IO.puts("La cantidad debe ser un número entero.")
    end
  end

  def main(["resumen"]) do
    servidor = conectar()
    comando(servidor, "list_resources", ["zona=#{@zona}"])
    comando(servidor, "list_needs", ["zona=#{@zona}"])
  end

  def main(_otros) do
    IO.puts("Uso: cliente_remoto.exs preparar | pedir usuario cantidad | resumen")
  end

  # ========== Pasos ==========

  # Cada cliente pide agua: registra la necesidad y le asigna agua, las dos cosas en
  # el servidor. Antes espera la marca del reloj para coincidir con el otro cliente.
  defp pedir(servidor, usuario, litros) do
    esperar_marca()
    IO.puts("#{usuario} (nodo #{Node.self()}) pide #{litros} litros")

    with {:ok, necesidad} <-
           llamar(servidor, Necesidades, :registrar, [
             "agua",
             litros,
             "alta",
             @zona,
             "Pedido remoto de #{usuario}",
             usuario
           ]),
         {:ok, asignada} <-
           llamar(servidor, Necesidades, :asignar_recurso, [necesidad.id, "agua", litros]) do
      IO.puts("  #{usuario}: #{asignada.id} recibió #{litros} litros (estado: #{asignada.estado})")
    else
      {:error, razon} ->
        IO.puts("  #{usuario}: NO recibió #{litros} litros (#{inspect(razon)})")
    end
  end

  # ========== Ayudas ==========

  # Verifica que este nodo sea distribuido y se conecte al servidor
  defp conectar do
    servidor = nombre_del_servidor()

    cond do
      not Node.alive?() ->
        IO.puts("Este nodo no es distribuido. Lance el script con --sname y --cookie.")
        System.halt(1)

      Node.connect(servidor) ->
        servidor

      true ->
        IO.puts("No se pudo conectar con #{servidor}. Revise que el servidor esté encendido")
        IO.puts("y que la cookie y los nombres de nodo coincidan.")
        System.halt(1)
    end
  end

  # Por defecto el servidor es servidor@<nombre de este equipo>
  defp nombre_del_servidor do
    case System.get_env("SERVIDOR") do
      nil ->
        {:ok, equipo} = :inet.gethostname()
        :"servidor@#{equipo}"

      nombre ->
        :"#{nombre}"
    end
  end

  # Llama a una función del servidor. Si el servidor está apagado, :rpc.call devuelve
  # {:badrpc, :nodedown} y se traduce a un error propio.
  defp llamar(servidor, modulo, funcion, argumentos) do
    case :rpc.call(servidor, modulo, funcion, argumentos, 10_000) do
      {:badrpc, :nodedown} -> {:error, :servidor_no_disponible}
      {:badrpc, razon} -> {:error, {:rpc, razon}}
      resultado -> resultado
    end
  end

  # Ejecuta un comando de logística en el servidor y muestra su respuesta
  defp comando(servidor, nombre, argumentos) do
    IO.puts("> #{nombre} #{Enum.join(argumentos, " ")}")
    imprimir(llamar(servidor, Logistica, :ejecutar, [nombre, argumentos, "admin"]))
  end

  defp imprimir({:ok, texto}) when is_binary(texto) do
    texto
    |> String.split("\n")
    |> Enum.each(fn linea -> IO.puts("  " <> linea) end)
  end

  defp imprimir({:ok, zona = %Zonas.Zona{}}), do: IO.puts("  Zona #{zona.codigo} registrada.")
  defp imprimir({:ok, otro}), do: IO.puts("  #{inspect(otro)}")
  defp imprimir({:error, razon}), do: IO.puts("  ERROR: #{inspect(razon)}")

  # Espera a la siguiente marca de 20 segundos del reloj. Los dos clientes corren en el
  # mismo equipo, así que comparten reloj y salen en el mismo instante.
  defp esperar_marca do
    ahora = System.os_time(:millisecond)
    marca = (div(ahora, @espera_ms) + 1) * @espera_ms
    IO.puts("Esperando #{div(marca - ahora, 1000)} segundos para salir a la vez...")
    Process.sleep(marca - ahora)
  end
end

ClienteRemoto.main(System.argv())
