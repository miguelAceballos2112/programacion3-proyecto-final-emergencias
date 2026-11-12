defmodule Emergencias.Application do
  @moduledoc """
  Aplicación OTP del sistema de gestión de emergencias.

  Al iniciar el proyecto, Elixir llama a `start/2`, que levanta el supervisor raíz
  con todos los procesos del sistema.
  - Integrante 1: base del sistema (sesiones, usuarios y zonas)
  - Integrante 2: logística (recursos, albergues y necesidades)
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
      # Integrante 2: logística, en orden de dependencia (cada uno solo llama a los
      # que van antes)
      Emergencias.Recursos,
      Emergencias.Albergues
      # Integrante 3: Emergencias.Personas, Emergencias.Mascotas
    ]

    # Cada servidor carga su estado desde archivos al iniciar y no depende de los
    # demás para arrancar, así que si uno falla basta con reiniciar solo ese.
    Supervisor.start_link(hijos, strategy: :one_for_one, name: Emergencias.Supervisor)
  end
end
