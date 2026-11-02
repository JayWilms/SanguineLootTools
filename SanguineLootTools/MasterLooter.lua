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
            if type(raidID) == "number" and raidID % 1 == 0 and raidID >= 1 and raidID <= 40 then unit = "raid" .. raidID
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
    if not s.masterAutoSync or self.demo then return s.master, "manual", false, false end
    local name, status = self:ReadGameMaster()
    if name then return name, "game", false, true end
    local blocked = status == "pending" or status == "restricted" or (status == "unavailable" and (s.masterWasGame == true or s.masterBlocked == true))
    local wasGame = status == "pending" or ((status == "unavailable" or status == "restricted") and s.masterWasGame == true)
    return s.master, status, blocked, wasGame
end

function A:ApplyGameMaster()
    local s = self.state
    s.master, s.masterSource, s.masterBlocked, s.masterWasGame = self:GameMasterState()
end

function A:SyncGameMaster()
    if self.demo or not self:IsLeader() or not self.state or not self.state.masterAutoSync then
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
