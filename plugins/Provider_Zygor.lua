local Nn, GWB = ...
local plugin = {
    name = "ZygorProvider",
	xpacs = "classic|retail",
    author = "GWB",
    description = "Provides autopilot routing and objective targeting driven by Zygor Guides.",
    version = "1.0",
}

local ZygorProvider = {}

-- Track alternative coordinates for cycling
local altCoordsIndex = 0
local altCoordsList = {}
local lastAltCoordsUpdate = 0

-- Helper function to check if a quest is actually in the player's quest log
local function IsQuestInLog(questId)
    if not questId then return false end

    local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for i = 1, numEntries do
        local title, level, suggestedGroup, isHeader, isComplete = GetQuestLogTitle(i)
        if title and not isHeader then
            local questLogId = GetQuestLogQuestID and GetQuestLogQuestID(i)
            if questLogId == questId then
                return true
            end
        end
    end
    return false
end

local function MapPosToWorldPos(mapID, x, y)
    local mapPos = CreateVector2D(x, y)
    local ret1, ret2 = C_Map.GetWorldPosFromMapPos(mapID, mapPos)
    if ret2 then
        return ret2.x, ret2.y, 0 -- Returning 0 for Z, the mover can handle trace/grounding
    end
    return nil, nil, nil
end

function ZygorProvider.GetNextWaypoint()
    if not ZGV or not ZGV.Pointer or not ZGV.Pointer.DestinationWaypoint then
        return nil
    end

    local wp = ZGV.Pointer.DestinationWaypoint
    local debugZ = false

    if wp and wp.x and wp.y and wp.m then
        if debugZ then GWB:Print("[Zygor Debug] Waypoint coords:", wp.m, wp.x, wp.y) end

        -- Check for alternative coordinates in Zygor step data
        local now = GetTime()
        local hasAltCoords = false

        if ZGV.CurrentStep and ZGV.CurrentStep.goals then
            altCoordsList = {}
            for i, goal in ipairs(ZGV.CurrentStep.goals) do
                -- Zygor stores alternative coords in goal.alt_coords or similar
                if goal.alt_coords and type(goal.alt_coords) == "table" then
                    for _, altCoord in ipairs(goal.alt_coords) do
                        if altCoord.x and altCoord.y and altCoord.m then
                            table.insert(altCoordsList, {
                                x = altCoord.x,
                                y = altCoord.y,
                                m = altCoord.m
                            })
                            hasAltCoords = true
                        end
                    end
                end
                -- Also check for coords in goal.coords (some Zygor versions use this)
                if goal.coords and type(goal.coords) == "table" then
                    for _, coord in ipairs(goal.coords) do
                        if coord.x and coord.y and coord.m then
                            table.insert(altCoordsList, {
                                x = coord.x,
                                y = coord.y,
                                m = coord.m
                            })
                            hasAltCoords = true
                        end
                    end
                end
            end
        end

        -- If we have alternative coordinates, cycle through them
        if hasAltCoords and #altCoordsList > 0 then
            -- Only advance index if 10 seconds have passed, allowing the bot time to walk there
            if now - lastAltCoordsUpdate > 10.0 or altCoordsIndex == 0 then
                altCoordsIndex = altCoordsIndex + 1
                if altCoordsIndex > #altCoordsList then
                    altCoordsIndex = 1
                end
                lastAltCoordsUpdate = now
            end

            -- Use current alternative coordinate (Do not modify wp directly to avoid corrupting Zygor's internal state)
            local wp_local_x, wp_local_y, wp_local_m = nil, nil, nil
            local altCoord = altCoordsList[altCoordsIndex]
            if altCoord then
                if debugZ then GWB:Print("[Zygor Debug] Using alternative coordinate", altCoordsIndex, "of", #altCoordsList) end
                
                -- Create a local copy to map to world position
                local altX = altCoord.x
                local altY = altCoord.y
                local altM = altCoord.m
                
                local wx, wy, wz = MapPosToWorldPos(altM, altX, altY)
                if wx and wy then
                    local p = { x = altX, y = altY, wx = wx, wy = wy, wz = wz, mapId = altM, score = 100 }
                    -- (We continue with the normal NPC ID matching logic using this new point)
                    wp_local_x = altX
                    wp_local_y = altY
                    wp_local_m = altM
                end
            end
        end

        local useX = wp_local_x or wp.x
        local useY = wp_local_y or wp.y
        local useM = wp_local_m or wp.m

        -- Zygor uses normalized coordinates (e.g., 0.45)
        local wx, wy, wz = MapPosToWorldPos(useM, useX, useY)
        if wx and wy then
            local p = { x = useX, y = useY, wx = wx, wy = wy, wz = wz, mapId = useM, score = 100 }

            -- If this step requires NPC interaction, map it to the engine's 'available' or 'complete' type
            if ZGV.CurrentStep and ZGV.CurrentStep.goals then
                for i, goal in ipairs(ZGV.CurrentStep.goals) do
                    local action = goal.action
                    if debugZ then GWB:Print("[Zygor Debug] Goal", i, "Action:", tostring(action), "NPCID:", tostring(goal.npcid), "TargetID:", tostring(goal.targetid)) end

                    if action == "talk" or action == "accept" or action == "turnin" or
                       action == "buy" or action == "sell" or action == "interact" or action == "fly" then
                       
                        if action == "fly" and ZGV.db and ZGV.db.profile then
                            ZGV.db.profile.autotaxi = true
                        end

                        p.type = "available"
                        local rawId = goal.npcid or goal.targetid
                        if rawId then
                            if type(rawId) == "string" and rawId:find(",") then
                                p.id = tonumber((strsplit(",", rawId)))
                            else
                                p.id = tonumber(rawId)
                            end
                        end

                        if not p.id and goal.mobs and goal.mobs[1] then
                            p.id = tonumber(goal.mobs[1].id)
                        end

                        if p.id then
                            if debugZ then GWB:Print("[Zygor Debug] Matched interaction! Returning pin with ID:", p.id) end
                            break
                        end
                    end
                end
            end

            if debugZ and not p.id then GWB:Print("[Zygor Debug] Returning pure coordinates. No NPC ID found.") end
            return p
        end
    end
    return nil
end

function ZygorProvider.IsObjective(obj)
    if not ZGV or not ZGV.CurrentStep or not ZGV.CurrentStep.goals then
        return false, nil
    end

    local objType = ObjectType(obj)
    local targetId = nil
    if objType == 8 then
        targetId = type(ObjectId) == "function" and ObjectId(obj) or (Nn and Nn.ObjectId and Nn.ObjectId(obj))
    else
        targetId = type(ObjectUnitId) == "function" and ObjectUnitId(obj) or (Nn and Nn.ObjectUnitId and Nn.ObjectUnitId(obj))
    end

    if not targetId then return false, nil end

    local currentStepNum = ZGV.CurrentStepNum or 1
    local steps = ZGV.CurrentGuide and ZGV.CurrentGuide.steps
    local maxLookahead = currentStepNum

    if steps then
        maxLookahead = currentStepNum -- Only check current step, not future steps
    else
        steps = { [currentStepNum] = ZGV.CurrentStep }
    end

    for stepIdx = currentStepNum, maxLookahead do
        local step = steps[stepIdx]
        
        -- Try to avoid checking completely finished steps if possible
        local stepComplete = false
        if type(step.IsComplete) == "function" then
            pcall(function() stepComplete = step:IsComplete() end)
        end

        if step and step.goals and not stepComplete then
            for _, goal in ipairs(step.goals) do
                -- Skip completed goals
                local goalComplete = (goal.status == "complete")
                if type(goal.IsComplete) == "function" then
                    pcall(function() goalComplete = goalComplete or goal:IsComplete() end)
                end
                
                if not goalComplete then
                    local match = false
                    
                    local function checkIdMatch(rawId)
                        if not rawId then return false end
                        if type(rawId) == "string" and rawId:find(",") then
                            for idStr in rawId:gmatch("%d+") do
                                if tonumber(idStr) == targetId then return true end
                            end
                            return false
                        else
                            return tonumber(rawId) == targetId
                        end
                    end

                    if checkIdMatch(goal.targetid) then match = true end
                    if checkIdMatch(goal.npcid) then match = true end
                    
                    if goal.mobs then
                        for _, mob in ipairs(goal.mobs) do
                            if checkIdMatch(mob.id) then match = true; break end
                        end
                    end
                    
                    if not match and goal.target then
                        local objName = type(ObjectName) == "function" and ObjectName(obj) or (Nn and Nn.ObjectName and Nn.ObjectName(obj))
                        if objName and objName == goal.target then match = true end
                    end

                    if match then
                        local action = goal.action
                        if action == "kill" or action == "collect" or action == "interact" or
                           action == "talk" or action == "accept" or action == "turnin" or
                           action == "buy" or action == "sell" or action == "click" then
                            -- Check if this goal has a quest ID and validate it's in the player's log
                            local questId = goal.questId or goal.questid
                            if questId then
                                if not IsQuestInLog(questId) then
                                    -- Quest is in Zygor's data but not actually in the player's log, skip it
                                else
                                    return true, (goal.target or goal.targetshort or "Zygor Target")
                                end
                            else
                                return true, (goal.target or goal.targetshort or "Zygor Target")
                            end
                        end
                    end
                end
            end
        end
    end

    return false, nil
end

local function PluginInit()
    if not GWB.QuestHandler then return end
    if not GWB.QuestHandler.RegisterProvider then return end
    
    GWB.QuestHandler:RegisterProvider("Zygor", ZygorProvider)
    
    if ZGV then
        GWB:Print("[Zygor] Integration Initialized: Found Zygor Guides data structures.")
    end
end

-- Zygor blocks step progression on 'buy'/'sell' steps until the Merchant window is closed.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then
        if GWB.Settings and GWB.Settings.AutopilotProvider == "Zygor" then
            if GWB.State and GWB.State:getCurrentState() == "plugin.Waypoints" then
                -- Give ZGV 1.5 seconds to auto-buy/sell its items, then close it to advance the step
                C_Timer.After(1.5, function()
                    if MerchantFrame and MerchantFrame:IsVisible() then
                        local unlock = Unlock or (Nn and Nn.Unlock)
                        if unlock then
                            unlock(CloseMerchant)
                        else
                            CloseMerchant()
                        end
                        if GWB.Settings.DebugZygor then
                            GWB:Print("[Zygor Debug] Auto-closed Merchant window to advance Zygor step.")
                        end
                    end
                end)
            end
        end
    end
end)

C_Timer.After(1.0, PluginInit)
GWB:RegisterPlugin(plugin)
