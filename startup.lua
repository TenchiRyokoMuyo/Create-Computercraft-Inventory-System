-- Frogport Central Command startup.lua
-- Place this file at /startup.lua and the Frogport folder at /Frogport

local ROOT = "/Frogport"
local LIB = ROOT .. "/FrogportLib.lua"
local DATA = ROOT .. "/data"
local ROLE_FILE = DATA .. "/role.cfg"

if not fs.exists(ROOT) then fs.makeDir(ROOT) end
if not fs.exists(DATA) then fs.makeDir(DATA) end

local function clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local data = h.readAll()
  h.close()
  return data
end

local function writeFile(path, data)
  local h = fs.open(path, "w")
  h.write(data)
  h.close()
end

if not fs.exists(LIB) then
  clear()
  print("FrogportLib.lua missing.")
  print("Expected: " .. LIB)
  return
end

clear()
print("Frogport Central Command")
print("-------------------------")

local role = readFile(ROLE_FILE)
if role then
  role = role:gsub("%s+", "")
end

if not role or role == "" then
  print("First boot setup")
  print("")
  print("Select role:")
  print("1. Vault Keeper")
  print("2. Producer")
  print("3. Consumer")
  print("4. Overseer")
  print("")
  write("> ")
  local choice = read()

  if choice == "1" then role = "vault"
  elseif choice == "2" then role = "producer"
  elseif choice == "3" then role = "consumer"
  elseif choice == "4" then role = "overseer"
  else
    print("Invalid role.")
    return
  end

  writeFile(ROLE_FILE, role)
end

local programMap = {
  vault = ROOT .. "/FrogportVaultKeeper.lua",
  producer = ROOT .. "/FrogportProducer.lua",
  consumer = ROOT .. "/FrogportConsumer.lua",
  overseer = ROOT .. "/FrogportOverseer.lua"
}

local program = programMap[role]
if not program or not fs.exists(program) then
  clear()
  print("Configured role: " .. tostring(role))
  print("Program missing: " .. tostring(program))
  print("")
  print("Delete " .. ROLE_FILE .. " to rerun setup.")
  return
end

shell.run(program)
