# Changelog

All notable changes to the Generic WoW Bot (GWB) project will be documented in this file.

## [Unreleased]
- **Navigation:** Restored the whisker-based dynamic steering (`ClickToMoveWithWhiskers`), but resolved conflicts by forcefully pausing whiskers while the `UnstuckHandler` is active. Increased the whisker fallback distance from 2.5 to 5.0 yards to prevent false stuck triggers caused by micro-stuttering.
- **Core:** Added automatic `LoadSettings` invocation via `init.lua` to ensure Autopilot toggle correctly synchronizes from saved settings without opening the UI manually.
- **QuestHandler:** Normalized internal Questie active objectives (`"monster"`, `"object"`, etc.) to `"active"`, ensuring Autopilot correctly assigns them navigation priority instead of ignoring them.
- **QuestHandler:** Dynamically calculate the maximum quest log limit using `C_QuestLog.GetMaxNumQuestsCanAccept()`, fixing a bug on the Midnight (12.0) client where the bot thought the log was full at 20 quests and stubbornly ignored all new quest pickups.
- **QuestHandler:** Implemented Target Isolation for Questie Autopilot pins. The bot will now aggressively ignore hostile mobs that belong to quests other than its active Autopilot pin.
- **QuestHandler:** Fixed a 1-frame race condition where targeting systems would latch onto nearby mobs before the Autopilot pin could calculate during UI reload.
- **QuestHandler:** Redesigned Autopilot scoring algorithm to prioritize active local quests regardless of level difference, preventing unwanted cross-zone navigation.
- **QuestHandler:** Reversed quest objective prioritization to always finish active quests before turning them in or acquiring new ones.
- **QuestHandler:** Re-enabled generic string matching for GameObject interactions, enabling support for gathering quests like Milly's Harvest.
- **Core:** Implemented missing `InteractOrApproach` utility method in `core/utils.lua` to fix broken vendor and repair NPC interactions.
- **RestHandler:** Converted `UseContainerItem` to simulate a hardware event via `SecureActionButtonTemplate`, properly unlocking food and water consumption.
- **CombatHandler / Waypoints:** Halts movement and prevents pulling new targets while the player is actively casting or channeling (e.g., gathering nodes, looting).
- **QuestHandler:** Fixed quest mob filtering in Questie Autopilot mode. The bot now properly skips non-quest mobs when Questie Autopilot is enabled, preventing unwanted combat with random creatures.
- **CombatHandler:** Fixed autoTarget function to use OR condition instead of AND for quest filtering. This ensures quest mob filtering applies when either Questie Autopilot is enabled OR Questie integration is available.
- **UI (Map):** Simplified Questie availability check to use QuestHandler's IsQuestieObjectiveFast function instead of direct Questie global variable access, improving reliability.
- **UI (Map):** Added throttling to quest filter debug logs to prevent chat spam (logs once every 2 seconds instead of per mob).
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
- **Core (Navigation):** Fixed a bug where A* pathing would cause the bot to run backwards to the first generated navmesh node instead of proceeding to the NPC. Paths are now automatically trimmed to skip nodes behind the player, and targets closer than 5.5 yards are bypassed entirely.
- **Core (Waypoints):** Added dynamic circular jitter to the grinding waypoints. The bot now rerolls a persistent (-2.0 to +2.0) yard offset for each waypoint every lap, guaranteeing it never clicks the exact same coordinate twice while maintaining stable local pathing.
- **TownHandler:** Fixed the infinite oscillation loop near town NPCs. Previously, the handler would overwrite the active NPC interaction sequence every 5 seconds by forcefully sending the player back to the static database coordinate. It now correctly hands off movement to InteractOrApproach once within 4.5 yards.
- **RoutinePlayback:** Fixed a startup crash (ttempt to index field 'RoutinePlayback' (a nil value)) caused by an uninitialized namespace table.
- **LootHandler:** Fixed an issue where the bot would run away from corpses post-combat before returning to loot. This was caused by the bot retaining its forward movement path while waiting for the pathfinder to generate a route to the corpse, compounded by a missing grace period for server-side loot flags. The player is now instantly halted upon exiting combat, and the scanner waits up to 1.5s for the lootable flag to appear before giving up.
- **Waypoints vs CombatHandler (Tug of war):** Fixed an infinite loop where the bot was stuck spamming halted by Stop while trying to approach a target. Medium_Waypoints was repeatedly forcefully stopping the player because it thought the bot shouldn	 move toward waypoints while a target was acquired, but Medium_CombatHandler was simultaneously commanding the bot to move toward the target to engage. We disabled Waypoints` redundant Halt calls when a target is active so CombatHandler can seamlessly move the bot to the target. 
- **LootHandler:** Fixed an ttempt to perform arithmetic on global 'lastLootDist' nil error caused by a missing local variable declaration.
- **TownHandler / Modules:** Fixed an ttempt to index local 'townHandler' nil error that occurred on startup for the Rogue and Warlock routines by adding a safety check to make sure the plugin is loaded before injecting profile settings.
- **Core State:** Paused utoTarget() and movement/combat routines from running while the bot is disabled via IsBotRunning(). This prevents the bot from aggressively finding targets or running waypoints as soon as the scripts load but before hitting start.
- **Routine Recorder:** Fixed bugs causing the recorder to drop interactions. It now properly saves object_interact steps when looting GameObjects, robustly identifies the target of interaction using fallbacks (PlayerTarget/Mouseover) if GetNPCObject() is nil, and grabs the correct Unit ID for NPCs instead of erroneously outputting zero.
- **Routine Recorder:** Fixed a UX issue where stopping the recording would instantly wipe the visual step list from the UI. The recorder now persists the finished routine into memory so it stays visible and is immediately ready to be test played.
- **Core State:** Fixed ttempt to call method 'IsBotRunning' (a nil value) error spam by correctly referencing the GWB.Map:IsRunning() UI state check instead of an invalid method name.
- **UI / Core State:** Fixed a critical state-tracking bug where the bot incorrectly believed it was paused the moment it entered combat or approached an NPC. GWB.Map:IsRunning() now properly scans the entire state stack instead of strictly checking if the top-most state is plugin.Waypoints. This restores combat execution and fixes the UI minimap button inaccurately displaying Stopped while the bot was still active.
- **Rogue Routine:** Fixed spell spamming. Added proper UnitPower and GetComboPoints resource checks to Sinister Strike and Eviscerate so the bot no longer endlessly tries to cast spells it doesn't have energy for.
- **LootHandler:** Fixed an issue where the bot was completely unable to loot. Previously, the bot was rapidly spamming ObjectInteract every 0.1s and sending a ClickToMove command to its own coordinates, which forcibly canceled the interaction and continually interrupted the server's Auto-Loot action before the items could be pulled into the inventory. The interaction is now properly debounced with a 2-second grace period.
- **Movement/Navigation:** Removed random jitter on intermediate nav-mesh nodes which was causing super jank zig-zag movement and OnMovementFinished chat spam.
- **StorageManager:** Silenced repetitive chat prints when saving to disk.
- **Recorder:** Fixed an issue where stopping a recording and then saving would write an empty session to disk instead of the recorded steps.
- **Recorder:** Fixed NPC interaction recording so it properly records the NPC ID using Object(" npc\) and added error handling to the OnGossipStart event to prevent silent failures.
- **Quests:** Created Medium_QuestHandler.lua to dynamically scan nearby objects/NPCs (within a 40 yard radius) and cross-reference them with active WoW Classic quest objectives.
- **Movement/Waypoints:** Fixed the issue where Waypoints would aggressively fight against Combat and Looting by cleanly yielding movement control when engaged with an enemy, looting, or pursuing a quest target.
## [2026-06-15]
- **LootHandler:** Added a 1.5-second pause after looting to prevent the bot from instantly snapping to the next coordinate.
- **CombatHandler:** Added a 1.5-second pause upon exiting combat, and completely refactored autoTarget to prevent chain pulling and group pulling by checking 18-yard proximity around targets.
- **CombatHandler:** Fixed a bug where Waypoints wouldn't yield during combat by explicitly pushing the CombatHandler state to the state machine.
- **Waypoints/Map:** Disabled scanning for quest objectives and active engagements while the player is dead or a ghost.
- **GhostWalk:** Implemented smart resurrection logic that scans for hostiles and resurrects at maximum safe distance (up to 38 yards) instead of walking blindly to the corpse.
- **Navigation:** Doubled 360-degree whiskers from 32 to 64 rays for higher resolution obstacle avoidance.
- **Navigation/Waypoints:** Implemented extreme aggro-avoidance routing when walking to quest turn-ins or accepts.
- **QuestHandler:** Fixed a nil value error in blacklisting by replacing ObjectGUID with ObjectPointer.
- **Settings:** Made DisableCR persistent across reloads.
- **RestHandler:** Enabled eating food/drink from bags and added First Aid bandaging support.

- **Navigation:** Completely rewrote the whisker collision array to use proactive distance brackets (12, 8, 4, 2 yards) so the bot sweeps and steers early when approaching obstacles instead of waiting until it hits them.

- **Waypoints:** Fixed a major issue where the bot would try to interact with NPCs or blackbox Zygor pins through ceilings/floors. It now respects the Z-axis (height) and will continue pathing to the stairs instead of getting stuck below targets on the 2D plane.

- **Navigation/Whiskers:** Fixed a critical terrain bug where downward-angled whiskers (-60 degrees) would constantly hit flat ground, triggering a false-positive 'obstacle detected' state that completely disabled steering. The system now traces two parallel rays at Knee and Chest height that dynamically pitch to match the terrain slope. This allows the bot to fluidly glide up and down hills while only ever steering away from genuine protruding obstacles (walls, trees, fences).

- **Navigation:** Added steering memory so the whiskers prefer sticking to the side they recently chose, completely preventing rapid left-right erratic jittering.
- **Waypoints:** Fixed an issue where the waypoint engine would incorrectly force itself to step and fight with CombatHandler during combat.
- **QuestHandler:** The objective scanner now strictly evaluates all possible targets in range and paths to the mathematically closest one instead of the first one it finds in memory, preventing you from ninja pulling distant mobs.


- **TownHandler:** Protected common gathering tools (Mining Pick, Skinning Knife, Blacksmith Hammer) from being automatically sold.
- **TownHandler:** Added explicit protection to prevent the bot from selling Quest Items (classID 12).
- **ReleaseSpiritOnGhost:** Fixed a ghost-walking bug where the bot would spam path generation and stop moving due to incorrect tracking variable assignments.
- **ObjectManager:** Refactored object enumeration across `core` to use the optimized `ObjectManager(type)` instead of generic `Objects()` loops, massively boosting performance.
- **CombatHandler:** Fixed syntax and scoping issues in targeting logic and improved validation in movement loops.
- **LootHandler:** Resolved a nasty closure bug involving `C_Timer.After` inside `OnLootStarted` that would throw errors during combat loot checks.
- **State Machine:** Fixed `TownHandler` and `RestHandler` dropping state incorrectly when interrupted by combat.
- **Waypoints:** Resolved a bug where `GWB.Mover.IsMoving` was incorrectly called using dot notation instead of method syntax (`:`).
- **Warlock (Soulstone):** Addressed a scoping issue where the `CanUseSoulstone` check shadowed the global WoW API function.

### New Features
- **GatherBot (`Medium_GatherBot.lua`):** Added a new, fully integrated automation plugin to safely path to and gather nearby mining nodes and herbs.
  - Exposes settings toggles for turning the bot on/off and specifically toggling mining vs. herbalism targets.
  - Automatically filters tapped nodes via dynamic flags and gracefully yields pathing control back to `CombatHandler` if you are attacked.
  - Includes an exhaustive name database for ores and herbs alongside programmatic Tooltip scanning (looking for "Requires Mining" or "Requires Herbalism") to robustly discover new expansion nodes automatically.
  - Restricts the plugin execution explicitly to `classic|retail` environments using the `xpacs` configuration flag.

### Core Systems Updates
- **EZNavSafe (NavMesh Raycasting):** Implemented a native `Nav.Raycast` feature in the A* engine. This traces lines directly across the invisible navigation polygons (navmesh). If a straight line safely crosses walkable polygons without traversing cliffs, oceans, or empty voids, it mathematically guarantees the shortcut is safe.
- **EZMover (A* Path Smoothing):** `GWB.EZMover` now scans up to 6 nodes ahead on its generated path. If `Nav.Raycast` confirms a safe shortcut, it instantly trims the intermediate nodes, creating incredibly smooth, human-like corner cutting.
- **Waypoints (Farming Smoothing):** Added a lookahead A* Raycast to `Medium_Waypoints.lua`. When traversing dense farming points, it will scan up to 10 points ahead. If a future point is safely walkable in a straight line, it will skip the zig-zag micro-points and take the safe shortcut, eliminating the "walking backward" behavior entirely.
- **Navigation (Water Avoidance):** The Whisker Array now dynamically traces for `Liquid` surfaces (`0x20000`). If deep water (>1.2 yards) is detected in the player's path, the engine treats it as a solid brick wall, seamlessly steering the bot around lakes and deep rivers.
- **Navigation (Cliff & Edge Detection):** The Whisker Array now projects a vertical line downward at every potential forward step. If the ground drops more than 2.5 yards (a cliff/hole) or rises more than 1.5 yards (a steep mountain wall), the engine marks the path as blocked, preventing the bot from falling or getting stuck climbing.
- **QuestHandler (Water Avoidance):** Quest objective evaluation now projects a vertical ray downward from all potential targets to measure water depth. If an objective is submerged in deep water, it is penalized with a massive distance score (+50000), guaranteeing the bot will prioritize dry targets unless absolutely necessary.
- **StateManager:** Fixed a crash (`attempt to index field 'handlers'`) that occurred when a plugin state failed to export a `handlers` table.

### Unstuck Updates
- **Default_UnstuckHandler:** Completely rewrote the stuck detection mechanism. It now uses absolute timestamps (`GetTime()`) instead of counting frame ticks. The bot will now patiently wait 3 seconds before attempting jump maneuvers, and 5 seconds before entering the hard unstuck state, vastly reducing false positives.

