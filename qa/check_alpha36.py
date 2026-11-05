from pathlib import Path
import json
import sys
sys.path.insert(0, str(Path(__file__).parent / 'test-deps'))
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'SanguineLootTools'

MOCK = r'''
now, allowance, allowanceAt, failures, sent = 0, serverTokens, 0, 0, {}
Enum={SendAddonMessageResult={Success=0,AddonMessageThrottle=3,ChannelThrottle=8,AddOnMessageLockdown=11}}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
A={}
'''
CLIENT = r'''
A.Client={}
function A.Client:Combat() return false end
function A.Client:InGroup() return true end
function A.Client:InRaid() return players>5 end
function A.Client:Uptime() return now end
function A.Client:ServerTime() return 100000+math.floor(now) end
function A.Client:Invoke() return false end
function A.Client:Call(name,prefix,message,channel,target)
    if name=='C_Item.GetItemInfo' or name=='UnitClass' then return false end
    assert(name=='C_ChatInfo.SendAddonMessage')
    allowance=math.min(10,allowance+math.max(0,now-allowanceAt)*serverRate);allowanceAt=now
    if now<blockedUntil or allowance+0.000001<1 then failures=failures+1;return true,3 end
    allowance=allowance-1
    sent[#sent+1]={at=now,message=message,target=target}
    return true,0
end
function A:EquipmentLink(link) return link end
function A:RenderNetworkStatus() end
function A:Print(message) error(message) end
function A:Record() end
function A:Changed() end
function A:ClearPendingPersonalResponse() end
function A:RequestSync() error('Unexpected revision gap') end
function A:Render() end
function A:WarningPacket() return false end
function A:FeaturePacket() return false end
function A:BuildUI() end
'''
FIXTURE = r'''
A.me,A.leader,A.demo,A.groupTest='Leader-Realm','Leader-Realm',true,true
A.roster={['Leader-Realm']='player'}
for i=2,players do A.roster['Player'..i..'-Realm']='party'..i end
A.state={id='100000:123456:test:1',groupTest=true,leader=A.leader,master=A.me,
 council={[A.me]=true},selfVotes=false,rules=A:DefaultVoting(),responseOptions=A:DefaultResponses(),
 responseDuration=120,items={},trackedLoot={},lootSequences={},responseConfigRevision=0,
 masterAutoSync=false,autoCollect=false}
A.rev=1
A:SeedTestLoot()
baseline=A:PublicState()
local entries={}
for _,entry in ipairs(A.state.trackedLoot) do entries[#entries+1]={tracked=entry.id,guid=entry.guid} end
assert(A:ReduceLoot(A.me,{op='queueLoot',entries=entries,release=true}))
A.rev=2
current=A:PublicState()
edits=A:StateChanges(baseline,current)
rawPacket={kind='stateDelta',protocol=A.protocol,sid=current.id,baseRev=1,rev=2,edits=edits}
rawBytes=#A:WireEncode(rawPacket)
'''

def setup(old=False, players=5, tokens=10, rate=1, blocked=0):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.players, g.serverTokens, g.serverRate, g.blockedUntil = players, tokens, rate, blocked
    lua.execute(MOCK)
    for name in ['Core','Features','Archive','Voting','ResponseConfig','Responses','Items','Loot','WireCodec','StateDelta','Network']:
        file = ROOT / f'qa/fixtures/{name}-alpha35.lua' if old and name in ('Network','StateDelta') else SRC / f'{name}.lua'
        lua.execute(file.read_text(encoding='utf-8'), 'SanguineLootTools', g.A)
    lua.execute(CLIENT)
    lua.execute(FIXTURE)
    return lua

def transfer(old=False, players=5, tokens=10, rate=1, blocked=0, coalesce=False):
    lua=setup(old,players,tokens,rate,blocked)
    g=lua.globals()
    if not old:
        lua.execute('''
packed,templates,releases=A:CompactStateChanges(edits,baseline)
assert(#templates==1, 'Expected shared round template')
assert(#A:StateChanges(A:ApplyStateChanges(baseline,packed,templates,releases),current)==0)
-- Encode/decode really used by recipients, including compression and dictionary.
wire=A:WireEncode({kind='stateDelta',protocol=A.protocol,sid=current.id,baseRev=1,rev=2,edits=packed,templates=templates,releases=releases})
roundTrip=A.Decode(wire)
assert(#A:StateChanges(A:ApplyStateChanges(baseline,roundTrip.edits,roundTrip.templates,roundTrip.releases),current)==0)
-- A missing tracked copy or malformed reference must not partially mutate state.
bad='1,999,1,1,1'
assert(A:ApplyStateChanges(baseline,packed,templates,bad)==nil)
assert(#baseline.items==0 and not baseline.trackedLoot[1].item)
''')
    lua.execute("A.publicBaseline=baseline; A:Publish({op='queueLoot'})")
    if coalesce:
        lua.execute('''
older=current
A.state.items[1].responses['Player2-Realm']={choice=1,note='Changed while queued',revision=1}
current=A:PublicState();A.rev=3
assert(A:Send({kind='stateDelta',protocol=A.protocol,sid=current.id,baseRev=2,rev=3,edits=A:StateChanges(older,current)},nil,
 {key='delta:'..current.id,baseState=older,nextState=current,liveResponse=true}))
''')
    initial=lua.eval('select(1,A:NetworkQueueStats())')
    if isinstance(initial,tuple): initial=initial[0]
    complete=None
    for step in range(12001):
        g.now=step/100
        lua.execute('A:PumpSender()')
        q=lua.eval('select(1,A:NetworkQueueStats())')
        if isinstance(q,tuple): q=q[0]
        if not q: complete=g.now;break
    assert complete is not None,'transfer stalled'
    messages=[row.message for row in g.sent.values()]
    parts={}
    expected=None
    for message in messages:
        assert len(message)<=255
        _,index,count,chunk=message.split(':',3)
        index,count=int(index),int(count)
        assert index not in parts,'duplicate fragment'
        parts[index]=chunk;expected=count
    assert len(parts)==expected,'missing fragment'
    packet=lua.eval('A.Decode')(''.join(parts[i] for i in range(1,expected+1)))
    g.receivedPacket=packet
    lua.execute('''
local updated=A:ApplyStateChanges(baseline,receivedPacket.edits,receivedPacket.templates,receivedPacket.releases)
assert(updated and #A:StateChanges(updated,current)==0,'recipient state diverged')
-- Exercise the real recipient packet handler, not only the delta helper.
A.me='Player2-Realm';A.state=A.Copy(baseline);A.rev=1
A:Packet(A.leader,receivedPacket)
assert(A.rev==receivedPacket.rev and #A:StateChanges(A.state,current)==0)
assert(A.state.items[1].responseDuration==120)
''')
    return {'fragments':initial,'seconds':complete,'throttles':g.failures,'raw_bytes':g.rawBytes,
            'payload_bytes':len(''.join(parts.values()))}

results={}
for n in [2,5,40]:
    results[f'alpha35_{n}_players']=transfer(True,n)
    results[f'alpha36_{n}_players']=transfer(False,n)
    assert results[f'alpha36_{n}_players']['fragments'] < results[f'alpha35_{n}_players']['fragments']
    assert results[f'alpha36_{n}_players']['throttles']==0
results['exhausted_allowance']=transfer(tokens=0)
results['server_half_per_second']=transfer(tokens=0,rate=0.5)
results['temporary_block']=transfer(tokens=0,blocked=5)
results['coalesced_response']=transfer(coalesce=True)
assert results['server_half_per_second']['throttles']<5

# Recovery and topology changes must preserve exact state, even if references
# cannot use the compact tracked-item linkage shortcut.
lua=setup()
lua.execute('''
current.trackedLoot[1],current.trackedLoot[2]=current.trackedLoot[2],current.trackedLoot[1]
local p,t,r=A:CompactStateChanges(A:StateChanges(baseline,current),baseline)
assert(#A:StateChanges(A:ApplyStateChanges(baseline,p,t,r),current)==0)
for _,bad in ipairs({'',';1,1,1,1,1','1,1,1,1,1;','1,1,1,1,1;;2,2,2,1,1','x,1,1,1,1','1,0,1,1,1','1,1,1,999,1','1,1,1,1,1;1,1,1,1,1'}) do
    assert(A:ApplyStateChanges(baseline,{},t,bad)==nil)
end
local noCopies=A.Copy(baseline);noCopies.trackedLoot={}
local p,t,r=A:CompactStateChanges(A:StateChanges(noCopies,current),noCopies)
assert(r==nil and #A:StateChanges(A:ApplyStateChanges(noCopies,p,t,r),current)==0)
''')

# Simulate repeated batches within one login. Resetting disposable test state
# must not invent fresh burst tokens or erase native pacing after each batch.
lua=setup()
g=lua.globals()
lua.execute('''
function A:WireEncode(packet) return packet.payload end
''')
step=0
for cycle in range(5):
    lua.execute("A:ResetTestTransport();assert(A:Send({kind='test',payload=string.rep('x',900)}))")
    while step<20000:
        g.now=step/100;step+=1
        lua.execute('A:PumpSender()')
        q=lua.eval('select(1,A:NetworkQueueStats())')
        if isinstance(q,tuple): q=q[0]
        if not q: break
    else: raise AssertionError('repeated batch stalled')
assert g.failures==0 and len(g.sent)==25
results['five_consecutive_batches']={'sent':len(g.sent),'throttles':g.failures,'seconds':g.now}

# A queued private report must not block a new release. If another public
# baseline is required, its packets still have to precede that release.
lua=setup()
lua.execute('''
A:Send({kind='privateVotingBatch',data={}},'Player2-Realm')
A.publicBaseline=baseline
A:Publish({op='queueLoot'})
A:PumpSender()
assert(sent[1].target==nil,'private data overtook public release')
''')
for file in SRC.glob('*.lua'):
    lua=LuaRuntime()
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
report=json.dumps(results,indent=2)
(ROOT/'work/alpha36-checks.json').write_text(report,encoding='utf-8')
print(report)
print('Real queue release, codec, recipient, coalescing, token-bucket and Lua 5.1 checks passed.')
