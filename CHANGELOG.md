# Changelog

All notable changes to the Generic WoW Bot (GWB) project will be documented in this file.

## [Unreleased]
- **Core (Routine):** Implemented Advanced Routine Recorder in `routineManager.lua`. Supports auto-simplification (Douglas-Peucker) for waypoints to keep profiles small and organic.
- **Core (Routine):** Built `Default_RoutinePlayback` plugin to handle playback of JSON-saved routines. Includes automatic gossip replication and quest acceptance/turn-in hooks.
- **UI:** Added new Recorder UI window for profile creation (Middle-Click Minimap or click World Map 'Recorder' button).
- **Core (Utils):** Added `InteractOrApproach` utility to prevent long-range interaction deadlocks. Applies globally to ensure the player approaches `< 4.5` yards before sending `ObjectInteract()`.
- **EZNavSafe:** Fixed A* Engine crash caused by a typo (`lz=lz` instead of `z=lz`) in the partial path fallback logic.
- **UI (Map):** Fixed a map-draw crash (`attempt to perform arithmetic on local 'x' (a nil value)`) when waypoints pushed by external modules lacked 2D coordinates.
- **Core (Inventory):** Implemented loot tracking via the `BAG_UPDATE` event in `inventoryManager.lua`. It now calculates item diffs and fires a generic `OnItemLooted` callback.
- **Core (Inventory):** Built a generic `GetBestConsumable` function that dynamically iterates database requirements against the player's level to locate the optimal food/drink in the player's bags.
- **Core (Inventory):** Added a global `GetAverageDurability` helper function to easily compute gear durability state.
- **RestHandler:** Hooked up inventory parsing logic to dynamically consume the highest-tier food and water available rather than relying on natural regen ("rawdogging").
- **TownHandler:** Implemented "Sell ALL" logic, ensuring all grey (Poor) quality items and tracked vendor trash are sold regardless of legacy tracking bugs.
- **TownHandler:** Implemented critical fleeing logic. If attacked while running to town for repairs and average durability is below 10%, `TownHandler` will successfully suppress `CombatHandler` to flee rather than fighting with broken gear.
- **Core (Navigation):** Implemented movement humanization. The bot now applies a randomized jitter (`± 0.5 - 1.0` yards) to its navigation waypoints so it doesn't run the exact same path linearly. It also has a small random chance to jump while running straight lines.
- **Core (Navigation):** Added an interaction delay of 400-1200ms when stopping to interact with an object (e.g. looting a corpse) rather than clicking it on the very frame movement stops.
- **CombatHandler:** Added reaction humanization. The bot now takes 1.5 - 3.0 seconds to pick a new target in its aggro radius, and randomized delays (0.2s - 0.8s) for updating facing/rotation, preventing perfectly mechanical snapping.
- **TownHandler:** Added pacing humanization. The bot now takes 0.8 - 2.5 seconds between buying/learning operations at merchants and trainers.
- **Core (Settings UI):** Overhauled the Active Profile selector. It now uses a Dropdown menu that automatically scans the `storage/` directory to list available `.json` profiles, making it drastically easier to switch between configs.
- **Core (Storage):** Added an "Active Profile" selector to the `GWBConfigFrame` UI. Users can now share config profiles between characters by entering a profile name. If empty, it defaults back to using the character's name (`storage_<PlayerName>.json`).
- **TownHandler:** Fixed a major bug where the bot would incorrectly path to the Warlock trainer in Northshire while on a Rogue. The Rogue trainer ID in the database was a copy-paste error (`459` -> `915`), and `Default_TownHandler` was incorrectly hardcoded to always query `ROGUE` spell lists regardless of the player's actual class. It now correctly uses `UnitClass("player")`.
- **Core:** Fixed `GWB.Utils.SafeNumber()` utility to correctly unwrap retail WoW's "secret number" values (`UnitHealth`, `UnitPower`, etc.). Corrected the capitalization to use the exact `Nn.issecretvalue` and `Nn.secretunwrap` framework API endpoints, resolving the `attempt to perform arithmetic on 'hp'` crash on retail.
- **RestHandler:** Wrapped all `UnitHealth`/`UnitPower` calls with `SafeNumber` — fixes `attempt to perform arithmetic on 'hp' (a secret number value)` crash on retail.
- **Warlock CR:** Wrapped `UnitPower`/`UnitPowerMax` mana check with `SafeNumber` for retail.
- **TownHandler:** Fixed `Invalid inventory slot in GetInventorySlotInfo` by wrapping the call in `pcall` with a hardcoded fallback slot ID map for retail where string slot names are no longer accepted.
- **Core**: Built standalone `GWB.EZMover` object to bypass obfuscated engine and enable async pathing via `UseEZNavSafe`.
- **Navigation API:** Globally hooked all `GWB.Mover` methods (`MoveToXYZ`, `MoveToObject`, `Stop`, `HaltMovement`, `IsMoving`) in `navigation.lua` to intelligently proxy commands to `EZMover` if `UseEZNavSafe` is enabled, resolving the issue where plugins like `CombatHandler` and `TownHandler` were forcefully falling back to legacy NnNav.
- **EZMover:** Added Raycast Whiskers collision avoidance logic inside `EZMoverTick` (ported from Skirmisher) to smoothly sweep around dynamic obstacles that aren't on the navmesh.
- **EZMover:** Added `OnMovementFinished` callback dispatching when arriving at destinations or specific objects so the CombatHandler can successfully loot and skin.
- **EZMover:** Added a short-distance bypass for `MoveToXYZ` (if target is < 1.5 yards) to prevent `GeneratePath` from failing on very short path requests, which was breaking looting for enemies that died at the player's feet.
- **EZMover:** Hooked `GWB.Mover.StartMove` to correctly resume `GWB.EZMover` after combat. This fixes the legacy pathing bug where the bot would mistakenly call NnNav and attempt to path to `0, 0, 0` when leaving combat.
- **Combat Logic:** Fixed `OnLootStarted` failing silently in Classic Era due to referencing retail's `LootFrame.isOpen` instead of `LootFrame:IsVisible()`. The bot will now correctly auto-loot the items from the window.
- **Combat Logic:** Re-engineered the post-combat looting loop in `Medium_CombatHandler`. It now waits for the loot window to be fully processed, using `ObjectLootable(corpse)` checks to clear targets dynamically, rather than instantly wiping the target on arrival and entering a stutter loop.
- **Combat Logic:** Fixed an issue where `OnBotScanTick` would continuously spam-scan and overwrite the target every tick. It now gracefully aborts if you already have a valid target.
- **Combat Logic:** Resolved a massive state-machine flip-flop loop between `Waypoints` and `CombatHandler` that was causing severe target spamming.
- **Combat Logic:** The Rogue Combat Routine will now immediately `StartAttack()` as it approaches an enemy out-of-combat, mimicking a human "right-click" instead of just standing and waiting for melee range.
- **Navigation API:** Shimmed `GWB.Mover.Tick`, `Update()`, `GetPlayerPosition()`, and `GetTargetXYZ()` to no-op or use `ObjectPosition` when EZNavSafe is active, preventing the obfuscated legacy mover from running in the background and firing spurious NnNav calls.
- **EZMover:** `Stop()` now fully resets internal state (clears last destination), preventing `StartMove()` from accidentally resuming cleared movement.
- **UI:** Stop button now explicitly calls `GWB.EZMover:Stop()`, `GWB.Mover:Stop()`, and `ClickToMove` to player position to ensure the character physically halts.
- **UnstuckHandler:** Fixed `GWB.Mover.IsMoving()` dot-call to `GWB.Mover:IsMoving()` colon-call so the navigation hook intercepts it.
- **Post-Combat Looting:** Complete rework — `tickPostCombat` now clears live targets, tries direct `ObjectInteract` when within 5 yards (bypassing pathing entirely), and sets `GWB.isPostCombatLooting` flag to prevent other systems from interfering.
- **EZMover:** Fixed the root cause of EZNavSafe looting failure — when EZMover arrived at a target object, it never stopped ClickToMove or called ObjectInteract. The WoW client silently ignores ObjectInteract while ClickToMove is active. EZMover now stops movement, interacts with the object, then fires the callback. All direct interact calls in CombatHandler also stop ClickToMove first.
- **Waypoints:** Added `isPostCombatLooting` guard so the waypoint ticker yields entirely during post-combat looting instead of fighting the mover.
- **Waypoints:** Fixed another dot-call `GWB.Mover.IsMoving()` in `DoActiveEngage`.
- **Rogue CR:** Removed per-tick `StartAttack` spam; now fires once per unique target GUID. Removed redundant `Attack` from combat ticker.
- **Medium Waypoints:** Updated waypoint logic to route through `GWB.EZMover` when configured.
- **Initialization:** Fixed load order in `init.lua` so `navigation.lua` properly loads after `engine.lua` defines the Ticker API.
- **EZNavSafe:** Added fallback to load `.mmtile` files without underscores (e.g. `00003248.mmtile`) for Classic Era compatibility.
- **UI**: Fixed `GetPointsForCurrentMap` to read the player's physical zone via `C_Map.GetBestMapForUnit("player")` instead of checking the actively viewed UI map.

## [2026-06-12]
- fix: resolve json saving by creating storage directory before write
- fix: compact settings UI layout to prevent text clipping
- feat: persist dynamic plugin UI settings to storage json
- feat: sync GWB/init.lua with GWB_DEV/init.lua paths
- feat: create _GWBloader.lua proxy script for easy dev loading
- feat: add settings UI to toggle EZNavSafe path generation
- feat: add dynamic plugin settings UI menu to minimap right-click
- docs: create architecture.md and establish CHANGELOG
- refactor: migrate core engine and ui scripts into subdirectories
- fix: implement single bulk purchase for merchant items
- feat: add classic warlock combat routine opening rotation
- fix: correct world map UI anchoring to prevent obscurement
- **TownHandler:** Fixed target oscillation and MoveToXYZ stutter flip-flopping by caching the town NPC targets individually, and adding a destDist check to prevent restarting active movement.
- **Core (Navigation):** Implemented ClickToMoveSafeZ logic to prevent clicking into the sky. It now traces downward (0x111) to find the correct terrain height at the requested XY coordinate before triggering ClickToMove.
- **Core (Logic):** Fixed premature timeouts when pathing to distant enemies or corpses. The 15-second combat engagement timeout and 7-second looting timeout now dynamically refresh as long as the player's distance to the target is actively decreasing. This ensures the bot never gives up while making progress towards a far target, but will still properly timeout if hard-stuck.
