local Unlocker, GWB, inventory = ...

GWB.Inv = {}

-- Shit to make Wow API work on Retail
local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
local GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink or C_Container.GetContainerItemLink
local GetContainerItemInfo = GetContainerItemInfo or C_Container.GetContainerItemInfo
local UseContainerItem = UseContainerItem or C_Container.UseContainerItem
local GetContainerItemCooldown = GetContainerItemCooldown or C_Container.GetContainerItemCooldown

-- TODO: figure out level, parse inventory and get best food?
function GWB.Inv:FindUsableDrink()
    return {}
end
function GWB.Inv:FindUsableFood() 
    return {}
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
    local _, bag, slot = GWB.Inv:FindItemInBags(itemId)
    
    if bag == nil then return false end

    local _, _, cooldown = GetContainerItemCooldown(bag, slot)
    return coodlown == false
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
LootLog = {}
 
local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE") -- TODO; callback?

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

                    --if collectedList[itemID] == nil or newCollected ~= collectedList[itemID] then
                    if collectedList[itemID] == nil or newCollected ~= collectedList[itemID] then
                        print("set ", tostring(newCollected) .. " for ", item)
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
