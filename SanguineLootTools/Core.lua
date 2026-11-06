local _, A = ...
SanguineLootTools = A
SanguineLootCouncil = A -- Retained internal integration identity for existing test modules.
A.displayName = "Sanguine Loot Tools"
A.version = "0.12.0-alpha.70"
A.protocol = 19
A.confirmationDialogs = {}
A.responses = {"BIS", "Upgrade", "Minor Upgrade", "Off-Spec", "PvP", "Pass"}
A.roster = {}
A.rev = 0

function A:Print(s)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd8b35aSanguine Loot Tools:|r " .. s)
end

function A:IsForever()
    return self.Client and self.Client.IsForever and self.Client:IsForever()
end

function A:Name(unit)
    local ok, name, suffix = self.Client:Call("UnitFullName", unit)
    if not ok or type(name) ~= "string" or name == "" then return end
    -- Forever returns the character's surname in the second slot.
    if self:IsForever() then
        if type(suffix) == "string" and suffix ~= "" then return name .. "-" .. suffix end
        return
    end
    if not suffix or suffix == "" then
        local available, realm = self.Client:Call("GetNormalizedRealmName")
        suffix = available and realm or nil
    end
    if type(suffix) == "string" and suffix ~= "" then return name .. "-" .. suffix end
end

function A:RefreshRoster()
    if self:IsSoloTest() then return end
    self.me = self:Name("player")
    self.roster, self.leader = {}, nil
    if A.Client:InRaid() then
        local ok,count=self.Client:Call("GetNumGroupMembers")
        if not ok or type(count)~="number" or count%1~=0 or count<0 or count>40 then count=0 end
        for i = 1, count do
            local unit = "raid" .. i
            local name = self:Name(unit)
            if name then
                self.roster[name] = unit
                local ok,isLeader=self.Client:Call("UnitIsGroupLeader",unit)
                if ok and (isLeader==true or isLeader==1) then self.leader = name end
            end
        end
    elseif self.Client:InGroup() then
        for _,unit in ipairs({"player","party1","party2","party3","party4"}) do
            local name=self:Name(unit)
            if name then
                self.roster[name]=unit
                local ok,isLeader=self.Client:Call("UnitIsGroupLeader",unit)
                if ok and (isLeader==true or isLeader==1) then self.leader=name end
            end
        end
    end
    self.gameLeader = self.leader or false
    local state=self.state
    local liveRaid=state and not self.demo and not state.groupTest and self.Client:InRaid()
    if liveRaid and self.RefreshRecoveryAuthority then self:RefreshRecoveryAuthority() end
    if state and not liveRaid and (state.leader ~= self.leader or (not state.groupTest and not self.Client:InRaid())) then
        self.state, self.rev, self.demo, self.groupTest = nil, 0, nil, nil
        if self.ResetTestTransport then self:ResetTestTransport() end
        self:Print("Leadership changed or you left the raid. The old session has stopped; the leader can start a new one.")
    end
    if not self.state and self.locatedRecovery then
        local located=self.locatedRecovery
        if self.roster[located.sender] and self.Client:InRaid() and self.Client:Uptime()<located.untilAt then
            self.leader=located.sender
        else self.locatedRecovery=nil end
    end
    if self.CheckRecoveryRoster then self:CheckRecoveryRoster() end
    if not self.recoveryPending and self.OnVotingRosterChanged then self:OnVotingRosterChanged() end
    if self.Render then self:Render() end
end

function A:Resolve(name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
    local forever = self:IsForever()
    if forever then name = name:gsub("^([^%s%-]+)%s+([^%s%-]+)$", "%1-%2") end
    if self.roster[name] then return name end
    local wanted, found = name:lower()
    for full in pairs(self.roster) do
        if full:lower() == wanted or (not forever and (full:match("^[^-]+") or full):lower() == wanted) then
            if found then return nil end
            found = full
        end
    end
    return found
end

function A:IsGameLeader()
    if self.gameLeader==nil then return self:IsLeader() end
    return self.me and self.me==self.gameLeader
end
function A:IsLeader() return self.me and self.me == self.leader end
function A:IsSoloTest() return self.demo and not self.groupTest end
function A:TestLabel() return self.groupTest and "GROUP TEST" or "SOLO TEST" end
function A:IsMaster() return self.state and self.state.master == self.me and not self.state.masterBlocked and not self.recoveryPending end
function A:IsCouncilMember(name)
    local s = self.state
    return s and name and ((s.council and s.council[name] == true) or (s.master == name and not s.masterBlocked)) or false
end
function A:IsCouncil() return self:IsCouncilMember(self.me) end
function A:CanViewCouncil() return (self:IsMaster() or self:IsCouncil()) == true end
function A:DisplayName(name)
    if self:IsForever() then return name end
    local short=name:match("^[^-]+") or name
    for other in pairs(self.roster or {}) do
        if other~=name and (other:match("^[^-]+") or other)==short then return name end
    end
    return short
end

function A:Changed()
    if self.NotifyLootSuggestions then self:NotifyLootSuggestions() end
    if self.PreloadSessionItems then self:PreloadSessionItems() end
    if self.corpseOpen or (self.state and next(self.state.corpseRoutes or {})) then self.corpseScanSoon=true end
    if self.PrimeLootBagSnapshot then self:PrimeLootBagSnapshot() end
    if self.PruneActiveCaches then self:PruneActiveCaches() end
    if self.PersistSession then self:PersistSession() end
    if self.Render then self:Render() end
end

function A:Record(item)
    self:UpsertAward(item)
end

-- All requests are reduced here on the current raid leader's client.
-- The transport supplies sender; never trust an identity in the payload.
function A:Reduce(sender, p)
    if not self.Client:ClockReady() then return false,"Client clocks unavailable. Session changes are disabled; use /slt diagnostics." end
    if not self.roster[sender] or type(p) ~= "table" then return false, "Not a raid member." end
    if p.op == "start" then
        if sender ~= self.leader or (not self:IsSoloTest() and not self:IsGameLeader()) or self.state then return false, "Only the raid leader can start an idle session." end
        if p.groupTest~=nil and p.groupTest~=true then return false,"Invalid test mode." end
        if self.Client:InGroup() and not self.Client:InRaid() and p.groupTest~=true then return false,"Party sessions are available through /slt test only." end
        if p.groupTest and not self.Client:InGroup() then return false,"Shared tests require a party or raid." end
        self:InitStorage()
        local setup=self:SessionRaidSettings()
        self.rev = 0
        self.state = {id = tostring(A.Client:ServerTime()) .. ":" .. tostring(math.random(100000, 999999)),
            leader = sender, recoveryAssistant = setup.recoveryAssistant, master = setup.master, masterFallback = setup.masterFallback, council = self.Copy(setup.council), responseOptions=self.Copy(setup.responseOptions),responseNextID=6,responseConfigRevision=0, items = {}, selfVotes = setup.selfVotes, rules = self.Copy(setup.rules), responseDuration = setup.responseDuration,
            trackedLoot = {}, lootSequences = {}, autoCollect = setup.lootConfiguration.collection, lootConfiguration=self.Copy(setup.lootConfiguration),lootConfigRevision=0, warningSettings=self.Copy(setup.warningSettings),announcementSettings=self.Copy(setup.announcementSettings)}
        for _,option in ipairs(self.state.responseOptions) do self.state.responseNextID=math.max(self.state.responseNextID,option.id) end
        if p.groupTest then
            self.testSerial=(self.testSerial or 0)+1
            self.state.id=self.state.id..":test:"..self.testSerial
            self.state.groupTest=true;self.state.autoCollect=false
            self.state.responseDuration=60;self.demo,self.groupTest=true,true
        end
        self:ApplyGameMaster()
        return true
    end
    local s = self.state
    if not s or p.sid ~= s.id then return false, "No matching active session." end
    if p.op=="recoveryAssistant" then
        if sender~=self.leader or s.groupTest then return false, "Only the session host can name a recovery assistant." end
        if p.target~=false and (p.target==sender or not self:IsRaidAssistant(p.target)) then
            return false, "Choose a promoted Raid Assistant from the current raid."
        end
        s.recoveryAssistant=p.target or nil
        return true
    end
    if p.op=="corpseNativeReceipt" then return self:ReduceNativeReceipt(sender,p) end
    if p.op=="lootConfiguration" or p.op=="routeLoot" or p.op=="corpsePrepare" or p.op=="corpseReady" or p.op=="corpseStarted" or p.op=="corpseCleared" or p.op=="corpseFailed" or p.op=="corpseReceipt" then
        return self:ReduceLootConfiguration(sender,p)
    end
    if s.groupTest and (p.op=="lootReport" or p.op=="tradeReceipt" or p.op=="tradeActivity" or p.op=="autoCollect") then
        return false,"Shared tests use simulated loot only. Real collection and trade reporting are disabled."
    end
    if p.op=="archiveCompleted" then return self:ReduceArchive(sender,p) end
    if p.op=="suggestLoot" or p.op=="dismissLootSuggestion" then return self:ReduceLootSuggestion(sender,p) end
    if p.op == "tradeReceipt" or p.op == "tradeActivity" or p.op == "lootReport" or p.op == "autoCollect" or p.op == "queueLoot" or p.op == "manualLoot" or p.op == "bagLoot" or p.op == "lootHolder" or p.op == "confirmDelivery" or p.op == "reopenDelivery" then
        return self:ReduceLoot(sender, p)
    end
    if s.masterBlocked and (p.op == "add" or p.op == "open" or p.op == "close" or p.op == "openVoting" or p.op == "closeVoting" or p.op == "resetVoting" or p.op == "award" or p.op == "correctAward") then
        return false, "Waiting for the game's master-looter role to resolve. The raid leader can select manual mode if needed."
    end
    if p.op=="responseOptions" then
        if sender~=self.leader or self:VotingLocked() then return false,"Only the raid leader edits responses outside active rounds." end
        if p.expectedRevision~=(s.responseConfigRevision or 0) then return false,"Response settings changed. Review them again." end
        local options=self:CleanResponses(p.options)
        if not options then return false,"Invalid response configuration." end
        s.responseOptions=options;s.responseConfigRevision=(s.responseConfigRevision or 0)+1
        for _,v in ipairs(options) do s.responseNextID=math.max(s.responseNextID or 6,v.id) end
        if not self.demo then SanguineLootCouncilDB.responseOptions=self.Copy(options) end
        return true
    elseif p.op=="announcementSetting" then
        if sender~=self.leader then return false,"Only the raid leader changes raid announcements." end
        local settings=self:EditAnnouncementSetting(p)
        if not settings then return false,"Invalid announcement setting." end
        s.announcementSettings=settings
        return true
    elseif p.op=="warningSettings" then
        if sender~=self.leader then return false,"Only the raid leader changes warning settings." end
        local settings=self:CleanWarningSettings(p.settings)
        if not settings then return false,"Invalid warning settings." end
        s.warningSettings=settings
        if not self.demo then SanguineLootCouncilDB.warningSettings=self.Copy(settings) end
        return true
    elseif p.op == "end" then
        if sender ~= self.leader then return false, "Only the raid leader can end the session." end
        self.state = nil
        return true
    elseif p.op == "profile" then
        if sender ~= self.leader then return false, "Only the raid leader can apply profiles." end
        if type(p.master) ~= "string" or self:SetupMemberName(p.master)~=p.master or type(p.council) ~= "table" or type(p.selfVotes) ~= "boolean" then
            return false, "Invalid profile settings."
        end
        if self:VotingLocked() then return false, "Reset all unawarded ballots before changing council or voting rules." end
        if not self:ValidVoting(p.rules) then return false, "Invalid voting rules." end
        if not self:ValidResponseDuration(p.responseDuration or 60) then return false, "Invalid response timer." end
        local lootConfiguration=self:CleanLootConfiguration(p.lootConfiguration or self:DefaultLootConfiguration())
        if not lootConfiguration then return false,"Invalid profile Loot Configuration." end
        local options=self:CleanResponses(p.responseOptions or self:DefaultResponses())
        if not options then return false,"Invalid profile responses." end
        local count = 0
        for name, enabled in pairs(p.council) do
            count = count + 1
            if count > 40 or type(name) ~= "string" or not self.roster[name] or enabled ~= true then return false, "Invalid profile council." end
        end
        s.responseOptions=options;s.responseConfigRevision=(s.responseConfigRevision or 0)+1
        for _,v in ipairs(options) do s.responseNextID=math.max(s.responseNextID or 6,v.id) end
        if not self.demo then SanguineLootCouncilDB.responseOptions=self.Copy(options) end
        s.masterFallback, s.council, s.selfVotes, s.rules = p.master, p.council, p.selfVotes, self.Copy(p.rules)
        s.warningSettings=self:CleanWarningSettings(p.warningSettings) or self:DefaultWarningSettings()
        if not self.demo then SanguineLootCouncilDB.warningSettings=self.Copy(s.warningSettings) end
        if self.RememberNativePolicy then self:RememberNativePolicy() end
        s.lootConfiguration=lootConfiguration;s.autoCollect=lootConfiguration.collection;s.lootConfigRevision=(s.lootConfigRevision or 0)+1;self:CancelPreparedCorpseRoutes()
        if not self.demo then SanguineLootCouncilDB.lootConfiguration=self.Copy(lootConfiguration) end
        self:ApplyGameMaster()
        s.responseDuration = p.responseDuration or 60
        if not self.demo then SanguineLootCouncilDB.responseDuration = s.responseDuration end
        return true
    elseif p.op == "syncMaster" then
        if sender ~= self.leader then return false, "Only the raid leader controls Master Looter synchronization." end
        self:ApplyGameMaster()
        return true
    elseif p.op == "responseDuration" then
        if sender ~= self.leader then return false, "Only the raid leader can change the response timer." end
        if not self:ValidResponseDuration(p.duration) then return false, "Use 5–600 whole seconds." end
        s.responseDuration = p.duration
        if not self.demo then SanguineLootCouncilDB.responseDuration = p.duration end
        return true
    elseif p.op == "classAutoPass" then
        if sender~=self.leader then return false,"Only the raid leader resolves class auto passes." end
        local changed=0
        for _,it in ipairs(s.items) do changed=changed+self:RefreshClassAutoPasses(it,true) end
        return changed>0,"No class auto passes changed."
    elseif p.op == "rules" then
        if sender ~= self.leader then return false, "Only the raid leader can change voting rules." end
        if self:VotingLocked() then return false, "Reset all unawarded ballots before changing voting rules." end
        if not self:ValidVoting(p.rules) then return false, "Invalid voting rules." end
        s.rules = self.Copy(p.rules)
        return true
    elseif p.op == "master" or p.op == "council" or p.op == "selfVotes" then
        if sender ~= self.leader then return false, "Only the raid leader can change session settings." end
        if p.op ~= "master" and self:VotingLocked() and not (s.groupTest and p.op=="council") then return false, "Reset all unawarded ballots before changing council or self-voting." end
        if p.op == "selfVotes" then
            s.selfVotes = not s.selfVotes
        else
            local target = (p.op=="council" and p.enabled==false and type(p.target)=="string" and s.council[p.target] and p.target) or self:Resolve(p.target)
            if not target then return false, "Use an unambiguous raid member name (full name)." end
            if p.op == "master" then
                if not self.demo then
                    local gameMaster, status = self:ReadGameMaster()
                    if gameMaster then
                        if gameMaster ~= target then
                            local ok, message = self:RequestMasterHandoff(target)
                            if not ok then return false, message end
                        end
                        self:ApplyGameMaster()
                        return true
                    end
                    if status=="pending" or status=="restricted" or (status=="unavailable" and s.masterBlocked) then
                        return false, "Wait for WoW to report its Master Looter before assigning."
                    end
                end
                s.masterFallback = target
                self.masterHandoff = nil
                self:ApplyGameMaster()
            else
                local ok,message=self:ApplyCouncilMemberChange(s.council,target,p)
                if not ok then return false,message end
                if s.groupTest then
                    for _,it in ipairs(s.items) do
                        if it.status~="awarded" and it.voting~="idle" then self:ResetBallot(it);self:StartBallot(it) end
                    end
                end
            end
        end
        return true
    elseif p.op == "add" then
        if sender ~= s.master then return false, "Only the master looter can add loot." end
        if #s.items >= self.limits.activeItems then return false, "Active queue is full (40 items). Archive confirmed deliveries in Settings > Tools." end
        if type(p.link) ~= "string" or #p.link > 500 or not p.link:match("|Hitem:%d+:[^|]*|h%[[^%]]+%]|h") then
            return false, "Paste a complete item link using Shift-click."
        end
        local link = p.link:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h%[[^%]]+%]|h|r)")
            or p.link:match("(|Hitem:[^|]+|h%[[^%]]+%]|h)")
        table.insert(s.items, {id = self:NextIdentity("item"), link = link, status = "queued", responses = {}, ballots = {}, voting = "idle", deadline = false, round = 1, ballotVersion = 0})
        return true
    end
    local item = type(p.item) == "number" and self:ItemByID(p.item)
    if not item then return false, "Select a valid item." end
    if p.op == "open" or p.op == "close" then
        if sender ~= s.master or item.status == "awarded" then return false, "Only the master looter can open/close unawarded items." end
        if p.op == "close" and item.status ~= "open" then return false, "Responses are not open." end
        if p.op=="open" and ((p.expectedRound~=nil and p.expectedRound~=item.round) or (p.expectedResponseRound~=nil and p.expectedResponseRound~=item.responseRound)) then return false,"Response round changed. Review release again." end
        if p.op == "open" and A.Client:Combat() then return false,"Open responses after combat." end
        if p.op == "open" then self:StartResponses(item)
        else self:FinishResponses(item, item.responseDeadline and A.Client:ServerTime() >= item.responseDeadline and "timer" or "manual") end
        return true
    elseif p.op == "expireResponses" then
        if sender ~= self.leader or item.status ~= "open" or not item.responseDeadline or A.Client:ServerTime() < item.responseDeadline then return false, "Response deadline has not been reached." end
        self:FinishResponses(item, "timer")
        return true
    elseif p.op == "respond" then
        if item.status ~= "open" then return false, "This item is not open for responses." end
        if p.responseRound ~= item.responseRound then return false, "Responses were reopened. Review the item and respond again." end
        if item.responseDeadline and A.Client:ServerTime() >= item.responseDeadline then return false, "The response deadline has passed." end
        local option=self:ResponseOption(p.choice,item)
        if type(p.choice) ~= "number" or not option or not option.enabled then return false, "Invalid response." end
        if type(p.note) ~= "string" or #p.note > 100 then return false, "Note is too long (100 bytes maximum)." end
        local equipment, valid = self:CleanEquipment(item, p.equipment)
        if not valid then return false, "Invalid equipped-item snapshot." end
        self:ApplyResponse(item, sender, p.choice, p.note:gsub("[%c|]", ""), equipment)
        item.responseMembers = item.responseMembers or {}
        item.responseMembers[sender] = true
        return true
    elseif p.op == "vote" or p.op == "setVote" or p.op == "abstain" or p.op == "openVoting" or p.op == "closeVoting" or p.op == "resetVoting" or p.op == "expireVoting" then
        return self:ReduceVoting(sender, p, item)
    elseif p.op == "correctAward" then
        return self:ReduceCorrection(sender, p, item)
    elseif p.op == "award" then
        if sender ~= s.master then return false, "Only the master looter can award loot." end
        local expired=item.status=="open" and item.responseDeadline and A.Client:ServerTime()>=item.responseDeadline
        if item.status~="closed" and not expired then return false,"Wait for the response timer to finish before awarding." end
        if item.voting~="open" and item.voting~="closed" then return false,"Resume voting before awarding this item." end
        local target = self:Resolve(p.target)
        if not target or not item.responses[target] or item.responses[target].choice == 6 then return false, "Winner must be in the raid and have requested the item." end
        if (p.expectedRound and p.expectedRound~=item.round) or (p.expectedResponseRound and p.expectedResponseRound~=item.responseRound)
            or (p.expectedResponseRevision and p.expectedResponseRevision~=item.responses[target].revision) then return false,"The item or response changed. Review the award again." end
        if expired then self:FinishResponses(item,"timer") end
        if item.voting=="open" then self:CloseBallot(item);item.ballotVersion=(item.ballotVersion or 0)+1 end
        item.winner, item.status = target, "awarded"
        item.awardedAt, item.awardedBy = p.awardedAt or A.Client:ServerTime(), sender
        local totals = self:BallotTotals(item)
        local votes = totals[target] or 0
        item.awardedVotes = p.awardedVotes or votes
        item.awardRevision, item.corrections = 1, {}
        item.originalAward = self:AwardSnapshot(item)
        self:UpdateDeliveryAward(item, false)
        return true
    end
    return false, "Unknown action."
end

function A:Act(op, data)
    if self.recoveryPending and op~="end" then
        self:Print("Loot actions are paused during session recovery.");return false
    end
    if not self.state and self.raidSetupOperations[op] then return self:ApplyIdleRaidSetting(op,data or {}) end
    if not self.Client:ClockReady() then self:Print("Client clocks unavailable. Session actions are disabled; use /slt diagnostics.");return false end
    data = data or {}
    if (op=="respond" or op=="open" or op=="queueLoot") and A.Client:Combat() then
        self:Print("Loot responses and releases are unavailable in combat. Reopen responses after combat if needed.");return false
    end
    if op=="respond" then
        local item=self:ItemByID(data.item)
        if self:ClassEligibility(item)=="Restricted" then
            self:Print("This item is not usable by your class. The response list has been refreshed.");self:Render();return false
        end
        local option=item and self:ResponseOption(data.choice,item)
        if option and option.transmog then
            local _,reason=self:TransmogResponseStatus(item)
            if reason then self:Print(reason);self:Render();return false end
        end
        if type(data.note)~="string" or #data.note>100 then self:Print("Notes must fit within 100 bytes. Your draft has been kept.");return false end
    end
    data.op, data.sid = op, self.state and self.state.id
    if op == "respond" and self.state and self:ItemByID(data.item) then
        data.responseRound = self:ItemByID(data.item).responseRound
        data.equipment = self:CaptureEquipment(self:ItemByID(data.item))
        if not self:IsSoloTest() and not self:IsLeader() then self:PreparePersonalResponse(data) end
    end
    if (op == "vote" or op == "setVote" or op == "abstain") and self.state and self:ItemByID(data.item) then data.round = self:ItemByID(data.item).round end
    if self:IsSoloTest() or self:IsLeader() then return self:HostRequest(self.me, data)
    elseif self.leader then
        local queued=self:Send({kind = "request", data = data}, self.leader)
        if op=="respond" then
            if queued==false then self:ClearPendingPersonalResponse(data.responseRequest) end
            self:Render()
        end
        return queued
    else self:Print("Join a raid. Its leader controls the session. Use /slt test to try it solo.");return false end
end

function A:StartDemo()
    if self.Client:Combat() then self:Print("Start or refresh test mode after combat.");return false end
    if self.Client:InGroup() then return self:StartGroupTest() end
    if self.state and not self.demo then self:Print("End the current session before using test mode."); return end
    local player=self:Name("player")
    if not player then self:Print("Player identity unavailable; test mode cannot start. Use /slt diagnostics.");return end
    self.state,self.rev,self.renderSession,self.selectedLootKey,self.selectedTracked=nil,0,nil,nil,nil
    self.demo, self.me = true, player
    self.leader = self.me
    self.roster = {[self.me] = "player", ["Warrior-Test"] = true, ["Priest-Test"] = true}
    self:Act("start")
    if not self.state then self.demo=nil;self:Print("Test session could not start. Use /slt diagnostics for details.");return end
    self.state.responseDuration=60
    self:SeedTestLoot()
    self:Render()
    self:Print("Solo test: "..#self.state.trackedLoot.." Forever items await release in Loot. Use Queue on a row, Manage > Queue item, or Queue all to start 60-second responses. Real trading and history saving are disabled. /slt test refreshes; /slt leave-test exits.")
end


function A:StartGroupTest()
    -- Discard only an old solo simulation before reading real group membership.
    if self:IsSoloTest() then self.demo,self.state=nil,nil end
    self:RefreshRoster()
    if self.state and not self.groupTest then self:Print("End the real loot session before starting a shared test.");return false end
    if not self:IsLeader() then
        self.ignoredTestSID=nil;self.lastSync=nil;self:RequestSync()
        self:Print("Shared test: ask the group leader to run /slt test. Your addon will receive the test items automatically.")
        return false
    end
    self.state,self.rev,self.renderSession,self.selectedTracked,self.publicBaseline=nil,0,nil,nil,nil
    self:ResetTestTransport()
    self.demo,self.groupTest,self.preparingGroupTest=true,true,true
    self:Act("start",{groupTest=true})
    if not self.state then self.demo,self.groupTest,self.preparingGroupTest=nil,nil,nil;return false end
    self:SeedTestLoot()
    self.preparingGroupTest=nil
    self:Publish() -- One complete set of unreleased simulated copies.
    self:Render()
    self:Print("GROUP TEST: "..#self.state.trackedLoot.." Forever items await release in the Master Looter’s Loot window. Queue individual items or Queue all to start 60-second responses for the group. Assign council/master in Settings. Real bag collection, trading and history saving are disabled. /slt test refreshes; /slt leave-test ends the shared test.")
    return true
end

function A:LeaveTest()
    if not self.demo then return end
    if self.groupTest and self:IsLeader() then
        self:Act("end") -- publish the end while the transport still knows test mode
        return
    end
    self.ignoredTestSID=self.groupTest and self.state and self.state.id or nil
    self.demo,self.groupTest,self.state,self.rev=nil,nil,nil,0
    self:ResetTestTransport()
    self:RefreshRoster()
end
