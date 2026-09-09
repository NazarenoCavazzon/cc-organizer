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
  { "sword", "tool" }, { "pickaxe", "tool" }, { "axe", "tool" },
  { "shovel", "tool" }, { "hoe", "tool" }, { "shears", "tool" },
  { "helmet", "tool" }, { "chestplate", "tool" }, { "leggings", "tool" },
  { "boots", "tool" }, { "bow", "tool" }, { "shield", "tool" },
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
  { "iron", "lightGrey" }, { "copper", "orange" }, { "charcoal", "grey" },
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

--- Que forma y color le toca a un item. Separado del dibujo para testearlo.
function icons.describe(key)
  local name = shortName(key)
  return {
    kind = matchFirst(KINDS, name) or "block",
    colour = matchFirst(MATERIALS, name) or hashColour(name),
  }
end

--- El sprite como filas de celdas { char, fg, bg }, listo para dibujar.
---
--- Los caracteres 128..159 encienden 5 de los 6 subpixeles y dejan el de abajo
--- a la derecha con el color de fondo. Cuando ese pixel tiene que estar
--- encendido se invierte el patron entero y se intercambian los colores.
function icons.render(key, background)
  local info = icons.describe(key)
  local fg = colours[info.colour] or colours.white
  local bg = background or colours.black
  local shape = SHAPES[info.kind] or SHAPES.block

  local rows = {}
  for cy = 0, HEIGHT / 3 - 1 do
    local cells = {}
    for cx = 0, WIDTH / 2 - 1 do
      local mask, bit = 0, 1
      for py = 1, 3 do
        for px = 1, 2 do
          local char = shape[cy * 3 + py]:sub(cx * 2 + px, cx * 2 + px)
          if char ~= "." and char ~= " " then mask = mask + bit end
          bit = bit * 2
        end
      end
      local front, back = fg, bg
      if mask >= 32 then
        mask = 63 - mask
        front, back = back, front
      end
      cells[cx + 1] = { string.char(128 + mask % 32), front, back }
    end
    rows[cy + 1] = cells
  end
  return rows
end

icons.WIDTH, icons.HEIGHT = WIDTH, HEIGHT

return icons
