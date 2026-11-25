-- ============================================================================
-- Feudal Wars v5 — Native Database Layer
-- ============================================================================

local FW = require("feudalwars.core")

FW.db = {}
local handle = nil

function FW.db.init()
  if GetDatabase then
    handle = GetDatabase()
  end

  if handle then
    handle:ExecuteSync([[
      CREATE TABLE IF NOT EXISTS fw_players (
        steam_id VARCHAR(64) PRIMARY KEY,
        name VARCHAR(64),
        purse INT DEFAULT 500,
        house_id VARCHAR(32) DEFAULT '',
        rank VARCHAR(32) DEFAULT 'peasant',
        lang VARCHAR(8) DEFAULT 'ru'
      );
    ]])
    handle:ExecuteSync([[
      CREATE TABLE IF NOT EXISTS fw_houses (
        id VARCHAR(32) PRIMARY KEY,
        name VARCHAR(64),
        treasury INT DEFAULT 1000,
        prestige INT DEFAULT 100
      );
    ]])
    FW.log("database tables initialized.")
  else
    FW.log("running in memory-only mode (no database handle).")
  end
end

function FW.db.execute(sql, params)
  if handle then
    handle:Execute(sql, params or {}, function() end)
  end
end

function FW.db.query(sql, params, cb)
  if handle then
    handle:Query(sql, params or {}, cb)
  else
    if cb then cb({}) end
  end
end

return FW.db
