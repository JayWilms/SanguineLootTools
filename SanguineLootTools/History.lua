local _, A = ...

-- Counts describe this installation's retained records, never a player's lifetime loot.
function A:PlayerHistory(name)
    self:InitStorage()
    local result = {records = {}, total = 0, week = 0, session = 0}
    if type(name) ~= "string" then return result end
    local prefix = self.state and ((self.state.historyID or self.state.id) .. ":")
    local now, seen = A.Client:ServerTime(), {}
    for _, record in ipairs(SanguineLootCouncilDB.history) do
        if record.winner == name and type(record.key) == "string" and not seen[record.key] then
            seen[record.key] = true
            result.records[#result.records + 1] = record
            result.total = result.total + 1
            if type(record.time) == "number" and record.time <= now and record.time >= now - 7 * 86400 then result.week = result.week + 1 end
            if prefix and record.key:sub(1, #prefix) == prefix then result.session = result.session + 1 end
        end
    end
    table.sort(result.records, function(a, b)
        if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) > (b.time or 0) end
        return a.key < b.key
    end)
    return result
end

function A:PlayerHistoryLabel(name)
    local history = self:PlayerHistory(name)
    local short = name and name:match("^[^-]+") or "Candidate"
    return short .. ": " .. history.session .. " this session | " .. history.week .. " last 7 days | " .. history.total .. " local records", history
end

function A:HistoryWithAudit(name)
    local current = self:PlayerHistory(name)
    local records, seen = {}, {}
    for _, record in ipairs(SanguineLootCouncilDB.history) do
        local involved = record.winner == name or (record.original and record.original.winner == name)
        for _, correction in ipairs(record.corrections or {}) do
            if correction.from == name or correction.to == name then involved = true end
        end
        if involved and type(record.key) == "string" and not seen[record.key] then records[#records + 1] = record; seen[record.key] = true end
    end
    table.sort(records, function(a, b)
        if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) > (b.time or 0) end
        return tostring(a.key) < tostring(b.key)
    end)
    return records, current.total
end

function A:FormatAwardHistory(record, player)
    local lines = {
        (player and record.winner ~= player and "[Corrected away] " or "") .. date("%d %b %Y %H:%M", record.time or 0)
            .. " | " .. tostring(record.winner) .. " | " .. (record.responseLabel or self.responses[record.response] or "Unknown"),
        (record.item or "Unknown item") .. " (" .. (record.votes or 0) .. " votes)" .. (record.timeSource ~= "award" and " [time observed]" or ""),
    }
    if record.awardReason then lines[#lines+1]="Assignment reason: "..record.awardReason..(record.awardNote and record.awardNote~="" and " | "..record.awardNote or "")..(record.automatic and " (quality rule)" or "") end
    if #(record.corrections or {}) > 0 then
        local original = record.original or record
        lines[#lines + 1] = "Original award: " .. date("%d %b %Y %H:%M", original.time or 0) .. " | " .. tostring(original.winner)
            .. " | " .. (original.responseLabel or self.responses[original.response] or "Unknown") .. " | by " .. tostring(original.master) .. " | " .. (original.votes or 0) .. " votes"
        for _, correction in ipairs(record.corrections) do
            lines[#lines + 1] = "Correction " .. (correction.revision - 1) .. ": " .. date("%d %b %Y %H:%M", correction.time)
                .. " | " .. correction.from .. " to " .. correction.to .. " | by " .. correction.by .. "\nReason: " .. correction.reason
        end
    end
    if record.delivery then
        local delivery = record.delivery
        lines[#lines + 1] = "Delivery: " .. delivery.status .. " | Recorded holder: " .. delivery.holder .. (delivery.method=="automatic" and " (game-confirmed trade)" or delivery.method=="masterloot" and " (Master Loot and verified recipient bag)" or " (manual tracking)")
        for _, event in ipairs(delivery.log or {}) do
            lines[#lines + 1] = "Delivery log: " .. date("%d %b %Y %H:%M", event.time) .. " | " .. event.action .. " | by " .. tostring(event.by) .. (event.to and (" | to " .. event.to) or "")
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

function A:RenderCandidateHistory()
    if not self.ui then return end
    self:RenderVotingHistory()
    local u, name = self.ui, self.selectedCandidate
    local item = self.state and self:ItemByID(self.selectedItem or 1)
    local allowed = name and item and item.responses[name] and (self:IsCouncil() or self:IsMaster())
    u.playerHistory:SetEnabled(allowed == true)
    if not allowed then
        u.playerHistoryTitle:SetText("Select a candidate to see their recent recorded awards")
        for _, row in ipairs(u.playerHistoryRows) do row:Hide() end
        return
    end
    if self.demo then
        u.playerHistoryTitle:SetText((self.groupTest and "Group" or "Solo").." test: no real player history is displayed")
        for _, row in ipairs(u.playerHistoryRows) do row:Hide() end
        u.playerHistory:SetEnabled(false)
        return
    end
    local label, history = self:PlayerHistoryLabel(name)
    u.playerHistoryTitle:SetText(label)
    for i, row in ipairs(u.playerHistoryRows) do
        local record = history.records[i]
        row:SetShown(record ~= nil)
        row.record = record
        if record then
            row:SetText(date("%d %b", record.time or 0) .. " | " .. (record.responseLabel or self.responses[record.response] or "Unknown") .. (#(record.corrections or {}) > 0 and " | Corrected" or "") .. " | " .. record.item)
        end
    end
end

function A:BuildVotingHistory(u,parent,text,button)
    local p={rows={},records={}}
    u.votingHistory=p
    p.frame=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    p.frame:SetPoint("TOPLEFT",796,-332);p.frame:SetSize(304,308)
    self:StylePanel(p.frame,24)
    p.title=text(p.frame,"Player loot history",11,10,-9,280)
    self:LayoutTitleText(p.title,10,280,24)
    p.title:SetTextColor(0.86,0.76,0.49)
    p.summary=text(p.frame,"",10,10,-30,280);p.summary:SetMaxLines(1)
    p.scroll=A:CreateScrollFrame(p.frame)
    p.scroll:SetPoint("TOPLEFT",8,-52);p.scroll:SetSize(266,228)
    p.child=CreateFrame("Frame",nil,p.scroll);p.child:SetSize(266,228);p.scroll:SetScrollChild(p.child)
    p.empty=text(p.child,"Select a player to view recorded loot.",11,5,-5,250);p.empty:SetHeight(100)
    p.footer=text(p.frame,"Local records only • newest first",9,10,-290,280)
    -- Reuse fourteen visible/overscan rows even when the record store is full.
    for i=1,14 do
        local row=button(p.child,"",0,0,262,function(self) if self.record then A:ShowAwardAudit(self.record) end end)
        row:SetHeight(44);row:SetNormalTexture("");row:SetPushedTexture("")
        self:StyleDataRow(row,i)
        row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetPoint("TOPLEFT",3,-5);row.icon:SetSize(28,28)
        row.item=text(row,"",10,36,-4,222);row.item:SetHeight(24);row.item:SetMaxLines(2)
        row.detail=text(row,"",9,36,-29,222);row.detail:SetMaxLines(1)
        row:SetScript("OnEnter",function(self)
            if not self.record then return end
            GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetHyperlink(self.record.item)
            GameTooltip:AddLine(date("%d %b %Y %H:%M",self.record.time or 0),1,1,1)
            GameTooltip:AddLine("Click to view award audit.",1,0.8,0.4);GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        p.rows[i]=row
    end
    p.scroll:HookScript("OnVerticalScroll",function(_,offset) A:RenderVotingHistoryRows(offset) end)
end

function A:RenderVotingHistoryRows(offset)
    local p=self.ui and self.ui.votingHistory
    if not p then return end
    if type(offset)~="number" then offset=p.scroll:GetVerticalScroll() end
    if type(offset)~="number" then offset=0 end
    local first=math.floor(math.max(0,offset)/44)+1
    for i,row in ipairs(p.rows) do
        local index=first+i-1;local record=p.records[index]
        row.record=record;row:SetShown(record~=nil)
        if record then
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-(index-1)*44)
            row.icon:SetTexture(self:ItemIcon({link=record.item}))
            row.item:SetText(record.item)
            row.detail:SetText(date("%d %b",record.time or 0).." • "..(record.responseLabel or self.responses[record.response] or "Unknown"))
        end
    end
end

function A:RenderVotingHistory()
    local p=self.ui and self.ui.votingHistory
    if not p then return end
    local name=self.selectedCandidate
    local item=self.state and self:ItemByID(self.selectedItem or 0)
    local allowed=name and item and item.responses[name] and self:CanViewCouncil()
    local key=allowed and (self.state.id..":"..item.id..":"..name) or nil
    local reset=p.key~=key;p.key=key
    p.records=allowed and not self.demo and self:PlayerHistory(name).records or {}
    p.title:SetText(allowed and (self:DisplayName(name).." — Loot history") or "Player loot history")
    p.summary:SetText(allowed and (#p.records.." recorded award"..(#p.records==1 and "" or "s")) or "")
    p.empty:SetText(not allowed and "Select a player to view recorded loot." or (self.demo and ((self.groupTest and "Group" or "Solo").." test: no real player history is displayed.") or "No recorded loot for this player."))
    p.empty:SetShown(#p.records==0)
    p.child:SetHeight(math.max(p.scroll:GetHeight(),#p.records*44))
    local offset=p.scroll:GetVerticalScroll()
    if type(offset)~="number" then offset=0 end
    if reset or offset>math.max(0,#p.records*44-p.scroll:GetHeight()) then p.scroll:SetVerticalScroll(0);offset=0 end
    self:RenderVotingHistoryRows(offset)
end

function A:BuildAuditUI(u,window,text)
    u.awardAudit=window("SanguineLootCouncilAwardAudit","Recorded award audit (read-only)",780,570)
    local scroll=A:CreateScrollFrame(u.awardAudit)
    scroll:SetPoint("TOPLEFT",20,-55);scroll:SetSize(720,475)
    local child=CreateFrame("Frame",nil,scroll);child:SetSize(695,475);scroll:SetScrollChild(child)
    u.auditText=text(child,"",12,0,0,690);u.auditText:SetJustifyV("TOP")
    u.auditChild,u.auditScroll=child,scroll
end
function A:ShowAwardAudit(record)
    if type(record)~="table" then return end
    self:BuildUI()
    self.ui.auditText:SetText(self:FormatAwardHistory(record)..(record.archivedAt and "\nArchived: read-only completed work." or ""))
    self.ui.auditChild:SetHeight(math.max(475,self.ui.auditText:GetStringHeight()+25))
    self.ui.auditScroll:SetVerticalScroll(0);self.ui.awardAudit:Show()
end
