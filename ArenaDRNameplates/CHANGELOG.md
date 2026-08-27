# Changelog

All notable changes to this project should be documented in this file.

## 1.7.6 - Icon Growth Direction Fix
- Fixed Left, Right, and Center icon growth all expanding the same way for nameplate DR, My DRs, and Target/Focus trackers.
- Fixed the Left and Right growth option labels being swapped.
- Fixed switching to Custom position resetting the icon growth direction.

## 1.7.5 - Text Outline Option
- Added a Text Outline setting to General options for DR countdowns, trinket countdowns, and DR state symbols.
- Choose from None, Outline, Thick Outline, Monochrome, Monochrome Outline, or Monochrome Thick Outline.

## 1.7.4 - DR Preview and Scaling Fixes
- Added separate countdown text size and color controls for Target and Focus.
- Fixed Preview and placement frames appearing for disabled My DRs, Target, or Focus trackers.
- Fixed Stop Preview leaving Target or Focus DR text visible.
- Fixed icon sizing moving My DRs, Target/Focus, nameplate DR, and trinket positions.
- My DRs, Target, and Focus placement handles are now unlocked by default.
- My DRs, Target, and Focus now follow their matching Blizzard Unit Frames by default.

## 1.7.3 - DR Bar UI Consistency
- Unlocked Target and Focus bars now show labeled placement handles instead of sample DR icons.
- Target and Focus sample DR icons now appear only while Preview Mode is active.
- Added a My DRs label to the unlocked personal DR bar.
- Icon sizing now scales icons, timer text, DR text, borders, and spacing consistently across all trackers.

## 1.7.2 - My DRs and Target/Focus Performance
- Fixed the frame drops caused by the My DRs and Target/Focus trackers.
- The Target and Focus bars no longer rebuild themselves once per mirrored icon on every arena tick; the enemy DR mirror now only announces a change when something actually changed.
- Fixed the Target and Focus bars asking the arena tracker for a full resync every frame while an enemy tray was unavailable, which never settled.
- The My DRs tracker no longer rescans and restyles on every one of your aura events; it now only redraws when a diminishing return actually moved.
- Both trackers now settle once per frame instead of once per event, and reuse their styling until a setting changes.
- Disabling the Target and Focus tracker now really costs nothing.
- Settings are validated once per change instead of on every read.
- `/adr perf` now reports the My DRs and Target/Focus timings.

## 1.7.1 - Target and Focus Scaling Fixes
- Added independent Target and Focus bar scaling for icons, countdowns, and DR text.
- Fixed unlocked Target and Focus bars snapping back while being dragged.
- Fixed text overflowing the Timers and DR Text section in Target/Focus settings.

## 1.7.0 - Target and Focus DR Tracker
- Added optional arena DR bars for the current target and focus.
- Added separate visibility and position controls for the Target and Focus bars.
- Added size, opacity, spacing, layout, and border controls.
- Target and Focus bars use the existing Timers and DR Text settings.
- Target and Focus tracking continues when enemy nameplates are temporarily unavailable.
- Replaced the top tabs with a compact vertical navigation menu.

## 1.6.2 - DR Timer Fix
- Fixed enemy DR icons sometimes counting down during the crowd control instead of after it.
- Fixed enemy DR icons sometimes getting stuck on a nameplate with no countdown for the rest of the match.
- Fixed the My DRs tracker missing the moment a crowd control ends when no other combat event follows it.

## 1.6.1 - Platynator Adapter Fix
- Updated the Platynator nameplate adapter to keep working after Platynator's internal layout changes.
- Fixed DR icons sometimes anchoring to the wrong Platynator widget.

## 1.6.0 - Personal DR Tracker
- Added a My DRs tab that tracks the diminishing returns applied to you.
- Personal DR icons show the half stage and an immune state.
- The personal DR bar follows the Timers and DR Text tabs, each with an optional override for its own styling.
- The personal DR bar can be unlocked and dragged into position.
- Stun, incapacitate, and disorient are tracked by default; root, silence, and disarm can be enabled.
- The personal DR bar can be turned off separately for arenas, battlegrounds, and the open world.

## 1.5.4 - ADR Slash Command
- Added `/adr` as a slash command alias.

## 1.5.3 - Arena DR Nameplate Fix
- Fixed DR icons not appearing on enemy nameplates during arena matches.

## 1.5.2 - Patch 12.1 Stable Release
- Promoted the WoW Patch 12.1 build from beta to a stable release.

## 1.5.1 - WoW 12.1 DR Timer Fix
- Updated DR countdowns for the 20-second Midnight Season 2 reset window.

## 1.5.0 - WoW 12.1 Support
- Updated the addon for WoW Midnight 12.1.
- Removed support for Midnight 12.0.x.
- Options window panels now use gradient shading.

## 1.4.7 - Arena Stuttering Improvements
- Reduced periodic addon work during arena matches.
- Reduced nameplate remapping during target, focus, and mouseover changes.
- Improved recovery when arena nameplate tokens change.
- Reduced preview-mode processing on visible enemy nameplates.
- Added `/arenadr perf` for a 60-second performance report.

## 1.4.6 - Arena Performance Improvements
- Reduced background processing for arena nameplate updates.
- Reduced addon work while outside arenas.
- The options window now loads when first opened.
- Fixed an error when DR immunity ended.

## 1.4.5 - BetterBlizzPlates Compatibility
- Added BetterBlizzPlates nameplate support.
- DR and trinket icons now retain their configured opacity when nameplate transparency changes.
- Horizontal Below DR trays now move beneath visible BetterBlizzPlates castbars.

## 1.4.4 - EllesmereUI Nameplates Support
- Added EllesmereUI Nameplates support.

## 1.4.3 - Shared Text Font Selection
- Added one text font selector for DR countdowns, trinket countdowns, and DR state text.
- Added Blizzard and LibSharedMedia font choices with duplicate font files removed.

## 1.4.2 - Setup Sharing
- Added setup export and import strings.
- Added a Share tab to the standalone options window.
- Added slash commands for setup export and import.

## 1.4.1 - Arena DR Icon Error Fix
- Fixed an error when arena DR icons show or hide during combat

## 1.4.0 - Configurable Timer Decimals
- Added optional decimal countdowns with an adjustable 1-20 second threshold (5 seconds by default)
- Applies to DR icons, previews, and the optional trinket icon

## 1.3.9 - Midnight 12.0.7 TOC Update
- Updated addon interface compatibility metadata to include Midnight 12.0.7.

## 1.3.8 - Reset Confirmation Prompt
- Added a confirmation prompt before resetting all settings
- Localized the reset confirmation message for supported languages

## 1.3.7 - Timer Text Visibility Option
- Added a Timers option to hide DR countdown text while keeping cooldown swipes available

## 1.3.6 - Trinket and DR Border Styles
- Added trinket border controls for style, color, and width, including Classic and None style choices
- Added a None style for DR borders

## 1.3.5 - Fixed DR Icon Size
- Added a setting to keep DR icon size fixed instead of following nameplate scaling
- Updated preview mode to show randomized DR samples on all nearby enemy nameplates

## 1.3.4 - Blizzard Arena DR Options
- Added General options for Blizzard's arena DR frames
- Added a filter to show only DR categories your character can apply

## 1.3.3 - Midnight 12.0.5 TOC Update
- Updated the TOC file to include the 12.0.5 interface versions

## 1.3.2 - Immunity Badge and Trinket Fixes
- Fixed the immunity badge icon to use the addon shield texture and render above the DR border
- Fixed Solo Shuffle trinket mirrors retaining cooldown state between rounds

## 1.3.1 - DR Tray Recovery Fixes
- Fixed DR icons getting stuck or disappearing after vanish and other temporary nameplate loss cases
- Prevented this recovery flow from affecting Blizzard's default arena DR frames

## 1.3.0 - Midnight-Safe DR Tray Mirroring
- Switch live DR nameplate rendering from reparenting Blizzard's tray to mirroring it into addon-owned frames
- Keep Blizzard's original arena DR tray in place while the addon copies textures, cooldowns, and immunity state into Midnight-safe nameplate frames
- Restyle the standalone options window to match the dark blue panel style used by the other addon configuration panels

## 1.2.5 - Enemy Trinket Cooldown Icon
- Added an optional enemy trinket cooldown icon on arena nameplates
- Added localization and a dedicated settings page for the trinket feature
- Added trinket defaults, appearance controls, positioning options, and README updates

## 1.2.4 - Friendly Nameplate Arena Mapping Filter
- Improve arena mapping by filtering friendly player nameplates

## 1.2.3 - Icon Layout and Border Options
- Added icon layout and border style options

## 1.2.2 - DR Tray Recovery Improvements
- Improve DR tray recovery after vanish, feign death, and other temporary enemy target loss cases

## 1.2.1 - Arena Mapping Recovery
- Restore arena mapping after transient target/nameplate loss

## 1.2.0 - Standalone Options Window
- Added a new standalone options window
- Added preview buttons
- Improved page layout and scrolling

## 1.1.1 - Slash Command Cleanup
- Removed the `/arenadr on` and `/arenadr off` commands to keep the command list clear. Arena DR tracking still turns on automatically when it should.
- Cleaned up the README and in-game slash handler so the documented commands match the ones players can actually use.

## 1.1.0 - Localization Support
- Add localization support with a dedicated `Locales` folder
- Add default/fallback English locale (`enUS`) and translated locale files for `deDE`, `frFR`, `esES`, `ruRU`, `ptBR`, `koKR`, `zhCN`, and `zhTW`
- Localize settings UI labels and addon chat/status messages through `ns.L`

## 1.0.9 - Settings UI Improvements
- Improve settings UI

## 1.0.8 - Icon Padding and Color Picker
- Add icon padding setting
- Reduce color picker size

## 1.0.7 - Plater and Threat Plates Adapters

- Add a dedicated Plater adapter that anchors to Plater's custom unit frame instead of the Blizzard fallback
- Add a Threat Plates adapter that resolves the active `TPFrame` anchor for healthbar and headline layouts

## 1.0.6 - Adapter File Refactor

- Refactor nameplate adapters into an `Adapters` folder
- Split Blizzard, Platynator, and ElvUI adapters into separate files

## 1.0.5 - ElvUI Nameplate Adapter

- Add ElvUI nameplate adapter support
- Anchor ElvUI integration to the ElvUI health bar instead of the full plate

## 1.0.4 - Modular Nameplate Adapter Registry

- Add a modular nameplate adapter registry for future third-party integrations
- Add first external adapter for Platynator nameplates
- Reuse adapter-based anchor resolution for live trays and preview mode

## 1.0.3 - Cooldown Preview Cleanup

- Refactor frame naming with `NextFrameName`
- Improve cooldown preview (swipe + edge options)
- Clean up DR text and border color handling
## 1.0.2 - Border Width and Icon Growth Options
- Add border width setting and enhance icon growth options in settings

## 1.0.1 - DR Text and Immunity Settings
- Add DR text overlay and immunity indicator settings to the UI
- Update timer color and position settings; enhance UI controls for DR text and immunity indicators

## 1.0.0 - Initial Arena DR Nameplate Release

- Includes arena DR nameplate anchoring, timer styling, preview mode, placement controls, DR text overlays, immunity options, and Blizzard Settings integration.
