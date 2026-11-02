# Sanguine Loot Tools

Raid loot management addon for WoW: Forever. Current version: **0.12.0-alpha.40**, protocol **15** (private testing build). Includes Voting trade actions, a Change winner dropdown, verified holder handovers and protection against queuing completed copies again. Shared Settings dropdowns, fresh pickup detection, compact loot releases and conservative network pacing are retained. Solo and group loot tests start response rounds at 120 seconds. Everyone testing together should use alpha.40.

## Installation

Download the [alpha.40 installer](dist/SanguineLootTools-0.12.0-alpha.40-install.zip). See the [raid testing checklist](TESTING.md) for the current acceptance checks.

Copy the `SanguineLootTools` folder into your game's `Interface/AddOns` folder. Install ItemDB and its required dependencies separately. Enable the addon and **Load out of date AddOns** at character selection. Use `/slt` in game to open the launcher.

See [the addon README](SanguineLootTools/README.txt) for upgrade instructions, commands, changes and outstanding in-game checks.

## Source

The addon source and artwork were originally imported from `SanguineLootTools-0.12.0-alpha.33-install.zip`. Alpha.34 extends the test response countdown to two minutes; alpha.35 adjusts throttle backoff and recovery; alpha.36 reduces loot-release traffic and caps sustainable token refill; alpha.37 corrects fresh unbound pickup detection. The original development tests and build tools were not included in that archive and have not yet been recovered.

## Licence

Private alpha testing terms apply. See [LICENSE.txt](SanguineLootTools/LICENSE.txt).
