defmodule Emergencias.ComandosTest do
  use ExUnit.Case

  alias Emergencias.Bitacora
  alias Emergencias.Comandos
  alias Emergencias.Comandos.Base
  alias Emergencias.Comandos.Logistica
  alias Emergencias.Comandos.Personas, as: ComandosPersonas
  alias Emergencias.Permisos
  alias Emergencias.Usuarios

  # ========== Ayudas ==========

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  # Conecta un usuario nuevo y devuelve su nombre
  defp conectar(tipo, zona) do
    usuario = unico("u")
    {:ok, _texto, ^usuario} = Comandos.ejecutar(nil, "connect #{usuario} clave #{tipo} #{zona}")
    usuario
  end

  # Un coordinador con su zona ya registrada
  defp coordinador_con_zona do
    zona = unico("zona_")
    usuario = conectar("coordinador", zona)

    {:ok, _texto, _usuario} =
      Comandos.ejecutar(usuario, "register_zone #{zona} \"Zona prueba\" alto")

    {usuario, zona}
  end

  # Espera hasta que la condición se cumpla (máximo 1 segundo)
  defp esperar(condicion, intentos \\ 50) do
    cond do
      condicion.() -> true
      intentos == 0 -> false
      true -> :timer.sleep(20) && esperar(condicion, intentos - 1)
    end
  end

  # ========== Pruebas ==========

  describe "connect y disconnect" do
    test "connect registra a un usuario nuevo y lo deja conectado" do
      usuario = unico("u")

      assert {:ok, texto, ^usuario} =
               Comandos.ejecutar(
                 nil,
                 ~s(connect #{usuario} 1234 voluntario norte nombre="Ana Ruiz")
               )

      assert texto =~ "Ana Ruiz"
      assert texto =~ "Usuario nuevo registrado"
      assert {:ok, %{tipo: :voluntario, zona: "norte"}} = Usuarios.sesion(usuario)
    end

    test "con una sesión abierta en la consola no se puede conectar otra" do
      usuario = conectar("ciudadano", "centro")

      assert {:error, texto, ^usuario} = Comandos.ejecutar(usuario, "connect otro 1 ciudadano x")
      assert texto =~ "disconnect"
    end

    test "una contraseña incorrecta no conecta" do
      usuario = conectar("ciudadano", "centro")
      {:ok, _texto, nil} = Comandos.ejecutar(usuario, "disconnect")

      assert {:error, texto, nil} = Comandos.ejecutar(nil, "connect #{usuario} otra")
      assert texto =~ "contraseña"
    end

    test "un usuario existente se conecta solo con usuario y contraseña" do
      usuario = conectar("voluntario", "sur")
      {:ok, _texto, nil} = Comandos.ejecutar(usuario, "disconnect")

      assert {:ok, texto, ^usuario} = Comandos.ejecutar(nil, "connect #{usuario} clave")
      assert texto =~ "voluntario de la zona sur"
    end

    test "disconnect cierra la sesión y después se pide conectar de nuevo" do
      usuario = conectar("ciudadano", "centro")

      assert {:ok, _texto, nil} = Comandos.ejecutar(usuario, "disconnect")
      assert {:error, :no_conectado} = Usuarios.sesion(usuario)
      assert {:error, texto, nil} = Comandos.ejecutar(nil, "list_needs")
      assert texto =~ "Primero conéctate"
    end

    test "si el proceso dueño de la sesión termina, la sesión se cierra sola" do
      usuario = unico("u")
      padre = self()

      # Una "pestaña" que se conecta y termina
      pestana =
        spawn(fn ->
          resultado = Comandos.ejecutar(nil, "connect #{usuario} 1 ciudadano centro", self())
          send(padre, {:conectado, resultado})
        end)

      assert_receive {:conectado, {:ok, _texto, ^usuario}}
      refute Process.alive?(pestana)

      assert esperar(fn -> Usuarios.sesion(usuario) == {:error, :no_conectado} end)
      # Ya puede conectarse otra vez
      assert {:ok, _texto, ^usuario} = Comandos.ejecutar(nil, "connect #{usuario} 1")
    end
  end

  describe "despacho" do
    test "un comando que no existe responde un error claro" do
      usuario = conectar("ciudadano", "centro")
      assert {:error, texto, ^usuario} = Comandos.ejecutar(usuario, "borrar_todo")
      assert texto =~ "no existe"
    end

    test "si faltan datos muestra cómo se usa el comando" do
      usuario = conectar("ciudadano", "centro")
      assert {:error, texto, ^usuario} = Comandos.ejecutar(usuario, "register_need agua")
      assert texto =~ "Uso: register_need tipo cantidad prioridad zona descripcion"
    end

    test "unas comillas sin cerrar son un error, no una excepción" do
      assert {:error, texto, nil} = Comandos.ejecutar(nil, ~s(connect "laura))
      assert texto =~ "comillas"
    end

    test "help funciona sin sesión" do
      assert {:ok, texto, nil} = Comandos.ejecutar(nil, "help")
      assert texto =~ "register_need"
      assert {:ok, uso, nil} = Comandos.ejecutar(nil, "help assign_resource")
      assert uso =~ "assign_resource necesidad categoria cantidad"
    end

    test "los textos entre comillas llegan como un solo argumento" do
      {usuario, zona} = coordinador_con_zona()

      assert {:ok, texto, ^usuario} =
               Comandos.ejecutar(
                 usuario,
                 ~s(register_shelter #{unico("A")} "Albergue Norte" #{zona} 10)
               )

      assert texto =~ "registrado en la zona #{zona}"
    end

    test "todo comando de los módulos tiene su regla de permisos" do
      comandos = Base.comandos() ++ Logistica.comandos() ++ ComandosPersonas.comandos()

      for comando <- comandos, comando != "help" do
        assert {:ok, _accion} = Permisos.accion(comando), "#{comando} no tiene permisos"
      end
    end
  end

  describe "permisos y zona" do
    test "un ciudadano no puede asignar recursos y queda registrado como denegado" do
      usuario = conectar("ciudadano", "centro")

      assert {:error, texto, ^usuario} = Comandos.ejecutar(usuario, "assign_resource N001 agua 5")
      assert texto =~ "no puede ejecutar"

      eventos = Bitacora.consultar(usuario)

      assert Enum.any?(eventos, fn e ->
               e.accion == "assign_resource" and e.resultado == "denegado"
             end)
    end

    test "un coordinador solo modifica su zona" do
      {usuario, zona} = coordinador_con_zona()
      otra = unico("otra_")
      {:ok, _zona} = Emergencias.Zonas.registrar_zona(otra, "Otra", "bajo")

      assert {:ok, _texto, _u} =
               Comandos.ejecutar(usuario, ~s(register_need agua 5 alta #{zona} "En su zona"))

      assert {:error, texto, _u} =
               Comandos.ejecutar(usuario, ~s(register_need agua 5 alta #{otra} "En otra zona"))

      assert texto =~ "su zona principal"

      # Sus consultas son globales
      assert {:ok, _texto, _u} = Comandos.ejecutar(usuario, "zone_status #{otra}")
    end

    test "el administrador no tiene límite de zona" do
      admin = conectar("administrador", unico("zona_"))
      zona = unico("zona_")

      assert {:ok, _texto, _u} = Comandos.ejecutar(admin, "register_zone #{zona} Lejana medio")

      assert {:ok, _texto, _u} =
               Comandos.ejecutar(admin, ~s(register_need agua 5 alta #{zona} "x"))
    end

    test "show_activity de otro usuario es solo para administradores" do
      ciudadano = conectar("ciudadano", "centro")
      otro = conectar("ciudadano", "centro")
      admin = conectar("administrador", "centro")

      assert {:error, _texto, _u} = Comandos.ejecutar(ciudadano, "show_activity #{otro}")
      assert {:ok, texto, _u} = Comandos.ejecutar(admin, "show_activity #{otro}")
      assert texto =~ "connect"
    end
  end

  describe "conflicto concurrente a través del despachador" do
    test "dos asignaciones simultáneas nunca superan el inventario" do
      {usuario, zona} = coordinador_con_zona()
      centro = unico("centro_")
      recurso = unico("R")

      for linea <- [
            "register_center #{centro} Acopio acopio #{zona}",
            "register_resource #{recurso} agua 50 litros #{centro}",
            ~s(register_need agua 30 critica #{zona} "Punto 3"),
            ~s(register_need agua 25 alta #{zona} "Sector 5")
          ] do
        assert {:ok, _texto, _u} = Comandos.ejecutar(usuario, linea)
      end

      [n1, n2] =
        [{"zona", zona}]
        |> Emergencias.Necesidades.listar()
        |> Enum.map(fn necesidad -> necesidad.id end)

      resultados =
        [{n1, 30}, {n2, 25}]
        |> Enum.map(fn {id, cantidad} ->
          Task.async(fn ->
            Comandos.ejecutar(usuario, "assign_resource #{id} agua #{cantidad}")
          end)
        end)
        |> Enum.map(fn tarea -> Task.await(tarea) end)

      confirmadas = Enum.count(resultados, fn {resultado, _texto, _u} -> resultado == :ok end)
      assert confirmadas == 1
      assert {:ok, disponible} = Emergencias.Recursos.disponibilidad("agua", zona)
      assert disponible in [20, 25]
    end
  end

  describe "comandos de la base" do
    test "register_sector, register_point, list_zones y zone_status" do
      {usuario, zona} = coordinador_con_zona()

      assert {:ok, _t, _u} =
               Comandos.ejecutar(usuario, ~s(register_sector #{zona} s1 "Sector 1" alto 40))

      assert {:ok, _t, _u} =
               Comandos.ejecutar(usuario, ~s(register_point #{zona} s1 p1 "Punto 1" 10))

      assert {:ok, lista, _u} = Comandos.ejecutar(usuario, "list_zones")
      assert lista =~ zona

      assert {:ok, estado, _u} = Comandos.ejecutar(usuario, "zone_status #{zona}")
      assert estado =~ "Personas afectadas (acumulado): 50"
      assert estado =~ "s1: 50 personas"
    end

    test "summary es para coordinadores y muestra el resumen global" do
      {coordinador, _zona} = coordinador_con_zona()
      ciudadano = conectar("ciudadano", "centro")

      assert {:ok, texto, _u} = Comandos.ejecutar(coordinador, "summary")
      assert texto =~ "Resumen global"
      assert texto =~ "Recursos restantes"
      assert texto =~ "Mensajes"
      assert {:error, _texto, _u} = Comandos.ejecutar(ciudadano, "summary")
    end

    test "zone_status de una zona que no existe" do
      usuario = conectar("ciudadano", "centro")
      assert {:error, texto, _u} = Comandos.ejecutar(usuario, "zone_status #{unico("nada_")}")
      assert texto =~ "no existe"
    end
  end
end
