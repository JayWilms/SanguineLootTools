from pathlib import Path
import ast
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parent.parent
tree=ast.parse((root/'qa/check_reason_dropdown.py').read_text(encoding='utf-8'))
frames=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign)
            and any(isinstance(t,ast.Name) and t.id=='FRAMES' for t in n.targets))
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(frames)
lua.execute('''
SlashCmdList={}
local create=CreateFrame
function CreateFrame(kind,name,parent,...)
    local f=create(kind,name,parent,...)
    function f:SetWidth(w) self.width=w end
    function f:SetHeight(h) self.height=h end
    function f:CreateTexture() return CreateFrame('Texture',nil,self) end
    function f:SetScrollChild(child) self.child=child end
    function f:GetVerticalScrollRange() return math.max(0,(self.child and self.child.height or 0)-self.height) end
    function f:GetVerticalScroll() return self.offset or 0 end
    function f:SetVerticalScroll(value) self.offset=value end
    return f
end
''')
for name in ['UI','LootUI']:
    lua.execute((root/'SanguineLootTools'/f'{name}.lua').read_text(encoding='utf-8'),
                'SanguineLootTools',lua.globals().A)
lua.execute('''
local timerMode="Full"
function A:LootWindowLayout() return timerMode end
function A:StyleRailArrow() end
function A:StyleDataRow() end
function A:WarningSettings() return {early=600,urgent=120} end
function A:ItemIcon(entry) return entry.id end
function A:FitTimerItemName(link) return link end
function A:TradeRemaining(entry) return 1000,'~0:16:40' end
function A:LootHolderInfo(name) return name end
local function window(name,title,w,h)
    local f=CreateFrame('Frame',name,UIParent);f:SetSize(w,h);return f
end
local function text(parent,value)
    local f=CreateFrame('FontString',nil,parent);f:SetText(value);return f
end
A.ui={}
A:BuildLootTimerUI(A.ui,window,text,function() error('Timer still uses page buttons') end)
local p=A.ui.lootTimers
assert(p.itemHeader.parent==p.window and p.rows[80].parent==p.child)
assert(not p.previous and not p.next)
A.state={id='raid',trackedLoot={}}
for i=80,1,-1 do A.state.trackedLoot[#A.state.trackedLoot+1]={id=i,link='item:'..i,holder='Holder'} end
A:RenderLootTimers()
assert(p.rows[1].tracked==1 and p.rows[80].tracked==80 and p.rows[80]:IsShown())
assert(p.scroll:GetVerticalScroll()==0 and p.scroll.sltScrollChrome.rail:IsShown())
p.scroll.scripts.OnMouseWheel(p.scroll,-1)
assert(p.scroll:GetVerticalScroll()==36)
p.scroll.sltScrollChrome.down:Click();assert(p.scroll:GetVerticalScroll()==72)
local maximum=p.scroll:GetVerticalScrollRange()
p.scroll.sltScrollChrome.slider:SetValue(maximum)
assert(p.scroll:GetVerticalScroll()==maximum)
A:RenderLootTimers();assert(p.scroll:GetVerticalScroll()==maximum,'countdown refresh reset scroll')
p.window:SetSize(760,460);A:LayoutLootTimer()
assert(p.scroll:GetVerticalScroll()==p.scroll:GetVerticalScrollRange())
-- Removal of delivered items clamps the bottom position and hides old rows.
for i=1,78 do A.state.trackedLoot[i].delivery='delivered' end
A:RenderLootTimers()
assert(p.count==2 and p.rows[1].tracked==1 and p.rows[2].tracked==2)
assert(not p.rows[3]:IsShown() and p.scroll:GetVerticalScroll()==0)
assert(not p.scroll.sltScrollChrome.rail:IsShown())
A.state.trackedLoot={};A:RenderLootTimers()
assert(p.empty:IsShown() and not p.rows[1]:IsShown())
A.state={id='next',trackedLoot={}}
for i=1,20 do A.state.trackedLoot[i]={id=i,link='item:'..i,holder='Holder'} end
p.scroll:SetVerticalScroll(100)
A:RenderLootTimers();assert(p.scroll:GetVerticalScroll()==0)
p.window:SetSize(440,220);A:LayoutLootTimer()
assert(p.rows[1].holder:GetWidth()>=40 and p.rows[1].caption:GetWidth()>=90)

p.scroll:SetVerticalScroll(88)
timerMode='Compact';p.window:SetSize(380,250);A:LayoutLootTimer()
assert(not p.holderHeader:IsShown() and not p.rows[1].holder:IsShown() and not p.rows[1].holderStatus:IsShown())
assert(p.rowStride==32 and p.rows[1]:GetHeight()==30 and p.scroll:GetVerticalScroll()==64)
A:RenderLootTimers()
assert(p.rows[1].caption:GetText()=='item:1' and p.rows[1].countdown:GetText()=='~0:16:40')
assert(p.scroll:GetVerticalScroll()==64 and not p.rows[1].holder:IsShown())
timerMode='Full';p.window:SetSize(600,320);A:LayoutLootTimer();A:RenderLootTimers()
assert(p.holderHeader:IsShown() and p.rows[1].holder:IsShown() and p.rows[1].holder:GetText()=='Holder')
assert(p.rowStride==44 and p.scroll:GetVerticalScroll()==88)
''')
print('Timer scroll: 80 items, wheel/arrows/slider, refresh preservation, resize, delivery removal, empty and session reset passed.')
