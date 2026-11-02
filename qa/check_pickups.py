from pathlib import Path
import json
import sys
sys.path.insert(0,str(Path(__file__).parent/'test-deps'))
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'

MOCK=r'''
now,wall,bags,received,reports=100,100000,{}, {},0
LOOT_ITEM_SELF='You receive loot: %s.'
LOOT_ITEM_SELF_MULTIPLE='You receive loot: %sx%d.'
LOOT_ITEM_PUSHED_SELF='You receive item: %s.'
LOOT_ITEM_PUSHED_SELF_MULTIPLE='You receive item: %sx%d.'
NUM_BAG_SLOTS=0
ItemLocation={CreateFromBagAndSlot=function(self,bag,slot) return {bag=bag,slot=slot} end}
C_Container={GetContainerNumSlots=function() return 8 end,
 GetContainerItemInfo=function(bag,slot)
    local item=bags[slot]
    if item then return {hyperlink=item.link,stackCount=1,quality=2,isLocked=false} end
 end}
C_Item={GetItemGUID=function(location) return bags[location.slot] and bags[location.slot].guid end,
 IsBound=function() return false end}
function UnitIsConnected() return true end
A={}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
'''
SETUP=r'''
A.Client={}
function A.Client:Invoke(fn,...) if type(fn)~='function' then return false end;return pcall(fn,...) end
function A.Client:Uptime() return now end
function A.Client:ServerTime() return wall end
function A.Client:InRaid() return true end
function A.Client:Combat() return false end
A.me='Holder-Realm';A.leader=A.me;A.roster={[A.me]='player'}
A.state={id='real-raid-session',leader=A.me,master=A.me,items={},trackedLoot={},autoCollect=true,
 council={[A.me]=true},lootConfiguration=A:DefaultLootConfiguration()}
A.state.lootConfiguration.minimum=2
A.PruneActiveCaches=nil;A.PersistSession=nil;A.Render=nil
function A:Act(op,p)
    reports=reports+1
    p.op=op
    local ok,err=self:ReduceLoot(self.me,p)
    assert(ok,err)
end
chatLink='|cff1eff00|Hitem:8299::::::::0:::::::::|h[Traveler\'s Helm]|h|r'
bagLink='|cff1eff00|Hitem:8299::::::::60:::::::::|h[Traveler\'s Helm]|h|r'
'''

def setup(old=False):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    g=lua.globals()
    for name in ['Core','Features','Archive','Equipment','ResponseConfig','Voting','LootConfiguration','Loot','WireCodec','StateDelta','Network']:
        path=ROOT/f'qa/fixtures/{name}-alpha36.lua' if old and name in ('Core','Loot') else SRC/f'{name}.lua'
        lua.execute(path.read_text(encoding='utf-8'),'SanguineLootTools',g.A)
    lua.execute(SETUP)
    return lua

results={}
for old in [True,False]:
    lua=setup(old)
    lua.execute('''
bags[1]={guid='Item-Old-Helm',link=bagLink}
A:Changed();A:ScanLoot()
bags[2]={guid='Item-New-Helm',link=bagLink}
A:LootEvent('CHAT_MSG_LOOT',string.format(LOOT_ITEM_SELF,chatLink))
A:ScanLoot()
''')
    count=lua.eval('#A.state.trackedLoot')
    results['alpha36_mismatched_links' if old else 'fixed_mismatched_links']=count
    assert count==(0 if old else 1)
    if not old:
        lua.execute('''
assert(A.state.trackedLoot[1].guid=='Item-New-Helm')
assert(A.state.trackedLoot[1].kind=='unbound')
local time,label=A:TradeRemaining(A.state.trackedLoot[1])
assert(time==nil and label=='Unbound — no BoP timer')
-- Repeated scans/duplicate reports must not add the same physical copy again.
for i=1,3 do now=now+2;wall=wall+2;A:ScanLoot() end
assert(#A.state.trackedLoot==1)
''')

lua=setup()
lua.execute('''
A:Changed()
bags[1]={guid='Item-Early-Bag',link=bagLink}
A:ScanLoot();assert(#A.state.trackedLoot==0)
now=now+2
A:LootEvent('CHAT_MSG_LOOT',string.format(LOOT_ITEM_SELF,chatLink))
A:ScanLoot();assert(#A.state.trackedLoot==1)
''')
results['bag_event_before_chat']='passed'

lua=setup()
lua.execute('''
A:Changed()
A:LootEvent('CHAT_MSG_LOOT',string.format(LOOT_ITEM_SELF,chatLink))
A:ScanLoot();assert(#A.state.trackedLoot==0)
now=now+2;bags[1]={guid='Item-Late-Bag',link=bagLink}
A:ScanLoot();assert(#A.state.trackedLoot==1)
''')
results['chat_before_bag']='passed'

for format_name in ['LOOT_ITEM_SELF_MULTIPLE','LOOT_ITEM_PUSHED_SELF_MULTIPLE']:
    lua=setup()
    lua.execute(f'''
A:Changed()
for i=1,3 do bags[i]={{guid='Item-Multi-'..i,link=bagLink}} end
A:LootEvent('CHAT_MSG_LOOT',string.format({format_name},chatLink,2))
A:ScanLoot();assert(#A.state.trackedLoot==2)
''')
    results[format_name]='passed'

for name,alter,message,wait in [
 ('existing_bag_item',"bags[1]={guid='Item-Old-Helm',link=bagLink};A:Changed()",True,0),
 ('someone_elses_loot','A:Changed()',False,0),
 ('expired_pickup','A:Changed()',True,31),
 ('disabled_collection','A:Changed();A.state.autoCollect=false',True,0),
 ('below_threshold','A:Changed();A.state.lootConfiguration.minimum=4',True,0),
 ('ignored_green','A:Changed();A.state.lootConfiguration.rules[3].action="ignore"',True,0),
 ('test_mode','A:Changed();A.demo=true',True,0),
 ('outside_raid','A:Changed();function A.Client:InRaid() return false end',True,0),
]:
    lua=setup()
    lua.execute(alter)
    text="string.format(LOOT_ITEM_SELF,chatLink)" if message else "'Other-Realm receives loot: '..chatLink..'.'"
    lua.execute(f"A:LootEvent('CHAT_MSG_LOOT',{text});now=now+{wait}")
    if name!='existing_bag_item':
        lua.execute("bags[1]={guid='Item-New-Helm',link=bagLink}")
    lua.execute('A:ScanLoot();assert(#A.state.trackedLoot==0)')
    results[name]='passed'

for file in SRC.glob('*.lua'):
    lua=LuaRuntime()
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
report=json.dumps(results,indent=2)
(ROOT/'work/pickup-checks.json').write_text(report,encoding='utf-8')
print(report)
print('Pickup, holder report, unbound label and Lua 5.1 checks passed.')
