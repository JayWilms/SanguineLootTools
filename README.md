# Sanguine Loot Tools

Raid loot management addon for WoW: Forever. Current version: **0.12.0-alpha.55**, protocol **16** (private testing build). Native Master Loot moves eligible automatic assignments without waiting for recipient messages; stacked green materials retain quantities and can merge into existing stacks. Collect for council automatically sends eligible single-copy loot to the actual Master Looter, unawarded, while preserving real bag tracking and trade timers for normal responses and voting. Council stacks remain manual. History recording synchronises in the background and distinguishes native evidence from bag GUID verification. Completed automatic Disenchant and Guild Bank assignments are hidden from active Loot while their history remains available. Early and urgent trade warnings use Alarm Clock 2 (12867), with the existing On/Off switch and no dropdown. All 17 local suites pass; a tester reported instant native distribution on alpha.54, with further raid checks continuing. Test response rounds remain 60 seconds.

## Installation

Download the [alpha.55 installer](dist/SanguineLootTools-0.12.0-alpha.55-install.zip). **Update all testers together and start a new normal session:** protocol 16 is incompatible with alpha.53. Enable Automatic collection for council pickup; enable Automatic assignment separately for final assignment rules. Both require the appropriate game Master Loot threshold. See the [raid testing checklist](TESTING.md). Previous installers remain in `dist`.

Copy the `SanguineLootTools` folder into your game's `Interface/AddOns` folder. Install ItemDB and its required dependencies separately. Enable the addon and **Load out of date AddOns** at character selection. Use `/slt` in game to open the launcher.

See [the addon README](SanguineLootTools/README.txt) for upgrade instructions, commands, changes and outstanding in-game checks.

## Source

The addon source and artwork were originally imported from `SanguineLootTools-0.12.0-alpha.33-install.zip`. Alpha.34 extends the test response countdown to two minutes; alpha.35 adjusts throttle backoff and recovery; alpha.36 reduces loot-release traffic and caps sustainable token refill; alpha.37 corrects fresh unbound pickup detection. The original development tests and build tools were not included in that archive and have not yet been recovered.

## Licence

Private alpha testing terms apply. See [LICENSE.txt](SanguineLootTools/LICENSE.txt).
