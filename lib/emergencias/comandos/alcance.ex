defmodule Emergencias.Comandos.Alcance do
  @moduledoc """
  Regla de zona del coordinador: un coordinador solo modifica datos de su zona
  principal. Sus consultas son globales y el administrador no tiene límite de zona.

  Para cada comando que modifica algo se averigua la zona afectada: a veces viene en
  los argumentos (`register_need agua 30 critica centro ...`) y a veces hay que
  preguntársela al servidor dueño del dato con su `zona_de/1` (por ejemplo, la zona
  de la necesidad `N001`).

  Si el dato no existe, la regla no lo bloquea: el comando seguirá y su módulo
  responderá el error que corresponde (por ejemplo, `:necesidad_no_existe`).
  - Integrante 1: permisos
  """

  alias Emergencias.Albergues
  alias Emergencias.Mascotas
  alias Emergencias.Necesidades
  alias Emergencias.Personas
  alias Emergencias.Recursos

  @doc """
  Revisa si el usuario de la sesión puede modificar la zona que toca el comando.
  Retorna `:ok` o `{:error, :fuera_de_zona}`.
  """
  def revisar(%{tipo: :coordinador, zona: zona_propia}, comando, argumentos) do
    case zona_afectada(comando, argumentos) do
      {:ok, zona} when zona != zona_propia -> {:error, :fuera_de_zona}
      _otro -> :ok
    end
  end

  def revisar(_sesion, _comando, _argumentos), do: :ok

  # La zona viene en los argumentos
  defp zona_afectada("register_zone", [zona | _resto]), do: {:ok, zona}
  defp zona_afectada("register_sector", [zona | _resto]), do: {:ok, zona}
  defp zona_afectada("register_point", [zona | _resto]), do: {:ok, zona}
  defp zona_afectada("register_center", [_codigo, _nombre, _tipo, zona]), do: {:ok, zona}
  defp zona_afectada("register_need", [_t, _c, _p, zona | _resto]), do: {:ok, zona}
  defp zona_afectada("register_shelter", [_codigo, _nombre, zona | _resto]), do: {:ok, zona}
  defp zona_afectada("report_person", [_documento, _nombre, zona | _resto]), do: {:ok, zona}
  defp zona_afectada("register_family", [_nombre, zona]), do: {:ok, zona}
  defp zona_afectada("report_pet", [_t, _e, _n, _c, _ta, zona | _resto]), do: {:ok, zona}

  # La zona se le pregunta al servidor dueño del dato
  defp zona_afectada("register_resource", [_c, _cat, _can, _u, centro | _r]),
    do: Recursos.zona_de(centro)

  defp zona_afectada("add_stock", [_codigo, centro, _cantidad]), do: Recursos.zona_de(centro)
  defp zona_afectada("remove_stock", [_codigo, centro, _cantidad]), do: Recursos.zona_de(centro)

  defp zona_afectada("transfer_resource", [_codigo, origen | _resto]),
    do: Recursos.zona_de(origen)

  defp zona_afectada("assign_resource", [id | _resto]), do: Necesidades.zona_de(id)
  defp zona_afectada("update_need_status", [id | _resto]), do: Necesidades.zona_de(id)
  defp zona_afectada("cancel_need", [id | _resto]), do: Necesidades.zona_de(id)
  defp zona_afectada("register_entry", [albergue | _resto]), do: Albergues.zona_de(albergue)
  defp zona_afectada("register_exit", [albergue | _resto]), do: Albergues.zona_de(albergue)

  defp zona_afectada("update_person_status", [documento | _resto]),
    do: Personas.zona_de(documento)

  defp zona_afectada("add_family_member", [familia | _resto]),
    do: Personas.zona_de_familia(familia)

  defp zona_afectada("mark_message", [id | _resto]), do: Personas.zona_de_mensaje(id)
  defp zona_afectada("confirm_match", [perdida | _resto]), do: Mascotas.zona_de(perdida)
  defp zona_afectada("reject_match", [perdida | _resto]), do: Mascotas.zona_de(perdida)

  # Consultas y comandos sin zona: no aplica
  defp zona_afectada(_comando, _argumentos), do: :no_aplica
end
