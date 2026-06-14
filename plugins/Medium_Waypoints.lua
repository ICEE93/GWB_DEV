local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "Waypoints"

plugin.author = "your_name"

--[[

Just a thing that can take waypoints, we then Mover:MoveToXYZ
to them to get dynamic pathing!

]]

local tickerNameCombat = plugin.name .. "_" .. "test"

-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.LOW
plugin.callbacks = {}
plugin.handlers = {}

plugin.settings = {
    ["use_glider"] = {
        ["label"] = "Enable dragon riding",
        ["value"] = false -- experimental! need to mount!!
    },
    ["glider_z_offset"] = {
        ["label"] = "Offset glider target from ground",
        ["value"] = 250 -- experimental! need to mount!!
    },
    ["use_mount"] = {
        ["label"] = "Enable mounting",
        ["value"] = false -- TODO
    }
}

-- TODO: move this into a plugin???
-- #================================#
-- #         Movement Logic         #
-- #================================#
local pointIndex = 1
GWB.targetUnit = 0
GWB.isMovingOn = true
-- TODO: add blacklisting and timeout on unit encounters
-- this is needed in case unit is unreachable etc

function _tickTest_old() 
  if not GWB.Map:IsRunning() then
    C_Timer.After(1, _tickTest_old)
    return
  end

  -- is alive?
    if not UnitIsDeadOrGhost("player") then
        print("Player is alive!")
    else
        if UnitIsGhost("player") then
            print("Player is a ghost.")
            -- TODO: walk ghost?
        else
            print("Player is dead.")
            RepopMe()
            C_Timer.After(1, _tickTest_old)
            return
        end
    end

  local updateMov = false
  -- is in combat? or should stop?
  --if InCombatLockdown() or (ObjectExists(GWB.targetUnit) and not UnitIsDead(GWB.targetUnit)) then
  if 
    GWB.isMovingOn and
    (
        InCombatLockdown() or 
    (ObjectExists(GWB.targetUnit) and not UnitIsDead(GWB.targetUnit)) 
    )
  then   
    GWB.isMovingOn = false;

    -- update facing? also check for ONLY nearby combat mobs?
    if GetUnitSpeed("player") ~= 0 then
        -- stop mov?
        print("stop mov")
        ClickToMove(ObjectPosition("player"))
        Unlock(MoveForwardStart)
        C_Timer.After(0, function() Unlock(MoveForwardStop) end)
    end
    C_Timer.After(1, _tickTest_old)
    return -- REEEE
  else
    -- force update mov?
    updateMov = true
    GWB.isMovingOn = true
    if (ObjectExists(GWB.targetUnit) and not UnitIsDead(GWB.targetUnit)) then
        GWB.targetUnit = 0 -- unset if finished?
    end
  end
   
  if GWB:OnBotScanTick() then
    C_Timer.After(1, _tickTest_old)
    return -- stop mov?
  end

  local points = GWB:GetPointsForCurrentMap()
  if updateMov and #points ~= 0 then 

    local p = points[pointIndex]

    local px, py, pz = ObjectPosition("player")

    p.wz = 400
    local cx, cy, cz = TraceLine(p.wx, p.wy, 5000, p.wx, p.wy, -5000, 0x101111)
    if cx ~= false then
      p.wz = cz
    end
    
    local d = Distance(px, py, 0, p.wx, p.wy, 0)
    if (d < 2.5) then -- TODO: adjust with mov sped?
      pointIndex = pointIndex + 1
      if pointIndex > #points then
        pointIndex = 1
      end
      p = points[pointIndex]
      print("Taking next point!!")
    end
    --dragon.ride(p.wx, p.wy, p.wz)
    ClickToMove(p.wx, p.wy, p.wz)
    
  end

  C_Timer.After(0.25, _tickTest_old)
end
--_tickTest_old()

local inCombat = false
local isDedOrGhost = false
local lastDynMeshUpdate = 0
local updateDynInternal = 2

-- returns true if all conditions to run waypoints are met!
local function DoWaypoints()
    if UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil then
        return false
    end
    return not inCombat and not isDedOrGhost
end

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    inCombat = true
end
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    print("WE LEFT COMBAT??")
    -- NOTE: this will be "delayed" by the post-combat
    -- looting mechanism in the Medium CombatHandler <3
    inCombat = false
end
plugin.callbacks.OnPlayerDeath = function(ctx)
    isDedOrGhost = UnitIsDead("player") or UnitIsDeadOrGhost("player")
end
plugin.callbacks.OnPlayerUnghost = function(ctx)
    isDedOrGhost = false
    -- Dispatch into rest handler?
    if GWB.State:getCurrentState() == "plugin.Waypoints" then
        GWB.State:callState("plugin.RestHandler")
    end
end
plugin.callbacks.OnPlayerAlive = function(ctx)
    isDedOrGhost = true --UnitIsDead("player") or UnitIsDeadOrGhost("player")
    
end

local function OnLoad()
    inCombat = UnitAffectingCombat("player")
    isDedOrGhost = UnitIsDead("player") or UnitIsDeadOrGhost("player")
end

local engageTarget = nil
local engageStartTime = 0
local engageLastDist = 99999

-- Check for nearby mobs, no need to path to waypoints after 
local function DoActiveEngage()
    if GWB.isPostCombatLooting then return false end
    if GWB:OnBotScanTick() then
        if engageTarget ~= GWB.targetUnit then
            engageTarget = GWB.targetUnit
            engageStartTime = GetTime()
            engageLastDist = 99999
        else
            local px, py, pz = ObjectPosition("player")
            local tx, ty, tz = ObjectPosition(engageTarget)
            if px and tx then
                local dist = math.sqrt((tx-px)^2 + (ty-py)^2 + (tz-pz)^2)
                -- If distance is actively decreasing, refresh the timeout
                if dist < engageLastDist - 0.5 then
                    engageLastDist = dist
                    engageStartTime = GetTime()
                end
            end
        end

        if engageTarget == GWB.targetUnit and GetTime() - engageStartTime > 15 then
            -- Timed out trying to engage this unit (likely unreachable or evaded)
            GWB:Print("Target encounter timed out. Blacklisting target.")
            GWB.BlacklistedTargets = GWB.BlacklistedTargets or {}
            local ptr = ObjectPointer(GWB.targetUnit)
            if ptr then GWB.BlacklistedTargets[ptr] = GetTime() + 120 end -- Blacklist for 2 mins
            
            -- Clear target so we can move on
            if Unlock and RunMacroText then
                Unlock(RunMacroText, "/cleartarget")
            end
            GWB.targetUnit = nil
            engageTarget = nil
            return false
        end

        -- force stop it if it target something so we can engage!!
        if GWB.Settings.UseEZNavSafe and GWB.EZMover:IsMoving() then
            GWB.EZMover:Stop()
            C_Timer.After(0.01, function()
                if GetUnitSpeed("player") ~= 0 then
                    local px, py, pz = ObjectPosition("player")
                    if px then ClickToMove(px, py, pz) end
                end
            end)
        elseif not GWB.Settings.UseEZNavSafe and GWB.Mover:IsMoving() then
            --GWB.Mover:HaltMovement()
            GWB.Mover:Stop() -- force click stop
            C_Timer.After(0.01, function()
                if GetUnitSpeed("player") ~= 0 then
                    print("!!force stop")
                    GWB.Mover:Update()
                    local px, py, pz = GWB.Mover:GetPlayerPosition()
                    if px then ClickToMove(px, py, pz) end
                end
            end)
        end
        return true
    end
    return false
end

-- force face target
local function ForceFaceTarget()
    if not useGlider then
        GWB:UpdateFacingTarget()
    else
        -- time to land!
        GWB.Mover:Update()
        local px, py, pz = GWB.Mover:GetPlayerPosition()
        local cx, cy, cz = TraceLine(px, py, pz, px, py, -5000, 0x101111)
        if cx ~= false then
            pz = cz
        end
        print("dragon_ride down!")
        GWB.dragon.ride(px, py, pz)
    end
end

function _tickTest() 
    if not GWB.Map:IsRunning() then
        return
    end
    
    -- Yield if any other state is active (LootHandler, RestHandler, TownHandler, etc.)
    if GWB.State and GWB.State:getCurrentState() ~= "plugin.Waypoints" then
        return
    end
    
    -- Don't interfere with post-combat looting
    if GWB.isPostCombatLooting then
        return
    end

    -- make sure we are alive?
    if UnitIsDead("player") or UnitIsDeadOrGhost("player") then
        return
    end

    if inCombat then return end

    -- Yield to QuestHandler if pursuing a quest objective
    if GWB.QuestTarget then return end

    if GWB.Settings.QuestieAutopilot then
        -- Run Autopilot navigation
        local pin = GWB.QuestHandler and GWB.QuestHandler.GetNextWaypoint and GWB.QuestHandler:GetNextWaypoint()
        if not pin then
            GWB.autopilotEmptyTicks = (GWB.autopilotEmptyTicks or 0) + 1
            if GWB.autopilotEmptyTicks < 15 then
                return -- Buffer for ~3 seconds to ignore split-second Questie redraws
            end

            -- No quests, stop moving
            local now = GetTime()
            if now - (GWB.lastAutopilotHaltLog or 0) > 5.0 then
                GWB.lastAutopilotHaltLog = now
                GWB:Print("[Autopilot] Halting: No quest pins found for current map.")
            end
            
            if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                if GWB.EZMover:IsMoving() then GWB.EZMover:Stop() end
            elseif GWB.Mover and GWB.Mover.Stop then
                GWB.Mover:Stop()
            end
            
            -- Keep facing/engaging nearby if needed
            DoActiveEngage()
            return
        end
        
        -- Pin found, reset buffer
        GWB.autopilotEmptyTicks = 0

        local px, py, pz = ObjectPosition("player")
        if not px then return end

        -- If it's a questgiver/finisher (complete or available), let's look for them nearby
        if pin.type == "complete" or pin.type == "available" then
            local objects = ObjectManager(5) or {}
            local foundTarget = nil
            for i = 1, #objects do
                local obj = objects[i]
                if ObjectExists(obj) and ObjectUnitId(obj) == pin.id then
                    foundTarget = obj
                    break
                end
            end

            -- Also check GameObjects just in case
            if not foundTarget then
                local gameObjs = ObjectManager(8) or {}
                for i = 1, #gameObjs do
                    local obj = gameObjs[i]
                    if ObjectExists(obj) and ObjectId(obj) == pin.id then
                        foundTarget = obj
                        break
                    end
                end
            end

            if foundTarget then
                local cx, cy, cz = ObjectPosition(foundTarget)
                local dist = Distance(px, py, pz, cx, cy, cz)
                if dist < 4.5 then
                    -- Stop moving
                    if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                        GWB.EZMover:Stop()
                    end
                    ClickToMove(px, py, pz)
                    
                    -- Debounce interaction
                    local now = GetTime()
                    if now - (GWB.lastQuestieInteractTime or 0) > 2.0 then
                        GWB.lastQuestieInteractTime = now
                        ObjectInteract(foundTarget)
                        GWB:Print("Interacting with quest NPC/Object:", ObjectName(foundTarget))
                    end
                else
                    -- Move directly to the NPC/Object
                    if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                        GWB.EZMover:MoveToXYZ(cx, cy, cz)
                    else
                        GWB.Mover:MoveToXYZ(cx, cy, cz)
                    end
                end
                return
            end
        end

        -- If not interacting, move towards the pin coordinate
        local distToPin2D = Distance(px, py, 0, pin.wx, pin.wy, 0)
        if distToPin2D > 5 then
            if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                GWB.EZMover:MoveToXYZ(pin.wx, pin.wy, pin.wz)
            else
                GWB.Mover:MoveToXYZ(pin.wx, pin.wy, pin.wz)
            end
        else
            -- We reached the coordinate but NPC isn't here yet. Blacklist this pin for 120s and move on!
            if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                if GWB.EZMover:IsMoving() then GWB.EZMover:Stop() end
            end
            
            if pin.type == "active" and pin.questId and pin.x and pin.y then
                if not GWB.QuestHandler.BlacklistedPins then GWB.QuestHandler.BlacklistedPins = {} end
                local pinId = tostring(pin.questId) .. "_" .. tostring(pin.x) .. "_" .. tostring(pin.y)
                GWB.QuestHandler.BlacklistedPins[pinId] = GetTime() + 120.0
                GWB.QuestHandler.CurrentAutopilotPin = nil
                GWB:Debug("Pin empty! Roaming to next pin...")
            else
                ClickToMove(px, py, pz)
            end
        end

        -- Check if there are nearby mobs to engage (if we are near an objective)
        if pin.type ~= "complete" and pin.type ~= "available" then
            DoActiveEngage()
        end
        return
    end

    -- not in combat, now a good time to check up on durability and switch if needed?
    local townHandlerPlugin = GWB.plugins["TownHandler"] 
    if townHandlerPlugin ~= nil then
        if townHandlerPlugin.handlers.NeedTown() then
            -- okay, call into the TownHandler!
            print("Going to town!")
            GWB.State:callState("plugin.TownHandler")
            return
        end
    end

    -- do not interrupt if we are casting?
    if UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil then
        return
    end

    -- yield to CombatHandler if we have a valid attack target
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        return 
    end


    local useGlider = plugin.settings.use_glider.value
    local gliderZOff = plugin.settings.glider_z_offset.value
    local useMount = plugin.settings.use_mount.value
    local shouldTickWaypoints = DoWaypoints()

    -- important one?
    --GWB:Debug("[", shouldTickWaypoints, "] inCombat:", inCombat, "isDedOrGhost:", isDedOrGhost)

    local updateMov = false

    -- TODO: move this "toggle" into combat/ded
    if not shouldTickWaypoints then   
        -- force stop it if needed
        if GWB.Settings.UseEZNavSafe and GWB.EZMover:IsMoving() then
            GWB.EZMover:Stop()
        elseif not GWB.Settings.UseEZNavSafe and GWB.Mover.IsMoving() then
            GWB.Mover:HaltMovement()
        end
        GWB:Debug("[", shouldTickWaypoints, "] inCombat:", inCombat, "isDedOrGhost:", isDedOrGhost)
        return
    else
        -- force update mov?
        --print("aaa", GetTime(), ">", lastDynMeshUpdate + updateDynInternal)
        if GetTime() > (lastDynMeshUpdate + updateDynInternal) then
            --print(".. updated true")
            updateMov = true
            lastDynMeshUpdate = GetTime()
        end
    end
   
    local points = GWB:GetPointsForCurrentMap()
    if not points or #points == 0 then return end

    local px, py, pz
    if not GWB.Settings.UseEZNavSafe then
        GWB.Mover:Update()
        px, py, pz = GWB.Mover:GetPlayerPosition()
    else
        px, py, pz = ObjectPosition("player")
    end
    if not px then return end
    
    local p = points[pointIndex]

    -- take next Waypoint?
    local d = Distance(px, py, 0, p.wx, p.wy, 0)

    -- NOTE: we should ONLY engage if we are nearby the Waypoint zone?
    if d < 100 then
        DoActiveEngage()
    end

    --print(d, "distance on waypoint")
    local minDist = 7
    if useMount then
        minDist = 8
    end
    if useGlider then
        minDist = 12
    end
    if (d < minDist) then -- TODO: adjust with mov sped?
      pointIndex = pointIndex + 1
      if pointIndex > #points then
        pointIndex = 1
      end
      print(".. Taking next point!!")
      updateMov = true -- force update Mover 
      
      -- Reroll the jitter so we don't click the exact same spot next time
      local nextP = points[pointIndex]
      nextP.jx = (math.random() * 4.0) - 2.0
      nextP.jy = (math.random() * 4.0) - 2.0
    end

    -- update mesh if needed???
    if updateMov and #points ~= 0 then 
        local p = points[pointIndex]
        
        local jx = p.jx or ((math.random() * 4.0) - 2.0)
        local jy = p.jy or ((math.random() * 4.0) - 2.0)
        p.jx = jx
        p.jy = jy
        
        local targetX = p.wx + jx
        local targetY = p.wy + jy

        p.wz = 400
        -- 0x100 Terrain, 0x10 WMOCollision, 0x1 M2Collision
        -- we can skip M2 to avoid tree's and other bullshit
        local cx, cy, cz = TraceLine(targetX, targetY, 5000, targetX, targetY, -5000, 0x110)
        if cx ~= false then
            p.wz = cz
        end

        if useGlider and true then
            GWB:Debug("ride", targetX, targetY, p.wz+gliderZOff)
            GWB.dragon.ride(targetX, targetY, p.wz+gliderZOff)
        elseif GWB.Settings.UseEZNavSafe and GWB.EZMover then
            GWB.EZMover:MoveToXYZ(targetX, targetY, p.wz)
        else
            GWB.Mover:MoveToXYZ(targetX, targetY, p.wz)
        end
    else
        -- always tick dragon!
        if useGlider and true then
            GWB:Debug("ride_update", p.wx, p.wy, p.wz+gliderZOff)
            GWB.dragon.ride(p.wx, p.wy, p.wz+gliderZOff)
        end
    end
end

plugin.handlers.stateTick = function()
    -- TODO: we can use this to get into new state for some reason?
    -- Maybe here we should check for repair?? ;_;

    if UnitIsDead("player") or UnitIsDeadOrGhost("player") then
        -- yeah maybe dispatch to the ghost thing?
        GWB.State:callState("plugin.ReleaseSpiritOnGhost")
        return
    end

    if 
        not UnitAffectingCombat("player") and 
        not UnitIsDeadOrGhost("player") and
        not UnitIsDead("player")
    then
        -- check something?
        local restHandlerPlugin = GWB.plugins.RestHandler
        if restHandlerPlugin ~= nil then
            if restHandlerPlugin.handlers.NeedResting() then
                print("TAKING REST HANDLER!")
                -- stop mov in case we alrdy started going to the next?
                if GWB.Settings.UseEZNavSafe and GWB.EZMover:IsMoving() then
                    GWB.EZMover:Stop()
                elseif not GWB.Settings.UseEZNavSafe and GWB.Mover:IsMoving() then
                    GWB.Mover:Stop()
                end
                GWB.State:callState("plugin.RestHandler")
                return
            end
        else
            GWB:Debug("plugin.RestHandler wasn't loaded!")
        end
    end

    if UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") then
        -- Okay, now force CombatState if we DO have something to fight?
        if GWB.State:getCurrentState() == "plugin.Waypoints" then
            GWB.State:callState("plugin.CombatHandler")
        end
    end
end

GWB:RegisterTicker("MapTick", _tickTest)
GWB:TickerSetState("MapTick", true) -- always true?
GWB:RegisterPlugin(plugin)
