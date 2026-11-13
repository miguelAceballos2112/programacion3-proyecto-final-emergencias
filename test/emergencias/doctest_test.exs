defmodule Emergencias.DoctestTest do
  use ExUnit.Case

  # Ejecuta los ejemplos `iex>` escritos en la documentación
  doctest Emergencias.Persistencia
  doctest Emergencias.Validaciones
  doctest Emergencias.Permisos
  doctest Emergencias.Usuarios.Usuario
  doctest Emergencias.Zonas.Zona
  doctest Emergencias.Recursos.Reparto
  doctest Emergencias.Personas
  doctest Emergencias.Personas.Persona
  doctest Emergencias.Personas.Mensaje
end
