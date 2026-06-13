local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "CombatHandler"

-- TODO: add these for API or whatever? maybe just use Interface/build nrs?
plugin.xpacs = "era|tbc|cata|wotlk|mop|wod|legion|tww" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "Unknown"

-- TODO: register settings?
plugin.settings = {
    ["cb_range_melee"] = {
        --["name"] = "cb_range_melee",
        ["label"] = "Combat range melee",
        ["value"] = 1.5,
    },
    ["cb_range_caster"] = {
        --["name"] = "cb_range_caster",
        ["label"] = "Combat range caster",
        ["value"] = 25,
    },

    ["cb_range_min"] = {
        ["label"] = "Combat range min",
        ["value"] = 0.1,
    },
    ["cb_range_max"] = {
        ["label"] = "Combat range max",
        ["value"] = 25,
    },

    ["cb_post_timeout"] = {
        --["name"] = "cb_range_caster",
        ["label"] = "Time-out post-combat actions (looting, skinning, ...) after X seconds",
        ["value"] = 5, --20,
    },
    ["cb_delay_after_loot"] = {
        ["label"] = "Delay after looting before continue routine",
        ["value"] = 1.2
    },
    ["loot_after_combat"] = {
        ["label"] = "Enable looting",
        ["value"] = true,
    },
    ["skinning_after_combat"] = {
        ["label"] = "Enable skinning",
        ["value"] = false,
    },
    ["skinning_only_self"] = {
        ["label"] = "Only skin own kills",
        ["value"] = false
    }
}

if plugin.settings.loot_after_combat.value then
    plugin.settings.cb_post_timeout.value = 7 -- take our time?
end

--[[

- Face enemny (lowest hp aggro?)
- Distance enemy (caster/melee, dynamic check)
- Invoke a CR if available?
- Loot after enemies have been killed? (and trigger loot/vendor/gear handlers?)
- Resume movement after clearing loot?

]]

-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.LOW
plugin.callbacks = {}
plugin.handlers = {}

local tickerNameCombat = plugin.name .. "_" .. "tickCombat"
local tickerNamePostCombat = plugin.name .. "_" .. "tickPostCombat"

local previousCtx = nil
local updateLastFacing = 0
local updateLastTarget = 0
local lastTarget = nil

local combatStarted = 0
local postCombatStarted = 0

local lastLootingCorpse = nil
GWB.isPostCombatLooting = false

-- ===============================

local function IgnoreCombatInCurrentState()
    local state = GWB.State:getCurrentState()
    if state == "plugin.TownHandler" then return true end

    return false
end

-- Dispatch Post-Combat if we died (while in combat)
plugin.callbacks.OnPlayerDeath = function(ctx)
    -- we ded, dispatch the ctx and stop post combat!
    GWB:TickerSetState(tickerNamePostCombat, false)
    local ctx = previousCtx
    previousCtx = nil

    -- leave state
    if GWB.State:getCurrentState() == "plugin.CombatHandler" then
        GWB.State:returnState()
    end

    ctx.continue() 
end

-- Combat ticker for movement/facing
plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    --if IgnoreCombatInCurrentState() then return end
    if GWB.Settings.UseEZNavSafe then
        if GWB.EZMover:IsMoving() then
            GWB:Print("CH enter combat, force stop mov")
            GWB.EZMover:Stop()
        end
    else
        if GWB.Mover:IsMoving() then
            GWB:Print("CH enter combat, force stop mov")
            GWB.Mover:Stop()
        end
    end

    GWB:Print("OnPlayerEnterCombat CH")
    combatStarted = GetTime()
    postCombatStarted = 0
    GWB:TickerSetState(tickerNameCombat, true)
    --GWB:TickerSetState(tickerNamePostCombat, false)
    return false
end

-- post-combat for loot?
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    if previousCtx then return true end
    previousCtx = ctx

    GWB:Print("OnPlayerLeaveCombat CH")
    combatStarted = 0
    postCombatStarted = GetTime()
    print("postCombatStarted", postCombatStarted)
    GWB:TickerSetState(tickerNameCombat, false)
    GWB:TickerSetState(tickerNamePostCombat, true)
    GWB.isPostCombatLooting = true
    
    -- Clear target so waypoint ticker doesn't fight us
    if UnitIsDead("target") then
        Unlock(ClearTarget)
        ClearTarget()
    end
    
    -- leave state
    if GWB.State:getCurrentState() == "plugin.CombatHandler" then
        GWB.State:returnState()
    end

    return true -- yes block it?
end

-- TODO: MOVE THIS INTO A POST-COMBAT HELPER!!! 
-- WE CONFLICT WITH RESTING HANDLER ON THIS ONE!
--
-- to know when to disable post-combat 
plugin.callbacks.OnLootFinished = function(ctx)
    GWB:Debug("CombatHandler, OnLootFinished")
    GWB:TickerSetState(tickerNamePostCombat, false)
    GWB.isPostCombatLooting = false

    local delay = plugin.settings.cb_delay_after_loot.value
    C_Timer.After(delay, function()
        GWB:Debug("CombatHandler, OnLootFinished resuming CombatLeave")
        -- unset loot object 
        lastLootingCorpse = nil
        
        -- only dispatch if needed?
        if previousCtx then
            local ctx = previousCtx
            previousCtx = nil
            
            -- leave state
            if GWB.State:getCurrentState() == "plugin.CombatHandler" then
                GWB.State:returnState()
            end
            
            ctx.continue() -- by doing so, the MovementHandler should pick up and continue?
        end
    end)

    return false -- never consume
end

plugin.callbacks.OnLootStarted = function(ctx, autoloot)
    -- max 1 extra second delay now that we have loot window open
    local timeoutSeconds = plugin.settings.cb_post_timeout.value
    postCombatStarted = GetTime() - (timeoutSeconds + 1.5)
    if autoloot then return false end
    
    -- force loot items?
    if LootFrame == nil or not LootFrame:IsVisible() then return false end

    --LootFrame
    local numLoot = GetNumLootItems and GetNumLootItems() or 5
    for i=1, numLoot do 
        C_Timer.After(0.5 + (i/10), function() Unlock(LootSlot, i) end)-- eh?
    end

    return false
end

plugin.callbacks.OnMovementFinished = function(ctx, type, ...)
    -- we have no skin in the game?
    
    if lastLootingCorpse == nil then return false end

    if type == "object" then
        local targetObject = ...
        if targetObject == lastLootingCorpse then
            -- Just loot it!
            GWB:Debug("CombatHandler, OnMovementFinished true!")
            ObjectInteract(lastLootingCorpse)
            C_Timer.After(0.5, function() --[[print("Looting...")]] ObjectInteract(lastLootingCorpse) end)
            -- TODO: verify if loot was gained tho?
            GWB:Debug("CombatHandler, OnMovementFinished")
            return true -- mi mi mi mi mi :3
        end
    elseif type == "xyz" then
        --local x, y, z = {...}
    end
    return false
end

-- helper funcs?
local lastUpdate = GetTime()

local function updateFacingTarget()
    local tick = GetTime()
    if lastUpdate + 0.5 > tick then
        return
    end
    local px, py, _ = ObjectPosition("player")
    local tx, ty, _ = ObjectPosition("target")
    if px ~= nil and tx ~= nil then
        lastUpdate = tick
        local f = GWB:GetFacing(px, py, tx, ty)
        SetPlayerFacing(f)
    end
end

-- hacky one!!!
local function autoTarget()
    if not Objects or not GetFocus then print("fail") return end -- Unlocker API's
    local os = Objects()
    local old = GetFocus()
    for i=1, #os do
        local o = os[i]
        if ObjectType(o) == 5 then
            SetFocus(o)
            if 
                not UnitIsDead("focus") and 
                UnitIsEnemy("player", "focus") and 
                UnitCanAttack("player", "focus") and 
                UnitExists("focus") and 
                CheckInteractDistance("focus", 1)  
            then
                Unlock(TargetUnit, "focus")
                SetFocus(old)
                updateFacingTarget()
                return
            end
        end

    end
    SetFocus(old)
end

-- combat facing and distancing
local function tickMovement()
    -- we should also run to it?
    GWB.Mover:Update()
    local px, py, pz = GWB.Mover:GetPlayerPosition()
    local tx, ty, tz = ObjectPosition("target")
    local d = GWB.Utils:Distance(px, py, 0, tx, ty, 0)
    local min = plugin.settings.cb_range_min.value
    local max = plugin.settings.cb_range_max.value
    --print(d, ">", max, "or ", d, "<", min)
    if d > max or d < min and d < 100 then
        -- only block if it was more then 3 sec ago
        if GetTime() > updateLastFacing +3 then
            if GWB.Settings.UseEZNavSafe then
                if GWB.EZMover:IsMoving() then GWB.EZMover:Stop() end
            else
                if GWB.Mover:IsMoving() then GWB.Mover:Stop() end
            end
        else
            -- we need to halt, or we stuck on prev?
            if GWB.Settings.UseEZNavSafe then
                if GWB.EZMover:IsMoving() then GWB.EZMover:Stop() end
            else
                if GWB.Mover:IsMoving() then GWB.Mover:HaltMovement() end
            end
        end

        --GWB.Mover:MoveToXYZ(tx, ty, tz)
        local x3, y3 = GWB:calculateThirdDot(tx, ty, px, py, min+1)
        if GWB.Settings.UseEZNavSafe then
            GWB.EZMover:MoveToXYZ(x3, y3, tz)
        else
            GWB.Mover:MoveToXYZ(x3, y3, tz)
        end
    end
end
local function tickCombat()
    --GWB:Debug("CombatHandle tickCombat")
    local tick = GetTime()

    --print("A")
    -- Humanize reaction time for target selection
    if tick > updateLastTarget + (math.random(15, 30) / 10.0) then
        if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then
            GWB:Debug("autoTarget()")
            autoTarget() -- custom target routine
            --if GWB:OnBotScanTick() then -- build-in target routine
            --    GWB.Mover:HaltMovement() -- stop if found?
            --end
            updateLastTarget = GetTime()
        end
    end

    -- NOTE; also done in tick handler?
    -- Randomize the facing interval (0.2s - 0.8s) so turning isn't perfectly mechanical
    if tick > updateLastFacing + (math.random(2, 8) / 10.0) then 
        if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
            --print("tickMovement")
            -- update facing for target
            --local tx, ty, tz = ObjectPosition("target")
            updateFacingTarget()
            updateLastFacing = GetTime()

            tickMovement()
        end
    end

end

-- post-combat looting and whatnot?
local function tickPostCombat()
    -- at one point, it gotta take itself out!
    local timeoutSeconds = plugin.settings.cb_post_timeout.value

    -- Keep target clear during looting so waypoint ticker doesn't fight us
    if UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") then
        Unlock(ClearTarget)
        ClearTarget()
    end

    if lastLootingCorpse ~= nil then
        -- Check if corpse is still valid and lootable
        if not ObjectExists(lastLootingCorpse) or (ObjectLootable and not ObjectLootable(lastLootingCorpse)) then
            lastLootingCorpse = nil
        else
            -- Try to interact directly if close enough
            local px, py, pz = ObjectPosition("player")
            local cx, cy, cz = ObjectPosition(lastLootingCorpse)
            if px and cx then
                local dx, dy, dz = cx-px, cy-py, cz-pz
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist < 5.0 then
                    -- Must stop ClickToMove before ObjectInteract will work
                    ClickToMove(px, py, pz)
                    ObjectInteract(lastLootingCorpse)
                end
            end
        end
    end

    -- find a corpse if we aren't alrdy looking at one?
    if lastLootingCorpse == nil then
        -- try looting?
        local corpses = GWB.OM:GetNearbyLootableCorpses()
        if #corpses == 0 then
            GWB:Debug("No loot? returning!")
            lastLootingCorpse = nil

            GWB:Debug("CombatHandler, OnLootFinished")
            GWB:TickerSetState(tickerNamePostCombat, false)
            GWB.isPostCombatLooting = false
            
            -- only dispatch if needed?
            if previousCtx then
                local ctx = previousCtx
                previousCtx = nil

                -- leave state
                if GWB.State:getCurrentState() == "plugin.CombatHandler" then
                    GWB.State:returnState()
                end

                ctx.continue() -- by doing so, the MovementHandler should pick up and continue?
            end
        else
            GWB:Debug("There is ", #corpses, "corpses nearby")
        
            -- take the closest corpse?
            local px, py, pz = ObjectPosition("player")
            if not px then return end
            local nearbyCorpses = GWB.Utils:GetClosestObject(corpses, px, py, pz)
            
            -- If already close enough, just interact directly
            local cx, cy, cz = ObjectPosition(nearbyCorpses)
            if cx then
                local dx, dy, dz = cx-px, cy-py, cz-pz
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist < 5.0 then
                    lastLootingCorpse = nearbyCorpses
                    -- Must stop ClickToMove before ObjectInteract will work
                    ClickToMove(px, py, pz)
                    ObjectInteract(nearbyCorpses)
                    GWB:Debug("Direct interact with corpse at dist:", dist)
                    return
                end
            end
            
            local isMoveOk = false
            if GWB.Settings.UseEZNavSafe then
                isMoveOk = GWB.EZMover:MoveToObject(nearbyCorpses)
            else
                isMoveOk = GWB.Mover:MoveToObject(nearbyCorpses)
            end
            if isMoveOk then
                lastLootingCorpse = nearbyCorpses
            end
            GWB:Debug("Setting movement to corpse! from CombatHandler, isMoveOk:", isMoveOk)
        end
    end

    --GWB:Debug("tickPostCombat", GetTime(), ">", postCombatStarted+timeoutSeconds)

    local finishedLooting = GetTime() > postCombatStarted + timeoutSeconds

    if finishedLooting then
        GWB:Debug("tickPostCombat timed-out!")
        GWB:TickerSetState(tickerNamePostCombat, false)
        GWB.isPostCombatLooting = false
        lastLootingCorpse = nil
        -- now dispatch the "LeaveCombat fr"
        if previousCtx then
            local ctx = previousCtx
            previousCtx = nil
            
            -- leave state
            if GWB.State:getCurrentState() == "plugin.CombatHandler" then
                GWB.State:returnState()
            end

            ctx.continue() -- by doing so, the MovementHandler should pick up and continue?
        end
    end
end

plugin.handlers.tickCombat = function()
    if IgnoreCombatInCurrentState("player") then
        print("SKIP COMBAT")
        GWB.State:returnState()
    end
end

plugin.handlers.stateTick = function()
    --print("tick CombatHandler!")
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        local tick = GetTime()
        if tick > updateLastFacing + 0.5 then
            updateLastFacing = tick
            updateFacingTarget()
            tickMovement()
        end
    else
        -- if the target died, we return?
        return true
    end
end

GWB:RegisterTicker(tickerNameCombat, tickCombat)
GWB:RegisterTicker(tickerNamePostCombat, tickPostCombat)
GWB:RegisterPlugin(plugin)
