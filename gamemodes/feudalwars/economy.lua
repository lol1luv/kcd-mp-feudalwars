-- ============================================================================
-- Feudal Wars v5 — Physical Hit Economy
-- ============================================================================

local FW = require("feudalwars.core")

FW.economy = {}

function FW.economy.init()
  FW.economy.setup_zones()
  FW.log("economy engine initialized.")
end

function FW.economy.setup_zones()
  local level = tostring(GetLevel and GetLevel() or ""):lower()
  local preset = FW.config.level_presets[level] or FW.config.level_presets.kutnohorsko

  FW.state.sites = {}
  for _, p in ipairs(preset) do
    local z = FW.ground(FW.config.spawn.x + p.dx, FW.config.spawn.y + p.dy, FW.config.spawn.z)
    local site_id = p.trade .. "_" .. math.floor(p.dx) .. "_" .. math.floor(p.dy)
    FW.state.sites[site_id] = {
      id = site_id,
      trade = p.trade,
      x = FW.config.spawn.x + p.dx,
      y = FW.config.spawn.y + p.dy,
      z = z,
      label = p.label
    }
  end
  FW.log("work zones set up for level '%s'", level)
end

function FW.economy.on_hit(pid, hit)
  local pdata = FW.state.players[pid]
  if not pdata or not hit then return end

  local now = GetServerTime and GetServerTime() or 0
  local cd = FW.state.work_cd[pid] or 0
  if now < cd then return end
  FW.state.work_cd[pid] = now + FW.config.work_cooldown_ms

  local closest_site = nil
  local min_dist = 40.0
  for _, site in pairs(FW.state.sites) do
    local dx = hit.x - site.x
    local dy = hit.y - site.y
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < min_dist then
      min_dist = dist
      closest_site = site
    end
  end

  local trade = closest_site and closest_site.trade or "quarry"
  local reward = FW.config.trade_rewards[trade] or 10

  pdata.purse = pdata.purse + reward
  FW.player.save(pid)

  local msg = pdata.lang == "ru"
    and FW.fmt("Добыто ресурса [%s]! Получено +%s грошей.", trade, FW.grosch(reward))
    or FW.fmt("Gathered resource [%s]! Received +%s groschen.", trade, FW.grosch(reward))

  if SendChatMessage then SendChatMessage(pid, msg) end
end

return FW.economy
