-- KCD:MP custom game mode: feudalwars.
--
-- Feudal lords and their clans fight wars that cost the treasury and move the
-- world economy. Houses collect taxes, spend on war and upkeep, and players
-- farm to earn money that flows back into the system through many sinks.
-- Run with `KcdMp.Server --gamemode gamemodes/feudalwars.lua`.

SetGameModeText("feudalwars")

local WAR = {
  declare_cost = 5000,     -- treasury spent to declare war
  truce_cost = 1000,       -- treasury spent to ask for truce
  war_seconds = 86400,     -- war duration unless ended sooner
  kill_score = 10,         -- war score per killing blow
  tax_rate = 0.10,         -- 10% of player earnings goes to house treasury
  upkeep_per_member = 50,  -- per member per minute, paid from treasury
}

local ECONOMY = {
  farm_pay = 100,          -- base pay for farming actions
  craft_pay = 150,         -- base pay for crafting
  trade_tax = 0.05,        -- 5% tax on player-to-player trades
  shop_tax = 0.05,         -- 5% tax on shop purchases
  prestige_cost = 10000,   -- cost to raise house prestige level
}

local houses = {}            -- name -> { treasury, members, war, war_started, score, prestige }
local playerHouse = {}       -- pid -> house name
local playerMoney = {}       -- pid -> money
local playerPrestige = {}    -- pid -> prestige points

local function fmt(...) return string.format(...) end

local function house_new(name)
  houses[name] = { treasury = 0, members = {}, war = nil, war_started = 0, score = 0, prestige = 1 }
  return houses[name]
end

local function house_join(pid, name)
  playerHouse[pid] = name
  local h = houses[name]
  if h then h.members[pid] = true end
end

local function house_leave(pid)
  local name = playerHouse[pid]
  if not name then return end
  local h = houses[name]
  if h then h.members[pid] = nil end
  playerHouse[pid] = nil
end

local function house_at_war(a, b)
  local ha, hb = houses[a], houses[b]
  return (ha and ha.war == b) or (hb and hb.war == a)
end

local function house_member_count(name)
  local h = houses[name]
  return h and #h.members or 0
end

local function pay_player(pid, amount)
  playerMoney[pid] = (playerMoney[pid] or 0) + amount
  local hname = playerHouse[pid]
  if hname then
    local tax = math.floor(amount * WAR.tax_rate)
    local h = houses[hname]
    if h then h.treasury = h.treasury + tax end
  end
  SendClientMessage(pid, COLOR_SERVER, fmt("You earned %d groschen.", amount))
end

local function take_money(pid, amount)
  playerMoney[pid] = math.max(0, (playerMoney[pid] or 0) - amount)
end

function OnGameModeInit()
  Log("feudalwars on " .. GetLevel() .. ": houses, wars, economy")
  SetTimer(function()
    local now = GetServerTime()
    -- war expiration
    for name, h in pairs(houses) do
      if h.war and now - h.war_started > WAR.war_seconds * 1000 then
        local enemy = houses[h.war]
        if enemy then
          if h.score > enemy.score then
            h.treasury = h.treasury + WAR.declare_cost * 2
            SendClientMessageToAll(COLOR_YELLOW, fmt("%s won the war on %s: the treasury is theirs.", name, h.war))
          end
        end
        h.war = nil
        if enemy then enemy.war = nil end
        h.war_started = 0
      end
    end
    -- upkeep: each house pays per member per minute from treasury
    for name, h in pairs(houses) do
      local count = house_member_count(name)
      local cost = WAR.upkeep_per_member * count
      if h.treasury >= cost then
        h.treasury = h.treasury - cost
      else
        h.treasury = 0
        SendClientMessageToAll(COLOR_RED, fmt("%s's treasury is empty - upkeep unpaid.", name))
      end
    end
  end, 60000, true)
end

function OnPlayerConnect(pid)
  playerMoney[pid] = 500   -- starting purse
  playerPrestige[pid] = 0
  SendClientMessage(pid, COLOR_SERVER, fmt("Welcome to feudalwars, %s. Purse: %d groschen. /house to serve a lord, /war to fight, /help for commands.", GetPlayerName(pid), playerMoney[pid]))
end

function OnPlayerSpawn(pid)
  local name = playerHouse[pid]
  if name then SendClientMessage(pid, COLOR_SERVER, "You serve " .. name .. ". Treasury: " .. (houses[name] and houses[name].treasury or 0)) end
end

function OnPlayerDeath(pid, attacker)
  local victim, killer = playerHouse[pid], playerHouse[attacker]
  if killer and victim and killer ~= victim and house_at_war(killer, victim) then
    local kh, vh = houses[killer], houses[victim]
    kh.score = kh.score + WAR.kill_score
    vh.score = vh.score - WAR.kill_score
    pay_player(attacker, 200)
    SendClientMessageToAll(COLOR_YELLOW, fmt("%s's house %s took a blow from %s's house %s.",
      GetPlayerName(pid), victim, GetPlayerName(attacker), killer))
  end
end

function OnPlayerCommandText(pid, cmd, args)
  local function say(text, bad) SendClientMessage(pid, bad and COLOR_RED or COLOR_SERVER, text) end
  local verb, rest = args:match("^(%S*)%s*(.-)$")
  verb = verb:lower()

  if cmd == "help" then
    say("commands: /house [create|join|leave|list|info], /war [declare|peace|status], /money, /pay <player> <amount>, /farm, /craft, /prestige, /taxes")
    return true
  end

  if cmd == "house" then
    if verb == "create" then
      local name = rest:lower()
      if not name:match("^%a+$") or #name < 3 or #name > 16 then
        say("a lord's name is 3 to 16 letters, no spaces: /house create <name>"); return true
      end
      if houses[name] then say("a house of that name is already known."); return true end
      house_new(name)
      house_join(pid, name)
      SendClientMessage(pid, COLOR_SERVER, "You are now " .. name)
      return true
    elseif verb == "join" then
      local name = rest:lower()
      local h = houses[name]
      if not h then say("no such house."); return true end
      if playerHouse[pid] then say("you already serve a lord."); return true end
      house_join(pid, name)
      SendClientMessage(pid, COLOR_SERVER, "You join " .. name)
      return true
    elseif verb == "leave" then
      if not playerHouse[pid] then say("you serve no lord."); return true end
      house_leave(pid)
      SendClientMessage(pid, COLOR_SERVER, "you leave " .. playerHouse[pid])
      return true
    elseif verb == "list" then
      local names = {}
      for hname in pairs(houses) do names[#names + 1] = hname end
      table.sort(names)
      say(#names > 0 and ("houses: " .. table.concat(names, ", ")) or "no houses yet - /house create <name>")
      return true
    elseif verb == "info" then
      local name = playerHouse[pid]
      if not name then say("you serve no lord."); return true end
      local h = houses[name]
      say(fmt("%s: treasury %d, members %d, prestige %d, war %s", name, h.treasury, house_member_count(name), h.prestige, h.war or "none"))
      return true
    end
    return false
  end

  if cmd == "war" then
    local me = playerHouse[pid]
    if not me then say("you serve no lord - /house create <name> or /house join <name> first."); return true end
    local h = houses[me]
    if verb == "declare" then
      local target = rest:lower()
      local th = houses[target]
      if not th then say("no such house."); return true end
      if me == target then say("you cannot declare war on yourself."); return true end
      if h.war then say("you are already at war."); return true end
      if h.treasury < WAR.declare_cost then say("the treasury is empty - war costs " .. WAR.declare_cost .. "."); return true end
      h.treasury = h.treasury - WAR.declare_cost
      th.treasury = th.treasury - WAR.truce_cost
      h.war = target
      th.war = me
      h.war_started = GetServerTime()
      SendClientMessageToAll(COLOR_YELLOW, fmt("%s declared war on %s!", me, target))
      return true
    elseif verb == "peace" then
      if not h.war then say("you are not at war."); return true end
      local enemy = houses[h.war]
      h.war = nil
      if enemy then enemy.war = nil end
      SendClientMessageToAll(COLOR_YELLOW, GetPlayerName(pid) .. " ended the war with " .. (enemy and enemy or h.war))
      return true
    elseif verb == "status" then
      if not h.war then say("you are not at war."); return true end
      local enemy = houses[h.war]
      SendClientMessage(pid, COLOR_SERVER, fmt("%s: war since %d, score %d - theirs %d", me, h.war_started, h.score, enemy and enemy.score or 0))
      return true
    end
    return false
  end

  if cmd == "money" then
    say(fmt("Your purse: %d groschen.", playerMoney[pid] or 0))
    return true
  end

  if cmd == "pay" then
    local target, amount = sscanf(args, "ud")
    if target == false then say("usage: /pay <player> <amount>"); return true end
    if amount <= 0 then say("amount must be positive."); return true end
    if (playerMoney[pid] or 0) < amount then say("not enough money."); return true end
    take_money(pid, amount)
    playerMoney[target] = (playerMoney[target] or 0) + amount
    local tax = math.floor(amount * ECONOMY.trade_tax)
    local hname = playerHouse[pid]
    if hname and houses[hname] then houses[hname].treasury = houses[hname].treasury + tax end
    SendClientMessage(pid, COLOR_SERVER, fmt("You paid %d groschen to %s.", amount, GetPlayerName(target)))
    SendClientMessage(target, COLOR_SERVER, fmt("%s paid you %d groschen.", GetPlayerName(pid), amount))
    return true
  end

  if cmd == "farm" then
    pay_player(pid, ECONOMY.farm_pay)
    return true
  end

  if cmd == "craft" then
    pay_player(pid, ECONOMY.craft_pay)
    return true
  end

  if cmd == "prestige" then
    local name = playerHouse[pid]
    if not name then say("you serve no lord."); return true end
    local h = houses[name]
    if verb == "raise" then
      if h.treasury < ECONOMY.prestige_cost then say("treasury too low - costs " .. ECONOMY.prestige_cost .. "."); return true end
      h.treasury = h.treasury - ECONOMY.prestige_cost
      h.prestige = h.prestige + 1
      SendClientMessageToAll(COLOR_YELLOW, fmt("%s raised its prestige to %d!", name, h.prestige))
      return true
    elseif verb == "info" then
      say(fmt("%s prestige: %d", name, h.prestige))
      return true
    end
    return false
  end

  if cmd == "taxes" then
    local name = playerHouse[pid]
    if not name then say("you serve no lord."); return true end
    local h = houses[name]
    say(fmt("%s treasury: %d groschen. Tax rate: %d%%. Upkeep: %d per member per minute.", name, h.treasury, math.floor(WAR.tax_rate * 100), WAR.upkeep_per_member))
    return true
  end

  return false
end
