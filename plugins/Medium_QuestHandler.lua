local Nn, GWB = ...

local plugin = {}
plugin.name = "QuestHandler"
-- Works on all versions
plugin.xpacs = "classic|retail"
plugin.author = "Antigravity"

local cacheTickerName = plugin.name .. "_CacheTick"
local scanTickerName = plugin.name .. "_ScanTick"

local activeObjectives = {}
GWB.QuestTarget = nil
local questTargetTimeout = 0
local SEARCH_RADIUS = 100.0

-- Blacklist for NPCs we've recently interacted with (to prevent RP runaway issues)
local interactedNPCBlacklist = {}
local BLACKLIST_DURATION = 60 -- 1 minute in seconds

-- Helper functions for blacklist management
local function IsNPCBlacklisted(guid)
    if not guid then return false end
    local entry = interactedNPCBlacklist[guid]
    if not entry then return false end

    -- Check if entry has expired
    if GetTime() > entry.expireTime then
        interactedNPCBlacklist[guid] = nil
        return false
    end

    return true
end

local function AddNPCToBlacklist(guid)
    if not guid then return end
    interactedNPCBlacklist[guid] = {
        expireTime = GetTime() + BLACKLIST_DURATION
    }
end

local function CleanupBlacklist()
    local now = GetTime()
    for guid, entry in pairs(interactedNPCBlacklist) do
        if now > entry.expireTime then
            interactedNPCBlacklist[guid] = nil
        end
    end
end

-- Caches the active quest objectives from the Quest Log
local function UpdateQuestCache()
    activeObjectives = {}
    
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        -- Modern WoW API (11.0+)
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden then
                local objectives = C_QuestLog.GetQuestObjectives(info.questID)
                if objectives then
                    for _, obj in ipairs(objectives) do
                        if not obj.finished then
                            activeObjectives[obj.text] = true
                        end
                    end
                end
            end
        end
    else
        -- Classic / Older API Fallback
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
    if not obj or not ObjectExists(obj) then return false end
    
    local provider = self:GetActiveProvider()
    if provider and provider.IsObjective then
        local isObj, name = provider.IsObjective(obj)
        if isObj then return true, name end
    end
    
    -- Fallback to Tooltip Scan
    local oldMouseover = GetMouseover()
    SetMouseover(obj)
    local isTooltipObj = self.ScanTooltipForObjective("mouseover")
    SetMouseover(oldMouseover)
    
    if isTooltipObj then
        return true, "Tooltip Objective"
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

local function isIncompleteObjective(text)
    if not text then return false end
    local cur, req = string.match(text, "(%d+)%s*/%s*(%d+)")
    if cur and req then
        return tonumber(cur) < tonumber(req)
    end
    return false
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
                    if isIncompleteObjective(line.leftText) then
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
                if text and string.len(text) > 3 then
                    if activeObjectives[text] then
                        GameTooltip:Hide()
                        return true
                    end
                    if isIncompleteObjective(text) then
                        GameTooltip:Hide()
                        return true
                    end
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

    -- Cleanup blacklist periodically
    CleanupBlacklist()

    if UnitAffectingCombat("player") then return end
    if UnitIsDeadOrGhost("player") then return end

    if GWB.QuestTarget then
        if not ObjectExists(GWB.QuestTarget) or (GetTime() > questTargetTimeout) then
            GWB.QuestTarget = nil
            GWB:Debug("Quest Target timed out or disappeared.")
        else
            -- If it's a game object, check if we are close enough to interact
            if ObjectType(GWB.QuestTarget) == 8 then
                local px, py, pz = ObjectPosition("player")
                local cx, cy, cz = ObjectPosition(GWB.QuestTarget)
                if px and cx then
                    local dist = math.sqrt((cx-px)^2 + (cy-py)^2 + (cz-pz)^2)
                    if dist < 5.0 then
                        -- Stop moving and interact
                        ClickToMove(px, py, pz)

                        local isCasting = (UnitCastingInfo and UnitCastingInfo("player")) or (C_Spell and C_Spell.GetUnitCastingInfo and C_Spell.GetUnitCastingInfo("player"))
                        local isChanneling = (UnitChannelInfo and UnitChannelInfo("player")) or (C_Spell and C_Spell.GetUnitChannelInfo and C_Spell.GetUnitChannelInfo("player"))

                        local now = GetTime()
                        if not isCasting and not isChanneling and now - (GWB.lastQuestInteractTime or 0) > 1.5 then
                            ObjectInteract(GWB.QuestTarget)
                            GWB.lastQuestInteractTime = now
                            -- Add NPC to blacklist after interaction
                            local targetGuid = ObjectPointer(GWB.QuestTarget)
                            if targetGuid then
                                AddNPCToBlacklist(targetGuid)
                            end
                        end

                        questTargetTimeout = now + 5 -- give it 5s to finish interacting
                    else
                        -- Keep moving towards it
                        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                            GWB.EZMover:MoveToXYZ(cx, cy, cz)
                        else
                            GWB.Mover:MoveToXYZ(cx, cy, cz)
                        end
                    end
                end
            -- If it's a friendly NPC, check if we are close enough to interact
            elseif ObjectType(GWB.QuestTarget) == 5 then
                local oldMouseover = GetMouseover()
                SetMouseover(GWB.QuestTarget)
                local isFriendly = not UnitCanAttack("player", "mouseover")
                SetMouseover(oldMouseover)

                if isFriendly then
                    local px, py, pz = ObjectPosition("player")
                    local cx, cy, cz = ObjectPosition(GWB.QuestTarget)
                    if px and cx then
                        local dist = math.sqrt((cx-px)^2 + (cy-py)^2 + (cz-pz)^2)
                        if dist < 5.0 then
                            -- Stop moving and interact
                            ClickToMove(px, py, pz)

                            local isCasting = (UnitCastingInfo and UnitCastingInfo("player")) or (C_Spell and C_Spell.GetUnitCastingInfo and C_Spell.GetUnitCastingInfo("player"))
                            local isChanneling = (UnitChannelInfo and UnitChannelInfo("player")) or (C_Spell and C_Spell.GetUnitChannelInfo and C_Spell.GetUnitChannelInfo("player"))

                            local now = GetTime()
                            if not isCasting and not isChanneling and now - (GWB.lastQuestInteractTime or 0) > 1.5 then
                                ObjectInteract(GWB.QuestTarget)
                                GWB.lastQuestInteractTime = now
                                -- Add NPC to blacklist after interaction
                                local targetGuid = ObjectPointer(GWB.QuestTarget)
                                if targetGuid then
                                    AddNPCToBlacklist(targetGuid)
                                end
                            end

                            questTargetTimeout = now + 5 -- give it 5s to finish interacting
                        else
                            -- Keep moving towards it
                            if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                                GWB.EZMover:MoveToXYZ(cx, cy, cz)
                            else
                                GWB.Mover:MoveToXYZ(cx, cy, cz)
                            end
                        end
                    end
                else
                    -- Hostile NPC quest target. CombatHandler will handle movement and combat
                    if Unlock and TargetUnit then
                        local oldMouseover = GetMouseover()
                        SetMouseover(GWB.QuestTarget)
                        Unlock(TargetUnit, "mouseover")
                        SetMouseover(oldMouseover)
                    end
                    -- Do not move to it here, CombatHandler does that
                end
            end
            return
        end
    end

    -- If we don't have a QuestTarget, scan for the CLOSEST one
    if not GWB.QuestTarget then
        local px, py, pz = ObjectPosition("player")
        if not px then return end

        local objects = Objects()
        if not objects then return end

        local bestObj = nil
        local bestDist = SEARCH_RADIUS + 1

        for i = 1, #objects do
            local obj = objects[i]
            if ObjectExists(obj) then
                local typeId = ObjectType(obj)
                -- 5 = Unit (NPC/Monster), 8 = GameObject (Chests, Gatherables)
                if typeId == 5 or typeId == 8 then
                    local cx, cy, cz = ObjectPosition(obj)
                    if cx then
                        local dx, dy, dz = cx-px, cy-py, cz-pz
                        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                        
                        if dist < bestDist then
                            -- Check if the unit is dead
                            local skipObj = false
                            if typeId == 5 then
                                local oldMouseover = GetMouseover()
                                SetMouseover(obj)
                                if UnitIsDead("mouseover") then
                                    skipObj = true
                                end
                                SetMouseover(oldMouseover)
                            end

                            if not skipObj then
                                -- Check blacklist
                                local objGuid = ObjectPointer(obj)
                                if objGuid and IsNPCBlacklisted(objGuid) then
                                    skipObj = true
                                end

                                if not skipObj then
                                    local isQuestObj, questName = GWB.QuestHandler:IsObjective(obj)
                                    if isQuestObj then
                                        bestObj = obj
                                        bestDist = dist
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if bestObj then
            GWB.QuestTarget = bestObj
            questTargetTimeout = GetTime() + 15
            GWB:Debug("Found Closest Quest Objective:", ObjectName(bestObj), "at dist", bestDist)

            -- Check if friendly or hostile
            local typeId = ObjectType(bestObj)
            local isFriendly = false
            if typeId == 5 then
                local oldMouseover = GetMouseover()
                SetMouseover(bestObj)
                isFriendly = not UnitCanAttack("player", "mouseover")
                SetMouseover(oldMouseover)
            end

            -- Approach
            if typeId == 5 then
                if isFriendly then
                    local cx, cy, cz = ObjectPosition(bestObj)
                    if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                        GWB.EZMover:MoveToXYZ(cx, cy, cz)
                    else
                        GWB.Mover:MoveToXYZ(cx, cy, cz)
                    end
                else
                    -- Hostile, let CombatHandler handle
                    if Unlock and TargetUnit then
                        local oldMouseover = GetMouseover()
                        SetMouseover(bestObj)
                        Unlock(TargetUnit, "mouseover")
                        SetMouseover(oldMouseover)
                    end
                end
            else
                -- GameObject
                local cx, cy, cz = ObjectPosition(bestObj)
                if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                    GWB.EZMover:MoveToXYZ(cx, cy, cz)
                else
                    GWB.Mover:MoveToXYZ(cx, cy, cz)
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

            local numActive = 0
            if type(GetNumGossipActiveQuests) == "function" then
                numActive = GetNumGossipActiveQuests() or 0
            end

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

            local numAvailable = 0
            if type(GetNumGossipAvailableQuests) == "function" then
                numAvailable = GetNumGossipAvailableQuests() or 0
            end

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

