local _, A = ...
-- Solid textures avoid the translucent tooltip artwork multiplying panel
-- opacity differently between clients. Every addon-owned surface shares this.
function A:StylePanel(frame, headerHeight)
    frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}})
    frame:SetBackdropColor(0.055,0.06,0.07,1)
    frame:SetBackdropBorderColor(0.26,0.28,0.31,1)
    if headerHeight then
        local band=frame:CreateTexture(nil,"BACKGROUND")
        band:SetPoint("TOPLEFT",1,-1);band:SetPoint("TOPRIGHT",-1,-1);band:SetHeight(headerHeight)
        band:SetColorTexture(0.10,0.11,0.13,1)
        frame.headerBand=band
    end
end

-- Keep thin button edges inside the bounds at any effective UI scale.
function A:StyleButtonOutline(b)
    if type(b.sltOutline)~="table" then
        b:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
        b:SetBackdropColor(.12,.13,.15,1)
        b.sltOutline={}
        for _,edge in ipairs({"top","bottom","left","right"}) do
            local line=b:CreateTexture(nil,"OVERLAY");line:SetColorTexture(.26,.28,.31,1)
            b.sltOutline[edge]=line
        end
    end
    local scale=b:GetEffectiveScale()
    if type(scale)~="number" or scale~=scale or scale<=0 or scale>100 then scale=1 end
    local pixel=1/scale
    local e=b.sltOutline
    e.top:ClearAllPoints();e.top:SetPoint("TOPLEFT",0,0);e.top:SetPoint("TOPRIGHT",0,0);e.top:SetHeight(pixel)
    e.bottom:ClearAllPoints();e.bottom:SetPoint("BOTTOMLEFT",0,0);e.bottom:SetPoint("BOTTOMRIGHT",0,0);e.bottom:SetHeight(pixel)
    e.left:ClearAllPoints();e.left:SetPoint("TOPLEFT",0,-pixel);e.left:SetPoint("BOTTOMLEFT",0,pixel);e.left:SetWidth(pixel)
    e.right:ClearAllPoints();e.right:SetPoint("TOPRIGHT",0,-pixel);e.right:SetPoint("BOTTOMRIGHT",0,pixel);e.right:SetWidth(pixel)
end

function A:StyleDataRow(row,index)
    if row.SetBackdrop then row:SetBackdrop(nil) end
    row.shade=row:CreateTexture(nil,"BACKGROUND")
    row.shade:SetAllPoints();row.shade:SetColorTexture(1,1,1,index%2==0 and 0.045 or 0.015)
end

-- A shared, template-free scrollbar keeps the same dark chrome on every client.
-- The native ScrollFrame and Slider still own clipping, dragging and hit testing.
local function scrollNumber(value)
    return type(value)=="number" and value==value and value>=0 and value<10000000 and value or 0
end
function A:RefreshScrollChrome(scroll,range,offset)
    local chrome=scroll.sltScrollChrome
    if type(chrome)~="table" or chrome.updating then return end
    range=scrollNumber(range or scroll:GetVerticalScrollRange())
    local current=scrollNumber(offset or scroll:GetVerticalScroll())
    offset=math.max(0,math.min(range,current))
    local viewport=scrollNumber(scroll:GetHeight())
    local track=math.max(1,viewport-34)
    local extent=range>0 and math.min(track,math.max(24,track*viewport/(viewport+range))) or track
    chrome.updating=true
    chrome.slider:SetMinMaxValues(0,range)
    chrome.thumb:SetSize(10,extent)
    chrome.slider:SetValue(offset)
    if current~=offset then scroll:SetVerticalScroll(offset) end
    chrome.up:SetEnabled(offset>0);chrome.down:SetEnabled(offset<range)
    chrome.rail:SetShown(range>0 and viewport>=40)
    chrome.range,chrome.offset=range,offset
    chrome.updating=false
end
function A:CreateScrollFrame(parent)
    local scroll=CreateFrame("ScrollFrame",nil,parent)
    local rail=CreateFrame("Frame",nil,scroll)
    rail:SetPoint("TOPLEFT",scroll,"TOPRIGHT",4,0)
    rail:SetPoint("BOTTOMLEFT",scroll,"BOTTOMRIGHT",4,0);rail:SetWidth(14)
    local slider=CreateFrame("Slider",nil,rail,"BackdropTemplate")
    slider:SetPoint("TOPLEFT",0,-17);slider:SetPoint("BOTTOMRIGHT",0,17)
    slider:SetOrientation("VERTICAL");slider:SetValueStep(1);slider:SetMinMaxValues(0,0);slider:EnableMouse(true)
    slider:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
    slider:SetBackdropColor(.035,.04,.05,1);slider:SetBackdropBorderColor(.14,.15,.18,1)
    slider:SetThumbTexture("Interface/Buttons/WHITE8X8")
    local thumb=slider:GetThumbTexture();thumb:SetSize(10,24);thumb:SetVertexColor(.29,.31,.35,1)
    slider:SetScript("OnEnter",function() thumb:SetVertexColor(.42,.44,.49,1) end)
    slider:SetScript("OnLeave",function() thumb:SetVertexColor(.29,.31,.35,1) end)
    local chrome={rail=rail,slider=slider,thumb=thumb,updating=false,range=0,offset=0}
    scroll.sltScrollChrome=chrome
    local function step(direction)
        local range=scrollNumber(scroll:GetVerticalScrollRange())
        local offset=scrollNumber(scroll:GetVerticalScroll())
        scroll:SetVerticalScroll(math.max(0,math.min(range,offset+direction*36)))
        A:RefreshScrollChrome(scroll)
    end
    local function arrow(point,direction)
        local b=CreateFrame("Button",nil,rail)
        b:SetSize(14,14);b:SetPoint(point,0,0)
        b:SetHighlightTexture("Interface/Buttons/WHITE8X8","ADD")
        b:GetHighlightTexture():SetVertexColor(.2,.22,.26,.45)
        A:StyleRailArrow(b,direction,10)
        b:SetScript("OnClick",function() step(direction) end)
        b:EnableMouseWheel(true);b:SetScript("OnMouseWheel",function(_,delta) step(-delta) end)
        return b
    end
    chrome.up=arrow("TOP",-1);chrome.down=arrow("BOTTOM",1)
    slider:SetScript("OnValueChanged",function(_,value)
        if chrome.updating then return end
        local range=scrollNumber(scroll:GetVerticalScrollRange())
        scroll:SetVerticalScroll(math.max(0,math.min(range,scrollNumber(value))))
        A:RefreshScrollChrome(scroll)
    end)
    slider:EnableMouseWheel(true);slider:SetScript("OnMouseWheel",function(_,delta) step(-delta) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(_,delta) step(-delta) end)
    scroll:HookScript("OnScrollRangeChanged",function(_,_,range) A:RefreshScrollChrome(scroll,range) end)
    scroll:HookScript("OnVerticalScroll",function(_,offset) A:RefreshScrollChrome(scroll,nil,offset) end)
    scroll:HookScript("OnSizeChanged",function() A:RefreshScrollChrome(scroll) end)
    scroll:HookScript("OnShow",function() A:RefreshScrollChrome(scroll) end)
    rail:Hide()
    self.scrollFrames=self.scrollFrames or {};self.scrollFrames[#self.scrollFrames+1]=scroll
    return scroll
end

-- Link insertion moved between chat namespaces across client branches.
-- Post-hooks leave Blizzard/other addons' click handling and return values intact.
function A:CaptureManualLootLink(link)
    local u=self.ui
    if not u or not u.itemTools or u.itemTools:IsShown()~=true or not self:IsMaster()
        or u.itemInput:IsEnabled()~=true or u.itemInput:HasFocus()~=true then return false end
    link=self:EquipmentLink(link)
    if not link then return false end
    -- One item per manual entry: replace rather than concatenate. Multiple
    -- native callbacks for the same click therefore cannot duplicate the link.
    self.manualBagSelection=nil
    if u.itemInput:GetText()~=link then u.itemInput:SetText(link) end
    u.itemInput:SetCursorPosition(#link)
    return true
end
function A:CaptureManualBagSlot(bag,slot)
    local u=self.ui
    if not u or u.itemTools:IsShown()~=true or not self:IsMaster()
        or u.itemInput:IsEnabled()~=true or u.itemInput:HasFocus()~=true then return false end
    local sample=self:ReadManualBagItem(bag,slot)
    if not sample then
        -- Never substitute a different matching copy when the clicked stack/slot is unreadable.
        self.manualBagSelection={sid=self.state and self.state.id,unavailable=true}
        return false
    end
    if not self:CaptureManualLootLink(sample.link) then return false end
    self.manualBagSelection={sid=self.state and self.state.id,guid=sample.guid,link=sample.link}
    return true
end

function A:InstallManualLootLinkHooks()
    if type(hooksecurefunc)~="function" then return end
    local installed=self.manualLootLinkHooks or {};self.manualLootLinkHooks=installed
    local function capture(link) A:CaptureManualLootLink(link) end
    if not installed.modern and type(ChatFrameUtil)=="table" and type(ChatFrameUtil.InsertLink)=="function" then
        installed.modern=pcall(hooksecurefunc,ChatFrameUtil,"InsertLink",capture)
    end
    if not installed.legacy and type(ChatEdit_InsertLink)=="function" then
        installed.legacy=pcall(hooksecurefunc,"ChatEdit_InsertLink",capture)
    end
    if not installed.modified and type(HandleModifiedItemClick)=="function" then
        installed.modified=pcall(hooksecurefunc,"HandleModifiedItemClick",function(link,location)
            local modified=false
            if type(IsModifiedClick)=="function" then modified=IsModifiedClick("CHATLINK")==true
            elseif type(IsShiftKeyDown)=="function" then modified=IsShiftKeyDown()==true end
            if modified then
                capture(link)
                if location and type(location.GetBagAndSlot)=="function" then
                    local ok,bag,slot=pcall(location.GetBagAndSlot,location)
                    if ok then A:CaptureManualBagSlot(bag,slot) end
                end
            end
        end)
    end
    local function bagClick(control)
        if type(IsModifiedClick)=="function" and IsModifiedClick("CHATLINK")~=true then return end
        if type(IsModifiedClick)~="function" and (type(IsShiftKeyDown)~="function" or IsShiftKeyDown()~=true) then return end
        local ok,bag,slot=pcall(function()
            return type(control.GetBagID)=="function" and control:GetBagID() or control:GetParent():GetID(),control:GetID()
        end)
        if ok then A:CaptureManualBagSlot(bag,slot) end
    end
    if not installed.bagLegacy and type(ContainerFrameItemButton_OnModifiedClick)=="function" then
        installed.bagLegacy=pcall(hooksecurefunc,"ContainerFrameItemButton_OnModifiedClick",bagClick)
    end
    if not installed.bagMixin and type(ContainerFrameItemButtonMixin)=="table" and type(ContainerFrameItemButtonMixin.OnModifiedClick)=="function" then
        installed.bagMixin=pcall(hooksecurefunc,ContainerFrameItemButtonMixin,"OnModifiedClick",bagClick)
    end
end

local function text(parent, value, size, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", x, y)
    t:SetFont(STANDARD_TEXT_FONT, size)
    if size>=14 then t:SetTextColor(0.86,0.76,0.49) else t:SetTextColor(0.84,0.86,0.89) end
    t:SetJustifyH("LEFT")
    if width then t:SetWidth(width) end
    t:SetText(value)
    return t
end

function A:RefreshRailArrow(b)
    if type(b.sltArrowParts)~="table" then return end
    local enabled=b:IsEnabled()~=false
    local r,g,blue=.60,.63,.69
    if not enabled then r,g,blue=.28,.30,.34
    elseif b.sltArrowHover then r,g,blue=.90,.92,.95 end
    for _,part in ipairs(b.sltArrowParts) do part:SetVertexColor(r,g,blue,1) end
end
function A:SetRailArrowDirection(b,direction)
    b.sltArrowDirection=direction
    if type(b.sltArrowParts)=="table" then
        b.sltArrowIcon:SetTexCoord(0,1,direction<0 and 1 or 0,direction<0 and 0 or 1)
    end
end
function A:StyleRailArrow(b,direction,size)
    b:SetText("")
    if type(b.sltArrowParts)~="table" then
        local part=b:CreateTexture(nil,"ARTWORK")
        part:SetTexture("Interface\\AddOns\\SanguineLootTools\\Assets\\Chevron","CLAMP","CLAMP","LINEAR")
        if part.SetSnapToPixelGrid then part:SetSnapToPixelGrid(false) end
        if part.SetTexelSnappingBias then part:SetTexelSnappingBias(0) end
        part:SetPoint("CENTER",0,0)
        b.sltArrowIcon=part;b.sltArrowParts={part}
    end
    b.sltArrowIcon:SetSize(size or 14,size or 14)
    self:SetRailArrowDirection(b,direction)
    b:SetScript("OnEnter",function() b.sltArrowHover=true;A:RefreshRailArrow(b) end)
    b:SetScript("OnLeave",function() b.sltArrowHover=false;A:RefreshRailArrow(b) end)
    self:RefreshRailArrow(b)
    b:HookScript("OnEnable",function() A:RefreshRailArrow(b) end)
    b:HookScript("OnDisable",function() A:RefreshRailArrow(b) end)
end

function A:RefreshCrossButton(b)
    if type(b.sltCrossParts)~="table" then return end
    local r,g,blue=.84,.86,.89
    if b:IsEnabled()==false then r,g,blue=.42,.44,.48
    elseif b.sltCrossHover then r,g,blue=1,1,1 end
    for _,part in ipairs(b.sltCrossParts) do part:SetColorTexture(r,g,blue,1) end
end
function A:StyleCrossButton(b)
    b:SetText("");b.sltCrossParts={}
    for _,angle in ipairs({math.pi/4,-math.pi/4}) do
        local part=b:CreateTexture(nil,"ARTWORK");part:SetSize(15,2)
        part:SetPoint("CENTER",0,0);part:SetRotation(angle)
        b.sltCrossParts[#b.sltCrossParts+1]=part
    end
    b:SetScript("OnEnter",function() b.sltCrossHover=true;A:RefreshCrossButton(b) end)
    b:SetScript("OnLeave",function() b.sltCrossHover=false;A:RefreshCrossButton(b) end)
    self:RefreshCrossButton(b)
end

local function button(parent, label, x, y, width, action)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 26)
    b:SetPoint("TOPLEFT", x, y)
    A:StylePanel(b)
    b:SetBackdropColor(0.12,0.13,0.15,1)
    local labelText=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    labelText:SetPoint("LEFT",5,0);labelText:SetPoint("RIGHT",-5,0)
    labelText:SetJustifyH("CENTER");labelText:SetMaxLines(1)
    b:SetFontString(labelText)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetHighlightTexture("Interface/Buttons/WHITE8X8","ADD")
    b:GetHighlightTexture():SetVertexColor(0.35,0.39,0.45,0.18)
    b:SetPushedTexture("Interface/Buttons/WHITE8X8")
    b:GetPushedTexture():SetVertexColor(0.02,0.025,0.03,0.6)
    b:SetText(label)
    b:SetScript("OnClick", action)
    return b
end

local function edit(parent, x, y, width, hint)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, 26)
    e:SetPoint("TOPLEFT", x, y)
    A:StylePanel(e);e:SetBackdropColor(0.025,0.028,0.035,1)
    e:SetFontObject("ChatFontNormal");e:SetTextColor(0.90,0.91,0.93)
    e:SetTextInsets(8,8,0,0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(500)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e.hint=text(parent, hint, 11, x, y + 18, width)
    e.hint:SetHeight(14);e.hint:SetMaxLines(1)
    return e
end

local function window(name, title, w, h, transient)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) A:BeginWindowMove(frame) end)
    f:SetScript("OnDragStop",function(frame) A:FinishWindowMove(frame,name) end)
    A:StylePanel(f,34)
    f.title = text(f, title, 14, 18, -18, w - 60)
    A:LayoutTitleText(f.title,18,w-60,34)
    local close = button(f,"×",0,0,22,function() f:Hide() end)
    close:SetSize(22,22);close:ClearAllPoints();close:SetPoint("TOPRIGHT", -6, -6)
    A:StyleCrossButton(close)
    f.closeButton=close
    table.insert(UISpecialFrames, name)
    f:Hide()
    A.allWindowFrames = A.allWindowFrames or {}
    A.allWindowFrames[#A.allWindowFrames+1] = f
    A.windowFrames = A.windowFrames or {}
    if not transient then A.windowFrames[#A.windowFrames+1] = {frame=f,name=name} end
    A:InstallWindowChrome(f,name,button)
    A:RegisterWindowLayers(f)
    return f
end

function A:BuildCorrectionUI(u,window,text,button,edit)
    u.correction=window("SanguineLootCouncilCorrection","Change winner  |  Master Looter",620,430)
    u.correctionItem=text(u.correction,"",14,20,-55,575)
    u.correctionCurrent=text(u.correction,"",12,20,-100,575)
    text(u.correction,"Replacement winner",12,20,-134,575)
    u.correctionTargetDropdown=button(u.correction,"Choose a replacement",20,-154,575,function() end)
    u.correctionTargetDropdown:SetHeight(28)
    self:BindSettingsDropdown(u.correctionTargetDropdown,function() return A:CorrectionDropdownChoices() end,
        function(target) A:SelectCorrectionCandidate(target) end,button)
    u.correctionEligibility=text(u.correction,"",12,20,-190,575)
    u.correctionEligibility:SetHeight(42);u.correctionEligibility:SetJustifyV("TOP");u.correctionEligibility:SetMaxLines(3)
    u.correctionReason=edit(u.correction,25,-255,565,"Reason for changing winner (required)")
    u.correctionReason:SetMaxLetters(160)
    u.correctionReasonBytes=text(u.correction,"0/160",11,0,0,80)
    u.correctionReasonBytes:ClearAllPoints();u.correctionReasonBytes:SetPoint("TOPRIGHT",u.correctionReason,"TOPRIGHT",0,18)
    u.correctionReasonBytes:SetJustifyH("RIGHT");u.correctionReasonBytes:SetHeight(14);u.correctionReasonBytes:SetMaxLines(1)
    local function updateReasonCount()
        local count=#u.correctionReason:GetText()
        u.correctionReasonBytes:SetText(count.."/160")
        u.correctionReasonBytes:SetTextColor(count>160 and 1 or .8,count>160 and .2 or .8,.6)
    end
    u.correctionReason:HookScript("OnTextChanged",updateReasonCount)
    updateReasonCount()
    u.correctionStatus=text(u.correction,"",12,20,-295,575)
    u.correctionStatus:SetHeight(45);u.correctionStatus:SetJustifyV("TOP")
    u.correctReview=button(u.correction,"Review change",20,-380,280,function() A:ReviewCorrection() end)
    button(u.correction,"Cancel",315,-380,280,function() u.correction:Hide() end)
    u.correction:HookScript("OnHide",function()
        local menu=u.settingsDropdown
        if menu and menu.owner==u.correctionTargetDropdown then A:CloseSettingsDropdown() end
        u.correctionReason:ClearFocus()
    end)
end

function A:BuildUI()
    if self.ui then return end
    local u = {}
    self.ui = u
    local f = window("SanguineLootCouncilMain", "Sanguine Loot Tools  |  Loot desk", 920, 620)
    u.main = f
    u.status = text(f, "", 12, 20, -50, 875)
    u.start = button(f, "Start session", 20, -80, 125, function() A:Act("start") end)
    u.finish = button(f, "End session", 150, -80, 115, function()
        A:ReviewEndSession()
    end)
    u.settings = button(f, "Leader settings", 270, -80, 135, function() u.config:Show(); A:Render() end)
    u.myResponses = button(f, "My responses", 410, -80, 130, function() A:ShowResponses() end)
    u.lootHistory = button(f, "Loot history", 545, -80, 110, function() A:ShowHistory() end)
    u.readiness = button(f, "Version Check", 660, -80, 110, function() A:StartReadiness() end)
    u.resume = button(f, "Resume saved", 775, -80, 125, function() A:ShowConfirmation("SANGUINELOOTCOUNCIL_RESUME") end)
    u.itemInput = edit(f, 25, -140, 650, "Shift-click an item here to add it to the session")
    u.itemInput:HookScript("OnTextChanged",function()
        local chosen=A.manualBagSelection
        if chosen and A:EquipmentLink(u.itemInput:GetText())~=chosen.link then A.manualBagSelection=nil end
    end)
    u.add = button(f, "Add loot", 700, -140, 100, function()
        if not A:IsMaster() then return end
        local link=A:EquipmentLink(u.itemInput:GetText())
        if not link then A:Print("Shift-click a complete item link into Add loot.");return end
        local selection=A.manualBagSelection
        if selection and selection.sid==A.state.id and selection.unavailable then
            A:Print("That bag slot could not be verified. Split stacks into single items, then Shift-click the exact unlocked copy again.");return
        end
        local guid=selection and selection.sid==A.state.id and selection.link==link and selection.guid or nil
        local sample,why=A:FindManualBagItem(link,guid)
        if not sample then A:Print(why);return end
        local existing=A:TrackedByGUID(sample.guid)
        if existing then
            if existing.holder~=A.me then A:Print("This item copy is already tracked with another holder. Review it in Manage.");return end
            A.selectedTracked=existing.id;A:Print("That item copy is already in Loot; selecting its existing entry.")
        elseif A:Act("bagLoot",sample)==false then return end
        local added=A:TrackedByGUID(sample.guid);if added then A.selectedTracked=added.id end
        A.manualBagSelection=nil
        u.itemInput:SetText("");u.itemInput:ClearFocus();u.itemTools:Hide();A:ShowLootWindow()
    end)
    u.timers = button(f, "Timers", 810, -115, 90, function() A:ShowLootWindow("timer") end)
    u.deliveries = button(f, "Deliveries", 810, -145, 90, function() A:ShowLootWindow("deliveries") end)
    self:BuildLootUI(u, window, text, button, edit)
    self:BuildLootTimerUI(u, window, text, button)
    u.railLabel = text(f, "SESSION ITEMS", 12, 20, -185, 200)
    u.itemButtons = {}
    for i = 1, 9 do
        local row = i
        local b = button(f, "", 20, -210 - (i - 1) * 36, 220, function()
            local item=A.state and A.state.items[(A.itemPage or 0)*(A.votingItemRows or 9)+row]
            A.selectedItem = item and item.id
            A.candidatePage, A.selectedCandidate = 0, nil
            A:Render()
        end)
        u.itemButtons[i] = b
    end
    u.itemPrev = button(f, "", 20, -545, 22, function() A:MoveVotingRail(-1) end)
    u.itemNext = button(f, "", 48, -545, 22, function() A:MoveVotingRail(1) end)
    u.itemPages = text(f, "", 12, 75, -552, 120)
    u.itemIcon = f:CreateTexture(nil, "ARTWORK")
    u.itemIcon:SetSize(24, 24); u.itemIcon:SetPoint("TOPLEFT", 260, -181)
    u.itemTitle = text(f, "Select an item", 15, 292, -185, 598)
    u.itemStatus = text(f, "", 12, 260, -212, 630)
    u.itemDetails = text(f, "", 11, 260, -233, 630)
    u.itemDetails:SetMaxLines(1)
    f:SetScript("OnEnter", function(self)
        local item = A.state and A:ItemByID(A.selectedItem or 1)
        if item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.link)
            A:AddItemFacts(GameTooltip, item)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    u.oldHeading = text(f, "Candidate / response / votes / eligibility / note", 11, 260, -252, 620)
    u.candidates = {}
    for i = 1, 14 do
        local b = button(f, "", 260, -275 - (i - 1) * 27, 630, function(self)
            A.selectedCandidate = self.candidate
            A:Render()
        end)
        b:SetNormalFontObject("GameFontHighlightSmall")
        u.candidates[i] = b
    end
    u.candidatePrev = button(f, "<", 260, -415, 40, function() A.candidatePage = math.max(0, (A.candidatePage or 0) - 1); A:Render() end)
    u.candidateNext = button(f, ">", 850, -415, 40, function()
        if ((A.candidatePage or 0) + 1) * (A.votingCandidateRows or 14) < (A.candidateCount or 0) then A.candidatePage = (A.candidatePage or 0) + 1 end
        A:Render()
    end)
    u.selection = text(f, "", 12, 310, -422, 410)
    u.compareGear = button(f, "Compare gear", 730, -415, 110, function() u.voting:Show(); A:Render() end)
    u.playerHistoryTitle = text(f, "", 11, 260, -452, 510)
    u.playerHistory = button(f, "Full history", 785, -445, 105, function() A:ShowHistory(A.selectedCandidate) end)
    u.playerHistoryRows = {}
    for i = 1, 3 do
        local row = button(f, "", 260, -474 - (i - 1) * 22, 630, function() A:ShowHistory(A.selectedCandidate) end)
        row:SetSize(630, 20)
        row:SetNormalFontObject("GameFontHighlightSmall")
        row:SetScript("OnEnter", function(self)
            if self.record then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.record.item)
                GameTooltip:AddLine(date("%d %b %Y %H:%M", self.record.time or 0), 1, 1, 1)
                GameTooltip:AddLine("Response: " .. (self.record.responseLabel or A.responses[self.record.response] or "Unknown"), 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        u.playerHistoryRows[i] = row
    end
    u.open = button(f,"Open responses",260,-545,135,function() A:ReviewRelease(A.selectedItem) end)
    u.vote = button(f, "Vote / remove vote", 540, -545, 130, function() A:VoteForCandidate() end)
    u.votingDesk = button(f, "Voting", 785, -545, 105, function() u.voting:Show(); A:RenderVotingStatus() end)
    u.correctAward = button(f,"Change winner",675,-545,150,function() A:OpenCorrection() end)
    u.oldFooter = text(f, "", 11, 20, -591, 880)

    self:BuildCorrectionUI(u,window,text,button,edit)

    local c = window("SanguineLootCouncilConfig", "Raid leader settings", 570, 640)
    u.config = c
    text(c, "Only the current raid leader can change these settings.", 12, 20, -52, 530)
    u.masterName = edit(c, 25, -100, 350, "Master looter: Name-Realm (must be in the raid)")
    u.setMaster = button(c, "Assign", 395, -100, 140, function() A:Act("master", {target = u.masterName:GetText()}) end)
    u.councilName = edit(c, 25, -165, 350, "Council member: Name-Realm")
    u.toggleCouncil = button(c, "Add / remove", 395, -165, 140, function() A:Act("council", {target = u.councilName:GetText()}) end)
    u.selfVotes = button(c, "", 20, -215, 250, function() A:Act("selfVotes") end)
    u.votingRules = button(c, "Voting rules", 290, -215, 245, function() u.rules:Show(); A:RenderVotingStatus() end)
    u.responseSeconds = edit(c, 25, -265, 155, "Response time: 5–600 seconds")
    u.responseSeconds:SetMaxLetters(3)
    u.applyResponseTimer = button(c, "Apply response timer", 205, -265, 330, function()
        A:Act("responseDuration", {duration = tonumber(u.responseSeconds:GetText())})
        u.responseSeconds:ClearFocus()
    end)
    u.councilList = text(c, "", 12, 20, -310, 530)
    u.councilList:SetHeight(65)
    u.councilList:SetJustifyV("TOP")
    u.autoMaster = button(c, "", 20, -385, 530, function() A:Act("masterAutoSync") end)
    u.profileName = edit(c, 25, -450, 510, "Saved profile name (maximum 40 bytes)")
    u.profileName:SetMaxLetters(40)
    u.saveProfile = button(c, "Save / overwrite", 20, -490, 170, function()
        local name = u.profileName:GetText():match("^%s*(.-)%s*$")
        if SanguineLootCouncilDB.profiles and SanguineLootCouncilDB.profiles[name] then
            local dialog = A:ShowConfirmation("SANGUINELOOTCOUNCIL_SAVE_PROFILE", name)
            if dialog then dialog.data = name end
        else A:SaveProfile(name) end
    end)
    u.loadProfile = button(c, "Apply profile", 200, -490, 170, function()
        local name = u.profileName:GetText():match("^%s*(.-)%s*$")
        local dialog = A:ShowConfirmation("SANGUINELOOTCOUNCIL_LOAD_PROFILE", name)
        if dialog then dialog.data = name end
    end)
    u.deleteProfile = button(c, "Delete", 380, -490, 170, function()
        local name = u.profileName:GetText():match("^%s*(.-)%s*$")
        local dialog = A:ShowConfirmation("SANGUINELOOTCOUNCIL_DELETE_PROFILE", name)
        if dialog then dialog.data = name end
    end)
    u.profileList = text(c, "", 12, 20, -535, 530)
    u.profileList:SetHeight(85); u.profileList:SetJustifyV("TOP")

    u.rules = window("SanguineLootCouncilVotingRules", "Voting rules  |  Raid leader", 630, 405)
    text(u.rules, "Rules and council membership are locked while unawarded ballots are open or closed.\nThe master looter can reset those ballots before rules change.", 12, 20, -55, 585)
    u.ruleLimit = button(u.rules, "", 20, -110, 585, function() if A.state then A:UpdateVotingRule("limit", A.state.rules.limit % 3 + 1) end end)
    u.ruleVisibility = button(u.rules, "", 20, -155, 585, function()
        if A.state then local nextMode = {closed = "immediate", immediate = "own", own = "closed"}; A:UpdateVotingRule("visibility", nextMode[A.state.rules.visibility]) end
    end)
    u.ruleNames = button(u.rules, "", 20, -200, 585, function() if A.state then A:UpdateVotingRule("names", not A.state.rules.names) end end)
    text(u.rules,"Votes can be changed until the item is awarded.",12,20,-245,585)
    text(u.rules,"Voting stays open after responses expire; the master looter awards when ready.",11,20,-290,585)
    text(u.rules, "Concealed results stay on the raid leader's client. Each voter receives their own\nballot acknowledgement. The leader necessarily has access to all ballots.", 11, 20, -345, 585)

    u.voting = window("SanguineLootCouncilVoting", "Voting desk", 660, 580)
    u.votingItem = text(u.voting, "", 14, 20, -55, 615)
    u.votingStatus = text(u.voting, "", 12, 20, -90, 615)
    u.votingProgress = text(u.voting, "", 12, 20, -125, 615)
    u.votingOwn = text(u.voting, "", 12, 20, -165, 615)
    u.votingOwn:SetHeight(75); u.votingOwn:SetJustifyV("TOP")
    button(u.voting, "Previous", 20, -250, 85, function() A:CycleVotingCandidate(-1) end)
    u.votingCandidate = text(u.voting, "", 12, 115, -257, 430)
    button(u.voting, "Next", 550, -250, 85, function() A:CycleVotingCandidate(1) end)
    u.equipmentStatus = text(u.voting, "", 11, 20, -285, 615)
    u.equipmentStatus:SetMaxLines(1)
    u.equipmentRows = {}
    for i = 1, 2 do
        local row = button(u.voting, "", 20, -310 - (i - 1) * 30, 615, function() end)
        row:SetNormalFontObject("GameFontHighlightSmall")
        row:SetScript("OnEnter", function(self)
            if self.link then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        u.equipmentRows[i] = row
    end
    u.pickCandidate = button(u.voting, "Vote / remove vote for selected candidate", 20, -375, 615, function() A:VoteForCandidate() end)
    u.openVoting = button(u.voting, "Resume voting", 20, -420, 195, function() A:Act("openVoting", {item = A.selectedItem}) end)
    u.resetVoting = button(u.voting, "Reset / pause", 440, -420, 195, function()
        local dialog = A:ShowConfirmation("SANGUINELOOTCOUNCIL_RESET_BALLOT")
        if dialog then dialog.data = {sid = A.state and A.state.id, item = A.selectedItem} end
    end)
    text(u.voting, "Click Vote to choose a player. Click Voted to remove your vote. Responses close on the timer; the master looter awards from the council table.", 11, 20, -545, 615)

    local p = window("SanguineLootCouncilResponses", "Sanguine Loot Tools - Response Frame", 760, 425)
    u.popup = p
    u.popupIcon = p:CreateTexture(nil, "ARTWORK")
    u.popupIcon:SetSize(24, 24); u.popupIcon:SetPoint("TOPLEFT", 92, -61)
    u.popupItem = text(p, "No items open for responses", 17, 124, -65, 608)
    u.popupItem:SetMaxLines(1)
    u.popupStatus = text(p, "", 13, 92, -108, 640)
    u.popupFacts = text(p, "", 10, 92, -125, 640)
    u.popupEligibility = text(p, "", 10, 92, -165, 640)
    u.popupFacts:SetMaxLines(1); u.popupEligibility:SetMaxLines(1)
    u.popupItemHover=CreateFrame("Frame",nil,p)
    u.popupItemHover:SetPoint("TOPLEFT",92,-61);u.popupItemHover:SetSize(24,24)
    u.popupItemHover:EnableMouse(true)
    u.popupItemHover:SetScript("OnEnter", function(self)
        local item = A.state and A:ItemByID(A.popupItem or 0)
        if item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.link)
            A:AddItemFacts(GameTooltip, item)
            GameTooltip:AddLine(A:EligibilityText(item, A.me), 1, 0.8, 0.4, true)
            GameTooltip:Show()
        end
    end)
    u.popupItemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    u.popupItemHover:SetScript("OnHide", function() GameTooltip:Hide() end)
    u.responseBar = CreateFrame("StatusBar", nil, p)
    u.responseBar:SetPoint("TOPLEFT", 92, -140)
    u.responseBar:SetSize(635, 20)
    u.responseBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    u.responseBar:SetMinMaxValues(0, 60); u.responseBar:SetValue(60)
    local barBackground = u.responseBar:CreateTexture(nil, "BACKGROUND")
    barBackground:SetAllPoints(); barBackground:SetColorTexture(0.08, 0.08, 0.10, 1)
    u.responseCountdown = u.responseBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    u.responseCountdown:SetPoint("CENTER", u.responseBar, "CENTER", 0, 0)
    local responseElapsed = 0
    p:SetScript("OnUpdate", function(_, dt)
        responseElapsed = responseElapsed + dt
        if responseElapsed >= 0.05 then responseElapsed = 0; A:RenderResponseTimer() end
    end)
    u.note = edit(p, 97, -200, 620, "Optional note")
    u.note:SetMaxLetters(100)
    u.noteBytes=text(p,"0/100",11,542,-182,180)
    u.noteBytes:ClearAllPoints();u.noteBytes:SetPoint("TOPRIGHT",u.note,"TOPRIGHT",0,18)
    u.noteBytes:SetJustifyH("RIGHT");u.noteBytes:SetHeight(14);u.noteBytes:SetMaxLines(1)
    u.popupNetwork=text(p,"",11,92,-350,630)
    u.note:SetScript("OnTextChanged",function() A:RenderResponseTimer() end)
    u.responseButtons = {}
    local responseFont=CreateFont("SanguineLootCouncilResponseFont")
    responseFont:SetFont(STANDARD_TEXT_FONT,13,"OUTLINE");responseFont:SetTextColor(1,1,1)
    local responseDisabledFont=CreateFont("SanguineLootCouncilResponseDisabledFont")
    responseDisabledFont:SetFont(STANDARD_TEXT_FONT,13,"OUTLINE");responseDisabledFont:SetTextColor(0.50,0.52,0.55)
    for i=1,9 do
        local label = ""
        u.responseButtons[i] = button(p, label, 92 + (i - 1) % 3 * 215, -245 - math.floor((i - 1) / 3) * 34, 205, function()
            local selected=u.responseButtons[i].choice
            if A.popupItem and selected then A.popupPinned=nil;A:Act("respond", {item = A.popupItem, choice = selected, note = u.note:GetText()}) end
            u.note:ClearFocus()
        end)
        u.responseButtons[i]:SetNormalFontObject(responseFont)
        u.responseButtons[i]:SetHighlightFontObject(responseFont)
        u.responseButtons[i]:SetDisabledFontObject(responseDisabledFont)
    end
    u.responsePrevious=button(p, "Previous", 92, -380, 95, function() A:CyclePopup(-1) end)
    u.responseNext=button(p, "Next", 632, -380, 95, function() A:CyclePopup(1) end)
    u.responseRoleHint=text(p, "Everyone can respond, regardless of their role.", 11, 207, -388, 410)
    u.responseVoting=button(p,"Open Voting",285,-380,200,function() A:ShowVoting() end)
    self:StyleButtonOutline(u.responseVoting)

    self:BuildResponseRail(u,p,text,button)

    local h = window("SanguineLootCouncilHistory", "Sanguine Loot Tools Loot History", 980, 560)
    u.history = h
    u.historyScope = text(h, "", 11, 20, -52, 580)
    u.historyAll=button(h, "All players", 815, -45, 125, function() A:ShowHistory() end)
    u.historyColumns={{"Name",0,150},{"Date",155,90},{"Time",250,75},{"Item",330,410},{"Response",745,155}}
    for _,col in ipairs(u.historyColumns) do col.heading=text(h,col[1],11,20+col[2],-82,col[3]);col.heading:SetTextColor(0.80,0.74,0.57) end
    u.historyRows={}
    local scroll = A:CreateScrollFrame(h)
    u.historyScroll = scroll
    scroll:SetPoint("TOPLEFT", 20, -105); scroll:SetPoint("BOTTOMRIGHT", -35, 20)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(915, 400)
    scroll:SetScrollChild(child)
    u.historyChild = child
    u.historyText = text(child, "", 12, 0, 0, 705)
    u.historyText:SetJustifyV("TOP")
    u.historyText:Hide() -- Plain summary retained for diagnostics; the window renders aligned columns.
    u.checkWindow = window("SanguineLootCouncilReadiness", "Sanguine Loot Tools - Version Check", 640, 500)
    u.checkDescription=text(u.checkWindow,"Everyone in the group is listed. Not detected means no reply; the addon may be absent, disabled, outdated or delayed.",11,20,-54,590);u.checkDescription:SetHeight(40)
    u.checkExpected=text(u.checkWindow,"",10,430,-22,150);u.checkExpected:SetJustifyH("RIGHT")
    u.checkplayerHeader=text(u.checkWindow,"PLAYER",10,20,-110,280)
    u.checkaddonHeader=text(u.checkWindow,"ADDON",10,320,-110,130)
    u.checkversionHeader=text(u.checkWindow,"VERSION",10,460,-110,130)
    local checkScroll = A:CreateScrollFrame(u.checkWindow)
    checkScroll:SetPoint("TOPLEFT",20,-132);checkScroll:SetPoint("BOTTOMRIGHT",-35,65)
    u.checkScroll=checkScroll
    u.checkChild=CreateFrame("Frame",nil,checkScroll)
    u.checkChild:SetSize(585,400);checkScroll:SetScrollChild(u.checkChild)
    u.checkRows={}
    for i=1,40 do
        local row=CreateFrame("Frame",nil,u.checkChild)
        row:SetPoint("TOPLEFT",0,-(i-1)*24);row:SetSize(585,24)
        A:StyleDataRow(row,i)
        row.player=text(row,"",12,0,-5,290)
        row.addon=text(row,"",12,300,-5,130)
        row.version=text(row,"",12,440,-5,140)
        for _,cell in ipairs({row.player,row.addon,row.version}) do cell:SetHeight(16);cell:SetMaxLines(1) end
        row:EnableMouse(true)
        row:SetScript("OnEnter",function(self)
            if not self.member then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:AddLine(self.member,1,1,1)
            GameTooltip:AddLine(self.detail or "",0.8,0.8,0.8,true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        row:SetScript("OnHide",function() GameTooltip:Hide() end)
        row:Hide();u.checkRows[i]=row
    end
    u.checkSummary=text(u.checkWindow,"",11,20,-562,465)
    u.recheck=button(u.checkWindow,"Refresh",500,-552,115,function() A:StartAddonCheck(true) end)
    local checkElapsed = 0
    u.checkWindow:SetScript("OnUpdate", function(_, dt)
        checkElapsed = checkElapsed + dt
        if checkElapsed >= 1 then checkElapsed = 0; A:RenderReadiness() end
    end)
    -- Version Check is a standalone destination, including when dismissed with Escape.
    local function hideOtherWindows()
        for _, frame in ipairs(A.allWindowFrames or {}) do
            if frame ~= u.checkWindow then frame:Hide() end
        end
        if GameTooltip then GameTooltip:Hide() end
    end
    u.checkWindow:HookScript("OnShow", hideOtherWindows)
    u.checkWindow:HookScript("OnHide", hideOtherWindows)
    self:BuildCouncilUI(u, window, text, button)
    u.reroll=window("SanguineLootCouncilReroll","Reroll Item",500,245,true)
    u.reroll:SetFrameStrata("FULLSCREEN_DIALOG")
    u.rerollItem=text(u.reroll,"",15,20,-52,460);u.rerollItem:SetHeight(40);u.rerollItem:SetMaxLines(2)
    text(u.reroll,"Reroll this item only?\n\nAll player responses, notes, equipped-item snapshots and council votes for this item are cleared. The timer restarts and everyone must choose again. Other items are unaffected.",12,20,-97,460):SetHeight(85)
    u.rerollConfirm=button(u.reroll,"Reroll Item",20,-201,220,function() A:ConfirmReroll() end)
    u.rerollCancel=button(u.reroll,"Cancel",260,-201,220,function() A:CloseReroll() end)
    u.reroll.closeButton:SetScript("OnClick",function() A:CloseReroll() end)
    u.reroll:SetScript("OnHide",function() A.rerollContext=nil end)
    u.reroll:SetScript("OnUpdate",function() A:FitVotingDialog(u.reroll) end)
    u.main:HookScript("OnHide",function() A:CloseReroll() end)
    u.endSession=window("SanguineLootCouncilEndSession","End Session",500,230,true)
    u.endSession:SetFrameStrata("FULLSCREEN_DIALOG")
    text(u.endSession,"End the current loot session?\n\nUnawarded items, votes and live delivery/timer tracking will stop. Recorded awards and delivery logs remain in history.",12,20,-57,460):SetHeight(110)
    u.endSessionConfirm=button(u.endSession,"End Session",20,-186,220,function() A:ConfirmEndSession() end)
    u.endSessionCancel=button(u.endSession,"Cancel",260,-186,220,function() A:CloseEndSession() end)
    u.endSession.closeButton:SetScript("OnClick",function() A:CloseEndSession() end)
    u.endSession:SetScript("OnHide",function() A.endSessionContext=nil end)
    self:BuildSettingsUI(u,window,text,button,edit)
    self:BuildPersonalColorUI(u,window,text,button,edit)
    u.receiving=window("SanguineLootCouncilReceiving","Receiving loot data",340,94,true)
    u.receiving:ClearAllPoints();u.receiving:SetPoint("TOP",UIParent,"TOP",0,-110)
    u.receivingText=text(u.receiving,"",12,18,-51,304)
    u.receiving:SetScript("OnHide",function() if A:IncomingProgress() then A.hiddenTransferProgress=true end end)
    u.networkStatus=text(u.main,"",11,80,-610,690)
    self:BuildDiagnosticUI(u,window,text,button)
    self:BuildAuditUI(u,window,text)
    u.launcher=window("SanguineLootCouncilLauncher","Sanguine Loot Tools",320,205)
    u.launcherButtons={}
    for i,name in ipairs({"Responses","Voting","Loot","Timer","History","Settings"}) do
        local b=button(u.launcher,name,16+((i-1)%2)*148,-53-math.floor((i-1)/2)*45,140,function() A:OpenLauncherOption(name) end)
        b:SetHeight(34);u.launcherButtons[name]=b
    end
    self:BuildConfirmationUI(u,window,text,button)
    self:RestoreWindowLayouts()
    for _,frame in ipairs({u.main,u.voting}) do
        frame:HookScript("OnShow",function(f) if not A:CanViewCouncil() then f:Hide() end end)
    end
    u.checkWindow:HookScript("OnShow",function(f) if not A:IsLootController() then f:Hide() end end)
    u.lootPanels.timer.manage:HookScript("OnShow",function(f) if not A:IsMaster() then f:Hide() end end)
    self:InstallManualLootLinkHooks()
    for _,frame in ipairs(self.allWindowFrames) do self:RefreshWindowChrome(frame) end
    self:RefreshWindowLayers()
end

function A:RenderLauncher()
    if not self.ui or not self.ui.launcherButtons then return end
    self.ui.launcherButtons.Voting:SetEnabled(self:CanViewCouncil())
    self.ui.launcherButtons.Loot:SetEnabled(self:CanViewLoot()==true)
end

function A:ShowLauncher()
    if not self.state or #self.state.items==0 then self:RequestSync() end
    self:BuildUI();self:Render();self:RenderLauncher();self.ui.launcher:Show()
end

function A:ShowResponses()
    if not self.state or #self.state.items==0 then self:RequestSync() end
    self:BuildUI();self:Render()
    self.ui.main:Hide();self.ui.voting:Hide()
    if self.ui.popup:GetWidth()+self.ui.lootPanels.timer.window:GetWidth()+64>UIParent:GetWidth() then self.ui.lootPanels.timer.window:Hide();self.ui.lootPanels.timer.manage:Hide() end
    self.ui.popup:Show()
end

function A:ShowVoting()
    self:BuildUI();self:Render()
    if not self:CanViewCouncil() then return false end
    self.ui.popup:Hide();self.ui.main:Show()
    return true
end

function A:OpenLauncherOption(name)
    self:BuildUI()
    if name=="Voting" and not self:CanViewCouncil() then self:RenderLauncher();return false end
    if name=="Loot" and not self:CanViewLoot() then self:RenderLauncher();return false end
    if name=="Responses" then self:ShowResponses()
    elseif name=="Voting" then self:ShowVoting()
    elseif name=="Loot" then self:ShowLootWindow("timer")
    elseif name=="Timer" then self:ShowLootTimers()
    elseif name=="History" then self:ShowHistory()
    elseif name=="Settings" then self:ShowSettings()
    else return false end
    self.ui.launcher:Hide()
    return true
end

function A:CyclePopup(direction)
    local rows=self:ResponseItems()
    if #rows==0 then return end
    local at=1
    for i,row in ipairs(rows) do if row.item.id==self.popupItem then at=i end end
    self:SelectResponseItem(rows[(at-1+direction)%#rows+1].item.id)
end

function A:Render()
    self:BuildUI()
    local u, s = self.ui, self.state
    self:LayoutReadableWindow(u.main)
    if self.confirmationContext and not self:ConfirmationContextValid(self.confirmationContext) then self:CloseConfirmation() end
    self:RenderLauncher()
    if self.endSessionContext and (not s or s.id~=self.endSessionContext or not self:IsLeader()) then self:CloseEndSession() end
    self.noteDrafts=self.noteDrafts or {}
    if self.noteDraftKey then self.noteDrafts[self.noteDraftKey]=u.note:GetText() end
    self:PruneActiveCaches()
    local previousSession = self.renderSession
    if previousSession ~= (s and s.id) then
        self.selectedItem, self.itemPage, self.candidatePage = 1, 0, 0
        self.selectedCandidate, self.popupItem = nil, nil
        self.popupSeen,self.responseReceipts,self.pendingPersonalResponses = {},{},{}
        self.popupPinned,self.responseRailSelected,self.responseEligibilityKey=nil,nil,nil
        self.responseRailPage=0
        self.noteDrafts,self.noteDraftKey,self.candidateOrders={},nil,{}
    end
    self.renderSession = s and s.id
    self:ApplyVotingAdvance()
    local reviewRole = self:CanViewCouncil()
    if not reviewRole then u.main:Hide();u.voting:Hide() end
    u.responseVoting:SetShown(reviewRole);u.responseVoting:SetEnabled(reviewRole)
    u.responseRoleHint:SetShown(not reviewRole)
    u.status:SetText((self.demo and (self:TestLabel().." | ") or "") .. (s and ("Leader: " .. s.leader .. "  |  Master looter: " .. s.master .. (s.masterBlocked and " (waiting for game role)" or (s.masterSource == "game" and " (game)" or " (manual)"))) or "No active session. The raid leader starts and configures it."))
    u.start:SetEnabled(self:IsLeader() and not s)
    u.finish:SetEnabled(self:IsLeader() and s ~= nil)
    u.settings:SetEnabled(self:CanConfigureRaid())
    u.readiness:SetEnabled(self:IsLootController() and not self.demo)
    u.readiness:SetShown(self:IsLootController())
    if not self:IsLootController() then u.checkWindow:Hide() end
    u.resume:SetEnabled(self:RecoveryAvailable() == true)
    u.add:SetEnabled(self:IsMaster())
    u.itemInput:SetEnabled(self:IsMaster())
    u.setMaster:SetEnabled(self:CanConfigureRaid() and (not s and not self:RaidSettings().masterAutoSync or s and not (s.masterAutoSync and (s.masterSource == "game" or s.masterBlocked))))
    u.autoMaster:SetEnabled(self:CanConfigureRaid())
    self:SetSettingsToggle(u.autoMaster,s and s.masterAutoSync and not self.demo)
    u.toggleCouncil:SetEnabled(self:CanConfigureRaid())
    u.selfVotes:SetEnabled(self:CanConfigureRaid())
    self:SetSettingsToggle(u.selfVotes,s and s.selfVotes)
    u.applyResponseTimer:SetEnabled(self:CanConfigureRaid())
    u.responseSeconds:SetEnabled(self:CanConfigureRaid())
    if u.responseSeconds:HasFocus() ~= true then u.responseSeconds:SetText(tostring(s and s.responseDuration or SanguineLootCouncilDB.responseDuration or 60)) end
    u.saveProfile:SetEnabled(self:CanConfigureRaid() and not self.demo)
    u.loadProfile:SetEnabled(self:CanConfigureRaid() and not self.demo)
    u.deleteProfile:SetEnabled(self:CanConfigureRaid() and not self.demo)
    local profiles = {}
    for name in pairs(SanguineLootCouncilDB.profiles) do profiles[#profiles + 1] = name end
    table.sort(profiles)
    u.profileList:SetText("Saved profiles: " .. (#profiles > 0 and table.concat(profiles, ", ") or "None") .. "\nApplying a profile updates roles and self-voting. Loot responses are retained.")
    local names = {}
    for name in pairs(self:RaidSettings().council) do names[#names + 1] = name end
    table.sort(names)
    u.councilList:SetText("Council: " .. (#names > 0 and table.concat(names, ", ") or "None assigned") .. "\n\nThe leader and master looter vote only if added to the council.")
    if s and not self:ItemByID(self.selectedItem) then self.selectedItem=s.items[1] and s.items[1].id end
    if s then self.itemPage=math.min(self.itemPage or 0,math.max(0,math.ceil(#s.items/(self.votingItemRows or 9))-1)) end
    for i, b in ipairs(u.itemButtons) do
        local id = (self.itemPage or 0) * (self.votingItemRows or 9) + i
        local item = (i<=(self.votingItemRows or 9) and s and s.items[id]) or nil
        b:SetShown(item ~= nil)
        if b.awarded then b.awarded:SetShown(item~=nil and item.status=="awarded" and item.winner~=nil) end
        if item then
            local name = item.link:match("%[([^%]]+)%]") or "Item"
            b:SetText("")
            if b.icon then b.icon:SetTexture(self:ItemIcon(item)) end
            b:SetBackdropBorderColor(item.id == self.selectedItem and 1 or 0.4, item.id == self.selectedItem and 0.8 or 0.45, 0.35)
            b:SetScript("OnEnter",nil);b:SetScript("OnLeave",nil)
        end
    end
    local itemPages=math.max(1,math.ceil((s and #s.items or 0)/(self.votingItemRows or 9)))
    u.itemPages:SetText(itemPages>1 and (((self.itemPage or 0)+1).."/"..itemPages) or "")
    u.itemPages:SetShown(itemPages>1)
    u.itemPrev:SetShown(itemPages>1);u.itemNext:SetShown(itemPages>1)
    u.itemPrev:SetEnabled((self.itemPage or 0)>0);u.itemNext:SetEnabled((self.itemPage or 0)<itemPages-1)
    self:RefreshRailArrow(u.itemPrev);self:RefreshRailArrow(u.itemNext)
    local item = s and self:ItemByID(self.selectedItem or 1)
    local selectedIndex=1
    for i,v in ipairs(s and s.items or {}) do if v.id==self.selectedItem then selectedIndex=i;break end end
    u.candidatePrev:SetEnabled(item~=nil and selectedIndex>1)
    u.candidateNext:SetEnabled(item~=nil and selectedIndex<#s.items)
    u.itemTitle:SetText(item and item.link or (not s and "No active session" or (#s.items==0 and "No loot queued" or "Select an item")))
    u.itemIcon:SetTexture(self:ItemIcon(item)); u.itemIcon:SetShown(item ~= nil)
    u.itemStatus:SetText(item and ("Status: " .. item.status .. (item.winner and "  |  Winner: " .. item.winner or "")) or "")
    u.itemDetails:SetText(item and self:ItemSummary(item) or "")
    local candidates = {}
    local ballotView = item and self:VisibleVoting(item)
    local draft = item and self:VotingDraft(item)
    if item and (self:IsCouncil() or self:IsMaster()) then
        for name, response in pairs(item.responses) do
            local votes = ballotView.totals and (ballotView.totals[name] or 0) or -1
            candidates[#candidates + 1] = {name = name, response = response, votes = votes}
        end
        for name in pairs(item.noResponse or {}) do
            if not item.responses[name] then
                candidates[#candidates + 1] = {name = name, response = {choice = 0, note = self.roster[name] and (item.responseCloseReason == "timer" and "Timed out" or "Closed without a response") or "Left raid"}, votes = -1}
            end
        end
    end
    if item and item.status == "open" and (self:IsCouncil() or self:IsMaster()) then
        for name in pairs(item.responseMembers or {}) do
            if not item.responses[name] and not (item.noResponse or {})[name] then
                candidates[#candidates + 1] = {name = name, response = {choice = 0, note = "Waiting for response"}, votes = -1}
            end
        end
    end
    local orderKey=item and (s.id..":"..item.id..":"..(item.responseRound or 0))
    self.candidateOrders=self.candidateOrders or {}
    local order=orderKey and self.candidateOrders[orderKey]
    if not order then order={next=0};if orderKey then self.candidateOrders[orderKey]=order end end
    table.sort(candidates,function(a,b) return a.name<b.name end)
    for _,c in ipairs(candidates) do if not order[c.name] then order.next=order.next+1;order[c.name]=order.next end end
    table.sort(candidates, function(a, b)
        -- Session response order defines priority; votes never reorder ties.
        local ar,br=self:ResponseRank(a.response.choice,item),self:ResponseRank(b.response.choice,item)
        if ar~=br then return ar<br end
        return order[a.name]<order[b.name]
    end)
    self.candidateCount = #candidates
    u.playerPagePrevious:SetShown(#candidates>(self.votingCandidateRows or 14))
    u.playerPageNext:SetShown(#candidates>(self.votingCandidateRows or 14))
    u.playerPagePrevious:SetEnabled((self.candidatePage or 0)>0)
    u.playerPageNext:SetEnabled(((self.candidatePage or 0)+1)*(self.votingCandidateRows or 14)<#candidates)
    if self.candidateRowsChanged then
        for i,c in ipairs(candidates) do if c.name==self.selectedCandidate then self.candidatePage=math.floor((i-1)/(self.votingCandidateRows or 14));break end end
        self.candidateRowsChanged=nil
    end
    self.candidatePage=math.min(self.candidatePage or 0,math.max(0,math.ceil(#candidates/(self.votingCandidateRows or 14))-1))
    for i, b in ipairs(u.candidates) do
        local c = (i<=(self.votingCandidateRows or 14) and candidates[(self.candidatePage or 0) * (self.votingCandidateRows or 14) + i]) or nil
        b:SetShown(c ~= nil)
        b.candidate = c and c.name
        if c then
            -- The table owns all visible row text. SetText can reset a native
            -- button's font styling, exposing the old combined label over cells.
            b:SetText("")
            b:SetScript("OnEnter",nil)
            b:SetScript("OnLeave",nil)
        end
    end
    u.selection:SetText(self.selectedCandidate and ("Selected: " .. self.selectedCandidate) or (#candidates>0 and "Select a candidate to vote or award" or ""))
    self:RenderCandidateHistory()
    if u.history:IsShown() == true then self:ShowHistory(self.historyFilter) end
    local mutable = item and item.status ~= "awarded"
    u.open:SetEnabled(self:IsMaster() and mutable)
    u.open:SetText(item and item.voting~="idle" and "Reroll Item" or "Open responses")
    if self.rerollContext and not self:ReleaseContextValid(self.rerollContext) then self:CloseReroll() end
    u.vote:SetEnabled(self:IsCouncil() and mutable and item.voting == "open" and self.selectedCandidate ~= nil)
    u.votingDesk:SetEnabled(item ~= nil and (self:IsMaster() or self:IsCouncil()))
    u.compareGear:SetEnabled(item ~= nil and self.selectedCandidate ~= nil and (self:IsMaster() or self:IsCouncil()))
    u.correctAward:SetShown(self:IsMaster())
    u.correctAward:SetEnabled(self:IsMaster() and item and item.status=="awarded" and #self:CorrectionCandidates(item)>0 and #(item.corrections or {})<10)
    self:RenderVotingStatus()
    self:RenderCorrection()
    self:RenderCouncilTable(item, candidates, draft)
    self:RenderLootWindows()
    self:RenderSettings()

    local rows,hidden=self:ResponseItems()
    self.popupSeen=self.popupSeen or {}
    local available,visible,active,pending,firstOpen,newlyOpened={},{},{},nil,nil,false
    for _,row in ipairs(rows) do
        local it=row.item
        available[#available+1]=it.id;visible[it.id]=it
        local canRespond=it.status=="open" and (not it.responseDeadline or A.Client:ServerTime()<it.responseDeadline)
        if canRespond then
            active[it.id]=true
            firstOpen=firstOpen or it.id
            if not self:PersonalSelection(it) and not pending then pending=it.id end
            if self.popupSeen[it.id]~=it.responseRound then newlyOpened=true;self.popupSeen[it.id]=it.responseRound end
        end
    end
    local current=visible[self.popupItem or 0]
    local pin=self.popupPinned
    local pinned=current and pin and pin.sid==s.id and pin.item==current.id and pin.round==current.responseRound
    if not current or (newlyOpened and not active[current.id])
        or (active[current.id] and self:PersonalSelection(current) and pending and not pinned) then
        local nextItem=pending or firstOpen or available[1]
        if nextItem or not current then
            self.popupItem=nextItem
            self.popupPinned=nil
            current=s and self:ItemByID(self.popupItem or 0)
        end
    end
    -- Only newly eligible item rounds prompt. Never reopen on votes, awards or
    -- ordinary refreshes; retain seen rounds even if eligibility changes.
    if newlyOpened then
        u.main:Hide();u.voting:Hide();u.lootPanels.timer.window:Hide();u.lootPanels.timer.manage:Hide();u.popup:Show()
    end
    self:RenderResponseRail(rows,hidden)
    local noteKey=current and (s.id..":"..current.id..":"..(current.responseRound or 0))
    if noteKey~=self.noteDraftKey then
        self.noteDraftKey=noteKey
        u.note:SetText(noteKey and self.noteDrafts[noteKey] or "")
    end
    self:ResizeReadableWindow(u.popup,u.popup:GetWidth(),u.popup:GetHeight())
    u.popupItem:SetText(current and current.link or self:ResponseEmptyMessage(hidden))
    u.popupIcon:SetTexture(self:ItemIcon(current)); u.popupIcon:SetShown(current ~= nil)
    local response = self:PersonalSelection(current)
    local responseStatus = response and ("Your response: " .. self:ResponseLabel(response.choice,current) .. (current.status == "open" and " (click to change)" or " (closed)")) or (current and current.status ~= "open" and "No response recorded (closed)." or "Choose one response below.")
    u.popupStatus:SetText(current and responseStatus or (s and (hidden>0 and "Items your class cannot use are hidden." or "Wait for the master looter to release loot.") or "Responses will appear after the raid leader starts a session and loot is released."))
    u.popupFacts:SetText(current and self:ItemSummary(current) or "")
    local classStatus,classReason
    if current then classStatus,classReason=self:ClassEligibility(current) end
    u.popupEligibility:SetText(current and (classStatus=="Unknown" and ("Eligibility unknown: "..classReason) or self:EligibilityText(current,self.me)) or "")
    local options={}
    for _,v in ipairs(self:ResponseOptions(current)) do if v.enabled then options[#options+1]=v end end
    for i,b in ipairs(u.responseButtons) do
        local v=options[i];b.choice=v and v.id;b:SetShown(v~=nil)
        if v then
            b:SetText(v.label)
            b:GetFontString():SetTextColor(self:ResponseRGB(v.id,current))
            b:SetScript("OnEnter",nil)
            b:SetScript("OnLeave",nil)
        end
    end
    self:RenderResponseTimer()
    for _,frame in ipairs(self.allWindowFrames) do self:RefreshWindowChrome(frame) end
    if self.demo and s and #(s.trackedLoot or {})>0 and self:IsMaster() and self.testLootShownSID~=s.id then
        self.testLootShownSID=s.id
        u.main:Hide();u.voting:Hide();u.popup:Hide()
        self:ShowLootWindow("timer")
    end
end

function A:RenderCorrection()
    if not self.ui then return end
    local u, c = self.ui, self.correctionContext
    local item = c and self.state and c.sid == self.state.id and self:ItemByID(c.item)
    local current = item and item.status == "awarded" and item.winner == c.expectedWinner and (item.awardRevision or 1) == c.expectedRevision
    local choices=self:CorrectionDropdownChoices()
    local target=false
    for _,choice in ipairs(choices) do if choice[2]==c.target then target=true;break end end
    local limitReached = item and #(item.corrections or {}) >= 10
    local allowed = current and not limitReached and self:IsMaster() and target
    u.correctionItem:SetText(item and item.link or "Select an awarded item from the loot desk")
    u.correctionCurrent:SetText(item and ("Current winner: " .. item.winner .. " | Award revision: " .. (item.awardRevision or 1)) or "No active award selected")
    u.correctionTargetDropdown:SetText(target and c.target or (#choices>0 and "Choose a replacement" or "No eligible replacement"))
    u.correctionTargetDropdown:SetEnabled(#choices>0)
    u.correctionTargetDropdown.dropdownArrow:SetEnabled(#choices>0)
    u.correctionEligibility:SetText(target and self:EligibilityText(item,c.target) or "")
    u.correctReview:SetEnabled(allowed == true)
    u.correctionStatus:SetText(not current and "This award or session changed. Close this window and reopen the correction." or (limitReached and "This alpha supports up to 10 corrections per item." or (not self:IsMaster() and "Only the current master looter can confirm a correction." or "This updates the award record and preserves its audit trail.\nArrange any item transfer manually.")))
end

function A:RenderVotingStatus()
    if not self.ui then return end
    if not self:CanViewCouncil() then self.ui.main:Hide();self.ui.voting:Hide() end
    self:RenderCouncilTimer()
    local u, s = self.ui, self.state
    local rules = self:RaidSettings().rules
    local labels = {closed = "After award", immediate = "Immediately", own = "After your vote"}
    local editable = self:CanConfigureRaid() and not self:VotingLocked()
    u.votingRules:SetEnabled(self:IsLeader() and s ~= nil)
    u.selfVotes:SetEnabled(editable)
    u.toggleCouncil:SetEnabled(editable or (self:IsLeader() and s and s.groupTest==true))
    u.loadProfile:SetEnabled(editable and not self.demo)
    for _, control in ipairs({u.ruleLimit, u.ruleVisibility, u.ruleNames}) do control:SetEnabled(editable) end
    u.ruleLimit:SetText("Candidates per council ballot: " .. rules.limit .. " (click to change)")
    u.ruleVisibility:SetText("Reveal results: " .. labels[rules.visibility])
    u.ruleNames:SetText("Voter identities: " .. (rules.names and "Shown with revealed results" or "Totals only"))
    local item = s and self:ItemByID(self.selectedItem or 1)
    u.votingItem:SetText(item and item.link or "Select an item in the loot desk")
    local ballotRules = item and item.votingRules or rules
    local open = item and item.voting == "open" and (not item.deadline or A.Client:ServerTime() < item.deadline)
    local view = item and self:VisibleVoting(item)
    local own = view and view.ownBallot
    local canVote = self:IsCouncil() and open
    local selected = item and item.responses[self.selectedCandidate or ""]
    u.votingCandidate:SetText("Candidate: " .. (self.selectedCandidate or "Choose with Previous / Next"))
    self:RenderEquipment()
    local pick = canVote and selected and selected.choice ~= 6
    u.vote:SetEnabled(pick)
    u.pickCandidate:SetEnabled(pick)
    u.openVoting:SetEnabled(self:IsMaster() and item and (item.status == "open" or item.status == "closed") and item.voting == "idle")
    u.resetVoting:SetEnabled(self:IsMaster() and item and (item.status == "open" or item.status == "closed") and item.voting ~= "idle")
    if not item then
        u.votingStatus:SetText(""); u.votingProgress:SetText("Results: "..labels[rules.visibility].." | Names: "..(rules.names and "Shown" or "Totals only")); u.votingOwn:SetText("")
        return
    end
    local progress = (self:IsSoloTest() or self:IsLeader()) and select(3, self:BallotTotals(item)) or item.progress
    progress = progress or {eligible = 0, submitted = 0, abstained = 0}
    local timer = item.deadline and (" | " .. math.max(0, item.deadline - A.Client:ServerTime()) .. "s left") or ""
    local phase = "Responses: " .. item.status .. " | Voting: " .. item.voting .. timer
    u.itemStatus:SetText(phase .. (item.winner and (" | Winner: " .. item.winner) or "") .. ((item.awardRevision or 1) > 1 and (" | Corrected " .. (item.awardRevision - 1) .. " time(s)") or ""))
    u.votingStatus:SetText(phase .. "\nResults: " .. (view.totals and "Visible to you" or "Concealed"))
    u.votingProgress:SetText(progress.submitted .. "/" .. progress.eligible .. " council voted | " .. ballotRules.limit .. " candidate(s) per voter")
    local names = {}
    for name in pairs(own and own.choices or {}) do names[#names + 1] = name end
    table.sort(names)
    local state = own and (own.abstain and "Abstained" or "Recorded") or "No vote recorded"
    u.votingOwn:SetText("Your vote: " .. state .. "\nSelection: " .. (#names > 0 and table.concat(names, ", ") or "None") .. "\nClick Vote to choose a player. Click Voted to remove your vote." .. (view.notice and ("\n" .. view.notice) or ""))
end

function A:RenderReadiness()
    self:RenderAddonCheck()
end

function A:ShowReadiness()
    if not self:IsLootController() or self.demo then self:Print("Only the raid leader and master looter can view addon readiness."); return end
    self:BuildUI();self:RenderReadiness();self.ui.checkWindow:Show()
end

function A:ShowHistory(player)
    self:BuildUI()
    self:InitStorage()
    if type(player) ~= "string" then player = nil end
    if self.historyFilter ~= player then self.ui.historyScroll:SetVerticalScroll(0) end
    self.historyFilter = player
    local lines = {}
    local records=player and self:PlayerHistory(player).records or SanguineLootCouncilDB.history
    for i, h in ipairs(records) do
        local row=self.ui.historyRows[i]
        if not row then
            row=CreateFrame("Button",nil,self.ui.historyChild);row:SetPoint("TOPLEFT",0,-(i-1)*32);row:SetSize(905,32)
            self:StyleDataRow(row,i)
            row.cells={}
            for j,col in ipairs(self.ui.historyColumns) do
                row.cells[j]=text(row,"",11,col[2],-7,col[3]);row.cells[j]:SetMaxLines(1)
            end
            row:SetScript("OnEnter",function(r) if r.record and r.record.item then GameTooltip:SetOwner(r,"ANCHOR_RIGHT");GameTooltip:SetHyperlink(r.record.item);GameTooltip:Show() end end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            row:SetScript("OnClick",function(r) A:ShowAwardAudit(r.record) end)
            self.ui.historyRows[i]=row
        end
        local values={tostring(h.winner or "Unknown"),date("%d/%m/%Y",h.time or 0),date("%H:%M:%S",h.time or 0),h.item or "Unknown item",h.responseLabel or self.responses[h.response] or "Unknown"}
        for j,value in ipairs(values) do row.cells[j]:SetText(value) end
        row.record=h;row:Show()
        lines[#lines+1]=table.concat(values," | ")..(h.timeSource~="award" and " [time observed]" or "")
    end
    for i=#records+1,#self.ui.historyRows do self.ui.historyRows[i]:Hide() end
    self.ui.historyScope:SetText((player and ("Player: "..player) or "All players").." | "..#records.." recorded awards; latest 500 retained. Click a row for audit.")
    self.ui.historyText:SetText(#lines > 0 and table.concat(lines, "\n") or "No local records for this selection. This does not mean the player has never received loot.")
    if not self.ui.historyEmpty then self.ui.historyEmpty=text(self.ui.historyChild,"No recorded awards for this selection.",12,0,-8,890) end
    self.ui.historyEmpty:SetShown(#records==0)
    self.ui.historyChild:SetHeight(math.max(400,#records*32))
    self:LayoutReadableWindow(self.ui.history)
    self.ui.history:Show()
end

A.confirmationDialogs["SANGUINELOOTCOUNCIL_AWARD"] = {
    text="Item: %s\n\nRecipient: %s\n\nConfirming closes voting and records this winner.",
    button1="Award",button2="Cancel",timeout=0,whileDead=true,hideOnEscape=true,
    OnAccept=function(dialog) A:ConfirmAward(dialog.data) end,
}

A.confirmationDialogs["SANGUINELOOTCOUNCIL_CORRECT_AWARD"] = {
    text = "Current winner: %s\nReplacement: %s\n\nThe original award remains in the audit trail. Arrange any item transfer manually.",
    button1 = "Change winner", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(dialog)
        local p = dialog.data
        if p and A.state and p.sid == A.state.id then A:Act("correctAward", p); A.ui.correction:Hide() end
    end,
}
A.confirmationDialogs["SANGUINELOOTCOUNCIL_DELIVERY"] = {
    text = "%s\n\n%s", button1 = "Confirm", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(dialog)
        local p = dialog.data
        if p and A.state and p.sid == A.state.id then A:Act(p.op, p) end
    end,
}

A.confirmationDialogs["SANGUINELOOTCOUNCIL_RESUME"] = {
    text = "Resume your saved loot session in this raid?\n\nLoot, responses and votes will be restored from WoW's last saved checkpoint. Absent council members are removed.",
    button1 = "Resume", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() A:ResumeSession() end,
}
A.confirmationDialogs["SANGUINELOOTCOUNCIL_RESET_BALLOT"] = {
    text = "Clear and pause all votes and abstentions for this item?\n\nThe master looter can then Resume voting. Previously revealed results cannot be forgotten.",
    button1 = "Reset ballot", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(dialog)
        local p = dialog.data
        if p and A.state and p.sid == A.state.id then A:Act("resetVoting", p) end
    end,
}
A.confirmationDialogs["SANGUINELOOTCOUNCIL_SAVE_PROFILE"] = {
    text = "Overwrite saved profile %s with the current raid setup?", button1 = "Overwrite", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, OnAccept = function(dialog) A:SaveProfile(dialog.data) end,
}
A.confirmationDialogs["SANGUINELOOTCOUNCIL_LOAD_PROFILE"] = {
    text = "Apply profile %s?\n\nMaster looter, council and self-voting settings will be replaced. Votes that are no longer allowed will be removed.", button1 = "Apply", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, OnAccept = function(dialog) A:LoadProfile(dialog.data) end,
}
A.confirmationDialogs["SANGUINELOOTCOUNCIL_DELETE_PROFILE"] = {
    text = "Delete saved profile %s?", button1 = "Delete", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(dialog) A:DeleteProfile(dialog.data) end,
}

SLASH_SANGUINELOOTTOOLS1 = "/slt"
SlashCmdList["SANGUINELOOTTOOLS"] = function(input)
    local command = (input or ""):lower():match("^%s*(.-)%s*$")
    if command == "test" then A:StartDemo()
    elseif command == "leave-test" then
        A:LeaveTest()
    elseif command == "diagnostics start" then A:StartDiagnostics()
    elseif command == "diagnostics stop" then A.diagnosticRecording=false;A:ShowDiagnostics()
    elseif command == "diagnostics" then A:ShowDiagnostics()
    elseif command == "settings" then A:ShowSettings()
    elseif command == "responses" then A:ShowResponses()
    elseif command == "history" then A:ShowHistory()
    elseif command == "loot" then A:ShowLootWindow("timer")
    elseif command == "timer" then A:ShowLootTimers()
    elseif command == "sync" then A:RequestSync()
    elseif command == "check" then A:StartAddonCheck(true)
    elseif command == "resume" then A:Render(); if A:RecoveryAvailable() then A:ShowConfirmation("SANGUINELOOTCOUNCIL_RESUME") else A:Print("No saved session is available for this raid leader.") end
    elseif command == "help" then A:Print("/slt opens the window launcher; /slt settings; /slt responses; /slt loot; /slt timer (all roles); /slt test; /slt leave-test; /slt history; /slt sync; /slt check; /slt resume; /slt diagnostics.")
    elseif command == "" then
        A:ShowLauncher()
    else A:Print("Unknown command. Use /slt help; /slt loot opens loot tracking.")
    end
end

function A:ReviewEndSession()
    if not self.state or not self:IsLeader() then return false end
    self:BuildUI();self.endSessionContext=self.state.id
    self.ui.endSession:ClearAllPoints();self.ui.endSession:SetPoint("CENTER",self.ui.settingsHub,"CENTER",0,0)
    self.ui.endSession:Show();self:FocusWindow(self.ui.endSession)
    return true
end
function A:CloseEndSession()
    self.endSessionContext=nil
    if self.ui and self.ui.endSession then self.ui.endSession:Hide() end
end
function A:ConfirmEndSession()
    local sid=self.endSessionContext;self:CloseEndSession()
    if not sid or not self.state or self.state.id~=sid or not self:IsLeader() then return false end
    self:Act("end");return true
end

local confirmationTitles={
    AWARD="Confirm Award",CORRECT_AWARD="Correct Award",DELIVERY="Confirm Delivery",
    RESUME="Resume Saved Session",RESET_BALLOT="Reset Voting",SAVE_PROFILE="Overwrite Profile",
    LOAD_PROFILE="Apply Profile",DELETE_PROFILE="Delete Profile",ARCHIVE="Archive Completed Loot",
    TRADE_ITEMS="Add Trade Items",DELETE_RESPONSE="Delete Response",RESET_RESPONSES="Restore Responses",
}
function A:BuildConfirmationUI(u,window,text,button)
    u.confirmation=window("SanguineLootCouncilConfirmation","Confirm",540,240,true)
    local f=u.confirmation;f:SetFrameStrata("FULLSCREEN_DIALOG")
    local scroll=A:CreateScrollFrame(f)
    scroll:SetPoint("TOPLEFT",20,-54);scroll:SetSize(480,120)
    local child=CreateFrame("Frame",nil,scroll);child:SetSize(460,120);scroll:SetScrollChild(child)
    u.confirmationScroll,u.confirmationChild=scroll,child
    u.confirmationBody=text(child,"",13,0,0,460);u.confirmationBody:SetJustifyV("TOP")
    u.confirmationAccept=button(f,"Confirm",20,-194,240,function() A:AcceptConfirmation() end)
    u.confirmationCancel=button(f,"Cancel",280,-194,240,function() A:CloseConfirmation() end)
    f.closeButton:SetScript("OnClick",function() A:CloseConfirmation() end)
    f:SetScript("OnHide",function()
        if A.confirmationContext then A.confirmationContext.data=nil end
        A.confirmationContext=nil
    end)
    f:SetScript("OnUpdate",function()
        if A.confirmationContext and not A:ConfirmationContextValid(A.confirmationContext) then A:CloseConfirmation() end
        if A.confirmationContext and A.confirmationContext.votingOwner then A:FitVotingDialog(f) end
    end)
end
function A:ConfirmationContextValid(context)
    if not context or context.sid~=(self.state and self.state.id or false) then return false end
    if context.expires and self.Client:Uptime()>=context.expires then return false end
    local data=context.data
    if type(data)=="table" and data.item and context.rounds[data.item] then
        local item=self:ItemByID(data.item);local before=context.rounds[data.item]
        if not item or item.round~=before[1] or item.responseRound~=before[2] then return false end
    end
    return true
end
function A:ShowConfirmation(kind,first,second)
    local definition=self.confirmationDialogs[kind]
    if not definition then return end
    self:BuildUI()
    local ok,message=pcall(string.format,definition.text,first or "",second or "")
    if not ok then return end
    if self.confirmationContext then self.confirmationContext.data=nil end
    local context={kind=kind,sid=self.state and self.state.id or false,rounds={}}
    for _,item in ipairs(self.state and self.state.items or {}) do context.rounds[item.id]={item.round,item.responseRound} end
    if definition.timeout and definition.timeout>0 then context.expires=self.Client:Uptime()+definition.timeout end
    self.confirmationContext=context
    local u=self.ui;local short=kind:gsub("^SANGUINELOOTCOUNCIL_","")
    u.confirmation.title:SetText(confirmationTitles[short] or "Confirm")
    u.confirmationBody:SetText(message)
    local height=u.confirmationBody:GetStringHeight()
    if type(height)~="number" or height~=height then height=100 end
    height=math.max(90,math.min(height,390))
    u.confirmationChild:SetHeight(math.max(height,u.confirmationBody:GetStringHeight()))
    u.confirmationScroll:SetHeight(height);u.confirmationScroll:SetVerticalScroll(0)
    u.confirmation:SetHeight(height+116)
    u.confirmationAccept:ClearAllPoints();u.confirmationAccept:SetPoint("TOPLEFT",20,-height-74)
    u.confirmationCancel:ClearAllPoints();u.confirmationCancel:SetPoint("TOPLEFT",280,-height-74)
    u.confirmationAccept:SetText(definition.button1 or "Confirm")
    u.confirmationCancel:SetText(definition.button2 or "Cancel")
    local owner=(short=="AWARD" or short=="CORRECT_AWARD" or short=="RESET_BALLOT") and u.votingSurface or u.settingsHub
    context.votingOwner=owner==u.votingSurface and owner:IsShown()
    if not owner:IsShown() then owner=UIParent end
    u.confirmation:ClearAllPoints();u.confirmation:SetPoint("CENTER",owner,"CENTER",0,0)
    u.confirmation:SetScale(self:WindowScale(u.confirmation,owner:GetEffectiveScale()/UIParent:GetEffectiveScale()))
    if context.votingOwner then self:FitVotingDialog(u.confirmation) end
    local modalOwner=owner
    if short=="CORRECT_AWARD" and u.correction:IsShown() then modalOwner=u.correction
    elseif short=="ARCHIVE" and u.history:IsShown() then modalOwner=u.history
    elseif short=="DELIVERY" then
        local panel=u.lootPanels.timer
        modalOwner=panel.manage:IsShown() and panel.manage or panel.window
    end
    u.confirmation.sltDialogOwner=modalOwner
    u.confirmation:Show();self:FocusWindow(u.confirmation)
    return context
end
function A:CloseConfirmation()
    if self.confirmationContext then self.confirmationContext.data=nil end
    self.confirmationContext=nil
    if self.ui and self.ui.confirmation then self.ui.confirmation:Hide() end
end
function A:AcceptConfirmation()
    local context=self.confirmationContext
    if not self.ui or not self.ui.confirmation:IsShown() or not self:ConfirmationContextValid(context) then self:CloseConfirmation();return false end
    local definition=self.confirmationDialogs[context.kind]
    local data=self.Copy(context.data)
    self:CloseConfirmation()
    if definition and definition.OnAccept then definition.OnAccept({data=data});return true end
    return false
end
