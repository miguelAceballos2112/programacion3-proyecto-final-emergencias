defmodule Emergencias.Sesion do
  @moduledoc """
  Sesión de un usuario conectado.

  Cada usuario conectado tiene su propio proceso, independiente de los demás, que
  guarda los datos de su sesión. Los procesos los crea el `DynamicSupervisor`
  `Emergencias.SupervisorSesiones`, porque no se sabe de antemano cuántos usuarios
  se conectarán.
  - Integrante 1: usuarios
  """

  @supervisor Emergencias.SupervisorSesiones

  @doc """
  Inicia el proceso de una sesión con los datos indicados.
  Retorna `{:ok, pid}` o `{:error, razon}`.
  """
  def iniciar(datos) do
    # :temporary => si la sesión termina, no se reinicia: el usuario debe reconectarse
    especificacion = Supervisor.child_spec({Agent, fn -> datos end}, restart: :temporary)
    DynamicSupervisor.start_child(@supervisor, especificacion)
  end

  @doc "Datos guardados en la sesión."
  def datos(pid), do: Agent.get(pid, fn datos -> datos end)

  @doc "Termina el proceso de la sesión."
  def detener(pid), do: DynamicSupervisor.terminate_child(@supervisor, pid)
end
