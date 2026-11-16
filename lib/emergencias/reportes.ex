defmodule Emergencias.Reportes do
  @moduledoc """
  Resumen global (`summary`) y estado general de una zona (`zone_status`).

  No es un proceso: solo consulta a los servidores. Para no preguntarles uno por uno,
  lanza una tarea (`Task.async`) por cada consulta y después espera todas las
  respuestas (`Task.await`). Así las consultas a los distintos servidores corren al
  mismo tiempo.
  - Integrante 1: resumen
  """

  alias Emergencias.Albergues
  alias Emergencias.Albergues.Albergue
  alias Emergencias.Mascotas
  alias Emergencias.Necesidades
  alias Emergencias.Personas
  alias Emergencias.Recursos
  alias Emergencias.Recursos.Recurso
  alias Emergencias.Usuarios
  alias Emergencias.Zonas

  # Personas localizadas: las que tienen paradero conocido
  @con_paradero [:localizada, :en_albergue, :trasladada, :reunificada]

  @doc """
  Resumen global: recursos restantes, necesidades pendientes, personas, mensajes,
  reportes de mascotas, albergues y zonas. Retorna un mapa.
  """
  def resumen do
    datos =
      consultar_en_paralelo([
        {:zonas, fn -> Zonas.listar() end},
        {:recursos, fn -> Recursos.listar() end},
        {:necesidades, fn -> Necesidades.listar() end},
        {:pendientes, fn -> Necesidades.pendientes() end},
        {:criticos, fn -> Necesidades.recursos_criticos() end},
        {:albergues, fn -> Albergues.listar() end},
        {:personas, fn -> Personas.buscar() end},
        {:mensajes, fn -> Personas.mensajes() end},
        {:mascotas, fn -> Mascotas.listar() end},
        {:conectados, fn -> Usuarios.conectados() end}
      ])

    %{
      zonas: Enum.count(datos.zonas),
      conectados: datos.conectados,
      recursos: Enum.map(datos.recursos, fn recurso -> resumen_de_recurso(recurso) end),
      recursos_por_categoria: sumar_por_categoria(datos.recursos, %{}),
      necesidades: Enum.count(datos.necesidades),
      necesidades_por_estado: contar_por(datos.necesidades, :estado),
      necesidades_pendientes: datos.pendientes,
      recursos_criticos: datos.criticos,
      albergues: resumen_de_albergues(datos.albergues),
      personas: Enum.count(datos.personas),
      personas_por_estado: contar_por(datos.personas, :estado),
      personas_localizadas: Enum.count(datos.personas, fn p -> p.estado in @con_paradero end),
      mensajes: Enum.count(datos.mensajes),
      mensajes_por_estado: contar_por(datos.mensajes, :estado),
      mascotas: Enum.count(datos.mascotas),
      mascotas_por_estado: contar_por(datos.mascotas, :estado),
      mascotas_por_tipo: contar_por(datos.mascotas, :tipo)
    }
  end

  @doc """
  Estado general de una zona (`zone_status`): sus datos, las estadísticas acumuladas
  de sus sectores y puntos (recursivas, de `Zonas`) y todo lo que tiene asociado:
  albergues, necesidades, centros con sus recursos, personas y reportes de mascotas.
  Retorna `{:ok, mapa}` o `{:error, :zona_no_existe}`.
  """
  def estado_zona(codigo) do
    with {:ok, %{zona: zona, estadisticas: estadisticas}} <- Zonas.estado(codigo) do
      filtro = [{"zona", codigo}]

      datos =
        consultar_en_paralelo([
          {:albergues, fn -> Albergues.listar() end},
          {:necesidades, fn -> Necesidades.listar(filtro) end},
          {:centros, fn -> Recursos.listar_centros() end},
          {:recursos, fn -> Recursos.listar() end},
          {:personas, fn -> Personas.buscar(filtro) end},
          {:mascotas, fn -> Mascotas.listar(filtro) end}
        ])

      centros = Enum.filter(datos.centros, fn centro -> centro.zona == codigo end)
      codigos_de_centros = Enum.map(centros, fn centro -> centro.codigo end)

      {:ok,
       %{
         zona: zona,
         estadisticas: estadisticas,
         albergues: Enum.filter(datos.albergues, fn albergue -> albergue.zona == codigo end),
         necesidades: datos.necesidades,
         centros: centros,
         recursos: recursos_en_centros(datos.recursos, codigos_de_centros),
         personas: datos.personas,
         mascotas: datos.mascotas
       }}
    end
  end

  @doc """
  Cuenta los elementos de una lista según el valor de un campo. Recursiva con
  acumulador: el mapa parcial viaja de una llamada a la siguiente.

  ## Ejemplo

      iex> Emergencias.Reportes.contar_por([%{estado: :a}, %{estado: :b}, %{estado: :a}], :estado)
      %{a: 2, b: 1}
  """
  def contar_por(lista, campo), do: contar_por(lista, campo, %{})

  # Caso base: no quedan elementos, se devuelve lo contado
  defp contar_por([], _campo, acumulado), do: acumulado

  # Caso recursivo: suma uno al valor del primero y sigue con el resto
  defp contar_por([head | tail], campo, acumulado) do
    valor = Map.get(head, campo)
    contar_por(tail, campo, Map.update(acumulado, valor, 1, fn cantidad -> cantidad + 1 end))
  end

  # ========== Funciones auxiliares privadas ==========

  # Lanza una tarea por consulta y después espera todas: las consultas corren a la vez.
  # Retorna un mapa %{nombre => resultado}.
  defp consultar_en_paralelo(consultas) do
    tareas =
      Enum.map(consultas, fn {nombre, consulta} -> {nombre, Task.async(consulta)} end)

    Enum.reduce(tareas, %{}, fn {nombre, tarea}, resultados ->
      Map.put(resultados, nombre, Task.await(tarea))
    end)
  end

  defp resumen_de_recurso(recurso) do
    %{
      codigo: recurso.codigo,
      nombre: recurso.nombre,
      categoria: recurso.categoria,
      unidad: recurso.unidad,
      total: Recurso.total(recurso)
    }
  end

  # Caso base: no quedan recursos
  defp sumar_por_categoria([], acumulado), do: acumulado

  # Caso recursivo: suma el total del primero a su categoría y sigue con el resto
  defp sumar_por_categoria([head | tail], acumulado) do
    total = Recurso.total(head)

    sumar_por_categoria(
      tail,
      Map.update(acumulado, head.categoria, total, fn suma -> suma + total end)
    )
  end

  defp resumen_de_albergues(albergues) do
    capacidad = albergues |> Enum.map(fn albergue -> albergue.capacidad end) |> Enum.sum()

    ocupacion =
      albergues |> Enum.map(fn albergue -> Albergue.ocupacion(albergue) end) |> Enum.sum()

    %{
      cantidad: Enum.count(albergues),
      capacidad: capacidad,
      ocupacion: ocupacion,
      cupos: capacidad - ocupacion,
      mas_ocupados: albergues |> Albergue.ordenar_por_ocupacion() |> Enum.take(3)
    }
  end

  # Recursos con existencias en los centros indicados, con el total de esos centros
  defp recursos_en_centros(recursos, centros) do
    recursos
    |> Enum.map(fn recurso ->
      cantidad =
        recurso.existencias
        |> Enum.filter(fn {centro, _cantidad} -> Enum.member?(centros, centro) end)
        |> Enum.map(fn {_centro, cantidad} -> cantidad end)
        |> Enum.sum()

      %{resumen_de_recurso(recurso) | total: cantidad}
    end)
    |> Enum.filter(fn recurso -> recurso.total > 0 end)
  end
end
