-- Feudal Wars justice: the crown's console, moderation, the map editor.
-- Every power is a registered command with the admin flag, so the server's own /help
-- shows them to those who may use them.

local FW = require("feudalwars.core")

function FW.admin_panel(pid)
  if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
  local players = {}
  for _, p in ipairs(GetPlayers() or {}) do
    players[#players + 1] = {
      id = p, name = GetPlayerName(p), house = FW.state.player_house[p],
      money = FW.purse(p), ping = GetPlayerPing(p),
    }
  end
  FW.open_frame(pid, "admin")
  FW.push(pid, "admin", {
    lang = FW.lang_of(pid), players = players, log = FW.state.admin_log,
    house = FW.state.player_house[pid], admin = true,
  })
end

function FW.editor(pid)
  if not IsPlayerAdmin(pid) then FW.say(pid, "admins_only") return end
  if not IsPlayerWebReady(pid) then
    FW.say_raw(pid, "the editor needs the web layer: turn server interfaces on in the launcher and rejoin.", COLOR_RED)
    return
  end
  local ok, err = SetPlayerEditor(pid, "admin")
  if ok then
    FW.say_raw(pid, "editor open: fly, pick a mesh, place with the mouse. /editor again to close.",
      COLOR_YELLOW)
  else
    FW.say_raw(pid, "the editor refused: " .. tostring(err), COLOR_RED)
  end
end

return FW