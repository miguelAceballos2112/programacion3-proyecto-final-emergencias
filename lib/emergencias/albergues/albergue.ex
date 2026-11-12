defmodule Emergencias.Albergues.Albergue do
  @moduledoc """
  Albergue con capacidad máxima, la ocupación con la que se registró y el conjunto
  (`MapSet`) de documentos de las personas que ingresaron con `register_entry`.

  Con un `MapSet` una persona no puede quedar dos veces adentro. La ocupación actual
  es la ocupación inicial más el tamaño del conjunto.
  """

  defstruct codigo: "",
            nombre: "",
            zona: "",
            capacidad: 0,
            ocupacion_inicial: 0,
            ocupantes: MapSet.new()

  def crear(codigo, nombre, zona, capacidad, ocupacion_inicial \\ 0) do
    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      zona: zona,
      capacidad: capacidad,
      ocupacion_inicial: ocupacion_inicial,
      ocupantes: MapSet.new()
    }
  end

  def ocupacion(%__MODULE__{} = albergue) do
    albergue.ocupacion_inicial + MapSet.size(albergue.ocupantes)
  end

  def cupos(%__MODULE__{} = albergue), do: albergue.capacidad - ocupacion(albergue)

  @doc "Porcentaje de ocupación con un decimal."
  def porcentaje(%__MODULE__{} = albergue) do
    Float.round(ocupacion(albergue) * 100 / albergue.capacidad, 1)
  end

  def esta?(%__MODULE__{} = albergue, documento),
    do: MapSet.member?(albergue.ocupantes, documento)

  @doc "Ingresa una persona si no está adentro y si hay cupo."
  def ingresar(%__MODULE__{} = albergue, documento) do
    cond do
      esta?(albergue, documento) -> {:error, :ya_esta_en_albergue}
      cupos(albergue) <= 0 -> {:error, :albergue_lleno}
      true -> {:ok, %{albergue | ocupantes: MapSet.put(albergue.ocupantes, documento)}}
    end
  end

  @doc "Saca a una persona que está adentro."
  def salir(%__MODULE__{} = albergue, documento) do
    if esta?(albergue, documento) do
      {:ok, %{albergue | ocupantes: MapSet.delete(albergue.ocupantes, documento)}}
    else
      {:error, :no_esta_en_albergue}
    end
  end

  @doc "Ordena de mayor a menor porcentaje de ocupación (ordenamiento por inserción)."
  # Caso base: una lista vacía ya está ordenada
  def ordenar_por_ocupacion([]), do: []

  # Caso recursivo: se ordena el resto y se inserta el primero en su lugar
  def ordenar_por_ocupacion([head | tail]), do: insertar(head, ordenar_por_ocupacion(tail))

  def a_fila(%__MODULE__{} = albergue) do
    [
      albergue.codigo,
      albergue.nombre,
      albergue.zona,
      "#{albergue.capacidad}",
      "#{albergue.ocupacion_inicial}",
      Enum.join(MapSet.to_list(albergue.ocupantes), ",")
    ]
  end

  def desde_fila([codigo, nombre, zona, capacidad, ocupacion_inicial, ocupantes]) do
    albergue =
      crear(
        codigo,
        nombre,
        zona,
        String.to_integer(capacidad),
        String.to_integer(ocupacion_inicial)
      )

    %{albergue | ocupantes: MapSet.new(String.split(ocupantes, ",", trim: true))}
  end

  # Caso base: se llegó al final, va de último
  defp insertar(albergue, []), do: [albergue]

  # Caso recursivo: si está más ocupado que el primero va antes; si no, se busca más
  # adelante
  defp insertar(albergue, [head | tail]) do
    if porcentaje(albergue) >= porcentaje(head) do
      [albergue, head | tail]
    else
      [head | insertar(albergue, tail)]
    end
  end
end
