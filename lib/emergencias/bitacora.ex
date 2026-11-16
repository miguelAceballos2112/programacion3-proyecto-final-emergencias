defmodule Emergencias.Bitacora do
  @moduledoc """
  Bitácora de actividad: un proceso independiente que NO es un GenServer.

  Se crea con `spawn_link`, se registra con `Process.register` y atiende sus mensajes
  con `receive` dentro de una función recursiva (`bucle/1`), como en la guía de
  procesos. Quien quiere registrar algo le envía un mensaje con `send` y sigue su
  trabajo sin esperar respuesta.

  La Bitácora hace dos cosas con cada evento:
  - lo escribe en `actividad.txt` (es el único proceso que escribe ese archivo, así
    dos usuarios nunca escriben a la vez y las líneas no se mezclan);
  - avisa a los procesos suscritos, por ejemplo a cada pestaña de la interfaz web,
    para que se actualicen solas cuando otro usuario cambia algo.

  Su único estado es la lista de suscriptores, que viaja como argumento del bucle.
  El supervisor raíz la reinicia si falla.
  - Integrante 1: usuarios (registro de actividad)
  """

  alias Emergencias.Persistencia

  @archivo "actividad.txt"
  @tiempo_de_espera 5_000

  # ========== API del cliente ==========

  @doc "Cómo la inicia el supervisor: llama a `start_link/0`."
  def child_spec(_opciones) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  @doc """
  Crea el proceso, enlazado con quien lo inicia (el supervisor), y lo registra con el
  nombre del módulo para poder enviarle mensajes sin conocer su pid.
  """
  def start_link do
    pid = spawn_link(fn -> bucle([]) end)
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  @doc """
  Registra un evento: quién hizo qué, con qué detalle y con qué resultado
  (`:ok`, `:error` o `:denegado`). No espera respuesta.
  """
  def registrar(usuario, accion, detalle, resultado \\ :ok) do
    enviar({:evento, ahora(), usuario, accion, detalle, resultado})
  end

  @doc """
  Suscribe un proceso: desde ahora recibirá `{:bitacora, evento}` por cada evento
  nuevo. Si el proceso termina, la Bitácora lo quita sola (lo vigila con un monitor).
  """
  def suscribir(pid \\ self()), do: enviar({:suscribir, pid})

  @doc """
  Eventos de un usuario (o de todos, con `nil`), del más antiguo al más reciente.
  Cada evento es un mapa con `fecha`, `usuario`, `accion`, `detalle` y `resultado`.

  La consulta pasa por el proceso para que incluya los eventos que este proceso ya
  le envió. Si la Bitácora no está (por ejemplo, mientras se reinicia), lee el archivo.
  """
  def consultar(usuario \\ nil) do
    case Process.whereis(__MODULE__) do
      nil ->
        leer(usuario)

      pid ->
        referencia = make_ref()
        send(pid, {:consultar, self(), referencia, usuario})

        receive do
          {^referencia, eventos} -> eventos
        after
          @tiempo_de_espera -> leer(usuario)
        end
    end
  end

  @doc """
  Espera a que la Bitácora escriba todo lo que ya tiene en su buzón. La consola la
  llama antes de terminar, para que no se pierdan los últimos eventos.
  """
  def sincronizar do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        referencia = make_ref()
        send(pid, {:sincronizar, self(), referencia})

        receive do
          {^referencia, :ok} -> :ok
        after
          @tiempo_de_espera -> :ok
        end
    end
  end

  # ========== Bucle del proceso ==========

  # Atiende un mensaje y vuelve a llamarse con la lista de suscriptores actualizada
  defp bucle(suscriptores) do
    receive do
      {:evento, fecha, usuario, accion, detalle, resultado} ->
        evento = %{
          fecha: fecha,
          usuario: usuario,
          accion: accion,
          detalle: Persistencia.limpiar("#{detalle}"),
          resultado: "#{resultado}"
        }

        escribir(evento)
        avisar(suscriptores, evento)
        bucle(suscriptores)

      {:suscribir, pid} ->
        if Enum.member?(suscriptores, pid) do
          bucle(suscriptores)
        else
          Process.monitor(pid)
          bucle([pid | suscriptores])
        end

      # Un suscriptor terminó (por ejemplo, se cerró una pestaña)
      {:DOWN, _referencia, :process, pid, _razon} ->
        bucle(quitar(suscriptores, pid))

      {:consultar, quien, referencia, usuario} ->
        send(quien, {referencia, leer(usuario)})
        bucle(suscriptores)

      # Los mensajes se atienden en orden: si llegó hasta aquí, lo anterior ya se escribió
      {:sincronizar, quien, referencia} ->
        send(quien, {referencia, :ok})
        bucle(suscriptores)
    end
  end

  # ========== Funciones auxiliares privadas ==========

  # Si la Bitácora no está registrada (se está reiniciando), el evento se descarta:
  # send/2 con un nombre que no existe lanzaría un error.
  defp enviar(mensaje) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> send(pid, mensaje)
    end

    :ok
  end

  # Caso base: no quedan suscriptores por avisar
  defp avisar([], _evento), do: :ok

  # Caso recursivo: avisa al primero y sigue con el resto
  defp avisar([head | tail], evento) do
    send(head, {:bitacora, evento})
    avisar(tail, evento)
  end

  # Caso base: lista vacía
  defp quitar([], _pid), do: []

  # Caso recursivo: se salta el pid que terminó y conserva los demás
  defp quitar([head | tail], pid) do
    if head == pid, do: quitar(tail, pid), else: [head | quitar(tail, pid)]
  end

  defp escribir(evento) do
    linea =
      Persistencia.unir([
        evento.fecha,
        evento.usuario,
        evento.accion,
        evento.detalle,
        evento.resultado
      ])

    Persistencia.agregar(@archivo, linea)
  end

  defp leer(usuario) do
    @archivo
    |> Persistencia.cargar()
    |> Enum.map(fn linea -> Persistencia.separar(linea) end)
    |> convertir(usuario)
  end

  # Caso base: no quedan líneas
  defp convertir([], _usuario), do: []

  # Caso recursivo: convierte la primera línea si es del usuario pedido y sigue.
  # Las líneas viejas no tienen resultado: se toman como "ok".
  defp convertir([head | tail], usuario) do
    case head do
      [fecha, de, accion, detalle, resultado] when usuario == nil or de == usuario ->
        [evento(fecha, de, accion, detalle, resultado) | convertir(tail, usuario)]

      [fecha, de, accion, detalle] when usuario == nil or de == usuario ->
        [evento(fecha, de, accion, detalle, "ok") | convertir(tail, usuario)]

      _otra ->
        convertir(tail, usuario)
    end
  end

  defp evento(fecha, usuario, accion, detalle, resultado) do
    %{fecha: fecha, usuario: usuario, accion: accion, detalle: detalle, resultado: resultado}
  end

  defp ahora, do: NaiveDateTime.local_now() |> NaiveDateTime.to_string()
end
