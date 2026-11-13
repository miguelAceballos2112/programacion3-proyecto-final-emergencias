defmodule Emergencias.Mascotas.Similitud do
  @moduledoc """
  Puntaje de similitud, de 0 a 100, entre un reporte de mascota perdida y uno de
  mascota encontrada.

  Reglas:

  - Una especie distinta descarta el par: puntaje 0.
  - Si la especie coincide aporta 30 puntos, y se suman:
    color 20, tamaño 15, zona 15 y características hasta 20.
  - Las características puntúan por palabras en común sobre palabras totales
    (`MapSet`): si coinciden todas aportan 20, la mitad aporta 10.
  - Un puntaje de 60 o más marca el par como posible coincidencia.

  Son funciones puras: reciben cualquier mapa o struct con los campos `especie`,
  `color`, `tamano`, `zona` y `caracteristicas`.
  - Integrante 3: mascotas
  """

  # Atributos que se comparan (después de la especie) y los puntos que aporta cada uno
  @atributos [color: 20, tamano: 15, zona: 15, caracteristicas: 20]
  @puntos_especie 30
  @umbral 60

  @doc "Puntaje mínimo para marcar un par como posible coincidencia."
  @spec umbral() :: pos_integer()
  def umbral, do: @umbral

  @doc """
  Puntaje de 0 a 100 entre dos reportes.

  Recursiva: `sumar/3` recorre la lista de atributos sumando los puntos de cada
  uno. Con la lista vacía el resultado es 0 (caso base).

  ## Ejemplos

      iex> a = %{especie: "perro", color: "café", tamano: :mediano, zona: "centro", caracteristicas: "collar rojo"}
      iex> Emergencias.Mascotas.Similitud.puntaje(a, a)
      100

      iex> a = %{especie: "perro", color: "café", tamano: :mediano, zona: "centro", caracteristicas: ""}
      iex> b = %{a | especie: "gato"}
      iex> Emergencias.Mascotas.Similitud.puntaje(a, b)
      0
  """
  @spec puntaje(map(), map(), keyword()) :: non_neg_integer()
  def puntaje(perdida, encontrada, atributos \\ @atributos) do
    if normalizar(perdida.especie) == normalizar(encontrada.especie) do
      @puntos_especie + sumar(perdida, encontrada, atributos)
    else
      0
    end
  end

  # Caso base: no quedan atributos por comparar
  defp sumar(_perdida, _encontrada, []), do: 0

  # Caso recursivo: los puntos del primer atributo más los del resto
  defp sumar(perdida, encontrada, [{campo, peso} | resto]) do
    puntos(campo, peso, perdida, encontrada) + sumar(perdida, encontrada, resto)
  end

  # Las características se comparan por palabras: en común sobre totales
  defp puntos(:caracteristicas, peso, perdida, encontrada) do
    una = palabras(perdida.caracteristicas)
    otra = palabras(encontrada.caracteristicas)
    total = MapSet.size(MapSet.union(una, otra))

    if total == 0 do
      0
    else
      comunes = MapSet.size(MapSet.intersection(una, otra))
      round(peso * comunes / total)
    end
  end

  # Los demás atributos puntúan completo si coinciden y nada si no
  defp puntos(campo, peso, perdida, encontrada) do
    if normalizar(Map.get(perdida, campo)) == normalizar(Map.get(encontrada, campo)) do
      peso
    else
      0
    end
  end

  defp palabras(texto) do
    texto
    |> normalizar()
    |> String.split(" ", trim: true)
    |> MapSet.new()
  end

  # Sin distinguir mayúsculas ni espacios sobrantes; sirve para textos y átomos
  defp normalizar(nil), do: ""
  defp normalizar(valor), do: valor |> to_string() |> String.trim() |> String.downcase()
end
