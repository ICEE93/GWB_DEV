local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "CombatHandler"

-- Works on all versions
plugin.xpacs = "" 

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
    if state == "plugin.TownHandler" then 
        local avgPct, lowestPct, lowestSlot = GWB.Inv:GetAverageDurability()
        if avgPct < 10 or lowestPct < 5 then
            return true
        end
    end

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
    if IgnoreCombatInCurrentState() then
        GWB:Print("CombatHandler ignoring combat (fleeing).")
        return false
    end

    -- Force stop ALL movement when entering combat
    if GWB.Settings.UseEZNavSafe then
        if GWB.EZMover:IsMoving() then
            GWB.EZMover:Stop()
        end
    else
        if GWB.Mover:IsMoving() then
            GWB.Mover:Stop()
        end
    end

    -- Also stop ClickToMove directly
    local px, py, pz = ObjectPosition("player")
    if px then
        ClickToMove(px, py, pz)
    end

    GWB:Print("OnPlayerEnterCombat CH")
    combatStarted = GetTime()
    postCombatStarted = 0
    GWB:TickerSetState(tickerNameCombat, true)
    
    -- Actually push the state so Waypoints yields to us!
    GWB.State:callState("plugin.CombatHandler")
    
    return true -- block others
end

-- post-combat for loot?
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    if previousCtx then return true end
    previousCtx = ctx

    GWB:Print("OnPlayerLeaveCombat CH")
    combatStarted = 0
    GWB:TickerSetState(tickerNameCombat, false) -- Fix leak!
    
    -- Clear target so waypoint ticker doesn't fight us
    if UnitIsDead("target") then
        if Unlock and RunMacroText then
            Unlock(RunMacroText, "/cleartarget")
        end
    end
    
    -- leave state
    if GWB.State:getCurrentState() == "plugin.CombatHandler" then
        GWB.State:returnState()
    end

    return false -- let event propagate to LootHandler and RestHandler
end

plugin.callbacks.OnMovementFinished = function(ctx, type, ...)
    -- we have no skin in the game?
    
    if type == "object" then
        --
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

local function autoTarget()
    if not ObjectManager then return end
    local os = ObjectManager(5) or {}
    local old = GetFocus()
    local isAutopilot = GWB.Settings.QuestieAutopilot or (GWB.Settings and GWB.Settings.AutopilotProvider)
    local function isQuestObjFast(o) return GWB.QuestHandler and GWB.QuestHandler.IsObjective and GWB.QuestHandler:IsObjective(o) end

    local bestTarget = nil
    local bestScore = -999999
    local inCombat = UnitAffectingCombat("player")
    local isMountedAndMoving = IsMounted and IsMounted() and GetUnitSpeed("player") > 0
    local px, py, pz = ObjectPosition("player")

    for i=1, #os do
        local o = os[i]
        if ObjectExists(o) then
            SetFocus(o)
            if not UnitIsDead("focus") and UnitIsEnemy("player", "focus") and UnitCanAttack("player", "focus") then
                local isAttackingMe = UnitTarget and UnitTarget(o) == Object("player")

                -- Skip if it's tapped by someone else and not attacking us
                local isTapped = UnitIsTapDenied and UnitIsTapDenied("focus")

                -- If we are mounted and moving, ignore everything unless it dismounts us
                if not (isMountedAndMoving and not isAttackingMe) then
                    local isQuest = false
                    if isAutopilot then
                        isQuest = isQuestObjFast(o)
                    else
                        isQuest = true
                    end

                    local distToMe = 999
                    local px, py, pz = ObjectPosition("player")
                    local ox, oy, oz = ObjectPosition(o)
                    if px and ox then
                        distToMe = math.sqrt((ox-px)^2 + (oy-py)^2 + (oz-pz)^2)
                    end

                    -- For quest mobs, engage at longer range (up to 30 yards)
                    -- For non-quest mobs, require melee range
                    local inRange = (isQuest and distToMe <= 30) or CheckInteractDistance("focus", 1)

                    if inRange and (isAttackingMe or (not isTapped and isQuest) or (inCombat and UnitAffectingCombat("focus"))) then
                        local score = 0

                        if isAttackingMe then
                            score = 10000 - distToMe -- Prioritize closest attackers
                        elseif inCombat then
                            if UnitAffectingCombat("focus") then
                                score = 5000 - distToMe -- Likely the mob we are in combat with
                            else
                                score = -999999 -- Do NOT chain pull passive mobs!
                            end
                        else
                            -- Check for groups
                            local friendsNearby = 0
                            if ox then
                                for j=1, #os do
                                    local friend = os[j]
                                    if friend ~= o and ObjectType(friend) == 5 then
                                        local fx, fy, fz = ObjectPosition(friend)
                                        if fx then
                                            local fDist = math.sqrt((ox-fx)^2 + (oy-fy)^2 + (oz-fz)^2)
                                            if fDist < 18.0 then
                                                SetFocus(friend)
                                                if UnitCanAttack("player", "focus") and not UnitIsDead("focus") then
                                                    friendsNearby = friendsNearby + 1
                                                end
                                            end
                                        end
                                    end
                                end
                                SetFocus(o) -- restore outer loop focus
                            end

                            if friendsNearby > 0 then
                                score = -50000 -- Do not pull groups!
                            else
                                score = 1000 - distToMe
                            end
                        end

                        if score > bestScore then
                            bestScore = score
                            bestTarget = o
                        end
                    end
                end
            end
        end
    end

    if bestTarget and bestScore > -10000 then
        SetFocus(bestTarget)
        Unlock(TargetUnit, "focus")
    end

    SetFocus(old)
end

-- combat facing and distancing
local function tickMovement()
    local px, py, pz
    if not GWB.Settings.UseEZNavSafe then
        GWB.Mover:Update()
        px, py, pz = GWB.Mover:GetPlayerPosition()
    else
        px, py, pz = ObjectPosition("player")
    end
    
    if not px then return end
    
    local tx, ty, tz = ObjectPosition("target")
    if not tx then return end
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
    if not GWB.Map:IsRunning() then return end
    
    --GWB:Debug("CombatHandle tickCombat")
    local tick = GetTime()

    --print("A")
    -- Humanize reaction time for target selection
    if tick > updateLastTarget + (math.random(15, 30) / 10.0) then
        if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then
            -- GWB:Debug("autoTarget()") -- Removed to prevent spam
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

plugin.handlers.tickCombat = function()
    if IgnoreCombatInCurrentState("player") then
        print("SKIP COMBAT")
        GWB.State:returnState()
    end
end

local exitCombatDelay = 0

plugin.handlers.stateTick = function()
    local hasValidTarget = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    
    if not hasValidTarget then
        -- Clear dead target
        if UnitIsDead("target") and Unlock and RunMacroText then
            Unlock(RunMacroText, "/cleartarget")
        end

        if not UnitAffectingCombat("player") then
            if exitCombatDelay == 0 then
                exitCombatDelay = GetTime() + 1.5
                -- Stop moving
                if GWB.Settings.UseEZNavSafe then
                    if GWB.EZMover:IsMoving() then GWB.EZMover:Stop() end
                elseif GWB.Mover:IsMoving() then
                    GWB.Mover:Stop()
                end
                local px, py, pz = ObjectPosition("player")
                if px then ClickToMove(px, py, pz) end
            elseif GetTime() > exitCombatDelay then
                exitCombatDelay = 0
                return true
            end
        else
            -- We are in combat but have no target. Wait for autoTarget() to pick one.
            exitCombatDelay = 0
        end
        return false
    else
        exitCombatDelay = 0
        local tick = GetTime()
        if tick > updateLastFacing + 0.5 then
            updateLastFacing = tick
            updateFacingTarget()
            tickMovement()
        end
        return false
    end
end

GWB:RegisterTicker(tickerNameCombat, tickCombat)
GWB:TickerSetState(tickerNameCombat, false)


GWB:RegisterPlugin(plugin)
