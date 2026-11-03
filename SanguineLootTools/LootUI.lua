local _, A = ...
function A:IsCompletedUtilityAssignment(entry)
    local item=entry and entry.item and self:ItemByID(entry.item)
    return item and item.automaticAssignment and item.status=="awarded"
        and (item.awardReason=="Disenchant" or item.awardReason=="Guild Bank")
        and entry.delivery=="delivered" and item.winner~=nil and entry.deliveredTo==item.winner
end

function A:LootHolderInfo(holder)
    if type(holder)~="string" or holder=="" then return "Unknown", "Holder not confirmed" end
    local unit=self.roster[holder]
    local status,color
    if type(unit)=="string" then
        local ok,connected=self.Client:Call("UnitIsConnected",unit)
        if ok and (connected==false or connected==0) then status="Offline" end
        local ok,_,class=self.Client:Call("UnitClass",unit)
        if ok and type(class)=="string" and type(RAID_CLASS_COLORS)=="table" then color=RAID_CLASS_COLORS[class] end
    elseif not unit then status="Not in raid" end
    if self:IsSoloTest() and type(RAID_CLASS_COLORS)=="table" then
        local fixtureClass=holder=="Warrior-Test" and "WARRIOR" or holder=="Priest-Test" and "PRIEST"
        if fixtureClass then color=RAID_CLASS_COLORS[fixtureClass] end
    end
    return self:DisplayName(holder),status,color
end

function A:MoveLootPage(direction)
    if not self.ui or not self.ui.lootPanels or not self:CanViewLoot() then return end
    local panel=self.ui.lootPanels.deliveries
    local last=math.max(0,math.ceil((panel.count or 0)/(panel.visibleRows or 6))-1)
    panel.page=math.max(0,math.min((panel.page or 0)+direction,last))
    if GameTooltip then GameTooltip:Hide() end
    self:RenderLootWindows()
end

function A:BuildLootUI(u, window, text, button, edit)
    local panel = {page = 0}
    u.lootPanels = {timer = panel, deliveries = panel}
    local w = window("SanguineLootCouncilTrade", "Sanguine Loot Tools - Loot", 820, 440)
    panel.window = w
    local function wheel(_,delta) if delta~=0 then A:MoveLootPage(delta>0 and -1 or 1) end end
    w.sltWheelEnabled=true;w:EnableMouseWheel(true);w:SetScript("OnMouseWheel",wheel)
    panel.summary = text(w, "", 11, 20, -43, 710)
    panel.empty=text(w,"No loot collected yet.\nEligible items will appear here when holders report them.",13,45,-170,670)
    panel.empty:SetHeight(85);panel.empty:SetJustifyH("CENTER");panel.empty:SetJustifyV("TOP")
    panel.itemHeader=text(w, "Item", 11, 24, -70, 265); panel.timeHeader=text(w, "Trade time", 11, 296, -70, 90)
    panel.holderHeader=text(w, "Holder", 11, 398, -70, 105); panel.winnerHeader=text(w, "Winner", 11, 528, -70, 108)
    panel.rows = {}
    for i=1,12 do
        local row = button(w, "", 18, -88-(i-1)*44, 724, function(self) A.selectedTracked=self.tracked; A:RenderLootWindows() end)
        row:SetHeight(42); row:SetNormalTexture(""); row:SetPushedTexture("")
        self:StyleDataRow(row,i)
        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetPoint("TOPLEFT",4,-4); row.icon:SetSize(34,34)
        row.caption=text(row,"",11,46,-4,220); row.caption:SetHeight(26); row.caption:SetMaxLines(2)
        row.detail=text(row,"",9,46,-30,220); row.detail:SetMaxLines(1)
        row.holder=text(row,"",11,380,-8,70); row.holder:SetMaxLines(1);row.holder:SetWordWrap(false)
        row.holderMeasure=text(row,"",11,0,0);row.holderMeasure:Hide()
        row.holderStatus=text(row,"",9,380,-26,105); row.holderStatus:SetMaxLines(1)
        row.arrow=CreateFrame("Frame",nil,row);row.arrow:SetPoint("TOPLEFT",486,-10);row.arrow:SetSize(20,18)
        local function stroke(x,y,w,h)
            local t=row.arrow:CreateTexture(nil,"ARTWORK");t:SetPoint("TOPLEFT",x,y);t:SetSize(w,h);t:SetColorTexture(0.64,0.66,0.70,1)
        end
        -- Pixel strokes need neither a Unicode glyph nor rotated texture UVs.
        stroke(2,-8,12,1)
        for offset=0,4 do
            stroke(14-offset,-8+offset,1,1)
            if offset>0 then stroke(14-offset,-8-offset,1,1) end
        end
        row.winner=text(row,"",11,510,-8,108); row.winner:SetMaxLines(1)
        row.bar=CreateFrame("StatusBar",nil,row); row.bar:SetPoint("TOPLEFT",278,-12); row.bar:SetSize(90,18)
        row.bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
        row.countdown=row.bar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.countdown:SetPoint("CENTER"); row.countdown:SetWidth(88); row.countdown:SetMaxLines(1)
        row.trade=button(row,"",624,-8,88,function() A:StartTrade(row.tracked) end)
        row.tradeSummary=text(row,"",9,510,-28,202); row.tradeSummary:SetMaxLines(1)
        row.tradeLabel=text(row.trade,"Trade",11,0,-6,88); row.tradeLabel:SetJustifyH("CENTER"); row.trade:GetFontString():Hide()
        row:SetScript("OnEnter",function(self)
            local entry=A.state and A:TrackedByID(self.tracked or 0)
            if entry then
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetHyperlink(entry.link)
                local _,status=A:LootHolderInfo(entry.holder)
                GameTooltip:AddLine("Holder: "..(entry.holder or "Unknown"),1,1,1)
                if status then GameTooltip:AddLine(status,1,0.7,0.3) end
                local item=entry.item and A:ItemByID(entry.item)
                local count=item and item.winner and A:PendingTradeCount(item.winner,entry.holder) or 0
                if count>0 then
                    GameTooltip:AddLine(count.." pending item(s) for "..item.winner.." from this holder. Up to six free normal trade slots can be filled; any remaining items stay pending.",1,1,1,true)
                end
                local _, timerStatus=A:TradeRemaining(entry)
                GameTooltip:AddLine(timerStatus,1,1,1,true)
                GameTooltip:AddLine("Timer is a holder-reported estimate. Green means the winner is in trade range of you. Click Trade to offer all your pending awards for this winner; delivery is confirmed separately.",1,0.8,0.4,true); GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        for _,surface in ipairs({row,row.bar,row.arrow,row.trade}) do
            surface:EnableMouseWheel(true);surface:SetScript("OnMouseWheel",wheel)
        end
        panel.rows[i]=row
    end
    panel.previous=button(w,"<",20,-365,35,function() A:MoveLootPage(-1) end)
    panel.next=button(w,">",60,-365,35,function() A:MoveLootPage(1) end)
    self:StyleRailArrow(panel.previous,-1);self:StyleRailArrow(panel.next,1)
    panel.pageLabel=text(w,"",10,110,-373,280)
    panel.queueAll=button(w,"Queue all",410,-365,105,function() A:QueueTrackedLoot() end)
    u.manageLoot=button(w,"Manage",525,-365,100,function() A:ShowLootManagement() end)
    u.manageLoot:Hide();u.manageLoot:SetEnabled(false)
    panel.manage=window("SanguineLootCouncilDeliveryManagement","Loot management",820,290)
    panel.close=button(w,"Close",635,-365,100,function() w:Hide() end)
    panel.footer=text(w,"/slt loot reopens this window. Closing keeps tracking active.",10,20,-407,710)
    local m=panel.manage
    panel.selectionIcon=m:CreateTexture(nil,"ARTWORK")
    panel.selectionIcon:SetPoint("TOPLEFT",20,-55);panel.selectionIcon:SetSize(32,32)
    panel.selection=text(m,"",11,62,-55,738); panel.selection:SetHeight(45)
    panel.queue=button(m,"Queue item",20,-110,130,function() if A.selectedTracked then A:QueueTrackedLoot(A.selectedTracked) end end)
    panel.attach=button(m,"Attach selected loot",160,-110,150,function() A:Act("queueLoot",{tracked=A.selectedTracked,item=A.selectedItem,attach=true}) end)
    panel.delivered=button(m,"Confirm delivered",320,-110,160,function() A:ReviewDelivery("confirmDelivery") end)
    panel.reopen=button(m,"Reopen delivery",490,-110,150,function() A:ReviewDelivery("reopenDelivery") end)
    panel.holder=edit(m,25,-175,250,"Correct holder (Name-Realm)")
    panel.setHolder=button(m,"Set holder",290,-175,130,function() A:ReviewDelivery("lootHolder",panel.holder:GetText()) end)
    panel.auto=button(m,"",440,-175,250,function() A:Act("autoCollect") end)
    text(m,"Select an item in the trade list first. Confirm delivery only after the recipient has received it.",11,20,-235,780)
end
function A:ShowLootWindow(mode)
    if not self:CanViewLoot() then self:Print("Loot tracking requires an active leader, master looter, or holder of an awarded item."); return end
    self:BuildUI()
    if self.ui.itemTools and self.ui.itemTools:IsShown() then return end
    if self.ui.popup:GetWidth()+self.ui.lootPanels.timer.window:GetWidth()+64>UIParent:GetWidth() then self.ui.popup:Hide() end
    self.ui.lootPanels.timer.window:Show(); self:RenderLootWindows()
end

function A:ReviewDelivery(op, target)
    local entry = self.state and self.state.trackedLoot and self:TrackedByID(self.selectedTracked or 0)
    if not entry or not self:IsMaster() then return end
    local item = entry.item and self:ItemByID(entry.item)
    local data = {sid = self.state.id, op = op, tracked = entry.id, expectedRevision = entry.deliveryRevision,
        expectedWinner = item and item.winner, expectedAwardRevision = item and (item.awardRevision or 1), target = target}
    local message
    if op == "lootHolder" then
        data.target = self:Resolve(target)
        if not data.target then self:Print("Enter an unambiguous current raid member."); return end
        message = "Change the recorded holder from " .. entry.holder .. " to " .. data.target .. "?\nThis changes tracking only and clears the old timer reading."
    elseif not item or not item.winner then return
    elseif op == "confirmDelivery" then message = "Confirm that " .. item.winner .. " actually received this item?\nThis records your manual confirmation; it does not perform a trade."
    else message = "Reopen delivery to " .. item.winner .. "?\nThe earlier confirmation stays in the delivery log. This does not move the item." end
    if self.demo then message = self:TestLabel().." - simulated change only.\n\n" .. message end
    local dialog = A:ShowConfirmation("SANGUINELOOTCOUNCIL_DELIVERY", entry.link, message)
    if dialog then dialog.data = data end
end

function A:RenderLootWindows()
    if not self.ui or not self.ui.lootPanels then return end
    self:RenderLootTimers()
    local panel=self.ui.lootPanels.timer
    local selected=self:TrackedByID(self.selectedTracked or 0)
    if self:IsCompletedUtilityAssignment(selected) then self.selectedTracked=nil;selected=nil end
    self.ui.manageLoot:SetShown(self:IsMaster())
    self.ui.manageLoot:SetEnabled(self:IsMaster() and selected~=nil)
    if not self:IsMaster() or not selected then panel.manage:Hide() end
    if not self:CanViewLoot() then
        panel.window:Hide(); panel.manage:Hide(); return
    end
    local s=self.state
    if panel.discoverySID~=s.id then panel.discoverySID=s.id;panel.discoveryID=0 end
    local newest=panel.discoveryID or 0
    for _,entry in ipairs(s.trackedLoot or {}) do
        if not self:IsCompletedUtilityAssignment(entry) then newest=math.max(newest,entry.id) end
    end
    if newest>(panel.discoveryID or 0) and self:LootConfiguration().openWindow
        and (not self.ui.itemTools or not self.ui.itemTools:IsShown()) then panel.window:Show() end
    panel.discoveryID=newest
    local rows={}
    local completedAssignments=0
    for _, entry in ipairs(s.trackedLoot or {}) do
        if self:IsLeader() or self:IsMaster() or entry.holder==self.me then
            if self:IsCompletedUtilityAssignment(entry) then completedAssignments=completedAssignments+1
            else rows[#rows+1]=entry end
        end
    end
    table.sort(rows,function(a,b)
        local ad,bd=a.delivery=="delivered",b.delivery=="delivered"
        if ad~=bd then return not ad end
        local at,bt=self:TradeRemaining(a),self:TradeRemaining(b); at,bt=at or math.huge,bt or math.huge
        return at==bt and a.id<b.id or at<bt
    end)
    panel.count,panel.page=#rows,math.min(panel.page,math.max(0,math.ceil(#rows/(panel.visibleRows or 6))-1))
    local pending=0
    for _,entry in ipairs(rows) do
        local item=entry.item and self:ItemByID(entry.item)
        if item and item.status=="awarded" and item.winner and entry.delivery~="delivered" then pending=pending+1 end
    end
    panel.empty:SetShown(#rows==0)
    panel.empty:SetText(s.autoCollect==false and "No loot collected yet.\nAutomatic collection is off in Settings > Council." or "No loot collected yet.\nEligible items will appear here when holders report them.")
    if #rows==0 and completedAssignments>0 then panel.empty:SetText("No active loot to show.\nCompleted Disenchant and Guild Bank assignments are retained in Loot History.") end
    local capacity=(#s.items>=35 or #(s.trackedLoot or {})>=70) and (" | Active capacity: "..#s.items.."/40 items, "..#(s.trackedLoot or {}).."/80 copies (archive confirmed deliveries)") or ""
    panel.summary:SetText((self.demo and (self:TestLabel().." | ") or "")..(#rows==0 and (completedAssignments>0 and "No active loot" or "No loot collected yet") or (pending==0 and "No awards awaiting trade | "..#rows.." tracked items" or pending..(pending==1 and " award awaiting trade" or " awards awaiting trade").." | "..#rows.." tracked items"))..(completedAssignments>0 and (" | "..completedAssignments.." completed assignments in history") or "")..capacity.." | "..(s.archivedCount or 0).." archived")
    if self.demo then panel.empty:SetText("No simulated loot.\nRun /slt test to prepare a fresh SoD loot set.") end
    for i,row in ipairs(panel.rows) do
        local entry=i<=(panel.visibleRows or 6) and rows[panel.page*(panel.visibleRows or 6)+i] or nil; row:SetShown(entry~=nil); row.tracked=entry and entry.id
        if entry then
            local item=entry.item and self:ItemByID(entry.item)
            local awarded=item and item.status=="awarded" and item.winner
            local remaining,label=self:TradeRemaining(entry)
            local cfg=self:WarningSettings()
            local level=self:TradeWarningLevel(entry)
            row.warningLevel=level
            row.icon:SetTexture(self:ItemIcon(entry)); row.caption:SetText(entry.link)
            if level=="urgent" then row.caption:SetTextColor(1,0.3,0.2)
            elseif level=="early" then row.caption:SetTextColor(1,0.7,0.2)
            else row.caption:SetTextColor(1,1,1) end
            row.detail:SetText(entry.nativeReceipt and ("Master Loot record • Quantity "..(entry.quantity or 1)) or entry.manual and "Manual item - holder and timer unverified" or self.demo and (not entry.item and "Simulated loot - queue to open responses" or "Simulated loot - Manage tests delivery") or (self.selectedTracked==entry.id and "Selected" or ""))
            local holder,status,color=self:LootHolderInfo(entry.holder)
            row.holder:SetText(self:FitTimerItemName(holder,row.holderMeasure,row.holder:GetWidth()))
            row.holder:SetTextColor(color and color.r or 1,color and color.g or 1,color and color.b or 1)
            row.holderStatus:SetText(status or "")
            row.holderStatus:SetTextColor(1,0.7,0.3)
            row.winner:SetText(awarded and self:DisplayName(item.winner) or "Awaiting award")
            row.bar:SetMinMaxValues(0,entry.maxSeconds or 1); row.bar:SetValue(remaining or 0)
            if remaining==nil then row.bar:SetStatusBarColor(0.35,0.35,0.38)
            elseif remaining<=cfg.urgent then row.bar:SetStatusBarColor(0.85,0.15,0.15)
            elseif remaining<=cfg.early then row.bar:SetStatusBarColor(0.95,0.6,0.1)
            else row.bar:SetStatusBarColor(0.2,0.65,0.3) end
            row.countdown:SetText(label)
            local inTrade=awarded and self:EntryInTrade(entry,item.winner)
            row.inTrade=inTrade or false
            local inRange=awarded and entry.holder==self.me and self:WinnerInTradeRange(item.winner)
            row.inRange=inRange or false
            local pending=awarded and entry.delivery~="delivered" and self:PendingTradeCount(item.winner,entry.holder) or 0
            row.tradeSummary:SetText(pending>0 and (pending..(pending==1 and " item for " or " items for ")..self:DisplayName(item.winner)) or "")
            local selfHeld=awarded and item.winner==entry.holder and entry.delivery~="delivered"
            if selfHeld then row.tradeSummary:SetText("Confirm via Manage") end
            if entry.delivery=="delivered" then row.tradeSummary:SetText(entry.deliveryMethod=="automatic" and "Delivered automatically" or entry.deliveryMethod=="bag_handover" and "Verified handover" or (entry.deliveryMethod=="masterloot" or entry.deliveryMethod=="masterloot_native") and "Delivered by Master Loot" or "Confirmed manually")
            elseif entry.delivery=="review" then row.tradeSummary:SetText("Delivery needs review") end
            if entry.manual and awarded and entry.delivery~="delivered" then row.tradeSummary:SetText("Confirm via Manage") end
            local queueable=self:CanQueueTrackedLoot(entry)
            row.tradeLabel:SetText(entry.delivery=="delivered" and "Delivered" or (selfHeld and "Already held" or (awarded and (inTrade and "In trade" or "Trade") or (queueable and "Queue" or (entry.item and "Queued" or "Recorded")))))
            local canTrade=(queueable and self:IsMaster() and (not self.demo or entry.demo)) or (not self.demo and not entry.manual and entry.delivery~="delivered" and awarded and entry.holder==self.me and item.winner~=self.me)
            row.trade:SetEnabled(canTrade)
            row.trade:GetFontString():Hide()
            if canTrade and inRange then row.tradeLabel:SetTextColor(0.2,1,0.2)
            elseif canTrade then row.tradeLabel:SetTextColor(0.84,0.86,0.89)
            else row.tradeLabel:SetTextColor(0.50,0.52,0.55) end
            row.trade:SetScript("OnClick",function()
                self.selectedTracked=entry.id
                if awarded then self:StartTrade(entry.id) elseif self:CanQueueTrackedLoot(entry) then self:QueueTrackedLoot(entry.id) end
                self:RenderLootWindows()
            end)
        end
    end
    local entry=s.trackedLoot and self:TrackedByID(self.selectedTracked or 0)
    local item=entry and entry.item and self:ItemByID(entry.item)
    local master=self:IsMaster()
    local unqueued,seen=0,{}
    for _,value in ipairs(s.trackedLoot or {}) do
        if self:CanQueueTrackedLoot(value) and not seen[value.guid] then unqueued=unqueued+1;seen[value.guid]=true end
    end
    panel.queueAll:SetEnabled(master and not s.masterBlocked and unqueued>0 and #s.items+unqueued<=40)
    panel.selectionIcon:SetShown(entry~=nil)
    if entry then panel.selectionIcon:SetTexture(self:ItemIcon(entry)) end
    panel.selection:SetText(entry and (entry.link.." | Holder: "..(entry.holder~="" and entry.holder or "Unknown").." | "..(entry.delivery or "Unawarded").."\n"..(entry.delivery=="review" and "Award changed after delivery: arrange transfer and confirm again." or "Confirm delivery after the recipient receives the item.")) or "Select an item in Loot / Trade first.")
    panel.queue:SetEnabled(master and entry and self:CanQueueTrackedLoot(entry))
    local selected=self:ItemByID(self.selectedItem or 0)
    panel.attach:SetEnabled(master and entry and self:CanQueueTrackedLoot(entry) and selected and not selected.lootGUID and selected.link==entry.link)
    panel.delivered:SetEnabled(master and item and item.status=="awarded" and entry.delivery~="delivered")
    panel.reopen:SetEnabled(master and entry and (entry.delivery=="delivered" or entry.delivery=="review"))
    panel.setHolder:SetEnabled(master and entry~=nil)
    panel.auto:SetEnabled(self:IsLeader());self:SetSettingsToggle(panel.auto,s.autoCollect~=false)
    panel.previous:SetEnabled(panel.page>0)
    panel.next:SetEnabled((panel.page+1)*(panel.visibleRows or 6)<#rows)
    self:RefreshRailArrow(panel.previous);self:RefreshRailArrow(panel.next)
    local pages=math.max(1,math.ceil(#rows/(panel.visibleRows or 6)))
    panel.pageLabel:SetText(panel.pageLabel:GetWidth()<80 and ((panel.page+1).."/"..pages) or ("Page "..(panel.page+1).." / "..pages))
end

-- Shared public tracking only: no delivery, voting or management controls.
-- Shorten display text only; the original item link and identity stay intact.
function A:FitTimerItemName(link,measure,width)
    link=type(link)=="string" and link or "Unknown item"
    local name=(link:match("|h(.-)|h") or link):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    local color=link:match("|c(%x%x%x%x%x%x%x%x)")
    local function measured(value)
        measure:SetText(value)
        local ok,size=pcall(measure.GetStringWidth,measure)
        if ok and type(size)=="number" and size==size and size>=0 then return size end
        return #value*6
    end
    local value=name
    if measured(name)>width then
        -- Boundaries preserve complete UTF-8 characters when adding an ellipsis.
        local ends={0}
        for i=1,#name do
            local nextByte=name:byte(i+1)
            if not nextByte or nextByte<128 or nextByte>=192 then ends[#ends+1]=i end
        end
        local low,high=0,#ends-1
        while low<high do
            local mid=math.ceil((low+high)/2)
            if measured(name:sub(1,ends[mid+1]).."...")<=width then low=mid else high=mid-1 end
        end
        value=name:sub(1,ends[low+1]).."..."
    end
    return color and ("|c"..color..value.."|r") or value
end

function A:BuildLootTimerUI(u,window,text,button)
    local p={rows={}}
    u.lootTimers=p
    p.window=window("SanguineLootCouncilTimer","Sanguine Loot Tools - Timer",600,320,nil,false)
    p.itemHeader=text(p.window,"Item",11,24,-50,210)
    p.timeHeader=text(p.window,"Trade time",11,250,-50,145)
    p.holderHeader=text(p.window,"Holder",11,420,-50,155)
    p.empty=text(p.window,"No loot timers to show.",13,24,-170,550)
    p.empty:SetJustifyH("CENTER")
    p.scroll=self:CreateScrollFrame(p.window)
    p.scroll:SetPoint("TOPLEFT",18,-68);p.scroll:SetSize(546,232)
    p.child=CreateFrame("Frame",nil,p.scroll)
    p.child:SetSize(546,1);p.scroll:SetScrollChild(p.child)
    -- Active tracking is bounded at 80 copies. Keep each physical copy in the
    -- scroll child so mouse wheel and scrollbar expose the complete list.
    for i=1,80 do
        local row=CreateFrame("Frame",nil,p.child)
        row:SetPoint("TOPLEFT",0,-(i-1)*44);row:SetSize(546,42);row:EnableMouse(false)
        self:StyleDataRow(row,i)
        row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetPoint("TOPLEFT",4,-4);row.icon:SetSize(34,34)
        row.caption=text(row,"",11,46,-13,170);row.caption:SetHeight(16);row.caption:SetMaxLines(1);row.caption:SetWordWrap(false)
        row.measure=text(row,"",11,0,0);row.measure:Hide()
        row.bar=CreateFrame("StatusBar",nil,row);row.bar:SetPoint("TOPLEFT",232,-12);row.bar:SetSize(145,18)
        row.bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
        row.countdown=row.bar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row.countdown:SetPoint("CENTER");row.countdown:SetWidth(141);row.countdown:SetMaxLines(1)
        row.holder=text(row,"",11,402,-7,155);row.holder:SetMaxLines(1)
        row.holderStatus=text(row,"",9,402,-25,155);row.holderStatus:SetMaxLines(1)
        p.rows[i]=row
    end
    self:LayoutLootTimer()
end

function A:LayoutLootTimer()
    local p=self.ui.lootTimers
    local w,h=p.window:GetWidth(),p.window:GetHeight()
    local width=w-54
    p.scroll:SetSize(width,math.max(44,h-88));p.child:SetWidth(width)
    local itemWidth=math.max(90,w-448)
    local timeX=itemWidth+62
    local timeWidth=math.min(145,math.max(100,w*.23))
    local holderX=timeX+timeWidth+16
    local holderWidth=math.max(40,width-holderX-8)
    p.itemHeader:SetWidth(itemWidth+30)
    p.timeHeader:ClearAllPoints();p.timeHeader:SetPoint("TOPLEFT",p.window,"TOPLEFT",18+timeX,-50);p.timeHeader:SetWidth(timeWidth)
    p.holderHeader:ClearAllPoints();p.holderHeader:SetPoint("TOPLEFT",p.window,"TOPLEFT",18+holderX,-50);p.holderHeader:SetWidth(holderWidth)
    for _,header in ipairs({p.itemHeader,p.timeHeader,p.holderHeader}) do header:SetTextColor(.80,.74,.57) end
    p.empty:SetWidth(w-48)
    for _,row in ipairs(p.rows) do
        row:SetWidth(width);row.caption:SetWidth(itemWidth)
        row.bar:ClearAllPoints();row.bar:SetPoint("TOPLEFT",timeX,-12);row.bar:SetWidth(timeWidth);row.countdown:SetWidth(timeWidth-4)
        row.holder:ClearAllPoints();row.holder:SetPoint("TOPLEFT",holderX,-7);row.holder:SetWidth(holderWidth)
        row.holderStatus:ClearAllPoints();row.holderStatus:SetPoint("TOPLEFT",holderX,-25);row.holderStatus:SetWidth(holderWidth)
    end
    self:ClampLootTimerScroll()
end

function A:ClampLootTimerScroll(reset)
    local p=self.ui.lootTimers
    local height=math.max(1,(p.count or 0)*44-2)
    p.child:SetHeight(height)
    local maximum=math.max(0,height-p.scroll:GetHeight())
    p.scroll:SetVerticalScroll(reset and 0 or math.min(p.scroll:GetVerticalScroll(),maximum))
    self:RefreshScrollChrome(p.scroll,maximum)
end

function A:ShowLootTimers()
    self:BuildUI();self:RenderLootTimers();self.ui.lootTimers.window:Show()
end

function A:RenderLootTimers()
    local p=self.ui and self.ui.lootTimers
    if not p then return end
    local sid=self.state and self.state.id
    local reset=p.sid~=sid
    p.sid=sid
    local rows={}
    for _,entry in ipairs(self.state and self.state.trackedLoot or {}) do
        if entry.delivery~="delivered" then rows[#rows+1]=entry end
    end
    -- Stable identities keep rows steady while their countdowns change.
    table.sort(rows,function(a,b) return a.id<b.id end)
    p.count=#rows
    p.empty:SetShown(#rows==0)
    p.empty:SetText(self.demo and "No demo loot timers yet. Award an item in Voting first." or "No loot timers to show.")
    self:ClampLootTimerScroll(reset)
    local cfg=self:WarningSettings()
    for i,row in ipairs(p.rows) do
        local entry=rows[i];row:SetShown(entry~=nil);row.tracked=entry and entry.id
        if entry then
            row.icon:SetTexture(self:ItemIcon(entry))
            local key=entry.link..":"..row.caption:GetWidth()
            if row.captionKey~=key then
                row.caption:SetText(self:FitTimerItemName(entry.link,row.measure,row.caption:GetWidth()))
                row.captionKey=key
            end
            local remaining,label=self:TradeRemaining(entry)
            row.bar:SetMinMaxValues(0,entry.maxSeconds or entry.seconds or 1);row.bar:SetValue(remaining or 0)
            if remaining==nil then row.bar:SetStatusBarColor(0.35,0.35,0.38)
            elseif remaining<=cfg.urgent then row.bar:SetStatusBarColor(0.85,0.15,0.15)
            elseif remaining<=cfg.early then row.bar:SetStatusBarColor(0.95,0.6,0.1)
            else row.bar:SetStatusBarColor(0.2,0.65,0.3) end
            row.countdown:SetText(label)
            local holder,status,color=self:LootHolderInfo(entry.holder)
            row.holder:SetText(holder);row.holder:SetTextColor(color and color.r or 1,color and color.g or 1,color and color.b or 1)
            row.holderStatus:SetText(self.demo and entry.demo and "Simulated loot / timer" or (status or ""));row.holderStatus:SetTextColor(1,0.7,0.3)
        end
    end
end

function A:ShowLootManagement()
    if not self:IsMaster() then self:Print("Only the current master looter can manage loot delivery.");return end
    self:BuildUI()
    local entry=self.state.trackedLoot and self:TrackedByID(self.selectedTracked or 0)
    if not entry then self:Print("Select an item in Loot / Trade first.");return end
    self:RenderLootWindows()
    local panel=self.ui.lootPanels.timer
    panel.manage:Show();self:FocusWindow(panel.manage);panel.window:Hide()
end
