-- Instalador para bajar cc-organizer desde GitHub dentro del juego.
--   wget <raw del repo>/install.lua install.lua
--   install
-- Cambia REPO por tu usuario/rama si hiciste fork.

local REPO = "https://raw.githubusercontent.com/NazarenoCavazzon/cc-organizer/main/"

local FILES = {
  "startup.lua",
  "lib/items.lua",
  "lib/storage.lua",
  "lib/ui.lua",
}

-- config.lua no se pisa: ahi estan los nombres de tus cofres.
local ONCE = { "config.lua" }

local function download(path, skipIfExists)
  if skipIfExists and fs.exists(path) then
    print("  = " .. path .. " (ya existe, no lo toco)")
    return true
  end
  local res, err = http.get(REPO .. path)
  if not res then
    printError("  x " .. path .. ": " .. tostring(err))
    return false
  end
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  f.write(res.readAll())
  f.close()
  res.close()
  print("  + " .. path)
  return true
end

if not http then
  printError("el mod tiene la API http desactivada; copia los archivos a mano")
  return
end

print("bajando cc-organizer...")
local ok = true
for _, path in ipairs(FILES) do ok = download(path, false) and ok end
for _, path in ipairs(ONCE) do ok = download(path, true) and ok end

if ok then
  print("listo. edita config.lua y reinicia la computadora")
else
  printError("hubo errores, revisa la URL del repo en install.lua")
end
