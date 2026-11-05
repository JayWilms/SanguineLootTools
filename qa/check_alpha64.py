from pathlib import Path
from lupa.lua51 import LuaRuntime

source = Path(__file__).resolve().parent.parent / 'SanguineLootTools'
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('A = {}')
for name in ('Client', 'Core', 'Archive', 'Items', 'CouncilUI', 'History'):
    lua.execute((source / f'{name}.lua').read_text(encoding='utf-8'), 'SanguineLootTools', lua.globals().A)

lua.execute(r'''
local requested = {}
C_Item = {
    IsItemDataCachedByID = function(id) return id == 12 end,
    RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
}
A.state = {id='first', trackedLoot={{link='item:11'}, {link='item:12'}}, items={{id=1, link='item:11:2'}}}
A:Changed()
A:Changed()
assert(#requested == 1 and requested[1] == 11)
A.state.trackedLoot[3] = {link='item:13'}
A:Changed()
assert(#requested == 2 and requested[2] == 13)
A.state.id = 'second'
A:Changed()
assert(#requested == 4 and requested[3] == 11 and requested[4] == 13)

local owner, shown, enters = nil, true, 0
local row = {
    IsVisible=function() return true end,
    GetScript=function(_, event)
        assert(event == 'OnEnter')
        return function() enters = enters + 1 end
    end,
}
GameTooltip = {
    SetOwner=function(_, value) owner = value end,
    SetHyperlink=function() end,
    IsShown=function() return shown end,
    GetOwner=function() return owner end,
}
A:SetHoveredItem(row, 'item:11:2')
A:ItemDataLoaded(12, true)
A:ItemDataLoaded(11, false)
assert(enters == 0)
A:ItemDataLoaded(11, true)
assert(enters == 1)
shown = false
A:ItemDataLoaded(11, true)
shown, owner = true, {}
A:ItemDataLoaded(11, true)
assert(enters == 1)

local samples = A:TestItems()
local ids = {}
for _, sample in ipairs(samples) do ids[sample.id] = true end
assert(#samples == 27)
for _, id in ipairs({279247, 279249, 279250, 274277, 279308, 279295, 279322, 279301, 279315}) do
    assert(ids[id])
end
assert(not ids[274415] and not ids[255726] and not ids[16083])
''')

lua.execute(r'''
function GetBuildInfo() return '1.60.1', '123', 'today', 16001 end
local units = {
    player={'Alex', 'Stone'}, party1={'Alex', 'River'}, party2={'Alex'},
    NPC={'Alex', 'River'},
}
function UnitFullName(unit)
    if units[unit] then return unpack(units[unit]) end
end
function GetNormalizedRealmName() return 'LegacyRealm' end
function IsInGroup() return true end
function UnitIsGroupLeader(unit) return unit == 'player' end
A.state = nil
A:RefreshRoster()
assert(A.me == 'Alex-Stone' and A.leader == 'Alex-Stone')
assert(A.roster['Alex-Stone'] == 'player' and A.roster['Alex-River'] == 'party1')
assert(A:Name('NPC') == 'Alex-River' and not A:Name('party2'))
assert(A:Resolve('Alex') == nil and A:Resolve('Alex-LegacyRealm') == nil)
assert(A:Resolve('alex river') == 'Alex-River' and A:Resolve('Alex-Stone') == 'Alex-Stone')
assert(A:DisplayName('Alex-Stone') == 'Alex-Stone')
SanguineLootCouncilDB = {history={
    {key='legacy', winner='Alex-LegacyRealm'},
    {key='stone', winner='Alex-Stone'},
    {key='river', winner='Alex-River'},
}}
function A:InitStorage() end
assert(A:PlayerHistory('Alex-Stone').records[1].key == 'stone')
assert(A:PlayerHistory('Alex-River').records[1].key == 'river')
assert(A:PlayerHistory('Alex-LegacyRealm').records[1].key == 'legacy')
function GetBuildInfo() return '1.15.8', '123', 'today', 11508 end
assert(A:Name('party2') == 'Alex-LegacyRealm')
''')

lua.execute(r'''
function GetServerTime() return 100 end
A.ui = {main={IsShown=function() return true end}}
function A:VisibleVoting(item) return {ownBallot=item.testBallot} end
local function item(id, status, voting, responses, deadline)
    return {id=id, round=1, status=status, voting=voting, responses=responses, deadline=deadline}
end
local first = item(1, 'open', 'open', {['Alex-River']={choice=1,revision=3}})
local closed = item(2, 'closed', 'closed', first.responses)
local pass = item(3, 'open', 'open', {['Alex-River']={choice=6}, ['Alex-Stone']={choice=1}})
local expired = item(4, 'closed', 'open', first.responses, 100)
local departed = item(5, 'open', 'open', {['Absent-River']={choice=1}})
local eligible = item(6, 'open', 'open', first.responses)
A.state = {id='voting', council={[A.me]=true}, items={first,closed,pass,expired,departed,eligible}, rules={limit=1}}
A.selectedItem, A.selectedCandidate, A.votingItemRows = first.id, 'Alex-River', 3
A:PrepareVotingAdvance('vote', first, 'Alex-River')
A:ApplyVotingAdvance()
assert(A.selectedItem == first.id and A.pendingVotingAdvance)
first.testBallot = {choices={['Alex-River']=true}, versions={['Alex-River']=3}}
A:ApplyVotingAdvance()
assert(A.selectedItem == eligible.id and A.itemPage == 1 and not A.selectedCandidate)
A.selectedCandidate = 'Alex-River'
eligible.testBallot = first.testBallot
A:PrepareVotingAdvance('vote', eligible, 'Alex-River')
A:ApplyVotingAdvance()
assert(A.selectedItem == eligible.id and A.selectedCandidate == 'Alex-River' and not A.pendingVotingAdvance)
function A:Render() end
A:CycleCouncilItem(-1)
assert(A.selectedItem == departed.id)
''')
print('Item preload and hover refresh, test samples, Forever identities, and confirmed voting advance pass.')
