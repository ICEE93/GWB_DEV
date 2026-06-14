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
            return { x = wp.x, y = wp.y, wx = wx, wy = wy, wz = wz, mapId = wp.m, score = 100 }
        end
    end
    return nil
end

function ZygorProvider.IsObjective(obj)
    if not ZGV or not ZGV.CurrentStep or not ZGV.CurrentStep.goals then
        return false, nil
    end

    local unitId = Nn.ObjectUnitId and Nn.ObjectUnitId(obj) or ObjectUnitId(obj)
    local objectId = Nn.ObjectId and Nn.ObjectId(obj) or ObjectId(obj)
    local targetId = unitId or objectId

    if not targetId then return false, nil end

    for _, goal in ipairs(ZGV.CurrentStep.goals) do
        -- Action types in Zygor like 'kill', 'collect', 'talk', 'accept', 'turnin', 'interact'
        if goal.targetid == targetId then
            local action = goal.action
            if action == "kill" or action == "collect" or action == "interact" then
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
