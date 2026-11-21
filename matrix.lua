-- Induction Matrix monitor and high-energy failsafe
local VERSION = '1.2.6'
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
  drawText(rightX + 1, topH + 2, '[ ] Energy >99%', colors.white, colors.gray, rightW - 2)
  drawText(rightX + 1, topH + 3, 'Redstone: OFF', colors.white, colors.gray, rightW - 2)
  drawText(rightX + 1, topH + 5, 'Version: ' .. VERSION, colors.white, colors.gray, rightW - 2)
  drawText(rightX + 1, topH + 6, 'Latest: ' .. LATEST_VERSION, colors.white, colors.gray, rightW - 2)
  local updateY, rebootY = topH + 8, topH + 9
  if rebootY > h then updateY, rebootY = h - 2, h - 1 end
  add('update', rightX + 1, updateY, rightW - 2, 1, 'UPDATE', runUpdater)
  add('reboot', rightX + 1, rebootY, rightW - 2, 1, 'REBOOT', rebootComputer)
  drawBtn(newButtons.update, nil, colors.blue, colors.white)
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
      energy, capacity = e, c
      input = readOptional(matrix, 'getLastInput')
      output = readOptional(matrix, 'getLastOutput')
      transfer = readOptional(matrix, 'getTransferCap')
      pct = energy / capacity * 100
      valid = true
    end
  end
  local tripped = valid and pct > 99
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
  local boxH = floor(h / 4)
  if changed.energy or changed.capacity or changed.pct or changed.online or redrawAll then
    local y = 1
    local barHeight = max(1, boxH - 1)
    drawText(2, y, 'Energy', colors.white, colors.black, leftW - 3)
    local value = valid and (fmt(energy) .. ' / ' .. fmt(capacity) .. ' (' .. fmtStr('%d%%', floor(pct + 0.5)) .. ')') or 'n/a'
    drawText(max(2, leftW - #value - 1), y, value, colors.white, colors.black, leftW)
    drawBar(1, y + 1, leftW, barHeight, valid and pct or 0, colors.green)
  end
  if changed.input or changed.output or changed.transfer or changed.online or redrawAll then
    drawText(rightX+1,statusH+2,'Energy Input: '..(input and fmt(input) or 'n/a'),colors.white,colors.gray,rightW-2)
    drawText(rightX+1,statusH+3,'Energy Output: '..(output and fmt(output) or 'n/a'),colors.white,colors.gray,rightW-2)
    drawText(rightX+1,statusH+4,'Transfer Rate: '..(transfer and fmt(transfer) or 'n/a'),colors.white,colors.gray,rightW-2)
  end
  if changed.tripped or changed.online or redrawAll then
    drawText(rightX+1,topH+1,'Safety: CHECKS',colors.white,colors.gray,rightW-2)
    drawText(rightX+1,topH+2,'[x] Energy >99%',colors.white,colors.gray,rightW-2)
    drawText(rightX+1,topH+3,' ',colors.white,colors.gray,rightW-2)
    drawText(rightX+1,topH+2,'[x] Energy >99%',tripped and colors.red or colors.white,colors.gray,rightW-2)
  end
  if changed.latest or redrawAll then
    drawText(rightX+1,topH+5,'Version: '..VERSION,colors.white,colors.gray,rightW-2)
    drawText(rightX+1,topH+6,'Latest: '..LATEST_VERSION,colors.white,colors.gray,rightW-2)
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
      if latest then LATEST_VERSION=latest:gsub('%s+','') end
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
