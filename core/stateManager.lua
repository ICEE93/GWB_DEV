local Nn, GWB, stateMgr = ...

GWB.State = {}

--[[

This is the main logic control flow components that will decide
which routines, plugins, or whatever will get executed.

There will be ZERO logic inside on when a state should change.
All state-change related logic should come from anywhere else,
plz do not put logic states in here, isolate them into plugins

- Mode, this is Top level states, to indicate global actions
- - Quester, goto_town, take_quests, goto_poi, waypoints
- Module, tasks, can be interruptable and overwritable (to achieve the task)
- - roam, combat, regen
- Action, multi-step actions 
- - movement stuff etc?

]]

--GWB.State.currentState = "idle" -- root state
GWB.State.stateStack = { "idle" } -- add root state?

function GWB.State:callState(newState)
    if #GWB.State.stateStack > 200 then
        print("EWAAA THIS IS TOO MUCH STATE CALLS???A")
    end
    GWB.State.stateStack[#GWB.State.stateStack+1] = newState
    return true
end

function GWB.State:returnState()
    if #GWB.State.stateStack == 1 then return false end
    local prev_state = GWB.State.stateStack[#GWB.State.stateStack-1]
    GWB.State.stateStack[#GWB.State.stateStack] = nil -- unset current?
    return true
end

function GWB.State:getCurrentState()
    return GWB.State.stateStack[#GWB.State.stateStack]
end
-- eh, start DebugState?
--GWB.State.currentState = "plugin.TownHandler"
--GWB.State:callState("plugin.TownHandler") -- TEST

function GWB.State:GetStatePluginName()
    local state = GWB.State:getCurrentState()
    local rest = state:match("^plugin%.(.*)")
    return rest 
end


local function tick()
    local state = GWB.State:getCurrentState()

    if state == "idle" then 
        -- make sure to stop moving? actually... we want to move?
        if GWB.Mover:IsMoving() then
            GWB.Mover:Stop()
        end
        return 
    end

    --print("State[", #GWB.State.stateStack, "]: ", GWB.State:getCurrentState())
    
    
    local statePluginName = GWB.State:GetStatePluginName();
    if statePluginName then
        local plugin = GWB.plugins[statePluginName]
        if plugin == nil then
            GWB:Debug("Err, plugin", statePluginName, "not loaded or active!")
            return
        end

        local handlers = plugin.handlers
        if handlers == nil then
            GWB:Debug("Err, no handlers found on", statePluginName)
        end
        local tickFn = plugin.handlers.stateTick
        if tickFn == nil then
            GWB:Debug("Err, handlers.stateTick NOT found on", statePluginName, "state!!!")
            return
        end

        -- hmm
        --print("calling tickFn", tickFn)
        local next_state = tickFn()

        -- nil means not finished!
        if next_state == nil then return end

        local retState = type(next_state) == "boolean" and next_state == true
        if retState then
            -- consume and return to previous state
            print("!NextState.pop ", GWB.State:getCurrentState(), "->", next_state)
            --GWB.State.currentState = next_state
            GWB.State:returnState()
        end

        if type(next_state) == "string" then
            -- we "call" into the new one
            if next_state then
                print("!NextState.call ", GWB.State:getCurrentState(), "->", next_state)
                --GWB.State.currentState = next_state
                GWB.State:callState(next_state)
            end
        end
    else
        print("State not found, unk state plugin. ?")
    end
end

local tickerName = "System.State.Tick"
GWB:RegisterTicker(tickerName, tick)
GWB:TickerSetState(tickerName, true)
