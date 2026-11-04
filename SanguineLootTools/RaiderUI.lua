local _,A=...

function A:ResponseItems()
    local rows,hidden={},0
    for _,item in ipairs(self.state and self.state.items or {}) do
        -- Keep expired rounds for review while awaiting an award. Completed
        -- awards belong in Voting/History, not a later response prompt.
        if not item.automaticAssignment and (item.status=="open" or item.status=="closed") then
            local status,reason=self:ClassEligibility(item)
            if status=="Restricted" then hidden=hidden+1
            else rows[#rows+1]={item=item,status=status,reason=reason} end
        end
    end
    return rows,hidden
end

-- Receipts are authoritative personal UI overlays, never replicated council state.
function A:PersonalResponse(item)
    if not item then return end
    local actual=item.responses[self.me]
    local receipt=self.responseReceipts and self.responseReceipts[item.id]
    if receipt and self.state and receipt.sid==self.state.id and receipt.round==item.responseRound
        and (not actual or receipt.revision>(actual.revision or 0)) then return receipt end
    return actual
end
function A:PendingPersonalResponse(item)
    local pending=item and self.pendingPersonalResponses and self.pendingPersonalResponses[item.id]
    if pending and self.state and pending.sid==self.state.id and pending.round==item.responseRound then
        local actual=item.responses[self.me]
        if actual and actual.choice==pending.choice and actual.note==pending.note and self:SameEquipment(actual.equipment,pending.equipment) then
            self.pendingPersonalResponses[item.id]=nil;return
        end
        return pending
    end
end

-- The tick means the player has chosen, not that the host has acknowledged it.
-- Keep this local preview separate from authoritative council/award state.
function A:PersonalSelection(item)
    return self:PendingPersonalResponse(item) or self:PersonalResponse(item)
end
function A:PreparePersonalResponse(data)
    self.personalResponseSerial=(self.personalResponseSerial or 0)%1000000000+1
    data.responseRequest=self.personalResponseSerial
    self.pendingPersonalResponses=self.pendingPersonalResponses or {}
    self.pendingPersonalResponses[data.item]={sid=data.sid,round=data.responseRound,request=data.responseRequest,choice=data.choice,note=data.note,equipment=self.Copy(data.equipment)}
end
function A:ClearPendingPersonalResponse(request)
    local changed=false
    for id,value in pairs(self.pendingPersonalResponses or {}) do
        if value.request==request then self.pendingPersonalResponses[id]=nil;changed=true end
    end
    if changed and self.ui then self:Render() end
end
function A:AcceptPersonalReceipt(data)
    if type(data)~="table" or not self.state or data[1]~=self.state.id then return false end
    local item=type(data[2])=="number" and self:ItemByID(data[2])
    if not item or data[3]~=item.responseRound or type(data[4])~="number" or not self:ResponseOption(data[4],item)
        or type(data[5])~="number" or data[5]%1~=0 or data[5]<1 then return false end
    local old=self:PersonalResponse(item)
    if not old or data[5]>=(old.revision or 0) then
        self.responseReceipts=self.responseReceipts or {}
        self.responseReceipts[item.id]={sid=data[1],round=data[3],choice=data[4],revision=data[5]}
    end
    local pending=self:PendingPersonalResponse(item)
    if pending and pending.request==data[6] then self.pendingPersonalResponses[item.id]=nil end
    self:Render();return true
end

function A:SelectResponseItem(id)
    for _,row in ipairs(self:ResponseItems()) do
        if row.item.id==id then
            self.popupItem=id
            self.popupPinned={sid=self.state.id,item=id,round=row.item.responseRound}
            self:Render()
            return true
        end
    end
    return false
end

function A:ResponseEmptyMessage(hidden)
    if not self.state then return "No active session" end
    if (hidden or 0)>0 then return "No class-eligible items open" end
    if #self.state.items==0 then return "No loot queued" end
    for _,item in ipairs(self.state.items) do
        if item.status=="queued" then return "Waiting for responses to open" end
    end
    return "Responses closed"
end

function A:BuildResponseRail(u,p,text,button)
    u.responseProgress=text(p,"",11,92,-42,635)
    local rail=CreateFrame("Frame",nil,p)
    rail:SetPoint("TOPLEFT",16,-58);rail:SetSize(56,300)
    u.responseRail=rail;u.responseItemButtons={}
    for i=1,6 do
        local b=button(rail,"",5,-(i-1)*43,40,function() end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel",function(_,delta) if delta~=0 then A:MoveResponseRail(delta>0 and -1 or 1) end end)
        b:SetHeight(38);b:SetNormalTexture("");b:SetPushedTexture("")
        self:StylePanel(b)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetPoint("TOPLEFT",4,-4);b.icon:SetSize(30,30)
        b.answered=b:CreateTexture(nil,"OVERLAY");b.answered:SetTexture("Interface/RaidFrame/ReadyCheck-Ready")
        b.answered:SetPoint("BOTTOMRIGHT",3,-3);b.answered:SetSize(20,20)
        b.unknown=text(b,"?",13,0,-1,14);b.unknown:SetTextColor(1,0.8,0.2)
        b:SetScript("OnClick",function() if b.itemID then A:SelectResponseItem(b.itemID) end end)
        b:SetScript("OnEnter",function()
            local item=A:ItemByID(b.itemID)
            if not item then return end
            GameTooltip:SetOwner(b,"ANCHOR_RIGHT");GameTooltip:SetHyperlink(item.link)
            GameTooltip:AddLine(b.eligibility=="Unknown" and ("Eligibility unknown: "..(b.reason or "Awaiting item data")) or "Usable by your class",1,0.8,0.4,true)
            local response=A:PersonalSelection(item)
            GameTooltip:AddLine(response and ("Your response: "..A:ResponseLabel(response.choice,item)) or "Choose a response",1,1,1,true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        b:Hide();u.responseItemButtons[i]=b
    end
    u.responseRailPage=text(rail,"",10,0,-258,52)
    u.responseRailPrevious=button(rail,"^",0,-278,25,function() A:MoveResponseRail(-1) end)
    u.responseRailNext=button(rail,"v",28,-278,25,function() A:MoveResponseRail(1) end)
    self:StyleRailArrow(u.responseRailPrevious,-1);self:StyleRailArrow(u.responseRailNext,1)
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel",function(_,delta) if delta~=0 then A:MoveResponseRail(delta>0 and -1 or 1) end end)
    rail:EnableMouseWheel(true)
    rail:SetScript("OnMouseWheel",function(_,delta) if delta~=0 then A:MoveResponseRail(delta>0 and -1 or 1) end end)
end

function A:ResponseEligibilityKey(rows,hidden)
    local parts={self.state and self.state.id or "",tostring(hidden)}
    for _,row in ipairs(rows) do
        parts[#parts+1]=row.item.id..":"..(row.item.responseRound or 0)..":"..row.status
    end
    return table.concat(parts,"|")
end

function A:RenderResponseRail(rows,hidden)
    if not self.ui then return end
    if not rows then rows,hidden=self:ResponseItems() end
    local u=self.ui
    local answered=0
    for i,row in ipairs(rows) do
        if self:PersonalSelection(row.item) then answered=answered+1 end
        if row.item.id==self.popupItem and self.responseRailSelected~=self.popupItem then self.responseRailPage=math.floor((i-1)/6) end
    end
    self.responseRailSelected=self.popupItem
    local pages=math.max(1,math.ceil(#rows/6))
    self.responseRailPage=math.max(0,math.min(self.responseRailPage or 0,pages-1))
    for i,b in ipairs(u.responseItemButtons) do
        local row=rows[self.responseRailPage*6+i]
        b:SetShown(row~=nil);b.itemID=row and row.item.id
        b.eligibility=row and row.status;b.reason=row and row.reason
        if row then
            b.icon:SetTexture(self:ItemIcon(row.item))
            b.answered:SetShown(self:PersonalSelection(row.item)~=nil)
            b.unknown:SetShown(row.status=="Unknown")
            local selected=row.item.id==self.popupItem
            b:SetBackdropBorderColor(selected and 1 or 0.4,selected and 0.8 or 0.45,0.35)
        end
    end
    u.responseProgress:SetText(#rows>0 and (answered.." of "..#rows.." items answered") or self:ResponseEmptyMessage(hidden))
    u.responseRailPage:SetText(#rows>6 and ((self.responseRailPage+1).."/"..pages) or "")
    u.responseRailPrevious:SetShown(#rows>6);u.responseRailNext:SetShown(#rows>6)
    u.responseRailPrevious:SetEnabled(self.responseRailPage>0);u.responseRailNext:SetEnabled(self.responseRailPage<pages-1)
    self:RefreshRailArrow(u.responseRailPrevious);self:RefreshRailArrow(u.responseRailNext)
    self.responseEligibilityKey=self:ResponseEligibilityKey(rows,hidden)
end

function A:MoveResponseRail(direction)
    local rows,hidden=self:ResponseItems()
    self.responseRailPage=math.max(0,math.min((self.responseRailPage or 0)+direction,math.max(0,math.ceil(#rows/6)-1)))
    self:RenderResponseRail(rows,hidden)
end

function A:TickResponseEligibility()
    if not self.ui or not self.state then return end
    local rows,hidden=self:ResponseItems()
    if self.responseEligibilityKey~=self:ResponseEligibilityKey(rows,hidden) then self:Render()
    elseif self.ui.popup:IsShown() then self:RenderResponseRail(rows,hidden) end
end
