-- Tests de la TUI: se dibuja en una terminal falsa y se le mandan eventos.

local mock = require("tests.mock_peripheral")
local mterm = require("tests.mock_term")
local h = require("tests.harness")

local eq, check, test = h.eq, h.check, h.test

local IN, OUT = "minecraft:chest_in", "minecraft:chest_out"

--- Mundo + storage + ui limpios, con `stock` ya guardado en la red.
local function setup(stock, outSize, termOpts)
  mock.reset({
    { name = IN, size = 27 },
    { name = OUT, size = outSize or 27 },
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  mterm.reset(termOpts)

  for _, mod in ipairs({ "lib.storage", "lib.items", "lib.ui", "lib.draw", "lib.dialog" }) do
    package.loaded[mod] = nil
  end
  local items = require("lib.items")
  items.reset()
  local storage = require("lib.storage")
  local ui = require("lib.ui")

  local cfg = { input = IN, output = OUT, ignore = {} }
  storage.init(cfg)
  storage.refresh()

  -- De a uno: el cofre de entrada tiene 27 slots y algun test usa 40 items.
  -- Ordenado para que el resultado no dependa del orden de pairs.
  local names = {}
  for name in pairs(stock or {}) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    mock.give(IN, name, stock[name])
    storage.store()
  end
  storage.refresh()
  return storage, ui, cfg
end

test("la lista muestra el stock con nombres legibles", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 200,
    ["minecraft:oak_log"] = 64,
  })
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("Cobblestone", 1, true) ~= nil, "la lista muestra Cobblestone")
  check(frame:find("Oak Log", 1, true) ~= nil, "la lista muestra Oak Log")
  check(frame:find("200", 1, true) ~= nil, "la lista muestra la cantidad")
  check(frame:find("cc%-organizer") ~= nil, "hay barra de titulo")
  check(frame:find("5/54 slots", 1, true) ~= nil, "el titulo muestra la ocupacion")
  check(frame:find("2 tipos", 1, true) ~= nil, "el titulo cuenta los tipos de item")
end)

test("escribir filtra la lista en vivo", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 200,
    ["minecraft:oak_log"] = 64,
  })
  mterm.type("oak")
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("Oak Log", 1, true) ~= nil, "queda el que matchea")
  check(frame:find("Cobblestone", 1, true) == nil, "se va el que no matchea")
  check(frame:find("buscar: oak", 1, true) ~= nil, "se ve lo que escribiste")
  check(frame:find("1/2 tipos", 1, true) ~= nil, "el titulo cuenta filtrados sobre el total")
end)

test("backspace y escape limpian la busqueda", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 200 })
  mterm.type("zzz")
  mterm.key(mterm.KEYS.backspace)
  mterm.key(mterm.KEYS.escape)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("buscar: _", 1, true) ~= nil, "la busqueda quedo vacia")
  check(frame:find("Cobblestone", 1, true) ~= nil, "volvio a aparecer el stock")
end)

test("enter pide la cantidad y entrega al cofre de salida", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 200 })
  mterm.key(mterm.KEYS.enter)
  mterm.type("10") -- reemplaza el valor sugerido
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 10, "llegaron al cofre de salida")
  eq(storage.count("minecraft:cobblestone"), 190, "bajo el stock")
  check(mterm.lastFrame():find("10 Cobblestone", 1, true) ~= nil, "confirma en el mensaje")
end)

test("la cantidad por defecto es un stack", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 200 })
  mterm.key(mterm.KEYS.enter) -- abre el dialogo
  mterm.key(mterm.KEYS.enter) -- acepta el stack sugerido
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 64, "entrego un stack")
end)

test("las flechas cambian el item seleccionado", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 300,
    ["minecraft:oak_log"] = 64,
  })
  -- La lista viene ordenada por cantidad: cobblestone primero.
  mterm.key(mterm.KEYS.down)
  mterm.key(mterm.KEYS.enter)
  mterm.type("5")
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:oak_log"), 5, "entrego el segundo de la lista")
  eq(mock.count(OUT, "minecraft:cobblestone"), 0, "no toco el primero")
end)

test("click derecho pide todo el stock", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 150 })
  mterm.click(2, 5, 3) -- primera fila de la lista
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 150, "entrego todo")
  eq(storage.count("minecraft:cobblestone"), 0, "no quedo stock")
end)

test("avisa cuando el cofre de salida no da abasto", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 }, 1)
  mterm.click(2, 5, 3)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 64, "entro un solo stack")
  check(mterm.lastFrame():find("cofre de salida lleno", 1, true) ~= nil, "lo explica en pantalla")
end)

test("F2 ordena por nombre", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 300,
    ["minecraft:andesite"] = 10,
  })
  mterm.key(mterm.KEYS.f2)
  mterm.key(mterm.KEYS.home) -- F2 mantiene el item seleccionado, no la posicion
  mterm.key(mterm.KEYS.enter)
  mterm.type("3")
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:andesite"), 3, "primero el alfabeticamente menor")
  check(mterm.lastFrame():find("A%-Z") ~= nil, "muestra el modo de orden")
end)

test("F1 abre la ayuda y vuelve", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 64 })
  mterm.key(mterm.KEYS.f1)
  mterm.key(mterm.KEYS.enter) -- cierra el overlay
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("atajos"), "se dibujo la ayuda")
  check(mterm.lastFrame():find("Cobblestone", 1, true) ~= nil, "volvio a la lista")
end)

test("el dialogo acepta cuentas como 64*2+16", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.type("64*2+16")
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 144, "resolvio la cuenta")
end)

test("el dialogo no deja pedir una cantidad invalida", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.type("0")
  mterm.key(mterm.KEYS.enter) -- rechazado, el dialogo sigue abierto
  mterm.type("8")
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("cantidad invalida"), "avisa en el dialogo")
  eq(mock.count(OUT, "minecraft:cobblestone"), 8, "despues acepta el valor bueno")
end)

test("el dialogo recorta al stock disponible", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 20 })
  mterm.key(mterm.KEYS.enter)
  mterm.type("9999")
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 20, "no pide mas de lo que hay")
end)

test("ctrl+d cancela el pedido sin mover nada", function()
  -- El escape no sirve: en CC cierra la GUI antes de llegar al programa.
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.leftCtrl)
  mterm.key(mterm.KEYS.d)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("ctrl+d cancela"), "el dialogo lo dice")
  eq(mock.count(OUT, "minecraft:cobblestone"), 0, "no entrego nada")
  eq(storage.count("minecraft:cobblestone"), 300, "el stock quedo igual")
end)

-- Coordenadas del dialogo con dos lineas de info: caja de 38 de ancho centrada
-- en x=7, con los presets en la fila 9 y pedir/cancelar en la 10. Si un click
-- no cae en su boton el dialogo queda abierto, se come el F10 y el test explota
-- al vaciarse la cola de eventos, asi que son coordenadas verificadas.
local PRESET_16 = { x = 13, y = 9 }
local BOTON_PEDIR = { x = 29, y = 10 }
local BOTON_CANCELAR = { x = 38, y = 10 }

test("el boton cancelar del dialogo tambien cierra", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.click(1, BOTON_CANCELAR.x, BOTON_CANCELAR.y)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 0, "no entrego nada")
end)

test("clickear una cantidad la escribe pero no manda nada", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.click(1, PRESET_16.x, PRESET_16.y)  -- boton "16"
  mterm.key(mterm.KEYS.f10)                 -- el dialogo sigue abierto: lo ignora
  mterm.key(mterm.KEYS.leftCtrl)
  mterm.key(mterm.KEYS.d)                   -- cancela
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("cantidad: 16_"), "el click lleno el campo")
  eq(mock.count(OUT, "minecraft:cobblestone"), 0, "pero no entrego nada sin confirmar")
end)

test("el boton pedir confirma la cantidad clickeada", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.click(1, PRESET_16.x, PRESET_16.y)
  mterm.click(1, BOTON_PEDIR.x, BOTON_PEDIR.y)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 16, "recien ahi mando los items")
end)

test("enter tambien confirma lo que clickeaste", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.click(1, PRESET_16.x, PRESET_16.y)
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 16, "mismo resultado por teclado")
end)

test("ctrl+d cancela el dialogo sin cerrar el programa", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.leftCtrl)
  mterm.key(mterm.KEYS.d)       -- cancela el dialogo, sigue en la lista
  mterm.type("cob")             -- y la lista responde al teclado
  mterm.key(mterm.KEYS.leftCtrl)
  mterm.key(mterm.KEYS.d)       -- recien ahora sale
  ui.run(storage, cfg)

  check(mterm.lastFrame():find("buscar: cob", 1, true) ~= nil, "seguia en la lista")
end)

test("tab muestra el sprite y donde esta guardado el item", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.tab)
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("300 unidades"), "dice cuanto hay")
  check(mterm.anyFrame("apila de a 64"), "dice cuanto apila")
  check(mterm.anyFrame("minecraft:chest_0"), "y en cuales")

  -- El sprite se dibuja con los caracteres de bloque 128..159.
  local drew = false
  for _, frame in ipairs(mterm.frames) do
    if frame:find("300 unidades", 1, true) then
      for i = 1, #frame do
        local byte = frame:byte(i)
        if byte >= 128 and byte <= 159 then drew = true break end
      end
    end
  end
  check(drew, "hay pixeles de sprite en la pantalla del detalle")
end)

--- Dos picos de diamante con distinto desgaste, que es el caso que no se podia
--- distinguir en la lista.
--- `onlyWorn` deja un solo pico, para que la seleccion no dependa del orden.
local function setupTools(onlyWorn)
  local storage, ui, cfg = setup({})
  mock.setDetail("gastado", {
    damage = 1000, maxDamage = 1561,
    enchantments = { { name = "minecraft:efficiency", level = 5 } },
  })
  mock.setDetail("nuevo", { damage = 0, maxDamage = 1561 })
  mock.give(IN, "minecraft:diamond_pickaxe", 1, "gastado")
  if not onlyWorn then mock.give(IN, "minecraft:diamond_pickaxe", 1, "nuevo") end
  mock.give(IN, "minecraft:cobblestone", 64)
  storage.store()
  storage.refresh()
  return storage, ui, cfg
end

test("la lista muestra la durabilidad y marca lo encantado", function()
  local storage, ui, cfg = setupTools()
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  local worn = frame:match("Diamond Pickaxe%s+%*36%%")
  local new = frame:match("Diamond Pickaxe%s+100%%")
  check(worn ~= nil, "el pico gastado muestra 36% y el asterisco de encantado")
  check(new ~= nil, "el pico entero muestra 100% y sin asterisco")

  -- Y el bloque, que no se gasta, no gana ningun badge.
  for line in frame:gmatch("[^\n]+") do
    if line:find("Cobblestone", 1, true) then
      check(line:find("%%") == nil, "un bloque no muestra durabilidad")
    end
  end
end)

test("el detalle de una herramienta muestra desgaste y encantamientos", function()
  local storage, ui, cfg = setupTools(true)
  mterm.type("pick")
  mterm.key(mterm.KEYS.tab)
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("durabilidad"), "dice la durabilidad")
  check(mterm.anyFrame("quedan 561 de 1561 usos"), "y los usos que quedan")
  check(mterm.anyFrame("encantamientos:"), "lista los encantamientos")
  check(mterm.anyFrame("Efficiency V"), "con nombre y nivel")
  local bar = false
  for _, frame in ipairs(mterm.frames) do
    if frame:find("%[#+%-+%]") then bar = true end
  end
  check(bar, "dibuja la barra de desgaste")
end)

test("se puede buscar por encantamiento", function()
  local storage, ui, cfg = setupTools()
  mterm.type("efficiency")
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("1/3 tipos", 1, true) ~= nil, "queda un solo item de los tres")
  check(frame:find("Diamond Pickaxe", 1, true) ~= nil, "el pico encantado")
end)

test("ctrl+u limpia la busqueda", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 200,
    ["minecraft:oak_log"] = 64,
  })
  mterm.type("oak")
  mterm.key(mterm.KEYS.leftCtrl)
  mterm.key(mterm.KEYS.u)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("buscar: _", 1, true) ~= nil, "la busqueda quedo vacia")
  check(frame:find("Cobblestone", 1, true) ~= nil, "volvio todo el stock")
end)

test("ctrl+d sale", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 64 })
  mterm.key(mterm.KEYS.leftCtrl)
  mterm.key(mterm.KEYS.d)
  ui.run(storage, cfg) -- si no sale, la cola de eventos se vacia y falla
  eq(ui.reconfigure, false, "salio sin pedir reconfigurar")
end)

test("click en el orden alterna cantidad / alfabetico", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 300,
    ["minecraft:andesite"] = 10,
  })
  mterm.click(1, 48, 2) -- el boton [cant] vive arriba a la derecha
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.lastFrame():find("%[A%-Z%]") ~= nil, "quedo en orden alfabetico")
end)

test("anda en una computadora normal (sin color ni mouse)", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 300,
    ["minecraft:oak_log"] = 64,
  }, nil, { colour = false })

  mterm.type("oak")
  mterm.key(mterm.KEYS.enter)  -- dialogo de cantidad
  mterm.type("a")              -- "todo" sin mouse
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f1)     -- overlay de ayuda
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:oak_log"), 64, "la tecla a pidio todo el stock")
  check(mterm.lastFrame():find("Oak Log", 1, true) ~= nil, "la lista se dibujo igual")
end)

test("la tecla a pide todo el stock disponible", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 150 })
  mterm.key(mterm.KEYS.enter)
  mterm.type("a")
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 150, "entrego todo")
end)

test("las flechas cambian de categoria", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 300,   -- bloque
    ["minecraft:iron_ingot"] = 64,     -- material
    ["minecraft:diamond_pickaxe"] = 1, -- herramienta
  })
  mterm.key(mterm.KEYS.right)  -- recientes
  mterm.key(mterm.KEYS.right)  -- bloques
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("<bloques>", 1, true) ~= nil, "muestra la categoria")
  check(frame:find("Cobblestone", 1, true) ~= nil, "deja los bloques")
  check(frame:find("Iron Ingot", 1, true) == nil, "y saca lo que no es bloque")
end)

test("la categoria recientes junta lo ultimo pedido", function()
  local storage, ui, cfg = setup({
    ["minecraft:cobblestone"] = 300,
    ["minecraft:oak_log"] = 64,
  })
  mterm.type("oak")            -- selecciona Oak Log
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.enter)  -- confirma el stack sugerido
  mterm.key(mterm.KEYS.leftCtrl)
  mterm.key(mterm.KEYS.u)      -- limpia la busqueda
  mterm.key(mterm.KEYS.right)  -- categoria recientes
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("<recientes>", 1, true) ~= nil, "esta en recientes")
  check(frame:find("Oak Log", 1, true) ~= nil, "aparece lo pedido")
  check(frame:find("Cobblestone", 1, true) == nil, "y nada mas")
end)

test("F4 repite el ultimo pedido", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  mterm.type("10")
  mterm.key(mterm.KEYS.enter)  -- pide 10
  mterm.key(mterm.KEYS.f4)     -- repite: dialogo con 10 ya escrito
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 20, "pidio 10 dos veces")
end)

test("F4 sin pedidos previos no rompe", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.f4)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.lastFrame():find("todavia no pediste nada", 1, true) ~= nil, "lo avisa")
end)

test("buscar por tag filtra la lista", function()
  local storage, ui, cfg = setup({
    ["minecraft:oak_log"] = 64,
    ["minecraft:iron_ingot"] = 64,
  })
  mterm.type("#logs")
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("Oak Log", 1, true) ~= nil, "queda la madera")
  check(frame:find("Iron Ingot", 1, true) == nil, "se va el lingote")
end)

test("F3 muestra el diagnostico del armado", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 64 })
  mterm.key(mterm.KEYS.f3)
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("diagnostico"), "se dibujo el diagnostico")
  check(mterm.anyFrame("minecraft:chest_0"), "lista los cofres con su ocupacion")
end)

test("F9 sale pidiendo reconfigurar", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 64 })
  mterm.key(mterm.KEYS.f9)
  ui.run(storage, cfg)
  eq(ui.reconfigure, true, "avisa que hay que reconfigurar")
end)

test("los avisos del guardado automatico aparecen en pantalla", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 64 })
  ui.notify("guardados 12 items")
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.lastFrame():find("guardados 12 items", 1, true) ~= nil, "se ve el aviso")
end)

test("la lista larga scrollea sin romperse", function()
  local stock = {}
  for i = 1, 40 do stock["minecraft:item_" .. string.format("%02d", i)] = i end
  local storage, ui, cfg = setup(stock)

  mterm.scroll(1)
  mterm.key(mterm.KEYS.pageDown)
  mterm.key(mterm.KEYS["end"])
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  local frame = mterm.lastFrame()
  check(frame:find("Item 01", 1, true) ~= nil, "el final de la lista es visible")
  eq(#storage.stock(), 40, "estan los 40 tipos")
end)
