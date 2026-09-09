-- Pantalla principal: lista de stock con busqueda en vivo, orden alfabetico o
-- por cantidad, detalle del item y pedidos con cantidad libre.
--
-- Se dibuja sobre un buffer de window y se presenta de una sola vez, asi que no
-- parpadea aunque se redibuje entera en cada evento.
--
-- Layout (51x19 en una Advanced Computer):
--   1        titulo con tipos y ocupacion
--   2        busqueda + orden actual (clickeable)
--   3..H-2   lista + barra de scroll
--   H-1      ultimo mensaje
--   H        atajos

local items = require("lib.items")
local draw = require("lib.draw")
local dialog = require("lib.dialog")

local ui = {}

local storage, cfg
local win, W, H
local colour = false
local query = ""
local rows = {}
local sel, top = 1, 1
local sortByName = false
local message, messageColour
local ctrlDown = false
local dirty, running = true, true
local sortButton = { x1 = 0, x2 = -1 }

-- Los avisos del guardado automatico llegan desde otra corrutina.
local pending = {}

local function listHeight()
  return math.max(1, H - 4)
end

--- Cantidad compacta para que entre en la columna.
local function shortCount(n)
  if n < 100000 then return tostring(n) end
  return ("%dk"):format(math.floor(n / 1000))
end

local function setMessage(text, c)
  message, messageColour = text, c or colours.lightGrey
  dirty = true
end

function ui.notify(msg)
  pending[#pending + 1] = msg
  os.queueEvent("organizer_update")
end

local function clampView()
  local h = listHeight()
  sel = math.max(1, math.min(math.max(1, #rows), sel))
  if sel < top then top = sel end
  if sel > top + h - 1 then top = sel - h + 1 end
  top = math.max(1, math.min(top, math.max(1, #rows - h + 1)))
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
  clampView()
  dirty = true
end

local function drawHeader()
  local s = storage.space()
  local total = #storage.stock()
  local tipos = query ~= "" and ("%d/%d tipos"):format(#rows, total) or ("%d tipos"):format(total)
  local right = ("%s   %d/%d slots"):format(tipos, s.used, s.slots)
  draw.paint(colours.black, colours.cyan)
  draw.at(1, 1, draw.fit(" cc-organizer", W))
  draw.right(W - 1, 1, right)
end

local function drawSearch()
  draw.paint(colours.white, colours.black)
  draw.at(1, 2, string.rep(" ", W))
  draw.paint(colours.lightGrey, colours.black)
  draw.at(1, 2, "buscar: ")
  draw.paint(colours.white, colours.black)
  draw.at(9, 2, query .. "_")

  local label = sortByName and "[A-Z]" or "[cant]"
  sortButton.x1, sortButton.x2 = W - #label, W - 1
  draw.paint(colours.black, colour and colours.lightGrey or colours.white)
  draw.at(sortButton.x1, 2, label)
end

local function drawList()
  local h = listHeight()
  local thumbFrom, thumbSize
  if #rows > h then
    thumbSize = math.max(1, math.floor(h * h / #rows))
    thumbFrom = math.floor((top - 1) * (h - thumbSize) / math.max(1, #rows - h) + 0.5)
  end

  for i = 0, h - 1 do
    local y = 3 + i
    local entry = rows[top + i]
    local selected = (top + i) == sel
    local bg = selected and (colour and colours.cyan or colours.white) or colours.black
    local fg = selected and colours.black or colours.white

    draw.paint(fg, bg)
    draw.at(1, y, string.rep(" ", W - 1))
    if entry then
      draw.paint(selected and colours.black or colours.yellow, bg)
      draw.right(7, y, shortCount(entry.total))
      draw.paint(fg, bg)
      draw.at(9, y, draw.fit(entry.display, W - 10))
    end

    -- Barra de scroll.
    local track = colour and colours.grey or colours.black
    local thumb = colour and colours.lightGrey or colours.white
    local isThumb = thumbFrom and i >= thumbFrom and i < thumbFrom + thumbSize
    draw.paint(colours.white, thumbFrom and (isThumb and thumb or track) or colours.black)
    draw.at(W, y, " ")
  end

  if #rows == 0 then
    local text = query ~= "" and ("sin resultados para '" .. query .. "'") or "el almacenamiento esta vacio"
    draw.paint(colours.grey, colours.black)
    draw.at(math.max(1, math.floor((W - #text) / 2)), 3 + math.floor(h / 2), text)
  end
end

local function drawFooter()
  draw.paint(messageColour or colours.lightGrey, colours.black)
  draw.at(1, H - 1, draw.fit(message or "", W))
  draw.paint(colours.black, colour and colours.grey or colours.white)
  draw.at(1, H, draw.fit(" enter pedir   tab detalle   F1 ayuda   F10 salir", W))
end

local function render()
  drawHeader()
  drawSearch()
  drawList()
  drawFooter()
  draw.cursor(1, 1, false)
  draw.present()
  dirty = false
end

local function showHelp()
  dialog.message("atajos", {
    "escribir        filtra la lista",
    "flechas         mover la seleccion",
    "rePag / avPag   pagina entera",
    "enter           pedir (cantidad libre)",
    "tab             detalle: donde esta guardado",
    "click           elegir; de nuevo, pedir",
    "click derecho   pedir todo el stock",
    "esc / ctrl+u    limpiar la busqueda",
    "F2              orden: cantidad / A-Z",
    "F3              diagnostico del armado",
    "F5              re-escanear la red",
    "F9              reconfigurar entrada/salida",
    "F10 / ctrl+d    salir",
  })
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
    lines[#lines + 1] = ("  %-24s %2d/%2d slots %s")
      :format(c.chest or c.name, c.used, c.size, c.reachable and "" or "OTRA RED")
  end
  dialog.message("diagnostico", lines)
  dirty = true
end

local function showDetail()
  local entry = rows[sel]
  if not entry then return end
  local lines = {
    entry.key,
    ("%d unidades, apila de a %d"):format(entry.total, items.maxCount(entry.key)),
    "",
  }
  local locations = storage.locations(entry.key)
  lines[#lines + 1] = ("guardado en %d %s:"):format(#locations, #locations == 1 and "cofre" or "cofres")
  for _, loc in ipairs(locations) do
    lines[#lines + 1] = ("  %-24s %5d en %d %s")
      :format(loc.chest, loc.count, loc.slots, loc.slots == 1 and "slot" or "slots")
  end
  dialog.message(entry.display, lines)
  dirty = true
end

local function deliver(entry, amount)
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
  local amount = dialog.number({
    title = entry.display,
    info = {
      ("hay %d en stock"):format(entry.total),
      "podes escribir cuentas: 64*3+16",
    },
    default = math.min(entry.total, items.maxCount(entry.key)),
    max = entry.total,
  })
  dirty = true
  if not amount then
    setMessage("cancelado")
    return
  end
  deliver(entry, amount)
end

local function move(delta)
  if #rows == 0 then return end
  sel = sel + delta
  clampView()
  dirty = true
end

local function scroll(delta)
  local h = listHeight()
  top = math.max(1, math.min(math.max(1, #rows - h + 1), top + delta))
  dirty = true
end

local function doRefresh()
  setMessage("escaneando la red...")
  render()
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
  if key == keys.leftCtrl or key == keys.rightCtrl then ctrlDown = true return end

  if ctrlDown and key == keys.u then
    query = ""
    recompute()
  elseif ctrlDown and key == keys.d then
    running = false
  elseif key == keys.up then move(-1)
  elseif key == keys.down then move(1)
  elseif key == keys.pageUp then move(-listHeight())
  elseif key == keys.pageDown then move(listHeight())
  elseif key == keys.home then sel = 1; clampView(); dirty = true
  elseif key == keys["end"] then sel = #rows; clampView(); dirty = true
  elseif key == keys.enter or key == keys.numPadEnter then requestSelected()
  elseif key == keys.tab then showDetail()
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

local function onClick(button, x, y)
  if y == 2 and x >= sortButton.x1 and x <= sortButton.x2 then
    sortByName = not sortByName
    recompute(true)
    return
  end
  local i = top + (y - 3)
  if y < 3 or y > H - 2 or not rows[i] then return end
  if button == 2 then
    sel = i
    deliver(rows[i], rows[i].total)
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
  win = window.create(term.current(), 1, 1, W, H, false)
  draw.attach(win, colour, function()
    win.setVisible(true)
    win.setVisible(false)
  end)

  running, ui.reconfigure = true, false
  query, sel, top, ctrlDown = "", 1, 1, false
  term.setBackgroundColour(colours.black)
  term.clear()
  draw.clear()

  recompute()
  local s = storage.space()
  setMessage(("listo: %d cofres, %d tipos de item"):format(s.chests, #rows))

  while running do
    if #pending > 0 then
      setMessage(table.remove(pending, 1))
      recompute(true)
    end
    if dirty then render() end

    local event = { os.pullEvent() }
    local name = event[1]
    if name == "char" then
      query = query .. event[2]
      recompute()
    elseif name == "key" then
      onKey(event[2])
    elseif name == "key_up" then
      if event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then ctrlDown = false end
    elseif name == "mouse_click" then
      onClick(event[2], event[3], event[4])
    elseif name == "mouse_scroll" then
      scroll(event[2] * 3)
    elseif name == "term_resize" then
      W, H = term.getSize()
      win.reposition(1, 1, W, H)
      recompute(true)
    elseif name == "organizer_update" then
      dirty = true
    end
  end

  term.setBackgroundColour(colours.black)
  term.setTextColour(colours.white)
  term.clear()
  term.setCursorPos(1, 1)
end

return ui
