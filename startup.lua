-- Frogport Central Command startup.lua
-- Place this file at /startup.lua. On boot it will install any missing Frogport files
-- from the GitHub repository, then launch the configured role.

local args = { ... }

local ROOT = "/Frogport"
local DATA = ROOT .. "/data"
local ROLE_FILE = DATA .. "/role.cfg"

local REPO_RAW = "https://raw.githubusercontent.com/TenchiRyokoMuyo/Create-Computercraft-Inventory-System/main"

local REQUIRED_FILES = {
  { path = "/Frogport/FrogportLib.lua",          url = REPO_RAW .. "/Frogport/FrogportLib.lua" },
  { path = "/Frogport/FrogportVaultKeeper.lua",  url = REPO_RAW .. "/Frogport/FrogportVaultKeeper.lua" },
  { path = "/Frogport/FrogportProducer.lua",     url = REPO_RAW .. "/Frogport/FrogportProducer.lua" },
  { path = "/Frogport/FrogportConsumer.lua",     url = REPO_RAW .. "/Frogport/FrogportConsumer.lua" },
  { path = "/Frogport/FrogportOverseer.lua",     url = REPO_RAW .. "/Frogport/FrogportOverseer.lua" },
  { path = "/README.txt",                        url = REPO_RAW .. "/README.txt" },
}

local function clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function pause(msg)
  print(msg or "Press Enter to continue...")
  read()
end

local function dirname(path)
  return fs.getDir(path)
end

local function ensureDir(path)
  if path and path ~= "" and not fs.exists(path) then
    fs.makeDir(path)
  end
end

local function ensureBaseDirs()
  ensureDir(ROOT)
  ensureDir(DATA)
end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local data = h.readAll()
  h.close()
  return data
end

local function writeFile(path, data)
  ensureDir(dirname(path))
  local h = fs.open(path, "w")
  h.write(data)
  h.close()
end

local function httpAvailable()
  return type(http) == "table" and type(http.get) == "function"
end

local function downloadFile(url, path)
  if not httpAvailable() then
    return false, "HTTP API is not enabled. Enable http in ComputerCraft config or upload files manually."
  end

  local handle, err = http.get(url)
  if not handle then
    return false, tostring(err or "http.get failed")
  end

  local body = handle.readAll()
  handle.close()

  if not body or body == "" then
    return false, "downloaded file was empty"
  end

  writeFile(path, body)
  return true
end

local function installMissingFiles(force)
  ensureBaseDirs()

  local missing = {}
  for _, file in ipairs(REQUIRED_FILES) do
    if force or not fs.exists(file.path) then
      table.insert(missing, file)
    end
  end

  if #missing == 0 then
    return true
  end

  clear()
  print("Frogport Central Command")
  print("Installing missing files")
  print("------------------------")
  print("")

  for _, file in ipairs(missing) do
    print("Downloading: " .. file.path)
    local ok, err = downloadFile(file.url, file.path)
    if not ok then
      print("")
      print("Failed to install:")
      print(file.path)
      print("")
      print("Reason:")
      print(tostring(err))
      print("")
      print("Repository URL:")
      print("github.com/TenchiRyokoMuyo/Create-Computercraft-Inventory-System")
      return false
    end
  end

  print("")
  print("Install complete.")
  sleep(1)
  return true
end

local forceUpdate = false
for _, arg in ipairs(args) do
  if tostring(arg):lower() == "update" or tostring(arg):lower() == "--update" then
    forceUpdate = true
  end
end

if not installMissingFiles(forceUpdate) then
  pause()
  return
end

clear()
print("Frogport Central Command")
print("-------------------------")
print("")

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
  print("Run this to force reinstall:")
  print("startup update")
  print("")
  print("Or delete " .. ROLE_FILE .. " to rerun setup.")
  return
end

shell.run(program)
