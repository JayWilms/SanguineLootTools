# Alpha.47 raid testing checklist

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

- [ ] With alpha.47 on the holder and raid clients, verify a soulbound
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

Everyone testing together should use **0.12.0-alpha.47**, protocol **15**.
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
