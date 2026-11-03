local _, A=...
local allowed={ADDON_LOADED=true,PLAYER_ENTERING_WORLD=true,GROUP_ROSTER_UPDATE=true,PARTY_LOOT_METHOD_CHANGED=true,
    BAG_UPDATE_DELAYED=true,TRADE_SHOW=true,TRADE_CLOSED=true,TRADE_REQUEST_CANCEL=true,TRADE_ACCEPT_UPDATE=true,
    TRADE_PLAYER_ITEM_CHANGED=true,TRADE_TARGET_ITEM_CHANGED=true,TRADE_MONEY_CHANGED=true,UI_INFO_MESSAGE=true,UI_ERROR_MESSAGE=true}
local function safeNumber(value)
    return type(value)=="number" and value==value and value>=0 and value<=1000000000 and value%1==0
end
function A:DiagnosticEvent(event,code)
    if not self.diagnosticRecording or not allowed[event] then return end
    if type(issecretvalue)=="function" and issecretvalue(code) then code=nil end
    local events=self.diagnosticEvents or {};self.diagnosticEvents=events
    events[#events+1]={at=math.max(0,self.Client:Uptime()-(self.diagnosticStarted or self.Client:Uptime())),
        event=event,code=safeNumber(code) and code or nil}
    while #events>200 do table.remove(events,1) end
end
function A:StartDiagnostics()
    self.diagnosticRecording,self.diagnosticEvents,self.diagnosticStarted=true,{},self.Client:Uptime()
    self:Print("Local diagnostic recording started (latest 200 technical events). /slt diagnostics stop ends it; /slt diagnostics opens a report to copy. Nothing is uploaded.")
end
function A:DiagnosticReport()
    local lines={"Sanguine Loot Tools diagnostic report", "Addon: "..self.version.." | protocol "..self.protocol,
        "Contract fixture: "..self.Client.fixtureVersion,"Native compatibility: unverified until tester records target client results"}
    local ok,version,build,_,interface=self.Client:Call("GetBuildInfo")
    local function technical(value)
        if type(value)~="string" and type(value)~="number" then return "Unknown" end
        local s=tostring(value)
        return #s<=40 and s:match("^[%w%.%-]+$") and s or "Unknown"
    end
    lines[#lines+1]="Client: "..(ok and technical(version) or "Unknown").." | build "..technical(build).." | interface "..technical(interface)
    local db=self:ItemLibrary()
    local metadataOK,dependencyVersion=self.Client:Call("GetAddOnMetadata","ItemDB","Version")
    lines[#lines+1]="ItemDB version: "..(metadataOK and technical(dependencyVersion) or "Unknown")
    lines[#lines+1]="ItemDB: "..(db and "ready" or "missing/not ready").." (external; see installed dependency version)"
    local queued,age,bytes=self:NetworkQueueStats()
    lines[#lines+1]=string.format("Queue: %d fragments | %.1fs oldest | %d payload bytes",queued,age,bytes or 0)
    local metrics=self.networkMetrics or {}
    lines[#lines+1]=string.format("Ignored background requests: %d expired assignments | %d unrelated trades",metrics.staleCorpseRequests or 0,metrics.irrelevantTradeReports or 0)
    lines[#lines+1]=string.format("Duplicate assignment confirmations: %d without new broadcasts",metrics.duplicateCorpseRequests or 0)
    lines[#lines+1]=string.format("Queue peaks: %d fragments | %.1fs oldest | %d bytes | send failures %d | overflows %d",
        metrics.maxFragments or 0,metrics.maxAge or 0,metrics.maxBytes or 0,metrics.sendFailures or 0,metrics.overflows or 0)
    lines[#lines+1]="Last send result: "..technical(metrics.lastResult)
    lines[#lines+1]=string.format("Throttle events: %d | minimum spacing: %.2fs | target refill: %.2f/s",metrics.throttleEvents or 0,metrics.sendInterval or 0.10,metrics.refillRate or 1)
    if metrics.lastReleaseFragments then
        lines[#lines+1]=string.format("Last loot release: %d fragments | %d payload bytes",metrics.lastReleaseFragments,metrics.lastReleaseBytes or 0)
    end
    if metrics.lastThrottleAt then
        lines[#lines+1]=string.format("Last throttle: result %s | %.1fs ago",technical(metrics.lastThrottleResult),math.max(0,self.Client:Uptime()-metrics.lastThrottleAt))
    end
    lines[#lines+1]=string.format("Receive: %d fragments | %d decoded packets | %d decode failures | %d protocol mismatches",
        metrics.receivedFragments or 0,metrics.decodedPackets or 0,metrics.decodeFailures or 0,metrics.protocolMismatches or 0)
    lines[#lines+1]="Role: "..(self:IsLeader() and "raid leader" or self:IsMaster() and "master looter" or self:IsCouncil() and "council" or "raider")
    lines[#lines+1]="Combat: "..(self.Client:Combat() and "paused/unknown" or "out of combat").." | response deadlines continue"
    lines[#lines+1]="Clocks: "..(self.Client:ClockReady() and "available" or "unavailable; mutations disabled")
    lines[#lines+1]="Active: "..#(self.state and self.state.items or {}).." items / "..#(self.state and self.state.trackedLoot or {}).." copies | archived this session "..(self.state and self.state.archivedCount or 0)
    local loot=self:LootConfiguration()
    lines[#lines+1]="Session: "..(self.state and (self.demo and "test" or "normal") or "none").." | automatic collection: "..(self.state and self.state.autoCollect~=false and loot.collection and "on" or "off").." | automatic assignment: "..(loot.automatic and "on" or "off").." | minimum quality: "..loot.minimum.." | green rule: "..loot.rules[3].action.." | blue rule: "..loot.rules[4].action
    local nativeMaster,nativeStatus
    if self.ReadGameMaster then nativeMaster,nativeStatus=self:ReadGameMaster() end
    lines[#lines+1]="Master Loot routing: addon authority "..(self.state and self.state.masterBlocked and "blocked" or self:IsMaster() and "local" or "other").." | native status "..technical(nativeStatus).." | local native master "..(nativeMaster==self.me and "yes" or "no").." | corpse window "..(self.corpseOpen and "open" or "closed")
    lines[#lines+1]="Loot detection: "..(self.lootPickupMessages or 0).." self pickup messages | last scan reports: "..(self.lootLastReportCount or 0).." | "..(self.lootScanStatus or "No bag scan yet")
    lines[#lines+1]=string.format("Settings menus: %d opens | %d option clicks",self.settingsMenuOpens or 0,self.settingsMenuClicks or 0)
    local claims=0
    for _,claim in pairs(self.lootHolderClaims or {}) do if self.Client:ServerTime()-claim.sampledAt<=90 then claims=claims+1 end end
    lines[#lines+1]=string.format("Holder handovers: %d confirmed | %d awaiting matching bag evidence",self.lootHandoverCount or 0,claims)
    local ready,start,clear,receipt,expired,oldest,stacked=0,0,0,0,0,0,0
    for _,route in pairs(self.state and self.state.corpseRoutes or {}) do
        if route.failed and route.failure=="stacked" then stacked=stacked+1 end
        if not route.finished and not route.failed then
            local age=math.max(0,self.Client:ServerTime()-(route.time or 0))
            oldest=math.max(oldest,age)
            if age>60 then expired=expired+1
            elseif not route.ready then ready=ready+1
            elseif not route.started then start=start+1
            elseif not route.cleared then clear=clear+1
            elseif not route.guid then receipt=receipt+1 end
        end
    end
    lines[#lines+1]=string.format("Automatic assignments pending: %d recipient ready | %d start | %d corpse clear | %d bag receipt | %d expired | %ds oldest",ready,start,clear,receipt,expired,oldest)
    lines[#lines+1]=string.format("Stackable material routes requiring manual distribution: %d",stacked)
    lines[#lines+1]="API presence (presence alone does not verify behaviour):"
    for _,api in ipairs(self.Client:APIInventory()) do lines[#lines+1]=api.name..": "..(api.available and "present" or "MISSING") end
    lines[#lines+1]="Recording: "..(self.diagnosticRecording and "on" or "off").." | latest 200 events, current login only"
    for _,event in ipairs(self.diagnosticEvents or {}) do
        lines[#lines+1]=string.format("+%.1fs %s%s",event.at,event.event,event.code and (" code="..event.code) or "")
    end
    lines[#lines+1]="No names, GUIDs, links, notes, ballots, message contents or chat are included. Review this text before sharing. No automatic upload."
    return table.concat(lines,"\n")
end
function A:BuildDiagnosticUI(u,window,text,button)
    u.diagnostics=window("SanguineLootCouncilDiagnostics","Local diagnostics — select and copy report",780,570)
    text(u.diagnostics,"Read-only addon report. Ctrl+A / Ctrl+C in the box; share it yourself if needed.",11,20,-48,720)
    local scroll=A:CreateScrollFrame(u.diagnostics)
    scroll:SetPoint("TOPLEFT",20,-78);scroll:SetSize(720,420)
    local box=CreateFrame("EditBox",nil,scroll)
    box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFontObject("ChatFontNormal");box:SetWidth(695)
    box:SetScript("OnEscapePressed",function(b) b:ClearFocus() end)
    box:SetScript("OnTextChanged",function(b)
        -- EditBox text metrics differ between client branches. Reserve space
        -- per line if the optional native measurement is unavailable.
        local value=b:GetText() or ""
        local _,newlines=value:gsub("\n","")
        local height=(newlines+1)*32
        if type(b.GetStringHeight)=="function" then
            local ok,measured=A.Client:Invoke(b.GetStringHeight,b)
            if ok and type(measured)=="number" and measured>0 then height=measured+20 end
        end
        b:SetHeight(math.max(420,height))
        if b.report and b:GetText()~=b.report then b:SetText(b.report) end
    end)
    scroll:SetScrollChild(box);u.diagnosticText=box
    button(u.diagnostics,"Refresh report",20,-520,215,function() A:ShowDiagnostics() end)
    button(u.diagnostics,"Start recording",260,-520,215,function() A:StartDiagnostics();A:ShowDiagnostics() end)
    button(u.diagnostics,"Stop recording",500,-520,215,function() A.diagnosticRecording=false;A:ShowDiagnostics() end)
end
function A:ShowDiagnostics()
    self:BuildUI()
    local box=self.ui.diagnosticText
    box.report=self:DiagnosticReport();box:SetText(box.report)
    self.ui.diagnostics:Show()
    box:SetFocus();box:HighlightText()
end
