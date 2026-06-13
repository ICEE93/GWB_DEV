local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "template"

-- TODO: add these for API or whatever? maybe just use Interface/build nrs?
plugin.xpacs = "legion|tww" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "your_name"

local tickerNameCombat = plugin.name .. "_" .. "test"

-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.LOW
plugin.callbacks = {}

-- set callbacks you need
plugin.callbacks.OnPlayerLevelUp = function(ctx)
    -- to consume or not to consume
    return true -- or false, can save ctx and call 
    -- ctx.continue() afterwards to "resume" afterwards
end

local function test()

end

local function OnLoad()

end

GWB:RegisterTicker(tickerNameCombat, tick)
GWB:RegisterPlugin(plugin)

OnLoad() -- maybe call this external??
