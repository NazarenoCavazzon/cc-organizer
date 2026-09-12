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

1. Una **Advanced Computer** con un modem cableado pegado. En una computadora
   normal el programa anda igual, pero **sin mouse ni colores**: CC solo manda
   eventos de click en las advanced. Todo se puede hacer con el teclado.
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
| tab | detalle del item: sprite, durabilidad, encantamientos y en que cofres esta |
| click | seleccionar; click de nuevo pide (solo Advanced Computer) |
| click derecho | pedir todo el stock de ese item (idem) |
| a (en el dialogo) | poner todo el stock como cantidad |
| flechas izq/der | cambiar de categoria (todo, recientes, bloques, materiales, herramientas, comida, plantas) |
| `#logs` `#ores` | filtrar por tag del juego, no por nombre |
| `fortune` | la busqueda tambien mira los encantamientos |
| F4 | repetir el ultimo pedido, con la misma cantidad |
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
lo reemplaza, y podes escribir cuentas (`64*3+16`). Los botones `1 / 16 / 64 /
todo` **solo llenan el campo**: para que salgan los items hay que confirmar con
`enter` o con el boton `pedir`, asi un click de mas no te vacia el cofre. Las
flechas suben y bajan de a uno.

El cofre de entrada se vacia solo cada 3 segundos (`autoStoreInterval` en `config.lua`)
y la pantalla avisa cuanto guardo. Si rompes o agregas un cofre, el indice se actualiza
solo.

## Panel en un monitor

Si hay un monitor en la red (o pegado a la computadora) se dibuja solo, sin
configurar nada:

```
 CC-ORGANIZER (en letra grande)              15 tipos
 ---------------------------------------------------
 STOCK                        | ACTIVIDAD
   1.7k Cobblestone           | -64   Oak Log
   1.2k Sand                  | +833  Coal
    999 Torch                 | +96   Gold Ingot
 ---------------------------------------------------
 bloques 4.6k  materiales 4.1k  comida 64
 #########------  65%  142/216  1/2
```

- **Titulo en letra grande**, dibujado con una tipografia de 3x5 pixeles sobre
  los subpixeles del monitor (`lib/bigtext.lua`), para que se lea de lejos.
- **Actividad**: las ultimas entradas y salidas, `+` lo que se guardo, `-` lo que
  se entrego.
- **Paginacion**: si el stock no entra, el panel rota solo cada 5 segundos y lo
  indica abajo a la derecha (`1/2`).
- **Resumen por categoria** y barra de ocupacion, con aviso `ESPACIO BAJO`
  cuando queda menos del 10% de slots.
- Las secciones se separan con reglas finas dibujadas a subpixel, no con lineas
  de guiones.

Anda igual en un monitor comun: sin color la barra se dibuja blanco sobre negro
en vez de dos grises que se verian iguales, y en monitores chicos cae a un
layout compacto sin titulo grande ni columnas. Se actualiza
cuando algo cambia y cada 5 segundos, y se acomoda al tamano del monitor: usa
tantas columnas como entren. No hay que configurar nada; si conectas el monitor
con el programa andando, lo detecta.

## Categorias, tags y recientes

La lista se filtra de tres formas, combinables:

- **texto**: `cobble`, busca en el nombre visible y en el id
- **tag del juego**: `#logs`, `#ores`, `#ingots` — sale de `getItemDetail`, asi que
  funciona con items de mods sin saber como se llaman
- **categoria** (flechas izquierda/derecha): bloques, materiales, herramientas,
  comida, plantas, y **recientes**, que son los ultimos 20 items que pediste

Los recientes se guardan en `recent.txt` y sobreviven al reboot. **F4** repite el
ultimo pedido con la misma cantidad, para confirmar de nuevo.

## Herramientas: durabilidad y encantamientos

Dos picos de diamante se llaman igual en la lista, asi que cada herramienta
muestra a la derecha de su fila **cuanta durabilidad le queda** (`36%`, verde
sobre la mitad, amarillo abajo de 50, rojo abajo de 25) y un `*` si esta
**encantada**. El detalle (tab) agrega la barra de desgaste, los usos que
quedan y la lista de encantamientos con su nivel:

```
 Diamond Pickaxe
 ########  minecraft:diamond_pickaxe@a
 ########  1 unidad
 ########  durabilidad 36% [####------]
 ########  quedan 561 de 1561 usos
 encantamientos:
   Efficiency V
   Fortune III
```

Todo sale de `getItemDetail`: `damage`/`maxDamage` (o `durability` segun la
version) y `enchantments`. Buscar `fortune` filtra por encantamiento.

## Los sprites

La terminal de CC no puede mostrar la textura real de un item, pero cada
caracter puede pintar 2x3 subpixeles con los caracteres 128..159. El detalle
(tab) usa 8 celdas por 4 filas, o sea **16x12 pixeles**, casi la resolucion de
una textura de Minecraft.

Los dibujos son procedurales: la **forma** sale del tipo de item y el **color**
del material (hierro gris claro, diamante celeste, madera marron...). Cada
herramienta tiene su propia silueta —pico, hacha, pala, azada, espada, tijeras,
arco, escudo, casco, pechera, grebas y botas— porque un pico y un hacha del
mismo material comparten color y nombre parecido; el resto son lingote, gema,
polvo, comida, planta, liquido, palo y bloque. Asi cualquier
item del juego o de un mod tiene icono sin mantener una tabla item por item; lo
desconocido cae en un color estable sacado del nombre. Esta en `lib/icons.lua`.

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
lib/pixels.lua     dibujo a subpixel (2x3 por caracter)
lib/bigtext.lua    tipografia de 3x5 para titulos y numeros
lib/icons.lua      sprites procedurales de 16x12
lib/monitor.lua    panel de solo lectura en un monitor
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
