-- Fission Reactor updater
-- Run with: update
local BASE = "https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/"

local function download(file)
	print("Updating " .. file .. "...")
	-- Use the complete URL in one command string for CC:Tweaked's wget.
	if fs.exists(file) then
		fs.delete(file)
	end
	local ok = shell.run("wget " .. BASE .. file .. " " .. file)
	if not ok or not fs.exists(file) then
		error("Failed to download " .. file .. ". Check the internet connection and try again.")
	end
end

-- Detect the installed role before replacing startup.lua.
local bridgeMode = false
if fs.exists("startup.lua") then
	local h = fs.open("startup.lua", "r")
	if h then
		local oldStartup = h.readAll()
		h.close()
		bridgeMode = oldStartup:find("Reactor Modem Bridge", 1, true) ~= nil
			or oldStartup:find("reactor-modem.lua", 1, true) ~= nil
	end
end

download("version.txt")
download("functions.lua")
download("reactor.lua")
download("reactor-modem.lua")

-- Remove the existing startup file first; fs.copy does not overwrite it.
if fs.exists("startup.lua") then
	fs.delete("startup.lua")
end
if bridgeMode then
	fs.copy("reactor-modem.lua", "startup.lua")
else
	fs.copy("reactor.lua", "startup.lua")
end

print("")
term.setTextColor(colors.lime)
print("Fission Reactor updated successfully!")
term.setTextColor(colors.white)
print("Your config.lua was left unchanged.")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
