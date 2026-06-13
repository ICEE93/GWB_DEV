local Nn, GWB, StorageMgr = ...

GWB.StorageMgr = {}

function GWB.StorageMgr:SaveStorageToDisk()
    if not GWB.Storage then GWB.Storage = {} end
    local str = Nn.Utils.JSON.encode(GWB.Storage)
    local path = GWB.StorageMgr:GenerateStoragePath()

    if Nn.CreateDirectory then
        if GWB.is_debug then
            Nn.CreateDirectory("/scripts/GWB_DEV/storage")
        else
            Nn.CreateDirectory("/scripts/GWB/storage")
        end
    elseif CreateDirectory then
        if GWB.is_debug then
            CreateDirectory("/scripts/GWB_DEV/storage")
        else
            CreateDirectory("/scripts/GWB/storage")
        end
    end

    local success, err
    if Nn.WriteFile then
        success, err = pcall(Nn.WriteFile, path, str, false)
    elseif WriteFile then
        success, err = pcall(WriteFile, path, str, false)
    end
    
    if not success then
        GWB:Print("Failed to write config: " .. tostring(err))
    end
end

function GWB.StorageMgr:GenerateStoragePath()
    local a = ""
    if GWB.Settings and GWB.Settings.ActiveProfile and GWB.Settings.ActiveProfile ~= "" then
        a = GWB.Settings.ActiveProfile
    else
        a = UnitName("player") or "unknown"
    end
    -- TODO: file check "storage" exists!!
    if GWB.is_debug then
        return "/scripts/GWB_DEV/storage/storage_" .. a .. ".json"
    else
        return "/scripts/GWB/storage/storage_" .. a .. ".json"
    end
end

function GWB.StorageMgr:Initialize()
    -- save to disk?
    local json = Nn.Utils.JSON
    local path = GWB.StorageMgr:GenerateStoragePath() --Bot.Config.jsonSavePath
    GWB:Debug("Reading ", path)

    if json ~= nil then
        --ReadFile() -- TODO: deserialize?
        local loaded = false
        if FileExists(path) then
            GWB:Print("Loading existing storage...")
            -- read it
            local loadStr = ReadFile(path)
            local s, res = pcall(json.decode, loadStr)
            if s then
                GWB.Storage = res
                --GWB.Config.jsonSavePath = path
                loaded = true
                GWB:Debug("Storage OK!")
            end
        end
        
        -- not always loaded?
        if not loaded then
            -- else, create one
            GWB.StorageMgr:SaveStorageToDisk()
        end
    end
end

GWB.StorageMgr:Initialize()