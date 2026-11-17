-- Fission Reactor updater
-- Run with: update
local BASE = "https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/"

local function download(file)
	print("Updating " .. file .. "...")
	local ok = shell.run("wget", "-f", BASE .. file, file)
	if not ok then
		error("Failed to download " .. file .. ". Check the connection and try again.")
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
