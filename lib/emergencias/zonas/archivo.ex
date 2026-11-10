defmodule Emergencias.Zonas.Archivo do
  @moduledoc """
  Conversión entre el mapa de zonas y las líneas del archivo `zonas.txt`.

  Cada línea es un registro de la jerarquía:
  - `Z;codigo;nombre;nivel;personas` para una zona.
  - `S;zona;codigo;nombre;nivel;personas` para un sector.
  - `P;zona;sector;codigo;nombre;personas` para un punto de atención.
  - Integrante 1: zonas
  """

  alias Emergencias.Persistencia
  alias Emergencias.Zonas.PuntoAtencion
  alias Emergencias.Zonas.Sector
  alias Emergencias.Zonas.Zona

  # ---------- De zonas a líneas (recorre la jerarquía recursivamente) ----------

  @doc "Convierte el mapa `%{codigo => %Zona{}}` en la lista de líneas del archivo."
  def a_lineas(zonas) do
    zonas
    |> Map.values()
    |> Enum.sort_by(fn zona -> zona.codigo end)
    |> lineas_de_zonas()
  end

  defp lineas_de_zonas([]), do: []

  defp lineas_de_zonas([zona | resto]) do
    linea =
      Persistencia.unir([
        "Z",
        zona.codigo,
        zona.nombre,
        Atom.to_string(zona.nivel),
        Integer.to_string(zona.personas_afectadas)
      ])

    [linea] ++ lineas_de_sectores(zona.codigo, zona.sectores) ++ lineas_de_zonas(resto)
  end

  defp lineas_de_sectores(_codigo_zona, []), do: []

  defp lineas_de_sectores(codigo_zona, [sector | resto]) do
    linea =
      Persistencia.unir([
        "S",
        codigo_zona,
        sector.codigo,
        sector.nombre,
        Atom.to_string(sector.nivel),
        Integer.to_string(sector.personas_afectadas)
      ])

    [linea] ++
      lineas_de_puntos(codigo_zona, sector.codigo, sector.puntos) ++
      lineas_de_sectores(codigo_zona, resto)
  end

  defp lineas_de_puntos(_codigo_zona, _codigo_sector, []), do: []

  defp lineas_de_puntos(codigo_zona, codigo_sector, [punto | resto]) do
    linea =
      Persistencia.unir([
        "P",
        codigo_zona,
        codigo_sector,
        punto.codigo,
        punto.nombre,
        Integer.to_string(punto.personas_afectadas)
      ])

    [linea | lineas_de_puntos(codigo_zona, codigo_sector, resto)]
  end

  # ---------- De líneas a zonas ----------

  @doc """
  Reconstruye el mapa de zonas desde las líneas del archivo. Las líneas
  incorrectas, o que mencionan una zona o sector inexistente, se ignoran.
  """
  def desde_lineas(lineas) do
    Enum.reduce(lineas, %{}, fn linea, zonas ->
      aplicar(Persistencia.separar(linea), zonas)
    end)
  end

  defp aplicar(["Z", codigo, nombre, nivel, personas], zonas) do
    with {:ok, nivel} <- Zona.normalizar_nivel(nivel),
         {personas, ""} <- Integer.parse(personas) do
      Map.put(zonas, codigo, %Zona{
        codigo: codigo,
        nombre: nombre,
        nivel: nivel,
        personas_afectadas: personas
      })
    else
      _error -> zonas
    end
  end

  defp aplicar(["S", codigo_zona, codigo, nombre, nivel, personas], zonas) do
    with %Zona{} = zona <- Map.get(zonas, codigo_zona),
         {:ok, nivel} <- Zona.normalizar_nivel(nivel),
         {personas, ""} <- Integer.parse(personas) do
      sector = %Sector{codigo: codigo, nombre: nombre, nivel: nivel, personas_afectadas: personas}
      Map.put(zonas, codigo_zona, Zona.agregar_sector(zona, sector))
    else
      _error -> zonas
    end
  end

  defp aplicar(["P", codigo_zona, codigo_sector, codigo, nombre, personas], zonas) do
    with %Zona{} = zona <- Map.get(zonas, codigo_zona),
         %Sector{} <- Zona.buscar_sector(zona, codigo_sector),
         {personas, ""} <- Integer.parse(personas) do
      punto = %PuntoAtencion{codigo: codigo, nombre: nombre, personas_afectadas: personas}
      Map.put(zonas, codigo_zona, Zona.agregar_punto(zona, codigo_sector, punto))
    else
      _error -> zonas
    end
  end

  defp aplicar(_otra_linea, zonas), do: zonas
end
