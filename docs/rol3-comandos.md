# Comandos de personas y mascotas (Integrante 3)

`Emergencias.Comandos.Personas` traduce los 14 comandos del Integrante 3 a llamadas a
`Personas` y `Mascotas`. Tiene la misma forma que `Comandos.Logistica`:

- `comandos/0` devuelve los nombres que atiende.
- `ejecutar(comando, argumentos, usuario)` devuelve `{:ok, texto}` o `{:error, razon}`.

El despachador (Integrante 1) separa la línea en palabras, revisa permisos y la regla de
zona del coordinador, y llama a `ejecutar/3`.

## Sintaxis

| Comando | Argumentos | Llama a |
|---|---|---|
| `report_person` | `documento nombre zona [estado] [edad=N]` | `Personas.registrar/5` |
| `find_person` | `documento` o `[nombre=] [zona=] [estado=]` | `Personas.buscar/1` |
| `update_person_status` | `documento estado [detalle]` | `Personas.actualizar_estado/3` |
| `person_history` | `documento` | `Personas.historial/1` |
| `register_family` | `nombre zona` | `Personas.registrar_familia/2` |
| `add_family_member` | `familia documento` | `Personas.agregar_miembro/2` |
| `send_family_message` | `documento "texto"` o `familia=F001 "texto"` | `Personas.enviar_mensaje/3` |
| `list_family_messages` | `documento` o `familia=F001` | `Personas.listar_mensajes/1` |
| `mark_message` | `mensaje estado` | `Personas.marcar_mensaje/2` |
| `report_pet` | `lost\|found especie nombre color tamano zona contacto [caracteristicas]` | `Mascotas.registrar/8` |
| `list_pets` | `[especie=] [zona=] [estado=]` | `Mascotas.listar/1` |
| `match_pets` | (sin argumentos) | `Mascotas.buscar_coincidencias/0` |
| `reject_match` | `perdida encontrada` | `Mascotas.rechazar/2` |
| `confirm_match` | `perdida encontrada` | `Mascotas.confirmar/2` |

El remitente de `send_family_message` es el usuario conectado.

## Decisiones

- **El módulo no valida reglas de negocio.** Solo convierte texto a los tipos que piden
  los servidores (`"34"` a `34`, `lost` a `:perdida`) y da formato a la respuesta. Las
  reglas (transiciones, zona existente, no duplicados) viven dentro de los `GenServer`,
  en el mismo `handle_call` que modifica el estado.
- **Opciones `clave=valor`.** `opcion/2` busca una clave recorriendo la lista
  (recursión sobre `[head | tail]`); `filtros/2` convierte todas las opciones y devuelve
  `{:error, :opcion_invalida}` si alguna no es válida.
- **`find_person` con un solo argumento** sin `=` se toma como documento.
- **`send_family_message` y `list_family_messages`:** un texto `familia=F001` apunta a la
  familia; cualquier otro texto es el documento de una persona.
- **Errores propios del módulo:** `:numero_invalido` (edad que no es número),
  `:opcion_invalida`, `:tipo_invalido` (ni `lost` ni `found`) y `:argumentos_invalidos`.
  El Integrante 1 debe agregarlos a `Errores.mensaje/1`.

## Pruebas

```
mix test test/emergencias/comandos/personas_test.exs
```