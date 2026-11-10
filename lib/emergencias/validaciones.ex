defmodule Emergencias.Validaciones do
  @moduledoc """
  Validaciones de entradas del usuario, antes de modificar el estado.
  Todas retornan `:ok` o `{:error, razon}`, donde la razón la indica quien llama.
  - Integrante 1: base del sistema
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
end
