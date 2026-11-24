-- Feudal Wars world: work zones, the realm's people, ground handling, travel.

local FW = require("feudalwars.core")

FW.TRADE = {
  quarry = {
    label = { en = "the quarry", ru = "каменоломня" },
    skill = "mining", pay = 6,
    icon = "troskyQuarry", icon_num = 48,
    prompt = "Strike the rock",
    do_label = { en = "swing at the rock face", ru = "бей каменную стену" },
    foreman = { en = "Quarry master", ru = "Каменотёс" },
  },
  woods = {
    label = { en = "the woods", ru = "лес" },
    skill = "craftsmanship", pay = 6,
    icon = "camp", icon_num = 38,
    prompt = "Fell the tree",
    do_label = { en = "swing at the trunk", ru = "бей по стволу" },
    foreman = { en = "Woodcutter", ru = "Лесоруб" },
  },
  fields = {
    label = { en = "the fields", ru = "поля" },
    skill = "survival", pay = 5,
    icon = "miller", icon_num = 21,
    prompt = "Cut the crop",
    do_label = { en = "swing at the crop", ru = "бей по посевам" },
    foreman = { en = "Reeve", ru = "Староста" },
  },
  hunt = {
    label = { en = "the hunting ground", ru = "охотничьи угодья" },
    skill = "houndmaster", pay = 14,
    icon = "huntingGround", icon_num = 194,
    prompt = "Hunt here",
    do_label = { en = "bring down the game", ru = "бей зверя" },
    foreman = { en = "Huntsman", ru = "Ловчий" },
  },
  workshop = {
    label = { en = "the workshop", ru = "мастерская" },
    skill = "weaponsmithing", pay = 10,
    icon = "blacksmith", icon_num = 12,
    prompt = "Work here",
    do_label = { en = "work the anvil and the table", ru = "работай у наковальни и стола" },
    foreman = { en = "Master craftsman", ru = "Мастер" },
  },
}

FW.TREE_WORDS = {
  quercus = true, picea = true, pinus = true, fagus = true, betula = true, carpinus = true,
  abies = true, alnus = true, tilia = true, acer = true, fraxinus = true, salix = true,
  populus = true, ulmus = true, juglans = true, trees = true, tree_ = true, stump = true,
}

FW.CROP_WORDS = { hay = true, wheat = true, barley = true, rye = true, field = true, crop = true, sheaf = true, straw = true }

function FW.zone_all()
  local out = {}
  for _, z in pairs(FW.state.sites) do out[#out + 1] = z end
  table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return out
end

function FW.zone_at(x, y, z)
  local best, bestd = nil, 1e9
  for _, s in pairs(FW.state.sites) do
    local d = FW.dist(x, y, s.x, s.y)
    if d <= (s.radius or 40) and d < bestd then best, bestd = s, d end
  end
  return best
end

function FW.zone_of_trade(trade)
  for _, s in pairs(FW.state.sites) do
    if s.trade == trade then return s end
  end
  return nil
end

function FW.zone_nearest(x, y)
  local best, bestd = nil, 1e9
  for _, s in pairs(FW.state.sites) do
    local d = FW.dist(x, y, s.x, s.y)
    if d < bestd then best, bestd = s, d end
  end
  return best, bestd
end

function FW.zone_draw(zone)
  local def = FW.TRADE[zone.trade]
  if not def then return end
  if zone.area then pcall(DeleteArea, zone.area_name) zone.area = nil end
  local r = zone.radius or 40
  local area = CreateArea(zone.area_name, "cylinder", {
    x = zone.x, y = zone.y, radius = r, zmin = zone.z - 30, zmax = zone.z + 60,
    label = def.label.en, public = true, color = 0x8a5a2a,
    nav = "auto", layer = "base",
  })
  if area then zone.area = area end
  if zone.icon then pcall(DeleteMapIcon, zone.icon) end
  local iid = CreateMapIcon(zone.x, zone.y, FW.ground(zone.x, zone.y, zone.z),
    { icon = def.icon_num, name = zone.label ~= "" and zone.label or def.label.en })
  if iid then zone.icon = iid end
  if zone.actor then
    FW.state.people[zone.actor] = nil
    pcall(DestroyEntity, zone.actor)
    zone.actor = nil
  end
  if zone.foreman ~= false then
    local ax, ay = zone.x + 2.5, zone.y + 2.5
    local actor = CreateActor(nil, ax, ay, -1, 180.0, def.foreman.en, nil, "none", nil)
    if actor then
      zone.actor = actor
      pcall(SetActorInvulnerable, actor, true)
      pcall(SetActorPrompt, actor, def.prompt)
      FW.state.people[actor] = {
        id = "zone:" .. zone.id, role = "foreman", name = def.foreman.en,
        x = ax, y = ay, z = zone.z, actor = actor, zone = zone.id, data = {},
      }
    end
  end
end

function FW.zone_save(zone)
  FW.x("INSERT INTO fw_sites (id, trade, x, y, z, label) VALUES (@i, @t, @x, @y, @z, @l) " ..
    "ON DUPLICATE KEY UPDATE trade = @t2, x = @x2, y = @y2, z = @z2, label = @l2",
    { i = zone.id, t = zone.trade, x = zone.x, y = zone.y, z = zone.z, l = zone.label or "",
      t2 = zone.trade, x2 = zone.x, y2 = zone.y, z2 = zone.z, l2 = zone.label or "" })
end

function FW.zone_add(trade, x, y, z, label, id)
  trade = tostring(trade or ""):lower()
  local def = FW.TRADE[trade]
  if not def then return nil, "unknown trade" end
  id = id or (trade .. "_" .. math.floor(x) .. "_" .. math.floor(y))
  local zone = FW.state.sites[id] or { id = id }
  zone.trade, zone.x, zone.y, zone.z = trade, x, y, FW.ground(x, y, z)
  zone.label = label or ""
  zone.radius = zone.radius or 40
  zone.area_name = "fw_zone_" .. id
  FW.state.sites[id] = zone
  FW.zone_save(zone)
  FW.zone_draw(zone)
  return zone
end

function FW.zone_remove(id)
  local zone = FW.state.sites[id]
  if not zone then return false end
  if zone.area then pcall(DeleteArea, zone.area_name) end
  if zone.icon then pcall(DeleteMapIcon, zone.icon) end
  if zone.actor then pcall(DestroyEntity, zone.actor) end
  FW.state.sites[id] = nil
  FW.x("DELETE FROM fw_sites WHERE id = @i", { i = id })
  return true
end

function FW.zone_load_all()
  local rows = FW.qs("SELECT id, trade, x, y, z, label FROM fw_sites")
  if not rows then return end
  for _, r in ipairs(rows) do
    local zone = {
      id = r.id, trade = r.trade, x = r.x, y = r.y, z = r.z, label = r.label or "",
      radius = 40, area_name = "fw_zone_" .. tostring(r.id),
    }
    FW.state.sites[r.id] = zone
    FW.zone_draw(zone)
  end
  FW.log("zones: %d placed by the crown", #rows)
end

-- ---------------------------------------------------------------- what a strike hit

function FW.hit_trade(hit)
  if not hit then return nil end
  local surface = tostring(hit.surface or ""):lower()
  local kind = tostring(hit.kind or ""):lower()
  local mesh = tostring(hit.mesh or ""):lower()
  if kind == "vegetation" or kind == "static" then
    for word in pairs(FW.TREE_WORDS) do
      if mesh:find(word, 1, true) then return "woods" end
    end
    for word in pairs(FW.CROP_WORDS) do
      if mesh:find(word, 1, true) then return "fields" end
    end
  end
  if surface:find("rock", 1, true) or surface:find("stone", 1, true) then return "quarry" end
  if surface:find("wood", 1, true) then return "woods" end
  if surface:find("grass", 1, true) or surface:find("vegetation", 1, true) or surface:find("soil", 1, true) then
    return "fields"
  end
  if kind == "static" then return "quarry" end
  if kind == "vegetation" then return "woods" end
  return nil
end

-- ---------------------------------------------------------------- travel

function FW.place(pid, where)
  where = tostring(where or ""):lower()
  local x, y, z
  if where == "spawn" or where == "town" then
    x, y, z = FW.spawn.x, FW.spawn.y, -1
  elseif where == "quarry" or where == "woods" or where == "fields" or where == "hunt" or where == "workshop" then
    local zone = FW.zone_of_trade(where)
    if not zone then return false, "no zone" end
    x, y, z = zone.x, zone.y, -1
  else
    local zone = FW.state.sites[where]
    if not zone then return false, "nowhere" end
    x, y, z = zone.x, zone.y, -1
  end
  SetPlayerPos(pid, x + 2.0, y, z, 0.0)
  return true
end

-- ---------------------------------------------------------------- the realm's people

FW.PERSON_ROLES = { vendor = true, trainer = true, guard = true, quest = true, civilian = true, foreman = true }

FW.ROLE_LABEL = {
  vendor = { en = "Vendor", ru = "Торговец" },
  trainer = { en = "Trainer", ru = "Учитель" },
  guard = { en = "Guard", ru = "Стражник" },
  quest = { en = "Quest giver", ru = "Поручения" },
  civilian = { en = "Citizen", ru = "Горожанин" },
  foreman = { en = "Foreman", ru = "Бригадир" },
}

function FW.role_label(pid, role)
  local l = FW.ROLE_LABEL[role] or FW.ROLE_LABEL.civilian
  return l[FW.lang_of(pid)] or l.en
end

function FW.person_save(n)
  FW.x("INSERT INTO fw_people (id, role, name, x, y, z, yaw, prompt, data) VALUES " ..
    "(@i, @r, @n, @x, @y, @z, @yw, @p, @d) " ..
    "ON DUPLICATE KEY UPDATE role = @r2, name = @n2, x = @x2, y = @y2, z = @z2, yaw = @yw2, prompt = @p2, data = @d2",
    { i = n.id, r = n.role, n = n.name, x = n.x, y = n.y, z = n.z, yw = n.yaw or 0, p = n.prompt or "",
      d = JsonEncode(n.data or {}),
      r2 = n.role, n2 = n.name, x2 = n.x, y2 = n.y, z2 = n.z, yw2 = n.yaw or 0, p2 = n.prompt or "",
      d2 = JsonEncode(n.data or {}) })
end

function FW.person_spawn(n)
  if n.actor then pcall(DestroyEntity, n.actor) n.actor = nil end
  if n.shop then pcall(DestroyShop, n.shop) n.shop = nil end
  local actor = CreateActor(nil, n.x, n.y, -1, n.yaw or 0, n.name, nil, "none", nil)
  if not actor then return false end
  n.actor = actor
  pcall(SetActorInvulnerable, actor, true)
  local prompt = n.prompt
  if not prompt or prompt == "" then
    prompt = ({ vendor = "Trade", trainer = "Learn", guard = "Hail", quest = "Ask for work",
      civilian = "Speak", foreman = "Speak" })[n.role] or "Speak"
  end
  pcall(SetActorPrompt, actor, prompt)
  FW.state.people[actor] = n

  if n.role == "vendor" then
    local stock = (n.data and n.data.stock) or {}
    local shop = CreateShop(n.name or "Merchant", 0.5, -1)
    if shop then
      n.shop = shop
      for _, row in ipairs(stock) do
        pcall(SetShopItem, shop, row.item, row.price or 10, row.amount or -1)
      end
      pcall(SetActorShop, actor, shop)
    end
  elseif n.role == "trainer" then
    local skill = n.data and n.data.skill
    if skill then
      local l = FW.SKILL_LABEL[skill]
      pcall(SetActorNameplateTitle, actor, "Teacher: " .. ((l and l.en) or skill), 1.0, 0xE8C84AFF, "above")
    end
  end
  return true
end

function FW.person_by_actor(actor)
  return FW.state.people[actor]
end

function FW.person_open(pid, n)
  if not n then return end
  local lang = FW.lang_of(pid)
  local stock = {}
  if n.role == "vendor" then
    for _, row in ipairs((n.data and n.data.stock) or {}) do
      local info = GetItemInfo and GetItemInfo(row.item) or nil
      stock[#stock + 1] = {
        item = row.item,
        label = info and (info.display ~= "" and info.display or info.name) or tostring(row.item),
        price = row.price,
      }
    end
  end
  local train_skill = n.data and n.data.skill or nil
  FW.open_frame(pid, "npc")
  FW.push(pid, "npc", {
    lang = lang, mode = "single",
    npc = {
      id = n.id, name = n.name, role = n.role,
      role_label = FW.role_label(pid, n.role), stock = stock,
      train_skill = train_skill and FW.skill_label(pid, train_skill) or nil,
    },
    actions = FW.person_actions(pid, n),
  })
end

function FW.person_actions(pid, n)
  local lang = FW.lang_of(pid)
  local function L(en, ru) return lang == "ru" and ru or en end
  if n.role == "vendor" then
    return { { id = "trade", label = L("Trade", "Торговать") } }
  elseif n.role == "trainer" then
    return { { id = "train", label = L("Learn", "Учиться") } }
  elseif n.role == "guard" then
    return { { id = "report", label = L("Report a crime", "Донести о краже") } }
  elseif n.role == "quest" then
    return { { id = "task", label = L("Ask for work", "Спросить работу") } }
  elseif n.role == "foreman" then
    return { { id = "hire", label = L("Ask about the work", "Спросить о работе") } }
  end
  return { { id = "talk", label = L("Speak", "Поговорить") } }
end

function FW.person_create(pid, role, name)
  role = tostring(role or ""):lower()
  if not FW.PERSON_ROLES[role] then return nil, "role" end
  name = tostring(name or "")
  if #name < 2 then return nil, "name" end
  local px, py, pz = GetPlayerPos(pid)
  local id = FW.state.person_next or 1
  FW.state.person_next = id + 1
  local n = {
    id = id, role = role, name = name, x = px, y = py, z = FW.ground(px, py, pz),
    yaw = GetPlayerYaw(pid) + 180.0, prompt = "", data = { stock = {} },
  }
  if role == "vendor" then n.data.stock = {} end
  FW.state.people_list[id] = n
  FW.person_save(n)
  FW.person_spawn(n)
  return n
end

function FW.person_remove(id)
  local n = FW.state.people_list[id]
  if not n then return false end
  if n.actor then FW.state.people[n.actor] = nil pcall(DestroyEntity, n.actor) end
  if n.shop then pcall(DestroyShop, n.shop) end
  FW.state.people_list[id] = nil
  FW.x("DELETE FROM fw_people WHERE id = @i", { i = id })
  return true
end

function FW.people_load_all()
  local rows = FW.qs("SELECT id, role, name, x, y, z, yaw, prompt, data FROM fw_people")
  if not rows then return end
  for _, r in ipairs(rows) do
    local ok, data = pcall(JsonDecode, r.data or "{}")
    local n = {
      id = r.id, role = r.role, name = r.name, x = r.x, y = r.y, z = r.z,
      yaw = r.yaw or 0, prompt = r.prompt or "", data = ok and data or {},
    }
    FW.state.people_list[r.id] = n
    if r.id >= (FW.state.person_next or 1) then FW.state.person_next = r.id + 1 end
    FW.person_spawn(n)
  end
  FW.log("people: %d placed", #rows)
end

return FW