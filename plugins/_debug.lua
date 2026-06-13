local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "_debug"


-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.DEFAULT -- nothing better to do ;_;
plugin.callbacks = {}
plugin.handlers = {}

plugin.handlers.TestDebug = function()

end

local pendingCtx = nil
local cmd = GWB.enums.cb_action

plugin.callbacks.OnObjectLoaded = function(object)
    -- We can use Nn to inspect the object, no drops on object parsing

    -- e.g. we could check if GWB.state.type == "grind" and return a enum?
    GWB:Print("OnObjectLoaded")
    return cmd.ATTACK -- we now attack?
end

--[[
plugin.callbacks.OnObjectStateChanged = function(object, state)
    -- do we rly need this? yes, cuz if shit dies we need to know?
    -- but target can despawn? player can die? etc etc?
    -- do we track object?
end]]

plugin.callbacks.OnPlayerDeath = function(ctx)
    -- we ded? what we do now? change waypoints for gravyard or wait healer etc?
    -- we should have default "walk to corpse" and/or "walk to dung entry" idk?
    -- diff profiles may require diff types of getting back to life

    if UnitIsDead("player") and not UnitIsDeadOrGhost("player") then
        GWB:Print("OnPlayerDeath, RepopMe()")
        Unlock(RepopMe)
        return true
    end

    if UnitIsDead("player") and UnitIsDeadOrGhost("player") then
        if pendingCtx then return true end

        -- TODO: start walking healing?
    end

    return false
end
plugin.callbacks.OnPlayerLevelUp = function()
    -- take it up to the next lvl?
    GWB:Print("OnPlayerLevelUp")
end

plugin.callbacks.OnPlayerEnterCombat = function()
    -- u wanna fight?
    GWB:Print("OnPlayerEnterCombat")
end
plugin.callbacks.OnPlayerLeaveCombat = function()
    -- as long we no ded ;_;
    -- scan for corpses and see if we need to loot
    GWB:Print("OnPlayerLeaveCombat")
end

plugin.callbacks.OnPlayerChangeMapOrInstance = function()
    -- in case we get phased? gotta switch maps etc
    GWB:Print("OnPlayerChangeMapOrInstance")
end
plugin.callbacks.OnLootStarted = function()
    -- gotta let em know?
    GWB:Print("OnLootStarted")
end
plugin.callbacks["OnLootFinished"] = function(...)
    -- gotta wait b4 resume?
    -- and maybe check the drip we got!
    GWB:Print("OnLootFinished", ...)
end
plugin.callbacks.OnLootFailed = function()
    -- eh? to handle blacklisting?
    GWB:Print("OnLootFailed")
end
plugin.callbacks.OnAttackEnemyStarted = function()
    -- let know when we try to cast/attack/engage with an enemy?
    GWB:Print("OnAttackEnemyStarted")
end
plugin.callbacks.OnAttackEnemyFailed = function()
    -- do we know if we fail? we should time-out after X sec of nothing and have logic to proceed routine?
    GWB:Print("OnAttackEnemyFailed")
end
plugin.callbacks.OnAttackEnemyFinished = function()
    -- biatch we slay!
    GWB:Print("OnAttackEnemyFinished")
end
plugin.callbacks.OnGossipStart = function()
    -- we started the gossi, dont move or we jinx it?
    GWB:Print("OnGossipStart")
end
plugin.callbacks.OnGossipFailed = function()
    -- bad? re-try? maybe vendor isn't even here?
    GWB:Print("OnGossipFailed")
end
plugin.callbacks.OnGossipFinished = function()
    -- gossip dialog is now open for bussines? we get data on the gossip window?
    GWB:Print("OnGossipFinished")
end
plugin.callbacks.OnMovementStarted = function()
    -- we are actually moving to somewhere?
    GWB:Print("OnMovementStarted")
end
plugin.callbacks.OnMovementFailed = function()
    -- we got stuck and failed to navigate somewhere?
    GWB:Print("OnMovementFailed")
end


-- some misc shit?
plugin.callbacks.OnPartyOrRaidInviteRequest = function()
    -- yay or nay?
    GWB:Print("OnPartyOrRaidInviteRequest")
end
plugin.callbacks.OnPartyOrRaidGroupJoined = function()
    -- we got in yeah? xD
    GWB:Print("OnPartyOrRaidGroupJoined")
end
-- vote to kick?
-- LFG states?
-- Quest completion?
plugin.callbacks.OnQuestTurninStarted = function()
    -- request to turn-in quest
    GWB:Print("OnQuestTurninStarted")
end
plugin.callbacks.OnQuestTurningFailed = function()
    -- ¡Ay, caramba!
    -- should also get error codes somehow?
    GWB:Print("OnQuestTurningFailed")
end
plugin.callbacks.OnQuestCompleted = function()
    -- tada!
    GWB:Print("OnQuestCompleted")
end
plugin.callbacks.OnNewQuestAvailable = function()
    -- either from nearby NPC or auto logged into questlog
    GWB:Print("OnNewQuestAvailable")
end
plugin.callbacks.OnNewQuestStarted = function()
    GWB:Print("OnNewQuestStarted")
end


-- =============================
-- We need some UI triggers too
-- =============================

plugin.callbacks.OnGUIUpdateWaypoints = function()
    GWB:Print("OnGUIUpdateWaypoints")
end
plugin.callbacks.OnGUIResetWaypoints = function()
    GWB:Print("OnGUIResetWaypoints")
end
plugin.callbacks.OnGUIButtonStartToggle = function()
    GWB:Print("OnGUIButtonStartToggle")
end







--GWB.plugins[plugin.name] = plugin -- register it
GWB:RegisterPlugin(plugin)
