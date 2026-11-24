-- KCD:MP game mode: feudalwars (v4).
--
-- A feudal role-play realm: houses with ranks and wars, a treasury economy in real
-- groschen, persistent accounts, work that pays per real strike, the game's own
-- gathering, hunting, crafting and shops, an in-world cast of NPCs, a web interface
-- and the crown's commands.
--
-- The mode is a folder: this file is the single entry point the server loads, and it
-- pulls the rest in with `require`, which resolves beside it (gamemodes/feudalwars/).
--
--   core.lua      the namespace, config, language, database, money, frames, probes
--   world.lua     work places, the realm's people, ground handling, travel
--   economy.lua   labour, herbs, hunting, the game's stations, the market
--   factions.lua  houses, wars, the treasury, prestige, upkeep
--   social.lua    accounts, the character page, paying, the lifecycle
--   build.lua     the architect's blueprints
--   npc.lua       the NPC constructor and the conversations
--   justice.lua   the crown's console and the map editor
--   ui.lua        the menu, the page dispatcher and every chat command
--
-- Needs the game mode database ([gamemode.database] in server.toml) for persistence;
-- without one everything still works but is not saved across restarts.
-- Run with `KcdMp.Server --gamemode gamemodes/feudalwars.lua`.

local FW = require("feudalwars.core")
require("feudalwars.world")
require("feudalwars.economy")
require("feudalwars.factions")
require("feudalwars.social")
require("feudalwars.build")
require("feudalwars.npc")
require("feudalwars.justice")
require("feudalwars.ui")

SetGameModeText("feudalwars")

-- ---------------------------------------------------------------- boot

function OnGameModeInit()
  FW.log("v%s on %s", FW.VERSION, GetLevel())
  FW.probe_world()
  FW.db_init()

  FW.house_load_all()
  FW.blueprints_load_all()
  FW.market_load_all()
  FW.people_load_all()
  FW.zone_load_all()

  AddSpawnPoint(FW.spawn.x, FW.spawn.y, FW.spawn.z, FW.spawn.yaw, "town")

  -- the realm's own trades, if the crown has not placed any yet: a small ring of work
  -- places around the spawn. Admins move them to their true homes with /zone here.
  if next(FW.state.sites) == nil then
    local plan = {
      { trade = "quarry", dx = 22, dy = 14 },
      { trade = "woods", dx = -24, dy = 16 },
      { trade = "fields", dx = -14, dy = -22 },
      { trade = "hunt", dx = 26, dy = -18 },
      { trade = "workshop", dx = 8, dy = 8 },
    }
    for _, p in ipairs(plan) do
      FW.zone_add(p.trade, FW.spawn.x + p.dx, FW.spawn.y + p.dy, FW.spawn.z, nil)
    end
    FW.log("no work places saved: raised the default ring around the spawn")
  end

  -- the game's own stations wait for the mode: only inside a workshop or quarry
  pcall(SetCraftCheck, "*", true)

  -- the game's own pickpocketing between players, with the realm's rules
  pcall(SetPickpocketing, true, { range = 3, cooldown = 30, money = true, money_share = 0.15, money_cap = 200 })

  -- the scoreboard: house, rank, purse
  pcall(SetScoreboardColumns, {
    { key = "house", label = "House", width = 120 },
    { key = "rank", label = "Rank", width = 80 },
    { key = "purse", label = "Groschen", width = 90, align = "right" },
  })

  FW.register_commands()

  -- the world's upkeep: wars expire, treasuries pay their people, once a minute
  SetTimer(function()
    FW.war_tick()
    for _, zone in ipairs(FW.zone_all()) do
      if zone.trade == "hunt" then FW.hunt_spawn(zone) end
    end
  end, 60000, true)

  -- earnings are gathered and told in one line, a few times a minute
  SetTimer(function() FW.flush_all_earnings() end, 12000, true)

  FW.log("ready: %d house(s), %d work place(s), %d person(s), %d blueprint(s)",
    (function() local n = 0 for _ in pairs(FW.state.houses) do n = n + 1 end return n end)(),
    (function() local n = 0 for _ in pairs(FW.state.sites) do n = n + 1 end return n end)(),
    (function() local n = 0 for _ in pairs(FW.state.people_list) do n = n + 1 end return n end)(),
    (function() local n = 0 for _ in pairs(FW.state.blueprints) do n = n + 1 end return n end)())
end

-- ---------------------------------------------------------------- lifecycle

function OnPlayerConnect(pid)
  FW.account_open(pid)
end

function OnPlayerRequestSpawn(pid)
  local sp = GetSpawnPoints("town")[1]
  if sp then SetSpawnInfo(pid, sp.x, sp.y, sp.z, sp.yaw) end
  return true
end

function OnPlayerSpawn(pid)
  FW.account_spawn(pid)
end

function OnPlayerDeath(pid, attacker)
  if attacker and attacker >= 0 then FW.war_score(pid, attacker) end
end

function OnPlayerDisconnect(pid, reason)
  FW.account_close(pid)
end

-- ---------------------------------------------------------------- the world's callbacks

function OnPlayerKeyBinding(pid, name, pressed)
  if not pressed then return end
  if name == "fw.menu" then
    FW.menu_panel(pid)
  elseif name == "fw.work" then
    FW.work_report(pid)
  end
end

-- a swing struck the level: the work lives here, combat lives elsewhere - never blocked
function OnPlayerHitScenery(pid, hit)
  FW.work_on_hit(pid, hit)
end

-- the game's own herb picking: the realm pays a little for it
function OnPlayerPickHerb(pid, herb)
  FW.herb_on_pick(pid, herb)
end

-- a hunted animal fell: the bounty is paid
function OnActorDeath(id, attacker)
  if attacker and attacker >= 0 then FW.hunt_pay(attacker, id) end
end

-- the game's own stations: the mode only says where they may be used
function OnPlayerCraft(pid, station, class)
  return FW.craft_check(pid, station, class)
end

-- the use key on a placed person: vendors open their shop (the engine does it), the rest speak
function OnPlayerInteractActor(pid, id)
  local n = FW.person_by_actor(id)
  if not n then return end
  if n.role == "vendor" then return end
  FW.talk(pid, n)
end

function OnDialogueResponse(pid, dialogid, option, reason)
  FW.dialogue_answer(pid, dialogid, option, reason)
end

-- ---------------------------------------------------------------- the web pages

function OnClientEvent(pid, name, payload, source)
  local data = {}
  if payload and payload ~= "" and payload:sub(1, 1) == "{" then
    local ok, decoded = pcall(JsonDecode, payload)
    if ok and type(decoded) == "table" then data = decoded end
  end
  FW.web_event(pid, name, data)
end

function OnPlayerWebSurfaceEvent(pid, id, name, payload)
  local data = {}
  if payload and payload ~= "" then
    local ok, decoded = pcall(JsonDecode, payload)
    if ok and type(decoded) == "table" then data = decoded end
  end
  FW.web_event(pid, name, data)
end