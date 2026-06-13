local Nn, GWB = ...

local module = {}
module.name = "Classic_Human_Rogue_1-10"
module.group = "Leveling"

local maxLvl = 60

local function _update()
    local restHandler = GWB.plugins.RestHandler
    local townHandler = GWB.plugins.TownHandler
    local combatHandler = GWB.plugins.CombatHandler

    local lvl = UnitLevel("player")

    if lvl <= 3 then
        -- 1-3 zone, Wolfs at lvl 1, West
        GWB.Map.pointsPerMap[1429] = {
            { wx=-8901.39, wy=-62.08, wz=0 },
            { wx=-8860.38, wy=-57.53, wz=0 },
            { wx=-8883.16, wy=-84.86, wz=0 },
            { wx=-8883.16, wy=-39.31, wz=0 },
        }
    elseif lvl <= 4 then
        -- zone 4-6, Candle guys, North
        GWB.Map.pointsPerMap[1429] = {
            { wx=-8755.59, wy=-62.08, wz=0 },
            { wx=-8746.48, wy=-125.85, wz=0 },
            { wx=-8787.48, wy=-93.97, wz=0 },
            { wx=-8670.14, wy=-185.07, wz=0 },
        }
    elseif lvl <= 6 then
        -- 6-8, Bandits, East at farm
        GWB.Map.pointsPerMap[1429] = {
            { wx=-9060.86, wy=-253.39, wz=0 },
            { wx=-9047.19, wy=-276.16, wz=0 },
            { wx=-9083.64, wy=-262.50, wz=0 },
            { wx=-9092.75, wy=-289.83, wz=0 },
            { wx=-9097.31, wy=-244.28, wz=0 }
        }
    elseif lvl <= 8 then
        -- 7, the small mountain on Goldshire
        GWB.Map.pointsPerMap[1429] = {
            { wx=-9252.22, wy=-16.54, wz=0 },
            { wx=-9361.00, wy=-2.87, wz=0 },
            { wx=-9361.57, wy=56.34, wz=0 },
            { wx=-9293.22, wy=97.34, wz=0 },
            { wx=-9252.22, wy=120.11, wz=0 },
            { wx=-9316.00, wy=51.79, wz=0 },
            { wx=-9256.77, wy=29.01, wz=0 },
            
        }
    elseif lvl <= 12 then
        -- Forst Edge
        GWB.Map.pointsPerMap[1429] = {
            {x=25.42, y=80.92, wx=-9812.63, wy=653.03, wz=0},
            {x=27.39, y=80.33, wx=-9798.97, wy=584.71, wz=0},
            {x=26.34, y=82.89, wx=-9858.20, wy=621.15, wz=0},
            {x=27.26, y=82.89, wx=-9858.20, wy=621.15, wz=0},
            {x=27.92, y=82.50, wx=-9849.08, wy=566.49, wz=0},
            
        }
    else
        -- Westfall East side, lvl 10-13 mobs
        GWB.Map.pointsPerMap[1436] = {
            {wx=-10502.80, wy=832.65, wz=0},
            {wx=-10383.38, wy=951.02, wz=0},
            {wx=-10291.51, wy=854.56, wz=0},
            {wx=-10181.28, wy=849.97, wz=0},
            {wx=-10089.41, wy=849.97, wz=0},
            {wx=-10080.23, wy=914.27, wz=0},
            {wx=-10158.31, wy=973.99, wz=0},
            {wx=-10286.92, wy=973.99, wz=0},
            
        }
    end


    -- combat
    combatHandler.settings.cb_range_min.value = 0.1
    combatHandler.settings.cb_range_max.value = 5

    -- #==============================#
    -- #         Rest Handler         #
    -- #==============================#

    restHandler.settings.rest_start_mana_percent.value = 50 -- NO!
    restHandler.settings.rest_stop_mana_percent.value = 50
    restHandler.settings.rest_use_drink.value = false
    restHandler.settings.rest_consume_collected_only.value = true

    -- We are gods at lvl 1~3
    if lvl < 3 then
        restHandler.settings.rest_start_hp_percent.value = 30
        restHandler.settings.rest_stop_hp_percent.value = 50

        -- save copper until we matter
        restHandler.settings.rest_use_food_normal.value = false
    else
        restHandler.settings.rest_start_hp_percent.value = 50
        restHandler.settings.rest_stop_hp_percent.value = 70

        restHandler.settings.rest_use_food_normal.value = true
    end


    -- #==============================#
    -- #         Town Handler         #
    -- #==============================#

    --townHandler.settings.town_buy_drink.value = false -- bugged
    townHandler.settings.town_repair_at_percent.value = 30
    townHandler.settings.town_vendor_at_bags_free.value = 1
    townHandler.settings.town_buy_food_count.value = 20
    --townHandler.settings.town_buy_food.value = true -- bugged
    townHandler.settings.town_buy_drink_count.value = 0

    if lvl > 5 then
        townHandler.settings.town_buy_food_count.value = 20
    end
end

module.PlayerCanUse = function()
    local lvl = UnitLevel("player")
    if lvl > maxLvl or lvl < 1 then return false end
    if select(2, UnitClass("player")) ~= "ROGUE" then return false end
    return true
end
module.OnLoad = function()
    _update()

    -- set Waypoints
    --GWB.State:callState("plugin.Waypoints")
end
module.OnLevelUp = function()
    local lvl = UnitLevel("player")
    if lvl > maxLvl then 
        -- TODO: unload??
        return false 
    end

    
    _update()
end

GWB.Modules:RegisterModule(module)

