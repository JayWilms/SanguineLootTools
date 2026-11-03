# Sanguine Loot Tools

Raid loot management addon for WoW: Forever. Current version: **0.12.0-alpha.52**, protocol **15** (private testing build). Loot, bag and state events promptly wake automatic assignment checks; readiness replies follow loot-slot order. Different boss drops prepare their recipient checks together to shorten the gap between sends; identical copies retain separate snapshots. Receipt checks tolerate cross-character item-link metadata while verifying a fresh GUID. Duplicate confirmations no longer create new broadcasts, and irrelevant background trade/expired-route errors stay out of chat. Diagnostics report pending assignment stages. Automatic assignment confirmations use bounded retries and prioritised public updates to reduce avoidable delays; native timing is pending. Timer has a scrollable item list with fixed headings. Automatic boss assignments continue past completed routes and distinguish different drops reusing a slot. Voting details are grouped above their background to prevent disappearing on reopen. Raid trade timers support Classic bag tooltips when C_TooltipInfo is unavailable. Timer stays open when Escape is pressed. Dropdown option layers stay within the native limit so the outside-click catcher cannot cover them. Master Looter and council assignment support sorted current-group dropdowns alongside manual Name-Realm entry; pick a member then click Assign or Add / remove. Uses cursor-delta dragging with stable anchors to address reported window jumps; in-game confirmation is pending. Quality-rule labels use the in-game item-quality colours. Solo raid setup persistence and transfer into leader-started sessions have regression coverage. Includes grouped window layering, opaque panels, parent-blocking dialogs, class Auto Pass in Voting, a Change winner reason counter and flush screen-edge positioning. Voting trade actions, verified holder handovers, queue protection and compact loot releases are retained. Solo and group loot tests start response rounds at 60 seconds. Everyone testing together should use alpha.52.

## Installation

Download the [alpha.52 installer](dist/SanguineLootTools-0.12.0-alpha.52-install.zip). See the [raid testing checklist](TESTING.md) for the current acceptance checks. The previous alpha.40, alpha.41, alpha.43, alpha.44, alpha.45, alpha.46, alpha.47, alpha.48, alpha.49, alpha.50 and alpha.51 installers remain in `dist`.

Copy the `SanguineLootTools` folder into your game's `Interface/AddOns` folder. Install ItemDB and its required dependencies separately. Enable the addon and **Load out of date AddOns** at character selection. Use `/slt` in game to open the launcher.

See [the addon README](SanguineLootTools/README.txt) for upgrade instructions, commands, changes and outstanding in-game checks.

## Source

The addon source and artwork were originally imported from `SanguineLootTools-0.12.0-alpha.33-install.zip`. Alpha.34 extends the test response countdown to two minutes; alpha.35 adjusts throttle backoff and recovery; alpha.36 reduces loot-release traffic and caps sustainable token refill; alpha.37 corrects fresh unbound pickup detection. The original development tests and build tools were not included in that archive and have not yet been recovered.

## Licence

Private alpha testing terms apply. See [LICENSE.txt](SanguineLootTools/LICENSE.txt).
