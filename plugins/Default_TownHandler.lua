local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "TownHandler"

-- Works on all versions
plugin.xpacs = "" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "Unknown"

--[[

This plugin will "know" different vendors in different zones/areas, and
will only work in specific areas.

When (actively) invoked, it will walk around in the town and try to do
multiple things:
- Repair
- Sell junk
- Buy food
- Buy ammo (or other resources?)
- Class Trainer (only critical spells while leveling?)
- Proff Trainer (only a selected few?)

The ordering and logic must be optimized for e.g. Classic or TBC as
gold generation is rather slow. However in later expacs things get
nerfd so we can not worry about minmaxxing gold consumption

]]

plugin.settings = {
    ["town_buy_food"] = {
        ["label"] = "Buy vendor food",
        ["value"] = false
    },
    ["town_buy_food_count"] = {
        ["label"] = "Buy vendor food count",
        ["value"] = 0
    },
    ["town_buy_drink"] = {
        ["label"] = "Buy vendor drink",
        ["value"] = false
    },
    ["town_buy_drink_count"] = {
        ["label"] = "Buy vendor drink count",
        ["value"] = 40
    },
    ["town_repair_at_percent"] = {
        ["label"] = "Repair at x%",
        ["value"] = 30
    },

    -- Vendor at X bag free
    ["town_vendor_at_bags_free"] = {
        ["label"] = "Vendor items at X free bags",
        ["value"] = 2
    },


}


local lastStep = nil
local nearbyRepair = nil
local nearbyGoods = nil
local nearbyTrainer = nil
local lastRepairUpdate = 0
local lastSellAllDone = 0 -- we can sell during repair also >:3
local merchantOpened = false
local trainerOpened = false
local lastRepairAttempt = 0
local repairAttemptCount = 0
local MAX_ATTEMPT_REPAIR = 10 -- eh?
local vendorAttemptCount = 0
local sellQueue = {}
local sellTicker


local blacklistGoodsUntil = 0
local blacklistVendorUntil = 0
local blacklistRepairUntil = 0
local blacklistClassTrainerUntil = 0



-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.DEFAULT
plugin.callbacks = {}
plugin.handlers = {}

-- 1453, SW
-- 1429, Elwyn Forest
-- 

--[[
    1429 (Elwyn Forest), 74 (Kurran Steele), { -9457.64, 99.68, 58.34 }
    1453 (Stormwind City), 1287 (Marda Weller), { }
]]

local db_repair = {}

--       MapId,                                                                 ZoneText
db_repair[1429] = { -- Elwyn Forest
    { ["id"]=74,     ["coord"]={ ['x']=-9457.64, ['y']=99.68, ['z']=58.34 } }, -- Goldshire (Blacksmith), Kurran Steele
    { ["id"]=1213,   ["coord"]={ ['x']=-8898.23, ['y']=-119.83, ['z']=81.83 } }, -- Northshire Valley, Godric Rothgar
    { ["id"]=190,    ["coord"]={ ['x']=-8897.70, ['y']=-115.32, ['z']=81.84 } }, -- Northshire Valley, Dermot Johns
    { ["id"]=78,     ["coord"]={ ['x']=-8909.45, ['y']=-104.16, ['z']=81.84 } }, -- Northshire Valley, Janos Hammerknuckle
}

db_repair[1453] = { -- Stormwind City
    { ["id"]=1287,   ["coord"]={ ['x']=-9457.64, ['y']=99.68, ['z']=58.34 } } -- Marda Weller, Trade District
}
db_repair[1436] = { -- Westfall
    { id=1668, coord={x=-10658.62, y=996.85, z=32.87} } -- Bowyer
}

local db_goods = {}

-- Food/Drinks
db_goods[1429] = { -- Elwyn Forest
    { id=152, coord={x=-8901.58, y=-112.71, z=81.84}, lvl=1 }, -- Northshire, Brother Danil only has lvl 1 food ;_;
    { id=465, coord={x=-9459.97, y=8.41, z=56.96}, lvl=45 }, -- Goldshire, Barkeep Dobbins
}
db_goods[1436] = { -- Westfall
    { id=1670, coord={x=-10653.26,y=995.39,z=32.87}, lvl=45 }, -- ONLY FOOD!? Sentinel Hill
}

GWB.goods = db_goods
GWB.repairs = db_repair
-- TODO: use OM and check for? GetObjectFlags? UnitCreatureTypeId("target")

local function IsSpellLearned(spellID)
    if IsPlayerSpell then
        return IsPlayerSpell(spellID)
    elseif IsSpellKnown then
        return IsSpellKnown(spellID)
    else
        -- ultra fallback: assume not learned if API missing
        return false
    end
end

-- TODO: improve?
local function AvgSpellCostCopper(lvlReq)
    -- quadratic fit to (8->200c) and (60->54000c)
    local cost = 16.826923 * (lvlReq * lvlReq) - 109.615385 * lvlReq

    if cost < 50 then cost = 50 end -- minimum 50c "travel/rounding" floor
    return math.floor(cost + 0.5)
end
-- trainersList = array of {spellID, lvlReq}
-- myLvl = UnitLevel("player")
-- moneySafetyX = e.g. 1.2 means "need 20% extra money"
local function ShouldTrain(trainersList, myLvl, moneySafetyX)
    moneySafetyX = moneySafetyX or 1.0

    local toLearn = {}
    local totalEstCost = 0

    for _, entry in ipairs(trainersList) do
        local spellID = entry[1]
        local lvlReq  = entry[2]

        if myLvl >= lvlReq and not IsSpellLearned(spellID) then
            local est = AvgSpellCostCopper(lvlReq)
            totalEstCost = totalEstCost + est
            table.insert(toLearn, {spellID = spellID, lvlReq = lvlReq, estCost = est})
        end
    end

    local money = GetMoney() or 0
    local needed = math.floor(totalEstCost * moneySafetyX + 0.5)

    local canAfford = money >= needed
    local hasAnythingToLearn = #toLearn > 0

    return hasAnythingToLearn and canAfford, toLearn, totalEstCost, needed, money
end



local function _findClosestTrainerForLevel(trainers, myLvl, px, py, pz)
    local bestTrainer = nil
    local bestDistSq = math.huge  -- use squared distance to avoid sqrt cost

    for _, t in ipairs(trainers) do
        if t.lvl >= myLvl then
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

local function FindNearbyVendorNPC(type)
    --[[
    local mapId = select(8, GetInstanceInfo())
    local mapId = C_Map.GetBestMapForUnit("player")
    local info = C_Map.GetMapInfo(mapId)
    ]]
    local mapId = C_Map.GetBestMapForUnit("player")
    
    local info = nil 
    
    if type == "repair" then
        info = db_repair[mapId]
    elseif type == "goods" then
        info = db_goods[mapId]
    --[[else
        GWB:Debug("Error, no NPCs for type:", type)
        return ]]
    end

    -- check if we own it?
    if info == nil then 
        GWB:Debug("ERROR no data on MapId:", mapId)
        return 
    end

    local points = {}
    for i=1, #info do
        points[i] = info[i].coord
    end

    GWB.Mover:Update()
    local x, y, z = GWB.Mover:GetPlayerPosition()
    local ref = {x=x, y=y, z=z}
    local bestTarget, idx, distSqr = GWB:ClosestPoint(ref, points)

    if bestTarget == nil then return nil end

    print("bestTarget:", bestTarget.x, bestTarget.y, bestTarget.z, ", distSqr:", distSqr, idx)
    --_G.info = info
    return info[idx]
end

local function FindNearbyRepairNPC()
    return FindNearbyVendorNPC("repair")
end
local function FindNearbyGoodsNPC()
    return FindNearbyVendorNPC("goods")
end
local function FindNearbyVendorNPC()
    -- check repair and/or goods?
    return FindNearbyVendorNPC("repair")
end
local function FindNearbyClassTrainerNPC()
    local mapId = C_Map.GetBestMapForUnit("player")
    return GetNearbyClassTrainer(mapId)
    -- /dump GWB.DB.classic.trainers["ROGUE"][1453]
end
-- slots that can have durability in Classic
local DURABILITY_SLOTS = {
    "HeadSlot", "ShoulderSlot", "ChestSlot", "WristSlot", "HandsSlot",
    "WaistSlot", "LegsSlot", "FeetSlot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot"
}

-- Fallback map for retail where GetInventorySlotInfo may reject string names
local SLOT_NAME_TO_ID = {
    HeadSlot = 1, ShoulderSlot = 3, ChestSlot = 5, WristSlot = 9,
    HandsSlot = 10, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8,
    MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18,
}

local function SafeGetSlotId(slotName)
    local ok, slotId = pcall(GetInventorySlotInfo, slotName)
    if ok and slotId then return slotId end
    return SLOT_NAME_TO_ID[slotName]
end

local function CalcualteAvrgArmorDurability()
    local totalCur, totalMax = 0, 0
    local lowestPct, lowestSlot = 101, nil

    for _, slotName in ipairs(DURABILITY_SLOTS) do
        local slotId = SafeGetSlotId(slotName)
        if slotId then
            local cur, max = GetInventoryItemDurability(slotId)
            if cur and max and max > 0 then
                totalCur = totalCur + cur
                totalMax = totalMax + max

                local pct = (cur / max) * 100
                if pct < lowestPct then
                    lowestPct = pct
                    lowestSlot = slotName
                end
            end
        end
    end
    local avgPct = (totalMax > 0) and (totalCur / totalMax) * 100 or 100
    
    --print(avgPct, lowestPct, lowestSlot)
    return avgPct, lowestPct
end

local function IsRepairFinished()
    if repairAttemptCount > 10 then return true end


    local repairAfter = plugin.settings.town_repair_at_percent.value -- / 100
    local avgPct, lowestPct = CalcualteAvrgArmorDurability()
    return lowestPct >= repairAfter
end
local function IsRepairNeeded()
    -- just block repair until reload?
    if repairAttemptCount > 10 then return false end

    local tick = GetTime()
    if blacklistRepairUntil > tick then return false end

    local repairAfter = plugin.settings.town_repair_at_percent.value -- / 100
    local avgPct, lowestPct = CalcualteAvrgArmorDurability()
    return lowestPct < repairAfter
end

local lastVendorSaleTime = 0
local function IsVendorFinished()
    --print("#sellQueue", 0, "slots", GWB.Inv:GetTotalFreeBagSlots())
    if #sellQueue == 0 and GetTime() > lastVendorSaleTime + 2.0 then
        return GWB.Inv:GetTotalFreeBagSlots() >= 2
    end
    return false
end
local function IsVendorNeeded()
    if blacklistRepairUntil > GetTime() then return false end
    if GetTime() < lastVendorSaleTime + 2.0 then return true end
    return GWB.Inv:GetTotalFreeBagSlots() < 2
end

local function IsClassTrainerNeeded()
    local tick = GetTime()

    -- are we blacklisted?
    if blacklistClassTrainerUntil > tick then return false end

    local myLvl = UnitLevel("player")
    local myClass = select(2, UnitClass("player"))
    local list  = GWB.DB.classic.trainer_info[myClass]
    if not list then return false end

    local ok, spells, estTotal, needed, money = ShouldTrain(list, myLvl, 1.15)

    if ok then
        --[[GWB:Print(("Go train! %d spells, est cost %dc (need %dc, have %dc)")
            :format(#spells, estTotal, needed, money))]]
        return true
    else
        --[[
        if #spells == 0 then
            GWB:Print("Nothing new to train.")
        else
            GWB:Print(("Not enough money. Est %dc (need %dc), have %dc.")
                :format(estTotal, needed, money))
        end
        ]]
    end
    return false
end
local function IsClassTrainerFinished()
    if not IsClassTrainerNeeded() then return true end
    return false
end
-- test
GWB.IsClassTrainerNeeded = IsClassTrainerNeeded

local function GetItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end
-- NOTE: this BuildMerchantItemIDSet only works while Merchant page is open!
local function BuildMerchantItemIDSet()
    local set = {}
    local n = GetMerchantNumItems()
    for i = 1, n do
        local link = GetMerchantItemLink(i)
        local id = GetItemIDFromLink(link)
        if id then set[id] = true end
    end
    return set
end
-- NOTE: this is the FULL set of available food, so we can check if our bags are OK
local function GetAllIDsFromLevelTable(levelTable, onlyUpToPlayerLevel)
    local out = {}
    local seen = {}
    if type(levelTable) ~= "table" then return out end

    local playerLevel = UnitLevel("player")

    for reqLevel, idList in pairs(levelTable) do
        if type(idList) == "table" then
            if (not onlyUpToPlayerLevel) or (type(reqLevel) == "number" and reqLevel <= playerLevel) then
                for _, id in ipairs(idList) do
                    if not seen[id] then
                        seen[id] = true
                        out[#out + 1] = id
                    end
                end
            end
        end
    end

    return out
end

-- Build two lookup sets once (or reuse your earlier flatten helper)
local function BuildIDSetFromLevelTable(levelTable)
    local set = {}
    if type(levelTable) ~= "table" then return set end
    for _, idList in pairs(levelTable) do
        if type(idList) == "table" then
            for _, id in ipairs(idList) do
                set[id] = true
            end
        end
    end
    return set
end

-- Returns: hasAny, drinkCount, foodCount
local function HasAnyConsumables(drinksTable, foodTable)
    local drinkSet = BuildIDSetFromLevelTable(drinksTable)
    local foodSet  = BuildIDSetFromLevelTable(foodTable)

    local drinkCount, foodCount = 0, 0

    for bag = 0, NUM_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local c = info.stackCount or 1
                if drinkSet[info.itemID] then
                    drinkCount = drinkCount + c
                elseif foodSet[info.itemID] then
                    foodCount = foodCount + c
                end
            end
        end
    end

    return (drinkCount + foodCount) > 0, drinkCount, foodCount
end

-- returns:
--   chosenKey (number or nil)
--   chosenList (table of ids, or empty)
local function GetBestAvailableTier(levelTable, merchantSet)
    if type(levelTable) ~= "table" then
        return nil, {}
    end

    local playerLevel = UnitLevel("player")
    local bestKey, bestList = nil, {}

    for reqLevel, idList in pairs(levelTable) do
        if type(reqLevel) == "number"
           and reqLevel <= playerLevel
           and type(idList) == "table" then

            -- does this tier have ANY item the vendor sells?
            local anySoldHere = false
            for _, id in ipairs(idList) do
                if merchantSet[id] then
                    anySoldHere = true
                    break
                end
            end

            if anySoldHere and (not bestKey or reqLevel > bestKey) then
                bestKey = reqLevel
                bestList = idList
            end
        end
    end

    if not bestKey then
        return nil, {}
    end

    return bestKey, bestList
end
local function MakeIDSet(idList)
    local set = {}
    for _, id in ipairs(idList or {}) do
        set[id] = true
    end
    return set
end
local function AutoBuyFromVendor(idSet, desiredCount)
    print("AutoBuyFromVendor", idSet)
    desiredCount = desiredCount or 20
    local bought = 0
    local numItems = GetMerchantNumItems()

    for i = 1, numItems do
        local id = GetItemIDFromLink(GetMerchantItemLink(i))
        print("id", id, "at", i)
        if id and idSet[id] then
            print("I want", id)
            local name, texture, price, quantity, numAvailable, isUsable, extendedCost =
                GetMerchantItemInfo(i)

            --[[if not extendedCost and price and price > 0
               and (numAvailable == -1 or numAvailable > 0) then]]

                local perPurchase = quantity or 1
                local remaining = desiredCount - bought
                if remaining <= 0 then break end

                local times = math.ceil(remaining / perPurchase)
                print("Buymerchant", i, times)
                BuyMerchantItem(i, times)
                bought = bought + (times * perPurchase)
            --end
        end
    end

    return bought
end


local function CountItemsFromList(idList)
    local total = 0
    if type(idList) ~= "table" then print("FFF") return 0 end

    -- make lookup set for fast membership
    local set = {}
    _G.set = set
    for _, id in ipairs(idList) do set[id] = true end

    for bag = 0, NUM_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            --print(info.itemID, info.stackCount)
            if info and info.itemID and set[info.itemID] then
                total = total + (info.stackCount or 1)
            end
        end
    end

    return total
end

-- this checks for the BEST goods!
local function CanAffordConsumables()
    -- NOTE: one stack is like 25 copper, 
    if GetMoney() < 25 + (UnitLevel("player") * 10) then
    -- hacky guess to see if we "poor", if so, leave vendor ;_;
        return false
    end
    return true
end
local function IsGoodsFinished()
    local DESIRED_DRINK = plugin.settings.town_buy_drink_count.value
    local DESIRED_FOOD = plugin.settings.town_buy_food_count.value
    --print("food_", DESIRED_FOOD, "drink_", DESIRED_DRINK)

    local drinkOk = true
    local foodOk = true

    local drinks = GWB.DB.classic.drinks
    local foods = GWB.DB.classic.food_normal
    local _, drinkCount, foodCount = HasAnyConsumables(drinks, foods)

    --print("isfinish dc", drinkCount, "/", DESIRED_DRINK, ", fc", foodCount, "/", DESIRED_FOOD)


    if DESIRED_DRINK ~= 0 then
        if drinkCount >= DESIRED_DRINK then
            drinkOk = true
        else
            drinkOk = false
        end
    end

    if DESIRED_FOOD ~= 0 then
        if foodCount >= DESIRED_FOOD then
            foodOk = true
        else
            foodOk = false
        end
    end

    local missingFood = DESIRED_FOOD - foodCount;
    if missingFood < 0 then missingFood = 0 end
    local missingDrink = DESIRED_DRINK - drinkCount
    if missingDrink < 0 then missingDrink = 0 end
    local totalMissing = missingFood - missingDrink
    
    -- TODO: calc food tier prices??
    if not CanAffordConsumables() then 
        GWB:Debug("Cannot afford consumables, skipping goods.")
        return true 
    end 

    
    --print('drinkOk', drinkOk, 'foodOk', foodOk)
    if drinkOk and foodOk then return true end
    return false
end
-- this checks for ANY goods!
local function IsGoodsNeeded()
    -- no gold means inf stuck at vendor ;_;
    if not CanAffordConsumables() then return false end

    local tick = GetTime()

    -- are we blacklisted?
    if blacklistGoodsUntil > tick then return false end

    local DESIRED_DRINK = plugin.settings.town_buy_drink_count.value
    local DESIRED_FOOD = plugin.settings.town_buy_food_count.value

    local drinks = GWB.DB.classic.drinks
    local foods = GWB.DB.classic.food_normal
    local _, drinkCount, foodCount = HasAnyConsumables(drinks, foods)

    --print("dc", drinkCount, "/", DESIRED_DRINK, ", fc", foodCount, "/", DESIRED_FOOD)

    -- the moment we are out of any, we need to get more
    if DESIRED_DRINK ~= 0 and drinkCount == 0 then
        return true
    end

    if DESIRED_FOOD ~= 0 and foodCount == 0 then
        return true
    end

    return false
end
--GWB.IsGoodsNeeded = IsGoodsNeeded
--GWB.IsGoodsFinished = IsGoodsFinished


plugin.handlers.NeedTown = function()
    return 
        IsRepairNeeded() or 
        IsVendorNeeded() or 
        IsGoodsNeeded() or
        IsClassTrainerNeeded()
end
--GWB.IsRepairFinished = IsRepairFinished

-- weak-key cache so tables can be GC'd if replaced
local _blacklistCache = setmetatable({}, { __mode = "k" })

local function ParseBlacklistTable(arg1)
    if type(arg1) ~= "table" then return {} end

    -- return cached set if we already built it for this table
    local cached = _blacklistCache[arg1]
    if cached then return cached end

    local set = {}

    -- arg1 looks like:
    -- arg1[1]  = { 5350, 159 }
    -- arg1[5]  = { 1179 }
    -- etc.
    for _, list in pairs(arg1) do
        if type(list) == "table" then
            for _, id in ipairs(list) do
                set[id] = true
            end
        end
    end

    _blacklistCache[arg1] = set
    return set
end
function IsVendorItemBlacklisted(itemID, arg1)
    if not itemID then return false end
    local set = ParseBlacklistTable(arg1)
    return set[itemID] == true
end

local function ShouldVendor(itemID, quality)
    -- exclude food/drink ofc!
    if IsVendorItemBlacklisted(itemID, GWB.DB.classic.drinks) then return false end
    if IsVendorItemBlacklisted(itemID, GWB.DB.classic.food) then return false end

    -- Always sell poor (grey) items regardless of if we looted them
    if quality == 0 then return true end
    
    -- Prevent selling Uncommon (Green) or higher quality items
    if quality >= 2 then return false end

    -- Protect gathering tools
    local protectedTools = {
        [2901] = true, -- Mining Pick
        [7005] = true, -- Skinning Knife
        [5956] = true, -- Blacksmith Hammer
    }
    if protectedTools[itemID] then return false end

    -- Prevent selling valuable auction house items
    local itemName, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(itemID)
    if classID then
        if classID == 7 then return false end -- Trade Goods (Herbs, Ore, Cloth, Skins, etc.)
        if classID == 9 then return false end -- Recipes
        if classID == 12 then return false end -- Quest items!
    end

    local count = GWB.Inv.currentItems[tostring(itemID)]
    if count == nil then return false end
    return true -- Sell all of it if it was collected by us
end

local function EnqueueVendorItems()
    wipe(sellQueue)

    for bag = 0, NUM_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked then
                if ShouldVendor(info.itemID, info.quality) then
                    sellQueue[#sellQueue + 1] = {bag = bag, slot = slot, count = info.stackCount or 1}
                end
            end
        end
    end
end

local function ProcessSellQueue()
    --print("ProcessSellQ")
    if not MerchantFrame or not MerchantFrame:IsShown() then
        if sellTicker then sellTicker:Cancel() sellTicker = nil end
        return
    end

    --print("ProcessSellQ 2")
    local entry = table.remove(sellQueue, 1)
    if not entry then
        if sellTicker then sellTicker:Cancel() sellTicker = nil end
        return
    end

    --print("ProcessSellQ 3")

    -- This sells to the merchant when their window is open
    C_Container.UseContainerItem(entry.bag, entry.slot)
    lastVendorSaleTime = GetTime()
end

local function _trigger_repair_btn()
    if not merchantOpened then return end

    local tick = GetTime()

    if lastRepairAttempt+0.825 > tick then return end

    repairAttemptCount = repairAttemptCount + 1

    Unlock(MerchantRepairAllButton.Click, MerchantRepairAllButton) 
    lastRepairAttempt = GetTime()
end

plugin.callbacks.OnMerchantShow = function(ctx)
    merchantOpened = true
    repairAttemptCount = 0 -- reset when open?
    vendorAttemptCount = 0

    -- start selling?
    --if IsRepairNeeded() then
    if not IsRepairFinished() then
        -- repair?
        if _G.MerchantRepairAllButton ~= nil then
            lastRepairAttempt = GetTime()
            UpdateLastHardwareAction()
            
            C_Timer.After(1, _trigger_repair_btn)
        end
    end

    --if IsVendorNeeded() then
    if not IsVendorFinished() then
        -- MAKE IT RAIN
        print("MAKE IT RAIN")
        EnqueueVendorItems()
        if #sellQueue > 0 and not sellTicker then
            -- sell 1 item stack per 0.1s (safe throttle)
            sellTicker = C_Timer.NewTicker(0.1, ProcessSellQueue)
        end

    end

    return
end

local function ExpandAllTrainerHeaders()
    local num = GetNumTrainerServices()
    for i = 1, num do
        local _, _, _, expanded, serviceType = GetTrainerServiceInfo(i)
        if serviceType == "header" and not expanded then
            -- toggles expansion
            SelectTrainerService(i)
        end
    end
end
local function DumpTrainerServices()
    if not ClassTrainerFrame or not ClassTrainerFrame:IsShown() then
        print("Trainer window not open.")
        return
    end

    local num = GetNumTrainerServices()
    print("Trainer services:", num)

    for i = 1, num do
        local name, subText, category, expanded, serviceType,
              isLearned, isAvailable, spellID = GetTrainerServiceInfo(i)

        local reqLevel = GetTrainerServiceLevelReq(i)
        local cost     = GetTrainerServiceCost(i)  -- copper

        -- serviceType: "available", "unavailable", "used", "header"
        -- category/subText often empty on Classic but still returned.

        print(("%02d) %s | spellID=%s | reqLvl=%s | cost=%dc | type=%s | learned=%s | available=%s")
            :format(
                i,
                name or "<?>",
                spellID or "nil",
                reqLevel or "nil",
                cost or 0,
                serviceType or "nil",
                tostring(isLearned),
                tostring(isAvailable)
            )
        )
    end
end

local function ApproachOrInteractTownNPC(npcInfo)
    if not npcInfo then return end

    if not GWB.TownBlacklist then GWB.TownBlacklist = {} end
    if GWB.TownBlacklist[npcInfo.id] and GetTime() < GWB.TownBlacklist[npcInfo.id] then
        -- Force re-eval of target if blacklisted
        if nearbyTrainer and nearbyTrainer.id == npcInfo.id then nearbyTrainer = nil end
        if nearbyRepair and nearbyRepair.id == npcInfo.id then nearbyRepair = nil end
        if nearbyVendor and nearbyVendor.id == npcInfo.id then nearbyVendor = nil end
        return
    end

    -- If the actual NPC is visible in the Object Manager, navigate to/interact with it directly!
    local npcs = GWB.OM:FindNPCsById(npcInfo.id)
    if npcs and #npcs > 0 then
        if not npcInfo.firstSeenTime then npcInfo.firstSeenTime = GetTime() end
        if GetTime() - npcInfo.firstSeenTime > 45 then
            GWB:Print("Failed to reach NPC " .. npcInfo.id .. " for 45s (path blocked?). Blacklisting.")
            GWB.TownBlacklist[npcInfo.id] = GetTime() + 1800 -- 30 mins
            npcInfo.firstSeenTime = nil
            if nearbyTrainer and nearbyTrainer.id == npcInfo.id then nearbyTrainer = nil end
            if nearbyRepair and nearbyRepair.id == npcInfo.id then nearbyRepair = nil end
            if nearbyVendor and nearbyVendor.id == npcInfo.id then nearbyVendor = nil end
            return
        end

        GWB.Utils:InteractOrApproach(npcs[1], function(obj)
            npcInfo.firstSeenTime = nil -- Success
            ObjectInteract(obj)
        end, 4.5)
        return
    else
        npcInfo.firstSeenTime = nil -- reset if we lost sight
    end

    -- Otherwise, navigate to the town marker coordinate
    local coord = npcInfo.coord
    local px, py, pz = ObjectPosition("player")
    local dist = 9999
    if px then
        dist = math.sqrt((coord.x-px)^2 + (coord.y-py)^2 + (coord.z-pz)^2)
    end
    
    if dist >= 4.5 then
        npcInfo.arrivalWaitTime = nil
        GWB.Mover:MoveToXYZ(coord.x, coord.y, coord.z)
    else
        if not npcInfo.arrivalWaitTime then npcInfo.arrivalWaitTime = GetTime() end
        if GetTime() - npcInfo.arrivalWaitTime > 15 then
            GWB:Print("Reached DB coordinates but NPC " .. npcInfo.id .. " is missing! Blacklisting.")
            GWB.TownBlacklist[npcInfo.id] = GetTime() + 1800 -- 30 mins
            npcInfo.arrivalWaitTime = nil
            if nearbyTrainer and nearbyTrainer.id == npcInfo.id then nearbyTrainer = nil end
            if nearbyRepair and nearbyRepair.id == npcInfo.id then nearbyRepair = nil end
            if nearbyVendor and nearbyVendor.id == npcInfo.id then nearbyVendor = nil end
            return
        end
    end
end


local function tick_repair()
    -- in case window is alrdy open, we try to repair
    _trigger_repair_btn()
    if repairAttemptCount > 10 then
        -- fail to repair? just skip it ;_;
        GWB:Print("Failed to Repair, skipping!!!")
    end

    local tick = GetTime()
    if lastRepairUpdate+5 < tick then
        if nearbyRepair == nil then
            nearbyRepair = FindNearbyRepairNPC()
            print("updated nearbyRepair")
        end
        lastRepairUpdate = tick

        if nearbyRepair then
            ApproachOrInteractTownNPC(nearbyRepair)
        end
    end

    if nearbyRepair == nil then
        -- If we are on cooldown from lastRepairUpdate, we shouldn't return true (fail).
        -- Returning true causes stateTick to mark it as checked and pop the state!
        -- Only return true if we ACTUALLY failed to find a vendor when the cooldown allowed us to search.
        if lastRepairUpdate+5 < tick then 
            return true 
        else
            return false -- wait for cooldown
        end
    end

    return false
end
local function tick_vendor()
    local tick = GetTime()
    if lastRepairUpdate+5 < tick then
        if nearbyRepair == nil then
            nearbyRepair = FindNearbyRepairNPC()
            if nearbyRepair == nil then
                GWB:Print("Error, not Repair NPC found in this map!")
                blacklistRepairUntil = tick + (60 * 45) -- 45 min only?
                return true
            end
            print("updated nearbyRepair for vendor")
        end
        lastRepairUpdate = tick

        -- move to it?
        ApproachOrInteractTownNPC(nearbyRepair)
    end

    if nearbyRepair == nil then
        if lastRepairUpdate+5 < tick then return true else return false end
    end

    return false
end

local lastBuyTick = 0
local function tick_goods()
    -- move to Goods??
    local tick = GetTime()
    if lastRepairUpdate+5 < tick then
        if nearbyGoods == nil then
            nearbyGoods = FindNearbyGoodsNPC()
            if nearbyGoods == nil then
                GWB:Print("Failed finding goods NPC!")
                blacklistGoodsUntil = tick + (60 * 60 * 1) --1h timeout
                return true -- eh?
            end
            print("updated nearbyGoods")
        end
        lastRepairUpdate = tick

        -- move to it?
        ApproachOrInteractTownNPC(nearbyGoods)
    end

    -- we good?
    if IsGoodsFinished() then return true end

    if nearbyGoods == nil then
        if lastRepairUpdate+5 < tick then return true else return false end
    end

    if merchantOpened then
        -- Humanize interaction delay (0.8s - 2.5s)
        local interactionDelay = math.random(8, 25) / 10.0
        if not IsGoodsFinished() and lastBuyTick + interactionDelay < tick then
            lastBuyTick = tick
            -- Get that dough!
            print("Getting that dough!")
            local DESIRED_DRINK = plugin.settings.town_buy_drink_count.value
            local DESIRED_FOOD = plugin.settings.town_buy_food_count.value
            
            local merchantSet = BuildMerchantItemIDSet()
            
            local drinks = GWB.DB.classic.drinks
            local foods = GWB.DB.classic.food_normal

            local drinkTier, drinkIDs = GetBestAvailableTier(drinks, merchantSet)
            local foodTier,  foodIDs  = GetBestAvailableTier(foods, merchantSet)
            
            local _, drinkCount, foodCount = HasAnyConsumables(drinks, foods)

            print(foodTier, foodCount, DESIRED_FOOD)
            if drinkTier then
                if drinkCount < DESIRED_DRINK then
                    GWB:Debug("Buying drinks tier", drinkTier)
                    AutoBuyFromVendor(MakeIDSet(drinkIDs), DESIRED_DRINK)
                end
            else
                blacklistGoodsUntil = GetTime() + (30 * 60) -- 30 min timeout?
                GWB:Print("No drinks available at this vendor!1!!")
                return true
            end

            if foodTier then
                if foodCount < DESIRED_FOOD then
                    GWB:Debug("Buying food tier", foodTier)
                    AutoBuyFromVendor(MakeIDSet(foodIDs), DESIRED_FOOD)
                end
            else
                blacklistGoodsUntil = GetTime() + (30 * 60) -- 30 min timeout?
                GWB:Print("No food available at this vendor!!!")
                return true
            end
        end
    end

    return false
end
local BuildTrainerQueueFromSpells

local function tick_trainer()
    --print('tick_trainer')

    -- move to Trainer??
    local tick = GetTime()
    if lastRepairUpdate+5 < tick then
        if nearbyTrainer == nil then
            nearbyTrainer = FindNearbyClassTrainerNPC()
            if nearbyTrainer == nil then
                GWB:Print("Failed finding class trainer!")
                blacklistClassTrainerUntil = tick + (60 * 60 * 2) -- 2h?
                return true
            end
            print("updated nearbyTrainer")
        end
        lastRepairUpdate = tick

        -- move to it?
        ApproachOrInteractTownNPC(nearbyTrainer)
    end

    -- we good?
    if IsClassTrainerFinished() then return true end

    if trainerOpened then
        -- Humanize trainer interaction delay (0.8s - 2.5s)
        local interactionDelay = math.random(8, 25) / 10.0
        if lastBuyTick + interactionDelay < tick then
            lastBuyTick = tick
            
            local myLvl = UnitLevel("player")
            local myClass = select(2, UnitClass("player"))
            local list = GWB.DB.classic.trainer_info[myClass]
            if list then
                local ok, spells = ShouldTrain(list, myLvl, 1.0)
                if spells and #spells > 0 then
                    local queue = BuildTrainerQueueFromSpells(spells)
                    if queue and #queue > 0 then
                        local firstSpell = queue[1]
                        GWB:Print("Training spell:", firstSpell.name, "at index:", firstSpell.index)
                        if Unlock then
                            Unlock(BuyTrainerService, firstSpell.index)
                        else
                            BuyTrainerService(firstSpell.index)
                        end
                    end
                end
            end
        end
    end

    if nearbyTrainer == nil then
        if lastRepairUpdate+5 < tick then return true else return false end
    end

    return false
end

-- we need to maintain state here, and let know if we are "done" or
-- are still doing shit in the town.
plugin.handlers.stateTick = function()
    -- check if we want repair and if it was done
    local repairChecked = false
    local repairNeeded = IsRepairNeeded()
    local repairDone = IsRepairFinished()

    if not repairNeeded then
        repairChecked = true 
    elseif repairDone then
        repairChecked = true
    else
        repairChecked = false
    end

    local vendorChecked = false
    local vendorNeeded = IsVendorNeeded()
    local vendorDone = IsVendorFinished()

    if not vendorNeeded then
        vendorChecked = true
    elseif vendorDone then
        vendorChecked = true
    else
        vendorChecked = false
    end

    local goodsChecked = false
    local goodsNeeded = IsGoodsNeeded()
    local goodsDone = IsGoodsFinished()

    if not goodsNeeded then
        goodsChecked = true
    elseif goodsDone then
        goodsChecked = true
    else
        goodsChecked = false
    end

    local trainerChecked = false
    local trainerNeeded = IsClassTrainerNeeded()
    local trainerDone = IsClassTrainerFinished()

    if not trainerNeeded then
        trainerChecked = true
    elseif trainerDone then
        trainerChecked = true
    else
        trainerChecked = false
    end

    local currentStep = nil
    if not repairChecked then currentStep = "repair"
    elseif not vendorChecked then currentStep = "vendor"
    elseif not goodsChecked then currentStep = "goods"
    elseif not trainerChecked then currentStep = "trainer"
    end

    if lastStep ~= currentStep then
        nearbyRepair = nil
        nearbyGoods = nil
        nearbyTrainer = nil
        lastStep = currentStep
    end

    --print("repairNeeded:", repairNeeded, ", repairDone:", repairDonem, ", repairChecked: ", repairChecked)
 
    --if repairChecked then
    --    return true -- true means we "resume" to the "previous" state
    if not repairChecked then
        if not tick_repair() then
            return -- wait for it to update state from above, or to just fail?
        else
            repairChecked = true -- we failed, just continue
        end
    end

    -- check vendor
    local vendorChecked = false
    local vendorNeeded = IsVendorNeeded()
    local vendorDone = IsVendorFinished()

    if not vendorNeeded then
        vendorChecked = true
    elseif vendorDone then
        vendorChecked = true
    else
        vendorChecked = false
    end

    if not vendorChecked then
        if not tick_vendor() then
            return
        else
            vendorChecked = true
        end
    end

    -- check Goods
    -- check vendor
    local goodsChecked = false
    local goodsNeeded = IsGoodsNeeded()
    local goodsDone = IsGoodsFinished()

    if not goodsNeeded then
        goodsChecked = true
    elseif goodsDone then
        goodsChecked = true
    else
        goodsChecked = false
    end

    if not goodsChecked then
        if not tick_goods() then
            return
        else
            goodsChecked = true
        end
    end

    -- check Class Trainer
    local trainerChecked = false
    local trainerNeeded = IsClassTrainerNeeded()
    local trainerDone = IsClassTrainerFinished()

    if not trainerNeeded then
        trainerChecked = true
    elseif trainerDone then
        trainerChecked = true
    else
        trainerChecked = false
    end

    if not trainerChecked then
        if not tick_trainer() then
            return
        else
            trainerChecked = true
        end
    end

    --[[print(
        "repairChecked", repairChecked, 
        "vendorChecked", vendorChecked, 
        "goodsChecked", goodsChecked, 
        "trainerChecked", trainerChecked)]]

    if repairChecked and vendorChecked and goodsChecked and trainerChecked then
        -- NOTE: WE RETURN TO EARLY BEFORE IsGoodsFinished is statisfied!
        return true -- test
    end

    return false
end

local function test()

end


plugin.callbacks.OnMerchantClosed = function(ctx)
    merchantOpened = false
    return
end
function BuildTrainerQueueFromSpells(spells)
    local queue = {}
    if not ClassTrainerFrame or not ClassTrainerFrame:IsShown() then
        return queue
    end

    -- map wanted spellIds -> their db info
    local wanted = {}
    for _, s in ipairs(spells) do
        if s.spellId then
            wanted[s.spellId] = s  -- keep lvlReq/estCost handy
        end
    end

    local num = GetNumTrainerServices()
    for i = 1, num do
        local name, _, _, _, serviceType, isLearned, isAvailable, spellID =
            GetTrainerServiceInfo(i)

        local dbEntry = spellID and wanted[spellID]
        if dbEntry then
            if serviceType == "available" and not isLearned and isAvailable then
                table.insert(queue, {
                    index   = i,
                    spellID = spellID,
                    name    = name,
                    cost    = GetTrainerServiceCost(i),
                    reqLvl  = GetTrainerServiceLevelReq(i),

                    -- from your DB / estimator
                    dbLvlReq  = dbEntry.lvlReq,
                    estCost   = dbEntry.estCost,
                })
            end
        end
    end

    -- sort by your intended order: lowest lvlReq first, then cheapest
    table.sort(queue, function(a, b)
        local la = a.dbLvlReq or a.reqLvl or 0
        local lb = b.dbLvlReq or b.reqLvl or 0
        if la == lb then
            return (a.cost or 0) < (b.cost or 0)
        end
        return la < lb
    end)

    return queue
end

plugin.callbacks.OnTrainerShow = function(ctx)
    trainerOpened = true

    C_Timer.After(0.5, function()
        ExpandAllTrainerHeaders()
    end)

    C_Timer.After(1.5, function()
        local myLvl = UnitLevel("player")
        local myClass = select(2, UnitClass("player"))
        local list  = GWB.DB.classic.trainer_info[myClass]
        if not list then
            GWB:Print("No trainer info for class: " .. myClass)
            blacklistClassTrainerUntil = GetTime() + (60*60*2)
            return
        end

        local ok, spells, estTotal, needed, money = ShouldTrain(list, myLvl, 1.15)

        if not spells or #spells == 0 then
            print("GWB: Nothing new to train.")
            blacklistClassTrainerUntil = GetTime() + (60*60*2) -- 2h
            return
        end

        if not ok then
            print(("GWB: Too expensive right now. Est %dc (need %dc), have %dc.")
                :format(estTotal, needed, money))
            blacklistClassTrainerUntil = GetTime() + (60*60*2) -- 2h
            return
        end

        local queue = BuildTrainerQueueFromSpells(spells)

        if #queue == 0 then
            print("GWB: Trainer has none of your needed spells available.")
            blacklistClassTrainerUntil = GetTime() + (60*60*2) -- 2h
            return
        end

        print(("GWB: %d spells ready to train:"):format(#queue))
        for n, t in ipairs(queue) do
            print(("%d) %s (id=%d, reqLvl=%d, cost=%dc, est=%dc) -> click Train")
                :format(
                    n,
                    t.name or ("spell "..t.spellID),
                    t.spellID,
                    t.dbLvlReq or t.reqLvl or -1,
                    t.cost or 0,
                    t.estCost or 0
                ))
        end

        -- Select first one so Blizzard Train button is ready
        SelectTrainerService(queue[1].index)
        print("GWB: Selected first spell. Press Train.")

        GWB._trainQueue = queue
        GWB._trainQueuePos = 1
    end)
end



plugin.callbacks.OnGossipStart = function(ctx)
    -- check if this was from training??
    print("GOSSIP")
    local opts = C_GossipInfo.GetOptions()
    if not opts then return false end

    for _, opt in ipairs(opts) do
        -- opt.type can be "trainer", "vendor", "questgiver", etc.
        if opt.icon == 132058 --[[ spellbook icon ]] then
            --return true, opt.gossipOptionID, opt.name
            print("taking opt", opt.name)
            C_GossipInfo.SelectOption(opt.gossipOptionID)
        end
    end
    return false
end
plugin.callbacks.OnTrainerClosed = function(ctx)
    trainerOpened = false
end
plugin.callbacks.OnMovementFinished = function(ctx, type, tx, ty, tz)
    if type ~= "xyz" then return end

    local activeTarget = nil
    if lastStep == "repair" or lastStep == "vendor" then activeTarget = nearbyRepair
    elseif lastStep == "goods" then activeTarget = nearbyGoods
    elseif lastStep == "trainer" then activeTarget = nearbyTrainer end

    if activeTarget == nil or activeTarget.coord == nil then return end 

    -- check if us?
    local coord = activeTarget.coord
    
    if coord.x ~= tx or coord.y ~= ty or coord.z ~= tz then return end
    
    print("Mover finished walking to Town Target", activeTarget.id ," at ", tx, ty, tz)

    local npcs = GWB.OM:FindNPCsById(activeTarget.id)

    -- Use InteractOrApproach to ensure we are actually close enough
    for i=1, #npcs do
        GWB.Utils:InteractOrApproach(npcs[i], function(obj)
            ObjectInteract(obj)
        end, 4.5)
    end
    
    return
end
plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    if GWB.State:getCurrentState() == "plugin.TownHandler" then
        local avgPct, lowestPct, lowestSlot = GWB.Inv:GetAverageDurability()
        if avgPct < 10 or lowestPct < 5 then
            GWB:Print("TownHandler ignoring combat, fleeing to vendor!")
            return true -- suppress other handlers, keep moving
        end

        print("RETURN FROM TownHandler ???")
        GWB.State:returnState()
    end
end
plugin.callbacks.OnPlayerDeath = function(ctx)
    if GWB.State:getCurrentState() == "plugin.TownHandler" then
        print("RETURN FROM TownHandler ?")
        GWB.State:returnState()
    end
end


local function OnLoad()

end

GWB:RegisterPlugin(plugin)

OnLoad() -- maybe call this external??
