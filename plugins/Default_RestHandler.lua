local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "RestHandler"

-- TODO: add these for API or whatever? maybe just use Interface/build nrs?
plugin.xpacs = "classic" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "Unknown"

--[[

This is some sort of post-combat thing, which will make sure
to use resources, check bags, and dispatch to Waypoints when
certain params have reached

]]

plugin.settings = {
    ["rest_start_hp_percent"] = {
        ["label"] = "Regen hp at x%",
        ["value"] = 50
    },
    ["rest_start_mana_percent"] = {
        ["label"] = "Regen mana at x%",
        ["value"] = 50,
    },
    ["rest_stop_hp_percent"] = {
        ["label"] = "Regen hp stop at x%",
        ["value"] = 85,
    },
    ["rest_stop_mana_percent"] = {
        ["label"] = "Regen mana stop at x%",
        ["value"] = 85,
    },

    -- TODO!!!
    ["rest_use_food_normal"] = {
        ["label"] = "Consume food while resting",
        ["value"] = false,
    },
    ["rest_use_drink"] = {
        ["label"] = "Consume drink while resting",
        ["value"] = false,
    },
    -- Track item collection, and ONLY use items collected (purchased)
    -- while botting, to prevent harming inventory?
    ["rest_consume_collected_only"] = {
        ["label"] = "Consume ONLY items collected from botting",
        ["value"] = true 
    }
}



-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.DEFAULT
plugin.callbacks = {}
plugin.handlers = {}

-- helper to locate an item in bags
local function FindItemLocation(itemId)
    local GetContainerItemID = GetContainerItemID or C_Container.GetContainerItemID
    local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots

    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = GetContainerNumSlots(bag)

        for slot = 1, numSlots do
            local idInSlot = GetContainerItemID(bag, slot)
            if idInSlot == itemId then
                return bag, slot
            end
        end
    end
    return nil, nil
end

local function FindBestConsumableInBags(consumables)
    local itemIds = GWB.Inv.currentItems

    if not itemIds or not consumables then return nil end

    -- quick lookup set for inventory itemIDs
    --[[
    local invSet = {}
    for i = 1, #itemIds do
        local id = itemIds[i]
        if id then invSet[id] = true end
    end]]

    local lvl = UnitLevel("player") -- player level :contentReference[oaicite:1]{index=1}
    if not lvl or lvl <= 0 then return nil end

    -- find highest required level in food table
    local maxReq = 0
    for reqLevel, _ in pairs(consumables) do
        --print(reqLevel, maxReq)
        if reqLevel > maxReq then maxReq = reqLevel end
    end
    
    local function GetCount(itemId)
        return itemIds[tostring(itemId)] or 0
    end
    
    -- walk down from best food to worst
    for req = maxReq, 1, -1 do
        if req <= lvl then
            local foodsAtReq = consumables[req]
            --print(req, foodsAtReq)
            if foodsAtReq then
                for j = 1, #foodsAtReq do
                    local itemId = foodsAtReq[j]
                    --print("checking", itemId)
                    local count = GetCount(itemId)

                    if count > 0 then
                        local bag, slot = FindItemLocation(itemId)
                        if bag then
                            return itemId, bag, slot, req, count
                        end
                        -- if count says yes but bag scan fails, keep searching
                    end
                end
            end
        end
    end

    return nil
end

local function FindBestConsumableInBags_()
    return FindBestConsumableInBags(GWB.DB.classic.drinks)
end
GWB.test = FindBestConsumableInBags_

-- FYI "Food" AuraId: 433
local function ConsumeBestFoodIfPossible()
    local foodIds = GWB.DB.classic.food_normal
    local foodId, bag, slot, req = FindBestConsumableInBags(foodIds)
    if not foodId then return end
    if C_Container and C_Container.UseContainerItem then
        --print("C_Container.UseContainerItem(", bag, slot, ")")
        Unlock(C_Container.UseContainerItem, bag, slot)
    else
        Unlock(UseContainerItem, bag, slot)
    end
end

-- FYI "Drink" AuraId: 430
local function ConsumeBestDrinkIfPossible()
    local drinkIds = GWB.DB.classic.drinks
    local drinkId, bag, slot, req = FindBestConsumableInBags(drinkIds)
    --print("drinkIds", drinkId, bag, slot, req)
    if not drinkId then return end
    if C_Container and C_Container.UseContainerItem then
        --print("C_Container.UseContainerItem(", bag, slot, ")")
        Unlock(C_Container.UseContainerItem, bag, slot)
    else
        Unlock(UseContainerItem, bag, slot)
    end
end

local EATING_SPELL_ID   = 433 -- "Food"
local DRINKING_SPELL_ID = 430 -- "Drink"

local function HasAuraByID(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil
    else
        return GetPlayerAuraBySpellID(spellID) ~= nil
    end
end

local function IsPlayerEating()
    return HasAuraByID(EATING_SPELL_ID)
end

local function IsPlayerDrinking()
    return HasAuraByID(DRINKING_SPELL_ID)
end


plugin.handlers.NeedResting = function()
    -- no resting mid combat
    if UnitAffectingCombat("player") then return false end

    local min_hp = plugin.settings.rest_start_hp_percent.value / 100
    local min_mana = plugin.settings.rest_start_mana_percent.value / 100

    local hp = GWB.Utils.SafeNumber(UnitHealth("player"))
    local maxHp = GWB.Utils.SafeNumber(UnitHealthMax("player"))
    local hpp = (maxHp > 0) and (hp/maxHp) or 1

    local power = GWB.Utils.SafeNumber(UnitPower("player"))
    local powerMax = GWB.Utils.SafeNumber(UnitPowerMax("player"))
    local pp = (powerMax > 0) and (power/powerMax) or 1

    -- Start resting if below 70 %
    --print("need resting", hpp, ", ", pp)
    if hpp < min_hp or pp < min_mana then return true end

    return false
end

-- check if resting is OK?
-- NOTE: Maybe we should dispatch into "PostCombat"
-- if we were in combat while getting rested?
plugin.handlers.stateTick = function()
    -- cant eat shit if ded tho
    if 
        UnitAffectingCombat("player") or -- this is always true after combat ;_;
        UnitIsDead("player") or 
        UnitIsDeadOrGhost("player") 
    then
        return true -- exit current
    end

    local min_hp = plugin.settings.rest_start_hp_percent.value / 100
    local min_mana = plugin.settings.rest_start_mana_percent.value / 100

    local max_hp = plugin.settings.rest_stop_hp_percent.value / 100
    local max_mana = plugin.settings.rest_stop_mana_percent.value / 100

    local use_food = plugin.settings.rest_use_food_normal.value
    local use_drink = plugin.settings.rest_use_drink.value

    -- just wait for 90/90 on energy/mana/hp?

    -- pause movement?
    if GWB.Mover:IsMoving() then
        GWB.Mover:HaltMovement()
    end

    local hp = GWB.Utils.SafeNumber(UnitHealth("player"))
    local maxHp = GWB.Utils.SafeNumber(UnitHealthMax("player"))
    local hpp = (maxHp > 0) and (hp/maxHp) or 1

    local power = GWB.Utils.SafeNumber(UnitPower("player"))
    local powerMax = GWB.Utils.SafeNumber(UnitPowerMax("player"))
    local pp = (powerMax > 0) and (power/powerMax) or 1

    -- if we drinking, we better wait for 100% lmfao
    if (IsPlayerDrinking() and pp < 0.98) or (IsPlayerEating() and hpp < 0.98) then
        -- wait!
        --print("we consuming items, better wait to get near 98% !")
    else
        -- rest finish after 90%
        --GWB:Debug("rest regen", hpp, ", ", pp)
        -- NOTE: We can check if previous state was "Wapoints" or
        -- if "TownHandler", so we can reduce regen required?
        local prevState = GWB.State.stateStack[#GWB.State.stateStack]
        if prevState == "plugin.TownHandler" then
            -- only take 75% of requested?
            if (hpp > (max_hp*0.75) and pp > (max_mana*0.75)) then return true end
        else
            -- TODO: check if we rawdogging it, or consume food/drink?
            if (hpp > max_hp and pp > max_mana) then return true end
        end

        if hpp < min_hp and not IsPlayerEating() then
            --GWB:Debug("start consume foooood??")
            if use_food then
                ConsumeBestFoodIfPossible()
            end
        end

        if pp < min_mana and not IsPlayerDrinking() then
            --GWB:Debug("Start consume drunk!??")
            if use_drink then
                ConsumeBestDrinkIfPossible()
            end
        end
    end

    -- oh well, if we 100 we can leave, regardless of Food/Drink buff!
    if pp > 0.98 and hpp >= 0.98 then return true end

    return false
end

local function test()

end

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    -- TODO: stop resting !!!
    if GWB.State:getCurrentState() == "plugin.RestHandle" then
        print("COMBAT WHILE RESTING, REEEEEEEEE")
        GWB.State:returnState()
    end
    --print("WEEE NEED LEAVE REST HANDLER")
end
plugin.callbacks.OnPlayerDeath = function(ctx)
    if GWB.State:getCurrentState() == "plugin.RestHandle" then
        print("LEAVING TEST HANDLER ")
        GWB.State:returnState()
    end
    --print("WEEE NEED LEAVE REST HANDLER")
    -- ????, we must return if this is our current state!
end



local function OnLoad()

end

GWB:RegisterPlugin(plugin)

OnLoad() -- maybe call this external??
