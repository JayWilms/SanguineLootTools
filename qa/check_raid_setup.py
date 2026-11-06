from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parent.parent
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
A={}; SlashCmdList={}
''')
modules=['Core','Features','Voting','ResponseConfig','Responses','LootConfiguration','Warnings','MasterLooter']
def load():
    for name in modules:
        lua.execute((root/'SanguineLootTools'/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)

load()
lua.execute('''
function configureClient()
    A.me='Leader-Realm';A.roster={};A.leader=nil
    A.Client={ready=false,raid=false,group=false}
    function A.Client:ClockReady() return self.ready end
    function A.Client:InRaid() return self.raid end
    function A.Client:InGroup() return self.group end
    function A.Client:Combat() return false end
    function A.Client:ServerTime() return 100000 end
    function A.Client:Invoke() return false end
    function A:Changed() end
    function A:Print(message) end
end
configureClient();A:InitStorage()
assert(not A:IsLeader() and A:CanConfigureRaid())
-- Idle configuration must not depend on raid membership or working clocks.
assert(A:Act('responseDuration',{duration=95}))
assert(A:Act('master',{target='Master-Realm'}))
assert(A:Act('council',{target='Council-Realm'}))
assert(A:Act('council',{target='Absent-Realm'}))
assert(A:Act('selfVotes',{}))
assert(A:UpdateVotingRule('limit',3)~=false)
assert(A:UpdateVotingRule('visibility','own')~=false)
assert(A:UpdateVotingRule('names',true)~=false)
assert(A:EditResponse(1,'label','Priority'))
assert(A:ApplyWarningSettings({trade=true,sound=true,early=1200,urgent=240,release=false}))
local loot=A:LootConfiguration();loot.minimum=3;loot.collection=false;loot.openWindow=true
loot.automatic=true;loot.rules[3]={action='assign',target='Council-Realm',reason='Disenchant',note='Prepared solo'}
assert(A:SaveLootConfiguration(loot))
assert(A:SaveProfile('Prepared raid'))
assert(A:Act('responseDuration',{duration=55}));assert(A:LoadProfile('Prepared raid'))
assert(A:RaidSettings().responseDuration==95)
assert(A.state==nil,'preparation started a live session')
-- Simulate an addon reload: only SavedVariables survives.
A={}
''')
load()
lua.execute('''
configureClient();A:InitStorage()
local saved=A:RaidSettings()
assert(saved.responseDuration==95 and saved.responseOptions[1].label=='Priority')
assert(saved.master=='Master-Realm')
assert(saved.council['Council-Realm'] and saved.council['Absent-Realm'])
assert(saved.selfVotes==false and saved.rules.limit==3 and saved.rules.names and saved.rules.visibility=='own')
assert(saved.warningSettings.sound and saved.warningSettings.early==1200)
assert(saved.lootConfiguration.minimum==nil and saved.lootConfiguration.collection==false)
assert(saved.lootConfiguration.openWindow and saved.lootConfiguration.automatic)
assert(saved.lootConfiguration.rules[3].target=='Council-Realm')
assert(SanguineLootCouncilDB.profiles['Prepared raid'])
-- Joining alone must not apply a session. Starting is still leader-only.
A.Client.ready=true;A.Client.raid=true;A.Client.group=true
A.roster={['Leader-Realm']='raid1',['Master-Realm']='raid2',['Council-Realm']='raid3',['Raider-Realm']='raid4'}
A.leader=A.me
assert(A.state==nil)
assert(not A:Reduce('Raider-Realm',{op='start'}))
assert(A.state==nil)
assert(A:Reduce(A.me,{op='start'}))
local s=A.state
assert(s.responseDuration==95 and s.responseOptions[1].label=='Priority')
assert(s.master=='Master-Realm' and s.masterFallback=='Master-Realm')
assert(s.council['Council-Realm'] and not s.council['Absent-Realm'])
assert(s.rules.limit==3 and s.rules.visibility=='own' and s.rules.names and not s.selfVotes)
assert(s.warningSettings.sound and s.warningSettings.urgent==240)
assert(not s.autoCollect and s.lootConfiguration.minimum==nil and s.lootConfiguration.openWindow)
assert(s.lootConfiguration.automatic and s.lootConfiguration.rules[3].note=='Prepared solo')
-- Filtering absent members for this raid must not erase the prepared defaults.
assert(SanguineLootCouncilDB.raidSetup.council['Absent-Realm'])
s.rules.limit=1;assert(SanguineLootCouncilDB.raidSetup.rules.limit==3)
A.me='Raider-Realm';assert(not A:CanConfigureRaid())
assert(not A:SaveLootConfiguration(A:LootConfiguration()))
assert(not A:EditResponse(1,'label','Unauthorized'))
assert(not A:Reduce(A.me,{op='responseDuration',sid=s.id,duration=10}))
-- A missing automatic-assignment recipient pauses automation for that session.
A.state=nil;A.me='Leader-Realm';A.roster['Council-Realm']=nil
assert(A:Reduce(A.me,{op='start'}));assert(not A.state.lootConfiguration.automatic)
assert(SanguineLootCouncilDB.lootConfiguration.automatic)
''')
print('Solo setup edits, profiles, SavedVariables reload, leader-only session start, settings transfer, absent members/recipients and live non-leader restrictions passed.')

lua.execute('''
local leader,old,new,fallback='Leader-Realm','Old-Realm','New-Realm','Master-Realm'
A.me=leader;A.leader=leader
A.roster={[leader]='raid1',[old]='raid2',[new]='raid3',[fallback]='raid4'}
A.state=nil
local now,masterSlot,calls,mode=10,2,0,2
local setterAccepted=true
Enum={LootMethod={Masterlooter=2}}
C_PartyInfo={GetLootMethod=function() return mode,nil,masterSlot end}
function A:Name(unit)
    for name,id in pairs(self.roster) do if id==unit then return name end end
end
function A.Client:Uptime() return now end
function A.Client:Call(api,method,name)
    if api=='GetUnitName' then return true,A:Name(method) end
    if api=='C_PartyInfo.SetLootMethod' then
        assert(method==2 and name==new)
        calls=calls+1
        return true,setterAccepted
    end
    error(api)
end
function A:HostRequest(sender,p) return self:Reduce(sender,p) end
assert(A:Reduce(leader,{op='start'}))
local s=A.state
assert(s.master==old and s.masterFallback==fallback and not s.council[old])
assert(A:IsCouncilMember(old) and not A:IsCouncilMember(leader))

local item={id=1,status='open',voting='idle',round=1,ballotVersion=0,
    ballots={},ballotInvalidations={},responses={[leader]={choice=1,revision=1}}}
s.items={item}
s.trackedLoot={{holder=old,winner=leader,delivery='pending'}}
A:StartBallot(item)
local function vote(name)
    return A:ReduceVoting(name,{op='setVote',round=1,target=leader,selected=true,responseRevision=1},item)
end
local function assign(sender,target)
    return A:Reduce(sender,{op='master',sid=s.id,target=target})
end
assert(vote(old) and not vote(new))
assert(not assign(new,new) and calls==0)
assert(assign(leader,new) and calls==1)
assert(s.master==old and A.masterHandoff.target==new and not vote(new))
assert(not assign(leader,new) and calls==1)

-- The readback may briefly lose the holder during a game-side change.
masterSlot=nil;A:SyncGameMaster()
assert(s.masterBlocked and not A:IsCouncilMember(old) and not vote(old))
assert(A:BallotTotals(item)[leader]==1)
masterSlot=3;A:SyncGameMaster()
assert(not A.masterHandoff and s.master==new and not s.masterBlocked)
assert(A:IsCouncilMember(new) and not A:IsCouncilMember(old))
assert(not A:PrivateVoting(item,old).ownBallot and not vote(old))
assert(vote(new) and A:PrivateVoting(item,new).ownBallot)
local totals,_,progress=A:BallotTotals(item)
assert(totals[leader]==2 and progress.eligible==2 and progress.submitted==2)
assert(s.items[1]==item and s.trackedLoot[1].holder==old and s.trackedLoot[1].delivery=='pending')

mode=3;A:SyncGameMaster()
assert(s.master==fallback and A:IsCouncilMember(fallback))
A.roster[fallback]=nil;A:SyncGameMaster()
assert(s.master==leader and not s.masterBlocked)
mode=2;masterSlot=2;A:SyncGameMaster()
setterAccepted=false
assert(not assign(leader,new) and s.master==old and A.masterHandoff.message)
setterAccepted=true
assert(assign(leader,new) and s.master==old)
now=16;A:SyncGameMaster()
assert(A.masterHandoff.message and s.master==old and not s.masterBlocked)
''')
print('Native Master Looter confirmation, timeout and rejection, raid fallback, automatic voting rights and mid-ballot handoff passed.')
