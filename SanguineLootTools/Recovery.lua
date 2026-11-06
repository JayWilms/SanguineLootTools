local _, A = ...

local function revision(value)
    return type(value) == "number" and value >= 0 and value <= 1000000000 and value % 1 == 0
end

function A:IsRaidAssistant(name)
    local unit = name and self.roster[name]
    local index = unit and tonumber(unit:match("^raid(%d+)$"))
    if not index or name==self.gameLeader then return false end
    local ok, assistant = self.Client:Call("UnitIsGroupAssistant", unit)
    if ok and (assistant==true or assistant==false or assistant==0 or assistant==1) then
        return assistant==true or assistant==1
    end
    local available, _, rank = self.Client:Call("GetRaidRosterInfo", index)
    return available and rank==1
end

function A:RecoveryOnline(name)
    if not name or not self.roster[name] then return false end
    if name==self.me then return true end
    local ok, connected = self.Client:Call("UnitIsConnected", self.roster[name])
    if ok and (connected==true or connected==1) then return true end
    if ok and (connected==false or connected==0) then return false end
end

-- The crown is still the starting authority. Once delegated, an online
-- session host keeps control even if the original raid leader reconnects.
function A:RefreshRecoveryAuthority()
    local s = self.state
    if not s or s.groupTest or self.demo or not self.Client:InRaid() then return end
    local leader, waiting, manual = s.leader
    local crown = self.gameLeader
    if crown and crown~=s.leader and not s.delegatedHost then
        leader, waiting = crown, true
    elseif self:RecoveryOnline(s.leader)==false then
        waiting = true
        local crownOnline
        if crown and crown~=s.leader then crownOnline=self:RecoveryOnline(crown) else crownOnline=false end
        if crownOnline==true then
            leader = crown
        elseif crownOnline==false then
            local master = not s.masterBlocked and s.master
            if s.masterSource=="recovery" then master=self:ReadGameMaster() end
            if master and master~=s.leader and self:RecoveryOnline(master)==true then
                leader, manual = master, true
            elseif (not master or master==s.leader or self:RecoveryOnline(master)==false)
                and s.recoveryAssistant~=s.leader and self:IsRaidAssistant(s.recoveryAssistant)
                and self:RecoveryOnline(s.recoveryAssistant)==true then
                leader, manual = s.recoveryAssistant, true
            end
        end
    end
    self.leader = leader
    self.manualRecovery = manual
    if waiting and not self.recoveryPending then
        self.recoveryPending = true
        self:ResetTestTransport()
        self:Print("The loot session host is unavailable. Loot actions are paused.")
    end
    if waiting and self.recovery and not self:IsLeader() then self.recovery=nil end
    if not waiting and self.offlineRecovery then
        self.recovery, self.recoveryFailed, self.recoveryPending = nil, nil, nil
    end
    self.offlineRecovery = waiting
end

function A:CanTakeOverSession()
    return self.state and self.manualRecovery and self:IsLeader() and not self.recovery
end

function A:TakeOverSession()
    self:RefreshRecoveryAuthority()
    if not self:CanTakeOverSession() then
        self:Print("The takeover is available to the first eligible backup while the session host is offline.")
        return false
    end
    local s = self.state
    self.recoveryFailed = nil
    self:BeginRecovery(s.id, s.leader, s.recoveryBackup)
    self:Render()
    return true
end

function A:IsRecoveryBackup(s, name)
    return name and (s.recoveryBackup==name or (s.recoveryAssistant==name and self:IsRaidAssistant(name)))
end

function A:ChooseRecoveryBackup()
    local s = self.state
    if not s or s.groupTest then return end
    local function eligible(name)
        return name and name ~= self.me and self.roster[name] and self:IsCouncilMember(name)
    end
    local backup = eligible(s.master) and s.master or nil
    if not backup and eligible(s.recoveryBackup) then backup=s.recoveryBackup end
    if not backup then
        for name in pairs(s.council) do
            if eligible(name) and (not backup or name < backup) then backup = name end
        end
    end
    s.recoveryBackup = backup
end

function A:SendRecoveryBallots()
    local s = self.state
    if not s or self.demo or self.recoveryPending or not self:IsLeader() then return end
    self.sentRecoveryBallots = self.sentRecoveryBallots or {}
    local items, targets
    targets = {}
    if s.recoveryBackup then targets[s.recoveryBackup] = true end
    if self:IsRaidAssistant(s.recoveryAssistant) then targets[s.recoveryAssistant] = true end
    for target in pairs(self.sentRecoveryBallots) do
        if not targets[target] then self.sentRecoveryBallots[target]=nil end
    end
    for target in pairs(targets) do
        local last = self.sentRecoveryBallots[target]
        if target~=self.me and self:RecoveryOnline(target)~=false and
            (not last or last.sid~=s.id or last.rev~=self.rev or self.Client:Uptime()-last.at>=30) then
            if not items then
                items = {}
                for _, item in ipairs(s.items) do
                    items[item.id] = {version=item.ballotVersion, ballots=item.ballots,
                        closed=item.closedResults, invalidations=item.ballotInvalidations}
                end
            end
            if self:Send({kind="recoveryBallots", sid=s.id, rev=self.rev, items=items}, target, {key="recoveryBallots:"..target}) then
                self.sentRecoveryBallots[target] = {sid=s.id, rev=self.rev, at=self.Client:Uptime()}
            end
        end
    end
end

-- The host retains authoritative ballots. A designated backup can combine its
-- public view with the private fields only when every item version matches.
function A:HasRecoveryBallots()
    local s, backup = self.state, self.recoveryBallots
    if not s or s.groupTest or not self:IsRecoveryBackup(s,self.me) or not backup or backup.sid~=s.id then return false end
    for _, item in ipairs(s.items) do
        local row = backup.items[item.id]
        if type(row)~="table" or row.version~=item.ballotVersion or type(row.ballots)~="table" then return false end
    end
    return true
end

function A:RecoveryCopy()
    local s = self.state
    if not s or s.groupTest or (s.leader~=self.me and not self:HasRecoveryBallots()) then return end
    local backup = self.recoveryBallots
    local copy = self.Copy(s)
    for _, item in ipairs(copy.items) do
        if s.leader ~= self.me then
            local row = backup.items[item.id]
            item.ballots, item.closedResults, item.ballotInvalidations = self.Copy(row.ballots), self.Copy(row.closed), self.Copy(row.invalidations)
        end
        item.progress = nil
    end
    return copy
end

function A:BeginRecovery(sid, previous, backup, saved)
    local state=self.state or (saved and saved.state)
    self.recoveryPending = true
    self.recovery = {sid=sid, previous=previous, backup=backup, saved=saved, offers={},
        assistant=state and state.recoveryAssistant, manual=self.manualRecovery,
        token=tostring(self.Client:ServerTime())..":"..math.random(100000,999999)}
end

function A:CheckRecoveryRoster()
    if not self.Client:InRaid() or self.demo then
        self:EndRecovery()
        return
    end
    local s = self.state
    if s and self.leader ~= s.leader then
        self.recoveryPending = true
        if not self:IsLeader() then self.recovery = nil
        elseif not self.manualRecovery and self.recoveryFailed~=s.id and (not self.recovery or self.recovery.sid ~= s.id) then
            self:BeginRecovery(s.id, s.leader, s.recoveryBackup)
        end
    elseif s and self:IsLeader() and self.recoveryPending and not self.offlineRecovery then
        -- The original leader may have missed a completed handoff. Confirm
        -- the retained view with a peer before giving it authority again.
        if not self.recovery and self.recoveryFailed~=s.id then
            self:BeginRecovery(s.id, s.leader, s.recoveryBackup)
            self.recovery.requirePeer=true
        end
    elseif s and self.recoveryPending and not self.recoveryProbeSeen and not self.offlineRecovery then
        self:EndRecovery()
    elseif not s and self:IsLeader() and not self.recovery and self:RecoveryAvailable() then
        local saved = SanguineLootCouncilDB.checkpoints[self.me]
        if saved.protocol~=self.protocol or self.recoveryFailed==saved.state.id then return end
        for name in pairs(saved.members or {}) do
            if name ~= self.me and self.roster[name] then
                self:BeginRecovery(saved.state.id, self.me, saved.state.recoveryBackup, saved)
                break
            end
        end
    end
end

function A:EndRecovery()
    self.recovery, self.recoveryPending, self.recoveryFailed, self.recoveryBallots = nil, nil, nil, nil
    self.recoveryHasNewer, self.recoveryProbeSeen = nil, nil
    self.offlineRecovery, self.manualRecovery, self.recoveryClaim = nil, nil, nil
end

function A:CompleteRecovery(state, rev)
    if self.state and self.offlineRecovery then
        self:RefreshRecoveryAuthority()
        if not self.recovery or not self:IsLeader() then return false end
    end
    self:EndRecovery()
    self:ResetTestTransport()
    return self:RestoreSession({state=state, rev=rev, protocol=self.protocol}, true)
end

function A:TickRecovery()
    local r = self.recovery
    if not r or not self:IsLeader() or self.Client:Combat() or not self.Client:ClockReady() then return end
    local now = self.Client:Uptime()
    if not r.untilAt then
        if self:Send({kind="recoveryProbe", sid=r.sid, token=r.token}, nil, {liveResponse=true}) then r.untilAt=now+6 end
        return
    end
    if now < r.untilAt then return end
    if not r.source then
        local newest = self.state and self.rev or (r.saved and r.saved.rev or 0)
        local localCopy = self:RecoveryCopy()
        local ownRev = localCopy and self.rev or (r.saved and r.saved.rev)
        local source, sourceRev
        for name, offer in pairs(r.offers) do
            if self.roster[name] then
                newest = math.max(newest, offer.rev)
                if r.saved and offer.rev>r.saved.rev then self.recoveryHasNewer=true end
                if offer.complete and (name==r.backup or name==r.previous or (name==r.assistant and self:IsRaidAssistant(name))) and (not sourceRev or offer.rev > sourceRev) then
                    source, sourceRev = name, offer.rev
                end
            end
        end
        if ownRev == newest and not r.superseded and not r.hostOnline and (localCopy or r.saved)
            and (next(r.offers) or (localCopy and not r.requirePeer)) then
            return self:CompleteRecovery(localCopy or r.saved.state, newest)
        end
        if source and sourceRev == newest and not r.superseded and not r.hostOnline then
            if self:Send({kind="recoveryFetch", sid=r.sid, token=r.token, rev=newest}, source, {liveResponse=true}) then
                r.source, r.rev, r.untilAt = source, newest, now+60
            end
            return
        end
    end
    -- Remain frozen after a failed handoff. The leader can retry or end the
    -- session explicitly. A reload with no peer evidence keeps manual Resume.
    self.recoveryFailed = r.sid
    self.recovery = nil
    if not self.state then self.recoveryPending = nil end
    self:Print("Automatic recovery could not verify the latest session. Use /slt sync to retry.")
    if self.Render then self:Render() end
end

function A:RetryRecovery()
    if not self:IsLeader() or not self.recoveryFailed then return false end
    local failed = self.recoveryFailed
    self.recoveryFailed = nil
    if self:CanTakeOverSession() then return self:TakeOverSession() end
    self:CheckRecoveryRoster()
    if not self.recovery then self.recoveryFailed = failed; return false end
    return true
end

function A:RecoveryTransportPeer(sender)
    return self.recovery and self.recovery.source == sender and self:IsLeader()
end

-- Clients without a snapshot discover a delegated host through two distinct
-- roster senders: the host and a peer already following that exact session.
function A:LocateRecoveryHost()
    local now=self.Client:Uptime()
    if not self.Client:InRaid() or self.state or (self.recoveryLocate and now<self.recoveryLocate.untilAt) then return end
    if self.locatedRecovery then
        if now<self.locatedRecovery.untilAt and self:RecoveryOnline(self.locatedRecovery.sender)==true then return end
        self.locatedRecovery=nil
        self.recoveryPending=nil
        self.leader=self.gameLeader or nil
    end
    local token=tostring(self.Client:ServerTime())..":"..math.random(100000,999999)
    if self:Send({kind="recoveryLocate",token=token},nil,{liveResponse=true}) then
        self.recoveryLocate={token=token,untilAt=now+10,offers={}}
    end
end

function A:RecoveryLocatePacket(sender,p,channel)
    if type(p.token)~="string" or #p.token>48 then return end
    local s,now=self.state,self.Client:Uptime()
    if p.kind=="recoveryLocate" then
        if channel~="RAID" or not s or not s.delegatedHost or self.recoveryPending or self:RecoveryOnline(s.leader)~=true then return end
        self.recoveryLocateReplies=self.recoveryLocateReplies or {}
        if (self.recoveryLocateReplies[sender] or -10)+10>now then return end
        self.recoveryLocateReplies[sender]=now
        self:Send({kind="recoveryHost",token=p.token,sid=s.id,host=s.leader},sender,{liveResponse=true})
        return
    end
    local locate=self.recoveryLocate
    if channel~="WHISPER" or s or not locate or now>=locate.untilAt or p.token~=locate.token
        or type(p.sid)~="string" or #p.sid>80 or type(p.host)~="string"
        or self:RecoveryOnline(p.host)~=true then return end
    if p.host==self.me then
        local saved=SanguineLootCouncilDB and SanguineLootCouncilDB.checkpoints and SanguineLootCouncilDB.checkpoints[self.me]
        if sender~=self.me and saved and saved.protocol==self.protocol and saved.state.delegatedHost
            and saved.state.id==p.sid and not self.recovery then
            self.leader=self.me
            if self:RecoveryAvailable() then
                self.recoveryLocate=nil
                self:BeginRecovery(p.sid,self.me,saved.state.recoveryBackup,saved)
            else self.leader=self.gameLeader or nil end
        end
        return
    end
    local key=p.host..":"..p.sid
    local offer=locate.offers[key] or {}
    locate.offers[key]=offer
    if sender==p.host then offer.host=true else offer.witness=true end
    if offer.host and offer.witness then
        self.recovery=nil
        self.recoveryPending=true
        self.recoveryHasNewer=true
        self.locatedRecovery={sender=p.host,sid=p.sid,untilAt=now+120}
        self.recoveryLocate=nil
        self.leader=p.host
        self.lastSync=nil
        self:RequestSync()
    end
end

function A:RecoveryViewPeer(sender)
    local match=self.state and self.recoveryClaim or self.locatedRecovery
    if match and match.sender==sender and self.Client:Uptime()<match.untilAt then return match end
end

function A:RecoveryPacket(sender, p, channel)
    local kind, s, r = p.kind, self.state, self.recovery
    if kind=="recoveryLocate" or kind=="recoveryHost" then
        self:RecoveryLocatePacket(sender,p,channel)
    elseif kind == "recoveryBallots" then
        if channel=="WHISPER" and sender==self.leader and s and not self.demo
            and p.sid==s.id and self:IsRecoveryBackup(s,self.me) and type(p.items)=="table" and revision(p.rev) then
            local previous=self.recoveryBallots
            if not previous or previous.sid~=p.sid or p.rev>=previous.rev then
                self.recoveryBallots = {sid=p.sid, rev=p.rev, items=p.items}
            end
        end
    elseif kind == "recoveryProbe" or kind == "recoveryFetch" then
        if sender==self.me or not s or s.groupTest
            or type(p.token)~="string" or #p.token>48 then return true end
        if p.sid~=s.id then
            if kind=="recoveryProbe" and (sender==self.leader or sender==self.gameLeader or sender==s.previousHost)
                and (p.sid==s.recoveredFrom or p.sid==s.historyID) then
                self:Send({kind="recoveryOffer", sid=p.sid, token=p.token, rev=self.rev, superseded=true}, sender, {liveResponse=true})
            end
            return true
        end
        if kind=="recoveryProbe" and self:IsLeader() and s.leader==self.me and not self.recoveryPending
            and ((sender==s.master and not s.masterBlocked) or (sender==s.recoveryAssistant and self:IsRaidAssistant(sender))) then
            self:Send({kind="recoveryOffer",sid=s.id,token=p.token,rev=self.rev,hostOnline=true},sender,{liveResponse=true})
            return true
        end
        if sender~=self.leader then return true end
        if kind=="recoveryProbe" then
            if self.manualRecovery and sender~=s.leader then
                self.recoveryClaim={sender=sender,sid=s.id,untilAt=self.Client:Uptime()+90}
            end
            if sender==s.leader then self.recoveryProbeSeen=true end
            if not self.recoveryPending then
                self.recoveryPending=true
                self:Print("The loot session host is recovering the loot session. Loot actions are paused.")
                if self.Render then self:Render() end
            end
            local complete = self:RecoveryCopy() ~= nil
            self:Send({kind="recoveryOffer", sid=s.id, token=p.token, rev=self.rev, complete=complete}, sender, {liveResponse=true})
        elseif channel=="WHISPER" and p.rev==self.rev then
            local copy = self:RecoveryCopy()
            if copy then self:Send({kind="recoveryState", sid=s.id, token=p.token, rev=self.rev, state=copy}, sender, {liveResponse=true}) end
        end
    elseif kind == "recoveryOffer" or kind == "recoveryState" then
        if channel~="WHISPER" or not r or not self:IsLeader() or p.sid~=r.sid or p.token~=r.token or not revision(p.rev) then return true end
        if kind=="recoveryOffer" then
            r.offers[sender] = {rev=p.rev, complete=p.complete==true}
            if r.manual and sender==r.previous and p.hostOnline==true then r.hostOnline=true end
            if p.superseded==true then
                r.superseded=true
                if r.saved then self.recoveryHasNewer=true end
            end
        elseif not r.superseded and not r.hostOnline and r.source==sender and p.rev==r.rev and type(p.state)=="table" and p.state.id==r.sid
            and p.state.leader==r.previous and type(p.state.items)=="table" and #p.state.items<=40
            and type(p.state.trackedLoot)=="table" and #p.state.trackedLoot<=80 and type(p.state.council)=="table" then
            for name, offer in pairs(r.offers) do
                if self.roster[name] and offer.rev>p.rev then return true end
            end
            for _, item in ipairs(p.state.items) do
                if type(item)~="table" or type(item.responses)~="table" or type(item.ballots)~="table" then return true end
            end
            self:CompleteRecovery(p.state, p.rev)
        end
    else return false end
    return true
end
