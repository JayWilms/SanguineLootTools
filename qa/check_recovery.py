from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
LUA = LuaRuntime(unpack_returned_tuples=True)
LUA.execute('''
A={};SlashCmdList={}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
''')
for name in ('Core','Client','Features','Archive','Awards','Voting','ResponseConfig','Responses',
             'LootConfiguration','Warnings','MasterLooter','Recovery','StateDelta','WireCodec','Network'):
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
''')
print('Recovery passed: same-leader reload, leader promotion, ballot privacy, stale copies, deadline, awards and trade holders.')
