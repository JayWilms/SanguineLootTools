local _, A = ...

function A:AwardSnapshot(item)
    local totals = self:BallotTotals(item)
    local response = item.responses[item.winner]
    if not item.awardedAt and SanguineLootCouncilDB then
        local key = (self.state.historyID or self.state.id) .. ":" .. item.id
        for _, old in ipairs(SanguineLootCouncilDB.history or {}) do
            if old.key == key and old.winner == item.winner and old.time then
                return {winner = old.winner, response = old.response or (response and response.choice),responseLabel=old.responseLabel or self:ResponseLabel(old.response or (response and response.choice),item), time = old.time,
                    master = old.master or self.state.master, votes = old.votes or 0, timeSource = old.timeSource or "observed"}
            end
        end
    end
    return {winner = item.winner, response = response and response.choice,responseLabel=item.awardReason or (response and self:ResponseLabel(response.choice,item)),awardReason=item.awardReason,awardNote=item.awardNote,automatic=item.automaticAssignment, time = item.awardedAt or A.Client:ServerTime(),
        master = item.awardedBy or self.state.master, votes = item.awardedVotes or totals[item.winner] or 0,
        timeSource = item.awardedAt and "award" or "observed"}
end

function A:CleanCorrectionReason(reason)
    if type(reason) ~= "string" or #reason > 160 then return nil end
    reason = reason:gsub("[%c|]", " "):match("^%s*(.-)%s*$")
    if reason == "" then return nil end
    return reason
end

function A:ReduceCorrection(sender, p, item)
    if sender ~= self.state.master then return false, "Only the current master looter can correct an award." end
    if item.status ~= "awarded" or item.voting ~= "closed" or not item.winner then return false, "Only a completed award can be corrected." end
    local revision = item.awardRevision or 1
    if p.expectedRevision ~= revision or p.expectedWinner ~= item.winner then return false, "This award changed. Reopen the correction and review the current winner." end
    local target = self:Resolve(p.target)
    if not target or (not item.automaticAssignment and (not item.responses[target] or item.responses[target].choice == 6)) then return false, "Choose a current raid member who requested this item." end
    if target == item.winner then return false, "Choose a different winner to make a correction." end
    local reason = self:CleanCorrectionReason(p.reason)
    if not reason then return false, "Enter a correction reason (1–160 bytes)." end
    if #(item.corrections or {}) >= 10 then return false, "This alpha supports up to 10 corrections per item." end
    item.originalAward = item.originalAward or self:AwardSnapshot(item)
    item.corrections = item.corrections or {}
    local votes = p.awardedVotes
    if votes == nil then votes = self:BallotTotals(item)[target] or 0 end
    item.corrections[#item.corrections + 1] = {
        revision = revision + 1, from = item.winner, to = target, by = sender,
        time = p.awardedAt or A.Client:ServerTime(), reason = reason,
        response = item.responses[target] and item.responses[target].choice,responseLabel=item.awardReason or (item.responses[target] and self:ResponseLabel(item.responses[target].choice,item)), votes = votes,
    }
    item.winner, item.awardRevision = target, revision + 1
    item.awardedAt, item.awardedBy, item.awardedVotes = p.awardedAt or A.Client:ServerTime(), sender, votes
    self:UpdateDeliveryAward(item, true)
    return true
end

-- One stable record per item. Reassignment moves its ownership rather than adding loot.
function A:UpsertAward(item)
    local s = self.state
    if self.demo or not s or not item.winner then return end
    self:InitStorage()
    local key, revision = (s.historyID or s.id) .. ":" .. item.id, item.awardRevision or 1
    local history, index = SanguineLootCouncilDB.history
    for i, record in ipairs(history) do
        if record.key == key then
            if (record.revision or 1) > revision or ((record.revision or 1) == revision and (record.deliveryRevision or 0) >= (item.delivery and item.delivery.revision or 0)) then return end
            index = i; break
        end
    end
    local record = self:AwardSnapshot(item)
    record.delivery, record.deliveryRevision = self.Copy(item.delivery), item.delivery and item.delivery.revision or 0
    record.key, record.item, record.revision = key, item.link, revision
    record.quantity=item.quantity
    record.original = self.Copy(item.originalAward or record)
    record.corrections = self.Copy(item.corrections or {})
    if index then history[index] = record else history[#history + 1] = record end
    table.sort(history, function(a, b)
        if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) > (b.time or 0) end
        return tostring(a.key) < tostring(b.key)
    end)
    while #history > 500 do table.remove(history) end
end

function A:CorrectionCandidates(item)
    local names = {}
    if item.automaticAssignment then
        for name in pairs(self.roster) do if name~=item.winner then names[#names+1]=name end end
        table.sort(names);return names
    end
    for name, response in pairs(item.responses) do
        if name ~= item.winner and response.choice ~= 6 and self.roster[name] then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

function A:OpenCorrection()
    self:BuildUI()
    local item = self.state and self:ItemByID(self.selectedItem or 1)
    if not self:IsMaster() or not item or item.status ~= "awarded" then return end
    local candidates, target = self:CorrectionCandidates(item), self.selectedCandidate
    local valid = false
    for _, name in ipairs(candidates) do if name == target then valid = true end end
    if not valid then target = candidates[1] end
    self:CloseSettingsDropdown()
    self.correctionContext = {sid = self.state.id, item = item.id, expectedRevision = item.awardRevision or 1, expectedWinner = item.winner, target = target}
    self.ui.correctionReason:SetText("")
    self:RenderCorrection()
    self.ui.correction:Show()
end

function A:CorrectionDropdownChoices()
    local c=self.correctionContext
    local item=c and self.state and c.sid==self.state.id and self:ItemByID(c.item)
    local choices={}
    if not self:IsMaster() or not item or item.status~="awarded" or item.winner~=c.expectedWinner
        or (item.awardRevision or 1)~=c.expectedRevision or #(item.corrections or {})>=10 then return choices end
    for _,name in ipairs(self:CorrectionCandidates(item)) do choices[#choices+1]={name,name} end
    return choices
end

function A:SelectCorrectionCandidate(target)
    for _,choice in ipairs(self:CorrectionDropdownChoices()) do
        if choice[2]==target then self.correctionContext.target=target;self:RenderCorrection();return true end
    end
    self:RenderCorrection()
    return false
end

function A:ReviewCorrection()
    local c = self.correctionContext
    local item = c and self.state and c.sid == self.state.id and self:ItemByID(c.item)
    if not self:IsMaster() or not item or item.winner ~= c.expectedWinner or (item.awardRevision or 1) ~= c.expectedRevision then self:Print("Reopen this award correction to review the current state."); return end
    local reason = self:CleanCorrectionReason(self.ui.correctionReason:GetText())
    if not reason then self:Print("Enter a correction reason (1–160 bytes)."); return end
    if not c.target or not self.roster[c.target] or (not item.automaticAssignment and (not item.responses[c.target] or item.responses[c.target].choice == 6)) or c.target == item.winner then self:Print("Choose a different eligible winner."); return end
    local dialog = A:ShowConfirmation("SANGUINELOOTCOUNCIL_CORRECT_AWARD", item.winner, c.target .. "\nReason: " .. reason .. self:AwardEligibilityNotice(item, c.target))
    if dialog then
        dialog.data = self.Copy(c)
        dialog.data.reason = reason
    end
end

-- Response time closes automatically; awarding is the final council decision.
function A:CanAwardCandidate(item,target)
    if not self:IsMaster() or not item or item.status=="awarded" then return false end
    local responsesClosed=item.status=="closed" or (item.status=="open" and item.responseDeadline and A.Client:ServerTime()>=item.responseDeadline)
    local response=target and item.responses[target]
    return responsesClosed and (item.voting=="open" or item.voting=="closed") and response~=nil and response.choice~=6 and self.roster[target]~=nil or false
end

function A:ReviewAward(target)
    local item=self.state and self:ItemByID(self.selectedItem or 1)
    if not self:CanAwardCandidate(item,target) then return end
    local response=item.responses[target]
    local dialog=A:ShowConfirmation("SANGUINELOOTCOUNCIL_AWARD",item.link,target..self:AwardEligibilityNotice(item,target))
    if dialog then
        dialog.data={sid=self.state.id,item=item.id,target=target,expectedRound=item.round,
            expectedResponseRound=item.responseRound,expectedResponseRevision=response.revision}
    end
end

function A:ConfirmAward(context)
    local item=context and self.state and context.sid==self.state.id and self:ItemByID(context.item)
    local response=item and item.responses[context.target]
    if not self:CanAwardCandidate(item,context and context.target) or not response
        or context.expectedRound~=item.round or context.expectedResponseRound~=item.responseRound
        or context.expectedResponseRevision~=response.revision then
        self:Print("The award or your permissions changed. Review the item and winner again.")
        return false
    end
    self:PrepareVotingAdvance("award",item,context.target)
    local accepted=self:Act("award",self.Copy(context))
    if accepted==false then self.pendingVotingAdvance=nil end
    return accepted
end
