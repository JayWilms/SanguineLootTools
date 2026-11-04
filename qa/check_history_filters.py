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
