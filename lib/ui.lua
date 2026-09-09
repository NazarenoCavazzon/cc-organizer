-- TUI de pantalla completa: lista de stock con busqueda en vivo, seleccion
-- con teclado o mouse y pedidos al cofre de salida.
--
-- Layout (terminal de 51x19 en una Advanced Computer):
--   1        barra de titulo con la ocupacion
--   2        linea de busqueda
--   3..H-2   lista de items + barra de scroll
--   H-1      ultimo mensaje
--   H        atajos

local items = require("lib.items")

local ui = {}

local storage, cfg
local W, H
local colour = false
local query = ""
local rows = {}
local sel, top = 1, 1
local sortByName = false
local message, messageColour
local dirty, running = true, true

-- Los mensajes del guardado automatico llegan desde otra corrutina.
local pending = {}

local function paint(fg, bg)
  if colour then
    term.setTextColour(fg)
    term.setBackgroundColour(bg)
  else
    -- Las computadoras normales solo tienen blanco y negro.
    local inverted = bg ~= colours.black
    term.setTextColour(inverted and colours.black or colours.white)
    term.setBackgroundColour(inverted and colours.white or colours.black)
  end
end

local function fit(s, w)
  if #s > w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

local function listHeight()
  return math.max(1, H - 4)
end

--- Cantidad compacta para que entre en la columna: 12345 -> "12.3k"
local function shortCount(n)
  if n < 100000 then return tostring(n) end
  if n < 10000000 then return ("%.1fk"):format(n / 1000) end
  return ("%dk"):format(n // 1000)
end

local function setMessage(text, c)
  message, messageColour = text, c or colours.lightGrey
  dirty = true
end

--- Aviso desde fuera del bucle de eventos (guardado automatico, red).
function ui.notify(msg)
  pending[#pending + 1] = msg
  os.queueEvent("organizer_update")
end

local function recompute(keepSelection)
  local previous = keepSelection and rows[sel] and rows[sel].key
  rows = storage.stock(query ~= "" and query or nil)
  if sortByName then
    table.sort(rows, function(a, b) return a.display:lower() < b.display:lower() end)
  end
  sel = 1
  if previous then
    for i, r in ipairs(rows) do
      if r.key == previous then sel = i break end
    end
  end
  local h = listHeight()
  top = math.max(1, math.min(top, math.max(1, #rows - h + 1)))
  if sel < top then top = sel end
  if sel > top + h - 1 then top = sel - h + 1 end
  dirty = true
end

local function drawHeader()
  local s = storage.space()
  local right = ("%d/%d slots  %d cofres"):format(s.used, s.slots, s.chests)
  paint(colours.black, colour and colours.cyan or colours.white)
  term.setCursorPos(1, 1)
  term.write(fit(" cc-organizer", W - #right - 1) .. right .. " ")
end

local function drawSearch()
  paint(colours.white, colours.black)
  term.setCursorPos(1, 2)
  term.clearLine()
  paint(colours.lightGrey, colours.black)
  term.write("buscar: ")
  paint(colours.white, colours.black)
  term.write(query)
  local tag = sortByName and "A-Z" or "cant"
  local count = ("%d %s  %s"):format(#rows, #rows == 1 and "item" or "items", tag)
  paint(colours.grey, colours.black)
  term.setCursorPos(math.max(1, W - #count), 2)
  term.write(count)
end

local function drawList()
  local h = listHeight()
  for i = 0, h - 1 do
    local y = 3 + i
    local entry = rows[top + i]
    local selected = (top + i) == sel
    paint(selected and colours.black or colours.white,
          selected and (colour and colours.lightGrey or colours.white) or colours.black)
    term.setCursorPos(1, y)
    if entry then
      local count = shortCount(entry.total)
      local line = ("%7s  %s"):format(count, entry.display)
      term.write(fit(line, W - 1))
    else
      term.write(string.rep(" ", W - 1))
    end
    -- Barra de scroll en la ultima columna.
    paint(colours.grey, colours.black)
    local bar = " "
    if #rows > h then
      local from = math.floor((top - 1) / #rows * h)
      local size = math.max(1, math.floor(h / #rows * h))
      if i >= from and i < from + size then bar = colour and "\149" or "|" end
    end
    term.write(bar)
  end
end

local function drawMessage()
  paint(messageColour or colours.lightGrey, colours.black)
  term.setCursorPos(1, H - 1)
  term.clearLine()
  if message then term.write(fit(message, W)) end
end

local function drawHelp()
  paint(colours.black, colour and colours.grey or colours.white)
  term.setCursorPos(1, H)
  term.write(fit(" enter pedir  F1 ayuda  F3 diag  F5 scan  F10 salir", W))
end

local function draw()
  drawHeader()
  drawSearch()
  drawList()
  drawMessage()
  drawHelp()
  -- El cursor vive en la busqueda: se siente como un campo de texto.
  paint(colours.white, colours.black)
  term.setCursorPos(math.min(9 + #query, W), 2)
  term.setCursorBlink(true)
  dirty = false
end

--- Ventana modal simple; devuelve cuando el usuario aprieta una tecla.
local function overlay(title, lines)
  local maxLines = math.max(1, H - 5)
  if #lines > maxLines then
    local cut = {}
    for i = 1, maxLines - 1 do cut[i] = lines[i] end
    cut[maxLines] = ("... y %d lineas mas"):format(#lines - maxLines + 1)
    lines = cut
  end
  local w = #title + 4
  for _, l in ipairs(lines) do w = math.max(w, #l + 4) end
  w = math.min(w, W)
  local h = #lines + 4
  local x = math.floor((W - w) / 2) + 1
  local y = math.floor((H - h) / 2) + 1

  paint(colours.black, colour and colours.cyan or colours.white)
  term.setCursorPos(x, y)
  term.write(fit(" " .. title, w))
  for i, l in ipairs(lines) do
    paint(colours.white, colour and colours.grey or colours.black)
    term.setCursorPos(x, y + i)
    term.write(fit(" " .. l, w))
  end
  paint(colours.lightGrey, colour and colours.grey or colours.black)
  term.setCursorPos(x, y + #lines + 1)
  term.write(fit("", w))
  term.setCursorPos(x, y + #lines + 2)
  term.write(fit(" (cualquier tecla para cerrar)", w))
  term.setCursorBlink(false)
  os.pullEvent("key")
  dirty = true
end

--- Por que no entra nada / que ve el programa de la red.
local function showDiagnostics()
  local report = storage.diagnose()
  local lines = {}
  if #report.problems == 0 then
    lines[#lines + 1] = "no veo problemas en el armado"
  else
    for _, p in ipairs(report.problems) do lines[#lines + 1] = "! " .. p end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("entrada: %s"):format(cfg.input)
  lines[#lines + 1] = ("salida:  %s"):format(cfg.output)
  lines[#lines + 1] = ("cofres de almacenamiento: %d"):format(#report.chests)
  for _, c in ipairs(report.chests) do
    lines[#lines + 1] = ("  %-28s %2d/%2d slots"):format(c.name, c.used, c.size)
  end
  overlay("diagnostico", lines)
end

local function showHelp()
  overlay("atajos", {
    "escribir       filtra la lista",
    "flechas        mover la seleccion",
    "reAv / rePag   pagina",
    "enter          pedir (pregunta cantidad)",
    "click derecho  pedir todo el stock",
    "esc            limpiar la busqueda",
    "F2             ordenar por cantidad / nombre",
    "F3             diagnostico del armado",
    "F5             re-escanear la red",
    "F9             reconfigurar entrada/salida",
    "F10            salir",
  })
end

--- Pregunta en la linea de mensajes. Devuelve nil si el usuario cancela.
local function ask(label, default)
  paint(colours.white, colours.black)
  term.setCursorPos(1, H - 1)
  term.clearLine()
  paint(colours.yellow, colours.black)
  term.write(label)
  paint(colours.white, colours.black)
  term.setCursorBlink(true)
  local answer = read(nil, nil, nil, default)
  dirty = true
  if answer == nil or answer == "" then return nil end
  return answer
end

local function request(entry, amount)
  if not entry then return end
  storage.busy = true
  local moved, reason = storage.take(entry.key, amount)
  storage.busy = false

  if moved == 0 then
    setMessage(("no entregue nada: %s"):format(reason or "?"), colours.red)
  elseif moved < amount then
    setMessage(("%d/%d %s (%s)"):format(moved, amount, entry.display, reason or "?"), colours.yellow)
  else
    setMessage(("%d %s -> %s"):format(moved, entry.display, cfg.output), colours.lime)
  end
  recompute(true)
end

local function requestSelected()
  local entry = rows[sel]
  if not entry then return end
  local default = math.min(entry.total, items.maxCount(entry.key))
  local answer = ask(("cuantos %s? "):format(entry.display), tostring(default))
  if not answer then
    setMessage("cancelado")
    return
  end
  local amount = math.floor(tonumber(answer) or 0)
  if amount <= 0 then
    setMessage("cantidad invalida", colours.red)
    return
  end
  request(entry, amount)
end

local function move(delta)
  if #rows == 0 then return end
  sel = math.max(1, math.min(#rows, sel + delta))
  local h = listHeight()
  if sel < top then top = sel end
  if sel > top + h - 1 then top = sel - h + 1 end
  dirty = true
end

local function scroll(delta)
  local h = listHeight()
  top = math.max(1, math.min(math.max(1, #rows - h + 1), top + delta))
  dirty = true
end

local function doRefresh()
  setMessage("escaneando la red...")
  draw()
  storage.busy = true
  local ok, err = pcall(storage.refresh)
  storage.busy = false
  if ok then
    local s = storage.space()
    setMessage(("%d cofres, %d slots ocupados"):format(s.chests, s.used), colours.lime)
  else
    setMessage("fallo el escaneo: " .. tostring(err), colours.red)
  end
  recompute(true)
end

local function onKey(key)
  if key == keys.up then move(-1)
  elseif key == keys.down then move(1)
  elseif key == keys.pageUp then move(-listHeight())
  elseif key == keys.pageDown then move(listHeight())
  elseif key == keys.home then sel, top = 1, 1; dirty = true
  elseif key == keys["end"] then sel = #rows; move(0)
  elseif key == keys.enter or key == keys.numPadEnter then requestSelected()
  elseif key == keys.backspace then
    if #query > 0 then query = query:sub(1, -2); recompute() end
  elseif key == keys.escape then
    if #query > 0 then query = ""; recompute() end
  elseif key == keys.f1 then showHelp()
  elseif key == keys.f2 then sortByName = not sortByName; recompute(true)
  elseif key == keys.f3 then showDiagnostics()
  elseif key == keys.f5 then doRefresh()
  elseif key == keys.f9 then ui.reconfigure = true; running = false
  elseif key == keys.f10 then running = false
  end
end

local function onClick(button, _, y)
  local i = top + (y - 3)
  if y < 3 or y > H - 2 or not rows[i] then return end
  if button == 2 then
    sel = i
    request(rows[i], rows[i].total)
    return
  end
  if sel == i then
    requestSelected()
  else
    sel = i
    dirty = true
  end
end

function ui.run(store, config)
  storage, cfg = store, config
  W, H = term.getSize()
  colour = term.isColour and term.isColour()
  running, ui.reconfigure = true, false
  query, sel, top = "", 1, 1

  term.setBackgroundColour(colours.black)
  term.clear()
  recompute()
  local s = storage.space()
  setMessage(("listo: %d cofres, %d tipos de item"):format(s.chests, #rows))

  while running do
    if #pending > 0 then
      setMessage(table.remove(pending, 1))
      recompute(true)
    end
    if dirty then draw() end
    local event = { os.pullEvent() }
    local name = event[1]
    if name == "char" then
      query = query .. event[2]
      recompute()
    elseif name == "key" then
      onKey(event[2])
    elseif name == "mouse_click" then
      onClick(event[2], event[3], event[4])
    elseif name == "mouse_scroll" then
      scroll(event[2] * 3)
    elseif name == "term_resize" then
      W, H = term.getSize()
      recompute(true)
    elseif name == "organizer_update" then
      dirty = true
    end
  end

  term.setCursorBlink(false)
  paint(colours.white, colours.black)
  term.clear()
  term.setCursorPos(1, 1)
end

return ui
