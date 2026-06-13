local Nn, GWB, engine = ...

-- ============================================================================
-- Engine: central event frame + callback dispatcher
-- ============================================================================

GWB.engine = GWB.engine or {}
local engine = GWB.engine

-- One frame to rule them all
local frame = CreateFrame("Frame")
engine.frame = frame

-- Safety: ensure plugin registry exists
GWB.plugins = GWB.plugins or {}

GWB._reg_counter = GWB._reg_counter or 0

function GWB:RegisterPlugin(plugin)
    GWB._reg_counter = GWB._reg_counter + 1
    plugin._reg_index = GWB._reg_counter
    GWB.plugins[plugin.name] = plugin
end

-- Helper: iterate all registered plugins
local function ForEachPlugin(fn)
    for _, plugin in pairs(GWB.plugins) do
        --print(plugin, plugin,callbacks)
        if plugin and plugin.callbacks then
            fn(plugin)
        end
    end
end

-- Helper: safe-call a callback (never break the event loop)
local function SafeCall(plugin, cbName, ...)
    local cb = plugin.callbacks and plugin.callbacks[cbName]
    if not cb then
        --GWB:Debug("no callbacks registered for", plugin.name, " - ", plugin.callbacks, plugin.callbacks[cbName])
        return false
    end

    local ok, ret = pcall(cb, ...)
    --GWB:Debug("pcall(", cb, ",", ...)

    if not ok then
        GWB:Print(("Callback error in %s.%s: %s"):format(plugin.name or "?", cbName, ret))
        return false
    end
    return ret
end

local function GetPluginsSorted()
    local arr = {}
    for _, p in pairs(GWB.plugins) do
        arr[#arr + 1] = p
    end

    table.sort(arr, function(a, b)
        local pa = a.cb_priority or 0
        local pb = b.cb_priority or 0
        if pa ~= pb then
            return pa > pb  -- HIGH priority first
        end
        -- tie-breaker: earlier registered first
        return (a._reg_index or 0) < (b._reg_index or 0)
    end)

    return arr
end

-- Public dispatcher so non-WoW systems can trigger callbacks too
--[[
function GWB:FireCallback(cbName, ...)
    --GWB:Debug("GWB:FireCallback(", cbName, ",", ...,")")
    local lastRet
    ForEachPlugin(function(plugin, ...)
        lastRet = SafeCall(plugin, cbName, ...)
    end)
    --return lastRet
end]]
function GWB:FireCallback(cbName, ...)
    local plugins = GetPluginsSorted()
    _G.dplugs = plugins

    local i = 1
    local args = {...}

    local ctx = {}
    ctx.cbName = cbName

    function ctx.continue()
        while i <= #plugins do
            local plugin = plugins[i]
            i = i + 1

            if plugin and plugin.callbacks and plugin.callbacks[cbName] then
                -- Pass ctx as first arg
                local consumed = SafeCall(plugin, cbName, ctx, unpack(args))
                if consumed then
                    --GWB:Debug("Consumed ", cbName, "by", plugin.name)
                    return  -- chain paused/consumed
                end
            end
        end
    end

    -- start chain
    ctx.continue()
end


GWB.tickers = {}
function GWB:GlobalTick()
    for k, v in pairs(GWB.tickers) do
        if v.enabled and v.fn ~= nil then
            local success, err = pcall(v.fn)
            if not success then
                GWB:Debug("Ticker", k, "failed", err);
            end
        end
    end
end
function GWB:RegisterTicker(name, fn_tick)
    GWB.tickers[name] =
    {
        ["enabled"] = false,
        ["fn"] = fn_tick
    }
    GWB:Debug("Registerd Ticker:", name)
end
function GWB:TickerSetState(name, state)
    --GWB:Debug()
    if GWB.tickers[name] ~= nil then
        GWB.tickers[name].enabled = state
    else
        GWB:Debug("Failed toggle ticker", name, "to", state)
    end
end

local function _tick()
    GWB:GlobalTick()
    C_Timer.After(0.1, _tick)
end 
_tick()

-- ============================================================================
-- WoW event -> callback mapping
-- ============================================================================

local eventToCallbacks = {
    -- Addon/object lifecycle
    ADDON_LOADED          = function(addonName)
        -- If you want "object loaded" for your own objects instead,
        -- call GWB:FireCallback("OnObjectLoaded", object) from your core.
        GWB:FireCallback("OnObjectLoaded", addonName)
    end,
    PLAYER_LOGIN          = function()
        -- sometimes nicer for initialization
        -- You can also treat this as "object loaded"
        GWB:FireCallback("OnObjectLoaded", "PLAYER_LOGIN")
    end,

    -- Player life/level
    PLAYER_DEAD           = function()
        GWB:FireCallback("OnPlayerDeath")
    end,
    PLAYER_ALIVE          = function(ctx)  
        GWB:FireCallback("OnPlayerAlive", ctx)
    end,
    PLAYER_UNGHOST          = function(ctx)  
        GWB:FireCallback("OnPlayerUnghost", ctx)
    end,
    PLAYER_LEVEL_UP       = function(ctx, level)
        GWB:FireCallback("OnPlayerLevelUp", ctx, level)
    end,

    -- Combat state
    PLAYER_REGEN_DISABLED = function(ctx)
        GWB:FireCallback("OnPlayerEnterCombat", ctx)
    end,
    PLAYER_REGEN_ENABLED  = function(ctx)
        GWB:FireCallback("OnPlayerLeaveCombat", ctx)
    end,

    -- Map/instance changes (phasing, instance swap, zoning)
    ZONE_CHANGED_NEW_AREA = function()
        GWB:FireCallback("OnPlayerChangeMapOrInstance")
    end,
    PLAYER_ENTERING_WORLD = function(isLogin, isReload)
        -- Fires on login/reload and zone loads
        GWB:FireCallback("OnPlayerChangeMapOrInstance", isLogin, isReload)
    end,

    -- Looting
    LOOT_OPENED           = function(ctx, autoLoot) -- OK (also, LootFrame.ItemLooted)
        GWB:FireCallback("OnLootStarted", ctx, autoLoot)
    end,
    LOOT_CLOSED           = function(ctx, ...) -- OK
        GWB:FireCallback("OnLootFinished", ctx, ...)
    end,
    --LOOT_SLOT_CLEARED     = function(slot)
    LOOT_SLOT_CHANGED     = function(ctx, slot)
        -- optional extra hook if you want per-slot logic
        --GWB:FireCallback("OnLootFinished")
    end,
    UI_ERROR_MESSAGE      = function(_, msg)
        -- Crude loot-fail detection; refine as needed
        if msg and (msg:find("loot") or msg:find("Loot")) then
            GWB:FireCallback("OnLootFailed", msg)
        end
    end,

    -- Gossip / NPC dialogs
    GOSSIP_SHOW           = function(ctx)
        GWB:FireCallback("OnGossipStart", ctx)
        --GWB:FireCallback("OnGossipFinished")
    end,
    GOSSIP_CLOSED         = function(ctx)
        -- If you want a separate "finished", move it here instead
        -- GWB:FireCallback("OnGossipFinished")
    end,
    TRAINER_SHOW         = function(ctx)
        GWB:FireCallback("OnTrainerShow", ctx)
    end,
    TRAINER_CLOSED         = function(ctx)
        GWB:FireCallback("OnTrainerClosed", ctx)
    end,

    -- Party / raid invites & joining
    PARTY_INVITE_REQUEST  = function(inviterName)
        GWB:FireCallback("OnPartyOrRaidInviteRequest", inviterName)
    end,
    GROUP_ROSTER_UPDATE   = function()
        -- Fires on join/leave; you can detect join by size > 1 etc.
        if IsInGroup() then
            GWB:FireCallback("OnPartyOrRaidGroupJoined")
        end
    end,

    -- Quest flow
    -- QUEST_LOG_UPDATE
    QUEST_DETAIL          = function(ctx)
        GWB:FireCallback("OnNewQuestAvailable", ctx)
    end,
    QUEST_ACCEPTED        = function(ctx, questID)
        GWB:FireCallback("OnNewQuestStarted", ctx, questID)
    end,
    QUEST_PROGRESS        = function(ctx)
        GWB:FireCallback("OnQuestTurninStarted", ctx)
    end,
    QUEST_TURNED_IN       = function(ctx, questID)
        GWB:FireCallback("OnQuestCompleted", ctx, questID)
    end,
    QUEST_COMPLETE        = function(ctx)
        -- quest completion dialog open (reward choice)
        GWB:FireCallback("OnQuestCompleted", ctx)
    end,
    QUEST_FINISHED        = function(ctx)
        -- quest dialog closed
        -- could be success or fail; if you want fail, detect errors via UI_ERROR_MESSAGE
    end,

    -- eh
    MERCHANT_SHOW         = function(ctx)
        GWB:FireCallback("OnMerchantShow", ctx)
    end,
    MERCHANT_CLOSED        = function(ctx)
        GWB:FireCallback("OnMerchantClosed", ctx)
    end,
    }

-- ============================================================================
-- Register all WoW events we mapped
-- ============================================================================

for eventName, _ in pairs(eventToCallbacks) do
    frame:RegisterEvent(eventName)
end

-- Main WoW event handler
frame:SetScript("OnEvent", function(_, eventName, ...)
    local handler = eventToCallbacks[eventName]
    if handler then
        handler(...)
    end
end)

-- ============================================================================
-- Optional: convenience API for your core systems
-- ============================================================================

-- Example usage from your movement/pathing code:
--   GWB:FireCallback("OnMovementStarted", destX, destY)
--   GWB:FireCallback("OnMovementFailed", reason)

-- Example usage from attack routine:
--   GWB:FireCallback("OnAttackEnemyStarted", guid)
--   GWB:FireCallback("OnAttackEnemyFailed", guid, reason)
--   GWB:FireCallback("OnAttackEnemyFinished", guid)

-- Example usage from GUI buttons:
--   GWB:FireCallback("OnGUIButtonStartToggle")
--   GWB:FireCallback("OnGUIResetWaypoints")



GWB.Spells = {}

function GWB.Spells:TryCastSpell(spell, unit, cb_ok, cb_err)
    local unit = unit or "target"
    if type(spell) == "name" then
        Unlock(CastSpellByName, spell, unit)
    elseif type(spell) == "number" then
        Unlock(CastSpellByID, spell, unit)
    end

    -- always assume it is OK?
    cb_ok(); -- TODO: register more events ??
end


GWB.Modules = {}
GWB.Modules.modules = {}

function GWB.Modules:RegisterModule(module)
    if module.name == nil or type(module.name) ~= "string" then
        GWB:Debug("Failed RegisterModule: name field missing!")
        return false
    end

    if module.PlayerCanUse == nil or type(module.PlayerCanUse) ~= "function" then
        GWB:Debug("Failed REgisterModule: PlayerCanUse method missing")
        return false
    end

    GWB.Modules.modules[module.name] = module
    return true
end
