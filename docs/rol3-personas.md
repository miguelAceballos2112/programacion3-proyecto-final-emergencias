# Personas, familias y mensajes (Integrante 3)

## Módulos

| Módulo | Tipo | Qué hace |
|---|---|---|
| `Emergencias.Personas` | GenServer | Personas, historial de estados, familias y mensajes, con su persistencia |
| `Personas.Persona` | struct + funciones puras | Tabla de transiciones de estado y conversión a línea de texto |
| `Personas.Familia` | struct | Miembros en un `MapSet` (nadie queda dos veces) |
| `Personas.Mensaje` | struct | Estado `pendiente` / `entregado` y conversión a línea de texto |

## Funciones

| Comando | Función |
|---|---|
| `report_person documento nombre zona [estado] [edad=]` | `Personas.registrar/5` |
| `find_person documento` o filtros `nombre=`, `zona=`, `estado=` | `Personas.obtener/1` y `Personas.buscar/1` |
| `update_person_status documento estado` | `Personas.actualizar_estado/3` (rechaza `en_albergue`) |
| `person_history documento` | `Personas.historial/1` |
| `register_family nombre zona` | `Personas.registrar_familia/2` |
| `add_family_member familia documento` | `Personas.agregar_miembro/2` |
| `send_family_message documento "texto"` o `familia=F001 "texto"` | `Personas.enviar_mensaje/3` |
| `list_family_messages documento` o `familia=F001` | `Personas.listar_mensajes/1` |
| `mark_message mensaje entregado\|pendiente` | `Personas.marcar_mensaje/2` |

Para la regla de zona del coordinador: `zona_de/1` (persona), `zona_de_familia/1` y
`zona_de_mensaje/1`. Para los demás integrantes: `obtener/1`, `existe?/1`,
`existe_familia?/1` y `cambiar_estado/3` (la usa `Albergues`).

Las funciones reciben enteros y textos ya convertidos; el estado puede llegar como átomo
o como texto (`Validaciones.opcion/3` lo convierte).

## Estados de una persona

| Estado | Puede pasar a |
|---|---|
| `sin_informacion` | `reportada`, `localizada`, `en_albergue` |
| `reportada` | `localizada`, `reunificada`, `en_albergue` |
| `localizada` | `trasladada`, `reunificada`, `en_albergue` |
| `trasladada` | `localizada`, `reunificada`, `en_albergue` |
| `en_albergue` | `trasladada` |
| `reunificada` | terminal |

- Al registrar se acepta `sin_informacion` (por defecto), `reportada`, `localizada` o
  `trasladada`.
- A `en_albergue` solo se entra con `register_entry` y solo se sale con `register_exit`:
  `actualizar_estado/3` responde `{:error, :usar_albergue}`. `Albergues` usa
  `cambiar_estado/3`, que no tiene esa restricción.
- Los mensajes alternan entre `pendiente` y `entregado`.

## Decisiones de diseño

- **Un solo proceso.** Validar, modificar, guardar y responder ocurren en el mismo
  `handle_call`. Dos reportes simultáneos del mismo documento: uno se acepta y el otro
  recibe `:ya_existe`.
- **Llamadas en un solo sentido.** `Personas` solo llama a `Zonas`. `Albergues` y
  `Necesidades` llaman a `Personas`; si `Personas` los llamara, los dos se quedarían
  esperando.
- **Mapas por clave.** `%{documento => persona}`, `%{"F001" => familia}` y
  `%{"MSG001" => mensaje}`: buscar es una sola operación, sin recorrer listas.
- **Códigos consecutivos** `P001`, `F001`, `MSG001`. Al cargar, el siguiente es el mayor
  sufijo existente más uno (`siguiente_numero/2`), así que continúan después de un
  reinicio. Los códigos de familia y de mensaje se aceptan en minúscula.
- **Documentos exactos.** Se comparan tal como se escriben (igual que `Albergues`). No
  pueden tener espacios ni comas, porque los albergues guardan los documentos de sus
  ocupantes separados por coma.
- **Textos libres.** El contenido de un mensaje y el detalle de un cambio de estado pasan
  por `Persistencia.limpiar/1`: el `;` se cambia por `,`.
- **Archivos dañados.** `desde_fila/1` devuelve `{:error, :fila_invalida}` y el servidor
  descarta esa línea. Un archivo con una línea mala no impide que arranque.

## Archivos (en `datos/`, campos separados por `;`)

- `personas.txt`: id, documento, nombre, edad, zona, estado, familia (vacío si no tiene).
- `historial_personas.txt`: fecha, documento, estado anterior (`-` en el primer reporte),
  estado nuevo, detalle. Solo se agregan líneas.
- `familias.txt`: código, nombre, zona, documentos de los miembros separados por coma.
- `mensajes.txt`: id, fecha, remitente, tipo de destino, destino, contenido, estado.

## Funciones recursivas propias

- `Personas.filtrar/2`: recorre la lista de personas; `cumple?/2` (privada) recorre la
  lista de filtros.
- `Personas.filtrar_historial/2`: entradas del historial de un documento.
- `Personas.reunir_mensajes/2`: mensajes de una persona y de su familia.
- `Personas.siguiente_numero/2`: mayor sufijo más uno, con acumulador.

## Pruebas

```
mix test test/emergencias/personas_test.exs test/emergencias/personas/persona_test.exs
```

Cubren el caso exitoso, los errores, la tabla de transiciones, el mensaje a familia visible
para sus miembros, la recuperación después de que el servidor falla y la concurrencia
(mismo documento a la vez, veinte reportes distintos y diez miembros agregados a la vez).