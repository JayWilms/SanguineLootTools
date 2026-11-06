local _, A = ...
local anchors={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<100000 end

function A:WindowModalOwner(frame)
    local u=self.ui
    if not u then return nil,false end
    local parent
    local modal=frame==u.correction or frame==u.lootReason or frame==u.personalColor or frame==u.itemTools
        or frame==u.reroll or frame==u.endSession or frame==u.confirmation
    if frame==u.correction then parent=u.main
    elseif frame==u.lootReason or frame==u.personalColor or frame==u.endSession then parent=u.settingsHub
    elseif frame==u.itemTools then parent=u.lootPanels and u.lootPanels.timer.window
    elseif frame==u.confirmation then parent=frame.sltDialogOwner
    elseif frame==u.reroll then
        parent=u.main and u.main:IsShown() and u.main or u.lootPanels and u.lootPanels.timer.window
    end
    while parent and parent~=UIParent and not parent.sltManagedWindow do parent=parent:GetParent() end
    return parent~=UIParent and parent or nil,modal
end

function A:FocusWindow(frame)
    if not frame or not frame.sltManagedWindow or self.sltLayering then return end
    for _=1,#(self.windowStack or {}) do
        local nextDialog
        for _,candidate in ipairs(self.windowStack or {}) do
            local parent=self:WindowModalOwner(candidate)
            if candidate:IsShown() and parent==frame then nextDialog=candidate end
        end
        if not nextDialog then break end
        frame=nextDialog
    end
    local stack=self.windowStack or {}
    for i=#stack,1,-1 do if stack[i]==frame then table.remove(stack,i) end end
    stack[#stack+1]=frame;self.windowStack=stack
    self:RefreshWindowLayers()
end

function A:RefreshWindowLayers()
    if self.sltLayering then return end
    self.sltLayering=true
    local stack=self.windowStack or {}
    local present={}
    for _,frame in ipairs(stack) do present[frame]=true end
    for _,frame in ipairs(self.allWindowFrames or {}) do
        if not present[frame] then stack[#stack+1]=frame;present[frame]=true end
    end
    self.windowStack=stack
    -- Capture offsets before changing any level: native setters may also move
    -- descendants. Keep each complete window within its own 256-level band.
    local function capture(node,root)
        if node~=root and node.sltManagedWindow then return end
        node.sltFocusRoot=root
        if not node.sltFocusHooked and not node.sltModalBlocker then
            node:HookScript("OnMouseDown",function(f) A:FocusWindow(f.sltFocusRoot) end)
            node.sltFocusHooked=true
        end
        for _,child in ipairs({node:GetChildren()}) do
            if child.sltLayerParent~=node then
                child.sltLayerOffset=math.max(0,math.min(40,child:GetFrameLevel()-node:GetFrameLevel()))
                child.sltLayerParent=node
            end
            capture(child,root)
        end
    end
    local function paint(node,root,base,relative,strata)
        if node~=root and node.sltManagedWindow then return end
        if node.sltModalBlocker then relative=240 end
        node:SetFrameStrata(strata);node:SetFrameLevel(base+relative)
        for _,child in ipairs({node:GetChildren()}) do
            paint(child,root,base,math.min(200,relative+(child.sltLayerOffset or 1)),strata)
        end
    end
    local blocked={}
    for _,frame in ipairs(stack) do
        if frame:IsShown() then
            local parent=self:WindowModalOwner(frame)
            if parent and parent:IsShown() then blocked[parent]=frame end
        end
    end
    for _,parent in ipairs(stack) do
        local dialog=blocked[parent]
        local blocker=parent.sltDialogBlocker
        if dialog and not blocker then
            blocker=CreateFrame("Frame",nil,parent)
            parent.sltDialogBlocker=blocker;blocker.sltModalBlocker=true
            blocker:SetAllPoints(parent);blocker:EnableMouse(true);blocker:EnableMouseWheel(true)
            blocker:SetScript("OnMouseDown",function(f) A:FocusWindow(f.sltBlockedBy) end)
            local shade=blocker:CreateTexture(nil,"BACKGROUND");shade:SetAllPoints();shade:SetColorTexture(0,0,0,.25)
        end
        if blocker then blocker.sltBlockedBy=dialog;blocker:SetShown(dialog~=nil) end
    end
    for _,frame in ipairs(stack) do if frame:IsShown() then capture(frame,frame) end end
    local index=0
    for _,frame in ipairs(stack) do
        if frame:IsShown() then
            index=index+1
            local _,modal=self:WindowModalOwner(frame)
            paint(frame,frame,10+index*256,0,modal and "FULLSCREEN_DIALOG" or "DIALOG")
        end
    end
    self.sltLayering=false
end

function A:RegisterWindowLayers(frame)
    frame.sltManagedWindow=true
    frame:HookScript("OnShow",function(f) A:FocusWindow(f) end)
    frame:HookScript("OnHide",function() A:RefreshWindowLayers() end)
end

-- Personal layout is deliberately separate from shared raid profiles/state.
function A:WindowLayoutStore()
    self:InitStorage()
    local db=SanguineLootCouncilDB
    if type(db.windowLayouts)~="table" then db.windowLayouts={} end
    local character=self.me or "local"
    if type(db.windowLayouts[character])~="table" then db.windowLayouts[character]={} end
    return db.windowLayouts[character]
end

function A:FitVotingDialog(dialog)
    local owner=self.ui and self.ui.votingSurface
    if not owner then return end
    local scale=math.min(1,owner:GetWidth()*0.82/dialog:GetWidth(),owner:GetHeight()*0.8/dialog:GetHeight())
    dialog:SetScale(scale*owner:GetEffectiveScale()/UIParent:GetEffectiveScale())
    dialog:ClearAllPoints();dialog:SetPoint("CENTER",owner,"CENTER",0,0)
end

-- Title controls are personal UI state; never part of raid communication.
function A:LayoutTitleText(title,left,width,barHeight)
    title:ClearAllPoints();title:SetPoint("TOPLEFT",left,-4)
    title:SetSize(math.max(1,width),barHeight-8)
    title:SetJustifyH("LEFT");title:SetJustifyV("MIDDLE")
    title:SetMaxLines(1);title:SetWordWrap(false)
end
function A:WindowLocked(frame)
    local locks=self:WindowLayoutStore().windowLocks
    local name=frame.sltWindowName
    if type(locks)=="table" and type(locks[name])=="boolean" then return locks[name] end
    return self:WindowPositionsLocked()
end
function A:ToggleWindowLock(frame)
    local store=self:WindowLayoutStore()
    if type(store.windowLocks)~="table" then store.windowLocks={} end
    store.windowLocks[frame.sltWindowName]=not self:WindowLocked(frame)
    self:FinishWindowMove(frame)
    self:RefreshWindowChrome(frame)
end
function A:RefreshWindowChrome(frame)
    if frame.sltChrome~=true then return end
    local locked=self:WindowLocked(frame)
    frame.lockButton.locked=locked
    if type(frame.resizeGrip)=="table" or type(frame.resizeGrip)=="userdata" then
        frame.resizeGrip:SetShown(self:CanResizeWindow(frame) and not locked and frame.sltCollapsed~=true)
    end
    frame.lockButton.shackle:ClearAllPoints()
    frame.lockButton.shackle:SetPoint("TOPLEFT",locked and 7 or 10,-4)
    frame.lockButton.leftStem:SetShown(locked)
    frame.collapseButton:SetText(frame.sltCollapsed==true and "+" or "−")
    local width=(self.ui and frame==self.ui.main) and self.ui.votingSurface:GetWidth() or frame:GetWidth()
    frame.sltHeader:SetWidth(width)
    self:LayoutTitleText(frame.title,18,width-110,34)
    if self.ui and frame==self.ui.checkWindow then
        self:LayoutTitleText(frame.title,18,width-260,34)
        self:LayoutTitleText(self.ui.checkExpected,width-250,145,34)
    end
    if frame.sltCollapsed==true then
        self:CaptureWindowBody(frame)
        frame.sltBody:Hide();frame:SetBackdrop(nil);frame:EnableMouse(false);frame:EnableMouseWheel(false)
    end
end
function A:CaptureWindowBody(frame)
    if type(frame.sltBody)~="table" and type(frame.sltBody)~="userdata" then
        frame.sltBody=CreateFrame("Frame",nil,frame)
        frame.sltBody:SetAllPoints(frame)
    end
    local body=frame.sltBody
    -- Reparent content without hiding the window or changing any child's own
    -- visibility. Network/render refreshes can continue safely while collapsed.
    for _,child in ipairs({frame:GetChildren()}) do
        if child~=body and child~=frame.sltHeader then child:SetParent(body) end
    end
    for _,region in ipairs({frame:GetRegions()}) do
        local kind=region:GetObjectType()
        if region~=frame.headerBand and (kind=="FontString" or kind=="Texture") then
            region:SetParent(body)
        end
    end
end
function A:ToggleWindowCollapse(frame)
    if self.ui and frame==self.ui.settingsHub then self:CloseSettingsDropdown() end
    if frame.sltCollapsed==true then
        frame.sltCollapsed=false
        if frame.sltBackdrop then self:StylePanel(frame) end
        frame:EnableMouse(true)
        if frame==self.ui.popup or frame.sltWheelEnabled==true then frame:EnableMouseWheel(true) end
        frame.sltBody:Show()
    else
        frame.sltBackdrop=frame:GetBackdrop()
        frame.sltCollapsed=true
        self:FinishWindowMove(frame)
    end
    self:RefreshWindowChrome(frame)
end
function A:InstallWindowChrome(frame,name,button)
    frame.sltWindowName=name
    if name=="SanguineLootCouncilLauncher" then return end
    frame.sltChrome=true;frame.sltCollapsed=false;frame.sltBody=nil
    local header=CreateFrame("Frame",nil,frame,"BackdropTemplate")
    frame.sltHeader=header
    header:SetPoint("TOPLEFT",0,0);header:SetSize(frame:GetWidth(),34)
    self:StylePanel(header,34)
    frame.headerBand:Hide()
    frame.title:SetParent(header);frame.closeButton:SetParent(header)
    local level=frame:GetFrameLevel();if type(level)=="number" then header:SetFrameLevel(level+30) end
    header:EnableMouse(true);header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart",function() A:BeginWindowMove(frame) end)
    header:SetScript("OnDragStop",function() A:FinishWindowMove(frame,name) end)
    frame.collapseButton=button(header,"−",0,0,22,function() A:ToggleWindowCollapse(frame) end)
    frame.collapseButton:SetSize(22,22);frame.collapseButton:ClearAllPoints();frame.collapseButton:SetPoint("TOPRIGHT",-32,-6)
    local lock=button(header,"",0,0,22,function() A:ToggleWindowLock(frame) end)
    frame.lockButton=lock
    lock:SetSize(22,22);lock:ClearAllPoints();lock:SetPoint("TOPRIGHT",-58,-6)
    local function stroke(parent,x,y,w,h,r,g,b)
        local t=parent:CreateTexture(nil,"ARTWORK");t:SetColorTexture(r,g,b,1)
        t:SetPoint("TOPLEFT",x,y);t:SetSize(w,h);return t
    end
    lock.iconParts={stroke(lock,6,-10,10,8,.84,.86,.89)}
    stroke(lock,10,-12,2,3,.1,.11,.13)
    local shackle=CreateFrame("Frame",nil,lock);shackle:SetSize(8,8);lock.shackle=shackle
    lock.iconParts[#lock.iconParts+1]=stroke(shackle,0,0,8,2,.84,.86,.89)
    lock.iconParts[#lock.iconParts+1]=stroke(shackle,6,-1,2,7,.84,.86,.89)
    lock.leftStem=stroke(shackle,0,-1,2,7,.84,.86,.89)
    lock.iconParts[#lock.iconParts+1]=lock.leftStem
    lock:SetScript("OnEnter",function() for _,part in ipairs(lock.iconParts) do part:SetColorTexture(1,1,1,1) end end)
    lock:SetScript("OnLeave",function() for _,part in ipairs(lock.iconParts) do part:SetColorTexture(.84,.86,.89,1) end end)
    frame:HookScript("OnShow",function() A:RefreshWindowChrome(frame) end)
    self:RefreshWindowChrome(frame)
end

-- Dimensions are UI units; resizing never changes text or icon scale.
local policies={
    SanguineLootCouncilResponses={760,380,680,380,900,475,"responses"},
    SanguineLootCouncilMain={1100,640,1000,560,1300,800,"voting"},
    SanguineLootCouncilTrade={820,440,680,300,960,620,"loot",true},
    SanguineLootCouncilTimer={600,320,440,220,760,460,"timer",true},
    SanguineLootCouncilSettings={1000,720,900,600,1200,820,"middle"},
    SanguineLootCouncilHistory={980,560,840,440,1200,720,"middle"},
    SanguineLootCouncilReadiness={640,500,560,360,760,650,"middle"},
}
function A:WindowPolicy(frame)
    for _,entry in ipairs(self.windowFrames or {}) do if entry.frame==frame then return policies[entry.name] end end
end
function A:CanResizeWindow(frame)
    local p=self:WindowPolicy(frame)
    return p and p[8]==true or false
end
function A:IsReadableWindow(frame) return self:WindowPolicy(frame)~=nil end
function A:WindowPositionsLocked()
    return self:WindowLayoutStore().positionsLocked==true
end
function A:SetWindowPositionsLocked(locked)
    local store=self:WindowLayoutStore()
    store.positionsLocked=locked==true
    store.windowLocks={}
    for _,frame in ipairs(self.allWindowFrames or {}) do self:RefreshWindowChrome(frame) end
    self:RenderSettings()
end
function A:ReadableWindowBounds(frame)
    local p=self:WindowPolicy(frame)
    if not p then return frame:GetWidth(),frame:GetHeight(),frame:GetWidth(),frame:GetHeight() end
    return p[3],p[4],p[5],p[6]
end
function A:ResponseWindowHeight()
    local count=0
    local item=self.state and self:ItemByID(self.popupItem or 0)
    for _,v in ipairs(self:ResponseOptions(item)) do if v.enabled then count=count+1 end end
    local rows=math.ceil(count/3)
    return math.max(380,math.min(475,312+rows*34+math.max(0,rows-2)*8))
end
function A:ResizeReadableWindow(frame,width,height)
    local minW,minH,maxW,maxH=self:ReadableWindowBounds(frame)
    local policy=self:WindowPolicy(frame)
    if policy and not self:CanResizeWindow(frame) then width,height=policy[1],policy[2] end
    local sw,sh=UIParent:GetWidth(),UIParent:GetHeight()
    -- On a smaller desktop fit the available canvas without shrinking fonts.
    local availableW,availableH=math.max(1,sw-32),math.max(1,sh-32)
    if sw<minW+32 then availableW=sw end
    if sh<minH+32 then availableH=sh end
    maxW,maxH=math.min(maxW,availableW),math.min(maxH,availableH)
    minW,minH=math.min(minW,maxW),math.min(minH,maxH)
    if self.ui and frame==self.ui.popup then height=self:ResponseWindowHeight() end
    frame:SetScale(1)
    frame:SetSize(math.max(minW,math.min(maxW,width)),math.max(minH,math.min(maxH,height)))
    self:LayoutReadableWindow(frame)
end
local fractions={TOPLEFT={0,1},TOP={.5,1},TOPRIGHT={1,1},LEFT={0,.5},CENTER={.5,.5},RIGHT={1,.5},BOTTOMLEFT={0,0},BOTTOM={.5,0},BOTTOMRIGHT={1,0}}
function A:WindowTopLeft(frame)
    local point,_,relativePoint,x,y=frame:GetPoint(1)
    local a,b=fractions[point],fractions[relativePoint]
    if not a or not b or not finite(x) or not finite(y) then return 16,60 end
    return b[1]*UIParent:GetWidth()+x-a[1]*frame:GetWidth(),(1-b[2])*UIParent:GetHeight()-y-(1-a[2])*frame:GetHeight()
end
-- Keep one UIParent-relative anchor throughout a drag. Native StartMoving can
-- switch to screen-relative anchors, whose offsets differ at non-default scales.
function A:BeginWindowMove(frame)
    self:FocusWindow(frame)
    if self:WindowLocked(frame) or frame.sltResizing==true then return false end
    if frame.sltMoving then return false end
    local x,y=GetCursorPosition()
    local scale=UIParent:GetEffectiveScale()
    if not finite(x) or not finite(y) or not finite(scale) or scale<=0 then return false end
    local left,top=self:WindowTopLeft(frame)
    frame.sltDrag={x=x,y=y,left=left,top=top,scale=scale}
    frame.sltMoving=true
    if not frame.sltDragHooked then
        frame.sltDragHooked=true
        frame:HookScript("OnUpdate",function(f)
            if not f.sltMoving then return end
            if A:WindowLocked(f) or not IsMouseButtonDown("LeftButton")
                or UIParent:GetEffectiveScale()~=f.sltDrag.scale then
                A:FinishWindowMove(f)
            else A:UpdateWindowMove(f) end
        end)
        frame:HookScript("OnHide",function(f) A:FinishWindowMove(f) end)
    end
    return true
end
function A:UpdateWindowMove(frame)
    local drag=frame.sltDrag
    if not frame.sltMoving or not drag then return end
    local x,y=GetCursorPosition()
    local scale=UIParent:GetEffectiveScale()
    -- A display/scale change invalidates the old mouse coordinate space.
    if scale~=drag.scale or not finite(x) or not finite(y) then return end
    local sw,sh,w,h=UIParent:GetWidth(),UIParent:GetHeight(),frame:GetWidth(),frame:GetHeight()
    local left=math.max(0,math.min(sw-w,drag.left+(x-drag.x)/scale))
    local top=math.max(0,math.min(sh-h,drag.top+(drag.y-y)/scale))
    frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",left,-top)
end
function A:FinishWindowMove(frame,name)
    if not frame.sltMoving then return end
    self:UpdateWindowMove(frame)
    frame.sltMoving=false;frame.sltDrag=nil
    self:ClampWindowPosition(frame)
    self:SaveWindowLayout(frame,name or frame.sltWindowName)
end
function A:ClampWindowPosition(frame)
    if frame.sltMoving then return end
    local x,y=self:WindowTopLeft(frame)
    local sw,sh,w,h=UIParent:GetWidth(),UIParent:GetHeight(),frame:GetWidth(),frame:GetHeight()
    x=math.max(0,math.min(sw-w,x));y=math.max(0,math.min(sh-h,y))
    frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",x,-y)
end
function A:DefaultWindowPosition(frame)
    local p=self:WindowPolicy(frame)
    local sw,sh=UIParent:GetWidth(),UIParent:GetHeight()
    local w,h=frame:GetWidth(),frame:GetHeight()
    local kind=p and p[7] or "middle"
    local x,y=(sw-w)/2,math.max(32,(sh-h)*.28)
    if kind=="loot" then
        x,y=(sw-w)/2,(sh-h)/2
    elseif kind=="responses" then
        local responseW=policies.SanguineLootCouncilResponses[1]
        local lootW=policies.SanguineLootCouncilTrade[1]
        if sw>=responseW+lootW+64 then
            x=(sw-responseW-lootW-24)/2
            if kind=="loot" then x=x+responseW+24 end
        elseif kind=="responses" then x=math.max(16,(sw-w)/2-80)
        else x=math.min(sw-w-16,(sw-w)/2+80) end
        y=math.max(60,sh*.18)
    elseif kind=="timer" then x=sw-w-24;y=math.max(180,sh*.2)
    elseif kind=="voting" then y=math.max(32,sh*.1) end
    frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",x,-y)
    self:ClampWindowPosition(frame)
end
local resetWindowLabels={
    SanguineLootCouncilResponses="Response Window",SanguineLootCouncilMain="Voting Window",
    SanguineLootCouncilTrade="Loot Window",SanguineLootCouncilTimer="Timer Window",
    SanguineLootCouncilSettings="Settings Window",SanguineLootCouncilHistory="History Window",
    SanguineLootCouncilReadiness="Version Check Window",
}
function A:WindowResetChoices()
    local choices={}
    for _,entry in ipairs(self.windowFrames or {}) do
        local label=resetWindowLabels[entry.name]
        if label then choices[#choices+1]={label,entry.name} end
    end
    table.sort(choices,function(a,b) return a[1]<b[1] end)
    return choices
end
function A:ResetOneWindowLayout(name)
    if not resetWindowLabels[name] then return false end
    for _,entry in ipairs(self.windowFrames or {}) do
        if entry.name==name then
            local frame=entry.frame
            self:FinishWindowMove(frame,name)
            self:WindowLayoutStore()[name]=nil
            local policy=self:WindowPolicy(frame)
            if policy then self:ResizeReadableWindow(frame,policy[1],policy[2]) end
            self:DefaultWindowPosition(frame)
            self:SaveWindowLayout(frame,name)
            self:RefreshWindowChrome(frame)
            self:Render()
            return true
        end
    end
    return false
end

function A:ResetWindowLayout()
    local store=self:WindowLayoutStore()
    for _,entry in ipairs(self.windowFrames or {}) do store[entry.name]=nil end
    self:RestoreWindowLayouts()
    self:Render()
end

function A:LayoutReadableWindow(frame)
    local u=self.ui
    if not u then return end
    self:RefreshWindowChrome(frame)
    local w,h=frame:GetWidth(),frame:GetHeight()
    local function place(object,x,y,width,height)
        object:ClearAllPoints();object:SetPoint("TOPLEFT",x,-y)
        if width then object:SetWidth(width) end
        if height then object:SetHeight(height) end
    end
    if frame==u.settingsHub then self:LayoutSettings();return end
    if frame==u.lootTimers.window then self:LayoutLootTimer();return end
    if frame==u.lootPanels.deliveries.window then
        local isLoot=frame==u.lootPanels.deliveries.window
        local p=isLoot and u.lootPanels.deliveries or u.lootTimers
        local old=p.visibleRows or 6
        p.visibleRows=math.max(1,math.min(#p.rows,math.floor((h-(isLoot and 165 or 115))/44)))
        if old~=p.visibleRows then p.page=math.floor((p.page or 0)*old/p.visibleRows) end
        frame.title:SetWidth(w-60)
        local itemWidth=isLoot and w-570 or w-430
        itemWidth=math.max(isLoot and 120 or 90,itemWidth)
        if isLoot then itemWidth=itemWidth+30 end
        local timeX=itemWidth+72
        local timeWidth=isLoot and 90 or math.min(145,math.max(100,w*.23))
        local holderX=timeX+timeWidth+20
        local holderWidth=isLoot and 70 or w-holderX-30
        place(p.itemHeader,24,isLoot and 70 or 50,itemWidth+30)
        place(p.timeHeader,18+timeX,isLoot and 70 or 50,timeWidth)
        place(p.holderHeader,18+holderX,isLoot and 70 or 50,holderWidth)
        for _,header in ipairs({p.itemHeader,p.timeHeader,p.holderHeader}) do header:SetTextColor(.80,.74,.57) end
        if isLoot then place(p.winnerHeader,w-234,70,100);p.winnerHeader:SetTextColor(.80,.74,.57) end
        for i,row in ipairs(p.rows) do
            place(row,18,(isLoot and 88 or 68)+(i-1)*44,w-36,42)
            row.caption:SetWidth(itemWidth)
            place(row.bar,timeX,12,timeWidth,18);row.countdown:SetWidth(timeWidth-4)
            place(row.holder,holderX,isLoot and 8 or 7,holderWidth)
            place(row.holderStatus,holderX,isLoot and 26 or 25,holderWidth)
            if isLoot then
                row.detail:SetWidth(itemWidth)
                place(row.arrow,w-278,10)
                place(row.winner,w-252,8,100)
                place(row.trade,w-130,8,88)
                place(row.tradeSummary,w-252,28,210)
            end
        end
        place(p.empty,24,math.min(150,h*.4),w-48)
        place(p.previous,20,h-(isLoot and 75 or 50));place(p.next,60,h-(isLoot and 75 or 50))
        place(p.pageLabel,110,h-(isLoot and 67 or 42),isLoot and math.min(95,math.max(55,w-625)) or w-140)
        if isLoot then
            p.summary:SetWidth(w-40)
            place(u.itemToolsButton,w-505,h-75,145)
            place(p.queueAll,w-350,h-75,105);place(u.manageLoot,w-235,h-75,100)
            place(p.close,w-125,h-75,100);place(p.footer,20,h-33,w-40)
        end
        return
    elseif frame==u.history then
        local cols=u.historyColumns
        local itemWidth=w-570
        cols[4][3]=itemWidth;cols[5][2]=340+itemWidth
        cols[5][3]=w-65-cols[5][2]
        frame.title:SetWidth(w-60);u.historyScope:SetWidth(w-60)
        place(u.historySearch,20,98,math.min(560,w-60),26)
        place(u.historyMine,20,132,165,26)
        place(u.historyGuildBank,195,132,165,26)
        place(u.historySync,w-170,h-50,130,28)
        place(u.historyDelete,20,h-50,170,28)
        place(u.historySelectAll,200,h-50,145,28)
        place(u.historyDeleteCancel,355,h-50,85,28)
        place(u.historySyncStatus,610,136,w-650,32)
        if u.archiveCompleted then place(u.archiveCompleted,370,132,220,28) end
        if u.archiveHelp then place(u.archiveHelp,20,h-78,w-40,18);u.archiveHelp:SetMaxLines(1) end
        u.historyScroll:ClearAllPoints();u.historyScroll:SetPoint("TOPLEFT",20,-194);u.historyScroll:SetPoint("BOTTOMRIGHT",-35,95)
        for _,col in ipairs(cols) do place(col.heading,20+col[2],171,col[3]) end
        u.historyChild:SetWidth(w-55)
        for _,row in ipairs(u.historyRows) do
            row:SetWidth(w-65)
            for i,col in ipairs(cols) do place(row.cells[i],col[2],7,col[3]) end
        end
        if type(u.historyEmpty)=="table" then u.historyEmpty:SetWidth(w-65) end
        return
    elseif frame==u.checkWindow then
        frame.title:SetWidth(w-200)
        place(u.checkExpected,w-250,22,145)
        u.checkDescription:SetWidth(w-50)
        local playerWidth=w-350
        place(u.checkplayerHeader,20,110,playerWidth)
        place(u.checkaddonHeader,30+playerWidth,110,130)
        place(u.checkversionHeader,170+playerWidth,110,140)
        u.checkChild:SetWidth(w-55)
        for _,row in ipairs(u.checkRows) do
            row:SetWidth(w-55);row.player:SetWidth(playerWidth)
            place(row.addon,playerWidth+10,5,130);place(row.version,playerWidth+150,5,140)
        end
        place(u.checkSummary,20,h-38,w-175);place(u.recheck,w-140,h-48,115)
        return
    end

    if frame==u.popup then
        local body=w-125
        frame.title:SetWidth(w-60)
        u.responseProgress:SetWidth(body)
        u.popupItem:SetWidth(w-152)
        u.popupStatus:SetWidth(body);u.popupFacts:SetWidth(body);u.popupEligibility:SetWidth(body)
        u.responseBar:SetWidth(body)
        u.note:SetWidth(body-10);u.note.hint:SetWidth(body-100)
        local step=(body+10)/3
        local buttonTop=math.min(245,h-145)
        for i,b in ipairs(u.responseButtons) do place(b,92+(i-1)%3*step,buttonTop+math.floor((i-1)/3)*34,step-10) end
        place(u.responsePrevious,92,h-45)
        place(u.responseNext,w-128,h-45)
        local scale=u.responseVoting:GetEffectiveScale()
        if not finite(scale) or scale<=0 then scale=1 end
        local votingX=math.floor((92+(body-200)/2)*scale+.5)/scale
        place(u.responseVoting,votingX,h-45)
        self:StyleButtonOutline(u.responseVoting)
        place(u.responseRoleHint,202,h-37,math.max(100,body-220))
    elseif frame==u.main then
        -- All panels fit within the actual window; never crop a larger canvas.
        local sidebar=math.min(304,math.max(264,math.floor(w*304/1100+0.5)))
        local surface=w-sidebar-16
        u.votingSurface:SetSize(surface,h)
        frame.title:SetParent(frame.sltHeader or u.votingSurface)
        place(frame.title,80,12,surface-130)
        frame.closeButton:SetParent(frame.sltHeader or u.votingSurface)
        frame.closeButton:ClearAllPoints();frame.closeButton:SetPoint("TOPRIGHT",-6,-6)
        u.status:SetWidth(surface-100);u.status:SetMaxLines(1)
        u.itemTitle:SetWidth(surface-145);u.itemTitle:SetMaxLines(1)
        u.itemDetails:SetWidth(surface-145)
        local barWidth=math.min(210,math.floor((surface-140)*0.42))
        u.councilResponseBar:SetWidth(barWidth)
        place(u.itemStatus,127+barWidth+12,112,surface-149-barWidth,16)
        place(u.councilEmpty,90,190,surface-110,100)
        self:LayoutVotingColumns(surface)
        local oldItems,oldCandidates=self.votingItemRows,self.votingCandidateRows
        self.votingItemRows=math.min(9,math.max(3,math.floor((h-251)/43)))
        self.votingCandidateRows=math.min(14,math.max(3,math.floor((h-332)/22)))
        if oldItems and oldItems~=self.votingItemRows then
            for i,item in ipairs(self.state and self.state.items or {}) do if item.id==self.selectedItem then self.itemPage=math.floor((i-1)/self.votingItemRows);break end end
        end
        if oldCandidates and oldCandidates~=self.votingCandidateRows then self.candidateRowsChanged=true end
        u.votingItemRail:SetHeight((self.votingItemRows or 9)*43)
        place(u.itemPages,15,h-182,50,14)
        place(u.itemPrev,16,h-162,22,22);place(u.itemNext,42,h-162,22,22)
        place(u.candidatePrev,80,h-177,85);place(u.candidateNext,surface-91,h-177,85)
        place(u.playerPagePrevious,surface-210,h-137,95);place(u.playerPageNext,surface-110,h-137,95)
        place(u.selection,175,h-171,math.max(100,surface-455));place(u.playerHistory,surface-270,h-177)
        place(u.votingProgress,80,h-137,surface-310)
        place(u.votingOwn,80,h-105,surface-90,42)
        place(u.open,80,h-60)
        place(u.correctAward,250,h-60,140)
        place(u.votingResponses,surface-(self:IsMaster() and 225 or 145),h-60)
        place(u.votingLoot,surface-90,h-60)
        local topHeight=math.floor(h/2)
        place(u.selectedLootPane,surface+16,0,sidebar,topHeight)
        local scrollWidth=sidebar-38
        u.selectedLootScroll:SetWidth(scrollWidth);u.selectedLootChild:SetWidth(scrollWidth)
        u.selectedLootPlaceholder:SetWidth(scrollWidth-16)
        u.selectedLootScroll:SetHeight(topHeight-41)
        local p=u.votingHistory
        local historyHeight=h-topHeight-12
        place(p.frame,surface+16,topHeight+12,sidebar,historyHeight)
        p.title:SetWidth(sidebar-24);p.title:SetMaxLines(1)
        p.summary:SetWidth(sidebar-24)
        p.scroll:SetWidth(scrollWidth);p.child:SetWidth(scrollWidth);p.empty:SetWidth(scrollWidth-16)
        for _,row in ipairs(p.rows) do row:SetWidth(scrollWidth-4);row.item:SetWidth(scrollWidth-44);row.detail:SetWidth(scrollWidth-44) end
        p.scroll:SetHeight(historyHeight-80)
        place(p.footer,10,historyHeight-18,sidebar-20)
        self:SizeSelectedLootTooltip()
    end
end

function A:SaveWindowLayout(frame,name)
    if frame.sltMoving then return end
    local point,_,relativePoint,x,y=frame:GetPoint(1)
    local scale=frame:GetScale()
    if not anchors[point] or not anchors[relativePoint] or not finite(x) or not finite(y) or not finite(scale) then return end
    local saved={point=point,relativePoint=relativePoint,x=x,y=y,scale=scale}
    if self:IsReadableWindow(frame) then saved.width,saved.height,saved.geometryVersion=frame:GetWidth(),frame:GetHeight(),3 end
    if name=="SanguineLootCouncilTrade" then saved.centeredLoot=true end
    self:WindowLayoutStore()[name]=saved
end

function A:WindowScale(frame,scale)
    local parentScale=UIParent:GetEffectiveScale()
    local width,height=UIParent:GetWidth(),UIParent:GetHeight()
    local fw,fh=frame:GetWidth(),frame:GetHeight()
    local maximum=2
    if finite(width) and finite(height) and finite(fw) and finite(fh) and finite(parentScale) and fw>0 and fh>0 then
        maximum=math.min(maximum,width/fw,height/fh)
    end
    return math.max(math.min(0.5,maximum),math.min(maximum,scale))
end

function A:InstallWindowResizeGrip(frame,name)
    if type(frame.resizeGrip)=="table" or type(frame.resizeGrip)=="userdata" then return end
    local grip=CreateFrame("Button",nil,frame)
    frame.resizeGrip=grip;grip:SetSize(18,18);grip:SetPoint("BOTTOMRIGHT",-3,3)
    local level=frame:GetFrameLevel();if type(level)=="number" then grip:SetFrameLevel(level+20) end
    for i=1,3 do
        local line=grip:CreateTexture(nil,"ARTWORK");line:SetSize(i*4,1.5)
        line:SetRotation(math.pi/4);line:SetPoint("CENTER",5-i*2,-5+i*2)
        line:SetColorTexture(.52,.54,.59,1)
    end
    local resizing
    local function finish()
        if not resizing then return end
        resizing=nil;frame.sltResizing=false
        A:ClampWindowPosition(frame);A:SaveWindowLayout(frame,name)
    end
    grip:SetScript("OnMouseDown",function(_,mouse)
        if mouse~="LeftButton" or A:WindowLocked(frame) or frame.sltCollapsed==true then return end
        local x,y=GetCursorPosition();if not finite(x) or not finite(y) then return end
        local left,top=A:WindowTopLeft(frame)
        resizing={x=x,y=y,left=left,top=top,width=frame:GetWidth(),height=frame:GetHeight()}
        frame.sltResizing=true
    end)
    grip:SetScript("OnUpdate",function()
        if not resizing then return end
        if A:WindowLocked(frame) or frame.sltCollapsed==true then finish();return end
        local x,y=GetCursorPosition();if not finite(x) or not finite(y) then return end
        if resizing.lastX==x and resizing.lastY==y then return end
        resizing.lastX,resizing.lastY=x,y
        local scale=UIParent:GetEffectiveScale();if not finite(scale) or scale<=0 then scale=1 end
        local width=math.min(resizing.width+(x-resizing.x)/scale,UIParent:GetWidth()-resizing.left-16)
        local height=math.min(resizing.height+(resizing.y-y)/scale,UIParent:GetHeight()-resizing.top-16)
        A:ResizeReadableWindow(frame,width,height)
        frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",resizing.left,-resizing.top)
        A:ClampWindowPosition(frame);A:RenderLootWindows()
    end)
    grip:SetScript("OnMouseUp",finish);grip:HookScript("OnHide",finish);frame:HookScript("OnHide",finish)
end

function A:RestoreWindowLayouts()
    local store=self:WindowLayoutStore()
    for _,entry in ipairs(self.windowFrames or {}) do
        local f,name=entry.frame,entry.name
        self:FinishWindowMove(f,name)
        local saved,p=store[name],self:WindowPolicy(f)
        f:SetScale(1)
        if p then
            local width,height=p[1],p[2]
            if self:CanResizeWindow(f) and type(saved)=="table" and saved.geometryVersion==3
                and finite(saved.width) and finite(saved.height) and saved.width>0 and saved.height>0 then
                width,height=saved.width,saved.height
            end
            self:ResizeReadableWindow(f,width,height)
        end
        if p and p[7]=="loot" and (type(saved)~="table" or saved.centeredLoot~=true) then
            self:DefaultWindowPosition(f)
        elseif type(saved)=="table" and anchors[saved.point] and anchors[saved.relativePoint] and finite(saved.x) and finite(saved.y) then
            f:ClearAllPoints();f:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y)
            self:ClampWindowPosition(f)
        else self:DefaultWindowPosition(f) end
        self:SaveWindowLayout(f,name)
        f:SetScript("OnDragStart",function(frame) A:BeginWindowMove(frame) end)
        f:SetScript("OnDragStop",function(frame)
            A:FinishWindowMove(frame,name)
        end)
        if self:CanResizeWindow(f) then
            self:InstallWindowResizeGrip(f,name)
        else f.resizeGrip=false end
        self:RefreshWindowChrome(f)

    end
    if not self.windowDisplayEvents then
        local events=CreateFrame("Frame");self.windowDisplayEvents=events
        events:RegisterEvent("DISPLAY_SIZE_CHANGED");events:RegisterEvent("UI_SCALE_CHANGED")
        events:SetScript("OnEvent",function()
            for _,entry in ipairs(A.windowFrames or {}) do
                local f=entry.frame
                A:FinishWindowMove(f,entry.name)
                if A:IsReadableWindow(f) then A:ResizeReadableWindow(f,f:GetWidth(),f:GetHeight()) end
                A:ClampWindowPosition(f);A:SaveWindowLayout(f,entry.name)
            end
            A:Render()
        end)
    end
end
