local Unlocker, Bot = ...


GWB.OM = {}

GWB.OM.LastUpdate = 0
GWB.OM.Objects = {} -- eh?

-- update all OM's
function GWB.OM:Update()
    GWB.OM.LastUpdate = GetTime()

    -- Fetching object manager by type directly for massive performance gains
    GWB.OM.Objects = {
        [5] = ObjectManager(5) or {},
        [6] = ObjectManager(6) or {},
        [7] = ObjectManager(7) or {},
        [8] = ObjectManager(8) or {},
        [9] = ObjectManager(9) or {},
    }
end

-- return a list of NPCs having the same Object identifier
function GWB.OM:FindNPCsById(id)
    self:Update() -- TODO: MOVE!

    local res = {}
    -- iterate all NPC objects
    for i=1, #GWB.OM.Objects[5] do
        local o = GWB.OM.Objects[5][i]
        if ObjectExists(o) then
            if ObjectUnitId(o) == id then
                table.insert(res, o)
            end
        end
    end
    return res
end

function GWB.OM:GetNearbyLootableCorpses(id)
    self:Update()

    local lootables = {}
    for i=1, #GWB.OM.Objects[5] do
        local o = GWB.OM.Objects[5][i]
        if ObjectExists(o) then
            if Unlocker.ObjectLootable(o) then
                table.insert(lootables, o)
            end
        end
    end

    return lootables
end

function GWB.OM:FindObjectsByName(name)
    self:Update()

    local objects = {}
    for i=1, #GWB.OM.Objects[8] do
        local o = GWB.OM.Objects[8][i]
        if ObjectExists(o) then
            if ObjectName(o) == name then
                table.insert(objects, o)
            end
        end
    end

    return objects
end

--- needles: list of string/keywords
function GWB.OM:FindObjectsByPartialName(needles)
    self:Update()

    local objects = {}
    for i=1, #GWB.OM.Objects[8] do
        local o = GWB.OM.Objects[8][i]
        if ObjectExists(o) then
            local objname = ObjectName(o)
            for j=1, #needles do
                if objname == nil then break end
                if string.find(string.lower(objname), string.lower(needles[j])) then
                    table.insert(objects, o)
                    break
                end
            end
        end
    end

    return objects
end

function GWB.OM:FindObjectsById(id)
    self:Update()

    local objects = {}
    for i=1, #GWB.OM.Objects[8] do
        local o = GWB.OM.Objects[8][i]
        if ObjectExists(o) then
            if ObjectId(o) == id then
                table.insert(objects, o)
            end
        end
    end

    return objects
end

function GWB.OM.FindPartyMembersPos()
    local pos = {}
    for i=1, 5 do
        local x, y, z = ObjectPosition("party" ..  tostring(i))
        if x then
            table.insert(pos, {x=x, y=y, z=z})
        end
    end
    return pos
end

function GWB.OM.FindTappedEnemiesPos()
    GWB.OM:Update() -- TODO: MOVE!

    local res = {}
    -- iterate all NPC objects
    for i=1, #GWB.OM.Objects[5] do
        local o = GWB.OM.Objects[5][i]
        if ObjectExists(o) then
            Unlocker.SetMouseover(o)
            if 
                UnitExists("mouseover") and not UnitIsDead("mouseover") 
                and UnitCanAttack("player", "mouseover") and UnitIsTapDenied("mouseover") 
            then
                table.insert(res, o)
            end
        end
    end

    return res
end
