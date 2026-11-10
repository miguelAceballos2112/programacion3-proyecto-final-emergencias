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
| Recursos | Integrante 2 | Pendiente |
| Necesidades | Integrante 2 | Pendiente |
| Albergues | Integrante 2 | Pendiente |
| Personas y mensajes | Integrante 3 | Pendiente |
| Mascotas | Integrante 3 | Pendiente |
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
├── Emergencias.Recursos    (GenServer)  pendiente
├── Emergencias.Necesidades (GenServer)  pendiente
├── Emergencias.Albergues   (GenServer)  pendiente
├── Emergencias.Personas    (GenServer)  pendiente
└── Emergencias.Mascotas    (GenServer)  pendiente
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
| `recursos.txt`, `movimientos.txt` | Inventario e historial de movimientos | Pendiente |
| `necesidades.txt` | Necesidades puntuales | Pendiente |
| `albergues.txt` | Albergues y ocupantes | Pendiente |
| `personas.txt`, `historial_personas.txt`, `mensajes.txt` | Personas, historial de estados y mensajes | Pendiente |
| `mascotas.txt` | Reportes de mascotas | Pendiente |

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
| `register_resource`, `list_resources`, `transfer_resource`, `assign_resource` | `Recursos`, `Necesidades` | Pendiente |
| `register_need`, `list_needs`, `pending_needs`, `critical_resources` | `Necesidades` | Pendiente |
| `register_shelter`, `check_shelter`, `register_entry`, `register_exit` | `Albergues` | Pendiente |
| `report_person`, `find_person`, `send_family_message`, `list_family_messages` | `Personas` | Pendiente |
| `report_pet`, `match_pets` | `Mascotas` | Pendiente |
| `summary` | `Reportes` | Pendiente |

## Estructuras de datos y recursividad

- **Mapas:** estado de cada servidor (`%{codigo => struct}`), usuarios y sesiones.
- **Listas anidadas:** zona → sectores → puntos de atención.
- **Tuplas:** resultados `{:ok, valor}` y `{:error, razon}`, y pares `{codigo, total}`.
- **Structs:** `Usuario`, `Zona`, `Sector` y `PuntoAtencion`, con campos obligatorios.
- **Funciones recursivas propias** (Integrante 1): `total_sectores/1`, `total_puntos/1`, `contar_puntos/1`, `sectores_por_nivel/2` (con acumulador), `totales_por_sector/1` y las funciones que recorren la jerarquía de zonas al escribir `zonas.txt`.

_Agregar aquí las estructuras y funciones recursivas de los otros integrantes._

## Validaciones y manejo de errores

- Los identificadores no pueden repetirse (`:ya_existe`).
- Las cantidades no pueden ser negativas ni textos (`:personas_invalidas`).
- Los textos no pueden estar vacíos ni contener `;`.
- Una zona, un sector o un punto solo se registran si existe lo que los contiene (`:zona_no_existe`, `:sector_no_existe`).
- Un usuario solo puede tener una sesión abierta (`:ya_conectado`).
- Cada `handle_call` valida antes de modificar: si algo falla, responde el error y el estado no cambia.

## Pruebas

```
mix test
```

Con la parte del Integrante 1 se obtienen **12 doctests y 52 pruebas, 0 fallos**. Incluyen casos válidos, inválidos y límite, conexiones simultáneas de varios usuarios y la recuperación de un servidor que falla (el supervisor lo reinicia y recupera sus datos desde el archivo). Las pruebas guardan sus datos en una carpeta temporal, sin tocar `datos/`.

_Actualizar el conteo cuando los otros integrantes agreguen sus pruebas._

## Demostración del conflicto concurrente

_(Completar cuando el Integrante 2 entregue `escenarios/conflicto_concurrente.exs`: con 50 litros de agua disponibles, dos solicitudes simultáneas de 30 y 25 litros no pueden confirmarse a la vez.)_

## Diagramas, informe y video

- Arquitectura de módulos y árbol OTP: _(enlace)_
- Modelo de datos: _(enlace)_
- Diagrama de secuencia: _(enlace)_
- Video de demostración: _(enlace)_