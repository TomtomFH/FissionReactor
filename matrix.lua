-- Induction Matrix monitor and high-energy failsafe
local VERSION = '1.3.5'
local LATEST_VERSION = 'CHECKING'

local term = _G.term
local colors = _G.colors or _G.colours
local peripheral = _G.peripheral
local osSleep = _G.os.sleep
local pullEvent = _G.os.pullEvent
local parallel = _G.parallel
local floor, max = math.floor, math.max
local abs = math.abs
local fmtStr = string.format

-- Mekanism reports energy in Joules; 1 FE = 2.5 J.
local JOULES_PER_FE = 2.5
local function joulesToFE(value)
  if type(value) ~= 'number' then return nil end
  return value / JOULES_PER_FE
end

local mon = peripheral and peripheral.find and peripheral.find('monitor') or term
if mon and mon.setTextScale then mon.setTextScale(0.5) end
local useMon = mon ~= term
if useMon then term.redirect(mon) end

do
  local target = colors.green
  if mon and mon.setPaletteColor then
    mon.setPaletteColor(target, 115 / 255, 186 / 255, 132 / 255)
  elseif term and term.setPaletteColor then
    term.setPaletteColor(target, 115 / 255, 186 / 255, 132 / 255)
  end
end

do
  local target = colors.pink
  if mon and mon.setPaletteColor then
    mon.setPaletteColor(target, 0xF2 / 255, 0xD7 / 255, 0xB6 / 255)
  elseif term and term.setPaletteColor then
    term.setPaletteColor(target, 0xF2 / 255, 0xD7 / 255, 0xB6 / 255)
  end
end

local RS_SIDES = {'top','bottom','left','right','front','back'}
local rs = _G.rs or _G.redstone
local buttons = {}
local newButtons = {}
local w, h = term.getSize()
local layoutDirty = true
local prevSnapshot = nil
local safetyTriggered = false

local energySafetyEnabled = true
if fs and fs.exists and fs.exists('matrix_safety.txt') then
  local f = fs.open('matrix_safety.txt', 'r')
  if f then
    energySafetyEnabled = f.readAll():gsub('%s+', '') ~= 'false'
    f.close()
  end
end

local function toggleEnergySafety()
  energySafetyEnabled = not energySafetyEnabled
  if fs and fs.open then
    local f = fs.open('matrix_safety.txt', 'w')
    if f then f.write(energySafetyEnabled and 'true' or 'false'); f.close() end
  end
  layoutDirty = true
  prevSnapshot = nil
end

local autoUpdateEnabled = false
local autoUpdateStarted = false
if fs and fs.exists and fs.exists('auto_update.txt') then
  local f = fs.open('auto_update.txt', 'r')
  if f then
    autoUpdateEnabled = f.readAll():gsub('%s+', '') == 'true'
    f.close()
  end
end

local function saveAutoUpdate()
  if not fs or not fs.open then return end
  local f = fs.open('auto_update.txt', 'w')
  if f then f.write(autoUpdateEnabled and 'true' or 'false'); f.close() end
end

local function toggleAutoUpdate()
  autoUpdateEnabled = not autoUpdateEnabled
  saveAutoUpdate()
  layoutDirty = true
  prevSnapshot = nil
end

local function findMatrix()
  if not peripheral then return nil end
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == 'inductionPort' then
      local obj = peripheral.wrap(name)
      if obj and type(obj.getEnergy) == 'function' and type(obj.getMaxEnergy) == 'function' then
        return obj, name
      end
    end
  end
end

local function setFailsafeRedstone(active)
  if rs and type(rs.setOutput) == 'function' then
    for _, side in ipairs(RS_SIDES) do pcall(rs.setOutput, side, active) end
  end
end

local function fmt(n)
  if type(n) ~= 'number' then return 'n/a' end
  local rounded = fmtStr('%.2f', abs(n))
  rounded = rounded:gsub('0+$', ''):gsub('%.$', '')
  local whole, fraction = rounded:match('^(%d+)%.?(%d*)$')
  if not whole then return tostring(n) end
  whole = whole:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. whole .. (fraction ~= '' and ('.' .. fraction) or '')
end

local function readOptional(obj, method)
  if type(obj[method]) ~= 'function' then return nil end
  local ok, value = pcall(obj[method])
  if ok and type(value) == 'number' then return value end
  return nil
end

local function drawText(x, y, value, fg, bg, width)
  if y < 1 or y > h then return end
  value = tostring(value or '')
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  if width then value = value:sub(1, width) end
  term.write(value)
end

local function drawBtn(b, _, bg, fg)
  local bh = b.h or 1
  for i = 0, bh - 1 do
    term.setCursorPos(b.x, b.y + i)
    term.setBackgroundColor(bg or colors.blue)
    term.write(string.rep(' ', b.w))
  end
  local label = b.l or ''
  term.setCursorPos(b.x + max(0, floor((b.w - #label) / 2)), b.y + floor((bh - 1) / 2))
  term.setTextColor(fg or colors.white)
  term.write(label:sub(1, b.w))
  term.setBackgroundColor(colors.black)
end

local function drawBar(x, y, width, height, pct, fill)
  pct = math.max(0, math.min(100, tonumber(pct) or 0))
  local filled = floor(width * pct / 100 + 0.5)
  for row = 0, height - 1 do
    term.setCursorPos(x, y + row)
    term.setBackgroundColor(colors.black)
    term.write(string.rep(' ', width))
    if filled > 0 then
      term.setCursorPos(x, y + row)
      term.setBackgroundColor(fill)
      term.write(string.rep(' ', filled))
    end
  end
  term.setBackgroundColor(colors.black)
end

local function drawGradientBar(x, y, width, height, pct)
  pct = math.max(0, math.min(100, tonumber(pct) or 0))
  local filled = floor(width * pct / 100 + 0.5)

  -- Smooth green-to-red RGB interpolation, quantized to the monitor's
  -- available 16-colour palette (CC:Tweaked terminal colours are palette-based).
  local stops = {
    {0.00, 0x00, 0xD9, 0x55},
    {0.25, 0x80, 0xF0, 0x30},
    {0.50, 0xF0, 0xF0, 0x20},
    {0.75, 0xFF, 0xA0, 0x20},
    {1.00, 0xF0, 0x35, 0x25}
  }
  local palette = {}
  local paletteGetter = mon and mon.getPaletteColor or (term and term.getPaletteColor)
  for i = 0, 15 do
    local color = 2 ^ i
    local r, g, b
    if paletteGetter then
      local ok, pr, pg, pb = pcall(paletteGetter, color)
      if ok and type(pr) == 'number' then r, g, b = pr * 255, pg * 255, pb * 255 end
    end
    if not r then
      local defaults = {
        [0]={240,240,240}, [1]={242,178,51}, [2]={229,127,216}, [3]={153,178,242},
        [4]={222,222,108}, [5]={127,204,25}, [6]={242,178,204}, [7]={76,76,76},
        [8]={153,153,153}, [9]={76,153,178}, [10]={178,102,229}, [11]={51,102,204},
        [12]={127,102,76}, [13]={87,166,78}, [14]={204,76,76}, [15]={25,25,25}
      }
      r, g, b = table.unpack(defaults[i])
    end
    palette[#palette + 1] = {color=color, r=r, g=g, b=b}
  end

  local function gradientRGB(position)
    local a, b = stops[1], stops[#stops]
    for i = 1, #stops - 1 do
      if position <= stops[i + 1][1] then a, b = stops[i], stops[i + 1]; break end
    end
    local t = (position - a[1]) / (b[1] - a[1])
    return a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t,
           a[4] + (b[4] - a[4]) * t
  end

  for row = 0, height - 1 do
    for col = 0, width - 1 do
      term.setCursorPos(x + col, y + row)
      if col < filled then
        local r, g, b = gradientRGB((col + 0.5) / math.max(1, width))
        local best, bestDistance = colors.green, math.huge
        for _, p in ipairs(palette) do
          local dr, dg, db = r - p.r, g - p.g, b - p.b
          local distance = dr * dr + dg * dg + db * db
          if distance < bestDistance then best, bestDistance = p.color, distance end
        end
        term.setBackgroundColor(best)
      else
        term.setBackgroundColor(colors.black)
      end
      term.write(' ')
    end
  end
  term.setBackgroundColor(colors.black)
end

local function runUpdater()
  if shell and shell.run then shell.run('update') end
end

local function rebootComputer()
  _G.os.reboot()
end

local function drawLayout()
  w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  local rightW = max(15, floor(w * 0.23))
  if w - rightW < 25 then rightW = max(12, w - 25) end
  local leftW = w - rightW - 1
  local rightX = leftW + 2
  for y = 1, h do
    term.setCursorPos(rightX, y)
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(' ', rightW))
  end
  term.setBackgroundColor(colors.black)
  drawText(2, 1, 'Energy', colors.white, colors.black, leftW - 2)
  local topH = floor(h / 2)
  local statusH = max(2, floor(topH / 5))
  newButtons = {}
  local function add(id, x, y, bw, bh, label, fn)
    newButtons[id] = {x=x,y=y,w=bw,h=bh,fn=fn,l=label}
  end
  add('status', rightX, 1, rightW, statusH, 'ONLINE', function() end)
  drawText(rightX + 1, statusH + 2, 'Energy Input:', colors.white, colors.gray, rightW - 2)
  drawText(rightX + 1, statusH + 3, 'Energy Output:', colors.white, colors.gray, rightW - 2)
  drawText(rightX + 1, statusH + 4, 'Transfer Rate:', colors.white, colors.gray, rightW - 2)
  drawText(rightX + 1, topH + 1, 'Safety: CHECKS', colors.white, colors.gray, rightW - 2)
  add('energy_safety', rightX + 1, topH + 2, 3, 1, '[x]', toggleEnergySafety)
  drawText(rightX + 1, topH + 3, 'Version: ' .. VERSION, colors.white, colors.gray, rightW - 2)
  drawText(rightX + 1, topH + 4, 'Latest: ' .. LATEST_VERSION, colors.white, colors.gray, rightW - 2)
  local updateY, autoY, rebootY = topH + 6, topH + 7, topH + 8
  if rebootY > h then updateY, autoY, rebootY = h - 3, h - 2, h - 1 end
  add('update', rightX + 1, updateY, rightW - 2, 1, 'UPDATE', runUpdater)
  add('auto', rightX + 1, autoY, rightW - 2, 1, 'AUTO UPDATE: ' .. (autoUpdateEnabled and 'ON' or 'OFF'), toggleAutoUpdate)
  add('reboot', rightX + 1, rebootY, rightW - 2, 1, 'REBOOT', rebootComputer)
  drawBtn(newButtons.update, nil, colors.blue, colors.white)
  drawBtn(newButtons.auto, nil, autoUpdateEnabled and colors.green or colors.gray, colors.white)
  drawBtn(newButtons.reboot, nil, colors.red, colors.white)
  buttons = newButtons
  layoutDirty = false
end

local function draw()
  w, h = term.getSize()
  local resized = prevSnapshot and (w ~= prevSnapshot.w or h ~= prevSnapshot.h)
  local redrawAll = layoutDirty or resized
  if redrawAll then layoutDirty = true; drawLayout() end
  local rightW = max(15, floor(w * 0.23))
  if w - rightW < 25 then rightW = max(12, w - 25) end
  local leftW = w - rightW - 1
  local rightX = leftW + 2
  local topH = floor(h / 2)
  local statusH = max(2, floor(topH / 5))
  local matrix, name = findMatrix()
  local energy, capacity, input, output, transfer, pct
  local valid = false
  if matrix then
    local ok, e, c = pcall(function() return matrix.getEnergy(), matrix.getMaxEnergy() end)
    if ok and type(e) == 'number' and type(c) == 'number' and c > 0 then
      -- Convert all displayed energy quantities from Mekanism Joules to FE.
      energy, capacity = joulesToFE(e), joulesToFE(c)
      input = joulesToFE(readOptional(matrix, 'getLastInput'))
      output = joulesToFE(readOptional(matrix, 'getLastOutput'))
      transfer = joulesToFE(readOptional(matrix, 'getTransferCap'))
      -- Conversion cancels in the ratio, so keep the failsafe percentage unchanged.
      pct = e / c * 100
      valid = true
    end
  end
  local tripped = energySafetyEnabled and valid and pct > 99
  safetyTriggered = tripped
  setFailsafeRedstone(tripped)
  local snap = {energy=energy,capacity=capacity,input=input,output=output,transfer=transfer,pct=pct,online=matrix~=nil,name=name,w=w,h=h,tripped=tripped,latest=LATEST_VERSION}
  local changed = {}
  if not prevSnapshot then
    for k in pairs(snap) do changed[k] = true end
  else
    for k,v in pairs(snap) do
      local old = prevSnapshot[k]
      if type(v)=='number' and type(old)=='number' then
        if abs(v-old)>0.01 then changed[k]=true end
      elseif v ~= old then changed[k]=true end
    end
  end
  if redrawAll then for k in pairs(snap) do changed[k]=true end end
  prevSnapshot = snap
  if changed.online or redrawAll then
    local bg = matrix and colors.lime or colors.red
    local label = matrix and 'ONLINE' or 'OFFLINE'
    drawBtn({x=rightX,y=1,w=rightW,h=statusH,l=label},nil,bg,colors.white)
  end
  local boxH = max(4, floor(h / 4))
  local inputPct = (input and transfer and transfer > 0) and (input / transfer * 100) or 0
  local outputPct = (output and transfer and transfer > 0) and (output / transfer * 100) or 0
  if changed.energy or changed.capacity or changed.pct or changed.online or redrawAll then
    local y = 1
    local barHeight = max(1, boxH - 1)
    drawText(2, y, 'Energy', colors.white, colors.black, leftW - 3)
    local value = valid and (fmt(energy) .. ' / ' .. fmt(capacity) .. ' (' .. fmtStr('%d%%', floor(pct + 0.5)) .. ')') or 'n/a'
    drawText(max(2, leftW - #value - 1), y, value, colors.white, colors.black, leftW)
    drawBar(1, y + 1, leftW, barHeight, valid and pct or 0, colors.green)
  end
  -- Leave one complete bar-height of empty space after the energy storage bar.
  -- Then show the input and output bars in consecutive sections.
  if changed.input or changed.transfer or changed.online or redrawAll then
    local y = boxH * 2 + 1
    drawText(2, y, 'Input', colors.white, colors.black, leftW - 3)
    local value = input and transfer and (fmt(input) .. ' / ' .. fmt(transfer) .. ' FE/t') or 'n/a'
    drawText(max(2, leftW - #value - 1), y, value, colors.white, colors.black, leftW)
    drawGradientBar(1, y + 1, leftW, max(1, boxH - 1), inputPct)
  end
  if changed.output or changed.transfer or changed.online or redrawAll then
    local y = boxH * 3 + 1
    drawText(2, y, 'Output', colors.white, colors.black, leftW - 3)
    local value = output and transfer and (fmt(output) .. ' / ' .. fmt(transfer) .. ' FE/t') or 'n/a'
    drawText(max(2, leftW - #value - 1), y, value, colors.white, colors.black, leftW)
    drawGradientBar(1, y + 1, leftW, max(1, boxH - 1), outputPct)
  end
  if changed.input or changed.output or changed.transfer or changed.online or redrawAll then
    drawText(rightX+1,statusH+2,'Energy Input: '..(input and fmt(input) or 'n/a'),colors.white,colors.gray,rightW-2)
    drawText(rightX+1,statusH+3,'Energy Output: '..(output and fmt(output) or 'n/a'),colors.white,colors.gray,rightW-2)
    drawText(rightX+1,statusH+4,'Transfer Rate: '..(transfer and fmt(transfer) or 'n/a'),colors.white,colors.gray,rightW-2)
  end
  if changed.tripped or changed.online or redrawAll then
    drawText(rightX+1,topH+1,'Safety: CHECKS',colors.white,colors.gray,rightW-2)
    drawText(rightX+1,topH+2,energySafetyEnabled and '[x]' or '[ ]',energySafetyEnabled and colors.lime or colors.white,colors.gray,3)
    drawText(rightX+5,topH+2,'Energy >99%',not energySafetyEnabled and colors.lightGray or (tripped and colors.red or colors.white),colors.gray,rightW-6)
  end
  if changed.latest or redrawAll then
    drawText(rightX+1,topH+3,'Version: '..VERSION,colors.white,colors.gray,rightW-2)
    drawText(rightX+1,topH+4,'Latest: '..LATEST_VERSION,colors.white,colors.gray,rightW-2)
  end
  term.setBackgroundColor(colors.black)
end

local function handleClick(x,y)
  for _,b in pairs(buttons) do
    if x>=b.x and x<b.x+b.w and y>=b.y and y<=b.y+(b.h or 1)-1 then
      b.fn()
      prevSnapshot=nil
      layoutDirty=true
      draw()
      return
    end
  end
end

local function inputLoop()
  while true do
    local ev,a,b,c=pullEvent()
    if useMon and ev=='monitor_touch' then
      handleClick(b,c)
    elseif not useMon and ev=='mouse_click' then
      handleClick(b,c)
    elseif ev=='term_resize' then
      draw()
    end
  end
end

local function monitorLoop()
  while true do
    draw()
    osSleep(0.05)
  end
end

local function versionChecker()
  while true do
    local ok,response=pcall(function()
      if not http or not http.get then return nil end
      return http.get('https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/version.txt',nil,true)
    end)
    if ok and response then
      local latest=response.readAll()
      response.close()
      if latest then
        LATEST_VERSION=latest:gsub('%s+','')
        if autoUpdateEnabled and not autoUpdateStarted and LATEST_VERSION ~= VERSION and LATEST_VERSION ~= '' then
          local attempted = ''
          if fs and fs.exists and fs.exists('auto_update_attempted.txt') then
            local f = fs.open('auto_update_attempted.txt', 'r')
            if f then attempted = f.readAll():gsub('%s+', ''); f.close() end
          end
          if attempted ~= LATEST_VERSION then
            if fs and fs.open then
              local f = fs.open('auto_update_attempted.txt', 'w')
              if f then f.write(LATEST_VERSION); f.close() end
            end
            autoUpdateStarted = true
            runUpdater()
          end
        end
      end
    else
      LATEST_VERSION='UNKNOWN'
    end
    layoutDirty=true
    draw()
    osSleep(300)
  end
end

local function supervise(name,fn)
  while true do
    local ok,err=pcall(fn)
    if not ok then
      pcall(function()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.setCursorPos(1,h)
        term.write((name..' recovering: '..tostring(err)):sub(1,w))
      end)
      layoutDirty=true
      prevSnapshot=nil
      osSleep(2)
    else
      osSleep(0.5)
    end
  end
end

draw()
if parallel and parallel.waitForAny then
  parallel.waitForAny(
    function() supervise('Monitor',monitorLoop) end,
    function() supervise('Input',inputLoop) end,
    function() supervise('Version check',versionChecker) end
  )
else
  supervise('Monitor',monitorLoop)
end

setFailsafeRedstone(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.white)
term.write('Induction Matrix UI closed.')
