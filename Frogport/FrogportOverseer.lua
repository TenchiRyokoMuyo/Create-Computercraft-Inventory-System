-- FrogportOverseer.lua
-- Passive dashboard for Frogport Central Command.

local Lib = dofile("/Frogport/FrogportLib.lua")
Lib.ensureDirs()

local cfgPath = Lib.DATA .. "/overseer.cfg"
local cfg = Lib.loadTable(cfgPath, nil)

if not cfg then
  Lib.header("First setup: overseer")
  local found = Lib.detectPeripherals()
  Lib.printDetection(found)
  print("")
  cfg = {
    role = "overseer",
    nodeId = Lib.uuid("OVER"),
    name = Lib.askString("Overseer name", "Frogport Overseer " .. os.getComputerID()),
    modems = found.modems,
    monitor = found.monitors[1],
    textScale = Lib.askNumber("Monitor text scale", 0.5, 0.5, 5)
  }
  Lib.saveTable(cfgPath, cfg)
  print("Saved config.")
  print("Press any key.")
  os.pullEvent("key")
end

local found = Lib.detectPeripherals()
cfg.modems = (#found.modems > 0) and found.modems or cfg.modems
cfg.monitor = found.monitors[1] or cfg.monitor
Lib.openModems(cfg.modems, Lib.CHANNEL)

local nodes = {}
local events = {}
local screen = term.current()

local function addEvent(line)
  table.insert(events, 1, os.date("%H:%M:%S") .. " " .. line)
  while #events > 12 do table.remove(events) end
end

local function getOut()
  if cfg.monitor and peripheral.isPresent(cfg.monitor) then
    local mon = peripheral.wrap(cfg.monitor)
    if mon then
      pcall(function() mon.setTextScale(cfg.textScale or 0.5) end)
      return mon
    end
  end
  return term.current()
end

local function colorForState(state)
  if state == "Full" then return colors.lime end
  if state == "Stock Needed" then return colors.yellow end
  if state == "Low" then return colors.orange end
  if state == "Critically Low" then return colors.red end
  if state == "Empty" then return colors.red end
  return colors.white
end

local function roleOrder(role)
  if role == "vault" then return 1 end
  if role == "producer" then return 2 end
  if role == "consumer" then return 3 end
  return 4
end

local function sortedNodes(role)
  local t = {}
  for _, n in pairs(nodes) do
    if not role or n.role == role then table.insert(t, n) end
  end
  table.sort(t, function(a,b)
    local ra, rb = roleOrder(a.role), roleOrder(b.role)
    if ra ~= rb then return ra < rb end
    return tostring(a.name) < tostring(b.name)
  end)
  return t
end

local function writeLine(out, y, text, color)
  local w, h = out.getSize()
  if y > h then return y end
  out.setCursorPos(1, y)
  out.setTextColor(color or colors.white)
  out.clearLine()
  if #text > w then text = text:sub(1, w) end
  out.write(text)
  return y + 1
end

local function drawSection(out, y, title, role)
  y = writeLine(out, y, title, colors.cyan)
  local list = sortedNodes(role)
  if #list == 0 then
    y = writeLine(out, y, "  none", colors.gray)
    return y + 1
  end

  for _, n in ipairs(list) do
    local age = math.floor((os.epoch("utc") - (n.time or 0)) / 1000)
    local stale = age > 15
    local pct = tonumber(n.percent) or 0
    local state = tostring(n.state or "unknown")
    local line = string.format("  %-16s %-22s %6.1f%% %-15s", tostring(n.name or n.nodeId), tostring(n.item or ""), pct, state)
    if stale then
      line = line .. " STALE"
      y = writeLine(out, y, line, colors.gray)
    else
      y = writeLine(out, y, line, colorForState(state))
    end
  end
  return y + 1
end

local function render()
  local out = getOut()
  local old = term.redirect(out)
  out.setBackgroundColor(colors.black)
  out.setTextColor(colors.white)
  out.clear()
  out.setCursorPos(1,1)

  local y = 1
  y = writeLine(out, y, "FROGPORT CENTRAL COMMAND", colors.lime)
  y = writeLine(out, y, cfg.name .. " | Channel " .. Lib.CHANNEL, colors.white)
  y = writeLine(out, y, string.rep("-", math.min(50, ({out.getSize()})[1])), colors.gray)

  y = drawSection(out, y, "VAULT KEEPERS", "vault")
  y = drawSection(out, y, "PRODUCERS", "producer")
  y = drawSection(out, y, "CONSUMERS", "consumer")

  y = writeLine(out, y, "RECENT EVENTS", colors.cyan)
  for _, e in ipairs(events) do
    y = writeLine(out, y, "  " .. e, colors.white)
  end

  term.redirect(old)
end

local function handlePacket(packet)
  if packet.type == "STATUS" then
    nodes[packet.nodeId] = packet
  elseif packet.type == "PRODUCER_REQUEST" then
    addEvent("PROD_REQ " .. tostring(packet.requesterName or packet.requester) .. " -> " .. tostring(packet.item) .. " " .. tostring(packet.state))
  elseif packet.type == "CONSUMER_REQUEST" then
    addEvent("CONS_REQ " .. tostring(packet.requesterName or packet.requester) .. " -> " .. tostring(packet.item) .. " " .. tostring(packet.state))
  elseif packet.type == "PRODUCER_PULSED" then
    addEvent("PRODUCER PULSE " .. tostring(packet.name) .. " " .. tostring(packet.item))
  elseif packet.type == "VAULT_PULSED" then
    addEvent("VAULT PULSE " .. tostring(packet.name) .. " " .. tostring(packet.item))
  end
end

local function networkLoop()
  while true do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if channel == Lib.CHANNEL and Lib.validPacket(message) then
      handlePacket(message)
    end
  end
end

local function renderLoop()
  while true do
    render()
    sleep(1)
  end
end

parallel.waitForAny(networkLoop, renderLoop)
