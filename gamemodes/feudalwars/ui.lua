-- Feudal Wars ui: the menu, the dispatcher for every page, and the chat commands.

local FW = require("feudalwars.core")
local world = require("feudalwars.world")
local economy = require("feudalwars.economy")
local factions = require("feudalwars.factions")
local social = require("feudalwars.social")
local build = require("feudalwars.build")
local npc = require("feudalwars.npc")
local justice = require("feudalwars.justice")

-- ---------------------------------------------------------------- the menu

-- The menu's sections are the ones menu.js draws: main, world, work, house, trade, build.
local CARD = {
  me = { section = "main", title = "card_me_t", desc = "card_me_d", action = "me" },
  jobs = { section = "main", title = "card_jobs_t", desc = "card_jobs_d", action = "jobs" },
  work = { section = "work", title = "card_work_t", desc = "card_work_d", action = "work" },
  trade = { section = "trade", title = "card_trade_t", desc = "card_trade_d", action = "trade" },
  house = { section = "house", title = "card_house_t", desc = "card_house_d", action = "house" },
  build = { section = "build", title = "card_build_t", desc = "card_build_d", action = "build", admin = true },
  people = { section = "build", title = "card_npc_t", desc = "card_npc_d", action = "people", admin = true },
  admin = { section = "build", title = "card_admin_t", desc = "card_admin_d", action = "admin", admin = true },
  editor = { section = "build", title = "card_editor_t", desc = "card_editor_d", action = "editor", admin = true },
}

FW.MENU_ORDER = { "me", "jobs", "work", "trade", "house", "build", "people", "admin", "editor" }

function FW.menu_panel(pid)
  local lang = FW.lang_of(pid)
  local cards = {}
  for _, key in ipairs(FW.MENU_ORDER) do
    local c = CARD[key]
    if c and ((not c.admin) or IsPlayerAdmin(pid)) then
      cards[#cards + 1] = {
        id = key, section = c.section, action = c.action,
        title = FW.t(pid, c.title), desc = FW.t(pid, c.desc),
      }
    end
  end
  -- the world section: one card per work place, plus the square
  for _, zone in ipairs(world.zone_all()) do
    local def = FW.TRADE[zone.trade]
    if def then
      cards[#cards + 1] = {
        id = "place_" .. zone.id, section = "world", action = "place:" .. zone.id,
        title = (zone.label ~= "" and zone.label) or (def.label[lang] or def.label.en),
        desc = FW.t(pid, "card_town_d"),
      }
    end
  end
  cards[#cards + 1] = {
    id = "place_spawn", section = "world", action = "place:spawn",
    title = FW.t(pid, "card_town_t"), desc = FW.t(pid, "card_town_d"),
  }
  FW.open_frame(pid, "menu")
  FW.push(pid, "menu", {
    lang = lang, title = FW.t(pid, "menu_title"), sub = FW.t(pid, "menu_sub"),
    keys = FW.t(pid, "keys"), cards = cards,
    house = FW.state.player_house[pid], money = FW.purse(pid),
  })
end

function FW.menu_do(pid, action)
  action = tostring(action or "")
  if action == "menu" then FW.menu_panel(pid) return end
  if action == "me" then FW.close_frame(pid, "menu") FW.me_panel(pid) return end
  if action == "trade" or action == "auction" or action == "market" then
    FW.close_frame(pid, "menu")
    FW.market_open(pid)
    return
  end
  if action == "house" or action == "hall" then
    FW.close_frame(pid, "menu")
    FW.house_panel(pid)
    return
  end
  if action == "work" then FW.close_frame(pid, "menu") FW.work_report(pid) return end
  if action == "jobs" then FW.close_frame(pid, "menu") FW.work_report(pid) return end
  if action == "build" then FW.close_frame(pid, "menu") FW.build_panel(pid) return end
  if action == "people" then FW.close_frame(pid, "menu") FW.npc_admin_panel(pid) return end
  if action == "admin" then FW.close_frame(pid, "menu") FW.admin_panel(pid) return end
  if action == "editor" then FW.close_frame(pid, "menu") FW.editor(pid) return end
  if action == "town" then
    FW.close_frame(pid, "menu")
    local lang = FW.lang_of(pid)
    FW.say_raw(pid, FW.t(pid, "trade_none") .. table.concat((function()
      local out = {}
      for _, zone in ipairs(world.zone_all()) do
        local def = FW.TRADE[zone.trade]
        if def then out[#out + 1] = (zone.label ~= "" and zone.label) or (def.label[lang] or def.label.en) end
      end
      out[#out + 1] = "the square"
      return out
    end)(), ", "), COLOR_SERVER)
    return
  end
  if action:sub(1, 6) == "place:" then
    local where = action:sub(7)
    local ok = world.place(pid, where)
    if ok then FW.close_frame(pid, "menu") else FW.say(pid, "not_here") end
    return
  end
  FW.log("menu: unknown action %s", action)
end

-- ---------------------------------------------------------------- chat commands

local function cmd(name, fn, opts)
  local ok, err = RegisterCommand(name, fn, opts)
  if not ok then FW.log("command /%s refused: %s", name, tostring(err)) end
  return ok
end

FW.register_commands = function()
  cmd("menu", function(pid) FW.menu_panel(pid) end, { help = "the realm's menu (also F2)" })
  cmd("help", function(pid) FW.menu_panel(pid) end, { help = "the realm's menu" })

  cmd("lang", function(pid, args)
    local code = (args:match("^(%S*)") or ""):lower()
    if code == "" then
      FW.say_raw(pid, "language: " .. FW.lang_of(pid) .. " (/lang en|ru)", COLOR_SERVER)
      return
    end
    if FW.set_lang(pid, code) then
      FW.say(pid, "lang_set")
      FW.menu_panel(pid)
    else
      FW.say(pid, "usage_lang")
    end
  end, { help = "language: en or ru", params = "[en|ru]" })

  cmd("me", function(pid) FW.me_panel(pid) end, { help = "your character: purse, house, skills" })

  cmd("money", function(pid)
    FW.say_raw(pid, FW.fmt("%s: %s groschen", FW.t(pid, "purse"), FW.grosch(FW.purse(pid))), COLOR_SERVER)
  end, { help = "count your groschen" })

  cmd("kit", function(pid)
    local lang = FW.lang_of(pid)
    if lang == "ru" then
      FW.say_raw(pid, "Тебе не нужен особый инвентарь: любое оружие или инструмент в руках подходят! Встань у жилы/дерева/посевов и бей.", COLOR_YELLOW)
    else
      FW.say_raw(pid, "You need no special items: any weapon or tool in your hands works! Stand near a node/tree/crop and swing.", COLOR_YELLOW)
    end
  end, { help = "tool instructions" })

  cmd("pay", function(pid, args)
    local target, amount = sscanf(args, "ud")
    if target == false or target == nil or amount == false or amount == nil then
      FW.say(pid, "pay_usage")
      return
    end
    FW.pay(pid, target, amount)
  end, { help = "pay another player", params = "<player> <amount>" })

  cmd("job", function(pid, args)
    local verb = (args:match("^(%S*)") or ""):lower()
    if verb == "skills" then
      FW.work_skills(pid)
    elseif verb == "goto" then
      local where = (args:match("^%S*%s*(%S*)") or ""):lower()
      if where ~= "" then
        if not world.place(pid, where) then FW.say(pid, "not_here") end
      else
        FW.work_report(pid)
      end
    else
      FW.work_report(pid)
    end
  end, { help = "the trades: where the work is and what it pays", params = "[skills|goto <trade>]" })

  cmd("goto", function(pid, args)
    local where = (args:match("^(%S*)") or ""):lower()
    if where == "" then
      FW.say_raw(pid, "usage: /goto [spawn|quarry|woods|fields|hunt|workshop]", COLOR_SERVER)
      return
    end
    if not world.place(pid, where) then FW.say(pid, "not_here") end
  end, { help = "walk to the square or a work place", params = "[spawn|quarry|woods|fields|hunt|workshop]" })

  cmd("market", function(pid) FW.market_open(pid) end, { help = "the realm's market" })
  cmd("auction", function(pid) FW.market_open(pid) end, { help = "the realm's market" })
  cmd("trade", function(pid) FW.market_open(pid) end, { help = "the realm's market" })

  cmd("house", function(pid, args)
    local verb, rest = args:match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if verb == "create" then
      local name = rest:lower()
      if not name:match("^%a+$") or #name < 3 or #name > 16 then FW.say(pid, "house_bad_name") return end
      if FW.state.houses[name] then FW.say(pid, "house_exists") return end
      if FW.state.player_house[pid] then FW.say(pid, "house_serves") return end
      FW.house_new(name)
      FW.house_join(pid, name, 1)
      FW.persist_house(name)
      FW.say_all(FW.fmt(FW.t(pid, "house_founded"), GetPlayerName(pid), name))
    elseif verb == "join" then
      local name = rest:lower()
      if not FW.state.houses[name] then FW.say(pid, "not_here") return end
      if FW.state.player_house[pid] then FW.say(pid, "house_serves") return end
      FW.house_join(pid, name, 3)
      FW.say_all(FW.fmt(FW.t(pid, "house_joined"), GetPlayerName(pid), name))
    elseif verb == "leave" then
      local name = FW.house_leave(pid)
      if name then FW.say(pid, "house_left", name) else FW.say(pid, "house_not_serving") end
    elseif verb == "list" then
      local names = {}
      for name in pairs(FW.state.houses) do names[#names + 1] = name end
      table.sort(names)
      if #names == 0 then FW.say(pid, "house_none_yet")
      else FW.say_raw(pid, FW.t(pid, "house_list") .. table.concat(names, ", "), COLOR_SERVER) end
    elseif verb == "info" or verb == "" then
      local name = FW.state.player_house[pid]
      if not name then FW.say(pid, "house_not_serving") return end
      local h = FW.state.houses[name]
      FW.say_raw(pid, FW.fmt(FW.t(pid, "house_info"), name, FW.grosch(h.treasury),
        FW.house_members(h), h.prestige, h.war or FW.t(pid, "peace")), COLOR_SERVER)
    else
      FW.say_raw(pid, "usage: /house [create|join|leave|list|info]", COLOR_RED)
    end
  end, { help = "found, join or leave a house", params = "[create|join|leave|list|info]" })

  cmd("hall", function(pid) FW.house_panel(pid) end, { help = "your house hall: people, treasury, wars" })

  cmd("prestige", function(pid, args)
    local verb = (args:match("^(%S*)") or ""):lower()
    local name = FW.state.player_house[pid]
    if not name then FW.say(pid, "house_not_serving") return end
    if verb == "raise" then
      if not FW.house_prestige(pid) then
        FW.say_raw(pid, FW.fmt(FW.t(pid, "war_cost"), FW.grosch(FW.CONFIG.prestige_cost)), COLOR_RED)
      end
    else
      local h = FW.state.houses[name]
      FW.say_raw(pid, FW.fmt("%s: %s %d", name, FW.t(pid, "prestige"), h.prestige), COLOR_SERVER)
    end
  end, { help = "the house's standing", params = "[raise]" })

  cmd("war", function(pid, args)
    local verb, rest = args:match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if not FW.state.player_house[pid] then FW.say(pid, "house_not_serving") return end
    if verb == "declare" then
      local ok, why = FW.war_declare(pid, rest)
      if not ok then
        if why == "self" then FW.say(pid, "war_self")
        elseif why == "already" then FW.say(pid, "war_already")
        elseif why == "cost" then FW.say_raw(pid, FW.fmt(FW.t(pid, "war_cost"), FW.grosch(FW.CONFIG.declare_cost)), COLOR_RED)
        else FW.say(pid, "not_here") end
      end
    elseif verb == "peace" then
      if not FW.war_peace(pid) then FW.say(pid, "war_none") end
    elseif verb == "status" then
      local name = FW.state.player_house[pid]
      local h = FW.state.houses[name]
      if not h.war then FW.say(pid, "war_none") return end
      local enemy = FW.state.houses[h.war]
      FW.say_raw(pid, FW.fmt(FW.t(pid, "war_status"), name, h.war, h.score or 0,
        enemy and (enemy.score or 0) or 0), COLOR_SERVER)
    else
      FW.say_raw(pid, "usage: /war [declare <house>|peace|status]", COLOR_RED)
    end
  end, { help = "wars between houses", params = "[declare|peace|status]" })

  cmd("commands", function(pid, args)
    local admin = (args:match("^(%S*)") or ""):lower() == "admin"
    local lang = FW.lang_of(pid)
    if admin then
      if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
      local lines = {
        { "/npc add <role> <name>", "place a person", "поставить человека" },
        { "/npc list | remove <id>", "manage the people", "управлять людьми" },
        { "/zone here <trade> [label]", "mark a work place", "отметить место работы" },
        { "/zone list | remove <id>", "manage the places", "управлять местами" },
        { "/build", "the architect", "зодчий" },
        { "/arch new <key> | save <n> | stamp <n> | list | cancel", "blueprints", "чертежи" },
        { "/editor", "the map editor", "редактор карты" },
        { "/admin", "the crown's console", "совет короны" },
        { "/kick <player> [reason]", "kick", "кик" },
        { "/ban <player> [minutes] [reason]", "ban", "бан" },
        { "/give <player> <amount>", "grant groschen", "выдать гроши" },
        { "/tp <player> | /tphere <player>", "travel", "перемещение" },
        { "/reload-zones", "re-place the world", "перестроить мир" },
      }
      FW.say_raw(pid, lang == "ru" and "Команды короны:" or "The crown's commands:", COLOR_YELLOW)
      for _, l in ipairs(lines) do
        FW.say_raw(pid, "  " .. l[1] .. " - " .. (lang == "ru" and l[3] or l[2]), COLOR_SERVER)
      end
      return
    end
    local lines = {
      { "/menu (F2)", "the realm's menu", "меню королевства" },
      { "/me", "your character", "твой персонаж" },
      { "/job", "where the work is", "где работа" },
      { "/job skills", "your trades", "твои промыслы" },
      { "/goto <place>", "walk to a place", "перейти к месту" },
      { "/market", "buy and sell", "купить и продать" },
      { "/house create|join|leave|list|info", "houses", "дома" },
      { "/hall", "the house hall", "зал дома" },
      { "/war declare|peace|status", "wars", "войны" },
      { "/prestige raise", "the house's standing", "слава дома" },
      { "/money", "your purse", "кошелёк" },
      { "/pay <player> <amount>", "pay a player", "передать гроши" },
      { "/lang en|ru", "language", "язык" },
    }
    FW.say_raw(pid, lang == "ru" and "Команды игрока:" or "Player commands:", COLOR_YELLOW)
    for _, l in ipairs(lines) do
      FW.say_raw(pid, "  " .. l[1] .. " - " .. (lang == "ru" and l[3] or l[2]), COLOR_SERVER)
    end
    if IsPlayerAdmin(pid) then
      FW.say_raw(pid, lang == "ru" and "  (админ: /commands admin)" or "  (admins: /commands admin)", COLOR_SERVER)
    end
  end, { help = "list the commands", params = "[admin]" })

  -- ---------------------------------------------------------------- the crown

  cmd("admin", function(pid) FW.admin_panel(pid) end, { help = "the crown's console", admin = true })

  cmd("editor", function(pid) FW.editor(pid) end, { help = "the game's map editor", admin = true })

  cmd("build", function(pid) FW.build_panel(pid) end, { help = "the architect's blueprints", admin = true })

  cmd("arch", function(pid, args)
    local verb, rest = args:match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    if verb == "new" then FW.draft_new(pid, rest:match("^(%S*)") or "")
    elseif verb == "save" then FW.draft_save(pid, rest)
    elseif verb == "stamp" then FW.draft_stamp(pid, rest:match("^(%S*)") or "")
    elseif verb == "cancel" then FW.draft_clear(pid) FW.build_panel(pid)
    elseif verb == "list" then
      local names = {}
      for name, bp in pairs(FW.state.blueprints) do names[#names + 1] = name .. " (" .. #bp.parts .. ")" end
      table.sort(names)
      FW.say_raw(pid, "blueprints: " .. (#names > 0 and table.concat(names, ", ") or "none"), COLOR_YELLOW)
    else
      FW.say_raw(pid, "usage: /arch new <key> | save <name> | stamp <name> | list | cancel", COLOR_SERVER)
    end
  end, { help = "blueprint tools", params = "new|save|stamp|list|cancel", admin = true })

  cmd("npc", function(pid, args)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    local verb, rest = args:match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if verb == "add" then
      local role, name = rest:match("^(%S*)%s*(.-)$")
      local n, why = FW.person_create(pid, role, name)
      if n then
        FW.say_raw(pid, FW.fmt("placed %s '%s' (#%d)", FW.role_label(pid, n.role), n.name, n.id), COLOR_YELLOW)
      elseif why == "role" then
        FW.say_raw(pid, "roles: vendor, trainer, guard, quest, foreman, civilian", COLOR_RED)
      else
        FW.say_raw(pid, "give a name: /npc add <role> <name>", COLOR_RED)
      end
    elseif verb == "remove" or verb == "del" then
      local id = math.floor(tonumber(rest) or 0)
      if FW.person_remove(id) then
        FW.say_raw(pid, FW.fmt("person #%d removed", id), COLOR_SERVER)
      end
    else
      FW.npc_admin_panel(pid)
    end
  end, { help = "place and configure people", params = "add|list|remove", admin = true })

  cmd("zone", function(pid, args)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    local verb, rest = args:match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if verb == "here" then
      local trade, label = rest:match("^(%S*)%s*(.-)$")
      trade = (trade or ""):lower()
      if not FW.TRADE[trade] then
        FW.say_raw(pid, "trades: quarry, woods, fields, hunt, workshop", COLOR_RED)
        return
      end
      local px, py, pz = GetPlayerPos(pid)
      local zone = world.zone_add(trade, px, py, pz, label ~= "" and label or nil)
      FW.say_raw(pid, FW.fmt("work place '%s' (%s) marked here.", zone.id, trade), COLOR_YELLOW)
    elseif verb == "remove" then
      if world.zone_remove(rest:match("^(%S*)") or "") then
        FW.say_raw(pid, "work place removed.", COLOR_SERVER)
      end
    elseif verb == "reset" then
      world.zone_setup_default()
      FW.say_raw(pid, "All work places reset to out-of-castle natural locations.", COLOR_YELLOW)
    else
      for _, zone in ipairs(world.zone_all()) do
        local def = FW.TRADE[zone.trade]
        FW.say_raw(pid, FW.fmt("%s: %s at %d %d", zone.id,
          (def and (def.label[FW.lang_of(pid)] or def.label.en)) or tostring(zone.trade),
          math.floor(zone.x), math.floor(zone.y)), COLOR_SERVER)
      end
    end
  end, { help = "mark the work places", params = "here <trade>|list|remove <id>", admin = true })

  cmd("reload-zones", function(pid)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    for _, zone in ipairs(world.zone_all()) do world.zone_draw(zone) end
    FW.say_raw(pid, "the work places are re-drawn.", COLOR_YELLOW)
  end, { help = "re-place the world after an edit", admin = true })

  cmd("kick", function(pid, args)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    local target, reason = args:match("^(%S*)%s*(.-)$")
    local tid = GetPlayerId(target)
    if not tid then FW.say(pid, "no_player") return end
    FW.admin_log(pid, "kicked " .. tostring(target))
    Kick(tid, (reason ~= "" and reason) or "the crown wills it")
  end, { help = "remove a soul from the realm", params = "<player> [reason]", admin = true })

  cmd("ban", function(pid, args)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    local target, rest = args:match("^(%S*)%s*(.-)$")
    local tid = GetPlayerId(target)
    if not tid then FW.say(pid, "no_player") return end
    local minutes = tonumber(rest:match("^(%d*)"))
    local reason = rest:gsub("^%d+%s*", "")
    FW.admin_log(pid, "banned " .. tostring(target))
    Ban(tid, (reason ~= "" and reason) or "banned by the crown", (minutes or 0) * 60)
  end, { help = "ban a soul", params = "<player> [minutes] [reason]", admin = true })

  cmd("give", function(pid, args)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    local target, amount = sscanf(args, "ud")
    if target == false or target == nil or amount == false or amount == nil then
      FW.say_raw(pid, "usage: /give <player> <amount>", COLOR_RED)
      return
    end
    GivePlayerMoney(target, amount)
    FW.save_money(target)
    FW.set_purse_state(target)
    FW.admin_log(pid, FW.fmt("gave %d to %s", amount, GetPlayerName(target)))
    FW.say_raw(target, FW.fmt("The crown granted you %d groschen.", amount), COLOR_YELLOW)
  end, { help = "grant groschen", params = "<player> <amount>", admin = true })

  cmd("tp", function(pid, args)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    local tid = GetPlayerId(args:match("^(%S*)") or "")
    if not tid then FW.say(pid, "no_player") return end
    local x, y, z, yaw = GetPlayerPos(tid)
    SetPlayerPos(pid, x + 1.0, y, z, yaw)
  end, { help = "travel to a player", params = "<player>", admin = true })

  cmd("tphere", function(pid, args)
    if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
    local tid = GetPlayerId(args:match("^(%S*)") or "")
    if not tid then FW.say(pid, "no_player") return end
    local x, y, z, yaw = GetPlayerPos(pid)
    SetPlayerPos(tid, x + 1.0, y, z, yaw)
  end, { help = "bring a player here", params = "<player>", admin = true })

  FW.bindings()
end

FW.bindings = function()
  local ok, err = RegisterKeyBinding("fw.menu", "Feudal Wars: the menu", "f2")
  if not ok then FW.log("binding fw.menu refused: %s", tostring(err)) end
  local ok2, err2 = RegisterKeyBinding("fw.work", "Feudal Wars: where is the work", "h")
  if not ok2 then FW.log("binding fw.work refused: %s", tostring(err2)) end
end

-- ---------------------------------------------------------------- the web pages

function FW.web_event(pid, name, data)
  data = data or {}
  local function admin_only()
    if not IsPlayerAdmin(pid) then return false end
    return true
  end

  if name == "menu.ready" or name == "menu.open" then
    FW.menu_panel(pid)
  elseif name == "menu.cursor" then
    SetPlayerCursor(pid, true)
    SetPlayerWebFocus(pid, "menu", true, true)
  elseif name == "menu.close" then FW.close_frame(pid, "menu")
  elseif name == "menu.lang" then
    if FW.set_lang(pid, data.lang) then
      FW.say(pid, "lang_set")
      FW.menu_panel(pid)
    end
  elseif name == "menu.run" then FW.menu_do(pid, data.action or data.cmd or "")

  elseif name == "me.close" then FW.close_frame(pid, "me")

  elseif name == "house.close" then FW.close_frame(pid, "hall")
  elseif name == "house.donate" then
    local amount = math.floor(tonumber(data.amount) or 0)
    if FW.house_donate(pid, amount) then
      FW.say(pid, "house_donated", FW.grosch(amount))
    else
      FW.say(pid, "no_money")
    end
    FW.house_panel(pid)
  elseif name == "house.prestige" then
    if not FW.house_prestige(pid) then
      FW.say_raw(pid, FW.fmt(FW.t(pid, "war_cost"), FW.grosch(FW.CONFIG.prestige_cost)), COLOR_RED)
    end
    FW.house_panel(pid)
  elseif name == "house.declare" then
    local ok, why = FW.war_declare(pid, data.enemy)
    if not ok and why == "cost" then
      FW.say_raw(pid, FW.fmt(FW.t(pid, "war_cost"), FW.grosch(FW.CONFIG.declare_cost)), COLOR_RED)
    end
    FW.house_panel(pid)
  elseif name == "house.peace" then
    FW.war_peace(pid)
    FW.house_panel(pid)

  elseif name == "auction.close" then FW.close_frame(pid, "auction")
  elseif name == "auction.sell" then FW.market_sell(pid, data.item or data.res, data.amount, data.price)
  elseif name == "auction.buy" then FW.market_buy(pid, math.floor(tonumber(data.id) or 0))
  elseif name == "auction.cancel" then FW.market_cancel(pid, math.floor(tonumber(data.id) or 0))
  elseif name == "market.refresh" then FW.market_open(pid)

  elseif name == "build.close" then FW.close_frame(pid, "build")
  elseif name == "build.new" then
    if admin_only() then FW.draft_new(pid, data.name) end
  elseif name == "build.save" then
    if admin_only() then FW.draft_save(pid, data.name) end
  elseif name == "build.stamp" then
    if admin_only() then FW.draft_stamp(pid, data.name) end
  elseif name == "build.cancel" then
    if admin_only() then FW.draft_clear(pid) FW.build_panel(pid) end

  elseif name == "npc.close" then FW.close_frame(pid, "npc")
  elseif name == "npc.action" then
    local n = FW.state.people_list[math.floor(tonumber(data.npc) or 0)]
    local act = tostring(data.id or "")
    if n then
      if act == "trade" and n.shop then
        FW.close_frame(pid, "npc")
        pcall(OpenShop, pid, n.shop, n.actor)
      elseif act == "train" then
        FW.say_raw(pid, FW.fmt("%s will teach you for coin.", n.name), COLOR_YELLOW)
      elseif act == "report" then
        FW.say(pid, "crime_reported")
        FW.admin_log(pid, "reported a crime to " .. n.name)
      elseif act == "task" then
        FW.work_report(pid)
      elseif act == "hire" then
        FW.work_report(pid)
      else
        FW.talk(pid, n)
      end
    end
  elseif name == "npc.remove" then
    if admin_only() then
      FW.person_remove(math.floor(tonumber(data.id) or 0))
      FW.npc_admin_panel(pid)
    end
  elseif name == "npc.stock" then
    if admin_only() then FW.npc_stock_set(pid, math.floor(tonumber(data.id) or 0), data.item, data.price) end
  elseif name == "npc.place" then
    if admin_only() then
      local role = tostring(data.role or ""):lower()
      local nm = tostring(data.name or "")
      local n = FW.person_create(pid, role, nm)
      if n then FW.npc_admin_panel(pid) else FW.say_raw(pid, "role or name is wrong", COLOR_RED) end
    end

  elseif name == "admin.close" then FW.close_frame(pid, "admin")
  elseif name == "admin.kick" then
    if admin_only() then
      local tid = tonumber(data.id)
      if tid then
        FW.admin_log(pid, "kicked " .. tostring(GetPlayerName(tid)))
        Kick(tid, data.reason or "the crown wills it")
      end
      FW.admin_panel(pid)
    end
  elseif name == "admin.ban" then
    if admin_only() then
      local tid = tonumber(data.id)
      if tid then
        FW.admin_log(pid, "banned " .. tostring(GetPlayerName(tid)))
        Ban(tid, data.reason or "banned by the crown", (tonumber(data.minutes) or 0) * 60)
      end
      FW.admin_panel(pid)
    end
  elseif name == "admin.heal" then
    if admin_only() then
      local tid = tonumber(data.id)
      if tid then
        SetPlayerHealth(tid, GetPlayerMaxHealth(tid))
        FW.notice(tid, "The crown's physician tended your wounds.")
      end
      FW.admin_panel(pid)
    end
  elseif name == "admin.money" then
    if admin_only() then
      local tid = tonumber(data.id)
      local amount = math.floor(tonumber(data.amount) or 0)
      if tid and amount ~= 0 then
        GivePlayerMoney(tid, amount)
        FW.save_money(tid)
        FW.set_purse_state(tid)
        FW.admin_log(pid, FW.fmt("gave %d to %s", amount, GetPlayerName(tid)))
      end
      FW.admin_panel(pid)
    end
  elseif name == "admin.tp" then
    if admin_only() then
      local tid = tonumber(data.id)
      if tid then
        local x, y, z, yaw = GetPlayerPos(tid)
        SetPlayerPos(pid, x + 1.0, y, z, yaw)
      end
    end
  elseif name == "admin.tphere" then
    if admin_only() then
      local tid = tonumber(data.id)
      if tid then
        local x, y, z, yaw = GetPlayerPos(pid)
        SetPlayerPos(tid, x + 1.0, y, z, yaw)
      end
      FW.admin_panel(pid)
    end
  else
    FW.log("unhandled page event %s from %s", tostring(name), tostring(pid))
  end
end

return FW