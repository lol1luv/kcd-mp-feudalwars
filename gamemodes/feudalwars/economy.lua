-- Feudal Wars economy: labour that pays per real strike, the game's own gathering and
-- crafting, hunting bounties, and the market.

local FW = require("feudalwars.core")
local world = require("feudalwars.world")

-- ---------------------------------------------------------------- labour

-- The strike itself is the work: the client reports where the blow landed, the height
-- is always right, and the trade comes from what was struck (a trunk, a rock face, a
-- crop). No tool check when the server has no item catalogue: a server that cannot
-- name an item cannot honestly ask for one, and the old check silently refused every
-- strike, which is why the work felt broken.
function FW.work_on_hit(pid, hit)
  if not hit or not hit.x then return end
  local now = GetServerTime()
  local ready = (FW.state.work_cd[pid] or 0)
  if now < ready then return end
  FW.state.work_cd[pid] = now + FW.CONFIG.work_cooldown_ms

  local trade = world.hit_trade(hit)
  if not trade then return end
  local zone = world.zone_at(hit.x, hit.y, hit.z)
  if zone and zone.trade ~= trade then trade = zone.trade end
  local def = FW.TRADE[trade]
  if not def then return end

  local skill = def.skill
  local level = FW.skill_of(pid, skill)
  local pay = def.pay + math.floor(level / 4)

  local effect = ({ quarry = "collisions.rock_hit", woods = "collisions.wood_hit",
    fields = "collisions.dirt_hit", hunt = "collisions.flesh_hit" })[trade]
  pcall(SpawnEffect, effect or "collisions.rock_hit", hit.x, hit.y, hit.z, 1.0)
  local sound = ({ quarry = "special_blacksmith_hammer_anvil", woods = "special_wood_chop",
    fields = "special_digging" })[trade]
  pcall(PlaySound, sound or "special_blacksmith_hammer_anvil", hit.x, hit.y, hit.z, 2)

  FW.earn(pid, pay, FW.skill_label(pid, skill))
  FW.skill_xp(pid, skill, 3)
  local streak = FW.skill_tick(pid, skill)
  if streak % 15 == 0 then
    FW.say(pid, "work_streak", streak)
  end
end

function FW.work_report(pid)
  local px, py = GetPlayerPos(pid)
  local lines = {}
  for _, zone in ipairs(world.zone_all()) do
    local def = FW.TRADE[zone.trade]
    if def then
      local d = math.floor(FW.dist(px, py, zone.x, zone.y))
      local name = (zone.label ~= "" and zone.label) or (def.label[FW.lang_of(pid)] or def.label.en)
      lines[#lines + 1] = FW.t(pid, "work_near", name, d, def.pay)
    end
  end
  if #lines == 0 then
    FW.say(pid, "work_none")
    return
  end
  for _, l in ipairs(lines) do FW.say_raw(pid, l) end
  local near, d = world.zone_nearest(px, py)
  if near and d and d < (near.radius or 40) then
    local def = FW.TRADE[near.trade]
    FW.say(pid, "work_hint",
      (def.label[FW.lang_of(pid)] or def.label.en), (def.do_label[FW.lang_of(pid)] or def.do_label.en))
  end
end

function FW.work_skills(pid)
  FW.say(pid, "skill_list",
    FW.skill_of(pid, "mining"), FW.skill_of(pid, "survival"),
    FW.skill_of(pid, "craftsmanship"), FW.skill_of(pid, "houndmaster"))
end

-- ---------------------------------------------------------------- herbs (the game's own)

function FW.herb_on_pick(pid, herb)
  if not herb then return end
  local zone = world.zone_at(herb.x or 0, herb.y or 0, herb.z or 0)
  local pay = 3
  if zone and zone.trade == "fields" then pay = 4 end
  FW.earn(pid, pay, FW.skill_label(pid, "survival"))
  FW.skill_xp(pid, "survival", 4)
  FW.skill_tick(pid, "survival")
end

-- ---------------------------------------------------------------- hunting (real animals)

function FW.hunt_spawn(zone)
  if not zone or zone.trade ~= "hunt" then return end
  zone.animals = zone.animals or {}
  if #zone.animals >= 4 then return end
  local kinds = { "red deer stag", "red deer doe", "roe deer", "hare", "boar" }
  for i = #zone.animals + 1, 4 do
    local ang = math.random() * math.pi * 2
    local r = 12 + math.random() * (zone.radius or 40) * 0.6
    local ax = zone.x + math.cos(ang) * r
    local ay = zone.y + math.sin(ang) * r
    local kind = kinds[math.random(#kinds)]
    local id = CreateAnimal(kind, ax, ay, -1, math.random(0, 359), nil, nil)
    if id then
      zone.animals[#zone.animals + 1] = id
      FW.state.animals[id] = { zone = zone.id, kind = kind }
      pcall(SetActorButcher, id, true)
    end
  end
end

function FW.hunt_pay(pid, id)
  local info = FW.state.animals[id]
  if not info then return end
  FW.state.animals[id] = nil
  local zone = FW.state.sites[info.zone]
  if zone and zone.animals then
    for i = #zone.animals, 1, -1 do
      if zone.animals[i] == id then table.remove(zone.animals, i) end
    end
  end
  local bounty = ({ ["red deer stag"] = 40, ["red deer doe"] = 28, ["roe deer"] = 20, hare = 8, boar = 45 })[info.kind] or 12
  FW.earn(pid, bounty, FW.skill_label(pid, "houndmaster"))
  FW.skill_xp(pid, "houndmaster", 12)
  FW.skill_tick(pid, "houndmaster")
end

-- ---------------------------------------------------------------- the game's own stations

-- The alchemy table, the anvil and the grindstone are the game's, not ours. The mode
-- only says where they may be used: inside a workshop zone. SetCraftCheck makes the
-- station wait for that answer, so a forge in the middle of a field is refused.
function FW.craft_check(pid, station, class)
  local px, py, pz = GetPlayerPos(pid)
  local zone = world.zone_at(px, py, pz)
  if zone and (zone.trade == "workshop" or zone.trade == "quarry") then return end
  return false
end

function FW.craft_native(pid, station)
  local skill = ({ alchemy = "scholarship", smithing = "weaponsmithing", sharpening = "craftsmanship" })[station] or "craftsmanship"
  FW.skill_xp(pid, skill, 3)
  local x, y, z = GetPlayerPos(pid)
  pcall(SpawnEffect, "collisions.spark_hit", x, y, z, 1.0)
end

-- ---------------------------------------------------------------- the market

function FW.market_ready()
  return FW.ready()
end

function FW.market_lots(pid)
  local lang = FW.lang_of(pid)
  local lots = {}
  for id, lot in pairs(FW.state.lots) do
    local label = lot.item
    if FW.ready() then
      local name = GetItemName and GetItemName(lot.item)
      if name and name ~= "" then label = name end
      local info = GetItemInfo and GetItemInfo(lot.item)
      if info and info.display and info.display ~= "" then label = info.display end
    end
    lots[#lots + 1] = {
      id = id, seller = lot.seller, item = lot.item, res_name = label,
      amount = lot.amount, price = lot.price,
      mine = lot.seller == (FW.state.accounts[pid] and FW.state.accounts[pid].name),
    }
  end
  table.sort(lots, function(a, b) return a.id < b.id end)
  return lots
end

-- what the player may put up: their own inventory, grouped by class
function FW.market_bag(pid)
  local bag = {}
  local seen = {}
  for _, it in ipairs(GetPlayerInventory(pid) or {}) do
    local cls = tostring(it.class or "")
    if cls ~= "" and not seen[cls] then
      seen[cls] = true
      local label = cls
      if FW.ready() then
        local info = GetItemInfo and GetItemInfo(cls)
        if info and info.display and info.display ~= "" then label = info.display end
      end
      bag[#bag + 1] = { res = cls, item = cls, name = label, have = it.amount or 1 }
    end
  end
  table.sort(bag, function(a, b) return a.name < b.name end)
  return bag
end

function FW.market_open(pid)
  FW.open_frame(pid, "auction")
  local lang = FW.lang_of(pid)
  FW.push(pid, "auction", {
    lang = lang, lots = FW.market_lots(pid), bag = FW.market_bag(pid), money = FW.purse(pid),
  })
  if not FW.ready() then FW.say(pid, "not_ready") end
end

function FW.market_sell(pid, item, amount, price)
  if not FW.ready() then FW.say(pid, "not_ready") return end
  item = tostring(item or "")
  amount = math.max(1, math.floor(tonumber(amount) or 1))
  price = math.max(1, math.floor(tonumber(price) or 1))
  if item == "" then return end
  if not TakePlayerItem(pid, item, amount) then
    FW.say(pid, "trade_hold")
    FW.market_open(pid)
    return
  end
  local id = FW.state.lot_next
  FW.state.lot_next = id + 1
  local seller = (FW.state.accounts[pid] and FW.state.accounts[pid].name) or GetPlayerName(pid):lower()
  FW.state.lots[id] = { id = id, seller = seller, item = item, amount = amount, price = price }
  FW.x("INSERT INTO fw_lots (id, seller, item, amount, price) VALUES (@i, @s, @t, @a, @p)",
    { i = id, s = seller, t = item, a = amount, p = price })
  local name = item
  if FW.ready() then
    local info = GetItemInfo and GetItemInfo(item)
    if info and info.display and info.display ~= "" then name = info.display end
  end
  FW.say(pid, "trade_lot_added", id, amount, FW.grosch(price))
  FW.market_open(pid)
end

function FW.market_buy(pid, id)
  if not FW.ready() then FW.say(pid, "not_ready") return end
  local lot = FW.state.lots[id]
  if not lot then FW.say(pid, "trade_lot_gone") FW.market_open(pid) return end
  local me = FW.state.accounts[pid] and FW.state.accounts[pid].name
  if lot.seller == me then FW.say(pid, "trade_mine") return end
  if FW.purse(pid) < lot.price then FW.say(pid, "no_money") return end
  GivePlayerMoney(pid, -lot.price)
  FW.save_money(pid)
  GivePlayerItem(pid, lot.item, lot.amount)
  local spid = GetPlayerId(lot.seller)
  if spid then
    GivePlayerMoney(spid, lot.price)
    FW.save_money(spid)
    FW.notice(spid, FW.fmt("lot #%d sold for %s", id, FW.grosch(lot.price)))
  else
    FW.x("UPDATE fw_players SET money = money + @m WHERE name = @n", { m = lot.price, n = lot.seller })
  end
  FW.state.lots[id] = nil
  FW.x("DELETE FROM fw_lots WHERE id = @i", { i = id })
  FW.say(pid, "trade_lot_bought", id)
  FW.market_open(pid)
end

function FW.market_cancel(pid, id)
  local lot = FW.state.lots[id]
  if not lot then return end
  local me = FW.state.accounts[pid] and FW.state.accounts[pid].name
  if lot.seller ~= me and not IsPlayerAdmin(pid) then return end
  if FW.ready() then GivePlayerItem(pid, lot.item, lot.amount) end
  FW.state.lots[id] = nil
  FW.x("DELETE FROM fw_lots WHERE id = @i", { i = id })
  FW.market_open(pid)
end

function FW.market_load_all()
  local rows = FW.qs("SELECT id, seller, item, amount, price FROM fw_lots")
  if not rows then return end
  for _, r in ipairs(rows) do
    FW.state.lots[r.id] = { id = r.id, seller = r.seller, item = r.item, amount = r.amount, price = r.price }
    if r.id >= FW.state.lot_next then FW.state.lot_next = r.id + 1 end
  end
  FW.log("market: %d lot(s)", #rows)
end

return FW