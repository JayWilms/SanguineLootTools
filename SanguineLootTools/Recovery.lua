local _, A = ...

local function revision(value)
    return type(value) == "number" and value >= 0 and value <= 1000000000 and value % 1 == 0
end

function A:ChooseRecoveryBackup()
    local s = self.state
    if not s or s.groupTest then return end
    local function eligible(name)
        return name and name ~= self.me and self.roster[name] and self:IsCouncilMember(name)
    end
    if eligible(s.recoveryBackup) then return end
    local backup = eligible(s.master) and s.master or nil
    if not backup then
        for name in pairs(s.council) do
            if eligible(name) and (not backup or name < backup) then backup = name end
        end
    end
    s.recoveryBackup = backup
end

function A:SendRecoveryBallots()
    local s = self.state
    if not s or self.demo or self.recoveryPending or not self:IsLeader() or not s.recoveryBackup then return end
    local last = self.sentRecoveryBallots
    if last and last.sid == s.id and last.target == s.recoveryBackup and last.rev == self.rev and self.Client:Uptime()-last.at < 30 then return end
    local items = {}
    for _, item in ipairs(s.items) do
        items[item.id] = {version = item.ballotVersion, ballots = item.ballots,
            closed = item.closedResults, invalidations = item.ballotInvalidations}
    end
    if self:Send({kind="recoveryBallots", sid=s.id, rev=self.rev, items=items}, s.recoveryBackup, {key="recoveryBallots"}) then
        self.sentRecoveryBallots = {sid=s.id, target=s.recoveryBackup, rev=self.rev, at=self.Client:Uptime()}
    end
end

-- The host retains authoritative ballots. A designated backup can combine its
-- public view with the private fields only when every item version matches.
function A:RecoveryCopy()
    local s = self.state
    if not s or s.groupTest then return end
    local backup = self.recoveryBallots
    if s.leader ~= self.me and (s.recoveryBackup ~= self.me or not backup or backup.sid ~= s.id) then return end
    for _, item in ipairs(s.items) do
        local row = backup and backup.items[item.id]
        if s.leader ~= self.me and (type(row) ~= "table" or row.version ~= item.ballotVersion or type(row.ballots) ~= "table") then return end
    end
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
    self.recoveryPending = true
    self.recovery = {sid=sid, previous=previous, backup=backup, saved=saved, offers={},
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
        elseif self.recoveryFailed~=s.id and (not self.recovery or self.recovery.sid ~= s.id) then
            self:BeginRecovery(s.id, s.leader, s.recoveryBackup)
        end
    elseif s and self:IsLeader() and self.recoveryPending then
        -- The original leader may have missed a completed handoff. Confirm
        -- the retained view with a peer before giving it authority again.
        if not self.recovery and self.recoveryFailed~=s.id then
            self:BeginRecovery(s.id, s.leader, s.recoveryBackup)
            self.recovery.requirePeer=true
        end
    elseif s and self.recoveryPending and not self.recoveryProbeSeen then
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
end

function A:CompleteRecovery(state, rev)
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
                if offer.complete and (name == r.backup or name == r.previous) and (not sourceRev or offer.rev > sourceRev) then
                    source, sourceRev = name, offer.rev
                end
            end
        end
        if ownRev == newest and not r.superseded and (localCopy or r.saved)
            and (next(r.offers) or (localCopy and not r.requirePeer)) then
            return self:CompleteRecovery(localCopy or r.saved.state, newest)
        end
        if source and sourceRev == newest and not r.superseded then
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
    self:CheckRecoveryRoster()
    if not self.recovery then self.recoveryFailed = failed; return false end
    return true
end

function A:RecoveryTransportPeer(sender)
    return self.recovery and self.recovery.source == sender and self:IsLeader()
end

function A:RecoveryPacket(sender, p, channel)
    local kind, s, r = p.kind, self.state, self.recovery
    if kind == "recoveryBallots" then
        if channel=="WHISPER" and sender==self.leader and s and not self.demo
            and p.sid==s.id and s.recoveryBackup==self.me and type(p.items)=="table" and revision(p.rev) then
            local previous=self.recoveryBallots
            if not previous or previous.sid~=p.sid or p.rev>=previous.rev then
                self.recoveryBallots = {sid=p.sid, rev=p.rev, items=p.items}
            end
        end
    elseif kind == "recoveryProbe" or kind == "recoveryFetch" then
        if sender~=self.leader or sender==self.me or not s or s.groupTest
            or type(p.token)~="string" or #p.token>48 then return true end
        if p.sid~=s.id then
            if kind=="recoveryProbe" and (p.sid==s.recoveredFrom or p.sid==s.historyID) then
                self:Send({kind="recoveryOffer", sid=p.sid, token=p.token, rev=self.rev, superseded=true}, sender, {liveResponse=true})
            end
            return true
        end
        if kind=="recoveryProbe" then
            if sender==s.leader then self.recoveryProbeSeen=true end
            if not self.recoveryPending then
                self.recoveryPending=true
                self:Print("The raid leader is recovering the loot session. Loot actions are paused.")
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
            if p.superseded==true then
                r.superseded=true
                if r.saved then self.recoveryHasNewer=true end
            end
        elseif not r.superseded and r.source==sender and p.rev==r.rev and type(p.state)=="table" and p.state.id==r.sid
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
