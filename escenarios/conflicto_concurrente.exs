# Escenario: conflicto concurrente sobre el inventario (regla obligatoria del 1.4.5).
#
# Ejecutar desde la raíz del proyecto:
#
#     mix run escenarios/conflicto_concurrente.exs
#
# Usa una carpeta de datos nueva cada vez, así no depende de ejecuciones anteriores
# ni toca datos/.

defmodule EscenarioConflicto do
  alias Emergencias.Necesidades
  alias Emergencias.Recursos
  alias Emergencias.Recursos.Recurso
  alias Emergencias.Zonas

  def main do
    datos_limpios()

    IO.puts("\n=== 1. Laura y Pedro piden agua al mismo tiempo ===")
    flujo_del_enunciado()

    IO.puts("\n=== 2. Diez solicitudes simultáneas de 10 litros sobre 50 ===")
    diez_solicitudes()

    IO.puts("\n=== 3. Se cancela la necesidad que recibió el agua ===")
    cancelar_y_devolver()
  end

  # Reinicia la aplicación con una carpeta de datos temporal
  defp datos_limpios do
    carpeta =
      Path.join(System.tmp_dir!(), "emergencias_escenario_#{System.unique_integer([:positive])}")

    Application.stop(:emergencias)
    Application.put_env(:emergencias, :directorio_datos, carpeta)
    {:ok, _aplicaciones} = Application.ensure_all_started(:emergencias)
  end

  defp flujo_del_enunciado do
    {:ok, _zona} = Zonas.registrar_zona("centro", "Centro", "critico")

    {:ok, _centro} =
      Recursos.registrar_centro("centro_acopio_1", "Centro de acopio 1", "acopio", "centro")

    {:ok, _recurso} = Recursos.registrar("R001", "agua", 50, "litros", "centro_acopio_1")
    IO.puts("Inventario inicial: R001 agua = 50 litros en centro_acopio_1")

    solicitudes = [
      {"laura", 30, "critica", "Punto de atención sector 3"},
      {"pedro", 25, "alta", "Familias del sector 5"}
    ]

    resultados =
      solicitudes
      |> Enum.map(fn solicitud -> Task.async(fn -> pedir_agua(solicitud) end) end)
      |> Enum.map(fn tarea -> Task.await(tarea) end)

    Enum.each(resultados, fn resultado -> mostrar(resultado) end)

    IO.puts("Quedan #{litros("R001")} litros. Se pidieron 55 y solo había 50:")
    IO.puts("se confirmó la primera solicitud que llegó y la otra se rechazó.")
  end

  defp pedir_agua({usuario, cantidad, prioridad, descripcion}) do
    {:ok, necesidad} =
      Necesidades.registrar("agua", cantidad, prioridad, "centro", descripcion, usuario)

    {usuario, necesidad.id, cantidad, Necesidades.asignar_recurso(necesidad.id, "agua", cantidad)}
  end

  defp mostrar({usuario, id, cantidad, {:ok, necesidad}}) do
    IO.puts("  #{usuario}: #{id} recibió #{cantidad} litros (estado: #{necesidad.estado})")
  end

  defp mostrar({usuario, id, cantidad, {:error, razon}}) do
    IO.puts("  #{usuario}: #{id} NO recibió #{cantidad} litros (#{razon})")
  end

  defp diez_solicitudes do
    {:ok, _zona} = Zonas.registrar_zona("norte", "Norte", "alto")

    {:ok, _centro} =
      Recursos.registrar_centro("centro_acopio_2", "Centro de acopio 2", "acopio", "norte")

    {:ok, _recurso} = Recursos.registrar("R002", "agua", 50, "litros", "centro_acopio_2")

    resultados =
      1..10
      |> Enum.map(fn numero ->
        Task.async(fn -> Recursos.reservar("agua", 10, "norte", "solicitud #{numero}") end)
      end)
      |> Enum.map(fn tarea -> Task.await(tarea) end)

    confirmadas = Enum.count(resultados, fn resultado -> confirmada?(resultado) end)

    IO.puts("  Confirmadas: #{confirmadas} de 10")
    IO.puts("  Rechazadas por stock insuficiente: #{10 - confirmadas}")
    IO.puts("  Quedan #{litros("R002")} litros (nunca negativo)")
  end

  defp confirmada?({:ok, _tomas}), do: true
  defp confirmada?(_resultado), do: false

  defp cancelar_y_devolver do
    [asignada] = Necesidades.listar(zona: "centro", estado: "asignada")
    {:ok, _necesidad} = Necesidades.cancelar(asignada.id)

    IO.puts("  #{asignada.id} cancelada: sus #{asignada.asignado} litros volvieron al centro.")
    IO.puts("  Hay #{litros("R001")} litros en centro_acopio_1.")
  end

  defp litros(codigo) do
    {:ok, recurso} = Recursos.consultar(codigo)
    Recurso.total(recurso)
  end
end

EscenarioConflicto.main()
