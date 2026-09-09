-- Canvas de dibujo sobre un buffer de window.
--
-- Es una instancia y no un singleton porque hay dos vistas a la vez: la
-- terminal de la computadora y el panel del monitor. Comparten codigo pero no
-- pueden compartir el estado del cursor ni el destino.

local draw = {}

local Canvas = {}
Canvas.__index = Canvas

--- `present` se llama para volcar el buffer a la pantalla de una sola vez.
function draw.new(target, present)
  return setmetatable({
    win = target,
    colour = (target.isColour and target.isColour()) or false,
    flush = present or function() end,
  }, Canvas)
end

function draw.fit(s, w)
  s = tostring(s)
  if #s > w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

function Canvas:size()
  return self.win.getSize()
end

function Canvas:present()
  self.flush()
end

--- Las computadoras y monitores normales solo tienen blanco y negro: cualquier
--- fondo que no sea negro se dibuja invertido.
function Canvas:paint(fg, bg)
  if self.colour then
    self.win.setTextColour(fg)
    self.win.setBackgroundColour(bg)
  else
    local inverted = bg ~= colours.black
    self.win.setTextColour(inverted and colours.black or colours.white)
    self.win.setBackgroundColour(inverted and colours.white or colours.black)
  end
end

function Canvas:at(x, y, text)
  self.win.setCursorPos(x, y)
  self.win.write(text)
end

--- Escribe alineado a la derecha terminando en la columna `right`.
function Canvas:right(right, y, text)
  self.win.setCursorPos(math.max(1, right - #text + 1), y)
  self.win.write(text)
end

function Canvas:fill(x, y, w, h, bg)
  self:paint(colours.white, bg)
  for i = 0, h - 1 do
    self:at(x, y + i, string.rep(" ", w))
  end
end

function Canvas:clear()
  self:paint(colours.white, colours.black)
  self.win.clear()
end

function Canvas:cursor(x, y, visible)
  self.win.setCursorPos(x, y)
  self.win.setCursorBlink(visible)
end

return draw
