local Nn, GWB = ...

-- ===========================================================================
-- GWB.Routine — Records, edits, saves and loads Routine Profiles
-- ===========================================================================

GWB.Routine = {}

local activeSession   = nil  -- steps[] being recorded right now
local loadedSession   = nil  -- steps[] loaded for playback
local sessionName     = nil
local lastWaypointPos = nil  -- {x, y, z} of the last recorded waypoint
local recordTicker    = nil

local WAYPOINT_DISTANCE = 4.5   -- record a waypoint every N yards
local SIMPLIFY_ANGLE    = 8.0   -- degrees; collinear points within this are removed

-- ---------------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------------
local function Dist3D(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x2-x1, y2-y1, z2-z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Angle (degrees) between vectors AB and BC
local function AngleBetween(ax, ay, bx, by, cx, cy)
    local u1, u2 = bx-ax, by-ay
    local v1, v2 = cx-bx, cy-by
    local mag_u = math.sqrt(u1*u1 + u2*u2)
    local mag_v = math.sqrt(v1*v1 + v2*v2)
    if mag_u == 0 or mag_v == 0 then return 0 end
    local dot = u1*v1 + u2*v2
    local cos_a = dot / (mag_u * mag_v)
    cos_a = math.max(-1, math.min(1, cos_a)) -- clamp for acos
    return math.deg(math.acos(cos_a))
end

-- Douglas-Peucker-style collinear simplification on waypoint steps only.
-- Removes intermediate waypoints that deviate < SIMPLIFY_ANGLE degrees.
local function SimplifyWaypoints(steps)
    local out = {}
    local i = 1
    while i <= #steps do
        local s = steps[i]
        if s.type ~= "waypoint" then
            table.insert(out, s)
            i = i + 1
        else
            -- peek ahead: skip s[i+1] if it's collinear with s[i] and s[i+2]
            if i+2 <= #steps and steps[i+1].type == "waypoint" and steps[i+2].type == "waypoint" then
                local a, b, c = s, steps[i+1], steps[i+2]
                local angle = AngleBetween(a.x, a.y, b.x, b.y, c.x, c.y)
                if angle < SIMPLIFY_ANGLE then
                    -- skip the middle waypoint
                    table.insert(out, s)
                    i = i + 2 -- jump over the collinear middle
                else
                    table.insert(out, s)
                    i = i + 1
                end
            else
                table.insert(out, s)
                i = i + 1
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Gossip / Quest helpers for playback (stored in steps at record time)
-- ---------------------------------------------------------------------------
local function CaptureGossipState()
    local opts = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()
    if not opts then return nil end
    local captured = {}
    for _, opt in ipairs(opts) do
        table.insert(captured, {
            gossipOptionID = opt.gossipOptionID,
            name           = opt.name,
            icon           = opt.icon,
            optionType     = opt.type or opt.optionType,
        })
    end
    return captured
end

-- ---------------------------------------------------------------------------
-- Internal: add a step to the active session
-- ---------------------------------------------------------------------------
local function AddStep(stepType, payload)
    if not activeSession then return end
    local step = { type = stepType }
    for k, v in pairs(payload) do step[k] = v end
    table.insert(activeSession, step)
    GWB:Debug("Routine: recorded step", stepType)
    -- Notify UI if open
    if GWB.RecorderUI and GWB.RecorderUI.OnStepAdded then
        GWB.RecorderUI.OnStepAdded(step)
    end
end

-- ---------------------------------------------------------------------------
-- Waypoint polling ticker
-- ---------------------------------------------------------------------------
local function WaypointTick()
    if not activeSession then return end

    local px, py, pz = ObjectPosition("player")
    if not px then return end

    if not lastWaypointPos then
        lastWaypointPos = {x=px, y=py, z=pz}
        local mapId = C_Map.GetBestMapForUnit("player")
        AddStep("waypoint", {x=px, y=py, z=pz, mapId=mapId})
        return
    end

    local dist = Dist3D(lastWaypointPos.x, lastWaypointPos.y, lastWaypointPos.z, px, py, pz)
    if dist >= WAYPOINT_DISTANCE then
        lastWaypointPos = {x=px, y=py, z=pz}
        local mapId = C_Map.GetBestMapForUnit("player")
        AddStep("waypoint", {x=px, y=py, z=pz, mapId=mapId})
    end
end

-- ---------------------------------------------------------------------------
-- GWB callbacks while recording
-- ---------------------------------------------------------------------------
local recordCallbacks = {}

local function GetInteractObj()
    local obj = nil
    if Object then
        obj = Object("npc")
        if not obj or not ObjectExists(obj) or ObjectType(obj) == 0 then
            obj = Object("target")
        end
        if not obj or not ObjectExists(obj) or ObjectType(obj) == 0 then
            obj = Object("mouseover")
        end
    end
    if obj and not ObjectExists(obj) then return nil end
    return obj
end

local function GetObjId(obj)
    if not obj or not ObjectExists(obj) then return 0 end
    local t = ObjectType(obj)
    if t == 5 then return ObjectUnitId(obj) or 0 end
    if t == 8 then return ObjectId(obj) or 0 end
    return 0
end

recordCallbacks.OnGossipStart = function()
    if not activeSession then return end
    local px, py, pz = ObjectPosition("player")
    local mapId = C_Map.GetBestMapForUnit("player")
    -- capture NPC info
    local npcObj = GetInteractObj()
    local npcId   = GetObjId(npcObj)
    local npcName = npcObj and ObjectName(npcObj) or "Unknown"
    -- capture gossip options at this moment
    C_Timer.After(0.3, function()
        local ok, err = pcall(function()
            local gossipOpts = CaptureGossipState()
            AddStep("npc_interact", {
                npcId      = npcId,
                npcName    = npcName,
                x = px, y = py, z = pz,
                mapId      = mapId,
                gossipOpts = gossipOpts,
            })
        end)
        if not ok then GWB:Print("OnGossipStart Timer Error: " .. tostring(err)) end
    end)
end

local function RecordQuestNpcInteract()
    if not activeSession then return end
    local px, py, pz = ObjectPosition("player")
    local mapId = C_Map.GetBestMapForUnit("player")
    local npcObj = GetInteractObj()
    local npcId   = GetObjId(npcObj)
    local npcName = npcObj and ObjectName(npcObj) or "Unknown"
    
    AddStep("npc_interact", {
        npcId      = npcId,
        npcName    = npcName,
        x = px, y = py, z = pz,
        mapId      = mapId,
        gossipOpts = {}, -- Quest dialogs don't have gossip options
    })
end

recordCallbacks.OnNewQuestAvailable = RecordQuestNpcInteract
recordCallbacks.OnQuestTurninStarted = RecordQuestNpcInteract

recordCallbacks.OnNewQuestStarted = function(_, questId)
    if not activeSession then return end
    local questName = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId) or ("Quest " .. tostring(questId))
    local px, py, pz = ObjectPosition("player")
    local mapId = C_Map.GetBestMapForUnit("player")
    AddStep("quest_accept", {
        questId   = questId,
        questName = questName,
        x = px, y = py, z = pz,
        mapId     = mapId,
    })
end

recordCallbacks.OnQuestCompleted = function(_, questId)
    if not activeSession then return end
    local questName = questId and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId) or "Quest"
    local px, py, pz = ObjectPosition("player")
    local mapId = C_Map.GetBestMapForUnit("player")
    AddStep("quest_turnin", {
        questId   = questId or 0,
        questName = questName or "Unknown",
        x = px, y = py, z = pz,
        mapId     = mapId,
    })
end

recordCallbacks.OnMerchantShow = function()
    if not activeSession then return end
    local px, py, pz = ObjectPosition("player")
    local mapId = C_Map.GetBestMapForUnit("player")
    local npcObj  = GetInteractObj()
    local npcId   = GetObjId(npcObj)
    local npcName = npcObj and ObjectName(npcObj) or "Vendor"
    AddStep("npc_interact", {
        npcId    = npcId,
        npcName  = npcName,
        x = px, y = py, z = pz,
        mapId    = mapId,
        isMerchant = true,
    })
end

recordCallbacks.OnLootStarted = function()
    if not activeSession then return end
    local px, py, pz = ObjectPosition("player")
    local mapId = C_Map.GetBestMapForUnit("player")
    
    local obj = GetInteractObj()
    local objId = GetObjId(obj)
    local objName = obj and ObjectName(obj) or "Lootable Object"
    
    -- Try to figure out if it's a corpse or an object
    local isCorpse = false
    if obj then
        if ObjectType(obj) == 10 then isCorpse = true end
        if ObjectType(obj) == 5 and UnitIsDead(obj) then isCorpse = true end
    end
    
    -- We mainly care about recording interactable objects, not every single dead mob
    if not isCorpse and objId ~= 0 then
        AddStep("object_interact", {
            objectId   = objId,
            objectName = objName,
            x = px, y = py, z = pz,
            mapId      = mapId,
        })
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function GWB.Routine:StartRecording(name)
    if activeSession then
        GWB:Print("Routine: already recording — stop first!")
        return
    end
    sessionName     = name or ("routine_" .. date("%Y%m%d_%H%M%S"))
    activeSession   = {}
    lastWaypointPos = nil
    GWB:Print("Routine: recording started — \"" .. sessionName .. "\"")

    -- Start waypoint polling
    recordTicker = C_Timer.NewTicker(0.5, WaypointTick)

    -- Hook GWB callbacks
    for cbName, fn in pairs(recordCallbacks) do
        GWB:FireCallback("__RecorderHook_" .. cbName, fn) -- internal signal
    end
    -- Direct hook via GWB callback system
    GWB._routineRecordCallbacks = recordCallbacks
end

function GWB.Routine:StopRecording()
    if not activeSession then
        GWB:Print("Routine: not recording.")
        return nil
    end

    if recordTicker then
        recordTicker:Cancel()
        recordTicker = nil
    end
    GWB._routineRecordCallbacks = nil

    -- Simplify collinear waypoints
    local simplified = SimplifyWaypoints(activeSession)
    GWB:Print(string.format("Routine: stopped. %d steps recorded (%d after simplification).",
        #activeSession, #simplified))

    local result = simplified
    loadedSession = result
    activeSession = nil
    lastWaypointPos = nil

    return result, sessionName
end

function GWB.Routine:IsRecording()
    return activeSession ~= nil
end

function GWB.Routine:GetCurrentSteps()
    return activeSession or loadedSession or {}
end

function GWB.Routine:GetSessionName()
    return sessionName
end

-- ---------------------------------------------------------------------------
-- Disk operations
-- ---------------------------------------------------------------------------

local function RoutinePath(name)
    local prefix = GWB.is_debug and "/scripts/GWB_DEV" or "/scripts/GWB"
    -- Remove any character name or server info — use only the supplied name
    local safeName = name:gsub("[^%w_%-]", "_")
    return prefix .. "/storage/routine_" .. safeName .. ".json"
end

function GWB.Routine:SaveToDisk(name, steps)
    name  = name or sessionName or "unnamed"
    steps = steps or activeSession or loadedSession or {}

    local simplified = SimplifyWaypoints(steps)
    local payload = {
        name    = name,
        version = 1,
        steps   = simplified,
    }

    local path = RoutinePath(name)
    local json = Nn.Utils.JSON
    if not json then GWB:Print("Routine: JSON not available!") return false end

    local str = json.encode(payload)

    local mkDir = Nn.CreateDirectory or CreateDirectory
    if mkDir then
        local dir = GWB.is_debug and "/scripts/GWB_DEV/storage" or "/scripts/GWB/storage"
        pcall(mkDir, dir)
    end

    local writeFile = Nn.WriteFile or WriteFile
    if not writeFile then GWB:Print("Routine: WriteFile not available!") return false end

    local ok, err = pcall(writeFile, path, str, false)
    if ok then
        GWB:Print("Routine: saved \"" .. name .. "\" to " .. path)
        return true
    else
        GWB:Print("Routine: save failed — " .. tostring(err))
        return false
    end
end

function GWB.Routine:LoadFromDisk(name)
    local path = RoutinePath(name)
    local readFile = Nn.ReadFile or ReadFile
    local fileExists = Nn.FileExists or FileExists

    if not fileExists or not fileExists(path) then
        GWB:Print("Routine: file not found — " .. path)
        return nil
    end

    local str = readFile(path)
    if not str or str == "" then
        GWB:Print("Routine: empty file — " .. path)
        return nil
    end

    local json = Nn.Utils.JSON
    local ok, data = pcall(json.decode, str)
    if not ok or not data or not data.steps then
        GWB:Print("Routine: failed to parse — " .. path)
        return nil
    end

    GWB:Print(string.format("Routine: loaded \"%s\" — %d steps", name, #data.steps))
    loadedSession = data.steps
    return data.steps, data.name
end

function GWB.Routine:ListSaved()
    local prefix = GWB.is_debug and "/scripts/GWB_DEV/storage" or "/scripts/GWB/storage"
    local listFiles = Nn.ListFiles or ListFiles
    if not listFiles then return {} end

    local all = listFiles(prefix .. "/*") or {}
    local routines = {}
    for _, f in ipairs(all) do
        local name = f:match("^routine_(.+)%.json$")
        if name then
            table.insert(routines, name)
        end
    end
    table.sort(routines)
    return routines
end

-- ---------------------------------------------------------------------------
-- Intercept GWB callbacks while recording
-- ---------------------------------------------------------------------------
-- We piggyback on the existing FireCallback system by checking
-- GWB._routineRecordCallbacks on each relevant event dispatch.
local origFireCallback = GWB.FireCallback
if origFireCallback then
    function GWB:FireCallback(cbName, ...)
        -- Dispatch to recorder hooks if active
        if GWB._routineRecordCallbacks then
            local hook = GWB._routineRecordCallbacks[cbName]
            if hook then
                local ok, err = pcall(hook, ...)
                if not ok then GWB:Print("Recorder Hook Error: " .. tostring(err)) end
            end
        end
        return origFireCallback(self, cbName, ...)
    end
end
