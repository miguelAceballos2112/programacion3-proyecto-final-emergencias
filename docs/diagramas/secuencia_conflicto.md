# Diagrama de secuencia: conflicto concurrente sobre el inventario

Laura y Carlos (dos coordinadores de la zona centro) asignan agua al mismo tiempo.
Hay 50 litros y entre los dos piden 55.

![Diagrama de secuencia del conflicto concurrente](secuencia_conflicto.png)

La fuente editable es `secuencia_conflicto.drawio` (se abre con draw.io o en
<https://app.diagrams.net>). El mismo flujo en Mermaid, que GitHub dibuja al abrir
este archivo:

```mermaid
sequenceDiagram
    autonumber
    actor L as Laura (proceso 1)
    actor C as Carlos (proceso 2)
    participant D as Comandos (despachador)
    participant U as Usuarios (GenServer)
    participant N as Necesidades (GenServer)
    participant R as Recursos (GenServer)
    participant B as Bitácora (spawn/receive)

    Note over R: R001 agua = 50 litros en centro_acopio_1
    par Al mismo tiempo
        L->>D: ejecutar("laura", "assign_resource N001 agua 30")
    and
        C->>D: ejecutar("carlos", "assign_resource N002 agua 25")
    end
    D->>U: autorizar(usuario, :assign_resource)
    U-->>D: :ok (y la regla de zona: centro)
    D->>N: asignar_recurso("N001", "agua", 30)
    D->>N: asignar_recurso("N002", "agua", 25)
    Note over N: Los dos mensajes quedan en el buzón<br/>y se atienden uno por uno
    N->>R: reservar(:agua, 30, "centro", "N001")
    Note over R: handle_call: ¿alcanza? 50 >= 30, sí<br/>descuenta en la misma llamada: quedan 20
    R-->>N: {:ok, [{"R001", "centro_acopio_1", 30}]}
    N-->>D: {:ok, N001 asignada}
    D-)B: send {:evento, laura, assign_resource, :ok}
    D-->>L: "Se asignaron 30 de agua a N001"
    N->>R: reservar(:agua, 25, "centro", "N002")
    Note over R: handle_call: ¿alcanza? 20 >= 25, no<br/>no cambia nada
    R-->>N: {:error, :stock_insuficiente}
    N-->>D: {:error, :stock_insuficiente}
    D-)B: send {:evento, carlos, assign_resource, :error}
    D-->>C: "No hay inventario suficiente. No se tomó nada."
```

Si la asignación de Carlos llega primero, se confirman sus 25 litros y se rechazan los
30 de Laura. En cualquier orden, nunca se asignan 55 litros cuando solo hay 50.

Se reproduce con `mix run escenarios/conflicto_concurrente.exs`, con
`mix run escenarios/flujo_ejemplo.exs` (paso 3) o en la web, sección
**Conflicto concurrente**.
