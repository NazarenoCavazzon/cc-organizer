-- Dibujo a subpixel: cada caracter de la terminal es una grilla de 2x3 pixeles
-- usando los caracteres 128..159.
--
-- Los caracteres encienden 5 de los 6 subpixeles y dejan el de abajo a la
-- derecha con el color de fondo; cuando ese pixel tiene que estar encendido se
-- invierte el patron entero y se intercambian los colores.

local pixels = {}

-- Reglas finas, para separar secciones sin comerse una fila entera.
pixels.RULE_H = string.char(128 + 12)  -- linea al medio de la celda
pixels.RULE_V = string.char(128 + 21)  -- linea sobre el borde izquierdo

--- Convierte filas de texto ('.' o ' ' = apagado) en celdas { char, fg, bg }.
function pixels.toCells(rows, fg, bg)
  local width = 0
  for _, row in ipairs(rows) do width = math.max(width, #row) end

  local out = {}
  for cy = 0, math.ceil(#rows / 3) - 1 do
    local cells = {}
    for cx = 0, math.ceil(width / 2) - 1 do
      local mask, bit = 0, 1
      for py = 1, 3 do
        for px = 1, 2 do
          local row = rows[cy * 3 + py]
          local char = row and row:sub(cx * 2 + px, cx * 2 + px) or ""
          if char ~= "" and char ~= "." and char ~= " " then mask = mask + bit end
          bit = bit * 2
        end
      end
      local front, back = fg, bg
      if mask >= 32 then
        mask, front, back = 63 - mask, bg, fg
      end
      cells[cx + 1] = { string.char(128 + mask % 32), front, back }
    end
    out[cy + 1] = cells
  end
  return out
end

--- Dibuja esas filas en un canvas, empezando en la celda (x, y).
function pixels.draw(canvas, x, y, rows, fg, bg)
  local cells = pixels.toCells(rows, fg, bg)
  for row, line in ipairs(cells) do
    for column, cell in ipairs(line) do
      canvas:paint(cell[2], cell[3])
      canvas:at(x + column - 1, y + row - 1, cell[1])
    end
  end
  return #(cells[1] or {}), #cells
end

--- Regla horizontal fina.
function pixels.ruleH(canvas, x, y, width, fg, bg)
  canvas:paint(fg, bg)
  canvas:at(x, y, string.rep(pixels.RULE_H, width))
end

--- Regla vertical fina.
function pixels.ruleV(canvas, x, y, height, fg, bg)
  canvas:paint(fg, bg)
  for i = 0, height - 1 do canvas:at(x, y + i, pixels.RULE_V) end
end

return pixels
