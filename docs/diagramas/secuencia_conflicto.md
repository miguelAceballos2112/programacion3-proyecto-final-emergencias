# Diagrama de secuencia: conflicto concurrente sobre el inventario

Laura y Pedro piden agua al mismo tiempo. Hay 50 litros y entre los dos piden 55.

![Diagrama de secuencia del conflicto concurrente](secuencia_conflicto.png)

El mismo diagrama en Mermaid (GitHub lo dibuja al abrir este archivo):

```mermaid
sequenceDiagram
    autonumber
    actor L as Laura (Task 1)
    actor P as Pedro (Task 2)
    participant N as Necesidades (GenServer)
    participant R as Recursos (GenServer)
    participant D as Archivos de texto

    Note over R: R001 agua = 50 litros en centro_acopio_1
    par Al mismo tiempo
        L->>N: asignar_recurso("N001", "agua", 30)
    and
        P->>N: asignar_recurso("N002", "agua", 25)
    end
    Note over N: Los dos mensajes quedan en el buzón<br/>y se atienden uno por uno
    N->>R: reservar(:agua, 30, "centro", "N001")
    Note over R: handle_call: ¿alcanza? 50 >= 30, sí<br/>descuenta en la misma llamada: quedan 20
    R->>D: recursos.txt y movimientos.txt (reserva de N001)
    R-->>N: {:ok, [{"R001", "centro_acopio_1", 30}]}
    N->>D: necesidades.txt (N001 asignada)
    N-->>L: {:ok, N001 asignada}
    N->>R: reservar(:agua, 25, "centro", "N002")
    Note over R: handle_call: ¿alcanza? 20 >= 25, no<br/>no cambia nada
    R-->>N: {:error, :stock_insuficiente}
    N-->>P: {:error, :stock_insuficiente}
```

Si el mensaje de Pedro llega primero, se confirman sus 25 litros y se rechazan los 30
de Laura. En los dos casos nunca se asignan 55 litros cuando solo hay 50.

Si se cambia el diagrama, el PNG se puede volver a generar copiando el bloque en
<https://mermaid.live> y descargándolo como PNG.
