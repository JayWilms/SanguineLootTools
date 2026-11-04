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
assert(A:Act('masterAutoSync',{}))
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
assert(saved.master=='Master-Realm' and saved.masterAutoSync==false)
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
assert(s.master=='Master-Realm' and s.masterAutoSync==false)
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
