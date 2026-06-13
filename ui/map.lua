
local Nn, GWB, map = ...

local DrawLinesAddon = CreateFrame("Frame")
local pointsPerMap = {} -- Stores points for each map
local currentMapID
local lastRemovedPoint = nil
local lastUndo = 0

GWB.Map = {}
GWB.Map.pointsPerMap = pointsPerMap

--GWB.Map.isRunning = false
function GWB.Map:IsRunning() 
    return GWB.State:getCurrentState() == "plugin.Waypoints"
end
function GWB.Map:SetIsRunning(enable)
    -- NOTE: we should walk the stack? and find "plugin.Waypoints?"
    --if not enable and GWB.State:getCurrentState() == "plugin.Waypoints" then
    if not enable then
        for i=#GWB.State.stateStack, 1, -1 do
            print("stateStack[", i, "] = ", GWB.State.stateStack[i])
            if GWB.State.stateStack[i] == "plugin.Waypoints" then
                -- okay, loop again nil all from here on?
                print("Found stack name at", i)
                for j=i, #GWB.State.stateStack do
                    print("erasing at ", j)
                    GWB.State.stateStack[j] = nil
                end
                break
            end
        end
    elseif enable then --and GWB.State:getCurrentState() ~= "plugin.Waypoints" then
        -- NOTE: lets assume user cannot double-enable? hold state in UI?
        -- enable cuz not alrdy active
        GWB.State:callState("plugin.Waypoints")
    end
end

--GWB.plugins = {}

local function Distance(x1, y1, z1, x2, y2, z2)
  --print(x1, y1, z1, x2, y2, z2)
  return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2)
end

-- Create a persistent overlay frame for the dots/lines
local overlayFrame = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
_G.test = overlayFrame
overlayFrame:SetAllPoints()
overlayFrame:SetFrameStrata("HIGH") -- Ensures it's drawn above the map
overlayFrame:SetFrameLevel(10) -- Prevents it from being covered

local function ClearOverlay()
    -- Remove all existing dots and lines?
    --[[
    for _, child in ipairs({overlayFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    ]]

    -- discard the frame as a whole!
    overlayFrame:Hide();
    overlayFrame:SetParent(nil) -- GC me this bruv

    -- pop new one
    overlayFrame = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    overlayFrame:SetAllPoints()
    overlayFrame:SetFrameStrata("HIGH")
    overlayFrame:SetFrameLevel(10)
end

local function DrawDot(x, y)
    local dot = overlayFrame:CreateTexture(nil, "OVERLAY")
    dot:SetColorTexture(0.267, 0.027, 0.52, 1) -- background-light
    dot:SetSize(12, 12)
    dot:SetDrawLayer("OVERLAY", 7) -- Keeps it on top
    dot:SetPoint("CENTER", WorldMapFrame.ScrollContainer.Child, "TOPLEFT", x * WorldMapFrame.ScrollContainer.Child:GetWidth(), -y * WorldMapFrame.ScrollContainer.Child:GetHeight())
    return dot
end

local function DrawLine(x1, y1, x2, y2)
    local line = overlayFrame:CreateLine(nil, "OVERLAY")
    line:SetColorTexture(0.21, 0.023, 0.41, 1) -- background-dark
    line:SetThickness(6)
    line:SetStartPoint("TOPLEFT", WorldMapFrame.ScrollContainer.Child, x1 * WorldMapFrame.ScrollContainer.Child:GetWidth(), -y1 * WorldMapFrame.ScrollContainer.Child:GetHeight())
    line:SetEndPoint("TOPLEFT", WorldMapFrame.ScrollContainer.Child, x2 * WorldMapFrame.ScrollContainer.Child:GetWidth(), -y2 * WorldMapFrame.ScrollContainer.Child:GetHeight())
    return line
end

local function CreateMapButton(name, label, x, y, onClick)
    local button = CreateFrame("Button", name, WorldMapFrame, "UIPanelButtonTemplate")
    button:SetSize(80, 22)
    button:SetText(label)
    button:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", x, y)

    button:SetScript("OnClick", onClick)

    return button
end

local function ClearLines()
    ClearOverlay() -- Remove previous drawings
    if not currentMapID then return end
    pointsPerMap[currentMapID] = {}
end

local function RedrawMapDots()
    ClearOverlay() -- Remove previous drawings
    
    -- skip if nil?
    if not currentMapID then return end

    -- create if not yet existed
    if not pointsPerMap[currentMapID] then 
        pointsPerMap[currentMapID] = {}
    end
    
    local points = pointsPerMap[currentMapID]
    print(string.format("%d dots for mapId %d", #points, currentMapID))

    for i, point in ipairs(points) do
        DrawDot(point.x, point.y)
        if i > 1 then
            DrawLine(points[i-1].x, points[i-1].y, point.x, point.y)
        end
    end
end

local function ConvertMapToWorldCoords(mapID, mapX, mapY)
    if not mapID or not mapX or not mapY then return nil, nil end

    -- Convert the 2D map coordinates to world coordinates
    local mapId, worldPos = C_Map.GetWorldPosFromMapPos(mapID, {x = mapX, y = mapY})

    if worldPos then
        return worldPos.x, worldPos.y
    end

    return nil, nil
end

-- TODO: OnDotRegisterd, to also draw
local function OnMapClick(self, button)
    if IsShiftKeyDown() and button == "LeftButton" then
        local cursorX, cursorY = WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()

        if cursorX and cursorY and cursorX >= 0 and cursorX <= 1 and cursorY >= 0 and cursorY <= 1 then
            local worldX, worldY = ConvertMapToWorldCoords(currentMapID, cursorX, cursorY)

            if worldX and worldY then
                print(string.format("Clicked at: %.2f, %.2f (Map) -> %.2f, %.2f (World)", cursorX * 100, cursorY * 100, worldX, worldY))
            else
                print(string.format("Clicked at: %.2f, %.2f (Map) -> No World Position Available", cursorX * 100, cursorY * 100))
            end
            
            if not pointsPerMap[currentMapID] then
                pointsPerMap[currentMapID] = {}
            end

            local points = pointsPerMap[currentMapID]
            table.insert(points, {x = cursorX, y = cursorY, wx = worldX, wy = worldY, wz = 0})

            DrawDot(cursorX, cursorY)

            if #points > 1 then
                DrawLine(points[#points - 1].x, points[#points - 1].y, cursorX, cursorY)
            end
        end
    end
end

local function OnMapChanged()
    local newMapID = WorldMapFrame:GetMapID()
    if not newMapID or newMapID == currentMapID then return end

    print("Switched to map:", newMapID) -- Debugging output
    currentMapID = newMapID
    lastRemovedPoint = nil -- unset
    RedrawMapDots() -- Load dots for the new map
end

local function OnUndo(revert)
    -- verify ctrl+Z is within context
    if not WorldMapFrame:IsShown() then return end
    if GWB.Map:IsRunning() then return end

    -- must have points ofc
    if not pointsPerMap[currentMapID] then return end

    local points = pointsPerMap[currentMapID]

    if revert then
        if lastRemovedPoint == nil then
            print("Undo (revert) failed, nothing to revert")
            return
        end
        print("Undo (revert)")
        points[#points+1] = lastRemovedPoint
        lastRemovedPoint = nil
        RedrawMapDots()
    else
        print("Undo")
        lastRemovedPoint = points[#points]
        points[#points] = nil
        RedrawMapDots()
    end
end

local function OnMapControlsUpdate()
    local VK_CONTROL = 0x11
    local VK_LSHIFT = 0xA0
    local VK_RSHIFT = 0xA1
    local VK_Z = 0x5A

    local tick = GetTime() * 1000;

    -- wait atleast 1 sec
    if lastUndo + 625 > tick then return end

    -- control down?
    local GetKeyState = Nn.GetKeyState
    if GetKeyState(VK_CONTROL) ~= 0 and GetKeyState(VK_Z) ~= 0 then
        lastUndo = tick;
        
        local undo = GetKeyState(VK_LSHIFT) ~= 0 or GetKeyState(VK_RSHIFT) ~= 0
        OnUndo(undo)
    end
end



-- logic movement??

-- all the logic when scanning nearbys?
function GWB:OnBotScanTick(losCheck)
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        return false -- We already have a valid target! Don't scan!
    end

    local checkLoS = losCheck or true
    local target = nil
    local dist = 30
    local px, py, pz = ObjectPosition("player")

    local old = GetMouseover()
    
    local objects = Objects()
    for i=1, #objects do
        local o = objects[i]
        SetMouseover(o)
        local t = ObjectType(o)
        if t == 5 then -- NPCs
            --print("found NPC", ObjectName(o), "==", UnitCanAttack("player", "mouseover"))
            local _, ctype = UnitCreatureType("mouseover")
            if 
              not UnitIsDeadOrGhost("mouseover") and 
              UnitCanAttack("player", "mouseover") and
              ctype ~= 8 -- Critter type
            then
                local x, y, z = ObjectPosition(o)
                --print(px, py, 0, x, y, 0)
                local d = Distance(px, py, 0, x, y, 0)
                if d < dist then
                    -- LoS, and Z diff?
                    local diffZ = pz - z;

                    local badHeight = diffZ > 30 or diffZ < -30;
                    if not badHeight then
                        local hitX = false
                        if checkLoS then
                            hitX = TraceLine(px, py, pz+1.5, x, y, z+1.5, 0x111)
                            --print("hit?", hitX)
                        end

                        if hitX == false then
                            target = o
                            dist = d
                        end
                    end
                end
            end
        end
    end
    SetMouseover(old)

    if target ~= nil then
        GWB:Debug("found", ObjectName(target), "at", dist, "distance")
        SetMouseover(target)
        Unlock(TargetUnit, "mouseover")
        GWB.targetUnit = target 
    end

    return target ~= nil
end

function GWB:GetPointsForCurrentMap()
    local mapID = C_Map.GetBestMapForUnit("player") or currentMapID
    if not mapID or not pointsPerMap[mapID] then return end

    -- contains .wx and .wy for World XYZ
    return pointsPerMap[mapID]
end

-- TODO: move this crap around for obj?
WorldMapFrame.ScrollContainer:HookScript("OnMouseDown", OnMapClick)
hooksecurefunc(WorldMapFrame, "OnMapChanged", OnMapChanged)
OnMapChanged();
-- listen for the ctrl+Z?
DrawLinesAddon:SetScript("OnUpdate", OnMapControlsUpdate)

-- APIs?
local btnStartToggle
local btnReset
local function OnStartStopToggle()
    pointIndex = 1
    if not GWB.Map:IsRunning() then
        --GWB.Map.isRunning = true
        GWB.Map:SetIsRunning(true)

        btnStartToggle:SetText("Stop")
        local x, y, z = ObjectPosition("player")
        if x then ClickToMove(x, y, z) end
    else
        --GWB.Map.isRunning = false
        GWB.Map:SetIsRunning(false)

        btnStartToggle:SetText("Start")
        -- Halt ALL movement — both EZMover and legacy mover
        if GWB.EZMover then
            GWB.EZMover:Stop()
        end
        if GWB.Mover and GWB.Mover.Stop then 
            GWB.Mover:Stop() 
        end
        -- Force-stop the character physically
        local x, y, z = ObjectPosition("player")
        if x then ClickToMove(x, y, z) end
    end
end

-- #================================#
-- #      Buttons and UI stuff      #
-- #================================#
local function InitializeUI()
    btnReset = CreateMapButton("GWBResetButton", "Reset", 10, -30, function()
        ClearLines()
        --GWB.Map.isRunning = true
        GWB.Map:SetIsRunning(true)
        OnStartStopToggle()
    end)
    btnReset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove all lines for this map", 1, 1, 1)
        GameTooltip:Show()
    end)

    btnReset:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    btnReset:SetFrameStrata("HIGH")
    btnReset:SetFrameLevel(10)

    btnStartToggle = CreateMapButton("GWBStartButton", "Start", 10, -55, function()
        OnStartStopToggle()
    end)
    btnStartToggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Start/Stop", 1, 1, 1)
        GameTooltip:Show()
    end)

    btnStartToggle:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    btnStartToggle:SetFrameLevel(10)

    -- Create Minimap Button
    local minimapBtn = CreateFrame("Button", "GWBMinimapButton", Minimap)
    minimapBtn:SetSize(31, 31)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetFrameLevel(8)
    minimapBtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, -20)

    local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01") -- Gear icon
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER", minimapBtn, "CENTER", 0, 0)

    local border = minimapBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 0, 0)

    minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            OnStartStopToggle()
        elseif button == "RightButton" then
            if GWB.ToggleConfigUI then
                GWB:ToggleConfigUI()
            else
                print("GWB Config UI not loaded!")
            end
        end
    end)
    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if GWB.Map:IsRunning() then
            GameTooltip:SetText("GWB: Running\nLeft-Click to Stop\nRight-Click for Settings", 0, 1, 0)
        else
            GameTooltip:SetText("GWB: Stopped\nLeft-Click to Start\nRight-Click for Settings", 1, 0, 0)
        end
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end
InitializeUI()

-- TODO: export? kinda only need to get those dots
local map = {
    GetPointsForCurrentMap = GWB.GetPointsForCurrentMap
}

GWB.map = map