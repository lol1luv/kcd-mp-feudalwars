-- Feudal Wars build: the architect's blueprints. Objects are placed at the player's own
-- height, which is the true ground under them - the server has no heightmap to snap to,
-- so anything placed from a stand-still point lands exactly where a person stands.

local FW = require("feudalwars.core")

FW.CATALOG = {
  tent = {
    label = { en = "Campaign tent", ru = "Походная палатка" },
    parts = { { mesh = "objects/manmade/structures/living/tents/tent_big_fancy_a.cgf", dx = 0, dy = 0 } },
  },
  stall = {
    label = { en = "Market stall", ru = "Торговая лавка" },
    parts = {
      { mesh = "objects/manmade/task_specific_props/trade/merge_market_bread_stand.cgf", dx = 0, dy = 0 },
      { mesh = "objects/manmade/common_furniture/barrels/barrel_a.cgf", dx = 2.2, dy = 0.4 },
    },
  },
  camp = {
    label = { en = "Campfire", ru = "Костёр" },
    parts = {
      { mesh = "objects/manmade/task_specific_props/food_processing/cooking/fireplace_wood_a.cgf", dx = 0, dy = 0 },
      { mesh = "objects/manmade/common_furniture/crates/crate_low_a.cgf", dx = 1.8, dy = 1.0 },
    },
  },
  palisade = {
    label = { en = "Palisade", ru = "Частокол" },
    parts = { { mesh = "objects/manmade/structures/defensive/walls/palisade/palisade_wall_a_v1.cgf", dx = 0, dy = 0 } },
  },
  bench = {
    label = { en = "Work bench", ru = "Верстак" },
    parts = { { mesh = "objects/manmade/common_furniture/tables/table_long_a.cgf", dx = 0, dy = 0 } },
  },
  forge = {
    label = { en = "Field forge", ru = "Полевая кузня" },
    parts = {
      { mesh = "objects/manmade/task_specific_props/metal_industry/smithing/anvil.cgf", dx = 0, dy = 0 },
      { mesh = "objects/manmade/task_specific_props/metal_industry/smithing/forge_small_a.cgf", dx = 2.0, dy = 0 },
    },
  },
}

FW.CATALOG_ORDER = { "camp", "tent", "stall", "palisade", "bench", "forge" }

function FW.draft_clear(pid)
  local draft = FW.state.drafts[pid]
  if not draft then return end
  for _, id in ipairs(draft.ids or {}) do pcall(DeleteMapObject, id) end
  FW.state.drafts[pid] = nil
end

function FW.draft_new(pid, key)
  if not IsPlayerAdmin(pid) then
    FW.say(pid, "admins_only")
    return
  end
  key = tostring(key or ""):lower()
  local spec = FW.CATALOG[key]
  if not spec then
    FW.say_raw(pid, "no such structure in the catalogue: /build", COLOR_RED)
    return
  end
  FW.draft_clear(pid)
  local px, py, pz = GetPlayerPos(pid)
  local yaw = FW.round(GetPlayerYaw(pid), 15)
  local cos, sin = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
  local ids = {}
  for _, part in ipairs(spec.parts) do
    local x = px + (part.dx or 0) * cos - (part.dy or 0) * sin
    local y = py + (part.dx or 0) * sin + (part.dy or 0) * cos
    local z = pz + (part.dz or 0)
    local id, err = CreateMapObject(part.mesh, x, y, z, { yaw = yaw, scale = part.scale, persist = false, solid = true })
    if id then ids[#ids + 1] = id else FW.log("part refused: %s", tostring(err)) end
  end
  if #ids == 0 then
    FW.say_raw(pid, "the ground refused the draft here.", COLOR_RED)
    return
  end
  FW.state.drafts[pid] = { key = key, ids = ids, x = px, y = py, z = pz, yaw = yaw }
  FW.say_raw(pid, "the pieces stand before you. /arch save <name> keeps them, /arch cancel sweeps them.",
    COLOR_YELLOW)
  FW.build_panel(pid)
end

function FW.draft_save(pid, name)
  if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
  local draft = FW.state.drafts[pid]
  if not draft or #(draft.ids or {}) == 0 then
    FW.say_raw(pid, "nothing laid out - pick a structure first.", COLOR_RED)
    return
  end
  name = tostring(name or ""):lower():gsub("[^%w_%-]", "")
  if #name < 2 then
    FW.say_raw(pid, "give the blueprint a name: /arch save <name>", COLOR_RED)
    return
  end
  local parts = {}
  for _, id in ipairs(draft.ids) do
    local obj = GetMapObject(id)
    if obj then
      parts[#parts + 1] = {
        mesh = obj.mesh,
        dx = obj.x - draft.x, dy = obj.y - draft.y, dz = obj.z - draft.z,
        yaw = (obj.yaw or 0) - draft.yaw, scale = obj.scale,
      }
    end
  end
  if #parts == 0 then
    FW.say_raw(pid, "the draft vanished before it could be saved.", COLOR_RED)
    return
  end
  local bp = { name = name, parts = parts, author = FW.state.accounts[pid] and FW.state.accounts[pid].name or "" }
  FW.state.blueprints[name] = bp
  FW.x("INSERT INTO fw_blueprints (name, parts, author) VALUES (@n, @p, @a) " ..
    "ON DUPLICATE KEY UPDATE parts = @p2, author = @a2",
    { n = name, p = JsonEncode(parts), a = bp.author, p2 = JsonEncode(parts), a2 = bp.author })
  FW.draft_clear(pid)
  FW.say_raw(pid, FW.fmt("blueprint '%s' saved with %d part(s).", name, #parts), COLOR_YELLOW)
  FW.build_panel(pid)
end

function FW.draft_stamp(pid, name)
  if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
  name = tostring(name or ""):lower()
  local bp = FW.state.blueprints[name]
  if not bp then
    FW.say_raw(pid, "no such blueprint - /arch list", COLOR_RED)
    return
  end
  local px, py, pz = GetPlayerPos(pid)
  local yaw = FW.round(GetPlayerYaw(pid), 15)
  local cos, sin = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
  local made = 0
  for _, part in ipairs(bp.parts) do
    local x = px + (part.dx or 0) * cos - (part.dy or 0) * sin
    local y = py + (part.dx or 0) * sin + (part.dy or 0) * cos
    local z = pz + (part.dz or 0)
    local id = CreateMapObject(part.mesh, x, y, z, {
      yaw = yaw + (part.yaw or 0), scale = part.scale, persist = true, solid = true,
    })
    if id then made = made + 1 end
  end
  if made == 0 then
    FW.say_raw(pid, "the ground refused the blueprint here.", COLOR_RED)
    return
  end
  FW.say_raw(pid, FW.fmt("'%s' raised here (%d part(s)).", name, made), COLOR_YELLOW)
  FW.build_panel(pid)
end

function FW.build_panel(pid)
  if not IsPlayerAdmin(pid) then return end
  local lang = FW.lang_of(pid)
  local structures = {}
  for _, key in ipairs(FW.CATALOG_ORDER) do
    local spec = FW.CATALOG[key]
    if spec then
      structures[#structures + 1] = {
        key = key, label = (spec.label[lang] or spec.label.en), parts = #spec.parts,
      }
    end
  end
  local blueprints = {}
  for name, bp in pairs(FW.state.blueprints) do
    blueprints[#blueprints + 1] = { key = name, label = name, parts = #bp.parts }
  end
  table.sort(blueprints, function(a, b) return a.key < b.key end)
  local draft = FW.state.drafts[pid]
  FW.open_frame(pid, "build")
  FW.push(pid, "build", {
    lang = lang, structures = structures, blueprints = blueprints,
    has_draft = draft ~= nil, draft_parts = draft and #draft.ids or 0,
  })
end

function FW.blueprints_load_all()
  local rows = FW.qs("SELECT name, parts, author FROM fw_blueprints")
  if not rows then return end
  for _, r in ipairs(rows) do
    local ok, parts = pcall(JsonDecode, r.parts or "[]")
    if ok and type(parts) == "table" then
      FW.state.blueprints[r.name] = { name = r.name, parts = parts, author = r.author or "" }
    end
  end
  FW.log("blueprints: %d saved", #rows)
end

return FW