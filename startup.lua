-- Frogport Central Command startup.lua
-- Shell-style launcher, installer, and updater for Create + ComputerCraft inventory system.

local ROOT = "/Frogport"
local DATA = ROOT .. "/data"
local ROLE_FILE = DATA .. "/role.cfg"
local REPO_RAW = "https://raw.githubusercontent.com/TenchiRyokoMuyo/Create-Computercraft-Inventory-System/main"

local REQUIRED_FILES = {
  { path = "/Frogport/FrogportLib.lua",         url = REPO_RAW .. "/Frogport/FrogportLib.lua" },
  { path = "/Frogport/FrogportVaultKeeper.lua", url = REPO_RAW .. "/Frogport/FrogportVaultKeeper.lua" },
  { path = "/Frogport/FrogportProducer.lua",    url = REPO_RAW .. "/Frogport/FrogportProducer.lua" },
  { path = "/Frogport/FrogportConsumer.lua",    url = REPO_RAW .. "/Frogport/FrogportConsumer.lua" },
  { path = "/Frogport/FrogportOverseer.lua",    url = REPO_RAW .. "/Frogport/FrogportOverseer.lua" },
  { path = "/README.txt",                       url = REPO_RAW .. "/README.txt" },
}

local PROGRAMS = {
  vault = ROOT .. "/FrogportVaultKeeper.lua",
  producer = ROOT .. "/FrogportProducer.lua",
  consumer = ROOT .. "/FrogportConsumer.lua",
  overseer = ROOT .. "/FrogportOverseer.lua",
}

local function clear() term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1) end
local function ensureDir(path) if path and path ~= "" and not fs.exists(path) then fs.makeDir(path) end end
local function ensureBaseDirs() ensureDir(ROOT); ensureDir(DATA) end
local function pause(msg) print(msg or "Press Enter to continue..."); read() end
local function readFile(path) if not fs.exists(path) then return nil end local h = fs.open(path,"r"); local d = h.readAll(); h.close(); return d end
local function writeFile(path, data) ensureDir(fs.getDir(path)); local h = fs.open(path,"w"); h.write(data); h.close() end
local function role() local r = readFile(ROLE_FILE); if r then return r:gsub("%s+","") end return nil end
local function setRole(r) ensureBaseDirs(); writeFile(ROLE_FILE, r) end

local function downloadFile(url, path)
  if type(http) ~= "table" or type(http.get) ~= "function" then return false, "HTTP API is not enabled." end
  local handle, err = http.get(url)
  if not handle then return false, tostring(err or "http.get failed") end
  local body = handle.readAll(); handle.close()
  if not body or body == "" then return false, "downloaded file was empty" end
  writeFile(path, body); return true
end

local function install(force)
  ensureBaseDirs()
  clear(); print("Frogport Central Command"); print(force and "Updating from GitHub" or "Installing missing files"); print(string.rep("-", 30)); print("")
  local count = 0
  for _, file in ipairs(REQUIRED_FILES) do
    if force or not fs.exists(file.path) then
      print("Downloading " .. file.path)
      local ok, err = downloadFile(file.url, file.path)
      if not ok then print("FAILED: " .. tostring(err)); return false end
      count = count + 1
    end
  end
  if count == 0 then print("All required files already exist.") else print("Installed/updated " .. count .. " file(s).") end
  return true
end

local function deleteFile(path)
  if fs.exists(path) then fs.delete(path); return true end
  return false
end

local function chooseRole()
  clear(); print("Choose Frogport role"); print(string.rep("-", 22)); print("1. Vault Keeper"); print("2. Producer"); print("3. Consumer"); print("4. Overseer"); print("5. Clear role")
  write("> "); local c = read()
  if c == "1" then setRole("vault")
  elseif c == "2" then setRole("producer")
  elseif c == "3" then setRole("consumer")
  elseif c == "4" then setRole("overseer")
  elseif c == "5" then deleteFile(ROLE_FILE)
  else print("Invalid choice."); sleep(1); return end
  print("Role set to: " .. tostring(role() or "none")); sleep(1)
end

local function resetRoleConfig()
  local r = role()
  if not r then print("No role configured."); sleep(1); return end
  local path = DATA .. "/" .. r .. ".cfg"
  clear(); print("Reset config for " .. r .. "?"); print("This deletes: " .. path); write("Type YES to confirm: ")
  if read() == "YES" then deleteFile(path); print("Deleted.") else print("Cancelled.") end
  sleep(1)
end

local function runRole()
  local r = role()
  if not r or not PROGRAMS[r] then print("No role configured."); sleep(1); chooseRole(); r = role() end
  if r and PROGRAMS[r] then
    if not fs.exists(PROGRAMS[r]) then print("Program missing. Run installer/update first."); sleep(2); return end
    shell.run(PROGRAMS[r])
  end
end

local args = { ... }
if args[1] == "update" or args[1] == "--update" then install(true); return end
if args[1] == "run" then if install(false) then runRole() end return end

while true do
  install(false)
  clear()
  print("Frogport Central Command Shell")
  print(string.rep("-", 31))
  print("Configured role: " .. tostring(role() or "none"))
  print("")
  print("1. Run configured role")
  print("2. Change role")
  print("3. Install missing files from GitHub")
  print("4. Force update files from GitHub")
  print("5. Reset this role's config")
  print("6. Peripheral list")
  print("7. Open CraftOS shell")
  print("8. Reboot")
  print("9. Shutdown")
  print("")
  write("> ")
  local c = read()
  if c == "1" then runRole()
  elseif c == "2" then chooseRole()
  elseif c == "3" then install(false); pause()
  elseif c == "4" then install(true); pause()
  elseif c == "5" then resetRoleConfig()
  elseif c == "6" then clear(); for _, n in ipairs(peripheral.getNames()) do print(n .. " : " .. tostring(peripheral.getType(n))) end; pause()
  elseif c == "7" then clear(); print("Type 'exit' to return to Frogport shell."); shell.run("shell")
  elseif c == "8" then os.reboot()
  elseif c == "9" then os.shutdown()
  end
end
