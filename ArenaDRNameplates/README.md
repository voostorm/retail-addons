# ArenaDR Nameplates

ArenaDR Nameplates is a World of Warcraft addon for Midnight (`12.1`) that copies Blizzard arena diminishing return tracking onto enemy nameplates.

It mirrors Blizzard's arena DR tray data into its own nameplate-safe frames during arena matches and adds cleaner timer text, optional DR state text, configurable colors, and flexible placement controls.

It can also mirror the enemy trinket cooldown on the same nameplate mapping, using a separate settings page so the extra icon stays optional.

## Features

- Shows arena DR icons on enemy nameplates during arena matches.
- Optionally mirrors arena DRs for the current target and focus on two independently positioned bars.
- Optionally shows the enemy trinket cooldown on enemy nameplates during arena matches.
- Uses a modular nameplate adapter layer, with Blizzard, BetterBlizzPlates, Platynator, Plater, Threat Plates, ElvUI, and EllesmereUI Nameplates support.
- Keeps timer text centered and readable on each icon, with an option to hide it.
- Offers one deduplicated Blizzard and LibSharedMedia font selector for DR timers, trinket timers, and DR state text.
- Optionally shows one decimal place below a configurable 1-20 second threshold (5 seconds by default) using WoW's native cooldown API.
- Can either follow nameplate scale changes or keep DR icons at a fixed visual size.
- Supports optional DR state text overlays with separate normal and immune colors.
- Supports None, Solid, and Classic DR border styles with separate normal and immune border colors.
- Lets you hide or show Blizzard's immunity badge.
- Keeps the trinket icon disabled by default and configurable through its own tab, including None, Solid, and Classic border styles.
- Includes placement presets plus advanced anchor point controls.
- Includes a preview mode for nearby enemy nameplates.
- Exports and imports setup strings for sharing layout, timer, trinket, and border settings.
- Includes a standalone options window plus a Blizzard Settings launcher page.

## Requirements

- World of Warcraft Midnight (`12.1`)
- Blizzard arena frames and enemy nameplates enabled

## Installation

1. Place the addon folder at `Interface\AddOns\ArenaDRNameplates`.
2. Start the game or run `/reload`.
3. Open the addon settings with `/arenadr` or `/arenadr config`.
4. You can also open the launcher entry from `Options -> AddOns -> Arena DR Nameplates`, then click `Open options window`.

## Usage

The addon activates in arena and mirrors Blizzard's DR tray into its own nameplate frames when a matching arena unit can be resolved.

The optional Target/Focus tracker uses that same Blizzard-owned arena DR source. It does not inspect or reconstruct protected aura data, and therefore remains arena-only on Retail 12.1. Target and Focus each have their own movable screen position and scale, with optional independent timer-text size and color overrides. Their placement handles are unlocked by default and initially follow `TargetFrame` and `FocusFrame`. Layout, spacing, DR text, and border styling remain shared.

If enabled, the addon also mirrors Blizzard's enemy trinket source frame onto the same resolved nameplate target, with independent size, opacity, border, and placement settings.

If Platynator is loaded, the addon automatically anchors to Platynator's live health bar widget instead of Blizzard's hidden unit frame.
If Plater is active, the addon anchors to Plater's custom health bar, and falls back to Plater's visible name text when the health bar is hidden.
If Threat Plates is active for the plate, the addon uses Threat Plates' exported anchor helper so headline and healthbar modes both resolve correctly.
If ElvUI nameplates are active, the addon anchors to ElvUI's `Health` status bar instead of the full ElvUI plate.
If EllesmereUI Nameplates is active, the addon anchors to its custom `health` status bar instead of the hidden Blizzard frame.
If BetterBlizzPlates is active, the addon keeps its native Blizzard anchor and moves a horizontal Below tray beneath BBP's visible castbar to avoid overlap.

Preview mode shows randomized sample DR trays on nearby hostile nameplates. My DRs and the Target/Focus bars appear only when their feature is enabled, and Target and Focus also respect their individual visibility toggles. Preview does not persist across reloads or zone changes and stops automatically during those transitions.

## Slash Commands

- `/arenadr` opens the standalone options window
- `/arenadr config` opens the standalone options window
- `/arenadr test`
- `/arenadr reset`
- `/arenadr scale <value>`
- `/arenadr share` opens the Share tab
- `/arenadr export` generates the current setup string
- `/arenadr import <export string>` imports a shared setup
- `/arenadr perf` records addon performance for 60 seconds and prints an aggregated report

The performance report lists calls, total time, average time, and maximum time for mapping, runtime reconciliation, trinket, and preview paths. Running `/arenadr perf` again while a capture is active shows the remaining time without restarting it.

## Settings Overview

- `General`: preview, reset, shared text font, icon display, nameplate scaling behavior, placement presets, advanced anchor controls
- `Trinket`: optional enemy trinket icon, visibility mode, appearance, border, and placement
- `Timers`: swipe toggle, edge highlight, timer text and decimal toggles, color, size, and offsets
- `DR Text`: toggle, anchor, scale, offsets, normal color, immune color
- `Borders`: border width, normal and immune colors, Blizzard immunity badge toggle
- `My DRs`: personal DR tracking with an initially unlocked position following `PlayerFrame`
- `Share`: export and import setup strings for sharing settings between players
- `Target/Focus`: optional arena Target and Focus bars, visibility, shared icon spacing, separate scale/position controls, and independent timer-text size/color overrides

## Saved Variables

- `ArenaDRNameplatesDB`

## Support & Links

- Download: [CurseForge](https://www.curseforge.com/wow/addons/arena-dr-nameplates)
- Source: [GitLab](https://gitlab.com/Anahkas/ArenaDRNameplates)
- Bug reports and feature requests: [Discord](https://discord.gg/GH9KGcgKQz)

## Addon Files

- `Adapters/Registry.lua`: adapter registry and shared helper functions for nameplate integrations.
- `Adapters/Blizzard.lua`: default Blizzard nameplate adapter.
- `Adapters/BetterBlizzPlates.lua`: BetterBlizzPlates native-frame and castbar-aware layout adapter.
- `Adapters/Plater.lua`: Plater nameplate adapter.
- `Adapters/Platynator.lua`: Platynator nameplate adapter.
- `Adapters/ThreatPlates.lua`: Threat Plates nameplate adapter.
- `Adapters/ElvUI.lua`: ElvUI nameplate adapter.
- `Adapters/EllesmereUI.lua`: EllesmereUI Nameplates adapter.
- `ArenaNameplateHelper.lua`: maps `arena1-3` units to visible enemy nameplates and exposes anchor helpers/callbacks.
- `Performance.lua`: opt-in, session-scoped performance aggregation used by `/arenadr perf`.
- `Core.lua`: runtime behavior, live tray anchoring, preview mode, slash commands, and saved variable defaults.
- `TargetFocusDR.lua`: arena-safe Target and Focus DR mirrors backed by the addon's Blizzard tray mirror.
- `Settings.lua`: initializes the standalone options workflow after login.
- `UI/StandaloneOptions.lua`: standalone options window, launcher entry, and option widgets.

