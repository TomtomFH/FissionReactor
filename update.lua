-- Automatic multiblock-aware clean updater
local BASE = "https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/"

local function detectMultiblock()
  local reactor, matrix = false, false
  for _, name in ipairs(peripheral.getNames()) do
    local kind = peripheral.getType(name)
    if kind == "inductionPort" then
      local p = peripheral.wrap(name)
      if p and type(p.getEnergy) == "function" and type(p.getMaxEnergy) == "function" then matrix = true end
    end
    if type(kind) == "string" and kind:lower():find("fissionreactor") then reactor = true end
    local methods = peripheral.getMethods(name) or {}
    local sig = {}
    for _, method in ipairs(methods) do sig[method] = true end
    if sig.getFuel or sig.getCoolant or sig.getBurnRate then reactor = true end
  end
  if reactor then return "reactor" end
  if matrix then return "matrix" end
end

local target = detectMultiblock()
if not target then error("No supported reactor or Induction Matrix detected. Existing installation was not changed.") end
local files = {"version.txt", "update.lua", target == "reactor" and "functions.lua" or "matrix.lua", target == "reactor" and "reactor.lua" or "matrix.lua"}
-- Remove duplicate entries while preserving order.
local unique, seen = {}, {}
for _, file in ipairs(files) do if not seen[file] then seen[file] = true; table.insert(unique, file) end end
files = unique
local function downloadFresh(file)
  local temp = file .. ".new"
  if fs.exists(temp) then fs.delete(temp) end
  print("Downloading " .. file .. "...")
  local ok = shell.run("wget " .. BASE .. file .. " " .. temp)
  if not ok or not fs.exists(temp) then error("Download failed: " .. file .. ". Current installation is untouched.") end
end
for _, file in ipairs(files) do downloadFresh(file) end
local old = {"startup.lua","functions.lua","reactor.lua","matrix.lua","reactor-modem.lua","version.txt","update.lua","install.lua"}
for _, file in ipairs(old) do if fs.exists(file) then fs.delete(file) end end
for _, file in ipairs(files) do fs.move(file .. ".new", file) end
fs.copy(target == "reactor" and "reactor.lua" or "matrix.lua", "startup.lua")
print("Installed updated " .. (target == "reactor" and "Fission Reactor" or "Induction Matrix") .. " controller.")
print("config.lua and unrelated files were preserved.")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
