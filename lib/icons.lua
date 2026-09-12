-- Sprites de 16x12 pixeles para el detalle de un item.
--
-- La terminal de CC no puede mostrar la textura real, pero cada caracter puede
-- pintar una grilla de 2x3 subpixeles usando los caracteres 128..159. Con 8
-- celdas de ancho por 4 de alto entran 16x12 pixeles, casi la resolucion de una
-- textura de Minecraft.
--
-- El dibujo sale del tipo de item (lingote, gema, herramienta...) y el color del
-- material, asi que cualquier item del juego o de un mod tiene icono sin
-- necesidad de una tabla item por item.

local pixels = require("lib.pixels")

local icons = {}

local WIDTH, HEIGHT = 16, 12

local SHAPES = {}

SHAPES.block = {
  "................",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "................",
}

SHAPES.ingot = {
  "................",
  "................",
  "................",
  "................",
  ".....######.....",
  "....########....",
  "...##########...",
  "..############..",
  ".##############.",
  "################",
  "................",
  "................",
}

SHAPES.gem = {
  "................",
  ".......##.......",
  "......####......",
  ".....######.....",
  "....########....",
  "...##########...",
  "..############..",
  "...##########...",
  ".....######.....",
  ".......##.......",
  "................",
  "................",
}

SHAPES.dust = {
  "................",
  "...##.....##....",
  "..####...####...",
  "...##.....##....",
  ".......##.......",
  "......####......",
  ".......##.......",
  "...##.....##....",
  "..####...####...",
  "...##.....##....",
  "................",
  "................",
}

SHAPES.tool = {
  "................",
  ".....########...",
  "...##........##.",
  "..##...........#",
  ".##.............",
  ".##.............",
  "..##............",
  "...##...........",
  "....##..........",
  ".....##.........",
  "......##........",
  ".......##.......",
}

-- Herramientas y equipo: la silueta tiene que distinguirse sola, porque un pico
-- y un hacha del mismo material comparten color y nombre parecido.

SHAPES.pickaxe = {
  "...##......##...",
  "..####....####..",
  "..#############.",
  "....#########...",
  ".........##.....",
  "........##......",
  ".......##.......",
  "......##........",
  ".....##.........",
  "....##..........",
  "...##...........",
  "..##............",
}

SHAPES.axe = {
  "........#####...",
  ".......########.",
  ".......#########",
  ".......#########",
  ".......########.",
  "........#####...",
  ".......##.......",
  "......##........",
  ".....##.........",
  "....##..........",
  "...##...........",
  "..##............",
}

SHAPES.shovel = {
  "................",
  "........####....",
  ".......######...",
  ".......######...",
  ".......######...",
  "........####....",
  ".......##.......",
  "......##........",
  ".....##.........",
  "....##..........",
  "...##...........",
  "..##............",
}

SHAPES.hoe = {
  "..###########...",
  "..###########...",
  "...........##...",
  "..........##....",
  ".........##.....",
  "........##......",
  ".......##.......",
  "......##........",
  ".....##.........",
  "....##..........",
  "...##...........",
  "..##............",
}

SHAPES.sword = {
  ".......##.......",
  "......####......",
  "......####......",
  "......####......",
  "......####......",
  "......####......",
  "....########....",
  "....########....",
  ".......##.......",
  ".......##.......",
  ".....######.....",
  "................",
}

SHAPES.shears = {
  "..##........##..",
  "...##......##...",
  "....##....##....",
  ".....##..##.....",
  "......####......",
  ".......##.......",
  "......####......",
  ".....##..##.....",
  "....##....##....",
  "...####..####...",
  "...####..####...",
  "................",
}

SHAPES.bow = {
  "...#....####....",
  "...#..##....##..",
  "...#.##.......#.",
  "...##..........#",
  "...#...........#",
  "...#...........#",
  "...#...........#",
  "...#...........#",
  "...##..........#",
  "...#.##.......#.",
  "...#..##....##..",
  "...#....####....",
}

SHAPES.helmet = {
  "....########....",
  "..############..",
  ".##############.",
  ".##############.",
  ".####......####.",
  ".###........###.",
  ".###........###.",
  ".###........###.",
  ".####......####.",
  ".#####....#####.",
  "................",
  "................",
}

SHAPES.chestplate = {
  ".###........###.",
  ".##############.",
  ".##############.",
  ".##############.",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "...##########...",
  "....########....",
  "................",
  "................",
}

SHAPES.leggings = {
  ".##############.",
  ".##############.",
  ".##############.",
  "..############..",
  "..####....####..",
  "..####....####..",
  "..###......###..",
  "..###......###..",
  "..###......###..",
  "..###......###..",
  "................",
  "................",
}

SHAPES.boots = {
  "................",
  "..###......###..",
  "..###......###..",
  "..###......###..",
  "..###......###..",
  "..####....####..",
  "..#####..#####..",
  ".######..######.",
  ".######..######.",
  "................",
  "................",
  "................",
}

SHAPES.shield = {
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "..############..",
  "...##########...",
  "...##########...",
  "....########....",
  ".....######.....",
  "......####......",
  ".......##.......",
  "................",
}

SHAPES.rod = {
  "................",
  "............##..",
  "...........##...",
  "..........##....",
  ".........##.....",
  "........##......",
  ".......##.......",
  "......##........",
  ".....##.........",
  "....##..........",
  "...##...........",
  "..##............",
}

SHAPES.food = {
  "................",
  ".......##.......",
  "......##........",
  "....########....",
  "..############..",
  ".##############.",
  ".##############.",
  ".##############.",
  "..############..",
  "...##########...",
  ".....######.....",
  "................",
}

SHAPES.plant = {
  "................",
  ".......##.......",
  "..##...##...##..",
  ".####..##..####.",
  "..####.##.####..",
  "....##.##.##....",
  ".......##.......",
  ".......##.......",
  ".......##.......",
  "....##########..",
  "....##########..",
  "................",
}

SHAPES.liquid = {
  "................",
  ".....######.....",
  ".....#....#.....",
  "....##....##....",
  "....#......#....",
  "....#.####.#....",
  "....#.####.#....",
  "....#.####.#....",
  "....#.####.#....",
  "....########....",
  "....########....",
  "................",
}

-- Gana el primero que matchea, asi que el orden importa: "golden_apple" es
-- comida antes que oro.
local KINDS = {
  { "seeds", "plant" }, { "sapling", "plant" }, { "flower", "plant" },
  { "leaves", "plant" }, { "wheat", "plant" }, { "bamboo", "plant" },
  { "apple", "food" }, { "carrot", "food" }, { "potato", "food" },
  { "bread", "food" }, { "beef", "food" }, { "porkchop", "food" },
  { "chicken", "food" }, { "cooked", "food" }, { "stew", "food" },
  { "soup", "food" }, { "berries", "food" }, { "melon", "food" },
  -- El orden importa de nuevo: "pickaxe" termina en "axe".
  { "pickaxe", "pickaxe" }, { "axe", "axe" }, { "sword", "sword" },
  { "trident", "sword" }, { "dagger", "sword" }, { "shovel", "shovel" },
  { "spade", "shovel" }, { "hoe", "hoe" }, { "shears", "shears" },
  { "helmet", "helmet" }, { "cap", "helmet" }, { "chestplate", "chestplate" },
  { "tunic", "chestplate" }, { "elytra", "chestplate" }, { "leggings", "leggings" },
  { "pants", "leggings" }, { "boots", "boots" }, { "bow", "bow" },
  { "shield", "shield" },
  { "ingot", "ingot" }, { "nugget", "dust" }, { "dust", "dust" },
  { "powder", "dust" }, { "gunpowder", "dust" }, { "sand", "dust" },
  { "gravel", "dust" }, { "redstone", "dust" },
  { "diamond", "gem" }, { "emerald", "gem" }, { "amethyst", "gem" },
  { "quartz", "gem" }, { "lapis", "gem" }, { "coal", "gem" },
  { "pearl", "gem" }, { "shard", "gem" }, { "star", "gem" },
  { "stick", "rod" }, { "rod", "rod" }, { "arrow", "rod" }, { "torch", "rod" },
  { "bucket", "liquid" }, { "bottle", "liquid" }, { "potion", "liquid" },
}

local MATERIALS = {
  { "netherite", "brown" }, { "diamond", "lightBlue" }, { "emerald", "green" },
  { "amethyst", "purple" }, { "quartz", "white" }, { "lapis", "blue" },
  { "redstone", "red" }, { "golden", "yellow" }, { "gold", "yellow" },
  { "iron", "lightGrey" }, { "chainmail", "lightGrey" }, { "copper", "orange" },
  { "turtle", "green" }, { "charcoal", "grey" },
  { "coal", "grey" }, { "obsidian", "purple" }, { "glowstone", "yellow" },
  { "prismarine", "cyan" }, { "ice", "lightBlue" }, { "snow", "white" },
  { "sand", "yellow" }, { "gravel", "grey" }, { "clay", "lightGrey" },
  { "dirt", "brown" }, { "grass", "lime" }, { "podzol", "brown" },
  { "cobblestone", "grey" }, { "deepslate", "grey" }, { "andesite", "lightGrey" },
  { "diorite", "white" }, { "granite", "orange" }, { "stone", "grey" },
  { "netherrack", "red" }, { "basalt", "grey" }, { "blackstone", "black" },
  { "oak", "brown" }, { "spruce", "brown" }, { "birch", "yellow" },
  { "jungle", "brown" }, { "acacia", "orange" }, { "cherry", "pink" },
  { "mangrove", "red" }, { "bamboo", "lime" }, { "crimson", "magenta" },
  { "warped", "cyan" }, { "wood", "brown" }, { "log", "brown" },
  { "plank", "brown" }, { "leaves", "green" }, { "wheat", "yellow" },
  { "hay", "yellow" }, { "wool", "white" }, { "glass", "lightBlue" },
  { "water", "blue" }, { "lava", "orange" }, { "slime", "lime" },
  { "honey", "orange" }, { "ender", "cyan" }, { "blaze", "orange" },
  { "bone", "white" }, { "string", "white" }, { "leather", "brown" },
  { "book", "brown" }, { "paper", "white" }, { "brick", "red" },
  { "terracotta", "orange" }, { "concrete", "lightGrey" },
}

-- Para lo desconocido: un color estable sacado del nombre, asi al menos dos
-- items distintos no se ven igual.
local PALETTE = {
  "red", "orange", "yellow", "lime", "green", "cyan",
  "lightBlue", "blue", "purple", "magenta", "pink", "brown",
}

local function hashColour(name)
  local sum = 0
  for i = 1, #name do
    sum = (sum * 31 + name:byte(i)) % 100003
  end
  return PALETTE[sum % #PALETTE + 1]
end

local function shortName(key)
  local name = key:match("^(.-)@") or key
  return (name:match("[^:]+$") or name):lower()
end

local function matchFirst(list, name)
  for _, pair in ipairs(list) do
    if name:find(pair[1], 1, true) then return pair[2] end
  end
  return nil
end

-- Categorias para navegar la lista, agrupando las formas.
local CATEGORIES = {
  block = "bloques", ingot = "materiales", gem = "materiales", dust = "materiales",
  rod = "materiales", liquid = "materiales", food = "comida", plant = "plantas",
}
-- Todas las siluetas de herramienta y equipo caen en la misma categoria.
for _, kind in ipairs({ "tool", "pickaxe", "axe", "sword", "shovel", "hoe", "shears",
                        "bow", "shield", "helmet", "chestplate", "leggings", "boots" }) do
  CATEGORIES[kind] = "herramientas"
end

icons.CATEGORIES = { "bloques", "materiales", "herramientas", "comida", "plantas" }

--- Categoria de un item, para el filtro por categoria de la lista.
function icons.category(key)
  return CATEGORIES[icons.describe(key).kind] or "bloques"
end

--- Que forma y color le toca a un item. Separado del dibujo para testearlo.
function icons.describe(key)
  local name = shortName(key)
  return {
    kind = matchFirst(KINDS, name) or "block",
    colour = matchFirst(MATERIALS, name) or hashColour(name),
  }
end

--- El sprite como filas de celdas { char, fg, bg }, listo para dibujar.
function icons.render(key, background)
  local info = icons.describe(key)
  return pixels.toCells(SHAPES[info.kind] or SHAPES.block,
                        colours[info.colour] or colours.white,
                        background or colours.black)
end

--- Las filas de pixeles crudas, para tests y para dibujar en otro lado.
function icons.shape(key)
  return SHAPES[icons.describe(key).kind] or SHAPES.block
end

icons.WIDTH, icons.HEIGHT = WIDTH, HEIGHT

return icons
