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
    if playerDist < 1.5 then
        ezPath = {{x=px, y=py, z=pz}, {x=jx, y=jy, z=z}}
        ezPathIndex = 2
        return
    end

    isGenerating = true
    Nn.EZ.Nav.GeneratePath(px, py, pz, jx, jy, z, function(path)
        isGenerating = false
        if path and type(path) == "table" and #path > 1 then
            ezPath = path
            ezPathIndex = 2
            if ezPath[ezPathIndex] then
                ClickToMove(ezPath[ezPathIndex].x, ezPath[ezPathIndex].y, ezPath[ezPathIndex].z)
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

local function ClickToMoveWithWhiskers(px, py, pz, wx, wy, wz)
    local finalX, finalY, finalZ = wx, wy, wz
    local tLine = TraceLine or (Nn and Nn.TraceLine)
    
    if tLine then
        local dx = wx - px
        local dy = wy - py
        local dist2D = math.sqrt(dx*dx + dy*dy)
        local slopeZ = (wz - pz) / (dist2D > 0.1 and dist2D or 1)
        
        local yaw = math.atan2(dy, dx)
        local rayLen = 3.5
        local cx = px + math.cos(yaw) * rayLen
        local cy = py + math.sin(yaw) * rayLen
        local cz = pz + slopeZ * rayLen
        
        local hitC = tLine(px, py, pz + 1.0, cx, cy, cz + 1.0, 0x11)
        
        if hitC then
            local numRays = 16
            local step = (math.pi * 2) / numRays
            local currentFacing = yaw
            local hits = {}
            
            for i = 0, numRays - 1 do
                local angle = i * step
                local rx = px + math.cos(angle) * rayLen
                local ry = py + math.sin(angle) * rayLen
                hits[i] = tLine(px, py, pz + 1.0, rx, ry, cz + 1.0, 0x11)
            end
            
            local bestAngle = nil
            local minScore = 99999
            
            for i = 0, numRays - 1 do
                if not hits[i] then
                    local angle = i * step
                    local prevIdx = (i - 1 + numRays) % numRays
                    local nextIdx = (i + 1) % numRays
                    local hasClearance = not hits[prevIdx] and not hits[nextIdx]
                    
                    local diffToGoal = math.abs((angle - yaw + math.pi) % (math.pi * 2) - math.pi)
                    local diffToFacing = math.abs((angle - currentFacing + math.pi) % (math.pi * 2) - math.pi)
                    
                    local score = diffToGoal
                    if diffToFacing > 1.57 then
                        score = score + 10.0
                    end
                    if not hasClearance then
                        score = score + 5.0
                    end
                    
                    if score < minScore then
                        minScore = score
                        bestAngle = angle
                    end
                end
            end
            
            if bestAngle then
                finalX = px + math.cos(bestAngle) * 2.5
                finalY = py + math.sin(bestAngle) * 2.5
                finalZ = pz
            end
        end
    end
    
    ClickToMove(finalX, finalY, finalZ)
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
            local tx, ty, tz = lastDestX, lastDestY, lastDestZ
            ezPath = nil
            GWB.EZMover.targetObj = nil
            -- Stop character movement
            ClickToMove(px, py, pz)
            GWB:FireCallback("OnMovementFinished", "xyz", tx, ty, tz)
            return
        end
        ezPathIndex = ezPathIndex + 1
        wp = ezPath[ezPathIndex]
        
        -- Add jitter to waypoints
        wp.x = wp.x + (math.random() * 1.0 - 0.5)
        wp.y = wp.y + (math.random() * 1.0 - 0.5)
        
        ClickToMoveWithWhiskers(px, py, pz, wp.x, wp.y, wp.z)
    else
        -- Random chance to jump while running
        if math.random(1, 1000) > 990 then
            if Unlock and JumpOrAscendStart then
                Unlock(JumpOrAscendStart)
                C_Timer.After(0.5, function() Unlock(AscendStop) end)
            end
        end
        ClickToMoveWithWhiskers(px, py, pz, wp.x, wp.y, wp.z)
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

    function GWB.Mover:MoveToXYZ(x, y, z, dist)
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            if orig_Mover_Stop then orig_Mover_Stop(self) end
            GWB.EZMover:MoveToXYZ(x, y, z)
            return true
        end
        if orig_Mover_MoveToXYZ then
            return orig_Mover_MoveToXYZ(self, x, y, z, dist)
        end
    end

    function GWB.Mover:MoveToObject(obj)
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

