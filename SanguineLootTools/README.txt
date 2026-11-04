Sanguine Loot Tools 0.12.0-alpha.58 - private testing build

INSTALL
Exit WoW completely. Back up WTF before upgrading.
Remove the OLD Interface/AddOns/SanguineLootCouncil addon folder. Extract the
included SanguineLootTools folder into Interface/AddOns. Do not load both copies.
The final TOC path is Interface/AddOns/SanguineLootTools/SanguineLootTools.toc.
ItemDB and its publisher-required dependencies remain separate required installs.
Everyone testing together should use alpha.58, protocol 16. Commands use /slt.
Start a new normal raid session; do not resume an old protocol-15 session.

NEW SINCE ALPHA.57
- Council membership uses one raid-member dropdown per member, with Remove
  on the right and Add Council Member underneath. Changes save immediately.
- Replacing a member is atomic; duplicate selections are rejected. Saved
  absent members remain visible and removable. Leader and voting locks remain.
- Gold Settings headings capitalize the start of every word, including
  Saved Raid Profiles, Profile Name, Council Membership and Voting Rules.
- Repeated tab titles and introductions are removed. Content starts higher,
  giving controls and the docked Responses preview more room.
- All nineteen local suites pass, including council row regressions.
  Native layout checks remain pending. Protocol 16 retained.

NEW SINCE ALPHA.56
- History shows muted "Search name, date or item..." text inside the empty
  search box, replacing the long label above it. Typing hides the hint;
  clearing the field restores it.
- Hover over the box for DD/MM/YYYY date guidance and Shift-click item linking.
- Includes all alpha.56 History filters, Guild Bank separation, green-item
  exclusion and group History sync. Protocol 16 retained.
- All nineteen local suites pass; native layout and sync checks remain pending.

NEW SINCE ALPHA.55
- History search supports player names, dates (DD/MM/YYYY), item names and
  Shift-clicked item links. Search sits at the top left of History.
- My Rewards automatically filters to the logged-in character (name and realm).
  Click Back to All Rewards to return to the main list.
- Guild Bank opens a separate view of awards marked Guild Bank, with the same
  return button. These records are hidden from the main/personal reward lists
  and candidate reward counts. Search works in both views.
- Green-quality awards no longer consume the 500 retained History slots.
  Existing known green records are removed on load; green loot distribution
  and active trade tracking remain available.
- Sync History merges retained awards across compatible online members of
  the current raid or party. Regroup after split raids, or invite an absent
  member back, then have the leader, master looter or council start the sync.
  No active loot session is required. Everyone participating needs alpha.56.
- Syncing/progress/completion states appear in History, with a completion
  message in chat. Missing or interrupted peers are reported. Sync preserves
  newer correction/delivery revisions, complete audits and distinct item copies.
- The merged history keeps the latest 500 records, including Guild Bank items.
  Sync cannot recover records no longer retained by any participating member.
- All nineteen local test suites pass, including a 20-member split-raid and
  absence simulation. Native Forever sync and layout checks remain pending.
  Protocol 16 retained; alpha.55 cannot participate in the new History sync.

NEW SINCE ALPHA.54
- Early and urgent trade warnings use Alarm Clock 2 (sound 12867), replacing
  Raid Warning. The existing sound On/Off switch remains; no dropdown added.
- Completed automatic Disenchant and Guild Bank assignments leave the active
  Loot list and do not trigger Open Loot on discovery. History and archive
  records remain intact. Pending trades, delivery review, Other assignments
  and ordinary council awards remain visible.
- Native distribution and council collection from alpha.54 are retained.
  A live tester reported instant distribution; remaining raid checks continue.
- All seventeen local test suites pass. Protocol 16 retained.

NEW SINCE ALPHA.53
- Eligible automatic assignments use local native Master Loot confirmation.
  The next item does not wait for recipient addon messages or history sync.
- Green materials can merge into existing stacks. Native records retain
  quantities and distribution evidence without inventing physical bag GUIDs.
- Collect for council moves eligible single-copy loot into the actual Master
  Looter's bags, unawarded. Enable Automatic collection and satisfy both the
  council collection and game Master Loot thresholds. Queue for normal voting.
  Real bag GUIDs and trade timers remain tracked. Council stacks remain manual.
- Final Assign automatically rules still require Automatic assignment enabled,
  a nominated recipient and a reason. Resuming a session disables that switch.
- Pending result recording is retried in the background. Duplicate results
  cannot recreate an award; failed or unconfirmed gives are not marked delivered.
- All seventeen local suites pass. Native client timing still needs raid testing.

NEW SINCE ALPHA.52
- Existing stacks and known stackable materials are reported as requiring
  manual distribution. They no longer block eligible single-copy drops.
- Only the assigned recipient can report a pre-transfer stack blocker;
  a ready/started transfer cannot be cancelled by that report.
- Reuse prepared routes for different items when corpse slots compact,
  preserving a single receipt baseline per item.
- All sixteen local suites pass, including three green material slots ahead
  of two blues. Native interaction still needs confirmation. Protocol 15.

NEW SINCE ALPHA.51
- Loot, bag and state changes coalesce into assignment checks on the existing
  0.1-second loop, outside event/reducer calls. One-second fallback retained.
- Recipient readiness replies follow loot-slot order. Native authority, combat,
  corpse-open and new-copy receipt checks and network pacing remain enforced.
- All sixteen local suites pass. Simulation first-send time with a depleted
  burst allowance improves from 5.0 to 2.4 seconds; native timing is pending.

NEW SINCE ALPHA.50
- Prepare recipient snapshots for distinct boss drops together. Physical sends
  remain sequential, with fresh-GUID receipt proof for each copy.
- Identical item IDs retain separate baselines to prevent ambiguous receipts.
- Diagnostics distinguish automatic collection/assignment, the blue rule,
  addon/native Master Loot authority and whether the corpse window is open.
- All sixteen local suites pass. The two-client transport simulation reduces
  the gap between two distinct items from 14 seconds to 3 seconds at one message
  per second. Native raid timing remains unverified. Protocol 15 retained.

NEW SINCE ALPHA.49
- Receipt snapshots/reservations match item IDs across character-specific link
  metadata. Exactly one new bag GUID remains required to verify receipt.
- Duplicate automatic confirmations do not advance revisions or rebroadcast
  unchanged state. Diagnostics show pending stages and duplicate counts.
- Ordinary trades without pending awards no longer report loot activity.
  Expired background requests are counted quietly; validation errors remain.
- All fifteen local suites pass. Raid latency still needs native confirmation.

NEW SINCE ALPHA.48
- Automatic assignment handshakes use live-update priority without resending
  unrelated private ballot views. Repeated requests have bounded retries.
- Recipient bag confirmation remains required before the next item is sent.
- All fifteen local suites pass. Improvement to the reported 45-second delay
  still needs native raid confirmation. Protocol 15 retained.

NEW SINCE ALPHA.47
- Timer uses one clipped list with a mouse wheel, scrollbar arrows and draggable
  thumb. Headings stay fixed; countdown refreshes preserve scroll position.
- Automatic boss assignments skip terminal routes and distinguish different
  drops reusing a loot slot. Receipt confirmation still gates the next send.
- Loot Configuration shows when recipient bag confirmation is pending.
- All fifteen local suites pass. Native raid and scroll checks remain pending.

NEW SINCE ALPHA.46
- Voting details, headings, images and controls belong to the voting surface
  so its opaque background cannot cover them after reopening or focus changes.
- Repeated reopen, focus and collapse/expand cycles have regression coverage.
- All thirteen local suites pass. Native display checks remain pending.

NEW SINCE ALPHA.45
- Raid trade timers fall back to the exact bag item tooltip on Classic clients
  without C_TooltipInfo. Existing tracked copies refresh on a holder bag scan.
- Escape leaves Timer open; the close button still works.
- Solo and group test response rounds now start at 60 seconds. Normal raid
  response settings are unchanged. Restart the test to use the new default.
- All thirteen local suites pass; native confirmation is pending. Protocol 15.

NEW SINCE ALPHA.44
- Corrected shared dropdown layers so the outside-click catcher sits below
  the menu and its clickable options within the native frame-level limit.
- Regression checks now enforce the limit and option input ordering for both
  raid member pickers and other shared dropdowns. All twelve suites pass.
- Native mouse interaction still needs in-game confirmation.

NEW SINCE ALPHA.43
- Settings > Council has current-group dropdowns for Master Looter and council.
  Select a full Name-Realm, then click Assign or Add / remove to apply it.
- Current council members are marked; full raids can be scrolled. Manual name
  entry remains available while solo for preparing the next session.
- Roster changes dismiss stale pickers. Existing leader permissions, ballot
  locks and Follow in-game Master Looter restrictions still apply.
- Twelve local suites passed. Native layout and mouse checks remain pending.
- Protocol 15 and the previous dragging/quality-colour changes are retained.

NEW SINCE ALPHA.41
- Dragging follows mouse travel in UIParent coordinates without native anchor
  switching. The same anchor is retained while dragging and saved on release.
- Interrupted drags finish on hide, lock, layout reset or display/scale changes.
- Quality-rule labels use the matching in-game quality colours.
- Solo setup edits, profiles, reload persistence and leader-started session
  transfer have regression coverage; the existing setup behavior is retained.
- Eleven local suites passed. The reported jumps still need confirmation by the
  affected users in WoW: Forever; this is a candidate fix. Protocol 15 retained.

NEW SINCE ALPHA.40
- Opaque panels and separate drawing-level bands keep each window's content
  together. Opening/clicking a window raises the entire group of controls.
- Small dialogs are above their parent and block its mouse input until closed.
  Nested confirmations retain the correct order; dropdowns stay above dialogs.
- Timer remains an independent window. Background windows are not hidden just
  to solve overlap. Collapse/expand and dynamically created controls are covered.
- Confirmed class-restricted raiders show Auto Pass in Voting rather than waiting
  or timed out. Unknown eligibility does not cause a pass; explicit responses are
  preserved. The leader synchronizes late class information and new members.
- Change winner has a live 0/160-byte reason counter matching response notes.
- Removed the enforced 16-unit positioning margin. Windows can be placed flush
  against screen edges while remaining on-screen.
- Nine local suites passed, including window layering and class auto passes.
  Native mouse layering, handovers and raid behavior still need in-game checks.
- Protocol 15 and two-minute test response rounds retained. Update all testers.

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
/slt test opens Loot for the Master Looter; queue items to start 60-second rounds.
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
