-- ============================================================================
-- Feudal Wars v5 — Clean Architecture Entry Point
-- Kingdom Come: Deliverance Multiplayer (KCD:MP) Game Mode
-- ============================================================================

local FW = require("feudalwars.core")
FW.config = require("feudalwars.config")
FW.db = require("feudalwars.db")
FW.player = require("feudalwars.player")
FW.house = require("feudalwars.house")
FW.economy = require("feudalwars.economy")
FW.npc = require("feudalwars.npc")
FW.ui = require("feudalwars.ui")
FW.bridge = require("feudalwars.bridge")

SetGameModeText("feudalwars v5")

function OnGameModeInit()
  FW.log("Booting Feudal Wars v5 (Clean Architecture Engine)...")
  FW.db.init()
  FW.house.init()
  FW.economy.init()
  FW.npc.init()
  FW.ui.init()

  SetSpawnPointMode(1)
  AddSpawnPoint(FW.config.spawn.x, FW.config.spawn.y, FW.config.spawn.z, FW.config.spawn.yaw, "town")
  FW.log("Feudal realm v5 initialized successfully.")
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

function OnPlayerHit(pid, hit)
  if hit then
    FW.economy.on_hit(pid, hit)
  end
end

function OnWebMessage(pid, frame, event, json_data)
  FW.bridge.handle(pid, frame, event, json_data)
end
