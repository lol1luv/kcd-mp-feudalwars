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

-- Work = hit the vein with the right tool in your hands. No buttons are locked,
-- no timers block combat: every swing on the vein's rock/tree/soil counts.
-- E on the site only tells you what tool to hold and how the vein stands.
-- Resources: the vein gives real items (weight + price from the base game item),
-- with rare drops. Coal/iron are common, silver/gold are rare. Sell them at the auction.
local RES = {
  coal  = { base = "charcoal", name = { en = "Coal", ru = "Уголь" }, price = 4 },
  iron  = { base = "iron", name = { en = "Iron ore", ru = "Железная руда" }, price = 8 },
  silver = { base = "silver", name = { en = "Silver ore", ru = "Серебряная руда" }, price = 25 },
  gold  = { base = "gold", name = { en = "Gold ore", ru = "Золотая руда" }, price = 60 },
  stone = { base = "stone", name = { en = "Stone", ru = "Камень" }, price = 2 },
  wood  = { base = "wood", name = { en = "Timber", ru = "Бревно" }, price = 3 },
  grain = { base = "grain", name = { en = "Grain", ru = "Зерно" }, price = 2 },
}

local JOBS = {
  mine = {
    label = "the mine", skill = "mining",
    stock_max = 50, hits_per_unit = 5,
    pay = 2, skill_pay_bonus = 1,
    icon = "troskyQuarry", icon_num = 48,
    tools = { "pickaxe", "hammer", "normalHammer", "shovel" },
    tool_names = "a pickaxe, hammer or shovel",
    vein_mesh = "objects/natural/rocks/boulder_granite_a.cgf",
    hit_effect = "collisions.rock_hit",
    hit_sound = "special_blacksmith_hammer_anvil",
    drops = { { res = "stone", w = 45 }, { res = "coal", w = 30 }, { res = "iron", w = 18 }, { res = "silver", w = 5 }, { res = "gold", w = 2 } },
    props = {
      "objects/manmade/common_furniture/barrels/barrel_a.cgf",
      "objects/manmade/common_furniture/crates/crate_box_a.cgf",
    },
  },
  farm = {
    label = "the field", skill = "farming",
    stock_max = 60, hits_per_unit = 3,
    pay = 2, skill_pay_bonus = 1,
    icon = "miller", icon_num = 21,
    tools = { "shovel", "hoe", "sickle", "scythe" },
    tool_names = "a shovel, hoe or sickle",
    vein_mesh = "objects/manmade/common_furniture/crates/crate_low_a.cgf",
    hit_effect = "collisions.dirt_hit",
    hit_sound = "special_digging",
    drops = { { res = "grain", w = 100 } },
    props = {
      "objects/manmade/common_furniture/barrels/barrel_b.cgf",
    },
  },
  forest = {
    label = "the logging camp", skill = "woodcutting",
    stock_max = 40, hits_per_unit = 4,
    pay = 2, skill_pay_bonus = 1,
    icon = "camp", icon_num = 38,
    tools = { "lumberjack_axe", "axe", "woodaxe", "hatchet" },
    tool_names = "a woodcutter's axe",
    vein_mesh = "objects/natural/trees/oak/oak_trunk_a.cgf",
    hit_effect = "collisions.wood_hit",
    hit_sound = "special_wood_chop",
    drops = { { res = "wood", w = 100 } },
    props = {
      "objects/manmade/common_furniture/crates/crate_box_b.cgf",
      "objects/manmade/task_specific_props/food_processing/cooking/fireplace_wood_a.cgf",
    },
  },
}

local job_sites = {}    -- id -> { id, kind, x, y, z, stock, hits, marker, mapicon, props = {ids}, vein, interact }
local job_skills = {}    -- pid -> { mining = n, farming = n, woodcutting = n }
local job_interactions = {} -- interaction id -> site id
local job_hit_cd = {}   -- pid -> earliest next hit time (anti-macro)
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

-- what the player holds: right/left hand item classes + drawn weapon name
local function job_tool_in_hands(pid)
  local r, l = GetPlayerHandItems(pid)
  local w = GetPlayerWeapon(pid)
  return (r or "") .. " " .. (l or "") .. " " .. (w or "")
end

local function job_has_tool(pid, def)
  local hands = job_tool_in_hands(pid):lower()
  for _, t in ipairs(def.tools or {}) do
    if hands:find(t:lower(), 1, true) then return true end
  end
  return false
end

-- E on the site: no lock, no timer - just tells what to do
local function job_work_start(pid, kind, site_id)
  local site = (site_id and job_sites[site_id]) or job_find_near(pid, kind)
  if not site then
    SendClientMessage(pid, COLOR_RED, fmt("no %s nearby - walk to %s.", JOBS[kind].label, JOBS[kind].label))
    return
  end
  local def = JOBS[site.kind]
  if site.stock <= 0 then
    SendClientMessage(pid, COLOR_RED, fmt("%s is exhausted - it regrows with time.", def.label))
    return
  end
  local skill = job_skill_of(pid, def.skill)
  SendClientMessage(pid, COLOR_YELLOW, fmt("%s: %d %s left. Hold %s and strike the %s - %d hits per %s. Your %s: %d.",
    def.label, site.stock, def.unit, def.tool_names, site.kind == "mine" and "rock" or (site.kind == "forest" and "trunk" or "soil"),
    def.hits_per_unit, def.unit, def.skill, skill))
end

-- a swing struck the level: if it hit our vein with the right tool, count it
local function job_on_hit(pid, hit)
  if not hit or not hit.x then return end
  local now = GetServerTime()
  if job_hit_cd[pid] and now < job_hit_cd[pid] then return end
  job_hit_cd[pid] = now + 800
  -- nearest vein within 4m of the hit point
  local best, bestd = nil, 4.0
  for _, site in pairs(job_sites) do
    local dx, dy, dz = site.x - hit.x, site.y - hit.y, site.z - hit.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < bestd then best, bestd = site, d end
  end
  if not best then return end
  local def = JOBS[best.kind]
  if best.stock <= 0 then
    SendClientMessage(pid, COLOR_RED, fmt("%s is exhausted - it regrows with time.", def.label))
    return
  end
  if not job_has_tool(pid, def) then
    SendClientMessage(pid, COLOR_RED, fmt("you need %s in your hands to work %s.", def.tool_names, def.label))
    return
  end
  -- feedback: sparks/dust + sound at the hit point
  pcall(SpawnEffect, def.hit_effect, hit.x, hit.y, hit.z, 1.0)
  pcall(PlaySound, def.hit_sound, hit.x, hit.y, hit.z, 2)
  best.hits = (best.hits or 0) + 1
  local need = def.hits_per_unit or 5
  if best.hits >= need then
    best.hits = 0
    best.stock = best.stock - 1
    if db then
      db:Execute("UPDATE job_sites SET stock = @s WHERE id = @i", { s = best.stock, i = best.id }, function() end)
    end
    -- the vein bursts: a weighted resource drop into your bag + small wage
    local drop = job_roll_drop(def)
    local rdef = RES[drop]
    if rdef then
      GivePlayerItem(pid, "fw_" .. drop, 1)
      SendClientMessage(pid, COLOR_YELLOW, fmt("a lump of %s breaks off.", rdef.name[lang_of(pid)] or rdef.name.en))
    end
    local skill = job_skill_of(pid, def.skill)
    local pay = def.pay + skill * def.skill_pay_bonus
    local total = skill + 1
    if total >= 10 and total % 10 == 0 then
      local nl = job_skill_up(pid, def.skill)
      SendClientMessage(pid, COLOR_YELLOW, fmt("%s skill raised to %d: +%d wage.", def.skill, nl, def.skill_pay_bonus))
    else
      job_skill_up(pid, def.skill)
    end
    earn(pid, pay)
    save_money(pid)
    SendClientMessage(pid, COLOR_SERVER, fmt("+%d groschen wage (%s %d left).", pay, def.label, best.stock))
    if best.stock <= 0 then
      SendClientMessage(pid, COLOR_YELLOW, fmt("%s is worked out - come back later.", def.label))
      if best.vein then pcall(DestroyEntity, best.vein) best.vein = nil end
    end
  else
    SendClientMessage(pid, COLOR_SERVER, fmt("crack... (%d/%d)", best.hits, need))
  end
end

-- weighted resource roll for a vein burst
function job_roll_drop(def)
  local total = 0
  for _, d in ipairs(def.drops or {}) do total = total + (d.w or 1) end
  local r = math.random() * total
  for _, d in ipairs(def.drops or {}) do
    r = r - (d.w or 1)
    if r <= 0 then return d.res end
  end
  return (def.drops or {})[1] and def.drops[1].res or "stone"
end

local function job_status(pid)
  local lines = {}
  for kind, def in pairs(JOBS) do
    local site = job_find_near(pid, kind)
    local skill = job_skill_of(pid, def.skill)
    if site then
      lines[#lines + 1] = fmt("%s: %d %s left, hold %s, your %s %d", def.label, site.stock, def.unit, def.tool_names, def.skill, skill)
    else
      lines[#lines + 1] = fmt("%s: walk closer (your %s %d)", def.label, def.skill, skill)
    end
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
    lang = lang_of(pid),
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
    lang = lang_of(pid),
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
  SendPlayerWebMessage(pid, "admin", { lang = lang_of(pid), players = players, log = adminLog })
end

-- ---------------------------------------------------------------- auction

local auction_lots = {}  -- id -> { id, seller, res, amount, price }
local auction_next = 1

local function auction_list_for(pid)
  local lang = lang_of(pid)
  local lots = {}
  for id, lot in pairs(auction_lots) do
    local rdef = RES[lot.res]
    lots[#lots + 1] = {
      id = id, seller = lot.seller, res = lot.res,
      res_name = rdef and (rdef.name[lang] or rdef.name.en) or lot.res,
      amount = lot.amount, price = lot.price,
      mine = lot.seller == (accounts[pid] and accounts[pid].name),
    }
  end
  table.sort(lots, function(a, b) return a.id < b.id end)
  return lots
end

local function auction_bag_of(pid)
  local bag = {}
  for _, it in ipairs(GetPlayerInventory(pid) or {}) do
    bag[it.class or it.item or ""] = (it.amount or 1)
  end
  return bag
end

local function open_auction(pid)
  open_frame(pid, "auction")
  local lang = lang_of(pid)
  local bag = {}
  for res, rdef in pairs(RES) do
    bag[#bag + 1] = { res = res, name = rdef.name[lang] or rdef.name.en, have = 0 }
  end
  for _, it in ipairs(GetPlayerInventory(pid) or {}) do
    local cls = tostring(it.class or it.item or "")
    if cls:sub(1, 3) == "fw_" then
      local res = cls:sub(4)
      for _, b in ipairs(bag) do
        if b.res == res then b.have = b.have + (it.amount or 1) end
      end
    end
  end
  SendPlayerWebMessage(pid, "auction", {
    lang = lang, lots = auction_list_for(pid), bag = bag,
    money = GetPlayerMoney(pid),
  })
end

-- ---------------------------------------------------------------- lifecycle

function OnGameModeInit()
  Log("feudalwars on " .. GetLevel() .. ": houses, wars, economy, ui" .. (db and ", database" or ", memory only"))

  -- resource items: our names on the game's bases (weight/price come along)
  for res, rdef in pairs(RES) do
    local ok, err = DefineItem("fw_" .. res, { base = rdef.base, name = rdef.name.en, price = rdef.price })
    if not ok then Log(fmt("feudalwars: resource %s not defined: %s (base '%s'?)", res, tostring(err), rdef.base)) end
  end

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
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS auction (id INT AUTO_INCREMENT PRIMARY KEY, seller VARCHAR(32), res VARCHAR(16), amount INT NOT NULL DEFAULT 1, price INT NOT NULL DEFAULT 1)")
    local arows = db:QuerySync("SELECT id, seller, res, amount, price FROM auction")
    if arows then
      for _, r in ipairs(arows) do
        auction_lots[r.id] = { id = r.id, seller = r.seller, res = r.res, amount = r.amount, price = r.price }
        if r.id >= auction_next then auction_next = r.id + 1 end
      end
      Log("feudalwars: loaded " .. #arows .. " auction lot(s)")
    end
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

  -- visible work sites: compass marker + map icon (real game types) + props + use prompt
  local JOB_NPC = { mine = "Foreman Dobesh", farm = "Reeve Matousek", forest = "Woodward Janek" }
  local mapinfo = GetMapInfo()
  Log(fmt("feudalwars: map folder=%s readOnly=%s objects=%s (level %s)",
    tostring(mapinfo and mapinfo.folder), tostring(mapinfo and mapinfo.readOnly),
    tostring(mapinfo and mapinfo.objects), GetLevel()))
  local icon_types = {}
  for _, t in ipairs(GetMapIconTypes() or {}) do icon_types[t.name or ""] = true end
  local function job_spawn_visual(site)
    local def = JOBS[site.kind]
    if not def then return end
    -- clear old visuals (re-map, reload)
    if site.marker then pcall(DestroyMarker, site.marker) site.marker = nil end
    if site.mapicon then pcall(DeleteMapIcon, site.mapicon) site.mapicon = nil end
    if site.props then for _, pe in ipairs(site.props) do pcall(DestroyEntity, pe) end end
    site.props = {}
    if site.interact then pcall(DestroyEntity, site.interact) site.interact = nil end
    -- compass marker (quest symbol, always drawn)
    local mid = CreateMarker(site.x, site.y, site.z + 1.0, MARKER_QUEST, 0, def.label)
    if mid then site.marker = mid ShowMarkerForAll(mid)
    else Log("feudalwars: marker refused for " .. site.id) end
    -- map icon: real game type when the level knows it, else the legend icon number
    local opts
    if def.icon and icon_types[def.icon] then
      opts = { type = def.icon, name = def.label }
    else
      Log(fmt("feudalwars: no map icon type '%s' on %s, using icon %d", tostring(def.icon), GetLevel(), def.icon_num or 0))
      opts = { icon = def.icon_num or 0, name = def.label }
    end
    local iid, ierr = CreateMapIcon(site.x, site.y, site.z, opts)
    if iid then site.mapicon = iid
    else Log(fmt("feudalwars: map icon refused for %s: %s", site.id, tostring(ierr))) end
    -- the vein itself: a rock / trunk / soil mound you strike with the tool
    if site.vein then pcall(DestroyEntity, site.vein) site.vein = nil end
    if site.stock > 0 and def.vein_mesh then
      local v = CreateProp(def.vein_mesh, site.x, site.y, site.z, 0, 1.2, false, nil)
      if v then site.vein = v
      else Log(fmt("feudalwars: vein refused: %s", def.vein_mesh)) end
    end
    -- physical props: crates, barrels, fireplace - the site looks like a work place
    for i, mesh in ipairs(def.props or {}) do
      local px = site.x + (i - 1) * 1.6 - 1.0
      local pe = CreateProp(mesh, px, site.y + 1.0, site.z, (i * 37) % 360, 1, false, nil)
      if pe then site.props[#site.props + 1] = pe
      else Log(fmt("feudalwars: prop refused: %s", mesh)) end
    end
    -- foreman NPC with a prompt
    local npc = CreateActor(nil, site.x + 1.5, site.y, site.z, 0, JOB_NPC[site.kind] or "Foreman", nil, "none", nil)
    if npc then
      SetActorPrompt(npc, "Ask about work")
      site.props[#site.props + 1] = npc
    end
    -- E interaction: radius 3m so the prompt actually shows
    local ie = CreateInteraction(site.x, site.y, site.z, "Work here (" .. site.kind .. ")", 3.0, nil)
    if ie then
      site.interact = ie
      job_interactions[ie] = site.id
      Log(fmt("feudalwars: interaction %d -> site %s (%s)", ie, site.id, site.kind))
    else
      Log("feudalwars: interaction refused for " .. site.id)
    end
  end
  for _, site in pairs(job_sites) do job_spawn_visual(site) end

  -- regrow job stocks on a timer; a refilled vein rises again
  SetTimer(function()
    for _, site in pairs(job_sites) do
      local def = JOBS[site.kind]
      if def and site.stock < def.stock_max then
        local was_empty = site.stock <= 0
        site.stock = math.min(def.stock_max, site.stock + math.max(1, math.floor(def.stock_max / 10)))
        if db then
          db:Execute("UPDATE job_sites SET stock = @s WHERE id = @i", { s = site.stock, i = site.id }, function() end)
        end
        if was_empty and site.stock > 0 and def.vein_mesh and not site.vein then
          local v = CreateProp(def.vein_mesh, site.x, site.y, site.z, 0, 1.2, false, nil)
          if v then site.vein = v end
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

  -- hotkeys: E = ask the site what to do, F2 = main menu (F1 is the photo mode).
  -- Work itself is by weapon swings on the vein (OnPlayerHitScenery) - nothing is locked.
  RegisterKeyBinding("fw.work", "Feudal Wars: ask the work site", "e")
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
  AddPlayerActionHint(pid, "fw-work", "e", "Ask about work", { binding = "fw.work" })
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
  elseif verb == "kit" then
    -- foreman's loan: a tool for the nearest site, into your hands
    local px, py, pz = GetPlayerPos(pid)
    local best, bestd = nil, 8.0
    for _, site in pairs(job_sites) do
      local dx, dy, dz = site.x - px, site.y - py, site.z - pz
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d < bestd then best, bestd = site, d end
    end
    if not best then
      SendClientMessage(pid, COLOR_RED, "no work site here - walk to a marked site first.")
      return
    end
    local def = JOBS[best.kind]
    local tool = def.tools and def.tools[1]
    if tool then
      GivePlayerItem(pid, tool, 1)
      SendClientMessage(pid, COLOR_YELLOW, fmt("the foreman lends you %s - take it in your hands and strike the %s.",
        def.tool_names, best.kind == "mine" and "rock" or (best.kind == "forest" and "trunk" or "soil")))
    end
  elseif verb == "skills" then
    local s = job_skills[pid] or {}
    SendClientMessage(pid, COLOR_SERVER, fmt("skills: mining %d, farming %d, woodcutting %d.",
      s.mining or 0, s.farming or 0, s.woodcutting or 0))
  else
    job_status(pid)
    SendClientMessage(pid, COLOR_SERVER, "usage: /job [mine|farm|forest|kit|skills] - work by striking the vein with the tool in your hands")
  end
end, { help = "work sites: mine, farm, forest", params = "[mine|farm|forest|kit|skills]" })

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

-- ---------------------------------------------------------------- help menu + language

local LANGS = { en = true, ru = true }
local player_lang = {}    -- pid -> "en" | "ru"

local STR = {
  en = {
    menu_title = "Feudal Wars",
    menu_keys = "Keys: E work where you stand, F collect the shift, F2 this menu, Esc close.",
    menu_mouse = "If the mouse is stuck in the look-around, press the button:",
    btn_mouse = "Free the mouse",
    btn_me = "My character",
    btn_hall = "House hall",
    btn_admin = "Crown's console",
    btn_settings = "Settings",
    col_cmd = "Command",
    col_what = "What it does",
    btn_open = "Open",
    settings_title = "Settings",
    settings_lang = "Language",
    settings_back = "Back",
    lang_saved = "Language: English.",
  },
  ru = {
    menu_title = "Феодальные войны",
    menu_keys = "Клавиши: E работать, F забрать смену, F2 это меню, Esc закрыть.",
    menu_mouse = "Если мышь застряла в обзоре, нажми кнопку:",
    btn_mouse = "Освободить мышь",
    btn_me = "Мой персонаж",
    btn_hall = "Зал дома",
    btn_admin = "Королевский совет",
    btn_settings = "Настройки",
    col_cmd = "Команда",
    col_what = "Что делает",
    btn_open = "Открыть",
    settings_title = "Настройки",
    settings_lang = "Язык",
    settings_back = "Назад",
    lang_saved = "Язык: русский.",
  },
}

-- Menu actions: every button does the thing through UI, never sends you to the chat.
-- action: frame to open. Commands stay untranslated (typed as-is); titles/descs localize.
local HELP_MENU = {
  { action = "me", cmd = "/me", title = { en = "My character", ru = "Мой персонаж" }, desc = { en = "purse, house, standing", ru = "кошелёк, дом, положение" } },
  { action = "hall", cmd = "/hall", title = { en = "House hall", ru = "Зал дома" }, desc = { en = "roster, treasury, wars", ru = "люди, казна, войны" } },
  { action = "auction", cmd = "/auction", title = { en = "Auction", ru = "Торг" }, desc = { en = "sell resources, buy from others", ru = "продать ресурсы, купить у других" } },
  { action = "job", cmd = "/job", title = { en = "Work", ru = "Работа" }, desc = { en = "strike the vein with the tool in your hands", ru = "бей жилу инструментом в руках" } },
  { action = "goto", cmd = "/goto", title = { en = "Go to a site", ru = "Идти к месту" }, desc = { en = "walk to a work site or the spawn", ru = "перейти к работе или на площадь" } },
  { action = "build", cmd = "/build", title = { en = "Build (admins)", ru = "Стройка (админы)" }, desc = { en = "raise a ready structure with a preview", ru = "построить готовое здание с предпросмотром" } },
  { action = "editor", cmd = "/editor", title = { en = "Map editor (admins)", ru = "Редактор карты (админы)" }, desc = { en = "the game's own editor: fly, place meshes", ru = "встроенный редактор: полёт, объекты" } },
  { action = "lang", cmd = "/lang", title = { en = "Language", ru = "Язык" }, desc = { en = "switch the menu language", ru = "сменить язык меню" } },
  { action = "admin", cmd = "/admin", title = { en = "Crown's console (admins)", ru = "Совет короны (админы)" }, desc = { en = "players, kick, ban, money", ru = "игроки, кик, бан, деньги" } },
}

local function lang_of(pid) return player_lang[pid] or "en" end
local function T(pid, key) return (STR[lang_of(pid)] or STR.en)[key] or key end

local function open_menu(pid)
  open_frame(pid, "menu")
  local lang = lang_of(pid)
  local cmds = {}
  for _, h in ipairs(HELP_MENU) do
    cmds[#cmds + 1] = { action = h.action, cmd = h.cmd, title = h.title[lang] or h.title.en, desc = h.desc[lang] or h.desc.en }
  end
  local s = STR[lang] or STR.en
  SendPlayerWebMessage(pid, "menu", {
    commands = cmds, lang = lang,
    title = s.menu_title, keys = s.menu_keys, mouse = s.menu_mouse,
    btn_mouse = s.btn_mouse, btn_me = s.btn_me, btn_hall = s.btn_hall,
    btn_admin = s.btn_admin, btn_settings = s.btn_settings,
    col_cmd = s.col_cmd, col_what = s.col_what, btn_open = s.btn_open,
    settings_title = s.settings_title, settings_lang = s.settings_lang,
    settings_back = s.settings_back,
  })
end

-- menu buttons act through UI: open the frame, never send you to the chat
local function menu_do(pid, action)
  close_frame(pid, "menu")
  if action == "me" then open_me(pid)
  elseif action == "hall" then
    if playerHouse[pid] then open_hall(pid)
    else SendClientMessage(pid, COLOR_RED, "you serve no lord - ask a house to take you in.") end
  elseif action == "auction" then open_auction(pid)
  elseif action == "job" then job_status(pid)
  elseif action == "goto" then
    local sp = GetSpawnPoints("town")[1]
    if sp then SetPlayerPos(pid, sp.x + 2.0, sp.y, sp.z, 0) end
  elseif action == "build" then open_build(pid)
  elseif action == "editor" then
    if isAdmin(pid) then
      if IsPlayerWebReady(pid) then SetPlayerEditor(pid, "admin")
      else SendClientMessage(pid, COLOR_RED, "the editor needs the web layer: enable server interfaces in the launcher options and relog.") end
    end
  elseif action == "lang" then open_menu(pid)
  elseif action == "admin" then if isAdmin(pid) then open_admin(pid) end
  end
end

RegisterCommand("lang", function(pid, args)
  local l = (args:match("^(%S*)") or ""):lower()
  if LANGS[l] then
    player_lang[pid] = l
    if db and accounts[pid] then
      db:Execute("INSERT INTO players (name, money) VALUES (@n, @m) ON DUPLICATE KEY UPDATE money = money",
        { n = accounts[pid].name, m = 0 }, function() end)
    end
    SendClientMessage(pid, COLOR_SERVER, STR[l].lang_saved)
    open_menu(pid)
  else
    SendClientMessage(pid, COLOR_SERVER, "usage: /lang [en|ru]")
  end
end, { help = "language: en or ru", params = "[en|ru]" })

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

-- map a work site to a real place: stand where the site should be, /jobsite <id|new> <mine|farm|forest>
RegisterCommand("jobsite", function(pid, args)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "only the crown's servants may move work sites."); return end
  local id, kind = args:match("^(%S*)%s*(%S*)")
  id, kind = (id or ""):lower(), (kind or ""):lower()
  if kind == "" or not JOBS[kind] then
    SendClientMessage(pid, COLOR_RED, "usage: /jobsite <id|new> <mine|farm|forest>")
    local list = {}
    for sid, s in pairs(job_sites) do list[#list + 1] = sid .. "=" .. s.kind end
    SendClientMessage(pid, COLOR_SERVER, "sites: " .. table.concat(list, ", "))
    return
  end
  local px, py, pz = GetPlayerPos(pid)
  if id == "new" then
    id = kind .. math.floor(px) .. "_" .. math.floor(py)
  end
  local site = job_sites[id] or { id = id }
  site.kind, site.x, site.y, site.z = kind, px, py, pz
  site.stock = JOBS[kind].stock_max
  job_sites[id] = site
  if db then
    db:Execute("INSERT INTO job_sites (id, kind, x, y, z, stock) VALUES (@i, @k, @x, @y, @z, @s) " ..
      "ON DUPLICATE KEY UPDATE kind = @k2, x = @x2, y = @y2, z = @z2, stock = @s2",
      { i = id, k = kind, x = px, y = py, z = pz, s = site.stock, k2 = kind, x2 = px, y2 = py, z2 = pz, s2 = site.stock }, function() end)
  end
  job_spawn_visual(site)
  SendClientMessage(pid, COLOR_YELLOW, fmt("work site %s (%s) mapped here.", id, kind))
  Log(fmt("feudalwars: jobsite %s mapped to %.1f %.1f %.1f", id, px, py, pz))
end, { help = "map a work site to this place", params = "<id|new> <mine|farm|forest>", admin = true })

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
    label = { en = "Campaign tent", ru = "Походная палатка" }, cost = 0,
    parts = { "objects/manmade/structures/living/tents/tent_big_fancy_a.cgf" },
  },
  stall = {
    label = { en = "Market stall", ru = "Торговая лавка" }, cost = 0,
    parts = {
      "objects/manmade/task_specific_props/trade/merge_market_bread_stand.cgf",
      "objects/manmade/common_furniture/barrels/barrel_a.cgf",
    },
  },
  camp = {
    label = { en = "Campfire", ru = "Костёр" }, cost = 0,
    parts = {
      "objects/manmade/task_specific_props/food_processing/cooking/fireplace_wood_a.cgf",
      "objects/manmade/common_furniture/crates/crate_low_a.cgf",
    },
  },
  palisade = {
    label = { en = "Palisade wall", ru = "Частокол" }, cost = 0,
    parts = { "objects/manmade/structures/defensive/walls/palisade/palisade_wall_a_v1.cgf" },
  },
  tower = {
    label = { en = "Watch tower", ru = "Сторожевая башня" }, cost = 0,
    parts = { "objects/manmade/structures/defensive/castles/unique/trosky/panna_wooden_tower.cgf" },
  },
  forge = {
    label = { en = "Field forge", ru = "Полевая кузня" }, cost = 0,
    parts = {
      "objects/manmade/task_specific_props/metal_industry/smithing/anvil.cgf",
      "objects/manmade/task_specific_props/metal_industry/smithing/forge_small_a.cgf",
    },
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

local function open_build(pid)
  if not isAdmin(pid) then
    SendClientMessage(pid, COLOR_RED, "only the crown's servants may raise structures.")
    return
  end
  open_frame(pid, "build")
  local lang = lang_of(pid)
  local list = {}
  for key, b in pairs(BUILD_CATALOG) do
    list[#list + 1] = { key = key, label = b.label[lang] or b.label.en, cost = b.cost }
  end
  table.sort(list, function(a, b) return a.cost < b.cost end)
  SendPlayerWebMessage(pid, "build", { lang = lang, structures = list })
end

local function build_place(pid, name)
  if not isAdmin(pid) then return end
  name = (name or ""):lower()
  local spec = BUILD_CATALOG[name]
  if not spec then return end
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
  SendClientMessage(pid, COLOR_YELLOW, "it rises before you - a preview for 60 seconds.")
  local t = SetTimer(function() build_cancel(pid) end, 60000, false)
  build_preview[pid] = { name = name, ids = ids, timer = t }
  open_build(pid)
end

RegisterCommand("build", function(pid)
  open_build(pid)
end, { help = "raise a ready structure (admins)" })

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
  elseif name == "fw.menu" then
    open_menu(pid)
  end
end

-- a swing struck the level: work veins live here, combat lives elsewhere - never blocked
function OnPlayerHitScenery(pid, hit)
  job_on_hit(pid, hit)
end

function OnPlayerUseMapObject(pid, id)
  local site_id = job_interactions[id]
  local site = site_id and job_sites[site_id]
  if site then
    Log(fmt("feudalwars: E on map object %d -> site %s", id, site_id))
    job_work_start(pid, site.kind, site_id)
  end
end

function OnPlayerInteract(pid, id)
  local site_id = job_interactions[id]
  local site = site_id and job_sites[site_id]
  if site then
    Log(fmt("feudalwars: E on interaction %d -> site %s", id, site_id))
    job_work_start(pid, site.kind, site_id)
  else
    Log(fmt("feudalwars: E on unknown interaction %d (known: %d)", id, #job_interactions))
  end
end

function OnPlayerDisconnect(pid, reason)
  build_cancel(pid, true)
  save_money(pid)
  job_hit_cd[pid] = nil
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
local function close_frame(pid, frame)
  DestroyPlayerWebFrame(pid, frame)
  SetPlayerWebFocus(pid, frame, false, false)
  SetPlayerCursor(pid, false)
end

local function web_event(pid, name, data)

  if name == "menu.cursor" then
    SetPlayerCursor(pid, true)
    SetPlayerWebFocus(pid, "menu", true, true)
  elseif name == "menu.lang" then
    local l = tostring(data.lang or ""):lower()
    if LANGS[l] then
      player_lang[pid] = l
      SendClientMessage(pid, COLOR_SERVER, STR[l].lang_saved)
      open_menu(pid)
    end
  elseif name == "menu.close" then
    close_frame(pid, "menu")
  elseif name == "menu.run" then
    menu_do(pid, tostring(data.action or data.cmd or ""))
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
  elseif name == "auction.close" then
    close_frame(pid, "auction")
  elseif name == "auction.sell" then
    local res = tostring(data.res or "")
    local amount = math.max(1, math.floor(tonumber(data.amount) or 1))
    local price = math.max(1, math.floor(tonumber(data.price) or 1))
    local rdef = RES[res]
    if not rdef then
      SendClientMessage(pid, COLOR_RED, "no such resource.")
    elseif TakePlayerItem(pid, "fw_" .. res, amount) then
      local id = auction_next
      auction_next = auction_next + 1
      local seller = accounts[pid] and accounts[pid].name or GetPlayerName(pid):lower()
      auction_lots[id] = { id = id, seller = seller, res = res, amount = amount, price = price }
      if db then
        db:Execute("INSERT INTO auction (id, seller, res, amount, price) VALUES (@i, @s, @r, @a, @p)",
          { i = id, s = seller, r = res, a = amount, p = price }, function() end)
      end
      SendClientMessage(pid, COLOR_YELLOW, fmt("lot #%d: %d x %s for %d groschen.", id, amount, rdef.name[lang_of(pid)] or res, price))
      open_auction(pid)
    else
      SendClientMessage(pid, COLOR_RED, "you don't hold that many.")
      open_auction(pid)
    end
  elseif name == "auction.buy" then
    local id = math.floor(tonumber(data.id) or 0)
    local lot = auction_lots[id]
    if not lot then
      SendClientMessage(pid, COLOR_RED, "no such lot.")
    elseif GetPlayerMoney(pid) < lot.price then
      SendClientMessage(pid, COLOR_RED, "not enough groschen.")
    else
      GivePlayerMoney(pid, -lot.price)
      save_money(pid)
      GivePlayerItem(pid, "fw_" .. lot.res, lot.amount)
      -- pay the seller if they are around, else their purse waits in the database
      local spid = GetPlayerId(lot.seller)
      if spid then
        GivePlayerMoney(spid, lot.price)
        save_money(spid)
        notice(spid, fmt("your lot #%d sold for %d groschen.", id, lot.price))
      elseif db then
        db:Execute("UPDATE players SET money = money + @m WHERE name = @n", { m = lot.price, n = lot.seller }, function() end)
      end
      auction_lots[id] = nil
      if db then db:Execute("DELETE FROM auction WHERE id = @i", { i = id }, function() end) end
      SendClientMessage(pid, COLOR_YELLOW, fmt("lot #%d is yours.", id))
      open_auction(pid)
    end
  elseif name == "auction.cancel" then
    local id = math.floor(tonumber(data.id) or 0)
    local lot = auction_lots[id]
    local me = accounts[pid] and accounts[pid].name
    if lot and (lot.seller == me or isAdmin(pid)) then
      GivePlayerItem(pid, "fw_" .. lot.res, lot.amount)
      auction_lots[id] = nil
      if db then db:Execute("DELETE FROM auction WHERE id = @i", { i = id }, function() end) end
      open_auction(pid)
    end
  elseif name == "build.close" then
    close_frame(pid, "build")
  elseif name == "build.place" then
    build_place(pid, data.name)
  elseif name == "build.cancel" then
    build_cancel(pid)
    open_build(pid)
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
