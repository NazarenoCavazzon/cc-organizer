-- cc-organizer: almacenamiento automatico para CC:Tweaked.
-- Requiere modems cableados en cada cofre y en la computadora.

local dir = fs.getDir(shell and shell.getRunningProgram() or "startup.lua")
package.path = ("/%s/?.lua;/%s/?/init.lua;"):format(dir, dir) .. package.path

local config = require("config")
local storage = require("lib.storage")
local setup = require("lib.setup")
local monitor = require("lib.monitor")
local ui = require("lib.ui")

--- Vacia el cofre de entrada cada tanto sin pisar un comando en curso.
local function autoStore()
  local interval = config.autoStoreInterval or 3
  while true do
    os.sleep(interval)
    if not storage.busy and storage.inputHasItems() then
      storage.busy = true
      local ok, moved, left, err = pcall(storage.store)
      storage.busy = false
      if not ok then
        ui.notify("auto-guardado fallo: " .. tostring(moved))
      elseif moved > 0 or left > 0 then
        local msg = ("guardados %d items"):format(moved)
        if left > 0 then msg = msg .. (", %d sin lugar (%s)"):format(left, err or "?") end
        ui.notify(msg)
      end
    end
  end
end

--- Un cofre agregado o roto en caliente invalida el indice.
local function watchNetwork()
  while true do
    local event = os.pullEvent()
    if event == "peripheral" or event == "peripheral_detach" then
      while storage.busy do os.sleep(0.2) end
      storage.busy = true
      local ok = pcall(storage.refresh)
      storage.busy = false
      ui.notify(ok and "la red cambio, indice actualizado" or "fallo el re-escaneo de la red")
    end
  end
end

local function configured()
  return peripheral.isPresent(config.input) and peripheral.isPresent(config.output)
end

term.setBackgroundColour(colours.black)
term.clear()
term.setCursorPos(1, 1)

if not configured() then
  print("no encuentro los cofres de entrada/salida configurados")
  os.sleep(1)
  if not setup.run(config) then
    printError("configuracion cancelada; edita config.lua a mano y reinicia")
    return
  end
end

--- Si el armado tiene problemas conviene decirlo antes de abrir la TUI.
local function warnAboutProblems()
  local report = storage.diagnose()
  if #report.problems == 0 then return end
  -- Las computadoras normales solo aceptan blanco y negro: pedirles otro color
  -- tira "Colour not supported".
  local function tint(c)
    if term.isColour and term.isColour() then term.setTextColour(c) end
  end
  tint(colours.yellow)
  print("")
  print("revisa el armado:")
  for _, problem in ipairs(report.problems) do print("  ! " .. problem) end
  tint(colours.lightGrey)
  print("")
  print("(F3 dentro del programa repite este diagnostico)")
  print("tecla para continuar...")
  tint(colours.white)
  os.pullEvent("key")
end

repeat
  print("escaneando la red...")
  storage.init(config)
  storage.refresh()
  warnAboutProblems()

  parallel.waitForAny(
    function() ui.run(storage, config) end,
    autoStore,
    watchNetwork,
    function() monitor.run(storage) end
  )

  -- F9 dentro de la TUI pide reconfigurar y volver a arrancar.
  local again = ui.reconfigure and setup.run(config)
until not again

term.setTextColour(colours.white)
print("cc-organizer detenido")
