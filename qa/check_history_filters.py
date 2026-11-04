from pathlib import Path
from lupa import LuaRuntime
root=Path(__file__).resolve().parent.parent
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('A={}; date=function(_,t) return t==1 and "04/11/2026" or "03/11/2026" end; SanguineLootCouncilDB={history={ {key="a",winner="Zergul-Realm",time=1,item="|cffa335ee|Hitem:123:0|h[Brutality Blade]|h|r"}, {key="b",winner="Moon-Realm",time=2,item="|Hitem:456:0|h[Other Blade]|h"}, {key="c",winner="Zergul-Realm",time=2,item="|Hitem:456:9|h[Other Blade]|h"} }}')
lua.execute((root/'SanguineLootTools/History.lua').read_text(),'SanguineLootTools',lua.globals().A)
lua.execute('''
assert(#A:FilterHistoryRecords(nil,'')==3)
assert(#A:FilterHistoryRecords(nil,' zErGuL ')==2)
assert(#A:FilterHistoryRecords(nil,'04/11/2026')==1)
assert(#A:FilterHistoryRecords(nil,'31/02/2026')==0)
assert(#A:FilterHistoryRecords(nil,'blade')==3)
assert(#A:FilterHistoryRecords(nil,'Brutality')==1)
assert(#A:FilterHistoryRecords(nil,'|Hitem:456:999|h[Other Blade]|h')==2)
assert(#A:FilterHistoryRecords('Zergul-Realm','Other')==1)
assert(#A:FilterHistoryRecords('Moon-Realm','04/11/2026')==0)
assert(#A:FilterHistoryRecords(nil,'%')==0)
local box={value='',HasFocus=function() return true end,GetText=function(s) return s.value end,SetText=function(s,v) s.value=v end,SetCursorPosition=function(s,v) s.cursor=v end}
A.ui={history={IsShown=function() return true end},historySearch=box}
assert(A:CaptureHistoryLink('|Hitem:123:0|h[Brutality Blade]|h'))
assert(box.value:find('item:123',1,true))
assert(not A:CaptureHistoryLink('|Hspell:123|h[Spell]|h'))
box.HasFocus=function() return false end
assert(not A:CaptureHistoryLink('item:456'))
assert(#SanguineLootCouncilDB.history==3)
''')
for p in (root/'SanguineLootTools').glob('*.lua'):
    lua.execute('assert(load(...))',p.read_text())
print('History search, exact linked item IDs, dates, personal rewards, focus guards and Lua syntax pass.')

# Retained greens are pruned before the capacity limit is enforced. Unknown
# quality stays intact; a cold-cache standard green link is still removable.
lua.execute((root/'SanguineLootTools/Awards.lua').read_text(),'SanguineLootTools',lua.globals().A)
lua.execute('''
A.Copy=function(v) return v end
A.InitStorage=function() A:PruneGreenHistory() end
A.AwardSnapshot=function(_,item) return {winner=item.winner,time=item.id} end
A.state={id='session',master='Master-Realm'}
SanguineLootCouncilDB.history={
 {key='old-green',item='|cff1eff00|Hitem:1|h[Green]|h|r'},
 {key='explicit-green',item='item:2',quality=2},
 {key='blue',item='item:3',quality=3},
 {key='unknown',item='item:4'} }
A:PruneGreenHistory()
assert(#SanguineLootCouncilDB.history==2)
for _,r in ipairs(SanguineLootCouncilDB.history) do assert(r.key=='blue' or r.key=='unknown') end
SanguineLootCouncilDB.history={}
for i=1,500 do SanguineLootCouncilDB.history[i]={key='blue:'..i,item='item:3',quality=3,time=i} end
A:UpsertAward({id=501,link='item:2',quality=2,winner='Zergul-Realm'})
assert(#SanguineLootCouncilDB.history==500 and SanguineLootCouncilDB.history[1].key=='blue:1')
A.TrackedForItem=function() return {quality=2} end
A:UpsertAward({id=502,link='item:2',winner='Moon-Realm'})
assert(#SanguineLootCouncilDB.history==500)
A.TrackedForItem=nil
A:UpsertAward({id=503,link='item:3',quality=3,winner='Moon-Realm'})
assert(#SanguineLootCouncilDB.history==500 and SanguineLootCouncilDB.history[1].key=='session:503')
assert(SanguineLootCouncilDB.history[1].quality==3)
''')
print('Existing greens removed; new greens preserve all 500 slots; blue awards retain normal capacity behavior.')
