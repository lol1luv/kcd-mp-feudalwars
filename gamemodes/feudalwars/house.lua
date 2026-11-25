-- ============================================================================
-- Feudal Wars v5 — House Domain Entity & Factions
-- ============================================================================

local FW = require("feudalwars.core")

FW.house = {}

function FW.house.init()
  local rows = FW.db.qs("SELECT id, name, treasury, prestige FROM fw_houses")
  if #rows == 0 then
    FW.db.x("INSERT INTO fw_houses (id, name, treasury, prestige) VALUES ('rosenberg', 'Дом Розенберг', 2500, 150)")
    FW.db.x("INSERT INTO fw_houses (id, name, treasury, prestige) VALUES ('lichtenstein', 'Дом Лихтенштейн', 2000, 120)")
    rows = FW.db.qs("SELECT id, name, treasury, prestige FROM fw_houses")
  end

  for _, r in ipairs(rows) do
    FW.state.houses[r.id] = {
      id = r.id,
      name = r.name,
      treasury = tonumber(r.treasury) or 1000,
      prestige = tonumber(r.prestige) or 100
    }
  end
  FW.log("loaded %d feudal houses.", #rows)
end

function FW.house.on_kill(killer_pid, victim_pid)
  local k_data = FW.state.players[killer_pid]
  local v_data = FW.state.players[victim_pid]
  if not k_data or not v_data then return end

  if k_data.house_id ~= "" and k_data.house_id ~= v_data.house_id then
    local h = FW.state.houses[k_data.house_id]
    if h then
      h.prestige = h.prestige + 5
      h.treasury = h.treasury + 50
      FW.db.x("UPDATE fw_houses SET prestige = %d, treasury = %d WHERE id = '%s'", h.prestige, h.treasury, h.id)
      FW.log("house %s gained prestige & war glory by kill", h.name)
    end
  end
end

return FW.house
