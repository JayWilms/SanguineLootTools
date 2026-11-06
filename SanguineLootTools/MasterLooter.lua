local _, A = ...

local function protected(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

-- Namespaced modern API first; older clients may expose the global function instead.
function A:ReadGameMaster()
    local providers = {}
    if C_PartyInfo and type(C_PartyInfo.GetLootMethod) == "function" then providers[#providers + 1] = C_PartyInfo.GetLootMethod end
    if type(GetLootMethod) == "function" then providers[#providers + 1] = GetLootMethod end
    for _, getter in ipairs(providers) do
        local ok, name, status = pcall(function()
            local method, partyID, raidID = getter()
            if protected(method) or protected(partyID) or protected(raidID) then return nil, "restricted" end
            if method == nil then return nil, "unavailable" end
            local enum = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter
            local master = method == "master" or (enum ~= nil and method == enum)
            if not master then
                local nonMaster = {freeforall = true, roundrobin = true, group = true, needbeforegreed = true, personalloot = true}
                if (type(method) == "string" and nonMaster[method]) or (type(method) == "number" and enum ~= nil and method % 1 == 0 and method >= 0 and method <= 5) then return nil, "none" end
                return nil, "unavailable"
            end
            local unit
            if self.Client:InRaid() then
                if type(raidID) == "number" and raidID % 1 == 0 and raidID >= 1 and raidID <= 40 then unit = "raid" .. raidID end
            elseif partyID == 0 then unit = "player"
            elseif type(partyID) == "number" and partyID % 1 == 0 and partyID >= 1 and partyID <= 4 then unit = "party" .. partyID end
            if not unit then return nil, "pending" end
            local resolved, full = pcall(self.Name, self, unit)
            if not resolved or protected(full) or not full or not self.roster[full] then return nil, "pending" end
            return full, "game"
        end)
        if ok and status ~= "unavailable" then return name, status end
    end
    return nil, "unavailable"
end

function A:GameMasterState()
    local s = self.state
    local fallback = s.masterFallback or s.master
    if not self.roster[fallback] then fallback = s.leader end
    if self.demo then return fallback, "manual", false, false end
    local name, status = self:ReadGameMaster()
    if name then return name, "game", false, true end
    local blocked = status == "pending" or status == "restricted" or (status == "unavailable" and (s.masterWasGame == true or s.masterBlocked == true))
    local wasGame = status == "pending" or ((status == "unavailable" or status == "restricted") and s.masterWasGame == true)
    return blocked and s.master or fallback, status, blocked, wasGame
end

function A:ApplyGameMaster()
    local s = self.state
    local previous = s.master
    s.master, s.masterSource, s.masterBlocked, s.masterWasGame = self:GameMasterState()
    if s.master ~= previous then
        self:CancelPreparedCorpseRoutes()
        for _, item in ipairs(s.items) do
            if item.voting ~= "idle" then item.ballotVersion = (item.ballotVersion or 0) + 1 end
        end
    end
end

local handoffHelp = "Change the Master Looter from WoW’s Loot Method menu."

function A:CheckMasterHandoff()
    local pending = self.masterHandoff
    if not pending then return end
    if pending.sid ~= (self.state and self.state.id) or not self:IsLeader() or self.demo then
        self.masterHandoff = nil
        return
    end
    if not pending.target then return end
    local actual, status = self:ReadGameMaster()
    if actual == pending.target then
        self.masterHandoff = nil
    elseif status == "none" or not self.roster[pending.target] or self.Client:Uptime() >= pending.deadline then
        self.masterHandoff = {sid=pending.sid, message="WoW did not confirm the handoff. "..handoffHelp}
    end
end

function A:RequestMasterHandoff(target)
    if not self:IsLeader() or not self.roster[target] or self.demo then
        return false, "Only the raid leader can hand off Master Loot to a current member."
    end
    local sid = self.state and self.state.id
    if self.masterHandoff and self.masterHandoff.sid == sid and self.masterHandoff.target then
        return false, "A Master Looter handoff is already awaiting confirmation."
    end
    local method = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter
    local gotName, name = self.Client:Call("GetUnitName", self.roster[target], true)
    if method == nil or not gotName or type(name) ~= "string" or name == "" or self.Client:Combat() then
        self.masterHandoff = {sid=sid, message=handoffHelp}
        return false, handoffHelp
    end
    self.masterHandoff = {sid=sid, target=target, deadline=self.Client:Uptime()+5}
    local ok, accepted = self.Client:Call("C_PartyInfo.SetLootMethod", method, name)
    if not ok or accepted == false then
        local message = "WoW declined the handoff. "..handoffHelp
        self.masterHandoff = {sid=sid, message=message}
        return false, message
    end
    self:CheckMasterHandoff()
    return true
end

function A:SyncGameMaster()
    if self.recoveryPending then return end
    self:CheckMasterHandoff()
    if self.demo or not self:IsLeader() or not self.state then
        if self.RenderMasterSettings then self:RenderMasterSettings() end
        return
    end
    local master, source, blocked, wasGame = self:GameMasterState()
    local s = self.state
    if master ~= s.master or source ~= s.masterSource or blocked ~= s.masterBlocked or wasGame ~= s.masterWasGame then
        self:HostRequest(self.me, {op = "syncMaster", sid = s.id})
    end
    if self.RenderMasterSettings then self:RenderMasterSettings() end
end
