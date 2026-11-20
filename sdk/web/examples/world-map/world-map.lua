-- Example: a world map window drawn by a web page, with the game's own map and a marker for every player.
--
-- The End key (a key binding the mode declares - a player can bind another) or /worldmap opens the window: the page shows the map
-- of the server's level (KcdMp.mapImage - every player's game makes the picture from its own files, nothing is downloaded) and the
-- mode sends it where every player is, once a second while it is open. A click on a town's outline opens the town's detailed map;
-- a click anywhere else sends the mode the world position there (KcdMp.mapToWorld), which it says in the chat - a waypoint, a
-- teleport for admins, a meeting point: what a click means is your mode's.
--
-- Run it with [gamemode] script = "sdk/web/examples/world-map/world-map.lua", or copy this folder into gamemodes/.

SetGameModeText("world map example")

local open = {}   -- pid -> true while the window is up

local function send(pid)
  local players = {}
  for _, other in ipairs(GetPlayers()) do
    local x, y = GetPlayerPos(other)
    if x then
      players[#players + 1] = { id = other, name = GetPlayerName(other), x = x, y = y, you = other == pid }
    end
  end
  SendPlayerWebMessage(pid, "worldmap", { players = players })
end

local function show(pid)
  open[pid] = true
  send(pid)
  ShowPlayerWebFrame(pid, "worldmap")
  SetPlayerWebFocus(pid, "worldmap", false, true)   -- the mouse, not the keyboard: the player can still walk
end

local function hide(pid)
  open[pid] = nil
  HidePlayerWebFrame(pid, "worldmap")   -- (hiding gives the mouse back)
end

local function toggle(pid)
  if open[pid] then hide(pid) else show(pid) end
end

function OnGameModeInit()
  RegisterKeyBinding("worldmap.toggle", "Open or close the world map", "end")
  RegisterCommand("worldmap", function(pid) toggle(pid) end, { help = "Open or close the world map" })
  SetTimer(function()
    for pid in pairs(open) do
      if IsPlayerConnected(pid) then send(pid) else open[pid] = nil end
    end
  end, 1000, true)
end

function OnPlayerKeyBinding(pid, name, pressed)
  if name == "worldmap.toggle" and pressed then
    toggle(pid)
  end
end

function OnPlayerDisconnect(pid)
  open[pid] = nil
end

-- what the page sends: check it like any input from a player
function OnClientEvent(pid, name, payload, source)
  if source ~= "worldmap" then
    return
  end
  if name == "map.close" then
    hide(pid)
  elseif name == "map.click" and type(payload) == "table" and tonumber(payload.x) and tonumber(payload.y) then
    SendClientMessage(pid, COLOR_SERVER, string.format("You clicked the map at %.0f, %.0f.", tonumber(payload.x), tonumber(payload.y)))
  end
end

function OnPlayerSpawn(pid)
  SendClientMessage(pid, COLOR_SERVER, "Press End (or type /worldmap) to open the world map - a web page of this server.")
end
