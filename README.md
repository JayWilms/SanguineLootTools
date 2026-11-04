# Sanguine Loot Tools

Raid loot management addon for WoW: Forever. Current version: **0.12.0-alpha.60**, protocol **17** (private testing build). Native Master Loot moves eligible automatic assignments without waiting for recipient messages; stacked green materials retain quantities and can merge into existing stacks. Collect for council automatically sends eligible single-copy loot to the actual Master Looter, unawarded, while preserving real bag tracking and trade timers for normal responses and voting. Council stacks remain manual. History recording synchronises in the background and distinguishes native evidence from bag GUID verification. Completed automatic Disenchant and Guild Bank assignments are hidden from active Loot while their history remains available. Early and urgent trade warnings use Alarm Clock 2 (12867), with the existing On/Off switch and no dropdown. All 21 local suites pass; a tester reported instant native distribution on alpha.54, with further raid checks continuing. Test response rounds remain 60 seconds.

## Installation

Download the [alpha.60 installer](dist/SanguineLootTools-0.12.0-alpha.60-install.zip). **Update all testers together and start a new normal session:** protocol 17 is incompatible with alpha.58 and older sessions. Saved raid setups/profiles are retained; review the Quality Rules before enabling automation. Enable Automatic Collection for council pickup; enable Automatic Awards separately for direct awards. The Quality Rules now control each item quality directly; the separate addon threshold is removed. Both automation paths still require the appropriate game Master Loot threshold. See the [raid testing checklist](TESTING.md). Previous installers remain in `dist`.

Copy the `SanguineLootTools` folder into your game's `Interface/AddOns` folder. Install ItemDB and its required dependencies separately. Enable the addon and **Load out of date AddOns** at character selection. Use `/slt` in game to open the launcher.

See [the addon README](SanguineLootTools/README.txt) for upgrade instructions, commands, changes and outstanding in-game checks.

## Alpha.60: Quiet loot transfers and cleaner Settings

Routine loot transfers no longer show a loading popup, fragment counters or response loading text. History Sync keeps progress and completion visible. History removes All Players and adds a Select All Shown / Deselect All toggle. A personal Display tab provides window locking, all-window or single-window reset, and Loot Window Auto-Open. Response Timing moves into Responses alongside response choices and personal colours. Settings reclaims header/footer space and shows permission or lock guidance only where needed. All 21 local suites pass; native layout and raid testing remain pending. Protocol 17 is retained.

## Alpha.59: Quality Rules, History and Master Looter controls

Master Looter selection is one typed/roster field. History has compact audits, full inline search guidance, Sync History at the bottom right and crimson selection-based deletion with confirmation. Local deletion can be reversed by an active session or another member's sync copy. Loot Configuration follows per-quality rules directly, without a separate minimum threshold. Automatic Collection and Automatic Awards are adjacent and clearly describe council collection versus direct awards. Actual routing notices remain visible while repeated status text is hidden. All twenty local suites pass; native layout/raid checks remain pending. Protocol 17 requires everyone to update and start a new session.

## Alpha.58: Council and Settings updates

Council membership now uses a raid-member dropdown and Remove button for each member, with Add Council Member underneath. Changes save immediately, replacing a member in one validated action. Duplicate selections are rejected and saved absent members remain removable. Existing leader permissions and voting locks remain. Gold Settings headings capitalize each word, while repeated tab titles and introductions are removed to give controls and the Responses preview more room. All nineteen local suites pass; native layout checks remain pending.

## Alpha.57: History updates

The History window's **Sync History** button merges retained awards across the current raid or party. Regroup after split raids, or invite an absent member back, then have the leader, master looter or configured council member start the sync. Everyone participating needs alpha.56 or newer; alpha.55 does not contain this feature. Progress and unavailable peers are reported. Guild Bank records, corrections and delivery audits are included; green items remain excluded and the newest 500 records are retained. This does not change the active loot session. The search box now shows "Search name, date or item…" inside the empty field. Date format and Shift-click guidance appear in its hover tooltip. History also adds name/date/item search, Shift-clicked item links, My Rewards and a separate Guild Bank view. Green awards no longer use the 500 retained slots; existing known green entries are removed on load. All nineteen local suites pass; native Forever communication and layout checks remain pending.

## Source

The addon source and artwork were originally imported from `SanguineLootTools-0.12.0-alpha.33-install.zip`. Alpha.34 extends the test response countdown to two minutes; alpha.35 adjusts throttle backoff and recovery; alpha.36 reduces loot-release traffic and caps sustainable token refill; alpha.37 corrects fresh unbound pickup detection. The original development tests and build tools were not included in that archive and have not yet been recovered.

## Licence

Private alpha testing terms apply. See [LICENSE.txt](SanguineLootTools/LICENSE.txt).
