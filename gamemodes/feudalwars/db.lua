-- ============================================================================
-- Feudal Wars v5 — Database Abstraction Layer (DAL)
-- ============================================================================

local FW = require("feudalwars.core")

FW.db = {}

function FW.db.x(sql, ...)
  if not ExecuteSql then return false end
  local query = FW.fmt(sql, ...)
  local ok, res = pcall(ExecuteSql, query)
  if not ok then FW.err("SQL exec failed: %s", tostring(res)) end
  return ok
end

function FW.db.qs(sql, ...)
  if not QuerySql then return {} end
  local query = FW.fmt(sql, ...)
  local ok, rows = pcall(QuerySql, query)
  if not ok or not rows then return {} end
  return rows
end

function FW.db.init()
  FW.db.x([[
    CREATE TABLE IF NOT EXISTS fw_players (
      steam_id TEXT PRIMARY KEY,
      name TEXT,
      purse INTEGER DEFAULT 500,
      house_id TEXT DEFAULT '',
      rank TEXT DEFAULT 'peasant',
      lang TEXT DEFAULT 'ru'
    );
  ]])
  FW.db.x([[
    CREATE TABLE IF NOT EXISTS fw_houses (
      id TEXT PRIMARY KEY,
      name TEXT,
      treasury INTEGER DEFAULT 1000,
      prestige INTEGER DEFAULT 100
    );
  ]])
  FW.db.x([[
    CREATE TABLE IF NOT EXISTS fw_sites (
      id TEXT PRIMARY KEY,
      trade TEXT,
      x REAL, y REAL, z REAL,
      label TEXT
    );
  ]])
  FW.log("database tables verified.")
end

return FW.db
