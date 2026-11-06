from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
LUA = LuaRuntime(unpack_returned_tuples=True)
LUA.execute('''
A={};SlashCmdList={}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
''')
for name in ('Core','Client','Features','Archive','Awards','Voting','ResponseConfig','Responses',
             'LootConfiguration','Equipment','Loot','Warnings','MasterLooter','Recovery','StateDelta','WireCodec','Network'):
    LUA.execute((ROOT/'SanguineLootTools'/f'{name}.lua').read_text(), 'SanguineLootTools', LUA.globals().A)

LUA.execute('''
local leader,backup,peer='Leader-Forever','Backup-Forever','Peer-Forever'
local now=100
function A.Client:ClockReady() return true end
function A.Client:InRaid() return true end
function A.Client:Combat() return false end
function A.Client:Uptime() return now end
function A.Client:ServerTime() return now+1000 end
function A:Print(message) lastMessage=message end
function A:SyncGameMaster() end
function A:Record(item) end
function A:Render() end
function A:Publish() self:ChooseRecoveryBackup() end
function A:Changed() end
local out={}
function A:Send(packet,target)
    packet.protocol=self.protocol
    out[#out+1]={packet=packet,target=target}
    return true
end
local function last(kind)
    for i=#out,1,-1 do if out[i].packet.kind==kind then return out[i] end end
end
local function inbound(from,packet,channel)
    packet.protocol=A.protocol
    A:Packet(from,packet,channel or 'WHISPER')
end
A.me,A.leader=leader,leader
A.roster={[leader]='raid1',[backup]='raid2',[peer]='raid3'}
SanguineLootCouncilDB={}
A:InitStorage()
local config=A:DefaultLootConfiguration()
config.collection,config.automatic=true,true
local vote={choices={[peer]=true},versions={[peer]=1}}
local live={id='original',leader=leader,master=backup,masterFallback=backup,
 council={[backup]=true},lootConfiguration=config,rules=A:DefaultVoting(),responseDuration=60,
 autoCollect=true,trackedLoot={{id=9,item=2,guid='Item-Sample',holder=backup,verifiedHolder=true,delivery='pending'}},
 items={
    {id=1, status='open', voting='open', round=1, ballotVersion=7, responseRound=2,
        responseDeadline=1160,responseDuration=60,responses={[peer]={choice=1,revision=1}},ballots={[backup]=vote}},
    {id=2, status='awarded', voting='closed', round=1, ballotVersion=9, responseRound=1,
        winner=peer,awardRevision=2,responses={},ballots={},closedResults={totals={},names={},progress={}}},
    {id=3, status='closed', voting='closed', round=1, ballotVersion=2, responseRound=1,
        responses={},ballots={},closedResults={totals={},names={},progress={}}},
 }}
A.state,A.rev=A.Copy(live),12
A:ChooseRecoveryBackup()
assert(A.state.recoveryBackup==backup)
live=A.Copy(A.state)
A:SendRecoveryBallots()
local ballotPacket=last('recoveryBallots')
assert(ballotPacket.target==backup and ballotPacket.packet.items[1].ballots[backup])
local public=A:PublicState()
assert(not public.items[1].ballots and not public.items[2].closedResults)
A.me,A.state=backup,A.Copy(public)
inbound(leader,ballotPacket.packet,'RAID')
assert(not A:RecoveryCopy())
inbound(leader,ballotPacket.packet)
assert(A:RecoveryCopy().items[1].ballots[backup].choices[peer])
local backupBallots=A.Copy(A.recoveryBallots)
A.me=peer
assert(not A:RecoveryCopy())

-- New leader has only the public view. Keep it frozen while a backup is fetched.
A.leader=peer;A:CheckRecoveryRoster()
assert(A.recoveryPending and A.state.id=='original' and not A:IsMaster())
assert(not A:HostRequest(peer,{op='award',sid='original',item=1,target=peer}))
A:TickRecovery()
local token=last('recoveryProbe').packet.token
inbound(backup,{kind='recoveryOffer',sid='original',token=token,rev=12,complete=true})
now=now+6;A:TickRecovery()
assert(last('recoveryFetch').target==backup and A:RecoveryTransportPeer(backup))
inbound(leader,{kind='recoveryState',sid='original',token=token,rev=12,state=live})
assert(A.recoveryPending and A.state.id=='original')
local payload=A.Encode({kind='recoveryState',sid='original',token=token,rev=12,state=live,protocol=A.protocol})
local fragments=math.ceil(#payload/180)
assert(fragments>8)
for i=1,fragments do
    A:Receive('SanguineLC','9988:'..i..':'..fragments..':'..payload:sub((i-1)*180+1,i*180),'WHISPER',backup)
end
local recovered=A.state
assert(not A.recoveryPending and recovered.id~='original' and recovered.historyID=='original')
assert(A.rev==13 and recovered.leader==peer and recovered.master==backup)
assert(recovered.items[1].responseDeadline==1160 and recovered.items[1].ballots[backup].choices[peer])
assert(recovered.items[2].winner==peer and recovered.items[2].awardRevision==2)
assert(recovered.items[3].voting=='closed' and recovered.items[3].closedResults)
assert(recovered.trackedLoot[1].delivery=='pending' and recovered.trackedLoot[1].holder==backup)
assert(not recovered.trackedLoot[1].verifiedHolder and not recovered.autoCollect and not recovered.lootConfiguration.automatic)

-- Restored clients reject delayed packets from the old leader or session.
local restoredView=A:PublicState()
A.me=backup;A.state=A.Copy(public);A.rev=12;A.recoveryPending=true
inbound(peer,{kind='view',full=true,rev=13,state=restoredView},'RAID')
assert(not A.recoveryPending and A.state.id==recovered.id)
inbound(leader,{kind='view',full=true,rev=100,state=false,ended=recovered.id},'RAID')
inbound(peer,{kind='view',full=true,rev=100,state=false,ended='original'},'RAID')
inbound(peer,{kind='view',full=true,rev=12,state=public},'RAID')
assert(A.state.id==recovered.id)

-- A public revision ahead of the backup must not silently roll back.
A.me,A.leader,A.state,A.rev=peer,peer,A.Copy(public),13
A:CheckRecoveryRoster();A:TickRecovery()
token=last('recoveryProbe').packet.token
inbound(backup,{kind='recoveryOffer',sid='original',token=token,rev=12,complete=true})
now=now+6;A:TickRecovery()
assert(A.recoveryFailed=='original' and A.recoveryPending and A.rev==13)

-- Same leader reload can use an older checkpoint to locate a newer live copy.
A:EndRecovery()
A.me,A.leader,A.state,A.rev=leader,leader,A.Copy(live),11
A:PersistSession()
A.state,A.rev=nil,0
A:CheckRecoveryRoster();A:TickRecovery()
token=last('recoveryProbe').packet.token
inbound(backup,{kind='recoveryOffer',sid='original',token=token,rev=12,complete=true})
now=now+6;A:TickRecovery()
assert(last('recoveryFetch').target==backup and A.recoveryHasNewer)
inbound(backup,{kind='recoveryState',sid='original',token=token,rev=12,state=live})
assert(A.state.leader==leader and A.rev==13 and not A.recoveryPending)

-- The former leader cannot revive a retained session after it was superseded.
A.me,A.leader,A.state,A.rev=leader,leader,A.Copy(live),12
A.recoveryPending=true
A:CheckRecoveryRoster();A:TickRecovery()
token=last('recoveryProbe').packet.token
inbound(peer,{kind='recoveryOffer',sid='original',token=token,rev=13,superseded=true})
now=now+6;A:TickRecovery()
assert(A.recoveryPending and A.recoveryFailed=='original' and A.rev==12)

-- Backup cannot offer a newer public version with stale ballot data.
A.me,A.leader,A.state,A.rev=backup,leader,A.Copy(public),13
A.recoveryBallots=backupBallots
A.state.items[1].ballotVersion=8
assert(not A:RecoveryCopy())

-- The crown can stay on a disconnected character. The nominated backup
-- must be an actual, currently promoted assistant and never outranks the ML.
local assistant='Assistant-Forever'
local online={raid1=false,raid2=true,raid3=true,raid4=true}
local rank={raid1=2,raid2=0,raid3=1,raid4=1}
function UnitIsConnected(unit) return online[unit] end
function UnitIsGroupAssistant(unit) return rank[unit]==1 end
function GetRaidRosterInfo(index) return nil,rank['raid'..index] end
A:EndRecovery()
A.me,A.gameLeader,A.leader=assistant,leader,leader
A.roster[assistant]='raid4'
A.state,A.rev=A.Copy(public),12
A.state.recoveryAssistant=assistant
assert(A:IsRaidAssistant(assistant) and not A:IsRaidAssistant(leader))
UnitIsGroupAssistant=nil
assert(A:IsRaidAssistant(assistant) and not A:IsRaidAssistant(backup))
A:RefreshRecoveryAuthority();A:CheckRecoveryRoster()
assert(A.leader==backup and A.recoveryPending and not A:CanTakeOverSession())
A.me=backup
assert(A:CanTakeOverSession())
A.me=assistant
online.raid2=nil
A:RefreshRecoveryAuthority();A:CheckRecoveryRoster()
assert(A.leader==leader and A.recoveryPending and not A:CanTakeOverSession())
online.raid2=false
rank.raid4=0
A:RefreshRecoveryAuthority();A:CheckRecoveryRoster()
assert(A.leader==leader and A.recoveryPending and not A:CanTakeOverSession())
rank.raid4=1
A:RefreshRecoveryAuthority();A:CheckRecoveryRoster()
assert(A.leader==assistant and A.recoveryPending and A:CanTakeOverSession() and not A.recovery)
assert(not A:HostRequest(assistant,{op='end',sid='original'}))

-- The chosen assistant's ballots arrive privately from the original host.
A:EndRecovery()
A.leader=leader
inbound(leader,ballotPacket.packet,'WHISPER')
assert(A:RecoveryCopy().items[1].ballots[backup].choices[peer])
A:RefreshRecoveryAuthority();A:CheckRecoveryRoster()
function A:ReadGameMaster() return backup,'game' end
assert(A:TakeOverSession())
A:TickRecovery()
local assistantProbe=last('recoveryProbe').packet
now=now+6;A:TickRecovery()
local delegated=A:PublicState()
assert(delegated.leader==assistant and delegated.delegatedHost and A:IsMaster())
assert(delegated.master==assistant and delegated.masterSource=='recovery')
assert(A:ReadGameMaster()==backup and not A:IsGameLeader())
assert(A.rev==13 and delegated.trackedLoot[1].holder==backup)
assert(delegated.items[1].responseDeadline==1160 and not delegated.lootConfiguration.automatic)

-- A participant accepts the linked recovery snapshot and keeps the host
-- when the crown reconnects. A delayed view from the former host is ignored.
A:EndRecovery()
A.me,A.leader,A.state,A.rev=peer,leader,A.Copy(public),12
A.state.recoveryAssistant=assistant
A:RefreshRecoveryAuthority();A:CheckRecoveryRoster()
inbound(assistant,assistantProbe,'RAID')
online.raid1=true
A:RefreshRecoveryAuthority();A:CheckRecoveryRoster()
inbound(assistant,{kind='view',full=true,rev=13,state=delegated},'RAID')
assert(A.leader==assistant and A.state.id==delegated.id and not A.recoveryPending)
A:RefreshRecoveryAuthority()
inbound(leader,{kind='view',full=true,rev=30,state=public},'RAID')
assert(A.leader==assistant and A.state.id==delegated.id)

-- A returning or joining client requires both host and independent witness.
A:EndRecovery()
A.me,A.leader,A.state,A.rev=leader,leader,nil,0
A:LocateRecoveryHost()
local locate=last('recoveryLocate').packet.token
local offer={kind='recoveryHost',token=locate,sid=delegated.id,host=assistant}
inbound(peer,offer)
assert(A.leader==leader)
inbound(assistant,offer)
assert(A.leader==assistant and A.recoveryPending)
inbound(assistant,{kind='view',full=true,rev=13,state=delegated},'RAID')
assert(A.state.id==delegated.id and A.leader==assistant and not A.recoveryPending)

-- The same on-demand check reports the actual game role, the guild's
-- council members and whether a private backup matches the active revision.
A:EndRecovery()
A.me,A.leader,A.state,A.rev=leader,leader,nil,0
SanguineLootCouncilDB.raidSetup={council={[peer]=true,['Absent-Forever']=true},recoveryAssistant=assistant}
local master,council,present,total,selected,assistantText=A:LootCheckRoles()
assert(master==backup..' (offline)' and council[backup] and present==1 and total==3)
assert(selected==assistant and assistantText:find('online, promoted',1,true))
assert(A:LootCheckRecoveryStatus()=='Available after session start')

A.state,A.rev=A.Copy(live),12
A.state.recoveryAssistant=assistant
function A:RenderAddonCheck() end
assert(A:BeginAddonCheck())
local presenceProbe=last('presenceProbe').packet
local check=A.addonCheck
A.me,A.state=assistant,A:PublicState()
inbound(leader,presenceProbe,'RAID')
assert(last('presenceReply').packet.recoveryRev==nil)
inbound(leader,ballotPacket.packet,'WHISPER')
assert(A:HasRecoveryBallots())
now=now+3
inbound(leader,presenceProbe,'RAID')
local proof=last('presenceReply').packet
assert(proof.recoveryRev==12 and proof.items==nil)

A.me,A.state,A.addonCheck=leader,A.Copy(live),check
A.state.recoveryAssistant=assistant
inbound(assistant,proof)
assert(A:LootCheckRecoveryStatus()=='Verified on '..assistant)
A.rev=13
assert(A:LootCheckRecoveryStatus()=='Unconfirmed for the current session revision')
A.rev=12
rank.raid4=0
assert(A:LootCheckRecoveryStatus()=='Unconfirmed for the current session revision')
rank.raid4=1
online.raid4=false
assert(A:LootCheckRecoveryStatus()=='Unconfirmed for the current session revision')
online.raid4=true
proof.wire=A.protocol-1
inbound(assistant,proof)
assert(A:AddonMemberStatus(assistant)=='Version mismatch')
assert(A:LootCheckRecoveryStatus()=='Unconfirmed for the current session revision')

-- Announcements are sent by the host for committed actions only.
local chat={}
C_ChatInfo={SendChatMessage=function(text,channel)
    assert(channel=='RAID' and #text<=255)
    chat[#chat+1]=text
end}
local itemLink='|Hitem:123:0|h[Council Blade]|h'
local cfg=A:DefaultLootConfiguration()
A.state={id='announce',leader=leader,master=backup,council={},trackedLoot={},items={},lootSequences={},
    responseDuration=75,responseOptions=A:DefaultResponses(),rules=A:DefaultVoting(),lootConfiguration=cfg}
A.me,A.leader=leader,leader
local function action(sender,p)
    p.sid=A.state.id
    return A:HostRequest(sender,p)
end
assert(not A:AnnouncementSettings().tracked and A:AnnouncementSettings().responses and A:AnnouncementSettings().awards)
local function add(id)
    return action(backup,{op='bagLoot',guid='Item-Chat-'..id,link=itemLink,sampledAt=A.Client:ServerTime(),kind='timed',seconds=999})
end
assert(add(1) and #chat==0)
assert(not action(peer,{op='announcementSetting',key='tracked',enabled=true}))
assert(action(leader,{op='announcementSetting',key='tracked',enabled=true}))
assert(add(2) and #chat==1 and chat[1]:find('Tracked for council',1,true))
assert(add(2) and #chat==1)
assert(action(leader,{op='announcementSetting',key='tracked',enabled=false}))
for i=3,12 do assert(add(i)) end
local selected={}
for _,row in ipairs(A.state.trackedLoot) do selected[#selected+1]={tracked=row.id,guid=row.guid} end
function A:RefreshClassAutoPasses() end
function A:SeedSoloTestResponses() end
assert(action(backup,{op='queueLoot',entries=selected,release=true}))
assert(#chat==2 and chat[2]:find('75 seconds',1,true) and chat[2]:find('and ',1,true))
assert(not action(backup,{op='queueLoot',entries=selected,release=true}) and #chat==2)
local item=A.state.items[1]
item.status='closed'
item.responses={[peer]={choice=1},[backup]={choice=1}}
assert(action(backup,{op='award',item=item.id,target=peer}))
assert(#chat==3 and chat[3]:find('awarded to '..peer,1,true))
assert(action(backup,{op='correctAward',item=item.id,target=backup,expectedRevision=1,expectedWinner=peer,reason='Correction'}))
assert(#chat==4 and chat[4]:find('Award corrected',1,true))
assert(not action(backup,{op='correctAward',item=item.id,target=backup,expectedRevision=1,expectedWinner=peer,reason='Retry'}))
assert(#chat==4)
assert(action(leader,{op='announcementSetting',key='responses',enabled=false}))
assert(action(backup,{op='open',item=A.state.items[2].id}) and #chat==4)
A:Changed();A:Publish();assert(#chat==4)
A.demo=true
assert(not A:LiveAnnouncementSettings('award'))
''')
print('Recovery passed: leader reload and promotion, takeover priority, assistant detection, reconnect, ballot privacy, and pending trades.')
