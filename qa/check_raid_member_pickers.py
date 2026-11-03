from pathlib import Path
import ast
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parent.parent
tree=ast.parse((root/'qa/check_reason_dropdown.py').read_text(encoding='utf-8'))
frames=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FRAMES' for t in n.targets))

def setup():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(frames+'\nSlashCmdList={}\n')
    for name in ['Core','Features','Voting','ResponseConfig','Responses','LootConfiguration','Warnings','SettingsUI']:
        lua.execute((root/'SanguineLootTools'/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.execute('''
function A:StylePanel() end
function A:StyleRailArrow() end
function A:RefreshRailArrow() end
function A:Changed() end
function A:Print(message) lastMessage=message end
A.me='Leader-Realm';A.leader=nil;A.roster={}
A:InitStorage()
parent=CreateFrame('Frame',nil,UIParent)
local function button(owner,label,x,y,width,callback)
    local b=CreateFrame('Button',nil,owner);b:SetText(label);b:SetScript('OnClick',callback);return b
end
local function dropdown(control,choices,callback) A:BindSettingsDropdown(control,choices,callback,button) end
A.ui={masterName=CreateFrame('EditBox',nil,parent),councilName=CreateFrame('EditBox',nil,parent)}
A:BuildRaidMemberPickers(parent,button,dropdown)
A:RefreshRaidMemberPickers();A:RefreshSettingsDropdowns()
function addRoster()
    A.roster={['Leader-Realm']='raid1',['Same-Alpha']='raid2',['Same-Beta']='raid3'}
    for i=4,40 do A.roster[string.format('Player%02d-Realm',i)]='raid'..i end
end
function choose(role,name)
    local control=role=='master' and A.ui.masterMemberPicker or A.ui.councilMemberPicker
    control.dropdownArrow:Click()
    local menu=A.ui.settingsDropdown
    for i,choice in ipairs(menu.choices) do
        if choice[2]==name then
            A:ScrollSettingsDropdown(i-1);ClickDropdownRow(menu.rows[i-menu.offset]);return
        end
    end
    error('Missing choice '..name)
end
''')
    return lua

lua=setup()
lua.execute('''
-- Solo: no empty dropdown, but manual setup still works.
assert(not A.ui.masterMemberPicker:IsEnabled() and not A.ui.councilMemberPicker:IsEnabled())
assert(A.ui.councilName:IsEnabled())
assert(A:Act('masterAutoSync',{}));A:RefreshRaidMemberPickers()
assert(A.ui.masterName:IsEnabled())
A.ui.masterName:SetText('FutureMaster-Realm');A.ui.councilName:SetText('FutureCouncil-Realm')
assert(A:Act('master',{target=A.ui.masterName:GetText()}))
assert(A:Act('council',{target=A.ui.councilName:GetText()}))
assert(A:RaidSettings().master=='FutureMaster-Realm')
assert(A:RaidSettings().council['FutureCouncil-Realm'])
-- Forty current members, scrolling, full realm disambiguation, and explicit apply.
addRoster();A:RefreshRaidMemberPickers();A:RefreshSettingsDropdowns()
assert(A.ui.masterMemberPicker:IsEnabled() and A.ui.councilMemberPicker.dropdownArrow:IsEnabled())
choose('master','Same-Beta')
assert(A.ui.masterName:GetText()=='Same-Beta')
assert(A.ui.councilName:GetText()=='FutureCouncil-Realm')
assert(A:RaidSettings().master=='FutureMaster-Realm','selection applied without Assign')
assert(A:Act('master',{target=A.ui.masterName:GetText()}))
assert(A:RaidSettings().master=='Same-Beta')
choose('council','Same-Alpha')
assert(not A:RaidSettings().council['Same-Alpha'],'selection changed membership')
assert(A:Act('council',{target=A.ui.councilName:GetText()}))
assert(A:RaidSettings().council['Same-Alpha'])
A.ui.councilMemberPicker:Click()
assert(#A.ui.settingsDropdown.choices==40)
local previous=''
for _,choice in ipairs(A.ui.settingsDropdown.choices) do
    assert(previous<choice[2]);previous=choice[2]
    if choice[2]=='Same-Alpha' then assert(choice[1]=='Same-Alpha (Council)') end
end
A:CloseSettingsDropdown();choose('council','Same-Alpha')
assert(A:Act('council',{target=A.ui.councilName:GetText()}))
assert(not A:RaidSettings().council['Same-Alpha'])
-- Manual edits survive all refreshes and dropdown selection on the other field.
A.ui.masterName:SetText('Typed-Realm');A:RefreshRaidMemberPickers()
choose('council','Player40-Realm');assert(A.ui.masterName:GetText()=='Typed-Realm')
''')
print('Solo manual setup, 40-member sorted dropdowns, scrolling, realm disambiguation, council labels, explicit apply and preserved drafts passed.')

lua=setup()
lua.execute('''
addRoster();A:Act('masterAutoSync',{});A:RefreshRaidMemberPickers()
A.ui.masterMemberPicker:Click();local menu=A.ui.settingsDropdown
-- Member leaves before a row click; stale option cannot replace typed input.
A.ui.masterName:SetText('Keep-Realm');A.roster[menu.choices[1][2]]=nil
menu.rows[1]:Click();assert(A.ui.masterName:GetText()=='Keep-Realm')
-- A roster refresh dismisses only these pickers, preserving unrelated menus.
A.ui.councilMemberPicker:Click();A.roster['New-Realm']='raid4'
A:RefreshRaidMemberPickers();assert(not menu:IsShown())
local unrelated=CreateFrame('Button',nil,parent)
A:OpenSettingsDropdown(unrelated,{{'Keep','keep'}},function() end)
A.roster['Another-Realm']='raid5';A:RefreshRaidMemberPickers();assert(menu:IsShown())
A:CloseSettingsDropdown()
-- Lost leader permissions between opening and clicking cannot change the draft.
A.ui.councilMemberPicker:Click();A.ui.councilName:SetText('KeepCouncil-Realm')
A.state={id='live',masterAutoSync=false,council={},items={}}
A.leader='Other-Realm';menu.rows[1]:Click()
assert(A.ui.councilName:GetText()=='KeepCouncil-Realm')
A:RefreshRaidMemberPickers();A:RefreshSettingsDropdowns()
assert(not A.ui.masterMemberPicker:IsEnabled() and not A.ui.councilMemberPicker:IsEnabled())
assert(not A.ui.masterName:IsEnabled() and not A.ui.councilName:IsEnabled())
-- Active ballots lock council changes. The existing group-test exception remains.
A.leader=A.me;A.state.items={{status='open',voting='open'}}
A:RefreshRaidMemberPickers();assert(not A.ui.councilMemberPicker:IsEnabled())
A.state.groupTest=true;A:RefreshRaidMemberPickers();assert(A.ui.councilMemberPicker:IsEnabled())
A.state.groupTest=nil;A.state.items={};A.state.masterAutoSync=true;A.state.masterSource='game'
A:RefreshRaidMemberPickers();assert(not A.ui.masterMemberPicker:IsEnabled())
A.state.masterSource='pending';A.state.masterBlocked=true
assert(not A:RaidMemberPickerEditable('master'))
A.state.masterBlocked=false;A.state.masterSource='unavailable'
assert(A:RaidMemberPickerEditable('master'))
assert(not A:RaidMemberPickerEditable('invalid'))
''')
print('Roster churn, stale clicks, unrelated menus, lost permissions, active ballots, shared tests and master-role synchronization passed.')
