local BASE = "https://raw.githubusercontent.com/TomtomFH/FissionReactor/refs/heads/main/"

local function header()
  term.setTextColor(colors.lime)
  print("Fission Reactor / Induction Matrix Control")
  print("==========================================")
  term.setTextColor(colors.white)
  print("")
end

local function detectMultiblock()
  local foundReactor, foundMatrix = false, false
  for _, name in ipairs(peripheral.getNames()) do
    local kind = peripheral.getType(name)
    if kind == "inductionPort" then
      local p = peripheral.wrap(name)
      if p and type(p.getEnergy) == "function" and type(p.getMaxEnergy) == "function" then
        foundMatrix = true
      end
    end
    if type(kind) == "string" and kind:lower():find("fissionreactor") then
      foundReactor = true
    end
    local methods = peripheral.getMethods(name) or {}
    local sig = {}
    for _, method in ipairs(methods) do sig[method] = true end
    if sig.getFuel or sig.getCoolant or sig.getBurnRate then foundReactor = true end
  end
  if foundReactor then return "reactor" end
  if foundMatrix then return "matrix" end
  return nil
end

header()
print("Detecting connected multiblock...")
local target = detectMultiblock()
if not target then
  term.setTextColor(colors.red)
  print("No supported reactor or Induction Matrix found.")
  term.setTextColor(colors.white)
  print("Connect its Logic Adapter or Induction Port")
  print("to this computer using Wired Modems.")
  return
end
print("Detected: " .. (target == "reactor" and "Fission Reactor" or "Induction Matrix"))
local files = {"version.txt", "update.lua", "config.lua"}
if target == "reactor" then
  table.insert(files, "functions.lua")
  table.insert(files, "reactor.lua")
else
  table.insert(files, "matrix.lua")
end
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
if fs.exists("startup.lua") then fs.delete("startup.lua") end
fs.copy(target == "reactor" and "reactor.lua" or "matrix.lua", "startup.lua")
print("")
term.setTextColor(colors.lime)
print((target == "reactor" and "Reactor" or "Induction Matrix") .. " controller installed!")
term.setTextColor(colors.white)
print("Reboot to start.")
