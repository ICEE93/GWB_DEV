local Nn, GWB = ...

local plugin = {}
plugin.name = "QuestHandler"
plugin.xpacs = "classic"
plugin.author = "Antigravity"

local cacheTickerName = plugin.name .. "_CacheTick"
local scanTickerName = plugin.name .. "_ScanTick"

-- Map of quest objectives we are looking for: string -> boolean
-- e.g. ["Boar Meat: 0/10"] = true
local activeObjectives = {}

-- The current object we are pursuing for a quest
GWB.QuestTarget = nil
local questTargetTimeout = 0

local SEARCH_RADIUS = 40.0

-- Caches the active quest objectives from the Quest Log
local function UpdateQuestCache()
    activeObjectives = {}
    
    local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for i = 1, numEntries do
        local title, level, questTag, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
        if title and not isHeader then
            local numObjectives = GetNumQuestLeaderBoards(i) or 0
            for j = 1, numObjectives do
                local text, objType, finished = GetQuestLogLeaderBoard(j, i)
                if text and not finished then
                    -- Store the raw text, typically like "Boar Meat: 2/10"
                    activeObjectives[text] = true
                end
            end
        end
    end
end

-- Make it accessible globally
GWB.QuestHandler = GWB.QuestHandler or {}
GWB.QuestHandler.IsQuestieObjectiveFast = function(obj)
    if not Questie or not QuestiePlayer or type(QuestiePlayer.currentQuestlog) ~= "table" then return false end
    
    local typeId = ObjectType(obj)
    local objId = ObjectId(obj)
    if typeId == 5 then objId = ObjectUnitId(obj) end
    if not objId then return false end
    
    local isAutopilot = GWB.Settings and GWB.Settings.QuestieAutopilot
    local activePinQuestId = nil
    
    if isAutopilot then
        if not (GWB.QuestHandler and GWB.QuestHandler.CurrentAutopilotPin) then
            if GWB.QuestHandler.GetNextQuestieWaypoint then
                GWB.QuestHandler.GetNextQuestieWaypoint()
            end
        end
        
        if GWB.QuestHandler and GWB.QuestHandler.CurrentAutopilotPin then
            local pin = GWB.QuestHandler.CurrentAutopilotPin
            if pin.type == "complete" or pin.type == "available" then
                return false
            end
            if pin.type == "active" then
                activePinQuestId = pin.questId
            end
        else
            return false
        end
    end
    
    for questId, quest in pairs(QuestiePlayer.currentQuestlog) do
        -- Check ALL incomplete quests, not just the current active pin
        if type(quest) == "table" and not quest.isComplete then
            if type(quest.Objectives) == "table" then
                for _, objective in pairs(quest.Objectives) do
                    if type(objective) == "table" and not objective.Completed then
                        -- direct monster/object match
                        if (objective.Type == "monster" and typeId == 5 and objective.Id == objId) or
                           (objective.Type == "object" and typeId == 8 and objective.Id == objId) then
                            return true, quest.name or tostring(questId)
                        end
                        
                        -- Check IdList for multiple valid IDs (common in multi-mob kill objectives)
                        if type(objective.IdList) == "table" then
                            for _, vId in pairs(objective.IdList) do
                                if vId == objId then
                                    return true, quest.name or tostring(questId)
                                end
                            end
                        end
                        
                        -- Check SpawnList (another Questie internal table for valid IDs)
                        if type(objective.SpawnList) == "table" then
                            for _, vId in pairs(objective.SpawnList) do
                                if vId == objId then
                                    return true, quest.name or tostring(questId)
                                end
                            end
                        end

                        -- item drop check via QuestieDB
                        if objective.Type == "item" and typeId == 5 and QuestieDB then
                            local dropMatched = false
                            if QuestieDB.QueryItemSingle then
                                local itemDrops = QuestieDB.QueryItemSingle(objective.Id, "npcDrops")
                                if type(itemDrops) == "table" then
                                    for dropNpcId, _ in pairs(itemDrops) do
                                        if dropNpcId == objId then dropMatched = true; break end
                                    end
                                end
                            elseif QuestieDB.QueryItem then
                                local itemData = QuestieDB.QueryItem(objective.Id)
                                if type(itemData) == "table" and type(itemData[3]) == "table" then
                                    for dropNpcId, _ in pairs(itemData[3]) do
                                        if dropNpcId == objId then dropMatched = true; break end
                                    end
                                end
                            end
                            if dropMatched then return true, quest.name or tostring(questId) end
                        end
                        
                        -- QuestieTooltips Direct NPC-to-Quest ID Match (The most reliable method)
                        if typeId == 5 and QuestieLoader then
                            local ok, QuestieTooltips = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTooltips")
                            if ok and QuestieTooltips and type(QuestieTooltips.tooltipLookup) == "table" then
                                local tData = QuestieTooltips.tooltipLookup["m_" .. tostring(objId)]
                                if type(tData) == "table" then
                                    for qIdKey, _ in pairs(tData) do
                                        local qIdNum = tonumber(qIdKey)
                                        if qIdNum and QuestiePlayer.currentQuestlog[qIdNum] and not QuestiePlayer.currentQuestlog[qIdNum].isComplete then
                                            return true, QuestiePlayer.currentQuestlog[qIdNum].name or tostring(qIdNum)
                                        end
                                    end
                                end
                            end
                        end

                        -- Fallback string matching for GameObjects and NPCs with missing IDs
                        if (typeId == 5 or typeId == 8 or typeId == 3) then
                            local objName = ObjectName(obj)
                            if objName then
                                local lowerName = string.lower(objName)
                                
                                if quest.name and lowerName == string.lower(quest.name) then
                                    return true, quest.name
                                end
                                
                                if objective.Description then
                                    local lowerDesc = string.lower(objective.Description)
                                    if string.find(lowerDesc, lowerName, 1, true) then
                                        return true, quest.name or tostring(questId)
                                    end
                                    
                                    -- Reverse string find: sometimes the mob name contains the description (e.g. "Diseased Boar" contains "Boar")
                                    if string.find(lowerName, lowerDesc, 1, true) then
                                        return true, quest.name or tostring(questId)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local IsQuestieObjectiveFast = GWB.QuestHandler.IsQuestieObjectiveFast

local function GetWorldCoordsFromMap(mapID, mapX, mapY)
    if not mapID or not mapX or not mapY then return nil, nil, nil end
    local mapPos = CreateVector2D and CreateVector2D(mapX, mapY) or {x = mapX, y = mapY}
    local ret1, ret2 = C_Map.GetWorldPosFromMapPos(mapID, mapPos)
    local worldPos = (type(ret2) == "table" and ret2) or (type(ret1) == "table" and ret1)
    
    if worldPos then
        local wx, wy
        if type(worldPos.GetXY) == "function" then
            wx, wy = worldPos:GetXY()
        else
            wx, wy = worldPos.x, worldPos.y
        end
        if not wx or not wy then return nil, nil, nil end
        
        local wz = 0
        local cx, cy, cz = TraceLine(wx, wy, 5000, wx, wy, -5000, 0x110)
        if cx ~= false then
            wz = cz
        end
        return wx, wy, wz
    end
    return nil, nil, nil
end

local cachedPins = {}
local lastCacheTime = 0

local function GetQuestiePins()
    local now = GetTime()
    if now - lastCacheTime < 2.0 then
        return cachedPins
    end
    lastCacheTime = now

    if not QuestieLoader then return cachedPins end
    local ok, QuestieMap = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieMap")
    if not ok or not QuestieMap or not QuestieMap.questIdFrames then return cachedPins end
    
    local okZ, ZoneDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    
    local pins = {}
    local currentMapID = C_Map.GetBestMapForUnit("player")
    if not currentMapID then return cachedPins end -- Retain cache during map transitions
    
    local scanCount = 0
    local matchCount = 0
    local debugCount = 0
    
    for questId, frames in pairs(QuestieMap.questIdFrames) do
        for frameName, frameRef in pairs(frames) do
            scanCount = scanCount + 1
            local actualFrame = type(frameRef) == "table" and frameRef or (type(frameName) == "string" and _G[frameName])
            if actualFrame and actualFrame.data then
                local data = actualFrame.data
                -- Collect pins matching current map
                local uiMapID = actualFrame.uiMapID or actualFrame.UiMapID or actualFrame.uiMapId or actualFrame.mapID
                if not uiMapID and data then
                    uiMapID = data.uiMapID or data.UiMapID or data.uiMapId or data.mapID
                end
                
                -- Fallback if Questie uses AreaID/Zone instead of modern UiMapID
                if not uiMapID then
                    local areaID = actualFrame.AreaID or actualFrame.areaID or actualFrame.Zone
                    if not areaID and data then
                        areaID = data.AreaID or data.areaID or data.Zone
                    end
                    if areaID and okZ and ZoneDB and ZoneDB.GetUiMapIdByAreaId then
                        uiMapID = ZoneDB:GetUiMapIdByAreaId(areaID)
                    end
                end

                -- debug removed

                if uiMapID == currentMapID then
                    matchCount = matchCount + 1
                    local targetId = nil
                    local targetType = "NPC"
                    
                    local questData = data.QuestData
                    if data.Type == "available" and type(questData) == "table" and type(questData.Starts) == "table" then
                        local starts = questData.Starts
                        if type(starts.NPC) == "table" then
                            for _, npcId in pairs(starts.NPC) do
                                targetId = npcId
                                targetType = "NPC"
                                break
                            end
                        elseif type(starts.GameObject) == "table" then
                            for _, goId in pairs(starts.GameObject) do
                                targetId = goId
                                targetType = "GameObject"
                                break
                            end
                        end
                    elseif data.Type == "complete" and type(questData) == "table" and type(questData.Finisher) == "table" then
                        local finisher = questData.Finisher
                        if type(finisher.NPC) == "table" then
                            for _, npcId in pairs(finisher.NPC) do
                                targetId = npcId
                                targetType = "NPC"
                                break
                            end
                        elseif type(finisher.GameObject) == "table" then
                            for _, goId in pairs(finisher.GameObject) do
                                targetId = goId
                                targetType = "GameObject"
                                break
                            end
                        end
                    else
                        targetId = data.Id
                    end

                    local pinX = actualFrame.x or (data and data.x) or 0
                    local pinY = actualFrame.y or (data and data.y) or 0
                    
                    local questLevel = (questData and (questData.Level or questData.level)) or data.Level or data.level or 99

                    local pinType = data.Type
                    if pinType == "monster" or pinType == "object" or pinType == "item" or pinType == "event" then
                        pinType = "active"
                    end

                    table.insert(pins, {
                        questId = questId,
                        type = pinType, -- "available", "complete", "active"
                        name = data.Name,
                        id = targetId or data.Id,
                        targetType = targetType,
                        uiMapID = uiMapID,
                        x = pinX / 100,
                        y = pinY / 100,
                        level = questLevel,
                    })
                end
            end
        end
    end
    
    cachedPins = pins
    
    -- Throttle prints so we don't spam chat
    local nowTime = GetTime()
    if nowTime - (GWB.lastQuestieLogTime or 0) > 3.0 then
        GWB.lastQuestieLogTime = nowTime
        GWB:Print("[Autopilot] Scanned " .. scanCount .. " Questie frames, matched map " .. tostring(currentMapID) .. ": " .. matchCount .. " pins")
    end
    
    return cachedPins
end

local function IsQuestLogFull()
    -- Dynamically check quest limit for Midnight/Retail
    local maxQuests = 20
    if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
        maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept()
    elseif C_QuestLog then
        maxQuests = 35 -- Safe default for modern WoW
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local numQuests = C_QuestLog.GetNumQuestLogEntries()
        return numQuests >= maxQuests
    end

    local numEntries, numQuests = GetNumQuestLogEntries and GetNumQuestLogEntries()
    if numQuests then return numQuests >= maxQuests end
    if not numEntries then return false end
    
    local count = 0
    for i=1, numEntries do
        local _, _, _, isHeader = GetQuestLogTitle(i)
        if not isHeader then count = count + 1 end
    end
    return count >= maxQuests
end

GWB.QuestHandler.BlacklistedPins = GWB.QuestHandler.BlacklistedPins or {}

GWB.QuestHandler.GetNextQuestieWaypoint = function()
    local now = GetTime()
    local px, py, pz = ObjectPosition("player")
    if not px then return nil end

    -- Force re-evaluation when player moves significantly (10+ yards) from last evaluation
    if GWB.QuestHandler.lastEvalPosition then
        local lastPx, lastPy, lastPz = unpack(GWB.QuestHandler.lastEvalPosition)
        local moveDist = math.sqrt((px-lastPx)^2 + (py-lastPy)^2 + (pz-lastPz)^2)
        if moveDist > 10.0 then
            GWB.QuestHandler.CurrentAutopilotPin = nil  -- Clear cache to force re-evaluation
        end
    end

    -- Force re-evaluation every 3 seconds to prevent stale decisions
    if GWB.QuestHandler.lastWaypointUpdate and now - GWB.QuestHandler.lastWaypointUpdate < 3.0 then
        -- Still within evaluation window, return cached pin
        return GWB.QuestHandler.CurrentAutopilotPin
    end
    GWB.QuestHandler.lastWaypointUpdate = now
    GWB.QuestHandler.lastEvalPosition = {px, py, pz}

    local pins = GetQuestiePins()
    if #pins == 0 then
        -- Clear cached pin if no pins found
        GWB.QuestHandler.CurrentAutopilotPin = nil
        return nil
    end

    local bestPin = nil
    local bestScore = 9999999
    local MAX_LOCAL_DIST = 500.0
    local MAX_COMPLETE_DIST = 2000.0
    local logFull = IsQuestLogFull()
    local playerLevel = UnitLevel("player") or 1

    for i = 1, #pins do
        local pin = pins[i]
        
        -- Blacklist check
        local pinId = tostring(pin.questId) .. "_" .. tostring(pin.x) .. "_" .. tostring(pin.y)
        if GWB.QuestHandler.BlacklistedPins[pinId] then
            if now < GWB.QuestHandler.BlacklistedPins[pinId] then
                -- Skip blacklisted pin
            else
                -- Expire blacklist
                GWB.QuestHandler.BlacklistedPins[pinId] = nil
            end
        end

        if not GWB.QuestHandler.BlacklistedPins[pinId] then
            local wx, wy, wz = GetWorldCoordsFromMap(pin.uiMapID, pin.x, pin.y)
            if wx then
                local dist = math.sqrt((wx-px)^2 + (wy-py)^2 + (wz-pz)^2)
                pin.wx, pin.wy, pin.wz = wx, wy, wz
                
                local isValid = false
                if pin.type == "complete" and dist < MAX_COMPLETE_DIST then isValid = true end
                if pin.type == "active" and dist < MAX_LOCAL_DIST then isValid = true end
                if pin.type == "available" and not logFull and dist < MAX_LOCAL_DIST then isValid = true end
                
                if isValid then
                    local pinLevel = pin.level or playerLevel
                    local levelPenalty = 0
                    
                    -- Penalize quests that are too high level
                    if pinLevel > playerLevel + 2 then
                        levelPenalty = (pinLevel - playerLevel) * 100
                    end
                    levelPenalty = levelPenalty + (pinLevel * 0.5)

                    -- Priority base points
                    local priorityBonus = 0
                    if pin.type == "active" then priorityBonus = 0 end
                    if pin.type == "complete" then priorityBonus = -1000 end  -- Strongly prefer completing quests
                    if pin.type == "available" then priorityBonus = 500 end -- available are last resort
                    
                    -- Stick to the same quest bonus!
                    if GWB.QuestHandler.LastActiveQuestId and pin.questId == GWB.QuestHandler.LastActiveQuestId then
                        priorityBonus = priorityBonus - 150
                    end

                    local score = dist + levelPenalty + priorityBonus

                    if score < bestScore then
                        bestPin = pin
                        bestScore = score
                    end
                end
            end
        end
    end

    GWB.QuestHandler.CurrentAutopilotPin = bestPin
    if bestPin and bestPin.type == "active" then
        GWB.QuestHandler.LastActiveQuestId = bestPin.questId
    end
    return bestPin
end

-- Scans nearby units/objects to see if their tooltip matches an active objective
local function ScanNearbyObjectives()
    -- Only scan if the bot is actually running
    if not GWB.Map:IsRunning() then return end
    
    -- Don't scan if we are busy looting or in combat
    if GWB.isPostCombatLooting or UnitAffectingCombat("player") then return end
    
    -- If Autopilot is active, let it handle objective navigation
    if GWB.Settings.QuestieAutopilot then return end
    
    -- If we already have a valid target and it hasn't timed out, verify it
    if GWB.QuestTarget then
        if GetTime() > questTargetTimeout then
            GWB:Debug("QuestTarget timed out.")
            GWB.QuestTarget = nil
        elseif not ObjectExists(GWB.QuestTarget) then
            GWB.QuestTarget = nil
        else
            -- We are still pursuing a valid quest target
            
            -- If it's a game object, check if we are close enough to interact
            if ObjectType(GWB.QuestTarget) == 8 then
                local px, py, pz = ObjectPosition("player")
                local cx, cy, cz = ObjectPosition(GWB.QuestTarget)
                if px and cx then
                    local dist = math.sqrt((cx-px)^2 + (cy-py)^2 + (cz-pz)^2)
                    if dist < 5.0 then
                        -- Stop moving and interact
                        ClickToMove(px, py, pz)
                        ObjectInteract(GWB.QuestTarget)
                        questTargetTimeout = GetTime() + 5 -- give it 5s to finish interacting
                    else
                        -- Keep moving towards it
                        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                            GWB.EZMover:MoveToXYZ(cx, cy, cz)
                        else
                            GWB.Mover:MoveToXYZ(cx, cy, cz)
                        end
                    end
                end
            end
            return
        end
    end

    local px, py, pz = ObjectPosition("player")
    if not px then return end

    -- Check NPCs (5) and GameObjects (8)
    for _, typeId in ipairs({5, 8}) do
        local objects = ObjectManager(typeId) or {}
        for i = 1, #objects do
            local obj = objects[i]
            if ObjectExists(obj) then
                local cx, cy, cz = ObjectPosition(obj)
                if cx then
                    local dx, dy, dz = cx-px, cy-py, cz-pz
                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                    
                    if dist <= SEARCH_RADIUS then
                        local isQuestieObj, questName = IsQuestieObjectiveFast(obj)
                        local matchFound = false
                        
                        if isQuestieObj then
                            matchFound = true
                            GWB:Print("[Questie] Found objective for: " .. tostring(questName))
                        else
                            -- Fallback to Tooltip Check
                            Nn.SetMouseover(obj)
                            
                            -- In Classic, GameTooltipTextLeftX holds the lines
                            for lineNum = 1, 6 do
                                local fontString = _G["GameTooltipTextLeft" .. lineNum]
                                if fontString and fontString.GetText then
                                    local text = fontString:GetText()
                                    if text then
                                        -- See if this tooltip line matches any active objective
                                        if activeObjectives[text] then
                                            matchFound = true
                                            break
                                        end
                                        
                                        -- Fallback check for standard Classic objective format e.g. " 0/8"
                                        if string.find(text, "%d+/%d+") then
                                            matchFound = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        
                        if matchFound then
                            GWB.QuestTarget = obj
                            questTargetTimeout = GetTime() + 15 -- Give it 15 seconds to reach/engage
                            GWB:Debug("Found Quest Objective:", ObjectName(obj))
                            
                            -- Tell the mover to approach
                            if typeId == 5 then
                                -- It's a Unit, try to target it so CombatHandler takes over
                                if Unlock and TargetUnit then
                                    Unlock(TargetUnit, "mouseover")
                                end
                            else
                                -- It's a GameObject, walk to it and interact
                                if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                                    GWB.EZMover:MoveToXYZ(cx, cy, cz)
                                else
                                    GWB.Mover:MoveToXYZ(cx, cy, cz)
                                end
                            end
                            return -- Stop scanning once we find one
                        end
                    end
                end
            end
        end
    end
end

-- ===========================================================================
-- Plugin Callbacks & Tickers
-- ===========================================================================

local lastCacheUpdate = 0
local function UpdateQuestCacheTicker()
    if not GWB.Map:IsRunning() then return end
    if GetTime() - lastCacheUpdate < 5.0 then return end
    lastCacheUpdate = GetTime()
    UpdateQuestCache()
end

local lastScan = 0
local function ScanNearbyObjectivesTicker()
    if not GWB.Map:IsRunning() then return end
    if GetTime() - lastScan < 0.5 then return end
    lastScan = GetTime()
    ScanNearbyObjectives()
end

GWB:RegisterTicker(cacheTickerName, UpdateQuestCacheTicker)
GWB:RegisterTicker(scanTickerName, ScanNearbyObjectivesTicker)
GWB:TickerSetState(cacheTickerName, true)
GWB:TickerSetState(scanTickerName, true)

-- Register plugin
GWB:RegisterPlugin(plugin)

-- Clear cached autopilot pin on load to prevent stale data
GWB.QuestHandler.CurrentAutopilotPin = nil

-- Print integration status on load
if Questie then
    GWB:Print("[Questie] Integration Active: Questie detected. Objective hunting enhanced.")
else
    GWB:Print("[Questie] Integration Inactive: Questie not found. Falling back to Tooltip scanning.")
end

-- ===========================================================================
-- Autopilot Quest Dialogue Automation (Native Event Frame)
-- ===========================================================================

local dialogFrame = CreateFrame("Frame")
dialogFrame:RegisterEvent("GOSSIP_SHOW")
dialogFrame:RegisterEvent("QUEST_GREETING")
dialogFrame:RegisterEvent("QUEST_DETAIL")
dialogFrame:RegisterEvent("QUEST_PROGRESS")
dialogFrame:RegisterEvent("QUEST_COMPLETE")

dialogFrame:SetScript("OnEvent", function(self, event, ...)
    if not GWB.Settings.QuestieAutopilot then return end
    
    C_Timer.After(math.random(6, 12) / 10.0, function()
        if event == "GOSSIP_SHOW" then
            if not GossipFrame or not GossipFrame:IsShown() then return end
            
            local numActive = GetNumGossipActiveQuests() or 0
            if numActive > 0 then
                GWB:Print("Autopilot: Selecting active gossip quest to turn in.")
                if Nn.Unlock then
                    local cmd = "CLICK GossipTitleButton1:LeftButton"
                    Nn.Unlock(RunBinding, cmd)
                    Nn.Unlock(RunBinding, cmd, "up")
                else 
                    SelectGossipActiveQuest(1) 
                end
                return
            end
            
            local numAvailable = GetNumGossipAvailableQuests() or 0
            if numAvailable > 0 then
                GWB:Print("Autopilot: Selecting available gossip quest to accept.")
                if Nn.Unlock then 
                    local cmd = "CLICK GossipTitleButton1:LeftButton"
                    Nn.Unlock(RunBinding, cmd)
                    Nn.Unlock(RunBinding, cmd, "up")
                else 
                    SelectGossipAvailableQuest(1) 
                end
                return
            end
            
            local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()
            if options and #options > 0 then
                GWB:Print("Autopilot: Selecting gossip option.")
                C_GossipInfo.SelectOption(options[1].gossipOptionID)
            end
            
        elseif event == "QUEST_GREETING" then
            if not QuestFrame or not QuestFrame:IsShown() then return end
            
            local numActive = GetNumActiveQuests() or 0
            if numActive > 0 then
                GWB:Print("Autopilot: Selecting active quest from greeting.")
                if Nn.Unlock then
                    local cmd = "CLICK QuestTitleButton1:LeftButton"
                    Nn.Unlock(RunBinding, cmd)
                    Nn.Unlock(RunBinding, cmd, "up")
                else
                    SelectActiveQuest(1)
                end
                return
            end
            
            local numAvailable = GetNumAvailableQuests() or 0
            if numAvailable > 0 then
                GWB:Print("Autopilot: Selecting available quest from greeting.")
                if Nn.Unlock then
                    local cmd = "CLICK QuestTitleButton1:LeftButton"
                    Nn.Unlock(RunBinding, cmd)
                    Nn.Unlock(RunBinding, cmd, "up")
                else
                    SelectAvailableQuest(1)
                end
                return
            end

        elseif event == "QUEST_DETAIL" then
            if QuestFrame and QuestFrame:IsShown() then
                GWB:Print("Autopilot: Accepting quest.")
                if Nn.Unlock then 
                    local cmd = "CLICK QuestFrameAcceptButton:LeftButton"
                    Nn.Unlock(RunBinding, cmd)
                    Nn.Unlock(RunBinding, cmd, "up")
                else 
                    AcceptQuest() 
                end
            end
            
        elseif event == "QUEST_PROGRESS" then
            if QuestFrame and QuestFrame:IsShown() then
                local isComplete = IsQuestCompletable()
                if isComplete then
                    GWB:Print("Autopilot: Clicking continue on quest progress.")
                    if Nn.Unlock then 
                        local cmd = "CLICK QuestFrameCompleteButton:LeftButton"
                        Nn.Unlock(RunBinding, cmd)
                        Nn.Unlock(RunBinding, cmd, "up")
                    else 
                        CompleteQuest() 
                    end
                else
                    GWB:Print("Autopilot: Quest progress not complete yet.")
                end
            end
            
        elseif event == "QUEST_COMPLETE" then
            if QuestFrame and QuestFrame:IsShown() then
                local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
                if numChoices > 0 then
                    -- Select the first reward item using GetQuestReward(1)
                    C_Timer.After(0.3, function()
                        if Nn.Unlock then
                            Nn.Unlock(GetQuestReward, 1)
                        else
                            GetQuestReward(1)
                        end
                    end)
                else
                    -- No reward choices, complete immediately
                    C_Timer.After(0.3, function()
                        if Nn.Unlock then
                            Nn.Unlock(GetQuestReward, 0)
                        else
                            GetQuestReward(0)
                        end
                    end)
                end
            end
        end
    end)
end)

