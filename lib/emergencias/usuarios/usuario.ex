defmodule Emergencias.Usuarios.Usuario do
  @moduledoc """
  Usuario que participa en la coordinación de la emergencia.

  La contraseña no se guarda: se guarda su huella (hash SHA-256), para que el archivo
  de usuarios no contenga contraseñas legibles.
  - Integrante 1: usuarios
  """

  alias Emergencias.Persistencia
  alias Emergencias.Validaciones

  @tipos [:ciudadano, :voluntario, :coordinador, :administrador]

  @enforce_keys [:usuario, :clave_hash, :nombre_completo, :tipo, :zona]
  defstruct [:usuario, :clave_hash, :nombre_completo, :tipo, :zona]

  @doc """
  Crea un usuario validando todos sus datos.
  Retorna `{:ok, %Usuario{}}` o `{:error, razon}`.

  El tipo puede llegar como átomo o como texto (por ejemplo, desde un comando).

  ## Ejemplos

      iex> {:ok, usuario} = Emergencias.Usuarios.Usuario.nuevo("laura", "1234", "Laura Gómez", "coordinador", "centro")
      iex> usuario.tipo
      :coordinador

      iex> Emergencias.Usuarios.Usuario.nuevo("laura", "1234", "Laura", "jefe", "centro")
      {:error, :tipo_invalido}
  """
  def nuevo(usuario, contrasena, nombre_completo, tipo, zona) do
    with :ok <- validar_identificador(usuario),
         :ok <- Validaciones.texto(contrasena, :contrasena_invalida),
         :ok <- Validaciones.texto(nombre_completo, :nombre_invalido),
         :ok <- Validaciones.texto(zona, :zona_invalida),
         {:ok, tipo} <- normalizar_tipo(tipo) do
      {:ok,
       %__MODULE__{
         usuario: usuario,
         clave_hash: cifrar(contrasena),
         nombre_completo: nombre_completo,
         tipo: tipo,
         zona: zona
       }}
    end
  end

  @doc "Indica si la contraseña corresponde a la huella guardada del usuario."
  def clave_correcta?(%__MODULE__{clave_hash: clave_hash}, contrasena) do
    clave_hash == cifrar(contrasena)
  end

  @doc "Datos del usuario que se pueden mostrar, sin la huella de la contraseña."
  def publico(%__MODULE__{} = usuario) do
    %{
      usuario: usuario.usuario,
      nombre_completo: usuario.nombre_completo,
      tipo: usuario.tipo,
      zona: usuario.zona
    }
  end

  @doc "Convierte el usuario en una línea del archivo `usuarios.txt`."
  def a_linea(%__MODULE__{} = usuario) do
    Persistencia.unir([
      usuario.usuario,
      usuario.clave_hash,
      usuario.nombre_completo,
      Atom.to_string(usuario.tipo),
      usuario.zona
    ])
  end

  @doc "Reconstruye un usuario desde una línea del archivo `usuarios.txt`."
  def desde_linea(linea) do
    case Persistencia.separar(linea) do
      [usuario, clave_hash, nombre_completo, tipo, zona] ->
        with {:ok, tipo} <- normalizar_tipo(tipo) do
          {:ok,
           %__MODULE__{
             usuario: usuario,
             clave_hash: clave_hash,
             nombre_completo: nombre_completo,
             tipo: tipo,
             zona: zona
           }}
        end

      _otra ->
        {:error, :linea_invalida}
    end
  end

  # El nombre de usuario no puede tener espacios, para poder escribirlo en un comando
  defp validar_identificador(usuario) do
    with :ok <- Validaciones.texto(usuario, :usuario_invalido) do
      if String.contains?(usuario, " "), do: {:error, :usuario_invalido}, else: :ok
    end
  end

  # Acepta un tipo ya convertido (átomo) o el texto que escribió el usuario.
  # Se busca entre los tipos conocidos, en lugar de crear átomos con texto externo.
  defp normalizar_tipo(tipo) when is_atom(tipo) do
    if Enum.member?(@tipos, tipo), do: {:ok, tipo}, else: {:error, :tipo_invalido}
  end

  defp normalizar_tipo(tipo) when is_binary(tipo) do
    texto = tipo |> String.trim() |> String.downcase()

    case Enum.find(@tipos, fn conocido -> Atom.to_string(conocido) == texto end) do
      nil -> {:error, :tipo_invalido}
      encontrado -> {:ok, encontrado}
    end
  end

  defp normalizar_tipo(_tipo), do: {:error, :tipo_invalido}

  defp cifrar(contrasena) do
    :crypto.hash(:sha256, contrasena) |> Base.encode16(case: :lower)
  end
end
