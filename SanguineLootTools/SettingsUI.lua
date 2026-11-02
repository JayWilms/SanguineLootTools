local _,A=...
local function move(object,parent,x,y,width,height)
    object:SetParent(parent);object:ClearAllPoints();object:SetPoint("TOPLEFT",x,-y)
    if width then object:SetWidth(width) end
    if height then object:SetHeight(height) end
end
local pageOrder={"Session","Loot Configuration","Responses","Council","Alerts","Profiles","Advanced"}
local pageDescriptions={["Loot Configuration"]="Choose what is collected, who receives automatic assignments and why.",Session="Manage this raid and its response rounds.",Responses="Configure raid choices and personalise your colours.",Council="Assign loot authority and set council voting rules.",Alerts="Control trade-expiry warnings and sounds.",Profiles="Reuse your raid configuration.",Advanced="Recovery and diagnostics for when you need them."}
local togglePath="Interface\\AddOns\\SanguineLootTools\\Assets\\"
local function switch(control)
    control:SetSize(76,26);control:SetBackdrop(nil)
    control:GetHighlightTexture():SetAlpha(0);control:GetPushedTexture():SetAlpha(0)
    control.track=control:CreateTexture(nil,"BACKGROUND");control.track:SetSize(40,20);control.track:SetPoint("LEFT",4,0)
    control.track:SetTexture(togglePath.."TogglePill.tga");control.track:SetVertexColor(.055,.06,.07,1)
    control.outline=control:CreateTexture(nil,"ARTWORK");control.outline:SetAllPoints(control.track)
    control.outline:SetTexture(togglePath.."ToggleOutline.tga");control.outline:SetVertexColor(.72,.56,.28,1)
    control.knob=control:CreateTexture(nil,"OVERLAY");control.knob:SetSize(14,14)
    control.knob:SetTexture(togglePath.."ToggleKnob.tga");control.knob:SetPoint("LEFT",7,0)
    local label=control:GetFontString();label:ClearAllPoints();label:SetPoint("LEFT",49,0);label:SetPoint("RIGHT",0,0)
    label:SetJustifyH("RIGHT");label:SetMaxLines(1)
    control.sltToggle=true
end
local function switchValue(control,on)
    on=on==true
    control.toggleOn=on;control:SetText(on and "On" or "Off")
    control.knob:ClearAllPoints();control.knob:SetPoint("LEFT",on and 27 or 7,0)
    control.knob:SetVertexColor(on and .90 or .75,on and .72 or .59,on and .38 or .29,1)
    local enabled=control:IsEnabled()~=false
    control.track:SetAlpha(enabled and 1 or .45);control.outline:SetAlpha(enabled and 1 or .35)
    control.knob:SetAlpha(enabled and 1 or .4)
    control:GetFontString():SetTextColor(enabled and .78 or .40,enabled and .80 or .42,enabled and .84 or .46)
end
function A:SetSettingsToggle(control,on) switchValue(control,on) end
function A:BindSettingsDropdown(control,choices,action,button)
    local function toggle() self:OpenSettingsDropdown(control,type(choices)=="function" and choices() or choices,action) end
    control:SetScript("OnClick",toggle)
    local arrow=button(control,"",0,0,28,toggle)
    control.dropdownArrow=arrow;arrow:SetBackdropColor(.16,.17,.20,1)
    arrow:ClearAllPoints();arrow:SetPoint("TOPRIGHT",-1,-1);arrow:SetPoint("BOTTOMRIGHT",-1,1);arrow:SetWidth(28)
    self:StyleRailArrow(arrow,1)
    local label=control:GetFontString();label:ClearAllPoints()
    label:SetPoint("LEFT",8,0);label:SetPoint("RIGHT",-36,0);label:SetJustifyH("LEFT");label:SetMaxLines(1)
    local u=self.ui;u.settingsDropdownControls=u.settingsDropdownControls or {}
    u.settingsDropdownControls[#u.settingsDropdownControls+1]=control
end
function A:BuildSettingsUI(u,window,text,button,edit)
    local hub=window("SanguineLootCouncilSettings","Sanguine Loot Tools  |  Settings",1000,720)
    u.settingsHub=hub;u.settingsPages={};u.settingsTabs={};u.settingsScrolls={};u.settingsPositions={};u.settingsRows={};u.settingsSections={}
    u.settingsStatus=text(hub,"",11,22,-61,950);u.settingsStatus:SetHeight(28);u.settingsStatus:SetMaxLines(2)
    u.settingsHeading=text(hub,"Session",18,210,-105,700)
    u.settingsDescription=text(hub,"",12,210,-132,700)
    u.settingsAccess=text(hub,"",11,22,-680,950)
    local statusBand=hub:CreateTexture(nil,"BACKGROUND");statusBand:SetPoint("TOPLEFT",1,-43);statusBand:SetPoint("TOPRIGHT",-1,-43);statusBand:SetHeight(45);statusBand:SetColorTexture(0.075,0.08,0.095,1)
    for i,name in ipairs(pageOrder) do
        local page=CreateFrame("Frame",nil,hub);page:SetPoint("TOPLEFT",210,-164);page:SetSize(750,490)
        local scroll=A:CreateScrollFrame(page);scroll:SetPoint("TOPLEFT",0,0);scroll:SetSize(730,490)
        local content=CreateFrame("Frame",nil,scroll);content:SetSize(710,600);scroll:SetScrollChild(content)
        scroll:EnableMouseWheel(true);scroll:SetScript("OnMouseWheel",function(f,delta) f:SetVerticalScroll(math.max(0,math.min(f:GetVerticalScrollRange(),f:GetVerticalScroll()-delta*36))) end)
        page.content=content;u.settingsPages[name]=page;u.settingsScrolls[name]=scroll
        local tab=button(hub,name,22,-112-(i-1)*43,158,function() A:SelectSettingsPage(name) end)
        tab:GetFontString():SetJustifyH("LEFT");tab:SetHeight(34)
        tab.accent=tab:CreateTexture(nil,"ARTWORK");tab.accent:SetPoint("TOPLEFT",0,0);tab.accent:SetPoint("BOTTOMLEFT",0,0);tab.accent:SetWidth(4);tab.accent:SetColorTexture(0.78,0.08,0.15,1)
        u.settingsTabs[name]=tab
    end
    -- Decorative branding never captures input or participates in page scrolling.
    u.settingsLogo=hub:CreateTexture(nil,"ARTWORK")
    u.settingsLogo:SetTexture("Interface\\AddOns\\SanguineLootTools\\Assets\\SLTMonogram.tga", "CLAMP", "CLAMP", "LINEAR")
    if u.settingsLogo.SetSnapToPixelGrid then u.settingsLogo:SetSnapToPixelGrid(false) end
    if u.settingsLogo.SetTexelSnappingBias then u.settingsLogo:SetTexelSnappingBias(0) end
    u.settingsLogo:SetSize(158,158);u.settingsLogo:SetPoint("TOPLEFT",22,-400)
    u.settingsSidebarDivider=hub:CreateTexture(nil,"BACKGROUND")
    u.settingsSidebarDivider:SetPoint("TOPLEFT",195,-89);u.settingsSidebarDivider:SetPoint("BOTTOMLEFT",195,38)
    u.settingsSidebarDivider:SetWidth(1);u.settingsSidebarDivider:SetColorTexture(.14,.15,.17,1)
    local function position(object,parent,x,y,width,height)
        object:SetParent(parent)
        u.settingsPositions[#u.settingsPositions+1]={object=object,x=x,y=y,width=width,height=height}
    end
    local function label(parent,value,y)
        local t=text(parent,value,14,0,-y,690);position(t,parent,0,y,function(w) return w end,22);return t
    end
    local function divider(parent,y)
        local line=parent:CreateTexture(nil,"BACKGROUND")
        line:SetColorTexture(.22,.24,.28,.8)
        position(line,parent,0,y,function(w) return w end,1)
        return line
    end
    local function section(parent,value,y)
        local heading=label(parent,value,y)
        local line=y>0 and divider(parent,y-18) or nil
        u.settingsSections[#u.settingsSections+1]={parent=parent,heading=heading,line=line,y=y}
        return heading
    end
    local function description(parent,value,y)
        local t=text(parent,value,11,0,-y,690);t:SetJustifyV("TOP");position(t,parent,0,y,function(w) return w end,38);return t
    end
    local function row(parent,title,help,y,control,width)
        local titleText=text(parent,title,12,0,-y,450)
        local helpText=text(parent,help,11,0,-y-20,450);helpText:SetTextColor(0.58,0.61,0.66);helpText:SetHeight(30);helpText:SetMaxLines(2)
        position(titleText,parent,0,y,function(w) return w-220 end,18)
        position(helpText,parent,0,y+20,function(w) return w-220 end,32)
        position(control,parent,function(w) return w-(width or 180) end,y+3,width or 180,26)
    end
    u.settingsDropdownControls=u.settingsDropdownControls or {}
    local function dropdown(control,choices,action)
        A:BindSettingsDropdown(control,choices,action,button)
    end
    self:BuildLootConfigurationUI(u,window,text,button,edit,dropdown,position,section,row,switch)
    local session=u.settingsPages.Session.content
    section(session,"Raid session",0)
    description(session,"Review your saved raid setup below, then start a session. Resume restores its saved session instead.",30)
    u.raidSetupSummary=text(session,"",12,0,-70,690)
    position(u.raidSetupSummary,session,0,70,function(w) return w end,100);u.raidSetupSummary:SetJustifyV("TOP")
    for i,key in ipairs({"start","finish","resume"}) do local index=i;position(u[key],session,function(w) return (index-1)*(w+10)/3 end,187,function(w) return (w-20)/3 end,30) end
    section(session,"Response rounds",250)
    row(session,"Response timer","Seconds allowed for players to respond. Applies to new rounds.",287,u.responseSeconds,100)
    u.responseSeconds.hint:Hide();position(u.applyResponseTimer,session,function(w) return w-180 end,353,180,28);u.applyResponseTimer:SetText("Apply timer")
    section(session,"Before the raid",425)
    row(session,"Addon versions","Review group versions before distributing loot.",465,u.readiness,180)
    section(session,"Personal display",550)
    u.lockWindows=button(session,"",0,0,76,function() A:SetWindowPositionsLocked(not A:WindowPositionsLocked()) end);switch(u.lockWindows)
    row(session,"Lock window positions","Lock all windows. Each title-bar padlock can override this for one window.",590,u.lockWindows,76)
    u.resetWindows=button(session,"Reset window layout",0,0,180,function() A:ResetWindowLayout() end)
    row(session,"Reset window layout","Restore recommended sizes and opening positions for every window.",665,u.resetWindows,180)
    session:SetHeight(755)
    local alerts=u.settingsPages.Alerts.content
    section(alerts,"Trade-expiry warnings",0)
    description(alerts,"Warnings go to the raid leader, Master Looter and item holder.",30)
    u.warningTrade=button(alerts,"",0,0,76,function() local c=A:WarningSettings();c.trade=not c.trade;A:ApplyWarningSettings(c) end);switch(u.warningTrade)
    u.warningSound=button(alerts,"",0,0,76,function() local c=A:WarningSettings();c.sound=not c.sound;A:ApplyWarningSettings(c) end);switch(u.warningSound)
    row(alerts,"Enable trade warnings","Notify before a tracked item's trade time expires.",90,u.warningTrade,76)
    row(alerts,"Warning sound","Play a sound alongside trade warnings.",163,u.warningSound,76)
    u.warningEarly=edit(alerts,0,0,100,"");u.warningEarly.hint:Hide()
    u.warningUrgent=edit(alerts,0,0,100,"");u.warningUrgent.hint:Hide()
    section(alerts,"Warning timing",254)
    row(alerts,"Early warning","Minutes remaining. Default: 15.",292,u.warningEarly,100)
    row(alerts,"Urgent warning","Minutes remaining. Must be lower than the early warning. Default: 5.",365,u.warningUrgent,100)
    u.warningApply=button(alerts,"Apply thresholds",0,0,180,function() local c=A:WarningSettings();c.early=(tonumber(u.warningEarly:GetText()) or -1)*60;c.urgent=(tonumber(u.warningUrgent:GetText()) or -1)*60;A:ApplyWarningSettings(c);u.warningEarly:ClearFocus();u.warningUrgent:ClearFocus() end)
    position(u.warningApply,alerts,function(w) return w-180 end,446,180,28)
    description(alerts,"Each threshold alerts once per item copy. Unknown or stale timers do not count down.",498);alerts:SetHeight(560)
    local council=u.settingsPages.Council.content;u.councilSettingsContent=council;u.councilSettingsScroll=u.settingsScrolls.Council
    section(council,"Loot authority",0)
    u.masterStatus=text(council,"",11,0,-32,690);position(u.masterStatus,council,0,32,function(w) return w end,38);u.masterStatus:SetMaxLines(2)
    switch(u.autoMaster);row(council,"Follow in-game Master Looter","Keep the addon assignment aligned with the game's loot role.",90,u.autoMaster,76)
    section(council,"Manual assignment",175)
    position(u.masterName,council,0,218,function(w) return w-195 end,28);u.masterName.hint:Hide()
    position(u.setMaster,council,function(w) return w-180 end,218,180,28)
    description(council,"Enter Name-Realm. Manual assignment is unavailable while actively following the game's Master Looter.",255)
    description(council,"Automatic collection and distribution settings are in Loot Configuration.",315)
    section(council,"Council membership",405)
    position(u.councilName,council,0,453,function(w) return w-195 end,28);u.councilName.hint:Hide()
    position(u.toggleCouncil,council,function(w) return w-180 end,453,180,28)
    description(council,"Enter Name-Realm to add or remove a council member.",490)
    position(u.councilList,council,0,545,function(w) return w end,100)
    section(council,"Voting rules",680)
    switch(u.selfVotes);row(council,"Allow self-voting","Council members may vote for themselves.",723,u.selfVotes,76)
    dropdown(u.ruleLimit,{{"1 candidate",1},{"2 candidates",2},{"3 candidates",3}},function(v) A:UpdateVotingRule("limit",v) end)
    row(council,"Candidates per ballot","Maximum candidates each council member can select.",796,u.ruleLimit)
    dropdown(u.ruleVisibility,{{"Immediately","immediate"},{"After your vote","own"},{"After award","closed"}},function(v) A:UpdateVotingRule("visibility",v) end)
    row(council,"Reveal vote totals","Choose when council members can see the results.",869,u.ruleVisibility)
    dropdown(u.ruleNames,{{"Totals only",false},{"Show voter names",true}},function(v) A:UpdateVotingRule("names",v) end)
    row(council,"Voter identities","Controls whether revealed results include voter names.",942,u.ruleNames)
    description(council,"Raid Leader and Master Looter vote only when added to council. Active rounds lock membership and voting rules; shared tests retain their existing membership exception.",1020);council:SetHeight(1090)
    local responses=u.settingsPages.Responses.content
    u.responseSectionOpen={raid=true,personal=true}
    u.responseSections={}
    local function responseSection(key,title,access)
        local group={}
        group.header=button(responses,"",0,0,690,function()
            A:CloseSettingsDropdown()
            u.responseSectionOpen[key]=not u.responseSectionOpen[key]
            u.settingsLayoutKey=nil;A:LayoutSettings()
        end)
        group.title=text(group.header,title,14,12,-9,380)
        group.access=text(group.header,access,11,0,-11,200)
        group.access:SetJustifyH("RIGHT");group.access:SetTextColor(.66,.69,.74)
        group.arrow=button(group.header,"",0,0,28,function() group.header:Click() end)
        group.body=CreateFrame("Frame",nil,responses)
        u.responseSections[key]=group
        return group.body
    end
    local raid=responseSection("raid","Raid response choices","Raid Leader only")
    local personal=responseSection("personal","Your response colours","Personal • everyone")
    u.responseEditNotice=description(raid,"",0)
    u.responseColumnLabels={}
    for i,value in ipairs({"Order","Response","Visible","Remove"}) do u.responseColumnLabels[i]=text(raid,value,10,0,-48,90);u.responseColumnLabels[i]:SetTextColor(0.66,0.61,0.49) end
    u.responseEditor={}
    for i=1,9 do
        local r={};u.responseEditor[i]=r
        r.up=button(raid,"^",0,0,22,function() A:EditResponse(i,"move",-1) end)
        r.down=button(raid,"v",0,0,22,function() A:EditResponse(i,"move",1) end)
        self:StyleRailArrow(r.up,-1);self:StyleRailArrow(r.down,1)
        r.label=edit(raid,0,0,180,"");r.label:SetMaxLetters(18);r.label.hint:Hide()
        r.label:SetScript("OnTextChanged",function() if A.ui and A.ui.responsePreview then A:RenderSettingsPreview() end end)
        r.label:SetScript("OnEnterPressed",function() r.save:Click() end)
        r.save=button(raid,"Rename",0,0,60,function() local v=A:ResponseOptions()[i];if v then A:EditResponse(i,"update",{label=r.label:GetText(),color=v.color}) end;r.label:ClearFocus();A:RenderSettings() end)
        r.enabled=button(raid,"",0,0,76,function() local v=A:ResponseOptions()[i];if v then A:EditResponse(i,"enabled",not v.enabled) end end);switch(r.enabled)
        r.delete=button(raid,"×",0,0,28,function() local popup=A:ShowConfirmation("SANGUINELOOTCOUNCIL_DELETE_RESPONSE");if popup then popup.data={sid=A.state and A.state.id or false,id=A:ResponseOptions()[i].id,revision=A:RaidConfigurationRevision()} end end)
        self:StyleCrossButton(r.delete)
        r.color=button(personal,"",0,0,180,function() end)
        r.color.swatch=r.color:CreateTexture(nil,"ARTWORK");r.color.swatch:SetPoint("LEFT",8,0);r.color.swatch:SetSize(20,20)
        r.color:GetFontString():ClearAllPoints();r.color:GetFontString():SetPoint("LEFT",36,0);r.color:GetFontString():SetPoint("RIGHT",-5,0);r.color:GetFontString():SetJustifyH("LEFT")
        r.color:RegisterForClicks("LeftButtonUp","RightButtonUp")
        r.color:SetScript("OnClick",function(_,mouse) A:CloseSettingsDropdown();local v=A:ResponseOptions()[i];if not v then return end;if mouse=="RightButton" then A:SetPersonalResponseColor(v.id,nil) else A:PickResponseColor(v.id) end end)
    end
    u.addResponse=button(raid,"+ Add response",0,0,180,function() A:EditResponse(0,"add") end)
    u.resetResponses=button(raid,"Restore raid choices",0,0,180,function() local popup=A:ShowConfirmation("SANGUINELOOTCOUNCIL_RESET_RESPONSES");if popup then popup.data={sid=A.state and A.state.id or false,revision=A:RaidConfigurationRevision()} end end)
    u.personalColorsDivider=divider(responses,0)
    u.personalColorsHeading=u.responseSections.personal.title
    u.personalColorsHelp=description(personal,"Click a swatch to choose; right-click to reset. Colours save automatically for your character.",0)
    u.previewDivider=divider(u.settingsPages.Responses,0)
    u.previewHeading=label(responses,"Response preview",0)
    u.previewHelp=description(responses,"Shows your current colours and enabled choices. Typed names preview before Rename is applied.",0)
    u.responsePreview=CreateFrame("Frame",nil,responses,"BackdropTemplate");A:StylePanel(u.responsePreview)
    u.previewPrompt=text(u.responsePreview,"Choose one response below.",12,16,-14,600)
    u.previewButtons={}
    for i=1,9 do
        local p=CreateFrame("Frame",nil,u.responsePreview,"BackdropTemplate");A:StylePanel(p);p:SetBackdropColor(0.12,0.13,0.15,1)
        p.label=text(p,"",12,6,-8,170);p.label:SetJustifyH("CENTER");p.label:SetMaxLines(1);p:EnableMouse(false);u.previewButtons[i]=p
    end
    local profiles=u.settingsPages.Profiles.content
    section(profiles,"Saved raid profiles",0)
    description(profiles,"Profiles store shared raid configuration. Your personal response colours stay with your character.",30)
    u.profileSelector=button(profiles,"Select a profile",0,0,260,function() end)
    dropdown(u.profileSelector,function() local choices={};for n in pairs(SanguineLootCouncilDB.profiles or {}) do choices[#choices+1]={n,n} end;table.sort(choices,function(a,b) return a[1]<b[1] end);return choices end,function(n) u.profileName:SetText(n);u.profileSelector:SetText(n) end)
    position(u.profileSelector,profiles,0,95,function(w) return w end,30)
    position(u.profileName,profiles,0,180,function(w) return w end,30);u.profileName.hint:Hide();label(profiles,"Profile name",145)
    for i,key in ipairs({"saveProfile","loadProfile","deleteProfile"}) do local index=i;position(u[key],profiles,function(w) return (index-1)*(w+10)/3 end,240,function(w) return (w-20)/3 end,30) end
    position(u.profileList,profiles,0,305,function(w) return w end,110)
    description(profiles,"Apply a profile before starting, or update an unlocked session as Raid Leader. Personal colours and recorded loot stay separate.",450);profiles:SetHeight(530)
    local advanced=u.settingsPages.Advanced.content
    section(advanced,"Session recovery",0)
    description(advanced,"Use these controls to recover session data or manage a voting interruption.",30)
    u.settingsResync=button(advanced,"Resynchronise",0,-92,180,function() A:RequestSync() end)
    position(u.resetVoting,advanced,0,155,180,30);position(u.openVoting,advanced,195,155,180,30)
    description(advanced,"Voting recovery affects the selected item. Review its state in Voting first.",205)
    section(advanced,"Diagnostics",290)
    u.settingsDiagnostics=button(advanced,"Open diagnostics",0,-340,180,function() A:ShowDiagnostics() end)
    description(advanced,"View the local diagnostic report. Recording remains opt-in; nothing is uploaded automatically.",390);advanced:SetHeight(480)
    -- Keep operational item utilities with Loot; the launcher owns window navigation.
    u.itemTools=window("SanguineLootCouncilItemTools","Add loot",620,170,true)
    move(u.itemInput,u.itemTools,20,90,430);move(u.add,u.itemTools,465,90,130);u.itemInput.hint:Hide()
    text(u.itemTools,"Shift-click a single item in your bags, then Add loot and Queue.",12,20,-55,570)
    move(u.correctAward,u.main,250,580,140)
    u.archiveCompleted=button(u.history,"Archive completed loot",740,-510,220,function() A:ReviewArchive() end)
    u.archiveHelp=text(u.history,"Archives all confirmed deliveries from the active Loot list, across all players.",11,20,-512,690)
    local loot=u.lootPanels.timer
    loot.pageLabel:SetWidth(135)
    u.itemToolsButton=button(loot.window,"Add loot",255,-365,145,function() if A:IsMaster() then u.itemTools:Show() end end)
    u.itemTools:HookScript("OnShow",function()
        if not A:IsMaster() then u.itemTools:Hide();return end
        u.itemToolsReturnSession=A.state and A.state.id
        loot.window:Hide()
        if u.itemTools.sltCollapsed then A:ToggleWindowCollapse(u.itemTools) end
        u.itemTools:ClearAllPoints()
        u.itemTools:SetPoint("TOP",UIParent,"TOP",0,-70)
        A:FocusWindow(u.itemTools)
        A:InstallManualLootLinkHooks();u.itemInput:SetFocus()
    end)
    u.itemTools:HookScript("OnHide",function()
        u.itemInput:ClearFocus()
        local sid=u.itemToolsReturnSession;u.itemToolsReturnSession=nil
        if sid and A.state and sid==A.state.id and A:IsMaster() and A:CanViewLoot()
            and not u.checkWindow:IsShown() then A:ShowLootWindow() end
    end)
    for _,key in ipairs({"myResponses","deliveries","settings","votingRules","session","config","rules"}) do u[key]:Hide() end
    u.readiness:SetScript("OnClick",function() A:StartAddonCheck(true) end);u.readiness:SetText("Version Check")
    u.recheck:SetScript("OnClick",function() A:StartAddonCheck(true) end)
    u.tradeAlerts=window("SanguineLootCouncilTradeAlerts","Trade time warning",570,310)
    u.tradeAlertScroll=A:CreateScrollFrame(u.tradeAlerts);u.tradeAlertScroll:SetPoint("TOPLEFT",20,-55);u.tradeAlertScroll:SetSize(505,185)
    u.tradeAlertChild=CreateFrame("Frame",nil,u.tradeAlertScroll);u.tradeAlertChild:SetSize(480,185);u.tradeAlertScroll:SetScrollChild(u.tradeAlertChild)
    u.tradeAlertText=text(u.tradeAlertChild,"",12,0,0,475);u.tradeAlertText:SetJustifyV("TOP")
    button(u.tradeAlerts,"Open Loot",20,-260,230,function() A:ShowLootWindow("timer") end)
    button(u.tradeAlerts,"Close",320,-260,230,function() u.tradeAlerts:Hide() end)
    hub:HookScript("OnHide",function() A:CloseSettingsDropdown();u.lootReason:Hide();A.lootReasonContext=nil end)
    self:SelectSettingsPage("Session")
end

function A:CloseSettingsDropdown()
    local u=self.ui;if not u then return end
    if u.settingsDropdown then u.settingsDropdown:Hide();u.settingsDropdown.owner=false end
    if u.settingsDropdownDismiss then u.settingsDropdownDismiss:Hide() end
end
function A:RefreshSettingsDropdowns()
    local u=self.ui;if not u then return end
    for _,control in ipairs(u.settingsDropdownControls or {}) do
        control.dropdownArrow:SetEnabled(control:IsEnabled())
        self:RefreshRailArrow(control.dropdownArrow)
    end
    if u.settingsDropdown and u.settingsDropdown.owner and (u.settingsDropdown.owner:IsEnabled()==false or not u.settingsDropdown.owner:IsVisible()) then self:CloseSettingsDropdown() end
end
function A:OpenSettingsDropdown(owner,choices,action)
    local u=self.ui
    local menu=u.settingsDropdown
    if menu and menu:IsShown() and menu.owner==owner then self:CloseSettingsDropdown();return end
    if not owner:IsEnabled() or not owner:IsVisible() then self:CloseSettingsDropdown();return end
    self:CloseSettingsDropdown()
    if #choices==0 then self:Print("No saved profiles yet.");return end
    if not menu then
        local dismiss=CreateFrame("Frame",nil,UIParent)
        u.settingsDropdownDismiss=dismiss
        dismiss:SetAllPoints(UIParent);dismiss:SetFrameStrata("FULLSCREEN_DIALOG");dismiss:SetFrameLevel(10000)
        dismiss:EnableMouse(true);dismiss:SetScript("OnMouseUp",function() A:CloseSettingsDropdown() end)
        dismiss:EnableMouseWheel(true);dismiss:SetScript("OnMouseWheel",function() A:CloseSettingsDropdown() end)
        dismiss:Hide()
        -- Direct child buttons avoid ScrollFrame hit-testing/layer changes.
        -- Every interactive layer is explicitly above the outside-click catcher.
        menu=CreateFrame("Frame",nil,UIParent,"BackdropTemplate");menu.rows={}
        menu:SetFrameStrata("FULLSCREEN_DIALOG");menu:SetFrameLevel(10010)
        menu:HookScript("OnHide",function() dismiss:Hide();menu.owner=false;menu.action=nil;menu.choices=nil end)
        local function wheel(_,delta) A:ScrollSettingsDropdown(-delta) end
        menu:EnableMouseWheel(true);menu:SetScript("OnMouseWheel",wheel)
        menu.slider=CreateFrame("Slider",nil,menu,"BackdropTemplate")
        menu.slider:SetFrameStrata("FULLSCREEN_DIALOG");menu.slider:SetFrameLevel(10014)
        menu.slider:SetPoint("TOPRIGHT",-5,-22);menu.slider:SetPoint("BOTTOMRIGHT",-5,22);menu.slider:SetWidth(12)
        menu.slider:SetOrientation("VERTICAL");menu.slider:SetValueStep(1)
        if menu.slider.SetObeyStepOnDrag then menu.slider:SetObeyStepOnDrag(true) end
        menu.slider:EnableMouse(true);menu.slider:SetThumbTexture("Interface/Buttons/WHITE8X8")
        local thumb=menu.slider:GetThumbTexture();thumb:SetSize(10,24);thumb:SetVertexColor(.4,.42,.46,1)
        menu.slider:SetScript("OnValueChanged",function(_,value)
            if menu.updating or not menu.choices then return end
            menu.offset=math.max(0,math.min(#menu.choices-8,math.floor(value+0.5)))
            A:RenderSettingsDropdown()
        end)
        menu.slider:EnableMouseWheel(true);menu.slider:SetScript("OnMouseWheel",wheel)
        for _,key in ipairs({"up","down"}) do
            local b=CreateFrame("Button",nil,menu)
            menu[key]=b;b:SetSize(16,16);b:SetFrameStrata("FULLSCREEN_DIALOG");b:SetFrameLevel(10014)
            b:SetPoint(key=="up" and "TOPRIGHT" or "BOTTOMRIGHT",-3,key=="up" and -3 or 3)
            A:StyleRailArrow(b,key=="up" and -1 or 1,10)
            b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp")
            b:SetScript("OnClick",function() A:ScrollSettingsDropdown(key=="up" and -1 or 1) end)
            b:EnableMouseWheel(true);b:SetScript("OnMouseWheel",wheel)
        end
        for i=1,8 do
            local b=CreateFrame("Button",nil,menu)
            menu.rows[i]=b;b:SetFrameStrata("FULLSCREEN_DIALOG");b:SetFrameLevel(10012)
            b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp")
            b.label=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            b.label:SetAllPoints();b.label:SetMaxLines(1);b.label:SetJustifyH("LEFT");b:SetFontString(b.label)
            b:SetHighlightTexture("Interface/Buttons/WHITE8X8");b:GetHighlightTexture():SetVertexColor(.5,.15,.2,.35)
            b:SetScript("OnClick",function()
                A.settingsMenuClicks=(A.settingsMenuClicks or 0)+1
                local currentOwner,callback=menu.owner,menu.action
                local choice=menu.choices and menu.choices[(menu.offset or 0)+i]
                local allowed=currentOwner and currentOwner:IsEnabled() and currentOwner:IsVisible()
                A:CloseSettingsDropdown()
                if allowed and choice and callback then callback(choice[2]) end
            end)
            b:EnableMouseWheel(true);b:SetScript("OnMouseWheel",wheel)
        end
    end
    self:StylePanel(menu);menu:ClearAllPoints()
    menu:SetBackdropColor(.055,.06,.07,1)
    menu:SetFrameStrata("FULLSCREEN_DIALOG");menu:SetPoint("TOPRIGHT",owner,"BOTTOMRIGHT",0,-3);menu:SetSize(math.max(180,owner:GetWidth()),math.min(248,#choices*30+8));menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    u.settingsDropdown=menu;menu.owner,menu.choices,menu.action,menu.offset=owner,choices,action,0
    self:RenderSettingsDropdown()
    u.settingsDropdownDismiss:Show();menu:Show()
    self.settingsMenuOpens=(self.settingsMenuOpens or 0)+1
end

function A:ScrollSettingsDropdown(delta)
    local menu=self.ui and self.ui.settingsDropdown
    if not menu or not menu.choices then return end
    menu.offset=math.max(0,math.min(math.max(0,#menu.choices-8),(menu.offset or 0)+delta))
    self:RenderSettingsDropdown()
end

function A:RenderSettingsDropdown()
    local menu=self.ui and self.ui.settingsDropdown
    if not menu or not menu.choices then return end
    local maximum=math.max(0,#menu.choices-8)
    menu.offset=math.max(0,math.min(maximum,menu.offset or 0))
    menu.updating=true
    menu.slider:SetMinMaxValues(0,maximum);menu.slider:SetValue(menu.offset)
    menu.updating=false
    menu.slider:SetShown(maximum>0);menu.up:SetShown(maximum>0);menu.down:SetShown(maximum>0)
    menu.up:SetEnabled(menu.offset>0);menu.down:SetEnabled(menu.offset<maximum)
    for i,b in ipairs(menu.rows) do
        local choice=menu.choices[menu.offset+i]
        b:ClearAllPoints();b:SetPoint("TOPLEFT",7,-4-(i-1)*30);b:SetSize(menu:GetWidth()-(maximum>0 and 30 or 14),28)
        b:SetShown(choice~=nil)
        if choice then b.label:SetText(choice[1]) end
    end
end

function A:LayoutSettings()
    local u=self.ui;if not u or not u.settingsPositions then return end
    local w,h=u.settingsHub:GetWidth(),u.settingsHub:GetHeight();local body=w-260
    local options=self:ResponseOptions();local enabled=0
    for _,v in ipairs(options) do if v.enabled then enabled=enabled+1 end end
    local key=w..":"..h..":"..#options..":"..enabled..":"..tostring(u.responseSectionOpen.raid)..":"..tostring(u.responseSectionOpen.personal)
    if u.settingsLayoutKey==key then self:RenderSettingsPreview();self:LayoutLootConfiguration();return end
    u.settingsLayoutKey=key
    u.settingsHub.title:SetWidth(w-70);u.settingsStatus:SetWidth(w-44)
    -- Anchor the branding near the sidebar foot, with clear navigation/footer margins.
    local logoTop=112+(#pageOrder-1)*43+34+16
    local logoRoom=math.max(0,h-48-logoTop)
    local logoSize=math.min(158,logoRoom)
    u.settingsLogo:SetSize(logoSize,logoSize)
    u.settingsLogo:ClearAllPoints();u.settingsLogo:SetPoint("TOPLEFT",22+(158-logoSize)/2,-logoTop-math.max(0,logoRoom-logoSize-20))
    u.settingsLogo:SetShown(logoSize>=48)
    u.settingsHeading:SetWidth(body);u.settingsDescription:SetWidth(body)
    u.settingsAccess:ClearAllPoints();u.settingsAccess:SetPoint("TOPLEFT",22,-h+28);u.settingsAccess:SetWidth(w-44)
    for name,page in pairs(u.settingsPages) do
        page:SetSize(body+20,h-220);u.settingsScrolls[name]:SetSize(body+10,h-220);page.content:SetWidth(body)
    end
    for _,p in ipairs(u.settingsPositions) do
        local x=type(p.x)=="function" and p.x(body) or p.x
        local width=type(p.width)=="function" and p.width(body) or p.width
        p.object:ClearAllPoints();p.object:SetPoint("TOPLEFT",x,-p.y)
        if width then p.object:SetWidth(width) end;if p.height then p.object:SetHeight(p.height) end
    end
    self:LayoutLootConfiguration()
    local count=#options
    local xs={0,66,body-154,body-62}
    for i,t in ipairs(u.responseColumnLabels) do t:ClearAllPoints();t:SetPoint("TOPLEFT",xs[i],-48);t:SetWidth(i==4 and 62 or 90) end
    local function at(object,x,y,width,height) object:ClearAllPoints();object:SetPoint("TOPLEFT",x,-y);if width then object:SetWidth(width) end;if height then object:SetHeight(height) end end
    local swatchWidth=(body-20)/3
    for i,r in ipairs(u.responseEditor) do
        local y=74+(i-1)*44
        at(r.up,0,y,22,28);at(r.down,25,y,22,28);at(r.label,66,y,body-300,28)
        at(r.save,body-224,y,60,28);at(r.enabled,body-154,y,76,28);at(r.delete,body-44,y,28,28)
        at(r.color,((i-1)%3)*(swatchWidth+10),40+math.floor((i-1)/3)*42,swatchWidth,32)
    end
    at(u.addResponse,0,74+count*44+10,180,28);at(u.resetResponses,195,74+count*44+10,190,28)
    at(u.personalColorsHelp,0,0,body,32)
    local sectionY=0
    for _,key in ipairs({"raid","personal"}) do
        local group=u.responseSections[key];local open=u.responseSectionOpen[key]
        at(group.header,0,sectionY,body,36)
        group.title:SetWidth(body-280)
        group.access:ClearAllPoints();group.access:SetPoint("RIGHT",-46,0);group.access:SetWidth(200)
        group.arrow:ClearAllPoints();group.arrow:SetPoint("TOPRIGHT",-1,-1);group.arrow:SetSize(34,34)
        if type(group.arrow.sltArrowParts)~="table" then self:StyleRailArrow(group.arrow,1) end
        self:SetRailArrowDirection(group.arrow,open and -1 or 1)
        local contentHeight=key=="raid" and (74+count*44+48) or (40+math.ceil(count/3)*42)
        at(group.body,0,sectionY+46,body,contentHeight);group.body:SetShown(open)
        sectionY=sectionY+46+(open and contentHeight+16 or 0)
        if key=="raid" then at(u.personalColorsDivider,0,sectionY-6,body,1) end
    end
        u.responsePreview:SetParent(u.settingsPages.Responses);u.previewHeading:SetParent(u.settingsPages.Responses)
    u.previewHelp:Hide()
    u.responsePreview:SetWidth(body);self:RenderSettingsPreview()
    local viewport=h-220;local previewHeight=u.responsePreview:GetHeight()
    local dockTop=viewport-previewHeight-30
    at(u.previewDivider,0,dockTop-18,body,1)
    at(u.previewHeading,0,dockTop,body,22)
    at(u.responsePreview,0,dockTop+30,body)
    u.settingsScrolls.Responses:SetHeight(math.max(40,dockTop-30))
    u.settingsPages.Responses.content:SetHeight(sectionY)
    for name,scroll in pairs(u.settingsScrolls) do
        local current=scroll:GetVerticalScroll()
        if type(current)=="number" then scroll:SetVerticalScroll(math.min(current,math.max(0,u.settingsPages[name].content:GetHeight()-scroll:GetHeight()))) end
    end
end

function A:RenderSettingsPreview()
    local u=self.ui;if not u or not u.responsePreview then return end
    local shown={}
    for i,v in ipairs(self:ResponseOptions()) do if v.enabled then shown[#shown+1]={option=v,index=i} end end
    local width=u.responsePreview:GetWidth();local cell=(width-52)/3
    u.previewPrompt:SetWidth(width-32)
    for i,p in ipairs(u.previewButtons) do
        local entry=shown[i];p:SetShown(entry~=nil)
        if entry then
            local v,index=entry.option,entry.index
            local field=u.responseEditor[index].label
            local label=field:HasFocus()==true and field:GetText() or v.label
            p:ClearAllPoints();p:SetPoint("TOPLEFT",16+((i-1)%3)*(cell+10),-43-math.floor((i-1)/3)*42);p:SetSize(cell,32)
            p.label:SetWidth(cell-12);p.label:SetText(label)
            p.label:SetTextColor(self:ResponseRGB(v.id));p.choice=v.id;p.previewLabel=label
        end
    end
    u.responsePreview:SetHeight(60+math.ceil(#shown/3)*42)
end

function A:RenderRaidSetupSummary()
    local u=self.ui;if not u or not u.raidSetupSummary then return end
    local c=self:RaidSettings();local names={}
    for name in pairs(c.council) do names[#names+1]=name end
    table.sort(names)
    local thresholds={[2]="Green+",[3]="Blue+",[4]="Epic+",[5]="Legendary only"}
    local profile=self.state and "Session configuration" or SanguineLootCouncilDB.raidSetup.profile or "Custom setup"
    local members={}
    for i=1,math.min(2,#names) do members[#members+1]=self:DisplayName(names[i]) end
    local memberSummary=#names>0 and (table.concat(members,", ")..(#names>2 and (" +"..(#names-2).." more • Council tab") or "")) or "No council members configured."
    u.raidSetupSummary:SetMaxLines(6)
    u.raidSetupSummary:SetText((self.state and "Active session" or "Next session").." | Profile: "..profile..
        "\nResponse timer: "..c.responseDuration.."s | Council: "..#names..
        " | Collection: "..thresholds[c.lootConfiguration.minimum]..
        "\nMaster Looter: "..(c.masterAutoSync and "Follow in-game role" or c.master or "You")..
        " | Automatic assignment: "..(c.lootConfiguration.automatic and "On" or "Off")..
        "\n"..memberSummary)
end

function A:RenderSettingsPresentation()
    local u,s=self.ui,self.state
    local role=self:IsLeader() and "Raid Leader" or self:IsMaster() and "Master Looter" or self:IsCouncil() and "Council" or "Raider"
    u.settingsStatus:SetText(not s and "Raid setup — saved settings for your next session" or
        ((self.demo and self:TestLabel() or "Active session").."   |   Your role: "..role.."   |   Master Looter: "..self:DisplayName(s.master)))
    u.settingsAccess:SetText(not s and "Edit your saved raid setup here, even while solo. It is used only when you start a session as Raid Leader." or self:IsLeader() and "Raid settings are controlled by you. Display preferences and colours affect only your character." or "Raid settings: view only — Raid Leader controls. Your display preferences and response colours remain editable.")
    u.responseEditNotice:SetText(not s and "Saved raid setup • edit choices for your next session as Raid Leader. Personal colours remain separate." or self:ResponseConfigEditable() and "Raid Leader controls • names, order and visibility apply to future response rounds." or self:IsLeader() and "Raid Leader only • choices are locked during active rounds. Finish or reset them before editing." or "View only • the Raid Leader controls names, order and visibility.")
    switchValue(u.autoMaster,not self.demo and (s and s.masterAutoSync or (not s and SanguineLootCouncilDB.masterAutoSync~=false)))
    switchValue(u.lootPanels.timer.auto,s and s.autoCollect~=false or not s)
    switchValue(u.selfVotes,self:RaidSettings().selfVotes)
    local cfg=self:WarningSettings();switchValue(u.warningTrade,cfg.trade);switchValue(u.warningSound,cfg.sound);switchValue(u.lockWindows,self:WindowPositionsLocked());u.lockWindows:SetEnabled(true);u.resetWindows:SetEnabled(true)
    local rules=self:RaidSettings().rules
    u.ruleLimit:SetText(rules.limit..(rules.limit==1 and " candidate" or " candidates"))
    local labels={immediate="Immediately",own="After your vote",closed="After award"}
    u.ruleVisibility:SetText(labels[rules.visibility] or "After award")
    u.ruleNames:SetText(rules.names and "Show voter names" or "Totals only")
    for i,r in ipairs(u.responseEditor) do
        local v=self:ResponseOptions()[i]
        if v then switchValue(r.enabled,v.enabled);r.color:SetText(v.label) end
    end
    u.itemToolsButton:SetShown(self:IsMaster());if not self:IsMaster() then u.itemTools:Hide() end
    self:RenderRaidSetupSummary()
    self:LayoutSettings()
end

function A:SelectSettingsPage(name)
    if not self.ui or not self.ui.settingsPages then return end
    if name=="Raid Profiles" then name="Profiles" end
    if name=="Master Loot" then name="Council" elseif name=="General" then name="Session" elseif name=="Tools" then name="Advanced" end
    if not self.ui.settingsPages[name] then name="Session" end
    self:CloseSettingsDropdown()
    for key,page in pairs(self.ui.settingsPages) do
        page:SetShown(key==name);local tab=self.ui.settingsTabs[key]
        tab:SetText(key=="Profiles" and "Raid Profiles" or key);tab.accent:SetShown(key==name);tab:SetBackdropColor(0.075,0.08,0.095,1)
    end
    self.ui.settingsHeading:SetText(name=="Profiles" and "Raid Profiles" or name);self.ui.settingsDescription:SetText(pageDescriptions[name])
    self.settingsPage=name
end
function A:ShowSettings()
    self:BuildUI();self:Render();self.ui.settingsHub:Show()
end
function A:RenderSettings()
    if not self.ui or not self.ui.settingsHub then return end
    local u,cfg=self.ui,self:WarningSettings()
    self:RenderMasterSettings()
    u.archiveCompleted:SetShown(self:IsMaster())
    u.archiveCompleted:SetEnabled(self:IsMaster() and #self:ArchivableItems()>0)
    u.manageLoot:SetShown(self:IsMaster())
    u.manageLoot:SetEnabled(self:IsMaster() and self.state and self:TrackedByID(self.selectedTracked or 0)~=nil)
    if not self:IsMaster() then u.lootPanels.timer.manage:Hide() end
    local options,editable=self:ResponseOptions(),self:ResponseConfigEditable()
    for i,row in ipairs(u.responseEditor or {}) do
        local option=options[i]
        for _,control in pairs(row) do control:SetShown(option~=nil);control:SetEnabled(editable and option and option.id~=6) end
        if option then
            if row.label:HasFocus()~=true then row.label:SetText(option.label) end
            row.color:SetEnabled(true)
            local red,green,blue=self:ResponseRGB(option.id)
            row.color.swatch:SetColorTexture(red,green,blue,1)
            switchValue(row.enabled,option.enabled)
            self:RefreshCrossButton(row.delete)
            row.up:SetEnabled(editable and option.id~=6 and i>1)
            row.down:SetEnabled(editable and option.id~=6 and i<#options-1)
        end
    end
    if u.addResponse then u.addResponse:SetEnabled(editable and #options<9);u.resetResponses:SetEnabled(editable) end

    u.lootPanels.timer.auto:SetEnabled(self:CanConfigureRaid())
    if not self.state then switchValue(u.lootPanels.timer.auto,self:LootConfiguration().collection) end
    switchValue(u.warningTrade,cfg.trade)
    switchValue(u.warningSound,cfg.sound)
    if u.warningEarly:HasFocus()~=true then u.warningEarly:SetText(tostring(cfg.early/60)) end
    if u.warningUrgent:HasFocus()~=true then u.warningUrgent:SetText(tostring(cfg.urgent/60)) end
    for _,control in ipairs({u.warningTrade,u.warningSound,u.warningEarly,u.warningUrgent,u.warningApply}) do control:SetEnabled(self:CanConfigureRaid()) end
    self:RenderSettingsPresentation()
    self:RenderLootConfigurationUI()
    self:RefreshSettingsDropdowns()
end
function A:RenderAddonCheck()
    if not self.ui then return end
    local u=self.ui
    if not self:IsLootController() then u.checkWindow:Hide();return end
    local names,detected,ready={},0,0
    for name in pairs(self.roster) do names[#names+1]=name end
    local fresh=self:AddonCheckFresh()
    local matching={}
    for _,name in ipairs(names) do matching[name]=fresh and self:AddonMemberStatus(name)=="Ready" or false end
    table.sort(names,function(a,b)
        if matching[a]~=matching[b] then return not matching[a] end
        return a<b
    end)
    u.checkExpected:SetText("v"..self.version)
    for i,row in ipairs(u.checkRows) do
        local name=names[i]
        row:SetShown(name~=nil);row.member=name
        if name then
            local entry=self.addonCheck and self.addonCheck.members[name]
            local known=entry and entry.version~=nil
            local status,detail=self:AddonMemberStatus(name)
            local correct=fresh and status=="Ready"
            if known then detected=detected+1 end
            if correct then ready=ready+1 end
            row.player:SetText(name)
            row.addon:SetText(known and "Installed" or (status=="Waiting" and "Checking…" or "Not detected"))
            row.version:SetText(known and ("v"..entry.version) or "—")
            local red,green=correct and 0.3 or 1,correct and 0.85 or 0.3
            row.addon:SetTextColor(red,green,correct and 0.45 or 0.3)
            row.version:SetTextColor(red,green,correct and 0.45 or 0.3)
            row.detail=detail..(known and ("\nProtocol: "..entry.wire) or "")
        end
    end
    u.checkChild:SetHeight(math.max(400,#names*24))
    local offset=u.checkScroll:GetVerticalScroll()
    if type(offset)=="number" then u.checkScroll:SetVerticalScroll(math.max(0,math.min(offset,math.max(0,#names*24-math.max(1,u.checkWindow:GetHeight()-197))))) end
    local state=not self.addonCheck and "Run a check" or (not fresh and "Refresh needed" or (ready.." matching"))
    u.checkSummary:SetText(detected.." of "..#names.." detected | "..state.." | Your version: v"..self.version)
    local stamp=self:IsLeader() and self.lastAddonProbe or self.lastAddonCheckRequest
    u.recheck:SetEnabled(not self.demo and A.Client:Uptime()-(stamp or -10)>=5)
end

function A:RenderTradeAlerts(show)
    if not self.ui then self:BuildUI() end
    if not self.ui.tradeAlerts then return end
    local lines={}
    for key,notice in pairs(self.tradeNotices or {}) do
        local entry=self.state and notice.sid==self.state.id and self:TrackedByGUID(notice.guid)
        if not entry or not self:CanReceiveTradeWarning(entry) or entry.holder~=notice.holder or A.Client:Uptime()>notice.expires or not self:WarningSettings().trade then
            self.tradeNotices[key]=nil
        else
            local remaining,status=self:TradeRemaining(entry)
            local item=entry.item and self:ItemByID(entry.item)
            local label=type(remaining)=="number" and remaining>0 and ("~"..math.ceil(remaining/60).." min remaining") or "Timer unavailable — awaiting holder"
            lines[#lines+1]={remaining=remaining or math.huge,text=(notice.level=="urgent" and "URGENT: " or "Trade reminder: ")..entry.link.."\n"..label.." | Holder: "..entry.holder.." | Winner: "..(item and item.winner or "Awaiting award")}
        end
    end
    table.sort(lines,function(a,b) return a.remaining<b.remaining end)
    local text={}
    for i=1,math.min(4,#lines) do text[#text+1]=lines[i].text end
    if #lines>4 then text[#text+1]="And "..(#lines-4).." more; open Loot / Trade." end
    self.ui.tradeAlertText:SetText(table.concat(text,"\n\n"))
    self.ui.tradeAlertChild:SetHeight(math.max(185,self.ui.tradeAlertText:GetStringHeight()+20))
    if show then self.ui.tradeAlertScroll:SetVerticalScroll(0) end
    if #lines==0 then self.ui.tradeAlerts:Hide() elseif show then self.ui.tradeAlerts:Show() end
end

A.confirmationDialogs["SANGUINELOOTCOUNCIL_DELETE_RESPONSE"]={text="Delete this response from future items? Existing rounds and history keep their recorded responses.",button1="Delete",button2="Cancel",timeout=0,whileDead=true,hideOnEscape=true,
    OnAccept=function(dialog)
        local c=dialog.data
        if not c or c.sid~=(A.state and A.state.id or false) or c.revision~=A:RaidConfigurationRevision() then return end
        for i,v in ipairs(A:ResponseOptions()) do if v.id==c.id then A:EditResponse(i,"delete");return end end
    end}
A.confirmationDialogs["SANGUINELOOTCOUNCIL_RESET_RESPONSES"]={text="Restore BIS, Upgrade, Minor Upgrade, Off-Spec, PvP and Pass for future items?",button1="Restore",button2="Cancel",timeout=0,whileDead=true,hideOnEscape=true,
    OnAccept=function(dialog) local c=dialog.data;if c and c.sid==(A.state and A.state.id or false) and c.revision==A:RaidConfigurationRevision() then A:EditResponse(0,"reset") end end}

function A:BuildPersonalColorUI(u,window,text,button,edit)
    u.personalColor=window("SanguineLootCouncilPersonalColor","Response colour",500,340,true)
    local f=u.personalColor;f:SetFrameStrata("FULLSCREEN_DIALOG")
    text(f,"Personal colours save automatically. Cancel restores your previous colour.",11,20,-47,460)
    u.personalColorChannels={}
    -- Use the game's colour-wheel interaction inside our own dark dialog.
    local wheel=CreateFrame("ColorSelect",nil,f)
    wheel:SetPoint("TOPLEFT",20,-76);wheel:SetSize(260,200)
    wheel:EnableMouse(true)
    local hues=wheel:CreateTexture(nil,"ARTWORK")
    hues:SetPoint("TOPLEFT",0,0);hues:SetSize(200,200)
    wheel:SetColorWheelTexture(hues)
    -- Cover the native wheel's stair-stepped perimeter with a smooth charcoal
    -- rim. This is a non-interactive texture; native wheel/value input stays intact.
    local rim=wheel:CreateTexture(nil,"OVERLAY",nil,-1)
    rim:SetTexture("Interface/AddOns/SanguineLootTools/Assets/ColourWheelRim.tga")
    rim:SetPoint("TOPLEFT",-2,2);rim:SetSize(204,204)
    u.personalColorRim=rim
    local marker=wheel:CreateTexture(nil,"OVERLAY")
    marker:SetTexture("Interface/Buttons/UI-ColorPicker-Buttons")
    marker:SetSize(10,10);marker:SetTexCoord(0,0.15625,0,0.625)
    wheel:SetColorWheelThumbTexture(marker)
    local brightness=wheel:CreateTexture(nil,"ARTWORK")
    brightness:SetPoint("TOPLEFT",224,0);brightness:SetSize(24,200)
    wheel:SetColorValueTexture(brightness)
    local thumb=wheel:CreateTexture(nil,"OVERLAY")
    thumb:SetTexture("Interface/Buttons/UI-ColorPicker-Buttons")
    thumb:SetSize(40,14);thumb:SetTexCoord(0.25,1,0,0.875)
    wheel:SetColorValueThumbTexture(thumb)
    wheel:SetScript("OnColorSelect",function(_,red,green,blue)
        local d=A.personalColorDraft
        if not d or d.updating then return end
        d.fromWheel=true
        A:ApplyPersonalPickerRGB(red*255,green*255,blue*255)
        d.fromWheel=nil
    end)
    u.personalColorWheel=wheel
    local preview=CreateFrame("Frame",nil,f,"BackdropTemplate");A:StylePanel(preview)
    preview:SetPoint("TOPLEFT",330,-85);preview:SetSize(130,85)
    u.personalColorPreview=preview:CreateTexture(nil,"ARTWORK")
    u.personalColorPreview:SetPoint("TOPLEFT",5,-5);u.personalColorPreview:SetPoint("BOTTOMRIGHT",-5,5)
    u.personalColorHex=edit(f,330,-214,130,"Hex colour")
    u.personalColorHex:SetMaxLetters(7)
    u.personalColorHex:SetScript("OnTextChanged",function(field) if field:HasFocus()==true then A:ApplyPersonalPickerHex(field:GetText()) end end)
    u.personalColorHex:SetScript("OnEnterPressed",function(field) A:ApplyPersonalPickerHex(field:GetText());field:ClearFocus() end)
    text(f,"Choose a colour on the wheel, then adjust its brightness.",11,330,-254,140)
    u.personalColorKeep=button(f,"Okay",20,-292,220,function()
        if u.personalColorHex:HasFocus()==true and not A:ApplyPersonalPickerHex(u.personalColorHex:GetText()) then return end
        A:FinishPersonalColor(true)
    end)
    u.personalColorCancel=button(f,"Cancel",260,-292,220,function() A:FinishPersonalColor(false) end)
    f.closeButton:SetScript("OnClick",function() A:FinishPersonalColor(false) end)
    f:SetScript("OnHide",function() if A.personalColorDraft then A:FinishPersonalColor(false) end end)
    u.settingsHub:HookScript("OnHide",function() A:FinishPersonalColor(false) end)
end
function A:RenderMasterSettings()
    if not self.ui or not self.ui.masterStatus then return end
    local s=self.state
    local following=s and s.masterAutoSync or (not s and SanguineLootCouncilDB.masterAutoSync~=false)
    self.ui.autoMaster:SetEnabled(self:CanConfigureRaid() and not self.demo)
    switchValue(self.ui.autoMaster,following and not self.demo)
    local name,status=self:ReadGameMaster()
    local message
    if not s then
        message=following and "Raid setup: follow the in-game Master Looter when the session starts." or ("Raid setup: manual Master Looter "..(self:RaidSettings().master or "you")..". Absent players are checked at start.")
    elseif self.demo then message="Test master looter: "..s.master.." — in-game role syncing is disabled in tests."
    elseif s.masterBlocked then message="Waiting for a readable in-game master looter; loot actions are paused."
    elseif s.masterAutoSync and s.masterSource=="game" then message="Current master looter: "..s.master.." (following in-game role)"
    elseif s.masterAutoSync then
        message="Addon master: "..s.master..(status=="none" and " — no in-game master-loot method is selected." or " — in-game role unavailable; using addon assignment.")
    else message="Current master looter: "..s.master.." (manual addon assignment)" end
    self.ui.masterStatus:SetText(message)
end
