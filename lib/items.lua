-- Claves de item y cache de metadatos.
--
-- `list()` solo devuelve name/count/nbt. `getItemDetail()` trae displayName,
-- maxCount, durabilidad y encantamientos, pero es caro: se consulta una sola vez
-- por clave y se cachea.

local items = {}

local meta = {}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

--- "minecraft:efficiency" + nivel 5 -> "Efficiency V".
local function enchantLabel(e)
  if type(e.displayName) == "string" and e.displayName ~= "" then return e.displayName end
  local name = tostring(e.name or "?"):match("[^:]+$") or "?"
  name = name:gsub("_", " "):gsub("^%l", string.upper)
  local level = tonumber(e.level)
  if not level or level <= 1 then return name end
  return name .. " " .. (ROMAN[level] or tostring(level))
end

--- Clave unica de un item. Dos stacks con NBT distinto (encantamientos,
--- durabilidad, componentes) no se apilan, asi que son claves distintas.
function items.key(item)
  if item.nbt then return item.name .. "@" .. item.nbt end
  return item.name
end

function items.getMeta(key)
  return meta[key]
end

function items.setMeta(key, detail)
  if not detail then return end
  -- getItemDetail trae los tags del juego ("minecraft:logs", "c:ingots"...);
  -- los guardamos como lista para poder filtrar con #logs.
  local tags = {}
  if type(detail.tags) == "table" then
    for tag in pairs(detail.tags) do tags[#tags + 1] = tag end
    table.sort(tags)
  end

  -- Las herramientas se gastan. Segun la version, getItemDetail trae
  -- `durability` (fraccion restante) o solo damage/maxDamage; aceptamos las dos.
  local maxDamage = tonumber(detail.maxDamage)
  local damage = tonumber(detail.damage) or 0
  local ratio = tonumber(detail.durability)
  if not ratio and maxDamage and maxDamage > 0 then
    ratio = 1 - damage / maxDamage
  end
  if ratio then ratio = math.max(0, math.min(1, ratio)) end

  local enchantments = {}
  if type(detail.enchantments) == "table" then
    for _, e in ipairs(detail.enchantments) do
      if type(e) == "table" then enchantments[#enchantments + 1] = enchantLabel(e) end
    end
  end

  meta[key] = {
    displayName = detail.displayName or detail.name,
    maxCount = detail.maxCount or 64,
    tags = tags,
    damage = damage,
    maxDamage = maxDamage,
    durability = ratio,
    unbreakable = detail.unbreakable and true or false,
    enchantments = enchantments,
  }
end

--- Tags del item, o lista vacia si todavia no tenemos metadata.
function items.tags(key)
  local m = meta[key]
  return m and m.tags or {}
end

--- Encantamientos ya formateados ("Efficiency V"), o lista vacia.
function items.enchantments(key)
  local m = meta[key]
  return m and m.enchantments or {}
end

function items.isEnchanted(key)
  return #items.enchantments(key) > 0
end

--- Desgaste de una herramienta, o nil si el item no se gasta.
--- { ratio = 0..1, percent = 0..100, left = usos, maxDamage, unbreakable }
function items.wear(key)
  local m = meta[key]
  if not m or not m.durability or not m.maxDamage or m.maxDamage <= 0 then return nil end
  return {
    ratio = m.durability,
    -- Se redondea hacia arriba para no mostrar 0% en algo que todavia sirve.
    percent = math.min(100, math.ceil(m.durability * 100)),
    left = math.floor(m.durability * m.maxDamage + 0.5),
    maxDamage = m.maxDamage,
    unbreakable = m.unbreakable,
  }
end

--- Barra ASCII de desgaste: sirve igual en un monitor sin color.
function items.bar(ratio, width)
  local filled = math.max(0, math.min(width, math.floor(ratio * width + 0.5)))
  return string.rep("#", filled) .. string.rep("-", width - filled)
end

function items.hasMeta(key)
  return meta[key] ~= nil
end

--- Cuanto apila este item. 64 es la suposicion segura mientras no haya metadata.
function items.maxCount(key)
  local m = meta[key]
  return m and m.maxCount or 64
end

--- Nombre lindo para mostrar; cae al id corto si todavia no hay metadata.
function items.displayName(key)
  local m = meta[key]
  if m then return m.displayName end
  return items.shortName(key)
end

--- "minecraft:cobblestone@abc123" -> "cobblestone"
function items.shortName(key)
  local name = key:match("^(.-)@") or key
  return name:match("[^:]+$") or name
end

--- Filtro que empieza con # busca en los tags del juego: #logs, #ores, #planks.
local function matchesTag(key, filter)
  for _, tag in ipairs(items.tags(key)) do
    -- El namespace del tag tampoco cuenta: #logs matchea "minecraft:logs".
    local short = tag:match("[^:]+$") or tag
    if short:lower():find(filter, 1, true) or tag:lower():find(filter, 1, true) then
      return true
    end
  end
  return false
end

local function matchesEnchant(key, filter)
  for _, e in ipairs(items.enchantments(key)) do
    if e:lower():find(filter, 1, true) then return true end
  end
  return false
end

--- true si el texto aparece en el id, en el nombre visible o en un encantamiento.
--- El namespace se ignora salvo que lo escribas: si no, buscar "in" o "raf"
--- matchearia "minecraft:" y por lo tanto todo el inventario.
function items.matches(key, filter)
  if filter == nil or filter == "" then return true end
  filter = filter:lower()
  if filter:sub(1, 1) == "#" then
    local tag = filter:sub(2)
    return tag == "" or matchesTag(key, tag)
  end
  local id = filter:find(":", 1, true) and key or (key:match("^.-:(.*)$") or key)
  if id:lower():find(filter, 1, true) then return true end
  local m = meta[key]
  if m and m.displayName:lower():find(filter, 1, true) then return true end
  return matchesEnchant(key, filter)
end

--- 1234 -> "1234 (19x64)" para leer cantidades grandes de un vistazo.
function items.formatCount(count, key)
  local max = items.maxCount(key)
  if max <= 1 or count < max then return tostring(count) end
  local stacks = math.floor(count / max)
  local rest = count % max
  if rest == 0 then return ("%d (%dx%d)"):format(count, stacks, max) end
  return ("%d (%dx%d+%d)"):format(count, stacks, max, rest)
end

--- Solo para tests: vacia el cache.
function items.reset()
  meta = {}
end

return items
