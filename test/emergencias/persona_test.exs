defmodule Emergencias.Personas.PersonaTest do
  # Pruebas de funciones puras: no usan procesos ni archivos
  use ExUnit.Case, async: true

  alias Emergencias.Personas.Familia
  alias Emergencias.Personas.Mensaje
  alias Emergencias.Personas.Persona

  describe "transiciones de estado" do
    test "permite las transiciones de la tabla" do
      assert Persona.puede_pasar(:sin_informacion, :reportada) == :ok
      assert Persona.puede_pasar(:localizada, :reunificada) == :ok
      assert Persona.puede_pasar(:en_albergue, :trasladada) == :ok
    end

    test "rechaza las que no están en la tabla" do
      assert Persona.puede_pasar(:reportada, :sin_informacion) == {:error, :transicion_invalida}
      assert Persona.puede_pasar(:en_albergue, :reunificada) == {:error, :transicion_invalida}
    end

    test "reunificada es terminal: no admite ninguna transición" do
      for destino <- Persona.estados() do
        assert Persona.puede_pasar(:reunificada, destino) == {:error, :transicion_invalida}
      end
    end

    test "los estados iniciales no incluyen en_albergue ni reunificada" do
      refute Enum.member?(Persona.estados_iniciales(), :en_albergue)
      refute Enum.member?(Persona.estados_iniciales(), :reunificada)
    end
  end

  describe "documento" do
    test "no admite vacío, espacios ni comas" do
      assert Persona.validar_documento("1094") == :ok
      assert Persona.validar_documento("") == {:error, :documento_invalido}
      assert Persona.validar_documento("10 94") == {:error, :documento_invalido}
      assert Persona.validar_documento("10,94") == {:error, :documento_invalido}
      assert Persona.validar_documento("10;94") == {:error, :documento_invalido}
      assert Persona.validar_documento(1094) == {:error, :documento_invalido}
    end
  end

  describe "a_fila y desde_fila" do
    test "una persona sobrevive al viaje de ida y vuelta" do
      persona = %Persona{
        id: "P001",
        documento: "1094",
        nombre: "Andrés Pérez",
        edad: 30,
        zona: "centro",
        estado: :localizada,
        familia: "F001"
      }

      assert {:ok, ^persona} = persona |> Persona.a_fila() |> Persona.desde_fila()
    end

    test "una persona sin familia queda con el último campo vacío y se recupera" do
      persona = %Persona{
        id: "P002",
        documento: "55",
        nombre: "Ana",
        edad: 0,
        zona: "norte",
        estado: :sin_informacion,
        familia: nil
      }

      campos = Persona.a_fila(persona)
      assert List.last(campos) == ""
      assert {:ok, ^persona} = Persona.desde_fila(campos)
    end

    test "una fila con estado fuera del catálogo o con campos de menos se rechaza" do
      assert Persona.desde_fila(["P1", "1", "Ana", "30", "centro", "volando", ""]) ==
               {:error, :fila_invalida}

      assert Persona.desde_fila(["P1", "1", "Ana", "treinta", "centro", "reportada", ""]) ==
               {:error, :fila_invalida}

      assert Persona.desde_fila(["P1", "1"]) == {:error, :fila_invalida}
    end

    test "las entradas del historial también hacen el viaje de ida y vuelta" do
      primera = %{fecha: "2026-01-01 10:00:00", documento: "1", anterior: nil, nuevo: :reportada, detalle: "Reporte inicial"}
      segunda = %{primera | anterior: :reportada, nuevo: :localizada, detalle: "La vio un voluntario"}

      assert {:ok, ^primera} = primera |> Persona.entrada_a_fila() |> Persona.entrada_desde_fila()
      assert {:ok, ^segunda} = segunda |> Persona.entrada_a_fila() |> Persona.entrada_desde_fila()
      assert Persona.entrada_desde_fila(["solo", "dos"]) == {:error, :fila_invalida}
    end
  end

  describe "Familia" do
    test "un miembro no se agrega dos veces" do
      familia = Familia.crear("F001", "Gómez", "centro")
      assert {:ok, familia} = Familia.agregar_miembro(familia, "1")
      assert Familia.miembro?(familia, "1")
      assert Familia.agregar_miembro(familia, "1") == {:error, :ya_es_miembro}
    end

    test "sobrevive al viaje de ida y vuelta, también sin miembros" do
      vacia = Familia.crear("F001", "Gómez", "centro")
      assert {:ok, ^vacia} = vacia |> Familia.a_fila() |> Familia.desde_fila()

      {:ok, con_miembros} = Familia.agregar_miembro(vacia, "2")
      {:ok, con_miembros} = Familia.agregar_miembro(con_miembros, "1")
      assert {:ok, ^con_miembros} = con_miembros |> Familia.a_fila() |> Familia.desde_fila()
    end
  end

  describe "Mensaje" do
    test "alterna entre pendiente y entregado" do
      mensaje = %Mensaje{id: "MSG001", estado: :pendiente}
      assert {:ok, entregado} = Mensaje.cambiar_estado(mensaje, :entregado)
      assert Mensaje.cambiar_estado(entregado, :entregado) == {:error, :transicion_invalida}
      assert {:ok, %Mensaje{estado: :pendiente}} = Mensaje.cambiar_estado(entregado, :pendiente)
    end

    test "sobrevive al viaje de ida y vuelta" do
      mensaje = %Mensaje{
        id: "MSG001",
        fecha: "2026-01-01 10:00:00",
        remitente: "laura",
        destino_tipo: :familia,
        destino_id: "F001",
        contenido: "Estamos bien",
        estado: :pendiente
      }

      assert {:ok, ^mensaje} = mensaje |> Mensaje.a_fila() |> Mensaje.desde_fila()
    end

    test "una fila con destino o estado fuera del catálogo se rechaza" do
      assert Mensaje.desde_fila(["MSG1", "f", "l", "mascota", "x", "hola", "pendiente"]) ==
               {:error, :fila_invalida}

      assert Mensaje.desde_fila(["MSG1", "f", "l", "persona", "x", "hola", "leido"]) ==
               {:error, :fila_invalida}
    end
  end
end
