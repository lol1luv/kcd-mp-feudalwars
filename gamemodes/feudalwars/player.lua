-- ============================================================================
-- Feudal Wars v5 — Player Domain Entity
-- ============================================================================

local FW = require("feudalwars.core")

FW.player = {}

function FW.player.load(pid)
  local name = GetPlayerName(pid) or ("Player_" .. pid)
  local guid = GetPlayerGuid and GetPlayerGuid(pid) or ("guid_" .. pid)
  
  local rows = FW.db.qs("SELECT purse, house_id, rank, lang FROM fw_players WHERE steam_id = '%s'", guid)
  local pdata = {
    pid = pid,
    guid = guid,
    name = name,
    purse = 500,
    house_id = "",
    rank = "peasant",
    lang = "ru"
  }
  
  if rows and #rows > 0 then
    pdata.purse = tonumber(rows[1].purse) or 500
    pdata.house_id = rows[1].house_id or ""
    pdata.rank = rows[1].rank or "peasant"
    pdata.lang = rows[1].lang or "ru"
  else
    FW.db.x("INSERT INTO fw_players (steam_id, name, purse, house_id, rank, lang) VALUES ('%s', '%s', %d, '', 'peasant', 'ru')", guid, name, 500)
  end

  FW.state.players[pid] = pdata
  FW.log("player %s (pid %d) loaded: %d groschen", name, pid, pdata.purse)
end

function FW.player.save(pid)
  local pdata = FW.state.players[pid]
  if not pdata then return end
  FW.db.x("UPDATE fw_players SET purse = %d, house_id = '%s', rank = '%s', lang = '%s' WHERE steam_id = '%s'",
    pdata.purse, pdata.house_id, pdata.rank, pdata.lang, pdata.guid)
end

function FW.player.on_spawn(pid)
  local pdata = FW.state.players[pid]
  if pdata then
    FW.log("player %s spawned in realm", pdata.name)
  end
end

function FW.player.unload(pid)
  FW.player.save(pid)
  FW.state.players[pid] = nil
end

return FW.player
