-- ============================================================================
-- Feudal Wars v5 — Web RPC Dispatcher
-- ============================================================================

local FW = require("feudalwars.core")

FW.bridge = {}

function FW.bridge.handle(pid, name, payload, source)
  local pdata = FW.state.players[pid]
  if not pdata then return end

  if name == "menu.close" or name == "me.close" or name == "hall.close" then
    DestroyPlayerWebFrame(pid, source or "menu")
    SetPlayerWebFocus(pid, source or "menu", false, false)
    SetPlayerCursor(pid, false)
  elseif name == "menu.lang" then
    pdata.lang = pdata.lang == "ru" and "en" or "ru"
    FW.player.save(pid)
    FW.ui.open_menu(pid)
  elseif name == "menu.run" then
    local action = type(payload) == "table" and payload.action or tostring(payload or "")
    if action == "me" then
      FW.ui.open_me(pid)
    elseif action == "hall" then
      FW.ui.open_hall(pid)
    elseif action == "job" then
      if SendChatMessage then SendChatMessage(pid, FW.t(pid, "kit_desc")) end
    end
  end
end

return FW.bridge
