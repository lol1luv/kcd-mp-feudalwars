-- ============================================================================
-- Feudal Wars v5 — Player Domain Entity
-- ============================================================================

local FW = require("feudalwars.core")

FW.player = {}

function FW.player.load(pid)
  local name = GetPlayerName(pid) or ("Player_" .. pid)
  local guid = (GetPlayerGuid and GetPlayerGuid(pid)) or ("guid_" .. pid)

  local pdata = {
    pid = pid,
    guid = guid,
    name = name,
    purse = 500,
    house_id = "",
    rank = "peasant",
    lang = "ru"
  }

  FW.state.players[pid] = pdata

  FW.db.query("SELECT purse, house_id, rank, lang FROM fw_players WHERE steam_id = @g", { g = guid }, function(rows)
    if rows and rows[1] then
      pdata.purse = tonumber(rows[1].purse) or 500
      pdata.house_id = rows[1].house_id or ""
      pdata.rank = rows[1].rank or "peasant"
      pdata.lang = rows[1].lang or "ru"
    else
      FW.db.execute("INSERT INTO fw_players (steam_id, name, purse, house_id, rank, lang) VALUES (@g, @n, @p, '', 'peasant', 'ru')", {
        g = guid, n = name, p = 500
      })
    end
    FW.log("player %s (pid %d) loaded.", name, pid)
  end)
end

function FW.player.save(pid)
  local pdata = FW.state.players[pid]
  if not pdata then return end
  FW.db.execute("UPDATE fw_players SET purse = @p, house_id = @h, rank = @r, lang = @l WHERE steam_id = @g", {
    p = pdata.purse, h = pdata.house_id, r = pdata.rank, l = pdata.lang, g = pdata.guid
  })
end

function FW.player.on_spawn(pid)
  local pdata = FW.state.players[pid]
  if pdata then
    FW.log("player %s spawned in realm.", pdata.name)
    if AddPlayerActionHint then
      AddPlayerActionHint(pid, "fw-menu", "f2", "Main menu", { binding = "fw.menu" })
    end
  end
end

function FW.player.unload(pid)
  FW.player.save(pid)
  FW.state.players[pid] = nil
end

return FW.player
