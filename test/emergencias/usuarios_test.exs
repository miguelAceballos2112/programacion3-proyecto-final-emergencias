defmodule Emergencias.UsuariosTest do
  use ExUnit.Case

  alias Emergencias.Usuarios

  # Cada prueba usa un usuario con nombre único, porque todas comparten el mismo
  # proceso Usuarios (lo inicia la aplicación)
  setup do
    {:ok, usuario: "usuario#{System.unique_integer([:positive])}"}
  end

  describe "conectar/4" do
    test "si el usuario no existe, lo registra automáticamente", %{usuario: usuario} do
      assert {:ok, datos} = Usuarios.conectar(usuario, "1234", "coordinador", "centro")
      assert datos.registrado == true
      assert datos.tipo == :coordinador
      assert datos.zona == "centro"
      refute Map.has_key?(datos, :clave_hash)
    end

    test "si el usuario existe, valida la contraseña", %{usuario: usuario} do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      :ok = Usuarios.desconectar(usuario)

      assert {:error, :credenciales_invalidas} =
               Usuarios.conectar(usuario, "incorrecta", "ciudadano", "norte")

      assert {:ok, datos} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      assert datos.registrado == false
    end

    test "un usuario existente conserva el tipo con el que se registró", %{usuario: usuario} do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      :ok = Usuarios.desconectar(usuario)

      {:ok, datos} = Usuarios.conectar(usuario, "1234", "administrador", "sur")
      assert datos.tipo == :ciudadano
      assert datos.zona == "norte"
    end

    test "no permite dos sesiones del mismo usuario", %{usuario: usuario} do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      assert {:error, :ya_conectado} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
    end

    test "rechaza datos inválidos", %{usuario: usuario} do
      assert {:error, :tipo_invalido} = Usuarios.conectar(usuario, "1234", "jefe", "centro")

      assert {:error, :contrasena_invalida} =
               Usuarios.conectar(usuario, "", "ciudadano", "centro")

      assert {:error, :zona_invalida} = Usuarios.conectar(usuario, "1234", "ciudadano", "")

      assert {:error, :usuario_invalido} =
               Usuarios.conectar("con espacio", "1234", "ciudadano", "x")

      assert {:error, :usuario_invalido} = Usuarios.conectar("a;b", "1234", "ciudadano", "x")
    end

    test "dos conexiones simultáneas del mismo usuario: solo una prospera", %{usuario: usuario} do
      resultados =
        1..2
        |> Enum.map(fn _ ->
          Task.async(fn -> Usuarios.conectar(usuario, "1234", "ciudadano", "centro") end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, fn resultado -> match?({:ok, _}, resultado) end) == 1
      assert Enum.count(resultados, fn resultado -> resultado == {:error, :ya_conectado} end) == 1
    end

    test "varios usuarios se conectan al mismo tiempo" do
      nombres = for _ <- 1..20, do: "masivo#{System.unique_integer([:positive])}"

      resultados =
        nombres
        |> Enum.map(fn nombre ->
          Task.async(fn -> Usuarios.conectar(nombre, "1234", "voluntario", "centro") end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.all?(resultados, fn resultado -> match?({:ok, _}, resultado) end)
      assert Enum.all?(nombres, fn nombre -> match?({:ok, _}, Usuarios.sesion(nombre)) end)
    end
  end

  describe "registrar/5" do
    test "registra un usuario con su nombre completo", %{usuario: usuario} do
      assert {:ok, datos} =
               Usuarios.registrar(usuario, "1234", "Laura Gómez", "voluntario", "centro")

      assert datos.nombre_completo == "Laura Gómez"
    end

    test "no permite registrar dos veces el mismo usuario", %{usuario: usuario} do
      {:ok, _} = Usuarios.registrar(usuario, "1234", "Laura", "voluntario", "centro")

      assert {:error, :ya_existe} =
               Usuarios.registrar(usuario, "5678", "Otra Laura", "ciudadano", "norte")
    end
  end

  describe "desconectar/1 y sesion/1" do
    test "desconectar termina la sesión", %{usuario: usuario} do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      assert {:ok, datos} = Usuarios.sesion(usuario)
      assert datos.usuario == usuario

      assert Usuarios.desconectar(usuario) == :ok
      assert Usuarios.sesion(usuario) == {:error, :no_conectado}
    end

    test "desconectar a alguien que no está conectado devuelve un error", %{usuario: usuario} do
      assert Usuarios.desconectar(usuario) == {:error, :no_conectado}
    end
  end

  describe "autorizar/2" do
    test "permite la acción si el tipo tiene permiso", %{usuario: usuario} do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "coordinador", "centro")
      assert Usuarios.autorizar(usuario, :register_zone) == :ok
    end

    test "rechaza la acción si el tipo no tiene permiso", %{usuario: usuario} do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "ciudadano", "centro")
      assert Usuarios.autorizar(usuario, :register_zone) == {:error, :sin_permiso}
    end

    test "rechaza a un usuario desconectado", %{usuario: usuario} do
      assert Usuarios.autorizar(usuario, :register_need) == {:error, :no_conectado}
    end
  end

  describe "actividad" do
    test "conectar y desconectar quedan registrados", %{usuario: usuario} do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      :ok = Usuarios.desconectar(usuario)

      acciones = usuario |> Usuarios.actividad() |> Enum.map(fn {_fecha, accion, _} -> accion end)
      assert acciones == ["connect", "disconnect"]
    end

    test "registrar_actividad guarda la acción con su detalle", %{usuario: usuario} do
      Usuarios.registrar_actividad(usuario, "register_need", "agua; 30 litros")

      assert [{_fecha, "register_need", "agua, 30 litros"}] = Usuarios.actividad(usuario)
    end

    test "un usuario sin actividad devuelve una lista vacía", %{usuario: usuario} do
      assert Usuarios.actividad(usuario) == []
    end
  end

  describe "tolerancia a fallos y persistencia" do
    test "si el servidor falla, el supervisor lo reinicia y recupera los usuarios", %{
      usuario: usuario
    } do
      {:ok, _} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      pid_anterior = Process.whereis(Usuarios)

      Process.exit(pid_anterior, :kill)
      esperar_reinicio(Usuarios, pid_anterior)

      # Las sesiones se pierden al reiniciar, pero el usuario se recupera del archivo
      assert Usuarios.sesion(usuario) == {:error, :no_conectado}
      assert {:ok, datos} = Usuarios.conectar(usuario, "1234", "ciudadano", "norte")
      assert datos.registrado == false
    end
  end

  # Espera, consultando cada 10 ms, a que el supervisor inicie un proceso nuevo
  defp esperar_reinicio(nombre, pid_anterior, intentos \\ 100)
  defp esperar_reinicio(_nombre, _pid_anterior, 0), do: flunk("El servidor no se reinició")

  defp esperar_reinicio(nombre, pid_anterior, intentos) do
    case Process.whereis(nombre) do
      nil -> reintentar(nombre, pid_anterior, intentos)
      ^pid_anterior -> reintentar(nombre, pid_anterior, intentos)
      _nuevo -> :ok
    end
  end

  defp reintentar(nombre, pid_anterior, intentos) do
    :timer.sleep(10)
    esperar_reinicio(nombre, pid_anterior, intentos - 1)
  end
end
