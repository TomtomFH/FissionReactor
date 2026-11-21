-- Induction Matrix monitor and high-energy failsafe
local VERSION = '1.2.0'
local sides = {'top','bottom','left','right','front','back'}
local rs = _G.rs or _G.redstone
local peripheral = _G.peripheral
local term = _G.term
local colors = _G.colors or _G.colours
local sleep = _G.os.sleep

local function findMatrix()
  for _, name in ipairs(peripheral.getNames()) do
    local kind = peripheral.getType(name)
    if kind == 'inductionPort' then
      local obj = peripheral.wrap(name)
      if obj and type(obj.getEnergy) == 'function' and type(obj.getMaxEnergy) == 'function' then
        return obj, name
      end
    end
  end
end

local function setAlarm(active)
  if rs and type(rs.setOutput) == 'function' then
    for _, side in ipairs(sides) do
      pcall(rs.setOutput, side, active)
    end
  end
end

local mon = peripheral.find('monitor') or term
if mon.setTextScale then mon.setTextScale(0.5) end
local function writeLine(y, text, color)
  mon.setCursorPos(2, y)
  mon.setTextColor(color or colors.white)
  mon.write(text)
end

while true do
  local matrix, name = findMatrix()
  mon.setBackgroundColor(colors.black)
  mon.clear()
  writeLine(1, 'INDUCTION MATRIX', colors.lime)
  writeLine(2, 'Control v' .. VERSION, colors.gray)
  if matrix then
    local ok, energy, capacity = pcall(function()
      return matrix.getEnergy(), matrix.getMaxEnergy()
    end)
    if ok and type(energy) == 'number' and type(capacity) == 'number' and capacity > 0 then
      local pct = energy / capacity * 100
      local tripped = pct > 99
      setAlarm(tripped)
      writeLine(4, 'Peripheral: ' .. tostring(name))
      writeLine(6, 'Energy: ' .. tostring(math.floor(energy)))
      writeLine(7, 'Capacity: ' .. tostring(math.floor(capacity)))
      writeLine(8, string.format('Filled: %.2f%%', pct), tripped and colors.red or colors.lime)
      writeLine(10, tripped and 'FAILSAFE: HIGH ENERGY' or 'Status: NORMAL', tripped and colors.red or colors.lime)
      writeLine(12, 'Redstone: ' .. (tripped and 'ON - ALL SIDES' or 'OFF'))
    else
      setAlarm(false)
      writeLine(5, 'Could not read matrix energy.', colors.red)
    end
  else
    setAlarm(false)
    writeLine(5, 'No Induction Matrix port found.', colors.red)
    writeLine(7, 'Connect an Induction Port')
    writeLine(8, 'to this wired network.')
  end
  sleep(0.5)
end
