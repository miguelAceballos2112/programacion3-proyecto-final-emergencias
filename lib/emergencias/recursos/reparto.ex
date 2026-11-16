defmodule Emergencias.Recursos.Reparto do
  @moduledoc """
  Reparte una cantidad pedida entre varias fuentes `{codigo, centro, disponible}`.

  Se toma de la primera fuente todo lo que se pueda y lo que falte, de las siguientes.
  Si entre todas no alcanzan, no se toma nada.
  """

  @doc """
  Lista de tomas `{codigo, centro, cantidad}` o `{:error, :stock_insuficiente}`.

  ## Ejemplos

      iex> Emergencias.Recursos.Reparto.repartir([{"R1", "c1", 50}, {"R2", "c2", 30}], 60)
      {:ok, [{"R1", "c1", 50}, {"R2", "c2", 10}]}

      iex> Emergencias.Recursos.Reparto.repartir([{"R1", "c1", 50}, {"R2", "c2", 30}], 81)
      {:error, :stock_insuficiente}
  """
  def repartir(fuentes, cantidad) do
    if total(fuentes) >= cantidad do
      {:ok, tomar(fuentes, cantidad, [])}
    else
      {:error, :stock_insuficiente}
    end
  end

  @doc """
  Cantidad disponible sumando todas las fuentes.

  ## Ejemplo

      iex> Emergencias.Recursos.Reparto.total([{"R1", "c1", 50}, {"R2", "c2", 30}])
      80
  """
  # Caso base: no hay fuentes
  def total([]), do: 0

  # Caso recursivo: lo de la primera fuente más el total del resto
  def total([{_codigo, _centro, disponible} | tail]), do: disponible + total(tail)

  # Caso base: ya no falta nada
  defp tomar(_fuentes, 0, tomas), do: Enum.reverse(tomas)

  # Caso recursivo: esta fuente alcanza para lo que falta
  defp tomar([{codigo, centro, disponible} | _tail], faltante, tomas)
       when disponible >= faltante do
    Enum.reverse([{codigo, centro, faltante} | tomas])
  end

  # Caso recursivo: se toma todo lo de esta fuente y se sigue con las demás
  defp tomar([{codigo, centro, disponible} | tail], faltante, tomas) do
    tomar(tail, faltante - disponible, [{codigo, centro, disponible} | tomas])
  end
end
