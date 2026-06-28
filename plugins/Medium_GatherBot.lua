local Nn, GWB = ...

local plugin = {}
plugin.name = "GatherBot"
plugin.xpacs = "classic|retail" 
plugin.author = "AI"

plugin.settings = {
    ["enable_gathering"] = {
        ["label"] = "Enable GatherBot",
        ["value"] = true,
    },
    ["gather_mining"] = {
        ["label"] = "Gather Mining Nodes",
        ["value"] = true,
    },
    ["gather_herbalism"] = {
        ["label"] = "Gather Herbs",
        ["value"] = true,
    },
    ["gather_distance"] = {
        ["label"] = "Max Gather Distance",
        ["value"] = 100,
    },
    ["interact_range"] = {
        ["label"] = "Interact Range",
        ["value"] = 4.5,
    }
}

plugin.cb_priority = GWB.enums.cb_priority.LOW
plugin.callbacks = {}
plugin.handlers = {
    stateTick = function()
        -- GWB.State expects this to exist when popped
    end
}

local tickerNameGather = plugin.name .. "_tickGather"
local targetNode = nil
local isGathering = false
local lastGatherAttempt = 0
local blacklist = {} -- node ID -> timestamp

local miningNodes = {
    "Copper Vein", "Tin Vein", "Silver Vein", "Iron Deposit", "Gold Vein", "Mithril Deposit", "Truesilver Deposit", 
    "Small Thorium Vein", "Rich Thorium Vein", "Fel Iron Deposit", "Adamantite Deposit", "Khorium Vein", 
    "Cobalt Node", "Saronite Node", "Titanium Node", "Obsidium Node", "Elementium Node", "Pyrite Node"
}

local herbNodes = {
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Swiftthistle", "Bruiseweed", "Wild Steelbloom",
    "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom",
    "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil",
    "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus"
}

-- Quick lookup tables
local isMiningNode = {}
for _, v in ipairs(miningNodes) do isMiningNode[string.lower(v)] = true end

local isHerbNode = {}
for _, v in ipairs(herbNodes) do isHerbNode[string.lower(v)] = true end

local function distance3D(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function GetTooltipText(obj)
    if not obj then return "" end
    Nn.SetMouseover(obj)
    local text = ""
    
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local tt = C_TooltipInfo.GetUnit("mouseover")
        if tt and tt.lines then
            for _, line in ipairs(tt.lines) do
                if line.leftText then text = text .. " " .. string.lower(line.leftText) end
                if line.rightText then text = text .. " " .. string.lower(line.rightText) end
            end
        end
    end
    
    if text == "" and _G.GameTooltipTextLeft1 then
        for i = 1, 5 do
            local left = _G["GameTooltipTextLeft"..i]
            if left and left:GetText() then text = text .. " " .. string.lower(left:GetText()) end
        end
    end
    return text
end

local function IsGatherable(obj)
    if not ObjectExists(obj) then return false end
    
    local name = ObjectName(obj)
    if not name or name == "Unknown" then return false end
    name = string.lower(name)
    
    local wantMining = plugin.settings.gather_mining.value
    local wantHerb = plugin.settings.gather_herbalism.value

    -- 1. Name database match
    if wantMining and isMiningNode[name] then return true end
    if wantHerb and isHerbNode[name] then return true end

    -- 2. Tooltip scan match (for unknown/new nodes)
    local ttText = GetTooltipText(obj)
    if wantMining and (string.find(ttText, "requires mining") or string.find(ttText, "mining")) then return true end
    if wantHerb and (string.find(ttText, "requires herbalism") or string.find(ttText, "herbalism")) then return true end

    return false
end

-- Filter and find nearest node
local function FindNearestNode()
    local px, py, pz = ObjectPosition("player")
    if not px then return nil end

    local gameObjects = ObjectManager(8) or {}
    local bestNode = nil
    local bestDist = plugin.settings.gather_distance.value

    for i = 1, #gameObjects do
        local obj = gameObjects[i]
        if ObjectExists(obj) then
            local objId = ObjectId(obj)
            if objId and not (blacklist[objId] and GetTime() - blacklist[objId] < 60) then
                local tx, ty, tz = ObjectPosition(obj)
                if tx then
                    local dist = distance3D(px, py, pz, tx, ty, tz)
                    if dist < bestDist then
                        if IsGatherable(obj) then
                            bestDist = dist
                            bestNode = obj
                        end
                    end
                end
            end
        end
    end

    return bestNode
end

local function tickGather()
    if not plugin.settings.enable_gathering.value then return end

    -- Yield to combat handler
    if UnitAffectingCombat("player") or (UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")) then 
        isGathering = false
        if GWB.State:getCurrentState() == "plugin.GatherBot" then
            GWB.State:callState("plugin.CombatHandler")
        end
        return 
    end

    -- Skip if dead or casting
    if UnitIsDeadOrGhost("player") or UnitCastingInfo("player") or UnitChannelInfo("player") then
        return
    end

    local px, py, pz = ObjectPosition("player")
    if not px then return end

    -- Find a node if we don't have one or current is invalid
    if not targetNode or not ObjectExists(targetNode) then
        targetNode = FindNearestNode()
        isGathering = false
        if not targetNode then
            if GWB.State:getCurrentState() == "plugin.GatherBot" then
                GWB.State:returnState()
            end
            return
        end
    end

    if targetNode and ObjectExists(targetNode) then
        -- Push state if we found something and aren't active
        if GWB.State:getCurrentState() ~= "plugin.GatherBot" then
            GWB.State:callState("plugin.GatherBot")
            return
        end

        local tx, ty, tz = ObjectPosition(targetNode)
        local dist = distance3D(px, py, pz, tx, ty, tz)

        if dist > plugin.settings.interact_range.value then
            -- Move to node
            if GWB.Settings.UseEZNavSafe and GWB.EZMover then
                if not GWB.EZMover:IsMoving() or not isGathering then
                    GWB.EZMover:MoveToXYZ(tx, ty, tz)
                    isGathering = true
                end
            else
                if not GWB.Mover:IsMoving() or not isGathering then
                    GWB.Mover:MoveToXYZ(tx, ty, tz)
                    isGathering = true
                end
            end
        else
            -- We are in range, stop moving and interact
            if GWB.EZMover:IsMoving() then
                GWB.EZMover:Stop()
            end
            
            if GetTime() - lastGatherAttempt > 1.5 then
                -- Interact with node
                ObjectInteract(targetNode)
                lastGatherAttempt = GetTime()
                
                -- Blacklist after a few attempts so we don't get stuck
                if not blacklist[ObjectId(targetNode)] then
                    blacklist[ObjectId(targetNode)] = GetTime()
                end
            end
        end
    end
end

plugin.callbacks.OnMovementFinished = function(ctx, type, ...)
    if GWB.State:getCurrentState() ~= "plugin.GatherBot" then return false end
    
    if targetNode and type == "xyz" then
        local tx, ty, tz = ObjectPosition(targetNode)
        local px, py, pz = ObjectPosition("player")
        if tx and px and distance3D(px, py, pz, tx, ty, tz) <= plugin.settings.interact_range.value then
            ObjectInteract(targetNode)
            lastGatherAttempt = GetTime()
            return true
        end
    end
    return false
end

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    if GWB.State:getCurrentState() == "plugin.GatherBot" then
        if GWB.EZMover:IsMoving() then
            GWB.EZMover:Stop()
        end
        GWB.State:callState("plugin.CombatHandler")
        return true
    end
    return false
end

local function OnLoad()
    GWB:Print("Medium_GatherBot loaded")
end

GWB:RegisterTicker(tickerNameGather, tickGather)
GWB:RegisterPlugin(plugin)

OnLoad()
