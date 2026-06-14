local Nn, GWB = ...
local plugin = {
    name = "ZygorProvider",
    author = "GWB",
    description = "Provides autopilot routing and objective targeting driven by Zygor Guides.",
    version = "1.0",
}

local ZygorProvider = {}

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
    if wp and wp.x and wp.y and wp.m then
        -- Zygor uses normalized coordinates (e.g., 0.45)
        local wx, wy, wz = MapPosToWorldPos(wp.m, wp.x, wp.y)
        if wx and wy then
            local p = { x = wp.x, y = wp.y, wx = wx, wy = wy, wz = wz, mapId = wp.m, score = 100 }
            
            -- If this step requires NPC interaction, map it to the engine's 'available' or 'complete' type
            if ZGV.CurrentStep and ZGV.CurrentStep.goals then
                for _, goal in ipairs(ZGV.CurrentStep.goals) do
                    local action = goal.action
                    if action == "talk" or action == "accept" or action == "turnin" or 
                       action == "buy" or action == "sell" or action == "interact" then
                        
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
                        
                        if p.id then break end
                    end
                end
            end
            
            return p
        end
    end
    return nil
end

function ZygorProvider.IsObjective(obj)
    if not ZGV or not ZGV.CurrentStep or not ZGV.CurrentStep.goals then
        return false, nil
    end

    local unitId = nil
    if type(ObjectUnitId) == "function" then
        unitId = ObjectUnitId(obj)
    elseif Nn and type(Nn.ObjectUnitId) == "function" then
        unitId = Nn.ObjectUnitId(obj)
    end

    local objectId = nil
    if type(ObjectId) == "function" then
        objectId = ObjectId(obj)
    elseif Nn and type(Nn.ObjectId) == "function" then
        objectId = Nn.ObjectId(obj)
    end

    local targetId = unitId or objectId

    if not targetId then return false, nil end

    for _, goal in ipairs(ZGV.CurrentStep.goals) do
        -- Action types in Zygor like 'kill', 'collect', 'talk', 'accept', 'turnin', 'interact'
        local match = false
        
        -- Zygor IDs are often strings, must cast to number for comparison
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

        if match then
            local action = goal.action
            if action == "kill" or action == "collect" or action == "interact" or 
               action == "talk" or action == "accept" or action == "turnin" or 
               action == "buy" or action == "sell" then
                return true, (goal.target or goal.targetshort or "Zygor Target")
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

C_Timer.After(1.0, PluginInit)
GWB:RegisterPlugin(plugin)
