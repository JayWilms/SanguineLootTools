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
A.Client={InGroup=function() return false end}
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
assert(A.ui.masterMemberPicker:IsEnabled() and not A.ui.masterMemberPicker.dropdownArrow:IsEnabled())
assert(not A.ui.councilMemberPicker:IsEnabled())
assert(A.ui.councilName:IsEnabled())
A:RefreshRaidMemberPickers()
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
addRoster();A:RefreshRaidMemberPickers()
A.ui.masterMemberPicker.dropdownArrow:Click();local menu=A.ui.settingsDropdown
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
A.state={id='live',council={},items={}}
A.leader='Other-Realm';menu.rows[1]:Click()
assert(A.ui.councilName:GetText()=='KeepCouncil-Realm')
A:RefreshRaidMemberPickers();A:RefreshSettingsDropdowns()
assert(not A.ui.masterMemberPicker:IsEnabled() and not A.ui.councilMemberPicker:IsEnabled())
assert(not A.ui.masterName:IsEnabled() and not A.ui.councilName:IsEnabled())
-- Active ballots lock council changes. The existing group-test exception remains.
A.leader=A.me;A.state.items={{status='open',voting='open'}}
A:RefreshRaidMemberPickers();assert(not A.ui.councilMemberPicker:IsEnabled())
A.state.groupTest=true;A:RefreshRaidMemberPickers();assert(A.ui.councilMemberPicker:IsEnabled())
A.state.groupTest=nil;A.state.items={};A.state.masterSource='game'
A:RefreshRaidMemberPickers();assert(A.ui.masterMemberPicker:IsEnabled())
A.state.masterSource='pending';A.state.masterBlocked=true
assert(not A:RaidMemberPickerEditable('master'))
A.state.masterBlocked=false;A.state.masterSource='unavailable'
assert(A:RaidMemberPickerEditable('master'))
assert(not A:RaidMemberPickerEditable('invalid'))
''')
print('Roster churn, stale clicks, unrelated menus, lost permissions, active ballots, shared tests and master-role synchronization passed.')

# Council row controls apply immediately and use one atomic change for replacement.
lua=setup()
lua.execute('''
addRoster()
A.ui.settingsHub=CreateFrame('Frame',nil,UIParent);A.ui.settingsHub:SetSize(1000,720)
A.ui.councilSettingsContent=parent;A.ui.councilRulesPositions={{y=680,councilBaseY=680}}
local function button(owner,label,x,y,width,callback)
 local b=CreateFrame('Button',nil,owner);b:SetText(label);b:SetScript('OnClick',callback);return b
end
local function text(owner,label) local t=CreateFrame('FontString',nil,owner);t:SetText(label);return t end
local function dropdown(control,choices,callback) A:BindSettingsDropdown(control,choices,callback,button) end
function A:RenderSettings() self:RenderCouncilMemberRows();self:RefreshSettingsDropdowns() end
A:BuildCouncilMemberRows(parent,button,text,dropdown);A:RenderSettings()
function chooseCouncilRow(index,name)
 local row=A.ui.councilRows[index]
 row.memberPicker.dropdownArrow:Click()
 local menu=A.ui.settingsDropdown
 for i,choice in ipairs(menu.choices) do
  if choice[2]==name then A:ScrollSettingsDropdown(i-1);ClickDropdownRow(menu.rows[i-menu.offset]);return end
 end
 error('Missing council choice '..name)
end
assert(A.ui.councilRowsShown==1 and not A.ui.councilRows[1].remove:IsEnabled())
chooseCouncilRow(1,'Same-Alpha')
assert(A:RaidSettings().council['Same-Alpha'])
assert(A.ui.councilRows[1].member=='Same-Alpha' and A.ui.councilRows[1].remove:IsEnabled())
A.ui.addCouncilMember:Click();assert(A.ui.councilRowsShown==2)
chooseCouncilRow(2,'Same-Beta')
assert(A:RaidSettings().council['Same-Alpha'] and A:RaidSettings().council['Same-Beta'])
-- Duplicate selection must not remove either existing member.
chooseCouncilRow(1,'Same-Beta')
assert(A:RaidSettings().council['Same-Alpha'] and A:RaidSettings().council['Same-Beta'])
chooseCouncilRow(1,'Player40-Realm')
assert(not A:RaidSettings().council['Same-Alpha'] and A:RaidSettings().council['Player40-Realm'])
A.ui.councilRows[1].remove:Click()
assert(not A:RaidSettings().council['Player40-Realm'] and A:RaidSettings().council['Same-Beta'])
-- Saved absent members can still be removed from their own row.
assert(A:Act('council',{target='Absent-Realm',enabled=true}));A:RenderSettings()
assert(A.ui.councilRows[1].member=='Absent-Realm')
assert(A.ui.councilRows[1].memberPicker:GetText():find('(Not in group)',1,true))
A.ui.councilRows[1].remove:Click();assert(not A:RaidSettings().council['Absent-Realm'])
A.ui.addCouncilMember:Click();A.ui.councilRows[2].remove:Click()
assert(A.ui.councilRowsShown==1 and A.ui.councilMemberDraft==nil)
-- Permission and active-ballot checks apply to every row.
A.state={id='live',council={['Same-Beta']=true},items={}}
A.leader='Other-Realm';A:RenderSettings()
assert(not A.ui.councilRows[1].memberPicker:IsEnabled() and not A.ui.councilRows[1].remove:IsEnabled())
A.ui.councilRows[1].remove:Click();assert(A.state.council['Same-Beta'])
A.leader=A.me;A.state.items={{status='open',voting='open'}};A:RenderSettings()
assert(not A.ui.councilRows[1].remove:IsEnabled())
''')
print('Council row selection, add/remove, atomic replacement, duplicate rejection, absent members and permission locks passed.')

lua=setup()
lua.execute('''
addRoster();A.leader=A.me
A.Client={ClockReady=function() return true end}
A.state={id='live',council={['Same-Alpha']=true,['Absent-Realm']=true},items={}}
assert(A:Reduce(A.me,{op='council',sid='live',target='Same-Beta',previous='Same-Alpha',enabled=true}))
assert(not A.state.council['Same-Alpha'] and A.state.council['Same-Beta'])
assert(A:Reduce(A.me,{op='council',sid='live',target='Absent-Realm',enabled=false}))
assert(not A.state.council['Absent-Realm'])
local ok=A:Reduce(A.me,{op='council',sid='live',target='Player40-Realm',previous='Same-Alpha',enabled=true})
assert(not ok and not A.state.council['Player40-Realm'],'stale replacement added an extra member')
assert(not A:Reduce('Same-Beta',{op='council',sid='live',target='Player40-Realm',enabled=true}))
A.state.items={{status='open',voting='open'}}
assert(not A:Reduce(A.me,{op='council',sid='live',target='Player40-Realm',previous='Same-Beta',enabled=true}))
assert(A.state.council['Same-Beta'] and not A.state.council['Player40-Realm'])
local full={}
for i=1,40 do full['Member'..i..'-Realm']=true end
assert(not A:ApplyCouncilMemberChange(full,'New-Realm',{enabled=true}))
assert(A:ApplyCouncilMemberChange(full,'New-Realm',{enabled=true,previous='Member1-Realm'}))
assert(not full['Member1-Realm'] and full['New-Realm'])
assert(A:ApplyCouncilMemberChange(full,'New-Realm',{enabled=true}))
assert(A:ApplyCouncilMemberChange(full,'New-Realm',{enabled=false}))
assert(A:ApplyCouncilMemberChange(full,'New-Realm',{enabled=false}))
''')
print('Live council reducer, stale replacements, absent-member removal, idempotent actions and full-council replacement passed.')

lua=setup()
lua.execute('''
local field=A.ui.masterName
assert(A.ui.masterMemberPicker==field and field.kind=='EditBox')
assert(field.placeholder:IsShown())
A:RefreshRaidMemberPickers();A:RefreshSettingsDropdowns()
assert(field:IsEnabled() and not field.dropdownArrow:IsEnabled(),'solo typing must remain available without an empty roster menu')
field:SetText('Typed-Realm');field.scripts.OnTextChanged(field)
assert(not field.placeholder:IsShown())
assert(A:RaidSettings().master~='Typed-Realm','typing applied without Assign')
field:SetText('');field.scripts.OnTextChanged(field)
assert(field.placeholder:IsShown())
addRoster();A:RefreshRaidMemberPickers();A:RefreshSettingsDropdowns()
assert(field.dropdownArrow:IsEnabled())
choose('master','Same-Beta');field.scripts.OnTextChanged(field)
assert(field:GetText()=='Same-Beta' and not field.placeholder:IsShown())
assert(A:RaidSettings().master~='Same-Beta','dropdown selection applied without Assign')
assert(A:Act('master',{target=field:GetText()}))
assert(A:RaidSettings().master=='Same-Beta')
A:RefreshRaidMemberPickers();A:RefreshSettingsDropdowns()
assert(field:IsEnabled() and field.dropdownArrow:IsEnabled())
''')
print('Single editable Master Looter field, placeholder visibility, solo typing, roster arrow and explicit Assign passed.')
