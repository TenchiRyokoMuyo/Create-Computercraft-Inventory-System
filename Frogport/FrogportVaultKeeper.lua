-- FrogportVaultKeeper.lua
-- One vault inventory + one packager. Auto-detects inventory/item, requests matching Producers, pulses for matching Consumers.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()
local cfgPath = Lib.DATA .. "/vault.cfg"
local cfg = Lib.loadTable(cfgPath, nil)

local function setup()
  local found = Lib.detectPeripherals()
  Lib.header("Vault Keeper setup")
  Lib.printDetection(found)
  print("")
  local c = Lib.basicConfig("vault", "VK")
  c.name = Lib.askString("Node name", os.getComputerLabel() or c.name)
  c.modems = found.modems
  c.monitor = found.monitors[1]
  c.packagerName = found.packagers[1]
  c.packagerSide = Lib.pickPackagerSide(found)
  c.inventory = found.inventories[1]
  if #found.inventories > 1 then
    print("Choose vault inventory:")
    for i, inv in ipairs(found.inventories) do print(i .. ". " .. inv .. " (" .. Lib.typeString(inv) .. ")") end
    local n = tonumber(Lib.askString("Inventory number", "1")) or 1
    c.inventory = found.inventories[n] or found.inventories[1]
  end
  if c.inventory then c.item = Lib.pickDetectedItem(c.inventory, Lib.firstDetectedItem(c.inventory)) else c.item = Lib.askString("Item string", "minecraft:iron_ingot") end
  c.defaultStackSize = Lib.askNumber("Default stack size", Lib.DEFAULTS.defaultStackSize, 1, 64)
  if c.inventory then c.capacityOverride, c.capacityMode = Lib.askCapacitySettings(c.inventory, c.item, c.defaultStackSize, c.capacityOverride, c.capacityMode) end
  c.pulseLength = Lib.askNumber("Packager pulse length seconds", Lib.DEFAULTS.pulseLength, 0.05, 10)
  c.vaultPulseCooldown = Lib.askNumber("Vault pulse cooldown", Lib.DEFAULTS.vaultPulseCooldown, 0.05, 30)
  Lib.rescanCommon(c)
  Lib.saveTable(cfgPath, c)
  return c
end

if not cfg then cfg = setup() else Lib.defaultThresholds(cfg); Lib.rescanCommon(cfg); Lib.saveTable(cfgPath, cfg) end
Lib.openModems(cfg.modems, Lib.CHANNEL)

local emptyLatched = false
local lastRequest = 0
local lastHeartbeat = 0
local lastPulse = 0
local lastStatus = nil
local recent = {}

local function log(line) table.insert(recent, 1, os.date("%H:%M:%S") .. " " .. line); while #recent > 7 do table.remove(recent) end end

local function scan()
  if cfg.inventory and (not cfg.item or cfg.item == "") then
    cfg.item = Lib.firstDetectedItem(cfg.inventory) or cfg.item
    Lib.saveTable(cfgPath, cfg)
  end
  local inv = Lib.countItem(cfg.inventory, cfg.item, cfg.defaultStackSize, cfg.capacityOverride, cfg.capacityMode)
  if inv.percent < (tonumber(cfg.criticalMin) or Lib.DEFAULTS.criticalMin) then emptyLatched = true end
  if inv.percent >= (tonumber(cfg.stockNeededMin) or Lib.DEFAULTS.stockNeededMin) then emptyLatched = false end
  local state = Lib.inventoryState(inv.percent, cfg, emptyLatched)
  inv.state, inv.stateKey, inv.interval, inv.mode, inv.shouldRequest = state.label, state.key, state.interval, state.mode, state.shouldRequest
  inv.item, inv.inventory, inv.role, inv.nodeId, inv.name = cfg.item, cfg.inventory, cfg.role, cfg.nodeId, cfg.name
  return inv
end

local function render(status)
  Lib.clear(); term.setTextColor(colors.lime); print("Frogport Vault Keeper"); term.setTextColor(colors.white)
  print(cfg.name); print(string.rep("-", 32))
  print("Item: " .. tostring(cfg.item)); print("Vault: " .. tostring(cfg.inventory)); print("Packager: " .. tostring(cfg.packagerSide)); if tonumber(cfg.capacityOverride or 0) > 0 then print("Capacity: manual " .. tostring(cfg.capacityOverride)) else print("Capacity: auto " .. tostring(cfg.capacityMode or "slot_limits")) end
  print("")
  if status then print("Count: " .. status.count .. " / " .. status.capacity); print(string.format("Percent: %.1f%%", status.percent)); print("State: " .. status.state); print("Mode: " .. status.mode); print("Empty latch: " .. tostring(emptyLatched)) end
  print(""); print("Recent:"); for _, l in ipairs(recent) do print(l) end
end

local function sendStatus(status)
  Lib.transmit(cfg.modems, { type = "STATUS", role = "vault", nodeId = cfg.nodeId, name = cfg.name, item = cfg.item, inventory = cfg.inventory, packagerSide = cfg.packagerSide, count = status.count, capacity = status.capacity, autoCapacity = status.autoCapacity, capacityOverride = cfg.capacityOverride, capacityMode = cfg.capacityMode, slotLimitCapacity = status.slotLimitCapacity, matchingSlotCapacity = status.matchingSlotCapacity, occupiedSlotCapacity = status.occupiedSlotCapacity, percent = status.percent, state = status.state, stateKey = status.stateKey, mode = status.mode, emptyLatched = emptyLatched, detectedInventories = cfg.detectedInventories, detectedItems = cfg.detectedItems })
end

local function maybeRequestProduction(status)
  if not status.shouldRequest then return end
  local now = os.clock(); local interval = status.interval or cfg.emptyInterval or Lib.DEFAULTS.emptyInterval
  if now - lastRequest < interval then return end
  lastRequest = now
  Lib.transmit(cfg.modems, { type = "PRODUCER_REQUEST", requester = cfg.nodeId, requesterName = cfg.name, item = cfg.item, percent = status.percent, state = status.state, requestMode = status.mode, emptyLatched = emptyLatched })
  log("Asked producers: " .. status.state)
end

local function pulseForConsumer(packet)
  if packet.item ~= cfg.item then return end
  local now = os.clock()
  if now - lastPulse < (tonumber(cfg.vaultPulseCooldown) or Lib.DEFAULTS.vaultPulseCooldown) then return end
  lastPulse = now
  local ok, err = Lib.pulse(cfg.packagerSide, cfg.pulseLength)
  if ok then
    log("Pulsed for " .. tostring(packet.sourceLabel or packet.requesterName or packet.requester))
    Lib.transmit(cfg.modems, { type = "VAULT_PULSED", nodeId = cfg.nodeId, name = cfg.name, item = cfg.item, requester = packet.requester, requesterName = packet.requesterName, sourceLabel = packet.sourceLabel, state = lastStatus and lastStatus.state or "unknown" })
  else log("Pulse failed: " .. tostring(err)) end
end

local function networkLoop()
  while true do
    local _, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if channel == Lib.CHANNEL and Lib.validPacket(message) then
      if Lib.configNetworkHandler(cfg, cfgPath, cfg.modems, message, lastStatus) then
      elseif message.type == "CONSUMER_REQUEST" and message.item == cfg.item then pulseForConsumer(message) end
    end
  end
end

local function mainLoop()
  while true do
    local status = scan(); lastStatus = status; render(status); maybeRequestProduction(status)
    local now = os.clock(); if now - lastHeartbeat >= Lib.DEFAULTS.heartbeatInterval then lastHeartbeat = now; sendStatus(status) end
    sleep(Lib.DEFAULTS.scanInterval)
  end
end

parallel.waitForAny(networkLoop, mainLoop)
