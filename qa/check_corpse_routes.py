from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parent.parent
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
A={Client={}}
function A.Client:Invoke(fn,...) if type(fn)~='function' then return false end;return pcall(fn,...) end
function A.Client:ServerTime() return 100 end
function A.Client:InRaid() return true end
function A.Client:Combat() return false end
''')
lua.execute((root/'SanguineLootTools/LootConfiguration.lua').read_text(encoding='utf-8'),
            'SanguineLootTools',lua.globals().A)
lua.execute('''
function A:EquipmentLink(link) return type(link)=='string' and link:match('item:%d+') and link end
function A:IsMaster() return true end
function A:ReadGameMaster() return self.me,'game' end
function A:Resolve(name) return name end
function A:TrackedByID() end
function A:TrackedByGUID(guid)
    for _,entry in ipairs(self.state.trackedLoot) do if entry.guid==guid then return entry end end
end
function A:PolicyTarget(rule) return rule.target end
function A:NextIdentity() return #self.state.trackedLoot+1 end
function A:MakeAutomaticAward(entry,intent,by,delivered)
    assert(delivered and intent.cleared and intent.guid==entry.guid)
    entry.delivery='delivered';self.state.trackedLoot[#self.state.trackedLoot+1]=entry
    self.state.items[#self.state.items+1]={lootGUID=entry.guid,winner=intent.target}
    return true
end
function A:Act(op,p)
    p.op=op
    local ok,why=self:ReduceLootConfiguration(self.me,p);assert(ok,why)
end
local slots,gives,mode={},0
function A:NativeCorpseItem(slot) return slots[slot] end
function GetNumLootItems() return 2 end
function GetLootThreshold() return 3 end
function GetMasterLootCandidate(slot,index) if index==1 then return 'Bank-Realm' end end
function UnitIsConnected() return true end
local function confirm(intent)
    local ok,why=A:ReduceLootConfiguration('Bank-Realm',{op='corpseReceipt',token=intent.token,
        guid='Item-Received-'..gives,link=intent.link})
    assert(ok,why)
end
function GiveMasterLoot(slot,candidate)
    gives=gives+1
    assert(candidate==1 and gives<=2,'repeated or invalid native award')
    local intent
    for _,route in pairs(A.state.corpseRoutes) do
        if route.started and not route.finished and not route.failed then intent=route end
    end
    assert(intent and intent.slot==slot)
    A:LootConfigurationEvent('LOOT_SLOT_CLEARED',slot)
    if mode=='compact' then
        table.remove(slots,slot)
        for i,item in ipairs(slots) do item.slot=i end
    elseif mode~='retained' then slots[slot]=nil end
    if mode~='delayed' then confirm(intent) end
end
local function setup(which)
    mode=which;gives=0
    A.me='Master-Realm';A.leader=A.me;A.corpseOpen=true;A.corpseSID=nil
    A.roster={['Bank-Realm']='raid2'}
    A.state={id=which,master=A.me,items={},trackedLoot={},lootConfiguration=A:DefaultLootConfiguration()}
    A.state.lootConfiguration.automatic=true
    A.state.lootConfiguration.rules[4]={action='assign',target='Bank-Realm',reason='Guild Bank',note=''}
    slots={
        {slot=1,link='item:209578',source='Creature-Boss',quality=3},
        {slot=2,link='item:211506',source='Creature-Boss',quality=3}}
end
local function tick()
    A:TickLootConfiguration()
    for _,intent in pairs(A.state.corpseRoutes or {}) do
        if not intent.ready and not intent.finished and not intent.failed then
            local ok,why=A:ReduceLootConfiguration('Bank-Realm',{op='corpseReady',token=intent.token})
            assert(ok,why)
        end
    end
end
for _,which in ipairs({'holes','retained','compact'}) do
    setup(which)
    for i=1,12 do tick() end
    assert(gives==2 and #A.state.items==2 and #A.state.trackedLoot==2,which)
    for i=1,5 do tick() end
    assert(gives==2,'completed drops awarded again')
end
-- Identical copies retain distinct slot assignments when slots remain stable.
setup('identical');slots[2].link=slots[1].link
for i=1,12 do tick() end
assert(gives==2 and #A.state.trackedLoot==2)
-- Preserve the one-at-a-time receipt gate: a cleared slot alone is insufficient.
setup('delayed')
for i=1,8 do tick() end
assert(gives==1 and #A.state.items==0)
assert(A.lootRoutingStatus=='Awaiting recipient bag confirmation before the next item')
local first
for _,intent in pairs(A.state.corpseRoutes) do if intent.started then first=intent end end
confirm(first)
for i=1,8 do tick() end
assert(gives==2)
-- A failed early slot must not block a later eligible item.
setup('failed');tick()
for _,intent in pairs(A.state.corpseRoutes) do if intent.slot==1 then intent.failed=true end end
slots[1]=nil
for i=1,8 do tick() end
assert(gives==1 and #A.state.items==1)
''')
print('Multiple boss drops: stable/retained/compacted slots, distinct copies, receipt gate and failed assignments passed.')

for name in ['Equipment','Loot']:
    lua.execute((root/'SanguineLootTools'/f'{name}.lua').read_text(encoding='utf-8'),
                'SanguineLootTools',lua.globals().A)
lua.execute('''
-- Real hyperlinks differ across characters. Existing copies must be in the
-- baseline and the newly received GUID must remain reserved from normal scans.
local sourceLink='|cff0070dd|Hitem:209578::::::::25:::::::::|h[Glowing Leather Bands]|h|r'
local bagLink='|cff0070dd|Hitem:209578::::::::60:::::::::|h[Glowing Leather Bands]|h|r'
local bags={{guid='Item-Old-Bands',link=bagLink}}
NUM_BAG_SLOTS=0
C_Container={GetContainerNumSlots=function() return 4 end,
    GetContainerItemInfo=function(bag,slot)
        local item=bags[slot]
        if item then return {hyperlink=item.link,stackCount=1,isLocked=false} end
    end}
ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {slot=slot} end}
C_Item={GetItemGUID=function(location) return bags[location.slot].guid end,IsBound=function() return true end}
local route={token='route',source='Creature-Boss',slot=1,link=sourceLink,quality=3,target='Bank-Realm',
    revision=0,by='Master-Realm',time=100,reason='Guild Bank'}
A.me='Bank-Realm';A.corpseSID=nil
A.state={id='recipient-links',master='Master-Realm',items={},trackedLoot={},corpseRoutes={route=route}}
A.state.lootConfiguration=A:DefaultLootConfiguration();A.state.lootConfiguration.automatic=true
A.roster={['Bank-Realm']='player'}
function A:IsMaster() return false end
A:TickLootConfiguration()
assert(route.ready and A.corpseSnapshots.route['Item-Old-Bands'])
assert(A:ReduceLootConfiguration('Master-Realm',{op='corpseStarted',token='route'}))
assert(A:ReduceLootConfiguration('Master-Realm',{op='corpseCleared',token='route'}))
bags[2]={guid='Item-New-Bands',link=bagLink}
assert(A:CorpseReservation('Item-New-Bands',bagLink))
assert(not A:CorpseReservation('Item-Old-Bands',bagLink))
A:TickLootConfiguration()
assert(route.finished and route.guid=='Item-New-Bands' and #A.state.items==1)
assert(not A:CorpseReservation('Item-New-Bands',bagLink))
-- Multiple new copies are ambiguous: item ID matching must not invent proof.
route.finished,route.guid=nil,nil
A.state.items={};A.state.trackedLoot={}
bags[3]={guid='Item-Another-Bands',link=bagLink}
A.corpseSnapshots.route={['Item-Old-Bands']=true}
A:TickLootConfiguration()
assert(not route.guid and not route.finished and #A.state.items==0)
A.me='Master-Realm'
''')
print('Actual cross-character hyperlinks: old-copy baseline, reserved fresh GUID, verified receipt and ambiguous copies passed.')

lua.execute('''
local now,count=0,0
function A.Client:ServerTime() return now end
function A:Act() count=count+1;return true end
A.state.id='delayed-network'
for second=0,19 do
    now=second
    A:SendCorpseAction('corpseReceipt',{token='copy',guid='Item-New'})
end
assert(count==4,'waiting for state queued the same receipt every tick')
now=20;A:SendCorpseAction('corpseReceipt',{token='copy',guid='Item-New'})
assert(count==5,'bounded retry did not recover a missing confirmation')
A.state.id='another-session'
A:SendCorpseAction('corpseReceipt',{token='copy',guid='Item-New'})
assert(count==6,'new session retained a previous retry cooldown')
local reject=true
function A:Act() count=count+1;if reject then reject=false;return false end;return true end
A:SendCorpseAction('corpseStarted',{token='other'})
A:SendCorpseAction('corpseStarted',{token='other'})
assert(count==7,'a rejected background action retried on the next tick')
now=25;A:SendCorpseAction('corpseStarted',{token='other'})
assert(count==8,'bounded retry did not recover')
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
''')
lua.execute((root/'SanguineLootTools/Network.lua').read_text(encoding='utf-8'),
            'SanguineLootTools',lua.globals().A)
lua.execute('''
function A:IsSoloTest() return false end
function A:RosterKey() return 'raid' end
function A:PublicState() return {id='routing'} end
function A:StateChanges() return {} end
local privateCount,sent=0,0
function A:SendPrivate() privateCount=privateCount+1 end
function A:Send(packet,target,options)
    sent=sent+1
    assert(packet.kind=='stateDelta' and options.liveResponse)
    assert(A:NetworkMessagePriority(packet,options)==1)
end
A.publicBaseline={id='routing'};A.rev=2
for _,op in ipairs({'corpsePrepare','corpseReady','corpseStarted','corpseCleared','corpseReceipt','corpseFailed'}) do
    A:Publish({op=op})
end
assert(sent==6 and privateCount==0,'corpse handshakes resent unrelated private ballot views')
function A:IsLeader() return true end
function A:SyncGameMaster() end
local printed,errors=0,0
function A:Print() printed=printed+1 end
function A:Send(packet) assert(packet.kind=='error');errors=errors+1 end
local why='Corpse assignment is stale or unavailable.'
function A:Reduce() return false,why end
for i=1,20 do
    A:HostRequest(A.me,{op='corpseReceipt'})
    A:HostRequest('Bank-Realm',{op='corpseReady'})
end
why='No pending award for this trade partner.'
A:HostRequest(A.me,{op='tradeActivity'})
A:HostRequest('Bank-Realm',{op='tradeActivity'})
assert(printed==0 and errors==0)
assert(A.networkMetrics.staleCorpseRequests==40 and A.networkMetrics.irrelevantTradeReports==2)
why='Invalid received bag copy.'
A:HostRequest(A.me,{op='corpseReceipt'})
A:HostRequest('Bank-Realm',{op='corpseReceipt'})
assert(printed==1 and errors==1,'real validation errors were hidden')
''')
print('Bounded confirmation retries, session reset, failed queue recovery and prioritised public handshakes without private fan-out passed.')

lua.execute('''
-- Repeated confirmations while broadcasts are delayed must not create more
-- revisions/broadcasts behind that same backlog. Use the real reducer/host.
A.me='Master-Realm';A.rev=100
function A.Client:ServerTime() return 100 end
A.state={id='idempotence',master=A.me,items={},trackedLoot={},corpseRoutes={},lootConfigRevision=0,
    lootConfiguration=A:DefaultLootConfiguration()}
A.state.lootConfiguration.automatic=true
A.state.lootConfiguration.rules[4]={action='assign',target='Bank-Realm',reason='Guild Bank',note=''}
A.roster={['Bank-Realm']='raid2'}
function A:Reduce(sender,p) return self:ReduceLootConfiguration(sender,p) end
function A:Send() error('duplicate confirmation emitted another packet') end
function A:Publish() error('duplicate confirmation republished state') end
function A:Changed() error('duplicate confirmation advanced state') end
local link='|cff0070dd|Hitem:209578::::::::25:::::::::|h[Glowing Leather Bands]|h|r'
local token='Creature-Boss:1:209578'
A.state.corpseRoutes[token]={token=token,target='Bank-Realm',by=A.me,link=link,revision=0,
    time=100,ready=true,started=true,cleared=true}
for i=1,20 do
    assert(A:HostRequest('Bank-Realm',{op='corpseReady',token=token}))
    assert(A:HostRequest(A.me,{op='corpseStarted',token=token}))
    assert(A:HostRequest(A.me,{op='corpseCleared',token=token}))
    assert(A:HostRequest(A.me,{op='corpsePrepare',source='Creature-Boss',slot=1,quality=3,link=link}))
end
assert(A.rev==100 and A.networkMetrics.duplicateCorpseRequests==80)
A.state.corpseRoutes[token].finished=true
assert(A:HostRequest('Bank-Realm',{op='corpseReceipt',token=token,guid='Item-New',link=link}))
assert(A.rev==100 and A.networkMetrics.duplicateCorpseRequests==81)
''')
print('Delayed-state duplicate confirmations do not amplify the queue or advance revisions.')
