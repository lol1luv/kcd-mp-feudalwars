-- ============================================================================
-- Feudal Wars v5 — Core Engine & Shared State
-- ============================================================================

local FW = {}
FW.VERSION = "5.0.0"

FW.state = {
  players = {},
  houses = {},
  sites = {},
  work_cd = {},
  npcs = {},
  auctions = {}
}

function FW.log(fmt, ...)
  print(string.format("[FeudalWars] " .. (fmt or ""), ...))
end

function FW.err(fmt, ...)
  print(string.format("[FeudalWars ERROR] " .. (fmt or ""), ...))
end

function FW.fmt(fmt, ...)
  return string.format(fmt or "", ...)
end

function FW.grosch(val)
  return string.format("%.2f", (val or 0) / 100)
end

local DICT = {
  ru = {
    purse = "Кошелек",
    groschen = "грошей",
    no_house = "Без дома",
    king = "Король",
    lord = "Лорд",
    knight = "Рыцарь",
    peasant = "Крестьянин",
    kit_desc = "Тебе не нужен особый инвентарь: любое оружие или инструмент в руках подходят! Встань у жилы/дерева/посевов и бей.",
  },
  en = {
    purse = "Purse",
    groschen = "groschen",
    no_house = "No house",
    king = "King",
    lord = "Lord",
    knight = "Knight",
    peasant = "Peasant",
    kit_desc = "You need no special items: any weapon or tool in your hands works! Stand near a node/tree/crop and swing.",
  }
}

function FW.t(pid_or_lang, key)
  local lang = type(pid_or_lang) == "string" and pid_or_lang or (FW.state.players[pid_or_lang] and FW.state.players[pid_or_lang].lang or "ru")
  local tbl = DICT[lang] or DICT.ru
  return tbl[key] or key
end

function FW.ground(x, y, fallback_z)
  if GetGroundZ then
    local gz = GetGroundZ(x, y)
    if gz and gz > -500 and gz < 2000 then return gz end
  end
  return fallback_z or 0
end

return FW
