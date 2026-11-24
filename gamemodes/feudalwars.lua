-- KCD:MP game mode: feudalwars (v3).
--
-- Feudal houses with ranks, wars with spoils, a treasury economy with real groschen,
-- persistent accounts, an in-world provisioner, a web interface (the character page,
-- the house hall, the admin console, notices) and admin commands.
--
-- Needs the game mode database ([gamemode.database] in server.toml) for persistence;
-- without one everything still works but is not saved across restarts.
-- Run with `KcdMp.Server --gamemode gamemodes/feudalwars.lua`.

SetGameModeText("feudalwars")

local WAR = {
  declare_cost = 5000,
  truce_cost = 1000,
  war_seconds = 86400,
  kill_score = 10,
  win_treasury = 10000,
}

local ECONOMY = {
  start_money = 500,
  farm_pay = 100,
  craft_pay = 150,
  trade_tax = 0.05,
  earn_tax = 0.10,
  upkeep_per_member = 50,
  prestige_cost = 10000,
}

-- ---------------------------------------------------------------- jobs (module 1: gathering)
-- Three work sites near the spawn: a mine, a farm field, a logging camp.
-- Each site has veins/nodes with stock that depletes and regrows; working a
-- node pays per unit and raises the matching skill, which speeds up the work
-- and raises the pay. Sites persist in the database (table jobs).

local JOBS = {
  mine = {
    label = "the mine", skill = "mining", unit = "ore",
    stock_max = 50, regrow_ms = 600000, work_ms = 8000,
    pay = 6, skill_pay_bonus = 1, skill_speed_bonus = 0.05,
  },
  farm = {
    label = "the field", skill = "farming", unit = "sheaf",
    stock_max = 60, regrow_ms = 300000, work_ms = 6000,
    pay = 5, skill_pay_bonus = 1, skill_speed_bonus = 0.05,
  },
  forest = {
    label = "the logging camp", skill = "woodcutting", unit = "log",
    stock_max = 40, regrow_ms = 450000, work_ms = 7000,
    pay = 5, skill_pay_bonus = 1, skill_speed_bonus = 0.05,
  },
}

local job_sites = {}    -- id -> { id, kind, x, y, z, stock }
local job_work = {}     -- pid -> { site_id, ready_at }
local job_skills = {}    -- pid -> { mining = n, farming = n, woodcutting = n }
local job_interactions = {} -- interaction id -> job kind
local build_preview = {}  -- pid -> { name, ids, timer }

local function job_skill_of(pid, skill)
  local s = job_skills[pid]
  return (s and s[skill]) or 0
end

local function job_skill_up(pid, skill)
  job_skills[pid] = job_skills[pid] or {}
  local s = job_skills[pid]
  s[skill] = (s[skill] or 0) + 1
  if db then
    db:Execute("INSERT INTO job_skills (player, skill, level) VALUES (@p, @s, @l) " ..
      "ON DUPLICATE KEY UPDATE level = @l2",
      { p = accounts[pid] and accounts[pid].name or ("pid" .. pid), s = skill, l = s[skill], l2 = s[skill] }, function() end)
  end
  return s[skill]
end

local function job_find_near(pid, kind)
  local px, py, pz = GetPlayerPos(pid)
  local best, bestd = nil, 6.0
  for _, site in pairs(job_sites) do
    if site.kind == kind then
      local dx, dy, dz = site.x - px, site.y - py, site.z - pz
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d < bestd then best, bestd = site, d end
    end
  end
  return best
end

local function job_work_start(pid, kind)
  if job_work[pid] then
    SendClientMessage(pid, COLOR_RED, "you are already working - wait for the shift to end.")
    return
  end
  local site = job_find_near(pid, kind)
  if not site then
    SendClientMessage(pid, COLOR_RED, fmt("no %s nearby - walk to %s.", JOBS[kind].label, JOBS[kind].label))
    return
  end
  if site.stock <= 0 then
    SendClientMessage(pid, COLOR_RED, fmt("%s is exhausted - it regrows with time.", JOBS[kind].label))
    return
  end
  local def = JOBS[kind]
  local skill = job_skill_of(pid, def.skill)
  local work_ms = math.floor(def.work_ms * math.max(0.4, 1 - skill * def.skill_speed_bonus))
  job_work[pid] = { site_id = site.id, ready_at = GetServerTime() + work_ms }
  SendClientMessage(pid, COLOR_SERVER, fmt("you started a shift at %s (%d %s left). Back in %d seconds: /job done.",
    def.label, site.stock, def.unit, math.floor(work_ms / 1000)))
  SetTimer(function()
    local w = job_work[pid]
    if w and w.site_id == site.id then
      SendClientMessage(pid, COLOR_YELLOW, fmt("your shift at %s is done: /job done to collect.", def.label))
    end
  end, work_ms, false)
end

local function job_work_collect(pid)
  local w = job_work[pid]
  if not w then
    SendClientMessage(pid, COLOR_RED, "no shift in progress - /job <mine|farm|forest> to start.")
    return
  end
  local site = job_sites[w.site_id]
  if not site then job_work[pid] = nil return end
  local def = JOBS[site.kind]
  if GetServerTime() < w.ready_at then
    local left = math.ceil((w.ready_at - GetServerTime()) / 1000)
    SendClientMessage(pid, COLOR_RED, fmt("the shift is not done yet - %d seconds left.", left))
    return
  end
  job_work[pid] = nil
  if site.stock <= 0 then
    SendClientMessage(pid, COLOR_RED, fmt("%s ran dry while you worked.", def.label))
    return
  end
  site.stock = site.stock - 1
  if db then
    db:Execute("UPDATE job_sites SET stock = @s WHERE id = @i", { s = site.stock, i = site.id }, function() end)
  end
  local skill = job_skill_of(pid, def.skill)
  local pay = def.pay + skill * def.skill_pay_bonus
  local total_units = skill + 1
  if total_units >= 10 and total_units % 10 == 0 then
    local nl = job_skill_up(pid, def.skill)
    SendClientMessage(pid, COLOR_YELLOW, fmt("%s skill raised to %d: faster shifts, +%d per unit.", def.skill, nl, def.skill_pay_bonus))
  else
    job_skill_up(pid, def.skill)
  end
  earn(pid, pay)
  save_money(pid)
  SendClientMessage(pid, COLOR_SERVER, fmt("+1 %s, +%d groschen (%s %d left).", def.unit, pay, def.label, site.stock))
end

local function job_status(pid)
  local lines = {}
  for kind, def in pairs(JOBS) do
    local site = job_find_near(pid, kind)
    local skill = job_skill_of(pid, def.skill)
    if site then
      lines[#lines + 1] = fmt("%s: %d %s left, your %s %d", def.label, site.stock, def.unit, def.skill, skill)
    else
      lines[#lines + 1] = fmt("%s: walk closer to see the stock (your %s %d)", def.label, def.skill, skill)
    end
  end
  if job_work[pid] then
    local w = job_work[pid]
    local site = job_sites[w.site_id]
    local left = math.max(0, math.ceil((w.ready_at - GetServerTime()) / 1000))
    lines[#lines + 1] = fmt("shift: %s, %d seconds left.", site and JOBS[site.kind].label or "?", left)
  end
  for _, l in ipairs(lines) do SendClientMessage(pid, COLOR_SERVER, l) end
end

local RANKS = { "lord", "steward", "retainer" }

local ADMIN_NAMES = { "minsk" }   -- promoted on connect; extend or move into the database

local db = GetDatabase()

local houses = {}         -- name -> { treasury, prestige, war, war_started, score, members = {lowerName = {rank}} }
local playerHouse = {}    -- pid -> house name
local playerRank = {}     -- pid -> rank index
local accounts = {}       -- pid -> { name, money, known }

local function fmt(...) return string.format(...) end

local function mylog(text)
  SendClientMessageToAll(COLOR_SERVER, text)
end

local function notice(pid, text)
  ShowPlayerWebFrame(pid, "notice")
  SendPlayerWebMessage(pid, "notice", { text = text })
end

local function broadcast_notice(text)
  for _, pid in ipairs(GetPlayers()) do notice(pid, text) end
end

-- ---------------------------------------------------------------- houses

local function house_new(name)
  houses[name] = { treasury = 0, prestige = 1, war = nil, war_started = 0, score = 0, members = {} }
  return houses[name]
end

local function house_member_count(h)
  local n = 0
  for _ in pairs(h.members) do n = n + 1 end
  return n
end

local function house_online_members(h)
  local list = {}
  for lname in pairs(h.members) do
    local pid = GetPlayerId(lname)
    if pid then list[#list + 1] = pid end
  end
  return list
end

local function house_at_war(a, b)
  local ha, hb = houses[a], houses[b]
  return (ha and ha.war == b) or (hb and hb.war == a)
end

local function house_rank_of(pid)
  return RANKS[playerRank[pid] or 3]
end

local function save_house(name)
  if not db then return end
  local h = houses[name]
  db:Execute("INSERT INTO houses (name, treasury, prestige) VALUES (@n, @t, @p) " ..
    "ON DUPLICATE KEY UPDATE treasury = @t2, prestige = @p2",
    { n = name, t = h.treasury, p = h.prestige, t2 = h.treasury, p2 = h.prestige }, function() end)
end

local function save_money(pid)
  if not db or not accounts[pid] or not accounts[pid].known then return end
  accounts[pid].money = GetPlayerMoney(pid)
  db:Execute("UPDATE players SET money = @m WHERE name = @n",
    { m = accounts[pid].money, n = accounts[pid].name }, function() end)
end

local function earn(pid, amount)
  GivePlayerMoney(pid, amount)
  local tax = math.floor(amount * ECONOMY.earn_tax)
  local name = playerHouse[pid]
  if name and houses[name] and tax > 0 then
    houses[name].treasury = houses[name].treasury + tax
    notice(pid, fmt("%d groschen earned; %d collected as the house's tax.", amount, tax))
  else
    notice(pid, fmt("%d groschen earned.", amount))
  end
end

-- ---------------------------------------------------------------- the web pages

local function open_frame(pid, frame)
  ShowPlayerWebFrame(pid, frame)
  SetPlayerWebFocus(pid, frame, true, true)
  SetPlayerCursor(pid, true)
end

local function open_me(pid)
  local name = playerHouse[pid]
  local h = name and houses[name]
  open_frame(pid, "me")
  SendPlayerWebMessage(pid, "me", {
    name = GetPlayerName(pid),
    money = GetPlayerMoney(pid),
    house = name,
    treasury = h and h.treasury or 0,
    prestige = h and h.prestige or 0,
    war = h and h.war or nil,
    rank = name and house_rank_of(pid) or nil,
    admin = IsPlayerAdmin(pid) or false,
    level = GetLevel(),
  })
end

local function open_hall(pid)
  local name = playerHouse[pid]
  if not name then return end
  local h = houses[name]

  local members = {}
  for lname, m in pairs(h.members) do
    members[#members + 1] = {
      name = lname,
      rank = RANKS[m.rank] or "retainer",
      online = GetPlayerId(lname) ~= nil,
    }
  end
  table.sort(members, function(a, b) return a.name < b.name end)

  local wars = {}
  if h.war then
    wars[#wars + 1] = { enemy = h.war, score = h.score, since = os.date("%H:%M", math.floor(h.war_started / 1000)) }
  end

  open_frame(pid, "hall")
  SendPlayerWebMessage(pid, "hall", {
    name = GetPlayerName(pid),
    house = name,
    money = GetPlayerMoney(pid),
    treasury = h.treasury,
    prestige = h.prestige,
    members = members,
    wars = wars,
    myRank = house_rank_of(pid),
  })
end

local function admin_log_entry(text)
  return os.date("%H:%M ") .. text
end

local adminLog = {}

local function admin_log(text)
  adminLog[#adminLog + 1] = admin_log_entry(text)
  if #adminLog > 40 then table.remove(adminLog, 1) end
end

local function open_admin(pid)
  local players = {}
  for _, p in ipairs(GetPlayers()) do
    players[#players + 1] = {
      id = p,
      name = GetPlayerName(p),
      house = playerHouse[p],
      money = GetPlayerMoney(p),
      ping = GetPlayerPing(p),
    }
  end
  open_frame(pid, "admin")
  SendPlayerWebMessage(pid, "admin", { players = players, log = adminLog })
end

-- ---------------------------------------------------------------- lifecycle

function OnGameModeInit()
  Log("feudalwars on " .. GetLevel() .. ": houses, wars, economy, ui" .. (db and ", database" or ", memory only"))

  if db then
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS players (name VARCHAR(32) PRIMARY KEY, money INT NOT NULL DEFAULT 0)")
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS houses (name VARCHAR(32) PRIMARY KEY, treasury INT NOT NULL DEFAULT 0, prestige INT NOT NULL DEFAULT 1)")
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS house_members (house VARCHAR(32), name VARCHAR(32), rank TINYINT NOT NULL DEFAULT 3, PRIMARY KEY (house, name))")
    local rows, err = db:QuerySync("SELECT name, treasury, prestige FROM houses")
    if rows then
      for _, r in ipairs(rows) do
        local h = house_new(r.name)
        h.treasury = r.treasury or 0
        h.prestige = r.prestige or 1
      end
      Log("feudalwars: loaded " .. #rows .. " house(s)")
    elseif err then
      Log("feudalwars: houses load failed: " .. tostring(err))
    end
    local mrows = db:QuerySync("SELECT house, name, rank FROM house_members")
    if mrows then
      for _, r in ipairs(mrows) do
        local h = houses[r.house]
        if h then h.members[r.name] = { rank = r.rank or 3 } end
      end
      Log("feudalwars: loaded " .. #mrows .. " house member(s)")
    end
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS job_sites (id VARCHAR(32) PRIMARY KEY, kind VARCHAR(16) NOT NULL DEFAULT 'mine', x DOUBLE NOT NULL DEFAULT 0, y DOUBLE NOT NULL DEFAULT 0, z DOUBLE NOT NULL DEFAULT 0, stock INT NOT NULL DEFAULT 0)")
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS job_skills (player VARCHAR(32), skill VARCHAR(16), level INT NOT NULL DEFAULT 0, PRIMARY KEY (player, skill))")
    local srows = db:QuerySync("SELECT id, kind, x, y, z, stock FROM job_sites")
    if srows then
      for _, r in ipairs(srows) do
        job_sites[r.id] = { id = r.id, kind = r.kind, x = r.x, y = r.y, z = r.z, stock = r.stock or 0 }
      end
      Log("feudalwars: loaded " .. #srows .. " job site(s)")
    end
  end

  local sx, sy, sz, syaw = GetDefaultSpawn()
  AddSpawnPoint(sx, sy, sz, syaw, "town")

  -- default work sites near the spawn (kept in memory when there is no database)
  local function job_ensure(id, kind, dx, dy)
    if job_sites[id] then return end
    local def = JOBS[kind]
    job_sites[id] = { id = id, kind = kind, x = sx + dx, y = sy + dy, z = sz, stock = def.stock_max }
    if db then
      local s = job_sites[id]
      db:Execute("INSERT INTO job_sites (id, kind, x, y, z, stock) VALUES (@i, @k, @x, @y, @z, @s)",
        { i = id, k = kind, x = s.x, y = s.y, z = s.z, s = s.stock }, function() end)
    end
  end
  job_ensure("mine1", "mine", -8.0, -4.0)
  job_ensure("farm1", "farm", 8.0, -4.0)
  job_ensure("forest1", "forest", 0.0, -10.0)

  -- visible work sites: compass marker + map icon + foreman NPC + use prompt
  local JOB_ICON = { mine = "mine", farm = "farm", forest = "camp" }
  local JOB_NPC = { mine = "Foreman Dobesh", farm = "Reeve Matousek", forest = "Woodward Janek" }
  local mapinfo = GetMapInfo()
  Log(fmt("feudalwars: map folder=%s readOnly=%s objects=%s (level %s)",
    tostring(mapinfo and mapinfo.folder), tostring(mapinfo and mapinfo.readOnly),
    tostring(mapinfo and mapinfo.objects), GetLevel()))
  local icon_types = {}
  for _, t in ipairs(GetMapIconTypes() or {}) do icon_types[t.name or ""] = true end
  for _, site in pairs(job_sites) do
    local def = JOBS[site.kind]
    if def then
      local mid = CreateMarker(site.x, site.y, site.z + 1.0, MARKER_POINT, 0, def.label)
      if mid then
        ShowMarkerForAll(mid)
      else
        Log("feudalwars: marker refused for " .. site.id)
      end
      local itype = JOB_ICON[site.kind]
      if not icon_types[itype] then
        Log(fmt("feudalwars: no map icon type '%s' on %s, using pin", itype, GetLevel()))
        itype = nil
      end
      local iid, ierr = CreateMapIcon(site.x, site.y, site.z,
        itype and { type = itype, name = def.label } or { icon = 0, name = def.label })
      if not iid then Log(fmt("feudalwars: map icon refused for %s: %s", site.id, tostring(ierr))) end
      local npc = CreateActor(nil, site.x + 1.5, site.y, site.z, 0, JOB_NPC[site.kind] or "Foreman", nil, "none", nil)
      if npc then SetActorPrompt(npc, "Ask about work") end
      local iid2 = CreateInteraction(site.x, site.y, site.z, "Work here (/job " .. site.kind .. ")")
      if iid2 then job_interactions[iid2] = site.kind end
    end
  end

  -- regrow job stocks on a timer
  SetTimer(function()
    for _, site in pairs(job_sites) do
      local def = JOBS[site.kind]
      if def and site.stock < def.stock_max then
        site.stock = math.min(def.stock_max, site.stock + math.max(1, math.floor(def.stock_max / 10)))
        if db then
          db:Execute("UPDATE job_sites SET stock = @s WHERE id = @i", { s = site.stock, i = site.id }, function() end)
        end
      end
    end
  end, 60000, true)

  local shop = CreateShop("The King's Provisioner", 0.5, -1)
  SetShopItem(shop, "torch", 10, -1)
  SetShopItem(shop, "bandage", 25, -1)
  SetShopItem(shop, "bread", 5, -1)
  SetShopItem(shop, "water", 3, -1)
  CreateVendor(shop, "provisioner", sx + 2.0, sy + 2.0, sz, syaw + 180.0, "Provisioner Bohush", nil, nil)

  -- hotkeys: E = work where you stand, F = collect, F2 = main menu (F1 is the photo mode)
  RegisterKeyBinding("fw.work", "Feudal Wars: start work here", "e")
  RegisterKeyBinding("fw.done", "Feudal Wars: collect the shift", "f")
  RegisterKeyBinding("fw.menu", "Feudal Wars: main menu", "f2")

  -- upkeep and war expiry, once a minute
  SetTimer(function()
    local now = GetServerTime()
    for name, h in pairs(houses) do
      if h.war and now - h.war_started > WAR.war_seconds * 1000 then
        local enemy = houses[h.war]
        if enemy then
          if h.score > enemy.score then
            local take = math.min(enemy.treasury, WAR.win_treasury)
            enemy.treasury = enemy.treasury - take
            h.treasury = h.treasury + take
            mylog(fmt("The house of %s won the war against %s and took %d groschen as the spoils.", name, h.war, take))
            broadcast_notice(fmt("%s won the war! The spoils: %d groschen.", name, take))
            save_house(h.war)
          end
          enemy.war = nil
          enemy.score = 0
          save_house(h.war)
        end
        h.war = nil
        h.war_started = 0
        h.score = 0
      end
      local cost = ECONOMY.upkeep_per_member * house_member_count(h)
      if cost > 0 then
        if h.treasury >= cost then
          h.treasury = h.treasury - cost
        else
          h.treasury = 0
          broadcast_notice(fmt("The treasury of %s ran dry - the upkeep is unpaid.", name))
        end
      end
    end
  end, 60000, true)

  -- the scoreboard: house, rank, purse
  SetScoreboardColumns({
    { key = "house", label = "House", width = 120 },
    { key = "rank", label = "Rank", width = 80 },
    { key = "purse", label = "Groschen", width = 90, align = "right" },
  })
end

function OnPlayerConnect(pid)
  local name = GetPlayerName(pid)
  local lname = name:lower()
  accounts[pid] = { name = lname, money = ECONOMY.start_money, known = false }

  SetPlayerState(pid, "house", "")
  SetPlayerState(pid, "rank", "")
  SetPlayerState(pid, "purse", "0")

  -- admins (from the script's list; move into the database when accounts arrive)
  for _, an in ipairs(ADMIN_NAMES) do
    if lname == an:lower() then SetPlayerAdmin(pid, true) end
  end

  local function restoreHouse()
    local name2 = playerHouse[pid]
    if name2 then
      local h = houses[name2]
      notice(pid, fmt("Welcome back under the banner of %s.", name2))
    end
  end

  if db then
    db:Query("SELECT money FROM players WHERE name = @n", { n = lname }, function(rows, err)
      if rows and rows[1] then
        accounts[pid].money = rows[1].money or 0
        accounts[pid].known = true
      elseif rows then
        accounts[pid].known = true
        db:Execute("INSERT INTO players (name, money) VALUES (@n, @m)", { n = lname, m = ECONOMY.start_money }, function() end)
      end
      restoreHouse()
    end)
    db:Query("SELECT skill, level FROM job_skills WHERE player = @n", { n = lname }, function(rows)
      if rows then
        job_skills[pid] = job_skills[pid] or {}
        for _, r in ipairs(rows) do job_skills[pid][r.skill] = r.level or 0 end
      end
    end)
  end
end

function OnPlayerRequestSpawn(pid)
  local sp = GetSpawnPoints("town")[1]
  if sp then SetSpawnInfo(pid, sp.x, sp.y, sp.z, sp.yaw) end
  return true
end

function OnPlayerSpawn(pid)
  local acc = accounts[pid]
  if acc then
    GivePlayerMoney(pid, acc.money - GetPlayerMoney(pid))
    SetPlayerState(pid, "purse", tostring(math.floor(GetPlayerMoney(pid))))
  end
  local name = playerHouse[pid]
  if name then
    local h = houses[name]
    SendClientMessage(pid, COLOR_SERVER, fmt("You serve the house of %s. Treasury: %d, prestige: %d.", name, h.treasury, h.prestige))
  end
  AddPlayerActionHint(pid, "fw-menu", "f2", "Main menu", { binding = "fw.menu" })
  AddPlayerActionHint(pid, "fw-work", "e", "Work here", { binding = "fw.work" })
  AddPlayerActionHint(pid, "fw-done", "f", "Collect shift", { binding = "fw.done" })
end

function OnPlayerDeath(pid, attacker)
  local victim, killer = playerHouse[pid], playerHouse[attacker]
  if killer and victim and killer ~= victim and house_at_war(killer, victim) then
    local kh, vh = houses[killer], houses[victim]
    kh.score = kh.score + WAR.kill_score
    vh.score = vh.score - WAR.kill_score
    SendClientMessageToAll(COLOR_YELLOW, fmt("%s of %s fell to %s of %s in the war.",
      GetPlayerName(pid), victim, GetPlayerName(attacker), killer))
  end
end

-- ---------------------------------------------------------------- chat commands

local function joinHouse(pid, name, rankIndex)
  playerHouse[pid] = name
  playerRank[pid] = rankIndex or 3
  local h = houses[name]
  if h then h.members[GetPlayerName(pid):lower()] = { rank = rankIndex or 3 } end
  if db then
    db:Execute("INSERT INTO house_members (house, name, rank) VALUES (@h, @n, @r) ON DUPLICATE KEY UPDATE rank = @r2",
      { h = name, n = GetPlayerName(pid):lower(), r = rankIndex or 3, r2 = rankIndex or 3 }, function() end)
  end
end

local function leaveHouse(pid)
  local name = playerHouse[pid]
  if not name then return end
  local h = houses[name]
  if h then h.members[GetPlayerName(pid):lower()] = nil end
  if db then
    db:Execute("DELETE FROM house_members WHERE house = @h AND name = @n", { h = name, n = GetPlayerName(pid):lower() }, function() end)
  end
  playerHouse[pid] = nil
  playerRank[pid] = nil
end

RegisterCommand("me", function(pid)
  open_me(pid)
end, { help = "your character: purse, house, standing" })

RegisterCommand("hall", function(pid)
  if not playerHouse[pid] then
    SendClientMessage(pid, COLOR_RED, "you serve no lord - /house create <name> or /house join <name> first.")
    return
  end
  open_hall(pid)
end, { help = "the house hall: roster, treasury, wars" })

RegisterCommand("house", function(pid, args)
  local verb, rest = args:match("^(%S*)%s*(.-)$")
  verb = verb:lower()
  local function say(text, bad) SendClientMessage(pid, bad and COLOR_RED or COLOR_SERVER, text) end

  if verb == "create" then
    local name = rest:lower()
    if not name:match("^%a+$") or #name < 3 or #name > 16 then
      say("a house name is 3 to 16 letters, no spaces: /house create <name>", true); return
    end
    if houses[name] then say("a house of that name already exists.", true); return end
    if playerHouse[pid] then say("you already serve a lord.", true); return end
    house_new(name)
    joinHouse(pid, name, 1)
    save_house(name)
    SendClientMessageToAll(COLOR_YELLOW, GetPlayerName(pid) .. " founded the house of " .. name .. ".")
  elseif verb == "join" then
    local name = rest:lower()
    if not houses[name] then say("no such house.", true); return end
    if playerHouse[pid] then say("you already serve a lord.", true); return end
    joinHouse(pid, name, 3)
    SendClientMessageToAll(COLOR_YELLOW, GetPlayerName(pid) .. " joined the house of " .. name .. ".")
  elseif verb == "leave" then
    if not playerHouse[pid] then say("you serve no lord.", true); return end
    local name = playerHouse[pid]
    leaveHouse(pid)
    SendClientMessage(pid, COLOR_SERVER, "you left the house of " .. name .. ".")
  elseif verb == "list" then
    local names = {}
    for hname in pairs(houses) do names[#names + 1] = hname end
    table.sort(names)
    SendClientMessage(pid, COLOR_SERVER, #names > 0 and ("houses: " .. table.concat(names, ", ")) or "no houses yet - /house create <name>")
  elseif verb == "info" then
    local name = playerHouse[pid]
    if not name then say("you serve no lord.", true); return end
    local h = houses[name]
    say(fmt("%s: treasury %d, members %d, prestige %d, war %s",
      name, h.treasury, house_member_count(h), h.prestige, h.war or "none"))
  else
    say("usage: /house [create|join|leave|list|info]", true)
  end
end, { help = "founding, joining and leaving a house", params = "[create|join|leave|list|info]" })

RegisterCommand("war", function(pid, args)
  local verb, rest = args:match("^(%S*)%s*(.-)$")
  verb = verb:lower()
  local function say(text, bad) SendClientMessage(pid, bad and COLOR_RED or COLOR_SERVER, text) end
  local me = playerHouse[pid]
  if not me then say("you serve no lord.", true); return end
  local h = houses[me]

  if verb == "declare" then
    local target = rest:lower()
    local th = houses[target]
    if not th then say("no such house.", true); return end
    if me == target then say("you cannot declare war on yourself.", true); return end
    if h.war then say("your house is already at war.", true); return end
    if h.treasury < WAR.declare_cost then say(fmt("the treasury needs %d groschen for a war.", WAR.declare_cost), true); return end
    h.treasury = h.treasury - WAR.declare_cost
    h.war = target
    th.war = me
    h.war_started = GetServerTime()
    save_house(me); save_house(target)
    SendClientMessageToAll(COLOR_YELLOW, fmt("The house of %s declared war on %s!", me, target))
    broadcast_notice(fmt("WAR: %s marches against %s!", me, target))
  elseif verb == "peace" then
    if not h.war then say("your house is not at war.", true); return end
    local enemyName = h.war
    local enemy = houses[enemyName]
    h.war = nil
    if enemy then enemy.war = nil end
    save_house(me)
    SendClientMessageToAll(COLOR_YELLOW, fmt("The war between %s and %s is over.", me, enemyName))
  elseif verb == "status" then
    if not h.war then say("your house is not at war.", true); return end
    local enemy = houses[h.war]
    say(fmt("%s vs %s: score %d - %d", me, h.war, h.score, enemy and enemy.score or 0))
  else
    say("usage: /war [declare <house>|peace|status]", true)
  end
end, { help = "declare wars, sue for peace, check the score", params = "[declare|peace|status]" })

RegisterCommand("money", function(pid)
  SendClientMessage(pid, COLOR_SERVER, fmt("Your purse: %d groschen.", GetPlayerMoney(pid)))
end, { help = "count your groschen" })

RegisterCommand("pay", function(pid, args)
  local target, amount = sscanf(args, "ud")
  if target == false or target == nil then SendClientMessage(pid, COLOR_RED, "usage: /pay <player> <amount>"); return end
  if amount <= 0 then SendClientMessage(pid, COLOR_RED, "the amount must be positive."); return end
  if GetPlayerMoney(pid) < amount then SendClientMessage(pid, COLOR_RED, "not enough groschen."); return end
  GivePlayerMoney(pid, -amount)
  GivePlayerMoney(target, amount)
  local tax = math.floor(amount * ECONOMY.trade_tax)
  local name = playerHouse[pid]
  if name and houses[name] and tax > 0 then houses[name].treasury = houses[name].treasury + tax end
  SendClientMessage(pid, COLOR_SERVER, fmt("You paid %d groschen to %s.", amount, GetPlayerName(target)))
  SendClientMessage(target, COLOR_SERVER, fmt("%s paid you %d groschen.", GetPlayerName(pid), amount))
end, { help = "pay another player", params = "<player> <amount>" })

-- /farm and /craft removed: use /job mine|farm|forest (visible sites with foremen, skills, map icons)

RegisterCommand("job", function(pid, args)
  local verb = (args:match("^(%S*)") or ""):lower()
  if verb == "mine" or verb == "farm" or verb == "forest" then
    job_work_start(pid, verb)
  elseif verb == "done" then
    job_work_collect(pid)
  elseif verb == "skills" then
    local s = job_skills[pid] or {}
    SendClientMessage(pid, COLOR_SERVER, fmt("skills: mining %d, farming %d, woodcutting %d.",
      s.mining or 0, s.farming or 0, s.woodcutting or 0))
  else
    job_status(pid)
    SendClientMessage(pid, COLOR_SERVER, "usage: /job [mine|farm|forest|done|skills]")
  end
end, { help = "work sites: mine, farm, forest", params = "[mine|farm|forest|done|skills]" })

RegisterCommand("prestige", function(pid, args)
  local verb = args:match("^(%S*)"):lower()
  local name = playerHouse[pid]
  if not name then SendClientMessage(pid, COLOR_RED, "you serve no lord."); return end
  local h = houses[name]
  if verb == "raise" then
    if h.treasury < ECONOMY.prestige_cost then
      SendClientMessage(pid, COLOR_RED, fmt("the treasury needs %d groschen.", ECONOMY.prestige_cost)); return
    end
    h.treasury = h.treasury - ECONOMY.prestige_cost
    h.prestige = h.prestige + 1
    save_house(name)
    SendClientMessageToAll(COLOR_YELLOW, fmt("The house of %s raised its prestige to %d.", name, h.prestige))
  else
    SendClientMessage(pid, COLOR_SERVER, fmt("%s prestige: %d", name, h.prestige))
  end
end, { help = "the house's standing", params = "[info|raise]" })

-- ---------------------------------------------------------------- help menu

local HELP_MENU = {
  { cmd = "/me", desc = "your character: purse, house, standing (opens the page)" },
  { cmd = "/hall", desc = "the house hall: roster, treasury, wars (opens the page)" },
  { cmd = "/house create|join|leave|list|info", desc = "found, join or leave a house" },
  { cmd = "/war declare|peace|status", desc = "declare wars, sue for peace, check the score" },
  { cmd = "/job mine|farm|forest|done|skills", desc = "work at the marked sites: mine, field, logging camp" },
  { cmd = "/goto mine|farm|forest|spawn", desc = "walk to a work site (teleport)" },
  { cmd = "/money", desc = "count your groschen" },
  { cmd = "/pay <player> <amount>", desc = "pay another player (5% tax to your house)" },
  { cmd = "/prestige info|raise", desc = "the house's standing" },
  { cmd = "/build list|place|cancel", desc = "raise a ready structure from the catalogue" },
  { cmd = "/editor", desc = "open the map editor (admins): place meshes by hand" },
  { cmd = "/admin", desc = "open the crown's console (admins)" },
}

local function open_menu(pid)
  open_frame(pid, "menu")
  local cmds = {}
  for _, h in ipairs(HELP_MENU) do cmds[#cmds + 1] = { cmd = h.cmd, desc = h.desc } end
  SendPlayerWebMessage(pid, "menu", { commands = cmds })
end

RegisterCommand("help", function(pid)
  open_menu(pid)
end, { help = "list all commands with descriptions" })

RegisterCommand("menu", function(pid)
  open_menu(pid)
end, { help = "open the command menu" })

RegisterCommand("goto", function(pid, args)
  local where = (args:match("^(%S*)") or ""):lower()
  local dest = nil
  if where == "spawn" then
    local sp = GetSpawnPoints("town")[1]
    if sp then dest = sp end
  else
    for _, site in pairs(job_sites) do
      if site.kind == where then dest = site break end
    end
  end
  if not dest then
    SendClientMessage(pid, COLOR_RED, "usage: /goto [mine|farm|forest|spawn]")
    return
  end
  SetPlayerPos(pid, dest.x + 2.0, dest.y, dest.z, 0)
  SendClientMessage(pid, COLOR_SERVER, "you walk to " .. (JOBS[where] and JOBS[where].label or "the town square") .. ".")
end, { help = "walk to a work site or the spawn", params = "[mine|farm|forest|spawn]" })

-- ---------------------------------------------------------------- admin

local function isAdmin(pid) return IsPlayerAdmin(pid) end

RegisterCommand("admin", function(pid)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "the crown's console is not yours."); return end
  open_admin(pid)
end, { help = "open the crown's console (admins)" })

RegisterCommand("kick", function(pid, args)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "only the crown's servants may kick."); return end
  local target, rest = args:match("^(%S*)%s*(.-)$")
  local tid = GetPlayerId(target)
  if not tid then SendClientMessage(pid, COLOR_RED, "no such player."); return end
  Kick(tid, rest ~= "" and rest or "the crown wills it")
  admin_log(GetPlayerName(pid) .. " kicked " .. GetPlayerName(tid))
end, { help = "remove a soul from the realm", params = "<player> [reason]", admin = true, secret = true })

RegisterCommand("ban", function(pid, args)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "only the crown's servants may ban."); return end
  local target, rest = args:match("^(%S*)%s*(.-)$")
  local tid = GetPlayerId(target)
  if not tid then SendClientMessage(pid, COLOR_RED, "no such player."); return end
  Ban(tid, rest ~= "" and rest or "banned by the crown", 0)
  admin_log(GetPlayerName(pid) .. " banned " .. GetPlayerName(tid))
end, { help = "ban a soul forever", params = "<player> [reason]", admin = true, secret = true })

RegisterCommand("give", function(pid, args)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "only the crown's servants may give."); return end
  local target, amount = sscanf(args, "ud")
  if target == false or target == nil then SendClientMessage(pid, COLOR_RED, "usage: /give <player> <amount>"); return end
  GivePlayerMoney(target, amount)
  admin_log(fmt("%s gave %d groschen to %s", GetPlayerName(pid), amount, GetPlayerName(target)))
  SendClientMessage(target, COLOR_SERVER, fmt("The crown granted you %d groschen.", amount))
end, { help = "grant groschen", params = "<player> <amount>", admin = true, secret = true })

RegisterCommand("tp", function(pid, args)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "only the crown's servants may travel freely."); return end
  local target = args:match("^(%S*)")
  local tid = GetPlayerId(target)
  if not tid then SendClientMessage(pid, COLOR_RED, "no such player."); return end
  local x, y, z, yaw = GetPlayerPos(tid)
  SetPlayerPos(pid, x + 1, y, z, yaw)
end, { help = "travel to a player", params = "<player>", admin = true, secret = true })

-- ---------------------------------------------------------------- builder: ready structures + preview

local BUILD_CATALOG = {
  tent = {
    label = "a campaign tent", cost = 200,
    parts = { "objects/manmade/common_fixtures/tents/tent_a.cgf" },
  },
  stall = {
    label = "a market stall", cost = 500,
    parts = { "objects/manmade/common_furniture/tables/table_market.cgf" },
  },
  palisade = {
    label = "a palisade wall", cost = 800,
    parts = { "objects/manmade/fortifications/palisade_wall.cgf" },
  },
  tower = {
    label = "a watch tower", cost = 2000,
    parts = { "objects/manmade/fortifications/watch_tower.cgf" },
  },
}

local function build_cancel(pid, silent)
  local b = build_preview[pid]
  if not b then return end
  if b.timer then KillTimer(b.timer) end
  for _, id in ipairs(b.ids or {}) do pcall(DeleteMapObject, id) end
  build_preview[pid] = nil
  if not silent then SendClientMessage(pid, COLOR_SERVER, "the builders stand down.") end
end

RegisterCommand("build", function(pid, args)
  local verb, rest = args:match("^(%S*)%s*(.-)$")
  verb = (verb or ""):lower()
  if verb == "list" or verb == "" then
    SendClientMessage(pid, COLOR_YELLOW, "Ready structures (the preview stands 60 seconds):")
    for key, b in pairs(BUILD_CATALOG) do
      SendClientMessage(pid, COLOR_SERVER, fmt("/build place %s - %s (%d groschen)", key, b.label, b.cost))
    end
    SendClientMessage(pid, COLOR_SERVER, "or open the map editor by hand: /editor")
    return
  end
  if verb == "cancel" then build_cancel(pid) return end
  if verb ~= "place" then
    SendClientMessage(pid, COLOR_RED, "usage: /build [list|place <name>|cancel]")
    return
  end
  local name = (rest:match("^(%S*)") or ""):lower()
  local spec = BUILD_CATALOG[name]
  if not spec then
    SendClientMessage(pid, COLOR_RED, "no such structure - /build list for the catalogue.")
    return
  end
  if GetPlayerMoney(pid) < spec.cost then
    SendClientMessage(pid, COLOR_RED, fmt("%s costs %d groschen.", spec.label, spec.cost))
    return
  end
  build_cancel(pid, true)
  local px, py, pz = GetPlayerPos(pid)
  local yaw = GetPlayerYaw(pid)
  local fx, fy = math.sin(math.rad(yaw)) * 6.0, math.cos(math.rad(yaw)) * 6.0
  local ids = {}
  for i, mesh in ipairs(spec.parts) do
    local id = CreateMapObject(mesh, px + fx + (i - 1) * 2.0, py + fy, pz, { yaw = yaw, persist = false })
    if id then ids[#ids + 1] = id end
  end
  if #ids == 0 then
    SendClientMessage(pid, COLOR_RED, "the ground refuses the builders here (no map, or a wrong mesh path).")
    return
  end
  GivePlayerMoney(pid, -spec.cost)
  save_money(pid)
  SendClientMessage(pid, COLOR_YELLOW, fmt("%s rises before you - a preview for 60 seconds. /build place again to keep it, /build cancel to tear it down.", spec.label))
  local t = SetTimer(function() build_cancel(pid) end, 60000, false)
  build_preview[pid] = { name = name, ids = ids, timer = t }
end, { help = "raise a ready structure with a preview", params = "[list|place <name>|cancel]" })

RegisterCommand("editor", function(pid)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "only the crown's servants may shape the land."); return end
  if not IsPlayerWebReady(pid) then
    SendClientMessage(pid, COLOR_RED, "the editor needs the web layer: enable server interfaces in the launcher options and relog.")
    return
  end
  local ok, err = SetPlayerEditor(pid, "admin")
  if ok then
    SendClientMessage(pid, COLOR_YELLOW, "the map editor is open: fly, pick meshes from the panel, place with the mouse. /editor close to shut it.")
  else
    SendClientMessage(pid, COLOR_RED, "the editor refuses: " .. tostring(err))
  end
end, { help = "open the map editor (admins)", admin = true })

function OnPlayerKeyBinding(pid, name, pressed)
  if not pressed then return end
  if name == "fw.work" then
    local px, py, pz = GetPlayerPos(pid)
    local best, bestd, bestkind = nil, 6.0, nil
    for _, site in pairs(job_sites) do
      local dx, dy, dz = site.x - px, site.y - py, site.z - pz
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d < bestd then best, bestd, bestkind = site, d, site.kind end
    end
    if bestkind then job_work_start(pid, bestkind)
    else SendClientMessage(pid, COLOR_RED, "no work site here - walk to a marked site (/goto mine|farm|forest).") end
  elseif name == "fw.done" then
    job_work_collect(pid)
  elseif name == "fw.menu" then
    open_menu(pid)
  end
end

function OnPlayerUseMapObject(pid, id)
  local kind = job_interactions[id]
  if kind and JOBS[kind] then
    job_work_start(pid, kind)
  end
end

function OnPlayerInteract(pid, id)
  local kind = job_interactions[id]
  if kind and JOBS[kind] then
    job_work_start(pid, kind)
  end
end

function OnPlayerDisconnect(pid, reason)
  build_cancel(pid, true)
  save_money(pid)
  job_work[pid] = nil
  job_skills[pid] = nil
  local name = playerHouse[pid]
  if name and houses[name] then houses[name].members[GetPlayerName(pid):lower()] = nil end
  playerHouse[pid] = nil
  playerRank[pid] = nil
  accounts[pid] = nil
end

-- ---------------------------------------------------------------- web events

-- UI frames talk via KcdMp.emitServer -> OnClientEvent (source = frame name).
-- OnPlayerWebSurfaceEvent is only for in-world boards (CreateWebSurface), which we don't use.
function OnClientEvent(pid, name, payload, source)
  local data = {}
  if payload and payload ~= "" then
    if payload:sub(1, 1) == "{" then data = JsonDecode(payload) or {} end
  end
  web_event(pid, name, data)
end

function OnPlayerWebSurfaceEvent(pid, id, name, payload)
  local data = {}
  if payload and payload ~= "" then data = JsonDecode(payload) or {} end
  web_event(pid, name, data)
end

local function close_frame(pid, frame)
  DestroyPlayerWebFrame(pid, frame)
  SetPlayerWebFocus(pid, frame, false, false)
  SetPlayerCursor(pid, false)
end

local function web_event(pid, name, data)

  if name == "menu.cursor" then
    SetPlayerCursor(pid, true)
    SetPlayerWebFocus(pid, "menu", true, true)
  elseif name == "menu.close" then
    close_frame(pid, "menu")
  elseif name == "menu.run" then
    local cmd = tostring(data.cmd or "")
    close_frame(pid, "menu")
    local base = cmd:match("^(%S+)")
    if base == "/me" then open_me(pid)
    elseif base == "/hall" then if playerHouse[pid] then open_hall(pid) end
    elseif base == "/admin" then if isAdmin(pid) then open_admin(pid) end
    elseif base == "/menu" or base == "/help" then open_menu(pid)
    else SendClientMessage(pid, COLOR_SERVER, "type it in the chat: " .. cmd) end
  elseif name == "me.close" then
    close_frame(pid, "me")
  elseif name == "house.close" then
    close_frame(pid, "hall")
  elseif name == "house.donate" then
    local amount = math.floor(tonumber(data.amount) or 0)
    local hname = playerHouse[pid]
    if amount > 0 and hname and GetPlayerMoney(pid) >= amount then
      GivePlayerMoney(pid, -amount)
      houses[hname].treasury = houses[hname].treasury + amount
      save_house(hname)
      SendClientMessage(pid, COLOR_SERVER, fmt("You donated %d groschen to the house.", amount))
      open_hall(pid)
    end
  elseif name == "house.prestige" then
    local hname = playerHouse[pid]
    if hname then
      local h = houses[hname]
      if h.treasury >= ECONOMY.prestige_cost then
        h.treasury = h.treasury - ECONOMY.prestige_cost
        h.prestige = h.prestige + 1
        save_house(hname)
        SendClientMessageToAll(COLOR_YELLOW, fmt("The house of %s raised its prestige to %d.", hname, h.prestige))
        open_hall(pid)
      else
        SendClientMessage(pid, COLOR_RED, fmt("the treasury needs %d groschen.", ECONOMY.prestige_cost))
      end
    end
  elseif name == "house.declare" then
    local hname = playerHouse[pid]
    local enemy = (data.enemy or ""):lower()
    if hname and enemy ~= "" then
      local h, th = houses[hname], houses[enemy]
      if th and hname ~= enemy and not h.war and h.treasury >= WAR.declare_cost then
        h.treasury = h.treasury - WAR.declare_cost
        h.war = enemy
        th.war = hname
        h.war_started = GetServerTime()
        save_house(hname); save_house(enemy)
        SendClientMessageToAll(COLOR_YELLOW, fmt("The house of %s declared war on %s!", hname, enemy))
        open_hall(pid)
      end
    end
  elseif name == "house.peace" then
    local hname = playerHouse[pid]
    if hname and houses[hname].war then
      local enemyName = houses[hname].war
      local enemy = houses[enemyName]
      houses[hname].war = nil
      if enemy then enemy.war = nil end
      save_house(hname)
      SendClientMessageToAll(COLOR_YELLOW, fmt("The war between %s and %s is over.", hname, enemyName))
      open_hall(pid)
    end
  elseif name == "admin.close" then
    close_frame(pid, "admin")
  elseif isAdmin(pid) then
    if name == "admin.kick" then
      Kick(data.id, data.reason or "the crown wills it")
      admin_log(fmt("%s kicked %s", GetPlayerName(pid), GetPlayerName(data.id) or tostring(data.id)))
      open_admin(pid)
    elseif name == "admin.ban" then
      Ban(data.id, data.reason or "banned by the crown", (tonumber(data.minutes) or 0) * 60)
      admin_log(fmt("%s banned %s", GetPlayerName(pid), GetPlayerName(data.id) or tostring(data.id)))
    elseif name == "admin.heal" then
      SetPlayerHealth(data.id, GetPlayerMaxHealth(data.id))
      notice(data.id, "The crown's physician tended your wounds.")
      open_admin(pid)
    elseif name == "admin.money" then
      local amount = math.floor(tonumber(data.amount) or 0)
      if amount ~= 0 then
        GivePlayerMoney(data.id, amount)
        save_money(data.id)
        admin_log(fmt("%s gave %d groschen to %s", GetPlayerName(pid), amount, GetPlayerName(data.id)))
        open_admin(pid)
      end
    elseif name == "admin.tp" then
      local x, y, z, yaw = GetPlayerPos(data.id)
      SetPlayerPos(pid, x + 1, y, z, yaw)
    end
  end
end
