from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'

def peer(name,names,party=False):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
A={};SlashCmdList={};now=0;outbox={};messages={};combat=false
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
''')
    for module in ['Core','WireCodec','Network','Awards','History','HistorySync']:
        lua.execute((SRC/(module+'.lua')).read_text(),'SanguineLootTools',lua.globals().A)
    lua.globals().peerName=name
    lua.globals().isParty=party
    lua.execute('''
A.me=peerName;A.leader='Zergul-Realm';A.roster={};A.Client={}
function A.Client:Uptime() return now end
function A.Client:ServerTime() return 1800000000+math.floor(now) end
function A.Client:Combat() return combat end
function A.Client:InGroup() return true end
function A.Client:InRaid() return not isParty end
function A.Client:Call(api,prefix,message,channel,target)
 assert(api=='C_ChatInfo.SendAddonMessage');outbox[#outbox+1]={prefix=prefix,message=message,channel=channel,target=target};return true,0
end
function A.Copy(v) if type(v)~='table' then return v end;local r={};for k,x in pairs(v) do r[k]=A.Copy(x) end;return r end
SanguineLootCouncilDB={history={},raidSetup={council={['Moon-Realm']=true}}}
function A:InitStorage() self:PruneGreenHistory() end
function A:Print(message) messages[#messages+1]=message end
A.state={id='active-session',master='Zergul-Realm',council={['Moon-Realm']=true},items={{id=1,status='open'}}}
A.rev=42
function award(key,id,time,winner,revision,reason)
 return {key=key,item='|cff0070dd|Hitem:'..id..':0|h[Item '..id..']|h|r',time=time,winner=winner or 'Zergul-Realm',revision=revision or 1,
 quality=3,deliveryRevision=0,awardReason=reason,corrections={}}
end
''')
    for index,member in enumerate(names,1):
        lua.globals().A.roster[member]='raid'+str(index)
    return lua

def state(lua):
    return lua.globals().A.historySync

def run(peers,start=0,limit=3000,drop=None):
    names=list(peers)
    for tick in range(start,limit):
        for lua in peers.values():
            lua.globals().now=tick
            lua.execute('A:TickHistorySync();A:PumpSender()')
        for name,lua in peers.items():
            for _,packet in lua.globals().outbox.items():
                for recipient,other in peers.items():
                    if name==recipient or (packet.target and packet.target!=recipient): continue
                    if drop and drop(name,recipient,packet): continue
                    other.globals().A.Receive(other.globals().A,packet.prefix,packet.message,packet.channel,name)
            lua.execute('outbox={}')
        if tick>start+20 and all(not state(lua) for lua in peers.values()):
            # Finish broadcasts are queued after local state is cleared.
            if all(lua.globals().A.NetworkQueueStats(lua.globals().A)[0]==0 for lua in peers.values()):
                return tick+1
    raise AssertionError('sync did not finish within simulation bound')

names=['Zergul-Realm','Moon-Realm','Absent-Realm','Council-Realm']
peers={name:peer(name,names) for name in names}
peers[names[0]].execute('''
SanguineLootCouncilDB.history={award('raid-a:1',100,100),award('raid-a:2',100,101),award('shared:1',200,110,'Old-Realm')}
''')
peers[names[1]].execute('''
local corrected=award('shared:1',200,120,'Moon-Realm',2)
corrected.original={winner='Old-Realm',time=110}
corrected.corrections={{revision=2,from='Old-Realm',to='Moon-Realm',by='Zergul-Realm',time=120,reason='Winner corrected'}}
corrected.deliveryRevision=3;corrected.archivedAt=130
corrected.delivery={status='delivered',holder='Moon-Realm',log={{action='delivered',time=125,by='Zergul-Realm'}}}
local green=award('green:1',300,140);green.quality=2
SanguineLootCouncilDB.history={corrected,award('raid-b:1',400,115,'Bank-Realm',1,'Guild Bank'),green}
''')
peers[names[3]].execute("SanguineLootCouncilDB.history={award('raid-c:1',500,116)}")
assert peers[names[0]].globals().A.StartHistorySync(peers[names[0]].globals().A)
end=run(peers)
for lua in peers.values():
    lua.execute('''
assert(#SanguineLootCouncilDB.history==5)
local seen={}
for _,r in ipairs(SanguineLootCouncilDB.history) do assert(not seen[r.key]);seen[r.key]=r end
assert(seen['raid-a:1'] and seen['raid-a:2'],'identical item copies were combined')
assert(seen['raid-b:1'].awardReason=='Guild Bank' and seen['raid-c:1'])
assert(not seen['green:1'])
assert(seen['shared:1'].winner=='Moon-Realm' and seen['shared:1'].revision==2)
assert(seen['shared:1'].deliveryRevision==3 and seen['shared:1'].delivery.status=='delivered')
assert(#seen['shared:1'].corrections==1 and seen['shared:1'].archivedAt==130)
assert(A.state.id=='active-session' and A.state.items[1].status=='open' and A.rev==42)
assert(#A:FilterHistoryRecords(nil,'')==4 and #A:FilterHistoryRecords(nil,'',true)==1)
assert(A.historySyncMessage:find('finished',1,true))
''')
# Repeating from a council member is idempotent and uses digest shortcuts.
for lua in peers.values(): lua.globals().now=end+31
assert peers[names[1]].globals().A.StartHistorySync(peers[names[1]].globals().A)
end=run(peers,start=end+31,limit=end+600)
for lua in peers.values(): lua.execute('assert(#SanguineLootCouncilDB.history==5)')
print('Split raid union, absent member catch-up, council initiation, identical copies, corrections, delivery audits, Guild Bank and repeat sync pass.')

# Party synchronization works with no live loot session; regular raiders cannot initiate.
party_names=['Zergul-Realm','Moon-Realm','Absent-Realm']
party={name:peer(name,party_names,party=True) for name in party_names}
for lua in party.values(): lua.execute('A.state=nil')
assert not party['Absent-Realm'].globals().A.StartHistorySync(party['Absent-Realm'].globals().A)
party['Moon-Realm'].execute("SanguineLootCouncilDB.history={award('party:1',900,150)}")
assert party['Moon-Realm'].globals().A.StartHistorySync(party['Moon-Realm'].globals().A)
run(party)
for lua in party.values(): lua.execute('assert(#SanguineLootCouncilDB.history==1 and A.state==nil)')
print('Party catch-up without an active session and initiator permissions pass.')

# Merge validation is atomic; lower award revisions cannot beat higher ones by
# claiming a higher delivery revision. Capacity is applied after the union.
lua=peer('Zergul-Realm',names)
lua.execute('''
SanguineLootCouncilDB.history={}
for i=1,500 do SanguineLootCouncilDB.history[i]=award('retained:'..i,100,i,'Zergul-Realm',2) end
local stale=award('retained:500',100,501,'Wrong-Realm',1);stale.deliveryRevision=999
assert(A:MergeHistorySyncRecords({stale}))
local fresh=award('new:1',200,501)
assert(A:MergeHistorySyncRecords({fresh}))
assert(#SanguineLootCouncilDB.history==500 and SanguineLootCouncilDB.history[1].key=='new:1')
for _,r in ipairs(SanguineLootCouncilDB.history) do assert(r.key~='retained:1' and r.winner~='Wrong-Realm') end
local invalid=award('bad:1',100,600);invalid.delivery={status={},holder='Bad-Realm'}
assert(not A:MergeHistorySyncRecords({award('valid-but-atomic:1',100,601),invalid}))
assert(#SanguineLootCouncilDB.history==500 and SanguineLootCouncilDB.history[1].key=='new:1')
A:HistorySyncPacket('Moon-Realm',{kind='historySync',schema=1,op='data',token='unsolicited',records={fresh}})
assert(not A.historySync)
''')
print('500-record capacity, stale revisions, atomic malformed-data rejection and unsolicited data guards pass.')

# A peer that stops responding must never be reported as successfully synced.
interrupted={name:peer(name,names[:2]) for name in names[:2]}
interrupted[names[1]].execute("SanguineLootCouncilDB.history={award('interrupted:1',100,500)}")
assert interrupted[names[0]].globals().A.StartHistorySync(interrupted[names[0]].globals().A)
run(interrupted,limit=1500,drop=lambda sender,recipient,packet: sender==names[1])
assert 'unavailable' in interrupted[names[0]].globals().A.historySyncMessage
print('Unresponsive peers are reported as unavailable, not successful.')

for p in SRC.glob('*.lua'): lua.execute('assert(loadstring(...))',p.read_text())
print('All addon source parses under Lua 5.1.')

# Full-size group, two raid histories and one absent member. Shared manifests
# should be requested once per distinct history, not from all twenty peers.
large_names=['Zergul-Realm','Moon-Realm']+['Raider%d-Realm'%i for i in range(18)]
large={name:peer(name,large_names) for name in large_names}
for index,(name,member) in enumerate(large.items()):
    member.globals().side='a' if index<10 else 'b'
    if index==19: continue
    member.execute('''
for i=1,80 do SanguineLootCouncilDB.history[i]=award('shared-raid:'..i,1000+i,i) end
for i=1,3 do SanguineLootCouncilDB.history[#SanguineLootCouncilDB.history+1]=award('split-'..side..':'..i,2000+i,100+i) end
''')
large['Zergul-Realm'].execute("assert(A:StartHistorySync())")
end=run(large,limit=5000)
for member in large.values():
    member.execute("assert(#SanguineLootCouncilDB.history==86);assert(A.historySyncMessage:find('19 member(s) updated',1,true))")
print('20-member split-raid reconciliation and absent member catch-up pass through real throttled transport in %d simulated seconds.'%end)

# A richly audited correction must travel from a non-leader in >8 fragments;
# unrelated oversized packets from that same peer remain rejected.
rich={name:peer(name,names[:2]) for name in names[:2]}
rich[names[1]].execute('''
math.randomseed(333)
for i=1,10 do
 local r=award('rich:'..i,3000+i,200+i,'Moon-Realm',11)
 for j=1,10 do
  local chars={};for k=1,155 do chars[k]=string.char(math.random(65,122)) end
  r.corrections[j]={revision=j+1,from='Zergul-Realm',to='Moon-Realm',by='Zergul-Realm',time=200,reason=table.concat(chars)}
 end
 SanguineLootCouncilDB.history[i]=r
end
''')
rich[names[0]].execute('assert(A:StartHistorySync())')
run(rich,limit=3000)
for member in rich.values(): member.execute('assert(#SanguineLootCouncilDB.history==10 and #SanguineLootCouncilDB.history[1].corrections==10)')
assert rich[names[0]].globals().A.networkMetrics.receivedFragments>8
print('Large non-leader history transfers preserve complete correction audits.')

# An interrupted transfer after the handshake reports incomplete and keeps all
# records that were already present/received. A later retry can merge safely.
partial={name:peer(name,names[:2]) for name in names[:2]}
partial[names[0]].execute("SanguineLootCouncilDB.history={award('before-sync:1',100,1000)}")
partial[names[1]].execute("for i=1,100 do SanguineLootCouncilDB.history[i]=award('partial:'..i,200+i,i) end")
partial[names[0]].execute('assert(A:StartHistorySync())')
run(partial,limit=1500,drop=lambda sender,recipient,packet: sender==names[1] and partial[sender].globals().now>20)
assert 'incomplete' in partial[names[0]].globals().A.historySyncMessage
partial[names[0]].execute("local found=false;for _,r in ipairs(SanguineLootCouncilDB.history) do if r.key=='before-sync:1' then found=true end end;assert(found)")
partial[names[1]].execute('assert(#SanguineLootCouncilDB.history>=100)')
print('Mid-transfer loss produces an incomplete result while retaining saved records.')

# Participating in History sync must not permit unrelated oversized requests.
guarded=peer('Zergul-Realm',names[:2])
guarded.execute('''
assert(A:StartHistorySync())
A.historySync.ready['Moon-Realm']='1-2'
function A:HostRequest() error('oversized non-History packet escaped its transport guard') end
local payload=A.Encode({protocol=A.protocol,kind='request',data={op='respond',padding=string.rep('x',9000)}})
local count=math.ceil(#payload/180)
assert(count>8)
for i=1,count do
 A:Receive('SanguineLC','111-222-1:'..i..':'..count..':'..payload:sub((i-1)*180+1,i*180),'WHISPER','Moon-Realm')
end
assert(A.networkMetrics.decodedPackets==1)
''')
print('History transport exceptions do not relax unrelated request limits.')

# Combat pauses outgoing traffic and collection; resume does not classify peers
# as missing simply because the combat period consumed the discovery window.
paused={name:peer(name,names[:2]) for name in names[:2]}
paused[names[1]].execute("SanguineLootCouncilDB.history={award('combat:1',100,100)}")
paused[names[0]].execute('assert(A:StartHistorySync())')
for member in paused.values():
    member.execute('combat=true;now=300;A:TickHistorySync();A:PumpSender();assert(#outbox==0);combat=false')
run(paused,start=301,limit=1500)
for member in paused.values(): member.execute('assert(#SanguineLootCouncilDB.history==1)')
print('Combat pause and resume preserve discovery and eventual synchronization.')

# A local delete selection must not race a locally or remotely initiated sync.
locked=peer('Zergul-Realm',names[:2])
locked.execute('''
assert(A:BeginHistoryDeletion())
assert(not A:StartHistorySync() and not A.historySync)
A:HistorySyncPacket('Moon-Realm',{kind='historySync',schema=1,op='hello',token='delete-mode-race'})
assert(not A.historySync and A.historyDeleteMode)
A:CancelHistoryDeletion()
assert(A:StartHistorySync())
assert(not A:BeginHistoryDeletion() and not A.historyDeleteMode)
''')
print('History deletion and local/remote sync initiation cannot overlap.')
