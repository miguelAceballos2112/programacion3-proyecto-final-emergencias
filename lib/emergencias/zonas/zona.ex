defmodule Emergencias.Zonas.Zona do
  @moduledoc """
  Zona afectada por la emergencia. Contiene una lista de sectores, y cada sector
  una lista de puntos de atención.

  Las funciones de este módulo son puras: reciben una zona y devuelven otra,
  sin guardar nada.
  - Integrante 1: zonas
  """

  alias Emergencias.Zonas.PuntoAtencion
  alias Emergencias.Zonas.Sector

  @niveles [:critico, :alto, :medio, :bajo]

  @enforce_keys [:codigo, :nombre, :nivel]
  defstruct [:codigo, :nombre, :nivel, personas_afectadas: 0, sectores: []]

  @doc """
  Convierte un nivel de afectación (átomo o texto) en uno de los niveles válidos:
  `:critico`, `:alto`, `:medio` o `:bajo`.

  ## Ejemplos

      iex> Emergencias.Zonas.Zona.normalizar_nivel("Crítico")
      {:ok, :critico}

      iex> Emergencias.Zonas.Zona.normalizar_nivel("extremo")
      {:error, :nivel_invalido}
  """
  def normalizar_nivel(nivel) when is_atom(nivel) do
    if Enum.member?(@niveles, nivel), do: {:ok, nivel}, else: {:error, :nivel_invalido}
  end

  def normalizar_nivel(nivel) when is_binary(nivel) do
    texto = nivel |> String.trim() |> String.downcase() |> String.replace("í", "i")

    case Enum.find(@niveles, fn conocido -> Atom.to_string(conocido) == texto end) do
      nil -> {:error, :nivel_invalido}
      encontrado -> {:ok, encontrado}
    end
  end

  def normalizar_nivel(_nivel), do: {:error, :nivel_invalido}

  @doc "Busca un sector de la zona por su código. Retorna el sector o `nil`."
  def buscar_sector(%__MODULE__{} = zona, codigo_sector) do
    Enum.find(zona.sectores, fn sector -> sector.codigo == codigo_sector end)
  end

  @doc "Busca un punto de atención dentro de un sector. Retorna el punto o `nil`."
  def buscar_punto(%Sector{} = sector, codigo_punto) do
    Enum.find(sector.puntos, fn punto -> punto.codigo == codigo_punto end)
  end

  @doc "Devuelve la zona con un sector más, al final de su lista de sectores."
  def agregar_sector(%__MODULE__{} = zona, %Sector{} = sector) do
    %{zona | sectores: zona.sectores ++ [sector]}
  end

  @doc "Devuelve la zona con un punto de atención más en el sector indicado."
  def agregar_punto(%__MODULE__{} = zona, codigo_sector, %PuntoAtencion{} = punto) do
    sectores =
      Enum.map(zona.sectores, fn sector ->
        if sector.codigo == codigo_sector do
          %{sector | puntos: sector.puntos ++ [punto]}
        else
          sector
        end
      end)

    %{zona | sectores: sectores}
  end
end
