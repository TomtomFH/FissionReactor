local BASE = "https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/"

local function header()
	term.setTextColor(colors.lime)
	print("Fission Reactor Control System")
	print("==============================")
	term.setTextColor(colors.white)
	print("")
end

header()
print("Installing wired Display Computer...")
print("")

local files = {
	"version.txt",
	"functions.lua",
	"update.lua",
	"config.lua",
	"reactor.lua"
}

for _, file in ipairs(files) do
	print("Downloading " .. file .. "...")
	local ok = shell.run("wget " .. BASE .. file .. " " .. file)
	if not ok or not fs.exists(file) then
		term.setTextColor(colors.red)
		print("Failed to download " .. file .. ". Installation stopped.")
		term.setTextColor(colors.white)
		return
	end
end

if fs.exists("startup.lua") then
	fs.delete("startup.lua")
end
fs.copy("reactor.lua", "startup.lua")

-- Force direct cable mode for this wired-only installer.
local config = fs.open("config.lua", "r")
if config then
	local content = config.readAll()
	config.close()
	content = content:gsub("IS_WIRELESS%s*=%s*%a+", "IS_WIRELESS = false")
	config = fs.open("config.lua", "w")
	if config then
		config.write(content)
		config.close()
	end
end

print("")
term.setTextColor(colors.lime)
print("Wired Display Computer installed!")
term.setTextColor(colors.white)
print("Make sure the Logic Adapter is connected to this computer.")
print("Reboot to start.")
