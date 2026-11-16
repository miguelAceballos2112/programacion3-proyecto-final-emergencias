defmodule Emergencias.CLI do
  @moduledoc """
  Consola de texto del sistema.

  Cada consola es un proceso que repite tres pasos: lee una línea, se la pasa al
  despachador (`Emergencias.Comandos`) y muestra la respuesta. El usuario conectado
  viaja como argumento de la función recursiva `bucle/2`.

  Consola local (el sistema corre en el mismo nodo):

      mix consola

  Consola remota (el sistema corre en otro nodo, el "servidor"):

      elixir --sname servidor --cookie emergencias -S mix run --no-halt
      elixir --sname laura --cookie emergencias -S mix run --no-start -e "Emergencias.CLI.iniciar(:\\"servidor@NOMBRE_DEL_PC\\")"

  `NOMBRE_DEL_PC` es el que muestra `hostname`; las comillas del átomo hacen falta si
  tiene guiones. En la remota, cada comando viaja con `:rpc.call/5` y lo ejecuta el
  servidor.
  La consola se pasa a sí misma como dueña de la sesión: si se cierra, la sesión
  también se cierra.
  - Integrante 1: comandos
  """

  alias Emergencias.Bitacora
  alias Emergencias.Comandos

  @tiempo_de_espera 10_000

  @doc "Inicia la consola, local (sin argumento) o conectada a un nodo servidor."
  def iniciar(nodo \\ nil) do
    IO.puts("""

    === Sistema de Coordinación y Gestión de Emergencias ===
    Escribe help para ver los comandos y salir para terminar.
    Para empezar: connect usuario contraseña tipo zona
    """)

    case verificar_nodo(nodo) do
      :ok ->
        bucle(nodo, nil)

      {:error, texto} ->
        IO.puts(texto)
        :error
    end
  end

  # ========== Bucle de la consola ==========

  # Lee una línea, la ejecuta y vuelve a empezar con el usuario que quedó conectado
  defp bucle(nodo, usuario) do
    case IO.gets(indicador(usuario)) do
      :eof ->
        salir(nodo, usuario)

      {:error, _razon} ->
        salir(nodo, usuario)

      linea ->
        texto = String.trim(linea)

        cond do
          texto in ["salir", "exit", "quit"] ->
            salir(nodo, usuario)

          texto == "" ->
            bucle(nodo, usuario)

          true ->
            {resultado, respuesta, nuevo_usuario} = ejecutar(nodo, usuario, texto)
            IO.puts(formatear(resultado, respuesta))
            bucle(nodo, nuevo_usuario)
        end
    end
  end

  # ========== Funciones auxiliares privadas ==========

  # Local: llama al despachador directamente
  defp ejecutar(nil, usuario, linea), do: Comandos.ejecutar(usuario, linea, self())

  # Remota: el despachador corre en el nodo servidor
  defp ejecutar(nodo, usuario, linea) do
    case :rpc.call(nodo, Comandos, :ejecutar, [usuario, linea, self()], @tiempo_de_espera) do
      {:badrpc, _razon} -> {:error, "No hay conexión con el servidor #{nodo}.", usuario}
      respuesta -> respuesta
    end
  end

  # Al salir se cierra la sesión que haya quedado abierta. En la consola local, además,
  # se espera a que la Bitácora escriba los últimos eventos antes de que el nodo termine.
  defp salir(nodo, usuario) do
    if usuario != nil, do: ejecutar(nodo, usuario, "disconnect")
    if nodo == nil, do: Bitacora.sincronizar()
    IO.puts("Hasta pronto.")
    :ok
  end

  defp verificar_nodo(nil), do: :ok

  defp verificar_nodo(nodo) do
    if Node.connect(nodo) do
      IO.puts("Conectado al servidor #{nodo}.")
      :ok
    else
      {:error, "No se pudo conectar con el nodo #{nodo}. ¿Está encendido y con la misma cookie?"}
    end
  end

  defp indicador(nil), do: "emergencias> "
  defp indicador(usuario), do: "#{usuario}> "

  defp formatear(:ok, texto), do: texto
  defp formatear(:error, texto), do: "ERROR: #{texto}"
end
