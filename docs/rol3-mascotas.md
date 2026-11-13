# Mascotas perdidas y encontradas (Integrante 3)

## Módulos

| Módulo | Tipo | Qué hace |
|---|---|---|
| `Emergencias.Mascotas` | GenServer | Reportes, coincidencias, rechazo y confirmación, con su persistencia |
| `Mascotas.Reporte` | struct + funciones puras | Tabla de transiciones de estado y conversión a línea de texto |
| `Mascotas.Similitud` | funciones puras | Puntaje de 0 a 100 entre una mascota perdida y una encontrada |

## Funciones

| Comando | Función |
|---|---|
| `report_pet lost\|found especie nombre color tamano zona contacto [caracteristicas]` | `Mascotas.registrar/8` (`lost` = `:perdida`, `found` = `:encontrada`) |
| `list_pets [especie=] [zona=] [estado=]` | `Mascotas.listar/1` |
| `match_pets` | `Mascotas.buscar_coincidencias/0` |
| `reject_match perdida encontrada` | `Mascotas.rechazar/2` |
| `confirm_match perdida encontrada` | `Mascotas.confirmar/2` |

Para la regla de zona del coordinador (`confirm_match`): `Mascotas.zona_de/1`.

El tamaño es `pequeno`, `mediano` o `grande` (también se acepta `pequeño`).

## Estados de un reporte

| Estado | Puede pasar a |
|---|---|
| `activa` | `posible_coincidencia`, `resuelta` |
| `posible_coincidencia` | `activa`, `resuelta` |
| `resuelta` | terminal |

- `match_pets` marca `posible_coincidencia` (los dos reportes del par, con el código del otro
  en el campo `pareja`).
- `reject_match` devuelve los dos a `activa` y borra la pareja.
- `confirm_match` pasa los dos a `resuelta`. Puede confirmarse un par propuesto o dos
  reportes activos. Un reporte que está propuesto con otro no se puede confirmar con un
  tercero (`:no_son_pareja`). Una segunda confirmación responde `:ya_resuelto`.

## Puntaje de similitud

Una especie distinta descarta el par (0). Si coincide aporta 30 puntos y se suman:

| Atributo | Puntos |
|---|---|
| Color | 20 |
| Tamaño | 15 |
| Zona | 15 |
| Características | hasta 20: palabras en común sobre palabras totales (`MapSet`) |

Un puntaje de **60 o más** marca `posible_coincidencia`. Ejemplo: "collar rojo" contra
"collar rojo azul verde" tiene 2 palabras en común de 4 en total, así que aporta 10 de 20.

## Decisiones de diseño

- **`confirm_match` en un solo `handle_call`.** Verificar que ninguno esté resuelto, que
  sean pareja y cerrar los dos reportes ocurre en el mismo mensaje. Si diez dueños reclaman
  a la vez la misma mascota encontrada, uno la recibe y los otros nueve reciben
  `:ya_resuelto`. Hay una prueba con `Task.async` que lo comprueba.
- **Un reporte entra en un solo par.** `match_pets` calcula todos los candidatos que llegan
  a 60, los ordena del mejor al peor (a igual puntaje decide el código) y
  `Mascotas.elegir_pares/2` recorre la lista saltando los candidatos cuyos reportes ya
  fueron usados.
- **Llamadas en un solo sentido.** `Mascotas` solo llama a `Zonas`.
- **Mapa por código.** `%{"M001" => reporte}`: buscar es una sola operación. Los códigos son
  consecutivos y, al cargar, continúan donde iban (mayor sufijo más uno).
- **Texto libre.** Las características pasan por `Persistencia.limpiar/1`: el `;` se
  cambia por `,`.
- **Archivos dañados.** `Reporte.desde_fila/1` devuelve `{:error, :fila_invalida}` y el
  servidor descarta esa línea.

## Archivo (en `datos/`, campos separados por `;`)

`mascotas.txt`: id, tipo, especie, nombre, características, color, tamaño, zona, contacto,
estado, pareja (vacío si no tiene). Se reescribe completo después de cada cambio.

## Funciones recursivas propias

- `Similitud.puntaje/3` con `sumar/3`: recorre la lista de atributos sumando sus puntos.
- `Mascotas.filtrar/2` y `cumple?/2`: recorren los reportes y los filtros.
- `Mascotas.elegir_pares/2`: recorre los candidatos llevando el conjunto de usados.
- `Mascotas.marcar_pares/2` (privada): marca un par y sigue con el resto.
- `siguiente_numero/2` (privada, con acumulador): mayor sufijo más uno.

## Pruebas

```
mix test test/emergencias/mascotas_test.exs test/emergencias/mascotas
```

Cubren el caso exitoso, los errores, el puntaje, que un reporte entre en un solo par,
rechazar y confirmar, la recuperación después de que el servidor falla y la concurrencia
(dos confirmaciones del mismo par, diez dueños para una mascota y veinte reportes a la vez).
`match_pets` mira todos los reportes activos, así que cada prueba usa una especie de nombre
único para no mezclarse con las demás.