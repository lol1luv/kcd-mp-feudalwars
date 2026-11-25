-- ============================================================================
-- Feudal Wars v5 — User Interface & Command Handler
-- ============================================================================

local FW = require("feudalwars.core")

FW.ui = {}

function FW.ui.init()
  RegisterKeyBinding("fw.menu", "Feudal Wars Main Menu", "f2")
  FW.ui.register_commands()
  FW.log("key bindings and commands registered.")
end

function FW.ui.open_menu(pid)
  local pdata = FW.state.players[pid]
  if not pdata then return end

  ShowPlayerWebFrame(pid, "menu")
  SetPlayerWebFocus(pid, "menu", true, true)
  SetPlayerCursor(pid, true)

  local lang = pdata.lang
  SendPlayerWebMessage(pid, "menu", {
    lang = lang,
    title = lang == "ru" and "Феодальные войны" or "Feudal Wars",
    keys = "F2 — Меню · ESC — Закрыть",
    cards = {
      { id = "me", section = "main", title = lang == "ru" and "Мой персонаж" or "My character", desc = lang == "ru" and "Кошелек и статус" or "Purse and status", action = "me" },
      { id = "hall", section = "main", title = lang == "ru" and "Зал дома" or "House hall", desc = lang == "ru" and "Управление феодом" or "Manage realm", action = "hall" },
      { id = "job", section = "work", title = lang == "ru" and "Промыслы" or "Work & Trades", desc = lang == "ru" and "Информация о работе" or "Info on gathering", action = "job" },
    }
  })
end

function FW.ui.open_me(pid)
  local pdata = FW.state.players[pid]
  if not pdata then return end

  ShowPlayerWebFrame(pid, "me")
  SetPlayerWebFocus(pid, "me", true, true)
  SetPlayerCursor(pid, true)

  SendPlayerWebMessage(pid, "me", {
    lang = pdata.lang,
    name = pdata.name,
    money = pdata.purse,
    house = pdata.house_id ~= "" and pdata.house_id or FW.t(pid, "no_house"),
    rank = pdata.rank
  })
end

function FW.ui.open_hall(pid)
  local pdata = FW.state.players[pid]
  if not pdata then return end

  ShowPlayerWebFrame(pid, "hall")
  SetPlayerWebFocus(pid, "hall", true, true)
  SetPlayerCursor(pid, true)

  local h = FW.state.houses[pdata.house_id]
  SendPlayerWebMessage(pid, "hall", {
    lang = pdata.lang,
    house = h and h.name or FW.t(pid, "no_house"),
    treasury = h and h.treasury or 0,
    prestige = h and h.prestige or 0
  })
end

function FW.ui.register_commands()
  RegisterCommand("menu", function(pid)
    FW.ui.open_menu(pid)
  end, { help = "Open main menu (F2)" })

  RegisterCommand("me", function(pid)
    FW.ui.open_me(pid)
  end, { help = "Character information" })

  RegisterCommand("hall", function(pid)
    FW.ui.open_hall(pid)
  end, { help = "House hall and treasury" })

  RegisterCommand("purse", function(pid)
    local pdata = FW.state.players[pid]
    if pdata then
      local msg = FW.fmt("%s: %s %s", FW.t(pid, "purse"), FW.grosch(pdata.purse), FW.t(pid, "groschen"))
      if SendChatMessage then SendChatMessage(pid, msg) end
    end
  end, { help = "Check purse" })

  RegisterCommand("kit", function(pid)
    if SendChatMessage then SendChatMessage(pid, FW.t(pid, "kit_desc")) end
  end, { help = "Tool guide" })

  RegisterCommand("commands", function(pid)
    if SendChatMessage then
      SendChatMessage(pid, "=== Feudal Wars Commands ===")
      SendChatMessage(pid, "/menu — Open menu (F2)")
      SendChatMessage(pid, "/me — Open character parchment")
      SendChatMessage(pid, "/hall — House hall")
      SendChatMessage(pid, "/purse — Check groschen balance")
      SendChatMessage(pid, "/kit — Work and gathering guide")
    end
  end, { help = "List commands" })
end

return FW.ui
