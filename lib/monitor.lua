-- Panel de solo lectura en un monitor: stock y ocupacion, en vivo.
--
-- No toca el estado: solo lee el indice y dibuja. Si no hay monitor conectado
-- se queda esperando a que aparezca uno.

local draw = require("lib.draw")

local monitor = {}

local COLUMN = 22  -- 7 de cantidad + espacio + 14 de nombre

--- Barra de ocupacion: mas legible de lejos que "151/162".
local function bar(screen, x, y, width, used, total)
  local filled = total > 0 and math.floor(width * used / total + 0.5) or 0
  screen:paint(colours.white, colours.lime)
  screen:at(x, y, string.rep(" ", math.min(filled, width)))
  if filled < width then
    screen:paint(colours.white, colours.grey)
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

--- Bucle: dibuja al arrancar, cuando algo cambia y cada tantos segundos.
--- Si no hay monitor espera a que conecten uno.
function monitor.run(storage)
  while true do
    local device = peripheral.find("monitor")
    if not device then
      -- Sin monitor no hay nada que hacer, pero la corrutina no puede terminar:
      -- parallel.waitForAny cortaria el programa entero.
      repeat
        local event = os.pullEvent()
      until event == "peripheral"
    else
      local ok = pcall(function()
        device.setTextScale(0.5)
        local w, h = device.getSize()
        local win = window.create(device, 1, 1, w, h, false)
        local screen = draw.new(win, function()
          win.setVisible(true)
          win.setVisible(false)
        end)
        local alive = true
        while alive do
          monitor.draw(screen, storage)
          -- Solo redibujar cuando cambia algo o cada 5s: si respondiera a
          -- cualquier evento, cada tecla que toca el jugador repintaria el
          -- monitor entero.
          local timer = os.startTimer(5)
          local waiting = true
          while waiting do
            local event, id = os.pullEvent()
            if event == "peripheral_detach" or event == "monitor_resize" then
              alive, waiting = false, false
            elseif event == "organizer_update" or (event == "timer" and id == timer) then
              waiting = false
            end
          end
        end
      end)
      if not ok then os.sleep(2) end
    end
  end
end

return monitor
