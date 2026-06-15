local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "AntiAFk"

-- Works on all versions
plugin.xpacs = "" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "Unknown"

local tickerUpdateAFK = plugin.name .. "_" .. "updateAfk"

-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.DEFAULT
plugin.callbacks = {}

local function updateAfk()
    UpdateLastHardwareAction(GetTime()*1000)
end

GWB:RegisterTicker(tickerUpdateAFK, updateAfk)
GWB:TickerSetState(tickerUpdateAFK, true)
GWB:RegisterPlugin(plugin)


