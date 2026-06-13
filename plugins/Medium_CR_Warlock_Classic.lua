local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "CR_Warlock_Classic"

-- TODO: add these for API or whatever? maybe just use Interface/build nrs?
plugin.xpacs = "classic|tbc|wotlk|cata" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "Unknown"

local tickerNameCombat = plugin.name .. "_" .. "tickCombat"
local tickerNameRested = plugin.name .. "_" .. "tickRested"


-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.LOW
plugin.callbacks = {}

-- locals
local Incinerate = 29722
local Conflagrate = 17962
local Immolate = 348
local DrainLife = 234153

--local buildInfo = GetBuildInfo()
--local buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo = GetBuildInfo()  -- Mainline
local buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo, currentVersion = GetBuildInfo()  -- Classic
local function IsPlayerWarlock()
    if interfaceVersion < 11500 or interfaceVersion > 12000 then
        return false -- this aint Classic bruv!
    end
    return select(2, UnitClass("player")) == "WARLOCK"
end

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    if not IsPlayerWarlock() then return false end
    
    GWB:Debug("Warlock Combat CR enabled!")
    GWB:TickerSetState(tickerNameCombat, true)
    GWB:TickerSetState(tickerNameRested, false)
    return false -- do not consume
end
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    if not IsPlayerWarlock() then return false end
    
    GWB:Debug("Warlock Rested CR enabled!")
    GWB:TickerSetState(tickerNameCombat, false)
    GWB:TickerSetState(tickerNameRested, true)
    return false -- do not consume
end

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
    if curr ~= 0 then
        return true -- moving
    end
    if GetTime() < nextSpellCastTime then
        return true -- humanization delay
    end
    return false
end

local function HasAura(unit, spellName, filter)
    for i = 1, 40 do
        local name = UnitAura(unit, i, filter)
        if not name then break end
        if name == spellName then return true end
    end
    return false
end
local function ShouldCast()
    return not ShouldNotCast()
end
local function tickRested()
    if not GWB.Map:IsRunning() then return end
    if not ShouldCast() then return end

    if not HasAura("player", "Demon Armor", "HELPFUL") and not HasAura("player", "Demon Skin", "HELPFUL") then
        Unlock(CastSpellByName, "Demon Armor")
        Unlock(CastSpellByName, "Demon Skin")
        RandomizeNextCast()
        return
    end

    if not UnitExists("pet") then
        Unlock(CastSpellByName, "Summon Imp")
        RandomizeNextCast()
        return
    end

    if 
        not UnitExists("target") or 
        UnitIsDead("target") or
        not UnitCanAttack("player", "target")
    then 
        return -- skip
    end

    Unlock(CastSpellByName, "Shadow Bolt")
    RandomizeNextCast()
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

    if not HasAura("target", "Corruption", "HARMFUL|PLAYER") then
        Unlock(CastSpellByName, "Corruption")
        RandomizeNextCast()
        return
    end

    if not HasAura("target", "Curse of Agony", "HARMFUL|PLAYER") then
        Unlock(CastSpellByName, "Curse of Agony")
        RandomizeNextCast()
        return
    end

    if not HasAura("target", "Immolate", "HARMFUL|PLAYER") then
        Unlock(CastSpellByName, "Immolate")
        RandomizeNextCast()
        return
    end

    local mana = GWB.Utils.SafeNumber(UnitPower("player", 0))
    local manaMax = GWB.Utils.SafeNumber(UnitPowerMax("player", 0))
    local manaPct = (manaMax > 0) and (mana / manaMax) * 100 or 100
    if manaPct < 15 then
        Unlock(CastSpellByName, "Shoot")
        RandomizeNextCast()
    else
        Unlock(CastSpellByName, "Shadow Bolt")
        RandomizeNextCast()
    end
    Unlock(CastSpellByName, "Attack")
end


GWB:RegisterTicker(tickerNameCombat, tickCombat)
GWB:RegisterTicker(tickerNameRested, tickRested)
GWB:RegisterPlugin(plugin)

-- make sure one of the tickers is always on without event triggers
local function OnLoad()
    if IsPlayerWarlock() then
        GWB:Print("CR Warlock Classic enabled!")
    end
    if UnitAffectingCombat("player") then
        GWB:TickerSetState(tickerNameCombat, true)
    else
        GWB:TickerSetState(tickerNameRested, true)
    end
end

OnLoad()
