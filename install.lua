-- Instalador de cc-organizer.
--   wget https://raw.githubusercontent.com/NazarenoCavazzon/cc-organizer/main/install.lua install.lua
--   install
--
-- Baja los archivos pineados al ultimo commit: las URLs con SHA son inmutables,
-- asi que nunca te sirve una version vieja del CDN de GitHub (que cachea la rama
-- unos minutos y es la causa clasica de "lo actualice y sigue igual").

local OWNER, REPO, BRANCH = "NazarenoCavazzon", "cc-organizer", "main"

local FILES = {
  "install.lua",  -- se actualiza a si mismo para que la lista no quede vieja
  "startup.lua",
  "lib/draw.lua",
  "lib/dialog.lua",
  "lib/pixels.lua",
  "lib/bigtext.lua",
  "lib/icons.lua",
  "lib/items.lua",
  "lib/monitor.lua",
  "lib/setup.lua",
  "lib/storage.lua",
  "lib/ui.lua",
}

-- config.lua no se pisa: ahi estan los nombres de tus cofres.
local ONCE = { "config.lua" }

--- Baja una URL cerrando siempre la conexion. Reintenta porque CC limita las
--- requests simultaneas por computadora (http.max_requests, 16 por defecto) y
--- un install cortado a la mitad deja slots ocupados un rato: eso es el
--- "Backend.max_conn reached".
local function get(url)
  local err
  for attempt = 1, 3 do
    local res
    res, err = http.get(url)
    if res then
      local body = res.readAll()
      res.close()
      return body
    end
    if attempt < 3 then
      print("  reintentando (" .. tostring(err) .. ")")
      os.sleep(attempt * 2)
    end
  end
  return nil, err
end

--- SHA del ultimo commit de la rama, para bajar todo de la misma version.
local function latestCommit()
  local body = get(("https://api.github.com/repos/%s/%s/commits/%s"):format(OWNER, REPO, BRANCH))
  if not body then return nil end
  return body:match('"sha"%s*:%s*"(%x+)"')
end

local function download(base, path, skipIfExists)
  if skipIfExists and fs.exists(path) then
    print("  = " .. path .. " (ya existe, no lo toco)")
    return true
  end
  local body, err = get(base .. path)
  if not body then
    printError("  x " .. path .. ": " .. tostring(err))
    return false
  end
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local file = fs.open(path, "w")
  file.write(body)
  file.close()
  print("  + " .. path)
  return true
end

if not http then
  printError("el mod tiene la API http desactivada; copia los archivos a mano")
  return
end

local commit = latestCommit()
local base
if commit then
  base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, commit)
  print("bajando cc-organizer @ " .. commit:sub(1, 7))
else
  base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, BRANCH)
  print("no pude consultar el commit; bajando de la rama " .. BRANCH)
  print("(si algo queda viejo, es el cache de GitHub: reintenta en 5 min)")
end

local ok = true
for _, path in ipairs(FILES) do ok = download(base, path, false) and ok end
for _, path in ipairs(ONCE) do ok = download(base, path, true) and ok end

if ok then
  print("listo. reinicia la computadora con: reboot")
else
  printError("hubo errores.")
  printError("si dice max_conn: reinicia con `reboot` y volve a correr install")
end
