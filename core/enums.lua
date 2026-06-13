local Nn, GWB, enums = ...

GWB.enums = {}

GWB.enums.cb_action = {
    ["SKIP"]        = 0, -- nothing, ignore it
    ["ATTACK"]      = 1, -- engage/attack (we walk in combar range)
    ["LOOT"]        = 2, -- Interact with the not-already-looted coprse
    ["LOOT_2"]      = 3, -- after LOOT, for skinning/herb/engineering a already-looted corpse
    ["INTERACT"]    = 4, -- Interact with object (GameObject)
    ["GOSSIP"]      = 5, -- dialog thing for NPC's
    --["REPAIR"]      = 6, -- Do we need this? isn't this GOSSIP but like, for certain types?

    ["RETRY"]       = 100, -- universal "try again" mode?
}


-- cb handler levels, higher will be first. Keep gaps for reserved?
GWB.enums.cb_priority = {
    ["DEFAULT"]       = 0,  -- debug system
    ["LOW"]           = 1,  -- default system
    ["MEDIUM"]        = 5,  -- basic plugin/setting?
    ["HIGH"]          = 10, -- overwriting logic?
    ["CRITICAL"]      = 30, -- idk tbh
}
