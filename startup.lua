-- cc-organizer: almacenamiento automatico para CC:Tweaked.
-- Requiere modems cableados en cada cofre y en la computadora.

local dir = fs.getDir(shell and shell.getRunningProgram() or "startup.lua")
package.path = ("/%s/?.lua;/%s/?/init.lua;"):format(dir, dir) .. package.path

local config = require("config")
local storage = require("lib.storage")
local ui = require("lib.ui")

local function check(name, label)
  if peripheral.isPresent(name) then return true end
  printError(("no encuentro el cofre de %s: %s"):format(label, name))
  printError("corrige config.lua (el comando `peripherals` lista los nombres reales)")
  return false
end

term.clear()
term.setCursorPos(1, 1)
print("escaneando la red...")
storage.init(config)
storage.refresh()
check(config.input, "entrada")
check(config.output, "salida")

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
    local event, name = os.pullEvent()
    if event == "peripheral" or event == "peripheral_detach" then
      while storage.busy do os.sleep(0.2) end
      storage.busy = true
      local ok = pcall(storage.refresh)
      storage.busy = false
      ui.notify(ok and ("red actualizada (" .. tostring(name) .. ")") or "fallo el re-escaneo de la red")
    end
  end
end

parallel.waitForAny(
  function() ui.run(storage, config) end,
  autoStore,
  watchNetwork
)

term.setTextColour(colours.white)
print("cc-organizer detenido")
