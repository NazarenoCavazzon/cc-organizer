-- Panel de solo lectura en un monitor: stock y ocupacion, en vivo.
--
-- No toca el estado: solo lee el indice y dibuja. Si no hay monitor conectado
-- se queda esperando a que aparezca uno.

local draw = require("lib.draw")

local monitor = {}

local COLUMN = 22  -- 7 de cantidad + espacio + 14 de nombre

-- Que esta pasando con el monitor, para mostrarlo en el diagnostico (F3).
monitor.status = { state = "sin arrancar" }

--- Barra de ocupacion: mas legible de lejos que "151/162".
local function bar(screen, x, y, width, used, total)
  local filled = total > 0 and math.floor(width * used / total + 0.5) or 0
  -- Sin color, cualquier fondo que no sea negro se dibuja blanco: si el vacio
  -- tambien fuera gris, la barra seria un rectangulo blanco sin informacion.
  local emptyBg = screen.colour and colours.grey or colours.black
  screen:paint(colours.white, colours.lime)
  screen:at(x, y, string.rep(" ", math.min(filled, width)))
  if filled < width then
    screen:paint(colours.white, emptyBg)
    screen:at(x + filled, y, string.rep(" ", width - filled))
  end
end

--- Dibuja el panel entero. Se le pasa el canvas para poder testearlo.
function monitor.draw(screen, storage)
  local W, H = screen:size()
  local stock = storage.stock()
  local space = storage.space()

  screen:clear()

  local title, types = " cc-organizer", ("%d tipos"):format(#stock)
  screen:paint(colours.black, colours.cyan)
  screen:at(1, 1, draw.fit(title, W))
  -- En un monitor angosto el titulo gana: el contador se dibuja solo si entra.
  if W >= #title + #types + 2 then
    screen:right(W - 1, 1, types)
  end

  -- Ocupacion: barra a la izquierda, numeros a la derecha.
  local label = ("%d/%d slots"):format(space.used, space.slots)
  local barWidth = math.max(4, W - #label - 3)
  bar(screen, 2, 2, barWidth, space.used, space.slots)
  screen:paint(colours.lightGrey, colours.black)
  screen:right(W - 1, 2, label)

  -- Items en tantas columnas como entren.
  local top, bottom = 4, H - 1
  local visibleRows = math.max(1, bottom - top + 1)
  local columns = math.max(1, math.floor((W - 1) / COLUMN))
  for i = 1, math.min(#stock, visibleRows * columns) do
    local entry = stock[i]
    local column = math.floor((i - 1) / visibleRows)
    local x = 2 + column * COLUMN
    local y = top + (i - 1) % visibleRows
    screen:paint(colours.yellow, colours.black)
    screen:right(x + 6, y, tostring(entry.total))
    screen:paint(colours.white, colours.black)
    screen:at(x + 8, y, draw.fit(entry.display, COLUMN - 9))
  end

  if #stock == 0 then
    screen:paint(colours.grey, colours.black)
    screen:at(2, top, "el almacenamiento esta vacio")
  end

  screen:paint(colours.black, colours.grey)
  screen:at(1, H, draw.fit((" %d cofres   %d slots libres"):format(space.chests, space.free), W))
  screen:cursor(1, 1, false)
  screen:present()
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
      local ok, err = pcall(monitor.draw, screen, storage)
      if ok then
        monitor.status.state = "dibujando"
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
