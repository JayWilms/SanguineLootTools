from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent/'test-deps'))
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'

FRAMES=r'''
A={confirmationDialogs={}}
local methods={}
local mt={__index=function(f,key)
    if methods[key] then return methods[key] end
    if key:match('^Set') or key:match('^Get') or key:match('^Clear') or key:match('^Enable') or key:match('^Register') then return function() end end
end}
function CreateFrame(kind,name,parent)
    local f=setmetatable({kind=kind,parent=parent,children={},scripts={},shown=true,enabled=true,width=250,height=30,text='',level=parent and parent.level+1 or 0,strata=parent and parent.strata or 'MEDIUM',mouse=kind=='Button'},mt)
    if parent then parent.children[#parent.children+1]=f end
    return f
end
function methods:SetParent(parent)
    if self.parent then for i,c in ipairs(self.parent.children) do if c==self then table.remove(self.parent.children,i);break end end end
    self.parent=parent;parent.children[#parent.children+1]=self
end
function methods:GetChildren() return unpack(self.children) end
function methods:GetRegions() end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetScript(name,fn) self.scripts[name]=fn end
function methods:HookScript(name,fn)
    local previous=self.scripts[name]
    self.scripts[name]=function(...) if previous then previous(...) end;fn(...) end
end
function methods:Show() self.shown=true end
function methods:Hide()
    local was=self.shown;self.shown=false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:IsVisible() local parent=rawget(self,'parent');return self.shown and (not parent or parent:IsVisible()) end
function methods:IsEnabled() return self.enabled end
function methods:SetEnabled(enabled) self.enabled=enabled end
function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function methods:SetFrameLevel(level) self.level=math.max(0,math.min(10000,level)) end
function methods:SetFrameStrata(strata) self.strata=strata end
function methods:EnableMouse(enabled) self.mouse=enabled end
function methods:SetMinMaxValues(minimum,maximum) self.minimum,self.maximum=minimum,maximum end
function methods:SetValue(value)
    local changed=self.value~=value;self.value=value
    if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end
end
function methods:GetThumbTexture() return CreateFrame('Texture',nil,self) end
function methods:SetText(text) self.text=text end
function methods:GetText() return self.text end
function methods:GetFontString()
    if not self.fontstring then self.fontstring=CreateFrame('FontString',nil,self) end
    return self.fontstring
end
function methods:SetFontString(fontstring) self.fontstring=fontstring end
function methods:CreateFontString() return CreateFrame('FontString',nil,self) end
function methods:GetHighlightTexture() return CreateFrame('Texture',nil,self) end
function methods:Click() assert(self.scripts.OnClick);self.scripts.OnClick(self) end
-- A direct OnClick call bypasses the native hit test. Check which dropdown
-- layer receives input before dispatching a simulated option click.
function ClickDropdownRow(row)
    local menu=A.ui.settingsDropdown
    local dismiss=A.ui.settingsDropdownDismiss
    assert(row:IsVisible() and row.mouse and row:IsEnabled())
    assert(row.strata==menu.strata and menu.strata==dismiss.strata)
    assert(menu.level>dismiss.level,'outside-click catcher covers dropdown')
    assert(row.level>menu.level,'dropdown background covers option')
    row:Click()
end
UIParent=CreateFrame('Frame')
SanguineLootCouncilDB={raidSetupRevision=0}
'''
BUILD=r'''
function A:StylePanel() end
function A:StyleRailArrow() end
function A:CreateScrollFrame(parent) return CreateFrame('ScrollFrame',nil,parent) end
function A:CanConfigureRaid() return true end
function A:Print(message) error(message) end
function A:Act(op,p)
    assert(op=='lootConfiguration')
    SanguineLootCouncilDB.lootConfiguration=p.settings
    SanguineLootCouncilDB.raidSetupRevision=SanguineLootCouncilDB.raidSetupRevision+1
    return true
end
function A:SetupMemberName(name) return name end
local function window(name,title,w,h)
    local f=CreateFrame('Frame',name,UIParent);f:SetSize(w,h);f:Hide();return f
end
local function button(parent,label,x,y,w,fn)
    local f=CreateFrame('Button',nil,parent);f:SetText(label);f:SetScript('OnClick',fn);return f
end
local function text(parent,label) local f=CreateFrame('FontString',nil,parent);f:SetText(label);return f end
local function edit(parent) return CreateFrame('EditBox',nil,parent) end
local function dropdown(control,choices,action)
    control:SetScript('OnClick',function() A:OpenSettingsDropdown(control,type(choices)=='function' and choices() or choices,action) end)
end
A.roster={};A.ui={settingsHub=CreateFrame('Frame',nil,UIParent),settingsPages={['Loot Configuration']={content=CreateFrame('Frame',nil,UIParent)}},lootPanels={timer={auto=CreateFrame('Button',nil,UIParent)}}}
A:BuildLootConfigurationUI(A.ui,window,text,button,edit,dropdown,function() end,nil,function() end,function() end)
A.ui.settingsHub.sltBody=CreateFrame('Frame',nil,A.ui.settingsHub)
A.ui.settingsHub.sltHeader=CreateFrame('Frame',nil,A.ui.settingsHub)
A.ui.settingsHub.sltBody:Hide()
'''

def setup(old=False):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FRAMES)
    g=lua.globals()
    for name in ['Features','LootConfiguration','WindowLayouts','SettingsUI','LootConfigurationUI']:
        path=ROOT/f'qa/fixtures/{name}-alpha37.lua' if old and name in ('SettingsUI','LootConfigurationUI') else SRC/f'{name}.lua'
        lua.execute(path.read_text(encoding='utf-8'),'SanguineLootTools',g.A)
    lua.execute(BUILD)
    return lua

for old in [True,False]:
    lua=setup(old)
    lua.execute('''
A:OpenLootReason(4)
A.ui.lootReasonPreset:Click()
A:CaptureWindowBody(A.ui.settingsHub)
''')
    visible=lua.eval('A.ui.settingsDropdown:IsVisible()')
    assert visible is (not old)
    print(('alpha.37' if old else 'fixed')+': reason menu visible with collapsed Settings = '+str(visible))

lua=setup()
for i,label,stored in [(1,'Disenchanted','Disenchant'),(2,'Guild Bank','Guild Bank'),(3,'Other','Other')]:
    lua.execute('A:OpenLootReason(4);A.ui.lootReasonPreset:Click();A:CaptureWindowBody(A.ui.settingsHub)')
    assert lua.eval(f'A.ui.settingsDropdown.rows[{i}].label:GetText()')==label
    lua.execute(f'ClickDropdownRow(A.ui.settingsDropdown.rows[{i}])')
    assert lua.eval('A.ui.lootReasonPreset:GetText()')==label
    lua.execute("A.ui.lootReasonRecipient:SetText('Hozfir-WildGrowth');A.ui.lootReasonNote:SetText('Raid test');A.ui.lootReasonSave:Click()")
    assert lua.eval('SanguineLootCouncilDB.lootConfiguration.rules[4].reason')==stored
    assert lua.eval('SanguineLootCouncilDB.lootConfiguration.rules[4].target')=='Hozfir-WildGrowth'
    assert lua.eval('SanguineLootCouncilDB.lootConfiguration.rules[4].note')=='Raid test'
    lua.execute('A:OpenLootReason(4)')
    assert lua.eval('A.ui.lootReasonPreset:GetText()')==label
    print(label+': selected, saved and reopened; recipient/note preserved')

# Hidden/disabled owners must not accept stale row clicks. Outside dismissal
# and dialog close must remove both the menu and its full-screen click catcher.
lua.execute('''
A.ui.lootReasonPreset:Click()
A.ui.settingsDropdownDismiss.scripts.OnMouseUp()
assert(not A.ui.settingsDropdown:IsShown() and not A.ui.settingsDropdownDismiss:IsShown())
A.ui.lootReasonPreset:Click()
A.ui.lootReason:Hide()
assert(not A.ui.settingsDropdown:IsShown() and not A.ui.settingsDropdownDismiss:IsShown())
local before=A.ui.lootReasonChoice
A.ui.settingsDropdown.rows[1]:Click()
assert(A.ui.lootReasonChoice==before)
A:OpenLootReason(4);A.ui.lootReasonPreset.enabled=false;A.ui.lootReasonPreset:Click()
assert(not A.ui.settingsDropdown:IsShown())
''')
for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Dropdown lifecycle, persisted reasons and Lua 5.1 compilation checks passed.')

# Exercise the actual quality and recipient callbacks repeatedly, including
# changing an action back after saving. These are the controls in the report.
lua=setup()
lua.execute('''
function A:SetSettingsToggle() end
function A:LayoutLootConfiguration() end
for _,selection in ipairs({3,1,2,3,2,1,3}) do
    A:RenderLootConfigurationUI()
    local row=A.ui.lootQualityRows[4]
    assert(row.action:IsEnabled())
    row.action:Click()
    local menu=A.ui.settingsDropdown
    local values={'ignore','council','assign'}
    for i=1,3 do
        local b=menu.rows[i]
        assert(b.parent==menu and b.mouse and b:IsVisible())
        assert(b.strata==menu.strata and b.level>menu.level)
        assert(menu.level>A.ui.settingsDropdownDismiss.level)
    end
    ClickDropdownRow(menu.rows[selection])
    assert(A:LootConfiguration().rules[4].action==values[selection])
    assert(not menu:IsShown() and not A.ui.settingsDropdownDismiss:IsShown())
    A:RenderLootConfigurationUI()
    assert(row.recipient:IsEnabled()==(selection==3))
    assert(row.reason:IsEnabled()==(selection==3))
end
-- A forty-member roster must remain selectable via wheel, arrows and slider.
for i=1,40 do A.roster['Player'..i..'-Realm']=true end
local recipient=A.ui.lootQualityRows[4].recipient
recipient:Click()
local menu=A.ui.settingsDropdown
assert(#menu.choices==42 and menu.slider:IsVisible())
assert(menu.slider.level>menu.level and menu.down.level>menu.level and menu.up.level>menu.level)
assert(menu.slider.level<=10000 and menu.down.level<=10000 and menu.up.level<=10000)
menu.down:Click();assert(menu.offset==1)
menu.rows[3].scripts.OnMouseWheel(menu.rows[3],-1);assert(menu.offset==2)
menu.slider:SetValue(34);assert(menu.offset==34)
local target=menu.choices[menu.offset+7][2]
ClickDropdownRow(menu.rows[7])
assert(A:LootConfiguration().rules[4].target==target)
recipient:Click();assert(menu.offset==0)
menu.rows[1]:Click();assert(A:LootConfiguration().rules[4].target=='@master')
-- Switching menu lengths must clear old rows and scroll state. False-valued
-- voting options must survive selection rather than becoming nil/true.
local owner=CreateFrame('Button',nil,UIParent)
local picked='unset'
for cycle=1,3 do
    A:OpenSettingsDropdown(owner,{{'Totals only',false},{'Show voter names',true}},function(v) picked=v end)
    assert(not menu.slider:IsShown() and not menu.rows[3]:IsShown())
    menu.rows[2]:Click();assert(picked==true)
    A:OpenSettingsDropdown(owner,{{'Totals only',false},{'Show voter names',true}},function(v) picked=v end)
    menu.rows[1]:Click();assert(picked==false)
end
''')
print('Repeated action changes, conditional recipient controls, 42-choice scrolling, direct mouse layers and boolean selections passed.')

# Operational notices must survive removal of the redundant status sentence
# and retirement of the minimum-quality selector.
lua=setup()
lua.execute('''
function A:SetSettingsToggle() end
function A:LayoutLootConfiguration() end
A.Client={ServerTime=function() return 1000 end}
A:RenderLootConfigurationUI()
assert(A.ui.lootMinimum==nil,'retired threshold selector remains')
assert(not A.ui.lootRoutingStatus:IsShown())
A.lootRoutingStatus='Native Master Loot APIs unavailable'
A:RenderLootConfigurationUI()
assert(A.ui.lootRoutingStatus:IsShown() and A.ui.lootRoutingStatus:GetText()==A.lootRoutingStatus)
A.lootRoutingStatus=nil
A.state={corpseRoutes={{time=995}}}
A:RenderLootConfigurationUI()
assert(A.ui.lootRoutingStatus:IsShown() and A.ui.lootRoutingStatus:GetText():find('1 awaiting verification',1,true))
A.state.corpseRoutes[1].failed=true
A:RenderLootConfigurationUI()
assert(A.ui.lootRoutingStatus:GetText():find('1 unresolved',1,true))
A.state=nil;A.demo=true
A:RenderLootConfigurationUI()
assert(A.ui.lootRoutingStatus:IsShown() and A.ui.lootRoutingStatus:GetText():find('Test mode:',1,true))
A.demo=nil
A:RenderLootConfigurationUI()
assert(not A.ui.lootRoutingStatus:IsShown())
''')
print('Retired threshold stays absent; routing warnings, progress and test-mode notices remain visible.')
