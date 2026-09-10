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
local function fakeMonitor(width, height, colour)
  local grid, bgGrid = {}, {}
  local cx, cy = 1, 1
  local bg = colours.black
  if colour == nil then colour = true end
  -- Un monitor normal solo acepta blanco, negro y grises: cualquier otro color
  -- tira "Colour not supported", igual que en el juego.
  local function check(c)
    if colour then return end
    if c ~= colours.white and c ~= colours.black
       and c ~= colours.grey and c ~= colours.lightGrey then
      error("Colour not supported", 0)
    end
  end
  local function blank()
    for y = 1, height do
      grid[y], bgGrid[y] = {}, {}
      for x = 1, width do
        grid[y][x] = " "
        bgGrid[y][x] = colours.black
      end
    end
  end
  blank()
  return {
    getSize = function() return width, height end,
    isColour = function() return colour end,
    setTextScale = function() end,
    setCursorPos = function(x, y) cx, cy = math.floor(x), math.floor(y) end,
    setCursorBlink = function() end,
    setTextColour = check,
    setBackgroundColour = function(c) check(c) bg = c end,
    clear = blank,
    write = function(s)
      if cy < 1 or cy > height then return end
      for i = 1, #s do
        local x = cx + i - 1
        if x >= 1 and x <= width then
          grid[cy][x] = s:sub(i, i)
          bgGrid[cy][x] = bg
        end
      end
      cx = cx + #s
    end,
    bgAt = function(x, y) return bgGrid[y] and bgGrid[y][x] end,
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

--- Monitor falso enchufado a la red, como en el juego.
local function attachMonitor(width, height)
  local device = fakeMonitor(width or 50, height or 20)
  device.setBackgroundColor = device.setBackgroundColour
  device.setTextColor = device.setTextColour
  return mock.attach("monitor_0", "monitor", device)
end

test("monitor.run dibuja apenas encuentra el monitor", function()
  local storage = setup({ ["minecraft:cobblestone"] = 300 })
  local device = attachMonitor()

  -- run() es un bucle infinito: se corta solo cuando la cola de eventos se
  -- vacia, o sea despues del primer dibujo.
  local ok, err = pcall(monitor.run, storage)
  check(not ok, "termino por quedarse sin eventos, no por otra cosa: " .. tostring(err))
  check(tostring(err):find("cola de eventos", 1, true) ~= nil, "el motivo es la cola: " .. tostring(err))

  local text = device.text()
  check(text:find("STOCK", 1, true) ~= nil, "dibujo el panel en el monitor")
  check(text:find("Cobblestone", 1, true) ~= nil, "y el stock")
end)

test("monitor.run avisa si el monitor falla en vez de callarselo", function()
  local storage = setup({ ["minecraft:cobblestone"] = 300 })
  local device = attachMonitor()
  device.setTextScale = function() error("Terminal is not attached", 0) end

  local avisos = {}
  pcall(monitor.run, storage, function(msg) avisos[#avisos + 1] = msg end)
  eq(#avisos > 0, true, "aviso del problema")
  check(tostring(avisos[1]):find("Terminal is not attached", 1, true) ~= nil,
    "con el error real: " .. tostring(avisos[1]))
end)

test("dibuja en un monitor normal, sin colores", function()
  local storage = setup({ ["minecraft:cobblestone"] = 300 })
  local device = fakeMonitor(50, 20, false)   -- monitor de piedra
  device.setTextColor, device.setBackgroundColor = device.setTextColour, device.setBackgroundColour
  mock.attach("monitor_0", "monitor", device)

  local avisos = {}
  pcall(monitor.run, storage, function(msg) avisos[#avisos + 1] = msg end)
  eq(#avisos, 0, "sin errores: " .. tostring(avisos[1]))

  local text = device.text()
  check(text:find("STOCK", 1, true) ~= nil, "igual dibuja el panel")
  check(text:find("Cobblestone", 1, true) ~= nil, "y el stock")
end)

test("el diagnostico cuenta que esta pasando con el monitor", function()
  local storage = setup({ ["minecraft:cobblestone"] = 300 })
  eq(monitor.attach(), nil, "sin monitor conectado no hay canvas")
  eq(monitor.status.state, "no encuentro ningun monitor", "y el estado lo dice")

  attachMonitor(50, 20)
  pcall(monitor.run, storage)
  eq(monitor.status.state, "dibujando", "con monitor, dibujando")
  eq(monitor.status.name, "monitor_0", "con el nombre de la red")
  eq(monitor.status.width, 50, "y el tamano")
end)

test("la barra de ocupacion se distingue en un monitor sin color", function()
  -- Con color el vacio va gris; sin color tiene que ir negro, o el lleno y el
  -- vacio se dibujan los dos blancos y la barra no dice nada.
  for _, colour in ipairs({ true, false }) do
    local storage = setup({ ["minecraft:cobblestone"] = 300 })
    local device = fakeMonitor(50, 20, colour)
    device.setTextColor, device.setBackgroundColor = device.setTextColour, device.setBackgroundColour
    monitor.draw(draw.new(device, function() end, colour), storage)

    -- 6 de 54 slots: el principio de la barra esta lleno y el medio vacio.
    -- Comparar dos puntos dentro de la barra, no el resto de la linea.
    -- La barra vive en la ultima fila del panel.
    local lleno, vacio = device.bgAt(3, 20), device.bgAt(20, 20)
    check(lleno ~= vacio, ("con color=%s el lleno (%s) tiene que verse distinto del vacio (%s)")
      :format(tostring(colour), tostring(lleno), tostring(vacio)))
  end
end)

test("el panel muestra el stock, la actividad y la ocupacion", function()
  local storage, device, screen = setup({
    ["minecraft:cobblestone"] = 300,
    ["minecraft:oak_log"] = 64,
  })
  storage.take("minecraft:oak_log", 20)
  monitor.draw(screen, storage)
  local text = device.text()

  check(text:find("STOCK", 1, true) ~= nil, "seccion de stock")
  check(text:find("ACTIVIDAD", 1, true) ~= nil, "seccion de actividad")
  check(text:find("2 tipos", 1, true) ~= nil, "cuenta los tipos")
  check(text:find("2 cofres", 1, true) ~= nil, "y los cofres")
  check(text:find("Cobblestone", 1, true) ~= nil, "lista los items")
  check(text:find("300", 1, true) ~= nil, "con la cantidad")
  check(text:find("-20", 1, true) ~= nil, "registra la entrega en actividad")
  check(text:find("6/54", 1, true) ~= nil, "ocupacion")
  check(text:find("bloques", 1, true) ~= nil, "resumen por categoria")
end)

test("el titulo grande se dibuja con subpixeles", function()
  local storage, device, screen = setup({ ["minecraft:cobblestone"] = 300 })
  monitor.draw(screen, storage)
  -- Las dos primeras filas son el titulo: tienen que ser caracteres de bloque.
  local text = device.text()
  local firstLine = text:match("[^\n]+") or ""
  local blocks = 0
  for i = 1, #firstLine do
    local byte = firstLine:byte(i)
    if byte >= 128 and byte <= 159 then blocks = blocks + 1 end
  end
  check(blocks > 10, "hay pixeles de titulo en la primera fila: " .. blocks)
end)

test("rota paginas cuando no entra todo el stock", function()
  local stock = {}
  for i = 1, 40 do stock["minecraft:item_" .. string.format("%02d", i)] = i * 10 end
  local storage, device, screen = setup(stock, 50, 20)

  local pages = monitor.draw(screen, storage, 1)
  check(pages > 1, "hay mas de una pagina: " .. pages)
  local first = device.text()
  check(first:find("1/" .. pages, 1, true) ~= nil, "muestra el indicador de pagina")

  monitor.draw(screen, storage, 2)
  local second = device.text()
  check(first ~= second, "la segunda pagina muestra otra cosa")
  check(second:find("2/" .. pages, 1, true) ~= nil, "y lo indica")
end)

test("avisa cuando queda poco espacio", function()
  -- Un solo cofre de 1 slot: se llena con el primer stack.
  mock.reset({
    { name = IN, size = 27 }, { name = OUT, size = 27 },
    { name = "minecraft:chest_0", size = 1 },
  })
  mterm.reset()
  for _, mod in ipairs({ "lib.storage", "lib.items" }) do package.loaded[mod] = nil end
  require("lib.items").reset()
  local storage = require("lib.storage")
  storage.init({ input = IN, output = OUT, ignore = {} })
  storage.refresh()
  mock.give(IN, "minecraft:cobblestone", 64)
  storage.store()

  local device = fakeMonitor(50, 20)
  monitor.draw(draw.new(device, function() end, true), storage)
  check(device.text():find("ESPACIO BAJO", 1, true) ~= nil, "lo dice en el pie")
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
  check(text:find("cc%-organizer") ~= nil, "el monitor chico usa el titulo simple")
  for line in text:gmatch("[^\n]+") do
    check(#line <= 18, "ninguna linea se pasa del ancho: " .. #line)
  end
end)
