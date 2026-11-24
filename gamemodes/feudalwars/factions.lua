-- Feudal Wars factions: houses with ranks, the treasury, wars, prestige, upkeep.

local FW = require("feudalwars.core")

function FW.house_of(pid)
  return FW.state.player_house[pid]
end

function FW.house_rank(pid)
  return FW.RANKS[FW.state.player_rank[pid] or 3]
end

function FW.house_members(h)
  local n = 0
  for _ in pairs(h.members or {}) do n = n + 1 end
  return n
end

function FW.house_at_war(a, b)
  local ha, hb = FW.state.houses[a], FW.state.houses[b]
  return (ha and ha.war == b) or (hb and hb.war == a) or false
end

function FW.house_new(name)
  FW.state.houses[name] = { name = name, treasury = 0, prestige = 1, war = nil, war_started = 0, score = 0, members = {} }
  return FW.state.houses[name]
end

function FW.house_join(pid, name, rank)
  FW.state.player_house[pid] = name
  FW.state.player_rank[pid] = rank or 3
  local h = FW.state.houses[name]
  local lname = GetPlayerName(pid):lower()
  if h then h.members[lname] = { rank = rank or 3 } end
  FW.x("INSERT INTO fw_members (house, name, rank) VALUES (@h, @n, @r) ON DUPLICATE KEY UPDATE rank = @r2",
    { h = name, n = lname, r = rank or 3, r2 = rank or 3 })
  local acc = FW.state.accounts[pid]
  if acc then
    FW.x("UPDATE fw_players SET house = @h, rank = @r WHERE name = @n",
      { h = name, r = rank or 3, n = acc.name })
  end
  pcall(SetPlayerState, pid, "house", name)
  pcall(SetPlayerState, pid, "rank", FW.RANKS[rank or 3] or "retainer")
end

function FW.house_leave(pid)
  local name = FW.state.player_house[pid]
  if not name then return end
  local h = FW.state.houses[name]
  local lname = GetPlayerName(pid):lower()
  if h then h.members[lname] = nil end
  FW.x("DELETE FROM fw_members WHERE house = @h AND name = @n", { h = name, n = lname })
  local acc = FW.state.accounts[pid]
  if acc then FW.x("UPDATE fw_players SET house = NULL, rank = 3 WHERE name = @n", { n = acc.name }) end
  FW.state.player_house[pid] = nil
  FW.state.player_rank[pid] = nil
  pcall(SetPlayerState, pid, "house", "")
  pcall(SetPlayerState, pid, "rank", "")
  return name
end

function FW.house_donate(pid, amount)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return false end
  local name = FW.state.player_house[pid]
  if not name or not FW.state.houses[name] then return false end
  if FW.purse(pid) < amount then return false end
  GivePlayerMoney(pid, -amount)
  FW.state.houses[name].treasury = FW.state.houses[name].treasury + amount
  FW.persist_house(name)
  FW.save_money(pid)
  FW.set_purse_state(pid)
  return true
end

function FW.house_prestige(pid)
  local name = FW.state.player_house[pid]
  if not name then return false end
  local h = FW.state.houses[name]
  if h.treasury < FW.CONFIG.prestige_cost then return false end
  h.treasury = h.treasury - FW.CONFIG.prestige_cost
  h.prestige = h.prestige + 1
  FW.persist_house(name)
  FW.say_all(FW.fmt(FW.t(pid, "house_prestige_up"), name, h.prestige))
  return true
end

function FW.war_declare(pid, target)
  target = tostring(target or ""):lower()
  local me = FW.state.player_house[pid]
  if not me then return false, "no_house" end
  local h, th = FW.state.houses[me], FW.state.houses[target]
  if not th then return false, "no_house" end
  if me == target then return false, "self" end
  if h.war then return false, "already" end
  if h.treasury < FW.CONFIG.declare_cost then return false, "cost" end
  h.treasury = h.treasury - FW.CONFIG.declare_cost
  h.war, th.war = target, me
  h.war_started = GetServerTime()
  h.score, th.score = 0, 0
  FW.persist_house(me)
  FW.persist_house(target)
  FW.say_all(FW.fmt(FW.t(pid, "war_declared"), me, target))
  FW.notice_all(FW.t(pid, "war_declared"):format(me, target))
  return true
end

function FW.war_peace(pid)
  local me = FW.state.player_house[pid]
  if not me then return false end
  local h = FW.state.houses[me]
  if not h.war then return false end
  local enemy = h.war
  local th = FW.state.houses[enemy]
  h.war = nil
  if th then th.war = nil end
  FW.persist_house(me)
  if th then FW.persist_house(enemy) end
  FW.say_all(FW.fmt(FW.t(pid, "war_peace"), me, enemy))
  return true
end

function FW.war_tick()
  local now = GetServerTime()
  for name, h in pairs(FW.state.houses) do
    if h.war then
      local started = h.war_started or 0
      if started > 0 and now - started > FW.CONFIG.war_seconds * 1000 then
        local enemy = FW.state.houses[h.war]
        if enemy then
          if h.score > enemy.score then
            local take = math.min(enemy.treasury, FW.CONFIG.war_trophy)
            enemy.treasury = enemy.treasury - take
            h.treasury = h.treasury + take
            FW.say_all(FW.fmt(FW.t(nil, "war_won"), name, FW.grosch(take)))
            FW.persist_house(h.war)
          end
          enemy.war, enemy.score = nil, 0
          FW.persist_house(h.war)
        end
        h.war, h.war_started, h.score = nil, 0, 0
        FW.persist_house(name)
      end
    end
    local cost = FW.CONFIG.upkeep_per_member * FW.house_members(h)
    if cost > 0 then
      if h.treasury >= cost then
        h.treasury = h.treasury - cost
      else
        h.treasury = 0
        FW.say_all(FW.fmt(FW.t(nil, "house_upkeep_dry"), name))
      end
    end
  end
end

function FW.war_score(victim, killer)
  local vh = FW.state.player_house[victim]
  local kh = FW.state.player_house[killer]
  if not vh or not kh or vh == kh then return end
  if not FW.house_at_war(vh, kh) then return end
  local a, b = FW.state.houses[kh], FW.state.houses[vh]
  if a then a.score = (a.score or 0) + FW.CONFIG.war_kill_score end
  if b then b.score = (b.score or 0) - FW.CONFIG.war_kill_score end
  FW.say_all(FW.fmt(FW.t(nil, "war_fell"),
    GetPlayerName(victim), vh, GetPlayerName(killer), kh))
end

function FW.house_load_all()
  local rows = FW.qs("SELECT name, treasury, prestige FROM fw_houses")
  if rows then
    for _, r in ipairs(rows) do
      local h = FW.house_new(r.name)
      h.treasury = r.treasury or 0
      h.prestige = r.prestige or 1
    end
    FW.log("houses: %d", #rows)
  end
  local mrows = FW.qs("SELECT house, name, rank FROM fw_members")
  if mrows then
    for _, r in ipairs(mrows) do
      local h = FW.state.houses[r.house]
      if h then h.members[r.name] = { rank = r.rank or 3 } end
    end
  end
end

function FW.house_sync(pid)
  local acc = FW.state.accounts[pid]
  if not acc or not acc.name then return end
  FW.q("SELECT house, rank FROM fw_players WHERE name = @n", { n = acc.name }, function(rows)
    if not rows or not rows[1] then return end
    local house = rows[1].house
    if house and house ~= "" and FW.state.houses[house] then
      FW.state.player_house[pid] = house
      FW.state.player_rank[pid] = rows[1].rank or 3
      pcall(SetPlayerState, pid, "house", house)
      pcall(SetPlayerState, pid, "rank", FW.RANKS[rows[1].rank or 3] or "retainer")
    end
  end)
end

function FW.house_panel(pid)
  local name = FW.state.player_house[pid]
  if not name then
    FW.say(pid, "house_not_serving")
    return
  end
  local h = FW.state.houses[name]
  if not h then return end
  local members = {}
  for lname, m in pairs(h.members or {}) do
    members[#members + 1] = { name = lname, rank = FW.RANKS[m.rank] or "retainer", online = GetPlayerId(lname) ~= nil }
  end
  table.sort(members, function(a, b) return a.name < b.name end)
  local wars = {}
  if h.war then
    local enemy = FW.state.houses[h.war]
    local since = h.war_started and math.floor(h.war_started / 1000) or 0
    wars[#wars + 1] = {
      enemy = h.war, score = h.score or 0,
      theirs = enemy and (enemy.score or 0) or 0,
      since = since > 0 and os.date("%H:%M", since) or "",
    }
  end
  local others = {}
  for other in pairs(FW.state.houses) do
    if other ~= name then others[#others + 1] = other end
  end
  table.sort(others)
  FW.open_frame(pid, "hall")
  FW.push(pid, "hall", {
    lang = FW.lang_of(pid), name = GetPlayerName(pid),
    house = name, money = FW.purse(pid), treasury = h.treasury, prestige = h.prestige,
    members = members, wars = wars, myRank = FW.house_rank(pid), others = others,
    declaring = h.war == nil and h.treasury >= FW.CONFIG.declare_cost,
    declare_cost = FW.CONFIG.declare_cost, prestige_cost = FW.CONFIG.prestige_cost,
  })
end

return FW