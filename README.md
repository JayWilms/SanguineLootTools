# Sanguine Loot Tools

Raid loot management addon for WoW: Forever. Current version: **0.12.0-alpha.44**, protocol **15** (private testing build). Master Looter and council assignment support sorted current-group dropdowns alongside manual Name-Realm entry; pick a member then click Assign or Add / remove. Uses cursor-delta dragging with stable anchors to address reported window jumps; in-game confirmation is pending. Quality-rule labels use the in-game item-quality colours. Solo raid setup persistence and transfer into leader-started sessions have regression coverage. Includes grouped window layering, opaque panels, parent-blocking dialogs, class Auto Pass in Voting, a Change winner reason counter and flush screen-edge positioning. Voting trade actions, verified holder handovers, queue protection and compact loot releases are retained. Solo and group loot tests start response rounds at 120 seconds. Everyone testing together should use alpha.44.

## Installation

Download the [alpha.44 installer](dist/SanguineLootTools-0.12.0-alpha.44-install.zip). See the [raid testing checklist](TESTING.md) for the current acceptance checks. The previous alpha.40, alpha.41 and alpha.43 installers remain in `dist`.

Copy the `SanguineLootTools` folder into your game's `Interface/AddOns` folder. Install ItemDB and its required dependencies separately. Enable the addon and **Load out of date AddOns** at character selection. Use `/slt` in game to open the launcher.

See [the addon README](SanguineLootTools/README.txt) for upgrade instructions, commands, changes and outstanding in-game checks.

## Source

The addon source and artwork were originally imported from `SanguineLootTools-0.12.0-alpha.33-install.zip`. Alpha.34 extends the test response countdown to two minutes; alpha.35 adjusts throttle backoff and recovery; alpha.36 reduces loot-release traffic and caps sustainable token refill; alpha.37 corrects fresh unbound pickup detection. The original development tests and build tools were not included in that archive and have not yet been recovered.

## Licence

Private alpha testing terms apply. See [LICENSE.txt](SanguineLootTools/LICENSE.txt).
