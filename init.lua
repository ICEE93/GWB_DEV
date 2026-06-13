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

-- load all plugins
local plugins = Nn.ListFiles(filePath .. "plugins/*")
for i=1, #plugins do
    local plugin = plugins[i]
    if plugin ~= "." and plugin ~= ".." and string.match(plugin, "%.lua$") then
        GWB:Print("Loading plugin", plugin)
        local path = filePath .. "plugins/" .. plugin
        local data, err = pcall(GWB.Require, GWB, path)
        if not data then
            GWB:Print("Failed loading", plugin, "with err:", err)
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
