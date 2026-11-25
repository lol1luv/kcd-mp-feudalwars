-- ============================================================================
-- Feudal Wars v5 — NPC & Interaction Subsystem
-- ============================================================================

local FW = require("feudalwars.core")

FW.npc = {}

function FW.npc.init()
  FW.log("NPC subsystem ready.")
end

function FW.npc.interact(pid, actor_id)
  local pdata = FW.state.players[pid]
  if not pdata then return end
  FW.log("player %d interacted with actor %d", pid, actor_id)
end

return FW.npc
