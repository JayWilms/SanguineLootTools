# Alpha.41 raid testing checklist

Everyone testing together should use **0.12.0-alpha.41**, protocol **15**.
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
