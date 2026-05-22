-- FrogportConsumer.lua
-- Watches one inventory and requests matching Vault Keepers to restock.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()

local cfg, cfgPath = Lib.setupCommon("consumer", "CON", true)
Lib.saveTable(cfgPath, cfg)

local found = Lib.detectPeripherals()
cfg.modems = (#found.modems > 0) and found.modems or cfg.modems
if not cfg.inventory and found.inventories[1] then cfg.inventory = found.inventories[1] end
Lib.openModems(cfg.modems, Lib.CHANNEL)

local emptyLatched = false
local lastRequest = 0
local lastHeartbeat = 0
local recent = {}

local function log(line)
  table.insert(recent, 1, os.date("%H:%M:%S") .. " " .. line)
  while #recent > 6 do table.remove(recent) end
end

local function scan()
  local inv = Lib.countItem(cfg.inventory, cfg.item, cfg.defaultStackSize)
  if inv.percent <= (tonumber(cfg.criticalMin) or Lib.DEFAULTS.criticalMin) - 0.001 then
    emptyLatched = true
  end
  if inv.percent >= (tonumber(cfg.stockNeededMin) or Lib.DEFAULTS.stockNeededMin) then
    emptyLatched = false
  end
  local state = Lib.inventoryState(inv.percent, cfg, emptyLatched)
  inv.state = state.label
  inv.stateKey = state.key
  inv.interval = state.interval
  inv.mode = state.mode
  inv.shouldRequest = state.shouldRequest
  return inv
end

local function render(status)
  Lib.clear()
  term.setTextColor(colors.cyan)
  print("Frogport Consumer")
  term.setTextColor(colors.white)
  print(cfg.name)
  print(string.rep("-", 28))
  print("Needs: " .. tostring(cfg.item))
  print("Inventory: " .. tostring(cfg.inventory))
  print("")
  if status then
    print("Count: " .. status.count .. " / " .. status.capacity)
    print(string.format("Percent: %.1f%%", status.percent))
    print("State: " .. status.state)
    print("Mode: " .. status.mode)
    print("Empty latch: " .. tostring(emptyLatched))
  end
  print("")
  print("Recent:")
  for _, l in ipairs(recent) do print(l) end
end

local function sendStatus(status)
  Lib.transmit(cfg.modems, {
    type = "STATUS",
    role = "consumer",
    nodeId = cfg.nodeId,
    name = cfg.name,
    item = cfg.item,
    inventory = cfg.inventory,
    count = status.count,
    capacity = status.capacity,
    percent = status.percent,
    state = status.state,
    stateKey = status.stateKey,
    mode = status.mode,
    emptyLatched = emptyLatched
  })
end

local function maybeRequest(status)
  if not status.shouldRequest then return end
  local now = os.clock()
  local interval = status.interval or cfg.emptyInterval or Lib.DEFAULTS.emptyInterval
  if now - lastRequest < interval then return end
  lastRequest = now

  Lib.transmit(cfg.modems, {
    type = "CONSUMER_REQUEST",
    requester = cfg.nodeId,
    requesterName = cfg.name,
    item = cfg.item,
    percent = status.percent,
    state = status.state,
    requestMode = status.mode,
    emptyLatched = emptyLatched
  })
  log("Requested restock: " .. status.state)
end

while true do
  local status = scan()
  render(status)
  maybeRequest(status)

  local now = os.clock()
  if now - lastHeartbeat >= Lib.DEFAULTS.heartbeatInterval then
    lastHeartbeat = now
    sendStatus(status)
  end

  sleep(Lib.DEFAULTS.scanInterval)
end
