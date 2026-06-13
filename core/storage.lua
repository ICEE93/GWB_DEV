local Nn, GWB, _storage = ...

local storage = {}

--config.vendor = {}

storage.inventory = {}
storage.inventory.limitItemUsage = true -- limit item usage to items we obtained?
-- if items are stacked onto our time, it means we tainted?
storage.inventory.collectedItems = {} -- items that can be touched

local a = UnitName("player") or "unknown"
--storage.jsonSavePath = GWB.StorageMgr:GetSto -- "/scripts/bot/config_" .. a .. ".json"


GWB.Storage = storage

