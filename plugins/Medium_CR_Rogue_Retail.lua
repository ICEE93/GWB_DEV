local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "CR_Rogue_Retail"

-- Retail only
plugin.xpacs = "retail|legion|tww"

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "Unknown"

local tickerNameCombat = plugin.name .. "_" .. "tickCombat"
local tickerNameRested = plugin.name .. "_" .. "tickRested"


-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.LOW
plugin.callbacks = {}

-- locals
local SinisterStrike = 1752
local Eviscerate = 196819

local buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo, currentVersion = GetBuildInfo()
local function IsPlayerRogue()
    if interfaceVersion < 100000 then
        return false -- this aint Retail bruv!
    end
    return select(2, UnitClass("player")) == "ROGUE"
end

-- Helper function to unwrap secret values in retail
local function SafeUnwrap(value)
    if not value then return value end
    -- Check if value is a secret value using Nn.issecretvalue
    if Nn and Nn.issecretvalue and Nn.issecretvalue(value) then
        return Nn.secretunwrap(value)
    end
    return value
end

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    if GWB.Settings.DisableCR or not IsPlayerRogue() then return false end

    GWB:Debug("Rogue Combat CR enabled!")
    GWB:TickerSetState(tickerNameCombat, true)
    GWB:TickerSetState(tickerNameRested, false)
    return false -- do not consume
end
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    if GWB.Settings.DisableCR or not IsPlayerRogue() then return false end

    GWB:Debug("Rogue Rested CR enabled!")
    GWB:TickerSetState(tickerNameCombat, false)
    GWB:TickerSetState(tickerNameRested, true)
    return false -- do not consume
end

local lastAttackTime = 0
local lastAttackTarget = nil

local nextSpellCastTime = 0
local function RandomizeNextCast()
    nextSpellCastTime = GetTime() + (0.15 + math.random() * 0.4)
end

local function ShouldNotCast()
    -- not alrdy casting or moving?
    if UnitCastingInfo("player") ~= nil then
        return true -- alrdy casting
    end
    if UnitChannelInfo("player") ~= nil then
        return true -- alrdy channeling
    end
    local curr, _, _, _ = GetUnitSpeed("player")
    curr = SafeUnwrap(curr)
    if curr ~= 0 then
        return true -- moving
    end
    if GetTime() < nextSpellCastTime then
        return true -- humanization delay
    end
    return false
end
local function ShouldCast()
    return not ShouldNotCast()
end

local function tickRested()
    if not GWB.Map:IsRunning() then return end

    -- Check for quest mobs that we should engage even if neutral
    local isQuestMobInRange = false
    if GWB.QuestHandler and GWB.QuestHandler.IsObjective then
        local os = Objects()
        local px, py, pz = ObjectPosition("player")
        px, py, pz = SafeUnwrap(px), SafeUnwrap(py), SafeUnwrap(pz)
        for i=1, #os do
            local o = os[i]
            if ObjectType(o) == 5 then
                if GWB.QuestHandler:IsObjective(o) and not UnitIsDead(o) and UnitCanAttack("player", o) then
                    local ox, oy, oz = ObjectPosition(o)
                    ox, oy, oz = SafeUnwrap(ox), SafeUnwrap(oy), SafeUnwrap(oz)
                    if px and ox then
                        local dist = math.sqrt((ox-px)^2 + (oy-py)^2 + (oz-pz)^2)
                        if dist <= 8 then -- Melee range for rogue
                            isQuestMobInRange = true
                            break
                        end
                    end
                end
            end
        end
    end

    if
        not UnitExists("target") or
        UnitIsDead("target") or
        not UnitCanAttack("player", "target")
    then
        lastAttackTarget = nil
        -- If we have a quest mob in melee range, target it
        if isQuestMobInRange then
            local os = Objects()
            local px, py, pz = ObjectPosition("player")
            px, py, pz = SafeUnwrap(px), SafeUnwrap(py), SafeUnwrap(pz)
            local closestQuestMob = nil
            local closestDist = 999
            for i=1, #os do
                local o = os[i]
                if ObjectType(o) == 5 then
                    if GWB.QuestHandler:IsObjective(o) and not UnitIsDead(o) and UnitCanAttack("player", o) then
                        local ox, oy, oz = ObjectPosition(o)
                        ox, oy, oz = SafeUnwrap(ox), SafeUnwrap(oy), SafeUnwrap(oz)
                        if px and ox then
                            local dist = math.sqrt((ox-px)^2 + (oy-py)^2 + (oz-pz)^2)
                            if dist <= 8 and dist < closestDist then
                                closestDist = dist
                                closestQuestMob = o
                            end
                        end
                    end
                end
            end
            if closestQuestMob then
                Unlock(TargetUnit, closestQuestMob)
                lastAttackTarget = UnitGUID(closestQuestMob)
                Unlock(StartAttack)
            end
        end
        return -- skip
    end

    -- Only call StartAttack once per target, not every tick
    local targetGUID = UnitGUID("target")
    if targetGUID ~= lastAttackTarget then
        Unlock(StartAttack)
        lastAttackTarget = targetGUID
    end

    if not ShouldCast() then return end

    local energy = UnitPower("player", 3)
    energy = SafeUnwrap(energy)
    local cp = GetComboPoints("player", "target")
    cp = SafeUnwrap(cp)

    if cp >= 2 and energy >= 35 then
        Unlock(CastSpellByName, "Eviscerate")
        RandomizeNextCast()
    elseif energy >= 40 then
        Unlock(CastSpellByName, "Sinister Strike")
        RandomizeNextCast()
    end
end
local function tickCombat()
    if not GWB.Map:IsRunning() then return end
    -- target is ok?
    if
        not UnitExists("target") or
        UnitIsDead("target") or
        not UnitCanAttack("player", "target")
    then
        return -- skip
    end

    if not ShouldCast() then return end

    local energy = UnitPower("player", 3)
    energy = SafeUnwrap(energy)
    local cp = GetComboPoints("player", "target")
    cp = SafeUnwrap(cp)

    if cp >= 2 and energy >= 35 then
        Unlock(CastSpellByName, "Eviscerate")
        RandomizeNextCast()
    elseif energy >= 40 then
        Unlock(CastSpellByName, "Sinister Strike")
        RandomizeNextCast()
    end
end


GWB:RegisterTicker(tickerNameCombat, tickCombat)
GWB:RegisterTicker(tickerNameRested, tickRested)
GWB:RegisterPlugin(plugin)

-- make sure one of the tickers is always on without event triggers
local function OnLoad()
    if IsPlayerRogue() then
        GWB:Print("CR Rogue Retail enabled!")
    end
    if UnitAffectingCombat("player") then
        GWB:TickerSetState(tickerNameCombat, true)
    else
        GWB:TickerSetState(tickerNameRested, true)
    end
end

OnLoad()
