local Nn, GWB = ...

-- ===========================================================================
-- Default_RoutinePlayback — Executes a recorded Routine step-by-step
-- ===========================================================================

local plugin = {}
plugin.name    = "RoutinePlayback"
plugin.author  = "GWB"
plugin.cb_priority = GWB.enums.cb_priority.LOW
plugin.callbacks = {}
plugin.handlers  = {}
plugin.settings  = {}

local steps      = {}   -- loaded routine steps
local stepIndex  = 1
local isRunning  = false
local isWaiting  = false  -- true while navigating / waiting for async event
local loadedName = nil

-- Current gossip-replay state
local gossipPending  = nil  -- {optionId} to click when gossip opens
local questPending   = nil  -- "accept" or "complete" to drive quest dialog

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

GWB.RoutinePlayback = {}

function GWB.RoutinePlayback:Load(name)
    local loaded, routineName = GWB.Routine:LoadFromDisk(name)
    if not loaded then
        GWB:Print("RoutinePlayback: failed to load '" .. tostring(name) .. "'")
        return false
    end
    steps      = loaded
    stepIndex  = 1
    loadedName = routineName or name
    GWB:Print(string.format("RoutinePlayback: loaded '%s' (%d steps)", loadedName, #steps))
    return true
end

function GWB.RoutinePlayback:Start()
    if not steps or #steps == 0 then
        GWB:Print("RoutinePlayback: no routine loaded.")
        return
    end
    isRunning = true
    isWaiting = false
    stepIndex = 1
    GWB.State:callState("plugin.RoutinePlayback")
    GWB:Print("RoutinePlayback: started.")
end

function GWB.RoutinePlayback:Stop()
    isRunning = false
    isWaiting = false
    gossipPending = nil
    questPending  = nil
    if GWB.State:getCurrentState() == "plugin.RoutinePlayback" then
        GWB.State:returnState()
    end
    if GWB.EZMover then GWB.EZMover:Stop() end
    GWB:Print("RoutinePlayback: stopped.")
end

function GWB.RoutinePlayback:IsRunning() return isRunning end
function GWB.RoutinePlayback:GetCurrentStep() return steps[stepIndex] end
function GWB.RoutinePlayback:GetStepIndex() return stepIndex end
function GWB.RoutinePlayback:GetTotalSteps() return #steps end

-- Expose on GWB table
GWB.RoutinePlayback = {}
-- (methods above are written after definition block below)

-- ---------------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------------
local function Dist3D(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x2-x1, y2-y1, z2-z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Find the live NPC object closest to a stored position
local function FindNPCByIdNear(npcId, wx, wy, wz, radius)
    radius = radius or 30
    local units = ObjectManager and ObjectManager(5) or Objects()
    local best, bestDist = nil, radius
    for i=1, #units do
        local u = units[i]
        if ObjectExists(u) then
            local id = ObjectUnitId and ObjectUnitId(u) or ObjectId(u)
            if id == npcId then
                local ux, uy, uz = ObjectPosition(u)
                if ux then
                    local d = Dist3D(wx, wy, wz, ux, uy, uz)
                    if d < bestDist then
                        bestDist = d
                        best = u
                    end
                end
            end
        end
    end
    return best
end

-- Advance to next step
local function NextStep()
    stepIndex = stepIndex + 1
    isWaiting = false
    gossipPending = nil
    questPending  = nil
    if stepIndex > #steps then
        -- Routine finished — loop back or stop
        GWB:Print("RoutinePlayback: routine complete! Looping.")
        stepIndex = 1
    end
    -- Notify UI
    if GWB.RecorderUI and GWB.RecorderUI.OnPlaybackStepChanged then
        GWB.RecorderUI.OnPlaybackStepChanged(stepIndex, steps[stepIndex])
    end
end

-- ---------------------------------------------------------------------------
-- Step executors
-- ---------------------------------------------------------------------------

local function ExecWaypoint(step)
    isWaiting = true
    local wx, wy, wz = step.x, step.y, step.z
    local px, py, pz = ObjectPosition("player")
    if not px then isWaiting = false return end

    local dist = Dist3D(px, py, pz, wx, wy, wz)
    if dist < 2.0 then
        NextStep()
        return
    end

    if GWB.Settings.UseEZNavSafe and GWB.EZMover then
        GWB.EZMover:MoveToXYZ(wx, wy, wz)
    else
        GWB.Mover:MoveToXYZ(wx, wy, wz)
    end
    -- OnMovementFinished will advance us
end

local function ExecNPCInteract(step)
    isWaiting = true
    local npc = FindNPCByIdNear(step.npcId, step.x, step.y, step.z)

    if not npc then
        -- NPC not in range yet — walk to recorded coords
        GWB:Debug("RoutinePlayback: NPC", step.npcId, "not found nearby, walking to coords")
        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            GWB.EZMover:MoveToXYZ(step.x, step.y, step.z)
        else
            GWB.Mover:MoveToXYZ(step.x, step.y, step.z)
        end
        -- stateTick will retry once we arrive
        return
    end

    -- Prepare gossip options to replay
    if step.gossipOpts and #step.gossipOpts > 0 then
        gossipPending = step.gossipOpts
    end

    -- Use the distance guard
    GWB.Utils:InteractOrApproach(npc, function(obj)
        ObjectInteract(obj)
        -- if no gossip opts, advance after short delay
        if not gossipPending then
            C_Timer.After(1.5, NextStep)
        end
        -- else: plugin.callbacks.OnGossipStart will handle it
    end, 4.5)
end

local function InteractClosestNpc(step)
    local px, py, pz = ObjectPosition("player")
    if not px then return false end
    local distToStep = math.sqrt((step.x-px)^2 + (step.y-py)^2 + (step.z-pz)^2)
    if distToStep > 5.0 then return false end -- too far, keep walking

    local npcs = ObjectManager(5) or {}
    local closest = nil
    local minDist = 999
    for i=1, #npcs do
        local obj = npcs[i]
        if ObjectExists(obj) then
            local cx, cy, cz = ObjectPosition(obj)
            if cx then
                local dist = math.sqrt((cx-px)^2 + (cy-py)^2 + (cz-pz)^2)
                if dist < minDist then
                    minDist = dist
                    closest = obj
                end
            end
        end
    end

    if closest and minDist < 6.0 then
        ClickToMove(px, py, pz)
        ObjectInteract(closest)
        return true
    end
    return false
end

local function ExecQuestAccept(step)
    isWaiting = true
    questPending = "accept"
    -- The quest accept dialog should already be open if we're at this step
    -- (i.e. previous npc_interact triggered it). If not, find the NPC again.
    if QuestFrame and QuestFrame:IsShown() then
        Nn.Unlock(AcceptQuest)
    else
        -- Walk to the NPC coords
        if InteractClosestNpc(step) then return end

        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            GWB.EZMover:MoveToXYZ(step.x, step.y, step.z)
        else
            GWB.Mover:MoveToXYZ(step.x, step.y, step.z)
        end
    end
end

local function ExecQuestTurnin(step)
    isWaiting = true
    questPending = "complete"
    if QuestFrame and QuestFrame:IsShown() then
        -- click complete / get rewards
        if QuestFrameCompleteButton and QuestFrameCompleteButton:IsShown() then
            Nn.Unlock(QuestFrameCompleteButton.Click, QuestFrameCompleteButton)
        elseif QuestFrameCompleteQuestButton and QuestFrameCompleteQuestButton:IsShown() then
            Nn.Unlock(QuestFrameCompleteQuestButton.Click, QuestFrameCompleteQuestButton)
        end
    else
        if InteractClosestNpc(step) then return end

        if GWB.Settings.UseEZNavSafe and GWB.EZMover then
            GWB.EZMover:MoveToXYZ(step.x, step.y, step.z)
        else
            GWB.Mover:MoveToXYZ(step.x, step.y, step.z)
        end
    end
end

local function ExecWait(step)
    isWaiting = true
    C_Timer.After(step.seconds or 1, NextStep)
end

local function ExecLootObject(step)
    isWaiting = true
    -- Find nearby game objects with matching ID
    local gameObjects = ObjectManager and ObjectManager(8) or Objects()
    local target = nil
    for i=1, #gameObjects do
        local o = gameObjects[i]
        if ObjectExists(o) and ObjectId(o) == step.objectId then
            target = o
            break
        end
    end

    if target then
        GWB.Utils:InteractOrApproach(target, function(obj)
            ObjectInteract(obj)
            C_Timer.After(2.0, NextStep) -- wait for loot window
        end, 4.5)
    else
        -- Walk to coords and try again next tick
        GWB.Mover:MoveToXYZ(step.x, step.y, step.z)
    end
end

-- Dispatch table
local stepExecutors = {
    waypoint     = ExecWaypoint,
    npc_interact = ExecNPCInteract,
    quest_accept = ExecQuestAccept,
    quest_turnin = ExecQuestTurnin,
    wait         = ExecWait,
    loot_object  = ExecLootObject,
}

-- ---------------------------------------------------------------------------
-- stateTick — called by the state machine
-- ---------------------------------------------------------------------------
plugin.handlers.stateTick = function()
    if not isRunning or isWaiting then return end

    local step = steps[stepIndex]
    if not step then
        GWB.RoutinePlayback:Stop()
        return
    end

    GWB:Debug(string.format("RoutinePlayback: step %d/%d [%s]", stepIndex, #steps, step.type))

    local exec = stepExecutors[step.type]
    if exec then
        exec(step)
    else
        GWB:Print("RoutinePlayback: unknown step type '" .. tostring(step.type) .. "', skipping.")
        NextStep()
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

-- When movement to a waypoint coord finishes, advance
plugin.callbacks.OnMovementFinished = function(ctx, moveType, tx, ty, tz)
    if not isRunning or not isWaiting then return false end
    local step = steps[stepIndex]
    if not step then return false end

    if moveType == "xyz" and step.type == "waypoint" then
        NextStep()
        return false
    end

    -- Arrived near recorded NPC coords — retry interact
    if moveType == "xyz" and step.type == "npc_interact" then
        local npc = FindNPCByIdNear(step.npcId, step.x, step.y, step.z, 15)
        if npc then
            if step.gossipOpts and #step.gossipOpts > 0 then
                gossipPending = step.gossipOpts
            end
            GWB.Utils:InteractOrApproach(npc, function(obj)
                ObjectInteract(obj)
                if not gossipPending then
                    C_Timer.After(1.5, NextStep)
                end
            end, 4.5)
        else
            GWB:Debug("RoutinePlayback: NPC", step.npcId, "still not found after arrival — advancing")
            C_Timer.After(2.0, NextStep)
        end
        return false
    end

    return false
end

-- Replay gossip options when a gossip dialog opens
plugin.callbacks.OnGossipStart = function(ctx)
    if not isRunning or not gossipPending then return false end

    local opts = gossipPending
    gossipPending = nil

    -- Humanize a slight delay before clicking
    C_Timer.After(math.random(6, 18) / 10.0, function()
        local available = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()
        if not available then return end

        for _, recorded in ipairs(opts) do
            for _, live in ipairs(available) do
                if live.gossipOptionID == recorded.gossipOptionID then
                    GWB:Debug("RoutinePlayback: selecting gossip option:", live.name)
                    C_GossipInfo.SelectOption(live.gossipOptionID)
                    return
                end
            end
        end
        -- fallback: take first available option
        if #available > 0 then
            GWB:Debug("RoutinePlayback: gossip option not matched, taking first option")
            C_GossipInfo.SelectOption(available[1].gossipOptionID)
        end
    end)
    return false
end

-- Quest accept dialog
plugin.callbacks.OnNewQuestAvailable = function(ctx)
    if not isRunning or questPending ~= "accept" then return false end

    C_Timer.After(math.random(8, 20) / 10.0, function()
        if QuestFrame and QuestFrame:IsShown() then
            if Nn.Unlock then
                Nn.Unlock(AcceptQuest)
            else
                AcceptQuest()
            end
        end
    end)
    return false
end

-- Quest accepted — advance
plugin.callbacks.OnNewQuestStarted = function(ctx, questId)
    if not isRunning then return false end
    local step = steps[stepIndex]
    if step and step.type == "quest_accept" and (step.questId == questId or questId == nil) then
        questPending = nil
        C_Timer.After(0.8, NextStep)
    end
    return false
end

-- Quest turnin dialog
plugin.callbacks.OnQuestTurninStarted = function(ctx)
    if not isRunning or questPending ~= "complete" then return false end

    C_Timer.After(math.random(6, 15) / 10.0, function()
        if QuestFrame and QuestFrame:IsShown() then
            if QuestFrameCompleteButton and QuestFrameCompleteButton:IsShown() then
                if Nn.Unlock then
                    Nn.Unlock(QuestFrameCompleteButton.Click, QuestFrameCompleteButton)
                else
                    QuestFrameCompleteButton:Click()
                end
            end
        end
    end)
    return false
end

-- Quest turned in — advance
plugin.callbacks.OnQuestCompleted = function(ctx, questId)
    if not isRunning then return false end
    local step = steps[stepIndex]
    if step and step.type == "quest_turnin" then
        questPending = nil
        -- pick first reward if any
        C_Timer.After(0.5, function()
            if QuestFrame and QuestFrame:IsShown() then
                local numRewards = GetNumQuestChoices and GetNumQuestChoices() or 0
                if numRewards > 0 then
                    -- Pick highest-quality reward (index 1 is usually best)
                    GetQuestReward(1)
                else
                    GetQuestReward(0)
                end
            end
        end)
        C_Timer.After(2.0, NextStep)
    end
    return false
end

-- Combat pauses playback
plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    if not isRunning then return false end
    isWaiting = true  -- pause execution, don't advance steps
    if GWB.EZMover then GWB.EZMover:Stop() end
    return false
end

plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    if not isRunning then return false end
    -- Resume after a short breather
    C_Timer.After(1.5, function() isWaiting = false end)
    return false
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
GWB.RoutinePlayback = {
    Load    = function(self, name) return GWB.Routine:LoadFromDisk(name) end,
    Start   = function(self) 
        steps, loadedName = GWB.Routine:LoadFromDisk(loadedName or "")
        if not steps then return end
        isRunning = true; isWaiting = false; stepIndex = 1
        GWB.State:callState("plugin.RoutinePlayback")
    end,
    Stop    = function(self)
        isRunning = false; isWaiting = false
        gossipPending = nil; questPending = nil
        if GWB.State:getCurrentState() == "plugin.RoutinePlayback" then
            GWB.State:returnState()
        end
        if GWB.EZMover then GWB.EZMover:Stop() end
    end,
    LoadAndStart = function(self, name, stepsData)
        steps = stepsData
        loadedName = name
        isRunning = true; isWaiting = false; stepIndex = 1
        GWB.State:callState("plugin.RoutinePlayback")
        GWB:Print(string.format("RoutinePlayback: playing '%s' (%d steps)", name, #steps))
    end,
    IsRunning = function(self) return isRunning end,
    GetStepIndex = function(self) return stepIndex end,
    GetTotalSteps = function(self) return #steps end,
    GetCurrentStep = function(self) return steps[stepIndex] end,
}

GWB:RegisterPlugin(plugin)
