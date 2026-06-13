local Unlocker, Bot = ...


GWB.OM = {}

GWB.OM.LastUpdate = 0
GWB.OM.Objects = {} -- eh?

-- update all OM's
function GWB.OM:Update()
    GWB.OM.LastUpdate = GetTime()

    -- TODO: check if new objects are added by comparing against old list,
    -- only query their names once, keep other cached?

    GWB.OM.Objects = {
        [5] = {},
        [6] = {},
        [7] = {},
        [8] = {},
        [9] = {},
    }
    local os = Unlocker.Objects()
    for i=1, #os do
        local o = os[i]
        local t = ObjectType(o)
        if t >= 5 and t <= 9 then
            table.insert(GWB.OM.Objects[t], o)
        end
    end
end

-- return a list of NPCs having the same Object identifier
function GWB.OM:FindNPCsById(id)
    GWB.OM.Update() -- TODO: MOVE!

    local res = {}
    -- iterate all NPC objects
    for i=1, #GWB.OM.Objects[5] do
        local o = GWB.OM.Objects[5][i]
        if ObjectId(o) == id then
            table.insert(res, o)
        end
    end
    return res
end

function GWB.OM:GetNearbyLootableCorpses(id)
    GWB.OM.Update()

    local lootables = {}
    for i=1, #GWB.OM.Objects[5] do
        local o = GWB.OM.Objects[5][i]
        if Unlocker.ObjectLootable(o) then
            table.insert(lootables, o)
        end
    end

    return lootables
end

function GWB.OM:FindObjectsByName(name)
    GWB.OM.Update()

    local objects = {}
    for i=1, #GWB.OM.Objects[8] do
        local o = GWB.OM.Objects[8][i]
        if ObjectName(o) == name then
            table.insert(objects, o)
        end
    end

    return objects
end

--- needles: list of string/keywords
function GWB.OM:FindObjectsByPartialName(needles)
    GWB.OM.Update()

    local objects = {}
    for i=1, #GWB.OM.Objects[8] do
        local o = GWB.OM.Objects[8][i]
        local objname = ObjectName(o)
        for i=1, #needles do
            if objname == nil then break end
            if string.find(string.lower(objname), string.lower(needles[i])) then
                table.insert(objects, o)
                break
            end
        end
    end

    return objects
end

function GWB.OM:FindObjectsById(id)
    GWB.OM.Update()

    local objects = {}
    for i=1, #GWB.OM.Objects[8] do
        local o = GWB.OM.Objects[8][i]
        if ObjectID(o) == id then
            table.insert(objects, o)
        end
    end

    return objects
end

function GWB.OM.FindPartyMembersPos()
    local pos = {}
    for i=1, 5 do
        local x, y, z = ObjectPosition("party" ..  tostring(i))
        table.insert(pos, {x=x, y=y, z=z})
    end
end

function GWB.OM.FindTappedEnemiesPos()
    GWB.OM.Update() -- TODO: MOVE!

    local old = Unlocker.GetFocus()

    local res = {}
    -- iterate all NPC objects
    for i=1, #GWB.OM.Objects[5] do
        local o = GWB.OM.Objects[5][i]
        
        Unlocker.SetFocus(o)
        if 
            UnitExists("focus") and not UnitIsDead("focus") 
            and UnitCanAttack("player", "focus") and UnitIsTapDenied("focus") 
        then
            table.insert(res, o)
        end
    end

    Unlocker.SetFocus(old)

    return res
end
