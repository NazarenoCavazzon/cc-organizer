-- Terminal falsa para probar la TUI fuera de Minecraft: guarda lo dibujado en
-- una grilla de caracteres y alimenta os.pullEvent desde una cola.

local mt = { frames = {} }

local W, H = 51, 19
local screen, cx, cy
local queue, inputs

local function blank()
  local rows = {}
  for y = 1, H do
    local row = {}
    for x = 1, W do row[x] = " " end
    rows[y] = row
  end
  return rows
end

function mt.text()
  local lines = {}
  for y = 1, H do lines[y] = table.concat(screen[y]) end
  return table.concat(lines, "\n")
end

function mt.lastFrame()
  return mt.frames[#mt.frames] or ""
end

function mt.anyFrame(needle)
  for _, f in ipairs(mt.frames) do
    if f:find(needle, 1, true) then return true end
  end
  return false
end

function mt.event(...) queue[#queue + 1] = { ... } end
function mt.key(k) mt.event("key", k, false) end
function mt.char(c) mt.event("char", c) end
function mt.click(button, x, y) mt.event("mouse_click", button, x, y) end
function mt.scroll(dir) mt.event("mouse_scroll", dir, 1, 1) end
function mt.type(text) for c in text:gmatch(".") do mt.char(c) end end
function mt.input(text) inputs[#inputs + 1] = text end

mt.COLOURS = {
  white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32,
  pink = 64, grey = 128, lightGrey = 256, cyan = 512, purple = 1024,
  blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768,
}

mt.KEYS = {
  up = 200, down = 208, pageUp = 201, pageDown = 209, home = 199, ["end"] = 207,
  enter = 28, numPadEnter = 156, backspace = 14, escape = 1, tab = 15,
  f1 = 59, f2 = 60, f5 = 63, f9 = 67, f10 = 68, q = 16,
}

function mt.reset()
  screen, cx, cy = blank(), 1, 1
  queue, inputs = {}, {}
  mt.frames = {}

  _G.colours = mt.COLOURS
  _G.colors = mt.COLOURS
  _G.keys = mt.KEYS

  _G.term = {
    getSize = function() return W, H end,
    isColour = function() return true end,
    isColor = function() return true end,
    setCursorPos = function(x, y) cx, cy = math.floor(x), math.floor(y) end,
    getCursorPos = function() return cx, cy end,
    setCursorBlink = function() end,
    setTextColour = function() end,
    setTextColor = function() end,
    setBackgroundColour = function() end,
    setBackgroundColor = function() end,
    write = function(s)
      s = tostring(s)
      if cy < 1 or cy > H then return end
      for i = 1, #s do
        local x = cx + i - 1
        if x >= 1 and x <= W then screen[cy][x] = s:sub(i, i) end
      end
      cx = cx + #s
    end,
    clearLine = function()
      if cy >= 1 and cy <= H then
        for x = 1, W do screen[cy][x] = " " end
      end
    end,
    clear = function()
      -- Cada clear cierra un cuadro: asi los tests ven lo ultimo dibujado.
      mt.frames[#mt.frames + 1] = mt.text()
      screen = blank()
    end,
  }

  _G.write = function(s) _G.term.write(s) end

  os.pullEvent = function(filter)
    -- Cada espera de evento congela un cuadro: es lo que el jugador ve.
    mt.frames[#mt.frames + 1] = mt.text()
    while true do
      local event = table.remove(queue, 1)
      if not event then error("la cola de eventos se vacio (falta un F10?)", 0) end
      if not filter or event[1] == filter then return table.unpack(event) end
    end
  end
  os.queueEvent = function(...) mt.event(...) end
  os.sleep = function() end

  _G.read = function(_, _, _, default)
    local answer = table.remove(inputs, 1)
    if answer == nil then return default end
    return answer
  end
end

return mt
