-- Feudal Wars core: the shared namespace, config, language, database, money, frames, probes.
-- Every other module takes this table and hangs its own functions on it.

local FW = {}
_G.FW = FW

FW.VERSION = "4"

FW.CONFIG = {
  start_money = 500,
  earn_tax = 0.10,
  trade_tax = 0.05,
  upkeep_per_member = 50,
  prestige_cost = 10000,
  declare_cost = 5000,
  war_seconds = 86400,
  war_kill_score = 10,
  war_trophy = 10000,
  node_respawn = 300,
  work_cooldown_ms = 700,
  work_radius = 4.0,
}

FW.RANKS = { "lord", "steward", "retainer" }

FW.ADMINS = { "minsk" }

FW.state = {
  houses = {},
  player_house = {},
  player_rank = {},
  accounts = {},
  lang = {},
  skills = {},
  work_cd = {},
  notices = {},
  drafts = {},
  blueprints = {},
  sites = {},
  stations = {},
  people = {},
  people_list = {},
  person_next = 1,
  lots = {},
  lot_next = 1,
  animals = {},
  dialog_next = 1,
  pending = {},
  admin_log = {},
  dialogues = {},
}

-- ---------------------------------------------------------------- numbers and text

FW.fmt = string.format

function FW.log(text, ...)
  if select("#", ...) > 0 then text = FW.fmt(text, ...) end
  Log("[feudalwars] " .. tostring(text))
end

function FW.grosch(n)
  return FW.fmt("%d", math.floor(tonumber(n) or 0))
end

function FW.dist(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

function FW.dist3(ax, ay, az, bx, by, bz)
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function FW.round(v, step)
  step = step or 1
  return math.floor((tonumber(v) or 0) / step + 0.5) * step
end

-- ---------------------------------------------------------------- language

FW.LANGUAGE = {
  en = {
    lang_set = "Language: English.",
    usage_lang = "usage: /lang [en|ru]",
    no_house = "You serve no lord yet.",
    no_money = "Not enough groschen.",
    no_player = "No such player.",
    admins_only = "The crown's servants only.",
    not_here = "There is nothing like that here.",
    unknown = "I do not know that.",
    saved = "Saved.",
    done = "Done.",
    keys = "F2 - the menu",
    purse = "Purse",
    house = "House",
    rank = "Rank",
    treasury = "Treasury",
    prestige = "Prestige",
    members = "Members",
    war = "War",
    peace = "no war",
    online = "online",
    offline = "away",
    close = "Close",
    back = "Back",
    menu_title = "Feudal Wars",
    menu_sub = "Work, houses, trade and the crown",
    col_work = "Labour",
    col_town = "The town",
    col_house = "Your house",
    col_crown = "The crown",
    card_work_t = "Earn your bread",
    card_work_d = "Fell trees, quarry stone, gather herbs, hunt, work the anvil",
    card_jobs_t = "The world's trades",
    card_jobs_d = "Where the work is and what it pays now",
    card_trade_t = "The market",
    card_trade_d = "Goods of the realm, bought and sold",
    card_house_t = "House hall",
    card_house_d = "Your people, the treasury, the wars",
    card_me_t = "Your character",
    card_me_d = "Purse, standing, skills",
    card_town_t = "Go somewhere",
    card_town_d = "The square, the woods, the quarry, the fields",
    card_build_t = "The architect",
    card_build_d = "Raise a blueprint on the land (admins)",
    card_npc_t = "The realm's people",
    card_npc_d = "Place and dress the NPCs (admins)",
    card_admin_t = "The crown's console",
    card_admin_d = "The living, the logs, the powers (admins)",
    card_editor_t = "Map editor",
    card_editor_d = "The game's own editor (admins)",
    work_none = "No work of that trade here - look at the map for the marked places.",
    work_near = "%s: %d m away, pays about %d groschen a strike.",
    work_hint = "Stand %s and swing at the %s: the strike itself is the work.",
    work_up = "Your %s rose to %d.",
    work_paid = "+%s groschen (%s).",
    work_streak = "%d in a row - the foreman notices you.",
    trade_none = "The trades here: ",
    skill_list = "You: mining %d, survival %d, craftsmanship %d, houndmaster %d.",
    kit_tool = "Your own %s must be in your hands - no one lends tools here.",
    kit_ok = "You already hold %s.",
    house_founded = "%s founded the house of %s.",
    house_joined = "%s joined the house of %s.",
    house_left = "You left the house of %s.",
    house_exists = "A house of that name stands already.",
    house_bad_name = "A house name is 3 to 16 letters: /house create <name>",
    house_list = "Houses of the realm: ",
    house_none_yet = "No houses yet - /house create <name>",
    house_serves = "You already serve a lord.",
    house_not_serving = "You serve no lord.",
    house_info = "%s: treasury %s, %d member(s), prestige %d, %s",
    house_donated = "You gave %s groschen to the treasury.",
    house_prestige_up = "The house of %s raised its prestige to %d.",
    house_upkeep_dry = "The treasury of %s ran dry - no upkeep was paid.",
    war_declared = "The house of %s declared war on %s!",
    war_self = "A house cannot war upon itself.",
    war_already = "Your house is at war already.",
    war_cost = "A war needs %s groschen in the treasury.",
    war_peace = "The war between %s and %s is over.",
    war_none = "Your house is not at war.",
    war_status = "%s against %s: %d to %d",
    war_fell = "%s of %s fell to %s of %s.",
    war_won = "The house of %s won the war and took %s groschen.",
    pay_usage = "usage: /pay <player> <amount>",
    pay_done = "You paid %s groschen to %s.",
    pay_got = "%s paid you %s groschen.",
    trade_lot_added = "Lot #%d: %d for %s groschen.",
    trade_lot_bought = "Lot #%d is yours.",
    trade_lot_gone = "That lot is gone.",
    trade_hold = "You do not hold that many.",
    trade_mine = "That lot is your own.",
    not_ready = "The realm's goods are not loaded yet: the server has no item tables. Labour, coin and coin-bought goods still work.",
    crime_reported = "The guard takes your word and writes it down.",
    archive = "The crown's archive has that.",
  },
  ru = {
    lang_set = "Язык: русский.",
    usage_lang = "как: /lang [en|ru]",
    no_house = "Ты пока никому не служишь.",
    no_money = "Не хватает грошей.",
    no_player = "Нет такого человека.",
    admins_only = "Только слугам короны.",
    not_here = "Здесь такого нет.",
    unknown = "Не разумею такого.",
    saved = "Сохранено.",
    done = "Готово.",
    keys = "F2 — меню",
    purse = "Кошель",
    house = "Дом",
    rank = "Сан",
    treasury = "Казна",
    prestige = "Слава",
    members = "Люди",
    war = "Война",
    peace = "мира нет",
    online = "на месте",
    offline = "в отлучке",
    close = "Закрыть",
    back = "Назад",
    menu_title = "Феодальные войны",
    menu_sub = "Труд, дома, торг и корона",
    col_work = "Промыслы",
    col_town = "Город",
    col_house = "Твой дом",
    col_crown = "Корона",
    card_work_t = "Добыть хлеб",
    card_work_d = "Руби лес, бей камень, собирай травы, охоться, работай у наковальни",
    card_jobs_t = "Промыслы мира",
    card_jobs_d = "Где какая работа и сколько даёт",
    card_trade_t = "Торг",
    card_trade_d = "Товары королевства: купить и продать",
    card_house_t = "Зал дома",
    card_house_d = "Твои люди, казна и войны",
    card_me_t = "Твой персонаж",
    card_me_d = "Кошель, положение, навыки",
    card_town_t = "Перейти к месту",
    card_town_d = "Площадь, лес, каменоломня, поля",
    card_build_t = "Зодчий",
    card_build_d = "Поставить чертёж на землю (админы)",
    card_npc_t = "Люди королевства",
    card_npc_d = "Поставить и одеть NPC (админы)",
    card_admin_t = "Совет короны",
    card_admin_d = "Живые, списки, полномочия (админы)",
    card_editor_t = "Редактор карты",
    card_editor_d = "Встроенный редактор игры (админы)",
    work_none = "Здесь нет такого промысла — ищи отмеченные места на карте.",
    work_near = "%s: %d м, даёт около %d грошей за удар.",
    work_hint = "Встань у %s и бей %s — сам удар и есть работа.",
    work_up = "Твой навык %s вырос до %d.",
    work_paid = "+%s грошей (%s).",
    work_streak = "%d подряд — бригадир тебя приметил.",
    trade_none = "Промыслы здесь: ",
    skill_list = "Ты: горное %d, выживание %d, ремесло %d, псарня %d.",
    kit_tool = "Свой %s должен быть в руках — здесь инструментов не выдают.",
    kit_ok = "У тебя уже есть %s.",
    house_founded = "%s основал дом %s.",
    house_joined = "%s вступил в дом %s.",
    house_left = "Ты покинул дом %s.",
    house_exists = "Дом с таким именем уже стоит.",
    house_bad_name = "Имя дома — 3–16 букв: /house create <имя>",
    house_list = "Дома королевства: ",
    house_none_yet = "Домов ещё нет — /house create <имя>",
    house_serves = "Ты уже служишь лорду.",
    house_not_serving = "Ты никому не служишь.",
    house_info = "%s: казна %s, людей %d, слава %d, %s",
    house_donated = "Ты отдал в казну %s грошей.",
    house_prestige_up = "Дом %s возвысил славу до %d.",
    house_upkeep_dry = "Казна дома %s опустела — содержание не уплачено.",
    war_declared = "Дом %s объявил войну дому %s!",
    war_self = "Дом не может воевать сам с собой.",
    war_already = "Твой дом уже на войне.",
    war_cost = "Для войны нужно %s грошей в казне.",
    war_peace = "Война между %s и %s окончена.",
    war_none = "Твой дом не воюет.",
    war_status = "%s против %s: %d на %d",
    war_fell = "%s из дома %s пал от руки %s из дома %s.",
    war_won = "Дом %s победил в войне и взял %s грошей.",
    pay_usage = "как: /pay <игрок> <сумма>",
    pay_done = "Ты передал %s грошей игроку %s.",
    pay_got = "%s передал тебе %s грошей.",
    trade_lot_added = "Лот #%d: %d за %s грошей.",
    trade_lot_bought = "Лот #%d — твой.",
    trade_lot_gone = "Этого лота уже нет.",
    trade_hold = "У тебя столько нет.",
    trade_mine = "Это твой собственный лот.",
    not_ready = "Товары королевства ещё не загружены: на сервере нет таблиц предметов. Труд, монета и покупки за монету работают.",
    crime_reported = "Стражник записывает твои слова.",
    archive = "В архиве короны это есть.",
  },
}

function FW.lang_of(pid)
  return FW.state.lang[pid] or "en"
end

function FW.ready()
  return FW.items_ready == true
end

function FW.t(pid, key, ...)
  local lang = FW.lang_of(pid)
  local pack = FW.LANGUAGE[lang] or FW.LANGUAGE.en
  local text = pack[key] or FW.LANGUAGE.en[key] or key
  if select("#", ...) > 0 then text = FW.fmt(text, ...) end
  return text
end

function FW.set_lang(pid, code)
  code = tostring(code or ""):lower()
  if not FW.LANGUAGE[code] then return false end
  FW.state.lang[pid] = code
  FW.persist_lang(pid)
  return true
end

-- ---------------------------------------------------------------- messages

function FW.say(pid, key, ...)
  local text = FW.t(pid, key, ...)
  SendClientMessage(pid, COLOR_SERVER, text)
end

function FW.say_raw(pid, text, color)
  SendClientMessage(pid, color or COLOR_SERVER, text)
end

function FW.say_all(text, color)
  SendClientMessageToAll(color or COLOR_YELLOW, text)
end

function FW.near(x, y, z, radius, text, color)
  pcall(SendClientMessageInRange, x, y, z, radius or 25, color or COLOR_WHITE, text, nil)
end

function FW.notice(pid, text)
  pcall(ShowPlayerWebFrame, pid, "notice")
  pcall(SendPlayerWebMessage, pid, "notice", { text = text })
end

function FW.notice_all(text)
  for _, pid in ipairs(GetPlayers() or {}) do FW.notice(pid, text) end
end

-- ---------------------------------------------------------------- frames

function FW.open_frame(pid, frame)
  local ok, err = ShowPlayerWebFrame(pid, frame)
  if ok then
    SetPlayerWebFocus(pid, frame, true, true)
    SetPlayerCursor(pid, true)
  else
    FW.log("frame %s refused for %s: %s", frame, tostring(pid), tostring(err))
  end
  return ok
end

function FW.close_frame(pid, frame)
  pcall(DestroyPlayerWebFrame, pid, frame)
  pcall(SetPlayerWebFocus, pid, frame, false, false)
  pcall(SetPlayerCursor, pid, false)
end

function FW.push(pid, frame, data)
  pcall(SendPlayerWebMessage, pid, frame, data)
end

-- ---------------------------------------------------------------- world probes

FW.has_navmesh = false
FW.has_collision = false
FW.has_heightmap = false
FW.spawn = { x = 1280, y = 1088, z = 0, yaw = 0 }

function FW.ground(x, y, hint)
  if FW.has_collision then
    local ok, hit = pcall(GetGroundZ, x, y, 900.0)
    if ok and type(hit) == "number" then return hit end
  end
  if FW.has_navmesh then
    local ok, hit = pcall(GetNavmeshHeight, x, y, hint or FW.spawn.z)
    if ok and type(hit) == "number" then return hit end
  end
  if FW.has_heightmap then
    local ok, hit = pcall(GetTerrainHeight, x, y)
    if ok and type(hit) == "number" then return hit end
  end
  return hint or FW.spawn.z
end

function FW.probe_world()
  local sx, sy, sz, syaw = GetDefaultSpawn()
  FW.spawn = { x = sx, y = sy, z = sz, yaw = syaw or 0 }
  FW.has_navmesh = HasNavmesh() and true or false
  FW.has_collision = HasCollision() and true or false
  FW.has_heightmap = (GetTerrainHeight(sx, sy) ~= nil)
  local seen = GetItemInfo and GetItemInfo("torch")
  FW.items_ready = seen ~= nil
  FW.log("world: spawn %.1f %.1f %.1f, navmesh=%s collision=%s heightmap=%s items=%s",
    sx, sy, sz, tostring(FW.has_navmesh), tostring(FW.has_collision), tostring(FW.has_heightmap),
    tostring(FW.items_ready))
  if not FW.has_heightmap and not FW.has_navmesh and not FW.has_collision then
    FW.log("no level data: objects only ground-snap near the spawn; work runs on real game objects instead")
  end
end

-- ---------------------------------------------------------------- database

FW.db = nil

function FW.db_init()
  FW.db = GetDatabase()
  if not FW.db then
    FW.log("no database: everything lives in memory for this session only")
    return false
  end
  local schema = {
    "CREATE TABLE IF NOT EXISTS fw_players (name VARCHAR(32) PRIMARY KEY, money INT NOT NULL DEFAULT 0, lang VARCHAR(4) NOT NULL DEFAULT 'en', house VARCHAR(32) NULL, rank TINYINT NOT NULL DEFAULT 3, last_seen BIGINT NOT NULL DEFAULT 0)",
    "CREATE TABLE IF NOT EXISTS fw_houses (name VARCHAR(32) PRIMARY KEY, treasury INT NOT NULL DEFAULT 0, prestige INT NOT NULL DEFAULT 1)",
    "CREATE TABLE IF NOT EXISTS fw_members (house VARCHAR(32) NOT NULL, name VARCHAR(32) NOT NULL, rank TINYINT NOT NULL DEFAULT 3, PRIMARY KEY (house, name))",
    "CREATE TABLE IF NOT EXISTS fw_sites (id VARCHAR(48) PRIMARY KEY, trade VARCHAR(16) NOT NULL DEFAULT 'forest', x DOUBLE NOT NULL DEFAULT 0, y DOUBLE NOT NULL DEFAULT 0, z DOUBLE NOT NULL DEFAULT 0, label VARCHAR(64) NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS fw_people (id INT PRIMARY KEY, role VARCHAR(16) NOT NULL DEFAULT 'civilian', name VARCHAR(64) NOT NULL DEFAULT '', x DOUBLE NOT NULL DEFAULT 0, y DOUBLE NOT NULL DEFAULT 0, z DOUBLE NOT NULL DEFAULT 0, yaw DOUBLE NOT NULL DEFAULT 0, prompt VARCHAR(64) NOT NULL DEFAULT '', data MEDIUMTEXT)",
    "CREATE TABLE IF NOT EXISTS fw_blueprints (name VARCHAR(48) PRIMARY KEY, parts MEDIUMTEXT, author VARCHAR(32))",
    "CREATE TABLE IF NOT EXISTS fw_lots (id INT PRIMARY KEY, seller VARCHAR(32), item VARCHAR(64), amount INT NOT NULL DEFAULT 1, price INT NOT NULL DEFAULT 1)",
    "CREATE TABLE IF NOT EXISTS fw_skills (name VARCHAR(32), skill VARCHAR(24), level INT NOT NULL DEFAULT 0, PRIMARY KEY (name, skill))",
  }
  for _, sql in ipairs(schema) do
    local ok, err = FW.db:ExecuteSync(sql)
    if not ok then FW.log("schema failed: %s", tostring(err)) end
  end
  return true
end

function FW.q(sql, params, cb)
  if not FW.db then return end
  local ok, err = pcall(function() FW.db:Query(sql, params or {}, cb or function() end) end)
  if not ok then FW.log("query failed: %s", tostring(err)) end
end

function FW.qs(sql, params)
  if not FW.db then return nil end
  local ok, rows, err = pcall(function() return FW.db:QuerySync(sql, params or {}) end)
  if not ok then FW.log("query failed: %s", tostring(rows)) return nil end
  return rows
end

function FW.x(sql, params)
  if not FW.db then return end
  pcall(function() FW.db:Execute(sql, params or {}, function() end) end)
end

function FW.xs(sql, params)
  if not FW.db then return nil end
  local ok, res, err = pcall(function() return FW.db:ExecuteSync(sql, params or {}) end)
  if not ok then FW.log("execute failed: %s", tostring(res)) end
  return res
end

-- ---------------------------------------------------------------- money

function FW.purse(pid)
  return math.floor(GetPlayerMoney(pid) or 0)
end

function FW.save_money(pid)
  local acc = FW.state.accounts[pid]
  if not FW.db or not acc then return end
  acc.money = FW.purse(pid)
  FW.x("UPDATE fw_players SET money = @m, last_seen = @t WHERE name = @n",
    { m = acc.money, t = GetServerTime(), n = acc.name })
end

function FW.earn(pid, amount, why)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return 0 end
  GivePlayerMoney(pid, amount)
  local tax = math.floor(amount * FW.CONFIG.earn_tax)
  local house = FW.state.player_house[pid]
  if house and FW.state.houses[house] and tax > 0 then
    FW.state.houses[house].treasury = FW.state.houses[house].treasury + tax
    FW.persist_house(house)
  else
    tax = 0
  end
  -- earnings are gathered and told in one line, not on every swing
  local p = FW.state.pending[pid]
  if not p then p = { amount = 0, why = why or "" } FW.state.pending[pid] = p end
  p.amount = p.amount + (amount - tax)
  p.why = why or p.why
  FW.set_purse_state(pid)
  return amount - tax
end

function FW.flush_earnings(pid)
  local p = FW.state.pending[pid]
  if not p or p.amount <= 0 then return end
  FW.say(pid, "work_paid", FW.grosch(p.amount), p.why or "")
  p.amount = 0
end

function FW.flush_all_earnings()
  for pid in pairs(FW.state.pending) do FW.flush_earnings(pid) end
end

function FW.set_purse_state(pid)
  pcall(SetPlayerState, pid, "purse", tostring(FW.purse(pid)))
end

-- ---------------------------------------------------------------- skills

FW.SKILL_LABEL = {
  mining = { en = "mining", ru = "горное дело" },
  survival = { en = "survival", ru = "выживание" },
  craftsmanship = { en = "craftsmanship", ru = "ремесло" },
  cooking = { en = "cooking", ru = "поварня" },
  weaponsmithing = { en = "weaponsmithing", ru = "оружейное дело" },
  armourer = { en = "armourer", ru = "бронное дело" },
  gunsmithing = { en = "gunsmithing", ru = "ружейное дело" },
  bowyery = { en = "bowyery", ru = "лучное дело" },
  tailoring = { en = "tailoring", ru = "портняжное дело" },
  shoemaking = { en = "shoemaking", ru = "сапожное дело" },
  houndmaster = { en = "houndmaster", ru = "псарня" },
  marksmanship = { en = "marksmanship", ru = "стрельба" },
  horse_riding = { en = "riding", ru = "верховая езда" },
  scholarship = { en = "scholarship", ru = "учёность" },
  thievery = { en = "thievery", ru = "воровство" },
  stealth = { en = "stealth", ru = "скрытность" },
}

function FW.skill_label(pid, skill)
  local l = FW.SKILL_LABEL[skill]
  if not l then return skill end
  return l[FW.lang_of(pid)] or l.en
end

function FW.skill_of(pid, skill)
  local s = FW.state.skills[pid]
  return (s and s[skill]) or 0
end

function FW.skill_xp(pid, skill, xp)
  if not skill or not xp or xp <= 0 then return false end
  local ok, res = pcall(AddPlayerSkillXP, pid, skill, math.min(xp, 100000))
  return ok and res and true or false
end

function FW.skill_tick(pid, skill)
  FW.state.skills[pid] = FW.state.skills[pid] or {}
  local s = FW.state.skills[pid]
  local before = s[skill] or 0
  s[skill] = before + 1
  -- the level is written every tenth tick, not on every swing
  if s[skill] % 10 == 0 then
    local acc = FW.state.accounts[pid]
    if FW.db and acc then
      FW.x("INSERT INTO fw_skills (name, skill, level) VALUES (@n, @s, @l) " ..
        "ON DUPLICATE KEY UPDATE level = @l2",
        { n = acc.name, s = skill, l = s[skill], l2 = s[skill] })
    end
    FW.say(pid, "work_up", FW.skill_label(pid, skill), s[skill])
  end
  return s[skill]
end

-- ---------------------------------------------------------------- accounts persistence

function FW.persist_lang(pid)
  local acc = FW.state.accounts[pid]
  if not FW.db or not acc then return end
  FW.x("UPDATE fw_players SET lang = @l WHERE name = @n", { l = FW.lang_of(pid), n = acc.name })
end

function FW.persist_house(name)
  if not FW.db then return end
  local h = FW.state.houses[name]
  if not h then return end
  FW.x("INSERT INTO fw_houses (name, treasury, prestige) VALUES (@n, @t, @p) " ..
    "ON DUPLICATE KEY UPDATE treasury = @t2, prestige = @p2",
    { n = name, t = h.treasury, p = h.prestige, t2 = h.treasury, p2 = h.prestige })
end

function FW.admin_log(pid, text)
  local line = os.date("%H:%M ") .. (pid and (GetPlayerName(pid) .. " ") or "") .. text
  local log = FW.state.admin_log
  log[#log + 1] = line
  if #log > 60 then table.remove(log, 1) end
end

return FW