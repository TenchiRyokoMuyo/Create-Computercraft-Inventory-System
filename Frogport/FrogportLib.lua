-- FrogportLib.lua
-- Shared utilities for Frogport Central Command

local Lib = {}

Lib.VERSION = 1
Lib.PROTOCOL = "FROGPORT"
Lib.CHANNEL = 6610
Lib.ROOT = "/Frogport"
Lib.DATA = "/Frogport/data"

Lib.DEFAULTS = {
  defaultStackSize = 64,
  pulseLength = 0.25,
  producerCooldown = 2.0,
  vaultPulseCooldown = 0.5,
  emptyInterval = 0.5,
  heartbeatInterval = 5.0,
  scanInterval = 1.0,

  fullMin = 95,
  stockNeededMin = 75,
  lowMin = 50,
  criticalMin = 10,

  stockNeededInterval = 5,
  lowInterval = 3,
  criticalInterval = 1
}

Lib.SIDES = { "top", "bottom", "left", "right", "front", "back" }

function Lib.ensureDirs()
  if not fs.exists(Lib.ROOT) then fs.makeDir(Lib.ROOT) end
  if not fs.exists(Lib.DATA) then fs.makeDir(Lib.DATA) end
end

function Lib.readAll(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local data = h.readAll()
  h.close()
  return data
end

function Lib.writeAll(path, data)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(path, "w")
  h.write(data)
  h.close()
end

function Lib.loadTable(path, fallback)
  local data = Lib.readAll(path)
  if not data then return fallback end
  local ok, result = pcall(textutils.unserialize, data)
  if ok and type(result) == "table" then return result end
  return fallback
end

function Lib.saveTable(path, tbl)
  Lib.writeAll(path, textutils.serialize(tbl))
end

function Lib.uuid(prefix)
  local id = tostring(os.getComputerID())
  return (prefix or "NODE") .. "_" .. id
end

function Lib.trim(s)
  if s == nil then return "" end
  return tostring(s):match("^%s*(.-)%s*$")
end

function Lib.clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
end

function Lib.header(title)
  Lib.clear()
  term.setTextColor(colors.lime)
  print("Frogport Central Command")
  term.setTextColor(colors.white)
  print(title or "")
  print(string.rep("-", 28))
end

function Lib.askString(label, default)
  if default and default ~= "" then
    write(label .. " [" .. tostring(default) .. "]: ")
  else
    write(label .. ": ")
  end
  local v = read()
  v = Lib.trim(v)
  if v == "" then return default end
  return v
end

function Lib.askNumber(label, default, minValue, maxValue)
  while true do
    local raw = Lib.askString(label, tostring(default))
    local n = tonumber(raw)
    if n and (not minValue or n >= minValue) and (not maxValue or n <= maxValue) then
      return n
    end
    print("Enter a number" ..
      (minValue and (" >= " .. minValue) or "") ..
      (maxValue and (" <= " .. maxValue) or "") .. ".")
  end
end

function Lib.isSide(name)
  for _, s in ipairs(Lib.SIDES) do
    if name == s then return true end
  end
  return false
end

function Lib.typeString(name)
  local ok, t = pcall(peripheral.getType, name)
  if not ok or not t then return "" end
  if type(t) == "table" then
    return table.concat(t, ","):lower()
  end
  return tostring(t):lower()
end

function Lib.hasMethod(name, method)
  local ok, methods = pcall(peripheral.getMethods, name)
  if not ok or type(methods) ~= "table" then return false end
  for _, m in ipairs(methods) do
    if m == method then return true end
  end
  return false
end

function Lib.detectPeripherals()
  local found = {
    modems = {},
    monitors = {},
    packagers = {},
    inventories = {}
  }

  for _, name in ipairs(peripheral.getNames()) do
    local t = Lib.typeString(name)
    local isModem = t:find("modem", 1, true) ~= nil
    local isMonitor = t:find("monitor", 1, true) ~= nil
    local isPackager = t:find("packager", 1, true) ~= nil

    if isModem then table.insert(found.modems, name) end
    if isMonitor then table.insert(found.monitors, name) end
    if isPackager then table.insert(found.packagers, name) end

    local looksInventory =
      Lib.hasMethod(name, "list") and
      (Lib.hasMethod(name, "size") or Lib.hasMethod(name, "getItemDetail"))

    if looksInventory and not isModem and not isMonitor and not isPackager then
      table.insert(found.inventories, name)
    end
  end

  table.sort(found.modems)
  table.sort(found.monitors)
  table.sort(found.packagers)
  table.sort(found.inventories)

  return found
end

function Lib.printDetection(found)
  print("Detected peripherals:")
  print("Modems:")
  for _, v in ipairs(found.modems) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
  print("Monitors:")
  for _, v in ipairs(found.monitors) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
  print("Packagers:")
  for _, v in ipairs(found.packagers) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
  print("Inventories:")
  for _, v in ipairs(found.inventories) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
end

function Lib.openModems(modemNames, channel)
  channel = channel or Lib.CHANNEL
  for _, name in ipairs(modemNames or {}) do
    local p = peripheral.wrap(name)
    if p and p.open then
      pcall(function()
        if not p.isOpen(channel) then p.open(channel) end
      end)
    end
  end
end

function Lib.transmit(modemNames, packet)
  packet.protocol = Lib.PROTOCOL
  packet.version = Lib.VERSION
  packet.time = os.epoch("utc")
  for _, name in ipairs(modemNames or {}) do
    local p = peripheral.wrap(name)
    if p and p.transmit then
      pcall(function() p.transmit(Lib.CHANNEL, Lib.CHANNEL, packet) end)
    end
  end
end

function Lib.validPacket(msg)
  return type(msg) == "table" and msg.protocol == Lib.PROTOCOL and msg.version == Lib.VERSION
end

function Lib.countItem(invName, itemName, defaultStack)
  defaultStack = tonumber(defaultStack) or Lib.DEFAULTS.defaultStackSize
  itemName = Lib.trim(itemName)

  local inv = peripheral.wrap(invName)
  if not inv or not inv.list or not inv.size then
    return { count = 0, capacity = 0, percent = 0, slots = 0, usedSlots = 0, matchingSlots = 0 }
  end

  local okSize, size = pcall(inv.size)
  if not okSize or type(size) ~= "number" then size = 0 end

  local okList, list = pcall(inv.list)
  if not okList or type(list) ~= "table" then list = {} end

  local count = 0
  local usedSlots = 0
  local matchingSlots = 0
  local capacity = 0

  for slot = 1, size do
    local stack = list[slot]
    local slotLimit = defaultStack

    if inv.getItemLimit then
      local okLimit, limit = pcall(inv.getItemLimit, slot)
      if okLimit and type(limit) == "number" and limit > 0 then
        slotLimit = limit
      end
    end

    capacity = capacity + slotLimit

    if stack then
      usedSlots = usedSlots + 1
      if stack.name == itemName then
        matchingSlots = matchingSlots + 1
        count = count + (tonumber(stack.count) or 0)
      end
    end
  end

  local percent = 0
  if capacity > 0 then percent = (count / capacity) * 100 end
  if percent > 100 then percent = 100 end

  return {
    count = count,
    capacity = capacity,
    percent = percent,
    slots = size,
    usedSlots = usedSlots,
    matchingSlots = matchingSlots
  }
end

function Lib.inventoryState(percent, cfg, emptyLatched)
  cfg = cfg or Lib.DEFAULTS
  local fullMin = tonumber(cfg.fullMin) or Lib.DEFAULTS.fullMin
  local stockMin = tonumber(cfg.stockNeededMin) or Lib.DEFAULTS.stockNeededMin
  local lowMin = tonumber(cfg.lowMin) or Lib.DEFAULTS.lowMin
  local criticalMin = tonumber(cfg.criticalMin) or Lib.DEFAULTS.criticalMin

  local state = "Empty"
  local key = "empty"
  local interval = tonumber(cfg.emptyInterval) or Lib.DEFAULTS.emptyInterval
  local mode = "constant"

  if percent >= fullMin then
    state, key, interval, mode = "Full", "full", nil, "none"
  elseif percent >= stockMin then
    state, key, interval, mode = "Stock Needed", "stock_needed", tonumber(cfg.stockNeededInterval) or Lib.DEFAULTS.stockNeededInterval, "pulse"
  elseif percent >= lowMin then
    state, key, interval, mode = "Low", "low", tonumber(cfg.lowInterval) or Lib.DEFAULTS.lowInterval, "pulse"
  elseif percent >= criticalMin then
    state, key, interval, mode = "Critically Low", "critically_low", tonumber(cfg.criticalInterval) or Lib.DEFAULTS.criticalInterval, "pulse"
  end

  if emptyLatched and percent < stockMin then
    mode = "constant"
    interval = tonumber(cfg.emptyInterval) or Lib.DEFAULTS.emptyInterval
  end

  return {
    label = state,
    key = key,
    interval = interval,
    mode = mode,
    shouldRequest = key ~= "full" or (emptyLatched and percent < stockMin)
  }
end

function Lib.pulse(side, seconds)
  if not side or side == "" or not Lib.isSide(side) then return false, "No direct redstone side" end
  seconds = tonumber(seconds) or Lib.DEFAULTS.pulseLength
  redstone.setOutput(side, true)
  sleep(seconds)
  redstone.setOutput(side, false)
  return true
end

function Lib.setupCommon(role, prefix, requireInventory)
  Lib.ensureDirs()
  local cfgPath = Lib.DATA .. "/" .. role .. ".cfg"
  local cfg = Lib.loadTable(cfgPath, nil)
  if cfg then return cfg, cfgPath end

  Lib.header("First setup: " .. role)
  local found = Lib.detectPeripherals()
  Lib.printDetection(found)
  print("")

  cfg = {}
  cfg.role = role
  cfg.nodeId = Lib.uuid(prefix)
  cfg.name = Lib.askString("Node name", role .. " " .. os.getComputerID())
  cfg.item = Lib.askString("Item string", "minecraft:iron_ingot")
  cfg.channel = Lib.CHANNEL
  cfg.defaultStackSize = Lib.askNumber("Default stack size", Lib.DEFAULTS.defaultStackSize, 1, 64)
  cfg.pulseLength = Lib.askNumber("Packager pulse length seconds", Lib.DEFAULTS.pulseLength, 0.05, 10)

  cfg.fullMin = Lib.askNumber("Full starts at percent", Lib.DEFAULTS.fullMin, 1, 100)
  cfg.stockNeededMin = Lib.askNumber("Stock Needed starts at percent", Lib.DEFAULTS.stockNeededMin, 0, cfg.fullMin)
  cfg.lowMin = Lib.askNumber("Low starts at percent", Lib.DEFAULTS.lowMin, 0, cfg.stockNeededMin)
  cfg.criticalMin = Lib.askNumber("Critically Low starts at percent", Lib.DEFAULTS.criticalMin, 0, cfg.lowMin)

  cfg.stockNeededInterval = Lib.askNumber("Stock Needed request interval", Lib.DEFAULTS.stockNeededInterval, 0.1, 120)
  cfg.lowInterval = Lib.askNumber("Low request interval", Lib.DEFAULTS.lowInterval, 0.1, 120)
  cfg.criticalInterval = Lib.askNumber("Critical request interval", Lib.DEFAULTS.criticalInterval, 0.1, 120)
  cfg.emptyInterval = Lib.askNumber("Empty emergency interval", Lib.DEFAULTS.emptyInterval, 0.1, 10)

  cfg.modems = found.modems
  cfg.monitor = found.monitors[1]
  cfg.packagerSide = nil
  for _, p in ipairs(found.packagers) do
    if Lib.isSide(p) then cfg.packagerSide = p break end
  end
  cfg.packagerName = found.packagers[1]

  if requireInventory or #found.inventories > 0 then
    cfg.inventory = found.inventories[1]
  end

  Lib.saveTable(cfgPath, cfg)
  print("")
  print("Saved config to " .. cfgPath)
  print("Press any key to continue.")
  os.pullEvent("key")

  return cfg, cfgPath
end

function Lib.statusLine(name, item, percent, state)
  return string.format("%s | %s | %.1f%% | %s", tostring(name), tostring(item), tonumber(percent) or 0, tostring(state))
end

return Lib
