-- ============================================================================
-- Feudal Wars v5 — House Domain Entity & Factions
-- ============================================================================

local FW = require("feudalwars.core")

FW.house = {}

function FW.house.init()
  FW.db.query("SELECT id, name, treasury, prestige FROM fw_houses", {}, function(rows)
    if not rows or #rows == 0 then
      FW.db.execute("INSERT INTO fw_houses (id, name, treasury, prestige) VALUES ('rosenberg', 'Дом Розенберг', 2500, 150)")
      FW.db.execute("INSERT INTO fw_houses (id, name, treasury, prestige) VALUES ('lichtenstein', 'Дом Лихтенштейн', 2000, 120)")
      FW.state.houses["rosenberg"] = { id = "rosenberg", name = "Дом Розенберг", treasury = 2500, prestige = 150 }
      FW.state.houses["lichtenstein"] = { id = "lichtenstein", name = "Дом Лихтенштейн", treasury = 2000, prestige = 120 }
    else
      for _, r in ipairs(rows) do
        FW.state.houses[r.id] = {
          id = r.id,
          name = r.name,
          treasury = tonumber(r.treasury) or 1000,
          prestige = tonumber(r.prestige) or 100
        }
      end
    end
    FW.log("houses initialized.")
  end)
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
      FW.db.execute("UPDATE fw_houses SET prestige = @p, treasury = @t WHERE id = @i", {
        p = h.prestige, t = h.treasury, i = h.id
      })
      FW.log("house %s gained glory for defeating rival.", h.name)
    end
  end
end

return FW.house
