-- Tipografia de 3x5 pixeles para titulos y numeros grandes.
--
-- Dibujada con subpixeles (lib/pixels), un caracter ocupa 2 celdas de ancho y
-- 2 de alto. Sirve para darle jerarquia al panel: el titulo y el numero
-- principal se leen de lejos, el resto queda en texto normal.

local pixels = require("lib.pixels")

local bigtext = {}

-- Cada glifo son 5 filas de 3 pixeles, separadas por "/".
local FONT = {
  ["0"] = "###/#.#/#.#/#.#/###",
  ["1"] = ".#./##./.#./.#./###",
  ["2"] = "###/..#/###/#../###",
  ["3"] = "###/..#/.##/..#/###",
  ["4"] = "#.#/#.#/###/..#/..#",
  ["5"] = "###/#../###/..#/###",
  ["6"] = "###/#../###/#.#/###",
  ["7"] = "###/..#/..#/..#/..#",
  ["8"] = "###/#.#/###/#.#/###",
  ["9"] = "###/#.#/###/..#/###",
  ["A"] = "###/#.#/###/#.#/#.#",
  ["B"] = "##./#.#/##./#.#/##.",
  ["C"] = "###/#../#../#../###",
  ["D"] = "##./#.#/#.#/#.#/##.",
  ["E"] = "###/#../###/#../###",
  ["F"] = "###/#../###/#../#..",
  ["G"] = "###/#../#.#/#.#/###",
  ["H"] = "#.#/#.#/###/#.#/#.#",
  ["I"] = "###/.#./.#./.#./###",
  ["J"] = "..#/..#/..#/#.#/###",
  ["K"] = "#.#/#.#/##./#.#/#.#",
  ["L"] = "#../#../#../#../###",
  ["M"] = "#.#/###/###/#.#/#.#",
  ["N"] = "#.#/##./#.#/#.#/#.#",
  ["O"] = "###/#.#/#.#/#.#/###",
  ["P"] = "###/#.#/###/#../#..",
  ["Q"] = "###/#.#/#.#/###/..#",
  ["R"] = "###/#.#/##./#.#/#.#",
  ["S"] = "###/#../###/..#/###",
  ["T"] = "###/.#./.#./.#./.#.",
  ["U"] = "#.#/#.#/#.#/#.#/###",
  ["V"] = "#.#/#.#/#.#/#.#/.#.",
  ["W"] = "#.#/#.#/###/###/#.#",
  ["X"] = "#.#/#.#/.#./#.#/#.#",
  ["Y"] = "#.#/#.#/.#./.#./.#.",
  ["Z"] = "###/..#/.#./#../###",
  ["-"] = ".../.../###/.../...",
  ["."] = ".../.../.../.../.#.",
  [":"] = ".../.#./.../.#./...",
  ["%"] = "#.#/..#/.#./#../#.#",
  ["/"] = "..#/..#/.#./#../#..",
  ["+"] = ".../.#./###/.#./...",
  [" "] = ".../.../.../.../...",
}

local GLYPH_WIDTH, GLYPH_HEIGHT, GAP = 3, 5, 1

local function glyph(char)
  return FONT[char:upper()] or FONT[" "]
end

--- Filas de pixeles de un texto, listas para pixels.draw.
function bigtext.rows(text)
  local rows = {}
  for i = 1, GLYPH_HEIGHT do rows[i] = "" end
  for i = 1, #text do
    local parts, index = glyph(text:sub(i, i)), 1
    for line in parts:gmatch("[^/]+") do
      rows[index] = rows[index] .. line .. string.rep(".", i < #text and GAP or 0)
      index = index + 1
    end
  end
  return rows
end

--- Cuantas celdas ocupa un texto: ancho, alto.
function bigtext.size(text)
  if #text == 0 then return 0, 0 end
  local width = #text * GLYPH_WIDTH + (#text - 1) * GAP
  return math.ceil(width / 2), math.ceil(GLYPH_HEIGHT / 3)
end

function bigtext.draw(canvas, x, y, text, fg, bg)
  return pixels.draw(canvas, x, y, bigtext.rows(text), fg, bg)
end

return bigtext
