-- Feudal Wars people: the NPC constructor and the conversations. Every placed person
-- speaks through the game's own dialogue pages, so a foreman, a guard and a smith feel
-- like the game's people rather than a list of menu buttons.

local FW = require("feudalwars.core")
local world = require("feudalwars.world")

function FW.people_all()
  local out = {}
  for _, n in pairs(FW.state.people_list) do out[#out + 1] = n end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

local function class_price(name)
  local ok, price = pcall(GetItemClassPrice, name)
  if ok and type(price) == "number" then return math.max(1, math.floor(price)) end
  return 10
end

function FW.npc_admin_panel(pid)
  if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
  local lang = FW.lang_of(pid)
  local list = {}
  for _, n in ipairs(FW.people_all()) do
    list[#list + 1] = {
      id = n.id, name = n.name, role = n.role, role_label = FW.role_label(pid, n.role),
      x = math.floor(n.x), y = math.floor(n.y),
      stock = (n.data and n.data.stock and #n.data.stock) or 0,
    }
  end
  local items = {}
  if FW.ready() then
    for _, it in ipairs(FindItems("", 200) or {}) do
      items[#items + 1] = {
        item = it.name,
        label = (it.display ~= "" and it.display) or it.name,
        price = class_price(it.name),
      }
    end
    table.sort(items, function(a, b) return a.label < b.label end)
  end
  FW.open_frame(pid, "npc")
  FW.push(pid, "npc", {
    lang = lang, npcs = list, items = items,
    roles = { "vendor", "trainer", "guard", "quest", "foreman", "civilian" },
  })
end

function FW.npc_stock_set(pid, id, item, price)
  if not IsPlayerAdmin(pid) then return end
  local n = FW.state.people_list[id]
  if not n or n.role ~= "vendor" then return end
  price = math.max(1, math.floor(tonumber(price) or 10))
  n.data = n.data or {}
  n.data.stock = n.data.stock or {}
  local found = false
  for _, row in ipairs(n.data.stock) do
    if tostring(row.item) == tostring(item) then row.price = price found = true end
  end
  if not found then n.data.stock[#n.data.stock + 1] = { item = item, price = price, amount = -1 } end
  FW.person_save(n)
  if n.shop then pcall(SetShopItem, n.shop, item, price, -1) end
  FW.say_raw(pid, "the good is on the counter.", COLOR_YELLOW)
  FW.npc_admin_panel(pid)
end

-- ---------------------------------------------------------------- conversations

FW.DIALOGUE = {
  foreman = {
    en = { text = "The work is honest and the pay is coin. Will you take a swing?",
      rows = { "Where is the work?", "What does it pay?", "Nothing for now." } },
    ru = { text = "Работа честная, и платят монетой. Возьмёшься за инструмент?",
      rows = { "Где работа?", "Сколько платят?", "Пока ничего." } },
  },
  guard = {
    en = { text = "Keep the peace, and the peace keeps you.", rows = { "I saw a crime.", "Who holds this land?", "Good day." } },
    ru = { text = "Блюди мир, и мир поблюдёт тебя.", rows = { "Я видел преступление.", "Кто держит эту землю?", "Доброго дня." } },
  },
  trainer = {
    en = { text = "Skill is bought with sweat, and coin shortens the road. Shall we begin?",
      rows = { "Teach me.", "What do you teach?", "Later." } },
    ru = { text = "Уменье берётся потом, а монета укорачивает путь. Начнём?",
      rows = { "Учи меня.", "Чему учишь?", "Позже." } },
  },
  quest = {
    en = { text = "There is always work for willing hands.", rows = { "What needs doing?", "Nothing today." } },
    ru = { text = "На охотливые руки работа всегда сыщется.", rows = { "Что надобно сделать?", "Нынче ничего." } },
  },
  civilian = {
    en = { text = "God keep you, stranger.", rows = { "Farewell." } },
    ru = { text = "Храни тебя Бог, странник.", rows = { "Прощай." } },
  },
}

function FW.talk(pid, n)
  if not n then return end
  local lang = FW.lang_of(pid)
  local pack = FW.DIALOGUE[n.role] or FW.DIALOGUE.civilian
  local page = pack[lang] or pack.en
  local id = (FW.state.dialog_next or 1)
  FW.state.dialog_next = id + 1
  FW.state.dialogues[pid] = { id = id, npc = n, page = 1 }
  local ok, err = ShowPlayerDialogue(pid, id, "", page.text, page.rows, n.actor)
  if not ok then
    FW.log("dialogue refused: %s", tostring(err))
    FW.person_open(pid, n)
  end
end

function FW.dialogue_answer(pid, id, option, reason)
  local st = FW.state.dialogues[pid]
  if not st or st.id ~= id then return end
  if option == 0 then
    FW.state.dialogues[pid] = nil
    return
  end
  local n = st.npc
  if not n then FW.state.dialogues[pid] = nil return end
  local lang = FW.lang_of(pid)

  if n.role == "foreman" then
    if option == 1 then
      local px, py = GetPlayerPos(pid)
      local zone, d = world.zone_nearest(px, py)
      if zone then
        local def = FW.TRADE[zone.trade]
        local name = (zone.label ~= "" and zone.label) or (def.label[lang] or def.label.en)
        FW.say_raw(pid, FW.t(pid, "work_hint", name, def.do_label[lang] or def.do_label.en), COLOR_YELLOW)
      else
        FW.say(pid, "work_none")
      end
    elseif option == 2 then
      local zone = world.zone_at(n.x, n.y, n.z)
      local def = zone and FW.TRADE[zone.trade]
      FW.say_raw(pid, FW.fmt("%s groschen a strike, and more as your %s grows.",
        FW.grosch(def and def.pay or 5), FW.skill_label(pid, def and def.skill or "survival")), COLOR_YELLOW)
    end
    FW.state.dialogues[pid] = nil
  elseif n.role == "guard" then
    if option == 1 then
      FW.say(pid, "crime_reported")
      FW.admin_log(pid, "reported a crime to " .. n.name)
    elseif option == 2 then
      local houses = {}
      for name in pairs(FW.state.houses) do houses[#houses + 1] = name end
      table.sort(houses)
      FW.say_raw(pid, #houses > 0 and ("The houses here: " .. table.concat(houses, ", ")) or "No house holds this land yet.",
        COLOR_YELLOW)
    end
    FW.state.dialogues[pid] = nil
  elseif n.role == "trainer" then
    FW.state.dialogues[pid] = nil
    FW.person_open(pid, n)
  elseif n.role == "quest" then
    if option == 1 then FW.work_report(pid) end
    FW.state.dialogues[pid] = nil
  else
    FW.state.dialogues[pid] = nil
  end
end

return FW