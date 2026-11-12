defmodule Emergencias.Recursos.Recurso do
  @moduledoc """
  Recurso de ayuda (agua, alimentos, medicamentos...) con su inventario por centro.

  `existencias` es un mapa `%{centro => cantidad}`: después de una transferencia el
  mismo recurso queda repartido entre varios centros de apoyo.
  """

  @categorias [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]

  defstruct codigo: "", nombre: "", categoria: :otra, unidad: "", existencias: %{}

  @doc "Categorías válidas de recurso (son las mismas que los tipos de necesidad)."
  def categorias, do: @categorias

  @doc "Crea un recurso con su cantidad inicial en un centro."
  def crear(codigo, nombre, categoria, unidad, centro, cantidad) do
    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      categoria: categoria,
      unidad: unidad,
      existencias: %{centro => cantidad}
    }
  end

  @doc "Cantidad del recurso en un centro (0 si no hay)."
  def disponible(%__MODULE__{} = recurso, centro), do: Map.get(recurso.existencias, centro, 0)

  @doc "Cantidad total del recurso sumando todos sus centros."
  def total(%__MODULE__{} = recurso), do: sumar(Map.values(recurso.existencias))

  @doc "Suma una cantidad en un centro (lo agrega si el recurso no estaba ahí)."
  def agregar(%__MODULE__{} = recurso, centro, cantidad) do
    existencias =
      Map.update(recurso.existencias, centro, cantidad, fn actual -> actual + cantidad end)

    %{recurso | existencias: existencias}
  end

  @doc "Resta una cantidad de un centro. Nunca deja cantidades negativas."
  def retirar(%__MODULE__{} = recurso, centro, cantidad) do
    actual = disponible(recurso, centro)

    if cantidad > actual do
      {:error, :stock_insuficiente}
    else
      {:ok, %{recurso | existencias: Map.put(recurso.existencias, centro, actual - cantidad)}}
    end
  end

  @doc "Filas para el archivo de texto: una por cada centro del recurso."
  def a_filas(%__MODULE__{} = recurso) do
    Enum.map(recurso.existencias, fn {centro, cantidad} ->
      [
        recurso.codigo,
        recurso.nombre,
        "#{recurso.categoria}",
        recurso.unidad,
        centro,
        "#{cantidad}"
      ]
    end)
  end

  @doc "Agrega al mapa de recursos lo que dice una fila del archivo."
  def cargar_fila(recursos, [codigo, nombre, categoria, unidad, centro, cantidad]) do
    cantidad = String.to_integer(cantidad)

    case Map.get(recursos, codigo) do
      nil ->
        recurso = crear(codigo, nombre, String.to_atom(categoria), unidad, centro, cantidad)
        Map.put(recursos, codigo, recurso)

      recurso ->
        Map.put(recursos, codigo, agregar(recurso, centro, cantidad))
    end
  end

  # Caso base: no quedan cantidades por sumar
  defp sumar([]), do: 0

  # Caso recursivo: la primera cantidad más la suma del resto
  defp sumar([head | tail]), do: head + sumar(tail)
end
