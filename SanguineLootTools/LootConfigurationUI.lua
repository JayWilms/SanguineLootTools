local _,A=...
local qualities={"Grey • Poor","White • Common","Green • Uncommon","Blue • Rare","Purple • Epic","Orange • Legendary"}
local qualityColours={"ff9d9d9d","ffffffff","ff1eff00","ff0070dd","ffa335ee","ffff8000"}
for i,label in ipairs(qualities) do qualities[i]="|c"..qualityColours[i]..label.."|r" end
local actions={ignore="Ignore",council="Collect for council",assign="Assign automatically"}
local reasonLabels={Disenchant="Disenchanted",["Guild Bank"]="Guild Bank",Other="Other"}
function A:BuildLootConfigurationUI(u,window,text,button,edit,dropdown,position,section,row,switch)
    local content=u.settingsPages["Loot Configuration"].content
    u.lootConfigGroups={};u.lootConfigOpen={collection=true,rules=true}
    local function group(key,title)
        local g={};u.lootConfigGroups[key]=g
        g.header=button(content,"",0,0,690,function() A:CloseSettingsDropdown();u.lootConfigOpen[key]=not u.lootConfigOpen[key];A:LayoutLootConfiguration() end)
        g.title=text(g.header,title,14,12,-9,540)
        g.arrow=button(g.header,"",0,0,34,function() g.header:Click() end);A:StyleRailArrow(g.arrow,1)
        g.body=CreateFrame("Frame",nil,content)
        return g.body
    end
    local collection=group("collection","Collection")
    switch(u.lootPanels.timer.auto)
    u.lootPanels.timer.auto:SetScript("OnClick",function() local c=A:LootConfiguration();c.collection=not c.collection;A:SaveLootConfiguration(c) end)
    row(collection,"Automatic collection","Collect council loot into the Master Looter's bags and detect eligible pickups. Existing tracking keeps refreshing.",0,u.lootPanels.timer.auto,76)
    u.lootMinimum=button(collection,"",0,0,180,function() end)
    dropdown(u.lootMinimum,{{"Green and above",2},{"Blue and above",3},{"Epic and above",4},{"Legendary only",5}},function(v) local c=A:LootConfiguration();c.minimum=v;A:SaveLootConfiguration(c) end)
    row(collection,"Council collection threshold","Applies to Collect for council rules, including items with a trade timer.",72,u.lootMinimum)
    u.lootOpen=button(collection,"",0,0,76,function() local c=A:LootConfiguration();c.openWindow=not c.openWindow;A:SaveLootConfiguration(c) end);switch(u.lootOpen)
    row(collection,"Open Loot on discovery","Open the Loot window when new items arrive. Tracking continues when disabled.",144,u.lootOpen,76)
    u.lootAutomatic=button(collection,"",0,0,76,function() local c=A:LootConfiguration();c.automatic=not c.automatic;A:SaveLootConfiguration(c) end);switch(u.lootAutomatic)
    row(collection,"Automatic assignment","Requires a recipient and reason for each Assign automatically rule. Starts off.",216,u.lootAutomatic,76)
    u.lootRoutingStatus=text(collection,"",11,0,-285,690);position(u.lootRoutingStatus,collection,0,285,function(w) return w end,44)
    local rules=group("rules","Quality Rules • Raid Leader Only")
    u.lootQualityRows={}
    for i=1,6 do
        local index=i;local r={};u.lootQualityRows[i]=r
        r.title=text(rules,qualities[i],12,0,0,170)
        r.action=button(rules,"",0,0,180,function() end)
        dropdown(r.action,{{"Ignore","ignore"},{"Collect for council","council"},{"Assign automatically","assign"}},function(value) local c=A:LootConfiguration();c.rules[index].action=value
            if value=="assign" and c.automatic and (c.rules[index].target=="" or c.rules[index].reason=="") then c.automatic=false;A:Print("Automatic assignment paused. Choose the recipient and reason, then enable it again.") end
            A:SaveLootConfiguration(c) end)
        r.recipient=button(rules,"",0,0,230,function() end)
        dropdown(r.recipient,function()
            local choices={{"Current Master Looter","@master"}};local names={}
            for name in pairs(A.roster) do names[#names+1]=name end;table.sort(names)
            for _,name in ipairs(names) do choices[#choices+1]={name,name} end
            choices[#choices+1]={"Enter Name-Realm…","@edit"}
            return choices
        end,function(value) if value=="@edit" then A:OpenLootReason(index);return end;local c=A:LootConfiguration();c.rules[index].target=value;A:SaveLootConfiguration(c) end)
        r.reason=button(rules,"Edit reason",0,0,100,function() A:OpenLootReason(index) end)
        r.help=text(rules,"",11,0,0,690);r.help:SetMaxLines(2);r.help:SetHeight(30)
    end
    u.lootReason=window("SanguineLootToolsLootReason","Automatic Assignment Reason",560,310,true)
    u.lootReasonTitle=text(u.lootReason,"",14,20,-50,520)
    u.lootReasonPreset=button(u.lootReason,"Choose a reason",20,-85,250,function() end)
    dropdown(u.lootReasonPreset,{{"Disenchanted","Disenchant"},{"Guild Bank","Guild Bank"},{"Other","Other"}},function(value) u.lootReasonChoice=value;u.lootReasonPreset:SetText(reasonLabels[value] or value) end)
    u.lootReasonRecipient=edit(u.lootReason,25,-145,510,"Recipient Name-Realm • blank uses current Master Looter")
    u.lootReasonRecipient:SetMaxLetters(100)
    u.lootReasonNote=edit(u.lootReason,25,-205,510,"Optional note • up to 100 bytes");u.lootReasonNote:SetMaxLetters(100)
    u.lootReasonSave=button(u.lootReason,"Save reason",20,-265,250,function()
        local context=A.lootReasonContext;local state=A.state
        if not context or not A:CanConfigureRaid() or context.sid~=(state and state.id or false) or context.revision~=(state and state.lootConfigRevision or SanguineLootCouncilDB.raidSetupRevision or 0) then A:Print("Loot settings changed. Reopen Edit reason.");u.lootReason:Hide();return end
        local c=A:LootConfiguration();local r=c.rules[context.index]
        if not A:IsLootAwardReason(u.lootReasonChoice) then A:Print("Choose Disenchanted, Guild Bank or Other.");return end
        local entered=u.lootReasonRecipient:GetText():match("^%s*(.-)%s*$")
        local target=entered=="" and "@master" or A:SetupMemberName(entered)
        if not target then A:Print("Enter a full recipient Name-Realm, or leave blank for the current Master Looter.");return end
        r.target=target
        r.reason=u.lootReasonChoice;r.note=u.lootReasonNote:GetText()
        if A:SaveLootConfiguration(c)~=false then u.lootReason:Hide();A.lootReasonContext=nil end
    end)
    button(u.lootReason,"Cancel",290,-265,250,function() u.lootReason:Hide();A.lootReasonContext=nil end)
    u.lootReason:HookScript("OnHide",function() A:CloseSettingsDropdown();u.lootReasonNote:ClearFocus();u.lootReasonRecipient:ClearFocus();A.lootReasonContext=nil end)
end
function A:OpenLootReason(index)
    if not self:CanConfigureRaid() or not self.ui or not self.ui.lootQualityRows[index] then return end
    self:CloseSettingsDropdown()
    local c=self:LootConfiguration();local r=c.rules[index];local u=self.ui
    self.lootReasonContext={index=index,sid=self.state and self.state.id or false,revision=self.state and self.state.lootConfigRevision or SanguineLootCouncilDB.raidSetupRevision or 0}
    u.lootReasonRecipient:SetText(r.target=="@master" and "" or r.target)
    u.lootReasonTitle:SetText(qualities[index]);u.lootReasonChoice=r.reason;u.lootReasonPreset:SetText(r.reason~="" and (reasonLabels[r.reason] or r.reason) or "Choose a reason");u.lootReasonNote:SetText(r.note);u.lootReason:Show()
end
function A:LayoutLootConfiguration()
    local u=self.ui;if not u or not u.lootConfigGroups then return end
    local body=u.settingsHub:GetWidth()-260;local y=0
    local function at(o,x,top,w,h) o:ClearAllPoints();o:SetPoint("TOPLEFT",x,-top);o:SetSize(w,h) end
    for _,key in ipairs({"collection","rules"}) do
        local g=u.lootConfigGroups[key];local open=u.lootConfigOpen[key]
        local height=key=="collection" and 335 or 630
        at(g.header,0,y,body,36);at(g.arrow,body-35,1,34,34);g.title:SetWidth(body-55)
        self:SetRailArrowDirection(g.arrow,open and -1 or 1)
        at(g.body,0,y+46,body,height);g.body:SetShown(open);y=y+46+(open and height+16 or 0)
    end
    for i,r in ipairs(u.lootQualityRows) do
        local top=(i-1)*105
        at(r.title,0,top,body,20)
        at(r.action,0,top+25,180,28);at(r.recipient,190,top+25,body-300,28);at(r.reason,body-100,top+25,100,28)
        at(r.help,0,top+60,body,34)
    end
    u.settingsPages["Loot Configuration"].content:SetHeight(y)
    local scroll=u.settingsScrolls["Loot Configuration"];local current=scroll:GetVerticalScroll()
    if type(current)=="number" then scroll:SetVerticalScroll(math.min(current,math.max(0,y-scroll:GetHeight()))) end
end
function A:RenderLootConfigurationUI()
    local u=self.ui;if not u or not u.lootConfigGroups then return end
    local c=self:LootConfiguration();local editable=self:CanConfigureRaid()
    local labels={[2]="Green and above",[3]="Blue and above",[4]="Epic and above",[5]="Legendary only"}
    u.lootMinimum:SetText(labels[c.minimum]);u.lootMinimum:SetEnabled(editable)
    self:SetSettingsToggle(u.lootOpen,c.openWindow);u.lootOpen:SetEnabled(editable)
    self:SetSettingsToggle(u.lootAutomatic,c.automatic);u.lootAutomatic:SetEnabled(editable)
    local pending,failed=0,0
    for _,intent in pairs(self.state and self.state.corpseRoutes or {}) do
        if intent.failed or (not intent.finished and self.Client:ServerTime()-intent.time>60) then failed=failed+1
        elseif not intent.finished then pending=pending+1 end
    end
    local summary=(pending>0 or failed>0) and (" | Corpse assignments: "..pending.." awaiting verification, "..failed.." unresolved") or ""
    u.lootRoutingStatus:SetText((editable and "Raid Leader controls" or "View only • Raid Leader controls").." | "..(self.demo and "Test mode: physical distribution disabled" or self.lootRoutingStatus or (c.collection and "Council collection enabled; eligible loot goes to the Master Looter unawarded" or c.automatic and "Automatic assignment enabled" or "Automatic collection and assignment off"))..summary)
    for i,row in ipairs(u.lootQualityRows) do
        local r=c.rules[i];row.action:SetText(actions[r.action]);row.action:SetEnabled(editable)
        row.recipient:SetText(r.action=="council" and "Current Master Looter" or r.target=="@master" and "Current Master Looter" or r.target~="" and r.target or "Choose recipient")
        row.recipient:SetEnabled(editable and r.action=="assign");row.reason:SetEnabled(editable and r.action=="assign")
        row.help:SetText(r.action=="assign" and ((r.reason~="" and (reasonLabels[r.reason] or r.reason) or "Set a reason before enabling automation")..(r.note~="" and " • "..r.note or "")) or r.action=="ignore" and "Excluded from automatic collection; manual Add loot remains available." or "With collection enabled, eligible single-copy loot goes to the Master Looter unawarded. Queue from Loot for responses.")
    end
    if not editable then u.lootReason:Hide();self.lootReasonContext=nil end
    self:LayoutLootConfiguration()
end
