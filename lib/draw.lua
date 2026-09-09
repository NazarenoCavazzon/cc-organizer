-- Helpers de dibujo sobre un buffer de window: colores con degradado a
-- blanco/negro en computadoras normales, y presentacion atomica del cuadro.

local draw = {}

local win, colour, flush

function draw.attach(target, isColour, present)
  win, colour, flush = target, isColour, present
end

function draw.size()
  return win.getSize()
end

function draw.present()
  if flush then flush() end
end

--- Las computadoras normales solo tienen blanco y negro: cualquier fondo que no
--- sea negro se dibuja invertido.
function draw.paint(fg, bg)
  if colour then
    win.setTextColour(fg)
    win.setBackgroundColour(bg)
  else
    local inverted = bg ~= colours.black
    win.setTextColour(inverted and colours.black or colours.white)
    win.setBackgroundColour(inverted and colours.white or colours.black)
  end
end

function draw.fit(s, w)
  s = tostring(s)
  if #s > w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

function draw.at(x, y, text)
  win.setCursorPos(x, y)
  win.write(text)
end

--- Escribe alineado a la derecha terminando en la columna `right`.
function draw.right(right, y, text)
  win.setCursorPos(math.max(1, right - #text + 1), y)
  win.write(text)
end

function draw.fill(x, y, w, h, bg)
  draw.paint(colours.white, bg)
  for i = 0, h - 1 do
    draw.at(x, y + i, string.rep(" ", w))
  end
end

function draw.clear()
  draw.paint(colours.white, colours.black)
  win.clear()
end

function draw.cursor(x, y, visible)
  win.setCursorPos(x, y)
  win.setCursorBlink(visible)
end

return draw
