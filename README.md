# Sistema Distribuido de Coordinación y Gestión de Emergencias

Proyecto final de **Programación III** · Universidad del Quindío · Ingeniería de Sistemas y Computación

Simulación, en Elixir, de una plataforma multiusuario para coordinar la atención posterior a un terremoto. Varios usuarios registran y consultan zonas afectadas, necesidades, recursos, albergues, personas, mensajes entre familiares y reportes de mascotas, de forma concurrente y sin inconsistencias.

**Repositorio:** _https://github.com/miguelAceballos2112/programacion3-proyecto-final-emergencias.git_

## Integrantes y roles

| Integrante | Rol | Responsabilidad |
|---|---|---|
| _Miguel Angel Ceballos Soler_ | Integrante 1 | Base del sistema: supervisión, persistencia, usuarios, permisos y zonas |
| _Nombre 2_ | Integrante 2 | Logística: recursos, necesidades y albergues |
| _Nombre 3_ | Integrante 3 | Personas, mensajes, mascotas, resumen e interfaz de comandos |

## Estado del proyecto

| Componente | Responsable | Estado |
|---|---|---|
| Aplicación, supervisores y sesiones | Integrante 1 | Listo |
| Persistencia en texto plano y validaciones | Integrante 1 | Listo |
| Usuarios, conexión y permisos | Integrante 1 | Listo |
| Zonas, sectores y puntos de atención | Integrante 1 | Listo |
| Recursos y centros de apoyo | Integrante 2 | Listo |
| Necesidades | Integrante 2 | Listo |
| Albergues | Integrante 2 | Listo (el ingreso y la salida necesitan `Personas`) |
| Comandos de logística (`comandos/logistica.ex`) | Integrante 2 | Listo; falta conectarlos al despachador |
| Personas, familias y mensajes | Integrante 3 | Listo |
| Mascotas | Integrante 3 | Listo |
| Resumen e interfaz de comandos | Integrante 3 | Pendiente |

## Requisitos

- Elixir 1.14 o superior (con Erlang/OTP). Se verifica con `elixir --version`.
- No tiene dependencias externas.

## Cómo ejecutar

```
git clone <URL del repositorio>
cd programacion3-proyecto-final-emergencias
mix test
iex -S mix
```

`mix test` ejecuta los doctests y las pruebas. `iex -S mix` abre una consola con el sistema ya iniciado, desde la que se pueden llamar los módulos. Ejemplo con lo que ya está implementado:

```elixir
Emergencias.Usuarios.conectar("laura", "1234", "coordinador", "centro")
Emergencias.Usuarios.autorizar("laura", :register_zone)
Emergencias.Zonas.registrar_zona("centro", "Centro", "critico", 100)
Emergencias.Zonas.registrar_sector("centro", "s3", "Sector 3", "alto", 40)
Emergencias.Zonas.registrar_punto("centro", "s3", "p1", "Punto de atención", 10)
Emergencias.Zonas.estado("centro")
Emergencias.Usuarios.desconectar("laura")
```

_Cuando el Integrante 3 entregue la interfaz de comandos, agregar aquí cómo iniciarla y los comandos de ejemplo._

## Arquitectura

La aplicación inicia un árbol de supervisión. Cada componente con estado es un `GenServer` registrado con el nombre de su módulo, y cada usuario conectado tiene su propio proceso de sesión, creado por un `DynamicSupervisor`.

```
Emergencias.Supervisor (:one_for_one)
├── Emergencias.SupervisorSesiones (DynamicSupervisor) -> una sesión por usuario conectado
├── Emergencias.Usuarios    (GenServer)
├── Emergencias.Zonas       (GenServer)
├── Emergencias.Recursos    (GenServer)
├── Emergencias.Albergues   (GenServer)
├── Emergencias.Necesidades (GenServer)
├── Emergencias.Personas    (GenServer)  personas, familias y mensajes
└── Emergencias.Mascotas    (GenServer)  reportes de mascotas y coincidencias
```

### Decisiones de diseño

- **Concurrencia sin inconsistencias:** un `GenServer` atiende un mensaje a la vez. Las operaciones críticas (reservar recursos, ocupar cupos, resolver reportes) verifican y modifican el estado dentro de un mismo `handle_call`, así que dos solicitudes simultáneas nunca se mezclan.
- **Persistencia en texto plano:** cada servidor carga su archivo al iniciar y lo guarda después de cada cambio exitoso. Si un proceso falla y el supervisor lo reinicia, recupera su información.
- **Supervisión:** estrategia `:one_for_one`, porque los servidores arrancan sin depender unos de otros. Las sesiones son procesos `:temporary`: si una termina, el usuario debe reconectarse.
- **Dependencias en un solo sentido:** Usuarios y Zonas no dependen de nadie; los demás módulos validan la zona con `Zonas.existe?/1`. Así no hay llamadas circulares entre servidores.
- **Resultados sin excepciones:** las funciones de dominio devuelven `{:ok, valor}` o `{:error, razon}` en las situaciones esperadas.
- **Un solo nodo:** el sistema simula la plataforma distribuida con procesos concurrentes. Como cada servidor está registrado con nombre, podría llamarse desde otro nodo con `GenServer.call({Modulo, nodo}, mensaje)`.

## Persistencia

Archivos de texto plano en la carpeta `datos/` (se crea al ejecutar; no se versiona). Un registro por línea y campos separados por `;`.

| Archivo | Contenido | Estado |
|---|---|---|
| `usuarios.txt` | Usuarios (la contraseña se guarda cifrada con SHA-256) | Listo |
| `actividad.txt` | Registro de actividad de cada usuario | Listo |
| `zonas.txt` | Zonas, sectores y puntos de atención | Listo |
| `centros.txt` | Centros de apoyo con su tipo y su zona | Listo |
| `recursos.txt`, `movimientos.txt` | Inventario por centro e historial de movimientos (las reservas llevan el id de la necesidad) | Listo |
| `necesidades.txt` | Necesidades puntuales con su destino | Listo |
| `albergues.txt` | Albergues, ocupación inicial y ocupantes | Listo |
| `personas.txt`, `historial_personas.txt` | Personas (`id;documento;nombre;edad;zona;estado;familia`) e historial de estados (solo se agregan líneas) | Listo |
| `familias.txt`, `mensajes.txt` | Familias con sus miembros y mensajes a personas o familias | Listo |
| `mascotas.txt` | Reportes de mascotas con su estado y su pareja | Listo |

_Los nombres de los archivos pendientes son los previstos; ajustarlos si cambian._

## Usuarios y permisos

Tipos de usuario: `ciudadano`, `voluntario`, `coordinador` y `administrador`. Con `connect`, si el usuario no existe se registra automáticamente; si existe, se valida la contraseña. La tabla de permisos está en `Emergencias.Permisos`.

| Acción (comando) | Ciudadano | Voluntario | Coordinador | Administrador |
|---|:---:|:---:|:---:|:---:|
| `register_need`, `list_needs`, `list_resources` | Sí | Sí | Sí | Sí |
| `report_person`, `find_person` | Sí | Sí | Sí | Sí |
| `send_family_message`, `list_family_messages` | Sí | Sí | Sí | Sí |
| `report_pet`, `check_shelter` | Sí | Sí | Sí | Sí |
| `register_resource`, `pending_needs`, `match_pets` | No | Sí | Sí | Sí |
| `register_entry`, `register_exit` | No | Sí | Sí | Sí |
| `register_zone`, `register_shelter` | No | No | Sí | Sí |
| `assign_resource`, `transfer_resource` | No | No | Sí | Sí |
| `critical_resources`, `summary` | No | No | Sí | Sí |

## Comandos de referencia

| Comando | Módulo | Estado |
|---|---|---|
| `connect`, `disconnect` | `Usuarios` | Función lista; falta la interfaz de comandos |
| `register_zone` | `Zonas` | Función lista; falta la interfaz de comandos |
| `register_resource`, `list_resources`, `transfer_resource`, `assign_resource` | `Recursos`, `Necesidades` | Listo en `Comandos.Logistica`; falta conectarlo al despachador |
| `register_need`, `list_needs`, `pending_needs`, `critical_resources` | `Necesidades` | Listo en `Comandos.Logistica`; falta conectarlo al despachador |
| `register_shelter`, `check_shelter`, `register_entry`, `register_exit` | `Albergues` | Listo en `Comandos.Logistica`; falta conectarlo al despachador |
| `report_person`, `find_person`, `update_person_status`, `person_history`, `register_family`, `add_family_member`, `send_family_message`, `list_family_messages`, `mark_message` | `Personas` | Función lista (ver `docs/rol3-personas.md`); falta `Comandos.Personas` y conectarlo al despachador |
| `report_pet`, `list_pets`, `match_pets`, `reject_match`, `confirm_match` | `Mascotas` | Función lista (ver `docs/rol3-mascotas.md`); falta `Comandos.Personas` y conectarlo al despachador |
| `summary` | `Reportes` | Pendiente |

Los comandos de personas están en `docs/rol3-personas.md` y los de mascotas en `docs/rol3-mascotas.md`.

Los 20 comandos de logística (los cuatro de arriba y los propios, como `register_center`, `add_stock` o `cancel_need`) y su función están en `docs/rol2-logistica.md`.

## Estructuras de datos y recursividad

- **Mapas:** estado de cada servidor (`%{codigo => struct}`), usuarios y sesiones.
- **Listas anidadas:** zona → sectores → puntos de atención.
- **Tuplas:** resultados `{:ok, valor}` y `{:error, razon}`, y pares `{codigo, total}`.
- **Structs:** `Usuario`, `Zona`, `Sector` y `PuntoAtencion`, con campos obligatorios.
- **Funciones recursivas propias** (Integrante 1): `total_sectores/1`, `total_puntos/1`, `contar_puntos/1`, `sectores_por_nivel/2` (con acumulador), `totales_por_sector/1` y las funciones que recorren la jerarquía de zonas al escribir `zonas.txt`.

- **Logística (Integrante 2):**
  - Mapas `%{centro => cantidad}` para el inventario de cada recurso.
  - `MapSet` con los documentos de los ocupantes de cada albergue: nadie queda dos veces.
  - Tuplas `{codigo, centro, cantidad}` para las partes de una reserva y `{tipo, codigo}` para el destino de una necesidad.
  - Structs `Centro`, `Recurso`, `Movimiento`, `Albergue` y `Necesidad`.
- **Funciones recursivas propias** (Integrante 2):
  - `Reparto.total/1` y `tomar/3`: reparten una reserva entre centros.
  - `Recursos.aplicar_tomas/4`, `aplicar_devoluciones/4` y `punto_en_sectores?/2`.
  - `Recurso.sumar/1`.
  - `Prioridad.ordenar/1` (ordenamiento por inserción) y `mas_urgente/1`.
  - `Necesidades.sumar_demanda/2` (con acumulador) y `filtrar/2`.
  - `Albergue.ordenar_por_ocupacion/1`.
  - `Validaciones.buscar_opcion/3`.
  - `Comandos.Logistica.opcion/2` y `filtros/1`.

- **Personas (Integrante 3):**
  - Mapas de mapas en el estado de `Personas`: `%{documento => persona}`, `%{"F001" => familia}` y `%{"MSG001" => mensaje}`.
  - `MapSet` con los documentos de los miembros de cada familia.
  - Tuplas `{:persona, documento}` y `{:familia, codigo}` para el destino de un mensaje.
  - Structs `Persona`, `Familia` y `Mensaje`.
  - Tabla de transiciones de estado como mapa `estado => [estados permitidos]`.
- **Funciones recursivas propias** (Integrante 3): `Personas.filtrar/2` y `cumple?/2`, `filtrar_historial/2`, `reunir_mensajes/2` y `siguiente_numero/2` (con acumulador).
- **Mascotas (Integrante 3):**
  - Mapa `%{"M001" => reporte}` en el estado de `Mascotas`.
  - `MapSet` con las palabras de las características (puntaje de similitud) y con los reportes ya usados (`elegir_pares/2`).
  - Lista de atributos con su peso `[color: 20, tamano: 15, ...]`, que recorre `Similitud.puntaje/3`.
  - Struct `Reporte` y tabla de transiciones como mapa `estado => [estados permitidos]`.
- **Funciones recursivas propias** (Integrante 3, mascotas): `Similitud.puntaje/3` con `sumar/3`, `Mascotas.filtrar/2`, `Mascotas.elegir_pares/2` y `marcar_pares/2`.

## Validaciones y manejo de errores

- Los identificadores no pueden repetirse (`:ya_existe`).
- Las cantidades no pueden ser negativas ni textos (`:personas_invalidas`).
- Los textos no pueden estar vacíos ni contener `;`.
- Una zona, un sector o un punto solo se registran si existe lo que los contiene (`:zona_no_existe`, `:sector_no_existe`).
- Un usuario solo puede tener una sesión abierta (`:ya_conectado`).
- El inventario nunca queda negativo y una reserva que no alcanza no toma nada (`:stock_insuficiente`).
- Un albergue no supera su capacidad (`:albergue_lleno`) y una persona no está en dos albergues (`:ya_esta_en_un_albergue`).
- Una necesidad solo cambia de estado por transiciones válidas (`:transicion_invalida`). Una atendida o cancelada no vuelve a recibir recursos (`:necesidad_cerrada`).
- El destino de una necesidad y el punto de un centro de tipo punto de atención deben existir (`:punto_no_existe`, `:albergue_no_existe`, `:persona_no_existe`, `:familia_no_existe`).
- Cada `handle_call` valida antes de modificar: si algo falla, responde el error y el estado no cambia.

## Pruebas

```
mix test
```

Con las partes de los integrantes 1 y 2 se obtienen **19 doctests y 127 pruebas, 0 fallos**. Incluyen:

- casos válidos, inválidos y límite;
- conexiones simultáneas de varios usuarios;
- reservas, registros e ingresos a albergues simultáneos;
- devoluciones repetidas;
- la recuperación de un servidor que falla: el supervisor lo reinicia y el servidor recupera sus datos desde el archivo.

Las pruebas guardan sus datos en una carpeta temporal, sin tocar `datos/`.

Otras 7 pruebas usan `Emergencias.Personas` (ingreso y salida de albergues y destinos de tipo persona o familia). Ahora que el módulo existe, `test_helper.exs` ya no las omite y se ejecutan solas.

_Actualizar el conteo cuando los otros integrantes agreguen sus pruebas._

## Demostración del conflicto concurrente

```
mix run escenarios/conflicto_concurrente.exs
```

El escenario muestra tres casos:

1. Hay 50 litros de agua y Laura (30 litros) y Pedro (25 litros) piden al mismo tiempo. Se confirma la solicitud que llega primero y la otra se rechaza con `:stock_insuficiente`. Nunca se asignan 55 litros.
2. Hay diez solicitudes simultáneas de 10 litros sobre 50. Se confirman exactamente 5 y el inventario termina en 0.
3. Se cancela la necesidad que recibió el agua y los litros vuelven al centro de acopio.

Funciona porque `Recursos` decide cada reserva dentro de un `handle_call`: la verificación y el descuento ocurren en el mismo mensaje. El escenario usa una carpeta de datos temporal.

## Diagramas, informe y video

- Arquitectura de módulos y árbol OTP: _(enlace)_
- Modelo de datos: _(enlace)_
- Diagrama de secuencia del conflicto concurrente: `docs/diagramas/secuencia_conflicto.png` (fuente Mermaid en `docs/diagramas/secuencia_conflicto.md`)
- Video de demostración: _(enlace)_