# Generic Wow Bot

Simple WoW bot for doing waypoint movement!

Currently dev it for Warlock/Rogue grinding in Elwyn Forest. No decent CR nor Spell related APIs exist tho.

## Features

These exists, but there is no GUI yet. You may want to check `./modules/Classic_Human_Rogue_1-10.lua` to get a better understanding. The only UI exist is the start/stop and reset button when opening map. Can also SHIFT+CLICK map to create Waypoints.

- Town handler
- - Sell junk
- - Auto Repair
- - Buy goods (food/drink)
- Waypoints
- - Walk waypoints and aggro mobs
- Ghost Handler
- - Walk back to corpse on death
- Rest Handler
- - Wait before entering combat
- - Consume food/drink while resting
- Drawings
- - Draw waypoints and pathing
- Trainer Handler
- - Class Trainer (Rogue lvl60, unfinished)

## Vibe-driven development

This project aims to support “vibe-driven” development—using AI coding tools—without letting the codebase devolve into AI slop.

The idea is to build small, isolated `plugins` that can be quickly vibe-coded to handle simple but tedious tasks (like vendoring items, choosing the best consumables for your level, etc.), without turning the whole project into a Jenga tower that falls apart.

The core design relies on callbacks and shared state to keep experimental components contained. This avoids sprawling chains of fragile `if` statements—_the kind that collapse the moment an AI agent hallucinates or makes a wrong assumption._

## Support

There is no support, check issues or create a PR/patch

## Todo

Many integration issues...

## Notes

- Does not have Combat Rotations build-in!