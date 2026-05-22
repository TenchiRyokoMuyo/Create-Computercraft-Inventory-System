-- FrogportVaultKeeper.lua
-- Watches one vault inventory, requests matching Producers, and pulses its packager for matching Consumer requests.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()

local cfg, cfgPath = Lib.setupCommon("vault", "VK", true)
cfg.vaultPulseCooldown = cfg.vaultPulseCooldown or Lib.DEFAULTS.vaultPulseCooldown
Lib.saveTable(cfgPath, cfg)

local found = Lib.detectPeripherals()
cfg.modems = (#found.modems > 0) and found.modems or cfg.modems
if not cfg.inventory and found.inventories[1] then cfg.inventory = found.inventories[1] end
if not cfg.packagerSide then
  for _, p in ipairs(found.packagers) do
    if Lib.isSide(p) then cfg.packagerSide = p break end
  end
end
Lib.openModems(cfg.modems, Lib.CHANNEL)

local emptyLatched = false
local lastRequest = 0
local lastHeartbeat = 0
local lastPulse = 0
local lastStatus = nil
local recent = {}

local function log(line)
  table.insert(recent, 1, os.date("%H:%M:%S") .. " " .. line)
  while #recent > 6 do table.remove(recent) end
end

local function render(status)
  Lib.clear()
  term.setTextColor(colors.lime)
  print("Frogport Vault Keeper")
  term.setTextColor(colors.white)
  print(cfg.name)
  print(string.rep("-", 28))
  print("Item: " .. tostring(cfg.item))
  print("Inventory: " .. tostring(cfg.inventory))
  print("Packager side: " .. tostring(cfg.packagerSide))
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
    role = "vault",
    nodeId = cfg.nodeId,
    name = cfg.name,
    item = cfg.item,
    inventory = cfg.inventory,
    packagerSide = cfg.packagerSide,
    count = status.count,
    capacity = status.capacity,
    percent = status.percent,
    state = status.state,
    stateKey = status.stateKey,
    mode = status.mode,
    emptyLatched = emptyLatched
  })
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

local function maybeRequestProduction(status)
  if not status.shouldRequest then return end
  local now = os.clock()
  local interval = status.interval or cfg.emptyInterval or Lib.DEFAULTS.emptyInterval
  if now - lastRequest < interval then return end
  lastRequest = now

  Lib.transmit(cfg.modems, {
    type = "PRODUCER_REQUEST",
    requester = cfg.nodeId,
    requesterName = cfg.name,
    item = cfg.item,
    percent = status.percent,
    state = status.state,
    requestMode = status.mode,
    emptyLatched = emptyLatched
  })
  log("Asked producers: " .. status.state)
end

local function pulseForConsumer(packet)
  if packet.item ~= cfg.item then return end

  local now = os.clock()
  if now - lastPulse < (tonumber(cfg.vaultPulseCooldown) or Lib.DEFAULTS.vaultPulseCooldown) then
    return
  end
  lastPulse = now

  local ok, err = Lib.pulse(cfg.packagerSide, cfg.pulseLength)
  if ok then
    log("Pulsed for " .. tostring(packet.requesterName or packet.requester))
    Lib.transmit(cfg.modems, {
      type = "VAULT_PULSED",
      nodeId = cfg.nodeId,
      name = cfg.name,
      item = cfg.item,
      requester = packet.requester,
      requesterName = packet.requesterName,
      state = lastStatus and lastStatus.state or "unknown"
    })
  else
    log("Pulse failed: " .. tostring(err))
  end
end

local function networkLoop()
  while true do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if channel == Lib.CHANNEL and Lib.validPacket(message) then
      if message.type == "CONSUMER_REQUEST" and message.item == cfg.item then
        pulseForConsumer(message)
      end
    end
  end
end

local function mainLoop()
  while true do
    local status = scan()
    lastStatus = status
    render(status)
    maybeRequestProduction(status)

    local now = os.clock()
    if now - lastHeartbeat >= Lib.DEFAULTS.heartbeatInterval then
      lastHeartbeat = now
      sendStatus(status)
    end

    sleep(Lib.DEFAULTS.scanInterval)
  end
end

parallel.waitForAny(networkLoop, mainLoop)
