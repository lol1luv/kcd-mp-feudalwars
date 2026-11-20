-- KCD:MP game mode: feudalwars (v2).
--
-- Feudal houses, wars, a treasury economy and persistent accounts.
-- Uses the game mode database ([gamemode.database] in server.toml) when one is
-- configured; without a database everything still works, but is not saved.
-- Run with `KcdMp.Server --gamemode gamemodes/feudalwars.lua`.

SetGameModeText("feudalwars")

local WAR = {
  declare_cost = 5000,     -- the treasury a house spends to declare war
  truce_cost = 1000,       -- ... and to ask for a truce
  war_seconds = 86400,     -- a war runs this long unless it ends sooner
  kill_score = 10,         -- war score a killing blow adds to the killer's house
  win_treasury = 10000,    -- the winner takes this from the loser's treasury
}

local ECONOMY = {
  start_money = 500,       -- a fresh character's purse
  farm_pay = 100,          -- /farm
  craft_pay = 150,         -- /craft
  trade_tax = 0.05,        -- 5% of every /pay goes to the treasury
  earn_tax = 0.10,         -- 10% of farm/craft earnings go to the treasury
  upkeep_per_member = 50,  -- per member per minute, paid from the treasury
  prestige_cost = 10000,   -- treasury cost to raise prestige
}

local db = GetDatabase()     -- nil unless [gamemode.database] is configured

local houses = {}            -- name -> { treasury, members = {pid}, war, war_started, score, prestige }
local playerHouse = {}       -- pid -> house name
local accounts = {}          -- pid -> { name, money, known }  (known = row loaded)

local function fmt(...) return string.format(...) end

local function house_new(name)
  houses[name] = { treasury = 0, members = {}, war = nil, war_started = 0, score = 0, prestige = 1 }
  return houses[name]
end

local function house_member_count(h)
  local n = 0
  for _ in pairs(h.members) do n = n + 1 end
  return n
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

local function save_house(name)
  if not db then return end
  local h = houses[name]
  db:Execute("INSERT INTO houses (name, treasury, prestige) VALUES (@n, @t, @p) " ..
    "ON DUPLICATE KEY UPDATE treasury = @t2, prestige = @p2",
    { n = name, t = h.treasury, p = h.prestige, t2 = h.treasury, p2 = h.prestige },
    function() end)
end

local function save_money(pid)
  if not db or not accounts[pid] or not accounts[pid].known then return end
  accounts[pid].money = GetPlayerMoney(pid)
  db:Execute("UPDATE players SET money = @m WHERE name = @n",
    { m = accounts[pid].money, n = accounts[pid].name }, function() end)
end

local function earn(pid, amount, taxTo)
  GivePlayerMoney(pid, amount)
  local tax = math.floor(amount * taxTo)
  local name = playerHouse[pid]
  if name and houses[name] and tax > 0 then
    houses[name].treasury = houses[name].treasury + tax
    SendClientMessage(pid, COLOR_SERVER, fmt("The house of %s collected %d groschen in tax.", name, tax))
  end
end

function OnGameModeInit()
  Log("feudalwars on " .. GetLevel() .. ": houses, wars, economy" .. (db and ", database" or ", no database (memory only)"))

  -- schema (only what the mode keeps; sync calls are legal inside OnGameModeInit)
  if db then
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS players (name VARCHAR(32) PRIMARY KEY, money INT NOT NULL DEFAULT 0)")
    db:ExecuteSync("CREATE TABLE IF NOT EXISTS houses (name VARCHAR(32) PRIMARY KEY, treasury INT NOT NULL DEFAULT 0, prestige INT NOT NULL DEFAULT 1)")
    -- load houses
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
  end

  -- spawn point at the default level spawn
  local sx, sy, sz, syaw = GetDefaultSpawn()
  AddSpawnPoint(sx, sy, sz, syaw, "town")

  -- a provisioner shop near the spawn: buys and sells for real groschen
  local shop = CreateShop("The King's Provisioner", 0.5, -1)
  SetShopItem(shop, "torch", 10, -1)
  SetShopItem(shop, "bandage", 25, -1)
  SetShopItem(shop, "bread", 5, -1)
  SetShopItem(shop, "water", 3, -1)
  CreateVendor(shop, "provisioner", sx + 2.0, sy + 2.0, sz, syaw + 180.0, "Provisioner Bohush", nil, nil)

  -- war expiry and house upkeep, once a minute
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
            SendClientMessageToAll(COLOR_YELLOW, fmt("%s won the war against %s and took %d groschen.", name, h.war, take))
            save_house(h.war)
          end
          enemy.war = nil
          enemy.score = 0
        end
        h.war = nil
        h.war_started = 0
        h.score = 0
      end
    end
    for name, h in pairs(houses) do
      local cost = ECONOMY.upkeep_per_member * house_member_count(h)
      if cost > 0 then
        if h.treasury >= cost then
          h.treasury = h.treasury - cost
        else
          h.treasury = 0
          SendClientMessageToAll(COLOR_RED, fmt("The treasury of %s is empty - upkeep unpaid.", name))
        end
      end
    end
  end, 60000, true)
end

function OnPlayerConnect(pid)
  local name = GetPlayerName(pid)
  accounts[pid] = { name = name:lower(), money = ECONOMY.start_money, known = false }

  local function greeting()
    SendClientMessage(pid, COLOR_SERVER, "Welcome to Feudal Wars. /help lists the commands.")
  end

  if db then
    db:Query("SELECT money FROM players WHERE name = @n", { n = accounts[pid].name }, function(rows, err)
      if rows and rows[1] then
        accounts[pid].money = rows[1].money or 0
        accounts[pid].known = true
      elseif err == nil and rows then
        accounts[pid].known = true
        db:Execute("INSERT INTO players (name, money) VALUES (@n, @m)", { n = accounts[pid].name, m = ECONOMY.start_money }, function() end)
      end
      greeting()
    end)
  else
    greeting()
  end
end

function OnPlayerRequestSpawn(pid)
  SetSpawnInfo(pid, GetSpawnPoints("town")[1])
  return true
end

function OnPlayerSpawn(pid)
  -- the purse is empty on every entry: restore the saved one (basicrp pattern)
  local acc = accounts[pid]
  if acc then
    GivePlayerMoney(pid, acc.money - GetPlayerMoney(pid))
  end
  local name = playerHouse[pid]
  if name then
    local h = houses[name]
    SendClientMessage(pid, COLOR_SERVER, fmt("You serve %s. Treasury: %d, prestige: %d.", name, h.treasury, h.prestige))
  end
end

function OnPlayerDisconnect(pid)
  save_money(pid)
  house_leave(pid)
  accounts[pid] = nil
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

function OnPlayerCommandText(pid, cmd, args)
  local function say(text, bad) SendClientMessage(pid, bad and COLOR_RED or COLOR_SERVER, text) end
  local verb, rest = args:match("^(%S*)%s*(.-)$")
  verb = verb:lower()

  if cmd == "help" then
    say("commands: /house [create|join|leave|list|info], /war [declare|peace|status], /money, /pay <player> <amount>, /farm, /craft, /prestige [info|raise], /taxes")
    return true
  end

  if cmd == "house" then
    if verb == "create" then
      local name = rest:lower()
      if not name:match("^%a+$") or #name < 3 or #name > 16 then
        say("a house name is 3 to 16 letters, no spaces: /house create <name>", true); return true
      end
      if houses[name] then say("a house of that name already exists.", true); return true end
      if playerHouse[pid] then say("you already serve a lord.", true); return true end
      house_new(name)
      house_join(pid, name)
      save_house(name)
      SendClientMessageToAll(COLOR_YELLOW, GetPlayerName(pid) .. " founded the house of " .. name .. ".")
      return true
    elseif verb == "join" then
      local name = rest:lower()
      if not houses[name] then say("no such house.", true); return true end
      if playerHouse[pid] then say("you already serve a lord.", true); return true end
      house_join(pid, name)
      SendClientMessageToAll(COLOR_YELLOW, GetPlayerName(pid) .. " joined the house of " .. name .. ".")
      return true
    elseif verb == "leave" then
      if not playerHouse[pid] then say("you serve no lord.", true); return true end
      local name = playerHouse[pid]
      house_leave(pid)
      say("you left the house of " .. name .. ".")
      return true
    elseif verb == "list" then
      local names = {}
      for hname in pairs(houses) do names[#names + 1] = hname end
      table.sort(names)
      say(#names > 0 and ("houses: " .. table.concat(names, ", ")) or "no houses yet - /house create <name>")
      return true
    elseif verb == "info" then
      local name = playerHouse[pid]
      if not name then say("you serve no lord.", true); return true end
      local h = houses[name]
      say(fmt("%s: treasury %d, members %d, prestige %d, war %s",
        name, h.treasury, house_member_count(h), h.prestige, h.war or "none"))
      return true
    end
    return false
  end

  if cmd == "war" then
    local me = playerHouse[pid]
    if not me then say("you serve no lord - /house create <name> or /house join <name> first.", true); return true end
    local h = houses[me]
    if verb == "declare" then
      local target = rest:lower()
      local th = houses[target]
      if not th then say("no such house.", true); return true end
      if me == target then say("you cannot declare war on yourself.", true); return true end
      if h.war then say("your house is already at war.", true); return true end
      if h.treasury < WAR.declare_cost then say(fmt("the treasury needs %d groschen for a war.", WAR.declare_cost), true); return true end
      h.treasury = h.treasury - WAR.declare_cost
      h.war = target
      th.war = me
      h.war_started = GetServerTime()
      save_house(me); save_house(target)
      SendClientMessageToAll(COLOR_YELLOW, fmt("The house of %s declared war on %s!", me, target))
      return true
    elseif verb == "peace" then
      if not h.war then say("your house is not at war.", true); return true end
      local enemy = houses[h.war]
      SendClientMessageToAll(COLOR_YELLOW, fmt("The war between %s and %s is over.", me, h.war))
      h.war = nil
      if enemy then enemy.war = nil end
      save_house(me)
      return true
    elseif verb == "status" then
      if not h.war then say("your house is not at war.", true); return true end
      local enemy = houses[h.war]
      say(fmt("%s vs %s: score %d - %d", me, h.war, h.score, enemy and enemy.score or 0))
      return true
    end
    return false
  end

  if cmd == "money" then
    say(fmt("Your purse: %d groschen.", GetPlayerMoney(pid)))
    return true
  end

  if cmd == "pay" then
    local target, amount = sscanf(args, "ud")
    if target == false or target == nil then say("usage: /pay <player> <amount>", true); return true end
    if amount <= 0 then say("the amount must be positive.", true); return true end
    if GetPlayerMoney(pid) < amount then say("not enough groschen.", true); return true end
    GivePlayerMoney(pid, -amount)
    GivePlayerMoney(target, amount)
    local tax = math.floor(amount * ECONOMY.trade_tax)
    local name = playerHouse[pid]
    if name and houses[name] and tax > 0 then houses[name].treasury = houses[name].treasury + tax end
    SendClientMessage(pid, COLOR_SERVER, fmt("You paid %d groschen to %s.", amount, GetPlayerName(target)))
    SendClientMessage(target, COLOR_SERVER, fmt("%s paid you %d groschen.", GetPlayerName(pid), amount))
    return true
  end

  if cmd == "farm" then
    earn(pid, ECONOMY.farm_pay, ECONOMY.earn_tax)
    return true
  end

  if cmd == "craft" then
    earn(pid, ECONOMY.craft_pay, ECONOMY.earn_tax)
    return true
  end

  if cmd == "prestige" then
    local name = playerHouse[pid]
    if not name then say("you serve no lord.", true); return true end
    local h = houses[name]
    if verb == "raise" then
      if h.treasury < ECONOMY.prestige_cost then say(fmt("the treasury needs %d groschen.", ECONOMY.prestige_cost), true); return true end
      h.treasury = h.treasury - ECONOMY.prestige_cost
      h.prestige = h.prestige + 1
      save_house(name)
      SendClientMessageToAll(COLOR_YELLOW, fmt("The house of %s raised its prestige to %d.", name, h.prestige))
      return true
    elseif verb == "info" then
      say(fmt("%s prestige: %d", name, h.prestige))
      return true
    end
    return false
  end

  if cmd == "taxes" then
    local name = playerHouse[pid]
    if not name then say("you serve no lord.", true); return true end
    local h = houses[name]
    say(fmt("%s treasury: %d groschen. Tax: %d%% of earnings, %d%% of trades. Upkeep: %d per member per minute.",
      name, h.treasury, math.floor(ECONOMY.earn_tax * 100), math.floor(ECONOMY.trade_tax * 100), ECONOMY.upkeep_per_member))
    return true
  end

  return false
end
