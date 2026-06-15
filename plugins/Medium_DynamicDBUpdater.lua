local Nn, GWB = ...

local plugin = {}
plugin.name = "DynamicDBUpdater"
plugin.xpacs = ""
plugin.author = "Antigravity"
plugin.cb_priority = GWB.enums.cb_priority.DEFAULT
plugin.callbacks = {}
plugin.handlers = {}

local prefix = "GWB"
if GWB.is_debug then prefix = prefix .. "_DEV" end
local OVERRIDES_FILE = "/scripts/" .. prefix .. "/db_overrides.json"

local overrides = {
    repairs = {},
    goods = {},
    trainers = {}
}

-- Load overrides from disk and apply to in-memory databases
local function LoadOverrides()
    if not Nn.FileExists(OVERRIDES_FILE) then
        return
    end

    local content = Nn.ReadFile(OVERRIDES_FILE)
    if not content or content == "" then
        return
    end

    local success, data = pcall(Nn.Utils.JSON.decode, content)
    if not success or type(data) ~= "table" then
        GWB:Print("DynamicDBUpdater: Failed to parse db_overrides.json")
        return
    end

    overrides = data
    overrides.repairs = overrides.repairs or {}
    overrides.goods = overrides.goods or {}
    overrides.trainers = overrides.trainers or {}

    -- Merge repairs
    if GWB.repairs then
        for mapIdStr, npcMap in pairs(overrides.repairs) do
            local mapId = tonumber(mapIdStr) or mapIdStr
            GWB.repairs[mapId] = GWB.repairs[mapId] or {}
            for npcIdStr, coord in pairs(npcMap) do
                local npcId = tonumber(npcIdStr) or npcIdStr
                local found = false
                for _, entry in ipairs(GWB.repairs[mapId]) do
                    if entry.id == npcId then
                        entry.coord = coord
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(GWB.repairs[mapId], { id = npcId, coord = coord })
                end
            end
        end
    end

    -- Merge goods
    if GWB.goods then
        for mapIdStr, npcMap in pairs(overrides.goods) do
            local mapId = tonumber(mapIdStr) or mapIdStr
            GWB.goods[mapId] = GWB.goods[mapId] or {}
            for npcIdStr, coord in pairs(npcMap) do
                local npcId = tonumber(npcIdStr) or npcIdStr
                local found = false
                for _, entry in ipairs(GWB.goods[mapId]) do
                    if entry.id == npcId then
                        entry.coord = coord
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(GWB.goods[mapId], { id = npcId, coord = coord, lvl = 1 })
                end
            end
        end
    end

    -- Merge trainers
    if GWB.DB and GWB.DB.classic and GWB.DB.classic.trainers then
        for class, mapData in pairs(overrides.trainers) do
            GWB.DB.classic.trainers[class] = GWB.DB.classic.trainers[class] or {}
            for mapIdStr, npcMap in pairs(mapData) do
                local mapId = tonumber(mapIdStr) or mapIdStr
                GWB.DB.classic.trainers[class][mapId] = GWB.DB.classic.trainers[class][mapId] or {}
                for npcIdStr, coord in pairs(npcMap) do
                    local npcId = tonumber(npcIdStr) or npcIdStr
                    local found = false
                    for _, entry in ipairs(GWB.DB.classic.trainers[class][mapId]) do
                        if entry.id == npcId then
                            entry.coord = coord
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(GWB.DB.classic.trainers[class][mapId], { id = npcId, coord = coord, lvl = 1 })
                    end
                end
            end
        end
    end

    GWB:Print("DynamicDBUpdater: Successfully merged database overrides from disk")
end

-- Save overrides to disk
local function SaveOverrides()
    local success, jsonStr = pcall(Nn.Utils.JSON.encode, overrides)
    if success and jsonStr then
        Nn.WriteFile(OVERRIDES_FILE, jsonStr, false)
    else
        GWB:Print("DynamicDBUpdater: Failed to save overrides to disk")
    end
end

-- Scan surrounding NPCs
local lastScanTime = 0
local function ScanNPCs()
    local now = GetTime()
    if now - lastScanTime < 2.0 then
        return
    end
    lastScanTime = now

    local mapId = C_Map.GetBestMapForUnit("player")
    if not mapId then return end

    local units = Nn.ObjectManager(5) or {}
    local changed = false

    for i = 1, #units do
        local unit = units[i]
        if Nn.ObjectExists(unit) then
            local npcFlags = Nn.NPCFlags(unit) or 0
            if npcFlags > 0 then
                local npcId = Nn.ObjectUnitId(unit)
                local name = Nn.ObjectName(unit)
                local x, y, z = Nn.ObjectPosition(unit)

                if npcId and name and x and y and z then
                    -- Round coords to 2 decimals
                    local coord = {
                        x = math.floor(x * 100 + 0.5) / 100,
                        y = math.floor(y * 100 + 0.5) / 100,
                        z = math.floor(z * 100 + 0.5) / 100
                    }

                    -- Repair flag: 0x1000 or 0x4000
                    local isRepair = bit.band(npcFlags, 0x1000) ~= 0 or bit.band(npcFlags, 0x4000) ~= 0
                    -- Vendor flag: 0x4
                    local isVendor = bit.band(npcFlags, 0x04) ~= 0
                    -- Trainer flag: 0x10
                    local isTrainer = bit.band(npcFlags, 0x10) ~= 0

                    -- 1. Repair NPC Updates
                    if isRepair and GWB.repairs then
                        GWB.repairs[mapId] = GWB.repairs[mapId] or {}
                        local found = false
                        for _, entry in ipairs(GWB.repairs[mapId]) do
                            if entry.id == npcId then
                                if math.abs(entry.coord.x - coord.x) > 0.5 or math.abs(entry.coord.y - coord.y) > 0.5 then
                                    entry.coord = coord
                                    changed = true
                                    GWB:Print("DynamicDBUpdater: Updated Repair NPC", name, "coord:", coord.x, coord.y)
                                end
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(GWB.repairs[mapId], { id = npcId, coord = coord })
                            changed = true
                            GWB:Print("DynamicDBUpdater: Added new Repair NPC", name, "coord:", coord.x, coord.y)
                        end

                        -- Save in local overrides table
                        overrides.repairs[tostring(mapId)] = overrides.repairs[tostring(mapId)] or {}
                        overrides.repairs[tostring(mapId)][tostring(npcId)] = coord
                    end

                    -- 2. Vendor NPC Updates
                    if isVendor and GWB.goods then
                        GWB.goods[mapId] = GWB.goods[mapId] or {}
                        local found = false
                        for _, entry in ipairs(GWB.goods[mapId]) do
                            if entry.id == npcId then
                                if math.abs(entry.coord.x - coord.x) > 0.5 or math.abs(entry.coord.y - coord.y) > 0.5 then
                                    entry.coord = coord
                                    changed = true
                                    GWB:Print("DynamicDBUpdater: Updated Vendor NPC", name, "coord:", coord.x, coord.y)
                                end
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(GWB.goods[mapId], { id = npcId, coord = coord, lvl = 1 })
                            changed = true
                            GWB:Print("DynamicDBUpdater: Added new Vendor NPC", name, "coord:", coord.x, coord.y)
                        end

                        -- Save in local overrides table
                        overrides.goods[tostring(mapId)] = overrides.goods[tostring(mapId)] or {}
                        overrides.goods[tostring(mapId)][tostring(npcId)] = coord
                    end

                    -- 3. Trainer NPC Updates
                    if isTrainer and GWB.DB and GWB.DB.classic and GWB.DB.classic.trainers then
                        -- Determine target class
                        local targetClass = nil
                        local lowerName = string.lower(name)
                        local classes = { "rogue", "warlock", "warrior", "hunter", "mage", "priest", "druid", "paladin", "shaman" }
                        for _, c in ipairs(classes) do
                            if lowerName:find(c) then
                                targetClass = string.upper(c)
                                break
                            end
                        end

                        -- Fallback to player's class
                        if not targetClass then
                            targetClass = select(2, UnitClass("player"))
                        end

                        if targetClass then
                            GWB.DB.classic.trainers[targetClass] = GWB.DB.classic.trainers[targetClass] or {}
                            GWB.DB.classic.trainers[targetClass][mapId] = GWB.DB.classic.trainers[targetClass][mapId] or {}
                            local found = false
                            for _, entry in ipairs(GWB.DB.classic.trainers[targetClass][mapId]) do
                                if entry.id == npcId then
                                    if math.abs(entry.coord.x - coord.x) > 0.5 or math.abs(entry.coord.y - coord.y) > 0.5 then
                                        entry.coord = coord
                                        changed = true
                                        GWB:Print("DynamicDBUpdater: Updated Trainer NPC", name, "for class", targetClass, "coord:", coord.x, coord.y)
                                    end
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                table.insert(GWB.DB.classic.trainers[targetClass][mapId], { id = npcId, coord = coord, lvl = 1 })
                                changed = true
                                GWB:Print("DynamicDBUpdater: Added new Trainer NPC", name, "for class", targetClass, "coord:", coord.x, coord.y)
                            end

                            -- Save in local overrides table
                            overrides.trainers[targetClass] = overrides.trainers[targetClass] or {}
                            overrides.trainers[targetClass][tostring(mapId)] = overrides.trainers[targetClass][tostring(mapId)] or {}
                            overrides.trainers[targetClass][tostring(mapId)][tostring(npcId)] = coord
                        end
                    end
                end
            end
        end
    end

    if changed then
        SaveOverrides()
    end
end

-- Initialize plugin
local function OnLoad()
    LoadOverrides()
    GWB:RegisterTicker("DynamicDBUpdater", ScanNPCs)
    GWB:TickerSetState("DynamicDBUpdater", true)
end

GWB:RegisterPlugin(plugin)
OnLoad()
