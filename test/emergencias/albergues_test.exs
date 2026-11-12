defmodule Emergencias.AlberguesTest do
  use ExUnit.Case

  alias Emergencias.Albergues
  alias Emergencias.Personas
  alias Emergencias.Recursos
  alias Emergencias.Zonas

  # Las pruebas con @tag :personas usan Emergencias.Personas (Integrante 3). Mientras
  # ese módulo no esté en el proyecto, test_helper.exs las omite.

  # ========== Datos de prueba y ayudas ==========

  defp unico(prefijo), do: "#{prefijo}#{System.unique_integer([:positive])}"

  defp crear_zona do
    zona = unico("zona_")
    {:ok, _zona} = Zonas.registrar_zona(zona, "Zona de prueba", "critico")
    zona
  end

  # Ayuda que depende de la firma de Personas (Integrante 3); ajustarla si cambia
  defp crear_persona(zona) do
    documento = unico("doc")
    {:ok, _persona} = Personas.registrar(documento, "Persona de prueba", zona, "reportada")
    documento
  end

  defp crear_albergue(zona, capacidad) do
    codigo = unico("A")
    {:ok, _albergue} = Albergues.registrar(codigo, "Albergue de prueba", zona, capacidad)
    codigo
  end

  defp estado_persona(documento) do
    {:ok, persona} = Personas.obtener(documento)
    persona.estado
  end

  defp confirmado?({:ok, _albergue}), do: true
  defp confirmado?(_resultado), do: false

  # ========== Pruebas ==========

  describe "registro" do
    test "registra un albergue que además queda como centro de apoyo de tipo albergue" do
      zona = crear_zona()
      codigo = crear_albergue(zona, 150)

      assert Albergues.cupos(codigo) == {:ok, 150}
      assert Albergues.zona_de(codigo) == {:ok, zona}
      assert Recursos.zona_de(codigo) == {:ok, zona}

      centro = Enum.find(Recursos.listar_centros(), fn centro -> centro.codigo == codigo end)
      assert centro.tipo == :albergue
    end

    test "con ocupación inicial: el albergue ya tiene gente al registrarse" do
      zona = crear_zona()
      codigo = unico("A")

      assert {:ok, albergue} = Albergues.registrar(codigo, "Albergue Sur", zona, 150, 148)
      assert albergue.ocupacion_inicial == 148
      assert Albergues.cupos(codigo) == {:ok, 2}
    end

    test "valida código, zona, capacidad y ocupación inicial" do
      zona = crear_zona()
      codigo = crear_albergue(zona, 10)

      assert Albergues.registrar(codigo, "Otro", zona, 10) == {:error, :ya_existe}
      assert Albergues.registrar(unico("A"), "Otro", "no_existe", 10) == {:error, :zona_no_existe}
      assert Albergues.registrar(unico("A"), "Otro", zona, 0) == {:error, :capacidad_invalida}
      assert Albergues.registrar(unico("A"), "Otro", zona, -3) == {:error, :capacidad_invalida}

      assert Albergues.registrar(unico("A"), "Otro", zona, 10, 11) ==
               {:error, :ocupacion_invalida}

      assert Albergues.registrar(unico("A"), "Otro", zona, 10, -1) ==
               {:error, :ocupacion_invalida}

      assert Albergues.cupos("no_existe") == {:error, :albergue_no_existe}
      assert Albergues.zona_de("no_existe") == {:error, :albergue_no_existe}
    end
  end

  describe "ingreso y salida" do
    @tag :personas
    test "el ingreso ocupa un cupo y la persona queda en albergue" do
      zona = crear_zona()
      codigo = crear_albergue(zona, 3)
      documento = crear_persona(zona)

      assert {:ok, _albergue} = Albergues.ingresar(codigo, documento)
      assert Albergues.cupos(codigo) == {:ok, 2}
      assert estado_persona(documento) == :en_albergue
    end

    @tag :personas
    test "no se supera la capacidad máxima, contando la ocupación inicial" do
      zona = crear_zona()
      codigo = unico("A")
      {:ok, _albergue} = Albergues.registrar(codigo, "Albergue", zona, 3, 1)

      assert {:ok, _albergue} = Albergues.ingresar(codigo, crear_persona(zona))
      assert {:ok, _albergue} = Albergues.ingresar(codigo, crear_persona(zona))
      assert Albergues.ingresar(codigo, crear_persona(zona)) == {:error, :albergue_lleno}
    end

    @tag :personas
    test "una persona no puede estar en dos albergues ni ingresar si no está registrada" do
      zona = crear_zona()
      norte = crear_albergue(zona, 5)
      sur = crear_albergue(zona, 5)
      documento = crear_persona(zona)

      assert {:ok, _albergue} = Albergues.ingresar(norte, documento)
      assert Albergues.ingresar(sur, documento) == {:error, :ya_esta_en_un_albergue}
      assert Albergues.ingresar(sur, "doc_que_no_existe") == {:error, :persona_no_existe}
      assert Albergues.cupos(sur) == {:ok, 5}
    end

    @tag :personas
    test "la salida libera el cupo y la persona pasa a trasladada" do
      zona = crear_zona()
      codigo = crear_albergue(zona, 4)
      documento = crear_persona(zona)
      {:ok, _albergue} = Albergues.ingresar(codigo, documento)

      assert {:ok, _albergue} = Albergues.salir(codigo, documento)
      assert Albergues.cupos(codigo) == {:ok, 4}
      assert estado_persona(documento) == :trasladada
      assert Albergues.salir(codigo, documento) == {:error, :no_esta_en_albergue}
    end

    @tag :personas
    test "10 ingresos simultáneos a un albergue de 3 cupos: exactamente 3 se confirman" do
      zona = crear_zona()
      codigo = crear_albergue(zona, 3)
      documentos = Enum.map(1..10, fn _numero -> crear_persona(zona) end)

      resultados =
        documentos
        |> Enum.map(fn documento ->
          Task.async(fn -> Albergues.ingresar(codigo, documento) end)
        end)
        |> Enum.map(fn tarea -> Task.await(tarea) end)

      assert Enum.count(resultados, fn resultado -> confirmado?(resultado) end) == 3

      assert Enum.count(resultados, fn resultado -> resultado == {:error, :albergue_lleno} end) ==
               7

      assert Albergues.cupos(codigo) == {:ok, 0}
    end
  end

  describe "reportes y consulta" do
    test "reporte de albergues con mayor ocupación" do
      zona = crear_zona()
      lleno = unico("A")
      medio = unico("A")
      vacio = unico("A")
      {:ok, _albergue} = Albergues.registrar(lleno, "Lleno", zona, 2, 2)
      {:ok, _albergue} = Albergues.registrar(medio, "Medio", zona, 4, 1)
      {:ok, _albergue} = Albergues.registrar(vacio, "Vacío", zona, 4)

      mios = [lleno, medio, vacio]

      orden =
        Albergues.mas_ocupados(1000)
        |> Enum.map(fn albergue -> albergue.codigo end)
        |> Enum.filter(fn codigo -> codigo in mios end)

      assert orden == [lleno, medio, vacio]
    end

    test "consultar un albergue muestra su ocupación y sus recursos" do
      zona = crear_zona()
      albergue = crear_albergue(zona, 20)
      centro = unico("centro_")
      recurso = unico("R")
      {:ok, _centro} = Recursos.registrar_centro(centro, "Centro de acopio", "acopio", zona)
      {:ok, _recurso} = Recursos.registrar(recurso, "agua", 200, "litros", centro)
      {:ok, _recurso} = Recursos.transferir(recurso, centro, albergue, 30)

      assert {:ok, estado} = Albergues.consultar(albergue)
      assert estado.cupos == 20
      assert estado.porcentaje == 0.0
      assert [%{codigo: ^recurso, cantidad: 30}] = estado.recursos
    end
  end
end
