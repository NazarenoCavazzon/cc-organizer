-- Panel de solo lectura en un monitor: stock, actividad y ocupacion, en vivo.
--
-- No toca el estado: solo lee el indice y dibuja. Si no hay monitor conectado
-- se queda esperando a que aparezca uno.
--
-- El panel esta pensado como tablero, no como volcado de datos: titulo en letra
-- grande, secciones separadas por reglas finas de subpixel, y las cosas que se
-- miran de lejos (ocupacion, ultimo movimiento) con jerarquia propia.

local draw = require("lib.draw")
local pixels = require("lib.pixels")
local bigtext = require("lib.bigtext")
local items = require("lib.items")
local icons = require("lib.icons")

local monitor = {}

local TITLE = "CC-ORGANIZER"
local ACTIVITY_WIDTH = 24  -- 5 de cantidad + espacio + nombre
local LOW_SPACE = 0.1      -- por debajo de esto, el panel avisa

-- Que esta pasando con el monitor, para mostrarlo en el diagnostico (F3).
monitor.status = { state = "sin arrancar" }

--- 12345 -> "12k", para que las cantidades no rompan la grilla.
local function short(n)
  if n < 1000 then return tostring(n) end
  if n < 1000000 then
    local k = n / 1000
    return (k < 10 and ("%.1fk"):format(k) or ("%dk"):format(math.floor(k)))
  end
  return ("%.1fM"):format(n / 1000000)
end

--- Barra de ocupacion. Sin color el vacio va en negro: si fuera gris, en un
--- monitor comun el lleno y el vacio se dibujarian los dos blancos.
local function bar(screen, x, y, width, used, total)
  local ratio = total > 0 and used / total or 0
  local filled = math.floor(width * ratio + 0.5)
  local low = total > 0 and (total - used) / total < LOW_SPACE
  local fullBg = low and colours.red or colours.lime
  local emptyBg = screen.colour and colours.grey or colours.black

  screen:paint(colours.white, screen.colour and fullBg or colours.white)
  screen:at(x, y, string.rep(" ", math.min(filled, width)))
  if filled < width then
    screen:paint(colours.white, emptyBg)
    screen:at(x + filled, y, string.rep(" ", width - filled))
  end
  return low
end

--- Totales por categoria, de mayor a menor.
local function categories(stock)
  local totals, order = {}, {}
  for _, entry in ipairs(stock) do
    local name = icons.category(entry.key)
    if not totals[name] then
      totals[name] = 0
      order[#order + 1] = name
    end
    totals[name] = totals[name] + entry.total
  end
  table.sort(order, function(a, b) return totals[a] > totals[b] end)
  local out = {}
  for i, name in ipairs(order) do out[i] = { name = name, total = totals[name] } end
  return out
end

--- Panel completo, para monitores con lugar de sobra.
local function drawFull(screen, storage, page, W, H)
  local stock = storage.stock()
  local space = storage.space()
  local rule = screen.colour and colours.grey or colours.white

  -- Titulo grande y, al lado, el resumen de la red.
  bigtext.draw(screen, 2, 1, TITLE, colours.white, colours.black)
  screen:paint(colours.lightGrey, colours.black)
  screen:right(W - 1, 1, ("%d tipos"):format(#stock))
  screen:right(W - 1, 2, ("%d cofres"):format(space.chests))
  pixels.ruleH(screen, 1, 3, W, rule, colours.black)

  -- Cuerpo: stock a la izquierda, actividad a la derecha.
  local top, bottom = 4, H - 3
  local rows = math.max(1, bottom - top)
  local activityX = W - ACTIVITY_WIDTH + 1
  local hasActivity = activityX > 26
  local stockWidth = (hasActivity and activityX - 3 or W - 2)

  if hasActivity then
    pixels.ruleV(screen, activityX - 2, top, rows + 1, rule, colours.black)
    screen:paint(colours.lightGrey, colours.black)
    screen:at(activityX, top, draw.fit("ACTIVIDAD", ACTIVITY_WIDTH - 1))
    local log = storage.activity(rows - 1)
    for i, move in ipairs(log) do
      screen:paint(move.sign == "+" and colours.lime or colours.orange, colours.black)
      screen:at(activityX, top + i, move.sign .. short(move.count))
      screen:paint(colours.white, colours.black)
      screen:at(activityX + 6, top + i, draw.fit(items.displayName(move.key), ACTIVITY_WIDTH - 7))
    end
    if #log == 0 then
      screen:paint(colours.grey, colours.black)
      screen:at(activityX, top + 1, "sin movimientos")
    end
  end

  -- Stock paginado: con muchos items el panel va rotando solo.
  local pages = math.max(1, math.ceil(#stock / (rows - 1)))
  page = ((page or 1) - 1) % pages + 1
  local first = (page - 1) * (rows - 1)

  screen:paint(colours.lightGrey, colours.black)
  screen:at(2, top, "STOCK")
  for i = 1, rows - 1 do
    local entry = stock[first + i]
    if entry then
      screen:paint(colours.yellow, colours.black)
      screen:right(7, top + i, short(entry.total))
      screen:paint(colours.white, colours.black)
      screen:at(9, top + i, draw.fit(entry.display, stockWidth - 8))
    end
  end
  if #stock == 0 then
    screen:paint(colours.grey, colours.black)
    screen:at(2, top + 1, "el almacenamiento esta vacio")
  end

  -- Pie: categorias y ocupacion.
  pixels.ruleH(screen, 1, H - 2, W, rule, colours.black)
  local parts = {}
  for _, category in ipairs(categories(stock)) do
    parts[#parts + 1] = ("%s %s"):format(category.name, short(category.total))
  end
  screen:paint(colours.lightGrey, colours.black)
  screen:at(2, H - 1, draw.fit(table.concat(parts, "  "), W - 2))

  local percent = math.floor(space.slots > 0 and space.used / space.slots * 100 or 0)
  local label = ("%d%%  %d/%d"):format(percent, space.used, space.slots)
  if pages > 1 then label = label .. ("  %d/%d"):format(page, pages) end
  -- El aviso se suma al label en vez de reemplazarlo: cuando el sistema se esta
  -- llenando es justo cuando queres ver la ocupacion y la pagina.
  local low = (space.slots > 0 and (space.free / space.slots) < LOW_SPACE)
  if low then label = "ESPACIO BAJO  " .. label end
  local barWidth = math.max(4, W - #label - 4)
  bar(screen, 2, H, barWidth, space.used, space.slots)
  screen:paint(low and colours.red or colours.lightGrey, colours.black)
  screen:right(W - 1, H, label)
  return pages
end

--- Version compacta para monitores chicos: sin titulo grande ni columnas.
local function drawCompact(screen, storage, page, W, H)
  local stock = storage.stock()
  local space = storage.space()

  screen:paint(colours.black, colours.cyan)
  screen:at(1, 1, draw.fit(" cc-organizer", W))

  local rows = math.max(1, H - 3)
  local pages = math.max(1, math.ceil(#stock / rows))
  page = ((page or 1) - 1) % pages + 1
  local first = (page - 1) * rows

  for i = 1, rows do
    local entry = stock[first + i]
    if entry then
      screen:paint(colours.yellow, colours.black)
      screen:right(6, 1 + i, short(entry.total))
      screen:paint(colours.white, colours.black)
      screen:at(8, 1 + i, draw.fit(entry.display, W - 8))
    end
  end
  if #stock == 0 then
    screen:paint(colours.grey, colours.black)
    screen:at(2, 2, "vacio")
  end

  local label = ("%d/%d"):format(space.used, space.slots)
  local barWidth = math.max(3, W - #label - 3)
  bar(screen, 2, H - 1, barWidth, space.used, space.slots)
  screen:paint(colours.lightGrey, colours.black)
  screen:right(W - 1, H - 1, label)
  screen:paint(colours.black, screen.colour and colours.grey or colours.white)
  screen:at(1, H, draw.fit((" %d cofres  %d libres"):format(space.chests, space.free), W))
  return pages
end

--- Dibuja el panel. `page` es la pagina del stock; devuelve cuantas hay.
function monitor.draw(screen, storage, page)
  local W, H = screen:size()
  screen:clear()
  local titleWidth = bigtext.size(TITLE)
  local pages
  if H >= 11 and W >= titleWidth + 12 then
    pages = drawFull(screen, storage, page, W, H)
  else
    pages = drawCompact(screen, storage, page, W, H)
  end
  screen:cursor(1, 1, false)
  screen:present()
  return pages
end
--- Prepara el canvas sobre el monitor. nil + motivo si no se puede.
function monitor.attach()
  local device = peripheral.find("monitor")
  if not device then
    monitor.status = { state = "no encuentro ningun monitor" }
    return nil
  end
  local name = peripheral.getName and peripheral.getName(device) or "monitor"
  local ok, result = pcall(function()
    device.setTextScale(0.5)
    local w, h = device.getSize()
    local win = window.create(device, 1, 1, w, h, false)
    return draw.new(win, function()
      win.setVisible(true)
      win.setVisible(false)
    end, device.isColour and device.isColour() or false)
  end)
  if not ok then
    monitor.status = { state = "error al preparar", name = name, error = tostring(result) }
    return nil, tostring(result)
  end
  local w, h = device.getSize()
  monitor.status = {
    state = "conectado", name = name, width = w, height = h,
    colour = device.isColour and device.isColour() or false,
  }
  return result
end

--- Bucle: dibuja al arrancar, cuando algo cambia y cada 5 segundos.
--- Si no hay monitor espera a que conecten uno. `notify` recibe los problemas:
--- antes esto se tragaba cualquier error y reintentaba callado para siempre.
function monitor.run(storage, notify)
  local screen, warned
  local page, pages = 1, 1
  while true do
    if not screen then
      local canvas, err = monitor.attach()
      screen = canvas
      if err and err ~= warned then
        warned = err
        if notify then notify("monitor: " .. err) end
      end
    end

    if screen then
      local ok, err = pcall(monitor.draw, screen, storage, page)
      if ok then
        pages = err or 1
        page = page % math.max(1, pages) + 1
        monitor.status.state = "dibujando"
        monitor.status.pages = pages
        monitor.status.frames = (monitor.status.frames or 0) + 1
      else
        screen = nil
        monitor.status = { state = "error al dibujar", error = tostring(err) }
        if notify then notify("monitor: " .. tostring(err)) end
      end
    end

    -- La espera queda fuera de todo pcall: un error aca tiene que romper,
    -- no convertirse en un reintento infinito y silencioso.
    local timer = os.startTimer(screen and 5 or 2)
    local waiting = true
    while waiting do
      local event, id = os.pullEvent()
      if event == "peripheral" or event == "peripheral_detach" or event == "monitor_resize" then
        screen, warned = nil, nil
        waiting = false
      elseif event == "organizer_update" or (event == "timer" and id == timer) then
        waiting = false
      end
    end
  end
end

return monitor
