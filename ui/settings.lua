local Nn, GWB = ...

-- Ensure global settings table exists
GWB.Settings = GWB.Settings or {}
if GWB.Settings.UseEZNavSafe == nil then
    GWB.Settings.UseEZNavSafe = false
end
if GWB.Settings.ActiveProfile == nil then
    GWB.Settings.ActiveProfile = ""
end

local configFrame = CreateFrame("Frame", "GWBConfigFrame", UIParent, "BasicFrameTemplateWithInset")
configFrame:SetSize(480, 500)
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

local scrollFrame = CreateFrame("ScrollFrame", "GWBConfigScrollFrame", configFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 10, -30)
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
    -- also clear font strings
    local regions = {scrollChild:GetRegions()}
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "FontString" then
            region:Hide()
            region:SetParent(nil)
        end
    end

    local yOffset = -10

    -- Core Settings First
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
    
    local profDropdown = CreateFrame("Frame", "GWBProfDD", scrollChild, "UIDropDownMenuTemplate")
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

    -- Plugin Settings
    for pluginName, plugin in pairs(GWB.plugins) do
        if plugin.settings then
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
