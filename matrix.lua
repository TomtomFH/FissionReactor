-- Induction Matrix display and high-energy failsafe
local VERSION = '1.2.1'
local sides = {'top','bottom','left','right','front','back'}
local rs = _G.rs or _G.redstone
local peripheral = _G.peripheral
local term = _G.term
local colors = _G.colors or _G.colours
local sleep = _G.os.sleep
local floor = math.floor
local max = math.max

local function findMatrix()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == 'inductionPort' then
      local obj = peripheral.wrap(name)
      if obj and type(obj.getEnergy) == 'function' and type(obj.getMaxEnergy) == 'function' then
        return obj, name
      end
    end
  end
end

local function setAlarm(active)
  if rs and type(rs.setOutput) == 'function' then
    for _, side in ipairs(sides) do pcall(rs.setOutput, side, active) end
  end
end

local mon = peripheral.find('monitor') or term
if mon.setTextScale then mon.setTextScale(0.5) end
local w, h = mon.getSize()
local buttons = {}
local layoutDirty = true
local last = {}
local latest = 'CHECKING'

local function fmt(n)
  if type(n) ~= 'number' then return 'n/a' end
  local s = tostring(floor(n + 0.5))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return out
end

local function text(x, y, value, fg, bg, width)
  if y < 1 or y > h then return end
  mon.setCursorPos(x, y)
  mon.setTextColor(fg or colors.white)
  mon.setBackgroundColor(bg or colors.black)
  value = tostring(value or '')
  if width then value = value:sub(1, width) end
  mon.write(value)
end

local function button(id, x, y, bw, label, bg, fn)
  if y < 1 or y > h then return end
  buttons[id] = {x=x,y=y,w=bw,fn=fn}
  mon.setBackgroundColor(bg)
  mon.setTextColor(colors.white)
  mon.setCursorPos(x,y)
  mon.write(string.rep(' ',bw))
  mon.setCursorPos(x + max(0,floor((bw-#label)/2)),y)
  mon.write(label:sub(1,bw))
end

local function runUpdater()
  if shell and shell.run then shell.run('update') end
end
local function reboot()
  os.reboot()
end

local function drawLayout()
  w,h = mon.getSize()
  mon.setBackgroundColor(colors.black)
  mon.clear()
  local rightW = max(19, floor(w*0.25))
  if w-rightW < 24 then rightW = max(14,w-24) end
  local leftW = w-rightW-1
  local rightX = leftW+2
  for y=1,h do
    mon.setCursorPos(rightX,y)
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(' ',rightW))
  end
  mon.setBackgroundColor(colors.black)
  text(2,1,'INDUCTION MATRIX',colors.white,colors.black,leftW-2)
  text(2,2,'ENERGY STORAGE',colors.lightGray,colors.black,leftW-2)
  text(rightX+1,1,'',colors.white,colors.gray,rightW-2)
  local statusH = max(2,floor(h*0.11))
  button('status',rightX,1,rightW,'ONLINE',colors.lime,function() end)
  text(rightX+1,statusH+1,'Energy Input:',colors.white,colors.gray,rightW-2)
  text(rightX+1,statusH+3,'Energy Output:',colors.white,colors.gray,rightW-2)
  text(rightX+1,statusH+5,'Transfer Rate:',colors.white,colors.gray,rightW-2)
  local safetyY = max(statusH+8,floor(h*0.53))
  text(rightX+1,safetyY,'Safety: CHECKS',colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+1,'[x] Energy >99%',colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+2,'    Redstone alarm',colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+4,'Version: '..VERSION,colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+5,'Latest: '..latest,colors.white,colors.gray,rightW-2)
  local updateY = h-2
  local rebootY = h-1
  button('update',rightX+1,updateY,rightW-2,'UPDATE',colors.blue,runUpdater)
  button('reboot',rightX+1,rebootY,rightW-2,'REBOOT',colors.red,reboot)
  -- Large single energy bar, leaving room for the title and value.
  text(2,4,'Stored Energy',colors.white,colors.black,leftW-2)
  layoutDirty = false
end

local function drawBar(x,y,bw,bh,pct)
  pct = math.max(0,math.min(100,tonumber(pct) or 0))
  local filled = floor(bw*pct/100+0.5)
  for row=0,bh-1 do
    mon.setCursorPos(x,y+row)
    mon.setBackgroundColor(colors.black)
    mon.write(string.rep(' ',bw))
    if filled>0 then
      mon.setCursorPos(x,y+row)
      mon.setBackgroundColor(colors.lightGreen)
      mon.write(string.rep(' ',filled))
    end
  end
  mon.setBackgroundColor(colors.black)
end

local function readOptional(obj, method)
  if type(obj[method]) ~= 'function' then return nil end
  local ok, value = pcall(obj[method])
  if ok and type(value)=='number' then return value end
  return nil
end

local function draw()
  w,h = mon.getSize()
  if layoutDirty then drawLayout() end
  local rightW = max(19,floor(w*0.25))
  if w-rightW<24 then rightW=max(14,w-24) end
  local leftW=w-rightW-1
  local rightX=leftW+2
  local statusH=max(2,floor(h*0.11))
  local safetyY=max(statusH+8,floor(h*0.53))
  local matrix,name=findMatrix()
  local energy,capacity,input,output,transfer,pct
  local valid=false
  if matrix then
    local ok,e,c=pcall(function() return matrix.getEnergy(),matrix.getMaxEnergy() end)
    if ok and type(e)=='number' and type(c)=='number' and c>0 then
      energy,capacity=e,c
      input=readOptional(matrix,'getLastInput')
      output=readOptional(matrix,'getLastOutput')
      transfer=readOptional(matrix,'getTransferCap')
      pct=energy/capacity*100
      valid=true
    end
  end
  local tripped=valid and pct>99
  setAlarm(tripped)
  local statusColor=matrix and colors.lime or colors.red
  button('status',rightX,1,rightW,matrix and 'ONLINE' or 'OFFLINE',statusColor,function() end)

  -- Keep the single large storage bar on the left.
  text(2,1,'INDUCTION MATRIX',colors.white,colors.black,leftW-2)
  text(2,2,'ENERGY STORAGE',colors.lightGray,colors.black,leftW-2)
  local valueLine=valid and (fmt(energy)..' / '..fmt(capacity)..' FE  ('..string.format('%.2f',pct)..'%)') or 'Waiting for Induction Matrix...'
  text(2,4,valueLine,colors.white,colors.black,leftW-2)
  local barY=6
  local barH=max(3,h-9)
  drawBar(2,barY,leftW-2,barH,valid and pct or 0)
  text(2,barY+barH+1,valid and (string.format('%.2f%% FULL',pct)) or 'NO MATRIX DATA',valid and (tripped and colors.red or colors.lightGreen) or colors.red,colors.black,leftW-2)

  text(rightX+1,statusH+1,'Energy Input:',colors.white,colors.gray,rightW-2)
  text(rightX+1,statusH+2,input and (fmt(input)..' FE/t') or 'n/a',colors.white,colors.gray,rightW-2)
  text(rightX+1,statusH+3,'Energy Output:',colors.white,colors.gray,rightW-2)
  text(rightX+1,statusH+4,output and (fmt(output)..' FE/t') or 'n/a',colors.white,colors.gray,rightW-2)
  text(rightX+1,statusH+5,'Transfer Rate:',colors.white,colors.gray,rightW-2)
  text(rightX+1,statusH+6,transfer and (fmt(transfer)..' FE/t') or 'n/a',colors.white,colors.gray,rightW-2)

  text(rightX+1,safetyY,'Safety: CHECKS',colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+1,tripped and '[x] Energy >99%' or '[ ] Energy >99%',tripped and colors.red or colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+2,tripped and '    REDSTONE: ON' or '    Redstone: OFF',tripped and colors.red or colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+4,'Version: '..VERSION,colors.white,colors.gray,rightW-2)
  text(rightX+1,safetyY+5,'Latest: '..latest,colors.white,colors.gray,rightW-2)
  button('update',rightX+1,h-2,rightW-2,'UPDATE',colors.blue,runUpdater)
  button('reboot',rightX+1,h-1,rightW-2,'REBOOT',colors.red,reboot)
  mon.setBackgroundColor(colors.black)
end

local function versionChecker()
  while true do
    local ok,response=pcall(function()
      if not http or not http.get then return nil end
      return http.get('https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/version.txt',nil,true)
    end)
    if ok and response then
      local value=response.readAll()
      response.close()
      if value then latest=value:gsub('%s+','') end
    end
    draw()
    sleep(300)
  end
end

local function inputLoop()
  while true do
    local event,side,x,y=os.pullEvent()
    if event=='monitor_touch' then
      for _,b in pairs(buttons) do
        if x>=b.x and x<b.x+b.w and y==b.y then b.fn(); break end
      end
    elseif event=='term_resize' then
      layoutDirty=true
      draw()
    end
  end
end

local function monitorLoop()
  while true do
    draw()
    sleep(0.5)
  end
end

draw()
parallel.waitForAny(monitorLoop,inputLoop,versionChecker)
