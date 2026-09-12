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
local icons = require("lib.icons")
local monitor = require("lib.monitor")

local ui = {}

local storage, cfg
local win, screen, W, H
local colour = false
local query = ""
local rows = {}
local sel, top = 1, 1
local sortByName = false
local category = 1
local recent = {}
local lastOrder = nil
local message, messageColour
local ctrlDown = false
local dirty, running = true, true
local sortButton = { x1 = 0, x2 = -1 }
local catButton = { x1 = 0, x2 = -1 }

local requestFor  -- se define abajo, la usa repeatLast

-- Los avisos del guardado automatico llegan desde otra corrutina.
local pending = {}

-- "todo" y "recientes" son especiales; el resto sale de lib/icons.
local CATEGORIES = { "todo", "recientes" }
for _, name in ipairs(icons.CATEGORIES) do CATEGORIES[#CATEGORIES + 1] = name end

local RECENT_FILE = "recent.txt"
local RECENT_MAX = 20

--- Los recientes sobreviven al reboot: es lo que mas se pide.
local function loadRecent()
  recent = {}
  if not fs or not fs.exists(RECENT_FILE) then return end
  local file = fs.open(RECENT_FILE, "r")
  if not file then return end
  local line = file.readLine()
  while line do
    if line ~= "" then recent[#recent + 1] = line end
    line = file.readLine()
  end
  file.close()
end

local function saveRecent()
  if not fs then return end
  local file = fs.open(RECENT_FILE, "w")
  if not file then return end
  for _, key in ipairs(recent) do file.writeLine(key) end
  file.close()
end

local function remember(key)
  for i, previous in ipairs(recent) do
    if previous == key then table.remove(recent, i) break end
  end
  table.insert(recent, 1, key)
  while #recent > RECENT_MAX do table.remove(recent) end
  saveRecent()
end

local function recentRank()
  local rank = {}
  for i, key in ipairs(recent) do rank[key] = i end
  return rank
end

local function listHeight()
  return math.max(1, H - 4)
end

--- Cantidad compacta para que entre en la columna.
local function shortCount(n)
  if n < 100000 then return tostring(n) end
  return ("%dk"):format(math.floor(n / 1000))
end

--- Badge de la derecha de cada fila: "87%" de durabilidad y "*" si esta
--- encantado. Es lo unico que distingue dos picos de diamante con el mismo
--- nombre, porque el juego no los renombra.
local function wearBadge(key)
  local wear = items.wear(key)
  local enchanted = items.isEnchanted(key)
  if not wear and not enchanted then return nil end

  local text = enchanted and "*" or ""
  local c = colours.lightBlue
  if wear then
    if wear.unbreakable then
      text = text .. "irr"
      c = colours.lightBlue
    else
      text = text .. ("%d%%"):format(wear.percent)
      c = wear.percent >= 50 and colours.lime
          or wear.percent >= 25 and colours.yellow or colours.red
    end
  end
  return text, c
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

  local cat = CATEGORIES[category]
  local rank = recentRank()
  if cat ~= "todo" then
    local kept = {}
    for _, entry in ipairs(rows) do
      local ok = cat == "recientes" and rank[entry.key] ~= nil or icons.category(entry.key) == cat
      if ok then kept[#kept + 1] = entry end
    end
    rows = kept
  end

  if cat == "recientes" then
    table.sort(rows, function(a, b) return rank[a.key] < rank[b.key] end)
  elseif sortByName then
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
  screen:paint(colours.black, colours.cyan)
  screen:at(1, 1, draw.fit(" cc-organizer", W))
  screen:right(W - 1, 1, right)
end

local function drawSearch()
  screen:paint(colours.white, colours.black)
  screen:at(1, 2, string.rep(" ", W))
  screen:paint(colours.lightGrey, colours.black)
  screen:at(1, 2, "buscar: ")
  screen:paint(colours.white, colours.black)
  screen:at(9, 2, query .. "_")

  local label = sortByName and "[A-Z]" or "[cant]"
  sortButton.x1, sortButton.x2 = W - #label, W - 1
  screen:paint(colours.black, colour and colours.lightGrey or colours.white)
  screen:at(sortButton.x1, 2, label)

  -- Categoria, con flechas clickeables.
  local chip = "<" .. CATEGORIES[category] .. ">"
  catButton.x1 = sortButton.x1 - #chip - 1
  catButton.x2 = catButton.x1 + #chip - 1
  screen:paint(colours.black, colour and colours.cyan or colours.white)
  screen:at(catButton.x1, 2, chip)
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

    screen:paint(fg, bg)
    screen:at(1, y, string.rep(" ", W - 1))
    if entry then
      screen:paint(selected and colours.black or colours.yellow, bg)
      screen:right(7, y, shortCount(entry.total))
      local badge, badgeColour = wearBadge(entry.key)
      local nameWidth = math.max(1, W - 10 - (badge and #badge + 1 or 0))
      screen:paint(fg, bg)
      screen:at(9, y, draw.fit(entry.display, nameWidth))
      if badge then
        -- En la fila seleccionada el fondo ya es de color: el negro se lee mejor.
        screen:paint(selected and colours.black or badgeColour, bg)
        screen:right(W - 2, y, badge)
      end
    end

    -- Barra de scroll.
    local track = colour and colours.grey or colours.black
    local thumb = colour and colours.lightGrey or colours.white
    local isThumb = thumbFrom and i >= thumbFrom and i < thumbFrom + thumbSize
    screen:paint(colours.white, thumbFrom and (isThumb and thumb or track) or colours.black)
    screen:at(W, y, " ")
  end

  if #rows == 0 then
    local text = query ~= "" and ("sin resultados para '" .. query .. "'") or "el almacenamiento esta vacio"
    screen:paint(colours.grey, colours.black)
    screen:at(math.max(1, math.floor((W - #text) / 2)), 3 + math.floor(h / 2), text)
  end
end

local function drawFooter()
  screen:paint(messageColour or colours.lightGrey, colours.black)
  screen:at(1, H - 1, draw.fit(message or "", W))
  screen:paint(colours.black, colour and colours.grey or colours.white)
  screen:at(1, H, draw.fit(" enter pedir   tab detalle   F1 ayuda   F10 salir", W))
end

local function render()
  drawHeader()
  drawSearch()
  drawList()
  drawFooter()
  screen:cursor(1, 1, false)
  screen:present()
  dirty = false
end

-- Dos columnas, porque la lista entera no entra en un cuadro de 19 filas.
local HELP = {
  { "escribir", "filtra" },
  { "#logs", "filtra por tag" },
  { "fortune", "busca encant." },
  { "flechas", "mover, categ." },
  { "enter", "pedir cantidad" },
  { "tab", "detalle" },
  { "click", "elegir/pedir" },
  { "click der", "pedir todo" },
  { "ctrl+u", "limpiar busq." },
  { "ctrl+d", "cancelar" },
  { "F1", "ayuda" },
  { "F2", "orden A-Z" },
  { "F3", "diagnostico" },
  { "F4", "repetir" },
  { "F5", "re-escanear" },
  { "F6", "juntar stacks" },
  { "F9", "reconfigurar" },
  { "F10", "salir" },
}

local function showHelp()
  local function cell(entry)
    if not entry then return "" end
    return ("%-9s %s"):format(entry[1], entry[2])
  end
  local lines = {}
  local half = math.ceil(#HELP / 2)
  for i = 1, half do
    lines[#lines + 1] = draw.fit(cell(HELP[i]), 25) .. cell(HELP[i + half])
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "en la lista: * encantado, 87% durabilidad"
  lines[#lines + 1] = "el mouse solo anda en las Advanced"
  lines[#lines + 1] = "el escape no sirve: cierra la computadora"
  dialog.message("atajos", lines)
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
  local mon = monitor.status
  lines[#lines + 1] = ("monitor: %s"):format(mon.state or "?")
  if mon.name then
    lines[#lines + 1] = ("  %s  %sx%s  %s")
      :format(mon.name, mon.width or "?", mon.height or "?", mon.colour and "color" or "sin color")
  end
  if mon.error then lines[#lines + 1] = "  " .. mon.error end
  if mon.frames then lines[#lines + 1] = ("  %d refrescos"):format(mon.frames) end
  lines[#lines + 1] = ""
  local frags, recoverable = storage.fragments()
  if recoverable > 0 then
    lines[#lines + 1] = ("%d slots se recuperan juntando parciales (F6):"):format(recoverable)
    for i = 1, math.min(4, #frags) do
      lines[#lines + 1] = ("  %-22s %d stacks parciales")
        :format(items.displayName(frags[i].key), frags[i].stacks)
    end
  else
    lines[#lines + 1] = "sin stacks parciales de mas"
  end
  if storage.compactError then
    lines[#lines + 1] = "! juntar parciales fallo: " .. storage.compactError
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
  local locations = storage.locations(entry.key)
  local lines = { entry.key,
                  ("%d %s"):format(entry.total, entry.total == 1 and "unidad" or "unidades") }

  local wear = items.wear(entry.key)
  if wear then
    if wear.unbreakable then
      lines[#lines + 1] = "irrompible"
    else
      lines[#lines + 1] = ("durabilidad %d%% [%s]"):format(wear.percent, items.bar(wear.ratio, 10))
      lines[#lines + 1] = ("quedan %d de %d usos"):format(wear.left, wear.maxDamage)
    end
  else
    lines[#lines + 1] = ("apila de a %d"):format(items.maxCount(entry.key))
  end

  local variants = storage.variants(entry.key)
  if #variants > 1 then
    lines[#lines + 1] = ("%d variantes con NBT distinto:"):format(#variants)
    lines[#lines + 1] = "no se apilan entre si"
  end

  local enchantments = items.enchantments(entry.key)
  if #enchantments > 0 then
    lines[#lines + 1] = "encantamientos:"
    for _, e in ipairs(enchantments) do lines[#lines + 1] = "  " .. e end
  end

  lines[#lines + 1] = ("en %d %s"):format(#locations, #locations == 1 and "cofre" or "cofres")
  for _, loc in ipairs(locations) do
    lines[#lines + 1] = ("  %-22s %5d en %d %s")
      :format(loc.chest, loc.count, loc.slots, loc.slots == 1 and "slot" or "slots")
  end
  dialog.detail(entry.display, icons.render(entry.key, colours.black), lines)
  dirty = true
end

local function deliver(entry, amount)
  storage.busy = true
  local moved, reason = storage.take(entry.key, amount)
  storage.busy = false
  if moved > 0 then
    remember(entry.key)
    lastOrder = { key = entry.key, display = entry.display, amount = amount }
    os.queueEvent("organizer_update")  -- que el panel del monitor se entere
  end

  if moved == 0 then
    setMessage(("no entregue nada: %s"):format(reason or "?"), colours.red)
  elseif moved < amount then
    setMessage(("%d/%d %s (%s)"):format(moved, amount, entry.display, reason or "?"), colours.yellow)
  else
    setMessage(("%d %s -> %s"):format(moved, entry.display, cfg.output), colours.lime)
  end
  recompute(true)
end

--- Abre el dialogo de cantidad para un item concreto.
function requestFor(entry, default)  -- luacheck: ignore
  local amount = dialog.number({
    title = entry.display,
    info = {
      ("hay %d en stock"):format(entry.total),
      "podes escribir cuentas: 64*3+16",
    },
    default = default or math.min(entry.total, items.maxCount(entry.key)),
    max = entry.total,
  })
  dirty = true
  if not amount then
    setMessage("cancelado")
    return
  end
  deliver(entry, amount)
end

local function requestSelected()
  local entry = rows[sel]
  if entry then requestFor(entry) end
end

--- Vuelve a pedir lo ultimo, con la misma cantidad ya escrita para confirmar.
local function repeatLast()
  if not lastOrder then
    setMessage("todavia no pediste nada", colours.yellow)
    return
  end
  local total = storage.count(lastOrder.key)
  if total == 0 then
    setMessage(("ya no queda %s"):format(lastOrder.display), colours.yellow)
    return
  end
  requestFor({ key = lastOrder.key, display = lastOrder.display, total = total },
             math.min(lastOrder.amount, total))
end

local function cycleCategory(delta)
  category = (category - 1 + delta) % #CATEGORIES + 1
  recompute(true)
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

--- Junta stacks parciales a mano. Al guardar ya se hace solo para lo que entra;
--- esto sirve despues de acomodar cofres a mano o para arreglar lo viejo.
local function compactNow()
  setMessage("juntando stacks parciales...")
  render()
  storage.busy = true
  local ok, freed, moves, err = pcall(storage.compact)
  storage.busy = false
  if not ok then
    setMessage("fallo juntar parciales: " .. tostring(freed), colours.red)
  elseif err then
    setMessage(("%d slots liberados, pero: %s"):format(freed, err), colours.yellow)
  elseif moves == 0 then
    setMessage("no hay stacks parciales para juntar", colours.lime)
  else
    setMessage(("%d slots liberados en %d movimientos"):format(freed, moves), colours.lime)
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
  elseif key == keys.left then cycleCategory(-1)
  elseif key == keys.right then cycleCategory(1)
  elseif key == keys.pageUp then move(-listHeight())
  elseif key == keys.pageDown then move(listHeight())
  elseif key == keys.home then sel = 1; clampView(); dirty = true
  elseif key == keys["end"] then sel = #rows; clampView(); dirty = true
  elseif key == keys.enter or key == keys.numPadEnter then requestSelected()
  elseif key == keys.tab then showDetail()
  elseif key == keys.backspace then
    if #query > 0 then query = query:sub(1, -2); recompute() end
  elseif key == keys.escape then
    -- Minecraft se queda con el escape antes que nosotros, pero por si acaso.
    if #query > 0 then query = ""; recompute() end
  elseif key == keys.f1 then showHelp()
  elseif key == keys.f2 then sortByName = not sortByName; recompute(true)
  elseif key == keys.f3 then showDiagnostics()
  elseif key == keys.f4 then repeatLast()
  elseif key == keys.f5 then doRefresh()
  elseif key == keys.f6 then compactNow()
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
  if y == 2 and x >= catButton.x1 and x <= catButton.x2 then
    cycleCategory(x == catButton.x1 and -1 or 1)
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
  screen = draw.new(win, function()
    win.setVisible(true)
    win.setVisible(false)
  end, colour)
  dialog.attach(screen)

  running, ui.reconfigure = true, false
  query, sel, top, ctrlDown, category = "", 1, 1, false, 1
  loadRecent()
  term.setBackgroundColour(colours.black)
  term.clear()
  screen:clear()

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
