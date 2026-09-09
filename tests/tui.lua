-- Tests de la TUI: se dibuja en una terminal falsa y se le mandan eventos.

local mock = require("tests.mock_peripheral")
local mterm = require("tests.mock_term")
local h = require("tests.harness")

local eq, check, test = h.eq, h.check, h.test

local IN, OUT = "minecraft:chest_in", "minecraft:chest_out"

--- Mundo + storage + ui limpios, con `stock` ya guardado en la red.
local function setup(stock, outSize)
  mock.reset({
    { name = IN, size = 27 },
    { name = OUT, size = outSize or 27 },
    { name = "minecraft:chest_0", size = 27 },
    { name = "minecraft:chest_1", size = 27 },
  })
  mterm.reset()

  for _, mod in ipairs({ "lib.storage", "lib.items", "lib.ui" }) do package.loaded[mod] = nil end
  local items = require("lib.items")
  items.reset()
  local storage = require("lib.storage")
  local ui = require("lib.ui")

  local cfg = { input = IN, output = OUT, ignore = {} }
  storage.init(cfg)
  storage.refresh()

  -- De a uno: el cofre de entrada tiene 27 slots y algun test usa 40 items.
  for name, count in pairs(stock or {}) do
    mock.give(IN, name, count)
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

test("el boton cancelar del dialogo tambien cierra", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.enter)
  -- Si el click no cae en el boton, el dialogo queda abierto, se come el F10 y
  -- el test explota al vaciarse la cola: la coordenada esta verificada.
  mterm.click(1, 36, 10)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  eq(mock.count(OUT, "minecraft:cobblestone"), 0, "no entrego nada")
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

test("tab muestra donde esta guardado el item", function()
  local storage, ui, cfg = setup({ ["minecraft:cobblestone"] = 300 })
  mterm.key(mterm.KEYS.tab)
  mterm.key(mterm.KEYS.enter)
  mterm.key(mterm.KEYS.f10)
  ui.run(storage, cfg)

  check(mterm.anyFrame("guardado en"), "dice en cuantos cofres esta")
  check(mterm.anyFrame("minecraft:chest_0"), "y en cuales")
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
