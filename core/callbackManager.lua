local Nn, GWB, cbHandler = ...

GWB.pluginCallbacks = {}

-- NOTE: unused so far?
function GWB:RegisterCallback(plugin, cbName, priority)
    if GWB.pluginCallbacks[plugin.name] == nil then
        GWB.pluginCallbacks[plugin.name] = {} 
    end

    local cb = {}
    cb.cbName = cbName
    cb.plugin = plugin
    cb.priority = priority

    table.insert(GWB.pluginCallbacks[plugin.name], cb)
end