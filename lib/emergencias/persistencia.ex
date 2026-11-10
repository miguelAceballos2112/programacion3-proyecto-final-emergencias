defmodule Emergencias.Persistencia do
  @moduledoc """
  Lectura y escritura de archivos de texto plano en la carpeta de datos.

  Cada archivo guarda un registro por línea, con los campos separados por `;`.
  Todos los módulos del sistema usan estas funciones para persistir su estado.
  - Integrante 1: base del sistema
  """

  @separador ";"

  @doc """
  Ruta completa de un archivo dentro de la carpeta de datos.

  ## Ejemplo

      iex> Emergencias.Persistencia.ruta("usuarios.txt") |> Path.basename()
      "usuarios.txt"
  """
  def ruta(nombre_archivo) do
    directorio = Application.get_env(:emergencias, :directorio_datos, "datos")
    Path.join(directorio, nombre_archivo)
  end

  @doc """
  Lee un archivo línea por línea, sin cargarlo completo como un solo texto, y
  retorna la lista de líneas sin espacios sobrantes. Ignora las líneas en blanco.
  Si el archivo no existe retorna una lista vacía.
  """
  def cargar(nombre_archivo) do
    ruta = ruta(nombre_archivo)

    if File.exists?(ruta) do
      ruta
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(fn linea -> linea == "" end)
      |> Enum.to_list()
    else
      []
    end
  end

  @doc """
  Reemplaza el contenido de un archivo con la lista de líneas indicada.
  Retorna `:ok` o `{:error, razon}`.
  """
  def guardar(nombre_archivo, lineas) do
    ruta = ruta(nombre_archivo)
    contenido = Enum.map(lineas, fn linea -> linea <> "\n" end)

    with :ok <- File.mkdir_p(Path.dirname(ruta)) do
      File.write(ruta, contenido)
    end
  end

  @doc """
  Agrega una línea al final de un archivo, sin borrar lo que ya tiene.
  Sirve para historiales y registros de actividad.
  """
  def agregar(nombre_archivo, linea) do
    ruta = ruta(nombre_archivo)

    with :ok <- File.mkdir_p(Path.dirname(ruta)) do
      File.write(ruta, linea <> "\n", [:append])
    end
  end

  @doc "Une los campos de un registro en una línea."
  def unir(campos), do: Enum.join(campos, @separador)

  @doc "Separa una línea en los campos de un registro."
  def separar(linea), do: String.split(linea, @separador)

  @doc """
  Reemplaza los caracteres que dañarían el formato de una línea: el separador `;`
  y los saltos de línea. Sirve para textos libres, como descripciones.

  ## Ejemplo

      iex> Emergencias.Persistencia.limpiar("agua; urgente")
      "agua, urgente"
  """
  def limpiar(texto) do
    texto
    |> String.replace(@separador, ",")
    |> String.replace(["\n", "\r"], " ")
    |> String.trim()
  end
end
