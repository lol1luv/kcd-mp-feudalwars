-- Feudal Wars social: accounts, the character page, paying another player, the
-- connect/spawn/disconnect lifecycle.

local FW = require("feudalwars.core")
local factions = require("feudalwars.factions")

function FW.account_open(pid)
  local name = GetPlayerName(pid):lower()
  FW.state.accounts[pid] = { name = name, money = FW.CONFIG.start_money, known = false }
  pcall(SetPlayerState, pid, "house", "")
  pcall(SetPlayerState, pid, "rank", "")
  pcall(SetPlayerState, pid, "purse", "0")

  for _, admin in ipairs(FW.ADMINS) do
    if name == admin:lower() then pcall(SetPlayerAdmin, pid, true) end
  end

  local lang = GetPlayerLanguage(pid)
  if lang and FW.LANGUAGE[lang] then FW.state.lang[pid] = lang end

  if not FW.db then FW.state.accounts[pid].known = true return end

  FW.q("SELECT money, lang, house, rank FROM fw_players WHERE name = @n", { n = name }, function(rows)
    local acc = FW.state.accounts[pid]
    if not acc then return end
    if rows and rows[1] then
      acc.money = rows[1].money or 0
      acc.known = true
      if rows[1].lang and FW.LANGUAGE[rows[1].lang] then FW.state.lang[pid] = rows[1].lang end
    else
      acc.known = true
      FW.x("INSERT INTO fw_players (name, money, lang, last_seen) VALUES (@n, @m, @l, @t)",
        { n = name, m = FW.CONFIG.start_money, l = FW.lang_of(pid), t = GetServerTime() })
    end
    factions.house_sync(pid)
  end)

  FW.q("SELECT skill, level FROM fw_skills WHERE name = @n", { n = name }, function(rows)
    if not rows then return end
    FW.state.skills[pid] = FW.state.skills[pid] or {}
    for _, r in ipairs(rows) do FW.state.skills[pid][r.skill] = r.level or 0 end
  end)
end

function FW.account_spawn(pid)
  local acc = FW.state.accounts[pid]
  if acc then
    local delta = acc.money - FW.purse(pid)
    if delta ~= 0 then GivePlayerMoney(pid, delta) end
    FW.set_purse_state(pid)
  end
  local house = FW.state.player_house[pid]
  if house then
    local h = FW.state.houses[house]
    if h then
      FW.say_raw(pid, FW.fmt("%s: treasury %s, prestige %d", house, FW.grosch(h.treasury), h.prestige), COLOR_YELLOW)
    end
  end
  pcall(AddPlayerActionHint, pid, "fw-menu", "f2", "Main menu", { binding = "fw.menu" })
  FW.sync_scoreboard(pid)
end

function FW.account_close(pid)
  FW.flush_earnings(pid)
  FW.save_money(pid)
  FW.state.skills[pid] = nil
  FW.state.work_cd[pid] = nil
  FW.state.dialogues[pid] = nil
  FW.state.pending[pid] = nil
  local name = FW.state.player_house[pid]
  if name and FW.state.houses[name] then FW.state.houses[name].members[GetPlayerName(pid):lower()] = nil end
  FW.state.player_house[pid] = nil
  FW.state.player_rank[pid] = nil
  FW.state.lang[pid] = nil
  FW.state.accounts[pid] = nil
  local draft = FW.state.drafts[pid]
  if draft and FW.draft_clear then FW.draft_clear(pid) end
end

function FW.sync_scoreboard(pid)
  pcall(SetPlayerState, pid, "purse", tostring(FW.purse(pid)))
end

-- ---------------------------------------------------------------- the character page

function FW.me_panel(pid)
  local house = FW.state.player_house[pid]
  local h = house and FW.state.houses[house]
  local skills = {}
  for _, skill in ipairs({ "mining", "survival", "craftsmanship", "houndmaster", "weaponsmithing", "scholarship" }) do
    skills[#skills + 1] = { key = skill, label = FW.skill_label(pid, skill), level = FW.skill_of(pid, skill) }
  end
  FW.open_frame(pid, "me")
  FW.push(pid, "me", {
    lang = FW.lang_of(pid),
    name = GetPlayerName(pid),
    money = FW.purse(pid),
    house = house,
    treasury = h and h.treasury or 0,
    prestige = h and h.prestige or 0,
    war = h and h.war or nil,
    rank = house and FW.house_rank(pid) or nil,
    admin = IsPlayerAdmin(pid) or false,
    level = GetPlayerLevel(pid) or 0,
    skills = skills,
  })
end

function FW.pay(pid, target, amount)
  amount = math.floor(tonumber(amount) or 0)
  if not target or amount <= 0 then FW.say(pid, "pay_usage") return end
  if FW.purse(pid) < amount then FW.say(pid, "no_money") return end
  GivePlayerMoney(pid, -amount)
  GivePlayerMoney(target, amount)
  FW.save_money(pid)
  FW.save_money(target)
  FW.set_purse_state(pid)
  FW.set_purse_state(target)
  local tax = math.floor(amount * FW.CONFIG.trade_tax)
  local house = FW.state.player_house[pid]
  if house and FW.state.houses[house] and tax > 0 then
    FW.state.houses[house].treasury = FW.state.houses[house].treasury + tax
    FW.persist_house(house)
  end
  FW.say(pid, "pay_done", FW.grosch(amount), GetPlayerName(target))
  FW.say(target, "pay_got", GetPlayerName(pid), FW.grosch(amount))
end

return FW