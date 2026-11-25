-- ============================================================================
-- Feudal Wars v5 — Clean Architecture Entry Point (KCD:MP Engine)
-- ============================================================================

local FW = require("feudalwars.core")
FW.config = require("feudalwars.config")
FW.db = require("feudalwars.db")
FW.player = require("feudalwars.player")
FW.house = require("feudalwars.house")
FW.economy = require("feudalwars.economy")
FW.npc = require("feudalwars.npc")
FW.bridge = require("feudalwars.bridge")
FW.ui = require("feudalwars.ui")

SetGameModeText("feudalwars v5")

function OnGameModeInit()
  FW.log("Booting Feudal Wars v5 Engine...")
  FW.db.init()
  FW.house.init()
  FW.economy.init()
  FW.npc.init()
  FW.ui.init()

  SetSpawnPointMode(1)
  AddSpawnPoint(FW.config.spawn.x, FW.config.spawn.y, FW.config.spawn.z, FW.config.spawn.yaw, "town")
  FW.log("Realm initialized successfully.")
end

function OnPlayerConnect(pid)
  FW.player.load(pid)
end

function OnPlayerSpawn(pid)
  FW.player.on_spawn(pid)
end

function OnPlayerDeath(pid, attacker)
  if attacker and attacker >= 0 and IsPlayerConnected(attacker) then
    FW.house.on_kill(attacker, pid)
  end
end

function OnPlayerDisconnect(pid, reason)
  FW.player.unload(pid)
end

function OnPlayerKeyBinding(pid, name, pressed)
  if not pressed then return end
  if name == "fw.menu" then
    FW.ui.open_menu(pid)
  end
end

function OnPlayerHitScenery(pid, hit)
  if hit then
    FW.economy.on_hit(pid, hit)
  end
end

function OnPlayerInteractActor(pid, actor_id)
  FW.npc.interact(pid, actor_id)
end

function OnClientEvent(pid, name, payload, source)
  FW.bridge.handle(pid, name, payload, source)
end
