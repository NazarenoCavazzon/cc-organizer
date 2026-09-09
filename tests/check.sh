#!/bin/sh
# Verificacion completa. Correr desde la raiz del repo: sh tests/check.sh
#
# CC:Tweaked corre Lua 5.1, pero los tests corren con el Lua del sistema (5.4+),
# que acepta sintaxis que en el juego explota (por ejemplo `//`). Por eso los
# archivos que van a la computadora se parsean con LuaJIT, que es 5.1.
set -e

RUNTIME="startup.lua config.lua install.lua lib/draw.lua lib/dialog.lua lib/items.lua lib/setup.lua lib/storage.lua lib/ui.lua"

if command -v luajit > /dev/null 2>&1; then
  echo "sintaxis Lua 5.1 (como CC:Tweaked):"
  for file in $RUNTIME; do
    luajit -e "assert(loadfile('$file'))" || exit 1
    echo "  ok $file"
  done
else
  echo "! luajit no esta instalado: no puedo verificar la sintaxis 5.1"
  echo "  brew install luajit"
fi

echo
echo "tests con el lua del sistema:"
lua tests/run.lua

if command -v luajit > /dev/null 2>&1; then
  echo
  echo "tests con semantica 5.1 (luajit):"
  luajit tests/run.lua
fi
