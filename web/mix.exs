defmodule EmergenciasWeb.MixProject do
  use Mix.Project

  # Interfaz web del sistema (Phoenix LiveView). Es un proyecto aparte que usa el
  # núcleo (la aplicación :emergencias de la carpeta de arriba) como dependencia:
  # la web solo llama al despachador de comandos y a los reportes, igual que la consola.
  def project do
    [
      app: :emergencias_web,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {EmergenciasWeb.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # El núcleo del sistema: GenServers, despachador, persistencia...
      {:emergencias, path: ".."},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1"},
      # Servidor HTTP
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.2"},
      # Solo para las pruebas de LiveView
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases do
    [setup: ["deps.get"]]
  end
end
