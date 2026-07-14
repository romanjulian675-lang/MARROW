# Politica de documentacion de cambios

Desde este punto, todo cambio funcional debe actualizar el archivo de flujo que
corresponda. La meta es que otro programador pueda leer la documentacion y
entender que sistema se toco, por que se toco, y que comportamiento debe probar.

## Archivos responsables

- Inventario: `docs/inventory_flow.md`
- Equipamiento: `docs/equipment_flow.md`
- Combate: `docs/combat_flow.md`
- Drops y pickups: `docs/drops_flow.md`
- Camara: `docs/camera_flow.md`

Si un cambio toca mas de un flujo, actualizar todos los archivos afectados.
Ejemplo: un nuevo ataque con arco que cambia la camara debe actualizar combate y
camara.

## Que documentar en cada cambio

Agregar una entrada corta en la seccion `Historial de cambios` del archivo
correspondiente:

- Fecha.
- Scripts o escenas tocadas.
- Comportamiento nuevo o corregido.
- Eventos de `GameEvents` nuevos, emitidos o escuchados.
- Pruebas recomendadas en el editor o en `TESTING ENVIRONMENT`.

## Regla practica

Antes de cerrar un cambio, preguntar:

1. El programador que revise esto sabra donde vive la logica?
2. Sabra que eventos conectan el sistema?
3. Sabra como probar si sigue funcionando?

Si alguna respuesta es no, falta documentacion.
