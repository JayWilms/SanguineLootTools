from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parent.parent
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
A={};SlashCmdList={}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
''')
for name in ['Core','Features','Voting','ResponseConfig','Responses','LootConfiguration','Warnings','WindowLayouts','CouncilUI']:
    lua.execute((root/'SanguineLootTools'/f'{name}.lua').read_text(),'SanguineLootTools',lua.globals().A)
lua.execute('''
A.me='Leader-Realm';A.roster={};A.leader=nil
A.Client={ClockReady=function() return false end}
function A:Print(message) lastMessage=message end
function A:Changed() end
function A:RenderSettings() end
function A:Render() end
A:InitStorage()
SanguineLootCouncilDB.lootConfiguration.openWindow=true
assert(A:LootWindowAutoOpen(),'the existing opening preference was not migrated')
A:SetLootWindowAutoOpen(false)
assert(not A:LootWindowAutoOpen())
assert(SanguineLootCouncilDB.lootConfiguration.openWindow,'personal toggle changed shared raid settings')
assert(A:SaveProfile('Display independent'))
assert(SanguineLootCouncilDB.profiles['Display independent'].displayPreferences==nil)
SanguineLootCouncilDB.lootConfiguration.openWindow=false
assert(A:LoadProfile('Display independent'))
assert(SanguineLootCouncilDB.lootConfiguration.openWindow)
assert(not A:LootWindowAutoOpen(),'loading a raid profile overwrote personal display preferences')
A:SetLootWindowAutoOpen(true)
A.me='Alt-Realm';A:SetLootWindowAutoOpen(false)
A.me='Leader-Realm';assert(A:LootWindowAutoOpen())
A.me='Alt-Realm';assert(not A:LootWindowAutoOpen())
-- A raid leader/state change must not override this character's preference.
A.state={lootConfiguration=A:DefaultLootConfiguration()}
A.state.lootConfiguration.openWindow=true
assert(not A:LootWindowAutoOpen())
A:SetLootWindowAutoOpen(true)
assert(A.state.lootConfiguration.openWindow)
A.state=nil


-- Both window layouts are independent and survive character/profile switches.
assert(A:LootWindowLayout('response')=='Full' and A:LootWindowLayout('voting')=='Full')
assert(A:SetLootWindowLayout('response','Compact'))
assert(A:LootWindowLayout('response')=='Compact' and A:LootWindowLayout('voting')=='Full')
assert(not A:SetLootWindowLayout('loot','Compact'))
assert(not A:SetLootWindowLayout('response','Unknown'))
A.me='Leader-Realm'
assert(A:LootWindowLayout('response')=='Full')
assert(A:SetLootWindowLayout('voting','Compact'))
A.me='Alt-Realm'
assert(A:LoadProfile('Display independent'))
assert(A:LootWindowLayout('response')=='Compact' and A:LootWindowLayout('voting')=='Full')

local response, voting={},{}
A.windowFrames={{name='SanguineLootCouncilResponses',frame=response},{name='SanguineLootCouncilMain',frame=voting}}
assert(A:WindowPolicy(response)[1]==620 and A:WindowPolicy(voting)[1]==1100)
A.me='Leader-Realm'
assert(A:WindowPolicy(response)[1]==760 and A:WindowPolicy(voting)[1]==740)
A.me='Alt-Realm'

local oldOptions=A.ResponseOptions
local options={}
function A:ResponseOptions() return options end
for i=1,6 do options[i]={enabled=true} end
assert(A:ResponseWindowHeight()==315)
for i=7,9 do options[i]={enabled=true} end
assert(A:ResponseWindowHeight()==345)
A.responseNoteExpanded=true
assert(A:ResponseWindowHeight()==389)
A.responseNoteExpanded=nil
A.ResponseOptions=oldOptions

-- Timer mode has independent sizing and keeps existing Full dimensions.
local timer={}
A.windowFrames[#A.windowFrames+1]={name='SanguineLootCouncilTimer',frame=timer}
local timerSaved={width=672,height=350,compactWidth=400,compactHeight=260,geometryVersion=3}
local w,h=A:PreferredWindowSize(timer,timerSaved)
assert(w==672 and h==350)
assert(A:SetLootWindowLayout('timer','Compact'))
w,h=A:PreferredWindowSize(timer,timerSaved)
assert(w==400 and h==260 and A:WindowPolicy(timer)[1]==380)
A.me='Leader-Realm'
assert(A:LootWindowLayout('timer')=='Full')
A.me='Alt-Realm'

-- Keep response actions and paging inside the tighter footprint.
local function layoutWidget(height)
 return {
    h=height or 26,text='',
    ClearAllPoints=function() end,SetPoint=function(w,_,x,y) w.x,w.y=x,-y end,
    SetWidth=function(w,v) w.w=v end,SetHeight=function(w,v) w.h=v end,
    SetSize=function(w,x,y) w.w,w.h=x,y end,
    GetWidth=function(w) return w.w end,GetHeight=function(w) return w.h end,
    GetEffectiveScale=function() return 1 end,
    SetShown=function(w,v) w.shown=v end,SetText=function(w,v) w.text=v end,
    GetText=function(w) return w.text end,SetMaxLines=function() end,
 }
end
response=layoutWidget(389);response.w=620;response.title=layoutWidget()
local u={popup=response,lootTimers={},lootPanels={deliveries={}},responseButtons={},responseItemButtons={}}
A.ui=u;A.noteDraftKey='item:1'
for _,key in ipairs({'responseProgress','popupItem','popupStatus','popupFacts','popupEligibility','responseBar',
    'note','noteBytes','responseNoteToggle','responseRail','responseRailPage','responseRailPrevious','responseRailNext',
    'responsePrevious','responseNext','responseVoting','responseRoleHint'}) do u[key]=layoutWidget() end
u.note.hint=layoutWidget()
for i=1,9 do u.responseButtons[i]=layoutWidget() end
for i=1,6 do u.responseItemButtons[i]=layoutWidget();u.responseItemButtons[i].icon=layoutWidget() end
function A:StyleButtonOutline() end
A.responseNoteExpanded=true
A:LayoutReadableWindow(response)
assert(u.note.shown and u.responseNoteToggle.shown and u.responseNoteToggle.text=='Hide Note')
assert(u.responseButtons[9].y+u.responseButtons[9].h<u.responseNext.y)
assert(58+u.responseRailNext.y+u.responseRailNext.h<response.h)
u.note.text='My draft'
A.responseNoteExpanded=nil;response.h=345
A:LayoutReadableWindow(response)
assert(not u.note.shown and not u.note.hint.shown and u.note.text=='My draft' and u.responseNoteToggle.text=='Edit Note')
assert(u.responseButtons[9].y+u.responseButtons[9].h<u.responseNext.y)

-- Compact voting keeps the ballot controls aligned and restores the Full columns.
local candidate=layoutWidget()
candidate.cells={};candidate.gear={layoutWidget(),layoutWidget()}
candidate.pick=layoutWidget();candidate.noteButton=layoutWidget();candidate.award=layoutWidget()
u.councilHeadings={};u.councilHeadingBackground=layoutWidget();u.candidates={candidate}
for i=1,9 do u.councilHeadings[i]=layoutWidget();candidate.cells[i]=layoutWidget() end
A:LayoutVotingColumns(620,true)
assert(not u.councilHeadings[5].shown and u.councilHeadings[9].shown)
assert(candidate.pick.x+candidate.pick.w<candidate.award.x)
assert(candidate.award.x+candidate.award.w<=candidate.w)
A:LayoutVotingColumns(780,false)
assert(u.councilHeadings[5].shown and candidate.cells[5].shown)
A.ui=nil;A.noteDraftKey=nil

local first={width=900,height=600,x=11,y=22}
local second={width=720,height=400,x=33,y=44}
A.windowFrames={{name='SanguineLootCouncilTrade',frame=first},{name='SanguineLootCouncilTimer',frame=second}}
local store=A:WindowLayoutStore()
store.SanguineLootCouncilTrade={x=11,y=22}
store.SanguineLootCouncilTimer={x=33,y=44}
store.positionsLocked=true;store.windowLocks={SanguineLootCouncilTrade=true}
local untouched=store.SanguineLootCouncilTimer
function A:FinishWindowMove(frame,name) frame.stopped=true end
function A:ResizeReadableWindow(frame,w,h) frame.width=w;frame.height=h end
function A:DefaultWindowPosition(frame) frame.x=100;frame.y=200 end
function A:SaveWindowLayout(frame,name) self:WindowLayoutStore()[name]={x=frame.x,y=frame.y,width=frame.width,height=frame.height} end
function A:RefreshWindowChrome() end
local choices=A:WindowResetChoices()
assert(#choices==2 and choices[1][1]=='Loot Window' and choices[2][1]=='Timer Window')
assert(not A:ResetOneWindowLayout('UnknownWindow'))
assert(A:ResetOneWindowLayout('SanguineLootCouncilTrade'))
assert(first.width==820 and first.height==440 and first.x==100 and first.y==200)
assert(second.width==720 and second.height==400 and second.x==33 and second.y==44)
assert(store.SanguineLootCouncilTimer==untouched,'single reset touched another window store')
assert(store.positionsLocked and store.windowLocks.SanguineLootCouncilTrade,'reset changed lock preferences')
function A:RestoreWindowLayouts()
 assert(store.SanguineLootCouncilTrade==nil and store.SanguineLootCouncilTimer==nil)
 self.restoredAll=true
end
A:ResetWindowLayout();assert(A.restoredAll and store.positionsLocked)
assert(A:LootWindowAutoOpen(),'layout reset changed the opening preference')
assert(A:LootWindowLayout('response')=='Compact','layout reset changed the display mode')
''')
print('Auto-open is per-character and independent of raid profiles/state; single-window reset preserves other layouts and display preferences.')

# Settings context distinguishes saved/live/personal work and keeps notices
# scoped to controls the viewer cannot change. Switching tabs updates it now,
# without waiting for another raid event.
lua.execute((root/'SanguineLootTools/SettingsUI.lua').read_text(),'SanguineLootTools',lua.globals().A)
lua.execute('''
local function widget()
 return {SetText=function(s,v) s.text=v end,SetShown=function(s,v) s.shown=v end,SetBackdropColor=function() end}
end
A.ui={settingsStatus=widget(),settingsAccess=widget()}
A.me='Leader-Realm';A.leader=nil;A.state=nil;A.settingsPage='Session'
A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Editing Saved Raid Setup' and not A.ui.settingsAccess.shown)
A.leader=A.me;A.state={id='live',master='Master-Realm',council={},items={}}
A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Active Session · Raid Leader' and not A.ui.settingsAccess.shown)
A.me='Council-Realm';A.state.council[A.me]=true;A.settingsPage='Council'
A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Active Session · Council' and A.ui.settingsAccess.shown)
assert(A.ui.settingsAccess.text:find('View only',1,true))
A.settingsPage='Display';A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Personal Display Settings' and not A.ui.settingsAccess.shown)
A.settingsPage='Responses';A:RefreshSettingsContext()
assert(A.ui.settingsAccess.shown and A.ui.settingsAccess.text:find('colours remain editable',1,true))
A.settingsPage='Advanced';A:RefreshSettingsContext();assert(not A.ui.settingsAccess.shown)
A.me='Master-Realm';A.settingsPage='Loot Configuration';A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Active Session · Master Looter')
A.me='Raider-Realm';A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Active Session · Raider' and A.ui.settingsAccess.shown)
A.me='Leader-Realm';A.settingsPage='Council';A.state.items={{status='open',voting='open'}}
A:RefreshSettingsContext()
assert(A.ui.settingsAccess.shown and A.ui.settingsAccess.text:find('locked',1,true))
A.state.groupTest=true;A.groupTest=true;A.demo=true;A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Group Test · Raid Leader')
assert(A.ui.settingsAccess.text=='Voting rules are locked during active rounds.')
A.groupTest=nil;A.state.groupTest=nil;A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Solo Test · Raid Leader')
A.demo=nil;A.state=nil;A:RefreshSettingsContext()
assert(A.ui.settingsStatus.text=='Editing Saved Raid Setup' and not A.ui.settingsAccess.shown)

A.me='Raider-Realm';A.leader='Leader-Realm';A.state={id='live',master='Master-Realm',council={},items={}}
A.ui.settingsPages={Session=widget(),Responses=widget(),Display=widget()}
A.ui.settingsTabs={}
for key in pairs(A.ui.settingsPages) do local t=widget();t.accent=widget();A.ui.settingsTabs[key]=t end
A.ui.settingsHeading=widget();A.ui.settingsDescription=widget();A.ui.settingsLayoutKey='ready'
function A:CloseSettingsDropdown() end
function A:LayoutSettings() self.layoutNotice=self.ui.settingsHasNotice;self.ui.settingsLayoutKey='ready' end
A:SelectSettingsPage('Responses')
assert(A.settingsPage=='Responses' and A.ui.settingsAccess.shown and A.layoutNotice)
A:SelectSettingsPage('Display')
assert(A.settingsPage=='Display' and not A.ui.settingsAccess.shown and not A.layoutNotice)
assert(A.ui.settingsPages.Display.shown and not A.ui.settingsPages.Responses.shown)
''')
print('Compact Settings status, scoped permission/lock notices and immediate personal/shared tab switching pass.')
