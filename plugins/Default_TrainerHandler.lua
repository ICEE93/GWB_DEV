local Nn, GWB = ...
--[==[
-- plugin object eh
local plugin = {}
plugin.name = "TrainerHandler"

-- TODO: add these for API or whatever? maybe just use Interface/build nrs?
plugin.xpacs = "classic" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "Unknown"

--[[

]]

plugin.settings = {
}

local blacklistRepairUntil = 0
-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.DEFAULT
plugin.callbacks = {}
plugin.handlers = {}


local function _findClosestTrainerForLevel(trainers, myLvl, px, py, pz)
    local bestTrainer = nil
    local bestDistSq = math.huge  -- use squared distance to avoid sqrt cost

    for _, t in ipairs(trainers) do
        if t.lvl <= myLvl then
            local dx = px - t.coord.x
            local dy = py - t.coord.y
            --local dz = pz - t.coord.z
            local distSq = dx*dx + dy*dy --+ dz*dz

            if distSq < bestDistSq then
                bestDistSq = distSq
                bestTrainer = t
            end
        end
    end

    return bestTrainer, bestDistSq
end
local function GetNearbyClassTrainer(mapId)
    -- GWB.DB.classic.trainers
    local trainers = GWB.DB.classic.trainers
    if trainers == nil then
        GWB:Print("No trainer data!")
        return
    end
    
    local class = select(2, UnitClass("player"))
    local classTrainers = trainers[class]
    if classTrainers == nil then
        GWB:Print("No trainer data for", class)
        return
    end

    local nearbyTrainers = classTrainers[mapId]
    if nearbyTrainers == nil then
        GWB:Print("No nearby trainers for map", mapId)
        return
    end

    -- find closest one??
    local lvl = UnitLevel("player")
    GWB.Mover:Update()
    local x, y, z = GWB.Mover:GetPlayerPosition()
    
    return _findClosestTrainerForLevel(nearbyTrainers, lvl, x, y, z)
end
GWB.GetNearbyClassTrainer = GetNearbyClassTrainer

local function IsClassTrainerFinished()
    return false
end
local function IsClassTrainerNeeded()
    true
end

]==]--