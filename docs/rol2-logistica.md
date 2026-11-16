# Logística: centros, recursos, necesidades y albergues (Integrante 2)

## Módulos

| Módulo | Tipo | Qué hace |
|---|---|---|
| `Emergencias.Recursos` | GenServer | Centros de apoyo, inventario por centro, entradas, salidas, transferencias, reservas, devoluciones e historial |
| `Recursos.Centro`, `Recurso`, `Movimiento` | structs | Datos y reglas puras (nunca cantidades negativas) |
| `Recursos.Reparto` | funciones puras | Reparte una cantidad entre varios centros (recursivo, todo o nada) |
| `Emergencias.Albergues` | GenServer | Registro con ocupación inicial, ingreso y salida, cupos y reporte de ocupación |
| `Albergues.Albergue` | struct | Capacidad, ocupación inicial y conjunto (`MapSet`) de documentos de los ocupantes |
| `Emergencias.Necesidades` | GenServer | Registro con destino, asignación de recursos, estados, cancelación, consultas y recursos críticos |
| `Necesidades.Necesidad` | struct | Transiciones de estado válidas |
| `Necesidades.Prioridad` | funciones puras | Ordena y elige por prioridad (recursivo) |
| `Emergencias.Comandos.Logistica` | funciones | Los 20 comandos de logística: texto que llega, servidor que se llama, texto que se muestra |

También se agregaron a `Emergencias.Validaciones` las funciones `entero_positivo/2` y
`opcion/3`.

## Comandos y funciones

`Comandos.Logistica.ejecutar(comando, argumentos, usuario)` recibe el comando y sus
argumentos como textos y devuelve `{:ok, texto}` o `{:error, razon}`. Los permisos y la
regla de zona del coordinador los revisa el despachador del Integrante 1 antes de
llamar, con `zona_de/1` de cada servidor.

| Comando | Función |
|---|---|
| `register_center codigo nombre tipo zona` | `Recursos.registrar_centro/4` (tipo `acopio` o `punto_atencion`) |
| `register_resource codigo categoria cantidad unidad centro [nombre=]` | `Recursos.registrar/6` |
| `list_resources [zona=] [categoria=]` | `Recursos.listar/0` y `Recursos.disponibilidad/2` |
| `add_stock codigo centro cantidad` | `Recursos.entrada/3` |
| `remove_stock codigo centro cantidad` | `Recursos.salida/3` |
| `list_movements [codigo]` | `Recursos.historial/1` |
| `transfer_resource codigo origen destino cantidad` | `Recursos.transferir/4` |
| `register_need tipo cantidad prioridad zona descripcion [destino=tipo:codigo]` | `Necesidades.registrar/7` (responsable = usuario conectado) |
| `list_needs [zona=] [tipo=] [prioridad=] [estado=]` | `Necesidades.listar/1` |
| `assign_resource necesidad categoria cantidad` | `Necesidades.asignar_recurso/3` |
| `update_need_status necesidad estado` | `Necesidades.cambiar_estado/2` |
| `cancel_need necesidad` | `Necesidades.cancelar/1` |
| `next_need [zona]` | `Necesidades.siguiente/1` |
| `pending_needs` | `Necesidades.pendientes/0` |
| `critical_resources` | `Necesidades.recursos_criticos/0` |
| `register_shelter codigo nombre zona capacidad [ocupacion]` | `Albergues.registrar/5` |
| `check_shelter codigo` | `Albergues.consultar/1` |
| `shelter_report [n]` | `Albergues.mas_ocupados/1` |
| `register_entry albergue documento` | `Albergues.ingresar/2` |
| `register_exit albergue documento` | `Albergues.salir/2` |

- Categorías, prioridades, estados y tipos llegan como texto (`"agua"`, `"Critica"`) y
  `Validaciones.opcion/3` los convierte en átomos.
- Los números llegan como texto a los comandos. `Comandos.Logistica` los convierte con
  `Integer.parse`. Las funciones de los servidores reciben enteros.
- Destino de una necesidad: `destino=punto:P3`, `destino=albergue:A01`,
  `destino=persona:1094` o `destino=familia:F001`. Sin la opción, la necesidad queda
  asociada a su zona.

## Decisiones de diseño

- **Inventario por centro.** Un recurso guarda `%{centro => cantidad}`. Cada centro
  pertenece a una zona y tiene un tipo:
  - `acopio`;
  - `punto_atencion`: usa el código de un punto de atención de su zona;
  - `albergue`: lo crea `Albergues` al registrar cada albergue.
- **Asignación por zona.** `assign_resource` toma de los centros de la misma zona que la
  necesidad, empezando por el que más tiene, y puede combinar varios centros. Si entre
  todos no alcanza, no se toma nada.
- **Devoluciones.** Cada parte de una reserva queda en `movimientos.txt` con el id de
  la necesidad en `referencia`.
  - `Recursos.devolver/1` suma lo reservado para esa necesidad, resta lo ya devuelto y
    lo repone en cada centro.
  - Una segunda devolución no repone nada.
  - `cancel_need` la usa si la necesidad estaba pendiente o asignada. En atención, los
    recursos ya se usaron.
- **Concurrencia.** Reservar, devolver, transferir, sacar inventario y ocupar cupos se
  deciden dentro de un `handle_call`: la verificación y el cambio ocurren juntos.
- **Prioridades:** `critica`, `alta`, `media`, `baja`. Con la misma prioridad va
  primero la necesidad más antigua.
- **Estados de una necesidad:**
  - `pendiente → asignada`, al recibir recursos.
  - `pendiente | asignada → en_atencion | cancelada`.
  - `en_atencion → atendida | cancelada`.
  - `atendida` y `cancelada` son finales.
- **Ocupación de un albergue** = ocupación inicial + personas que ingresaron con
  `register_entry`. Nunca supera la capacidad. Los documentos de los ocupantes se
  guardan en un `MapSet`, como pide el enunciado (1.3): nadie queda dos veces.
- **Llamadas en un solo sentido**, para que no haya bloqueos. Nunca se llama al revés:
  - Necesidades → Recursos, Albergues y Personas.
  - Albergues → Recursos y Personas.
  - Recursos → Zonas.
  - `check_shelter` reúne los datos en el proceso que llama, no dentro del servidor.
- **Archivos** (en `datos/`, campos separados por `;`):
  - `centros.txt`: código, nombre, tipo, zona.
  - `recursos.txt`: código, nombre, categoría, unidad, centro, cantidad. Una línea por
    recurso y centro.
  - `movimientos.txt`: fecha, tipo, código, origen, destino, cantidad, referencia,
    detalle. Solo se agregan líneas.
  - `necesidades.txt`: id, tipo, descripción, cantidad, asignado, zona, prioridad,
    responsable, estado, tipo de destino, código de destino, fecha.
  - `albergues.txt`: código, nombre, zona, capacidad, ocupación inicial, documentos de
    los ocupantes.

## Lo que se usa de los otros integrantes

- **Integrante 1:**
  - `Persistencia.cargar/1`, `guardar/2`, `agregar/2`, `unir/1` y `separar/1`.
  - `Validaciones.texto/2` y `entero_no_negativo/2`.
  - `Zonas.existe?/1`, `Zonas.obtener/1` y `Zonas.Zona.buscar_punto/2`.
  - Mientras Zonas no tenga `existe_punto?/2`, los puntos se buscan con
    `Recursos.punto_existe?/2`.
- **Integrante 3:**
  - `Personas.obtener/1` devuelve `{:ok, persona}` con el campo `estado`, o
    `{:error, :persona_no_existe}`.
  - `Personas.cambiar_estado(documento, estado, detalle)` se usa con `:en_albergue` al
    ingresar y con `:trasladada` al salir.
  - `Personas.existe?/1` y `Personas.existe_familia?/1` validan el destino de una
    necesidad.
  - Mientras `Personas` no esté en el proyecto:
    - el compilador avisa que esas funciones no existen;
    - las pruebas con `@tag :personas` se omiten (lo decide `test/test_helper.exs`).
  - Cuando llegue, las pruebas se activan solas. Si la firma cambia, se ajusta en
    `Albergues`, en `Necesidades` y en la ayuda `crear_persona` de las pruebas.

## Funciones recursivas propias

- `Reparto.total/1` y `Reparto.tomar/3`: reparto de una reserva entre centros.
- `Recursos.aplicar_tomas/4` y `Recursos.aplicar_devoluciones/4`: descuentan o reponen
  cada lote.
- `Recursos.punto_en_sectores?/2`: busca un punto de atención en los sectores de una
  zona.
- `Recurso.sumar/1`: total de un recurso en todos sus centros.
- `Prioridad.ordenar/1` con `insertar/2`: ordenamiento por inserción por prioridad.
- `Prioridad.mas_urgente/1` con `elegir/2`: selección de la necesidad más urgente.
- `Necesidades.sumar_demanda/2`: demanda pendiente por zona y tipo, con acumulador.
- `Necesidades.filtrar/2`: aplica los filtros de `list_needs` uno por uno.
- `Albergue.ordenar_por_ocupacion/1` con `insertar/2`: reporte de albergues más
  ocupados.
- `Validaciones.buscar_opcion/3`: convierte un texto en una opción permitida.
- `Comandos.Logistica.opcion/2` y `filtros/1`: leen las opciones `clave=valor`.

## Escenario y pruebas

```
mix run escenarios/conflicto_concurrente.exs
mix test test/emergencias/recursos_test.exs test/emergencias/albergues_test.exs test/emergencias/necesidades_test.exs
```

El escenario muestra tres casos:

- El flujo del enunciado: se piden 30 y 25 litros a la vez y solo hay 50.
- Diez solicitudes simultáneas de 10 litros sobre 50: se confirman exactamente 5.
- La cancelación de la necesidad que recibió el agua, que devuelve los litros al centro.

El diagrama de secuencia está en `docs/diagramas/secuencia_conflicto.md` y en PNG en
`docs/diagramas/secuencia_conflicto.png`.
