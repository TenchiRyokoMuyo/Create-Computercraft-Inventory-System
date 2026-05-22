-- FrogportProducer.lua
-- Pulses one packager when a matching Vault Keeper requests production.
-- May report attached inventory, but never requests items.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()

local cfg, cfgPath = Lib.setupCommon("producer", "PROD", false)
cfg.producerCooldown = cfg.producerCooldown or Lib.DEFAULTS.producerCooldown
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

local lastPulse = 0
local lastHeartbeat = 0
local recent = {}
local lastStatus = nil

local function log(line)
  table.insert(recent, 1, os.date("%H:%M:%S") .. " " .. line)
  while #recent > 6 do table.remove(recent) end
end

local function scan()
  if not cfg.inventory then
    return {
      count = 0, capacity = 0, percent = 0,
      state = "No Inventory", stateKey = "none",
      mode = "none", shouldRequest = false
    }
  end
  local inv = Lib.countItem(cfg.inventory, cfg.item, cfg.defaultStackSize)
  local state = Lib.inventoryState(inv.percent, cfg, false)
  inv.state = state.label
  inv.stateKey = state.key
  inv.mode = state.mode
  inv.shouldRequest = false
  return inv
end

local function render(status)
  Lib.clear()
  term.setTextColor(colors.orange)
  print("Frogport Producer")
  term.setTextColor(colors.white)
  print(cfg.name)
  print(string.rep("-", 28))
  print("Produces: " .. tostring(cfg.item))
  print("Packager side: " .. tostring(cfg.packagerSide))
  print("Inventory: " .. tostring(cfg.inventory or "none"))
  print("")
  if status and cfg.inventory then
    print("Count: " .. status.count .. " / " .. status.capacity)
    print(string.format("Percent: %.1f%%", status.percent))
    print("State: " .. status.state)
  end
  print("Cooldown: " .. tostring(cfg.producerCooldown) .. "s")
  print("")
  print("Recent:")
  for _, l in ipairs(recent) do print(l) end
end

local function sendStatus(status)
  Lib.transmit(cfg.modems, {
    type = "STATUS",
    role = "producer",
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
    mode = status.mode
  })
end

local function requestCooldown(packet)
  if packet.requestMode == "constant" or packet.emptyLatched then
    return math.max((tonumber(cfg.pulseLength) or Lib.DEFAULTS.pulseLength) * 2, 0.5)
  end
  return tonumber(cfg.producerCooldown) or Lib.DEFAULTS.producerCooldown
end

local function handleProducerRequest(packet)
  if packet.item ~= cfg.item then return end
  local now = os.clock()
  local cd = requestCooldown(packet)
  if now - lastPulse < cd then return end
  lastPulse = now

  local ok, err = Lib.pulse(cfg.packagerSide, cfg.pulseLength)
  if ok then
    log("Pulsed for " .. tostring(packet.requesterName or packet.requester))
    Lib.transmit(cfg.modems, {
      type = "PRODUCER_PULSED",
      nodeId = cfg.nodeId,
      name = cfg.name,
      item = cfg.item,
      requester = packet.requester,
      requesterName = packet.requesterName
    })
  else
    log("Pulse failed: " .. tostring(err))
  end
end

local function networkLoop()
  while true do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if channel == Lib.CHANNEL and Lib.validPacket(message) then
      if message.type == "PRODUCER_REQUEST" and message.item == cfg.item then
        handleProducerRequest(message)
      end
    end
  end
end

local function mainLoop()
  while true do
    local status = scan()
    lastStatus = status
    render(status)

    local now = os.clock()
    if now - lastHeartbeat >= Lib.DEFAULTS.heartbeatInterval then
      lastHeartbeat = now
      sendStatus(status)
    end

    sleep(Lib.DEFAULTS.scanInterval)
  end
end

parallel.waitForAny(networkLoop, mainLoop)
