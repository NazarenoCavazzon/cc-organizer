-- Ventanas modales: mensajes, detalle de un item y el pedido de cantidad.
-- Todas dibujan sobre el buffer de draw y corren su propio bucle de eventos.

local draw = require("lib.draw")

local dialog = {}

local CHARS = "0123456789+-*/() "

--- Acepta expresiones tipo "64*3+16" (idea prestada de artist).
local function evaluate(text)
  if text:match("^%s*$") then return nil end
  local plain = tonumber(text)
  if plain then return math.floor(plain) end
  -- load con entorno vacio es lo que usa CC:Tweaked; loadstring es el de Lua 5.1
  -- pelado. Probamos el primero y caemos al segundo.
  local ok, chunk = pcall(load, "return " .. text, "cantidad", "t", {})
  if not ok or not chunk then
    if not loadstring then return nil end
    ok, chunk = pcall(loadstring, "return " .. text)
    if not ok or not chunk then return nil end
    if setfenv then setfenv(chunk, {}) end
  end
  local fine, value = pcall(chunk)
  if not fine or type(value) ~= "number" or value ~= value then return nil end
  return math.floor(value)
end
dialog.evaluate = evaluate

--- Dibuja el marco y devuelve el rectangulo interior.
local function frame(title, width, height)
  local W, H = draw.size()
  width = math.min(width, W - 2)
  height = math.min(height, H - 2)
  local x = math.floor((W - width) / 2) + 1
  local y = math.floor((H - height) / 2) + 1

  draw.paint(colours.black, colours.cyan)
  draw.at(x, y, draw.fit(" " .. title, width))
  draw.fill(x, y + 1, width, height - 1, colours.grey)
  return x, y, width, height
end

local function line(x, y, width, text, fg)
  draw.paint(fg or colours.white, colours.grey)
  draw.at(x, y, draw.fit(" " .. text, width))
end

--- En CC el Escape cierra la GUI de la computadora y el programa nunca lo ve,
--- asi que cancelar es ctrl+d (la convencion de artist). Se acepta escape igual
--- por si alguna version si lo entrega.
local function isCancel(key, ctrl)
  return key == keys.escape or (ctrl and key == keys.d)
end

--- Caja informativa: se cierra con cualquier tecla o click.
function dialog.message(title, lines)
  local W, H = draw.size()
  local maxLines = H - 6
  if #lines > maxLines then
    local cut = {}
    for i = 1, maxLines - 1 do cut[i] = lines[i] end
    cut[maxLines] = ("... y %d lineas mas"):format(#lines - maxLines + 1)
    lines = cut
  end

  local width = #title + 4
  for _, l in ipairs(lines) do width = math.max(width, #l + 3) end
  width = math.max(width, 24)

  local x, y, w = frame(title, width, #lines + 4)
  for i, text in ipairs(lines) do
    line(x, y + 1 + i, w, text, text:sub(1, 1) == "!" and colours.yellow or colours.white)
  end
  line(x, y + #lines + 3, w, "tecla para cerrar", colours.lightGrey)
  draw.cursor(1, 1, false)
  draw.present()

  while true do
    local event = os.pullEvent()
    if event == "key" or event == "mouse_click" then return end
  end
end

--- Pide una cantidad. Devuelve el numero o nil si cancelan.
--- opts: { title, info = {lineas}, default, max }
function dialog.number(opts)
  local text = tostring(opts.default or 1)
  -- El valor sugerido se comporta como texto seleccionado: el primer caracter
  -- que escribis lo reemplaza en vez de pegarse atras.
  local fresh = true
  local error_ = nil
  local ctrl = false
  local presets = {
    { label = "1", value = 1 },
    { label = "16", value = 16 },
    { label = "64", value = 64 },
    { label = "todo", value = opts.max },
  }

  while true do
    local width = math.max(38, #opts.title + 4)
    for _, l in ipairs(opts.info or {}) do width = math.max(width, #l + 3) end
    local infoCount = #(opts.info or {})
    local x, y, w = frame(opts.title, width, infoCount + 7)

    local row = y + 1
    for _, l in ipairs(opts.info or {}) do
      line(x, row, w, l, colours.lightGrey)
      row = row + 1
    end

    line(x, row, w, "", colours.white)
    draw.paint(colours.yellow, colours.grey)
    draw.at(x + 1, row, "cantidad: ")
    draw.paint(colours.white, colours.black)
    draw.at(x + 11, row, draw.fit(text .. "_", w - 12))
    row = row + 1

    -- Botones de cantidad rapida y cancelar.
    local buttons, bx = {}, x + 1
    draw.paint(colours.white, colours.grey)
    draw.at(x + 1, row, string.rep(" ", w - 2))
    for _, preset in ipairs(presets) do
      local label = " " .. preset.label .. " "
      if bx + #label <= x + w - 1 then
        draw.paint(colours.black, colours.lightGrey)
        draw.at(bx, row, label)
        buttons[#buttons + 1] = { x1 = bx, x2 = bx + #label - 1, y = row, value = preset.value }
        bx = bx + #label + 1
      end
    end
    local cancel = " cancelar "
    local cx = x + w - 1 - #cancel
    if cx > bx then
      draw.paint(colours.white, colours.red)
      draw.at(cx, row, cancel)
      buttons[#buttons + 1] = { x1 = cx, x2 = cx + #cancel - 1, y = row, cancel = true }
    end
    row = row + 1

    if error_ then
      line(x, row, w, error_, colours.red)
    else
      line(x, row, w, "enter ok   a = todo   ctrl+d cancela", colours.lightGrey)
    end

    draw.cursor(1, 1, false)
    draw.present()

    local event, param, clickX, clickY = os.pullEvent()
    error_ = nil
    if event == "key_up" then
      if param == keys.leftCtrl or param == keys.rightCtrl then ctrl = false end
    elseif event == "char" then
      if CHARS:find(param, 1, true) then
        text = (fresh and "" or text) .. param
        fresh = false
      elseif param == "a" or param == "A" then
        -- "todo" sin mouse: en una computadora normal no hay clicks.
        text, fresh = tostring(opts.max or 1), false
      end
    elseif event == "key" then
      local a = param
      if a == keys.leftCtrl or a == keys.rightCtrl then
        ctrl = true
      elseif isCancel(a, ctrl) then
        return nil
      elseif a == keys.backspace then
        text = fresh and "" or text:sub(1, -2)
        fresh = false
      elseif a == keys.enter or a == keys.numPadEnter then
        local value = evaluate(text)
        if not value or value <= 0 then
          error_ = "cantidad invalida"
        else
          return math.min(value, opts.max or value)
        end
      elseif a == keys.up then
        text, fresh = tostring((evaluate(text) or 0) + 1), false
      elseif a == keys.down then
        text, fresh = tostring(math.max(1, (evaluate(text) or 2) - 1)), false
      end
    elseif event == "mouse_click" then
      for _, b in ipairs(buttons) do
        if clickY == b.y and clickX >= b.x1 and clickX <= b.x2 then
          if b.cancel then return nil end
          return math.min(b.value, opts.max or b.value)
        end
      end
    end
  end
end

return dialog
