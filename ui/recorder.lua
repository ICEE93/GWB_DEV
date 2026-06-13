local Nn, GWB = ...

-- Ensure UI module exists
GWB.RecorderUI = {}

local recorderFrame = CreateFrame("Frame", "GWBRecorderFrame", UIParent, "BasicFrameTemplateWithInset")
recorderFrame:SetSize(400, 500)
recorderFrame:SetPoint("CENTER")
recorderFrame:Hide()
recorderFrame:SetMovable(true)
recorderFrame:EnableMouse(true)
recorderFrame:RegisterForDrag("LeftButton")
recorderFrame:SetScript("OnDragStart", recorderFrame.StartMoving)
recorderFrame:SetScript("OnDragStop", recorderFrame.StopMovingOrSizing)
recorderFrame:SetFrameStrata("DIALOG")

recorderFrame.title = recorderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
recorderFrame.title:SetPoint("CENTER", recorderFrame.TitleBg, "CENTER", 0, 0)
recorderFrame.title:SetText("GWB Routine Recorder")

-- ---------------------------------------------------------------------------
-- Top Panel: Controls
-- ---------------------------------------------------------------------------
local topPanel = CreateFrame("Frame", nil, recorderFrame)
topPanel:SetSize(380, 40)
topPanel:SetPoint("TOPLEFT", 10, -30)

local btnRecord = CreateFrame("Button", nil, topPanel, "UIPanelButtonTemplate")
btnRecord:SetSize(80, 22)
btnRecord:SetPoint("LEFT", 0, 0)
btnRecord:SetText("REC")

local inputName = CreateFrame("EditBox", nil, topPanel, "InputBoxTemplate")
inputName:SetSize(120, 20)
inputName:SetPoint("LEFT", btnRecord, "RIGHT", 15, 0)
inputName:SetAutoFocus(false)
inputName:SetText("my_routine")

local btnSave = CreateFrame("Button", nil, topPanel, "UIPanelButtonTemplate")
btnSave:SetSize(70, 22)
btnSave:SetPoint("LEFT", inputName, "RIGHT", 10, 0)
btnSave:SetText("Save")

local btnPlay = CreateFrame("Button", nil, topPanel, "UIPanelButtonTemplate")
btnPlay:SetSize(70, 22)
btnPlay:SetPoint("LEFT", btnSave, "RIGHT", 5, 0)
btnPlay:SetText("Play")

-- ---------------------------------------------------------------------------
-- Middle Panel: Step List
-- ---------------------------------------------------------------------------
local scrollFrame = CreateFrame("ScrollFrame", "GWBRecorderScrollFrame", recorderFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", topPanel, "BOTTOMLEFT", 0, -10)
scrollFrame:SetPoint("BOTTOMRIGHT", recorderFrame, "BOTTOMRIGHT", -30, 10)

local scrollChild = CreateFrame("Frame", "GWBRecorderScrollChild", scrollFrame)
scrollChild:SetSize(scrollFrame:GetWidth(), scrollFrame:GetHeight())
scrollFrame:SetScrollChild(scrollChild)

-- ---------------------------------------------------------------------------
-- UI Refresh Logic
-- ---------------------------------------------------------------------------
local function GetActiveSteps()
    if GWB.Routine:IsRecording() then
        return GWB.Routine:GetCurrentSteps()
    elseif GWB.RoutinePlayback and GWB.RoutinePlayback:IsRunning() then
        -- Hacky way to access steps if needed, but usually we just want to see the loaded ones.
        -- We will pull from Routine (which holds the last saved/loaded in memory if we implement it)
        -- For now, if recording is false, just show the steps from Routine if they exist.
        return GWB.Routine:GetCurrentSteps() -- returns activeSession
    end
    return GWB.Routine:GetCurrentSteps()
end

local stepRows = {}

local function RefreshStepList()
    local steps = GetActiveSteps() or {}
    
    -- Hide old rows
    for _, row in ipairs(stepRows) do
        row:Hide()
    end

    local yOffset = -5
    for i, step in ipairs(steps) do
        local row = stepRows[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(340, 24)
            
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.2, 0.2, 0.2, 0.5)
            row.bg = bg
            
            local numText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            numText:SetPoint("LEFT", 5, 0)
            numText:SetWidth(25)
            numText:SetJustifyH("RIGHT")
            row.numText = numText
            
            local typeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            typeText:SetPoint("LEFT", numText, "RIGHT", 10, 0)
            typeText:SetWidth(80)
            typeText:SetJustifyH("LEFT")
            row.typeText = typeText

            local descText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            descText:SetPoint("LEFT", typeText, "RIGHT", 5, 0)
            descText:SetWidth(180)
            descText:SetJustifyH("LEFT")
            row.descText = descText

            stepRows[i] = row
        end

        row:SetPoint("TOPLEFT", 5, yOffset)
        row.numText:SetText(tostring(i))
        row.typeText:SetText(step.type)
        
        local desc = ""
        if step.type == "waypoint" then
            desc = string.format("X: %.1f, Y: %.1f", step.x, step.y)
        elseif step.type == "npc_interact" then
            desc = step.npcName or ("NPC " .. tostring(step.npcId))
        elseif step.type == "quest_accept" or step.type == "quest_turnin" then
            desc = step.questName or ("Quest " .. tostring(step.questId))
        elseif step.type == "loot_object" then
            desc = step.objectName or ("Obj " .. tostring(step.objectId))
        end
        row.descText:SetText(desc)

        row:Show()
        yOffset = yOffset - 26
    end
    
    scrollChild:SetHeight(math.abs(yOffset))
end

-- ---------------------------------------------------------------------------
-- Button Handlers
-- ---------------------------------------------------------------------------
btnRecord:SetScript("OnClick", function()
    if GWB.Routine:IsRecording() then
        GWB.Routine:StopRecording()
        btnRecord:SetText("REC")
        RefreshStepList()
    else
        local name = inputName:GetText()
        if name == "" then name = "routine_" .. date("%Y%m%d_%H%M%S") end
        GWB.Routine:StartRecording(name)
        btnRecord:SetText("STOP")
        RefreshStepList()
    end
end)

btnSave:SetScript("OnClick", function()
    local name = inputName:GetText()
    if name == "" then name = "routine_" .. date("%Y%m%d_%H%M%S") end
    GWB.Routine:SaveToDisk(name)
end)

btnPlay:SetScript("OnClick", function()
    if GWB.RoutinePlayback and GWB.RoutinePlayback:IsRunning() then
        GWB.RoutinePlayback:Stop()
        btnPlay:SetText("Play")
    else
        local name = inputName:GetText()
        if name == "" then GWB:Print("Enter a routine name to play.") return end
        
        local steps, loadedName = GWB.Routine:LoadFromDisk(name)
        if steps then
            if GWB.RoutinePlayback then
                GWB.RoutinePlayback:LoadAndStart(name, steps)
                btnPlay:SetText("Stop")
                RefreshStepList()
            else
                GWB:Print("RoutinePlayback plugin not loaded!")
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- GWB Callbacks
-- ---------------------------------------------------------------------------
function GWB.RecorderUI.OnStepAdded(step)
    if recorderFrame:IsShown() then
        RefreshStepList()
    end
end

function GWB.RecorderUI.OnPlaybackStepChanged(idx, step)
    if not recorderFrame:IsShown() then return end
    
    for i, row in ipairs(stepRows) do
        if i == idx then
            row.bg:SetColorTexture(0.2, 0.8, 0.2, 0.5) -- highlight green
        else
            row.bg:SetColorTexture(0.2, 0.2, 0.2, 0.5)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Integration
-- ---------------------------------------------------------------------------
function GWB:ToggleRecorderUI()
    if recorderFrame:IsShown() then
        recorderFrame:Hide()
    else
        recorderFrame:Show()
        RefreshStepList()
        if GWB.Routine:IsRecording() then
            btnRecord:SetText("STOP")
        else
            btnRecord:SetText("REC")
        end
        if GWB.RoutinePlayback and GWB.RoutinePlayback:IsRunning() then
            btnPlay:SetText("Stop")
        else
            btnPlay:SetText("Play")
        end
    end
end


