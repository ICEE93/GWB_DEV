local Nn = ...
local GWB = {}

GWB.is_debug = true
GWB.color_primary = "da92b4"
GWB.color_secondary = "cfa0d6"
GWB.color_back_light = "f7eef5"
GWB.color_back_dark = "2b1e2a"

local loadstring = _G.loadstring
local sprint = string.format

function GWB:Require(path, ...)
    local src = Nn.ReadFile(path)
    if src == nil then
        GWB:Print(sprint("GWB:Require failed on \"%s\"", path))
    end
    local f, err = loadstring(src)
    if not f then error(err) end
    --setfenv(f, Nn)
    f(Nn, GWB, ...)
end

function GWB:Print(...)
	print("|cff" .. GWB.color_primary  .. "[GWB]|r", ...)
end

function GWB:Debug(...)
	if not self.is_debug then return end
	print("|cff" .. GWB.color_secondary  .. "[GWB]|r", ...)
end

GWB:Print("Loading lua...")
GWB.plugins = {}

local prefix = "GWB"
if GWB.is_debug then prefix = prefix .. "_DEV" end

local filePath = "/scripts/" .. prefix .. "/"

_G.GWB = GWB -- eeh debug?

GWB:Require(filePath .. "core/utils.lua")
GWB:Require(filePath .. "core/enums.lua")
GWB:Require(filePath .. "core/callbackManager.lua")
GWB:Require(filePath .. "core/storage.lua") 
GWB:Require(filePath .. "core/storageManager.lua")

GWB:Require(filePath .. "core/EZNavSafe.lua")

GWB:Require(filePath .. "core/mover.lua")
GWB:Require(filePath .. "core/dragon.lua")
GWB:Require(filePath .. "core/engine.lua")
GWB:Require(filePath .. "core/navigation.lua")
GWB:Require(filePath .. "core/objectManager.lua")

GWB:Require(filePath .. "ui/map.lua")
GWB:Require(filePath .. "ui/settings.lua")

GWB:Require(filePath .. "core/inventoryManager.lua")
GWB:Require(filePath .. "core/stateManager.lua")
GWB:Require(filePath .. "core/routineManager.lua")
GWB:Require(filePath .. "ui/recorder.lua")

-- Classic Data
GWB:Require(filePath .. "database/classic/data.lua")

-- Helper function to get current game expansion
local function GetCurrentExpansion()
    local buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo, currentVersion = GetBuildInfo()
    if not interfaceVersion then return "unknown" end

    -- Retail interface versions are typically 100000+ (e.g., 100200 for Dragonflight, 115000 for The War Within)
    -- Classic interface versions are typically 10000-12000 range
    -- TBC Classic: 20000-21000
    -- WotLK Classic: 30000-31000
    -- Cata Classic: 40000-41000

    if interfaceVersion >= 100000 then
        return "retail"
    elseif interfaceVersion >= 40000 then
        return "cata"
    elseif interfaceVersion >= 30000 then
        return "wotlk"
    elseif interfaceVersion >= 20000 then
        return "tbc"
    elseif interfaceVersion >= 10000 then
        return "classic"
    else
        return "unknown"
    end
end

local currentExpansion = GetCurrentExpansion()

-- Helper function to check if plugin should load for current expansion
local function ShouldLoadPlugin(pluginXpacs)
    if not pluginXpacs or pluginXpacs == "" then
        return true -- Load if no xpacs specified (works on all versions)
    end

    -- Parse the xpacs string (e.g., "classic|tbc|wotlk|cata")
    for xpac in string.gmatch(pluginXpacs, "[^|]+") do
        if xpac == currentExpansion then
            return true
        end
    end

    -- Plugin has xpacs specified but doesn't match current expansion
    return false
end

-- load all plugins
local plugins = Nn.ListFiles(filePath .. "plugins/*")
for i=1, #plugins do
    local plugin = plugins[i]
    if plugin ~= "." and plugin ~= ".." and string.match(plugin, "%.lua$") then
        local path = filePath .. "plugins/" .. plugin

        -- Load plugin to check xpacs field
        local pluginSrc = Nn.ReadFile(path)
        if pluginSrc then
            -- Extract plugin.xpacs from source
            local xpacsMatch = pluginSrc:match('plugin%.xpacs%s*=%s*["\']([^"\']+)["\']')
            if xpacsMatch and not ShouldLoadPlugin(xpacsMatch) then
                GWB:Print("Skipping plugin", plugin, "(xpacs:", xpacsMatch, "does not match current expansion:", currentExpansion .. ")")
            else
                GWB:Print("Loading plugin", plugin)
                local data, err = pcall(GWB.Require, GWB, path)
                if not data then
                    GWB:Print("Failed loading", plugin, "with err:", err)
                end
            end
        else
            GWB:Print("Failed to read plugin file", plugin)
        end
    end
end

GWB:Print("Loaded!");
GWB:Debug("Test!");

-- load all modules
local modules = Nn.ListFiles(filePath .. "modules/*")
for i=1, #modules do
    local m = modules[i]
    if m ~= "." and m ~= ".." and string.match(m, "%.lua$") then
        GWB:Debug("Loading module", m)
        local path = filePath .. "modules/" .. m
        local data, err = pcall(GWB.Require, GWB, path)
        if not data then
            GWB:Print("Failed loading module", m, "with err:", err)
        end
    end
end

-- Start a module?
for k, v in pairs(GWB.Modules.modules) do
    --print("Module", k, v.name, v.PlayerCanUse())
    if v.group == "Leveling" and v.PlayerCanUse() then
        v.OnLoad()
    end
end

_G.GWB = GWB

-- Pre-load settings on initialization so saved variables like Autopilot apply immediately
C_Timer.After(1.0, function()
    if GWB.LoadSettings then
        GWB:LoadSettings()
        GWB:Print("Settings loaded from storage.")
    end
end)
