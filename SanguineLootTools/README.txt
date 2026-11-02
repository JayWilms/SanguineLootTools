Sanguine Loot Tools 0.12.0-alpha.40 - private testing build

INSTALL
Exit WoW completely. Back up WTF before upgrading.
Remove the OLD Interface/AddOns/SanguineLootCouncil addon folder. Extract the
included SanguineLootTools folder into Interface/AddOns. Do not load both copies.
The final TOC path is Interface/AddOns/SanguineLootTools/SanguineLootTools.toc.
ItemDB and its publisher-required dependencies remain separate required installs.
Everyone testing together should use alpha.40, protocol 15. Commands use /slt.

NEW SINCE ALPHA.39
- Voting's winner button becomes Trade for a verified item held by the local
  player, and Delivered when delivery is confirmed. Existing trade checks apply.
- Change winner now uses a recipient dropdown instead of Previous/Next, with
  eligibility details below it. Typed reasons survive recipient changes.
- Holder handovers require the same GUID to be absent from the old holder and
  present in the recipient's bags. Reports can arrive in either order.
- Handovers keep physical holder and award winner separate. Delivery to the
  winner is verified; a delivered item returned elsewhere needs review.
- Queue/Queue All reject previously recorded, awarded, delivered and retired
  copies, including stale associations and duplicate tracking rows. Distinct
  physical copies of an identical item remain queueable.
- Awarded items leave the response list. Closed, unawarded rounds remain for
  review. This prevents old awards appearing alongside fresh response rounds.
- Diagnostics include confirmed/pending holder handovers.
- Local checks cover trade actions, dropdowns, handovers, queue protection,
  pickups, network replication and Lua 5.1 syntax. Native raid testing required.
- Protocol 15 and two-minute test response rounds retained. Update all testers.

NEW SINCE ALPHA.38
- Replaced the shared dropdown's nested scrolling frames with direct clickable
  option rows. Menu, rows, scrollbar and outside-dismiss area use explicit
  input layers, so the dismiss area stays beneath the option buttons.
- Menus can be reopened and changed repeatedly. Long lists show eight options
  at a time with wheel, arrows and slider; switching menus resets scroll state.
- Covers collection thresholds, actions, recipients, reasons, voting options
  and profile menus. Recipient and Edit reason controls remain available only
  for Assign automatically; the action menu itself stays editable for leaders.
- Diagnostics now report menu opens and option clicks without selected values.
- Simulated checks cover repeated action/threshold changes, saved reasons,
  42-choice recipient lists, scrolling, boolean choices and direct input layers.
  Native game mouse behavior still requires tester confirmation.
- Protocol 15, pickup detection, compact releases and two-minute tests retained.

NEW SINCE ALPHA.37
- The assignment-reason dropdown is an independent overlay, so collapsing the
  main Settings window cannot hide it behind a separate reason dialog.
- The reason choices display Disenchanted, Guild Bank and Other. Existing
  saved Disenchant values are retained and display as Disenchanted.
- Dropdown actions use the owning control's visibility and enabled state;
  closing the dialog removes the menu and its click-dismiss overlay.
- Simulated UI checks cover the collapse failure, all three choices, saving,
  reopening, recipient/note preservation and dismissal. Verify in-game.
- Protocol 15, pickup detection, compact releases and two-minute tests retained.

NEW SINCE ALPHA.36
- Fresh unbound pickups are matched by item ID and physical bag copy, rather
  than requiring identical chat and bag hyperlinks. Handles self loot and
  pushed-item messages, with a 30-second observation window.
- The normal session snapshots existing bag copies so a fresh pickup cannot
  automatically pull an older identical item into tracking. Quantity evidence
  limits new copies; bag-before-chat and chat-before-bag ordering are supported.
- Existing unbound items are not retrospectively collected. Use Add loot for
  the helmet already in your bags; test automatic collection on a fresh drop.
- Diagnostics now include real/test session mode, collection settings, pickup
  message count and bag scan status. Verify pickup behavior in-game.
- Unbound items show "Unbound — no BoP timer" instead of a countdown.
- Protocol 15, compact releases and two-minute test rounds retained.

NEW SINCE ALPHA.35
- Queue All reuses the tracked loot links/GUIDs already held by recipients,
  and sends shared response-round settings once instead of once per item.
- Public loot-release updates take priority over background council packets,
  preserving their required baseline/revision order.
- Sustainable send allowance now refills at one fragment per second with a
  bounded burst. Repeated failures back off below that rate instead of
  repeatedly probing toward ten per second.
- Diagnostics include the most recent loot release size and fragment count.
- Release/codec/recipient tests cover 2, 5 and 40 members, queued response
  coalescing and a slowly refilling shared server allowance. In the five-member
  fixture, the release update shrank from 16 fragments to 5.
- Actual in-game latency still requires testing. Exhausted server allowance or
  a baseline still in transit can delay delivery. Timers still start on queue;
  the test default remains 120 seconds.
- Protocol 15 is required for compact releases: update every tester together.

OPTIONAL ONE-TIME SETTINGS/HISTORY TRANSFER
With WoW CLOSED, copy WTF/Account/<account>/SavedVariables/SanguineLootCouncil.lua
to SanguineLootTools.lua in the SAME SavedVariables directory before launching.
Keep the file contents unchanged. Keep a backup; do not overwrite newer data.
Without this transfer the renamed addon starts with fresh settings/history.

NEW SINCE ALPHA.34
- A temporary network throttle now halves the send rate instead of immediately
  dropping it to one fragment per second. Continued throttling slows it further.
- Successful sends gradually restore the rate. Consecutive rejections extend
  the retry cooldown; temporary throttles never discard the current fragment.
- Diagnostics now include the last throttle result and how long ago it occurred.
- Simulated 19-fragment transfer with one throttle: alpha.34 19 seconds;
  alpha.35 4.1 seconds. These are simulated results, not an in-game guarantee.
- Two-minute test response rounds retained. Response timers still start when
  the leader queues loot; slow delivery still consumes response time.

NEW IN ALPHA.34
- Solo and group /slt test response rounds now start at 120 seconds (two minutes)
  to allow more time while investigating throttling. Refreshing test mode keeps
  this two-minute default. This change does not fix the underlying throttling.
- Normal raid response settings and real item trade timers are unchanged.

NEW IN ALPHA.33
- Configure private saved raid setup before a session, including while solo.
- Existing Settings tabs cover responses/timer, council, Master Looter preference,
  voting rules, collection/recipients/reasons and alerts. Profiles is Raid Profiles.
- Save/apply Raid Profiles before starting. Session shows a compact setup summary.
- Start uses the Raid Leader's defaults. Absent council members are skipped,
  an absent manual Master Looter falls back, and absent named automatic-loot
  recipients pause automation for review without erasing saved preferences.
- Automatic recipient Name-Realm entry supports planning before players join.
- Active nonleaders cannot change shared settings; current item rules stay frozen.
- All alpha.32 popup, chevron, Voting advancement and title spacing work is retained.
- Protocol 14 retained. Everyone testing should install alpha.33.
Testing notes are supplied in chat; no separate checklist is included.

CARRIED OVER
Fixed sizes for other windows, title-bar lock/collapse controls, retained Response items after
expiry, modern Shift-click insertion, Voting loot navigation, SLT logo, clean
scrollbars, rounded Settings toggles, section dividers, immediate
response ticks, Loot-first manual additions and SoD-only 20-item tests.
/slt test opens Loot for the Master Looter; queue items to start 120-second rounds.
Real bag/trade/history actions remain disabled in test mode. Soft Reserve is planned.
Add loot requires a physical single item in carried bags; Shift-click selects its exact copy.
Bag-added items use normal trading after award; stack splitting and trade eligibility apply.
Existing old manual placeholders still require delivery confirmation through Manage.

NATIVE ACCEPTANCE
Loot Configuration appearance, native corpse eligibility/verification, Shift-click,
physical bag-copy trading, multiplayer timing, saved-data transfer
and full-exit persistence still need in-game testing. Full-exit persistence is not
claimed fixed by this release.

COMMANDS
/slt; /slt settings; /slt responses; /slt loot; /slt timer; /slt history
/slt check; /slt sync; /slt test; /slt leave-test; /slt resume; /slt help
/slt diagnostics; /slt diagnostics start; /slt diagnostics stop
See LICENSE.txt for private testing terms.
