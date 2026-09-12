-- Tests de los sprites: clasificacion y codificacion de subpixeles.

local icons = require("lib.icons")
local mterm = require("tests.mock_term")
local h = require("tests.harness")

local eq, check, test = h.eq, h.check, h.test

--- Decodifica una celda a sus 6 subpixeles, deshaciendo la inversion.
--- Es la operacion inversa a la que hace icons.render: si las dos coinciden,
--- el patron que ve el jugador es el que dibujamos.
local function decode(cell, fg)
  local char, front = cell[1]:byte(), cell[2]
  local mask = char - 128
  if front ~= fg then mask = 63 - mask end
  local pixels = {}
  for bit = 0, 5 do
    pixels[bit + 1] = math.floor(mask / 2 ^ bit) % 2 == 1
  end
  return pixels
end

test("clasifica items por tipo y material", function()
  mterm.reset()
  eq(icons.describe("minecraft:iron_ingot").kind, "ingot", "lingote")
  eq(icons.describe("minecraft:iron_ingot").colour, "lightGrey", "color del hierro")
  eq(icons.describe("minecraft:diamond").kind, "gem", "gema")
  eq(icons.describe("minecraft:diamond").colour, "lightBlue", "color del diamante")
  eq(icons.describe("minecraft:diamond_pickaxe").kind, "pickaxe", "herramienta antes que gema")
  eq(icons.describe("minecraft:golden_apple").kind, "food", "comida antes que oro")
  eq(icons.describe("minecraft:oak_log").colour, "brown", "madera")
  eq(icons.describe("minecraft:cobblestone").kind, "block", "el default es bloque")
  eq(icons.describe("minecraft:redstone").kind, "dust", "polvo")
end)

test("cada herramienta tiene su propia silueta", function()
  mterm.reset()
  -- El problema que resuelve: un pico y un hacha de diamante comparten color y
  -- nombre parecido; si comparten dibujo no hay forma de distinguirlos.
  local kinds = {}
  for key, expected in pairs({
    ["minecraft:diamond_pickaxe"] = "pickaxe", ["minecraft:diamond_axe"] = "axe",
    ["minecraft:diamond_shovel"] = "shovel", ["minecraft:diamond_hoe"] = "hoe",
    ["minecraft:diamond_sword"] = "sword", ["minecraft:shears"] = "shears",
    ["minecraft:bow"] = "bow", ["minecraft:shield"] = "shield",
    ["minecraft:iron_helmet"] = "helmet", ["minecraft:iron_chestplate"] = "chestplate",
    ["minecraft:iron_leggings"] = "leggings", ["minecraft:iron_boots"] = "boots",
  }) do
    eq(icons.describe(key).kind, expected, key)
    eq(icons.category(key), "herramientas", "sigue siendo herramienta: " .. key)

    local shape = icons.shape(key)
    eq(#shape, 12, "12 filas de pixeles: " .. key)
    for _, row in ipairs(shape) do
      eq(#row, 16, "16 pixeles de ancho: " .. key)
    end

    local art = table.concat(shape, "/")
    check(kinds[art] == nil, ("%s se dibuja igual que %s"):format(key, tostring(kinds[art])))
    kinds[art] = key
  end
end)

test("el material sigue decidiendo el color de la herramienta", function()
  mterm.reset()
  eq(icons.describe("minecraft:diamond_pickaxe").colour, "lightBlue", "diamante")
  eq(icons.describe("minecraft:iron_pickaxe").colour, "lightGrey", "hierro")
  eq(icons.describe("minecraft:golden_pickaxe").colour, "yellow", "oro")
  eq(icons.describe("minecraft:netherite_pickaxe").colour, "brown", "netherite")
  eq(icons.describe("minecraft:stone_pickaxe").colour, "grey", "piedra")
  eq(icons.describe("minecraft:wooden_pickaxe").colour, "brown", "madera")
end)

test("el item con NBT usa el icono del item base", function()
  mterm.reset()
  eq(icons.describe("minecraft:diamond_sword@abc123").kind, "sword", "ignora el NBT")
  eq(icons.describe("minecraft:diamond_sword@abc").colour,
     icons.describe("minecraft:diamond_sword").colour, "y el color no cambia")
end)

test("un item desconocido igual tiene color estable", function()
  mterm.reset()
  local first = icons.describe("algunmod:cosa_rara").colour
  eq(icons.describe("algunmod:cosa_rara").colour, first, "siempre el mismo")
  check(first ~= nil, "y no es nil")
  check(icons.describe("algunmod:otra_cosa").colour ~= nil, "otro item, otro color valido")
end)

test("el sprite mide 8 celdas por 4 filas", function()
  mterm.reset()
  local sprite = icons.render("minecraft:iron_ingot", colours.black)
  eq(#sprite, 4, "filas")
  eq(#sprite[1], 8, "columnas")
  for _, row in ipairs(sprite) do
    for _, cell in ipairs(row) do
      local byte = cell[1]:byte()
      check(byte >= 128 and byte <= 159, "usa los caracteres de bloque: " .. byte)
    end
  end
end)

test("los subpixeles dibujados son los del sprite", function()
  mterm.reset()
  -- La fila de abajo del lingote es solida: los 16 pixeles encendidos.
  local sprite = icons.render("minecraft:iron_ingot", colours.black)
  local fg = colours[icons.describe("minecraft:iron_ingot").colour]
  local bottom = sprite[4]
  local on = 0
  for _, cell in ipairs(bottom) do
    for _, lit in ipairs(decode(cell, fg)) do
      if lit then on = on + 1 end
    end
  end
  eq(on, 16, "la base del lingote son 16 pixeles llenos (fila 10 del dibujo)")

  -- Y la primera fila esta vacia en todos los sprites.
  local top = icons.render("minecraft:diamond", colours.black)[1]
  local topLit = 0
  for _, cell in ipairs(top) do
    for i, lit in ipairs(decode(cell, colours[icons.describe("minecraft:diamond").colour])) do
      if lit and i <= 2 then topLit = topLit + 1 end
    end
  end
  eq(topLit, 0, "la fila de arriba del todo esta vacia")
end)

test("la inversion intercambia los colores", function()
  mterm.reset()
  -- El bloque tiene celdas llenas, que necesitan el subpixel de abajo a la
  -- derecha: esas se dibujan invertidas.
  local sprite = icons.render("minecraft:cobblestone", colours.black)
  local inverted = 0
  for _, row in ipairs(sprite) do
    for _, cell in ipairs(row) do
      if cell[3] ~= colours.black then inverted = inverted + 1 end
    end
  end
  check(inverted > 0, "hay celdas invertidas")
end)
