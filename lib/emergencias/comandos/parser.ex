defmodule Emergencias.Comandos.Parser do
  @moduledoc """
  Separa una línea de comando en palabras.

  Las palabras se separan con espacios. Lo que va entre comillas dobles es una sola
  palabra, aunque tenga espacios: `register_shelter A01 "Albergue Norte" norte 150`
  da `["register_shelter", "A01", "Albergue Norte", "norte", "150"]`.

  Recorre la línea letra por letra con una función recursiva que lleva tres cosas:
  las palabras ya completas, la palabra que se está armando y si está dentro de
  unas comillas.
  - Integrante 1: comandos
  """

  @doc """
  Retorna `{:ok, palabras}` o `{:error, :comillas_sin_cerrar}`.

  ## Ejemplos

      iex> Emergencias.Comandos.Parser.tokenizar(~s(register_need agua 30 critica centro "Punto 3"))
      {:ok, ["register_need", "agua", "30", "critica", "centro", "Punto 3"]}

      iex> Emergencias.Comandos.Parser.tokenizar(~s(connect laura 1234 nombre="Laura Gómez"))
      {:ok, ["connect", "laura", "1234", "nombre=Laura Gómez"]}

      iex> Emergencias.Comandos.Parser.tokenizar(~s(send_family_message 1094 "hola))
      {:error, :comillas_sin_cerrar}
  """
  def tokenizar(linea) do
    linea
    |> String.trim()
    |> String.graphemes()
    |> leer([], "", false)
  end

  # Caso base: se acabó la línea dentro de unas comillas
  defp leer([], _palabras, _actual, true), do: {:error, :comillas_sin_cerrar}

  # Caso base: se acabó la línea; se guarda la última palabra
  defp leer([], palabras, actual, false) do
    {:ok, Enum.reverse(guardar(palabras, actual))}
  end

  # Caso recursivo: unas comillas abren o cierran una palabra con espacios
  defp leer(["\"" | tail], palabras, actual, entre_comillas) do
    leer(tail, palabras, actual, not entre_comillas)
  end

  # Caso recursivo: un espacio fuera de comillas termina la palabra actual
  defp leer([head | tail], palabras, actual, false) when head in [" ", "\t"] do
    leer(tail, guardar(palabras, actual), "", false)
  end

  # Caso recursivo: cualquier otra letra se agrega a la palabra actual
  defp leer([head | tail], palabras, actual, entre_comillas) do
    leer(tail, palabras, actual <> head, entre_comillas)
  end

  # Una palabra vacía (dos espacios seguidos) no se guarda
  defp guardar(palabras, ""), do: palabras
  defp guardar(palabras, palabra), do: [palabra | palabras]
end
