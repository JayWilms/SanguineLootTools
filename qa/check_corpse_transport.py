from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parent.parent
source=root/'SanguineLootTools'

def peer(name, before=False, identical=False, salvage=False):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
A={};SlashCmdList={};now=0;outbox={};bags={};gives={};NUM_BAG_SLOTS=0;combat=false
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
''')
    for module in ['Core','Features','Archive','Awards','Equipment','Voting','ResponseConfig',
                   'Responses','Warnings','Loot','LootConfiguration','WireCodec','StateDelta','Network']:
        path=root/'qa/fixtures/LootConfiguration-alpha50.lua' if before and module=='LootConfiguration' else source/(module+'.lua')
        lua.execute(path.read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.globals().peerName=name
    lua.execute('''
A.me=peerName;A.leader='Master-Realm'
A.roster={['Master-Realm']='raid1',['Bank-Realm']='raid2'}
A.Client={}
function A.Client:Uptime() return now end
function A.Client:ServerTime() return 100000+math.floor(now) end
function A.Client:Combat() return combat end
function A.Client:ClockReady() return true end
function A.Client:InRaid() return true end
function A.Client:InGroup() return true end
function A.Client:Invoke(fn,...) if type(fn)~='function' then return false end;return pcall(fn,...) end
function A.Client:Call(api,prefix,message,channel,target)
    assert(api=='C_ChatInfo.SendAddonMessage')
    outbox[#outbox+1]={prefix=prefix,message=message,target=target}
    return true,0
end
function A:SyncGameMaster() end
function A:ReadGameMaster() return 'Master-Realm','game' end
function A:Record() end
A.PrimeLootBagSnapshot=nil;A.PruneActiveCaches=nil;A.PersistSession=nil
function A:RenderNetworkStatus() end
function A:WarningPacket() return false end
function A:FeaturePacket() return false end
function A:Print(message) error(message) end
function A:Render() end
function A:ClearPendingPersonalResponse() end
function A:RequestSync() error('unexpected state revision gap') end
function UnitIsConnected() return true end
function GetMasterLootCandidate(slot,index) if index==1 then return 'Bank-Realm' end end
lootThreshold=3
function GetLootThreshold() return lootThreshold end
slots={
 {id=209578,name='Glowing Leather Bands'},
 {id=211506,name='Twilight Avenger Boots'}}
function itemLink(id,name,level)
    return '|cff0070dd|Hitem:'..id..'::::::::'..level..':::::::::|h['..name..']|h|r'
end
lootSlotCount=2
function GetNumLootItems() return lootSlotCount end
function GetLootSlotLink(slot)
    local item=slots[slot];return item and itemLink(item.id,item.name,25)
end
function GetLootSlotInfo(slot)
    if slots[slot] then return 1,slots[slot].name,1,nil,slots[slot].quality or 3,false,false end
end
function GetLootSourceInfo(slot) if slots[slot] then return 'Creature-Boss',1 end end
function GiveMasterLoot(slot,index)
    assert(index==1 and slots[slot])
    local item=slots[slot]
    gives[#gives+1]={at=now,slot=slot,id=item.id,name=item.name}
    slots[slot]=nil
    A:LootConfigurationEvent('LOOT_SLOT_CLEARED',slot)
end
C_Container={GetContainerNumSlots=function() return 4 end,
    GetContainerItemInfo=function(bag,slot)
        local item=bags[slot]
        if item then return {hyperlink=itemLink(item.id,item.name,60),stackCount=item.count or 1,isLocked=false} end
    end}
ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {slot=slot} end}
C_Item={GetItemGUID=function(loc) return bags[loc.slot].guid end,IsBound=function() return true end,
    GetItemInfo=function(link)
        return 'Item',link,3,30,25,'Item','Item',link:match('item:900001:') and 20 or 1
    end}
SanguineLootCouncilDB={}
A:InitStorage()
A.state={id='transport-test',leader='Master-Realm',master='Master-Realm',council={},items={},trackedLoot={},
    responseOptions=A:DefaultResponses(),rules=A:DefaultVoting(),responseDuration=60,lootConfigRevision=0,
    lootConfiguration=A:DefaultLootConfiguration(),retiredGUIDs={}}
A.state.lootConfiguration.automatic=true
A.state.lootConfiguration.rules[4]={action='assign',target='Bank-Realm',reason='Guild Bank',note=''}
A.rev=1;A.publicBaseline=A:PublicState();A.corpseOpen=A.me=='Master-Realm'
''')
    if identical:
        lua.execute('slots[2].id=slots[1].id;slots[2].name=slots[1].name')
    if salvage:
        lua.execute('''
slots[4],slots[5]=slots[1],slots[2]
for i=1,3 do slots[i]={id=900001,name='Grime-Encrusted Salvage',quality=2} end
lootSlotCount=5
lootThreshold=2
A.state.lootConfiguration.rules[3]={action='assign',target='Bank-Realm',reason='Guild Bank',note=''}
A.publicBaseline=A:PublicState()
if A.me=='Bank-Realm' then bags[1]={id=900001,name='Grime-Encrusted Salvage',count=12,guid='Item-Existing-Stack'} end
''')
    return lua

def run(before=False, identical=False, fast=True, cold=False, salvage=False):
    master=peer('Master-Realm',before,identical,salvage)
    recipient=peer('Bank-Realm',before,identical,salvage)
    peers=[master,recipient]
    fragments=[0,0]
    given=0
    end=None
    start=0
    if cold:
        # Exhaust the startup burst, as in an already active raid. The actual
        # token bucket/refill logic remains in PumpSender, not in this fixture.
        for lua in peers:
            lua.execute("for i=1,8 do A:Send({kind='warmup'}) end")
            for step in range(8):
                lua.globals().now=round(step*.11,2)
                lua.execute('A:PumpSender()')
            lua.execute('outbox={}')
        start=.8
    for step in range(1800):
        now=round(start+step*.1,1)
        for lua in peers: lua.globals().now=now
        if step%10==0:
            for lua in peers: lua.execute('A:TickLootConfiguration()')
        for index,lua in enumerate(peers):
            if fast:
                lua.execute('A:ServiceCorpseActions()')
            lua.execute('A:PumpSender()')
            box=lua.globals().outbox
            other=peers[1-index]
            sender='Master-Realm' if index==0 else 'Bank-Realm'
            for i in range(1,len(box)+1):
                packet=box[i]
                other.globals().A.Receive(other.globals().A,packet.prefix,packet.message,
                                         'WHISPER' if packet.target else 'RAID',sender)
                fragments[index]+=1
            lua.execute('outbox={}')
        native=master.globals().gives
        while given<len(native):
            given+=1
            drop=native[given]
            recipient.globals().bags[given+(1 if salvage else 0)]=recipient.table_from({
                'id':drop.id,'name':drop.name,'guid':'Item-Received-'+str(given)})
            recipient.execute("A:LootConfigurationEvent('BAG_UPDATE_DELAYED')")
        # Continue after both native sends until both canonical copies arrive.
        if len(recipient.globals().A.state['items'])==2:
            end=now
            break
    assert end is not None,'automatic distribution stalled'
    for lua in peers:
        assert len(lua.globals().A.state['items'])==2
        assert len(lua.globals().A.state.trackedLoot)==2
        entries=lua.globals().A.state.trackedLoot
        assert entries[1].guid!=entries[2].guid
        assert entries[1].delivery=='delivered' and entries[2].delivery=='delivered'
    first,second=master.globals().gives[1].at,master.globals().gives[2].at
    if salvage:
        assert master.globals().gives[1].slot==4 and master.globals().gives[2].slot==5
        master.execute('''
local blocked=0
for _,route in pairs(A.state.corpseRoutes) do
    if route.failure=='stacked' then blocked=blocked+1;assert(route.failed and not route.started) end
end
assert(blocked==1 and slots[1] and slots[2] and slots[3],'blocked material routes '..blocked)
A:TickLootConfiguration()
assert(A.lootRoutingStatus=='Stacked materials need manual distribution; continuing eligible single-copy items.')
''')
    return {'first':round(first-start,2),'second':round(second-start,2),
            'gap':round(second-first,2),'synced':end,'fragments':fragments}

if __name__=='__main__':
    before=run(True,fast=False)
    after=run()
    polling=run(fast=False)
    cold_polling=run(fast=False,cold=True)
    cold_fast=run(cold=True)
    assert after['gap']<before['gap'],(before,after)
    assert after['gap']<=5,(before,after)
    assert after['first']<polling['first'],(polling,after)
    assert cold_fast['first']<cold_polling['first'],(cold_polling,cold_fast)
    identical=run(identical=True)
    salvage=run(salvage=True)
    assert salvage['first']<10 and salvage['gap']<10,salvage
    # An urgent wake is scheduling only: permission/combat/window checks still
    # run immediately before any native item transfer.
    for change in ["A:LootConfigurationEvent('LOOT_CLOSED')",'combat=true',
                   "A.state.master='Other-Realm'",'A.state.lootConfiguration.automatic=false']:
        lua=peer('Master-Realm')
        lua.execute('''
A:TickLootConfiguration()
for token,route in pairs(A.state.corpseRoutes) do
    assert(A:HostRequest('Bank-Realm',{op='corpseReady',sid=A.state.id,token=token}))
end
A:ServiceCorpseActions()
assert(#gives==0)
''')
        lua.execute(change)
        lua.execute('A.corpseScanSoon=true;A:ServiceCorpseActions();assert(#gives==0)')
    print('Two real codec/queue peers, 1 message/sec: before',before,'after',after)
    print('Polling versus event wake: warm',polling,after,'depleted burst',cold_polling,cold_fast)
    print('Identical copies retain sequential receipt proof:',identical)
    print('Three stacked-material slots ahead of two blues: blues progress, materials remain manual:',salvage)
    print('Both native sends and canonical delivered awards verified; simulated timing is not a native-client guarantee.')
