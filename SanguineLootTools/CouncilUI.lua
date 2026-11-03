local _, A = ...
local function move(object, parent, x, y, w, h)
    object:SetParent(parent); object:ClearAllPoints(); object:SetPoint("TOPLEFT", x, -y)
    if w then object:SetWidth(w) end
    if h then object:SetHeight(h) end
end
function A:VotingResponseLabel(item,response)
    if response.autoPass and response.choice==6 then return "Auto Pass" end
    if response.choice~=0 then return self:ResponseLabel(response.choice,item) end
    return item.status=="open" and "Waiting…" or "No response"
end
function A:CouncilAwardAction(item,target)
    if not item or item.status~="awarded" or item.winner~=target then
        return "Award",self:CanAwardCandidate(item,target),nil
    end
    local entry=self:TrackedForItem(item)
    if entry and entry.delivery=="delivered" then return "Delivered",false,nil,"Delivery has been confirmed." end
    if self.demo then return "Awarded",false,nil,"Simulated items cannot be traded." end
    if not entry or entry.manual then return "Awarded",false,nil,"No verified bag copy. Use Loot > Manage to confirm manual delivery." end
    if entry.holder==item.winner then return "Already held",false,nil,"The winner already holds this item. Confirm delivery through Loot > Manage." end
    if entry.holder~=self.me then return "Trade",false,nil,"The recorded item holder must start the trade from their addon." end
    if self:EntryInTrade(entry,item.winner) then return "In trade",false,nil,"A trade with the winner is already open." end
    return "Trade",true,entry.id,"Trade pending awarded items to "..self:DisplayName(item.winner)..". Both players must accept the trade."
end

function A:UseCouncilAwardAction(target)
    local item=self.state and self:ItemByID(self.selectedItem or 1)
    local _,enabled,tracked=self:CouncilAwardAction(item,target)
    if not enabled then return false end
    if tracked then return self:StartTrade(tracked) end
    self.selectedCandidate=target
    self:ReviewAward(target)
    return true
end

function A:MoveVotingRail(direction)
    if not self.ui or not self:CanViewCouncil() then return end
    local pages=math.max(1,math.ceil((self.state and #self.state.items or 0)/(self.votingItemRows or 9)))
    self.itemPage=math.max(0,math.min((self.itemPage or 0)+direction,pages-1))
    self:Render()
end

function A:CycleCouncilItem(direction)
    local items=self.state and self.state.items or {}
    if #items==0 then return end
    local index=1
    for i,item in ipairs(items) do if item.id==self.selectedItem then index=i;break end end
    local target=math.max(1,math.min(#items,index+direction))
    if target==index then return end
    self.selectedItem=items[target].id
    self.itemPage=math.floor((target-1)/(self.votingItemRows or 9))
    self.candidatePage,self.selectedCandidate=0,nil
    self:Render()
end

function A:PrepareVotingAdvance(kind,item,target)
    self.pendingVotingAdvance=nil
    if not self.ui or not self.ui.main:IsShown() then return end
    self.pendingVotingAdvance={sid=self.state.id,item=item.id,round=item.round,
        kind=kind,target=target,responseRevision=item.responses[target] and item.responses[target].revision,
        expires=self.Client:ServerTime()+30}
end

function A:ApplyVotingAdvance()
    local p=self.pendingVotingAdvance;if not p then return end
    local item=self.state and self:ItemByID(p.item)
    if not item or self.state.id~=p.sid or item.round~=p.round or self.selectedItem~=p.item
        or not self.ui.main:IsShown() or not self:CanViewCouncil() or self.Client:ServerTime()>p.expires then
        self.pendingVotingAdvance=nil;return
    end
    local complete
    if p.kind=="vote" then
        if not self:IsCouncil() then self.pendingVotingAdvance=nil;return end
        local own=self:VisibleVoting(item).ownBallot
        complete=own and own.choices and own.choices[p.target]
            and own.versions and own.versions[p.target]==p.responseRevision
    else
        complete=item.status=="awarded" and item.winner==p.target and item.awardedBy==self.me
    end
    if not complete then return end
    self.pendingVotingAdvance=nil
    for i,current in ipairs(self.state.items) do
        local nextItem=self.state.items[i+1]
        if current.id==p.item and nextItem then
            self.selectedItem=nextItem.id
            self.itemPage=math.floor(i/(self.votingItemRows or 9))
            self.candidatePage,self.selectedCandidate=0,nil
            return
        end
    end
end

local function tip(button)
    button:SetScript("OnEnter", function(self)
        if self.link then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
function A:BuildCouncilUI(u, window, text, button)
    local f = u.main
    f:HookScript("OnHide",function() A.pendingVotingAdvance=nil end)
    f:SetSize(1100, 640); f.title:SetText("Sanguine Loot Tools - Voting")
    -- Keep one saved/movable footprint, with a voting surface and two aligned
    -- right-hand panes. Columns and pane bounds reflow at normal text scale.
    f:SetBackdrop(nil)
    f.headerBand:Hide()
    u.votingSurface=CreateFrame("Frame",nil,f,"BackdropTemplate")
    u.votingSurface:SetPoint("TOPLEFT",0,0);u.votingSurface:SetSize(780,640)
    local level=f:GetFrameLevel()
    if type(level)=="number" then u.votingSurface:SetFrameLevel(level) end
    self:StylePanel(u.votingSurface,34)
    f.closeButton:ClearAllPoints();f.closeButton:SetPoint("TOPLEFT",746,-4)
    move(f.title, f, 80, 12, 650)
    u.session = window("SanguineLootCouncilSession", "Session controls", 930, 235)
    for i, key in ipairs({"start", "finish", "settings", "readiness", "resume", "lootHistory"}) do
        move(u[key], u.session, 20 + (i-1)*150, 60, 140)
    end
    -- Keep manual item entry and its hint together in a separate management area.
    move(u.itemInput, u.session, 25, 130, 650); move(u.add, u.session, 700, 130, 150)
    text(u.session, "Shift-click an item into the entry field. Master looter adds and releases loot.", 11, 25, -110, 850)
    u.timers:Hide(); u.railLabel:Hide(); u.oldHeading:Hide(); u.oldFooter:Hide()
    -- The hint was originally created directly on the main frame.
    if f.GetRegions then
        for _, region in ipairs({f:GetRegions()}) do
            if region.GetText and region:GetText() == "Shift-click an item here to add it to the session" then region:Hide() end
        end
    end
    move(u.status, f, 80, 40, 610)
    move(u.itemIcon, f, 78, 69, 40, 40)
    move(u.itemTitle, f, 127, 70, 570); move(u.itemDetails, f, 127, 92, 570)
    move(u.itemStatus, f, 350, 112, 420, 16); u.itemStatus:SetJustifyV("TOP");u.itemStatus:SetMaxLines(1)
    u.councilResponseBar = CreateFrame("StatusBar", nil, f)
    u.councilResponseBar:SetPoint("TOPLEFT", 127, -112); u.councilResponseBar:SetSize(210, 12)
    u.councilResponseBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    u.councilCountdown = u.councilResponseBar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    u.councilCountdown:SetPoint("CENTER")
    u.votingItemRail=CreateFrame("Frame",nil,f)
    u.votingItemRail:SetPoint("TOPLEFT",10,-66);u.votingItemRail:SetSize(60,9*43)
    local function wheel(_,delta) if delta~=0 then A:MoveVotingRail(delta>0 and -1 or 1) end end
    u.votingItemRail:EnableMouseWheel(true);u.votingItemRail:SetScript("OnMouseWheel",wheel)
    for i, b in ipairs(u.itemButtons) do
        move(b, u.votingItemRail, 5, (i-1)*43, 38, 38)
        b:EnableMouseWheel(true);b:SetScript("OnMouseWheel",wheel)
        b:SetNormalTexture(""); b:SetPushedTexture("")
        self:StylePanel(b)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 4, -4); b.icon:SetSize(30, 30)
        b.awarded = b:CreateTexture(nil, "OVERLAY")
        b.awarded:SetTexture("Interface/RaidFrame/ReadyCheck-Ready")
        b.awarded:SetPoint("BOTTOMRIGHT", 3, -3); b.awarded:SetSize(22, 22); b.awarded:Hide()
    end
    self:StyleRailArrow(u.itemPrev,-1);self:StyleRailArrow(u.itemNext,1)
    move(u.itemPrev,f,16,478,22,22);move(u.itemNext,f,42,478,22,22)
    move(u.itemPages,f,15,458,50,14);u.itemPages:SetJustifyH("CENTER");u.itemPages:SetFont(STANDARD_TEXT_FONT,10)
    local columns = {{"Name",0,110},{"Rank",112,64},{"Role",178,48},{"Response",228,130},{"Gear",360,56},{"Votes",418,42},{"Vote",462,68},{"Notes",532,58},{"Award",592,80}}
    local heading=f:CreateTexture(nil,"BACKGROUND");u.councilHeadingBackground=heading;u.councilHeadings={}
    heading:SetPoint("TOPLEFT",76,-127);heading:SetSize(700,21);heading:SetColorTexture(0.13,0.14,0.17,1)
    for i,col in ipairs(columns) do local label=text(f,col[1],11,80+col[2],-129,col[3]);label:SetTextColor(0.80,0.74,0.57);u.councilHeadings[i]=label end
    u.councilEmpty=text(f,"",13,100,-190,640)
    u.councilEmpty:SetHeight(100);u.councilEmpty:SetJustifyH("CENTER");u.councilEmpty:SetJustifyV("TOP")
    for i, row in ipairs(u.candidates) do
        move(row, f, 76, 148+(i-1)*22, 700, 22)
        row:SetNormalTexture(""); row:SetPushedTexture("")
        row:GetFontString():Hide()
        self:StyleDataRow(row,i)
        row.cells = {}
        for j, col in ipairs(columns) do row.cells[j] = text(row, "", 11, 4+col[2], -5, col[3]); row.cells[j]:SetMaxLines(1) end
        row.gear = {}
        for j=1,2 do
            local gear = CreateFrame("Button", nil, row); gear:SetPoint("TOPLEFT", 364+(j-1)*26, -1); gear:SetSize(20,20)
            gear.icon = gear:CreateTexture(nil,"ARTWORK"); gear.icon:SetAllPoints(); tip(gear); row.gear[j]=gear
        end
        row.pick = button(row, "Vote", 466, -1, 66, function()
            A.selectedCandidate = row.candidate; A:VoteForCandidate()
        end); row.pick:SetHeight(20)
        row.cells[7]:Hide()
        local function showNote(b)
            GameTooltip:SetOwner(b,"ANCHOR_RIGHT");GameTooltip:ClearLines()
            GameTooltip:AddLine(b.player or "Raider")
            GameTooltip:AddLine(b.hasNote and b.note or "No note provided.",1,1,1,true);GameTooltip:Show()
        end
        row.noteButton=button(row,"",552,-1,22,showNote);row.noteButton:SetHeight(20);row.noteButton:SetBackdrop(nil);row.cells[8]:Hide()
        -- A small document drawn from solid textures, with no client-specific
        -- icon asset or red panel-button artwork.
        local n=row.noteButton
        -- Separate strokes cannot be reordered into a solid block by texture
        -- batching, unlike an outer fill covered by a same-layer inner fill.
        n.paper=n:CreateTexture(nil,"OVERLAY");n.paper:SetPoint("TOPLEFT",5,-2);n.paper:SetSize(1,16)
        n.edges={}
        for _,v in ipairs({{5,-2,12,1},{16,-2,1,16},{5,-17,12,1}}) do
            local edge=n:CreateTexture(nil,"OVERLAY");edge:SetPoint("TOPLEFT",v[1],v[2]);edge:SetSize(v[3],v[4]);n.edges[#n.edges+1]=edge
        end
        n.lines={}
        for line=1,3 do
            local t=n:CreateTexture(nil,"OVERLAY");t:SetPoint("TOPLEFT",8,-5-(line-1)*4);t:SetSize(line==3 and 4 or 6,1);n.lines[line]=t
        end
        row.noteButton:SetScript("OnEnter",showNote)
        row.noteButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
        row.award = button(row,"Award",596,-1,78,function()
            A:UseCouncilAwardAction(row.candidate)
        end);row.award:SetHeight(20);row.cells[9]:Hide()
        row.award:SetScript("OnEnter",function(b)
            local item=A.state and A:ItemByID(A.selectedItem or 1)
            if not item or not row.candidate then return end
            GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local label,_,_,notice=A:CouncilAwardAction(item,row.candidate)
            GameTooltip:AddLine(label.." • "..A:DisplayName(row.candidate))
            GameTooltip:AddLine(notice or A:EligibilityText(item,row.candidate),1,0.8,0.4,true)
            GameTooltip:Show()
        end)
        row.award:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    u.playerPagePrevious,u.playerPageNext=u.candidatePrev,u.candidateNext
    u.playerPagePrevious:SetText("Players <");u.playerPageNext:SetText("Players >")
    u.candidatePrev=button(f,"Previous",80,-463,85,function() A:CycleCouncilItem(-1) end)
    u.candidateNext=button(f,"Next",690,-463,85,function() A:CycleCouncilItem(1) end)
    move(u.selection,f,125,469,375); move(u.playerHistory,f,510,463,110); u.compareGear:Hide()
    u.playerHistoryTitle:Hide(); for _, row in ipairs(u.playerHistoryRows) do row:Hide() end
    u.votingResponses=button(f,"My Responses",635,-580,125,function() A:ShowResponses() end)
    u.votingLoot=button(f,"Loot",770,-580,70,function()
        if not A:IsMaster() then return end
        u.main:Hide();u.voting:Hide()
        A:ShowLootWindow("timer")
    end)
    move(u.open,f,80,580,160)
    u.open:SetScript("OnEnter",function(b)
        GameTooltip:SetOwner(b,"ANCHOR_TOP")
        GameTooltip:AddLine("Reroll Item")
        GameTooltip:AddLine("Only the selected item: restart its response timer and clear council votes. All player responses, notes and gear snapshots are cleared; everyone must choose again. Other items are unaffected.",1,1,1,true)
        GameTooltip:Show()
    end)
    u.open:SetScript("OnLeave",function() GameTooltip:Hide() end)
    move(u.resetVoting,u.session,20,201,140); move(u.openVoting,u.session,170,201,140)
    move(u.correctAward,u.session,320,201,170)
    move(u.votingProgress,f,80,503,680); move(u.votingOwn,f,80,535,690,42)
    u.vote:Hide(); u.votingDesk:Hide()
    self:BuildSelectedLootTooltip(u, f, text)
    self:BuildVotingHistory(u,f,text,button)
end
function A:ParentVotingContent()
    local u=self.ui
    local frame,surface=u.main,u.votingSurface
    -- The opaque voting surface must own its content. Sibling regions on the
    -- outer frame can be painted underneath it after hide/show or focus changes.
    local excluded={[surface]=true,[frame.sltHeader]=true}
    if frame.resizeGrip then excluded[frame.resizeGrip]=true end
    if frame.sltDialogBlocker then excluded[frame.sltDialogBlocker]=true end
    if u.selectedLootPane then excluded[u.selectedLootPane]=true end
    if u.votingHistory then excluded[u.votingHistory.frame]=true end
    for _,child in ipairs({frame:GetChildren()}) do
        if not excluded[child] then child:SetParent(surface) end
    end
    for _,region in ipairs({frame:GetRegions()}) do
        if region~=frame.headerBand then region:SetParent(surface) end
    end
end
function A:LayoutVotingColumns(surface)
    local u=self.ui
    local width=surface-80
    local mix=math.max(0,math.min(1,(width-440)/260))
    local normal={110,64,48,130,56,42,68,58,80}
    local compact={70,36,30,84,40,28,48,22,54}
    local columns,x={},0
    for i=1,9 do
        local size=math.floor(compact[i]+(normal[i]-compact[i])*mix)
        columns[i]={x=x,width=size}
        local label=u.councilHeadings[i]
        label:ClearAllPoints();label:SetPoint("TOPLEFT",80+x,-129);label:SetWidth(size)
        label:SetHeight(16);label:SetMaxLines(1)
        if i==8 then label:SetText(size<30 and "Note" or "Notes") end
        x=x+size+2
    end
    u.councilHeadingBackground:SetWidth(width)
    for _,row in ipairs(u.candidates) do
        row:SetWidth(width)
        for i,cell in ipairs(row.cells) do
            cell:ClearAllPoints();cell:SetPoint("TOPLEFT",4+columns[i].x,-5);cell:SetWidth(columns[i].width)
        end
        for i,gear in ipairs(row.gear) do
            local offset=i==1 and 0 or columns[5].width-20
            gear:ClearAllPoints();gear:SetPoint("TOPLEFT",4+columns[5].x+offset,-1)
        end
        row.pick:ClearAllPoints();row.pick:SetPoint("TOPLEFT",4+columns[7].x,-1);row.pick:SetWidth(columns[7].width-2)
        row.noteButton:ClearAllPoints();row.noteButton:SetPoint("TOPLEFT",4+columns[8].x+(columns[8].width-22)/2,-1)
        row.award:ClearAllPoints();row.award:SetPoint("TOPLEFT",4+columns[9].x,-1);row.award:SetWidth(columns[9].width-2)
    end
    u.compactVoting=mix<0.5
end

function A:RenderCouncilTable(item, candidates, draft)
    self.ui.votingLoot:SetShown(self:IsMaster())
    local u = self.ui
    local empty
    if not self.state then empty="No active session.\nThe raid leader can start one in Settings > Tools."
    elseif #self.state.items==0 then empty="No loot queued.\nThe master looter can queue items from Loot / Trade."
    elseif not item then empty="Select an item on the left to view its responses."
    elseif not (self:IsCouncil() or self:IsMaster()) then empty="Council voting is available to council members and the master looter."
    elseif #candidates==0 then
        if item.status=="queued" then empty="Responses have not opened yet.\nThe master looter can open responses for this item."
        elseif item.status=="open" then empty="Waiting for raider responses."
        else empty="No responses recorded for this item." end
    end
    u.councilEmpty:SetText(empty or "");u.councilEmpty:SetShown(empty~=nil)
    self:RenderSelectedLootTooltip(item)
    for i, row in ipairs(u.candidates) do
        local c = i<=(self.votingCandidateRows or 14) and candidates[(self.candidatePage or 0)*(self.votingCandidateRows or 14)+i]
        if c then
            local unit = self.roster[c.name]
            local rank, role = "—", "—"
            if type(unit)=="string" then
                if GetGuildInfo then local ok, _, r = pcall(GetGuildInfo,unit); if ok and type(r)=="string" then rank=r end end
                if UnitGroupRolesAssigned then local ok,r=pcall(UnitGroupRolesAssigned,unit); if ok and type(r)=="string" and r~="NONE" then role=r end end
            end
            row.rankText,row.roleText=rank,role
            if u.compactVoting then role=role=="DAMAGER" and "DPS" or role=="HEALER" and "Heal" or role=="TANK" and "Tank" or role end
            local comparison = self:ComparisonRows(item,c.name)
            for j, gear in ipairs(row.gear) do
                gear.link = comparison[j] and comparison[j].link
                gear.icon:SetTexture(gear.link and self:ItemIcon({link=gear.link}) or "Interface/Icons/INV_Misc_QuestionMark")
                gear:SetShown(comparison[j] ~= nil)
            end
            local response = self:VotingResponseLabel(item,c.response)
            local values={self:DisplayName(c.name),rank,role,response,"",c.votes>=0 and tostring(c.votes) or "—","",c.response.note~="" and "Note" or "—",""}
            for j, cell in ipairs(row.cells) do cell:SetText(values[j]); cell:SetTextColor(0.85,0.85,0.85) end
            local _,_,classColor=self:LootHolderInfo(c.name)
            if classColor then row.cells[1]:SetTextColor(classColor.r,classColor.g,classColor.b) end
            local colors={{0.3,1,0.45},{0.3,1,0.45},{0.75,1,0.3},{1,0.65,0.2},{0.45,0.7,1},{0.55,0.55,0.55},{0.9,0.25,0.2}}
            row.cells[4]:SetTextColor(self:ResponseRGB(c.response.choice,item))
            local awarded = item.status=="awarded"
            local winner = awarded and item.winner==c.name
            row.isWinner = winner
            if winner then row.shade:SetColorTexture(0.15,0.8,0.3,0.35)
            elseif self.selectedCandidate==c.name then row.shade:SetColorTexture(0.8,0.65,0.15,0.25)
            else row.shade:SetColorTexture(1,1,1,i%2==0 and 0.045 or 0.015) end
            local own=self:VisibleVoting(item).ownBallot
            row.noteButton.note,row.noteButton.player=c.response.note,c.name
            local n=row.noteButton
            n.hasNote=c.response.note~="" and c.response.choice~=0
            n:SetShown(true)
            local r,g,b=n.hasNote and 0.95 or 0.38,n.hasNote and 0.77 or 0.40,n.hasNote and 0.28 or 0.44
            n.paper:SetColorTexture(r,g,b,1)
            for _,edge in ipairs(n.edges) do edge:SetColorTexture(r,g,b,1) end
            for _,line in ipairs(n.lines) do line:SetColorTexture(r,g,b,1) end
            local voted=own and own.choices and own.choices[c.name]
            row.pick:SetEnabled(not awarded and self:IsCouncil() and item.voting=="open" and c.response.choice~=0 and c.response.choice~=6)
            row.pick:SetText(voted and "Voted" or "Vote")
            row.pick:GetFontString():SetTextColor(voted and 0.3 or 1, voted and 1 or 0.82, voted and 0.45 or 0)
            local awardLabel,awardEnabled=self:CouncilAwardAction(item,c.name)
            row.award:SetEnabled(awardEnabled)
            row.award:SetText(awardLabel)
        end
    end
    -- These summaries are available from the history button; keep the table uncluttered.
    for _, row in ipairs(u.playerHistoryRows) do row:Hide() end
end

function A:RenderCouncilTimer()
    if not self.ui or not self.ui.councilResponseBar then return end
    local u=self.ui
    local item=self.state and self:ItemByID(self.selectedItem or 1)
    local timed=item and item.status=="open" and item.responseDeadline and (item.responseDuration or 0)>0
    local remaining=timed and self:ResponseRemaining(item) or 0
    u.councilResponseBar:SetMinMaxValues(0,timed and item.responseDuration or 1)
    u.councilResponseBar:SetValue(remaining)
    u.councilCountdown:SetText(not item and "" or (timed and (math.ceil(remaining).."s remaining") or (item.status=="open" and "No response time limit" or (item.status=="queued" and "Responses not opened" or "Responses closed"))))
    if timed and remaining<=10 then u.councilResponseBar:SetStatusBarColor(0.85,0.15,0.15)
    elseif timed then u.councilResponseBar:SetStatusBarColor(0.3,0.6,0.25)
    else u.councilResponseBar:SetStatusBarColor(0.35,0.35,0.38) end
end

-- An independent tooltip, pinned inside the voting window. The shared
-- GameTooltip remains available for candidate notes and equipment comparisons.
function A:BuildSelectedLootTooltip(u, parent, text)
    parent:SetScript("OnEnter",nil);parent:SetScript("OnLeave",nil)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", 796, 0); pane:SetSize(304, 320)
    self:StylePanel(pane,24)
    local title=text(pane,"Selected loot",11,10,-9,270)
    self:LayoutTitleText(title,10,270,24)
    title:SetTextColor(0.86,0.76,0.49)
    u.selectedLootPane=pane
    u.selectedLootScroll=A:CreateScrollFrame(pane)
    u.selectedLootScroll:SetPoint("TOPLEFT",8,-29); u.selectedLootScroll:SetSize(266,279)
    u.selectedLootChild=CreateFrame("Frame",nil,u.selectedLootScroll)
    u.selectedLootChild:SetSize(266,279);u.selectedLootScroll:SetScrollChild(u.selectedLootChild)
    u.selectedLootPlaceholder=text(u.selectedLootChild,"Select an item on the left to view its tooltip.",12,8,-8,250)
    local ok,tooltip=pcall(CreateFrame,"GameTooltip","SanguineLootCouncilSelectedLootTooltip",u.selectedLootChild,"GameTooltipTemplate")
    if ok and tooltip then
        u.selectedLootTooltip=tooltip
        tooltip:SetClampedToScreen(false);tooltip:EnableMouse(false);tooltip:Hide()
        if tooltip.HookScript then tooltip:HookScript("OnSizeChanged",function() A:SizeSelectedLootTooltip() end) end
    end
    pcall(pane.RegisterEvent,pane,"GET_ITEM_INFO_RECEIVED")
    pane:SetScript("OnEvent",function(_,event,id,success)
        if event=="GET_ITEM_INFO_RECEIVED" and success and A.demo and A:RefreshDemoItems() then A:Render();return end
        local item=A.state and A:ItemByID(A.selectedItem or 1)
        if event=="GET_ITEM_INFO_RECEIVED" and success and item and tonumber(item.link:match("item:(%d+)"))==id then
            A:RenderSelectedLootTooltip(item,true)
        end
    end)
    parent:SetScript("OnHide",function()
        u.selectedLootKey=nil
        if u.selectedLootTooltip then u.selectedLootTooltip:Hide() end
    end)
    parent:SetScript("OnShow",function()
        local item=A.state and A:ItemByID(A.selectedItem or 1)
        A:RenderSelectedLootTooltip(item,true)
    end)
end

function A:SizeSelectedLootTooltip()
    local u=self.ui
    if not u or not u.selectedLootTooltip or u.sizingSelectedLoot then return end
    u.sizingSelectedLoot=true
    local tip=u.selectedLootTooltip
    local good,width=pcall(tip.GetWidth,tip)
    local available=u.selectedLootScroll:GetWidth()
    local scale=1
    if good and not (issecretvalue and issecretvalue(width)) and type(width)=="number" and width==width and width>0 and width<10000
        and type(available)=="number" and available>0 then scale=math.min(1,available/width) end
    -- Keep the native tooltip's natural left/right column layout, then fit the
    -- whole tooltip to the viewport. Forcing its width clipped right-side text.
    tip:SetScale(scale)
    local ok,height=pcall(tip.GetHeight,tip)
    if ok and not (issecretvalue and issecretvalue(height)) and type(height)=="number" and height==height and height>0 and height<10000 then
        u.selectedLootChild:SetHeight(math.max(u.selectedLootScroll:GetHeight(),height*scale+8))
    end
    u.sizingSelectedLoot=nil
end

function A:RenderSelectedLootTooltip(item,force)
    local u=self.ui
    if not u or not u.selectedLootPane then return end
    local link=item and item.link
    local key=link and ((self.state and self.state.id or "")..":"..link)
    if not force and key and u.selectedLootKey==key then return end
    u.selectedLootKey=key
    u.selectedLootScroll:SetVerticalScroll(0);u.selectedLootChild:SetHeight(u.selectedLootScroll:GetHeight())
    local tooltip=u.selectedLootTooltip
    if tooltip then tooltip:Hide();tooltip:ClearLines() end
    if not link then
        u.selectedLootPlaceholder:SetText("Select an item on the left to view its tooltip.")
        u.selectedLootPlaceholder:Show();return
    end
    if tooltip then
        local ok=pcall(function()
            tooltip:SetOwner(u.selectedLootChild,"ANCHOR_NONE")
            tooltip:SetParent(u.selectedLootChild);tooltip:SetFrameStrata("DIALOG")
            tooltip:SetClampedToScreen(false)
            tooltip:ClearAllPoints();tooltip:SetPoint("TOPLEFT",u.selectedLootChild,"TOPLEFT",0,0)
            tooltip:SetScale(1)
            tooltip:SetMinimumWidth(266,false)
            tooltip:SetHyperlink(link)
            local lines=tooltip:NumLines()
            if not (issecretvalue and issecretvalue(lines)) and type(lines)=="number" and lines==0 then error("item data unavailable") end
            tooltip:Show()
        end)
        if ok then
            u.selectedLootPlaceholder:Hide();self:SizeSelectedLootTooltip();return
        end
        tooltip:Hide();tooltip:ClearLines()
    end
    u.selectedLootPlaceholder:SetText(link.."\n\nItem tooltip data unavailable. Waiting for the client to load it.")
    u.selectedLootPlaceholder:Show()
end
