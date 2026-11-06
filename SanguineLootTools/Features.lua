local _, A = ...

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
A.Copy = copy

function A:InitStorage()
    SanguineLootCouncilDB = SanguineLootCouncilDB or {}
    local db = SanguineLootCouncilDB
    db.responseOptions=self:CleanResponses(db.responseOptions) or self:DefaultResponses()
    db.archives=type(db.archives)=="table" and db.archives or {}
    db.schemaVersion=2
    db.lootConfiguration=self:CleanLootConfiguration(db.lootConfiguration) or self:DefaultLootConfiguration()
    db.history, db.profiles, db.checkpoints = db.history or {}, db.profiles or {}, db.checkpoints or {}
    if self.PruneGreenHistory then self:PruneGreenHistory() end
    if not self:ValidResponseDuration(db.responseDuration) then db.responseDuration = 60 end
    db.warningSettings=self:CleanWarningSettings(db.warningSettings) or self:DefaultWarningSettings()
    if type(db.tradeWarningSeen)~="table" then db.tradeWarningSeen={} end
    db.raidSetup=self:CleanRaidSetup(db.raidSetup)
end

function A:CanConfigureRaid()
    return not self.state or self:IsLeader()
end
function A:RaidConfigurationRevision()
    return self.state and (self.state.responseConfigRevision or 0) or (SanguineLootCouncilDB.raidSetupRevision or 0)
end
function A:SetupMemberName(value)
    if type(value)~="string" then return end
    value=value:match("^%s*(.-)%s*$")
    local resolved=self.roster and self:Resolve(value)
    if resolved then return resolved end
    if #value<=100 and value:match("^[^%s|]+%-[^%s|]+$") and not value:find("%c") then return value end
end
function A:CleanRaidSetup(value)
    local v=type(value)=="table" and value or {}
    local result={council={},master=self:SetupMemberName(v.master),recoveryAssistant=self:SetupMemberName(v.recoveryAssistant),
        selfVotes=v.selfVotes~=false,rules=self:ValidVoting(v.rules) and self.Copy(v.rules) or self:DefaultVoting()}
    local count=0
    if type(v.council)=="table" then
        for name,enabled in pairs(v.council) do
            local full=self:SetupMemberName(name)
            if enabled==true and full and count<40 then result.council[full]=true;count=count+1 end
        end
    end
    if type(v.profile)=="string" and #v.profile<=40 and not v.profile:find("[%c|]") then result.profile=v.profile end
    return result
end
function A:RaidSettings()
    if self.state then return self.state end
    self:InitStorage()
    local d=SanguineLootCouncilDB;local c=self.Copy(d.raidSetup)
    c.master=c.master or self.me
    c.responseOptions=self.Copy(d.responseOptions);c.responseDuration=d.responseDuration
    c.warningSettings=self.Copy(d.warningSettings)
    c.announcementSettings=self:AnnouncementSettings()
    c.lootConfiguration=self.Copy(d.lootConfiguration)
    return c
end
A.raidSetupOperations={responseDuration=true,responseOptions=true,master=true,council=true,
    selfVotes=true,rules=true,warningSettings=true,announcementSetting=true,lootConfiguration=true,recoveryAssistant=true}
function A:RememberRaidSettings(settings,profile)
    if self.demo then return end
    local c=settings or self.state;if not c then return end
    self:InitStorage();local d=SanguineLootCouncilDB
    d.raidSetup=self:CleanRaidSetup(c);d.raidSetup.profile=profile
    d.raidSetup.master=c.masterFallback or d.raidSetup.master
    d.responseOptions=self:CleanResponses(c.responseOptions) or self:DefaultResponses()
    d.responseDuration=c.responseDuration
    d.warningSettings=self:CleanWarningSettings(c.warningSettings) or self:DefaultWarningSettings()
    if c.announcementSettings then d.announcementSettings=self.Copy(c.announcementSettings) end
    d.lootConfiguration=self:CleanLootConfiguration(c.lootConfiguration) or self:DefaultLootConfiguration()
    d.raidSetupRevision=(d.raidSetupRevision or 0)+1
end
-- Explicit row selections are idempotent; replacing a member is one validated change.
function A:ApplyCouncilMemberChange(council,target,p)
    if p.enabled~=nil and type(p.enabled)~="boolean" then return false,"Invalid council selection." end
    if p.previous~=nil then
        if p.enabled~=true or type(p.previous)~="string" or council[p.previous]~=true then return false,"Council membership changed. Select the member again." end
        if target~=p.previous and council[target] then return false,"That player is already on the council." end
    end
    local enabled=p.enabled
    if enabled==nil then enabled=not council[target] end
    if enabled and not council[target] and not p.previous then
        local count=0;for _ in pairs(council) do count=count+1 end
        if count>=40 then return false,"Council is full (40 members)." end
    end
    if p.previous then council[p.previous]=nil end
    council[target]=enabled and true or nil
    return true
end

function A:ApplyIdleRaidSetting(op,p)
    if self.state or self.demo or not self.raidSetupOperations[op] then return false end
    local c=self:RaidSettings()
    if op=="responseDuration" then
        if not self:ValidResponseDuration(p.duration) then self:Print("Use 5–600 whole seconds.");return false end
        c.responseDuration=p.duration
    elseif op=="responseOptions" then c.responseOptions=self:CleanResponses(p.options);if not c.responseOptions then return false end
    elseif op=="rules" then if not self:ValidVoting(p.rules) then return false end;c.rules=self.Copy(p.rules)
    elseif op=="selfVotes" then c.selfVotes=not c.selfVotes
    elseif op=="master" or op=="council" then
        local target=self:SetupMemberName(p.target)
        if not target then self:Print("Enter an unambiguous current member or full character name for later.");return false end
        if op=="master" then
            if self.Client:InGroup() then
                if not self:IsLeader() then self:Print("Only the raid leader can assign the Master Looter.");return false end
                if not self.roster[target] then self:Print("Choose a current raid member.");return false end
                local actual,status=self:ReadGameMaster()
                if actual then
                    if actual==target then return true end
                    local ok,message=self:RequestMasterHandoff(target)
                    if not ok then self:Print(message) end
                    if self.RenderMasterSettings then self:RenderMasterSettings() end
                    return ok
                end
                if status=="pending" or status=="restricted" then self:Print("Wait for WoW to report its Master Looter before assigning.");return false end
            end
            c.master=target
        else
            local ok,message=self:ApplyCouncilMemberChange(c.council,target,p)
            if not ok then self:Print(message);return false end
        end
    elseif op=="recoveryAssistant" then
        if not self:IsGameLeader() then return false end
        if p.target~=false and not self:IsRaidAssistant(p.target) then
            self:Print("Choose a promoted Raid Assistant from the current raid.");return false
        end
        c.recoveryAssistant=p.target or nil
    elseif op=="announcementSetting" then
        c.announcementSettings=self:EditAnnouncementSetting(p)
        if not c.announcementSettings then return false end
    elseif op=="warningSettings" then c.warningSettings=self:CleanWarningSettings(p.settings);if not c.warningSettings then return false end
    elseif op=="lootConfiguration" then c.lootConfiguration=self:CleanLootConfiguration(p.settings);if not c.lootConfiguration then return false end
    end
    self:RememberRaidSettings(c);self:Changed();return true
end
function A:SessionRaidSettings()
    local c=self:RaidSettings();local missing={}
    for name in pairs(c.council) do
        if not self.roster[name] then c.council[name]=nil;missing[#missing+1]=name end
    end
    if c.recoveryAssistant and not self:IsRaidAssistant(c.recoveryAssistant) then c.recoveryAssistant=nil end
    c.masterFallback=c.master
    if not self.roster[c.master] then c.master=self.me end
    if #missing>0 then table.sort(missing);self:Print("Skipped absent council: "..table.concat(missing,", ")) end
    if c.lootConfiguration.automatic then
        for _,r in ipairs(c.lootConfiguration.rules) do
            if r.action=="assign" and r.target~="@master" and not self.roster[r.target] then
                c.lootConfiguration.automatic=false
                self:Print("Automatic assignment paused: a saved recipient is absent. Review Loot Configuration.");break
            end
        end
    end
    return c
end

local function profileName(name)
    if type(name) ~= "string" then return end
    name = name:match("^%s*(.-)%s*$")
    if #name < 1 or #name > 40 or name:find("[%c|]") then return end
    return name
end

function A:SaveProfile(name)
    self:InitStorage()
    name = profileName(name)
    if self.demo then self:Print("Test mode does not save profiles."); return false end
    if not self:CanConfigureRaid() then self:Print("Only the Raid Leader can save the active session setup."); return false end
    if not name then self:Print("Use a profile name of 1–40 bytes without formatting."); return false end
    local n = 0
    for _ in pairs(SanguineLootCouncilDB.profiles) do n = n + 1 end
    if n >= 20 and not SanguineLootCouncilDB.profiles[name] then self:Print("Maximum 20 profiles. Delete one first."); return false end
    local c=self:RaidSettings()
    SanguineLootCouncilDB.profiles[name] = {master=c.masterFallback or c.master,council=copy(c.council),selfVotes=c.selfVotes,rules=copy(c.rules),responseOptions=copy(c.responseOptions),responseDuration=c.responseDuration,warningSettings=copy(c.warningSettings),lootConfiguration=copy(c.lootConfiguration)}
    self:RememberRaidSettings(self:RaidSettings(),name)
    self:Print("Saved profile: " .. name)
    self:Changed()
    return true
end

function A:LoadProfile(name)
    self:InitStorage()
    if self.demo or not self:CanConfigureRaid() then self:Print("Only the Raid Leader can apply a profile to the active session."); return false end
    local p = SanguineLootCouncilDB.profiles[profileName(name) or ""]
    if not p then self:Print("Profile not found."); return false end
    p=self.Copy(p)
    p.rules=p.rules or self:DefaultVoting();p.responseOptions=p.responseOptions or self:DefaultResponses()
    p.responseDuration=p.responseDuration or 60;p.lootConfiguration=p.lootConfiguration or self:DefaultLootConfiguration()
    p.council=p.council or {}
    if type(p.council)~="table" then self:Print("This profile has invalid council settings.");return false end
    if not self.state then
        if not self:ValidVoting(p.rules) or not self:CleanResponses(p.responseOptions)
            or not self:ValidResponseDuration(p.responseDuration) or not self:CleanLootConfiguration(p.lootConfiguration or self:DefaultLootConfiguration()) then
            self:Print("This profile has invalid settings.");return false
        end
        self:RememberRaidSettings(p,name);self:Changed();return true
    end
    local council, missing = {}, {}
    for member in pairs(p.council) do
        if self.roster[member] then council[member] = true else missing[#missing + 1] = member end
    end
    local master = self:SetupMemberName(p.master) or self.me
    table.sort(missing)
    if #missing > 0 then self:Print("Skipped absent council: " .. table.concat(missing, ", ")) end
    local accepted=self:Act("profile", {responseOptions=self:CleanResponses(p.responseOptions) or self:DefaultResponses(), master = master, council = council, selfVotes = p.selfVotes == true, rules = copy(p.rules or self:DefaultVoting()), responseDuration = self:ValidResponseDuration(p.responseDuration) and p.responseDuration or 60, warningSettings=self:CleanWarningSettings(p.warningSettings) or self:DefaultWarningSettings(),lootConfiguration=self:CleanLootConfiguration(p.lootConfiguration) or self:DefaultLootConfiguration()})
    if accepted~=false then SanguineLootCouncilDB.raidSetup.profile=name end
    return accepted
end

function A:DeleteProfile(name)
    self:InitStorage()
    if self.demo or not self:CanConfigureRaid() then self:Print("Only the raid leader can manage raid profiles."); return false end
    name = profileName(name)
    if not name or not SanguineLootCouncilDB.profiles[name] then self:Print("Profile not found."); return false end
    SanguineLootCouncilDB.profiles[name] = nil
    if SanguineLootCouncilDB.raidSetup.profile==name then SanguineLootCouncilDB.raidSetup.profile=nil end
    self:Print("Deleted profile: " .. name)
    self:Changed()
    return true
end

function A:PersistSession()
    if self.demo or self.recoveryPending or not self:IsLeader() or not self.state then return end
    self:InitStorage()
    SanguineLootCouncilDB.checkpoints[self.me] = {
        protocol = self.protocol, state = copy(self.state), rev = self.rev,
        savedAt = A.Client:ServerTime(), members = copy(self.roster),
    }
end

function A:ClearCheckpoint()
    if self.demo then return end
    self:InitStorage()
    if self.me then SanguineLootCouncilDB.checkpoints[self.me] = nil end
end

function A:RecoveryAvailable()
    self:InitStorage()
    if self.demo or not self:IsLeader() or self.state then return false end
    local saved = SanguineLootCouncilDB.checkpoints[self.me]
    return saved and (saved.protocol == self.protocol or saved.protocol == 18 or saved.protocol == 17 or saved.protocol == 3 or saved.protocol == 4 or saved.protocol == 5 or saved.protocol == 6 or saved.protocol == 7 or saved.protocol == 8 or saved.protocol == 9 or saved.protocol == 10 or saved.protocol == 11 or saved.protocol == 12 or saved.protocol == 13) and type(saved.state) == "table"
        and not saved.state.groupTest and saved.state.leader == self.me and type(saved.savedAt) == "number"
        and A.Client:ServerTime() >= saved.savedAt and A.Client:ServerTime() - saved.savedAt <= 43200
end

function A:ResumeSession()
    if self.recoveryPending or self.recoveryHasNewer then
        self:Print("The saved checkpoint could be stale. Use /slt sync to retry recovery.");return false
    end
    if not self:RecoveryAvailable() then self:Print("No compatible saved session from the last 12 hours is available for this raid leader."); return false end
    local saved = SanguineLootCouncilDB.checkpoints[self.me]
    local overlap = false
    for name in pairs(saved.members or {}) do
        if name ~= self.me and self.roster[name] then overlap = true end
    end
    if not overlap then self:Print("No other member of the saved raid is present. Start a new session for this raid."); return false end
    return self:RestoreSession(saved, false)
end

function A:RestoreSession(saved, recovered)
    self.state, self.rev = copy(saved.state), saved.rev + 1
    local s = self.state
    if recovered and self.gameLeader~=nil then s.delegatedHost=self.gameLeader~=self.me or nil end
    if s.leader~=self.me then s.previousHost=s.leader end
    s.leader = self.me
    s.responseOptions=self:CleanResponses(s.responseOptions) or self:DefaultResponses()
    s.responseNextID=s.responseNextID or 6
    s.responseConfigRevision=s.responseConfigRevision or 0
    s.tradeActivity = {}
    s.corpseRoutes={}
    s.lootConfiguration=self:CleanLootConfiguration(s.lootConfiguration) or self:DefaultLootConfiguration()
    -- Resume retains rules but requires explicit re-enabling of physical automation.
    s.lootConfiguration.automatic=false;s.lootConfigRevision=(s.lootConfigRevision or 0)+1
    if recovered then s.lootConfiguration.collection=false end
    s.warningSettings=self:CleanWarningSettings(s.warningSettings) or self:DefaultWarningSettings()
    s.trackedLoot, s.lootSequences = s.trackedLoot or {}, {}
    s.autoCollect = not recovered and s.autoCollect ~= false
    for _, entry in ipairs(s.trackedLoot) do entry.verifiedHolder = false end
    s.responseDuration = self:ValidResponseDuration(s.responseDuration) and s.responseDuration or 60
    s.masterFallback = s.masterFallback or (not s.masterWasGame and s.master) or SanguineLootCouncilDB.raidSetup.master or self.me
    s.masterAutoSync = nil
    self:ApplyGameMaster()
    s.historyID = s.historyID or s.id
    s.recoveredFrom = s.id
    s.id = tostring(A.Client:ServerTime()) .. ":" .. tostring(math.random(100000, 999999)) .. ":resume"
    for name in pairs(s.council) do if not self.roster[name] then s.council[name] = nil end end
    for _, item in ipairs(s.items) do
        item.responseOptions=self:CleanResponses(item.responseOptions) or self:DefaultResponses()
        item.ballotInvalidations = item.ballotInvalidations or {}
        for _, response in pairs(item.responses) do response.revision = response.revision or 1 end
        for _, ballot in pairs(item.ballots) do
            ballot.versions = ballot.versions or {}
            for name in pairs(ballot.choices) do if item.responses[name] then ballot.versions[name] = item.responses[name].revision end end
        end
        item.responseRound = item.responseRound or 0
        item.responseDuration = item.responseDuration or 0
        item.responseDeadline = item.responseDeadline or false
        if item.status=="open" and not item.responseDeadline then
            item.responseDuration=s.responseDuration;item.responseDeadline=A.Client:ServerTime()+item.responseDuration
        end
        if not recovered and item.status~="awarded" then
            item.deadline=false
            if item.voting=="closed" then item.voting="open";item.closedResults=false end
        end
        item.noResponse = item.noResponse or {}
        item.responseMembers = item.responseMembers or copy(self.roster)
        if saved.protocol < 5 and item.status == "open" and item.voting == "idle" then self:StartBallot(item) end
        if item.status ~= "awarded" and item.voting ~= "closed" then
            for voter, ballot in pairs(item.ballots) do
                if not self.roster[voter] or (not self:IsCouncilMember(voter) and not ballot.masterVote) then item.ballots[voter] = nil
                else
                    for candidate in pairs(ballot.choices) do if not self.roster[candidate] then ballot.choices[candidate] = nil end end
                    if not ballot.abstain and not next(ballot.choices) then item.ballots[voter] = nil end
                end
            end
            item.ballotVersion = (item.ballotVersion or 0) + 1
        end
        self:Record(item)
    end
    self:Publish()
    self:Changed()
    self:Print(recovered and "Loot session recovered. Check any in-flight deliveries before re-enabling automatic loot routing."
        or "Saved session resumed. Loot, responses and valid council votes have been restored.")
    return true
end

function A:StartReadiness()
    if self.demo or not self:IsLeader() then self:Print("Only the raid leader can run a raid readiness check."); return false end
    if self.readiness and A.Client:Uptime() - self.readiness.started < 15 then self:Print("Wait 15 seconds between checks."); return false end
    local check = {id = tostring(A.Client:ServerTime()) .. ":" .. tostring(math.random(100000, 999999)), started = A.Client:Uptime(), members = {}}
    for member in pairs(self.roster) do check.members[member] = {} end
    self.readiness = check
    self:Render()
    check.members[self.me] = {version = self.version, protocol = self.protocol, popup = self.ui.popup:IsShown() == true}
    self:Send({kind = "readiness", check = check.id})
    self:ShowReadiness()
    return true
end

function A:FeaturePacket(sender, p)
    if p.kind == "readiness" then
        if sender ~= self.leader or sender == self.me or type(p.check) ~= "string" or #p.check > 80 then return true end
        if self.lastProbe and A.Client:Uptime() - self.lastProbe < 5 then return true end
        self.lastProbe = A.Client:Uptime()
        self:Render()
        self:Send({kind = "readinessReply", check = p.check, version = self.version,
            wire = self.protocol, popup = self.ui.popup:IsShown() == true}, sender)
        return true
    elseif p.kind == "readinessReply" then
        local r = self.readiness
        if not self:IsLeader() or not r or p.check ~= r.id or not r.members[sender] or A.Client:Uptime() - r.started > 60 then return true end
        if type(p.version) ~= "string" or #p.version > 40 or not p.version:match("^[%w%.%-]+$") or type(p.wire) ~= "number" or type(p.popup) ~= "boolean" then return true end
        r.members[sender] = {version = p.version, protocol = p.wire, popup = p.popup}
        self:RenderReadiness()
        return true
    end
    return false
end

-- Display choices stay per-character and are never part of raid profiles/state.
function A:DisplayPreferences()
    self:InitStorage()
    local db=SanguineLootCouncilDB
    if type(db.displayPreferences)~="table" then db.displayPreferences={} end
    local character=self.me or "local"
    if type(db.displayPreferences[character])~="table" then db.displayPreferences[character]={} end
    local prefs=db.displayPreferences[character]
    if type(prefs.lootAutoOpen)~="boolean" then
        prefs.lootAutoOpen=self:LootConfiguration().openWindow==true
    end
    return prefs
end
function A:LootWindowLayout(kind)
    local db=SanguineLootCouncilDB
    local byCharacter=db and db.displayPreferences
    local prefs=type(byCharacter)=="table" and byCharacter[self.me or "local"]
    return type(prefs)=="table" and prefs[kind.."Layout"]=="Compact" and "Compact" or "Full"
end

function A:SetLootWindowLayout(kind, mode)
    if (kind~="response" and kind~="voting" and kind~="timer") or (mode~="Full" and mode~="Compact") then return false end
    self:DisplayPreferences()[kind.."Layout"]=mode
    local u=self.ui
    if u then
        local frame=kind=="response" and u.popup or kind=="voting" and u.main or u.lootTimers.window
        local saved=self:WindowLayoutStore()[frame.sltWindowName]
        self:ResizeReadableWindow(frame,self:PreferredWindowSize(frame,saved))
        self:ClampWindowPosition(frame)
        self:SaveWindowLayout(frame,frame.sltWindowName)
        self:Render()
    end
    return true
end

function A:LootWindowAutoOpen()
    return self:DisplayPreferences().lootAutoOpen
end
function A:SetLootWindowAutoOpen(enabled)
    self:DisplayPreferences().lootAutoOpen=enabled==true
    if self.RenderSettings then self:RenderSettings() end
end
