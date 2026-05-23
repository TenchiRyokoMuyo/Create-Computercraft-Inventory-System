-- FrogportConsumer.lua
-- Watches multiple inventories independently. Each entry auto-detects/uses one item and sends one restock request when it reaches the configured threshold.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()
local cfgPath = Lib.DATA .. "/consumer.cfg"
local cfg = Lib.loadTable(cfgPath, nil)

local CONSUMER_FIXED_CAPACITY = Lib.DEFAULTS.consumerFixedCapacity or 1280

local function addWatchedFromInventory(c, invName)
  local item = Lib.firstDetectedItem(invName)
  print("")
  print("Configure inventory: " .. tostring(invName))
  if item then print("Auto-detected first item: " .. item) end
  if Lib.askYesNo("Use/track this inventory", item ~= nil) then
    item = Lib.pickDetectedItem(invName, item or "minecraft:coal")
    local stackSize = c.defaultStackSize or Lib.DEFAULTS.defaultStackSize
    local capOverride, capMode = Lib.askCapacitySettings(invName, item, stackSize, 0, "slot_limits")
    table.insert(c.watched, {
      label = Lib.askString("Label", invName),
      inventory = invName,
      item = item,
      defaultStackSize = stackSize,
      capacityOverride = CONSUMER_FIXED_CAPACITY,
      capacityMode = "fixed_1280",
      enabled = true
    })
  end
end

local function setup()
  local found = Lib.detectPeripherals()
  Lib.header("Consumer setup")
  Lib.printDetection(found); print("")
  local c = Lib.basicConfig("consumer", "CON")
  c.name = Lib.askString("Node name", os.getComputerLabel() or c.name)
  c.modems = found.modems; c.monitor = found.monitors[1]
  c.defaultStackSize = Lib.askNumber("Default stack size", Lib.DEFAULTS.defaultStackSize, 1, 64)
  c.watched = {}
  for _, inv in ipairs(found.inventories) do addWatchedFromInventory(c, inv) end
  if #c.watched == 0 then
    print("No watched inventories configured. You can still add one manually.")
    local inv = Lib.askString("Inventory peripheral name", found.inventories[1] or "")
    if inv and inv ~= "" then
      local item = Lib.askString("Item string", "minecraft:coal")
      table.insert(c.watched, { label = Lib.askString("Label", inv), inventory = inv, item = item, defaultStackSize = c.defaultStackSize, capacityOverride = CONSUMER_FIXED_CAPACITY, capacityMode = "fixed_1280", enabled = true })
    end
  end
  Lib.rescanCommon(c); Lib.saveTable(cfgPath, c); return c
end

if not cfg then cfg = setup() else Lib.defaultThresholds(cfg); cfg.watched = cfg.watched or {}; Lib.rescanCommon(cfg); Lib.saveTable(cfgPath, cfg) end
Lib.openModems(cfg.modems, Lib.CHANNEL)

local persisted = Lib.loadRuntime("consumer", {})
local lastHeartbeat = tonumber(persisted.lastHeartbeat) or 0
local lastStatus = (Lib.loadStatusCache("consumer", {}).status) or persisted.lastStatus
local recent = persisted.recent or {}
local runtime = persisted.runtime or {}

local function savePersist() Lib.saveRuntime("consumer", { runtime = runtime, recent = recent, lastHeartbeat = lastHeartbeat, lastStatus = lastStatus }); Lib.saveStatusCache("consumer", cfg, lastStatus) end
local function log(line) table.insert(recent, 1, os.date("%H:%M:%S") .. " " .. line); while #recent > 9 do table.remove(recent) end; savePersist() end
local function rt(i) runtime[i] = runtime[i] or { emptyLatched = false, lastRequest = 0, requestLatched = false }; return runtime[i] end

local function scanEntry(entry, index)
  local r = rt(index)
  -- Consumer readings always use a fixed effective capacity of 1280, regardless of the exposed inventory size.
  entry.capacityOverride = CONSUMER_FIXED_CAPACITY
  entry.capacityMode = "fixed_1280"
  local inv = Lib.countItem(entry.inventory, entry.item, entry.defaultStackSize or cfg.defaultStackSize, CONSUMER_FIXED_CAPACITY, "slot_limits")
  if inv.percent < (tonumber(cfg.criticalMin) or Lib.DEFAULTS.criticalMin) then r.emptyLatched = true end
  if inv.percent >= (tonumber(cfg.stockNeededMin) or Lib.DEFAULTS.stockNeededMin) then r.emptyLatched = false end
  local state = Lib.inventoryState(inv.percent, cfg, r.emptyLatched)
  inv.state, inv.stateKey, inv.interval, inv.mode, inv.shouldRequest = state.label, state.key, state.interval, state.mode, state.shouldRequest
  inv.emptyLatched = r.emptyLatched
  inv.requestThreshold = tonumber(entry.requestPercent or cfg.consumerRequestPercent) or Lib.DEFAULTS.consumerRequestPercent
  inv.requestLatched = r.requestLatched
  inv.index = index; inv.label = entry.label; inv.inventory = entry.inventory; inv.item = entry.item; inv.enabled = entry.enabled ~= false; inv.capacityOverride = CONSUMER_FIXED_CAPACITY; inv.capacityMode = "fixed_1280"
  -- Consumers are one-shot requesters now: they request exactly one package when the watched inventory reaches the threshold.
  inv.shouldRequest = false
  if not inv.enabled then inv.shouldRequest = false end
  return inv
end

local function scanAll()
  local statuses = {}
  for i, entry in ipairs(cfg.watched or {}) do statuses[i] = scanEntry(entry, i) end
  return statuses
end

local function render(statuses)
  Lib.clear(); term.setTextColor(colors.cyan); print("Frogport Consumer"); term.setTextColor(colors.white)
  print(cfg.name); print(string.rep("-", 32))
  print("Watched inventories: " .. tostring(#(cfg.watched or {}))); print("")
  for _, s in ipairs(statuses or {}) do
    print(string.format("[%s] %s", s.state, s.label or s.inventory))
    print(string.format("  %s %.1f%% %s/%s", tostring(s.item), s.percent, tostring(s.count), tostring(s.capacity)))
    print(string.format("  Request at: %.1f%%  Armed: %s", tonumber(s.requestThreshold or 50), tostring(not s.requestLatched)))
    print("  Capacity: fixed 1280")
  end
  print(""); print("Recent:"); for _, l in ipairs(recent) do print(l) end
end

local function maybeRequest(status)
  if not status.enabled then return end
  local r = rt(status.index)
  local threshold = tonumber(status.requestThreshold or cfg.consumerRequestPercent) or Lib.DEFAULTS.consumerRequestPercent

  -- Rearm only after the inventory climbs back above the request threshold.
  if status.percent > threshold then
    r.requestLatched = false
    status.requestLatched = false
    savePersist()
    return
  end

  -- At or below the threshold, send exactly one request. No repeated pulse train.
  if r.requestLatched then return end
  r.requestLatched = true
  r.lastRequest = os.clock()

  Lib.transmit(cfg.modems, {
    type = "CONSUMER_REQUEST",
    requester = cfg.nodeId,
    requesterName = cfg.name,
    sourceLabel = status.label,
    inventory = status.inventory,
    item = status.item,
    percent = status.percent,
    state = status.state,
    requestMode = "one_package",
    requestThreshold = threshold,
    emptyLatched = status.emptyLatched
  })
  log("Requested 1 package: " .. tostring(status.item) .. " for " .. tostring(status.label))
  savePersist()
end

local function sendStatus(statuses)
  Lib.transmit(cfg.modems, { type = "STATUS", role = "consumer", nodeId = cfg.nodeId, name = cfg.name, watched = statuses, detectedInventories = cfg.detectedInventories, detectedItems = cfg.detectedItems })
end

local function networkLoop()
  while true do
    local _, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if channel == Lib.CHANNEL and Lib.validPacket(message) then
      Lib.configNetworkHandler(cfg, cfgPath, cfg.modems, message, lastStatus)
    end
  end
end

local function mainLoop()
  while true do
    local statuses = scanAll(); lastStatus = { watched = statuses }; savePersist(); render(statuses)
    for _, s in ipairs(statuses) do maybeRequest(s) end
    local now = os.clock(); if now - lastHeartbeat >= Lib.DEFAULTS.heartbeatInterval then lastHeartbeat = now; sendStatus(statuses) end
    sleep(Lib.DEFAULTS.scanInterval)
  end
end

parallel.waitForAny(networkLoop, mainLoop)
