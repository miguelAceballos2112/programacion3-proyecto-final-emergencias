defmodule Emergencias.MixProject do
  use Mix.Project

  def project do
    [
      app: :emergencias,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # mix consola: abre la consola de texto con el sistema iniciado en este nodo
  defp aliases do
    [consola: "run -e Emergencias.CLI.iniciar()"]
  end

  # Configuración de la aplicación: módulo que inicia el árbol de supervisión
  def application do
    [
      mod: {Emergencias.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    []
  end
end
