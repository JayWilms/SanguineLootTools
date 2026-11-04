from check_corpse_transport import peer, source


def master(salvage=False):
    return peer('Master-Realm',native=True,salvage=salvage)


# Physical delivery works with no recipient addon and no transmitted packets.
lua=master(salvage=True)
lua.execute('''
slots[1].quantity=3
for step=0,20 do
    now=step*.1
    A:TickLootConfiguration()
end
assert(#gives==5 and #A.state.items==5 and #A.state.trackedLoot==5)
assert(gives[1].quantity==3 and A.state.items[1].quantity==3)
assert(gives[5].at-gives[1].at<1)
for _,entry in ipairs(A.state.trackedLoot) do
    assert(entry.guid==nil and entry.nativeReceipt and entry.delivery=='delivered')
    assert(entry.deliveryMethod=='masterloot_native')
    assert(not A:CanQueueTrackedLoot(entry),'native-delivered loot became rerollable')
    assert(A:TrackedForItem(A:ItemByID(entry.item))==entry)
end
for step=21,40 do now=step*.1;A:TickLootConfiguration() end
assert(#gives==5,'native delivery repeated while messages were unsent')
assert(#outbox==0,'test sent addon packets before physical handovers')
local receipt
for token,value in pairs(A.state.nativeReceipts) do receipt=value;break end
local entry=A:TrackedByID(receipt.tracked)
assert(A:TradeRemaining(entry)==nil)
''')
print('Three green slots (including quantity 3) and two blues distribute without a recipient addon or network pumping; no invented GUIDs or rerolls.')

# Completed utility assignments leave the active Loot list, regardless of
# quality. Their canonical history/queue protections remain intact, while a
# pending trade or mismatched delivery must remain visible for action.
lua.execute((source/'LootUI.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
lua.execute('''
for _,entry in ipairs(A.state.trackedLoot) do
    local item=A:ItemByID(entry.item)
    assert(A:IsCompletedUtilityAssignment(entry))
    item.awardReason='Disenchant';assert(A:IsCompletedUtilityAssignment(entry))
    item.awardReason='Other';assert(not A:IsCompletedUtilityAssignment(entry))
    item.awardReason='Guild Bank'
    entry.delivery='pending';assert(not A:IsCompletedUtilityAssignment(entry))
    entry.delivery='review';assert(not A:IsCompletedUtilityAssignment(entry))
    entry.delivery='delivered'
    local target=entry.deliveredTo;entry.deliveredTo='Wrong-Realm'
    assert(not A:IsCompletedUtilityAssignment(entry));entry.deliveredTo=target
    item.automaticAssignment=false;assert(not A:IsCompletedUtilityAssignment(entry))
    item.automaticAssignment=true
    assert(not A:CanQueueTrackedLoot(entry))
end
assert(#A.state.items==5 and #A.state.trackedLoot==5 and #A:ArchivableItems()==5)
''')
print('Completed Disenchant/Guild Bank assignments are hidden from active Loot; pending/review, Other and council awards remain visible, with records retained.')

# Quantity proof follows native clear. Duplicate/unrelated clears and stale
# visual loot rows cannot turn a failed give into a delivered record.
lua=master()
lua.execute('''
function GiveMasterLoot(slot,index) end
A:TickLootConfiguration()
assert(A.nativeLoot.active and #A.state.items==0)
A:LootConfigurationEvent('LOOT_SLOT_CLEARED',2)
assert(not A.nativeLoot.active.cleared)
A:LootConfigurationEvent('LOOT_SLOT_CLEARED',1)
A:LootConfigurationEvent('LOOT_SLOT_CLEARED',1)
now=.2;A:TickLootConfiguration()
assert(#A.state.items==0 and A.nativeLoot.confirmed==0,'stale visible slot was treated as delivery')
now=3.2;A:TickLootConfiguration()
assert(not A.nativeLoot.active and A.nativeLoot.failed==1 and #A.state.items==0)
''')
print('Wrong/duplicate clears, unchanged corpse quantity and native timeout do not create false delivery records.')

# Closed windows, stale generations, authority/combat and policy changes.
for change in ["A:LootConfigurationEvent('LOOT_CLOSED')",'combat=true',
               "A.state.master='Other-Realm'",'A.state.lootConfiguration.automatic=false',
               'A.demo=true']:
    lua=master()
    lua.execute(change)
    lua.execute('A:TickLootConfiguration();assert(#gives==0 and #A.state.items==0)')
lua=master()
lua.execute('''
function GiveMasterLoot() end
A:TickLootConfiguration()
A:LootConfigurationEvent('LOOT_CLOSED')
A:LootConfigurationEvent('LOOT_OPENED')
A:LootConfigurationEvent('LOOT_SLOT_CLEARED',1)
assert(A.nativeLoot.active==nil and A.nativeLoot.confirmed==0)
''')

# Re-read native candidates for each item; unavailable first target must not
# stop another eligible slot. Failed calls cannot be auto-retried in a loop.
lua=master()
lua.execute('''
local give=GiveMasterLoot
function GetMasterLootCandidate(slot,index)
    if slot==2 and index==1 then return 'Bank-Realm' end
end
for step=0,10 do now=step*.1;A:TickLootConfiguration() end
assert(#gives==1 and gives[1].slot==2)
''')
lua=master()
lua.execute('''
local calls=0
function GiveMasterLoot() calls=calls+1;error('native failure') end
for step=0,20 do now=step*.1;A:TickLootConfiguration() end
assert(calls==2 and #A.state.items==0 and A.nativeLoot.failed==2)
''')
print('Authority, combat, test mode, close/reopen, ineligible targets and native call failures retain their guards.')

# Identical copies and slot compaction use quantity changes, not slot tombstones.
lua=master()
lua.execute('''
slots[2].id=slots[1].id;slots[2].name=slots[1].name
function GetNumLootItems() return #slots end
function GiveMasterLoot(slot,index)
    local item=slots[slot]
    gives[#gives+1]={slot=slot,id=item.id}
    table.remove(slots,slot)
    A:LootConfigurationEvent('LOOT_SLOT_CLEARED',slot)
end
for step=0,20 do now=step*.1;A:TickLootConfiguration() end
assert(#gives==2 and #A.state.items==2)
assert(A.state.items[1].nativeReceipt~=A.state.items[2].nativeReceipt)
''')
print('Two identical items with compacting slots receive two distinct native distribution records.')

# The client can close the empty corpse immediately after its final clear,
# before the next sender tick. That must not discard the last native result.
lua=master()
lua.execute('''
local give=GiveMasterLoot
function GiveMasterLoot(slot,index)
    give(slot,index)
    if #gives==2 then A:LootConfigurationEvent('LOOT_CLOSED') end
end
for step=0,20 do now=step*.1;A:TickLootConfiguration() end
assert(#gives==2 and #A.state.items==2 and A.nativeLoot.confirmed==2)
assert(not A.corpseOpen and A.nativeLoot.failed==0)
''')
print('Immediate corpse closure after the final clear preserves its confirmed delivery.')

# A later policy edit cannot erase a delivery that already completed under the
# prior revision, and turning automation off prevents the next physical give.
lua=master()
lua.execute('''
A:TickLootConfiguration()
assert(#gives==1 and A.nativeLoot.confirmed==1)
A:RememberNativePolicy()
A.state.lootConfiguration.automatic=false
A.state.lootConfigRevision=1
for step=1,10 do now=step*.1;A:TickLootConfiguration() end
assert(#gives==1 and #A.state.items==1)
local entry=A.state.trackedLoot[1]
assert(entry.deliveryLog[#entry.deliveryLog].method=='masterloot_native')
assert(entry.deliveryLog[#entry.deliveryLog].time==entry.deliveredAt)
''')
print('Policy changes stop new handovers while preserving already confirmed delivery history.')

# Different leader/master: handovers precede receipt transmission. Delivery
# records converge later with idempotence, acknowledgements and archive support.
ml=master(salvage=True)
host=peer('Leader-Realm',native=True,salvage=True)
for lua in [ml,host]:
    lua.execute('''
A.leader='Leader-Realm';A.state.leader=A.leader
A.roster['Leader-Realm']='raid3'
function A:ReadGameMaster() return 'Master-Realm','game' end
''')
ml.execute('''
for step=0,10 do now=step*.1;A:TickLootConfiguration() end
assert(#gives==5 and #A.state.items==0)
local n=0;for _ in pairs(A.nativeLoot.pending) do n=n+1 end;assert(n==5)
''')
for step in range(1200):
    now=round(2+step*.1,1)
    for lua in [ml,host]: lua.globals().now=now
    ml.execute('A:TickLootConfiguration()')
    for lua,other,sender in [(ml,host,'Master-Realm'),(host,ml,'Leader-Realm')]:
        lua.execute('A:PumpSender()')
        box=lua.globals().outbox
        for i in range(1,len(box)+1):
            p=box[i]
            other.globals().A.Receive(other.globals().A,p.prefix,p.message,'WHISPER' if p.target else 'RAID',sender)
        lua.execute('outbox={}')
    if len(ml.globals().A.state['items'])==5:
        break
else:
    raise AssertionError('native result recording did not converge')
assert len(host.globals().A.state['items'])==5
host.execute('''
assert(#A:ArchivableItems()==5)
local old=#A.state.items
local token,data=next(A.state.nativeReceipts)
local tracked=A:TrackedByID(data.tracked)
local result={op='corpseNativeReceipt',token=token,link=tracked.link,quantity=tracked.quantity,
    source=tracked.nativeReceipt.source,slot=tracked.nativeReceipt.slot,quality=tracked.quality,
    at=tracked.nativeReceipt.at,target=data.target,revision=0,reason='Guild Bank',note=''}
local ok,why,unchanged=A:ReduceNativeReceipt('Master-Realm',result)
assert(ok and unchanged and #A.state.items==old)
assert(not A:ReduceNativeReceipt('Bank-Realm',result))
result.quantity=result.quantity+1
assert(not A:ReduceNativeReceipt('Master-Realm',result),'conflicting receipt accepted')
function A:Record(item) self:UpsertAward(item) end
for _,item in ipairs(A.state.items) do A:Record(item) end
assert(#SanguineLootCouncilDB.history==2) -- Three green materials do not consume History capacity.
for _,record in ipairs(SanguineLootCouncilDB.history) do
    assert(record.quantity and record.delivery.method=='masterloot_native')
end
assert(A:ReduceArchive('Master-Realm',{expectedRevision=A.rev}))
assert(#A.state.items==0 and #A.state.trackedLoot==0)
result.quantity=result.quantity-1
local accepted,_,duplicate=A:ReduceNativeReceipt('Master-Realm',result)
assert(accepted and duplicate and #A.state.items==0,'late receipt recreated an archived award')
''')
print('Separate leader/Master Looter: five physical sends before any network delivery; eventual ledger convergence, duplicates and sender validation passed.')

# Background results survive controller reinitialisation without a fake delivery.
ml=master()
ml.execute('''
A.leader='Leader-Realm';A.state.leader=A.leader;A.roster[A.leader]='raid3'
for step=0,5 do now=step*.1;A:TickLootConfiguration() end
local old=A.nativeLoot.pending
assert(next(old))
A.nativeLoot=nil
assert(A:NativeLootState().pending==old)
''')
print('Pending native result persistence and native evidence separation passed.')

# Council collection goes to the real ML, without choosing a winner or using
# the final-assignment toggle. Actual bag GUIDs enter the ordinary council flow.
for timed in [False, True]:
    lua=master()
    lua.execute((source/'Loot.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.globals().timed=timed
    lua.execute('''
A.state.lootConfiguration.rules[4]={action='council',target='',reason='',note=''}
A.state.lootConfiguration.minimum=3
A.state.lootConfiguration.automatic=false
function GetMasterLootCandidate(slot,index) if index==1 then return 'Master-Realm' end end
function C_Item.GetItemGUID(loc) return bags[loc.slot] and bags[loc.slot].guid end
function C_Container.GetContainerItemInfo(bag,slot)
    local item=bags[slot]
    if item then return {hyperlink=itemLink(item.id,item.name,60),stackCount=1,quality=3,isLocked=false} end
end
function A:ReadTradeTimer() if timed then return 'timed',7200 end;return 'unknown' end
if not timed then bags[3]={guid='Item-Old-Council',id=slots[1].id,name=slots[1].name} end
local give=GiveMasterLoot
function GiveMasterLoot(slot,index)
    local item=slots[slot]
    bags[slot]={guid='Item-Council-'..slot,id=item.id,name=item.name}
    give(slot,index)
end
for step=0,20 do now=step*.1;A:TickLootConfiguration() end
assert(#gives==2 and A.nativeLoot.confirmed==2)
assert(#A.state.items==0 and #A.state.trackedLoot==0 and not next(A.nativeLoot.pending))
A:ScanLoot()
assert(#A.state.items==0 and #A.state.trackedLoot==2,'council pickup was awarded or lost')
for _,entry in ipairs(A.state.trackedLoot) do
    assert(entry.holder=='Master-Realm' and entry.verifiedHolder and not entry.manual)
    assert(entry.guid:match('^Item%-Council%-') and not entry.nativeReceipt)
    assert(not entry.item and not entry.deliveredTo and entry.delivery~='delivered')
    assert(A:CanQueueTrackedLoot(entry),'council item cannot enter normal response flow')
    if timed then assert(entry.kind=='timed' and entry.seconds==7200) end
end
A:ScanLoot();assert(#A.state.trackedLoot==2,'repeated scan duplicated council loot')
''')
print('Council loot collects into ML bags with assignment off; real GUIDs/timers remain queueable and unawarded, without collecting an old identical copy.')

for change in ['A.state.lootConfiguration.collection=false',
               "A.state.lootConfiguration.rules[4].action='ignore'"]:
    lua=master()
    lua.execute('''
A.state.lootConfiguration.rules[4]={action='council',target='',reason='',note=''}
A.state.lootConfiguration.minimum=3;A.state.lootConfiguration.automatic=false
function GetMasterLootCandidate(slot,index) if index==1 then return 'Master-Realm' end end
''')
    lua.execute(change)
    lua.execute('A:TickLootConfiguration();assert(#gives==0)')
print('Council collection respects its collection toggle and Ignore policy.')
