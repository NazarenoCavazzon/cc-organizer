-- Nucleo del almacenamiento: descubrimiento de cofres, indice de items,
-- guardado automatico desde el cofre de entrada y extraccion al de salida.

local items = require("lib.items")

-- CC:Tweaked corre Lua 5.1 con table.unpack agregado; Lua 5.1 pelado solo tiene
-- unpack. Aceptamos los dos para poder correr los tests con cualquiera.
local unpack = table.unpack or unpack

local storage = {}

local cfg
local chests = {}       -- array ordenado {name, wrap, size}
local byName = {}       -- name -> chest
local contents = {}     -- name -> { [slot] = {name, nbt, count, key} }
local index = {}        -- key -> {key, total, locs = { {chest, slot, count} }}

-- Evita que el guardado automatico y un comando del usuario muevan items a la vez.
storage.busy = false

-- Ultimos movimientos, mas reciente primero, para el panel del monitor.
local activity = {}
local ACTIVITY_MAX = 20

local function logActivity(sign, key, count)
  if not count or count <= 0 then return end
  table.insert(activity, 1, { sign = sign, key = key, count = count })
  while #activity > ACTIVITY_MAX do table.remove(activity) end
end

--- Los ultimos `n` movimientos: { sign = "+" o "-", key, count }.
function storage.activity(n)
  local out = {}
  for i = 1, math.min(n or ACTIVITY_MAX, #activity) do out[i] = activity[i] end
  return out
end

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
    parallel.waitForAll(unpack(batch))
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

--- Cofres ordenados por conveniencia: primero todos los que tienen un stack
--- parcial de ese item, despues los que tienen slots libres.
---
--- `room` es el hueco que queda en esos stacks parciales, y el que guarda lo usa
--- como tope: si no, el resto del stack se comeria un slot vacio de ese mismo
--- cofre mientras quedan parciales en otros, y el almacenamiento se llena de
--- medios stacks del mismo item. Un cofre con parcial Y slots libres aparece en
--- las dos listas.
local function targetsFor(key)
  local withItem, withSpace = {}, {}
  for _, c in ipairs(chests) do
    local partial, free = capacityFor(c, key)
    if partial > 0 then
      withItem[#withItem + 1] = { chest = c, room = partial }
    end
    if free > 0 then
      withSpace[#withSpace + 1] = { chest = c, free = free }
    end
  end
  table.sort(withItem, function(a, b) return a.room > b.room end)
  table.sort(withSpace, function(a, b) return a.free > b.free end)
  local out = {}
  for _, t in ipairs(withItem) do out[#out + 1] = t end
  for _, t in ipairs(withSpace) do out[#out + 1] = t end
  if #out == 0 then
    -- El indice dice que no entra en ningun lado. Puede ser cierto o puede ser
    -- que este desactualizado: probamos igual para que el error sea el real.
    for _, c in ipairs(chests) do out[#out + 1] = { chest = c } end
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
  local movedByKey = {}
  for slot, item in pairs(list) do
    local key = items.key(item)
    if not items.hasMeta(key) then
      local okd, detail = pcall(inv.getItemDetail, slot)
      if okd then items.setMeta(key, detail) end
    end
    local remaining = item.count
    for _, target in ipairs(targetsFor(key)) do
      if remaining <= 0 then break end
      local c = target.chest
      -- Con `room`, solo lo que entra en los stacks parciales de este cofre.
      local limit = target.room and math.min(remaining, target.room) or remaining
      local okm, n = pcall(c.wrap.pullItems, cfg.input, slot, limit)
      if not okm then
        moveError = cleanError(n)
      elseif n and n > 0 then
        remaining = remaining - n
        moved = moved + n
        movedByKey[key] = (movedByKey[key] or 0) + n
        touched[c.name] = true
        -- Re-leer ahora mantiene exacta la capacidad para los slots que siguen.
        readChest(c)
      end
    end
    left = left + remaining
  end

  if next(touched) then rebuildIndex() end
  for key, count in pairs(movedByKey) do logActivity("+", key, count) end

  -- Lo que acabamos de guardar puede tener stacks parciales viejos desparramados:
  -- juntarlos ahora cuesta un par de movimientos y evita que el almacenamiento
  -- se vaya fragmentando con el uso. Solo las claves que tocamos.
  if next(movedByKey) then
    local _, _, compactError = storage.compact(movedByKey)
    storage.compactError = compactError
  end
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

  -- De menor a mayor: se vacian los stacks parciales primero, que libera slots
  -- enteros. Sacar de los grandes deja los parciales ahi para siempre.
  local locs = {}
  for _, loc in ipairs(e.locs) do locs[#locs + 1] = loc end
  table.sort(locs, function(a, b) return a.count < b.count end)

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
  logActivity("-", key, moved)
  if moved < amount then
    if not outputHasRoom(key) then return moved, "cofre de salida lleno" end
    return moved, "no hay mas stock"
  end
  return moved
end

--- Stacks parciales de una clave, de mas lleno a mas vacio.
local function partialStacks(key)
  local e = index[key]
  local max = items.maxCount(key)
  if not e or max <= 1 then return {}, max end
  local out = {}
  for _, loc in ipairs(e.locs) do
    if loc.count < max then
      out[#out + 1] = { chest = loc.chest, slot = loc.slot, count = loc.count }
    end
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out, max
end

--- Cuantos slots se recuperarian juntando stacks parciales. No mueve nada.
--- Devuelve la lista por item (la que mas recupera primero) y el total.
function storage.fragments()
  local out, total = {}, 0
  for key in pairs(index) do
    local partial, max = partialStacks(key)
    if #partial > 1 then
      local sum = 0
      for _, p in ipairs(partial) do sum = sum + p.count end
      local needed = math.ceil(sum / max)
      if #partial > needed then
        local recover = #partial - needed
        out[#out + 1] = { key = key, stacks = #partial, recover = recover }
        total = total + recover
      end
    end
  end
  table.sort(out, function(a, b)
    if a.recover ~= b.recover then return a.recover > b.recover end
    return a.key < b.key
  end)
  return out, total
end

--- Junta los stacks parciales de cada item para liberar slots.
--- `onlyKeys` (set de claves) limita el trabajo; nil = toda la red.
--- Devuelve: slots liberados, movimientos, error.
function storage.compact(onlyKeys)
  local freed, moves, err = 0, 0, nil
  local touched = {}
  local keys = {}
  for key in pairs(index) do
    if not onlyKeys or onlyKeys[key] then keys[#keys + 1] = key end
  end
  table.sort(keys)  -- orden estable: el resultado no depende del hash

  for _, key in ipairs(keys) do
    local partial, max = partialStacks(key)
    -- Se llenan los stacks mas grandes con los mas chicos: asi se vacian slots
    -- enteros, en vez de repartir el faltante entre todos.
    local i, j = 1, #partial
    while i < j do
      local dest, src = partial[i], partial[j]
      local c = byName[dest.chest]
      if not c then break end
      local want = math.min(max - dest.count, src.count)
      local ok, n = pcall(c.wrap.pullItems, src.chest, src.slot, want, dest.slot)
      if not ok then
        err = cleanError(n)
        break
      end
      n = n or 0
      if n == 0 then break end  -- no avanza: cortar antes de girar en falso
      moves = moves + 1
      dest.count, src.count = dest.count + n, src.count - n
      touched[dest.chest], touched[src.chest] = true, true
      if src.count <= 0 then
        freed = freed + 1
        j = j - 1
      end
      if dest.count >= max then i = i + 1 end
    end
  end

  if next(touched) then rescan(touched) end
  return freed, moves, err
end

--- Otras claves del mismo item con NBT distinto: dos stacks que se ven iguales
--- pero no se apilan (encantamientos, durabilidad, componentes).
function storage.variants(key)
  local base = key:match("^(.-)@") or key
  local out = {}
  for other in pairs(index) do
    if (other:match("^(.-)@") or other) == base then out[#out + 1] = other end
  end
  table.sort(out)
  return out
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

--- Donde vive una clave: cuantas unidades y slots ocupa en cada cofre.
function storage.locations(key)
  local e = index[key]
  if not e then return {} end
  local byChest = {}
  for _, loc in ipairs(e.locs) do
    local entry = byChest[loc.chest]
    if not entry then
      entry = { chest = loc.chest, count = 0, slots = 0 }
      byChest[loc.chest] = entry
    end
    entry.count = entry.count + loc.count
    entry.slots = entry.slots + 1
  end
  local out = {}
  for _, entry in pairs(byChest) do out[#out + 1] = entry end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out
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
