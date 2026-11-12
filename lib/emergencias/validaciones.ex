defmodule Emergencias.Validaciones do
  @moduledoc """
  Validaciones de entradas del usuario, antes de modificar el estado.
  Todas retornan `:ok` o `{:error, razon}`, donde la razón la indica quien llama,
  salvo `opcion/3`, que si el valor es válido retorna la opción ya convertida.
  - Integrante 1: base del sistema
  - Integrante 2: `entero_positivo/2` y `opcion/3`, para la logística
  """

  @doc """
  Un texto es válido si no está vacío y no contiene `;` ni saltos de línea,
  que son los caracteres que usan los archivos de persistencia.

  ## Ejemplos

      iex> Emergencias.Validaciones.texto("centro", :nombre_invalido)
      :ok

      iex> Emergencias.Validaciones.texto("a;b", :nombre_invalido)
      {:error, :nombre_invalido}
  """
  def texto(valor, error) when is_binary(valor) do
    if String.trim(valor) != "" and not String.contains?(valor, [";", "\n", "\r"]) do
      :ok
    else
      {:error, error}
    end
  end

  def texto(_valor, error), do: {:error, error}

  @doc """
  Un entero no negativo es un número entero mayor o igual a cero.

  ## Ejemplos

      iex> Emergencias.Validaciones.entero_no_negativo(0, :cantidad_invalida)
      :ok

      iex> Emergencias.Validaciones.entero_no_negativo(-5, :cantidad_invalida)
      {:error, :cantidad_invalida}
  """
  def entero_no_negativo(valor, _error) when is_integer(valor) and valor >= 0, do: :ok
  def entero_no_negativo(_valor, error), do: {:error, error}

  @doc """
  Un entero positivo es un número entero mayor que cero. Sirve para las cantidades
  que se piden o se mueven y para la capacidad de un albergue.

  ## Ejemplos

      iex> Emergencias.Validaciones.entero_positivo(5, :cantidad_invalida)
      :ok

      iex> Emergencias.Validaciones.entero_positivo(0, :cantidad_invalida)
      {:error, :cantidad_invalida}
  """
  def entero_positivo(valor, _error) when is_integer(valor) and valor > 0, do: :ok
  def entero_positivo(_valor, error), do: {:error, error}

  @doc """
  Convierte un texto en una de las opciones permitidas (categorías, prioridades,
  estados). No distingue mayúsculas e ignora los espacios sobrantes. Si recibe una
  opción que ya es un átomo, solo revisa que esté permitida.
  Retorna `{:ok, opcion}` o `{:error, razon}`.

  ## Ejemplos

      iex> Emergencias.Validaciones.opcion(" Agua", [:agua, :alimentos], :categoria_invalida)
      {:ok, :agua}

      iex> Emergencias.Validaciones.opcion("gasolina", [:agua, :alimentos], :categoria_invalida)
      {:error, :categoria_invalida}
  """
  def opcion(valor, permitidas, error) when is_binary(valor) do
    buscar_opcion(permitidas, valor |> String.trim() |> String.downcase(), error)
  end

  def opcion(valor, permitidas, error) do
    if Enum.member?(permitidas, valor), do: {:ok, valor}, else: {:error, error}
  end

  # Caso base: no quedan opciones por comparar, el texto no es válido
  defp buscar_opcion([], _texto, error), do: {:error, error}

  # Caso recursivo: compara el texto con la primera opción y, si no coincide, sigue
  # con el resto
  defp buscar_opcion([head | tail], texto, error) do
    if "#{head}" == texto do
      {:ok, head}
    else
      buscar_opcion(tail, texto, error)
    end
  end
end
