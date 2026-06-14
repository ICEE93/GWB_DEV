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
local MAX_STUCK_COUNT = 20 -- Increased from 10 to 20 for less aggressive unstuck detection
local MIN_STUCK_DIST = 0.3 -- Reduced from 0.75 to 0.3 for more lenient stuck detection

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

local continueMovAfterCombat = false

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    -- stop movement!
    if GWB.Settings.UseEZNavSafe then
        if GWB.EZMover:IsMoving() then
            GWB:Print("EnterCombat, pause active EZMover")
            GWB.EZMover:Stop()
            continueMovAfterCombat = true
        end
    else
        if GWB.Mover:IsMoving() then
            GWB:Print("EnterCombat, pause active mover")
            GWB.Mover:HaltMovement()
            continueMovAfterCombat = true
        end
    end

    return false -- let it rip!
end
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    -- Check for lootable objects nearby before resuming movement
    if continueMovAfterCombat then
        local px, py, pz = ObjectPosition("player")
        if px then
            local os = Objects()
            local hasLoot = false
            for i = 1, #os do
                local o = os[i]
                -- Check if object is lootable using CanLootUnit for units or check object type
                local canLoot = false
                local typeId = ObjectType(o)
                if typeId == 5 then  -- Unit
                    canLoot = CanLootUnit(o)
                elseif typeId == 3 or typeId == 4 then  -- Item or GameObject
                    canLoot = IsLootable(o)
                end

                if canLoot then
                    local ox, oy, oz = ObjectPosition(o)
                    if ox then
                        local dist = math.sqrt((ox-px)^2 + (oy-py)^2 + (oz-pz)^2)
                        if dist < 10.0 then
                            hasLoot = true
                            break
                        end
                    end
                end
            end

            if hasLoot then
                GWB:Print("LeaveCombat: Loot nearby, delaying movement resume")
                -- Check again in 2 seconds
                C_Timer.After(2.0, function()
                    if not UnitAffectingCombat("player") then
                        GWB:Print("LeaveCombat: Resuming movement after loot check")
                        if GWB.Settings.UseEZNavSafe then
                            if GWB.EZMover.StartMove then GWB.EZMover:StartMove() end
                        else
                            GWB.Mover:StartMove()
                        end
                        continueMovAfterCombat = false
                    end
                end)
                return false
            end
        end

        GWB:Print("LeaveCombat, resume mover")
        if GWB.Settings.UseEZNavSafe then
            if GWB.EZMover.StartMove then GWB.EZMover:StartMove() end
        else
            GWB.Mover:StartMove() -- continue where left off?
        end
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
    unstuckX = 0
    unstuckY = 0
    unstuckZ = 0

    -- this is us! we moved away?!
    if GWB.State:getCurrentState() == "plugin.UnstuckHandler" then
        print("Taking out state from UnstuckHandler")
        GWB.State:returnState()
        -- Resume original movement instead of moving backward
        if prevX ~= 0 and prevY ~= 0 then
            if GWB.Settings.UseEZNavSafe then
                GWB.EZMover:MoveToXYZ(prevX, prevY, prevZ)
            else
                GWB.Mover:MoveToXYZ(prevX, prevY, prevZ)
            end
        end
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
    if dist > MIN_STUCK_DIST then
        -- not stuck, check again later
        ClearStuckTracker()
        return
    end

    -- we didn't progress enough?
    if stuckCounter == MAX_STUCK_COUNT-5 then
        -- try jumping?
        Unlock(JumpOrAscendStart)
    end
    if stuckCounter == MAX_STUCK_COUNT-3 then
        -- Try jumping while moving forward for low obstacles
        Unlock(JumpOrAscendStart)
        -- Also try moving slightly forward while jumping
        local px, py, pz = GWB.Mover:GetPlayerPosition()
        if px then
            local forwardX, forwardY = px + 2.0, py + 2.0
            ClickToMove(forwardX, forwardY, pz)
        end
    end
    if stuckCounter > MAX_STUCK_COUNT then
        stuckCounter = 0 -- so we don't get inf loop
        --GWB:Debug("UNSTUCKING!!")
        GWB.State:callState("plugin.UnstuckHandler")
        -- we are stuck fr, do unstuck?
        prevX, prevY, prevZ = GWB.Mover:GetTargetXYZ()
        GWB.Mover:Stop()

        -- Simplified unstuck: only try forward movement, no backward/strafing
        local unstuckX, unstuckY, unstuckZ = coords[1], coords[2], coords[3]

        -- Unstuck: We respect the user's wish to generally move forward toward the target,
        -- but we MUST apply an angle offset so we actually walk AROUND the obstacle (like a tree).
        local dx = prevX - coords[1]
        local dy = prevY - coords[2]
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist > 0.1 then
            -- Base forward direction
            local baseAngle = math.atan2(dy, dx)
            -- Apply a random angle offset between 30 and 90 degrees (left or right)
            local offsetAngle = (math.random() * (math.pi/3)) + (math.pi/6)
            if math.random() > 0.5 then
                offsetAngle = -offsetAngle
            end
            
            local finalAngle = baseAngle + offsetAngle
            
            -- Move forward-diagonally 3-5 yards
            local forwardDist = math.random(3, 5)
            unstuckX = coords[1] + math.cos(finalAngle) * forwardDist
            unstuckY = coords[2] + math.sin(finalAngle) * forwardDist
        else
            -- Fallback: try small random forward offset
            local angle = math.random() * math.pi * 2
            unstuckX = coords[1] + math.cos(angle) * 3
            unstuckY = coords[2] + math.sin(angle) * 3
        end

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
