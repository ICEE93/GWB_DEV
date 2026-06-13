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

local function IsQuestieObjectiveFast(obj)
    if not Questie or not QuestiePlayer or type(QuestiePlayer.currentQuestlog) ~= "table" then return false end
    
    local typeId = ObjectType(obj)
    local objId = typeId == 5 and ObjectUnitId(obj) or ObjectId(obj)
    if not objId then return false end
    
    for questId, quest in pairs(QuestiePlayer.currentQuestlog) do
        if type(quest) == "table" and not quest.isComplete then
            if type(quest.Objectives) == "table" then
                for _, objective in pairs(quest.Objectives) do
                    if type(objective) == "table" and not objective.Completed then
                        -- direct monster/object match
                        if (objective.Type == "monster" and typeId == 5 and objective.Id == objId) or
                           (objective.Type == "object" and typeId == 8 and objective.Id == objId) then
                            return true, quest.name or tostring(questId)
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
                    end
                end
            end
        end
    end
    return false
end

-- Scans nearby units/objects to see if their tooltip matches an active objective
local function ScanNearbyObjectives()
    -- Only scan if the bot is actually running
    if not GWB.Map:IsRunning() then return end
    
    -- Don't scan if we are busy looting or in combat
    if GWB.isPostCombatLooting or UnitAffectingCombat("player") then return end
    
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
-- Plugin Callbacks
-- ===========================================================================

function plugin.OnInitialize()
    -- Create tickers but don't start them yet
    GWB:TickerCreate(cacheTickerName, UpdateQuestCache, 5.0, false)
    GWB:TickerCreate(scanTickerName, ScanNearbyObjectives, 0.5, false) -- Throttle to 2 scans per second
    GWB:Print("Plugin loaded: " .. plugin.name)
end

function plugin.OnStart()
    UpdateQuestCache()
    GWB:TickerSetState(cacheTickerName, true)
    GWB:TickerSetState(scanTickerName, true)
end

function plugin.OnStop()
    GWB:TickerSetState(cacheTickerName, false)
    GWB:TickerSetState(scanTickerName, false)
    GWB.QuestTarget = nil
end

GWB.plugins[plugin.name] = plugin
