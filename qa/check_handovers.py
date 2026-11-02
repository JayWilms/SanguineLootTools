from pathlib import Path
import ast
import sys
sys.path.insert(0,str(Path(__file__).parent/'test-deps'))
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'
tree=ast.parse((ROOT/'qa/check_pickups.py').read_text(encoding='utf-8'))
constants={t.id:ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and isinstance(n.value,ast.Constant) and isinstance(n.value.value,str) for t in n.targets if isinstance(t,ast.Name)}

def setup():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(constants['MOCK'])
    for name in ['Core','Features','Archive','Equipment','ResponseConfig','Voting','LootConfiguration','Loot','WireCodec','StateDelta','Network']:
        lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.execute(constants['SETUP'])
    lua.execute('''
source='Holder-Realm';recipient='Recipient-Realm';winner='Winner-Realm'
A.roster[recipient]='raid2';A.roster[winner]='raid3'
entry={id=1,guid='Item-Tracked-Bracers',link=bagLink,quality=3,holder=source,kind='unbound',observedAt=wall,
 verifiedHolder=true,deliveryRevision=0,deliveryLog={}}
A.state.trackedLoot={entry}
seq={}
function report(sender,kind,guid,link)
    seq[sender]=(seq[sender] or 0)+1
    return A:ReduceLoot(sender,{op='lootReport',seq=seq[sender],sampledAt=wall,
        entries={{guid=guid or entry.guid,link=link or bagLink,kind=kind,quality=3}}})
end
function award(target,status)
    item={id=5,link=bagLink,lootGUID=entry.guid,status='awarded',winner=target,awardRevision=1}
    entry.item=5;entry.delivery=status or 'pending'
    A.state.items={item}
end
''')
    return lua

for order in ['recipient_first','old_holder_first']:
    lua=setup()
    lua.execute('''
local first='''+repr(order)+'''
if first=='recipient_first' then
    assert(report(recipient,'unbound'));assert(entry.holder==source)
    assert(report(source,'missing'))
else
    assert(report(source,'missing'));assert(entry.holder==source and entry.kind=='missing')
    assert(report(recipient,'unbound'))
end
assert(entry.holder==recipient and entry.kind=='unbound' and entry.verifiedHolder)
assert(#A.state.trackedLoot==1 and #A.state.items==0)
assert(entry.deliveryRevision==1 and A.lootHandoverCount==1)
assert(entry.lastHandover.from==source and entry.lastHandover.to==recipient)
local time,label=A:TradeRemaining(entry)
assert(time==nil and label=='Unbound — no BoP timer')
assert(report(source,'missing'));assert(entry.holder==recipient and entry.kind=='unbound')
''')
    print(order+': one tracked copy; holder and timer status synchronized; late old absence ignored')

lua=setup()
lua.execute('''
assert(report(recipient,'unbound'));assert(entry.holder==source)
wall=wall+91
assert(report(source,'missing'));assert(entry.holder==source)
''')
print('Uncorroborated/expired claims cannot move ownership.')

lua=setup()
lua.execute('''
assert(report(source,'missing'))
assert(report(recipient,'unbound','Item-Different-Copy'))
assert(#A.state.trackedLoot==2 and entry.holder==source)
local ok=report(recipient,'unbound',entry.guid,bagLink:gsub('8299','12345'))
assert(not ok and entry.holder==source)
''')
print('Identical item links with different GUIDs stay separate; mismatched base items rejected.')

lua=setup()
lua.execute('''
award(winner)
assert(report(recipient,'unbound'));assert(report(source,'missing'))
assert(entry.holder==recipient and item.winner==winner and entry.delivery=='pending')
assert(item.delivery.holder==recipient and item.delivery.status=='pending')
''')
print('Courier handover updates physical holder without changing the award winner.')

lua=setup()
lua.execute('''
award(recipient)
assert(report(recipient,'unbound'));assert(report(source,'missing'))
assert(entry.delivery=='delivered' and entry.deliveryMethod=='bag_handover')
assert(item.winner==recipient and item.delivery.holder==recipient and item.delivery.status=='delivered')
-- A simultaneously queued native completion receipt is idempotent.
assert(A:ReduceLoot(source,{op='tradeReceipt',tracked=1,guid=entry.guid,token='100000:123456:1',
 expectedRevision=0,expectedAwardRevision=1,expectedWinner=recipient,completedAt=wall}))
assert(entry.deliveryRevision==1 and #entry.deliveryLog==1)
-- Return the item after delivery: award stays intact, actual holder changes,
-- and the item reappears for delivery review rather than remaining hidden.
wall=wall+1
assert(report(source,'unbound'));assert(report(recipient,'missing'))
assert(entry.holder==source and entry.delivery=='review' and item.winner==recipient)
assert(item.delivery.holder==source and item.delivery.status=='review')
''')
print('Delivery to winner, racing completion receipt, and return-to-holder review passed.')

lua=setup()
lua.execute('''
award(recipient)
assert(A:ReduceLoot(source,{op='tradeReceipt',tracked=1,guid=entry.guid,token='100000:123456:2',
 expectedRevision=0,expectedAwardRevision=1,expectedWinner=recipient,completedAt=wall}))
assert(entry.holder==recipient and entry.delivery=='delivered')
assert(report(recipient,'unbound'));assert(report(source,'missing'))
assert(entry.holder==recipient and entry.kind=='unbound' and entry.deliveryRevision==1)
''')
print('Native completion arriving first also preserves the new holder.')

# Exercise actual scanning of a physically present tracked copy whose recorded
# holder is someone else. It must report promptly even if the kind is unchanged.
lua=setup()
lua.execute('''
A.me=recipient
bags[1]={guid=entry.guid,link=bagLink}
A:ScanLoot()
assert(A.lootHolderClaims[entry.guid].sender==recipient and entry.holder==source)
local sent=reports
now=now+2;A:ScanLoot();assert(reports==sent)
now=now+10;A:ScanLoot();assert(reports==sent+1)
assert(report(source,'missing'))
assert(entry.holder==recipient)
''')
print('Recipient bag scans report the existing GUID and bound retry frequency.')

lua=setup()
lua.execute('''
local snapshot=A.Copy(A.state)
assert(report(recipient,'unbound'));assert(report(source,'missing'))
local edits=A:StateChanges(snapshot,A.state)
local packet=A:WireEncode({edits=edits,protocol=A.protocol})
local decoded=A.Decode(packet)
local replica=A:ApplyStateChanges(snapshot,decoded.edits)
assert(replica.trackedLoot[1].holder==recipient and replica.trackedLoot[1].kind=='unbound')
assert(#A:StateChanges(replica,A.state)==0)
''')
print('Handover state survives actual wire codec and delta replication.')
for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Holder handover and Lua 5.1 checks passed. No installer generated.')
