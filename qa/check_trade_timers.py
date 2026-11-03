from pathlib import Path
import ast
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parent.parent
tree = ast.parse((root / 'qa/check_pickups.py').read_text(encoding='utf-8'))
fixtures = {n.targets[0].id: ast.literal_eval(n.value) for n in tree.body
            if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
            and n.targets[0].id in ('MOCK', 'SETUP')}
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(fixtures['MOCK'])
for name in ['Core', 'Features', 'Archive', 'Equipment', 'ResponseConfig', 'Voting',
             'LootConfiguration', 'Loot', 'WireCodec', 'StateDelta', 'Network']:
    lua.execute((root / 'SanguineLootTools' / (name + '.lua')).read_text(encoding='utf-8'),
                'SanguineLootTools', lua.globals().A)
lua.execute(fixtures['SETUP'])
lua.execute(r'''
UIParent={}
BIND_TRADE_TIME_REMAINING='You may trade this item with players that were also eligible to loot this item for the next %s.'
INT_SPELL_DURATION_HOURS='%d |4hour:hours;'
INT_SPELL_DURATION_MIN='%d min'
INT_SPELL_DURATION_SEC='%d sec'
local function timer(duration) return string.format(BIND_TRADE_TIME_REMAINING,duration) end
local tooltipLines={
    [1]={'Soulbound','|cff00ffff'..timer('1 hour 58 min')..'|r'},
    [2]={'Soulbound'},
    [3]={timer('0 sec')},
    [4]={timer('unreadable')},
    [5]={'Cooldown remaining: 1 hour 58 min'},
}
local tooltipCreates=0
function CreateFrame(kind,name,parent,template)
    assert(kind=='GameTooltip' and template=='GameTooltipTemplate')
    tooltipCreates=tooltipCreates+1
    local tip={lines={}}
    function tip:SetOwner(owner,anchor) assert(owner==UIParent and anchor=='ANCHOR_NONE') end
    function tip:ClearLines() self.lines={} end
    function tip:SetBagItem(bag,slot)
        assert(bag==0)
        if slot==6 then error('unavailable') end
        self.lines=tooltipLines[slot] or {}
        for i,text in ipairs(self.lines) do
            local value=text
            _G[name..'TextLeft'..i]={GetText=function() return value end}
        end
    end
    function tip:NumLines() return #self.lines end
    function tip:Hide() self.hidden=true end
    return tip
end
local bound=true
C_Item.IsBound=function() return bound end
C_TooltipInfo=nil
local kind,seconds=A:ReadTradeTimer(0,1,{})
assert(kind=='timed' and seconds==7080)
assert(A.tradeScanTooltip.hidden and tooltipCreates==1)
assert(A:ReadTradeTimer(0,2,{})=='unknown','stale timer leaked between bag slots')
kind,seconds=A:ReadTradeTimer(0,3,{})
assert(kind=='timed' and seconds==0)
assert(A:ReadTradeTimer(0,4,{})=='unknown')
assert(A:ReadTradeTimer(0,5,{})=='unknown','unrelated duration treated as trade timer')
assert(A:ReadTradeTimer(0,6,{})=='unknown' and A.tradeScanTooltip.hidden)
bound=false
assert(A:ReadTradeTimer(0,2,{})=='unbound')
assert(A:ReadTradeTimer(0,4,{})=='unknown','recognized unreadable timer became unbound')
bound=true
-- Existing tracked items refresh without another pickup message. Both windows
-- use this same countdown from the holder report.
A.state.trackedLoot={{id=1,guid='Item-Timer-Copy',link=bagLink,holder=A.me,
    kind='unknown',verifiedHolder=true,observedAt=wall,maxSeconds=1}}
A:PrimeLootBagSnapshot()
bags[1]={guid='Item-Timer-Copy',link=bagLink}
A:ScanLoot()
local entry=A.state.trackedLoot[1]
assert(entry.kind=='timed' and entry.seconds==7080)
local remaining,label=A:TradeRemaining(entry)
assert(remaining==7080 and label=='~1:58:00')
wall=wall+30
remaining,label=A:TradeRemaining(entry)
assert(remaining==7050 and label=='~1:57:30')
-- Modern data wins when readable; empty/error data still uses the fallback.
C_TooltipInfo={GetBagItem=function() return {lines={{leftText=timer('45 min')}}} end}
kind,seconds=A:ReadTradeTimer(0,6,{})
assert(kind=='timed' and seconds==2700)
C_TooltipInfo.GetBagItem=function() return {lines={}} end
kind,seconds=A:ReadTradeTimer(0,1,{})
assert(kind=='timed' and seconds==7080)
C_TooltipInfo.GetBagItem=function() error('unavailable') end
kind,seconds=A:ReadTradeTimer(0,1,{})
assert(kind=='timed' and seconds==7080 and tooltipCreates==1)
-- Localized grammar and punctuation must be matched literally.
BIND_TRADE_TIME_REMAINING='Echange possible (%s).'
INT_SPELL_DURATION_HOURS='%d |4heure:heures;'
INT_SPELL_DURATION_MIN='%d min'
kind,seconds=A:TradeTimerFromLines({{leftText='Echange possible (1 heure 58 min).'}})
assert(kind=='timed' and seconds==7080)
''')
print('Classic/modern tooltip reading, actual 1h58m text, stale slot isolation, zero/unknown timers, holder refresh and countdown passed.')
