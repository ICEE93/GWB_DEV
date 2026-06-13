local Nn, GWB = ...

--[[

Generic data storage. MUST fork and improve lateron
to keep things clean!! Only for testing now

]]

if not GWB.DB then GWB.DB = {} end
if not GWB.DB.classic then GWB.DB.classic = {} end

-- Food?
local food_normal = {}

food_normal[1] = {
    4604,       -- Forest Mushroom Cap
    117,        -- Tought Jerkt
    2070,       -- Darnassian Bleu
    4536,       -- Shiny Red Apple
    4540,       -- Tough Hunk of Bread
    7097,       -- Leg Meat
}
food_normal[5] = {
    414,        -- Dalaran Sharp
    4541,       -- Freshly Baked Bread
}
food_normal[15] = {
    422,        -- Dwarven Mild
    4542,       -- Moist Cornbread  
}
food_normal[25] = {
    1707,       -- Stormwind Brie
    4544,       -- Mulgore Spice Bread
}
food_normal[35] = {
    3927,       -- Fine Aged Cheddar
    4601,       -- Soft Banana Bread
}
food_normal[45] = {
    8932,       -- Alterac Swiss
    8950,       -- Homemade Cherry Pie
}

GWB.DB.classic.food_normal = food_normal

food_buffed = {}

-- we should think about the Well Fed food, we don't
-- want to spam that? unless we are configured to do so?

-- drinks?
local drinks = {}

drinks[1] = {
    5350,       -- Conjured Water
    159,        -- Refreshing Spring Water
}
drinks[5] = {
    1179,       -- Ice Cold Milk
}
drinks[15] = { 
    1205,       -- Melon Juice
}
drinks[25] = {
    1708,       -- Sweet Nectar
}
drinks[35] = {
    1645,       -- Moonberry Juice
}
drinks[45] = {
    8766,       -- Morning Glory Dew
}

GWB.DB.classic.drinks = drinks


-- select(2, /dump UnitClass("player"))
GWB.DB.classic.trainers = { }

GWB.DB.classic.trainers.WARLOCK = {
    [1429] = { -- northshire
        { id=459, coord={ x=-8926.74, y=-195.58, z=80.58}, lvl=6 }, -- in stables
    }
}

GWB.DB.classic.trainers.ROGUE = {
    [1429] = { -- northshire
        { id=915, coord={ x=-8914.0, y=-127.0, z=81.0}, lvl=6 }, -- Jorik Kerridan
    },
    [1453] = { -- Stormwind City
        { id=918, coord={ x=-8752.30, y=377.57, z=101.05}, lvl=60 } -- Old Town
    }
}

-- put in all the spell ID's that MUST be learned at given lvl
GWB.DB.classic.trainer_info = {}
GWB.DB.classic.trainer_info.ROGUE = {
    -- COMBAT
    {53, 4}, -- Backstab (rank1)
    {1776, 6}, -- Gouge
    {1757, 6}, -- Sinister Strike (rank2)
    {5277, 8}, -- Evasion
    {2983, 10}, -- Sprint (rank1)
    {2589, 12}, -- Backstak (rank2)
    {1766, 12}, -- Kick (rank1)
    {1758, 14}, -- Sinister Strike (rank3)
    {1777, 18}, -- Gouge (rank2)
    {2590, 20}, -- Backstab (rank3)
    {1759, 22}, -- Sinister Strike (rank4)
    {1767, 26}, -- Kick (rank2)
    {2591, 28}, -- Backstab (rank4)
    {1760, 30}, -- Sinister Strike (rank5)
    {8629, 32}, -- Gouge (rank3)
    {8696, 34}, -- Sprint (rank2)
    {8721, 36}, -- Backstack (rank5)
    {8621, 38}, -- Sinister Strike (rank6)
    {1768, 42}, -- Kick (rank3)
    {11279, 44}, -- Backstab (rank5)
    {11285, 46}, -- Gouge (rank4)
    {11293, 46}, -- Sinister Strike (rank7)
    {11280, 52}, -- Backstab (rank7)
    {11294, 54}, -- Sinister Strike (rank8)
    {1769, 48}, -- Kick (rank4)
    {11305, 58}, -- Sprint (rank3)
    {11281, 60}, -- Backstab (rank7)
    {11286, 60}, -- Gouge (rank5)
    -- ASSASSINATION
    {6760, 8}, -- Eviscerate (rank2)
    {5171, 10}, -- SLice and Dice (rank1)
    {703, 14}, -- Garrote (rank1)
    {6761, 16}, -- Eviscerate (rank3)
    {8676, 18}, -- Ambush (rank1)
    {1943, 20}, -- Rupture (rank1)
    {8631, 22}, -- Garrote (rank2)
    {6762, 24}, -- Eviscerate (rank4)
    {8724, 26}, -- Ambush (rank2)
    {1833, 26}, -- Cheap Shot
    {8639, 28}, -- Rupture (rank1)
    {8632, 30}, -- Garrote (rank3)
    -- TODO: lvl 31~60
    -- DEDENSE
    {3127, 12}, -- Parry
    -- DUAL WIELD
    {674, 10}, -- Dual Wield
    -- LOCKPCKING, skip
    -- POISONS, yeah, once quest is automated ;_;
    -- SUBTLETY
    {1784, 1}, -- Stealth (rank1)
    {6770, 10}, -- Sap (rank1)
    {1785, 20}, -- Stealth (rank2)
    {1856, 22}, -- Vanish (rank1)
    {2070, 28}, -- Sap (rank2)
    {2094, 34}, -- Blind
    {1860, 40}, -- Safe Fall ?
    {1786, 40}, -- Stealth (rank3)
    {1857, 42}, -- Vanish (rank2)
    --{17347, 46}, -- Hemorrhage (rank2) -- TALENT?
    {11297, 48}, -- Sap (rank3)
    -- 17348, Hemmorage rank3
    {1787, 60}, -- Stealth (rank4)
}

-- lvl 60 spell, 5g40s, 900/lvl
-- lvl 4 spell, 1s, 25/lvl
-- lvl 10 spell, 3s, 30/lvl
-- lvl 20 spell, 30s, 150.lvl
-- lvl 30 spell, 1g, 333/lvl
-- lvl 46 spell, 3g10s, 674/lvl
-- lvl 52 spell, 4g60s, 884/lvl


local bandages = {
  -- itemID, minSkill, maxSkill
  {1251, 1,20},
  {2581, 20,50},
  {3530, 50,75},
  {3531, 75,151},
  {6450, 100,125},
  {6451, 125,151},
  {8544, 151,175},
  {8545, 175,200},
  {14529, 200,225},
  {14530, 225,300},
  {21990, 300,325},
  {21991, 325,999},
}
  

local InstantPoisonIDs = {
  {6947, 20,28, "Instant Poison"},
  {6949, 28,36, "Instant Poison II"},
  {6950, 36,44, "Instant Poison III"},
  {8926, 44,52, "Instant Poison IV"},
  {8927, 52,60, "Instant Poison V"},
  {8928, 60,68, "Instant Poison VI"},
  {21927, 68,200, "Instant Poison VII"},
}

local DeadlyPoisonIDs = {
  {2892, 30,38, "Deadly Poison"},
  {2893, 38,46, "Deadly Poison II"},
  {8984, 46,54, "Deadly Poison III"},
  {8985, 54,60, "Deadly Poison IV"},
  {20844, 60,62, "Deadly Poison V"},
  {22053, 62,70, "Deadly Poison VI"},
  {22054, 70,200, "Deadly Poison VII"},
}

local CripplingPoisonIDs = {
  {3775, 20,50, "Crippling Poison"},
  {3776, 50,200, "Crippling Poison II"},
}


