local Nn, GWB = ...

local plugin = {}
plugin.name = "Provider_Questie"
plugin.xpacs = "classic"
plugin.author = "Antigravity"

local QuestieProvider = {}

local cachedPins = {}
local lastCacheTime = 0

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

local function GetQuestiePins()
    local now = GetTime()
    if now - lastCacheTime < 2.0 then
        return cachedPins
    end
    
    if not QuestieLoader then return cachedPins end
    local ok, QuestieMap = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieMap")
    if not ok or not QuestieMap or not QuestieMap.questIdFrames then return cachedPins end
    
    local okZ, ZoneDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    
    local pins = {}
    local currentMapID = C_Map.GetBestMapForUnit("player")
    local playerMapID = currentMapID
    
    local matchCount = 0
    local scanCount = 0

    for questId, frames in pairs(QuestieMap.questIdFrames) do
        for frameName, frameRef in pairs(frames) do
            scanCount = scanCount + 1
            local actualFrame = _G[frameName]
            if actualFrame and actualFrame.x and actualFrame.y and actualFrame.IsShown and actualFrame:IsShown() then
                local uiMapID = actualFrame.uiMapId or actualFrame.uiMapID
                
                -- Fallback if Questie uses AreaID/Zone instead of modern UiMapID
                if not uiMapID then
                    local areaID = actualFrame.AreaID or actualFrame.areaID or actualFrame.Zone
                    if areaID and ZoneDB and ZoneDB.GetUiMapIdByAreaId then
                        uiMapID = ZoneDB.GetUiMapIdByAreaId(areaID)
                    end
                end
                
                if uiMapID then
                    -- Get the type of pin (complete, active, available)
                    local iconType = "active"
                    if actualFrame.miniMapIcon then
                        local tex = actualFrame.miniMapIcon:GetTexture()
                        if type(tex) == "string" then
                            local t = string.lower(tex)
                            if string.find(t, "complete") then iconType = "complete" end
                            if string.find(t, "available") then iconType = "available" end
                        end
                    elseif actualFrame.texture then
                        local tex = actualFrame.texture:GetTexture()
                        if type(tex) == "string" then
                            local t = string.lower(tex)
                            if string.find(t, "complete") then iconType = "complete" end
                            if string.find(t, "available") then iconType = "available" end
                        end
                    end

                    -- For multi-zone compatibility, we'll collect all pins and just weight by distance later.
                    -- But if a pin has no coords, skip it.
                    local px, py = actualFrame.x / 100, actualFrame.y / 100
                    if px > 0 and py > 0 then
                        table.insert(pins, {
                            x = px,
                            y = py,
                            questId = questId,
                            uiMapID = uiMapID,
                            type = iconType
                        })
                        
                        if uiMapID == currentMapID then
                            matchCount = matchCount + 1
                        end
                    end
                end
            end
        end
    end
    
    cachedPins = pins
    lastCacheTime = now
    
    local nowTime = GetTime()
    if nowTime - (GWB.lastQuestieLogTime or 0) > 3.0 then
        GWB.lastQuestieLogTime = nowTime
        GWB:Print("[Autopilot] Scanned " .. scanCount .. " Questie frames, matched map " .. tostring(currentMapID) .. ": " .. matchCount .. " pins")
    end
    
    return cachedPins
end

function QuestieProvider.IsObjective(obj)
    if not Questie or not QuestiePlayer or type(QuestiePlayer.currentQuestlog) ~= "table" then return false end
    
    local typeId = ObjectType(obj)
    local objId = ObjectId(obj)
    if typeId == 5 then objId = ObjectUnitId(obj) end
    if not objId then return false end
    
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

function QuestieProvider.GetNextWaypoint()
    local now = GetTime()
    local px, py, pz = ObjectPosition("player")
    if not px then return nil end

    if GWB.QuestHandler and GWB.QuestHandler.lastEvalPosition then
        local lastPx, lastPy, lastPz = unpack(GWB.QuestHandler.lastEvalPosition)
        local moveDist = math.sqrt((px-lastPx)^2 + (py-lastPy)^2 + (pz-lastPz)^2)
        if moveDist > 10.0 then
            if GWB.QuestHandler then GWB.QuestHandler.CurrentAutopilotPin = nil end
        end
    end

    if GWB.QuestHandler and GWB.QuestHandler.lastWaypointUpdate and now - GWB.QuestHandler.lastWaypointUpdate < 3.0 then
        return GWB.QuestHandler.CurrentAutopilotPin
    end
    
    if GWB.QuestHandler then
        GWB.QuestHandler.lastWaypointUpdate = now
        GWB.QuestHandler.lastEvalPosition = {px, py, pz}
    end

    local pins = GetQuestiePins()
    if #pins == 0 then
        if GWB.QuestHandler then GWB.QuestHandler.CurrentAutopilotPin = nil end
        return nil
    end

    local bestPin = nil
    local bestScore = 9999999
    local logFull = false
    if GWB.QuestHandler and GWB.QuestHandler.IsQuestLogFull then
        logFull = GWB.QuestHandler.IsQuestLogFull()
    end
    local playerLevel = UnitLevel("player") or 1

    for i = 1, #pins do
        local pin = pins[i]
        
        local pinId = tostring(pin.questId) .. "_" .. tostring(pin.x) .. "_" .. tostring(pin.y)
        if GWB.QuestHandler and GWB.QuestHandler.BlacklistedPins and GWB.QuestHandler.BlacklistedPins[pinId] then
            if now < GWB.QuestHandler.BlacklistedPins[pinId] then
                -- Skip blacklisted pin
            else
                GWB.QuestHandler.BlacklistedPins[pinId] = nil
            end
        end

        local isBlacklisted = GWB.QuestHandler and GWB.QuestHandler.BlacklistedPins and GWB.QuestHandler.BlacklistedPins[pinId]
        if not isBlacklisted then
            local wx, wy, wz = GetWorldCoordsFromMap(pin.uiMapID, pin.x, pin.y)
            if wx then
                local dist = math.sqrt((wx-px)^2 + (wy-py)^2 + (wz-pz)^2)
                pin.wx, pin.wy, pin.wz = wx, wy, wz
                
                local ignorePin = false
                if pin.type == "available" and logFull then ignorePin = true end
                
                if not ignorePin then
                    local pinLevel = pin.level or playerLevel
                    local levelPenalty = 0
                    
                    if pinLevel > playerLevel + 2 then
                        levelPenalty = (pinLevel - playerLevel) * 100
                    end
                    levelPenalty = levelPenalty + (pinLevel * 0.5)

                    local priorityBonus = 0
                    if pin.type == "active" then priorityBonus = 0 end
                    if pin.type == "complete" then priorityBonus = -1000 end
                    if pin.type == "available" then priorityBonus = 500 end
                    
                    if GWB.QuestHandler and GWB.QuestHandler.LastActiveQuestId and pin.questId == GWB.QuestHandler.LastActiveQuestId then
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

    if GWB.QuestHandler then
        GWB.QuestHandler.CurrentAutopilotPin = bestPin
        if bestPin and bestPin.type == "active" then
            GWB.QuestHandler.LastActiveQuestId = bestPin.questId
        end
    end
    return bestPin
end

local function PluginInit()
    if not GWB.QuestHandler then return end
    if not GWB.QuestHandler.RegisterProvider then return end
    
    GWB.QuestHandler:RegisterProvider("Questie", QuestieProvider)
    
    if Questie then
        GWB:Print("[Questie] Provider registered successfully.")
    end
end

C_Timer.After(1.0, PluginInit)
GWB:RegisterPlugin(plugin)
