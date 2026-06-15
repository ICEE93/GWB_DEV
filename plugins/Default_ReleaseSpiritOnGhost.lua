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
    if not UnitIsDeadOrGhost("player") then
        return
    end

    local cx, cy, cz = GetCorpsePosition()
    if not cx then return end

    local px, py, pz = ObjectPosition("player")
    if px then
        local distToCorpse = math.sqrt((cx-px)^2 + (cy-py)^2 + (cz-pz)^2)
        
        -- If we are within resurrection range, check if it's safe to res early
        if distToCorpse <= 38.0 then
            local isSafe = true
            local os = Objects()
            local oldFocus = GetFocus()
            
            for i=1, #os do
                local o = os[i]
                if ObjectType(o) == 5 then
                    SetFocus(o)
                    if not UnitIsDead("focus") and UnitCanAttack("player", "focus") then
                        local mx, my, mz = ObjectPosition(o)
                        if mx then
                            local distToMob = math.sqrt((mx-px)^2 + (my-py)^2 + (mz-pz)^2)
                            -- Require 22 yards of safety
                            if distToMob < 22.0 then
                                isSafe = false
                                break
                            end
                        end
                    end
                end
            end
            
            SetFocus(oldFocus)
            
            local canRes = StaticPopup1Button1 and StaticPopup1Button1:IsVisible()
            
            if isSafe and canRes then
                GWB:Print("Safe spot found! Taking ress.")
                if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                    if GWB.EZMover:IsMoving() then GWB.EZMover:Stop() end
                elseif GWB.Mover then
                    if GWB.Mover:IsMoving() then GWB.Mover:Stop() end
                end
                
                Unlock(StaticPopup1Button1.Click, StaticPopup1Button1)
                return
            end
        end
    end

    local tick = GetTime()
    if not corpseTargetSet or tick > lastCorpseUpdate+2 then
        GWB:Print("TickGhostWalk, set CorposePos", cx, cy, cz)
        
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            corpseTargetSet = GWB.EZMover:MoveToXYZ(cx, cy, cz)
        else
            corpseTargetSet = GWB.Mover:MoveToXYZ(cx, cy, cz)
        end
        lastCorpseUpdate = tick
    else
        local isMoving = false
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            isMoving = GWB.EZMover:IsMoving()
        elseif GWB.Mover then
            isMoving = GWB.Mover:IsMoving()
        end
        
        if not isMoving then
            -- We arrived exactly at the corpse, or pathing failed. Take res anyway if possible.
            local canRes = StaticPopup1Button1 and StaticPopup1Button1:IsVisible()
            if canRes then
                GWB:Print("Arrived at corpse (or stuck). Taking ress anyway.")
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
