-- Nucleo del almacenamiento: descubrimiento de cofres, indice de items,
-- guardado automatico desde el cofre de entrada y extraccion al de salida.

local items = require("lib.items")

local storage = {}

local cfg
local chests = {}       -- array ordenado {name, wrap, size}
local byName = {}       -- name -> chest
local contents = {}     -- name -> { [slot] = {name, nbt, count, key} }
local index = {}        -- key -> {key, total, locs = { {chest, slot, count} }}

-- Evita que el guardado automatico y un comando del usuario muevan items a la vez.
storage.busy = false

local BATCH = 40

-- Los peripherals pegados directo a la computadora se llaman por su lado. Esos
-- NO estan en la red de cables, asi que ningun otro cofre puede moverles items.
local SIDES = {
  top = true, bottom = true, left = true, right = true, front = true, back = true,
}

--- Corre fn sobre cada elemento en paralelo, en tandas para no abusar de corrutinas.
local function eachParallel(list, fn)
  if not parallel or #list <= 1 then
    for _, v in ipairs(list) do fn(v) end
    return
  end
  local i = 1
  while i <= #list do
    local batch = {}
    for j = i, math.min(i + BATCH - 1, #list) do
      local v = list[j]
      batch[#batch + 1] = function() fn(v) end
    end
    parallel.waitForAll(table.unpack(batch))
    i = i + BATCH
  end
end

local function rebuildIndex()
  index = {}
  for name, slots in pairs(contents) do
    for slot, item in pairs(slots) do
      local e = index[item.key]
      if not e then
        e = { key = item.key, total = 0, locs = {} }
        index[item.key] = e
      end
      e.total = e.total + item.count
      e.locs[#e.locs + 1] = { chest = name, slot = slot, count = item.count }
    end
  end
end

local function readChest(c)
  local ok, list = pcall(c.wrap.list)
  if not ok or not list then return false end
  local slots = {}
  for slot, item in pairs(list) do
    slots[slot] = { name = item.name, nbt = item.nbt, count = item.count, key = items.key(item) }
  end
  contents[c.name] = slots
  return true
end

--- Pide displayName/maxCount de las claves que todavia no estan cacheadas.
local function hydrateMeta()
  local pending = {}
  for key, e in pairs(index) do
    if not items.hasMeta(key) and e.locs[1] then
      pending[#pending + 1] = { key = key, loc = e.locs[1] }
    end
  end
  local details = {}
  eachParallel(pending, function(p)
    local c = byName[p.loc.chest]
    if not c then return end
    local ok, detail = pcall(c.wrap.getItemDetail, p.loc.slot)
    if ok and detail then details[p.key] = detail end
  end)
  for key, detail in pairs(details) do items.setMeta(key, detail) end
end

function storage.init(config)
  cfg = config
  chests, byName, contents, index = {}, {}, {}, {}
end

--- Busca todos los inventarios de la red, salvo entrada, salida e ignorados.
function storage.discover()
  local skip = { [cfg.input] = true, [cfg.output] = true }
  for _, n in ipairs(cfg.ignore or {}) do skip[n] = true end

  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    if not skip[name] and peripheral.hasType(name, "inventory") then
      found[#found + 1] = name
    end
  end
  table.sort(found)

  local new, newByName = {}, {}
  for _, name in ipairs(found) do
    local prev = byName[name]
    local c = prev or { name = name, wrap = peripheral.wrap(name) }
    new[#new + 1] = c
    newByName[name] = c
  end
  chests, byName = new, newByName

  eachParallel(chests, function(c)
    local ok, size = pcall(c.wrap.size)
    c.size = (ok and size) or c.size or 0
  end)

  -- Olvida cofres que ya no estan en la red.
  for name in pairs(contents) do
    if not byName[name] then contents[name] = nil end
  end
  return #chests
end

--- Re-lee todos los cofres. Es la operacion cara: solo al arrancar o con `refresh`.
function storage.refresh()
  storage.discover()
  contents = {}
  eachParallel(chests, readChest)
  rebuildIndex()
  hydrateMeta()
end

--- Re-lee solo los cofres tocados por la ultima operacion.
local function rescan(touched)
  local list = {}
  for name in pairs(touched) do
    if byName[name] then list[#list + 1] = byName[name] end
  end
  eachParallel(list, readChest)
  rebuildIndex()
end

--- Espacio estimado en un cofre para una clave: hueco en stacks parciales y en slots libres.
local function capacityFor(c, key)
  local max = items.maxCount(key)
  local slots = contents[c.name] or {}
  local used, partial = 0, 0
  for _, item in pairs(slots) do
    used = used + 1
    if item.key == key then partial = partial + (max - item.count) end
  end
  return partial, math.max(0, (c.size or 0) - used) * max
end

--- Cofres ordenados por conveniencia: primero los que ya tienen el item
--- (compacta stacks), despues los que tienen mas espacio libre.
local function targetsFor(key)
  local withItem, withSpace = {}, {}
  for _, c in ipairs(chests) do
    local partial, free = capacityFor(c, key)
    if partial > 0 then
      withItem[#withItem + 1] = { c = c, score = partial }
    elseif free > 0 then
      withSpace[#withSpace + 1] = { c = c, score = free }
    end
  end
  table.sort(withItem, function(a, b) return a.score > b.score end)
  table.sort(withSpace, function(a, b) return a.score > b.score end)
  local out = {}
  for _, t in ipairs(withItem) do out[#out + 1] = t.c end
  for _, t in ipairs(withSpace) do out[#out + 1] = t.c end
  if #out == 0 then
    -- El indice dice que no entra en ningun lado. Puede ser cierto o puede ser
    -- que este desactualizado: probamos igual para que el error sea el real.
    for _, c in ipairs(chests) do out[#out + 1] = c end
  end
  return out
end

--- Mensajes de error de CC vienen como "startup.lua:12: texto"; solo queremos el texto.
local function cleanError(err)
  err = tostring(err)
  return (err:gsub("^.-:%d+: ", ""))
end

--- Vacia el cofre de entrada repartiendo todo en la red.
--- Devuelve: movidos, sobrantes, error.
function storage.store()
  local inv = peripheral.wrap(cfg.input)
  if not inv then return 0, 0, "no encuentro el cofre de entrada (" .. cfg.input .. ")" end
  local ok, list = pcall(inv.list)
  if not ok or not list then return 0, 0, "no puedo leer el cofre de entrada" end

  local moved, left, touched, moveError = 0, 0, {}, nil
  for slot, item in pairs(list) do
    local key = items.key(item)
    if not items.hasMeta(key) then
      local okd, detail = pcall(inv.getItemDetail, slot)
      if okd then items.setMeta(key, detail) end
    end
    local remaining = item.count
    for _, c in ipairs(targetsFor(key)) do
      if remaining <= 0 then break end
      local okm, n = pcall(c.wrap.pullItems, cfg.input, slot, remaining)
      if not okm then
        moveError = cleanError(n)
      elseif n and n > 0 then
        remaining = remaining - n
        moved = moved + n
        touched[c.name] = true
        -- Re-leer ahora mantiene exacta la capacidad para los slots que siguen.
        readChest(c)
      end
    end
    left = left + remaining
  end

  if next(touched) then rebuildIndex() end
  if left > 0 then
    if #chests == 0 then
      return moved, left, "no hay cofres de almacenamiento en la red"
    elseif SIDES[cfg.input] then
      return moved, left, "el cofre de entrada no esta en la red de cables (F3)"
    elseif moveError then
      return moved, left, moveError
    end
    return moved, left, "almacenamiento lleno"
  end
  return moved, left
end

--- Slot vacio del cofre de entrada: sirve para probar si otro cofre lo alcanza
--- sin mover ningun item (pullItems sobre un slot vacio devuelve 0).
local function probeSlot(inv)
  local okL, list = pcall(inv.list)
  local okS, size = pcall(inv.size)
  if not okL or not okS or not list or not size then return nil end
  for slot = 1, size do
    if not list[slot] then return slot end
  end
  return nil
end

--- Revision del armado: devuelve los problemas encontrados y el estado por cofre.
function storage.diagnose()
  local report = { problems = {}, chests = {} }
  local function problem(fmt, ...)
    report.problems[#report.problems + 1] = fmt:format(...)
  end

  for _, io in ipairs({ { cfg.input, "entrada" }, { cfg.output, "salida" } }) do
    local name, label = io[1], io[2]
    if not peripheral.isPresent(name) then
      problem("el cofre de %s (%s) no esta en la red", label, name)
    elseif SIDES[name] then
      problem("el cofre de %s esta pegado a la computadora (lado '%s'):", label, name)
      problem("  ponele un modem cableado y reconfiguralo con F9")
    elseif not peripheral.hasType(name, "inventory") then
      problem("el cofre de %s (%s) no es un inventario", label, name)
    end
  end

  if #chests == 0 then
    problem("no hay cofres de almacenamiento: conecta mas cofres con modem")
  end

  -- Prueba real: cada cofre tiene que poder sacarle items al de entrada. Si no
  -- lo alcanza es que estan en redes de cable distintas.
  local inv = peripheral.wrap(cfg.input)
  local slot = inv and probeSlot(inv)

  local sideChests, unreachable = 0, 0
  for _, c in ipairs(chests) do
    local used = 0
    for _ in pairs(contents[c.name] or {}) do used = used + 1 end
    local entry = { name = c.name, size = c.size or 0, used = used, reachable = true }
    if slot then
      entry.reachable = pcall(c.wrap.pullItems, cfg.input, slot)
      if not entry.reachable then unreachable = unreachable + 1 end
    end
    report.chests[#report.chests + 1] = entry
    if SIDES[c.name] then sideChests = sideChests + 1 end
    if (c.size or 0) == 0 then problem("no puedo leer el tamano de %s", c.name) end
  end
  if sideChests > 0 then
    problem("%d cofre(s) estan pegados a la computadora en vez de la red", sideChests)
  end
  if unreachable > 0 then
    problem("%d cofre(s) no alcanzan al cofre de entrada:", unreachable)
    problem("  estan en OTRA red de cables. Uni todos los modems entre si")
    problem("  con networking cable (tocar la computadora no alcanza)")
  end
  report.unreachable = unreachable

  local s = storage.space()
  if #chests > 0 and s.free == 0 then
    problem("todos los cofres estan llenos de verdad (%d/%d slots)", s.used, s.slots)
  end
  return report
end

--- Espacio del cofre de salida para una clave (para explicar por que no se entrego todo).
local function outputHasRoom(key)
  local out = peripheral.wrap(cfg.output)
  if not out then return false end
  local okS, size = pcall(out.size)
  local okL, list = pcall(out.list)
  if not okS or not okL then return false end
  local max, used, room = items.maxCount(key), 0, 0
  for _, item in pairs(list) do
    used = used + 1
    if items.key(item) == key then room = room + (max - item.count) end
  end
  return room > 0 or used < size
end

--- Manda `amount` unidades de `key` al cofre de salida.
--- Devuelve: entregados, motivo (cuando entrega menos de lo pedido).
function storage.take(key, amount)
  local out = peripheral.wrap(cfg.output)
  if not out then return 0, "no encuentro el cofre de salida (" .. cfg.output .. ")" end
  local e = index[key]
  if not e or e.total == 0 then return 0, "no hay stock" end

  local locs = {}
  for _, loc in ipairs(e.locs) do locs[#locs + 1] = loc end
  table.sort(locs, function(a, b) return a.count > b.count end)

  local moved, touched = 0, {}
  for _, loc in ipairs(locs) do
    if moved >= amount then break end
    local want = math.min(amount - moved, loc.count)
    local ok, n = pcall(out.pullItems, loc.chest, loc.slot, want)
    if ok and n and n > 0 then
      moved = moved + n
      touched[loc.chest] = true
    end
  end

  if next(touched) then rescan(touched) end
  if moved < amount then
    if not outputHasRoom(key) then return moved, "cofre de salida lleno" end
    return moved, "no hay mas stock"
  end
  return moved
end

--- Lista del stock ordenada por cantidad, opcionalmente filtrada.
function storage.stock(filter)
  local out = {}
  for key, e in pairs(index) do
    if items.matches(key, filter) then
      out[#out + 1] = { key = key, total = e.total, display = items.displayName(key) }
    end
  end
  table.sort(out, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.display < b.display
  end)
  return out
end

--- Claves que matchean el filtro. Un match exacto de id gana a los parciales.
function storage.findKeys(filter)
  if index[filter] then return { filter } end
  local matches = {}
  for _, entry in ipairs(storage.stock(filter)) do matches[#matches + 1] = entry.key end
  return matches
end

function storage.count(key)
  local e = index[key]
  return e and e.total or 0
end

function storage.space()
  local total, used = 0, 0
  for _, c in ipairs(chests) do
    total = total + (c.size or 0)
    local slots = contents[c.name]
    if slots then
      for _ in pairs(slots) do used = used + 1 end
    end
  end
  return { chests = #chests, slots = total, used = used, free = total - used }
end

--- true si el cofre de entrada tiene algo. Es la llamada barata del loop automatico.
function storage.inputHasItems()
  local inv = peripheral.wrap(cfg.input)
  if not inv then return false end
  local ok, list = pcall(inv.list)
  return ok and list ~= nil and next(list) ~= nil
end

function storage.chestNames()
  local out = {}
  for _, c in ipairs(chests) do out[#out + 1] = c.name end
  return out
end

return storage
