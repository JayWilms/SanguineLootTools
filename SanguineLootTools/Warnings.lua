local _, A = ...
local function integer(n,lo,hi)
    return type(n)=="number" and not (issecretvalue and issecretvalue(n)) and n==n and n%1==0 and n>=lo and n<=hi
end
function A:DefaultWarningSettings()
    return {trade=true,sound=false,early=900,urgent=300,release=false}
end
function A:CleanWarningSettings(value)
    if type(value)~="table" or type(value.trade)~="boolean" or type(value.sound)~="boolean" or type(value.release)~="boolean"
        or not integer(value.early,120,7200) or not integer(value.urgent,60,7140) or value.urgent>=value.early
        or value.early%60~=0 or value.urgent%60~=0 then return end
    return {trade=value.trade,sound=value.sound,early=value.early,urgent=value.urgent,release=false}
end
function A:WarningSettings()
    if self.state then return self:CleanWarningSettings(self.state.warningSettings) or self:DefaultWarningSettings() end
    return self:CleanWarningSettings(SanguineLootCouncilDB and SanguineLootCouncilDB.warningSettings) or self:DefaultWarningSettings()
end
function A:ApplyWarningSettings(value)
    if not self:CanConfigureRaid() then self:Print("Only the raid leader changes raid warning settings.");return false end
    local clean=self:CleanWarningSettings(value)
    if not clean then self:Print("Use whole-minute warnings: early 2–120 minutes, urgent at least 1 minute and below early.");return false end
    if self.state then self:Act("warningSettings",{settings=clean})
    else return self:Act("warningSettings",{settings=clean}) end
    return true
end
function A:AnnouncementSettings()
    local source=self.state and self.state.announcementSettings
        or (not self.state and SanguineLootCouncilDB and SanguineLootCouncilDB.announcementSettings)
    local saved=type(source)=="table" and source or {}
    return {tracked=saved.tracked==true,responses=saved.responses~=false,awards=saved.awards~=false}
end

function A:EditAnnouncementSetting(p)
    local settings=self:AnnouncementSettings()
    if type(p.key)~="string" or settings[p.key]==nil or type(p.enabled)~="boolean" then return end
    settings[p.key]=p.enabled
    return settings
end

local announcementEvent={lootReport="tracked",bagLoot="tracked",open="responses",queueLoot="responses",
    award="awards",correctAward="awards"}
function A:LiveAnnouncementSettings(op)
    local key=announcementEvent[op]
    if key and self.state and not self.demo and not self.state.groupTest and not self.recoveryPending
        and self:IsLeader() and self.Client:InRaid() then
        local settings=self:AnnouncementSettings()
        if settings[key] then return settings end
    end
end

local function announcementLabel(self,link,limit)
    link=self:EquipmentLink(link)
    local name=link and link:match("|h%[(.-)%]|h")
    if name and not name:find("[|%c]") then
        if #link<=limit then return link end
        if #name+2<=limit then return "["..name.."]" end
    end
    local itemID=link and link:match("item:(%d+)")
    return itemID and #itemID+6<=limit and ("Item #"..itemID) or "Item"
end

local function announceItems(self,prefix,links,suffix)
    if #links==0 then return end
    local message=prefix
    for i,link in ipairs(links) do
        local separator=i>1 and ", " or ""
        local rest=i<#links and (" and "..(#links-i).." more") or ""
        local limit=255-#message-#separator-#rest-#suffix
        if limit<4 then break end
        message=message..separator..announcementLabel(self,link,limit)
        -- Reserve space for the number of links left before trying the next.
        if i==#links or #message+#rest+#suffix+6>255 then
            message=message..rest
            break
        end
    end
    self.Client:Call("C_ChatInfo.SendChatMessage",message..suffix,"RAID")
end

function A:AnnounceLootAction(p,settings,trackedBefore)
    local op=p.op
    if settings.tracked and (op=="lootReport" or op=="bagLoot") then
        local links={}
        for i=trackedBefore+1,#self.state.trackedLoot do
            local entry=self.state.trackedLoot[i]
            if not entry.routePolicy and self:CanQueueTrackedLoot(entry) then links[#links+1]=entry.link end
        end
        announceItems(self,"[Sanguine] Tracked for council: ",links,".")
    elseif settings.responses and (op=="open" or (op=="queueLoot" and p.release==true and not p.attach)) then
        local links,duration={}
        local function add(item)
            if item and item.status=="open" then
                links[#links+1]=item.link
                duration=item.responseDuration
            end
        end
        if op=="open" then add(self:ItemByID(p.item))
        else
            for _,row in ipairs(p.entries or {p}) do
                local entry=self:TrackedByID(row.tracked)
                if entry then add(self:ItemByID(entry.item)) end
            end
        end
        local suffix=duration and duration>0 and (" — "..duration.." seconds to respond.") or " — no time limit."
        announceItems(self,"[Sanguine] Responses open for ",links,suffix)
    elseif settings.awards and (op=="award" or op=="correctAward") then
        local item=self:ItemByID(p.item)
        if not item or item.automaticAssignment then return end
        local winner=item.winner:gsub("[%c|]","")
        local prefix=op=="correctAward" and "[Sanguine] Award corrected: " or "[Sanguine] "
        local suffix=(op=="correctAward" and " now awarded to " or " awarded to ")..winner.."."
        announceItems(self,prefix,{item.link},suffix)
    end
end

function A:IsLootController()
    return self:IsLeader() or self:IsMaster()
end
function A:ProbeScope() return self.state and self.state.id or false end
function A:MemberOffline(name)
    local unit=self.roster[name]
    if type(unit)~="string" or type(UnitIsConnected)~="function" then return false end
    local ok,connected=pcall(UnitIsConnected,unit)
    return ok and not (issecretvalue and issecretvalue(connected)) and connected==false
end
function A:AddonCheckFresh()
    local r=self.addonCheck
    if not r or r.scope~=self:ProbeScope() or r.roster~=self:RosterKey() then return false end
    local age=A.Client:ServerTime()-r.at
    return age>=0 and age<=60
end
function A:AddonMemberStatus(name)
    if self:MemberOffline(name) then return "Offline","Player is disconnected." end
    local r=self.addonCheck
    local entry=r and r.members[name]
    if not self:AddonCheckFresh() then return "No reply","No current compatible-session check. Recheck the raid." end
    if entry and entry.version then
        if entry.version~=self.version or entry.wire~=self.protocol then return "Version mismatch",entry.version.." / protocol "..entry.wire end
        if entry.session~=r.scope then return "Session mismatch","Addon replied, but session synchronization is not confirmed." end
        return "Ready",entry.version.."; current session confirmed."
    end
    if A.Client:ServerTime()-r.at<3 then return "Waiting","Waiting for an addon reply…" end
    return "No reply","Unconfirmed: absent, delayed or unsupported addon; not proof it is missing."
end
function A:CheckedRecoveryBackup(name)
    local s, check = self.state, self.addonCheck
    local entry = check and check.members[name]
    return s and entry and name~=s.leader and self:IsRecoveryBackup(s,name) and self:RecoveryOnline(name)==true
        and self:AddonMemberStatus(name)=="Ready" and entry.recoveryRev==self.rev
end

function A:LootCheckRoles()
    local s, settings = self.state, self:RaidSettings()
    local gameMaster, gameStatus = self:ReadGameMaster()
    local addonMaster = s and s.master or gameMaster or (self.roster[settings.master] and settings.master) or self.gameLeader
    if (s and s.masterBlocked) or (not s and (gameStatus=="pending" or gameStatus=="restricted")) then addonMaster=nil end
    local masterText = gameMaster or (gameStatus=="none" and "None" or "Unconfirmed")
    if gameMaster and self:MemberOffline(gameMaster) then masterText=masterText.." (offline)" end
    if addonMaster and addonMaster~=gameMaster then
        masterText=masterText.."  |  Addon Master Looter: "..addonMaster..(self:MemberOffline(addonMaster) and " (offline)" or "")
    end
    local council, present, total = self.Copy(settings.council), 0, 0
    if addonMaster then council[addonMaster]=true end
    for name in pairs(council) do
        total=total+1
        if self:RecoveryOnline(name)==true then present=present+1 end
    end
    local assistant=settings.recoveryAssistant
    local assistantText=assistant or "None selected"
    if assistant then
        local online=self:RecoveryOnline(assistant)
        local status=not self.roster[assistant] and "absent" or not self:IsRaidAssistant(assistant) and "rank unconfirmed"
            or online==true and "online, promoted" or online==false and "offline" or "connection unconfirmed"
        assistantText=assistantText.." ("..status..")"
    end
    return masterText,council,present,total,assistant,assistantText
end

function A:LootCheckRecoveryStatus()
    local s=self.state
    if not s then return "Available after session start" end
    if self.recoveryPending then return "Recovery in progress" end
    local names={}
    for _,name in pairs({s.recoveryBackup,s.recoveryAssistant}) do
        if self:CheckedRecoveryBackup(name) and names[1]~=name then names[#names+1]=name end
    end
    table.sort(names)
    if #names>0 then return "Verified on "..table.concat(names,", ") end
    if not s.recoveryBackup and not s.recoveryAssistant then return "No backup assigned" end
    return "Unconfirmed for the current session revision"
end

function A:AddonIssues()
    local issues={}
    for name in pairs(self.roster) do
        local status,detail=self:AddonMemberStatus(name)
        if status~="Ready" then issues[#issues+1]={name=name,status=status,detail=detail} end
    end
    table.sort(issues,function(a,b) return a.name<b.name end)
    return issues
end
function A:BeginAddonCheck()
    if not self:IsLeader() or self.demo then return false end
    if self.addonCheck and self.addonCheck.scope==self:ProbeScope() and A.Client:Uptime()-(self.lastAddonProbe or -10)<5 then return false end
    self.lastAddonProbe=A.Client:Uptime()
    local r={id=tostring(A.Client:ServerTime())..":"..tostring(math.random(100000,999999)),scope=self:ProbeScope(),at=A.Client:ServerTime(),roster=self:RosterKey(),members={}}
    for name in pairs(self.roster) do r.members[name]={} end
    if r.members[self.me] then r.members[self.me]={version=self.version,wire=self.protocol,session=self:ProbeScope()} end
    self.addonCheck=r;self.addonSummaryDirty=true
    if self.SendRecoveryBallots then self:SendRecoveryBallots() end
    self:Send({kind="presenceProbe",check=r.id,scope=r.scope})
    self:SendAddonSummary()
    return true
end
function A:SendAddonSummary()
    if not self:IsLeader() or not self.addonCheck then return end
    self.addonSummarySerial=(self.addonSummarySerial or 0)+1
    self.addonCheck.seq=self.addonSummarySerial
    local master=self.state and self.state.master
    if master and master~=self.me and self.roster[master] and not self.state.masterBlocked then
        self:Send({kind="presenceSummary",data=self.Copy(self.addonCheck)},master)
    end
    self.addonSummaryDirty=false;self.lastAddonSummary=A.Client:Uptime()
end
function A:StartAddonCheck(show)
    if self.demo or not self:IsLootController() then self:Print("Raid leader and master looter can run addon checks.");return false end
    if self:IsLeader() then self:BeginAddonCheck()
    elseif A.Client:Uptime()-(self.lastAddonCheckRequest or -10)>=5 then
        self.lastAddonCheckRequest=A.Client:Uptime()
        self:Send({kind="presenceCheckRequest",scope=self:ProbeScope()},self.leader)
    end
    if show then self:BuildUI();self.ui.checkWindow:Show() end
    self:RenderAddonCheck()
    return true
end
function A:WarningPacket(sender,p)
    if p.kind=="presenceCheckRequest" then
        if self:IsLeader() and self.state and sender==self.state.master and not self.state.masterBlocked and p.scope==self:ProbeScope() then
            self:BeginAddonCheck();self:SendAddonSummary()
        end
        return true
    elseif p.kind=="presenceProbe" then
        if sender~=self.leader or sender==self.me or type(p.check)~="string" or #p.check>80 or (p.scope~=false and (type(p.scope)~="string" or #p.scope>120)) then return true end
        if A.Client:Uptime()-(self.lastPresenceReply or -10)<3 then return true end
        self.lastPresenceReply=A.Client:Uptime()
        local recoveryRev
        if p.scope==self:ProbeScope() and self.HasRecoveryBallots and self:HasRecoveryBallots() then recoveryRev=self.rev end
        self:Send({kind="presenceReply",check=p.check,scope=p.scope,version=self.version,wire=self.protocol,session=self:ProbeScope(),recoveryRev=recoveryRev},sender)
        return true
    elseif p.kind=="presenceReply" then
        local r=self.addonCheck
        if not self:IsLeader() or not r or p.check~=r.id or p.scope~=r.scope or r.scope~=self:ProbeScope() or not r.members[sender]
            or A.Client:ServerTime()-r.at<0 or A.Client:ServerTime()-r.at>30 then return true end
        if type(p.version)~="string" or #p.version>40 or not p.version:match("^[%w%.%-]+$") or not integer(p.wire,1,10000)
            or (p.session~=false and (type(p.session)~="string" or #p.session>120)) then return true end
        local recoveryRev=integer(p.recoveryRev,0,1000000000) and p.recoveryRev or nil
        r.members[sender]={version=p.version,wire=p.wire,session=p.session,recoveryRev=recoveryRev}
        self.addonSummaryDirty=true
        self:RenderAddonCheck()
        return true
    elseif p.kind=="presenceSummary" then
        local r=p.data
        if sender~=self.leader or not self:IsMaster() or type(r)~="table" or type(r.id)~="string" or #r.id>80
            or r.scope~=self:ProbeScope() or not integer(r.seq,1,1000000000) or type(r.roster)~="string" or #r.roster>4000 or not integer(r.at,A.Client:ServerTime()-60,A.Client:ServerTime()+5) or type(r.members)~="table" then return true end
        local members,count={},0
        for name,entry in pairs(r.members) do
            count=count+1
            if count>40 or type(name)~="string" or not self.roster[name] or type(entry)~="table" then return true end
            members[name]={}
            if entry.version then
                if type(entry.version)~="string" or #entry.version>40 or not entry.version:match("^[%w%.%-]+$") or not integer(entry.wire,1,10000)
                    or (entry.session~=false and (type(entry.session)~="string" or #entry.session>120)) then return true end
                local recoveryRev=integer(entry.recoveryRev,0,1000000000) and entry.recoveryRev or nil
                members[name]={version=entry.version,wire=entry.wire,session=entry.session,recoveryRev=recoveryRev}
            end
        end
        if self.addonCheck and self.addonCheck.scope==r.scope and ((self.addonCheck.seq or 0)>=r.seq or self.addonCheck.at>r.at) then return true end
        self.addonCheck={id=r.id,scope=r.scope,at=r.at,seq=r.seq,roster=r.roster,members=members}
        self:RenderAddonCheck()
        return true
    end
    return false
end
function A:ReleaseContextValid(c)
    if c and c.queue then
        if not self.state or c.sid~=self.state.id or not self:IsMaster() or self.state.masterBlocked or #c.queue==0 or #self.state.items+#c.queue>40 then return end
        local seen={}
        for _,value in ipairs(c.queue) do
            local entry=self:TrackedByID(value.tracked)
            if not entry or entry.guid~=value.guid or not self:CanQueueTrackedLoot(entry) or seen[entry.guid] then return end
            seen[entry.guid]=true
        end
        return {link=#c.queue==1 and self:TrackedByID(c.queue[1].tracked).link or (#c.queue.." item copies — queue and open responses")}
    end
    local item=c and self.state and c.sid==self.state.id and self:ItemByID(c.item)
    if not self:IsMaster() or not item or item.status=="awarded" or item.round~=c.round or item.responseRound~=c.responseRound then return end
    return item
end
function A:QueueTrackedLoot(id)
    if A.Client:Combat() then self:Print("Queue loot after combat. No response timers were started.");return false end
    if not self:IsMaster() or not self.state then return false end
    local entries,seen={},{}
    for _,entry in ipairs(self.state.trackedLoot or {}) do
        if self:CanQueueTrackedLoot(entry) and not seen[entry.guid] and (id==nil or id==entry.id) then
            entries[#entries+1]={tracked=entry.id,guid=entry.guid};seen[entry.guid]=true
        end
    end
    local c={sid=self.state.id,queue=entries}
    if not self:ReleaseContextValid(c) then self:Print("No unqueued loot selected, or the 40 session item limit would be exceeded.");return false end
    return self:CommitRelease(c)
end
function A:ReviewRelease(id,confirmed)
    if A.Client:Combat() then self:Print("Open responses after combat. No response timer was started.");return false end
    local item=self.state and self:ItemByID(id)
    if not self:IsMaster() or not item or item.status=="awarded" then return false end
    local c=confirmed or {sid=self.state.id,item=id,round=item.round,responseRound=item.responseRound}
    if not self:ReleaseContextValid(c) then self:Print("The item or response round changed. Review the release again.");return false end
    if item.voting~="idle" and not c.reopenConfirmed then
        self:ShowReroll(c,item)
        return true
    end
    return self:CommitRelease(c)
end
function A:ShowReroll(c,item)
    self:BuildUI()
    self.rerollContext=self.Copy(c)
    local dialog=self.ui.reroll
    self.ui.rerollItem:SetText(item.link)
    self:FitVotingDialog(dialog)
    dialog:Show();self:FocusWindow(dialog)
end
function A:CloseReroll()
    self.rerollContext=nil
    if self.ui and self.ui.reroll then self.ui.reroll:Hide() end
end
function A:ConfirmReroll()
    local c=self.rerollContext and self.Copy(self.rerollContext)
    self:CloseReroll()
    if not c then return false end
    c.reopenConfirmed=true
    return self:ReviewRelease(c.item,c)
end
function A:CommitRelease(c)
    if not self:ReleaseContextValid(c) then self:Print("The item, raid role or round changed. Review the release again.");return false end
    if c.queue then self:Act("queueLoot",{entries=c.queue,release=true})
    else self:Act("open",{item=c.item,expectedRound=c.round,expectedResponseRound=c.responseRound}) end
    return true
end
function A:CanReceiveTradeWarning(entry)
    return self.state and self.roster[self.me] and (self:IsLootController() or entry.holder==self.me) and entry.delivery~="delivered"
end
function A:TradeWarningLevel(entry)
    if not self:CanReceiveTradeWarning(entry) then return end
    local cfg=self:WarningSettings()
    local remaining=self:TradeRemaining(entry)
    if not cfg.trade or type(remaining)~="number" or remaining<=0 then return end
    if remaining<=cfg.urgent then return "urgent",remaining,cfg.urgent end
    if remaining<=cfg.early then return "early",remaining,cfg.early end
end
function A:TradeWarningKey(entry)
    return self.me..":"..(self.state.historyID or self.state.id)..":"..entry.guid..":"..entry.holder
end
function A:TickTradeWarnings()
    if not self.state then
        self.tradeNotices={}
        if self.ui and self.ui.tradeAlerts then self.ui.tradeAlerts:Hide() end
        return
    end
    self:InitStorage()
    local cfg=self:WarningSettings()
    local seen=SanguineLootCouncilDB.tradeWarningSeen
    local notices=self.tradeNotices or {};self.tradeNotices=notices
    local fresh=false
    local activeKeys={}
    for _,entry in ipairs(self.state.trackedLoot or {}) do
        local level,remaining,threshold=self:TradeWarningLevel(entry)
        local key=self:TradeWarningKey(entry)
        activeKeys[key]=true
        if level then
            local record=seen[key]
            if type(record)~="table" or type(record.thresholds)~="table" then record={at=A.Client:ServerTime(),thresholds={}} end
            seen[key]=record
            if not record.thresholds[tostring(threshold)] then
                record.at=A.Client:ServerTime();record.thresholds[tostring(threshold)]=true
                if level=="urgent" then record.thresholds[tostring(cfg.early)]=true end
                notices[key]={sid=self.state.id,guid=entry.guid,holder=entry.holder,level=level,expires=A.Client:Uptime()+30}
                fresh=true
            end
        end
    end
    local retained={}
    for key,record in pairs(seen) do
        if type(record)~="table" or type(record.at)~="number" or type(record.thresholds)~="table" or A.Client:ServerTime()-record.at>43200 or record.at>A.Client:ServerTime()+5 then seen[key]=nil
        else retained[#retained+1]={key=key,at=record.at} end
    end
    table.sort(retained,function(a,b) if activeKeys[a.key]~=activeKeys[b.key] then return not activeKeys[a.key] end;return a.at<b.at end)
    for i=1,math.max(0,#retained-512) do seen[retained[i].key]=nil end
    self:RenderTradeAlerts(fresh)
    if fresh and cfg.sound and type(PlaySound)=="function" then pcall(PlaySound,SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_2 or 12867,"Master") end
end
function A:TickWarnings()
    if self:IsLeader() and self.addonSummaryDirty and A.Client:Uptime()-(self.lastAddonSummary or -10)>=1 then self:SendAddonSummary() end
    if self.ui and not self:IsLootController() then self.ui.checkWindow:Hide() end
    self:TickTradeWarnings()
end
