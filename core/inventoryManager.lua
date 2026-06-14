local Unlocker, GWB, inventory = ...

GWB.Inv = {}

-- Shit to make Wow API work on Retail
local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
local GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink or C_Container.GetContainerItemLink
local GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
local UseContainerItem = UseContainerItem or C_Container.UseContainerItem
local GetContainerItemCooldown = GetContainerItemCooldown or C_Container.GetContainerItemCooldown

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

function GWB.Inv:GetBestConsumable(consumables)
    local itemIds = GWB.Inv.currentItems
    if not itemIds or not consumables then return nil end

    local lvl = UnitLevel("player")
    if not lvl or lvl <= 0 then return nil end

    local maxReq = 0
    for reqLevel, _ in pairs(consumables) do
        if reqLevel > maxReq then maxReq = reqLevel end
    end
    
    local function GetCount(itemId)
        return itemIds[tostring(itemId)] or 0
    end
    
    for req = maxReq, 1, -1 do
        if req <= lvl then
            local foodsAtReq = consumables[req]
            if foodsAtReq then
                for j = 1, #foodsAtReq do
                    local itemId = foodsAtReq[j]
                    local count = GetCount(itemId)
                    if count > 0 then
                        local bag, slot = FindItemLocation(itemId)
                        if bag then
                            return itemId, bag, slot, req, count
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Helper function to scan bags and find the best food or drink based on tooltip parsing
function GWB.Inv:ScanBagsForBestConsumable(isDrink)
    local bestRestore = 0
    local bestBag, bestSlot, bestItemId = nil, nil, nil
    local playerLevel = UnitLevel("player") or 1

    for bag = 0, 4 do
        local numSlots = 0
        if C_Container and C_Container.GetContainerNumSlots then
            numSlots = C_Container.GetContainerNumSlots(bag)
        elseif GetContainerNumSlots then
            numSlots = GetContainerNumSlots(bag)
        end
        
        for slot = 1, numSlots do
            local itemId = nil
            if C_Container and C_Container.GetContainerItemID then
                itemId = C_Container.GetContainerItemID(bag, slot)
            elseif GetContainerItemID then
                itemId = GetContainerItemID(bag, slot)
            end
            if itemId then
                local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID = GetItemInfo(itemId)
                
                -- Check if player meets the level requirement
                if not itemMinLevel or playerLevel >= itemMinLevel then
                    local restoreAmount = 0
                    local isCorrectType = false
                    
                    -- Retail / Midnight API
                    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
                        local tooltipInfo = C_TooltipInfo.GetBagItem(bag, slot)
                        if tooltipInfo and tooltipInfo.lines then
                            for _, line in ipairs(tooltipInfo.lines) do
                                if line.leftText then
                                    local text = line.leftText
                                    if not isDrink then
                                        local amt = string.match(text, "Restores ([%d,]+) health.*over")
                                        if amt then
                                            amt = string.gsub(amt, ",", "")
                                            restoreAmount = tonumber(amt)
                                            isCorrectType = true
                                        end
                                    else
                                        local amt = string.match(text, "([%d,]+) mana.*over")
                                        if amt then
                                            amt = string.gsub(amt, ",", "")
                                            restoreAmount = tonumber(amt)
                                            isCorrectType = true
                                        end
                                    end
                                end
                            end
                        end
                    else
                        -- Classic / Era API Fallback
                        if not _G.GWB_HiddenTooltip then
                            local tt = CreateFrame("GameTooltip", "GWB_HiddenTooltip", nil, "GameTooltipTemplate")
                            tt:SetOwner(WorldFrame, "ANCHOR_NONE")
                        end
                        _G.GWB_HiddenTooltip:ClearLines()
                        _G.GWB_HiddenTooltip:SetBagItem(bag, slot)
                        
                        for i = 1, _G.GWB_HiddenTooltip:NumLines() do
                            local left = _G["GWB_HiddenTooltipTextLeft"..i]
                            if left then
                                local text = left:GetText()
                                if text then
                                    if not isDrink then
                                        local amt = string.match(text, "Restores ([%d,]+) health.*over")
                                        if amt then
                                            amt = string.gsub(amt, ",", "")
                                            restoreAmount = tonumber(amt)
                                            isCorrectType = true
                                        end
                                    else
                                        local amt = string.match(text, "([%d,]+) mana.*over")
                                        if amt then
                                            amt = string.gsub(amt, ",", "")
                                            restoreAmount = tonumber(amt)
                                            isCorrectType = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    if isCorrectType and restoreAmount > bestRestore then
                        bestRestore = restoreAmount
                        bestBag = bag
                        bestSlot = slot
                        bestItemId = itemId
                    end
                end
            end
        end
    end
    
    return bestItemId, bestBag, bestSlot
end

function GWB.Inv:FindUsableDrink()
    return GWB.Inv:ScanBagsForBestConsumable(true)
end

function GWB.Inv:FindUsableFood() 
    return GWB.Inv:ScanBagsForBestConsumable(false)
end

-- Function to search for a specific item in the player's bags
-- itemID is the ID of the item you are looking for
-- \return itemCount, bag, slot
function GWB.Inv:FindItemInBags(itemID)
   local itemCount = 0
   local firstBagFound = nil
   local firstSlotFound = nil
   
   -- Iterate through all bags (0 to 4 for the main backpack and additional bags)
   for bag = 0, 4 do
      -- Get the number of slots in the current bag
      local numSlots = GetContainerNumSlots(bag)
      
      -- Iterate through each slot in the current bag
      for slot = 1, numSlots do
         -- Get the item ID of the item in the current slot
         local itemLink = GetContainerItemLink(bag, slot)
         if itemLink then
            local foundItemID = GetItemInfoInstant(itemLink)
            
            -- Check if the found item ID matches the item we are looking for
            if foundItemID == itemID then
                if firstBagFound == nil then
                    firstBagFound = bag
                    firstSlotFound = slot
                end
                -- Get the number of items in the current slot
                local _, itemStackCount = GetContainerItemInfo(bag, slot)
                if  itemStackCount ~= nil then
                    itemCount = itemCount + itemStackCount
                end
            end
         end
      end
   end
   return itemCount, firstBagFound, firstSlotFound
end

-- more like, HasHearthstone available, but for all we care, CD HS equals no HS
function GWB.Inv:HasHearthstone()
    local itemId = 6948
    local toybox = { } -- TODO: also check for expac?
    local count, bag, slot = GWB.Inv:FindItemInBags(itemId)
    return bag ~= nil
end

local DURABILITY_SLOTS = {
    "HeadSlot", "ShoulderSlot", "ChestSlot", "WristSlot", "HandsSlot",
    "WaistSlot", "LegsSlot", "FeetSlot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot"
}
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

function GWB.Inv:GetAverageDurability()
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
    return avgPct, lowestPct, lowestSlot
end

function GWB.Inv:UseHearthstone()
    local itemId = 6948
    local toybox = { } -- TODO: also check for expac?
    local _, bag, slot = GWB.Inv:FindItemInBags(itemId)

    --print(bag, slot)
    if bag ~= nil and slot ~= nil then
        Unlock(UseContainerItem, bag, slot)
        return true
    end
    return false
end

function GWB.Inv.GetTotalFreeBagSlots()
    local free = 0
    for bag = 0, NUM_BAG_SLOTS do  -- 0 = backpack, 1-4 = equipped bags
        local numFree, bagType = C_Container.GetContainerNumFreeSlots(bag)
        free = free + (numFree or 0)
    end
    return free
end
-- TODO: add some sort of generic filtering?
-- Apply policy on what to find here, not high levels?

--[[
GWB.Inv:FindNextScrapableItem(incGems, incRares, incGreens)
    local gems = {}
    local rares = {}
    local greens = {}

    local ids = {}
    
    local _, bag, slot = GWB.Inv:FindItemInBags(itemId)
end]]
function GWB.Inv:FindNextScrapableItem()
    local scrapable = {}
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
            if C_Item.DoesItemExist(itemLoc) and C_Item.CanScrapItem(itemLoc) then
                --[[tinsert(scrapable, {
                    itemID = C_Item.GetItemID(itemLoc),
                    itemLink = C_Item.GetItemLink(itemLoc)
                })]]
                return bag, slot
            end
        end
    end
    return nil, nil
end

function GWB.Inv:Tick()
    return
end

-- TODO: Register events to keep track of loot?
GWB.Inv.LootLog = GWB.Inv.LootLog or {}
 
local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE")

GWB.Inv.currentItems = {}
GWB.Inv.isInitialized = false

-- NOTE: Be ware about negative 'collected'
-- TODO: track if items fully dissapear (stack 
-- decrease is counter, but not full stack)
function GWB.Inv:TickBagUpdate()
    --print("TickBagUpdate")
    local isInit = not GWB.Inv.isInitialized
    local needSave = false

    local collectedList = GWB.Storage.inventory.collectedItems  --GWB.Config.GWB.Inv.collectedItems;
    local currentList = GWB.Inv.currentItems

    local itemIDs = {}

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local item = GetContainerItemLink(bag, slot)

            -- NOTE: this only checks for new items!
            if item ~= nil then
                --local itemName = select(1, GetItemInfo(item)) -- 6, "Gem" (localized!), 12 for ID
                local itemID = tostring(select(1, GetItemInfoInstant(item)))
                table.insert(itemIDs, itemID)

                local count = GetItemCount(itemID)

                local collected = collectedList[itemID]
                -- collected can be negative if stuff is consumed, but just keep track of it?
                --if collected < 0 then
                --    collected = 0
                --end
                if collected == nil then
                    -- init the item to prevent nil
                    collected = 0
                    collectedList[itemID] = 0
                end
                local current = count - collected -- max inventory, minus the GWBted amount
                
                -- if init, we only need to update the 'currentList' as only 'collectList' is
                -- saved to disk (and not lost on /reload)
                if isInit then
                    
                    --print("init", item, current, " ---[", collected)
                    if collected ~= 0 then
                        print("Collected", tostring(collected) .. "x", item) --, "/", count) --, "    | ", count, "-", collected,"=", current)
                    end
                    currentList[itemID] = current
                    collectedList[itemID] = collected -- eh?
                else
                    -- now potential new items were added
                    local current = currentList[itemID]
                    if current == nil then
                        current = 0 -- lazy init or we fail to subtract!
                        currentList[itemID] = 0
                    end
                    local newCollected = count - current -- max inventory, minus the known ones
                    --print("new collected", newCollected, item, "   = ", count, "  - ", current)
                    -- NOTE; newCollected cold be negative too?

                    if collectedList[itemID] == nil or newCollected ~= collectedList[itemID] then
                        local diff = newCollected - (collectedList[itemID] or 0)
                        if diff > 0 then
                            print("Looted: ", tostring(diff) .. "x ", item)
                            table.insert(GWB.Inv.LootLog, { time = GetTime(), itemID = itemID, link = item, count = diff })
                            if GWB.FireCallback then
                                GWB:FireCallback("OnItemLooted", itemID, item, diff)
                            end
                        end
                        
                        collectedList[itemID] = newCollected
                        needSave = true
                    end
                end

            end
        end
    end

    -- now scan old items?
    -- TODO events? just parse all the known id's and check if they
    -- were skipped from the 'itemIDs' list? then, count them, and
    -- see if something has changed

    -- TODO?
    --GWB.Config.GWB.Inv.collectedItems = collectedList
    GWB.Inv.currentItems = currentList
    
    if GWB.Inv.isInitialized and needSave then
        --print("saving!")
        GWB.StorageMgr:SaveStorageToDisk()
    end

    if not GWB.Inv.isInitialized then
        GWB.Inv.isInitialized = true
    end

    
end

 
f:SetScript("OnEvent", GWB.Inv.TickBagUpdate)

function GWB.Inv:Initialize()

    -- can only be called if Config and ConfigManager etc are all initited
    GWB.Inv:TickBagUpdate() -- initial
end

GWB.Inv:Initialize()
