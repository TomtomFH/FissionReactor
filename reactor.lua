local ok, config = pcall(require, 'config')
if not ok or type(config) ~= 'table' then config = {} end

local IS_WIRELESS = config.IS_WIRELESS == true
local MODEM_CHANNEL = tonumber(config.MODEM_CHANNEL) or 42
local TEMP_IN_F = config.TEMP_IN_F == true -- default Celsius
local VERSION = '1.3.6'
local LATEST_VERSION = 'CHECKING'

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

local safetyShutdown = false

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
local safetyHighDanger = false
local safetyLastReason = nil
local damageRestartAt = nil
local safetyEnabled = {
	coolant = config.SAFETY_COOLANT_ENABLED ~= false,
	damage = config.SAFETY_DAMAGE_ENABLED ~= false,
	heated = config.SAFETY_HEATED_ENABLED ~= false,
	waste = config.SAFETY_WASTE_ENABLED ~= false,
}

local function saveSafetySettings()
	if not fs or not fs.open then return end
	local file = fs.open('config.lua', 'r')
	if not file then return end
	local content = file.readAll()
	file.close()
	local values = {
		SAFETY_COOLANT_ENABLED = safetyEnabled.coolant,
		SAFETY_DAMAGE_ENABLED = safetyEnabled.damage,
		SAFETY_HEATED_ENABLED = safetyEnabled.heated,
		SAFETY_WASTE_ENABLED = safetyEnabled.waste,
	}
	for key, value in pairs(values) do
		content = content:gsub(key .. '%s*=%s*%a+', key .. ' = ' .. tostring(value), 1)
	end
	file = fs.open('config.lua', 'w')
	if file then file.write(content); file.close() end
end

local function toggleSafety(key)
	safetyEnabled[key] = not safetyEnabled[key]
	saveSafetySettings()
	layoutDirty = true
	prevSnapshot = nil
end

-- Fixed safety limits: intentionally not configurable from config.lua or the UI.
local SAFETY_COOLANT_MIN = 10
local SAFETY_HEATED_MAX = 99
local SAFETY_WASTE_MAX = 99
local SAFETY_RESTART_COOLANT_MIN = 10
local SAFETY_RESTART_HEATED_MAX = 99
local SAFETY_RESTART_WASTE_MAX = 99

local function resetSafetyShutdown()
	safetyShutdown = false
	safetyHighDanger = false
	safetyLastReason = nil
	damageRestartAt = nil
end

-- Redstone alarm on the top face while a failsafe shutdown is active.
local function updateFailsafeRedstone()
	if rs and type(rs.setOutput) == 'function' then
		for _, side in ipairs(RS_SIDES) do
			pcall(rs.setOutput, side, safetyShutdown)
		end
	end
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
	local rounded = fmtStr('%.2f', abs(n))
	rounded = rounded:gsub('0+$', ''):gsub('%.$', '')
	local whole, fraction = rounded:match('^(%d+)%.?(%d*)$')
	if not whole then return tostring(n) end
	whole = whole:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
	local sign = n < 0 and '-' or ''
	return sign .. whole .. (fraction ~= '' and ('.' .. fraction) or '')
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

local function runUpdater()
	if not shell or not shell.run then return end
	shell.run("update")
end

local function rebootComputer()
	_G.os.reboot()
end

local layoutDirty = true
local prevSnapshot = nil
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
	drawText(rightX + 1, statusH + 2, 'Burn Rate:', colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, statusH + 3, 'Heat Rate:', colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, statusH + 4, 'Damage:', colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, statusH + 5, 'Temp:', colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, topH + 1, 'Safety: CHECKS', colors.white, colors.gray, rightW - 2)
	add('safety_coolant', rightX + 1, topH + 2, 3, 1, function() toggleSafety('coolant') end)
	add('safety_damage', rightX + 1, topH + 3, 3, 1, function() toggleSafety('damage') end)
	add('safety_heated', rightX + 1, topH + 4, 3, 1, function() toggleSafety('heated') end)
	add('safety_waste', rightX + 1, topH + 5, 3, 1, function() toggleSafety('waste') end)
	drawText(rightX + 1, topH + 7, 'Version: ' .. VERSION, colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, topH + 8, 'Latest: ' .. LATEST_VERSION, colors.white, colors.gray, rightW - 2)

	local updateY = topH + 10
	local autoY = topH + 11
	local rebootY = topH + 12
	if rebootY > h then
		updateY = h - 3
		autoY = h - 2
		rebootY = h
	end
	add('update', rightX + 1, updateY, rightW - 2, 1, runUpdater)
	add('auto', rightX + 1, autoY, rightW - 2, 1, toggleAutoUpdate)
	add('reboot', rightX + 1, rebootY, rightW - 2, 1, rebootComputer)
	drawBtn({x=rightX + 1, y=updateY, w=rightW - 2, h=1, l='UPDATE'}, nil, colors.blue, colors.white)
	drawBtn({x=rightX + 1, y=autoY, w=rightW - 2, h=1, l='AUTO UPDATE: ' .. (autoUpdateEnabled and 'ON' or 'OFF')}, nil, autoUpdateEnabled and colors.green or colors.gray, colors.white)
	drawBtn({x=rightX + 1, y=rebootY, w=rightW - 2, h=1, l='REBOOT'}, nil, colors.red, colors.white)
	buttons = newButtons
	layoutDirty = false
end
local function draw()
	w, h = term.getSize()
	local dimensionsChanged = prevSnapshot and (w ~= prevSnapshot.w or h ~= prevSnapshot.h)
	local redrawAll = layoutDirty or dimensionsChanged
	if redrawAll then layoutDirty = true; drawLayout() end
	local rightW = max(15, floor(w * 0.23))
	if w - rightW < 25 then rightW = max(12, w - 25) end
	local leftW = w - rightW - 1
	local rightX = leftW + 2
	local topH = floor(h / 2)
	local statusH = max(2, floor(topH / 5))
	local snap = {
		active=r.getStatus(), dmg=r.getDamage(), temp=r.getTemp(), heatRate=r.getHeatingRate(),
		burnRate=r.getBurnRate(),
		fuel=r.getFuel('percent'), fuelAmount=r.getFuel(), fuelMax=r.getFuel('max'),
		waste=r.getWaste('percent'), wasteAmount=r.getWaste(), wasteMax=r.getWaste('max'),
		cool=r.getCoolant('percent'), coolAmount=r.getCoolant(), coolMax=r.getCoolant('max'),
		hot=r.getHeatedCoolant('percent'), hotAmount=r.getHeatedCoolant(), hotMax=r.getHeatedCoolant('max'),
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
	if redrawAll or changed.w or changed.h then
		for k in pairs(snap) do changed[k] = true end
	end
	prevSnapshot = snap
	local resources = {
		{key='cool', label='Coolant', pct=snap.cool or 0, color=colors.lightBlue},
		{key='fuel', label='Fuel', pct=snap.fuel or 0, color=colors.gray},
		{key='hot', label='Heated Coolant', pct=snap.hot or 0, color=colors.pink},
		{key='waste', label='Waste', pct=snap.waste or 0, color=colors.brown},
	}
	local boxH = floor(h/4)
	for i,res in ipairs(resources) do
		local amountKey = res.key .. 'Amount'
		local maxKey = res.key .. 'Max'
		if changed[res.key] or changed[amountKey] or changed[maxKey] or not prevSnapshot then
			local y = 1 + (i-1)*boxH
			local bh = (i==4) and (h-y+1) or boxH
			local areaY = y+1
			drawBar(1, areaY, leftW, max(1,bh-1), res.pct, res.color)
			local amount = snap[amountKey]
			local capacity = snap[maxKey]
			local exact = (amount ~= nil and capacity ~= nil) and (fmt(amount)..' / '..fmt(capacity)) or (amount ~= nil and fmt(amount) or 'n/a')
			local pctText = fmtStr('%d%%',floor((res.pct or 0)+0.5))
			drawText(2,y,res.label,colors.white,colors.black,leftW-3)
			local valueText = exact .. ' (' .. pctText .. ')'
			drawText(max(2,leftW-#valueText-1),y,valueText,colors.white,colors.black,leftW)
		end
	end
	local restartText = 'Restart: --'
	if safetyShutdown and safetyHighDanger and damageRestartAt then
		restartText = 'Restart: ' .. math.max(0, math.ceil(damageRestartAt - osClock())) .. 's'
	end
	drawText(rightX + 1, topH + 6, string.rep(' ', rightW - 2), colors.white, colors.gray, rightW - 2)
	drawText(rightX + 1, topH + 6, restartText, colors.white, colors.gray, rightW - 2)
	if changed.cool or changed.dmg or changed.hot or changed.waste or redrawAll then
		local function pct(v)
			return v ~= nil and (fmt(v) .. '%') or 'n/a'
		end
		local function safetyColor(tripped)
			return tripped and colors.red or colors.white
		end
		local safetyRows = {
			{key='coolant', y=topH+2, label='Coolant <10/' .. pct(snap.cool), tripped=type(snap.cool)=='number' and snap.cool<SAFETY_COOLANT_MIN},
			{key='damage', y=topH+3, label='Damage >0/' .. pct(snap.dmg), tripped=type(snap.dmg)=='number' and snap.dmg>0},
			{key='heated', y=topH+4, label='Heat >99/' .. pct(snap.hot), tripped=type(snap.hot)=='number' and snap.hot>SAFETY_HEATED_MAX},
			{key='waste', y=topH+5, label='Waste >99/' .. pct(snap.waste), tripped=type(snap.waste)=='number' and snap.waste>SAFETY_WASTE_MAX},
		}
		for _, row in ipairs(safetyRows) do
			local enabled = safetyEnabled[row.key]
			local fg = safetyColor(row.tripped)
			local boxText = enabled and '[x]' or '[ ]'
			drawText(rightX + 1, row.y, boxText, enabled and colors.lime or colors.white, colors.gray, 3)
			drawText(rightX + 5, row.y, row.label, fg, colors.gray, rightW - 6)
			if not enabled then
				-- CC:Tweaked terminals have no native strike-through; dim the disabled label
				-- while retaining red/white trip coloring and the unchecked box.
				drawText(rightX + 5, row.y, row.label, row.tripped and colors.red or colors.lightGray, colors.gray, rightW - 6)
			end
		end
	end
	if changed.active or changed.dmg or changed.temp or changed.heatRate or changed.burnRate then
		local btnColor = snap.active and colors.lime or (safetyShutdown and (safetyHighDanger and colors.magenta or colors.orange) or colors.red)
		for yy=0,statusH-1 do
			term.setCursorPos(rightX,1+yy); term.setBackgroundColor(btnColor); term.write(string.rep(' ',rightW))
		end
		local statusTxt = snap.active and 'ONLINE' or 'OFFLINE'
		drawText(rightX+floor((rightW-#statusTxt)/2),1+floor(statusH/2),statusTxt,colors.white,btnColor,rightW)
		drawText(rightX+1,statusH+2,'Burn Rate: '..(snap.burnRate and (fmt(snap.burnRate)..' mB/t') or 'n/a'),colors.white,colors.gray,rightW-2)
		drawText(rightX+1,statusH+3,'Heat Rate: '..(snap.heatRate and (fmt(snap.heatRate)..' mB/t') or 'n/a'),colors.white,colors.gray,rightW-2)
		drawText(rightX+1,statusH+4,'Damage: '..(snap.dmg ~= nil and (fmt(snap.dmg)..'%') or 'n/a'),colors.white,colors.gray,rightW-2)
		local t=convertTemp(snap.temp)
		drawText(rightX+1,statusH+5,'Temp: '..(t and (fmt(t)..DEG..TEMP_UNIT) or 'n/a'),colors.white,colors.gray,rightW-2)
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

		local coolant = r.getCoolant('percent')
		local heated = r.getHeatedCoolant('percent')
		local waste = r.getWaste('percent')
		local dmg = r.getDamage()

		if status then
			local reason = nil
			if safetyEnabled.damage and type(dmg) == 'number' and dmg > 0 then
				reason = 'Damage detected'
			elseif safetyEnabled.coolant and type(coolant) == 'number' and coolant < SAFETY_COOLANT_MIN then
				reason = 'Coolant <' .. SAFETY_COOLANT_MIN .. '%'
			elseif safetyEnabled.heated and type(heated) == 'number' and heated > SAFETY_HEATED_MAX then
				reason = 'Heated Coolant >' .. SAFETY_HEATED_MAX .. '%'
			elseif safetyEnabled.waste and type(waste) == 'number' and waste > SAFETY_WASTE_MAX then
				reason = 'Waste >' .. SAFETY_WASTE_MAX .. '%'
			end

			if reason then
				r.setStatus(false)
				safetyShutdown = true
				-- Damage is an emergency trip: require a manual restart after inspection.
				safetyHighDanger = safetyEnabled.damage and type(dmg) == 'number' and dmg > 0
				safetyLastReason = reason
				status = false
			end
		elseif safetyShutdown and safetyHighDanger then
			if type(dmg) ~= 'number' or dmg > 0 then
				damageRestartAt = nil
			else
				if not damageRestartAt then
					damageRestartAt = osClock() + 60
				end
				local countdownDone = osClock() >= damageRestartAt
				local allSafe = (not safetyEnabled.coolant or (type(coolant) == 'number' and coolant >= SAFETY_RESTART_COOLANT_MIN))
					and (not safetyEnabled.heated or (type(heated) == 'number' and heated <= SAFETY_RESTART_HEATED_MAX))
					and (not safetyEnabled.waste or (type(waste) == 'number' and waste <= SAFETY_RESTART_WASTE_MAX))
				if countdownDone and allSafe then
					resetSafetyShutdown()
					r.setStatus(true)
					status = true
				end
			end
		elseif safetyShutdown and not safetyHighDanger then
			local allSafe = (not safetyEnabled.coolant or (type(coolant) == 'number' and coolant >= SAFETY_RESTART_COOLANT_MIN))
				and (not safetyEnabled.heated or (type(heated) == 'number' and heated <= SAFETY_RESTART_HEATED_MAX))
				and (not safetyEnabled.waste or (type(waste) == 'number' and waste <= SAFETY_RESTART_WASTE_MAX))
				and (not safetyEnabled.damage or (type(dmg) == 'number' and dmg <= 0))
			if allSafe then
				resetSafetyShutdown()
				r.setStatus(true)
				status = true
			end
		end

		updateFailsafeRedstone()
		draw()
		osSleep(REFRESH_INTERVAL)
	end
end

local function versionChecker()
	while true do
		local latest = nil
		local ok, response = pcall(function()
			if not http or not http.get then return nil end
			return http.get('https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/version.txt', nil, true)
		end)
		if ok and response then
			latest = response.readAll()
			response.close()
			if latest then latest = latest:gsub('%s+', '') end
		end
		if latest then
			LATEST_VERSION = latest
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
		else
			LATEST_VERSION = 'UNKNOWN'
		end
		layoutDirty = true
		draw()
		osSleep(300)
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

local function supervise(name, fn)
	while true do
		local ok, err = pcall(fn)
		if not ok then
			-- Keep the UI process alive through chunk unloads/peripheral detach errors.
			pcall(function()
				term.setBackgroundColor(colors.black)
				term.setTextColor(colors.red)
				term.setCursorPos(1, h)
				term.write((name .. ' recovering: ' .. tostring(err)):sub(1, w))
			end)
			layoutDirty = true
			prevSnapshot = nil
			osSleep(2)
		else
			osSleep(0.5)
		end
	end
end

draw()
if parallel and parallel.waitForAny then
	if IS_WIRELESS then
		parallel.waitForAny(
			function() supervise('Monitor', autoRedraw) end,
			function() supervise('Input', inputLoop) end,
			function() supervise('Modem', modemListener) end,
			function() supervise('Version check', versionChecker) end
		)
	else
		parallel.waitForAny(
			function() supervise('Monitor', autoRedraw) end,
			function() supervise('Input', inputLoop) end,
			function() supervise('Version check', versionChecker) end
		)
	end
else
	supervise('Monitor', autoRedraw)
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.white)
term.write('Reactor UI closed.')
