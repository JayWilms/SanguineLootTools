local _, A = ...

-- Older records may have only the displayed assignment reason.
function A:IsGuildBankHistory(record)
    return (record.awardReason or record.responseLabel)=="Guild Bank"
end

-- Counts describe this installation's retained records, never a player's lifetime loot.
function A:PlayerHistory(name)
    self:InitStorage()
    local result = {records = {}, total = 0, week = 0, session = 0}
    if type(name) ~= "string" then return result end
    local prefix = self.state and ((self.state.historyID or self.state.id) .. ":")
    local now, seen = A.Client:ServerTime(), {}
    for _, record in ipairs(SanguineLootCouncilDB.history) do
        if not self:IsGuildBankHistory(record) and record.winner == name and type(record.key) == "string" and not seen[record.key] then
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
    local label = name and self:DisplayName(name) or "Candidate"
    return label .. ": " .. history.session .. " this session | " .. history.week .. " last 7 days | " .. history.total .. " local records", history
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
        (record.item or "Unknown item") .. ((record.quantity or 1)>1 and (" ×"..record.quantity) or "") .. " (" .. (record.votes or 0) .. " votes)" .. (record.timeSource ~= "award" and " [time observed]" or ""),
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
        lines[#lines + 1] = "Delivery: " .. delivery.status .. " | Recorded holder: " .. delivery.holder .. (delivery.method=="automatic" and " (game-confirmed trade)" or delivery.method=="masterloot_native" and " (native Master Loot confirmation; bag GUID unverified)" or delivery.method=="masterloot" and " (Master Loot and verified recipient bag)" or " (manual tracking)")
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
    if not p or self.ui.votingCompactLayout then return end
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
    u.awardAudit=window("SanguineLootCouncilAwardAudit","Recorded award audit (read-only)",620,220)
    local scroll=A:CreateScrollFrame(u.awardAudit)
    scroll:SetPoint("TOPLEFT",20,-55);scroll:SetSize(560,145)
    local child=CreateFrame("Frame",nil,scroll);child:SetSize(535,145);scroll:SetScrollChild(child)
    u.auditText=text(child,"",12,0,0,530);u.auditText:SetJustifyV("TOP")
    u.auditChild,u.auditScroll=child,scroll
end
function A:ShowAwardAudit(record)
    if type(record)~="table" then return end
    self:BuildUI()
    self.ui.auditText:SetText(self:FormatAwardHistory(record)..(record.archivedAt and "\nArchived: read-only completed work." or ""))
    local textHeight=self.ui.auditText:GetStringHeight()
    local height=math.max(160,math.min(340,textHeight+85))
    self.ui.awardAudit:SetSize(620,height)
    self.ui.auditScroll:SetHeight(height-75)
    self.ui.auditChild:SetHeight(math.max(height-75,textHeight+10))
    self.ui.auditScroll:SetVerticalScroll(0);self.ui.awardAudit:Show()
end

-- Search applies only to the history view; canonical records and audits stay intact.
function A:FilterHistoryRecords(player, query, guildBank)
    query=tostring(query or ""):match("^%s*(.-)%s*$")
    local itemID=query:match("item:(%d+)")
    local isDate=query:match("^%d%d/%d%d/%d%d%d%d$")
    local needle=query:lower()
    local records={}
    for _,record in ipairs(SanguineLootCouncilDB.history) do
        local matches=query==""
        if not matches then
            if itemID then
                matches=tostring(record.item or ""):match("item:(%d+)")==itemID
            elseif isDate then
                matches=date("%d/%m/%Y",record.time or 0)==query
            else
                local item=tostring(record.item or "")
                item=item:match("|h%[(.-)%]|h") or item
                matches=tostring(record.winner or ""):lower():find(needle,1,true)~=nil
                    or item:lower():find(needle,1,true)~=nil
            end
        end
        local inScope=self:IsGuildBankHistory(record)==(guildBank==true)
        if inScope and matches and (guildBank==true or not player or record.winner==player) then records[#records+1]=record end
    end
    table.sort(records,function(a,b)
        if (a.time or 0)~=(b.time or 0) then return (a.time or 0)>(b.time or 0) end
        return tostring(a.key)<tostring(b.key)
    end)
    return records
end

local function csvCell(value)
    if value==nil then return "" end
    if type(value)=="number" then return tostring(value) end
    local value=tostring(value)
    -- Spreadsheet programs can interpret formula-like text even inside quotes.
    if value:match("^%s*[=+@%-]") or value:match("^[%c]") then value="'"..value end
    return '"'..value:gsub('"','""')..'"'
end

function A:HistoryCSV(records)
    local lines={"Award Time (UTC),Winner,Item Name,Item ID,Quantity,Response,Votes,Awarded By,Delivery Status,Award ID"}
    for _,record in ipairs(records) do
        local link=record.item or ""
        local itemID=tonumber(link:match("item:(%d+)"))
        local name=link:match("|h%[(.-)%]|h")
        if not name and not itemID and link~="" then name=link end
        lines[#lines+1]=table.concat({
            csvCell(record.time and date("!%Y-%m-%dT%H:%M:%SZ",record.time)),
            csvCell(record.winner),csvCell(name),csvCell(itemID),csvCell(record.quantity or 1),
            csvCell(record.responseLabel or (self.responses or {})[record.response] or record.awardReason),
            csvCell(record.votes),csvCell(record.master),csvCell(record.delivery and record.delivery.status),
            csvCell(record.key),
        },",")
    end
    return table.concat(lines,"\n").."\n"
end

function A:BuildHistoryExportUI(u,window,text,button)
    local frame=window("SanguineLootCouncilHistoryExport","Loot History Export",780,465)
    u.historyExportWindow=frame
    u.historyExportSummary=text(frame,"",12,20,-48,730)
    text(frame,"Press Ctrl+C to copy the CSV, then save it as a .csv file or import it into a spreadsheet.",11,20,-72,730)
    local scroll=self:CreateScrollFrame(frame)
    scroll:SetPoint("TOPLEFT",20,-100);scroll:SetSize(740,300)
    local box=CreateFrame("EditBox",nil,scroll)
    box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFontObject("ChatFontNormal");box:SetWidth(710)
    box:SetScript("OnEscapePressed",function(b) b:ClearFocus() end)
    box:SetScript("OnTextChanged",function(b,userInput)
        if userInput and b.exportText and b:GetText()~=b.exportText then b:SetText(b.exportText) end
    end)
    scroll:SetScrollChild(box)
    u.historyExportBox,u.historyExportScroll=box,scroll
    button(frame,"Select All",20,-420,120,function() box:SetFocus();box:HighlightText() end)
    frame:HookScript("OnHide",function() box:ClearFocus() end)
end

function A:ShowHistoryExport()
    if self.historyDeleteMode then return false end
    local records=self:FilterHistoryRecords(self.historyFilter,self.historySearch,self.historyGuildBank)
    if #records==0 then return false end
    local u=self.ui
    local box=u.historyExportBox
    box.exportText=self:HistoryCSV(records)
    box:SetText(box.exportText)
    local _,lineBreaks=box.exportText:gsub("\n","")
    box:SetHeight(math.max(300,(lineBreaks+1)*50))
    local scope=self.historyGuildBank and "Guild Bank" or (self.historyFilter or "All Rewards")
    u.historyExportSummary:SetText(scope.." | "..#records.." matching "..(#records==1 and "record" or "records"))
    u.historyExportWindow:Show()
    self:FocusWindow(u.historyExportWindow)
    box:SetFocus();box:HighlightText()
    u.historyExportScroll:SetVerticalScroll(0)
    return true
end

function A:CaptureHistoryLink(link)
    local u=self.ui
    if not u or not u.history or u.history:IsShown()~=true or not u.historySearch
        or u.historySearch:HasFocus()~=true or type(link)~="string" or not link:match("item:%d+") then return false end
    if u.historySearch:GetText()~=link then u.historySearch:SetText(link) end
    u.historySearch:SetCursorPosition(#link)
    return true
end

function A:HistoryDeleteCount()
    local count=0
    for _ in pairs(self.historyDeleteSelection or {}) do count=count+1 end
    return count
end
function A:RefreshHistorySelection()
    if self.ui and self.ui.history and self.ui.history:IsShown() then self:ShowHistory(self.historyFilter,self.historyGuildBank) end
end
function A:BeginHistoryDeletion()
    if self.historySync then self:Print("Wait for History sync to finish before deleting records.");return false end
    if self.ui and self.ui.awardAudit then self.ui.awardAudit:Hide() end
    self.historyDeleteMode=true
    self.historyDeleteSelection={};self.historyDeleteViewKey=nil
    self.historyDeleteToken=(self.historyDeleteToken or 0)+1
    self:RefreshHistorySelection()
    return true
end
function A:CancelHistoryDeletion(refresh)
    self.historyDeleteMode=nil;self.historyDeleteSelection={};self.historyDeleteViewKey=nil
    self.historyDeleteToken=(self.historyDeleteToken or 0)+1
    if refresh~=false then self:RefreshHistorySelection() end
end
function A:ClickHistoryRecord(record)
    if not record then return end
    if not self.historyDeleteMode then self:ShowAwardAudit(record);return end
    if type(record.key)~="string" then return end
    self.historyDeleteSelection[record.key]=not self.historyDeleteSelection[record.key] or nil
    self:RefreshHistorySelection()
end
function A:AllShownHistorySelected()
    local count=0
    for _,record in ipairs(self.historyVisibleRecords or {}) do
        if type(record.key)=="string" then
            count=count+1
            if not (self.historyDeleteSelection or {})[record.key] then return false end
        end
    end
    return count>0
end
function A:SelectShownHistory()
    if not self.historyDeleteMode then return end
    if self:AllShownHistorySelected() then self.historyDeleteSelection={}
    else
        for _,record in ipairs(self.historyVisibleRecords or {}) do
            if type(record.key)=="string" then self.historyDeleteSelection[record.key]=true end
        end
    end
    self:RefreshHistorySelection()
end
function A:RenderHistoryDeletion(records,viewKey)
    self.historyVisibleRecords=records
    if self.historyDeleteMode and self.historyDeleteViewKey~=viewKey then
        self.historyDeleteSelection={};self.historyDeleteViewKey=viewKey
        self.historyDeleteToken=(self.historyDeleteToken or 0)+1
    end
    local u=self.ui
    if not u or not u.historyDelete then return end
    if u.historyExport then u.historyExport:SetEnabled(not self.historyDeleteMode and #records>0) end
    local count=self:HistoryDeleteCount()
    u.historyDelete:SetText(self.historyDeleteMode and ("Delete Selected ("..count..")") or "Delete History")
    u.historyDelete:SetEnabled(not self.historySync and (not self.historyDeleteMode or count>0))
    u.historySelectAll:SetText(self:AllShownHistorySelected() and "Deselect All" or "Select All Shown")
    u.historySelectAll:SetShown(self.historyDeleteMode==true)
    u.historySelectAll:SetEnabled(#records>0)
    u.historyDeleteCancel:SetShown(self.historyDeleteMode==true)
    if u.archiveHelp then u.archiveHelp:SetText(self.historyDeleteMode
        and "Select rows, then Delete Selected. Deletion is local; sessions or sync may restore records."
        or "Delete History lets you select local records for removal.") end
end
function A:ReviewHistoryDeletion()
    if not self.historyDeleteMode or self.historySync then return false end
    self:InitStorage()
    local snapshots,count={},0
    for _,record in ipairs(SanguineLootCouncilDB.history) do
        if self.historyDeleteSelection[record.key] then snapshots[record.key]=self.Copy(record);count=count+1 end
    end
    if count==0 then return false end
    local dialog=self:ShowConfirmation("SANGUINELOOTCOUNCIL_DELETE_HISTORY",tostring(count))
    if dialog then dialog.data={token=self.historyDeleteToken,records=snapshots} end
    return dialog~=nil
end
local function unchangedHistory(record,snapshot)
    for _,key in ipairs({"key","item","winner","time","revision","deliveryRevision","archivedAt","response","responseLabel","votes","quantity","quality"}) do
        if record[key]~=snapshot[key] then return false end
    end
    return true
end
function A:ConfirmHistoryDeletion(context)
    if not self.historyDeleteMode or self.historySync or type(context)~="table" or context.token~=self.historyDeleteToken
        or type(context.records)~="table" then return false end
    self:InitStorage()
    local removed,changed=0,0
    for i=#SanguineLootCouncilDB.history,1,-1 do
        local record=SanguineLootCouncilDB.history[i];local snapshot=context.records[record.key]
        if snapshot then
            if unchangedHistory(record,snapshot) then table.remove(SanguineLootCouncilDB.history,i);removed=removed+1
            else changed=changed+1 end
        end
    end
    self:CancelHistoryDeletion()
    self:Print("Deleted "..removed.." local History record(s)."..(changed>0 and (" "..changed.." changed record(s) were kept.") or ""))
    if self.ui and self.ui.playerHistory then self:RenderCandidateHistory() end
    return true
end
A.confirmationDialogs=A.confirmationDialogs or {}
A.confirmationDialogs["SANGUINELOOTCOUNCIL_DELETE_HISTORY"]={
    text="Delete %s selected History record(s) from this installation?\n\nActive sessions or History sync may restore these records. Current loot and trade tracking are unaffected.",
    button1="Delete Selected",button2="Cancel",timeout=0,whileDead=true,hideOnEscape=true,
    OnAccept=function(dialog) A:ConfirmHistoryDeletion(dialog.data) end,
}
