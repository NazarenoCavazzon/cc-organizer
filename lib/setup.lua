-- Asistente para elegir los cofres de entrada y salida sin editar config.lua a mano.
-- Se abre solo si los cofres configurados no estan en la red, o con F9.

local setup = {}

local CONFIG_PATH = "config.lua"

local function colourTerm()
  return term.isColour and term.isColour()
end

local function paint(fg, bg)
  if colourTerm() then
    term.setTextColour(fg)
    term.setBackgroundColour(bg)
  else
    local inverted = bg ~= colours.black
    term.setTextColour(inverted and colours.black or colours.white)
    term.setBackgroundColour(inverted and colours.white or colours.black)
  end
end

local function fit(s, w)
  if #s > w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

--- Todos los inventarios de la red, con su tamano.
local function inventories()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "inventory") then
      local ok, size = pcall(peripheral.call, name, "size")
      list[#list + 1] = { name = name, size = ok and size or 0 }
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

--- Menu de una sola columna. Devuelve el nombre elegido o nil si cancelan.
local function pick(title, hint, list, current)
  local W, H = term.getSize()
  local sel, top = 1, 1
  for i, entry in ipairs(list) do
    if entry.name == current then sel = i end
  end
  local rowsVisible = H - 4

  while true do
    if sel < top then top = sel end
    if sel > top + rowsVisible - 1 then top = sel - rowsVisible + 1 end

    paint(colours.black, colourTerm() and colours.cyan or colours.white)
    term.setCursorPos(1, 1)
    term.write(fit(" " .. title, W))
    paint(colours.yellow, colours.black)
    term.setCursorPos(1, 2)
    term.clearLine()
    term.write(fit(hint, W))

    for i = 0, rowsVisible - 1 do
      local entry = list[top + i]
      local selected = (top + i) == sel
      paint(selected and colours.black or colours.white,
            selected and (colourTerm() and colours.lightGrey or colours.white) or colours.black)
      term.setCursorPos(1, 3 + i)
      if entry then
        term.write(fit(("  %-32s %3d slots"):format(entry.name, entry.size), W))
      else
        term.write(string.rep(" ", W))
      end
    end

    paint(colours.black, colourTerm() and colours.grey or colours.white)
    term.setCursorPos(1, H)
    term.write(fit(" flechas mover   enter elegir   esc cancelar", W))

    local event, a, _, y = os.pullEvent()
    if event == "key" then
      if a == keys.up then sel = math.max(1, sel - 1)
      elseif a == keys.down then sel = math.min(#list, sel + 1)
      elseif a == keys.enter or a == keys.numPadEnter then
        return list[sel] and list[sel].name
      elseif a == keys.escape then return nil
      end
    elseif event == "mouse_click" then
      local i = top + (y - 3)
      if list[i] then
        if sel == i then return list[i].name end
        sel = i
      end
    elseif event == "mouse_scroll" then
      sel = math.max(1, math.min(#list, sel + a))
    end
  end
end

--- Reescribe config.lua con los valores actuales.
function setup.save(config)
  local file = fs.open(CONFIG_PATH, "w")
  if not file then return false, "no puedo escribir " .. CONFIG_PATH end
  file.write(([[
-- Configuracion del sistema de almacenamiento.
-- Generado por el asistente (F9 dentro del programa).
return {
  -- Cofre donde tiras los items para que se guarden solos.
  input = %q,

  -- Cofre donde aparecen los items que pedis.
  output = %q,

  -- Inventarios de la red que NO forman parte del almacenamiento.
  ignore = %s,

  -- Cada cuantos segundos se revisa el cofre de entrada.
  autoStoreInterval = %d,
}
]]):format(config.input, config.output,
           textutils.serialise(config.ignore or {}, { compact = true }),
           config.autoStoreInterval or 3))
  file.close()
  return true
end

--- Corre el asistente completo. Muta `config` y lo guarda. false si cancelan.
function setup.run(config)
  local list = inventories()
  if #list < 2 then
    term.setBackgroundColour(colours.black)
    term.clear()
    term.setCursorPos(1, 1)
    printError("solo encuentro " .. #list .. " inventario(s) en la red")
    print("conecta los cofres con modems cableados y volve a intentar")
    print("(cada modem se activa con click derecho)")
    return false
  end

  local input = pick("configuracion 1/2", " cofre de ENTRADA: donde tiras los items", list, config.input)
  if not input then return false end

  local rest = {}
  for _, entry in ipairs(list) do
    if entry.name ~= input then rest[#rest + 1] = entry end
  end
  local output = pick("configuracion 2/2", " cofre de SALIDA: donde aparecen los pedidos", rest, config.output)
  if not output then return false end

  config.input, config.output = input, output
  local ok, err = setup.save(config)
  term.setBackgroundColour(colours.black)
  term.setTextColour(colours.white)
  term.clear()
  term.setCursorPos(1, 1)
  if not ok then printError(err) end
  return ok
end

return setup
