# cc-organizer

Almacenamiento automatico para CC:Tweaked (1.16+): muchos cofres en una red de modems
cableados, un cofre de entrada que se vacia solo y un cofre de salida para los pedidos.
La interfaz es una TUI de pantalla completa con busqueda en vivo.

```
 cc-organizer                54/54 slots  2 cofres
buscar: oak                          2 items  cant
    384  Oak Log
   2048  Oak Planks

 384 Oak Log -> minecraft:chest_1
 enter pedir   F1 ayuda   F5 scan   F10 salir
```

## Armado en el juego

1. Una **Advanced Computer** con un modem cableado pegado (el mouse y los colores
   solo andan en las advanced).
2. Un **modem cableado** en cada cofre, activado con click derecho (se ilumina).
3. **Networking cable** uniendo todo.
4. Dos cofres mas de la misma red: uno de entrada y uno de salida.

## Instalacion

Con el repo publico, desde la computadora:

```
wget https://raw.githubusercontent.com/NazarenoCavazzon/cc-organizer/main/install.lua install.lua
install
```

El instalador consulta el ultimo commit y baja todo pineado a ese SHA. Es a
proposito: las URLs de rama de `raw.githubusercontent.com` quedan cacheadas unos
minutos, y sin eso "actualizo y sigue igual" es lo normal.

O copiando los archivos a `<mundo>/computercraft/computer/<ID>/`.

La primera vez, si los cofres de `config.lua` no estan en la red, se abre solo un
asistente para elegir cual es el de entrada y cual el de salida; guarda `config.lua`
por vos. Se puede volver a abrir con **F9**.

## Atajos

| tecla | que hace |
|---|---|
| escribir | filtra la lista en vivo (por nombre o id) |
| flechas / RePag / AvPag | mover la seleccion |
| enter | pedir: abre el dialogo de cantidad |
| tab | detalle del item: en que cofres esta y cuantos slots ocupa |
| click | seleccionar; click de nuevo pide |
| click derecho | pedir todo el stock de ese item |
| ctrl+u | limpiar la busqueda |
| F1 | ayuda |
| F2 | ordenar por cantidad / alfabetico (o click en `[cant]`) |
| F3 | diagnostico del armado |
| F5 | re-escanear la red |
| F9 | reconfigurar entrada/salida |
| ctrl+d | cancelar un dialogo |
| F10 | salir |

El **escape no se usa**: en CC cierra la GUI de la computadora y el programa
nunca lo recibe. Para cancelar un dialogo es `ctrl+d` o el boton `cancelar`.

En el dialogo de cantidad viene sugerido un stack, el primer numero que escribis
lo reemplaza, y podes escribir cuentas (`64*3+16`). Tambien hay botones
`1 / 16 / 64 / todo` y `cancelar` clickeables, y las flechas suben y bajan de a uno.

El cofre de entrada se vacia solo cada 3 segundos (`autoStoreInterval` en `config.lua`)
y la pantalla avisa cuanto guardo. Si rompes o agregas un cofre, el indice se actualiza
solo.

## Como reparte los items

Al guardar, cada stack va primero al cofre que **ya tiene ese item** con espacio (compacta
stacks parciales) y si no, al cofre con **mas slots libres**. Items con NBT distinto
(encantados, con durabilidad) se indexan por separado, igual que en el juego.

## Estructura

```
startup.lua        arranque, guardado automatico y vigilancia de la red
config.lua         cofres de entrada/salida e intervalo
lib/storage.lua    indice, reparto y entrega
lib/items.lua      claves de item, cache de nombres, busqueda
lib/ui.lua         TUI: lista, busqueda y eventos
lib/dialog.lua     ventanas modales (cantidad, detalle, ayuda)
lib/draw.lua       helpers de dibujo sobre el buffer
lib/setup.lua      asistente de configuracion
install.lua        instalador via wget
```

## Tests

Sin Minecraft, con Lua local:

```sh
sh tests/check.sh
```

Eso hace dos cosas. Primero parsea con **luajit** todos los archivos que van a la
computadora: CC:Tweaked corre **Lua 5.1** y el Lua del sistema (5.4+) acepta
sintaxis que en el juego explota, como `//`. Despues corre los tests con los dos
interpretes, asi que tambien se validan las diferencias de runtime.

`tests/mock_peripheral.lua` simula la red de cofres y `tests/mock_term.lua` una terminal
de 51x19 con cola de eventos, asi que se testean tanto el reparto (stacks parciales,
limites de stack, almacenamiento lleno, entrega parcial, cofre roto) como la TUI
(busqueda, seleccion, pedidos, overlays, scroll).

## Si algo no anda

**F3** abre el diagnostico: muestra los problemas detectados (cofres pegados a la
computadora en vez de conectados por cable, entrada/salida que no existen, sin cofres
de almacenamiento, o el almacenamiento realmente lleno) y la ocupacion de cada cofre.
El mismo chequeo corre al arrancar y avisa antes de abrir la interfaz.

El error mas comun es que los modems **no esten unidos entre si con networking
cable**. Un modem suelto es su propia red: la computadora los ve a todos (porque
los toca), pero un cofre de una red no puede moverle items a un cofre de otra, y
no se guarda nada. En el diagnostico esos cofres salen marcados como `OTRA RED`.

El otro error comun es tener el cofre de entrada **pegado** a la computadora: en ese caso
su nombre es un lado (`top`, `left`, `back`...) en vez de `minecraft:chest_N`, y ningun
otro cofre de la red puede sacarle items. Se arregla poniendole un modem cableado al
cofre, activandolo con click derecho, y eligiendolo de nuevo con **F9**.
