local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "ReleaseSpiritOnGhost"

--[[
This plugin will try to RepopMe() and walk to the corpse.

This does not take into account dungeon instances, unreachable
corpses, does not (yet) default to spirit healer, has no time-out
when failing to reach corpse...
]]

-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.LOW -- System
plugin.callbacks = {}
plugin.handlers = {}

local tickerName = plugin.name .. "_" .. "TickGhostWalk"

local previousCtx = nil
local corpseTargetSet = false

plugin.callbacks.OnMovementFinished = function(ctx, type, x, y, z)
    if not corpseTargetSet then return end
    if type ~= "xyz" then return end
    
    local cx, cy, cz = GetCorpsePosition()
    if x == cx and y == cy and z == cz then
        -- we did it?
        if StaticPopup1Button1 ~= nil then
                GWB:Print("Taking ress (2)?")
                Unlock(StaticPopup1Button1.Click, StaticPopup1Button1)
            end
    end
end
plugin.callbacks.OnPlayerDeath = function(ctx)
    -- RepopMe?
    local ded = UnitIsDead("player") -- true on corpse ded
    local dedOrGhost = UnitIsDeadOrGhost("player") -- true on corpse ded
    if ded or dedOrGhost then
        Unlock(RepopMe)
        GWB:Print("RepopMe(),", plugin.name)
        return true -- consumed fr fr
    end

    GWB:Debug("Skipped OnDead for ReleaseSpirit!")
    return false
end

-- got unghosted Uwu
-- NOTE: This is when you take Sickness!!
plugin.callbacks.OnPlayerUnghost = function(ctx)
    GWB:Print("Unghosted!")

    if GWB.State:getCurrentState() == "plugin.ReleaseSpiritOnGhost" then
        --GWB.State:callState("plugin.RestHandler")
        GWB.State:returnState()
    end

    GWB:TickerSetState(tickerName, false)
    previousCtx = nil -- jobs done!
end

-- we aren't alive, we are still a ghost
plugin.callbacks.OnPlayerAlive = function(ctx)
    GWB:Print("Corpse turned into bones! (and we in a ghost?)")

    if GWB.State:getCurrentState() == "plugin.ReleaseSpiritOnGhost" then
        GWB.State:returnState()
    end

    if pendingCtx then return true end -- interrupt?

    -- must be dead AND ghost
    local ded = UnitIsDead("player")
    local dedOrGhost = UnitIsDeadOrGhost("player")
    print("ded", ded, "dedOrGhost", dedOrGhost)
    -- do not consume :3
    if ded or not dedOrGhost then return false end

    previousCtx = ctx;

    GWB:Print("Dispatching Ghost Corpse routine!")

    corpseTargetSet = false
    GWB:TickerSetState(tickerName, true)
    return true
end


local lastCorpseUpdate = 0
local function TickGhostWalk()
    -- plug walk :3
    
    local tick = GetTime()
    -- added lastCorpseUpdate as we may want to poll new pos
    -- as our player may fall off a cliff, making it possible
    -- for a uncreachable 'next' point
    --print(tick, ">", lastCorpseUpdate+2)
    if not corpseTargetSet or tick > lastCorpseUpdate+2 then
        -- GetCorpsePosition
        local cx, cy, cz = GetCorpsePosition()
        GWB:Print("TickGhostWalk, set CorposePos", cx, cy, cz)
        corpseTargetSet = GWB.Mover:MoveToXYZ(cx, cy, cz)
        lastCorpseUpdate = tick
    else
        local isMoving = GWB.Mover:IsMoving()
        --GWB:Print("TickGhostWalk, isMoving", isMoving)
        if not isMoving then
            -- accept corpse?
            if StaticPopup1Button1 ~= nil then
                GWB:Print("Taking ress?")
                Unlock(StaticPopup1Button1.Click, StaticPopup1Button1)
            end
        end
    end

end

plugin.handlers.stateTick = function()
    --if not corpseTargetSet then
        TickGhostWalk()
    --end
end

GWB:RegisterTicker(tickerName, TickGhostWalk)
GWB:RegisterPlugin(plugin)
