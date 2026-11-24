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
    nodes = 4, node_hp = 5, node_label = "the ore vein",
    pay = 2, skill_pay_bonus = 1,
    icon = "troskyQuarry", icon_num = 48,
    tools = { "pickaxe", "hammer", "normalHammer", "shovel" },
    tool_names = "a pickaxe, hammer or shovel",
    vein_mesh = "objects/natural/rocks/boulder_granite_a.cgf", vein_scale = 1.2,
    hit_effect = "collisions.rock_hit",
    hit_sound = "special_blacksmith_hammer_anvil",
    drops = { { res = "stone", w = 45 }, { res = "coal", w = 30 }, { res = "iron", w = 18 }, { res = "silver", w = 5 }, { res = "gold", w = 2 } },
  },
  farm = {
    label = "the field", skill = "farming",
    nodes = 5, node_hp = 3, node_label = "the sheaf",
    pay = 2, skill_pay_bonus = 1,
    icon = "miller", icon_num = 21,
    tools = { "shovel", "hoe", "sickle", "scythe" },
    tool_names = "a shovel, hoe or sickle",
    vein_mesh = "objects/manmade/common_furniture/crates/crate_low_a.cgf", vein_scale = 0.9,
    hit_effect = "collisions.dirt_hit",
    hit_sound = "special_digging",
    drops = { { res = "grain", w = 100 } },
  },
  forest = {
    label = "the logging camp", skill = "woodcutting",
    nodes = 4, node_hp = 4, node_label = "the trunk",
    pay = 2, skill_pay_bonus = 1,
    icon = "camp", icon_num = 38,
    tools = { "lumberjack_axe", "axe", "woodaxe", "hatchet" },
    tool_names = "a woodcutter's axe",
    vein_mesh = "objects/natural/trees/oak/oak_trunk_a.cgf", vein_scale = 1.0,
    hit_effect = "collisions.wood_hit",
    hit_sound = "special_wood_chop",
    drops = { { res = "wood", w = 100 } },
  },
}

-- forward declarations (assigned further down; used by the node core above)
local lang_of, arch_open, bp_load_all, close_frame, isAdmin
local db, fmt, earn, save_money, job_skill_of, job_skill_up

-- ---------------------------------------------------------------- breakable objects
-- One registry for every thing in the world that can be struck and breaks into
-- resources: the works' veins and the rock pieces of a built blueprint. A node
-- remembers where it stands, how much it holds, what it drops, and when it grows
-- back. Nodes are rebuilt from the database on every boot, so their state survives.

local nodes = {}          -- key -> node
local node_by_entity = {} -- entity/map-object id -> node key
local NODE_RESPAWN = 300  -- seconds before a worked-out node comes back

local function node_hash(kind, x, y)
  return fmt("%s_%d_%d", kind, math.floor(x), math.floor(y))
end

local function terrain_z(x, y, fallback)
  local ok, h = pcall(GetTerrainHeight, x, y)
  if ok and type(h) == "number" and h > -100 then return h end
  ok, h = pcall(GetGroundZ, x, y, 200.0)
  if ok and type(h) == "number" and h > -100 then return h end
  return fallback or 0
end

local function node_persist(n)
  if not db then return end
  db:Execute("INSERT INTO fw_nodes (id, kind, x, y, z, hp, hp_max, res, respawn_at, mapid) " ..
    "VALUES (@i, @k, @x, @y, @z, @h, @hm, @r, @ra, @m) " ..
    "ON DUPLICATE KEY UPDATE kind=@k2, x=@x2, y=@y2, z=@z2, hp=@h2, hp_max=@hm2, res=@r2, respawn_at=@ra2, mapid=@m2",
    { i = n.key, k = n.kind, x = n.x, y = n.y, z = n.z, h = n.hp, hm = n.hp_max, r = n.res, ra = n.respawn_at or 0, m = n.mapid or 0,
      k2 = n.kind, x2 = n.x, y2 = n.y, z2 = n.z, h2 = n.hp, hm2 = n.hp_max, r2 = n.res, ra2 = n.respawn_at or 0, m2 = n.mapid or 0 },
    function() end)
end

-- a node's visual: a prop (works) or a map object (built blueprint pieces)
local function node_show(n)
  if n.entity then return end
  if n.is_map then
    -- a blueprint piece: a real map object, recreated if it was broken
    local id = CreateMapObject(n.mesh, n.x, n.y, n.z, { yaw = n.yaw or 0, scale = n.scale, persist = true, solid = true })
    if id then
      n.mapid = id
      n.entity = id
      node_by_entity[id] = n.key
      node_persist(n)
    end
    return
  end
  if n.mesh then
    local id = CreateProp(n.mesh, n.x, n.y, n.z, n.yaw or 0, n.scale or 1, false, nil)
    if id then
      n.entity = id
      node_by_entity[id] = n.key
      pcall(SetEntityPrompt, id, n.prompt or "Strike")
    end
  end
end

local function node_hide(n)
  if not n.entity then return end
  if n.is_map then
    pcall(DeleteMapObject, n.entity)
  else
    pcall(DestroyEntity, n.entity)
  end
  node_by_entity[n.entity] = nil
  n.entity = nil
end

local function node_break(n, pid)
  n.hp = 0
  n.respawn_at = GetServerTime() + NODE_RESPAWN * 1000
  node_hide(n)
  node_persist(n)
  -- the lump falls where it stood, and the striker takes it
  if pid then
    local rdef = RES[n.res]
    if rdef then
      GivePlayerItem(pid, "fw_" .. n.res, n.yield or 1)
      SendClientMessage(pid, COLOR_YELLOW, fmt("%s breaks apart - %d %s to your bag.",
        n.label or "the stone", n.yield or 1, rdef.name[lang_of(pid)] or rdef.name.en))
    end
    local def = JOBS[n.kind]
    if def then
      local skill = job_skill_of(pid, def.skill)
      local pay = def.pay + skill * def.skill_pay_bonus
      local total = skill + 1
      if total >= 10 and total % 10 == 0 then
        local nl = job_skill_up(pid, def.skill)
        SendClientMessage(pid, COLOR_YELLOW, fmt("%s skill raised to %d.", def.skill, nl))
      else
        job_skill_up(pid, def.skill)
      end
      earn(pid, pay)
      save_money(pid)
    end
  end
  if n.x then
    pcall(SpawnEffect, "collisions.rock_hit", n.x, n.y, n.z, 1.4)
    pcall(PlaySound, "special_rock_fall", n.x, n.y, n.z, 2)
  end
end

local function node_damage(n, pid, amount)
  if n.hp <= 0 then return end
  n.hp = n.hp - amount
  if n.hp <= 0 then node_break(n, pid) else node_persist(n) end
end

local function node_nearest(x, y, z, radius)
  local best, bestd = nil, radius or 3.0
  for _, n in pairs(nodes) do
    if n.hp > 0 then
      local dx, dy, dz = n.x - x, n.y - y, n.z - z
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d < bestd then best, bestd = n, d end
    end
  end
  return best
end

local function node_define(spec)
  local key = spec.key or node_hash(spec.kind or "node", spec.x, spec.y)
  local n = nodes[key]
  if n then
    n.x, n.y, n.z = spec.x, spec.y, spec.z
    n.mesh = spec.mesh or n.mesh
    n.mapid = spec.mapid or n.mapid
    return n
  end
  n = {
    key = key, kind = spec.kind or "node", x = spec.x, y = spec.y, z = spec.z,
    mesh = spec.mesh, scale = spec.scale or 1, yaw = spec.yaw or 0,
    hp = spec.hp or 5, hp_max = spec.hp or 5, res = spec.res or "stone",
    yield = spec.yield or 1, label = spec.label, prompt = spec.prompt,
    mapid = spec.mapid, is_map = spec.is_map or false, respawn_at = spec.respawn_at or 0,
  }
  nodes[key] = n
  node_show(n)
  return n
end

-- define a node that already has its object in the world; do not spawn another
local function node_define_noshow(spec)
  local key = spec.key or node_hash(spec.kind or "node", spec.x, spec.y)
  local n = nodes[key]
  if n then return n end
  n = {
    key = key, kind = spec.kind or "node", x = spec.x, y = spec.y, z = spec.z,
    mesh = spec.mesh, scale = spec.scale or 1, yaw = spec.yaw or 0,
    hp = spec.hp or 5, hp_max = spec.hp or 5, res = spec.res or "stone",
    yield = spec.yield or 1, label = spec.label, prompt = spec.prompt,
    mapid = spec.mapid, is_map = spec.is_map or false, respawn_at = spec.respawn_at or 0,
  }
  nodes[key] = n
  return n
end

local job_sites = {}    -- id -> { id, kind, x, y, z, stock, marker, mapicon }
local job_skills = {}    -- pid -> { mining = n, farming = n, woodcutting = n }
local job_hit_cd = {}   -- pid -> earliest next hit time (anti-macro)
local arch_interaction, architect_npc = nil, nil   -- the builder's use point and actor
local icon_types = {}   -- map icon type names the level knows, filled in init

-- a site's compass marker and map icon
local function site_show(site)
  local def = JOBS[site.kind]
  if not def then return end
  if site.marker then pcall(DestroyMarker, site.marker) site.marker = nil end
  if site.mapicon then pcall(DeleteMapIcon, site.mapicon) site.mapicon = nil end
  local mid = CreateMarker(site.x, site.y, site.z + 1.0, MARKER_QUEST, 0, site.label or def.label)
  if mid then site.marker = mid ShowMarkerForAll(mid) end
  local opts
  if def.icon and icon_types[def.icon] then
    opts = { type = def.icon, name = site.label or def.label }
  else
    opts = { icon = def.icon_num or 0, name = site.label or def.label }
  end
  local iid = CreateMapIcon(site.x, site.y, site.z, opts)
  if iid then site.mapicon = iid end
end

-- a site raises a handful of breakable nodes around its centre
local function site_raise_nodes(site)
  local def = JOBS[site.kind]
  if not def then return end
  local count = def.nodes or 4
  for i = 1, count do
    local ang = (i * 2 * math.pi / count)
    local nx, ny = site.x + math.cos(ang) * 2.2, site.y + math.sin(ang) * 2.2
    node_define({
      key = node_hash(site.id .. "_" .. i, nx, ny),
      kind = site.kind, x = nx, y = ny, z = terrain_z(nx, ny, site.z),
      mesh = def.vein_mesh, scale = def.vein_scale or 1.2,
      hp = def.node_hp or 4, res = job_roll_drop(def), yield = 1,
      label = def.node_label or "the vein", prompt = "Strike (" .. (def.tool_names or "tool") .. ")",
    })
  end
end

job_skill_of = function(pid, skill)
  local s = job_skills[pid]
  return (s and s[skill]) or 0
end

job_skill_up = function(pid, skill)
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
  local standing = 0
  for _, n in pairs(nodes) do
    if n.kind == site.kind and n.hp > 0 then
      local dx, dy = n.x - site.x, n.y - site.y
      if dx * dx + dy * dy < 100 then standing = standing + 1 end
    end
  end
  local skill = job_skill_of(pid, def.skill)
  local what = site.kind == "mine" and "rocks" or (site.kind == "forest" and "trunks" or "sheaves")
  if standing == 0 then
    SendClientMessage(pid, COLOR_RED, fmt("%s is worked out - the %s grow back with time.", site.label or def.label, what))
    return
  end
  SendClientMessage(pid, COLOR_YELLOW, fmt("%s: %d %s here. Hold %s and strike them. Your %s: %d.",
    site.label or def.label, standing, what, def.tool_names, def.skill, skill))
end

-- a swing struck the level: work veins and blueprint rocks live here; combat is never blocked
local function job_on_hit(pid, hit)
  if not hit or not hit.x then return end
  local now = GetServerTime()
  if job_hit_cd[pid] and now < job_hit_cd[pid] then return end
  job_hit_cd[pid] = now + 700
  local n = node_nearest(hit.x, hit.y, hit.z, 4.0)
  if not n then return end
  local def = JOBS[n.kind]
  local tool_ok = true
  if def and def.tools then tool_ok = job_has_tool(pid, def) end
  if not tool_ok then
    SendClientMessage(pid, COLOR_RED, fmt("you need %s in your hands.", def.tool_names))
    return
  end
  pcall(SpawnEffect, (def and def.hit_effect) or "collisions.rock_hit", hit.x, hit.y, hit.z, 1.0)
  pcall(PlaySound, (def and def.hit_sound) or "special_blacksmith_hammer_anvil", hit.x, hit.y, hit.z, 2)
  node_damage(n, pid, 1)
  if n.hp > 0 then
    SendClientMessage(pid, COLOR_SERVER, fmt("crack... (%d/%d)", n.hp_max - n.hp, n.hp_max))
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
  local px, py, pz = GetPlayerPos(pid)
  local lines = {}
  for _, site in pairs(job_sites) do
    local def = JOBS[site.kind]
    if def then
      local dx, dy = site.x - px, site.y - py
      local dist = math.sqrt(dx * dx + dy * dy)
      local standing = 0
      for _, n in pairs(nodes) do
        if n.kind == site.kind and n.hp > 0 then
          local ax, ay = n.x - site.x, n.y - site.y
          if ax * ax + ay * ay < 100 then standing = standing + 1 end
        end
      end
      local skill = job_skill_of(pid, def.skill)
      lines[#lines + 1] = fmt("%s - %d m, %d node(s), hold %s, your %s %d",
        site.label or def.label, math.floor(dist), standing, def.tool_names, def.skill, skill)
    end
  end
  for _, l in ipairs(lines) do SendClientMessage(pid, COLOR_SERVER, l) end
end

local RANKS = { "lord", "steward", "retainer" }

local ADMIN_NAMES = { "minsk" }   -- promoted on connect; extend or move into the database

db = GetDatabase()

local houses = {}         -- name -> { treasury, prestige, war, war_started, score, members = {lowerName = {rank}} }
local playerHouse = {}    -- pid -> house name
local playerRank = {}     -- pid -> rank index
local accounts = {}       -- pid -> { name, money, known }

fmt = function(...) return string.format(...) end

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

save_money = function(pid)
  if not db or not accounts[pid] or not accounts[pid].known then return end
  accounts[pid].money = GetPlayerMoney(pid)
  db:Execute("UPDATE players SET money = @m WHERE name = @n",
    { m = accounts[pid].money, n = accounts[pid].name }, function() end)
end

earn = function(pid, amount)
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
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS fw_nodes (id VARCHAR(64) PRIMARY KEY, kind VARCHAR(24) NOT NULL DEFAULT 'node', x DOUBLE NOT NULL DEFAULT 0, y DOUBLE NOT NULL DEFAULT 0, z DOUBLE NOT NULL DEFAULT 0, hp INT NOT NULL DEFAULT 4, hp_max INT NOT NULL DEFAULT 4, res VARCHAR(16) NOT NULL DEFAULT 'stone', respawn_at BIGINT NOT NULL DEFAULT 0, mapid INT NOT NULL DEFAULT 0)")
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS fw_blueprints (name VARCHAR(48) PRIMARY KEY, parts MEDIUMTEXT, cost INT NOT NULL DEFAULT 0, author VARCHAR(32))")
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

  -- Work sites spread over Kuttenberg, each in a place that suits its trade:
  -- a quarry by the hills, fields by the farmland, logging in the woods. Only
  -- the coordinates are fixed; z comes from the terrain, so a site always sits on
  -- the ground. Admins can re-place any site in the game with /jobsite.
  local SITE_PLAN = {
    { id = "mine_quarry",   kind = "mine",   x = 2870.0, y = 2960.0, label = "Kuttenberg quarry" },
    { id = "mine_hills",    kind = "mine",   x = 3130.0, y = 800.0,  label = "Hillside adit" },
    { id = "farm_lowlands", kind = "farm",   x = 1520.0, y = 1990.0, label = "Lowland fields" },
    { id = "farm_mill",     kind = "farm",   x = 3060.0, y = 770.0,  label = "Mill fields" },
    { id = "forest_woods",  kind = "forest", x = 660.0,  y = 3260.0, label = "North woods" },
    { id = "forest_grove",  kind = "forest", x = 1740.0, y = 2810.0, label = "Old grove" },
  }

  local mapinfo = GetMapInfo()
  Log(fmt("feudalwars: map folder=%s readOnly=%s objects=%s (level %s)",
    tostring(mapinfo and mapinfo.folder), tostring(mapinfo and mapinfo.readOnly),
    tostring(mapinfo and mapinfo.objects), GetLevel()))
  for _, t in ipairs(GetMapIconTypes() or {}) do icon_types[t.name or ""] = true end

  local function site_place(id, kind, x, y, label)
    local z = terrain_z(x, y, sz)
    local site = job_sites[id] or { id = id }
    site.kind, site.x, site.y, site.z, site.label = kind, x, y, z, label or JOBS[kind].label
    job_sites[id] = site
    if db then
      db:Execute("INSERT INTO job_sites (id, kind, x, y, z, stock) VALUES (@i, @k, @x, @y, @z, 0) " ..
        "ON DUPLICATE KEY UPDATE kind=@k2, x=@x2, y=@y2, z=@z2",
        { i = id, k = kind, x = x, y = y, z = z, k2 = kind, x2 = x, y2 = y, z2 = z }, function() end)
    end
    site_show(site)
    site_raise_nodes(site)
  end

  -- load admin-mapped sites from the database first; else use the plan
  local have_sites = next(job_sites) ~= nil
  if not have_sites then
    for _, p in ipairs(SITE_PLAN) do site_place(p.id, p.kind, p.x, p.y, p.label) end
  else
    for _, site in pairs(job_sites) do
      site_show(site)
      site_raise_nodes(site)
    end
  end

  -- restore saved nodes (state survives a restart)
  if db then
    local nrows = db:QuerySync("SELECT id, kind, x, y, z, hp, hp_max, res, respawn_at, mapid FROM fw_nodes")
    if nrows then
      for _, r in ipairs(nrows) do
        local def = JOBS[r.kind]
        local n = node_define({
          key = r.id, kind = r.kind, x = r.x, y = r.y, z = r.z,
          mesh = def and def.vein_mesh, scale = def and (def.vein_scale or 1.2),
          hp = r.hp_max or 4, res = r.res or "stone",
          label = def and (def.node_label or "the vein"), mapid = r.mapid,
          respawn_at = r.respawn_at or 0,
        })
        n.hp = r.hp or n.hp_max
        if n.hp <= 0 then
          if n.entity then pcall(DestroyEntity, n.entity) node_by_entity[n.entity] = nil n.entity = nil end
        end
      end
      Log("feudalwars: loaded " .. #nrows .. " node(s)")
    end
  end

  -- node growth: a broken node returns when its time comes
  SetTimer(function()
    local now = GetServerTime()
    for _, n in pairs(nodes) do
      if n.hp <= 0 and n.respawn_at > 0 and now >= n.respawn_at then
        n.hp = n.hp_max
        n.respawn_at = 0
        node_persist(n)
        node_show(n)
      end
    end
  end, 5000, true)

  local shop = CreateShop("The King's Provisioner", 0.5, -1)
  SetShopItem(shop, "torch", 10, -1)
  SetShopItem(shop, "bandage", 25, -1)
  SetShopItem(shop, "bread", 5, -1)
  SetShopItem(shop, "water", 3, -1)
  CreateVendor(shop, "provisioner", sx + 2.0, sy + 2.0, sz, syaw + 180.0, "Provisioner Bohush", nil, nil)

  -- the architect: an NPC by the spawn whose use key opens the blueprint workshop
  bp_load_all()
  local architect = CreateActor(nil, sx + 4.0, sy + 3.0, sz, 0, "Master Builder Havel", nil, "none", nil)
  if architect then
    SetActorPrompt(architect, "Plan a structure")
    architect_npc = architect
  end
  local arch_spot = CreateInteraction(sx + 4.0, sy + 3.0, sz, "Plan a structure", 2.0, nil)
  if arch_spot then arch_interaction = arch_spot end

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
    menu_keys = "E — ask about work · F2 — this menu · Esc — close",
    lang_saved = "Language: English.",
  },
  ru = {
    menu_title = "Феодальные войны",
    menu_keys = "E — спросить о работе · F2 — это меню · Esc — закрыть",
    lang_saved = "Язык: русский.",
  },
}

lang_of = function(pid) return player_lang[pid] or "en" end

local function open_menu(pid)
  open_frame(pid, "menu")
  local lang = lang_of(pid)
  local s = STR[lang] or STR.en
  local cards = {}
  local function add(section, id, title, desc, action)
    cards[#cards + 1] = { id = id, section = section, title = title, desc = desc, action = action }
  end
  local L = MENU_TEXT[lang] or MENU_TEXT.en
  add("main", "me", L.me_t, L.me_d, "me")
  add("main", "work", L.work_t, L.work_d, "job")
  add("main", "auction", L.auction_t, L.auction_d, "auction")
  add("world", "goto_mine", L.goto_mine_t, L.goto_mine_d, "goto_mine")
  add("world", "goto_farm", L.goto_farm_t, L.goto_farm_d, "goto_farm")
  add("world", "goto_forest", L.goto_forest_t, L.goto_forest_d, "goto_forest")
  add("world", "goto_spawn", L.goto_spawn_t, L.goto_spawn_d, "goto_spawn")
  add("work", "skills", L.skills_t, L.skills_d, "skills")
  add("work", "kit", L.kit_t, L.kit_d, "kit")
  add("house", "hall", L.hall_t, L.hall_d, "hall")
  add("trade", "trade", L.trade_t, L.trade_d, "auction")
  add("build", "build", L.build_t, L.build_d, "build")
  if isAdmin(pid) then
    add("build", "editor", L.editor_t, L.editor_d, "editor")
  end
  SendPlayerWebMessage(pid, "menu", {
    lang = lang, title = s.menu_title, keys = s.menu_keys, cards = cards,
  })
end

-- menu card texts (titles + descriptions) per language
local MENU_TEXT = {
  en = {
    me_t = "My character", me_d = "Purse, house and standing",
    work_t = "Work the veins", work_d = "Strike rocks, trunks and sheaves for ore, wood and grain",
    auction_t = "The auction", auction_d = "Sell your goods, buy from other players",
    goto_mine_t = "To the quarries", goto_mine_d = "Kuttenberg quarry and the hillside adit",
    goto_farm_t = "To the fields", goto_farm_d = "Lowland and mill fields",
    goto_forest_t = "To the woods", goto_forest_d = "The north woods and the old grove",
    goto_spawn_t = "To the town square", goto_spawn_d = "Back to the spawn",
    skills_t = "My skills", skills_d = "Mining, farming and woodcutting",
    kit_t = "Borrow a tool", kit_d = "The foreman lends the right tool for the nearest site",
    hall_t = "House hall", hall_d = "Roster, treasury and wars",
    trade_t = "Market", trade_d = "Open the auction house",
    build_t = "The architect", build_d = "Lay out, save and stamp blueprints (admins)",
    editor_t = "Map editor", editor_d = "The game's own editor: fly, place meshes",
  },
  ru = {
    me_t = "Мой персонаж", me_d = "Кошелёк, дом и положение",
    work_t = "Работать на жилах", work_d = "Бей камни, стволы и снопы — руда, дерево, зерно",
    auction_t = "Торг", auction_d = "Продай товар, купи у других игроков",
    goto_mine_t = "К каменоломням", goto_mine_d = "Куттенбергская каменоломня и горный штрек",
    goto_farm_t = "К полям", goto_farm_d = "Низинные и мельничные поля",
    goto_forest_t = "К лесам", goto_forest_d = "Северный лес и старая роща",
    goto_spawn_t = "На площадь", goto_spawn_d = "Обратно к точке появления",
    skills_t = "Мои навыки", skills_d = "Горное дело, земледелие, лесорубка",
    kit_t = "Одолжить инструмент", kit_d = "Бригадир выдаст нужный инструмент у ближней точки",
    hall_t = "Зал дома", hall_d = "Люди, казна и войны",
    trade_t = "Торг", trade_d = "Открыть торговый дом",
    build_t = "Зодчий", build_d = "Разложи, сохрани и ставь чертежи (админы)",
    editor_t = "Редактор карты", editor_d = "Встроенный редактор: полёт, объекты",
  },
}

-- menu buttons act through UI: open the frame, never send you to the chat
local function menu_do(pid, action)
  if action == "menu" then open_menu(pid) return end
  close_frame(pid, "menu")
  if action == "me" then open_me(pid)
  elseif action == "hall" then
    if playerHouse[pid] then open_hall(pid)
    else SendClientMessage(pid, COLOR_RED, "you serve no lord - ask a house to take you in.") end
  elseif action == "auction" or action == "trade" then open_auction(pid)
  elseif action == "build" then arch_open(pid)
  elseif action == "job" then job_status(pid)
  elseif action == "skills" then
    local s = job_skills[pid] or {}
    SendClientMessage(pid, COLOR_SERVER, fmt("skills: mining %d, farming %d, woodcutting %d.",
      s.mining or 0, s.farming or 0, s.woodcutting or 0))
  elseif action == "kit" then
    local px, py = GetPlayerPos(pid)
    local best, bestd = nil, 30.0
    for _, site in pairs(job_sites) do
      local dx, dy = site.x - px, site.y - py
      local d = math.sqrt(dx * dx + dy * dy)
      if d < bestd then best, bestd = site, d end
    end
    if best then
      local def = JOBS[best.kind]
      local tool = def.tools and def.tools[1]
      if tool then
        GivePlayerItem(pid, tool, 1)
        SendClientMessage(pid, COLOR_YELLOW, fmt("the foreman lends you %s.", def.tool_names))
      end
    else
      SendClientMessage(pid, COLOR_RED, "no work site near enough.")
    end
  elseif action == "goto_mine" or action == "goto_farm" or action == "goto_forest" then
    local want = action:sub(6)
    local px, py = GetPlayerPos(pid)
    local best, bestd = nil, 1e9
    for _, site in pairs(job_sites) do
      if site.kind == want then
        local dx, dy = site.x - px, site.y - py
        local d = dx * dx + dy * dy
        if d < bestd then best, bestd = site, d end
      end
    end
    if best then SetPlayerPos(pid, best.x + 2.0, best.y, best.z, 0) end
  elseif action == "goto_spawn" then
    local sp = GetSpawnPoints("town")[1]
    if sp then SetPlayerPos(pid, sp.x + 2.0, sp.y, sp.z, 0) end
  elseif action == "editor" then
    if isAdmin(pid) then
      if IsPlayerWebReady(pid) then SetPlayerEditor(pid, "admin")
      else SendClientMessage(pid, COLOR_RED, "the editor needs the web layer: enable server interfaces in the launcher options and relog.") end
    end
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

RegisterCommand("auction", function(pid)
  open_auction(pid)
end, { help = "the market: sell and buy resources" })

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

isAdmin = function(pid) return IsPlayerAdmin(pid) end

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
  site.kind, site.x, site.y, site.z = kind, px, py, terrain_z(px, py, pz)
  job_sites[id] = site
  if db then
    db:Execute("INSERT INTO job_sites (id, kind, x, y, z, stock) VALUES (@i, @k, @x, @y, @z, 0) " ..
      "ON DUPLICATE KEY UPDATE kind = @k2, x = @x2, y = @y2, z = @z2",
      { i = id, k = kind, x = px, y = py, z = site.z, k2 = kind, x2 = px, y2 = py, z2 = site.z }, function() end)
  end
  site_show(site)
  site_raise_nodes(site)
  SendClientMessage(pid, COLOR_YELLOW, fmt("work site %s (%s) mapped here.", id, kind))
  Log(fmt("feudalwars: jobsite %s mapped to %.1f %.1f %.1f", id, px, py, site.z))
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

-- ---------------------------------------------------------------- blueprints (the architect)
-- A blueprint is a set of parts saved from the world: the architect lays out
-- real game objects beside the player, the player strikes a rock to break it,
-- and what stands is saved under a name. Then it is stamped anywhere, and every
-- copy carries its own breakable nodes - cut a rock in any copy and it drops
-- resources there.

local BUILD_CATALOG = {
  tent = {
    label = { en = "Campaign tent", ru = "Походная палатка" },
    parts = { "objects/manmade/structures/living/tents/tent_big_fancy_a.cgf" },
  },
  stall = {
    label = { en = "Market stall", ru = "Торговая лавка" },
    parts = {
      "objects/manmade/task_specific_props/trade/merge_market_bread_stand.cgf",
      "objects/manmade/common_furniture/barrels/barrel_a.cgf",
    },
  },
  camp = {
    label = { en = "Campfire", ru = "Костёр" },
    parts = {
      "objects/manmade/task_specific_props/food_processing/cooking/fireplace_wood_a.cgf",
      "objects/manmade/common_furniture/crates/crate_low_a.cgf",
    },
  },
  palisade = {
    label = { en = "Palisade wall", ru = "Частокол" },
    parts = { "objects/manmade/structures/defensive/walls/palisade/palisade_wall_a_v1.cgf" },
  },
  tower = {
    label = { en = "Watch tower", ru = "Сторожевая башня" },
    parts = { "objects/manmade/structures/defensive/castles/unique/trosky/panna_wooden_tower.cgf" },
  },
  forge = {
    label = { en = "Field forge", ru = "Полевая кузня" },
    parts = {
      "objects/manmade/task_specific_props/metal_industry/smithing/anvil.cgf",
      "objects/manmade/task_specific_props/metal_industry/smithing/forge_small_a.cgf",
    },
  },
  rock_pile = {
    label = { en = "Rock pile (mineable)", ru = "Нагромождение камней (добыча)" },
    parts = { "objects/natural/rocks/boulder_granite_a.cgf", "objects/natural/rocks/boulder_granite_a.cgf" },
    nodes = true,   -- its rocks are breakable on every copy
  },
}

local blueprints = {}    -- name -> { name, parts = {{mesh,x,y,z,yaw,scale,node}}, author }
local arch_draft = {}    -- pid -> { name, ids = {map object ids} }

local function bp_save_to_db(bp)
  if not db then return end
  db:Execute("INSERT INTO fw_blueprints (name, parts, author) VALUES (@n, @p, @a) " ..
    "ON DUPLICATE KEY UPDATE parts=@p2, author=@a2",
    { n = bp.name, p = JsonEncode(bp.parts), a = bp.author or "",
      p2 = JsonEncode(bp.parts), a2 = bp.author or "" }, function() end)
end

bp_load_all = function()
  if not db then return end
  local rows = db:QuerySync("SELECT name, parts, author FROM fw_blueprints")
  if not rows then return end
  for _, r in ipairs(rows) do
    local ok, parts = pcall(JsonDecode, r.parts or "[]")
    if ok and type(parts) == "table" then
      blueprints[r.name] = { name = r.name, parts = parts, author = r.author }
    end
  end
  Log("feudalwars: loaded " .. #rows .. " blueprint(s)")
end

local function arch_draft_clear(pid)
  local d = arch_draft[pid]
  if not d then return end
  for _, id in ipairs(d.ids or {}) do
    pcall(DeleteMapObject, id)
    local key = node_by_entity[id]
    if key then nodes[key] = nil node_by_entity[id] = nil end
  end
  arch_draft[pid] = nil
end

-- the architect lays a draft: catalogue parts, or a copy of a blueprint
local function arch_draft_new(pid, name)
  arch_draft_clear(pid)
  local px, py, pz = GetPlayerPos(pid)
  local yaw = math.floor(GetPlayerYaw(pid) / 90) * 90
  local ids = {}
  local spec = BUILD_CATALOG[name]
  if spec then
    for i, mesh in ipairs(spec.parts) do
      local ox = math.cos(math.rad(yaw)) * ((i - 1) * 2.2)
      local oy = math.sin(math.rad(yaw)) * ((i - 1) * 2.2)
      local id = CreateMapObject(mesh, px + ox, py + oy, -1, { yaw = yaw, persist = false, solid = true })
      if id then
        ids[#ids + 1] = id
        if spec.nodes then
          -- the part is a breakable node in every copy; bind the existing object
          local mo = GetMapObject(id)
          if mo then
            local nkey = node_hash("bp_" .. id, mo.x, mo.y)
            local n = node_define_noshow({
              key = nkey, kind = "mine", x = mo.x, y = mo.y, z = mo.z,
              mesh = mo.mesh, is_map = true, mapid = id, yaw = mo.yaw, scale = mo.scale,
              hp = 5, res = job_roll_drop(JOBS.mine), yield = 1,
              label = "the boulder", prompt = "Strike the boulder",
            })
            n.entity = id
            node_by_entity[id] = n.key
          end
        end
      end
    end
  end
  if #ids == 0 then
    SendClientMessage(pid, COLOR_RED, "the ground refused the draft here (no map?).")
    return
  end
  arch_draft[pid] = { name = name, ids = ids }
  SendClientMessage(pid, COLOR_YELLOW,
    "the architect lays the pieces before you. Strike the rocks to see them break, /arch save <name> to keep what stands, /arch cancel to sweep it.")
  arch_open(pid)
end

-- save the draft's standing parts as a blueprint (broken rocks stay broken in it)
local function arch_save(pid, name)
  if not isAdmin(pid) then return end
  local d = arch_draft[pid]
  if not d or #d.ids == 0 then
    SendClientMessage(pid, COLOR_RED, "nothing laid out to save - /arch new <kind> first.")
    return
  end
  name = (name or ""):lower():gsub("[^%w_%-]", "")
  if #name < 2 then
    SendClientMessage(pid, COLOR_RED, "give the blueprint a name: /arch save <name>")
    return
  end
  local cx, cy = nil, nil
  local parts = {}
  for _, id in ipairs(d.ids) do
    local mo = GetMapObject(id)
    if mo then
      if not cx then cx, cy = mo.x, mo.y end
      local nkey = node_by_entity[id]
      parts[#parts + 1] = {
        mesh = mo.mesh, x = mo.x - cx, y = mo.y - cy, z = mo.z,
        yaw = mo.yaw or 0, scale = mo.scale, node = nkey ~= nil,
      }
    end
  end
  if #parts == 0 then
    SendClientMessage(pid, COLOR_RED, "the draft vanished - nothing to save.")
    return
  end
  local bp = { name = name, parts = parts, author = accounts[pid] and accounts[pid].name }
  blueprints[name] = bp
  bp_save_to_db(bp)
  arch_draft_clear(pid)
  SendClientMessage(pid, COLOR_YELLOW, fmt("blueprint '%s' saved (%d part(s)). Stamp it anywhere: /arch stamp %s", name, #parts, name))
  arch_open(pid)
end

-- stamp a blueprint where the player stands; every part is a real object, node parts break
local function arch_stamp(pid, name, wx, wy, wz, yaw)
  name = (name or ""):lower()
  local bp = blueprints[name]
  if not bp then
    SendClientMessage(pid, COLOR_RED, "no such blueprint - /arch list")
    return
  end
  if not wx then
    local x, y, z = GetPlayerPos(pid)
    wx, wy, wz = x, y, z
  end
  yaw = yaw or math.floor(GetPlayerYaw(pid) / 90) * 90
  local cos, sin = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
  local made = 0
  for _, p in ipairs(bp.parts) do
    local px = wx + p.x * cos - p.y * sin
    local py = wy + p.x * sin + p.y * cos
    local pz = (p.z ~= nil and p.z > -100) and p.z or terrain_z(px, py, wz)
    local id = CreateMapObject(p.mesh, px, py, pz, { yaw = (p.yaw or 0) + yaw, scale = p.scale, persist = true, solid = true })
    if id then
      made = made + 1
      if p.node then
        local n = node_define_noshow({
          key = node_hash("stamp_" .. name .. "_" .. id, px, py), kind = "mine",
          x = px, y = py, z = pz, mesh = p.mesh, is_map = true, mapid = id,
          yaw = (p.yaw or 0) + yaw, scale = p.scale,
          hp = 5, res = job_roll_drop(JOBS.mine), yield = 1,
          label = "the boulder", prompt = "Strike the boulder",
        })
        n.entity = id
        node_by_entity[id] = n.key
      end
    end
  end
  if made == 0 then
    SendClientMessage(pid, COLOR_RED, "the ground refused the blueprint here.")
    return
  end
  SendClientMessage(pid, COLOR_YELLOW, fmt("'%s' raised here (%d part(s)).", name, made))
  Log(fmt("feudalwars: blueprint '%s' stamped at %.1f %.1f", name, wx, wy))
end

arch_open = function(pid)
  if not isAdmin(pid) then
    SendClientMessage(pid, COLOR_RED, "only the crown's servants may shape the land.")
    return
  end
  open_frame(pid, "build")
  local lang = lang_of(pid)
  local list = {}
  for key, b in pairs(BUILD_CATALOG) do
    list[#list + 1] = { key = key, label = b.label[lang] or b.label.en, kind = "catalog" }
  end
  table.sort(list, function(a, b) return a.key < b.key end)
  local bp_list = {}
  for name, bp in pairs(blueprints) do
    bp_list[#bp_list + 1] = { key = name, label = name, parts = #bp.parts }
  end
  table.sort(bp_list, function(a, b) return a.key < b.key end)
  SendPlayerWebMessage(pid, "build", {
    lang = lang, structures = list, blueprints = bp_list,
    has_draft = arch_draft[pid] ~= nil,
    draft_parts = arch_draft[pid] and #arch_draft[pid].ids or 0,
  })
end

RegisterCommand("build", function(pid)
  arch_open(pid)
end, { help = "the architect: lay out, save and stamp blueprints (admins)" })

RegisterCommand("arch", function(pid, args)
  if not isAdmin(pid) then SendClientMessage(pid, COLOR_RED, "only the crown's servants may build."); return end
  local verb, rest = args:match("^(%S*)%s*(.-)$")
  verb = (verb or ""):lower()
  if verb == "new" then
    arch_draft_new(pid, (rest:match("^(%S*)") or ""):lower())
  elseif verb == "save" then
    arch_save(pid, rest)
  elseif verb == "stamp" then
    arch_stamp(pid, rest:match("^(%S*)") or "")
  elseif verb == "list" then
    local names = {}
    for n, bp in pairs(blueprints) do names[#names + 1] = n .. " (" .. #bp.parts .. ")" end
    SendClientMessage(pid, COLOR_YELLOW, "blueprints: " .. (#names > 0 and table.concat(names, ", ") or "none yet"))
  elseif verb == "cancel" then
    arch_draft_clear(pid)
    SendClientMessage(pid, COLOR_SERVER, "the draft is swept away.")
    arch_open(pid)
  else
    SendClientMessage(pid, COLOR_SERVER, "usage: /arch new <kind> | save <name> | stamp <name> | list | cancel")
  end
end, { help = "blueprint architect tools", params = "new|save|stamp|list|cancel", admin = true })

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
  -- a map object with a prompt: the architect's board or a blueprint boulder
  if arch_interaction and id == arch_interaction then
    arch_open(pid)
    return
  end
  local nkey = node_by_entity[id]
  if nkey and nodes[nkey] and nodes[nkey].hp > 0 then
    local n = nodes[nkey]
    SendClientMessage(pid, COLOR_SERVER, fmt("%s - strike it with a tool.", n.label or "the stone"))
    return
  end
end

function OnPlayerInteract(pid, id)
  if arch_interaction and id == arch_interaction then
    arch_open(pid)
    return
  end
  if architect_npc and id == architect_npc then
    arch_open(pid)
    return
  end
  local nkey = node_by_entity[id]
  if nkey then
    local n = nodes[nkey]
    if n and n.hp > 0 then
      SendClientMessage(pid, COLOR_SERVER, fmt("%s - %d/%d. Strike it with the right tool.", n.label or "the stone", n.hp, n.hp_max))
    end
    return
  end
  -- E near a work site: tell what to do
  local px, py, pz = GetPlayerPos(pid)
  local best, bestd = nil, 8.0
  for _, site in pairs(job_sites) do
    local dx, dy = site.x - px, site.y - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d < bestd then best, bestd = site, d end
  end
  if best then job_work_start(pid, best.kind, best.id) end
end

function OnPlayerDisconnect(pid, reason)
  arch_draft_clear(pid)
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
close_frame = function(pid, frame)
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
  elseif name == "build.new" then
    arch_draft_new(pid, data.name)
  elseif name == "build.save" then
    arch_save(pid, data.name)
  elseif name == "build.stamp" then
    arch_stamp(pid, data.name)
    arch_open(pid)
  elseif name == "build.cancel" then
    arch_draft_clear(pid)
    arch_open(pid)
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
