## Unreleased: green History exclusion

- Existing green-quality awards are removed from retained History on storage initialization.
- Award green equipment/materials by council and automatic assignment; neither should use History capacity.
- Confirm blue/epic awards remain, including when 500 records are retained.
- Active loot, delivery and archiving must continue normally for green items.

## Unreleased: History filters

- Search History by partial player name or item name (case insensitive).
- Enter a date as DD/MM/YYYY and confirm only awards from that displayed date appear.
- Focus the search box and Shift-click an item; confirm it replaces the search and matches that item across link variants.
- Toggle My Rewards to show only the current character’s awards; combine with item/date search, then click Back to All Rewards to return to all players.
- Check empty results, clearing search, window resizing, row tooltips and award audits.
- Confirm completed Disenchant/Guild Bank history remains searchable.

# Raid testing checklist

## Alpha.55: warning sound and completed utility assignments

- [ ] Enable Warning sound under Alerts. Confirm early and urgent trade
  warnings play Alarm Clock 2, matching `/run PlaySound(12867, "Master")`.
  Turning Warning sound off must silence it; no dropdown is expected.
- [ ] Complete automatic Disenchant and Guild Bank deliveries for green and
  blue items. They should leave the active Loot list and remain in Loot History.
  Completed automatic deliveries must not open Loot on discovery or be rerolled.
- [ ] Confirm pending trades, review/mismatched deliveries, Other assignments
  and ordinary council awards remain visible. Test Open Loot on discovery with
  a newly collected council item after utility assignments have completed.
- [ ] Archive completed deliveries in History and confirm their award records
  remain available. Repeat native distribution to check alpha.54 behaviour.

## Alpha.54: native distribution (protocol 16)

This change is included in the alpha.54 installer. Alpha.53 deliberately
leaves stackable greens for manual distribution; the new distributor supports
native Master Loot quantities, including merges into existing material stacks.
All participants testing this change must use the same alpha.54 protocol-16
build. Do not mix it with alpha.53 or resume an old protocol-15 test session.

- [ ] Start a normal raid session with the actual game Master Looter configured.
  Enable automatic assignment explicitly; resuming a saved session disables it.
  Set Green and Blue to Assign automatically, with the intended player and
  Guild Bank, Disenchanted or Other reason. Set the game's Master Loot threshold
  to Green as well. The addon's collection threshold alone does not change it.
- [ ] With the recipient already carrying Grime-Encrusted Salvage, open a boss
  containing several green stacks and blue items. Verify every eligible slot
  moves, the bag quantities are correct and each delivery has one history record.
- [ ] Repeat with no existing material stack, multiple units in one loot slot,
  identical drops, and a different player acting as raid leader.
- [ ] Measure time to the first physical transfer, gaps between later transfers,
  and time for shared Loot/history records separately. Background recording may
  finish later; it must not delay the next physical transfer.
- [ ] On a controlled test, disable the recipient's addon. Eligible native Master
  Loot transfers should still work. Restore it before testing shared views.
- [ ] Check that a full bag or ineligible recipient does not create a Delivered
  record, repeatedly attempt the same failed slot, or block other eligible drops.
- [ ] Close/reopen the corpse, turn automatic assignment off, and repeat with
  the final drop automatically closing the empty loot window. No duplicate or
  missing confirmed delivery should appear. Queue All must not reroll deliveries.
- [ ] Confirm Loot labels these as native Master Loot deliveries. Native source,
  slot and quantity are recorded; no bag GUID or later trade timer is invented.
  Council awards and ordinary bag-to-player trades retain their existing flow.

For failures, capture `/slt diagnostics` from the actual Master Looter and leader
before ending the session, together with the item, quantity, recipient bag space
and elapsed physical-transfer time. Native distribution counters distinguish
confirmed transfers, unconfirmed attempts and background records still pending.

### Automatic Collect for council

Included in alpha.55: completed automatic Disenchant and Guild Bank
assignments are hidden from active Loot rows and do not trigger Open Loot on
discovery. Their records remain in history and available for normal archiving.
Verify pending trades, delivery review, Other assignments and normal council
awards remain visible. Test both green materials and blue equipment; filtering
depends on completed assignment reason, not item quality.

- [ ] Set Epic to Collect for council, Automatic collection on, and the council
  collection threshold to Epic or lower. Automatic assignment can stay off.
  Open the corpse as the actual Master Looter with the game threshold set to
  Epic or lower. Eligible single-copy epics should move into the ML's bags.
- [ ] Check Loot and Timer: the actual ML is Holder, the real bag trade timer
  remains available, and there is no winner, award history or Delivered status.
  Queue the item for normal responses/voting, award it, then trade normally.
- [ ] Repeat with an unbound item and an older identical item already carried.
  Only the new copy should be discovered from the native pickup evidence.
- [ ] Test with separate raid leader and Master Looter. The ML collects the
  items; the leader's shared Loot view updates through normal bag reports.
- [ ] Turn Automatic collection off, raise its threshold, or choose Ignore.
  Each should stop council pickup for the affected quality. Assignment rules
  still use their separate Automatic assignment switch and nominated recipient.
- [ ] Verify ineligible targets, full bags, combat and unavailable bag APIs
  cannot create a false pickup/award. Known stackable council items stay on the
  corpse with a manual-distribution status, since council voting requires
  separate item copies. Stacked Assign automatically drops retain native routing.

## Historical alpha.53 behaviour

## Alpha.53 stacked materials no longer block equipment

Known stackable items or existing stacks cannot satisfy per-copy GUID receipt
proof. Before a transfer starts, the assigned recipient can report that blocker;
the leader records it and continues eligible single-copy drops. Other senders
cannot cancel the route this way, and ready/started transfers cannot be cancelled
by a late stack report. Similar materials on that corpse are left for manual
distribution with an explicit routing status and diagnostic count.

An unready/ineligible unsent item no longer blocks a different ready item.
Prepared routes for a different item moving into a vacated slot are reused so
the same copy does not gain competing receipt baselines. All 16 suites pass,
including three stacked green slots ahead of two blue drops and compacted slots.

- [ ] Reproduce three green Salvage drops with an existing stack in the recipient's
  bags and two blue drops configured for automatic assignment. Blues should
  progress without waiting for the materials to expire. Salvage stays manual.
- [ ] Repeat with one unit in the existing stack and with an empty material slot.
  Known stackable materials should still be reported as manual distribution.
- [ ] Verify each blue receives exactly one delivered record and that ordinary
  equipment copies and identical single-copy drops still use receipt proof.

## Alpha.52 first-item startup delay

Loot, bag and state changes now schedule an assignment check on the existing
0.1-second update loop. Repeated events coalesce into one pending wake; checks
run outside the event/reducer call stack and the one-second fallback remains.
Readiness replies are prepared in loot-slot order. Network refill and native
authority, combat, recipient proof and corpse-window guards remain in effect.

The actual-queue simulation with depleted burst allowance reduces first-send
time from 5.0 to 2.4 seconds; with a fresh allowance it changes from 3.0 to 0.4.
These are simulated timings, not native guarantees. All 16 suites pass, including
closing the corpse, entering combat, losing authority or disabling automation
between scheduling and execution, and sequential proof for identical copies.

- [ ] Time the first and second automatic drop on alpha.52, both after
  login and after ordinary addon traffic. Compare with the alpha.51 raid result
  of roughly 7 seconds for the first item and 3 seconds to the second.
- [ ] Verify exactly one transfer and delivery record per copy. Close/reopen
  the corpse and test a paused/changed assignment without duplicate transfers.
- [ ] For a remaining delay, capture both clients' diagnostics during the wait.

## Alpha.51 prepare distinct boss drops together

Recipient snapshots for different item IDs are prepared together before the
first send. The next distinct item need not wait for a large award broadcast
before beginning its readiness round trip. Physical sends remain sequential and
each receipt still requires one new bag GUID. Identical item IDs retain separate
snapshots to avoid attributing the same copy to two awards.

The new two-client transport suite runs the actual reducer, codec, send queues
and receiver at one message per second. The modeled gap between two distinct
drops decreases from 14 seconds (alpha.50 fixture) to 3 seconds; both clients
receive both delivered awards. Identical-copy receipt checks also pass. These
numbers are simulations, not verified native timings. All 16 suites pass.

- [ ] Time two different automatic blue drops on alpha.51, with all
  participants updated. Verify both physical receipts and delivery records.
- [ ] Repeat with two identical copies, an old identical copy already in the
  recipient's bags, and overlapping countdown/response traffic.
- [ ] Confirm no physical send occurs before the recipient's snapshot is ready
  and no copy receives two awards. Capture diagnostics during any long pause.

Diagnostics also now show automatic assignment separately from collection,
the blue rule, local addon/native Master Loot authority and corpse-window state.

## Alpha.50 receipt hyperlinks and duplicate confirmations

Corpse bag snapshots and pickup reservations now compare base item IDs, since
the boss and recipient can have different hyperlink metadata. The pre-delivery
GUID snapshot and exactly one new GUID remain required for receipt proof.
Diagnostics now count assignments waiting for readiness, start, corpse clear,
bag receipt or expiration. All 15 local suites pass, including actual hyperlink
shapes with different character-level fields and ambiguous-copy rejection.
Repeated confirmations that do not change an assignment no longer increment the
shared revision or queue another state broadcast. Diagnostics count these
duplicates so the outgoing backlog can be assessed during a reproduction.

- [ ] With alpha.50 on all participants, route two different blue drops
  to a player of a different level. Time the gap and verify the first receipt
  completes while the route is active, rather than advancing after expiration.
- [ ] Repeat with an old identical item already in the recipient's bags. The
  delivered award must reference the new copy; no duplicate pickup row should
  be created while the automatic receipt is pending.
- [ ] If delayed, capture diagnostics during the pause from the Master Looter,
  leader and recipient, including the new Automatic assignments pending line.

## Alpha.50 background chat spam

Ordinary trades no longer report active loot delivery without a pending held
award. Expired corpse requests and no-longer-relevant trade reports are rejected
quietly and counted in diagnostics; other validation errors remain visible.
Rejected automatic actions retain their retry cooldown, and unstarted routes
from an older configuration stop sending readiness/receipt requests.

- [ ] Open ordinary trades with several raid members, including after a loot
  delivery. No repeated No pending award messages should appear.
- [ ] Let an automatic route expire or change its configuration during setup.
  Delayed requests must not spam chat or award an item twice. Inspect the
  Ignored background requests counters on the leader's diagnostic report.
- [ ] Verify a pending award still reports In trade, clears after close/delivery,
  and genuine validation failures remain visible. All 15 local suites pass;
  native interaction still needs confirmation.

## Alpha.49 automatic assignment latency

Corpse handshake deltas now have live-update priority and do not resend private
ballot views. Automatic preparation/start/receipt requests use bounded retries
while waiting for shared state, rather than sending a duplicate every second.
The two-sided receipt check remains required before the next physical send.

- [ ] With alpha.49 on all participants, time the interval between two
  automatic boss awards. Confirm both deliveries and award records appear once.
- [ ] Reproduce with normal response/voting traffic. If a long pause remains,
  record Loot Configuration's routing status and diagnostics from the Master
  Looter, raid leader and recipient. No native latency target is verified yet.

## Alpha.48 multiple automatic boss assignments

Completed/failed routes no longer stop inspection of later loot slots. Route
identity also includes the item ID so a different remaining drop can reuse a
cleared slot. An unconfirmed first receipt still blocks further physical sends;
Loot Configuration displays that waiting reason. All 15 local suites pass.

- [ ] Configure two different blue boss drops for the Guild Bank recipient.
  Keep the corpse open until both arrive. Verify both receive one award and
  delivery record and the second is sent only after the first is confirmed.
- [ ] Check two identical drops with stable slots, eligibility restrictions,
  recipient bag space and an unavailable recipient. Record the routing status
  shown in Settings > Loot Configuration if the next item stays on the boss.

## Alpha.48 scrollable Timer

Timer now has a clipped, scrollable list instead of pages. Headings stay fixed;
mouse wheel, scrollbar arrows and draggable thumb use the shared scroll controls.
All 15 local suites pass; native interaction still needs confirmation.

- [ ] Track more items than fit in Timer. Scroll to the last item with the mouse
  wheel, scrollbar arrows and thumb. Verify the first/last items are reachable.
- [ ] Leave Timer scrolled while countdowns refresh. Its position should stay.
  Resize it and deliver items near the bottom; the position should clamp safely.
- [ ] Check minimum/maximum sizes, empty lists, collapse/expand, Escape and the
  close button. Column headings should stay above the list without clipping.

## Alpha.47 Voting reopen fix

Voting content now belongs to its opaque surface, keeping item details, column
headings and vote summaries above the background when the window reopens.

- [ ] Close and reopen Voting repeatedly using its close button, Escape and
  launcher. Check the item icon/name/details, leader line, all column headings,
  vote summary and footer buttons stay visible with the same session data.
- [ ] Repeat after resizing, changing the selected item, overlapping Settings,
  and collapsing/expanding Voting. Check both sidebar panes and award dialogs.

## Alpha.46 raid timers, Escape and test countdown

Classic bag-tooltip fallback for raid trade timers and Timer staying open on
Escape are included in alpha.46. All 13 local suites pass; native checks remain.

- [ ] With alpha.53 on the holder and raid clients, verify a soulbound
  raid drop with a visible trade timer shows a countdown in both Loot and Timer.
  Existing tracked copies should refresh from the holder's bag scan without
  another pickup or manual addition. Allow 20 seconds outside combat for a scan.
- [ ] Compare the countdown with the item's tooltip, then verify it decreases.
  Check a second item without a timer does not inherit the first item's reading.
- [ ] Press Escape with Timer open. It should stay open, and its close button
  should still work. Other windows should retain their usual Escape behavior.

- [ ] Restart solo and group tests, queue loot and confirm responses start at 60 seconds.

## Alpha.45 dropdown click fix

Dropdown input layers now stay below the native frame-level limit, with options
above the menu background and outside-click catcher. All 12 local suites pass;
the regression check reproduces the blocked option clicks before this fix.

- [ ] After installing alpha.45, select Master Looter
  and council members using both picker buttons and arrows. Confirm the selected
  name fills the field, then apply with Assign or Add / remove.
- [ ] Select members near the end of a full raid list using the wheel, arrows
  and scrollbar. Reopen each picker and select another member.
- [ ] Check other shared dropdowns (loot actions, recipients and assignment
  reasons), including a reason dialog above Settings. Outside clicks should
  dismiss the menu and restore ordinary window clicks.

## Alpha.44 raid member pickers

- [ ] In Settings > Council, turn off Follow in-game Master Looter to enable manual master assignment. Open Choose current group member, select a full Name-Realm, then click Assign. Selection alone must not change the assignment.
- [ ] Select a current member with the council picker, then click Add / remove. Existing council members should be marked in the picker, and selecting an existing member should allow removal with the same button.
- [ ] Test two members with the same character name on different realms, a full 40-member raid, scrolling, and both the picker button and its arrow.
- [ ] Change a typed name manually after selecting from a picker. Ordinary UI refreshes must preserve the typed name.
- [ ] Check roster joins/leaves while a picker is open. The picker should close on roster changes and show the current list when reopened.
- [ ] While solo, empty pickers should be disabled and manual Name-Realm entry should still save the next-session setup.
- [ ] Confirm live non-leaders cannot use either assignment method, council changes remain locked during active ballots, and following the in-game Master Looter disables manual master assignment.

All 12 local regression suites pass. Native layout and mouse interaction still need in-game confirmation.

Everyone testing together should use **0.12.0-alpha.53**, protocol **15**.
Local simulations passed; the following checks still need in-game confirmation.

- [ ] Exit WoW, replace the SanguineLootTools folder, restart and confirm versions with `/slt check`.
- [ ] Start a normal session after leaving test mode. Enable collection, set Green and above, choose Collect for council for greens/blues and initially turn automatic assignment off.
- [ ] Loot fresh green and blue BoE items. They should appear in Loot and Timer as Unbound — no BoP timer.
- [ ] Manually add an existing bag item with Add loot. Only one tracked copy should appear.
- [ ] Queue, respond and award that item. On the verified holder's client, the winner's Voting button should become Trade.
- [ ] Complete the trade. Check the new holder, Delivered status and removal from Timer.
- [ ] Trade an unawarded tracked item between players. Both Loot and Timer should update Holder instead of leaving Not in holder's bags.
- [ ] Trade it back. Holder should update again. Returning a previously delivered award elsewhere should flag delivery for review without changing the award winner.
- [ ] Click Queue All after delivery. The completed copy must not reopen for responses.
- [ ] Obtain another physical copy of the same item. This distinct copy should remain queueable.
- [ ] Open Change winner. Select players from the dropdown and check eligibility updates and preservation of the typed reason. Review change must identify the intended recipient.
- [ ] Repeatedly change and restore Settings actions, recipients and thresholds. Save/reopen Disenchanted, Guild Bank and Other reasons. Recipient and Edit reason are enabled only for Assign automatically.
- [ ] Enable automatic assignment with a recipient and reason. Test an eligible corpse drop under Master Loot; verify actual receipt, award and delivery. Guild Bank means a nominated player, not direct guild bank deposit.
- [ ] Queue All with several players responding/voting together. Check prompt delivery and synchronization.

For failures, record steps, expected/actual behavior, screenshots and `/slt diagnostics` from the raid leader and affected holder.

## Class restrictions, text counters and window layout

- [ ] Queue a class-restricted item with both usable and restricted classes present. Restricted players should show Auto Pass in Voting immediately, without being counted as waiting or timed out.
- [ ] Confirm restricted players cannot receive votes or be awarded the item, and eligible players still respond normally.
- [ ] Unknown/unavailable class data must not trigger a pass. Once a restriction is confirmed, the leader should synchronize Auto Pass to council members.
- [ ] An explicit player-selected Pass should still read Pass; existing explicit responses must be preserved.
- [ ] Type and clear a Change winner reason. The counter should update from 0/160, and still match after choosing a different replacement.
- [ ] Move Timer, Loot, Responses and Settings flush to each screen edge. Releasing the mouse should not push them inward.
- [ ] Overlap Settings, Responses and Timer in different orders. Only the foreground window's controls should be visible or clickable in the overlapping area.
- [ ] Click an exposed part of a background window. Its complete contents should come to the front together. Timer should remain open independently.
- [ ] Open Change winner, an assignment reason or another small dialog. Its parent should be dimmed and blocked until close/cancel.
- [ ] Open a nested confirmation and then cancel it. The preceding dialog should remain above its parent; closing both should restore parent clicks.
- [ ] Check dropdowns above dialogs, long recipient lists, resize grips and collapse/expand while windows overlap.

## Run local checks

Requires Python and the Lua runtime package:

```sh
python -m pip install -r qa/requirements.txt
python qa/run_checks.py
```

The fixtures in `qa/fixtures` preserve earlier source for regression comparisons. Generated reports go into the ignored `work` directory. The original development tests from before the alpha.33 installer import remain unrecovered; these are the checks added during alpha.34–alpha.40 work.

## Package the current source

```sh
python tools/build_install.py
```

This writes and verifies the current installer in `outputs`. It does not publish or upload anything. Build only when explicitly requested.

## Alpha.44 window dragging acceptance (native test pending)

- [ ] Each of the three affected users repeats the original failure with build 42.
- [ ] Record affected window, resolution, window mode, UI scale, and other UI addons.
- [ ] Move Launcher, Settings, Responses, Voting, Loot, Timer and History slowly and quickly in every direction. The pointer should keep the same grab offset.
- [ ] Release over another window, over the game world, and at each screen edge/corner. No jump on release; repeat at least twenty times.
- [ ] Repeat at the user's usual UI scale and a different scale, with windows overlapping and while responses/votes refresh.
- [ ] Collapse/expand and lock/unlock windows, then repeat. Close a window during a drag and reopen it; it must not follow the cursor afterward.
- [ ] Change UI scale or resolution during a drag. The drag should stop safely. Start a fresh drag afterward.
- [ ] Reload the UI and confirm each window stays at its released position.
- [ ] Confirm resize grips, focus/layering and dialogs still work. Test movable dialogs as well as main windows.

Pass criteria: no jumps during dragging or on release, no off-screen windows, and saved positions survive reload. If a jump remains, capture a short video and diagnostics; do not mark the issue resolved from simulated tests alone.

## Quality colours and solo preparation

- [ ] In Loot Configuration, confirm Poor is grey, Common white, Uncommon green, Rare blue, Epic purple, and Legendary orange. Assignment-reason headings retain the matching colour.
- [ ] Outside test mode, while solo, set the response timer and choices, council, voting rules, loot thresholds/assignment rules, and alerts. Save a raid profile.
- [ ] Reload the UI and verify all prepared values and the profile remain available.
- [ ] Join a raid as leader. Verify no session starts merely from joining. Start a session and check the prepared values.
- [ ] Confirm absent council members are skipped and missing assignment recipients pause automation. Live non-leaders must not be able to change shared raid settings.
