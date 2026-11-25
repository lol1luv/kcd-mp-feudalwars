-- ============================================================================
-- Feudal Wars v5 — Realm Configuration
-- ============================================================================

local FW = require("feudalwars.core")

FW.config = {
  spawn = { x = 2884.2, y = 1406.8, z = 44.5, yaw = 120.0 },
  work_cooldown_ms = 1800,
  trade_rewards = {
    quarry = 15,
    woods = 12,
    fields = 10,
    workshop = 25,
    hunt = 30
  },
  level_presets = {
    kutnohorsko = {
      { trade = "workshop", dx = 35.0,  dy = -60.0, label = "Ремесленная слобода" },
      { trade = "woods",    dx = -220.0, dy = 100.0, label = "Сухдольский лес" },
      { trade = "fields",   dx = 180.0,  dy = 120.0, label = "Сухдольские поля" },
      { trade = "quarry",   dx = 140.0,  dy = -230.0, label = "Каменоломня у скал" },
      { trade = "hunt",     dx = -100.0, dy = 370.0, label = "Заповедная чаща" },
    },
    klaster = {
      { trade = "workshop", dx = 40.0,  dy = -38.0, label = "Монастырская слобода" },
      { trade = "woods",    dx = -130.0, dy = 160.0, label = "Заречный лес" },
      { trade = "fields",   dx = -180.0, dy = -140.0, label = "Подмонастырские поля" },
      { trade = "quarry",   dx = 120.0,  dy = 62.0,  label = "Монастырский карьер" },
      { trade = "hunt",     dx = 220.0,  dy = -240.0, label = "Лесные угодья" },
    },
    trosecko = {
      { trade = "workshop", dx = 36.0,  dy = -35.0, label = "Подзамочная кузня" },
      { trade = "woods",    dx = -190.0, dy = 135.0, label = "Тросецкий бор" },
      { trade = "fields",   dx = -90.0,  dy = -215.0, label = "Деревенские нивы" },
      { trade = "quarry",   dx = 156.0,  dy = -165.0, label = "Скальный развал" },
      { trade = "hunt",     dx = -340.0, dy = 185.0, label = "Угодья у скал" },
    }
  }
}

return FW.config
