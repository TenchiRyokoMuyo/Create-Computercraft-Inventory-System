-- FrogportProducer.lua
-- One packager. Item is user-configured. Optional inventory is reported only; Producer never requests items.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()
local cfgPath = Lib.DATA .. "/producer.cfg"
local cfg = Lib.loadTable(cfgPath, nil)

local function setup()
  local found = Lib.detectPeripherals()
  Lib.header("Producer setup")
  Lib.printDetection(found); print("")
  local c = Lib.basicConfig("producer", "PROD")
  c.name = Lib.askString("Node name", os.getComputerLabel() or c.name)
  c.item = Lib.askString("Produced item string", "minecraft:iron_ingot")
  c.modems = found.modems; c.monitor = found.monitors[1]; c.packagerName = found.packagers[1]; c.packagerSide = Lib.pickPackagerSide(found)
  c.inventory = found.inventories[1]
  c.defaultStackSize = Lib.askNumber("Default stack size", Lib.DEFAULTS.defaultStackSize, 1, 64)
  if c.inventory then c.capacityOverride, c.capacityMode = Lib.askCapacitySettings(c.inventory, c.item, c.defaultStackSize, c.capacityOverride, c.capacityMode) end
  c.pulseLength = Lib.askNumber("Packager pulse length seconds", Lib.DEFAULTS.pulseLength, 0.05, 10)
  c.producerCooldown = Lib.askNumber("Producer cooldown seconds", Lib.DEFAULTS.producerCooldown, 0.05, 120)
  c.enabled = Lib.askYesNo("Enabled", true)
  Lib.rescanCommon(c); Lib.saveTable(cfgPath, c); return c
end

if not cfg then cfg = setup() else Lib.defaultThresholds(cfg); Lib.rescanCommon(cfg); Lib.saveTable(cfgPath, cfg) end
Lib.openModems(cfg.modems, Lib.CHANNEL)

local persisted = Lib.loadRuntime("producer", {})
local lastPulse, lastHeartbeat = tonumber(persisted.lastPulse) or 0, tonumber(persisted.lastHeartbeat) or 0
local lastStatus = (Lib.loadStatusCache("producer", {}).status) or persisted.lastStatus
local recent = persisted.recent or {}
local function savePersist() Lib.saveRuntime("producer", { lastPulse = lastPulse, lastHeartbeat = lastHeartbeat, lastStatus = lastStatus, recent = recent }); Lib.saveStatusCache("producer", cfg, lastStatus) end
local function log(line) table.insert(recent, 1, os.date("%H:%M:%S") .. " " .. line); while #recent > 7 do table.remove(recent) end; savePersist() end

local function scan()
  if not cfg.inventory then return { count = 0, capacity = 0, percent = 0, state = "No Inventory", stateKey = "none", mode = "none", shouldRequest = false } end
  local inv = Lib.countItem(cfg.inventory, cfg.item, cfg.defaultStackSize, cfg.capacityOverride, cfg.capacityMode)
  local state = Lib.inventoryState(inv.percent, cfg, false)
  inv.state, inv.stateKey, inv.mode, inv.shouldRequest = state.label, state.key, state.mode, false
  return inv
end

local function render(status)
  Lib.clear(); term.setTextColor(colors.orange); print("Frogport Producer"); term.setTextColor(colors.white)
  print(cfg.name); print(string.rep("-", 32)); print("Produces: " .. tostring(cfg.item)); print("Enabled: " .. tostring(cfg.enabled ~= false)); print("Packager: " .. tostring(cfg.packagerSide)); print("Inventory: " .. tostring(cfg.inventory or "none")); print("")
  if status and cfg.inventory then print("Count: " .. status.count .. " / " .. status.capacity); if tonumber(cfg.capacityOverride or 0) > 0 then print("Capacity: manual") else print("Capacity: auto " .. tostring(cfg.capacityMode or "slot_limits")) end; print(string.format("Percent: %.1f%%", status.percent)); print("State: " .. status.state) end
  print("Cooldown: " .. tostring(cfg.producerCooldown) .. "s"); print(""); print("Recent:"); for _, l in ipairs(recent) do print(l) end
end

local function sendStatus(status)
  Lib.transmit(cfg.modems, { type = "STATUS", role = "producer", nodeId = cfg.nodeId, name = cfg.name, item = cfg.item, enabled = cfg.enabled ~= false, inventory = cfg.inventory, packagerSide = cfg.packagerSide, count = status.count, capacity = status.capacity, autoCapacity = status.autoCapacity, capacityOverride = cfg.capacityOverride, capacityMode = cfg.capacityMode, slotLimitCapacity = status.slotLimitCapacity, matchingSlotCapacity = status.matchingSlotCapacity, occupiedSlotCapacity = status.occupiedSlotCapacity, percent = status.percent, state = status.state, stateKey = status.stateKey, mode = status.mode, detectedInventories = cfg.detectedInventories, detectedItems = cfg.detectedItems })
end

local function requestCooldown(packet)
  if packet.requestMode == "constant" or packet.emptyLatched then return math.max((tonumber(cfg.pulseLength) or Lib.DEFAULTS.pulseLength) * 2, 0.5) end
  return tonumber(cfg.producerCooldown) or Lib.DEFAULTS.producerCooldown
end

local function handleProducerRequest(packet)
  if cfg.enabled == false or packet.item ~= cfg.item then return end
  local now = os.clock(); local cd = requestCooldown(packet)
  if now - lastPulse < cd then return end
  lastPulse = now
  local ok, err = Lib.pulse(cfg.packagerSide, cfg.pulseLength)
  if ok then
    log("Pulsed for " .. tostring(packet.requesterName or packet.requester))
    Lib.transmit(cfg.modems, { type = "PRODUCER_PULSED", nodeId = cfg.nodeId, name = cfg.name, item = cfg.item, requester = packet.requester, requesterName = packet.requesterName })
  else log("Pulse failed: " .. tostring(err)) end
end

local function networkLoop()
  while true do
    local _, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if channel == Lib.CHANNEL and Lib.validPacket(message) then
      if Lib.configNetworkHandler(cfg, cfgPath, cfg.modems, message, lastStatus) then
      elseif message.type == "PRODUCER_REQUEST" then handleProducerRequest(message) end
    end
  end
end

local function mainLoop()
  while true do
    local status = scan(); lastStatus = status; savePersist(); render(status)
    local now = os.clock(); if now - lastHeartbeat >= Lib.DEFAULTS.heartbeatInterval then lastHeartbeat = now; savePersist(); sendStatus(status) end
    sleep(Lib.DEFAULTS.scanInterval)
  end
end

parallel.waitForAny(networkLoop, mainLoop)
