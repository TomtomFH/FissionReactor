local ok, config = pcall(require, 'config')
if not ok or type(config) ~= 'table' then config = {} end

local IS_WIRELESS = config.IS_WIRELESS == true
local MODEM_CHANNEL = tonumber(config.MODEM_CHANNEL) or 42
local TEMP_IN_F = config.TEMP_IN_F == true -- default Celsius

local term = _G.term
local colors = _G.colors or _G.colours
local peripheral = _G.peripheral
local osClock = _G.os.clock
local osSleep = _G.os.sleep
local pullEvent = _G.os.pullEvent
local parallel = _G.parallel
local floor, max = math.floor, math.max
local abs = math.abs
local fmtStr = string.format

local mon = peripheral and peripheral.find and peripheral.find('monitor') or term
if mon and mon.setTextScale then
	mon.setTextScale(0.5)
end
local useMon = mon ~= term
if useMon then
	term.redirect(mon)
end

do
	local target = colors.pink
	local rC, gC, bC = 0xF2 / 255, 0xD7 / 255, 0xB6 / 255
	if mon and mon.setPaletteColor then
		mon.setPaletteColor(target, rC, gC, bC)
	elseif term and term.setPaletteColor then
		term.setPaletteColor(target, rC, gC, bC)
	end
end

local r, modem, wirelessData

if IS_WIRELESS then
	modem = peripheral.find('modem')
	if not modem then
		error('No modem found! Attach a wireless modem.')
	end
	modem.open(MODEM_CHANNEL)
	wirelessData = {}

	r = {
		getStatus = function()
			return wirelessData.active
		end,
		getDamage = function()
			return wirelessData.dmg
		end,
		getTemp = function()
			return wirelessData.temp
		end,
		getHeatingRate = function()
			return wirelessData.heatRate
		end,
		getBurnRate = function(t)
			if t == 'max' then return wirelessData.brMax end
			if t == 'percent' then return wirelessData.brPct end
			return wirelessData.br
		end,
		getFuel = function(t)
			if t == 'percent' then return wirelessData.fuelPct end
			if t == 'max' then return wirelessData.fuelMax end
			return wirelessData.fuel
		end,
		getWaste = function(t)
			if t == 'percent' then return wirelessData.wastePct end
			if t == 'max' then return wirelessData.wasteMax end
			return wirelessData.waste
		end,
		getCoolant = function(t)
			if t == 'percent' then return wirelessData.coolPct end
			if t == 'max' then return wirelessData.coolMax end
			return wirelessData.cool
		end,
		getHeatedCoolant = function(t)
			if t == 'percent' then return wirelessData.hotPct end
			if t == 'max' then return wirelessData.hotMax end
			return wirelessData.hot
		end,
		setStatus = function(d)
			if not modem then return false, 'no modem' end
			modem.transmit(MODEM_CHANNEL, MODEM_CHANNEL, { type = 'command', cmd = 'setStatus', value = d })
			return true
		end,
		setBurnRate = function(v)
			if not modem then return false, 'no modem' end
			modem.transmit(MODEM_CHANNEL, MODEM_CHANNEL, { type = 'command', cmd = 'setBurnRate', value = v })
			return true
		end,
	}
else
	r = require('functions')
end

local REFRESH_INTERVAL = tonumber(config.REFRESH_INTERVAL) or 0.05
local REDSTONE_OFF_LEVEL = tonumber(config.REDSTONE_OFF_LEVEL)
local RS_SIDES = { 'top', 'bottom', 'left', 'right', 'front', 'back' }
local rs = _G.rs or _G.redstone
local buttons = {}
local newButtons = {}
local w, h = term.getSize()

local safetyMode = true
local safetyShutdown = false
local safetyHighDanger = false
local safetyLastReason = nil
local SAFETY_TEMP_F = tonumber(config.SAFETY_TEMP_F) or 5000
local SAFETY_DMG_HIGH = tonumber(config.SAFETY_DMG_HIGH) or 50
local SAFETY_COOLANT_MIN = tonumber(config.SAFETY_COOLANT_MIN) or 20
local SAFETY_FUEL_MIN = tonumber(config.SAFETY_FUEL_MIN) or 5
local SAFETY_HEATED_MAX = tonumber(config.SAFETY_HEATED_MAX) or 99
local SAFETY_WASTE_MAX = tonumber(config.SAFETY_WASTE_MAX) or 99
local SAFETY_DMG_WARN = tonumber(config.SAFETY_DMG_WARN) or 20
local SAFETY_RESTART_COOLANT_MIN = tonumber(config.SAFETY_RESTART_COOLANT_MIN) or 15
local SAFETY_RESTART_FUEL_MIN = tonumber(config.SAFETY_RESTART_FUEL_MIN) or 5
local SAFETY_RESTART_HEATED_MAX = tonumber(config.SAFETY_RESTART_HEATED_MAX) or 99
local SAFETY_RESTART_WASTE_MAX = tonumber(config.SAFETY_RESTART_WASTE_MAX) or 99
local SAFETY_RESTART_DMG_MAX = tonumber(config.SAFETY_RESTART_DMG_MAX) or 20
local SAFETY_RESTART_TEMP_MAX = tonumber(config.SAFETY_RESTART_TEMP_MAX) or SAFETY_TEMP_F

local function resetSafetyShutdown()
	safetyShutdown = false
	safetyHighDanger = false
	safetyLastReason = nil
end

local function drawBtn(b, _, bg, fg)
	local bgc = bg or colors.blue
	local bh = b.h or 1
	for i = 0, bh - 1 do
		term.setCursorPos(b.x, b.y + i)
		term.setBackgroundColor(bgc)
		term.write(string.rep(' ', b.w))
	end
	local txt = b.l or ''
	term.setCursorPos(b.x + max(0, floor((b.w - #txt) / 2)), b.y + floor((bh - 1) / 2))
	term.setTextColor(fg or colors.white)
	term.write(txt:sub(1, b.w))
	term.setBackgroundColor(colors.black)
end

local function round(n)
	if type(n) ~= 'number' then
		return nil
	end
	return n >= 0 and floor(n + 0.5) or math.ceil(n - 0.5)
end

local function fmt(n)
	if type(n) ~= 'number' then
		return 'n/a'
	end
	if n >= 1000 then
		return fmtStr('%.1fK', n / 1000)
	end
	return tostring(floor(n * 100 + 0.5) / 100)
end

local DEG = string.char(176)
local TEMP_UNIT = TEMP_IN_F and 'F' or 'C'

local function kelvinToF(k)
	if type(k) ~= 'number' then return nil end
	return (k - 273.15) * 9 / 5 + 32
end

local function kelvinToC(k)
	if type(k) ~= 'number' then return nil end
	return k - 273.15
end

local function convertTemp(k)
	if TEMP_IN_F then return kelvinToF(k) end
	return kelvinToC(k)
end

local function isRedstoneTriggered()
	if not (REDSTONE_OFF_LEVEL and rs) then return false end
	for _, side in ipairs(RS_SIDES) do
		if (rs.getAnalogueInput(side) or 0) >= REDSTONE_OFF_LEVEL then
			return true
		end
	end
	return false
end

local function getBurnStep()
	local m = r.getBurnRate('max') or 0
	if m <= 0 then return 0.1 end
	if m < 1 then return 0.1 end
	local targetPresses = 30
	local raw = m / targetPresses
	local nice = {0.1,0.2,0.25,0.5,1,2,2.5,5,10,15,20,25,50,75,100,125,150,200,250,300,400,500,750,1000}
	for _, v in ipairs(nice) do
		if v >= raw then
			return v
		end
	end
	return nice[#nice]
end

local function normalizeRate(v)
	return floor(v * 100 + 0.5) / 100
end

local function adjustRate(dir)
	local cur = r.getBurnRate() or 0
	local maxR = r.getBurnRate('max') or cur
	local new = cur + getBurnStep() * dir
	if new < 0 then
		new = 0
	elseif new > maxR then
		new = maxR
	end
	new = normalizeRate(new)
	if new ~= cur then
		r.setBurnRate(new)
	end
end

local function toggleOnOff()
	local cur = r.getStatus()
	if cur then
		resetSafetyShutdown()
		r.setStatus(false)
	else
		resetSafetyShutdown()
		r.setStatus(true)
	end
end

local layoutDirty = true
local prevSnapshot = nil
local safetyChecks = {
	{ key = 'COOLANT', label = 'Coolant low', enabled = config.SAFETY_ENABLE_COOLANT ~= false },
	{ key = 'FUEL', label = 'Fuel low', enabled = config.SAFETY_ENABLE_FUEL ~= false },
	{ key = 'HEATED', label = 'Heated coolant high', enabled = config.SAFETY_ENABLE_HEATED ~= false },
	{ key = 'WASTE', label = 'Waste high', enabled = config.SAFETY_ENABLE_WASTE ~= false },
	{ key = 'DMG_WARN', label = 'Damage warning', enabled = config.SAFETY_ENABLE_DMG_WARN ~= false },
	{ key = 'DMG_HIGH', label = 'Critical damage', enabled = config.SAFETY_ENABLE_DMG_HIGH ~= false },
	{ key = 'TEMP', label = 'Critical temperature', enabled = config.SAFETY_ENABLE_TEMP ~= false },
	{ key = 'REDSTONE', label = 'Redstone trip', enabled = config.SAFETY_ENABLE_REDSTONE ~= false },
}
local function drawText(x, y, value, fg, bg, width)
	value = tostring(value or '')
	term.setCursorPos(x, y)
	term.setTextColor(fg or colors.white)
	term.setBackgroundColor(bg or colors.black)
	if width then value = value:sub(1, width) end
	term.write(value)
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
local function drawLayout()
	w, h = term.getSize()
	term.setBackgroundColor(colors.black)
	term.clear()
	local rightW = max(15, floor(w * 0.23))
	if w - rightW < 25 then rightW = max(12, w - 25) end
	local leftW = w - rightW - 1
	local rightX = leftW + 2
	local boxH = floor(h / 4)
	for i, title in ipairs({'Coolant', 'Fuel', 'Heated Coolant', 'Waste'}) do
		local y = 1 + (i - 1) * boxH
		drawText(2, y, title, colors.white, colors.black, leftW - 2)
	end
	local topH = floor(h / 2)
	local bottomH = h - topH
	term.setBackgroundColor(colors.gray)
	for y = 1, h do
		term.setCursorPos(rightX, y)
		term.write(string.rep(' ', rightW))
	end
	term.setBackgroundColor(colors.black)
	local statusH = max(2, floor(topH / 5))
	newButtons = {}
	local function add(id, x, y, bw, bh, fn)
		newButtons[id] = {x=x,y=y,w=bw,h=bh,fn=fn}
	end
	add('onoff', rightX, 1, rightW, statusH, toggleOnOff)
	drawText(rightX + 1, statusH + 2, 'Heat Rate:', colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, statusH + 3, 'Damage:', colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, statusH + 4, 'Temp:', colors.white, colors.gray, rightW - 2)
	local listY = topH + 1
	drawText(rightX + 1, listY, 'Safety checks', colors.white, colors.gray, rightW - 2)
	local rowY = listY + 1
	for i, check in ipairs(safetyChecks) do
		local id = 'safety_' .. check.key
		add(id, rightX + 1, rowY + i - 1, rightW - 2, 1, function()
			check.enabled = not check.enabled
			layoutDirty = true
		end)
	end
	buttons = newButtons
	layoutDirty = false
end
local function draw()
	w, h = term.getSize()
	if layoutDirty then drawLayout() end
	local rightW = max(15, floor(w * 0.23))
	if w - rightW < 25 then rightW = max(12, w - 25) end
	local leftW = w - rightW - 1
	local rightX = leftW + 2
	local topH = floor(h / 2)
	local statusH = max(2, floor(topH / 5))
	local snap = {
		active=r.getStatus(), dmg=r.getDamage(), temp=r.getTemp(), heatRate=r.getHeatingRate(),
		fuel=r.getFuel('percent') or 0, waste=r.getWaste('percent') or 0,
		cool=r.getCoolant('percent') or 0, hot=r.getHeatedCoolant('percent') or 0,
		w=w,h=h
	}
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
	prevSnapshot = snap
	if changed.w or changed.h then layoutDirty=true; drawLayout() end
	local resources = {
		{key='cool', label='Coolant', pct=snap.cool, color=colors.lightBlue},
		{key='fuel', label='Fuel', pct=snap.fuel, color=colors.gray},
		{key='hot', label='Heated Coolant', pct=snap.hot, color=colors.pink},
		{key='waste', label='Waste', pct=snap.waste, color=colors.brown},
	}
	local boxH = floor(h/4)
	for i,res in ipairs(resources) do
		if changed[res.key] or not prevSnapshot then
			local y = 1 + (i-1)*boxH
			local bh = (i==4) and (h-y+1) or boxH
			local areaY = y+1
			drawBar(1, areaY, leftW, max(1,bh-1), res.pct, res.color)
			drawText(2,y,res.label,colors.white,colors.black,leftW-3)
			drawText(max(2,leftW-5),y,fmtStr('%d%%',floor(res.pct+0.5)),colors.white,colors.black,5)
		end
	end
	if changed.active or changed.dmg or changed.temp or changed.heatRate then
		local btnColor = snap.active and colors.lime or (safetyShutdown and (safetyHighDanger and colors.magenta or colors.orange) or colors.red)
		for yy=0,statusH-1 do
			term.setCursorPos(rightX,1+yy); term.setBackgroundColor(btnColor); term.write(string.rep(' ',rightW))
		end
		local statusTxt = snap.active and 'ONLINE' or 'OFFLINE'
		drawText(rightX+floor((rightW-#statusTxt)/2),1+floor(statusH/2),statusTxt,colors.white,btnColor,rightW)
		drawText(rightX+1,statusH+2,'Heat Rate: '..(snap.heatRate and (fmt(snap.heatRate)..' mB/t') or 'n/a'),colors.white,colors.gray,rightW-2)
		drawText(rightX+1,statusH+3,'Damage: '..(snap.dmg and (round(snap.dmg)..'%') or 'n/a'),colors.white,colors.gray,rightW-2)
		local t=convertTemp(snap.temp)
		drawText(rightX+1,statusH+4,'Temp: '..(t and (fmt(t)..DEG..TEMP_UNIT) or 'n/a'),colors.white,colors.gray,rightW-2)
	end
	local listY = topH+1
	for i,check in ipairs(safetyChecks) do
		local y=listY+i
		local label=(check.enabled and '[x] ' or '[ ] ')..check.label
		drawText(rightX+1,y,label,check.enabled and colors.lime or colors.lightGray,colors.gray,rightW-2)
	end
	term.setBackgroundColor(colors.black)
end

local function handleClick(x, y)
	for _, b in pairs(buttons) do
		if x >= b.x and x < b.x + b.w and y >= b.y and y <= b.y + (b.h or 1) - 1 then
			b.fn();
			prevSnapshot = nil
			layoutDirty = true
			draw();
			return
		end
	end
end

local function inputLoop()
	while true do
		local ev, a, b, c = pullEvent()
		if (useMon and ev == 'monitor_touch') then
			handleClick(b, c)
		elseif (not useMon and ev == 'mouse_click') then
			handleClick(b, c)
		elseif ev == 'term_resize' then
			draw()
		end
	end
end

local function autoRedraw()
	while true do
		local status = r.getStatus()

		if safetyMode then
			local coolant = r.getCoolant('percent') or 0
			local fuel = r.getFuel('percent') or 0
			local heated = r.getHeatedCoolant('percent') or 0
			local waste = r.getWaste('percent') or 0
			local tempK = r.getTemp() or 0
			local tempF = kelvinToF(tempK) or 0
			local dmg = r.getDamage() or 0

			if status then
				local reason, highDanger = nil, false
				if safetyChecks[6].enabled and dmg > SAFETY_DMG_HIGH then
					reason, highDanger = 'Damage >' .. SAFETY_DMG_HIGH .. '%', true
				elseif safetyChecks[7].enabled and tempF > SAFETY_TEMP_F then
					reason, highDanger = 'Temp >' .. SAFETY_TEMP_F .. 'F', true
				elseif safetyChecks[1].enabled and coolant < SAFETY_COOLANT_MIN then
					reason = 'Coolant <' .. SAFETY_COOLANT_MIN .. '%'
				elseif safetyChecks[2].enabled and fuel < SAFETY_FUEL_MIN then
					reason = 'Fuel <' .. SAFETY_FUEL_MIN .. '%'
				elseif safetyChecks[3].enabled and heated > SAFETY_HEATED_MAX then
					reason = 'Heated Coolant >' .. SAFETY_HEATED_MAX .. '%'
				elseif safetyChecks[4].enabled and waste > SAFETY_WASTE_MAX then
					reason = 'Waste >' .. SAFETY_WASTE_MAX .. '%'
				elseif safetyChecks[5].enabled and dmg > SAFETY_DMG_WARN then
					reason = 'Damage >' .. SAFETY_DMG_WARN .. '%'
				elseif safetyChecks[8].enabled and isRedstoneTriggered() then
					reason = 'Redstone signal'
				end
				if reason then
					r.setStatus(false)
					safetyShutdown = true
					safetyHighDanger = highDanger
					safetyLastReason = reason
					status = false
				end
			else
				if safetyShutdown and (not safetyHighDanger) then
					local allSafe = (not safetyChecks[1].enabled or coolant >= SAFETY_RESTART_COOLANT_MIN)
						and (not safetyChecks[2].enabled or fuel >= SAFETY_RESTART_FUEL_MIN)
						and (not safetyChecks[3].enabled or heated <= SAFETY_RESTART_HEATED_MAX)
						and (not safetyChecks[4].enabled or waste <= SAFETY_RESTART_WASTE_MAX)
						and (not safetyChecks[7].enabled or tempF <= SAFETY_RESTART_TEMP_MAX)
						and (not (safetyChecks[5].enabled or safetyChecks[6].enabled) or dmg <= SAFETY_RESTART_DMG_MAX)
						and (not safetyChecks[8].enabled or not isRedstoneTriggered())
					if allSafe then
						resetSafetyShutdown()
						r.setStatus(true)
						status = true
					end
				end
			end
		end
		draw();
		osSleep(REFRESH_INTERVAL)
	end
end

local function modemListener()
	while true do
		local _, _, ch, _, msg = _G.os.pullEvent('modem_message')
		if ch == MODEM_CHANNEL and type(msg) == 'table' and msg.type == 'reactor_data' then
			wirelessData = msg.data or {}
		end
	end
end

draw()
if parallel and parallel.waitForAny then
	if IS_WIRELESS then
		parallel.waitForAny(autoRedraw, inputLoop, modemListener)
	else
		parallel.waitForAny(autoRedraw, inputLoop)
	end
else
	autoRedraw()
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.white)
term.write('Reactor UI closed.')
