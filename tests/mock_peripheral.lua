-- Mundo falso de cofres para probar lib/storage.lua fuera de Minecraft.
-- Define los globales `peripheral` y `parallel` que espera CC:Tweaked.

local mock = {}

local MAXCOUNT = {
  ["minecraft:ender_pearl"] = 16,
  ["minecraft:diamond_sword"] = 1,
}

local registry = {}
local order = {}
local types = {}

-- Tags de mentira, con la forma que devuelve el juego: { ["minecraft:logs"] = true }
local TAGS = {
  ["minecraft:oak_log"] = { "minecraft:logs", "minecraft:oak_logs" },
  ["minecraft:spruce_log"] = { "minecraft:logs" },
  ["minecraft:iron_ingot"] = { "c:ingots", "c:ingots/iron" },
  ["minecraft:gold_ingot"] = { "c:ingots" },
  ["minecraft:cobblestone"] = { "minecraft:stone_crafting_materials" },
}

-- Un peripheral pegado a la computadora se llama por su lado y no existe para
-- el resto de la red: pullItems contra el falla, igual que en el juego.
local SIDES = {
  top = true, bottom = true, left = true, right = true, front = true, back = true,
}

-- Campos extra de getItemDetail (durabilidad, encantamientos), por nbt o por
-- nombre de item: las herramientas del juego llegan siempre con nbt propio.
local EXTRA = {}

local function maxCount(name) return MAXCOUNT[name] or 64 end

local function displayName(name)
  local short = name:match("[^:]+$"):gsub("_", " ")
  return (short:gsub("(%w+)", function(word) return word:gsub("^%l", string.upper) end))
end

local function sameStack(a, b)
  return a.name == b.name and a.nbt == b.nbt
end

--- Mete hasta `count` unidades en el cofre. Devuelve cuantas entraron.
local function insert(chest, item, count)
  local max, placed = maxCount(item.name), 0
  for slot = 1, chest.__size do
    local cur = chest.__slots[slot]
    if placed >= count then break end
    if cur and sameStack(cur, item) and cur.count < max then
      local n = math.min(max - cur.count, count - placed)
      cur.count = cur.count + n
      placed = placed + n
    end
  end
  for slot = 1, chest.__size do
    if placed >= count then break end
    if chest.__slots[slot] == nil then
      local n = math.min(max, count - placed)
      chest.__slots[slot] = { name = item.name, nbt = item.nbt, count = n }
      placed = placed + n
    end
  end
  return placed
end

--- Como insert, pero en un slot concreto: es lo que hace pullItems con toSlot.
local function insertAt(chest, item, count, slot)
  if slot < 1 or slot > chest.__size then error("Slot out of range", 0) end
  local max = maxCount(item.name)
  local cur = chest.__slots[slot]
  if cur then
    if not sameStack(cur, item) or cur.count >= max then return 0 end
    local n = math.min(max - cur.count, count)
    cur.count = cur.count + n
    return n
  end
  local n = math.min(max, count)
  chest.__slots[slot] = { name = item.name, nbt = item.nbt, count = n }
  return n
end

local function newChest(name, size, network)
  local c = { __name = name, __size = size, __slots = {}, __network = network or "main" }

  function c.size() return c.__size end

  function c.list()
    local out = {}
    for slot, it in pairs(c.__slots) do
      out[slot] = { name = it.name, nbt = it.nbt, count = it.count }
    end
    return out
  end

  function c.getItemDetail(slot)
    local it = c.__slots[slot]
    if not it then return nil end
    local tags = {}
    for _, tag in ipairs(TAGS[it.name] or {}) do tags[tag] = true end
    local detail = {
      name = it.name, nbt = it.nbt, count = it.count, tags = tags,
      displayName = displayName(it.name), maxCount = maxCount(it.name),
    }
    for field, value in pairs(EXTRA[it.nbt or ""] or EXTRA[it.name] or {}) do
      detail[field] = value
    end
    return detail
  end

  function c.pullItems(fromName, fromSlot, limit, toSlot)
    if SIDES[fromName] then error("Target '" .. fromName .. "' does not exist", 0) end
    local from = registry[fromName]
    if not from then error("no such peripheral: " .. tostring(fromName)) end
    -- Cofres en redes de cable distintas no se ven entre si.
    if from.__network ~= c.__network then
      error("Target '" .. fromName .. "' does not exist", 0)
    end
    local it = from.__slots[fromSlot]
    if not it then return 0 end
    local want = math.min(limit or it.count, it.count)
    -- Un cofre puede moverse items a si mismo (es como se juntan parciales).
    local moved = toSlot and insertAt(c, it, want, toSlot) or insert(c, it, want)
    it.count = it.count - moved
    if it.count <= 0 then from.__slots[fromSlot] = nil end
    return moved
  end

  function c.pushItems(toName, fromSlot, limit, toSlot)
    local to = registry[toName]
    if not to then error("no such peripheral: " .. tostring(toName)) end
    return to.pullItems(c.__name, fromSlot, limit, toSlot)
  end

  return c
end

--- Arranca un mundo nuevo. `spec` es una lista de {name=, size=}.
function mock.reset(spec)
  registry, order, types, EXTRA = {}, {}, {}, {}
  for _, s in ipairs(spec) do
    registry[s.name] = newChest(s.name, s.size, s.network)
    types[s.name] = "inventory"
    order[#order + 1] = s.name
  end

  _G.peripheral = {
    getNames = function()
      local out = {}
      for _, n in ipairs(order) do out[#out + 1] = n end
      return out
    end,
    wrap = function(name) return registry[name] end,
    getName = function(object)
      for name, peripheral_ in pairs(registry) do
        if peripheral_ == object then return name end
      end
      return nil
    end,
    isPresent = function(name) return registry[name] ~= nil end,
    getType = function(name)
      if not registry[name] then return nil end
      return types[name] == "monitor" and "monitor" or "minecraft:chest"
    end,
    hasType = function(name, t) return types[name] == t end,
    find = function(t)
      for _, name in ipairs(order) do
        if types[name] == t then return registry[name] end
      end
      return nil
    end,
  }

  -- En el mock nada cede el control, asi que correr en serie equivale a paralelo.
  _G.parallel = {
    waitForAll = function(...)
      for _, fn in ipairs({ ... }) do fn() end
    end,
  }
end

--- Conecta un peripheral que no es un cofre (por ejemplo un monitor).
function mock.attach(name, kind, object)
  registry[name] = object
  types[name] = kind
  order[#order + 1] = name
  return object
end

--- Pone items en un cofre directamente (sin pasar por el sistema).
--- Lo que getItemDetail va a agregar para ese nbt (o para ese item sin nbt):
--- damage, maxDamage, durability, enchantments, unbreakable.
function mock.setDetail(nbtOrName, extra)
  EXTRA[nbtOrName] = extra
end

function mock.give(name, itemName, count, nbt)
  local c = assert(registry[name], "cofre inexistente: " .. tostring(name))
  return insert(c, { name = itemName, nbt = nbt }, count)
end

--- Total de un item en un cofre.
function mock.count(name, itemName, nbt)
  local c = assert(registry[name])
  local total = 0
  for _, it in pairs(c.__slots) do
    if it.name == itemName and it.nbt == nbt then total = total + it.count end
  end
  return total
end

function mock.usedSlots(name)
  local c = assert(registry[name])
  local n = 0
  for _ in pairs(c.__slots) do n = n + 1 end
  return n
end

function mock.chest(name) return registry[name] end

return mock
