local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "LootHandler"
plugin.author = "GWB"

local tickerNamePostCombat = plugin.name .. "_PostCombatTick"
local postCombatStarted = 0
local lastLootingCorpse = nil
local lastLootDist = 99999
local previousCtx = nil

plugin.cb_priority = GWB.enums.cb_priority.HIGH
plugin.callbacks = {}

-- post-combat looting and whatnot?
local function tickPostCombat()
    local timeoutSeconds = plugin.settings.cb_post_timeout and plugin.settings.cb_post_timeout.value or 5

    -- Keep target clear during looting so waypoint ticker doesn't fight us
    if UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") then
        if Nn.Unlock and RunMacroText then
            Nn.Unlock(RunMacroText, "/cleartarget")
        end
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
            if GetTime() - postCombatStarted < 1.5 then
                -- Give the server up to 1.5s to flag the corpse as lootable before we give up
                return
            end
            
            GWB:Debug("No loot? returning!")
            lastLootingCorpse = nil

            GWB:Debug("LootHandler, finished")
            GWB:TickerSetState(tickerNamePostCombat, false)
            GWB.isPostCombatLooting = false
            
            -- only dispatch if needed?
            if previousCtx then
                local ctx = previousCtx
                previousCtx = nil

                -- leave state
                if GWB.State:getCurrentState() == "plugin.LootHandler" then
                    GWB.State:returnState()
                end

                ctx.continue() -- resume event prop
            end
        else
            GWB:Debug("There is ", #corpses, "corpses nearby")
            local px, py, pz = ObjectPosition("player")
            if not px then return end
            local nearbyCorpses = GWB.Utils:GetClosestObject(corpses, px, py, pz)
            
            local cx, cy, cz = ObjectPosition(nearbyCorpses)
            if cx then
                local dx, dy, dz = cx-px, cy-py, cz-pz
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist < 5.0 then
                    lastLootingCorpse = nearbyCorpses
                    ClickToMove(px, py, pz)
                    ObjectInteract(nearbyCorpses)
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
                lastLootDist = 99999
            end
        end
    else
        -- If we have a corpse, check if we are making progress
        local px, py, pz = ObjectPosition("player")
        if px then
            local cx, cy, cz = ObjectPosition(lastLootingCorpse)
            if cx then
                local dist = math.sqrt((cx-px)^2 + (cy-py)^2 + (cz-pz)^2)
                if dist < lastLootDist - 0.5 then
                    lastLootDist = dist
                    -- Reset timeout since we are making progress
                    postCombatStarted = GetTime() - (timeoutSeconds - 5) -- Give it at least 5 seconds from now
                end
            end
        end
    end

    local finishedLooting = GetTime() > postCombatStarted + timeoutSeconds
    if finishedLooting then
        GWB:Debug("tickPostCombat timed-out!")
        GWB:TickerSetState(tickerNamePostCombat, false)
        GWB.isPostCombatLooting = false
        lastLootingCorpse = nil
        
        if previousCtx then
            local ctx = previousCtx
            previousCtx = nil
            if GWB.State:getCurrentState() == "plugin.LootHandler" then
                GWB.State:returnState()
            end
            ctx.continue()
        end
    end
end

plugin.callbacks.OnPlayerLeaveCombat = function(ctx)
    if previousCtx then return true end
    previousCtx = ctx

    GWB:Print("OnPlayerLeaveCombat LootHandler")
    
    -- Immediately stop the player so they don't keep running away while we generate a path
    if GWB.Settings.UseEZNavSafe and GWB.EZMover then
        if GWB.EZMover:IsMoving() then GWB.EZMover:Stop() end
    elseif GWB.Mover then
        if GWB.Mover:IsMoving() then GWB.Mover:Stop() end
    end
    
    postCombatStarted = GetTime()
    GWB:TickerSetState(tickerNamePostCombat, true)
    GWB.isPostCombatLooting = true
    GWB.State:callState("plugin.LootHandler")
    
    return true -- block others until done
end

plugin.callbacks.OnLootFinished = function(ctx)
    GWB:Debug("LootHandler, OnLootFinished")
    GWB:TickerSetState(tickerNamePostCombat, false)
    GWB.isPostCombatLooting = false

    local delay = plugin.settings.cb_delay_after_loot and plugin.settings.cb_delay_after_loot.value or 0.5
    C_Timer.After(delay, function()
        lastLootingCorpse = nil
        if previousCtx then
            local ctx2 = previousCtx
            previousCtx = nil
            if GWB.State:getCurrentState() == "plugin.LootHandler" then
                GWB.State:returnState()
            end
            ctx2.continue()
        end
    end)
    return false
end

plugin.callbacks.OnLootStarted = function(ctx, autoloot)
    local timeoutSeconds = plugin.settings.cb_post_timeout and plugin.settings.cb_post_timeout.value or 5
    postCombatStarted = GetTime() - (timeoutSeconds + 1.5)
    if autoloot then return false end
    
    if LootFrame == nil or not LootFrame:IsVisible() then return false end
    local numLoot = GetNumLootItems and GetNumLootItems() or 5
    for i=1, numLoot do 
        C_Timer.After(0.5 + (i/10), function() if Nn.Unlock then Nn.Unlock(LootSlot, i) else LootSlot(i) end end)
    end
    return false
end

plugin.callbacks.OnMovementFinished = function(ctx, type, ...)
    if lastLootingCorpse == nil then return false end
    if type == "object" then
        local targetObject = ...
        if targetObject == lastLootingCorpse then
            GWB:Debug("LootHandler, OnMovementFinished true!")
            ObjectInteract(lastLootingCorpse)
            C_Timer.After(0.5, function() ObjectInteract(lastLootingCorpse) end)
            return true
        end
    end
    return false
end

plugin.settings = {
    ["cb_post_timeout"] = {
        ["label"] = "Timeout for looting",
        ["value"] = 5
    },
    ["cb_delay_after_loot"] = {
        ["label"] = "Delay after loot closed",
        ["value"] = 0.5
    }
}

plugin.handlers = {}
plugin.handlers.stateTick = function() end

GWB:RegisterTicker(tickerNamePostCombat, tickPostCombat)
GWB:TickerSetState(tickerNamePostCombat, false)

GWB:RegisterPlugin(plugin)
