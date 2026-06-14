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
                        d:SetColorRaw(255, 0, 0, 200)
                    else
                        d:SetColorRaw(0, 255, 0, 200)
                    end
                    d:Line(ray.px, ray.py, ray.pz, ray.rx, ray.ry, ray.rz)
                end
            end)
            return true
        end
    end
    return false
end

local function ClickToMoveWithWhiskers(px, py, pz, wx, wy, wz)
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
        local os = Objects()
        local avoidanceVectorX, avoidanceVectorY = 0, 0
        local avoidanceWeight = 0

        for i = 1, #os do
            local o = os[i]
            local ox, oy, oz = ObjectPosition(o)
            if ox then
                local odist = math.sqrt((ox-px)^2 + (oy-py)^2 + (oz-pz)^2)
                -- Check if mob is within 25 yards (aggro range is 20) and in front of us
                if odist < 25.0 and odist > 0.1 then
                    local toMobX, toMobY = ox - px, oy - py
                    local toMobDist = math.sqrt(toMobX^2 + toMobY^2)
                    local toMobNormX, toMobNormY = toMobX / toMobDist, toMobY / toMobDist

                    -- Check if mob is in front (dot product with movement direction)
                    local moveNormX, moveNormY = dx / dist2D, dy / dist2D
                    local dotProduct = toMobNormX * moveNormX + toMobNormY * moveNormY

                    if dotProduct > 0.1 then  -- Mob is generally in front
                        -- Check if mob is aggressive and not a quest objective
                        local isAggressive = UnitCanAttack("player", o) and not UnitIsDeadOrGhost(o)
                        local isQuestMob = GWB.QuestHandler and GWB.QuestHandler.IsObjective and GWB.QuestHandler:IsObjective(o)

                        if isAggressive and not isQuestMob then
                            -- Calculate avoidance vector (perpendicular to direction to mob)
                            local avoidX, avoidY = -toMobNormY, toMobNormX
                            -- Weight by distance (closer = stronger avoidance)
                            local weight = (25.0 - odist) / 25.0
                            avoidanceVectorX = avoidanceVectorX + avoidX * weight
                            avoidanceVectorY = avoidanceVectorY + avoidY * weight
                            avoidanceWeight = avoidanceWeight + weight
                        end
                    end
                end
            end
        end

        -- Apply avoidance steering if needed
        if avoidanceWeight > 0.1 then
            local avoidNormX = avoidanceVectorX / avoidanceWeight
            local avoidNormY = avoidanceVectorY / avoidanceWeight
            -- Blend avoidance with goal direction (30% goal, 70% avoidance for strong steering)
            finalX = px + (dx * 0.3 + avoidNormX * dist2D * 0.7)
            finalY = py + (dy * 0.3 + avoidNormY * dist2D * 0.7)
            finalZ = pz + slopeZ * dist2D
            GWB.EZMover:ClickToMoveSafeZ(finalX, finalY, finalZ)
            return
        end

        -- Use multiple ray lengths to detect obstacle boundaries
        local rayLengths = {1.5, 2.5, 4.0, 6.0, 8.0}  -- More varied ray lengths
        local numRays = 32  -- Increased from 16 to 32 for finer angular resolution
        local step = (math.pi * 2) / numRays

        local drawDebug = GWB.Settings and GWB.Settings.DebugWhiskers
        if drawDebug then
            InitLibDraw()
            wipe(libDrawRays)
        end

        -- Waist level raycasts (+1.0) instead of chest/head level (+2.0)
        local Z_OFFSET = 1.0

        -- Check if current path is clear up to the destination (don't check past it!)
        local currentPathClear = true
        for _, rayLen in ipairs(rayLengths) do
            if rayLen <= dist2D + 0.5 then
                local cx = px + math.cos(yaw) * rayLen
                local cy = py + math.sin(yaw) * rayLen
                local cz = pz + slopeZ * rayLen
                
                local hit = tLine(px, py, pz + Z_OFFSET, cx, cy, cz + Z_OFFSET, 0x100111)

                if drawDebug then
                    libDrawRays[#libDrawRays + 1] = {px = px, py = py, pz = pz + Z_OFFSET, rx = cx, ry = cy, rz = cz + Z_OFFSET, hit = hit}
                end

                if hit then
                    currentPathClear = false
                    break
                end
            end
        end

        -- If current path is clear and we have momentum, stick to it
        if currentPathClear and lastWhiskerAngle and now - lastWhiskerTime < 1.0 then
            local angleDiff = math.abs((yaw - lastWhiskerAngle + math.pi) % (math.pi * 2) - math.pi)
            if angleDiff < 0.5 and lastMovementSpeed > 3.0 then
                -- Keep current direction, no change needed
                lastWhiskerAngle = yaw
                lastWhiskerTime = now
                -- No need to hide lines manually, LibDraw Sync handles clearing
                GWB.EZMover:ClickToMoveSafeZ(wx, wy, wz)
                return
            end
        end

        -- Path blocked, use multi-length whiskers to find best direction
        local angleScores = {}
        local angleClearances = {}
        for i = 1, numRays do
            angleScores[i] = 0
            angleClearances[i] = 0
        end

        for i = 1, numRays do
            local angle = yaw - math.pi + (i - 1) * step

            -- Test each angle at multiple lengths, up to a reasonable cap
            for _, rayLen in ipairs(rayLengths) do
                -- Don't penalize paths that hit walls past the actual destination
                if rayLen <= math.max(dist2D + 1.0, 4.0) then
                    local rx = px + math.cos(angle) * rayLen
                    local ry = py + math.sin(angle) * rayLen
                    local rz = pz + slopeZ * rayLen
                    
                    local hit = tLine(px, py, pz + Z_OFFSET, rx, ry, rz + Z_OFFSET, 0x100111)

                    if drawDebug then
                        libDrawRays[#libDrawRays + 1] = {px = px, py = py, pz = pz + Z_OFFSET, rx = rx, ry = ry, rz = rz + Z_OFFSET, hit = hit}
                    end

                    if not hit then
                        angleClearances[i] = angleClearances[i] + rayLen
                    else
                        -- Penalize heavily if blocked at short range
                        if rayLen == 1.5 or rayLen == 2.5 then
                            angleScores[i] = angleScores[i] + 100
                        end
                    end
                end
            end

            -- Prefer angles with longer clearance
            angleScores[i] = angleScores[i] - angleClearances[i]
        end
        
        -- No need to hide lines manually, LibDraw Sync handles clearing

        -- Find best angle considering goal direction and clearance
        local bestAngle = nil
        local minScore = 99999

        for i = 1, numRays do
            local angle = yaw - math.pi + (i - 1) * step
            local diffToGoal = math.abs((angle - yaw + math.pi) % (math.pi * 2) - math.pi)

            -- HEAVILY penalize turning away from the goal (e.g. running backwards down a hallway)
            local score = angleScores[i] + (diffToGoal * 15.0)

            -- Bonus for angles similar to last chosen direction (momentum)
            if lastWhiskerAngle then
                local diffToLast = math.abs((angle - lastWhiskerAngle + math.pi) % (math.pi * 2) - math.pi)
                if diffToLast < 0.3 then
                    score = score - 2.0
                end
            end

            if score < minScore then
                minScore = score
                bestAngle = angle
            end
        end

        if bestAngle then
            finalX = px + math.cos(bestAngle) * 5.0
            finalY = py + math.sin(bestAngle) * 5.0
            finalZ = pz
            lastWhiskerAngle = bestAngle
            lastWhiskerTime = now
        else
            -- Fallback to goal direction
            lastWhiskerAngle = yaw
            lastWhiskerTime = now
        end

        -- Track movement speed for momentum
        if lastWhiskerAngle then
            local speed = dist2D / (now - lastWhiskerTime + 0.1)
            lastMovementSpeed = speed
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
    
    -- Smooth the path by skipping intermediate waypoints if we have direct line of sight
    local tLine = TraceLine or (Nn and Nn.TraceLine)
    if tLine and ezPathIndex < #ezPath then
        -- Check up to 5 waypoints ahead to skip jagged/unnecessary detours
        local maxScan = math.min(#ezPath, ezPathIndex + 5)
        for scanIdx = maxScan, ezPathIndex + 1, -1 do
            local scanWp = ezPath[scanIdx]
            -- Check Line of Sight at waist level (+1.0)
            local hit = tLine(px, py, pz + 1.0, scanWp.x, scanWp.y, scanWp.z + 1.0, 0x100111)
            if not hit then
                ezPathIndex = scanIdx
                break
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
        wp = ezPath[ezPathIndex]
        
        ClickToMoveWithWhiskers(px, py, pz, wp.x, wp.y, wp.z)
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
            ClickToMoveWithWhiskers(px, py, pz, wp.x, wp.y, wp.z)
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

