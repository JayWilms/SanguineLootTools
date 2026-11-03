# Loot distribution review — 3 November 2026

## Finding

Through alpha.53, Sanguine's native corpse distribution is coupled to its addon communication and
bag-copy tracking protocol. The current path prepares a route, waits for the
recipient's bag snapshot, confirms readiness through shared state, starts the
handover, waits for the corpse slot to clear and for a fresh bag GUID, and only
then releases the next physical transfer. State broadcasts share a paced queue.

These are useful tracking checks, but making all of them prerequisites for
physical distribution adds network round trips that native Master Loot does not
require. Polling and queue optimisations have reduced parts of this cost without
removing that coupling. Existing material stacks expose a second consequence:
merging into a stack cannot produce the new unique GUID this protocol expects.

The user's alpha.49 reports showed a leader queue peak of 27 fragments and a
50.1-second oldest message, without throttle failures. Alpha.51 native testing
reported seven seconds for the first drop and three more for the second.
The stacked-Salvage alpha.52 test produced expired routes. These are separate
reproductions; none proves that every subsequent pause has the same cause.

## References reviewed

### TheMizeGuy/wow-addon-dev

[Skill entry](https://github.com/TheMizeGuy/wow-addon-dev/blob/main/SKILL.md)
and [events/communications reference](https://github.com/TheMizeGuy/wow-addon-dev/blob/main/references/api-events-frames.md).

This is general addon development guidance, chiefly oriented to modern Retail
with Classic notes. Its event-driven design and communication guidance are
relevant, but it is not a Forever-specific loot implementation. Do not treat
its Retail-only guidance or unverified claims as the target client's contract.
It was reviewed as documentation; it was not installed or executed.

### RCLootCouncil Classic

[Classic auto-award path](https://github.com/evil-morfar/RCLootCouncil_Classic/blob/develop/API/MLUpdates.lua)
and [the core version pinned by that Classic repository](https://github.com/evil-morfar/RCLootCouncil2/blob/7270494ab3f9552792f51df5ced6e9c8db39aa24/ml_core.lua).

The inspected CanGiveLoot/GiveLoot/OnLootSlotCleared path checks native loot
availability and candidate eligibility, invokes GiveMasterLoot locally and
resolves a queued attempt through the slot-cleared event. A timeout reports
failure. AutoAward logs/announces after that success callback. The inspected
path does not wait for a recipient bag-snapshot handshake before GiveMasterLoot.

This supports the architectural comparison, not a latency guarantee on Forever.
No implementation was imported or copied.

### SimpleLootCouncil

[Author's public README](https://github.com/SimpleLootCouncil/SimpleLootCouncil/blob/main/README.md).

The public repository inspected exposes documentation and media, not its loot
implementation. The author describes Forever Master Loot, bag-based council
voting and delivery confirmation after an item changes hands. This establishes
documented behaviour; it does not establish an internal queue algorithm or an
instant-distribution benchmark. Source reuse is explicitly restricted.

### WLC

[Author's project description](https://www.curseforge.com/wow/addons/w-l-c).

The author documents quality-based distribution on opening a corpse, direct
Master Loot awards and small individual communication messages. These are
useful functional comparisons. A public implementation repository was not found
in this review; no internal timing or acknowledgement mechanism is claimed.

## Recommended independent redesign

1. **Local native distributor.** The actual in-game Master Looter validates
   the active normal session, enabled policy, current authority, out-of-combat
   state, open corpse, current slot/source/item/quantity, quality threshold,
   connected recipient and native candidate list. A configured council winner
   still requires its normal award decision. Automatic quality routing uses
   the saved quality policy.
2. **Native result drives the next handover.** Record one local attempt before
   calling GiveMasterLoot. Match LOOT_SLOT_CLEARED to that attempt and the current
   corpse generation. Re-read remaining slots and candidate eligibility before
   advancing. Do not wait for shared-state revision delivery or a recipient
   addon reply to move the next eligible item.
3. **Distinct evidence types.** Record a native-confirmed corpse distribution
   as native evidence. Record later bag GUID verification separately. Never
   fabricate an Item GUID, mark a timed-out attempt delivered, or claim a stack
   count is proof of a distinct equipment copy.
4. **Background recording.** Queue compact idempotent result messages and batch
   history/state updates. Display unsynchronised results explicitly if needed.
   A busy history queue must not stall native handovers. Keep the established
   sustainable addon-message pacing; do not solve latency by flooding it.
5. **Materials and quantities.** Use native source/slot/generation plus quantity
   for stackable corpse-distribution records. The recipient's existing stack
   must not prevent native Master Loot. Stack merging and per-copy trade tracking
   remain distinct operations. Bag-to-player trades still require the normal
   trade window and player acceptance.
6. **Failure handling.** No matching native clear means no success record. Close,
   authority/rule changes, full bags, ineligible recipients and timeouts must be
   surfaced without automatic blind repeats. Clear events from an old corpse or
   unrelated manual actions must not confirm another attempt. A failed attempt
   must not silently reroute to a different recipient.

This changes evidence and data-flow contracts. It needs dedicated implementation
and compatibility review, not a further timer-only patch. Protocol/session
versioning must be decided before deploying any new receipt schema.

## Acceptance checks for implementation

- Recipient addon absent, delayed or reloading: eligible native transfers still
  advance; tracking status remains honest about evidence available.
- Delayed/lost/duplicated addon messages: physical transfers are not repeated and
  eventual history converges exactly once.
- Existing stacks, multiple units in a loot slot and repeated identical drops:
  quantities remain correct without invented copy identities.
- Compacted loot slots, corpse close/reopen and stale clear events: the intended
  source/item/recipient remains stable and no unrelated item is awarded.
- Full bags, absent/ineligible recipient, combat and authority/configuration
  changes: no false delivery and a clear reason for failure or deferral.
- Separate leader and Master Looter: local native authority and current policy
  are rechecked, and the host accepts results only from its authorised master.
- Test mode retains zero real transfers. Council responses and subsequent
  player-to-player trading retain their existing permissions and confirmations.
- Native raid tests measure first transfer, later transfers and history-sync
  completion separately; simulation timings must not be presented as observed
  client behaviour.

## Implementation status

Alpha.54 implements a local native distributor in NativeLoot.lua.
It requires a matching slot-clear event and the expected reduction in corpse
quantity before recording success. Only one give is active at a time; the next
eligible handover no longer waits for recipient snapshots or network delivery.
Final-drop confirmation is captured even if the empty corpse closes immediately.

Protocol 16 distinguishes native receipts from bag GUID evidence. Receipts carry
source, slot, quantity, policy revision and a unique operation token. The host
validates the authorised Master Looter and policy, records each token once, and
acknowledges duplicates without recreating awards. Pending receipts survive a
controller reload; failed history recording remains visible and retryable.
History preserves quantities and labels native evidence as bag-GUID unverified.
Later bag-copy verification is not implemented for these native receipts.

Collect for council now has its own pickup branch in the local distributor.
With collection enabled and both quality thresholds satisfied, eligible
single-copy council loot goes to the actual Master Looter without creating an
award receipt. Local bag evidence then enters the existing tracking, timer and
queue flow with the real item GUID. The automatic-assignment switch is not
required for council pickup. Stackable council drops remain manual because the
voting flow requires separate copies; this does not limit stacked final
automatic assignments. Settings explain the destination and the two switches.

All 17 local suites pass, including stacked greens plus blue equipment without
recipient messages, distinct identical drops, compacted slots, unchanged-quantity
failures, timeouts, authority/combat gates, immediate final-drop closure, policy
changes, separate leader/Master Looter synchronisation, duplicates, archive and
pending-result persistence. These are simulations; native client timing and bag
behaviour still require the checklist in TESTING.md.

The alpha.54 installer packages these changes for native testing. GitHub
publication is a separate action.
