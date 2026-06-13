# GWB Architecture Overview

The Generic WoW Bot (GWB) uses a modular, plugin-based architecture centered around state machines and event callbacks.

## Core Modules
Located in `core/`, these scripts form the engine of the bot:
- **engine.lua**: The central event dispatcher. It hooks into the game's event system and dispatches callbacks to all registered plugins.
- **stateManager.lua**: Handles the bot's state machine (e.g., transitioning from `Waypoints` to `CombatHandler` to `RestHandler`).
- **mover.lua**: A pre-compiled movement engine responsible for physically walking paths.
- **navigation.lua**: Bridges the gap between the `mover` and the underlying navigation providers (`nnav` vs `eznavsafe`).

## Plugins
Located in `plugins/`, these scripts define specific behaviors (e.g., `Default_TownHandler.lua` for vendoring, `Medium_CombatHandler.lua` for fighting).
Plugins must register themselves using `GWB:RegisterPlugin(plugin)`. They can define `.settings` tables which are automatically exposed to the user in the UI.

## Modules (Profiles)
Located in `modules/`, these scripts configure the bot for specific tasks, such as a 1-10 leveling profile for a specific class. They dictate which waypoints to follow and what specific behaviors to enable.
