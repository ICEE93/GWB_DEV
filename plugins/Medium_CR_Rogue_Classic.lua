local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "CR_Rogue_Classic"

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
local SinisterStrike = 1752
local Eviscerate = 2098
local Throw = 2764

--local buildInfo = GetBuildInfo()
--local buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo = GetBuildInfo()  -- Mainline
local buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo, currentVersion = GetBuildInfo()  -- Classic
local function IsPlayerRogue()
    if interfaceVersion < 11500 or interfaceVersion > 12000 then
        return false -- this aint Classic bruv!
    end
    return select(2, UnitClass("player")) == "ROGUE"
end

plugin.callbacks.OnPlayerEnterCombat = function(ctx)
    if not IsPlayerRogue() then return false end
    
    GWB:Debug("Rogue Combat CR enabled!")
    GWB:TickerSetState(tickerNameCombat, true)
    GWB:TickerSetState(tickerNameRested, false)
    return false -- do not consume
end
plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    if not IsPlayerRogue() then return false end
    
    GWB:Debug("Rogue Rested CR enabled!")
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

local lastAttackTime = 0
local lastAttackTarget = nil

local function tickRested()
    if not GWB:IsBotRunning() then return end
    if 
        not UnitExists("target") or 
        UnitIsDead("target") or
        not UnitCanAttack("player", "target")
    then 
        lastAttackTarget = nil
        return -- skip
    end

    -- Only call StartAttack once per target, not every tick
    local targetGUID = UnitGUID("target")
    if targetGUID ~= lastAttackTarget then
        Unlock(StartAttack)
        lastAttackTarget = targetGUID
    end

    if not ShouldCast() then return end

    Unlock(CastSpellByName, "Sinister Strike")
end
local function tickCombat()
    if not GWB:IsBotRunning() then return end
    -- target is ok?
    if 
        not UnitExists("target") or 
        UnitIsDead("target") or
        not UnitCanAttack("player", "target")
    then 
        return -- skip
    end

    if not ShouldCast() then return end

    Unlock(CastSpellByName, "Sinister Strike")
    Unlock(CastSpellByName, "Eviscerate")
end


GWB:RegisterTicker(tickerNameCombat, tickCombat)
GWB:RegisterTicker(tickerNameRested, tickRested)
GWB:RegisterPlugin(plugin)

-- make sure one of the tickers is always on without event triggers
local function OnLoad()
    if IsPlayerRogue() then
        GWB:Print("CR Rogue Classic enabled!")
    end
    if UnitAffectingCombat("player") then
        GWB:TickerSetState(tickerNameCombat, true)
    else
        GWB:TickerSetState(tickerNameRested, true)
    end
end

OnLoad()
