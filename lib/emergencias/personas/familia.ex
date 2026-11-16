defmodule Emergencias.Personas.Familia do
  @moduledoc """
  Familia: agrupa personas por su documento.

  Los miembros se guardan en un `MapSet`, porque un documento no puede estar dos
  veces en la misma familia y solo importa saber si pertenece o no (el mismo
  criterio que usa `Albergue` con sus ocupantes).
  - Integrante 3: personas
  """

  defstruct codigo: "", nombre: "", zona: "", miembros: MapSet.new()

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          zona: String.t(),
          miembros: MapSet.t(String.t())
        }

  @doc "Crea una familia sin miembros."
  @spec crear(String.t(), String.t(), String.t()) :: t()
  def crear(codigo, nombre, zona) do
    %__MODULE__{codigo: codigo, nombre: nombre, zona: zona, miembros: MapSet.new()}
  end

  @doc "Indica si el documento ya es miembro de la familia."
  @spec miembro?(t(), String.t()) :: boolean()
  def miembro?(%__MODULE__{} = familia, documento),
    do: MapSet.member?(familia.miembros, documento)

  @doc "Agrega un documento como miembro. Si ya estaba retorna `:ya_es_miembro`."
  @spec agregar_miembro(t(), String.t()) :: {:ok, t()} | {:error, :ya_es_miembro}
  def agregar_miembro(%__MODULE__{} = familia, documento) do
    if miembro?(familia, documento) do
      {:error, :ya_es_miembro}
    else
      {:ok, %{familia | miembros: MapSet.put(familia.miembros, documento)}}
    end
  end

  @doc "Convierte la familia en los campos de una línea de `familias.txt`."
  @spec a_fila(t()) :: [String.t()]
  def a_fila(%__MODULE__{} = familia) do
    miembros = familia.miembros |> MapSet.to_list() |> Enum.sort() |> Enum.join(",")
    [familia.codigo, familia.nombre, familia.zona, miembros]
  end

  @doc "Reconstruye una familia desde los campos de una línea."
  @spec desde_fila([String.t()]) :: {:ok, t()} | {:error, :fila_invalida}
  def desde_fila([codigo, nombre, zona, miembros]) do
    familia = crear(codigo, nombre, zona)
    {:ok, %{familia | miembros: MapSet.new(String.split(miembros, ",", trim: true))}}
  end

  def desde_fila(_otra), do: {:error, :fila_invalida}
end
