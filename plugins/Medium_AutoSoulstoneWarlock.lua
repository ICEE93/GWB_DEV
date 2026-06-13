local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "AutoSoulstoneWarlock"


-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.MEDIUM -- cuz we need overwrite default :3
plugin.callbacks = {}
plugin.handlers = {}


-- some helper funcs
local soulstoneSpellId = 0 -- is set by game API, from calling local CanUseSoulstone()

local pendingCtx = nil

-- return true if we can Repop with Soulstone
local function CanUseSoulstone()
    if not select(2, UnitClass("player")) == "WARLOCK" then
        return false -- we are not a warlock
    end

    GWB:Print("OnPlayerDeath test UseSoulstone")
    if HasSoulstone ~= nil and CanUseSoulstone ~= nil then
        -- idk?
    else
        local options = C_DeathInfo.GetSelfResurrectOptions() -- added 7.3.5
        -- actually, there s many other self resurects?

        for i=1, #options do
            local option = options[i]
            GWB:Debug(string.format(
                "SelfResOpt: %s, %s, %d, %s, %s %s", 
                option.name, 
                tostring(option.optionType), -- 0 Spell, 1 Item
                option.id,
                tostring(option.canUse),
                tostring(option.isLimited),
                tostring(option.priority)
            ))

            -- NOTE: do NOT consume precious recourses?
            if option.canUse and not option.isLimited then
                if option.optionType == 0 then
                    GWB:Debug("Using", option.name, ", (casting spell ", option.id, ")")
                    soulstoneSpellId = option.id
                --[[else
                    GWB:Debug("Using", option.name, ", (using item ", option.id, ")")  
                ]]--
                end
                return true -- consume event! (or fail.. and try again????)
            end
        end
    end
    return false
end

-- callback for when we die
plugin.callbacks.OnPlayerDeath = function(ctx)
    if pendingCtx then return true end -- interrupt?

    GWB:Debug("CanUseSoulstone()", CanUseSoulstone())
    
    if CanUseSoulstone() then
        GWB:Debug("Consumed OnDeath")
        pendingCtx = ctx -- new state registered
        plugin.handlers.RepopWithSoulstone()
        return true
    end

    -- no? don't sweat it, take default handler
    GWB:Debug("skipped OnDeath")
    return false
end

-- state handler for when we need to ress
plugin.handlers.RepopWithSoulstone = function()
    -- NOTE: bruh, we need to somehow do this and verify if it worked?
    -- if not, we need to proceed with other callbacks even after interrupting the chain?
    local cb_ok = function() 
        GWB:Print('Soulstone OK!')
    end

    local cb_err = function()
        local ctx = pendingCtx
        pendingCtx = nil -- dispatch
        if ctx then ctx.continue() end -- resume to next cb
        GWB:Print('Soulstone FAILED!')
    end

    GWB.Spells:TryCastSpell(soulstoneSpellId, "player", cb_ok, cb_err)
end

--GWB.plugins[plugin.name] = plugin -- register it
GWB:RegisterPlugin(plugin)
