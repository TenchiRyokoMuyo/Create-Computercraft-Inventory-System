-- FrogportLib.lua
-- Shared utilities for Frogport Central Command

local Lib = {}

Lib.VERSION = 7
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
  criticalInterval = 1,
  consumerRequestPercent = 50,
  consumerFixedCapacity = 1280
}

Lib.SIDES = { "top", "bottom", "left", "right", "front", "back" }

function Lib.ensureDirs()
  if not fs.exists(Lib.ROOT) then fs.makeDir(Lib.ROOT) end
  if not fs.exists(Lib.DATA) then fs.makeDir(Lib.DATA) end
end

function Lib.readAll(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r"); local d = h.readAll(); h.close(); return d
end

function Lib.writeAll(path, data)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(path, "w"); h.write(data); h.close()
end

function Lib.loadTable(path, fallback)
  local data = Lib.readAll(path)
  if not data then return fallback end
  local ok, result = pcall(textutils.unserialize, data)
  if ok and type(result) == "table" then return result end
  return fallback
end

function Lib.saveTable(path, tbl) Lib.writeAll(path, textutils.serialize(tbl)) end
function Lib.uuid(prefix) return (prefix or "NODE") .. "_" .. tostring(os.getComputerID()) end
function Lib.trim(s) if s == nil then return "" end return tostring(s):match("^%s*(.-)%s*$") end
function Lib.clamp(n, a, b) n = tonumber(n) or 0; if n < a then return a elseif n > b then return b end return n end

function Lib.clear()
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
end

function Lib.header(title)
  Lib.clear(); term.setTextColor(colors.lime); print("Frogport Central Command"); term.setTextColor(colors.white)
  print(title or ""); print(string.rep("-", 32))
end

function Lib.pause(msg) print(msg or "Press Enter to continue..."); read() end

function Lib.askString(label, default)
  if default ~= nil and tostring(default) ~= "" then write(label .. " [" .. tostring(default) .. "]: ") else write(label .. ": ") end
  local v = Lib.trim(read())
  if v == "" then return default end
  return v
end

function Lib.askNumber(label, default, minValue, maxValue)
  while true do
    local raw = Lib.askString(label, tostring(default))
    local n = tonumber(raw)
    if n and (not minValue or n >= minValue) and (not maxValue or n <= maxValue) then return n end
    print("Enter a number" .. (minValue and (" >= " .. minValue) or "") .. (maxValue and (" <= " .. maxValue) or "") .. ".")
  end
end

function Lib.askYesNo(label, default)
  local d = default and "Y" or "N"
  while true do
    local v = tostring(Lib.askString(label .. " (y/n)", d)):lower()
    if v == "y" or v == "yes" then return true end
    if v == "n" or v == "no" then return false end
  end
end


function Lib.safeFileName(s)
  s = tostring(s or "unknown")
  s = s:gsub("[^%w_%-%.]", "_")
  if s == "" then s = "unknown" end
  return s
end

function Lib.runtimePath(role, suffix)
  Lib.ensureDirs()
  return Lib.DATA .. "/" .. Lib.safeFileName(role or "node") .. "_" .. Lib.safeFileName(suffix or "runtime") .. ".dat"
end

function Lib.loadRuntime(role, fallback)
  return Lib.loadTable(Lib.runtimePath(role, "runtime"), fallback or {})
end

function Lib.saveRuntime(role, tbl)
  tbl = tbl or {}
  tbl.savedAt = os.epoch("utc")
  Lib.saveTable(Lib.runtimePath(role, "runtime"), tbl)
end

function Lib.loadStatusCache(role, fallback)
  return Lib.loadTable(Lib.runtimePath(role, "status"), fallback or {})
end

function Lib.saveStatusCache(role, cfg, status)
  local cache = {
    savedAt = os.epoch("utc"),
    role = role,
    nodeId = cfg and cfg.nodeId,
    name = cfg and cfg.name,
    status = status,
  }
  Lib.saveTable(Lib.runtimePath(role, "status"), cache)
end

function Lib.truncate(text, width)
  text = tostring(text or "")
  width = tonumber(width) or 1
  if #text <= width then return text end
  if width <= 3 then return text:sub(1, width) end
  return text:sub(1, width - 3) .. "..."
end

function Lib.scrollMenu(title, items, opts)
  if type(opts) ~= "table" then opts = { subtitle = opts } end
  opts = opts or {}
  items = items or {}
  local selected = Lib.clamp(tonumber(opts.selected) or 1, 1, math.max(#items, 1))
  local top = 1
  while true do
    Lib.clear()
    local w, h = term.getSize()
    term.setTextColor(colors.lime)
    print(title or "Menu")
    term.setTextColor(colors.white)
    if opts.subtitle and opts.subtitle ~= "" then print(Lib.truncate(opts.subtitle, w)) end
    print(string.rep("-", math.min(w, 32)))
    if #items == 0 then
      print("No entries.")
      print("")
      print("Q/Esc/backspace to return")
    else
      local listHeight = h - 5
      if opts.subtitle and opts.subtitle ~= "" then listHeight = h - 6 end
      if opts.footer then listHeight = listHeight - 1 end
      if listHeight < 3 then listHeight = 3 end
      if selected < top then top = selected end
      if selected > top + listHeight - 1 then top = selected - listHeight + 1 end
      for row = 0, listHeight - 1 do
        local i = top + row
        local item = items[i]
        if item then
          local label = item.label or tostring(item.value or i)
          if item.sub and item.sub ~= "" then label = label .. " - " .. item.sub end
          label = Lib.truncate(label, w)
          if i == selected then
            term.setTextColor(colors.black)
            term.setBackgroundColor(colors.white)
          else
            term.setTextColor(item.color or colors.white)
            term.setBackgroundColor(colors.black)
          end
          term.write(label .. string.rep(" ", math.max(0, w - #label)))
          term.setBackgroundColor(colors.black)
          term.setTextColor(colors.white)
          print("")
        end
      end
      term.setTextColor(colors.gray)
      print(opts.footer or "Up/Down Enter | Q/Esc back")
    end
    local _, key = os.pullEvent("key")
    if key == keys.up then selected = math.max(1, selected - 1)
    elseif key == keys.down then selected = math.min(#items, selected + 1)
    elseif key == keys.pageUp then selected = math.max(1, selected - 8)
    elseif key == keys.pageDown then selected = math.min(#items, selected + 8)
    elseif key == keys.home then selected = 1
    elseif key == keys["end"] then selected = #items
    elseif key == keys.enter or key == keys.numPadEnter then if items[selected] then return items[selected].value, selected, items[selected] end
    elseif key == keys.q or key == keys.escape or key == keys.backspace then return nil end
  end
end

function Lib.isSide(name)
  for _, s in ipairs(Lib.SIDES) do if name == s then return true end end
  return false
end

function Lib.typeString(name)
  local ok, t = pcall(peripheral.getType, name)
  if not ok or not t then return "" end
  if type(t) == "table" then return table.concat(t, ","):lower() end
  return tostring(t):lower()
end

function Lib.hasMethod(name, method)
  local ok, methods = pcall(peripheral.getMethods, name)
  if not ok or type(methods) ~= "table" then return false end
  for _, m in ipairs(methods) do if m == method then return true end end
  return false
end

function Lib.detectPeripherals()
  local found = { modems = {}, monitors = {}, packagers = {}, inventories = {} }
  for _, name in ipairs(peripheral.getNames()) do
    local t = Lib.typeString(name)
    local isModem = t:find("modem", 1, true) ~= nil
    local isMonitor = t:find("monitor", 1, true) ~= nil
    local isPackager = t:find("packager", 1, true) ~= nil
    if isModem then table.insert(found.modems, name) end
    if isMonitor then table.insert(found.monitors, name) end
    if isPackager then table.insert(found.packagers, name) end
    local looksInventory = Lib.hasMethod(name, "list") and (Lib.hasMethod(name, "size") or Lib.hasMethod(name, "getItemDetail"))
    if looksInventory and not isModem and not isMonitor and not isPackager then table.insert(found.inventories, name) end
  end
  table.sort(found.modems); table.sort(found.monitors); table.sort(found.packagers); table.sort(found.inventories)
  return found
end

function Lib.printDetection(found)
  print("Modems:"); for _, v in ipairs(found.modems or {}) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
  print("Monitors:"); for _, v in ipairs(found.monitors or {}) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
  print("Packagers:"); for _, v in ipairs(found.packagers or {}) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
  print("Inventories:"); for _, v in ipairs(found.inventories or {}) do print("  " .. v .. " (" .. Lib.typeString(v) .. ")") end
end

function Lib.openModems(modemNames, channel)
  channel = channel or Lib.CHANNEL
  for _, name in ipairs(modemNames or {}) do
    local p = peripheral.wrap(name)
    if p and p.open then pcall(function() if not p.isOpen(channel) then p.open(channel) end end) end
  end
end

function Lib.transmit(modemNames, packet)
  packet.protocol = Lib.PROTOCOL; packet.version = Lib.VERSION; packet.time = os.epoch("utc")
  for _, name in ipairs(modemNames or {}) do
    local p = peripheral.wrap(name)
    if p and p.transmit then pcall(function() p.transmit(Lib.CHANNEL, Lib.CHANNEL, packet) end) end
  end
end

function Lib.validPacket(msg) return type(msg) == "table" and msg.protocol == Lib.PROTOCOL and msg.version == Lib.VERSION end

function Lib.scanInventoryItems(invName)
  local inv = peripheral.wrap(invName)
  local out, byName = {}, {}
  if not inv or not inv.list then return out end
  local okList, list = pcall(inv.list)
  if not okList or type(list) ~= "table" then return out end
  for slot, stack in pairs(list) do
    if stack and stack.name then
      local rec = byName[stack.name]
      if not rec then
        rec = { name = stack.name, displayName = stack.displayName or stack.name, count = 0, slots = 0 }
        if inv.getItemDetail then
          local okD, d = pcall(inv.getItemDetail, slot)
          if okD and type(d) == "table" then rec.displayName = d.displayName or rec.displayName end
        end
        byName[stack.name] = rec; table.insert(out, rec)
      end
      rec.count = rec.count + (tonumber(stack.count) or 0); rec.slots = rec.slots + 1
    end
  end
  table.sort(out, function(a,b) return a.name < b.name end)
  return out
end

function Lib.firstDetectedItem(invName)
  local items = Lib.scanInventoryItems(invName)
  if items[1] then return items[1].name end
  return nil
end

function Lib.pickDetectedItem(invName, current)
  local items = Lib.scanInventoryItems(invName)
  if #items == 0 then return Lib.askString("Item string", current or "minecraft:iron_ingot") end
  print("Detected items in " .. tostring(invName) .. ":")
  for i, it in ipairs(items) do print(i .. ". " .. it.name .. " x" .. it.count .. " (" .. tostring(it.displayName) .. ")") end
  print("M. Manual entry")
  local v = Lib.askString("Choose item", "1")
  if tostring(v):lower() == "m" then return Lib.askString("Item string", current or items[1].name) end
  local n = tonumber(v)
  if n and items[n] then return items[n].name end
  return current or items[1].name
end

function Lib.slotLimit(inv, slot, defaultStack)
  defaultStack = tonumber(defaultStack) or Lib.DEFAULTS.defaultStackSize
  if inv and inv.getItemLimit then
    local okLimit, limit = pcall(inv.getItemLimit, slot)
    if okLimit and type(limit) == "number" and limit > 0 then return limit end
  end
  return defaultStack
end

function Lib.countItem(invName, itemName, defaultStack, capacityOverride, capacityMode)
  defaultStack = tonumber(defaultStack) or Lib.DEFAULTS.defaultStackSize
  capacityOverride = tonumber(capacityOverride) or 0
  capacityMode = capacityMode or "slot_limits"
  itemName = Lib.trim(itemName)
  local inv = peripheral.wrap(invName)
  if not inv or not inv.list or not inv.size then return { count = 0, capacity = 0, autoCapacity = 0, slotLimitCapacity = 0, matchingSlotCapacity = 0, occupiedSlotCapacity = 0, percent = 0, slots = 0, usedSlots = 0, matchingSlots = 0, capacityOverride = capacityOverride, capacityMode = capacityMode } end

  local okSize, size = pcall(inv.size)
  if not okSize or type(size) ~= "number" then size = 0 end

  local okList, list = pcall(inv.list)
  if not okList or type(list) ~= "table" then list = {} end

  local count, usedSlots, matchingSlots = 0, 0, 0
  local slotLimitCapacity, occupiedSlotCapacity, matchingSlotCapacity = 0, 0, 0
  for slot = 1, size do
    local stack = list[slot]
    local slotLimit = Lib.slotLimit(inv, slot, defaultStack)
    slotLimitCapacity = slotLimitCapacity + slotLimit
    if stack then
      usedSlots = usedSlots + 1
      occupiedSlotCapacity = occupiedSlotCapacity + slotLimit
      if stack.name == itemName then
        matchingSlots = matchingSlots + 1
        matchingSlotCapacity = matchingSlotCapacity + slotLimit
        count = count + (tonumber(stack.count) or 0)
      end
    end
  end

  local selectedAuto = slotLimitCapacity
  if capacityMode == "matching_slots" then
    selectedAuto = matchingSlotCapacity > 0 and matchingSlotCapacity or slotLimitCapacity
  elseif capacityMode == "occupied_slots" then
    selectedAuto = occupiedSlotCapacity > 0 and occupiedSlotCapacity or slotLimitCapacity
  elseif capacityMode == "filled_plus_one" then
    -- Useful for some machine inputs: currently occupied matching slots plus one more slot.
    selectedAuto = matchingSlotCapacity + defaultStack
    if selectedAuto > slotLimitCapacity then selectedAuto = slotLimitCapacity end
    if selectedAuto <= 0 then selectedAuto = slotLimitCapacity end
  end

  -- Manual override still wins if an inventory peripheral lies about its real capacity.
  local capacity = capacityOverride > 0 and capacityOverride or selectedAuto
  local percent = capacity > 0 and ((count / capacity) * 100) or 0
  if percent > 100 then percent = 100 end

  return {
    count = count,
    capacity = capacity,
    autoCapacity = selectedAuto,
    slotLimitCapacity = slotLimitCapacity,
    matchingSlotCapacity = matchingSlotCapacity,
    occupiedSlotCapacity = occupiedSlotCapacity,
    percent = percent,
    slots = size,
    usedSlots = usedSlots,
    matchingSlots = matchingSlots,
    capacityOverride = capacityOverride,
    capacityMode = capacityMode
  }
end

function Lib.askCapacityMode(current)
  current = current or "slot_limits"
  print("Capacity mode:")
  print("1. slot_limits      - sum getItemLimit(slot) for every slot. Best for true single-item vaults.")
  print("2. matching_slots   - only slots currently holding the configured item. Useful for some machine buffers.")
  print("3. occupied_slots   - all currently occupied slots. Useful for small mixed machine inventories.")
  print("4. filled_plus_one  - matching item slots plus one extra stack. Useful for tiny input buffers.")
  local defaultChoice = "1"
  if current == "matching_slots" then defaultChoice = "2" elseif current == "occupied_slots" then defaultChoice = "3" elseif current == "filled_plus_one" then defaultChoice = "4" end
  local v = Lib.askString("Choose capacity mode", defaultChoice)
  if v == "2" then return "matching_slots" end
  if v == "3" then return "occupied_slots" end
  if v == "4" then return "filled_plus_one" end
  return "slot_limits"
end

function Lib.askCapacitySettings(invName, itemName, defaultStack, currentOverride, currentMode)
  local mode = Lib.askCapacityMode(currentMode)
  local probe = Lib.countItem(invName, itemName, defaultStack, 0, mode)
  print("")
  print("Auto capacity scan for " .. tostring(itemName) .. ":")
  print("  Count: " .. tostring(probe.count))
  print("  Selected auto max: " .. tostring(probe.autoCapacity))
  print("  All slot limits: " .. tostring(probe.slotLimitCapacity))
  print("  Matching slot limits: " .. tostring(probe.matchingSlotCapacity))
  print("  Occupied slot limits: " .. tostring(probe.occupiedSlotCapacity))
  print("  Slots: " .. tostring(probe.slots))
  print("Use 0 to keep automatic capacity. Manual override wins over capacity mode.")
  local override = Lib.askNumber("Manual full capacity", tonumber(currentOverride) or 0, 0, 1000000000)
  return override, mode
end

function Lib.askCapacityOverride(invName, itemName, defaultStack, current)
  local override = Lib.askCapacitySettings(invName, itemName, defaultStack, current, "slot_limits")
  return override
end

function Lib.inventoryState(percent, cfg, emptyLatched)
  cfg = cfg or Lib.DEFAULTS
  local fullMin = tonumber(cfg.fullMin) or Lib.DEFAULTS.fullMin
  local stockMin = tonumber(cfg.stockNeededMin) or Lib.DEFAULTS.stockNeededMin
  local lowMin = tonumber(cfg.lowMin) or Lib.DEFAULTS.lowMin
  local criticalMin = tonumber(cfg.criticalMin) or Lib.DEFAULTS.criticalMin
  local state, key, interval, mode = "Empty", "empty", tonumber(cfg.emptyInterval) or Lib.DEFAULTS.emptyInterval, "constant"
  if percent >= fullMin then state, key, interval, mode = "Full", "full", nil, "none"
  elseif percent >= stockMin then state, key, interval, mode = "Stock Needed", "stock_needed", tonumber(cfg.stockNeededInterval) or Lib.DEFAULTS.stockNeededInterval, "pulse"
  elseif percent >= lowMin then state, key, interval, mode = "Low", "low", tonumber(cfg.lowInterval) or Lib.DEFAULTS.lowInterval, "pulse"
  elseif percent >= criticalMin then state, key, interval, mode = "Critically Low", "critically_low", tonumber(cfg.criticalInterval) or Lib.DEFAULTS.criticalInterval, "pulse" end
  if emptyLatched and percent < stockMin then mode = "constant"; interval = tonumber(cfg.emptyInterval) or Lib.DEFAULTS.emptyInterval end
  return { label = state, key = key, interval = interval, mode = mode, shouldRequest = key ~= "full" or (emptyLatched and percent < stockMin) }
end

function Lib.pulse(side, seconds)
  if not side or side == "" or not Lib.isSide(side) then return false, "No direct redstone side" end
  seconds = tonumber(seconds) or Lib.DEFAULTS.pulseLength
  redstone.setOutput(side, true); sleep(seconds); redstone.setOutput(side, false); return true
end

function Lib.defaultThresholds(cfg)
  cfg = cfg or {}
  for k, v in pairs(Lib.DEFAULTS) do if cfg[k] == nil then cfg[k] = v end end
  return cfg
end

function Lib.basicConfig(role, prefix)
  return Lib.defaultThresholds({ role = role, nodeId = Lib.uuid(prefix), name = role .. " " .. os.getComputerID(), channel = Lib.CHANNEL })
end

function Lib.pickPackagerSide(found, current)
  if current and Lib.isSide(current) then return current end
  for _, p in ipairs(found.packagers or {}) do if Lib.isSide(p) then return p end end
  return current
end

function Lib.rescanCommon(cfg)
  local found = Lib.detectPeripherals()
  if #found.modems > 0 then cfg.modems = found.modems end
  if found.monitors[1] then cfg.monitor = found.monitors[1] end
  cfg.packagerName = found.packagers[1] or cfg.packagerName
  cfg.packagerSide = Lib.pickPackagerSide(found, cfg.packagerSide)
  cfg.detectedInventories = found.inventories
  cfg.detectedItems = {}
  for _, inv in ipairs(found.inventories or {}) do cfg.detectedItems[inv] = Lib.scanInventoryItems(inv) end
  return found
end

function Lib.applyConfigPacket(cfg, packet)
  if type(packet.config) ~= "table" then return false, "packet.config missing" end
  local incoming = packet.config
  for k, v in pairs(incoming) do cfg[k] = v end
  return true
end

function Lib.configNetworkHandler(cfg, cfgPath, modems, message, lastStatus)
  if not Lib.validPacket(message) then return false end
  if message.target and message.target ~= cfg.nodeId and message.target ~= cfg.name then return false end
  if message.type == "CONFIG_GET" then
    Lib.transmit(modems, { type = "CONFIG_RESPONSE", nodeId = cfg.nodeId, name = cfg.name, role = cfg.role, config = cfg, status = lastStatus })
    return true
  elseif message.type == "CONFIG_SET" then
    local ok, err = Lib.applyConfigPacket(cfg, message)
    if ok then
      Lib.saveTable(cfgPath, cfg)
      Lib.transmit(modems, { type = "CONFIG_ACK", nodeId = cfg.nodeId, name = cfg.name, role = cfg.role, ok = true, note = "Saved. Rebooting node." })
      sleep(0.5); os.reboot()
    else
      Lib.transmit(modems, { type = "CONFIG_ACK", nodeId = cfg.nodeId, name = cfg.name, role = cfg.role, ok = false, error = err })
    end
    return true
  elseif message.type == "RESCAN" then
    Lib.rescanCommon(cfg); Lib.saveTable(cfgPath, cfg)
    Lib.transmit(modems, { type = "CONFIG_ACK", nodeId = cfg.nodeId, name = cfg.name, role = cfg.role, ok = true, note = "Rescanned peripherals." })
    return true
  end
  return false
end

return Lib
