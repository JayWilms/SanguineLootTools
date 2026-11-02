from pathlib import Path
import ast
import sys
sys.path.insert(0,str(Path(__file__).parent/'test-deps'))
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'
tree=ast.parse((ROOT/'qa/check_reason_dropdown.py').read_text(encoding='utf-8'))
FRAMES=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FRAMES' for t in n.targets))

def setup():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FRAMES+'\nSlashCmdList={}\n')
    for name in ['Core','Features','Archive','Awards','SettingsUI','UI']:
        lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.execute('''
A.Client={ServerTime=function() return 100000 end}
A.me='Zergulx-WildGrowth';A.leader=A.me
A.roster={[A.me]='player',['Hozfir-WildGrowth']='raid2',['Alpha-Realm']='raid3',['Charlie-Realm']='raid4',['Pass-Realm']='raid5',['NoResponse-Realm']='raid6'}
item={id=1,status='awarded',link='Recipe: Greater Fire Protection Potion',winner='Hozfir-WildGrowth',awardRevision=2,
 responses={['Alpha-Realm']={choice=1},['Charlie-Realm']={choice=2},['Pass-Realm']={choice=6},['Left-Realm']={choice=1}}}
A.state={id='raid-session',master=A.me,items={item}}
A.selectedItem=1;A.selectedCandidate='Charlie-Realm'
A.ui={}
function A:StyleRailArrow() end
function A:EligibilityText(item,target) return 'Eligibility: '..target end
function A:AwardEligibilityNotice() return '' end
function A:BuildUI() end
function A:Print(message) lastMessage=message end
function A:ShowConfirmation(kind,first,second) confirmation={kind=kind,first=first,second=second};return confirmation end
local function window(name,title,w,h)
    local f=CreateFrame('Frame',name,UIParent);f:SetSize(w,h);f:Hide();return f
end
local function text(parent,label)
    local f=CreateFrame('FontString',nil,parent);f:SetText(label);return f
end
local function button(parent,label,x,y,w,fn)
    local f=CreateFrame('Button',nil,parent);f:SetText(label);f:SetScript('OnClick',fn);return f
end
local function edit(parent) return CreateFrame('EditBox',nil,parent) end
A:BuildCorrectionUI(A.ui,window,text,button,edit)
A:OpenCorrection()
''')
    return lua

lua=setup()
lua.execute('''
assert(A.ui.correctionTargetDropdown:GetText()=='Charlie-Realm')
A.ui.correctionReason:SetText('Awarded to the wrong player')
A.ui.correctionTargetDropdown:Click()
local menu=A.ui.settingsDropdown
assert(#menu.choices==2)
assert(menu.rows[1].label:GetText()=='Alpha-Realm' and menu.rows[2].label:GetText()=='Charlie-Realm')
menu.rows[1]:Click()
assert(A.correctionContext.target=='Alpha-Realm')
assert(A.ui.correctionTargetDropdown:GetText()=='Alpha-Realm')
assert(A.ui.correctionEligibility:GetText()=='Eligibility: Alpha-Realm')
assert(A.ui.correctionReason:GetText()=='Awarded to the wrong player')
assert(A.ui.correctReview:IsEnabled())
A.ui.correctReview:Click()
assert(confirmation.kind=='SANGUINELOOTCOUNCIL_CORRECT_AWARD')
assert(confirmation.data.target=='Alpha-Realm' and confirmation.data.reason=='Awarded to the wrong player')
assert(confirmation.data.expectedRevision==2 and item.winner=='Hozfir-WildGrowth')
A.ui.correctionTargetDropdown:Click();A.ui.correction:Hide()
assert(not menu:IsShown() and not A.ui.settingsDropdownDismiss:IsShown())
''')
print('Dropdown selection, eligibility refresh, preserved reason, review confirmation and dismissal passed.')

for name,change in [('award revision changed','item.awardRevision=3'),('master changed',"A.state.master='Other-Realm'"),
                    ('session changed',"A.state.id='another-session'"),('correction limit',"item.corrections={1,2,3,4,5,6,7,8,9,10}")]:
    lua=setup()
    lua.execute(change)
    lua.execute('''
assert(not A:SelectCorrectionCandidate('Alpha-Realm'))
assert(A.correctionContext.target=='Charlie-Realm')
assert(not A.ui.correctReview:IsEnabled() and not A.ui.correctionTargetDropdown:IsEnabled())
''')
    print(name+': stale selection blocked')

lua=setup()
lua.execute('''
A.roster['Charlie-Realm']=nil
A:RenderCorrection()
assert(not A.ui.correctReview:IsEnabled() and A.ui.correctionTargetDropdown:IsEnabled())
assert(not A:SelectCorrectionCandidate('Charlie-Realm'))
assert(A:SelectCorrectionCandidate('Alpha-Realm') and A.ui.correctReview:IsEnabled())
A.roster['Alpha-Realm']=nil;A:RenderCorrection()
assert(not A.ui.correctionTargetDropdown:IsEnabled() and not A.ui.correctReview:IsEnabled())
''')
print('Roster changes, lost selection and no eligible recipients handled.')

lua=setup()
lua.execute('''
item.automaticAssignment=true;item.responses={}
for i=1,35 do A.roster['Player'..i..'-Realm']='raid'..i end
A:RenderCorrection();A.ui.correctionTargetDropdown.dropdownArrow:Click()
local menu=A.ui.settingsDropdown
assert(#menu.choices==40)
A:ScrollSettingsDropdown(1000)
local target=menu.choices[menu.offset+7][2]
menu.rows[7]:Click()
assert(A.correctionContext.target==target and A.ui.correctReview:IsEnabled())
assert(item.responses[target]==nil)
''')
print('40-recipient automatic-award dropdown and scrolling passed.')

for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Correction dropdown and Lua 5.1 checks passed. No installer generated.')
