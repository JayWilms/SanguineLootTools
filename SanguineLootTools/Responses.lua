local _, A = ...

function A:ValidResponseDuration(value)
    return type(value) == "number" and value % 1 == 0 and (value >= 5 and value <= 600)
end

-- The leader uses the same class test that hides unusable items locally.
-- Unknown data is never a reason to pass, and explicit replies are preserved.
function A:RefreshClassAutoPasses(item,apply)
    if not item or (item.status~="open" and item.status~="closed") then return 0 end
    local count=0
    local details
    for name in pairs(item.responseMembers or {}) do
        local response=item.responses[name]
        if self.roster[name] and (not response or response.autoPass) then
            details = details or self:ItemDetails(item)
            local status=self:ClassEligibility(item,name,details)
            if status=="Restricted" and not response then
                count=count+1
                if apply then
                    self:ApplyResponse(item,name,6,"Auto pass: class restriction.",nil)
                    item.responses[name].autoPass=true
                    if item.noResponse then item.noResponse[name]=nil end
                end
            elseif status=="Eligible" and response and response.autoPass then
                count=count+1
                if apply then
                    item.responses[name]=nil;item.ballotVersion=(item.ballotVersion or 0)+1
                    if item.status=="closed" then item.noResponse=item.noResponse or {};item.noResponse[name]=true end
                end
            end
        end
    end
    return count
end

function A:StartResponses(item)
    item.responseOptions=item.responseOptions or self.Copy(self:ResponseOptions())
    self:ResetBallot(item)
    item.responseRound = (item.responseRound or 0) + 1
    item.responses = {}
    item.responseDuration = self:ValidResponseDuration(self.state.responseDuration) and self.state.responseDuration or 60
    item.responseDeadline = item.responseDuration > 0 and (A.Client:ServerTime() + item.responseDuration) or false
    item.responseMembers, item.noResponse, item.responseCloseReason = {}, {}, false
    for name in pairs(self.roster) do item.responseMembers[name] = true end
    item.status = "open"
    self:StartBallot(item)
    self:RefreshClassAutoPasses(item,true)
end

function A:FinishResponses(item, reason)
    self:RefreshClassAutoPasses(item,true)
    item.status, item.responseCloseReason = "closed", reason
    item.noResponse = {}
    for name in pairs(item.responseMembers or {}) do
        if not item.responses[name] then item.noResponse[name] = true end
    end
    item.deadline = false -- No final voting deadline: award finalises the decision.
end

function A:ApplyResponse(item, player, choice, note, equipment)
    local old = item.responses[player]
    if old and old.choice == choice and old.note == note and self:SameEquipment(old.equipment, equipment) then return end
    item.responses[player] = {choice = choice, note = note, revision = (old and old.revision or 0) + 1,
        equipment = equipment, equipmentAt = equipment and A.Client:ServerTime() or nil}
    item.ballotInvalidations = item.ballotInvalidations or {}
    for voter, ballot in pairs(item.ballots) do
        if ballot.choices[player] then
            item.ballots[voter] = nil
            item.ballotInvalidations[voter] = "Ballot cleared: " .. player .. " changed their response or equipped-item snapshot. Review and submit again."
        end
    end
    item.ballotVersion = item.ballotVersion + 1
end

function A:TrackResponseMembers()
    if not self.state then return end
    for _, item in ipairs(self.state.items) do
        if item.status == "open" then
            item.responseMembers = item.responseMembers or {}
            for name in pairs(self.roster) do item.responseMembers[name] = true end
            self:RefreshClassAutoPasses(item,true)
        end
    end
end

function A:TickResponses()
    if not self:IsLeader() or not self.state then return end
    for _,item in ipairs(self.state.items) do
        if self:RefreshClassAutoPasses(item,false)>0 then
            self:HostRequest(self.me,{op="classAutoPass",sid=self.state.id})
            break
        end
    end
    for _, item in ipairs(self.state.items) do
        if item.status == "open" and item.responseDeadline and A.Client:ServerTime() >= item.responseDeadline then
            self:HostRequest(self.me, {op = "expireResponses", sid = self.state.id, item = item.id})
        end
    end
end

-- Smooth interpolation between whole-second server samples. Authority still uses server time.
function A:ResponseClock()
    local wall, localTime = A.Client:ServerTime(), A.Client:Uptime()
    if self.responseWall ~= wall or not self.responseSample then
        self.responseWall, self.responseSample = wall, localTime
    end
    return wall + math.max(0, math.min(0.999, localTime - self.responseSample))
end

function A:ResponseRemaining(item)
    if not item or item.status ~= "open" or not item.responseDeadline then return 0 end
    return math.max(0, math.min(item.responseDuration or 60, item.responseDeadline - self:ResponseClock()))
end

function A:RenderResponseTimer()
    if not self.ui then return end
    local u, item = self.ui, self.state and self:ItemByID(self.popupItem or 0)
    local noteBytes=u.note and #u.note:GetText() or 0
    if u.noteBytes then
        u.noteBytes:SetText(noteBytes.."/100")
        u.noteBytes:SetTextColor(noteBytes>100 and 1 or 0.8,noteBytes>100 and 0.2 or 0.8,0.6)
    end
    local timed = item and item.responseDeadline and (item.responseDuration or 0) > 0
    local remaining = timed and self:ResponseRemaining(item) or 0
    local open = item and item.status == "open" and (not timed or A.Client:ServerTime() < item.responseDeadline)
    u.responseBar:SetMinMaxValues(0, timed and item.responseDuration or 1)
    u.responseBar:SetValue(remaining)
    if not item then
        u.responseCountdown:SetText("Waiting for loot")
    elseif item.status ~= "open" then
        u.responseCountdown:SetText(item.responseCloseReason == "timer" and "0s — response time expired" or "Responses closed")
    elseif timed then
        u.responseCountdown:SetText(math.ceil(remaining) .. "s remaining")
    else u.responseCountdown:SetText("No time limit — master looter closes responses") end
    if not open then u.responseBar:SetStatusBarColor(0.35, 0.35, 0.38)
    elseif timed and remaining <= 10 then u.responseBar:SetStatusBarColor(0.85, 0.15, 0.15)
    elseif timed and remaining <= 20 then u.responseBar:SetStatusBarColor(0.95, 0.6, 0.1)
    else u.responseBar:SetStatusBarColor(0.65, 0.12, 0.18) end
    if not self.Client:ClockReady() then u.responseCountdown:SetText("Client clocks unavailable — responses disabled") end
    if open and A.Client:Combat() then u.responseCountdown:SetText("Combat: responses unavailable — reopen after combat if needed") end
    for _, button in ipairs(u.responseButtons) do button:SetEnabled(open == true and not A.Client:Combat() and noteBytes<=100 and self.Client:ClockReady() and button.choice~=nil) end
end
