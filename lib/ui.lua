-- Interfaz de terminal: un REPL con comandos cortos sobre lib/storage.

local items = require("lib.items")

local ui = {}

local storage, cfg
local history = {}
local notices = {}
local running = true

local COMMANDS = { "stock", "get", "find", "store", "space", "refresh", "peripherals", "help", "exit" }

local function colour(c)
  if term.isColour and term.isColour() then term.setTextColour(c) end
end

local function say(c, fmt, ...)
  colour(c)
  print(select("#", ...) > 0 and fmt:format(...) or fmt)
  colour(colours.white)
end

--- Mensajes generados fuera del REPL (guardado automatico); se muestran antes del prompt.
function ui.notify(msg)
  notices[#notices + 1] = msg
end

local function flushNotices()
  for _, msg in ipairs(notices) do say(colours.lightGrey, msg) end
  notices = {}
end

--- Imprime lineas de a pantallas para que no se escapen hacia arriba.
local function paged(lines)
  local _, height = term.getSize()
  local perPage = height - 3
  for i, line in ipairs(lines) do
    print(line)
    if i % perPage == 0 and i < #lines then
      colour(colours.grey)
      write("-- " .. (#lines - i) .. " mas, tecla para seguir, q para cortar --")
      local _, key = os.pullEvent("key")
      colour(colours.white)
      print()
      if key == keys.q then return end
    end
  end
end

local function showStock(filter)
  local list = storage.stock(filter)
  if #list == 0 then
    say(colours.yellow, filter and ("nada que matchee '" .. filter .. "'") or "el almacenamiento esta vacio")
    return
  end
  local lines = {}
  for _, e in ipairs(list) do
    lines[#lines + 1] = ("%8s  %s"):format(e.total, e.display)
  end
  paged(lines)
  say(colours.grey, "%d tipos de item", #list)
end

local function showFind(filter)
  local list = storage.stock(filter)
  if #list == 0 then
    say(colours.yellow, "nada que matchee '%s'", filter)
    return
  end
  local lines = {}
  for _, e in ipairs(list) do
    lines[#lines + 1] = ("%8s  %s  (%s)"):format(e.total, e.display, e.key)
  end
  paged(lines)
end

--- Resuelve un filtro a una sola clave; si hay varias opciones las lista para elegir.
local function resolveKey(filter)
  local keys_ = storage.findKeys(filter)
  if #keys_ == 0 then
    say(colours.yellow, "no tengo nada que matchee '%s'", filter)
    return nil
  end
  if #keys_ == 1 then return keys_[1] end

  say(colours.yellow, "varias opciones:")
  local shown = math.min(#keys_, 9)
  for i = 1, shown do
    local key = keys_[i]
    print(("  %d) %-28s %s"):format(i, items.displayName(key), storage.count(key)))
  end
  if #keys_ > shown then say(colours.grey, "  ... y %d mas, afina el filtro", #keys_ - shown) end
  colour(colours.grey)
  write("numero (enter cancela): ")
  colour(colours.white)
  local answer = tonumber(read())
  if not answer or not keys_[answer] or answer > shown then return nil end
  return keys_[answer]
end

local function doGet(args)
  if #args == 0 then
    say(colours.yellow, "uso: get <item> [cantidad]")
    return
  end
  local amount = 64
  if #args > 1 and tonumber(args[#args]) then
    amount = math.floor(tonumber(table.remove(args)))
  end
  if amount <= 0 then
    say(colours.yellow, "la cantidad tiene que ser mayor a 0")
    return
  end
  local key = resolveKey(table.concat(args, " "))
  if not key then return end

  storage.busy = true
  local moved, reason = storage.take(key, amount)
  storage.busy = false

  if moved == 0 then
    say(colours.red, "no entregue nada: %s", reason or "?")
  elseif moved < amount then
    say(colours.yellow, "%d/%d %s -> %s (%s)", moved, amount, items.displayName(key), cfg.output, reason or "?")
  else
    say(colours.lime, "%d %s -> %s", moved, items.displayName(key), cfg.output)
  end
end

local function doStore()
  storage.busy = true
  local moved, left, err = storage.store()
  storage.busy = false
  if moved == 0 and left == 0 then
    say(colours.grey, "el cofre de entrada esta vacio")
    return
  end
  say(colours.lime, "guarde %d items", moved)
  if left > 0 then say(colours.red, "quedaron %d sin lugar (%s)", left, err or "?") end
end

local function doSpace()
  local s = storage.space()
  local pct = s.slots > 0 and math.floor(s.used / s.slots * 100) or 0
  say(colours.white, "%d cofres | %d/%d slots usados (%d%%) | %d libres",
    s.chests, s.used, s.slots, pct, s.free)
end

local function doRefresh()
  storage.busy = true
  local ok, err = pcall(storage.refresh)
  storage.busy = false
  if not ok then
    say(colours.red, "fallo el escaneo: %s", tostring(err))
    return
  end
  local s = storage.space()
  say(colours.lime, "indexados %d cofres, %d slots ocupados", s.chests, s.used)
end

local function doPeripherals()
  say(colours.grey, "entrada: %s | salida: %s", cfg.input, cfg.output)
  local lines = {}
  for _, name in ipairs(peripheral.getNames()) do
    local mark = " "
    if name == cfg.input then mark = "I"
    elseif name == cfg.output then mark = "O"
    elseif peripheral.hasType(name, "inventory") then mark = "*" end
    lines[#lines + 1] = ("%s %s (%s)"):format(mark, name, peripheral.getType(name))
  end
  paged(lines)
  say(colours.grey, "* = cofre de almacenamiento, I = entrada, O = salida")
end

local function doHelp()
  say(colours.white, "comandos:")
  print("  stock [filtro]      que hay guardado")
  print("  find <texto>        busca mostrando los ids")
  print("  get <item> [n]      manda n al cofre de salida (default 64)")
  print("  store               vacia el cofre de entrada ahora")
  print("  space               ocupacion del almacenamiento")
  print("  refresh             re-escanea todos los cofres")
  print("  peripherals         nombres de la red (para config.lua)")
  print("  exit                salir")
end

local function complete(partial)
  local out = {}
  for _, cmd in ipairs(COMMANDS) do
    if #cmd > #partial and cmd:sub(1, #partial) == partial then
      out[#out + 1] = cmd:sub(#partial + 1)
    end
  end
  return out
end

local function dispatch(line)
  local args = {}
  for word in line:gmatch("%S+") do args[#args + 1] = word end
  local cmd = table.remove(args, 1)
  if not cmd then return end
  history[#history + 1] = line

  if cmd == "stock" then showStock(#args > 0 and table.concat(args, " ") or nil)
  elseif cmd == "find" then
    if #args == 0 then say(colours.yellow, "uso: find <texto>") else showFind(table.concat(args, " ")) end
  elseif cmd == "get" then doGet(args)
  elseif cmd == "store" then doStore()
  elseif cmd == "space" then doSpace()
  elseif cmd == "refresh" then doRefresh()
  elseif cmd == "peripherals" then doPeripherals()
  elseif cmd == "help" or cmd == "?" then doHelp()
  elseif cmd == "exit" or cmd == "quit" then running = false
  else say(colours.red, "no conozco '%s' (help para la lista)", cmd)
  end
end

function ui.run(store, config)
  storage, cfg = store, config
  local s = storage.space()
  say(colours.lime, "cc-organizer | %d cofres, %d/%d slots", s.chests, s.used, s.slots)
  say(colours.grey, "help para ver los comandos")

  while running do
    flushNotices()
    colour(colours.cyan)
    write("> ")
    colour(colours.white)
    local line = read(nil, history, complete)
    if line == nil then break end
    local ok, err = pcall(dispatch, line)
    if not ok then say(colours.red, "error: %s", tostring(err)) end
  end
end

return ui
