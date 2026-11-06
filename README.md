# Sanguine Loot Tools

Raid loot management addon for WoW: Forever. Current version: **0.12.0-alpha.68**, protocol **18** (private testing build). Native Master Loot moves eligible automatic assignments without waiting for recipient messages; stacked green materials retain quantities and can merge into existing stacks. Collect for council automatically sends eligible single-copy loot to the actual Master Looter, unawarded, while preserving real bag tracking and trade timers for normal responses and voting. Council stacks remain manual. History recording synchronises in the background and distinguishes native evidence from bag GUID verification. Completed automatic Disenchant and Guild Bank assignments are hidden from active Loot while their history remains available. Early and urgent trade warnings use Alarm Clock 2 (12867), with the existing On/Off switch and no dropdown. A tester reported instant native distribution on alpha.54, with further raid checks continuing. Test response rounds remain 60 seconds.

## Installation

Download the [alpha.68 installer](dist/SanguineLootTools-0.12.0-alpha.68-install.zip). **Update all testers together and start a new normal session:** protocol 18 requires alpha.68 on every client. Saved raid setups/profiles are retained; review the Quality Rules before enabling automation. Enable Automatic Collection for council pickup; enable Automatic Awards separately for direct awards. The Quality Rules now control each item quality directly; the separate addon threshold is removed. Both automation paths still require the appropriate game Master Loot threshold. See the [raid testing checklist](TESTING.md). Previous installers remain in `dist`.

Copy the `SanguineLootTools` folder into your game's `Interface/AddOns` folder. No separate addon dependencies are required. Enable the addon and **Load out of date AddOns** at character selection. Use `/slt` in game to open the launcher.

See [the addon README](SanguineLootTools/README.txt) for upgrade instructions, commands, changes and outstanding in-game checks.

## Alpha.68: Loot session recovery

Sanguine can recover a confirmed session after a leader reload or a change in raid leadership. One designated Master Looter or council member receives the private ballot backup. If no complete copy matches the newest known session revision, recovery pauses for review. After recovery, automatic collection and awards stay off until the leader checks deliveries and re-enables them.

## Alpha.67: Optional Transmog response

The raid leader can enable Transmog under Settings → Responses → Raid Response Choices → Add Transmog. The response checks the player's own appearance collection, including appearances learned from another item. A collected or unlearnable look disables Transmog only. If collection data is unavailable, the response remains available and is marked Unverified.

## Alpha.66: Master Looter handoff and item previews

The active Master Looter is automatically on the council. The raid leader can use one picker in Settings → Council. Sanguine follows WoW's confirmed Master Looter and uses the saved assignee or raid leader when the game is using another loot method. Handoffs keep the active round and tracked item holders. In Responses, Ctrl-click an item name or icon to preview it in WoW's dressing room, or Shift-click to link it in chat.

## Alpha.65: Award confirmation, voting ticks and test loot

Voting clears the confirmation shade before an award advances. The item list shows a yellow tick for your recorded vote and a green tick for an award. Four test items that stayed on “Retrieving item information” were replaced with Walking Stick, Ring of Iron Will, Large Axe and Heavy Mithril Pants.

## Alpha.64: Tracked item preloading, vote advance and full names

The 27-item test pool includes all three relic types and one recipe each for Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking and Tailoring. The live recipe filter still supports Cooking, First Aid and Fishing. Tracked loot starts loading item data on arrival, and confirmed votes advance to the next item with a vote available. Forever roster identities use both character names throughout the addon.

## Alpha.62: Forever test loot and recipe visibility

Solo and group /slt test now start with 23 Forever items, including four profession recipes. Responses shows a recipe when your character knows its profession at any skill level. Recipes with unresolved profession data stay visible, and Loot and Council still list every recipe.

## Alpha.61: Native item data

SLT now gets item details from the game and uses class restrictions plus Forever proficiency rules for auto-pass. Unresolved data leaves responses available. Item details load locally, with no extra item data sent over addon comms. Use alpha.61 on every test client. Protocol 17 is retained. See the live Forever checklist in TESTING.md.

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
