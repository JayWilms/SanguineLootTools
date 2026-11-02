from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent/'test-deps'))
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'

def setup():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('A={};combat=false;inRange=true;tradeCalls=0;bagGUID="Item-Fresh-Helm"')
    for name in ['Core','Features','Archive','Awards','Equipment','Loot','Trade','CouncilUI']:
        lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.execute(r'''
A.Client={}
function A.Client:Invoke(fn,...) if type(fn)~='function' then return false end;return pcall(fn,...) end
function A.Client:Combat() return combat end
function A.Client:Uptime() return 100 end
function A.Client:ServerTime() return 100000 end
function GetCursorInfo() end
function UnitIsConnected() return true end
function CheckInteractDistance() return inRange end
function InitiateTrade(unit) tradeCalls=tradeCalls+1;tradeUnit=unit end
NUM_BAG_SLOTS=0
ItemLocation={CreateFromBagAndSlot=function(self,bag,slot) return {bag=bag,slot=slot} end}
C_Item={GetItemGUID=function() return bagGUID end,IsBound=function() return false end}
link="|cff1eff00|Hitem:8299::::::::60:::::::::|h[Traveler's Helm]|h|r"
C_Container={GetContainerNumSlots=function() return 1 end,
 GetContainerItemInfo=function() return {hyperlink=link,stackCount=1,isLocked=false} end}
function A:Print(message) lastMessage=message end
function A:ReviewAward(target) reviewed=target end
A.me='Zergulx-WildGrowth';A.leader=A.me
A.roster={[A.me]='player',['Hozfir-WildGrowth']='raid2',['Other-WildGrowth']='raid3'}
item={id=1,link=link,lootGUID='Item-Fresh-Helm',status='awarded',winner='Hozfir-WildGrowth',awardRevision=1,
 voting='closed',responses={['Hozfir-WildGrowth']={choice=1,revision=1}}}
entry={id=11,item=1,link=link,guid=item.lootGUID,holder=A.me,bagAdded=true,kind='unbound',delivery='pending',deliveryRevision=1}
A.state={id='raid-session',master=A.me,items={item},trackedLoot={entry}}
A.selectedItem=1
''')
    return lua

lua=setup()
lua.execute('''
local label,enabled,tracked=A:CouncilAwardAction(item,item.winner)
assert(label=='Trade' and enabled and tracked==11)
assert(A:UseCouncilAwardAction(item.winner))
assert(tradeCalls==1 and tradeUnit=='raid2')
assert(A.tradeIntent.guid==entry.guid and A.tradeIntent.target==item.winner)
assert(item.status=='awarded' and item.winner=='Hozfir-WildGrowth')
''')
print('Verified manually added BoE: winner action is Trade; real trade path selects the correct GUID and recipient.')

for name,change,label in [
    ('delivered',"entry.delivery='delivered'",'Delivered'),
    ('unverified legacy placeholder','entry.manual=true','Awarded'),
    ('different holder',"entry.holder='Other-WildGrowth'",'Trade'),
    ('winner already holds item','item.winner=A.me','Already held'),
    ('test mode','A.demo=true','Awarded'),
    ('missing tracked copy','A.state.trackedLoot={}','Awarded'),
    ('different candidate',"candidate='Other-WildGrowth'",'Award'),
]:
    lua=setup()
    lua.execute("candidate=item.winner;"+change)
    if name!='different candidate':
        lua.execute('candidate=item.winner')
    lua.execute(f"local text,enabled=A:CouncilAwardAction(item,candidate);assert(text=='{label}' and not enabled);assert(not A:UseCouncilAwardAction(candidate));assert(tradeCalls==0)")
    print(name+': no trade or duplicate award initiated')

for name,change in [('out of range','inRange=false'),('combat','combat=true'),('bag copy changed',"bagGUID='Item-Different-Copy'")]:
    lua=setup()
    lua.execute(change)
    lua.execute('assert(not A:UseCouncilAwardAction(item.winner));assert(tradeCalls==0 and lastMessage)')
    print(name+': existing trade validation blocks initiation')

lua=setup()
lua.execute('''
item.status='closed';item.winner=nil;item.voting='open'
local label,enabled,tracked=A:CouncilAwardAction(item,'Hozfir-WildGrowth')
assert(label=='Award' and enabled and not tracked)
assert(A:UseCouncilAwardAction('Hozfir-WildGrowth'))
assert(reviewed=='Hozfir-WildGrowth' and tradeCalls==0)
''')
print('Unawarded candidate: original award-review action retained.')
for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Voting trade-action and Lua 5.1 compilation checks passed. No installer generated.')
