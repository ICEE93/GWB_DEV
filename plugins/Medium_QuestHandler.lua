local Nn, GWB = ...

local plugin = {}
plugin.name = "QuestHandler"
plugin.xpacs = "classic"
plugin.author = "Antigravity"

local cacheTickerName = plugin.name .. "_CacheTick"
local scanTickerName = plugin.name .. "_ScanTick"

local activeObjectives = {}
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
                    activeObjectives[text] = true
                end
            end
        end
    end
end

GWB.QuestHandler = GWB.QuestHandler or {}
GWB.QuestHandler.Providers = {}
GWB.QuestHandler.ActiveProvider = nil
GWB.QuestHandler.BlacklistedPins = {}

function GWB.QuestHandler:RegisterProvider(name, providerTable)
    self.Providers[name] = providerTable
    
    -- Assign ActiveProvider based on UI setting if available, else just pick the first one registered
    local targetSetting = GWB.Settings and GWB.Settings.AutopilotProvider or "Questie"
    if name == targetSetting or not self.ActiveProvider then
        self.ActiveProvider = providerTable
    end
end

function GWB.QuestHandler:GetActiveProvider()
    local targetSetting = GWB.Settings and GWB.Settings.AutopilotProvider or "Questie"
    if self.Providers[targetSetting] then
        return self.Providers[targetSetting]
    end
    return self.ActiveProvider
end

function GWB.QuestHandler:IsObjective(obj)
    local provider = self:GetActiveProvider()
    if provider and provider.IsObjective then
        return provider.IsObjective(obj)
    end
    return false
end

function GWB.QuestHandler:GetNextWaypoint()
    local provider = self:GetActiveProvider()
    if provider and provider.GetNextWaypoint then
        return provider.GetNextWaypoint()
    end
    return nil
end

GWB.QuestHandler.IsQuestLogFull = function()
    local maxQuests = 20
    if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
        maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept()
    elseif C_QuestLog then
        maxQuests = 35 
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

-- Fallback tooltip scanning (generic for all providers)
GWB.QuestHandler.ScanTooltipForObjective = function(unit)
    if not unit then return false end
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local tooltipInfo = C_TooltipInfo.GetUnit(unit)
        if tooltipInfo and tooltipInfo.lines then
            for _, line in ipairs(tooltipInfo.lines) do
                if line.leftText then
                    if activeObjectives[line.leftText] then
                        return true
                    end
                end
            end
        end
    elseif GameTooltip then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetUnit(unit)
        for i = 2, GameTooltip:NumLines() do
            local line = _G["GameTooltipTextLeft" .. i]
            if line then
                local text = line:GetText()
                if text and activeObjectives[text] then
                    GameTooltip:Hide()
                    return true
                end
            end
        end
        GameTooltip:Hide()
    end
    return false
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
                        local isQuestieObj, questName = GWB.QuestHandler:IsObjective(obj)
                        local matchFound = false
                        
                        if isQuestieObj then
                            matchFound = true
                            GWB:Print("[Autopilot] Found objective for: " .. tostring(questName))
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
C_Timer.After(2.0, function()
    local provider = GWB.QuestHandler:GetActiveProvider()
    if provider then
        GWB:Print("[QuestHandler] Active Autopilot Provider: " .. (GWB.Settings.AutopilotProvider or "Questie"))
    else
        GWB:Print("[QuestHandler] No Autopilot Provider found. Falling back to Tooltip scanning.")
    end
end)

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

