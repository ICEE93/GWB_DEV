local Nn, GWB = ...

if not GWB.Settings then GWB.Settings = {} end
if GWB.Settings.UseEZNavSafe == nil then GWB.Settings.UseEZNavSafe = false end

local orig_GeneratePath = _G.GeneratePath
local orig_GenerateLocalPath = _G.GenerateLocalPath

if GWB.Storage and GWB.Storage.Settings and GWB.Storage.Settings.Core then
    GWB.Settings.UseEZNavSafe = GWB.Storage.Settings.Core.UseEZNavSafe
end

-- Hook GeneratePath (Async)
_G.GeneratePath = function(map, px, py, pz, tx, ty, tz, cb, smooth, errCb)
    if GWB.Settings.UseEZNavSafe and Nn.EZ and Nn.EZ.Nav and Nn.EZ.Nav.GeneratePath then
        GWB:Debug("Routing GeneratePath through EZNavSafe")
        -- EZNavSafe signature: GeneratePath(x1, y1, z1, x2, y2, z2, callback)
        return Nn.EZ.Nav.GeneratePath(px, py, pz, tx, ty, tz, cb)
    end
    if orig_GeneratePath then
        return orig_GeneratePath(map, px, py, pz, tx, ty, tz, cb, smooth, errCb)
    end
end

-- Hook GenerateLocalPath (Sync)
_G.GenerateLocalPath = function(map, px, py, pz, tx, ty, tz, errCb, smooth)
    if GWB.Settings.UseEZNavSafe and Nn.EZ and Nn.EZ.Nav and Nn.EZ.Nav.GeneratePath then
        GWB:Print("WARNING: GenerateLocalPath called synchronously while UseEZNavSafe is enabled.")
        -- We cannot block WoW thread to wait for EZNavSafe callback. 
        -- Falling back to orig_GenerateLocalPath to prevent engine crash.
        if orig_GenerateLocalPath then
            return orig_GenerateLocalPath(map, px, py, pz, tx, ty, tz, errCb, smooth)
        end
    end
    if orig_GenerateLocalPath then
        return orig_GenerateLocalPath(map, px, py, pz, tx, ty, tz, errCb, smooth)
    end
    return {}
end

-- ==========================================================
-- GWB.EZMover (Async Pathing Controller)
-- ==========================================================
GWB.EZMover = {}
local ezPath = nil
local ezPathIndex = 2
local isGenerating = false
local lastDestX, lastDestY, lastDestZ = 0, 0, 0

function GWB.EZMover:MoveToXYZ(x, y, z)
    if isGenerating then return end
    if GWB.pauseMovementUntil and GetTime() < GWB.pauseMovementUntil then
        return
    end
    GWB.EZMover.targetObj = nil
    
    local destDist = math.sqrt((x-lastDestX)^2 + (y-lastDestY)^2 + (z-lastDestZ)^2)
    if ezPath and destDist < 2.0 then
        -- We are already moving to this destination
        return
    end
    
    local px, py, pz = ObjectPosition("player")
    if not px then return end
    
    lastDestX, lastDestY, lastDestZ = x, y, z
    
    -- Jitter destination slightly
    local jx = x + (math.random() * 1.5 - 0.75)
    local jy = y + (math.random() * 1.5 - 0.75)
    
    local playerDist = math.sqrt((jx-px)^2 + (jy-py)^2 + (z-pz)^2)
    if playerDist < 5.5 then
        ezPath = {{x=px, y=py, z=pz}, {x=jx, y=jy, z=z}}
        ezPathIndex = 2
        return
    end

    local targetX, targetY, targetZ = jx, jy, z
    
    local dx, dy = targetX - px, targetY - py
    local totalDist2D = math.sqrt(dx*dx + dy*dy)
    if totalDist2D > 180.0 then
        -- Break long paths into chunks to prevent pathfinder timeouts/failures
        local ratio = 180.0 / totalDist2D
        targetX = px + dx * ratio
        targetY = py + dy * ratio
        targetZ = pz + (z - pz) * ratio
    end

    isGenerating = true
    Nn.EZ.Nav.GeneratePath(px, py, pz, targetX, targetY, targetZ, function(path)
        isGenerating = false
        if path and type(path) == "table" and #path > 1 then
            -- Trim nodes that we are already past
            while #path > 2 do
                local node = path[2]
                local nextNode = path[3]
                local d1 = math.sqrt((node.x-px)^2 + (node.y-py)^2)
                local d2 = math.sqrt((nextNode.x-px)^2 + (nextNode.y-py)^2)
                -- If we are closer to the 3rd node than the 2nd node, or 2nd node is very close, skip 2nd node
                if d1 < 2.0 or d2 < d1 then
                    table.remove(path, 2)
                else
                    break
                end
            end
            
            ezPath = path
            ezPathIndex = 2
            if ezPath[ezPathIndex] then
                GWB.EZMover:ClickToMoveSafeZ(ezPath[ezPathIndex].x, ezPath[ezPathIndex].y, ezPath[ezPathIndex].z)
            end
        else
            GWB:Print("EZNavSafe: Failed to generate path to destination.")
            ezPath = nil
        end
    end)
end

function GWB.EZMover:Stop()
    ezPath = nil
    isGenerating = false
    lastDestX, lastDestY, lastDestZ = 0, 0, 0
    GWB.EZMover.targetObj = nil
    local px, py, pz = ObjectPosition("player")
    if px then ClickToMove(px, py, pz) end
end

function GWB.EZMover:GetDestXYZ()
    return lastDestX, lastDestY, lastDestZ
end

function GWB.EZMover:StartMove()
    if lastDestX ~= 0 or lastDestY ~= 0 or lastDestZ ~= 0 then
        if GWB.EZMover.targetObj then
            self:MoveToObject(GWB.EZMover.targetObj)
        else
            self:MoveToXYZ(lastDestX, lastDestY, lastDestZ)
        end
    end
end

function GWB.EZMover:MoveToObject(obj)
    if not ObjectExists(obj) then return false end
    local tx, ty, tz = ObjectPosition(obj)
    if not tx then return false end
    self:MoveToXYZ(tx, ty, tz)
    GWB.EZMover.targetObj = obj
    return true
end

function GWB.EZMover:IsMoving()
    return ezPath ~= nil or isGenerating
end

function GWB.EZMover:ClickToMoveSafeZ(x, y, z)
    local tLine = TraceLine or (Nn and Nn.TraceLine)
    local finalZ = z
    if tLine then
        -- Find ground Z by tracing straight down
        local hx, hy, hz = tLine(x, y, z + 500, x, y, z - 500, 0x111)
        if hx and hz then
            finalZ = hz
        end
    end
    ClickToMove(x, y, finalZ)
end

-- Track last chosen direction for momentum
local lastWhiskerAngle = nil
local lastWhiskerTime = 0
local lastMovementSpeed = 0

-- LibDraw rendering for whiskers
local libDrawRays = {}
local libDrawInstance = nil

local function InitLibDraw()
    if libDrawInstance then return true end
    if Nn and Nn.Utils and Nn.Utils.Draw then
        local ok, draw = pcall(function() return Nn.Utils.Draw:New() end)
        if ok and draw then
            libDrawInstance = draw
            if libDrawInstance.Enable then pcall(function() libDrawInstance:Enable() end) end
            libDrawInstance:Sync(function(d)
                local drawDebug = GWB.Settings and GWB.Settings.DebugWhiskers
                if not drawDebug or #libDrawRays == 0 then
                    d:ClearCanvas()
                    return
                end
                
                d:ClearCanvas()
                d:SetWidth(2)
                for i = 1, #libDrawRays do
                    local ray = libDrawRays[i]
                    if ray.hit then
                        d:SetColorRaw(1, 0, 0, 1)
                    else
                        d:SetColorRaw(0, 1, 0, 1)
                    end
                    pcall(function() d:Line(ray.px, ray.py, ray.pz, ray.rx, ray.ry, ray.rz) end)
                end
            end)
            return true
        end
    end
    return false
end

local function ClickToMoveWithWhiskers(px, py, pz, wx, wy, wz, isQuestInteraction)
    if UnitIsDeadOrGhost("player") then
        GWB.EZMover:ClickToMoveSafeZ(wx, wy, wz)
        return
    end

    local finalX, finalY, finalZ = wx, wy, wz
    local tLine = TraceLine or (Nn and Nn.TraceLine)

    if tLine then
        local dx = wx - px
        local dy = wy - py
        local dist2D = math.sqrt(dx*dx + dy*dy)
        local slopeZ = (wz - pz) / (dist2D > 0.1 and dist2D or 1)

        local yaw = math.atan2(dy, dx)
        local now = GetTime()

        -- Check for aggressive non-quest mobs in path and steer around them
        local os = ObjectManager(5) or {}
        local avoidanceVectorX, avoidanceVectorY = 0, 0
        local avoidanceWeight = 0

        -- Use more aggressive avoidance for quest interactions (turn-in/accept)
        local avoidanceRange = isQuestInteraction and 40.0 or 25.0
        local avoidanceStrength = isQuestInteraction and 0.85 or 0.7
        local goalStrength = isQuestInteraction and 0.15 or 0.3

        for i = 1, #os do
            local o = os[i]
            if ObjectExists(o) then
                local ox, oy, oz = ObjectPosition(o)
                if ox then
                    local odist = math.sqrt((ox-px)^2 + (oy-py)^2 + (oz-pz)^2)
                -- Check if mob is within avoidance range and in front of us
                if odist < avoidanceRange and odist > 0.1 then
                    local toMobX, toMobY = ox - px, oy - py
                    local toMobDist = math.sqrt(toMobX^2 + toMobY^2)
                    local toMobNormX, toMobNormY = toMobX / toMobDist, toMobY / toMobDist

                    -- Check if mob is in front (dot product with movement direction)
                    local moveNormX, moveNormY = dx / dist2D, dy / dist2D
                    local dotProduct = toMobNormX * moveNormX + toMobNormY * moveNormY

                    -- If we are doing a quest turn in/accept, we want to detour around ANY hostile mob
                    if dotProduct > 0.1 or isQuestInteraction then
                        -- Check if mob is aggressive and not a quest objective
                        local isAggressive = UnitCanAttack("player", o) and not UnitIsDeadOrGhost(o)
                        local isQuestMob = GWB.QuestHandler and GWB.QuestHandler.IsObjective and GWB.QuestHandler:IsObjective(o)

                        if isAggressive and not isQuestMob then
                            -- Calculate avoidance vector (perpendicular to direction to mob, or directly away if very close)
                            local avoidX, avoidY
                            if isQuestInteraction and odist < 15.0 then
                                -- If we are very close, push directly away from them instead of just perpendicular
                                avoidX, avoidY = -toMobNormX, -toMobNormY
                            else
                                avoidX, avoidY = -toMobNormY, toMobNormX
                            end
                            
                            -- Calculate dot product to see if we're steering TOWARDS the mob, if so reverse it
                            local steerDot = avoidX * toMobNormX + avoidY * toMobNormY
                            if steerDot > 0 then
                                avoidX, avoidY = -avoidX, -avoidY
                            end
                            
                            -- Weight by distance (closer = stronger avoidance)
                            local weight = (avoidanceRange - odist) / avoidanceRange
                            
                            -- Exponential weight if we are walking to a turn-in so we heavily detour
                            if isQuestInteraction then
                                weight = weight * weight * 3.0
                            end
                            
                            avoidanceVectorX = avoidanceVectorX + avoidX * weight
                            avoidanceVectorY = avoidanceVectorY + avoidY * weight
                            avoidanceWeight = avoidanceWeight + weight
                        end
                    end
                end
                end
            end
        end

        -- Apply avoidance steering if needed
        if avoidanceWeight > 0.1 then
            local avoidNormX = avoidanceVectorX / avoidanceWeight
            local avoidNormY = avoidanceVectorY / avoidanceWeight

            -- Validate that the avoidance direction leads to walkable ground
            local testDist = 5.0
            local testX = px + avoidNormX * testDist
            local testY = py + avoidNormY * testDist
            local testZ = pz + slopeZ * testDist

            -- Check if the avoidance direction is walkable
            local groundHit = tLine(testX, testY, testZ + 10.0, testX, testY, testZ - 10.0, 0x100111)
            if groundHit then
                -- Avoidance direction leads to ground, use it
                -- Blend avoidance with goal direction (more aggressive for quest interactions)
                finalX = px + (dx * goalStrength + avoidNormX * dist2D * avoidanceStrength)
                finalY = py + (dy * goalStrength + avoidNormY * dist2D * avoidanceStrength)
                finalZ = pz + slopeZ * dist2D
                GWB.EZMover:ClickToMoveSafeZ(finalX, finalY, finalZ)
                return
            else
                -- Avoidance direction leads to unwalkable terrain, fall back to goal direction
                GWB.EZMover:ClickToMoveSafeZ(wx, wy, wz)
                return
            end
        end

        -- Forward Whisker Array with Fan Pattern
        local charRadius = 0.5  -- WoW character collision radius in yards
        local stepHeight = 0.5   -- Maximum step height in yards
        local testDist = math.min(dist2D, 10.0) -- Look ahead up to 10 yards
        
        -- Steering angles to test (0 = straight, then progressively wider)
        local steerAngles = {0, 0.25, -0.25, 0.5, -0.5, 0.75, -0.75, 1.0, -1.0, 1.25, -1.25, 1.5, -1.5}
        
        -- Anti-jitter memory: prefer the side we steered towards on the last tick!
        if GWB.lastSteerAngle and GWB.lastSteerAngle ~= 0 then
            if GWB.lastSteerAngle > 0 then
                -- Prefer right turns
                steerAngles = {0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, -0.25, -0.5, -0.75, -1.0, -1.25, -1.5}
            else
                -- Prefer left turns
                steerAngles = {0, -0.25, -0.5, -0.75, -1.0, -1.25, -1.5, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5}
            end
        end
        
        -- Distance brackets to check (proactive early avoidance)
        local distanceBrackets = { 
            math.min(dist2D, 12.0), 
            math.min(dist2D, 8.0), 
            math.min(dist2D, 4.0), 
            math.min(dist2D, 2.0) 
        }

        local pathBlocked = false
        local bestSteerAngle = 0
        local bestSteerDist = 5.0
        local clearPathFound = false

        for _, testDist in ipairs(distanceBrackets) do
            if testDist > 1.0 then
                for _, steer in ipairs(steerAngles) do
                    local testYaw = yaw + steer
                    local fx = math.cos(testYaw)
                    local fy = math.sin(testYaw)
                    local rx = math.sin(testYaw)
                    local ry = -math.cos(testYaw)

                    local anyRayBlocked = false

                    -- Test 5 positions across the body width
                    local positions = {
                        {offset = 0},
                        {offset = -charRadius * 0.5},
                        {offset = charRadius * 0.5},
                        {offset = -charRadius},
                        {offset = charRadius}
                    }

                    for posIdx, pos in ipairs(positions) do
                        local baseX = px + fx * testDist - rx * pos.offset
                        local baseY = py + fy * testDist - ry * pos.offset
                        
                        -- Cliff and Edge Detection (Slope-based)
                        local hX, hY, hZ = tLine(baseX, baseY, pz + 10.0, baseX, baseY, pz - 50.0, 0x100111)
                        if not hZ then
                            anyRayBlocked = true
                            break
                        else
                            local edgeSlope = (hZ - pz) / testDist
                            -- Allow slopes between -1.5 (steep drop) and 1.5 (steep climb)
                            if edgeSlope < -1.5 or edgeSlope > 1.5 then
                                anyRayBlocked = true
                                break
                            end
                            -- Absolute drop/rise cap
                            if (hZ - pz) < -8.0 or (hZ - pz) > 8.0 then
                                anyRayBlocked = true
                                break
                            end
                        end
                        
                        -- Calculate the expected Z height at the destination based on the path's slope
                        local expectedZDrop = slopeZ * testDist
                        
                        -- Test Knee Height (0.5) and Chest Height (1.2)
                        for _, zOffset in ipairs({0.5, 1.2}) do
                            local startZ = pz + zOffset
                            local endZ = pz + expectedZDrop + zOffset
                            
                            -- Trace ray parallel to the expected terrain slope
                            local hitX, hitY, hitZ = tLine(px, py, startZ, baseX, baseY, endZ, 0x100111)
                            
                            -- Deep water detection (Liquid = 0x20000)
                            local wX, wY, wZ = tLine(px, py, startZ, baseX, baseY, endZ, 0x20000)
                            if wX then
                                -- Trace straight down from water surface to find ground
                                local gX, gY, gZ = tLine(wX, wY, wZ, wX, wY, wZ - 50.0, 0x100111)
                                if not gZ or (wZ - gZ) > 1.2 then
                                    hitX, hitY, hitZ = wX, wY, wZ -- Treat deep water as a solid obstacle
                                end
                            end
                            
                            -- If the ray hits anything, it means there's an obstacle sticking out of the ground!
                            if hitX then
                                anyRayBlocked = true
                                break
                            end
                        end

                        if anyRayBlocked then break end
                    end

                    if not anyRayBlocked then
                        bestSteerAngle = steer
                        if steer ~= 0 then
                            pathBlocked = true -- We had to steer
                        end
                        bestSteerDist = testDist
                        clearPathFound = true
                        break -- Found the tightest clear angle at this distance!
                    end
                end
                
                if clearPathFound then
                    break -- Stop checking shorter distances, we found a proactive clear path!
                end
            end
        end

        if not clearPathFound then
            -- Extreme fallback: if all paths are blocked, just trust the Mover
            pathBlocked = true
        end

        if pathBlocked and bestSteerAngle ~= 0 then
            -- Apply steering proactively using the clear distance we found
            local steerYaw = yaw + bestSteerAngle
            -- Make the steering distance at least 5 yards for smooth movement, or longer if we saw further
            local steerDist = math.min(dist2D, math.max(5.0, bestSteerDist))
            finalX = px + math.cos(steerYaw) * steerDist
            finalY = py + math.sin(steerYaw) * steerDist
            finalZ = pz + slopeZ * steerDist
            
            -- Save for anti-jitter memory
            GWB.lastSteerAngle = bestSteerAngle
        else
            GWB.lastSteerAngle = 0
        end
    end

    GWB.EZMover:ClickToMoveSafeZ(finalX, finalY, finalZ)
end

local function EZMoverTick()
    if not GWB.Settings.UseEZNavSafe or not ezPath then return end
    
    local px, py, pz = ObjectPosition("player")
    if not px then return end
    
    -- If we have a target object, check distance to the LIVE object position
    -- (it may have shifted slightly from when the path was generated)
    local tObj = GWB.EZMover.targetObj
    if tObj then
        if not ObjectExists(tObj) then
            -- Object gone, abort
            ezPath = nil
            GWB.EZMover.targetObj = nil
            return
        end
        local ox, oy, oz = ObjectPosition(tObj)
        if ox then
            local odx, ody, odz = ox - px, oy - py, oz - pz
            local objDist = math.sqrt(odx*odx + ody*ody + odz*odz)
            if objDist < 3.5 then
                -- We're close enough to the actual object — stop and interact!
                ezPath = nil
                GWB.EZMover.targetObj = nil
                -- Stop character movement so ObjectInteract can work
                ClickToMove(px, py, pz)
                -- Humanize Object interaction with random delay
                local interactDelay = math.random(40, 120) / 100.0 -- 0.4s to 1.2s delay
                C_Timer.After(interactDelay, function()
                    if ObjectExists(tObj) then
                        ObjectInteract(tObj)
                    end
                end)
                -- Fire the callback so CombatHandler knows we arrived
                GWB:FireCallback("OnMovementFinished", "object", tObj)
                return
            end
        end
    end
    
    -- Safe Waypoint Skipping: We only skip waypoints if Line of Sight is clear AND the straight-line distance 
    -- is nearly identical to the mesh path distance. This prevents us from skipping over holes or cliffs 
    -- where LoS is clear but walking would be fatal.
    local tLine = TraceLine or (Nn and Nn.TraceLine)
    if tLine and ezPathIndex < #ezPath then
        local maxScan = math.min(#ezPath, ezPathIndex + 5)
        for scanIdx = maxScan, ezPathIndex + 1, -1 do
            local scanWp = ezPath[scanIdx]
            
            -- Calculate straight line 3D distance
            local straightDist = math.sqrt((scanWp.x - px)^2 + (scanWp.y - py)^2 + (scanWp.z - pz)^2)
            
            -- Calculate mesh path distance
            local meshDist = math.sqrt((ezPath[ezPathIndex].x - px)^2 + (ezPath[ezPathIndex].y - py)^2 + (ezPath[ezPathIndex].z - pz)^2)
            for i = ezPathIndex, scanIdx - 1 do
                local p1 = ezPath[i]
                local p2 = ezPath[i+1]
                meshDist = meshDist + math.sqrt((p2.x - p1.x)^2 + (p2.y - p1.y)^2 + (p2.z - p1.z)^2)
            end
            
            -- If straight distance is at least 85% of mesh distance, it's roughly a straight, flat path
            if straightDist > 0 and meshDist > 0 and (straightDist / meshDist) >= 0.85 then
                -- Double check Line of Sight to be absolutely sure no wall/tree is in the way
                local hit = tLine(px, py, pz + 1.0, scanWp.x, scanWp.y, scanWp.z + 1.0, 0x100111)
                if not hit then
                    ezPathIndex = scanIdx
                    break
                end
            end
        end
    end
    local wp = ezPath[ezPathIndex]
    if not wp then 
        ezPath = nil 
        return 
    end
    
    local dx = wp.x - px
    local dy = wp.y - py
    local dz = wp.z - pz
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    
    if dist < 1.5 then
        if ezPathIndex >= #ezPath then
            -- Check if we have a final destination for multi-segment pathing
            if GWB.EZMover.finalDest then
                local finalDest = GWB.EZMover.finalDest
                GWB.EZMover.finalDest = nil
                -- Generate next segment towards final destination
                GWB.EZMover:MoveToXYZ(finalDest.x, finalDest.y, finalDest.z)
                return
            end

            local tx, ty, tz = lastDestX, lastDestY, lastDestZ
            ezPath = nil
            GWB.EZMover.targetObj = nil
            -- Stop character movement
            GWB.EZMover:ClickToMoveSafeZ(px, py, pz)
            GWB:FireCallback("OnMovementFinished", "xyz", tx, ty, tz)
            return
        end
        ezPathIndex = ezPathIndex + 1
        
        -- Safe NavMesh Lookahead Smoothing
        if Nn.EZ and Nn.EZ.Nav and Nn.EZ.Nav.Raycast then
            local mapId = select(8, GetInstanceInfo())
            local lookahead = math.min(#ezPath, ezPathIndex + 6) -- Look up to 6 nodes ahead
            for i = lookahead, ezPathIndex + 1, -1 do
                local futureNode = ezPath[i]
                -- Test NavMesh line of sight!
                if Nn.EZ.Nav.Raycast(mapId, px, py, pz, futureNode.x, futureNode.y, futureNode.z) then
                    ezPathIndex = i
                    break
                end
            end
        end
        
        wp = ezPath[ezPathIndex]

        -- Check if this is a quest interaction (turn-in/accept)
        local isQuestInteraction = false
        if GWB.QuestHandler and GWB.QuestHandler.CurrentAutopilotPin then
            local pin = GWB.QuestHandler.CurrentAutopilotPin
            if pin.type == "complete" or pin.type == "available" then
                isQuestInteraction = true
            end
        end

        ClickToMoveWithWhiskers(px, py, pz, wp.x, wp.y, wp.z, isQuestInteraction)
    else
        -- Random chance to jump while running
        if math.random(1, 1000) > 990 then
            if Unlock and JumpOrAscendStart then
                Unlock(JumpOrAscendStart)
                C_Timer.After(0.5, function() Unlock(AscendStop) end)
            end
        end

        -- Disable whiskers if UnstuckHandler is performing maneuvers to prevent fighting
        local isUnstuck = GWB.State and GWB.State:getCurrentState() == "plugin.UnstuckHandler"
        if isUnstuck then
            GWB.EZMover:ClickToMoveSafeZ(wp.x, wp.y, wp.z)
        else
            -- Check if this is a quest interaction (turn-in/accept)
            local isQuestInteraction = false
            if GWB.QuestHandler and GWB.QuestHandler.CurrentAutopilotPin then
                local pin = GWB.QuestHandler.CurrentAutopilotPin
                if pin.type == "complete" or pin.type == "available" then
                    isQuestInteraction = true
                end
            end

            ClickToMoveWithWhiskers(px, py, pz, wp.x, wp.y, wp.z, isQuestInteraction)
        end
    end
end

GWB:RegisterTicker("EZMoverTick", EZMoverTick)
GWB:TickerSetState("EZMoverTick", true)

-- ==========================================================
-- Hook GWB.Mover to safely route to EZMover for all plugins
-- ==========================================================
if GWB.Mover then
    local orig_Mover_MoveToXYZ = GWB.Mover.MoveToXYZ
    local orig_Mover_MoveToObject = GWB.Mover.MoveToObject
    local orig_Mover_Stop = GWB.Mover.Stop
    local orig_Mover_IsMoving = GWB.Mover.IsMoving
    local orig_Mover_StartMove = GWB.Mover.StartMove

    function GWB.Mover:MoveToXYZ(x, y, z)
        if GWB.pauseMovementUntil and GetTime() < GWB.pauseMovementUntil then
            return false
        end
        if GWB.Settings.UseEZNavSafe then
            local lx, ly, lz = GWB.EZMover:GetDestXYZ()
            if lx then
                local destDist = math.sqrt((x-lx)^2 + (y-ly)^2 + (z-lz)^2)
                if GWB.EZMover:IsMoving() and destDist < 2.0 then
                    return true
                end
            end
            -- We intercept the command and pass it to EZMover
            if orig_Mover_Stop then orig_Mover_Stop(self) end
            return GWB.EZMover:MoveToXYZ(x, y, z)
        end
        if orig_Mover_MoveToXYZ then
            return orig_Mover_MoveToXYZ(self, x, y, z)
        end
    end

    function GWB.Mover:MoveToObject(obj)
        if GWB.pauseMovementUntil and GetTime() < GWB.pauseMovementUntil then
            return false
        end
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            if orig_Mover_Stop then orig_Mover_Stop(self) end
            return GWB.EZMover:MoveToObject(obj)
        end
        if orig_Mover_MoveToObject then
            return orig_Mover_MoveToObject(self, obj)
        end
    end

    function GWB.Mover:Stop()
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            GWB.EZMover:Stop()
        end
        if orig_Mover_Stop then
            return orig_Mover_Stop(self)
        end
    end

    local orig_Mover_HaltMovement = GWB.Mover.HaltMovement
    function GWB.Mover:HaltMovement()
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            GWB.EZMover:Stop()
        end
        if orig_Mover_HaltMovement then
            return orig_Mover_HaltMovement(self)
        end
    end

    function GWB.Mover:IsMoving()
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            return GWB.EZMover:IsMoving()
        end
        if orig_Mover_IsMoving then
            return orig_Mover_IsMoving(self)
        end
        return false
    end

    function GWB.Mover:StartMove()
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            GWB.EZMover:StartMove()
            return
        end
        if orig_Mover_StartMove then
            return orig_Mover_StartMove(self)
        end
    end

    -- Shim Update() and GetPlayerPosition() so legacy code
    -- doesn't trigger obfuscated mover internals when EZNavSafe is on
    local orig_Mover_Update = GWB.Mover.Update
    function GWB.Mover:Update()
        if GWB.Settings.UseEZNavSafe then
            return -- no-op: skip legacy mover tick
        end
        if orig_Mover_Update then
            return orig_Mover_Update(self)
        end
    end

    local orig_Mover_GetPlayerPosition = GWB.Mover.GetPlayerPosition
    function GWB.Mover:GetPlayerPosition()
        if GWB.Settings.UseEZNavSafe then
            return ObjectPosition("player")
        end
        if orig_Mover_GetPlayerPosition then
            return orig_Mover_GetPlayerPosition(self)
        end
        return ObjectPosition("player")
    end

    local orig_Mover_GetTargetXYZ = GWB.Mover.GetTargetXYZ
    function GWB.Mover:GetTargetXYZ()
        if GWB.Settings.UseEZNavSafe then
            return lastDestX, lastDestY, lastDestZ
        end
        if orig_Mover_GetTargetXYZ then
            return orig_Mover_GetTargetXYZ(self)
        end
        return 0, 0, 0
    end

    -- Shim the legacy Tick so it doesn't fire when EZNavSafe owns movement
    local orig_Mover_Tick = GWB.Mover.Tick
    GWB.Mover.Tick = function(...)
        if GWB.Settings.UseEZNavSafe then
            return -- no-op: EZMoverTick handles everything
        end
        if orig_Mover_Tick then
            return orig_Mover_Tick(...)
        end
    end
end

