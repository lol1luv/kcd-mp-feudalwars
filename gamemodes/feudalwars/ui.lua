-- ============================================================================
-- Feudal Wars v5 — UI Handler & Chat Commands
-- ============================================================================

local FW = require("feudalwars.core")

FW.ui = {}

function FW.ui.init()
  FW.ui.register_commands()
  FW.log("UI & chat commands registered.")
end

function FW.ui.open_menu(pid)
  local pdata = FW.state.players[pid]
  if not pdata then return end

  if SetPlayerCursor then SetPlayerCursor(pid, true) end
  if SetPlayerWebFocus then SetPlayerWebFocus(pid, "menu", true, true) end
end

function FW.ui.register_commands()
  if not AddCommandHandler then return end

  AddCommandHandler("purse", function(pid)
    local pdata = FW.state.players[pid]
    if pdata then
      local msg = FW.fmt("%s: %s %s", FW.t(pid, "purse"), FW.grosch(pdata.purse), FW.t(pid, "groschen"))
      SendChatMessage(pid, msg)
    end
  end)

  AddCommandHandler("kit", function(pid)
    SendChatMessage(pid, FW.t(pid, "kit_desc"))
  end)

  AddCommandHandler("menu", function(pid)
    FW.ui.open_menu(pid)
  end)
end

return FW.ui
