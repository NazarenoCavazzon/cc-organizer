# cc-organizer

Almacenamiento automatico para CC:Tweaked (1.16+): muchos cofres en una red de modems
cableados, un cofre de entrada que se vacia solo y un cofre de salida para los pedidos.

## Armado en el juego

1. Una **Advanced Computer** con un modem cableado pegado.
2. Un **modem cableado** en cada cofre, activado con click derecho (se pone rojo).
3. **Networking cable** uniendo todo.
4. Dos cofres mas de la misma red: uno de entrada y uno de salida.

## Instalacion

Copiar el repo a la computadora (o clonarlo en `.minecraft/saves/<mundo>/computercraft/computer/<id>/`).
Al arrancar, correr `startup` y usar el comando `peripherals` para ver los nombres reales
(`minecraft:chest_0`, etc.) y ponerlos en `config.lua`:

```lua
input = "minecraft:chest_0",   -- donde tiras los items
output = "minecraft:chest_1",  -- donde aparecen los pedidos
```

Reiniciar la computadora: `startup.lua` corre solo al encender.

## Comandos

| comando | que hace |
|---|---|
| `stock [filtro]` | que hay guardado, ordenado por cantidad |
| `find <texto>` | igual pero mostrando los ids completos |
| `get <item> [n]` | manda n unidades al cofre de salida (default 64) |
| `store` | vacia el cofre de entrada ahora mismo |
| `space` | slots usados / libres |
| `refresh` | re-escanea toda la red |
| `peripherals` | nombres de la red, para configurar |
| `exit` | salir |

El cofre de entrada se vacia solo cada 3 segundos (`autoStoreInterval` en `config.lua`),
asi que `store` es solo para apurarlo.

## Como reparte los items

Al guardar, cada stack va primero al cofre que **ya tiene ese item** con espacio (compacta
stacks parciales) y si no, al cofre con **mas slots libres**. Items con NBT distinto
(encantados, con durabilidad) se indexan por separado, igual que en el juego.

## Tests

Sin Minecraft, con Lua local:

```sh
lua tests/run.lua
```

`tests/mock_peripheral.lua` simula la red de cofres (`list`, `size`, `pullItems`,
`getItemDetail`) para probar el reparto, los limites de stack, el almacenamiento lleno,
la entrega parcial y la consistencia del indice.
