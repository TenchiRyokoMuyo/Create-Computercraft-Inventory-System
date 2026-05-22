-- FrogportOverseer.lua
-- Network dashboard + remote config editor for Frogport nodes.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()
local cfgPath = Lib.DATA .. "/overseer.cfg"
local cfg = Lib.loadTable(cfgPath, nil)

local function setup()
  local found = Lib.detectPeripherals()
  Lib.header("Overseer setup")
  Lib.printDetection(found); print("")
  local c = Lib.basicConfig("overseer", "OVR")
  c.name = Lib.askString("Node name", os.getComputerLabel() or c.name)
  c.modems = found.modems; c.monitor = found.monitors[1]
  Lib.rescanCommon(c); Lib.saveTable(cfgPath, c); return c
end

if not cfg then cfg = setup() else Lib.defaultThresholds(cfg); Lib.rescanCommon(cfg); Lib.saveTable(cfgPath, cfg) end
Lib.openModems(cfg.modems, Lib.CHANNEL)

local nodes, recent, selectedConfig = {}, {}, nil
local function log(line) table.insert(recent, 1, os.date("%H:%M:%S") .. " " .. line); while #recent > 12 do table.remove(recent) end end

local function age(packet) if not packet or not packet.time then return 999 end return math.floor((os.epoch("utc") - packet.time) / 1000) end
local function sortedNodes()
  local out = {}; for _, n in pairs(nodes) do table.insert(out, n) end
  table.sort(out, function(a,b) return tostring(a.name) < tostring(b.name) end)
  return out
end

local function colorForState(state)
  if state == "Full" then return colors.lime end
  if state == "Stock Needed" then return colors.yellow end
  if state == "Low" then return colors.orange end
  if state == "Critically Low" then return colors.red end
  if state == "Empty" then return colors.red end
  return colors.white
end

local function writeLine(target, text, color)
  if color then target.setTextColor(color) else target.setTextColor(colors.white) end
  local _, y = target.getCursorPos(); local w, h = target.getSize()
  if y <= h then target.write(string.sub(text, 1, w)); target.setCursorPos(1, y + 1) end
end

local function renderTo(target)
  target.setBackgroundColor(colors.black); target.setTextColor(colors.white); target.clear(); target.setCursorPos(1,1)
  writeLine(target, "FROGPORT CENTRAL COMMAND", colors.lime)
  writeLine(target, "Nodes: " .. tostring(#sortedNodes()) .. "   Press M for menu", colors.white)
  writeLine(target, string.rep("-", 50), colors.gray)
  local rows = sortedNodes()
  for _, n in ipairs(rows) do
    if n.role == "consumer" and type(n.watched) == "table" then
      writeLine(target, string.format("%s [%s] %ss", n.name or n.nodeId, n.role, age(n)), colors.cyan)
      for _, w in ipairs(n.watched) do
        writeLine(target, string.format("  %-16s %-24s %5.1f%%", tostring(w.state), tostring(w.item), tonumber(w.percent) or 0), colorForState(w.state))
      end
    else
      local c = colors.white; if n.role == "vault" then c = colors.lime elseif n.role == "producer" then c = colors.orange end
      writeLine(target, string.format("%s [%s] %ss", n.name or n.nodeId, n.role or "?", age(n)), c)
      writeLine(target, string.format("  %-16s %-24s %5.1f%%", tostring(n.state), tostring(n.item), tonumber(n.percent) or 0), colorForState(n.state))
    end
  end
  writeLine(target, string.rep("-", 50), colors.gray)
  writeLine(target, "Recent:", colors.white)
  for _, r in ipairs(recent) do writeLine(target, r, colors.gray) end
end

local function render()
  renderTo(term)
  if cfg.monitor then
    local mon = peripheral.wrap(cfg.monitor)
    if mon then pcall(function() mon.setTextScale(0.5); renderTo(mon) end) end
  end
end

local function requestConfig(node)
  selectedConfig = nil
  Lib.transmit(cfg.modems, { type = "CONFIG_GET", requester = cfg.nodeId, requesterName = cfg.name, target = node.nodeId })
  log("Requested config from " .. tostring(node.name))
  local deadline = os.clock() + 4
  while os.clock() < deadline do
    local ev = { os.pullEvent() }
    if ev[1] == "modem_message" then
      local channel, msg = ev[3], ev[5]
      if channel == Lib.CHANNEL and Lib.validPacket(msg) then
        if msg.type == "CONFIG_RESPONSE" and msg.nodeId == node.nodeId then selectedConfig = msg; return msg end
        if msg.type == "STATUS" then nodes[msg.nodeId or msg.name] = msg end
      end
    elseif ev[1] == "key" and ev[2] == keys.q then return nil end
  end
  return nil
end

local function sendConfig(node, config)
  Lib.transmit(cfg.modems, { type = "CONFIG_SET", requester = cfg.nodeId, requesterName = cfg.name, target = node.nodeId, config = config })
  log("Sent config to " .. tostring(node.name))
end

local function editThresholds(c)
  c.fullMin = Lib.askNumber("Full starts at", c.fullMin or 95, 1, 100)
  c.stockNeededMin = Lib.askNumber("Stock Needed starts at", c.stockNeededMin or 75, 0, c.fullMin)
  c.lowMin = Lib.askNumber("Low starts at", c.lowMin or 50, 0, c.stockNeededMin)
  c.criticalMin = Lib.askNumber("Critically Low starts at", c.criticalMin or 10, 0, c.lowMin)
  c.stockNeededInterval = Lib.askNumber("Stock Needed interval", c.stockNeededInterval or 5, 0.1, 120)
  c.lowInterval = Lib.askNumber("Low interval", c.lowInterval or 3, 0.1, 120)
  c.criticalInterval = Lib.askNumber("Critical interval", c.criticalInterval or 1, 0.1, 120)
  c.emptyInterval = Lib.askNumber("Empty interval", c.emptyInterval or 0.5, 0.1, 30)
end

local function editConsumer(c)
  c.watched = c.watched or {}
  while true do
    Lib.header("Edit Consumer: " .. tostring(c.name))
    print("1. Rename node")
    print("2. Edit thresholds/intervals")
    print("3. Edit watched inventory")
    print("4. Add watched inventory")
    print("5. Remove watched inventory")
    print("6. Save")
    print("7. Cancel")
    print("")
    for i, w in ipairs(c.watched) do print(i .. ". " .. tostring(w.label) .. " | " .. tostring(w.inventory) .. " | " .. tostring(w.item) .. " | enabled=" .. tostring(w.enabled ~= false)) end
    local ch = Lib.askString(">", "6")
    if ch == "1" then c.name = Lib.askString("Node name", c.name)
    elseif ch == "2" then editThresholds(c)
    elseif ch == "3" then
      local i = tonumber(Lib.askString("Entry number", "1"))
      local w = i and c.watched[i]
      if w then w.label = Lib.askString("Label", w.label); w.inventory = Lib.askString("Inventory peripheral", w.inventory); w.item = Lib.askString("Item string", w.item); w.defaultStackSize = Lib.askNumber("Default stack size", w.defaultStackSize or c.defaultStackSize or 64, 1, 64); w.capacityMode = Lib.askCapacityMode(w.capacityMode); w.capacityOverride = Lib.askNumber("Manual full capacity, 0 = auto", w.capacityOverride or 0, 0, 1000000000); w.enabled = Lib.askYesNo("Enabled", w.enabled ~= false) end
    elseif ch == "4" then
      local inv = Lib.askString("Inventory peripheral name", "")
      if inv ~= "" then table.insert(c.watched, { label = Lib.askString("Label", inv), inventory = inv, item = Lib.askString("Item string", "minecraft:coal"), defaultStackSize = c.defaultStackSize or 64, capacityMode = Lib.askCapacityMode("slot_limits"), capacityOverride = Lib.askNumber("Manual full capacity, 0 = auto", 0, 0, 1000000000), enabled = true }) end
    elseif ch == "5" then
      local i = tonumber(Lib.askString("Remove entry number", "")); if i and c.watched[i] then table.remove(c.watched, i) end
    elseif ch == "6" then return true
    elseif ch == "7" then return false end
  end
end

local function editSimple(c)
  while true do
    Lib.header("Edit " .. tostring(c.role) .. ": " .. tostring(c.name))
    print("1. Rename node")
    print("2. Item string")
    print("3. Inventory peripheral")
    print("4. Packager side")
    print("5. Capacity mode / override")
    print("6. Thresholds/intervals")
    print("7. Pulse/cooldown")
    if c.role == "producer" then print("8. Enabled") end
    print("S. Save")
    print("C. Cancel")
    local ch = tostring(Lib.askString(">", "S")):lower()
    if ch == "1" then c.name = Lib.askString("Node name", c.name)
    elseif ch == "2" then c.item = Lib.askString("Item string", c.item)
    elseif ch == "3" then c.inventory = Lib.askString("Inventory peripheral", c.inventory or "")
    elseif ch == "4" then c.packagerSide = Lib.askString("Packager redstone side", c.packagerSide or "right")
    elseif ch == "5" then c.capacityMode = Lib.askCapacityMode(c.capacityMode); c.capacityOverride = Lib.askNumber("Manual full capacity, 0 = auto", c.capacityOverride or 0, 0, 1000000000)
    elseif ch == "6" then editThresholds(c)
    elseif ch == "7" then c.pulseLength = Lib.askNumber("Pulse length", c.pulseLength or 0.25, 0.05, 10); c.producerCooldown = Lib.askNumber("Producer cooldown", c.producerCooldown or 2, 0.05, 120); c.vaultPulseCooldown = Lib.askNumber("Vault pulse cooldown", c.vaultPulseCooldown or 0.5, 0.05, 120)
    elseif ch == "8" and c.role == "producer" then c.enabled = Lib.askYesNo("Enabled", c.enabled ~= false)
    elseif ch == "s" then return true
    elseif ch == "c" then return false end
  end
end

local function chooseNode()
  local rows = sortedNodes()
  Lib.header("Choose network node")
  for i, n in ipairs(rows) do print(i .. ". " .. tostring(n.name) .. " [" .. tostring(n.role) .. "] " .. tostring(n.nodeId)) end
  local n = tonumber(Lib.askString("Node number", ""))
  return n and rows[n] or nil
end

local function menu()
  while true do
    Lib.header("Overseer menu")
    print("1. Return to dashboard")
    print("2. Edit remote node configuration")
    print("3. Request remote rescan")
    print("4. Broadcast config refresh")
    print("5. Local rescan")
    print("6. Reboot overseer")
    local ch = Lib.askString(">", "1")
    if ch == "1" then return
    elseif ch == "2" then
      local node = chooseNode(); if node then local resp = requestConfig(node); if resp and resp.config then local c = resp.config; local save = (c.role == "consumer") and editConsumer(c) or editSimple(c); if save then sendConfig(node, c) end else Lib.pause("No config response. Press Enter.") end end
    elseif ch == "3" then local node = chooseNode(); if node then Lib.transmit(cfg.modems, { type = "RESCAN", target = node.nodeId, requester = cfg.nodeId }); log("Asked " .. tostring(node.name) .. " to rescan") end
    elseif ch == "4" then Lib.transmit(cfg.modems, { type = "CONFIG_GET", requester = cfg.nodeId, requesterName = cfg.name }); log("Broadcast config refresh")
    elseif ch == "5" then Lib.rescanCommon(cfg); Lib.saveTable(cfgPath, cfg); Lib.openModems(cfg.modems, Lib.CHANNEL); log("Local rescan complete")
    elseif ch == "6" then os.reboot() end
  end
end

local function eventLoop()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "modem_message" then
      local channel, msg = ev[3], ev[5]
      if channel == Lib.CHANNEL and Lib.validPacket(msg) then
        if msg.type == "STATUS" then nodes[msg.nodeId or msg.name] = msg
        elseif msg.type == "PRODUCER_PULSED" then log("Producer pulsed: " .. tostring(msg.name) .. " " .. tostring(msg.item))
        elseif msg.type == "VAULT_PULSED" then log("Vault pulsed: " .. tostring(msg.name) .. " " .. tostring(msg.item))
        elseif msg.type == "CONFIG_ACK" then log("Config ACK: " .. tostring(msg.name) .. " " .. tostring(msg.note or msg.error or msg.ok))
        elseif msg.type == "CONFIG_RESPONSE" then nodes[msg.nodeId or msg.name] = msg.status or nodes[msg.nodeId or msg.name] or msg; log("Config from " .. tostring(msg.name)) end
      end
    elseif ev[1] == "key" and (ev[2] == keys.m or ev[2] == keys.enter) then menu() end
  end
end

local function drawLoop() while true do render(); sleep(1) end end
parallel.waitForAny(eventLoop, drawLoop)
