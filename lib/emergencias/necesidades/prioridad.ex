defmodule Emergencias.Necesidades.Prioridad do
  @moduledoc """
  Prioridades de las necesidades y funciones recursivas para ordenarlas y elegir la
  más urgente. Con la misma prioridad, va primero la más antigua (id menor).
  """

  @prioridades [:critica, :alta, :media, :baja]

  def lista, do: @prioridades

  @doc "Peso numérico de cada prioridad: más alto es más urgente."
  def valor(:critica), do: 4
  def valor(:alta), do: 3
  def valor(:media), do: 2
  def valor(:baja), do: 1

  @doc "Ordena de la más urgente a la menos urgente (ordenamiento por inserción)."
  # Caso base: una lista vacía ya está ordenada
  def ordenar([]), do: []

  # Caso recursivo: se ordena el resto y se inserta la primera en su lugar
  def ordenar([head | tail]), do: insertar(head, ordenar(tail))

  @doc "La necesidad más urgente de la lista."
  def mas_urgente([]), do: {:error, :sin_pendientes}
  def mas_urgente([head | tail]), do: {:ok, elegir(tail, head)}

  @doc "Indica si `a` debe atenderse antes que `b`."
  def antes?(a, b) do
    cond do
      valor(a.prioridad) > valor(b.prioridad) -> true
      valor(a.prioridad) < valor(b.prioridad) -> false
      true -> a.id < b.id
    end
  end

  # Caso base: se llegó al final, va de última
  defp insertar(necesidad, []), do: [necesidad]

  # Caso recursivo: si va antes que la primera se pone ahí; si no, se busca más adelante
  defp insertar(necesidad, [head | tail]) do
    if antes?(necesidad, head) do
      [necesidad, head | tail]
    else
      [head | insertar(necesidad, tail)]
    end
  end

  # Caso base: no quedan más por comparar
  defp elegir([], elegida), do: elegida

  # Caso recursivo: se queda con la más urgente entre la elegida y la siguiente
  defp elegir([head | tail], elegida) do
    if antes?(head, elegida) do
      elegir(tail, head)
    else
      elegir(tail, elegida)
    end
  end
end
