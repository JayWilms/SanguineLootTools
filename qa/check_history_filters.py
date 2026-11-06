import csv
from io import StringIO
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

# Guild Bank classification follows the award reason, never quality or the
# nominated holder's identity. Legacy displayed reasons remain supported.
lua.execute('''
SanguineLootCouncilDB.history={
 {key='reward',winner='Banker-Realm',time=1,item='|Hitem:10|h[Blue Sword]|h',quality=3},
 {key='bank-blue',winner='Banker-Realm',time=1,item='|Hitem:10|h[Blue Sword]|h',quality=3,awardReason='Guild Bank'},
 {key='bank-material',winner='Moon-Realm',time=2,item='|Hitem:20|h[Cloth Material]|h',quality=1,awardReason='Guild Bank'},
 {key='bank-rep',winner='Banker-Realm',time=2,item='|Hitem:30|h[Reputation Token]|h',responseLabel='Guild Bank'},
 {key='de',winner='Banker-Realm',time=2,item='item:40',awardReason='Disenchant'},
 {key='explicit',winner='Moon-Realm',time=2,item='item:50',awardReason='Other',responseLabel='Guild Bank'}
}
assert(#A:FilterHistoryRecords(nil,'')==3)
assert(#A:FilterHistoryRecords('Banker-Realm','')==2)
assert(#A:FilterHistoryRecords(nil,'',true)==3)
assert(#A:FilterHistoryRecords(nil,'banker',true)==2)
assert(#A:FilterHistoryRecords(nil,'04/11/2026',true)==1)
assert(#A:FilterHistoryRecords(nil,'material',true)==1)
assert(#A:FilterHistoryRecords(nil,'|Hitem:30:99|h[Reputation Token]|h',true)==1)
assert(#A:FilterHistoryRecords(nil,'no such item',true)==0)
A.Client={ServerTime=function() return 100 end}
assert(A:PlayerHistory('Banker-Realm').total==2)
assert(#SanguineLootCouncilDB.history==6)
''')

# Exercise the actual History renderer with empty search results so the test
# focuses on view state, labels and scroll transitions without a game client.
lua.execute('A.confirmationDialogs={}; SlashCmdList={}')
lua.execute((root/'SanguineLootTools/UI.lua').read_text(),'SanguineLootTools',lua.globals().A)
lua.execute('''
local function widget()
 return {SetText=function(s,v) s.value=v end,SetShown=function(s,v) s.shown=v end,
 SetHeight=function() end,Show=function() end,SetVerticalScroll=function(s,v) s.offset=v;s.resets=(s.resets or 0)+1 end}
end
A.ui={history=widget(),historyScroll=widget(),historyMine=widget(),historyGuildBank=widget(),historyScope=widget(),historyRows={},historyText=widget(),historyEmpty=widget(),historyChild=widget()}
A.BuildUI=function() end;A.LayoutReadableWindow=function() end
A.me='Banker-Realm';A.historySearch='no such item'
A:ShowHistory(nil,true)
assert(A.historyGuildBank and A.historyFilter==nil)
assert(A.ui.historyGuildBank.value=='Back to All Rewards' and A.ui.historyMine.value=='My Rewards')
assert(A.ui.historyScope.value:find('Guild Bank',1,true))
local resets=A.ui.historyScroll.resets
A:ShowHistory(A.historyFilter,A.historyGuildBank)
assert(A.historyGuildBank and A.ui.historyScroll.resets==resets)
A:ShowHistory(A.me)
assert(not A.historyGuildBank and A.historyFilter==A.me)
assert(A.ui.historyMine.value=='Back to All Rewards' and A.ui.historyGuildBank.value=='Guild Bank')
assert(A.ui.historyScroll.resets==resets+1)
A:ShowHistory(nil,true)
A:ShowHistory()
assert(not A.historyGuildBank and A.historyFilter==nil)
assert(A.ui.historyMine.value=='My Rewards' and A.ui.historyGuildBank.value=='Guild Bank')
assert(A.historySearch=='no such item')
assert(#SanguineLootCouncilDB.history==6)
''')
print('Guild Bank search, legacy classification, reward exclusion, view switching, return labels and audit retention pass.')

# The real audit display should fit short records, cap long records and keep
# their entire content scrollable, without changing the retained award data.
audit=LuaRuntime(unpack_returned_tuples=True)
audit.execute('A={}')
audit.execute((root/'SanguineLootTools/History.lua').read_text(),'SanguineLootTools',audit.globals().A)
audit.execute('''
local function frame()
 return {SetSize=function(s,w,h) s.width=w;s.height=h end,SetHeight=function(s,h) s.height=h end,
 SetVerticalScroll=function(s,v) s.offset=v end,Show=function(s) s.shown=true end}
end
local label={SetText=function(s,v) s.value=v end,GetStringHeight=function() return measured end}
A.ui={auditText=label,awardAudit=frame(),auditScroll=frame(),auditChild=frame()}
A.BuildUI=function() end
A.FormatAwardHistory=function(_,record) return record.text end
local record={text='Recorded award and complete audit',winner='Moon-Realm'}
measured=60
A:ShowAwardAudit(record)
assert(A.ui.awardAudit.width<780 and A.ui.awardAudit.height<=220)
assert(A.ui.auditText.value==record.text and A.ui.auditChild.height>=measured)
assert(A.ui.auditScroll.offset==0 and A.ui.awardAudit.shown)
local shortHeight=A.ui.awardAudit.height
measured=1000;record.archivedAt=123
A.ui.auditScroll.offset=500
A:ShowAwardAudit(record)
assert(A.ui.awardAudit.height<=340 and A.ui.awardAudit.height>shortHeight)
assert(A.ui.auditChild.height>A.ui.auditScroll.height and A.ui.auditChild.height>=measured)
assert(A.ui.auditText.value:find(record.text,1,true) and A.ui.auditText.value:find('Archived:',1,true))
assert(A.ui.auditScroll.offset==0)
measured=30;record.archivedAt=nil
A:ShowAwardAudit(record)
assert(A.ui.awardAudit.height<=shortHeight and A.ui.auditText.value==record.text)
assert(record.winner=='Moon-Realm' and record.text=='Recorded award and complete audit')
''')
print('Audit sizing fits short records, bounds long records and retains full scrollable audit text.')

# Deletion is opt-in, selection-scoped and local. It must not turn ordinary
# audit clicks into deletes, accept stale confirmations or remove newer awards.
delete=LuaRuntime(unpack_returned_tuples=True)
delete.execute('''
A={confirmationDialogs={}}
function A.Copy(v) if type(v)~='table' then return v end;local r={};for k,x in pairs(v) do r[k]=A.Copy(x) end;return r end
function A:InitStorage() end
function A:Print(message) self.lastMessage=message end
function A:ShowAwardAudit(record) self.openedAudit=record end
function A:ShowConfirmation(kind,count) self.dialog={kind=kind,count=count};return self.dialog end
SanguineLootCouncilDB={history={
 {key='a',winner='Moon-Realm',item='item:1',revision=1,deliveryRevision=0},
 {key='b',winner='Zergul-Realm',item='item:2',revision=1,deliveryRevision=0},
 {key='bank',winner='Bank-Realm',item='item:3',awardReason='Guild Bank',revision=1,deliveryRevision=0}}}
''')
delete.execute((root/'SanguineLootTools/History.lua').read_text(),'SanguineLootTools',delete.globals().A)
delete.execute('''
-- Override just the audit UI entry point after loading the real click handler.
function A:ShowAwardAudit(record) self.openedAudit=record end
local a,b,bank=SanguineLootCouncilDB.history[1],SanguineLootCouncilDB.history[2],SanguineLootCouncilDB.history[3]
A:ClickHistoryRecord(a);assert(A.openedAudit==a and #SanguineLootCouncilDB.history==3)
A.historySync={}
assert(not A:BeginHistoryDeletion())
A.historySync=nil
assert(A:BeginHistoryDeletion())
A:RenderHistoryDeletion({a,b},'all')
A:ClickHistoryRecord(a)
assert(A:HistoryDeleteCount()==1 and A.openedAudit==a)
A:ClickHistoryRecord(a);assert(A:HistoryDeleteCount()==0)
A:SelectShownHistory();assert(A:HistoryDeleteCount()==2)
assert(#SanguineLootCouncilDB.history==3,'selection deleted records before confirmation')
assert(A:ReviewHistoryDeletion());local canceled=A.dialog.data
A:CancelHistoryDeletion()
assert(not A:ConfirmHistoryDeletion(canceled) and #SanguineLootCouncilDB.history==3)
-- Switching filters clears selection, so hidden records cannot be deleted by mistake.
A:BeginHistoryDeletion();A:RenderHistoryDeletion({a,b},'all');A:SelectShownHistory()
A:RenderHistoryDeletion({bank},'guild-bank');assert(A:HistoryDeleteCount()==0)
A:SelectShownHistory();assert(A:ReviewHistoryDeletion())
A.confirmationDialogs.SANGUINELOOTCOUNCIL_DELETE_HISTORY.OnAccept(A.dialog)
assert(#SanguineLootCouncilDB.history==2 and not A.historyDeleteMode)
assert(SanguineLootCouncilDB.history[1]==a and SanguineLootCouncilDB.history[2]==b)
-- Updated records and records added after the prompt survive confirmation.
A:BeginHistoryDeletion();A:RenderHistoryDeletion({a,b},'all');A:SelectShownHistory()
assert(A:ReviewHistoryDeletion());local context=A.dialog.data
b.revision=2;b.winner='NewWinner-Realm'
SanguineLootCouncilDB.history[3]={key='new',winner='Late-Realm',revision=1}
A:ConfirmHistoryDeletion(context)
assert(#SanguineLootCouncilDB.history==2)
assert(SanguineLootCouncilDB.history[1].key=='b' and SanguineLootCouncilDB.history[2].key=='new')
assert(A.lastMessage:find('1 changed record(s) were kept',1,true))
assert(not A:ConfirmHistoryDeletion(context),'confirmation replay was accepted')
''')
print('Normal audit clicks, opt-in deletion, filter selection, cancellation, confirmation and newer-record guards pass.')

# Bulk selection is reversible without leaving delete mode. The label reflects
# manual row changes too; an empty result is never considered fully selected.
delete.execute('''
local function widget()
 return {SetText=function(s,v) s.value=v end,SetShown=function(s,v) s.shown=v end,SetEnabled=function(s,v) s.enabled=v end}
end
A.ui={historyDelete=widget(),historySelectAll=widget(),historyDeleteCancel=widget()}
local records=SanguineLootCouncilDB.history
local before=#records
A:BeginHistoryDeletion();A:RenderHistoryDeletion(records,'toggle')
assert(A.ui.historySelectAll.value=='Select All Shown')
A:SelectShownHistory();A:RenderHistoryDeletion(records,'toggle')
assert(A.ui.historySelectAll.value=='Deselect All' and A:HistoryDeleteCount()==before)
A:SelectShownHistory();A:RenderHistoryDeletion(records,'toggle')
assert(A.ui.historySelectAll.value=='Select All Shown' and A:HistoryDeleteCount()==0 and A.historyDeleteMode)
A:ClickHistoryRecord(records[1]);A:RenderHistoryDeletion(records,'toggle')
assert(A.ui.historySelectAll.value=='Select All Shown')
A:ClickHistoryRecord(records[2]);A:RenderHistoryDeletion(records,'toggle')
assert(A.ui.historySelectAll.value=='Deselect All')
A:ClickHistoryRecord(records[1]);A:RenderHistoryDeletion(records,'toggle')
assert(A.ui.historySelectAll.value=='Select All Shown')
A:SelectShownHistory();A:RenderHistoryDeletion(records,'toggle')
assert(A.ui.historySelectAll.value=='Deselect All')
A:RenderHistoryDeletion({},'empty')
assert(A.ui.historySelectAll.value=='Select All Shown' and not A.ui.historySelectAll.enabled)
A:SelectShownHistory();assert(A:HistoryDeleteCount()==0 and A.historyDeleteMode)
assert(#SanguineLootCouncilDB.history==before)
A:CancelHistoryDeletion();A:RenderHistoryDeletion(records,'toggle')
assert(not A.historyDeleteMode and not A.ui.historySelectAll.shown)
''')
print('Select/deselect labels follow bulk and manual row selection; clearing preserves delete mode and records.')


# CSV exports the whole filter and preserves spreadsheet cell boundaries.
export = LuaRuntime(unpack_returned_tuples=True)
export.execute('A={}; date=os.date')
export.execute((root/'SanguineLootTools/History.lua').read_text(), 'SanguineLootTools', export.globals().A)
export.execute('''
SanguineLootCouncilDB={history={
    {key='raid:1',item='|Hitem:123:0|h[Blade, "of Storms"]|h',time=1793923200,
        winner='Moon-Realm',responseLabel='=SUM(1,2)',master='Lead-Realm',votes=0,delivery={status='delivered'}},
    {key='raid:2',item='|Hitem:456:0|h[Other Blade]|h',winner='Other-Realm',responseLabel='BIS',quantity=2},
    {key='raid:3',item='|Hitem:789:0|h[Guild Blade]|h',winner='Banker-Realm',responseLabel='Guild Bank'},
}}
local function widget()
    return {SetText=function(s,v) s.text=v end,SetHeight=function() end,Show=function(s) s.shown=true end,
        SetFocus=function(s) s.focused=true end,HighlightText=function(s) s.selected=true end,SetVerticalScroll=function() end}
end
A.ui={historyExportBox=widget(),historyExportSummary=widget(),historyExportWindow=widget(),historyExportScroll=widget()}
A.FocusWindow=function() end
A.historyFilter='Moon-Realm';A.historySearch='blade'
assert(A:ShowHistoryExport())
assert(A.ui.historyExportWindow.shown and A.ui.historyExportBox.selected)
assert(A.ui.historyExportSummary.text=='Moon-Realm | 1 matching record')
filtered=A.ui.historyExportBox.text
A.historyDeleteMode=true
assert(not A:ShowHistoryExport())
A.historyDeleteMode=nil;A.historyFilter=nil;A.historyGuildBank=true
assert(A:ShowHistoryExport())
bank=A.ui.historyExportBox.text
A.historySearch='no results'
assert(not A:ShowHistoryExport())

local large={}
for i=1,500 do large[i]={key='raid:'..i,item='|Hitem:456:0|h[Other Blade]|h',winner='Other-Realm'} end
full=A:HistoryCSV(large)
assert(#SanguineLootCouncilDB.history==3)
''')
csv_rows = list(csv.reader(StringIO(export.globals().filtered)))
assert len(csv_rows) == 2 and len(csv_rows[1]) == 10
assert csv_rows[1] == ['2026-11-06T00:00:00Z', 'Moon-Realm', 'Blade, "of Storms"', '123', '1',
                       "'=SUM(1,2)", '0', 'Lead-Realm', 'delivered', 'raid:1']
bank_rows = list(csv.reader(StringIO(export.globals().bank)))
assert [row[-1] for row in bank_rows] == ['Award ID', 'raid:3']
assert len(list(csv.reader(StringIO(export.globals().full)))) == 501
print('History CSV filter scope, escaping, formula-like responses and 500-record export pass.')
