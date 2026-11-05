from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent/'test-deps'))
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'

def setup():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('A={}')
    for name in ['Core','Features','Archive','Voting','ResponseConfig','Responses','Items','Loot','Warnings','RaiderUI']:
        lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.execute('''
A.Client={Combat=function() return false end,ServerTime=function() return 100000 end}
A.me='Master-Realm';A.leader=A.me;A.roster={[A.me]='player',['Winner-Realm']='raid2'}
A.state={id='raid-session',master=A.me,items={},trackedLoot={},responseDuration=120,
 responseOptions=A:DefaultResponses(),rules=A:DefaultVoting(),council={[A.me]=true}}
function A:ClassEligibility() return 'Eligible','' end
function A:ItemDetails() return {} end
function A:SeedSoloTestResponses() end
function A:Print(message) lastMessage=message end
function A:Act(op,p) p.op=op;return self:ReduceLoot(self.me,p) end
link='|cff0070dd|Hitem:18722::::::::60::::|h[Death Grips]|h|r'
entry={id=1,guid='Item-Completed-Copy',link=link,holder=A.me,item=10,delivery='delivered',deliveredTo='Winner-Realm'}
completed={id=10,lootGUID=entry.guid,link=link,status='awarded',winner='Winner-Realm',
 responseRound=1,responseDeadline=99900,responses={['Winner-Realm']={choice=1}},ballots={},voting='closed'}
A.state.items={completed};A.state.trackedLoot={entry}
''')
    return lua

for name,change in [
    ('completed delivery',''),
    ('missing forward pointer','entry.item=nil'),
    ('only reverse item identity survives',"entry.item=nil;entry.delivery=nil;entry.deliveredTo=nil"),
    ('only delivery evidence survives','entry.item=nil;A.state.items={}'),
    ('archived copy',"entry.item=nil;entry.delivery=nil;entry.deliveredTo=nil;A.state.items={};A.state.retiredGUIDs={[entry.guid]=true}"),
]:
    lua=setup();lua.execute(change)
    lua.execute('''
local count=#A.state.items
assert(not A:CanQueueTrackedLoot(entry))
assert(not A:QueueTrackedLoot(1))
assert(not A:QueueTrackedLoot())
assert(not A:ReduceLoot(A.me,{op='queueLoot',tracked=1,release=true}))
assert(not A:ReduceLoot(A.me,{op='queueLoot',entries={{tracked=1,guid=entry.guid}},release=true}))
assert(#A.state.items==count and completed.status=='awarded' and completed.responseRound==1)
''')
    print(name+': Queue, Queue All and direct requests cannot reopen the copy')

lua=setup()
lua.execute('''
entry.item=nil
fresh={id=2,guid='Item-Genuinely-New-Copy',link=link,holder=A.me}
A.state.trackedLoot[#A.state.trackedLoot+1]=fresh
assert(A:QueueTrackedLoot())
assert(#A.state.items==2 and completed.status=='awarded' and completed.responseRound==1)
assert(fresh.item~=nil and A.state.items[2].status=='open')
local rows=A:ResponseItems()
assert(#rows==1 and rows[1].item.lootGUID==fresh.guid)
assert(A.state.items[2].responseDuration==120)
-- A closed, unawarded response remains available for review.
A.state.items[2].status='closed'
rows=A:ResponseItems();assert(#rows==1)
''')
print('Fresh identical item with a different GUID queues normally; awarded copy stays out of the response list.')

lua=setup()
lua.execute('''
A.state.items={};entry.item=nil;entry.delivery=nil;entry.deliveredTo=nil
duplicate=A.Copy(entry);duplicate.id=2
A.state.trackedLoot={entry,duplicate}
-- Explicit duplicate GUIDs are rejected atomically before starting any round.
assert(not A:ReduceLoot(A.me,{op='queueLoot',release=true,entries={{tracked=1,guid=entry.guid},{tracked=2,guid=entry.guid}}}))
assert(#A.state.items==0 and not entry.item and not duplicate.item)
-- Queue All's client selection deduplicates the physical identity.
assert(A:QueueTrackedLoot())
assert(#A.state.items==1)
assert(not A:CanQueueTrackedLoot(duplicate))
assert(not A:QueueTrackedLoot(2))
''')
print('Duplicate tracking rows cannot create two rounds for one physical copy.')

lua=setup()
lua.execute('''
fresh={id=2,guid='Item-Fresh-Two',link=link,holder=A.me}
A.state.trackedLoot[#A.state.trackedLoot+1]=fresh
local ok=A:ReduceLoot(A.me,{op='queueLoot',release=true,entries={{tracked=2,guid=fresh.guid},{tracked=1,guid=entry.guid}}})
assert(not ok and not fresh.item and #A.state.items==1)
''')
print('Mixed stale batches reject before creating partial rounds.')
for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Queue completion and response-list checks passed. No installer generated.')
