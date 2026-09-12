-- Tests de la logica de almacenamiento contra el mock de peripherals.
-- Correr desde la raiz del repo:  lua tests/run.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local mock = require("tests.mock_peripheral")
local h = require("tests.harness")

local IN, OUT = "minecraft:chest_in", "minecraft:chest_out"

local eq, check, test = h.eq, h.check, h.test

--- Arma un mundo nuevo y devuelve un storage limpio.
local function setup(chestSpec, config)
  local spec = { { name = IN, size = 27 }, { name = OUT, size = 27 } }
  for _, c in ipairs(chestSpec) do spec[#spec + 1] = c end
  mock.reset(spec)

  package.loaded["lib.storage"] = nil
  package.loaded["lib.items"] = nil
  local items = require("lib.items")
  items.reset()
  local storage = require("lib.storage")

  local cfg = config or { input = IN, output = OUT, ignore = {} }
  storage.init(cfg)
  storage.refresh()
  return storage, items
end

test("descubre los cofres y excluye entrada/salida", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  local s = storage.space()
  eq(s.chests, 2, "cofres de almacenamiento")
  eq(s.slots, 54, "slots totales")
  eq(s.used, 0, "slots usados")
end)

test("guarda todo lo que hay en el cofre de entrada", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  mock.give(IN, "minecraft:cobblestone", 200)
  mock.give(IN, "minecraft:oak_log", 30)

  local moved, left = storage.store()
  eq(moved, 230, "items movidos")
  eq(left, 0, "sobrantes")
  eq(mock.usedSlots(IN), 0, "el cofre de entrada quedo vacio")
  eq(storage.count("minecraft:cobblestone"), 200, "stock de cobblestone")
  eq(storage.count("minecraft:oak_log"), 30, "stock de oak_log")
end)

test("completa stacks parciales antes de ocupar slots nuevos", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  -- chest_1 ya tiene un stack a medias; ahi tiene que ir lo nuevo.
  mock.give("minecraft:chest_1", "minecraft:cobblestone", 40)
  storage.refresh()
  mock.give(IN, "minecraft:cobblestone", 20)

  local moved = storage.store()
  eq(moved, 20, "items movidos")
  eq(mock.count("minecraft:chest_1", "minecraft:cobblestone"), 60, "quedaron juntos en chest_1")
  eq(mock.count("minecraft:chest_0", "minecraft:cobblestone"), 0, "chest_0 sigue vacio")
  eq(storage.count("minecraft:cobblestone"), 60, "stock total")
end)

test("items con NBT distinto son claves distintas", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.give(IN, "minecraft:diamond_sword", 1, "aaa")
  mock.give(IN, "minecraft:diamond_sword", 1, "bbb")

  local moved = storage.store()
  eq(moved, 2, "items movidos")
  eq(storage.count("minecraft:diamond_sword@aaa"), 1, "espada aaa")
  eq(storage.count("minecraft:diamond_sword@bbb"), 1, "espada bbb")
  eq(#storage.stock("diamond_sword"), 2, "entradas separadas en el stock")
end)

test("respeta el maxCount de items que no apilan a 64", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 2 } })
  mock.give(IN, "minecraft:ender_pearl", 40)

  local moved, left = storage.store()
  eq(moved, 32, "entran 2 slots x 16")
  eq(left, 8, "el resto queda en la entrada")
  eq(mock.count(IN, "minecraft:ender_pearl"), 8, "sobrante en el cofre de entrada")
end)

test("avisa cuando el almacenamiento esta lleno", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 1 } })
  mock.give(IN, "minecraft:cobblestone", 100)

  local moved, left, err = storage.store()
  eq(moved, 64, "solo entra un stack")
  eq(left, 36, "sobrantes")
  eq(err, "almacenamiento lleno", "motivo")
  eq(storage.count("minecraft:cobblestone"), 64, "stock indexado")
end)

test("entrega items al cofre de salida y actualiza el indice", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  mock.give(IN, "minecraft:cobblestone", 300)
  storage.store()

  local moved, reason = storage.take("minecraft:cobblestone", 200)
  eq(moved, 200, "entregados")
  eq(reason, nil, "sin motivo de error")
  eq(mock.count(OUT, "minecraft:cobblestone"), 200, "llegaron al cofre de salida")
  eq(storage.count("minecraft:cobblestone"), 100, "stock restante")
end)

test("entrega parcial cuando no alcanza el stock", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.give(IN, "minecraft:cobblestone", 50)
  storage.store()

  local moved, reason = storage.take("minecraft:cobblestone", 200)
  eq(moved, 50, "entregados")
  eq(reason, "no hay mas stock", "motivo")
  eq(storage.count("minecraft:cobblestone"), 0, "stock vacio")
end)

test("detecta el cofre de salida lleno", function()
  mock.reset({
    { name = IN, size = 27 },
    { name = OUT, size = 1 },
    { name = "minecraft:chest_0", size = 27 },
  })
  package.loaded["lib.storage"] = nil
  package.loaded["lib.items"] = nil
  require("lib.items").reset()
  local storage = require("lib.storage")
  storage.init({ input = IN, output = OUT, ignore = {} })
  storage.refresh()

  mock.give(IN, "minecraft:cobblestone", 200)
  storage.store()

  local moved, reason = storage.take("minecraft:cobblestone", 200)
  eq(moved, 64, "solo entra un stack en la salida")
  eq(reason, "cofre de salida lleno", "motivo")
  eq(storage.count("minecraft:cobblestone"), 136, "el resto sigue guardado")
end)

test("pedir algo que no existe no rompe", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  local moved, reason = storage.take("minecraft:netherite_ingot", 1)
  eq(moved, 0, "no entrego nada")
  eq(reason, "no hay stock", "motivo")
end)

test("stock ordenado por cantidad y filtrable", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.give(IN, "minecraft:cobblestone", 300)
  mock.give(IN, "minecraft:oak_log", 64)
  mock.give(IN, "minecraft:diamond", 5)
  storage.store()

  local list = storage.stock()
  eq(#list, 3, "tipos de item")
  eq(list[1].key, "minecraft:cobblestone", "primero el mas abundante")
  eq(list[3].key, "minecraft:diamond", "ultimo el menos abundante")
  eq(list[1].display, "Cobblestone", "displayName cacheado")

  eq(#storage.stock("oak"), 1, "filtro por id")
  eq(#storage.stock("Diamond"), 1, "filtro case-insensitive por displayName")
  eq(#storage.findKeys("minecraft:diamond"), 1, "match exacto")
  eq(#storage.stock("in"), 0, "el namespace no cuenta: 'in' no matchea minecraft:")
  eq(#storage.stock("minecraft:oak"), 1, "pero si lo escribis completo, si")
end)

test("el indice sobrevive a un cofre que desaparece", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  mock.give(IN, "minecraft:cobblestone", 100)
  storage.store()
  eq(storage.count("minecraft:cobblestone"), 100, "stock inicial")

  -- Los 100 se repartieron: un stack lleno en chest_0 y el resto en chest_1.
  eq(mock.count("minecraft:chest_0", "minecraft:cobblestone"), 64, "stack lleno en chest_0")

  -- Alguien rompe chest_0: se rearma la red sin el.
  mock.reset({
    { name = IN, size = 27 },
    { name = OUT, size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  storage.refresh()
  eq(storage.space().chests, 1, "queda un solo cofre")
  eq(storage.count("minecraft:cobblestone"), 36, "el stock refleja solo lo que sigue en la red")
end)

test("avisa que no hay cofres de almacenamiento", function()
  local storage = setup({})
  mock.give(IN, "minecraft:cobblestone", 64)
  local moved, left, err = storage.store()
  eq(moved, 0, "no movio nada")
  eq(left, 64, "quedo todo en la entrada")
  eq(err, "no hay cofres de almacenamiento en la red", "el motivo es claro")
  eq(#storage.diagnose().problems, 1, "el diagnostico lo reporta")
end)

test("detecta el cofre de entrada pegado a la computadora", function()
  -- "top" = pegado a la computadora, no en la red de cables: ningun cofre
  -- puede sacarle items.
  mock.reset({
    { name = "top", size = 27 },
    { name = OUT, size = 27 },
    { name = "minecraft:chest_0", size = 27 },
  })
  package.loaded["lib.storage"] = nil
  package.loaded["lib.items"] = nil
  require("lib.items").reset()
  local storage = require("lib.storage")
  storage.init({ input = "top", output = OUT, ignore = {} })
  storage.refresh()

  mock.give("top", "minecraft:cobblestone", 64)
  local moved, left, err = storage.store()
  eq(moved, 0, "no pudo mover nada")
  eq(left, 64, "quedo todo en la entrada")
  eq(err, "el cofre de entrada no esta en la red de cables (F3)", "el motivo es el real")

  local problems = table.concat(storage.diagnose().problems, " | ")
  check(problems:find("pegado a la computadora", 1, true) ~= nil,
    "el diagnostico explica el problema: " .. problems)
end)

test("detecta cofres en otra red de cables", function()
  -- El cofre esta en la red del jugador pero colgado de otro modem suelto:
  -- la computadora lo ve, pero el cofre de entrada no lo alcanza.
  mock.reset({
    { name = IN, size = 27 },
    { name = OUT, size = 27 },
    { name = "minecraft:chest_0", size = 27, network = "otra" },
  })
  package.loaded["lib.storage"] = nil
  package.loaded["lib.items"] = nil
  require("lib.items").reset()
  local storage = require("lib.storage")
  storage.init({ input = IN, output = OUT, ignore = {} })
  storage.refresh()

  eq(storage.space().chests, 1, "la computadora igual lo ve")
  mock.give(IN, "minecraft:cobblestone", 155)

  local moved, left, err = storage.store()
  eq(moved, 0, "no puede mover nada")
  eq(left, 155, "queda todo en la entrada")
  check(err:find("does not exist", 1, true) ~= nil, "propaga el error del juego: " .. tostring(err))

  local report = storage.diagnose()
  eq(report.unreachable, 1, "el diagnostico cuenta el cofre inalcanzable")
  eq(report.chests[1].reachable, false, "y lo marca en la lista")
  local problems = table.concat(report.problems, " | ")
  check(problems:find("OTRA red de cables", 1, true) ~= nil, "lo explica: " .. problems)
end)

test("reporta el error real de un cofre que rechaza el movimiento", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.chest("minecraft:chest_0").pullItems = function() error("Inventory is locked", 0) end
  mock.give(IN, "minecraft:cobblestone", 64)

  local moved, left, err = storage.store()
  eq(moved, 0, "no movio nada")
  eq(err, "Inventory is locked", "propaga el error del cofre en vez de inventar")
end)

test("el diagnostico distingue lleno de verdad", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 1 } })
  mock.give(IN, "minecraft:cobblestone", 200)
  storage.store()

  local problems = table.concat(storage.diagnose().problems, " | ")
  check(problems:find("llenos de verdad", 1, true) ~= nil, "avisa que si esta lleno: " .. problems)
end)

test("filtra por tag del juego con #", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.give(IN, "minecraft:oak_log", 64)
  mock.give(IN, "minecraft:spruce_log", 64)
  mock.give(IN, "minecraft:iron_ingot", 64)
  mock.give(IN, "minecraft:cobblestone", 64)
  storage.store()

  eq(#storage.stock("#logs"), 2, "las dos maderas")
  eq(#storage.stock("#ingots"), 1, "el lingote, aunque el tag sea de otro namespace")
  eq(#storage.stock("#oak_logs"), 1, "tag mas especifico")
  eq(#storage.stock("#nada"), 0, "tag que no existe")
  eq(#storage.stock("log"), 2, "sin # sigue siendo busqueda por nombre")
end)

--- Los stacks de un item que hay en un cofre, de mayor a menor.
local function stacksIn(chest, name)
  local out = {}
  for _, it in pairs(mock.chest(chest).__slots) do
    if it.name == name then out[#out + 1] = it.count end
  end
  table.sort(out, function(a, b) return a > b end)
  return out
end

--- Todos los stacks de un item en la red, de mayor a menor.
local function stacksEverywhere(chests, name)
  local out = {}
  for _, chest in ipairs(chests) do
    for _, count in ipairs(stacksIn(chest, name)) do out[#out + 1] = count end
  end
  table.sort(out, function(a, b) return a > b end)
  return table.concat(out, " ")
end

test("llena los stacks parciales de todos los cofres antes de abrir uno nuevo", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  -- Un parcial en cada cofre: 24 y 14 de hueco.
  mock.give("minecraft:chest_0", "minecraft:cobblestone", 40)
  mock.give("minecraft:chest_1", "minecraft:cobblestone", 50)
  storage.refresh()

  mock.give(IN, "minecraft:cobblestone", 64)
  local moved, left = storage.store()
  eq(moved, 64, "guardo todo")
  eq(left, 0, "no quedo nada en la entrada")

  -- El bug era este: el stack entero se iba al cofre con mas hueco parcial y el
  -- resto se comia un slot vacio de ahi, dejando el otro parcial sin tocar.
  eq(stacksEverywhere({ "minecraft:chest_0", "minecraft:chest_1" }, "minecraft:cobblestone"),
     "64 64 26", "dos stacks completos y uno solo parcial")
end)

test("saca primero de los stacks mas chicos para liberar slots", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  local c = mock.chest("minecraft:chest_0")
  c.__slots[1] = { name = "minecraft:cobblestone", count = 64 }
  c.__slots[2] = { name = "minecraft:cobblestone", count = 10 }
  c.__slots[3] = { name = "minecraft:cobblestone", count = 5 }
  storage.refresh()
  eq(storage.space().used, 3, "arranca con tres slots")

  eq(storage.take("minecraft:cobblestone", 15), 15, "entrego lo pedido")
  eq(table.concat(stacksIn("minecraft:chest_0", "minecraft:cobblestone"), " "), "64",
     "vacio los dos parciales en vez de morder el stack lleno")
  eq(storage.space().used, 1, "y quedan dos slots libres")
end)

test("compactar junta los parciales y libera slots", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
    { name = "minecraft:chest_2", size = 27 },
  })
  mock.give("minecraft:chest_0", "minecraft:cobblestone", 30)
  mock.give("minecraft:chest_1", "minecraft:cobblestone", 20)
  mock.give("minecraft:chest_2", "minecraft:cobblestone", 10)
  storage.refresh()

  local frags, recoverable = storage.fragments()
  eq(recoverable, 2, "60 unidades en tres slots: sobran dos")
  eq(frags[1].key, "minecraft:cobblestone", "y dice de que item")
  eq(frags[1].stacks, 3, "cuantos parciales hay")

  local freed, moves, err = storage.compact()
  eq(err, nil, "sin errores")
  eq(freed, 2, "libero dos slots")
  eq(moves, 2, "en dos movimientos")
  eq(storage.space().used, 1, "todo junto en un slot")
  eq(storage.count("minecraft:cobblestone"), 60, "sin perder items")
  eq(select(2, storage.fragments()), 0, "ya no hay nada para juntar")
end)

test("compactar tambien junta dos parciales del mismo cofre", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  local c = mock.chest("minecraft:chest_0")
  c.__slots[1] = { name = "minecraft:cobblestone", count = 40 }
  c.__slots[2] = { name = "minecraft:cobblestone", count = 12 }
  storage.refresh()

  local freed, moves, err = storage.compact()
  eq(err, nil, "un cofre puede moverse items a si mismo")
  eq(freed, 1, "libero el slot")
  eq(moves, 1, "un movimiento")
  eq(table.concat(stacksIn("minecraft:chest_0", "minecraft:cobblestone"), " "), "52", "un solo stack")
end)

test("guardar junta los parciales que quedaron de antes", function()
  local storage = setup({
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  mock.give("minecraft:chest_0", "minecraft:cobblestone", 30)
  mock.give("minecraft:chest_1", "minecraft:cobblestone", 20)
  storage.refresh()

  mock.give(IN, "minecraft:cobblestone", 1)
  eq(storage.store(), 1, "guardo el item")
  eq(storage.space().used, 1, "y de paso junto los dos parciales viejos")
  eq(storage.count("minecraft:cobblestone"), 51, "sin perder nada")
  eq(storage.compactError, nil, "sin errores al juntar")
end)

test("compactar no toca items que no apilan", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.give("minecraft:chest_0", "minecraft:diamond_sword", 1, "a")
  mock.give("minecraft:chest_0", "minecraft:diamond_sword", 1, "b")
  storage.refresh()
  eq(select(2, storage.fragments()), 0, "dos espadas distintas no son un parcial")
  local freed, moves = storage.compact()
  eq(freed, 0, "no libera nada")
  eq(moves, 0, "ni intenta moverlas")
  eq(storage.space().used, 2, "siguen en sus slots")
end)

test("avisa cuando el mismo item tiene varias variantes de NBT", function()
  local storage = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.give(IN, "minecraft:diamond_pickaxe", 1, "a")
  mock.give(IN, "minecraft:diamond_pickaxe", 1, "b")
  mock.give(IN, "minecraft:cobblestone", 64)
  storage.store()

  eq(#storage.variants("minecraft:diamond_pickaxe@a"), 2, "dos variantes del pico")
  eq(#storage.variants("minecraft:cobblestone"), 1, "el bloque es uno solo")
end)

test("guarda durabilidad y encantamientos de las herramientas", function()
  local storage, items = setup({ { name = "minecraft:chest_0", size = 27 } })
  -- Dos picos de diamante identicos de nombre: en el juego solo los distingue
  -- el nbt, y para el jugador, el desgaste y los encantamientos.
  mock.setDetail("gastado", {
    damage = 1000, maxDamage = 1561,
    enchantments = {
      { name = "minecraft:efficiency", level = 5 },
      { name = "minecraft:unbreaking", level = 3, displayName = "Unbreaking III" },
    },
  })
  mock.setDetail("nuevo", { damage = 0, maxDamage = 1561 })
  mock.give(IN, "minecraft:diamond_pickaxe", 1, "gastado")
  mock.give(IN, "minecraft:diamond_pickaxe", 1, "nuevo")
  mock.give(IN, "minecraft:cobblestone", 64)
  storage.store()

  local worn = items.wear("minecraft:diamond_pickaxe@gastado")
  check(worn ~= nil, "la herramienta gastada tiene desgaste")
  eq(worn.percent, 36, "quedan 561 de 1561 usos")
  eq(worn.left, 561, "usos restantes")
  eq(items.wear("minecraft:diamond_pickaxe@nuevo").percent, 100, "el pico nuevo esta entero")
  eq(items.wear("minecraft:cobblestone"), nil, "un bloque no se gasta")

  local ench = items.enchantments("minecraft:diamond_pickaxe@gastado")
  eq(#ench, 2, "dos encantamientos")
  eq(ench[1], "Efficiency V", "arma el nombre con el nivel en romano")
  eq(ench[2], "Unbreaking III", "y respeta el displayName si viene")
  check(not items.isEnchanted("minecraft:diamond_pickaxe@nuevo"), "el nuevo no tiene")

  eq(#storage.stock("efficiency"), 1, "se puede buscar por encantamiento")
  eq(#storage.stock("pickaxe"), 2, "y por nombre siguen siendo dos")
end)

test("la durabilidad tambien sale de durability cuando no hay damage", function()
  local storage, items = setup({ { name = "minecraft:chest_0", size = 27 } })
  mock.setDetail("raro", { durability = 0.25, maxDamage = 200 })
  mock.setDetail("irr", { durability = 1, maxDamage = 100, unbreakable = true })
  mock.give(IN, "minecraft:diamond_axe", 1, "raro")
  mock.give(IN, "minecraft:diamond_axe", 1, "irr")
  storage.store()

  eq(items.wear("minecraft:diamond_axe@raro").percent, 25, "usa la fraccion que trae el juego")
  eq(items.wear("minecraft:diamond_axe@raro").left, 50, "50 de 200 usos")
  check(items.wear("minecraft:diamond_axe@irr").unbreakable, "marca lo irrompible")
  eq(items.bar(0.5, 10), "#####-----", "la barra de desgaste es ascii")
  eq(items.bar(0, 4), "----", "vacia")
  eq(items.bar(1, 4), "####", "llena")
end)

require("tests.icons")
require("tests.monitor")
require("tests.tui")

os.exit(h.summary() and 0 or 1)  -- 5.1 acepta el booleano como codigo 0/1
