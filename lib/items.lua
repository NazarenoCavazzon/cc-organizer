-- Claves de item y cache de metadatos.
--
-- `list()` solo devuelve name/count/nbt. `getItemDetail()` trae displayName y
-- maxCount pero es caro, asi que se consulta una sola vez por clave y se cachea.

local items = {}

local meta = {}

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
  meta[key] = {
    displayName = detail.displayName or detail.name,
    maxCount = detail.maxCount or 64,
    tags = tags,
  }
end

--- Tags del item, o lista vacia si todavia no tenemos metadata.
function items.tags(key)
  local m = meta[key]
  return m and m.tags or {}
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

--- true si el texto aparece en el id o en el nombre visible.
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
  return m ~= nil and m.displayName:lower():find(filter, 1, true) ~= nil
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
