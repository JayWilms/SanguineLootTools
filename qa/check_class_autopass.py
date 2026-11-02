from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'

def setup(ready=True):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('A={};SlashCmdList={};function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end')
    for name in ['Core','Features','Archive','Awards','Voting','ResponseConfig','Responses','Items','Equipment','StateDelta','WireCodec','Network','CouncilUI']:
        lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.globals().ready=ready
    lua.execute('''
now=100000
classes={player=1,raid2=8,raid4=3}
db={PROFICIENCY={armorCap={[1]=4,[8]=1,[3]=3}}}
function db:IsReady() return ready end
function db:HasItem(id) return id==12345 end
function db:GetInfo() return 'Restricted helm',4,4,4,'INVTYPE_HEAD',60,60 end
function db:GetItemType() return 'Plate' end
function db:CanUse(id,class,level) return class~=8 end
function LibStub() return db end
A.Client={}
function A.Client:Invoke(fn,...) if type(fn)~='function' then return false end;return pcall(fn,...) end
function A.Client:Call(name,unit)
    if name=='UnitClass' then return true,'Class','CLASS',classes[unit] end
    if name=='UnitLevel' then return true,60 end
    error('Unexpected native call: '..name)
end
function A.Client:ServerTime() return now end
function A.Client:ClockReady() return true end
function A.Client:Combat() return false end
function A:SyncGameMaster() end
function A:Record() end
function A:Changed() changed=(changed or 0)+1 end
function A:Publish(p) published=p.op;publishes=(publishes or 0)+1 end
function A:Print(message) lastMessage=message end
A.me='Leader-Realm';A.leader=A.me;A.rev=0
A.roster={[A.me]='player',['Mage-Realm']='raid2',['Unknown-Realm']='raid3'}
A.state={id='session',leader=A.me,master=A.me,responseDuration=120,rules=A:DefaultVoting(),
 responseOptions=A:DefaultResponses(),council={[A.me]=true},items={}}
item={id=1,link='|cffa335ee|Hitem:12345::::|h[Restricted helm]|h|r',status='queued',responses={},ballots={},round=1,ballotVersion=0}
A.state.items={item}
A:StartResponses(item)
''')
    return lua

lua=setup()
lua.execute('''
local response=item.responses['Mage-Realm']
assert(response and response.choice==6 and response.autoPass and response.revision==1)
assert(A:VotingResponseLabel(item,response)=='Auto Pass')
assert(A:VotingResponseLabel(item,{choice=6})=='Pass')
assert(not item.responses[A.me] and not item.responses['Unknown-Realm'])
assert(A:ClassEligibility(item,'Unknown-Realm')=='Unknown')
assert(A:RefreshClassAutoPasses(item,false)==0)
A:FinishResponses(item,'timer')
assert(not item.noResponse['Mage-Realm'])
assert(item.noResponse[A.me] and item.noResponse['Unknown-Realm'])
assert(not A:CanAwardCandidate(item,'Mage-Realm'))
assert(not A:ReduceVoting(A.me,{op='vote',choices={['Mage-Realm']=true}},item))
local decoded=A.Decode(A:WireEncode({responses=item.responses,noResponse=item.noResponse,protocol=A.protocol}))
assert(decoded.responses['Mage-Realm'].autoPass and decoded.responses['Mage-Realm'].choice==6)
assert(not decoded.noResponse['Mage-Realm'])
''')
print('Confirmed class restriction becomes Auto Pass; unknown players still wait; voting/awarding blocked; marker replicates.')

lua=setup(False)
lua.execute('''
assert(not next(item.responses))
ready=true
assert(not A:Reduce('Mage-Realm',{op='classAutoPass',sid=A.state.id}))
assert(not item.responses['Mage-Realm'])
A:TickResponses()
assert(item.responses['Mage-Realm'].autoPass and published=='classAutoPass' and A.rev==1)
local oldPublishes=publishes
A:TickResponses();assert(publishes==oldPublishes)
''')
print('Late database readiness adds one leader-authorized update without repeat traffic.')

lua=setup(False)
lua.execute('''
item.responses['Mage-Realm']={choice=6,note='Manual pass',revision=1}
ready=true
A:RefreshClassAutoPasses(item,true)
assert(item.responses['Mage-Realm'].note=='Manual pass' and not item.responses['Mage-Realm'].autoPass)
assert(A:VotingResponseLabel(item,item.responses['Mage-Realm'])=='Pass')
''')
print('Explicit player responses are preserved and remain distinguishable from Auto Pass.')

lua=setup(False)
lua.execute('''
A:FinishResponses(item,'timer');assert(item.noResponse['Mage-Realm'])
ready=true;A:TickResponses()
assert(item.responses['Mage-Realm'].autoPass and not item.noResponse['Mage-Realm'])
classes.raid2=1
A:TickResponses()
assert(not item.responses['Mage-Realm'] and item.noResponse['Mage-Realm'])
''')
print('Closed unawarded rounds resolve late restriction data without reopening the response timer.')

lua=setup()
lua.execute('''
classes.raid2=1
A:TickResponses();assert(not item.responses['Mage-Realm'])
classes.raid2=8;A:TickResponses();assert(item.responses['Mage-Realm'].autoPass)
ready=false;A:TickResponses();assert(item.responses['Mage-Realm'].autoPass)
ready=true;classes.raid2=1;A:TickResponses();assert(not item.responses['Mage-Realm'])
classes.raid4=8;A.roster['NewMage-Realm']='raid4'
A:TrackResponseMembers();assert(item.responses['NewMage-Realm'].autoPass)
A:StartResponses(item);assert(item.responses['NewMage-Realm'].autoPass and item.responses['NewMage-Realm'].revision==1)
item.status='awarded';item.winner=A.me
local version=item.ballotVersion
classes.raid4=1
assert(A:RefreshClassAutoPasses(item,true)==0 and item.ballotVersion==version)
''')
print('Eligibility changes, transient unknown data, new members, rerolls and immutable awarded rounds passed.')

for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Class auto-pass and Lua 5.1 checks passed. No installer generated.')
