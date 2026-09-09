-- Tests del panel del monitor. Se dibuja sobre un monitor falso con su propia
-- grilla, asi que no pisa la terminal.

local mock = require("tests.mock_peripheral")
local mterm = require("tests.mock_term")
local draw = require("lib.draw")
local monitor = require("lib.monitor")
local h = require("tests.harness")

local eq, check, test = h.eq, h.check, h.test

local IN, OUT = "minecraft:chest_in", "minecraft:chest_out"

--- Monitor de mentira: guarda lo dibujado en una grilla propia.
local function fakeMonitor(width, height)
  local grid = {}
  local cx, cy = 1, 1
  local function blank()
    for y = 1, height do
      grid[y] = {}
      for x = 1, width do grid[y][x] = " " end
    end
  end
  blank()
  return {
    getSize = function() return width, height end,
    isColour = function() return true end,
    setTextScale = function() end,
    setCursorPos = function(x, y) cx, cy = math.floor(x), math.floor(y) end,
    setCursorBlink = function() end,
    setTextColour = function() end,
    setBackgroundColour = function() end,
    clear = blank,
    write = function(s)
      if cy < 1 or cy > height then return end
      for i = 1, #s do
        local x = cx + i - 1
        if x >= 1 and x <= width then grid[cy][x] = s:sub(i, i) end
      end
      cx = cx + #s
    end,
    text = function()
      local lines = {}
      for y = 1, height do lines[y] = table.concat(grid[y]) end
      return table.concat(lines, "\n")
    end,
  }
end

local function setup(stock, width, height)
  mock.reset({
    { name = IN, size = 27 }, { name = OUT, size = 27 },
    { name = "minecraft:chest_0", size = 27 }, { name = "minecraft:chest_1", size = 27 },
  })
  mterm.reset()
  for _, mod in ipairs({ "lib.storage", "lib.items" }) do package.loaded[mod] = nil end
  require("lib.items").reset()
  local storage = require("lib.storage")
  storage.init({ input = IN, output = OUT, ignore = {} })
  storage.refresh()
  for name, count in pairs(stock or {}) do
    mock.give(IN, name, count)
    storage.store()
  end
  storage.refresh()

  local device = fakeMonitor(width or 50, height or 20)
  return storage, device, draw.new(device, function() end)
end

test("el panel muestra el stock y la ocupacion", function()
  local storage, device, screen = setup({
    ["minecraft:cobblestone"] = 300,
    ["minecraft:oak_log"] = 64,
  })
  monitor.draw(screen, storage)
  local text = device.text()

  check(text:find("cc-organizer", 1, true) ~= nil, "titulo")
  check(text:find("2 tipos", 1, true) ~= nil, "cuenta los tipos")
  check(text:find("Cobblestone", 1, true) ~= nil, "lista los items")
  check(text:find("300", 1, true) ~= nil, "con la cantidad")
  check(text:find("6/54 slots", 1, true) ~= nil, "ocupacion")
  check(text:find("2 cofres", 1, true) ~= nil, "cofres en el pie")
end)

test("usa mas de una columna si el monitor es ancho", function()
  local stock = {}
  for i = 1, 30 do stock["minecraft:item_" .. string.format("%02d", i)] = i * 10 end
  local storage, device, screen = setup(stock, 50, 12)
  monitor.draw(screen, storage)

  local lines = {}
  for line in device.text():gmatch("[^\n]+") do lines[#lines + 1] = line end
  -- Con 50 de ancho entran 2 columnas de 22: tiene que haber items pasada la 24.
  local wide = false
  for _, line in ipairs(lines) do
    if #line:gsub("%s+$", "") > 24 and line:find("Item", 1, true) then wide = true end
  end
  check(wide, "hay una segunda columna de items")
end)

test("avisa cuando no hay nada guardado", function()
  local storage, device, screen = setup({})
  monitor.draw(screen, storage)
  check(device.text():find("esta vacio", 1, true) ~= nil, "lo dice")
end)

test("se adapta a un monitor chico sin romperse", function()
  local storage, device, screen = setup({ ["minecraft:cobblestone"] = 300 }, 18, 5)
  monitor.draw(screen, storage)
  local text = device.text()
  check(text:find("cc%-organizer") ~= nil, "entra el titulo recortado")
  for line in text:gmatch("[^\n]+") do
    check(#line <= 18, "ninguna linea se pasa del ancho: " .. #line)
  end
end)
