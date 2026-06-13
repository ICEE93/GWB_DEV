local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "CR_Warlock_Legion"

-- TODO: add these for API or whatever? maybe just use Interface/build nrs?
plugin.xpacs = "legion|tww" 

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
    if interfaceVersion < 120000 then
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
    return false
end
local function ShouldCast()
    return not ShouldNotCast()
end

local function tickRested()
    if 
        not UnitExists("target") or 
        UnitIsDead("target") or
        --not UnitIsEnemy("player", "target") or
        --not UnitCanAttack
        not UnitCanAttack("player", "target")
    then 
        return -- skip
    end

    --GWB:Debug("tickRested", ShouldCast())

    if not ShouldCast() then return end

    -- try cast Immolate?
    Unlock(CastSpellByID, Immolate)
end
local function tickCombat()
    -- target is ok?
    if 
        not UnitExists("target") or 
        UnitIsDead("target") or
        --not UnitIsEnemy("player", "target") or
        not UnitCanAttack("player", "target")
    then 
        return -- skip
    end

    --GWB:Debug("tickCombat", ShouldCast())

    if not ShouldCast() then return end

    -- TODO: Warlock rotation?
    -- TODO: get some GWB.Spell:Cast and GWB.Spellbook stuff?

    -- spam Incinerate
    Unlock(CastSpellByID, Conflagrate)
    Unlock(CastSpellByName, "Incinerate")
    --Unlock(CastSpellByID, DrainLife)
end


GWB:RegisterTicker(tickerNameCombat, tickCombat)
GWB:RegisterTicker(tickerNameRested, tickRested)
GWB:RegisterPlugin(plugin)

-- make sure one of the tickers is always on without event triggers
local function OnLoad()
        if IsPlayerWarlock() then
        GWB:Print("CR Warlock TWW enabled!")
    end
    if UnitAffectingCombat("player") then
        GWB:TickerSetState(tickerNameCombat, true)
    else
        GWB:TickerSetState(tickerNameRested, true)
    end
end

OnLoad()
