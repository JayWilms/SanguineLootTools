local _, A = ...

function A:DefaultVoting()
    return {limit = 1, visibility = "immediate", names = false, changes = true, duration = 0}
end

function A:ValidVoting(r)
    return type(r) == "table" and type(r.limit) == "number" and r.limit % 1 == 0 and r.limit >= 1 and r.limit <= 3
        and (r.visibility == "immediate" or r.visibility == "own" or r.visibility == "closed")
        and type(r.names) == "boolean" and type(r.changes) == "boolean"
        and type(r.duration) == "number" and r.duration % 1 == 0 and (r.duration == 0 or (r.duration >= 15 and r.duration <= 600))
end

function A:VotingLocked()
    if not self.state then return false end
    for _, item in ipairs(self.state.items) do
        if item.status ~= "awarded" and (item.voting == "open" or item.voting == "closed") then return true end
    end
    return false
end

function A:ResetBallot(item)
    item.ballots, item.voting, item.deadline = {}, "idle", false
    item.votingRules, item.votingSelfVotes, item.closedResults = false, false, false
    item.ballotInvalidations = {}
    item.round = (item.round or 0) + 1
    item.ballotVersion = (item.ballotVersion or 0) + 1
end

function A:StartBallot(item)
    local rules = self.state.rules
    item.votingRules, item.votingSelfVotes, item.voting = self.Copy(rules), self.state.selfVotes, "open"
    item.deadline = false -- Voting remains editable until the master looter awards.
end

function A:BallotTotals(item)
    if item.closedResults then return item.closedResults.totals, item.closedResults.names, item.closedResults.progress end
    local totals, names, progress = {}, {}, {eligible = 0, submitted = 0, abstained = 0}
    if not self.state then return totals, names, progress end
    for voter in pairs(self.roster) do
        local ballot = item.ballots and item.ballots[voter]
        if self:IsCouncilMember(voter) or (ballot and ballot.masterVote) then
            progress.eligible = progress.eligible + 1
            if ballot then
                progress.submitted = progress.submitted + 1
                if ballot.abstain then progress.abstained = progress.abstained + 1 end
                for candidate in pairs(ballot.choices or {}) do
                    totals[candidate] = (totals[candidate] or 0) + 1
                    names[candidate] = names[candidate] or {}
                    names[candidate][#names[candidate] + 1] = voter
                end
            end
        end
    end
    for _, voters in pairs(names) do table.sort(voters) end
    return totals, names, progress
end

function A:PrivateVoting(item, viewer)
    local s = self.state
    local result = {ownBallot = false, totals = false, voterNames = false, notice = false}
    if not s then return result end
    local canReview = self:IsCouncilMember(viewer)
    local own = canReview and item.ballots and item.ballots[viewer]
    if own then result.ownBallot = self.Copy(own) end
    result.notice = item.ballotInvalidations and item.ballotInvalidations[viewer] or false
    local rules = item.votingRules or s.rules
    local reveal = item.voting == "closed" or item.status == "awarded" or rules.visibility == "immediate"
        or (rules.visibility == "own" and own ~= nil and own ~= false)
    if canReview and reveal then
        local totals, names = self:BallotTotals(item)
        result.totals = totals
        if rules.names then result.voterNames = names end
    end
    return result
end

function A:VisibleVoting(item)
    if self:IsSoloTest() or self:IsLeader() then return self:PrivateVoting(item, self.me) end
    local v = self.privateVoting and self.privateVoting[item.id]
    if v and self.state and v.sid == self.state.id and v.round == item.round and v.ballotVersion == item.ballotVersion
        and (self:IsCouncil() or self:IsMaster()) then return v end
    return {ownBallot = false, totals = false, voterNames = false}
end

function A:ReduceVoting(sender, p, item)
    local s, r = self.state, item.votingRules or self.state.rules
    if p.op == "openVoting" or p.op == "closeVoting" or p.op == "resetVoting" then
        if sender ~= s.master or (item.status ~= "open" and item.status ~= "closed") then return false, "Only the master looter can manage voting on released items." end
        if p.op == "openVoting" then
            if item.voting ~= "idle" then return false, "Reset the ballot before starting another voting round." end
            self:StartBallot(item)
        elseif p.op == "closeVoting" then
            if item.voting ~= "open" then return false, "Voting is not open." end
            if item.status ~= "closed" then return false, "Close responses before closing voting." end
            self:CloseBallot(item)
        else self:ResetBallot(item) end
    elseif p.op == "expireVoting" then
        if sender ~= self.leader or item.voting ~= "open" or not item.deadline or A.Client:ServerTime() < item.deadline then return false, "Voting deadline has not been reached." end
        self:CloseBallot(item)
    elseif p.op == "vote" or p.op == "abstain" or p.op == "setVote" then
        if not self:IsCouncilMember(sender) or (item.status ~= "open" and item.status ~= "closed") or item.voting ~= "open" then return false, "Only council members can vote on open ballots." end
        if p.round ~= item.round then return false, "The voting round changed. Review this item and submit again." end
        if item.deadline and A.Client:ServerTime() >= item.deadline then return false, "The voting deadline has passed." end
        local old = item.ballots[sender]
        if p.op ~= "setVote" and old and not r.changes then return false, "Your ballot is locked after submission." end
        if p.op == "setVote" then
            local response = type(p.target) == "string" and item.responses[p.target]
            if type(p.selected) ~= "boolean" or not self.roster[p.target] or not response or response.choice == 6
                or p.responseRevision ~= response.revision then return false, "The candidate response changed. Review it and vote again." end
            -- Merge on the leader so rapid clicks for different candidates do not
            -- replace each other while the client waits for acknowledgements.
            p.choices = old and self.Copy(old.choices or {}) or {}
            p.versions = old and self.Copy(old.versions or {}) or {}
            if p.selected then
                if r.limit == 1 then p.choices, p.versions = {}, {} end
                p.choices[p.target], p.versions[p.target] = true, response.revision
            else p.choices[p.target], p.versions[p.target] = nil, nil end
        end
        if p.op == "abstain" then
            item.ballots[sender] = {abstain = true, choices = {}}
        else
            if type(p.choices) ~= "table" or type(p.versions) ~= "table" then return false, "Submit a current candidate selection." end
            local choices, versions, n = {}, {}, 0
            for target, selected in pairs(p.choices) do
                n = n + 1
                if n > r.limit or type(target) ~= "string" or selected ~= true or not self.roster[target]
                    or not item.responses[target] or item.responses[target].choice == 6 then
                    return false, "Invalid candidate selection or vote limit exceeded."
                end
                if target == sender and not item.votingSelfVotes then return false, "Self-voting is disabled by the raid leader." end
                if p.versions[target] ~= item.responses[target].revision then return false, "A candidate response changed. Review it and select again." end
                choices[target] = true
                versions[target] = p.versions[target]
            end
            if n > 0 then item.ballots[sender] = {abstain = false, choices = choices, versions = versions}
            elseif old then item.ballots[sender] = nil
            else return false, "Choose a candidate or Abstain." end
        end
        -- Keep a submitted Master Looter vote after a handoff while its voter remains in the raid.
        if item.ballots[sender] and sender == s.master then item.ballots[sender].masterVote = true end
        item.ballotInvalidations[sender] = nil
    else return false, "Unknown voting action." end
    item.ballotVersion = (item.ballotVersion or 0) + 1
    return true
end

function A:CloseBallot(item)
    local totals, names, progress = self:BallotTotals(item)
    item.closedResults = {totals = totals, names = names, progress = progress}
    item.voting, item.deadline = "closed", false
end

function A:TickVoting()
    if not self:IsLeader() or not self.state then return end
    for _, item in ipairs(self.state.items) do
        if item.voting == "open" and item.deadline and A.Client:ServerTime() >= item.deadline then
            self:HostRequest(self.me, {op = "expireVoting", sid = self.state.id, item = item.id})
        end
    end
end


function A:VotingDraft(item)
    local key = self.state.id .. ":" .. item.id .. ":" .. item.round
    self.voteDrafts = self.voteDrafts or {}
    local draft = self.voteDrafts[key]
    if draft and draft.dirty then
        for name in pairs(draft.choices) do
            if not item.responses[name] or not draft.versions or draft.versions[name] ~= item.responses[name].revision then draft = nil; break end
        end
    end
    if not draft or not draft.dirty then
        local own = self:VisibleVoting(item).ownBallot
        draft = {choices = own and self.Copy(own.choices) or {}, versions = own and self.Copy(own.versions or {}) or {}, dirty = false}
        self.voteDrafts[key] = draft
    end
    return draft
end

function A:VoteForCandidate()
    local item = self.state and self:ItemByID(self.selectedItem or 1)
    local target = self.selectedCandidate
    local response = item and item.responses[target or ""]
    if not item or item.voting ~= "open" or not self:IsCouncil() or not response or response.choice == 6 then return end
    local own = self:VisibleVoting(item).ownBallot
    if target == self.me and not item.votingSelfVotes then self:Print("Self-voting is disabled."); return end
    local selected=not (own and own.choices and own.choices[target])
    self.pendingVotingAdvance=nil
    if selected then self:PrepareVotingAdvance("vote",item,target) end
    if self:Act("setVote", {item = item.id, target = target, responseRevision = response.revision,
        selected = selected})==false then self.pendingVotingAdvance=nil end
end

function A:ToggleDraft()
    local item = self.state and self:ItemByID(self.selectedItem or 1)
    if not item or item.voting ~= "open" or not self:IsCouncil() then return end
    local target = self.selectedCandidate
    if not target or not item.responses[target] or item.responses[target].choice == 6 then return end
    if target == self.me and not self.state.selfVotes then self:Print("Self-voting is disabled."); return end
    local own = self:VisibleVoting(item).ownBallot
    if own and not self.state.rules.changes then self:Print("Your submitted ballot is locked."); return end
    local draft = self:VotingDraft(item)
    if draft.choices[target] then draft.choices[target], draft.versions[target] = nil, nil
    else
        if self.state.rules.limit == 1 then draft.choices, draft.versions = {}, {} end
        local n = 0
        for _ in pairs(draft.choices) do n = n + 1 end
        if n >= self.state.rules.limit then self:Print("Remove a candidate before adding another."); return end
        draft.choices[target] = true
        draft.versions[target] = item.responses[target].revision
    end
    draft.dirty = true
    self:Render()
    self.ui.main:Show()
end

function A:SubmitDraft(abstain, withdraw)
    local item = self.state and self:ItemByID(self.selectedItem or 1)
    if not item then return end
    local draft = self:VotingDraft(item)
    local choices = withdraw and {} or self.Copy(draft.choices)
    self:Act(abstain and "abstain" or "vote", {item = item.id, choices = choices, versions = self.Copy(draft.versions)})
    draft.dirty = false
    self:Render()
end

function A:UpdateVotingRule(key, value)
    local rules = self.Copy(self:RaidSettings().rules)
    rules[key] = value
    self:Act("rules", {rules = rules})
end

function A:CycleVotingCandidate(direction)
    local item = self.state and self:ItemByID(self.selectedItem or 1)
    if not item then return end
    local names = {}
    for name, response in pairs(item.responses) do
        if response.choice ~= 6 and self.roster[name] then names[#names + 1] = name end
    end
    table.sort(names)
    if #names == 0 then return end
    local index = direction > 0 and 0 or 1
    for i, name in ipairs(names) do if name == self.selectedCandidate then index = i end end
    self.selectedCandidate = names[(index - 1 + direction) % #names + 1]
    self:Render()
end

function A:RosterKey()
    local names = {}
    for name in pairs(self.roster) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ";")
end

function A:OnVotingRosterChanged()
    if not self:IsLeader() or not self.state then return end
    local key = self:RosterKey()
    if key == self.publishedRoster then return end
    self:TrackResponseMembers()
    for _, item in ipairs(self.state.items) do
        if item.status ~= "awarded" and item.voting ~= "closed" then
            for voter, ballot in pairs(item.ballots) do
                if not self.roster[voter] or (not self:IsCouncilMember(voter) and not ballot.masterVote) then item.ballots[voter] = nil
                else
                    for candidate in pairs(ballot.choices) do
                        if not self.roster[candidate] then ballot.choices[candidate] = nil end
                    end
                    if not ballot.abstain and not next(ballot.choices) then item.ballots[voter] = nil end
                end
            end
            item.ballotVersion = item.ballotVersion + 1
        end
    end
    self.rev = self.rev + 1
    self:Publish()
    self:PersistSession()
end
