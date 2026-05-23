-- Frogport Central Command startup.lua
-- Auto-resume launcher + scrollable shell, installer, and updater.
-- Normal boot: install missing files, then immediately run the configured role.
-- To open the menu instead: startup menu
-- To force update directly: startup update

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

local function clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function ensureDir(path)
  if path and path ~= "" and not fs.exists(path) then fs.makeDir(path) end
end

local function ensureBaseDirs()
  ensureDir(ROOT)
  ensureDir(DATA)
end

local function pause(msg)
  print(msg or "Press Enter to continue...")
  read()
end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local d = h.readAll()
  h.close()
  return d
end

local function writeFile(path, data)
  ensureDir(fs.getDir(path))
  local h = fs.open(path, "w")
  h.write(data)
  h.close()
end

local function role()
  local r = readFile(ROLE_FILE)
  if r then return r:gsub("%s+", "") end
  return nil
end

local function setRole(r)
  ensureBaseDirs()
  writeFile(ROLE_FILE, r)
end

local function deleteFile(path)
  if fs.exists(path) then fs.delete(path); return true end
  return false
end

local function downloadFile(url, path)
  if type(http) ~= "table" or type(http.get) ~= "function" then return false, "HTTP API is not enabled." end
  local handle, err = http.get(url)
  if not handle then return false, tostring(err or "http.get failed") end
  local body = handle.readAll()
  handle.close()
  if not body or body == "" then return false, "downloaded file was empty" end
  writeFile(path, body)
  return true
end

local function install(force)
  ensureBaseDirs()
  clear()
  print("Frogport Central Command")
  print(force and "Updating from GitHub" or "Installing missing files")
  print(string.rep("-", 30))
  print("")
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

local function scrollMenu(title, items, subtitle)
  local selected, top = 1, 1
  while true do
    clear()
    local w, h = term.getSize()
    term.setTextColor(colors.lime)
    print(title)
    term.setTextColor(colors.white)
    if subtitle and subtitle ~= "" then print(subtitle) end
    print(string.rep("-", math.min(w, 32)))
    local listHeight = h - 5
    if subtitle and subtitle ~= "" then listHeight = h - 6 end
    if listHeight < 3 then listHeight = 3 end
    if selected < top then top = selected end
    if selected > top + listHeight - 1 then top = selected - listHeight + 1 end
    for row = 0, listHeight - 1 do
      local i = top + row
      local item = items[i]
      if item then
        if i == selected then
          term.setTextColor(colors.black)
          term.setBackgroundColor(colors.white)
        else
          term.setTextColor(colors.white)
          term.setBackgroundColor(colors.black)
        end
        local label = item.label or tostring(item.value or i)
        if item.sub and item.sub ~= "" then label = label .. " - " .. item.sub end
        if #label > w then label = label:sub(1, w) end
        term.write(label .. string.rep(" ", math.max(0, w - #label)))
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        print("")
      end
    end
    term.setTextColor(colors.gray)
    print("Up/Down Enter | Q/Esc back")
    local _, key = os.pullEvent("key")
    if key == keys.up then selected = math.max(1, selected - 1)
    elseif key == keys.down then selected = math.min(#items, selected + 1)
    elseif key == keys.pageUp then selected = math.max(1, selected - listHeight)
    elseif key == keys.pageDown then selected = math.min(#items, selected + listHeight)
    elseif key == keys.home then selected = 1
    elseif key == keys["end"] then selected = #items
    elseif key == keys.enter or key == keys.numPadEnter then return items[selected].value, selected, items[selected]
    elseif key == keys.q or key == keys.escape or key == keys.backspace then return nil end
  end
end

local function chooseRole()
  local v = scrollMenu("Choose Frogport role", {
    { label = "Vault Keeper", value = "vault", sub = "storage vault + packager" },
    { label = "Producer", value = "producer", sub = "packager source" },
    { label = "Consumer", value = "consumer", sub = "watched inventories" },
    { label = "Overseer", value = "overseer", sub = "dashboard/config editor" },
    { label = "Clear role", value = "clear" },
  }, "Current role: " .. tostring(role() or "none"))
  if v == "clear" then deleteFile(ROLE_FILE)
  elseif v then setRole(v) end
end

local function resetRoleConfig()
  local r = role()
  if not r then clear(); print("No role configured."); sleep(1); return end
  local path = DATA .. "/" .. r .. ".cfg"
  clear()
  print("Reset config for " .. r .. "?")
  print("This deletes: " .. path)
  write("Type YES to confirm: ")
  if read() == "YES" then deleteFile(path); print("Deleted.") else print("Cancelled.") end
  sleep(1)
end

local function runRole()
  local r = role()
  if not r or not PROGRAMS[r] then chooseRole(); r = role() end
  if r and PROGRAMS[r] then
    if not fs.exists(PROGRAMS[r]) then print("Program missing. Run installer/update first."); sleep(2); return end
    shell.run(PROGRAMS[r])
  end
end

local function peripheralList()
  clear()
  print("Peripheral List")
  print(string.rep("-", 24))
  for _, n in ipairs(peripheral.getNames()) do print(n .. " : " .. tostring(peripheral.getType(n))) end
  pause()
end

local function menuLoop()
  while true do
    local choice = scrollMenu("Frogport Central Command Shell", {
      { label = "Run configured role", value = "run", sub = tostring(role() or "none") },
      { label = "Change role", value = "role" },
      { label = "Install missing files from GitHub", value = "install" },
      { label = "Force update files from GitHub", value = "update" },
      { label = "Reset this role's config", value = "reset" },
      { label = "Peripheral list", value = "peripherals" },
      { label = "Open CraftOS shell", value = "shell" },
      { label = "Reboot", value = "reboot" },
      { label = "Shutdown", value = "shutdown" },
    }, "Configured role: " .. tostring(role() or "none") .. " | normal boot auto-runs the role")
    if choice == nil or choice == "run" then runRole()
    elseif choice == "role" then chooseRole()
    elseif choice == "install" then install(false); pause()
    elseif choice == "update" then install(true); pause()
    elseif choice == "reset" then resetRoleConfig()
    elseif choice == "peripherals" then peripheralList()
    elseif choice == "shell" then clear(); print("Type 'exit' to return to Frogport shell."); shell.run("shell")
    elseif choice == "reboot" then os.reboot()
    elseif choice == "shutdown" then os.shutdown()
    end
  end
end

local args = { ... }
if args[1] == "update" or args[1] == "--update" then install(true); return end
if args[1] == "install" then install(false); return end
if args[1] == "menu" or args[1] == "shell" then install(false); menuLoop(); return end
if args[1] == "run" then if install(false) then runRole() end return end

if not install(false) then pause("Install failed. Press Enter for shell."); menuLoop(); return end
if role() then
  runRole()
else
  menuLoop()
end
