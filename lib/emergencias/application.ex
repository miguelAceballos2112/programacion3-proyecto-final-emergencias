defmodule Emergencias.Application do
  @moduledoc """
  Aplicación OTP del sistema de gestión de emergencias.

  Al iniciar el proyecto, Elixir llama a `start/2`, que levanta el supervisor raíz
  con todos los procesos del sistema.
  - Integrante 1: base del sistema (sesiones, usuarios y zonas)
  - Integrante 2: logística (recursos, albergues y necesidades)
  - Integrante 3: personas (con familias y mensajes) y mascotas
  """

  use Application

  @impl true
  def start(_type, _args) do
    hijos = [
      # Supervisor dinámico: crea un proceso de sesión por cada usuario conectado.
      # Debe iniciar antes que Usuarios, que lo utiliza.
      {DynamicSupervisor, strategy: :one_for_one, name: Emergencias.SupervisorSesiones},
      Emergencias.Usuarios,
      Emergencias.Zonas,
      # Logística (Integrante 2) y personas (Integrante 3), en orden de dependencia:
      # cada servidor solo llama a los que van antes. Recursos y Personas solo llaman a
      # Zonas; Albergues llama a Recursos y Personas; Necesidades llama a los cuatro.
      Emergencias.Recursos,
      Emergencias.Personas,
      Emergencias.Mascotas,
      Emergencias.Albergues,
      Emergencias.Necesidades
    ]

    # Cada servidor carga su estado desde archivos al iniciar y no depende de los
    # demás para arrancar, así que si uno falla basta con reiniciar solo ese.
    # max_restarts y max_seconds: las pruebas de caída matan varios servidores seguidos;
    # con el límite por defecto (3 reinicios en 5 segundos) el supervisor se rendiría y
    # tumbaría toda la aplicación.
    Supervisor.start_link(hijos,
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 5,
      name: Emergencias.Supervisor
    )
  end
end
