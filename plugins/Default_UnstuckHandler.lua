local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "UnstuckHandler"


-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.LOW -- System
plugin.callbacks = {}
plugin.handlers = {}

local tickerName = "GWBMoverTick"
GWB:RegisterTicker(tickerName, GWB.Mover.Tick)


local lastStuckCoord = nil
local stuckCounter = 0
local MAX_STUCK_COUNT = 10 -- 10 ticks that is

local unstuckX, unstuckY, unstuckZ = 0, 0, 0
local prevX, prevY, prevZ = 0, 0, 0

local function ClearStuckTracker()
    -- clear
    lastStuckCoord = nil
    stuckCounter = 0
end

--[["

/run GWB.Mover:MoveToObject("target")

/run GWB.Mover:MoveToXYZ(-806, 4423, 738)

/run GWB.Mover.Tick()

/run GWB.Mover:MoveToRawXYZ(806, 4423, 738) -- raw wont path

]]

-- TODO: COPY MOV STATE SO WE CAN 'REPLAY' AFTER COMBAT!
local continueMovAfterCombat = false

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    -- stop movement!
    if GWB.Mover:IsMoving() then
        GWB:Print("EnterCombat, pause active mover")
        GWB.Mover:HaltMovement()
        continueMovAfterCombat = true
    end

    return false -- let it rip!
end
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    -- stop movement!
    if continueMovAfterCombat then
        GWB:Print("LeaveCombat, resume mover")
        GWB.Mover:StartMove() -- continue where left off?
        continueMovAfterCombat = false
    end
    
    return false
end

-- NOTE: unused?
plugin.callbacks.OnMoverStarted = function(ctx)
    --GWB:Print("OnMoverStarted")
    ClearStuckTracker()
    GWB:TickerSetState(tickerName, true)
    return true
end
-- NOTE: unused?
plugin.callbacks.OnMoverFailed = function(ctx, err)
    ClearStuckTracker()
    GWB:Print("OnMoverFailed, err:", err)
    GWB:TickerSetState(tickerName, false)
    return false
end

-- used ofc :3
plugin.callbacks.OnMovementFinished = function(ctx, type, x, y, z)
    if type ~= "xyz" then return end

    if unstuckX == 0 then return end

    if unstuckX~=x or unstuckY~=y or unstuckZ~=z then return end

    print("UNSTUCK DONE?")
    GWB.Mover:MoveToXYZ(prevX, prevY, prevZ)
    unstuckX = nil


    -- this is us! we moved away?!
    if GWB.State:getCurrentState() == "plugin.UnstuckHandler" then
        print("Taking out state from UnstuckHandler")
        GWB.State:returnState()
    end
end
plugin.callbacks.OnMovementFailed = function(ctx, type, x, y, z)
    if type ~= "xyz" then return end

    if unstuckX~=x or unstuckY~=y or unstuckZ~=z then return end

    -- this is us! we failed! go again?
    print("BRO WE FAILED")
end
--[[
-- we must tick for as long as we need to?
plugin.handlers.TickMovement = function()

end]]

-- This always ticks, and will invoke our state if "stuck"
local function tickStuckDetection()
    -- its okay to be "stuck" if we aren't instructed to move :3
    if not GWB.Mover:IsMoving() then
        return
    end

    if GWB.State:getCurrentState() == "plugin.UnstuckHandler" then
        --GWB:Debug("skip unstuck")
        return
    end

    if lastStuckCoord == nil then
        GWB.Mover:Update()
        lastStuckCoord = { GWB.Mover:GetPlayerPosition() }
        return
    end

    GWB.Mover:Update()
    local coords = { GWB.Mover:GetPlayerPosition() }

    local dist = GWB.Utils:Distance(coords[1], coords[2], 0, lastStuckCoord[1], lastStuckCoord[2], 0)
    if dist > 0.75 then
        -- not stuck, check again later
        ClearStuckTracker()
        return 
    end

    -- we didn't progress enough?
    if stuckCounter == MAX_STUCK_COUNT-3 then
        -- try jumping?
        Unlock(JumpOrAscendStart)
    end
    if stuckCounter > MAX_STUCK_COUNT then
        stuckCounter = 0 -- so we don't get inf loop
        --GWB:Debug("UNSTUCKING!!")
        GWB.State:callState("plugin.UnstuckHandler")
        -- we are stuck fr, do unstuck?
        prevX, prevY, prevZ = GWB.Mover:GetTargetXYZ()
        GWB.Mover:Stop()
        local x, y, z = 0, 0, 0
        local a1 = math.random(5, 15)
        local b1 = math.random(5, 15)
        local a2 = math.random(0, 2)
        local b2 = math.random(0, 2)
        if a2 == 1 then
            a1 = -a1
        end
        if b2 == 1 then
            b1 = -b1
        end
        unstuckX = coords[1] + a1
        unstuckY = coords[2] + b1
        unstuckZ = coords[3]
        GWB.Mover:MoveToXYZ(unstuckX, unstuckY, unstuckZ)
        ClearStuckTracker()

        -- time-out unstuck after 5 sec? in case we get stuck in the unstuck?
        C_Timer.After(5, function()
            if GWB.State:getCurrentState() == "plugin.UnstuckHandler" then
                GWB:Debug("skip unstuck!!")
                GWB.State:returnState()
                return
            end
        end)
    end

    stuckCounter = stuckCounter + 1
    --GWB:Debug("stuckCounter", stuckCounter)
end

plugin.handlers.stateTick = function()
    -- eh?
end

GWB:RegisterTicker(plugin.name .. "tickStuckDetection", tickStuckDetection)
GWB:TickerSetState(plugin.name .. "tickStuckDetection", true)

GWB:RegisterPlugin(plugin)
