-- ============================================================================
-- Feudal Wars v5 — RPC Web Bridge & Dispatcher
-- ============================================================================

local FW = require("feudalwars.core")

FW.bridge = {}

function FW.bridge.handle(pid, frame, event, json_data)
  if event == "menu.ready" or event == "menu.open" then
    FW.ui.open_menu(pid)
  elseif event == "menu.lang" then
    local pdata = FW.state.players[pid]
    if pdata then
      pdata.lang = pdata.lang == "ru" and "en" or "ru"
      FW.player.save(pid)
      FW.ui.open_menu(pid)
    end
  elseif event == "menu.close" then
    if SetPlayerCursor then SetPlayerCursor(pid, false) end
    if SetPlayerWebFocus then SetPlayerWebFocus(pid, frame or "menu", false, false) end
  end
end

return FW.bridge
