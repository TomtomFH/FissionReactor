-- Fission Reactor clean updater
-- Run with: update
-- Reinstalls the wired display computer files and preserves config.lua only.

local BASE = "https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/"

local function downloadFresh(file)
	local temp = file .. ".new"
	if fs.exists(temp) then fs.delete(temp) end
	print("Downloading " .. file .. "...")
	local ok = shell.run("wget " .. BASE .. file .. " " .. temp)
	if not ok or not fs.exists(temp) then
		error("Failed to download " .. file .. ". Existing installation has been left in place.")
	end
end

local files = {
	"version.txt",
	"functions.lua",
	"reactor.lua",
	"reactor-modem.lua",
	"update.lua"
}

-- Download and verify all new files before replacing the working installation.
for _, file in ipairs(files) do
	downloadFresh(file)
end

print("")
print("Installing fresh wired display computer...")

-- Remove known program files, but never touch config.lua or unrelated user files.
local oldFiles = {
	"startup.lua",
	"functions.lua",
	"reactor.lua",
	"reactor-modem.lua",
	"version.txt",
	"update.lua",
	"install.lua"
}
for _, file in ipairs(oldFiles) do
	if fs.exists(file) then fs.delete(file) end
end

for _, file in ipairs(files) do
	fs.move(file .. ".new", file)
end

-- This project now supports wired Display Computer mode only.
fs.copy("reactor.lua", "startup.lua")

print("")
term.setTextColor(colors.lime)
print("Fresh installation completed!")
term.setTextColor(colors.white)
print("config.lua was preserved.")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
