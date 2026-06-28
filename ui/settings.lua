local Nn, GWB = ...

-- Ensure global settings table exists
GWB.Settings = GWB.Settings or {}
if GWB.Settings.UseEZNavSafe == nil then
    GWB.Settings.UseEZNavSafe = false
end
if GWB.Settings.ActiveProfile == nil then
    GWB.Settings.ActiveProfile = ""
end
if GWB.Settings.QuestieAutopilot == nil then
    GWB.Settings.QuestieAutopilot = false
end
if GWB.Settings.DebugWhiskers == nil then
    GWB.Settings.DebugWhiskers = false
end
if GWB.Settings.DebugZygor == nil then
    GWB.Settings.DebugZygor = false
end
if GWB.Settings.DisableCR == nil then
    GWB.Settings.DisableCR = false
end

GWB.Settings.ActiveTab = GWB.Settings.ActiveTab or "Core"

local configFrame = CreateFrame("Frame", "GWBConfigFrame", UIParent, "BasicFrameTemplateWithInset")
configFrame:SetSize(620, 500)
configFrame:SetPoint("CENTER")
configFrame:Hide()
configFrame:SetMovable(true)
configFrame:EnableMouse(true)
configFrame:RegisterForDrag("LeftButton")
configFrame:SetScript("OnDragStart", configFrame.StartMoving)
configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
configFrame:SetFrameStrata("DIALOG")

configFrame.title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
configFrame.title:SetPoint("CENTER", configFrame.TitleBg, "CENTER", 0, 0)
configFrame.title:SetText("GWB Configuration")

function GWB:SaveSettings()
    GWB.Storage.Settings = GWB.Storage.Settings or {}
    
    GWB.Storage.Settings.Core = GWB.Storage.Settings.Core or {}
    GWB.Storage.Settings.Core.UseEZNavSafe = GWB.Settings.UseEZNavSafe
    GWB.Storage.Settings.Core.ActiveProfile = GWB.Settings.ActiveProfile
    GWB.Storage.Settings.Core.QuestieAutopilot = GWB.Settings.QuestieAutopilot
    GWB.Storage.Settings.Core.AutopilotProvider = GWB.Settings.AutopilotProvider
    GWB.Storage.Settings.Core.DebugWhiskers = GWB.Settings.DebugWhiskers
    GWB.Storage.Settings.Core.DebugZygor = GWB.Settings.DebugZygor
    GWB.Storage.Settings.Core.DisableCR = GWB.Settings.DisableCR

    for pluginName, plugin in pairs(GWB.plugins) do
        if plugin.settings then
            GWB.Storage.Settings[pluginName] = GWB.Storage.Settings[pluginName] or {}
            for settingKey, settingData in pairs(plugin.settings) do
                GWB.Storage.Settings[pluginName][settingKey] = settingData.value
            end
        end
    end

    if GWB.StorageMgr and GWB.StorageMgr.SaveStorageToDisk then
        GWB.StorageMgr:SaveStorageToDisk()
    end
end

function GWB:LoadSettings()
    if not GWB.Storage or not GWB.Storage.Settings then return end
    
    if GWB.Storage.Settings.Core then
        if GWB.Storage.Settings.Core.UseEZNavSafe ~= nil then
            GWB.Settings.UseEZNavSafe = GWB.Storage.Settings.Core.UseEZNavSafe
        end
        if GWB.Storage.Settings.Core.ActiveProfile ~= nil then
            GWB.Settings.ActiveProfile = GWB.Storage.Settings.Core.ActiveProfile
        end
        if GWB.Storage.Settings.Core.QuestieAutopilot ~= nil then
            GWB.Settings.QuestieAutopilot = GWB.Storage.Settings.Core.QuestieAutopilot
        end
        if GWB.Storage.Settings.Core.AutopilotProvider ~= nil then
            GWB.Settings.AutopilotProvider = GWB.Storage.Settings.Core.AutopilotProvider
        end
        if GWB.Storage.Settings.Core.DebugWhiskers ~= nil then
            GWB.Settings.DebugWhiskers = GWB.Storage.Settings.Core.DebugWhiskers
        end
        if GWB.Storage.Settings.Core.DebugZygor ~= nil then
            GWB.Settings.DebugZygor = GWB.Storage.Settings.Core.DebugZygor
        end
        if GWB.Storage.Settings.Core.DisableCR ~= nil then
            GWB.Settings.DisableCR = GWB.Storage.Settings.Core.DisableCR
        end
    end

    for pluginName, plugin in pairs(GWB.plugins) do
        if plugin.settings and GWB.Storage.Settings[pluginName] then
            for settingKey, settingData in pairs(plugin.settings) do
                if GWB.Storage.Settings[pluginName][settingKey] ~= nil then
                    settingData.value = GWB.Storage.Settings[pluginName][settingKey]
                end
            end
        end
    end
end

local tabScrollFrame = CreateFrame("ScrollFrame", "GWBConfigTabScroll", configFrame, "UIPanelScrollFrameTemplate")
tabScrollFrame:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 10, -30)
tabScrollFrame:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMLEFT", 140, 10)

local tabScrollChild = CreateFrame("Frame", "GWBConfigTabChild", tabScrollFrame)
tabScrollChild:SetSize(130, 460)
tabScrollFrame:SetScrollChild(tabScrollChild)

local scrollFrame = CreateFrame("ScrollFrame", "GWBConfigScrollFrame", configFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 160, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", -30, 10)

local scrollChild = CreateFrame("Frame", "GWBConfigScrollChild", scrollFrame)
scrollChild:SetSize(scrollFrame:GetWidth(), scrollFrame:GetHeight())
scrollFrame:SetScrollChild(scrollChild)

function GWB:RebuildConfigUI()
    GWB:LoadSettings() -- sync before rebuilding

    local children = {scrollChild:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    local tabChildren = {tabScrollChild:GetChildren()}
    for _, child in ipairs(tabChildren) do
        child:Hide()
        child:SetParent(nil)
    end
    local regions = {scrollChild:GetRegions()}
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "FontString" then
            region:SetText("")
            region:Hide()
        end
    end

    -- 1. BUILD TABS
    local tabY = -5
    local function createTabBtn(label, tabId)
        local btn = CreateFrame("Button", nil, tabScrollChild, "UIPanelButtonTemplate")
        btn:SetSize(120, 25)
        btn:SetPoint("TOPLEFT", 5, tabY)
        btn:SetText(label)
        if GWB.Settings.ActiveTab == tabId then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
        btn:SetScript("OnClick", function()
            GWB.Settings.ActiveTab = tabId
            GWB:RebuildConfigUI()
        end)
        tabY = tabY - 30
    end
    
    createTabBtn("Core Engine", "Core")
    for pluginName, plugin in pairs(GWB.plugins) do
        if plugin.settings then
            createTabBtn(plugin.name or pluginName, pluginName)
        end
    end
    tabScrollChild:SetHeight(math.abs(tabY))

    -- 2. BUILD CONTENT
    local yOffset = -10

    if GWB.Settings.ActiveTab == "Core" then
        local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 10, yOffset)
        header:SetText("Core Engine")
        yOffset = yOffset - 25

    local cb = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 20, yOffset)
    cb:SetChecked(GWB.Settings.UseEZNavSafe)
    local cbText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbText:SetPoint("LEFT", cb, "RIGHT", 5, 1)
    cbText:SetText("Use EZNavSafe (requires reload)")
    cb:SetScript("OnClick", function(self)
        GWB.Settings.UseEZNavSafe = self:GetChecked()
        GWB:SaveSettings()
        print("GWB: Set UseEZNavSafe to " .. tostring(GWB.Settings.UseEZNavSafe) .. ". Please /reload.")
    end)
    yOffset = yOffset - 25

    local cbAutopilot = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    cbAutopilot:SetSize(24, 24)
    cbAutopilot:SetPoint("TOPLEFT", 20, yOffset)
    cbAutopilot:SetChecked(GWB.Settings.QuestieAutopilot)
    local cbAutopilotText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbAutopilotText:SetPoint("LEFT", cbAutopilot, "RIGHT", 5, 1)
    cbAutopilotText:SetText("Enable Autopilot (No Waypoints)")
    cbAutopilot:SetScript("OnClick", function(self)
        GWB.Settings.QuestieAutopilot = self:GetChecked()
        if GWB.QuestHandler then
            GWB.QuestHandler.CurrentAutopilotPin = nil
        end
        GWB:SaveSettings()
        print("GWB: Set Autopilot to " .. tostring(GWB.Settings.QuestieAutopilot))
    end)
    yOffset = yOffset - 30

    local cbWhiskers = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    cbWhiskers:SetSize(24, 24)
    cbWhiskers:SetPoint("TOPLEFT", 20, yOffset)
    cbWhiskers:SetChecked(GWB.Settings.DebugWhiskers)
    local cbWhiskersText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbWhiskersText:SetPoint("LEFT", cbWhiskers, "RIGHT", 5, 1)
    cbWhiskersText:SetText("Show Navigation Rays (Debug)")
    cbWhiskers:SetScript("OnClick", function(self)
        GWB.Settings.DebugWhiskers = self:GetChecked()
        GWB:SaveSettings()
    end)
    yOffset = yOffset - 30

    local cbZygor = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    cbZygor:SetSize(24, 24)
    cbZygor:SetPoint("TOPLEFT", 20, yOffset)
    cbZygor:SetChecked(GWB.Settings.DebugZygor)
    local cbZygorText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbZygorText:SetPoint("LEFT", cbZygor, "RIGHT", 5, 1)
    cbZygorText:SetText("Debug Zygor Provider")
    cbZygor:SetScript("OnClick", function(self)
        GWB.Settings.DebugZygor = self:GetChecked()
        GWB:SaveSettings()
    end)
    yOffset = yOffset - 30

    local cbDisableCR = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    cbDisableCR:SetSize(24, 24)
    cbDisableCR:SetPoint("TOPLEFT", 20, yOffset)
    cbDisableCR:SetChecked(GWB.Settings.DisableCR)
    local cbDisableCRText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbDisableCRText:SetPoint("LEFT", cbDisableCR, "RIGHT", 5, 1)
    cbDisableCRText:SetText("Disable Internal Combat Routine")
    cbDisableCR:SetScript("OnClick", function(self)
        GWB.Settings.DisableCR = self:GetChecked()
        GWB:SaveSettings()
    end)
    yOffset = yOffset - 30

    local provText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    provText:SetPoint("TOPLEFT", 25, yOffset - 3)
    provText:SetText("Autopilot Provider")

    local provDropdown = CreateFrame("Frame", nil, scrollChild, "UIDropDownMenuTemplate")
    provDropdown:SetPoint("TOPLEFT", 200, yOffset + 5)
    UIDropDownMenu_SetWidth(provDropdown, 120)
    UIDropDownMenu_SetText(provDropdown, tostring(GWB.Settings.AutopilotProvider or "Questie"))
    
    UIDropDownMenu_Initialize(provDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        
        info.text = "Questie"
        info.arg1 = "Questie"
        info.func = function(self, arg1)
            GWB.Settings.AutopilotProvider = arg1
            UIDropDownMenu_SetText(provDropdown, arg1)
            GWB:SaveSettings()
            print("GWB: Set Autopilot Provider to: " .. arg1)
        end
        info.checked = (GWB.Settings.AutopilotProvider == "Questie")
        UIDropDownMenu_AddButton(info)
        
        info.text = "Zygor"
        info.arg1 = "Zygor"
        info.func = function(self, arg1)
            GWB.Settings.AutopilotProvider = arg1
            UIDropDownMenu_SetText(provDropdown, arg1)
            GWB:SaveSettings()
            print("GWB: Set Autopilot Provider to: " .. arg1)
        end
        info.checked = (GWB.Settings.AutopilotProvider == "Zygor")
        UIDropDownMenu_AddButton(info)
    end)
    yOffset = yOffset - 30
    
    local profText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    profText:SetPoint("TOPLEFT", 25, yOffset - 3)
    profText:SetText("Active Profile")

    local profEb = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    profEb:SetSize(100, 20)
    profEb:SetPoint("TOPLEFT", 220, yOffset)
    profEb:SetAutoFocus(false)
    profEb:SetText(tostring(GWB.Settings.ActiveProfile or ""))
    profEb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local txt = self:GetText()
        GWB.Settings.ActiveProfile = txt
        GWB.StorageMgr:Initialize()
        GWB:RebuildConfigUI()
        print("GWB: Loaded profile: " .. (txt == "" and UnitName("player") or txt))
    end)
    
    local profDropdown = CreateFrame("Frame", nil, scrollChild, "UIDropDownMenuTemplate")
    profDropdown:SetPoint("LEFT", profEb, "RIGHT", -15, -2)
    UIDropDownMenu_SetWidth(profDropdown, 120)
    UIDropDownMenu_SetText(profDropdown, "Select Profile...")

    UIDropDownMenu_Initialize(profDropdown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local pathStr = GWB.is_debug and "/scripts/GWB_DEV/storage/*" or "/scripts/GWB/storage/*"
        
        -- Default char profile
        local defName = UnitName("player") or "unknown"
        info.text = "Default (" .. defName .. ")"
        info.arg1 = ""
        info.func = function(self, arg1)
            GWB.Settings.ActiveProfile = arg1
            GWB.StorageMgr:Initialize()
            GWB:RebuildConfigUI()
            print("GWB: Loaded profile: Default")
        end
        UIDropDownMenu_AddButton(info)
        
        -- Enumerate actual files
        if Nn and Nn.ListFiles then
            local files = Nn.ListFiles(pathStr)
            if files then
                for i=1, #files do
                    local fname = files[i]
                    -- Extract profile name from storage_PROFILENAME.json
                    local profName = string.match(fname, "storage_(.+)%.json")
                    if profName and profName ~= defName then
                        info.text = profName
                        info.arg1 = profName
                        info.func = function(self, arg1)
                            GWB.Settings.ActiveProfile = arg1
                            GWB.StorageMgr:Initialize()
                            GWB:RebuildConfigUI()
                            print("GWB: Loaded profile: " .. arg1)
                        end
                        UIDropDownMenu_AddButton(info)
                    end
                end
            end
        end
    end)

    yOffset = yOffset - 30

    elseif GWB.Settings.ActiveTab ~= "Core" then
        -- Plugin Settings
        local pluginName = GWB.Settings.ActiveTab
        local plugin = GWB.plugins[pluginName]
        if plugin and plugin.settings then
            local pHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            pHeader:SetPoint("TOPLEFT", 10, yOffset)
            pHeader:SetText(plugin.name or pluginName)
            yOffset = yOffset - 25

            for settingKey, settingData in pairs(plugin.settings) do
                local label = settingData.label or settingKey
                local value = settingData.value
                local valType = type(value)

                if valType == "boolean" then
                    local chk = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
                    chk:SetSize(24, 24)
                    chk:SetPoint("TOPLEFT", 20, yOffset)
                    chk:SetChecked(value)
                    
                    local text = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    text:SetPoint("LEFT", chk, "RIGHT", 5, 1)
                    text:SetText(label)

                    chk:SetScript("OnClick", function(self)
                        settingData.value = self:GetChecked()
                        GWB:SaveSettings()
                    end)
                    yOffset = yOffset - 25

                elseif valType == "number" then
                    local text = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    text:SetPoint("TOPLEFT", 25, yOffset - 3)
                    text:SetText(label)

                    local eb = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
                    eb:SetSize(50, 20)
                    eb:SetPoint("TOPLEFT", 380, yOffset)
                    eb:SetAutoFocus(false)
                    eb:SetText(tostring(value))
                    eb:SetScript("OnTextChanged", function(self)
                        local num = tonumber(self:GetText())
                        if num then
                            settingData.value = num
                            GWB:SaveSettings()
                        end
                    end)
                    yOffset = yOffset - 25
                end
            end
            yOffset = yOffset - 10
        else
            -- Fallback if plugin deleted
            GWB.Settings.ActiveTab = "Core"
            C_Timer.After(0.01, function() GWB:RebuildConfigUI() end)
        end
    end

    scrollChild:SetHeight(math.abs(yOffset))
end

configFrame:SetScript("OnShow", function()
    GWB:RebuildConfigUI()
end)

function GWB:ToggleConfigUI()
    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end
