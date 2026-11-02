local _, A = ...
-- Target calls resolve at use time: a missing API stays missing in fixtures.
local C={fixtureVersion="slc-client-contract-1"}
A.Client=C
local unpack=unpack or table.unpack
local function pack(...) return {n=select("#",...),...} end
local providers={
    GetBuildInfo=function() return GetBuildInfo end,
    GetAddOnMetadata=function() return (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata end,
    GetServerTime=function() return GetServerTime end,
    GetTime=function() return GetTime end,
    InCombatLockdown=function() return InCombatLockdown end,
    IsInRaid=function() return IsInRaid end,
    IsInGroup=function() return IsInGroup end,
    GetNumGroupMembers=function() return GetNumGroupMembers end,
    UnitFullName=function() return UnitFullName end,
    GetNormalizedRealmName=function() return GetNormalizedRealmName end,
    UnitIsGroupLeader=function() return UnitIsGroupLeader end,
    UnitIsConnected=function() return UnitIsConnected end,
    UnitClass=function() return UnitClass end,
    UnitLevel=function() return UnitLevel end,
    UnitRace=function() return UnitRace end,
    UnitFactionGroup=function() return UnitFactionGroup end,
    GetInventoryItemLink=function() return GetInventoryItemLink end,
    GetLootMethod=function() return GetLootMethod end,
    ["C_PartyInfo.GetLootMethod"]=function() return C_PartyInfo and C_PartyInfo.GetLootMethod end,
    ["C_ChatInfo.SendAddonMessage"]=function() return C_ChatInfo and C_ChatInfo.SendAddonMessage end,
    ["C_ChatInfo.RegisterAddonMessagePrefix"]=function() return C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix end,
    ["C_Container.GetContainerNumSlots"]=function() return C_Container and C_Container.GetContainerNumSlots end,
    ["C_Container.GetContainerItemInfo"]=function() return C_Container and C_Container.GetContainerItemInfo end,
    ["C_Container.PickupContainerItem"]=function() return C_Container and C_Container.PickupContainerItem end,
    ["C_Item.GetItemGUID"]=function() return C_Item and C_Item.GetItemGUID end,
    ["C_Item.IsBound"]=function() return C_Item and C_Item.IsBound end,
    ["C_Item.GetItemInfoInstant"]=function() return C_Item and C_Item.GetItemInfoInstant end,
    ["C_Item.GetItemIconByID"]=function() return C_Item and C_Item.GetItemIconByID end,
    ["C_TooltipInfo.GetBagItem"]=function() return C_TooltipInfo and C_TooltipInfo.GetBagItem end,
    ["ItemLocation.CreateFromBagAndSlot"]=function() return ItemLocation and ItemLocation.CreateFromBagAndSlot end,
    ["C_Timer.After"]=function() return C_Timer and C_Timer.After end,
    InitiateTrade=function() return InitiateTrade end,
    ClickTradeButton=function() return ClickTradeButton end,
    GetTradePlayerItemLink=function() return GetTradePlayerItemLink end,
    GetTradePlayerItemInfo=function() return GetTradePlayerItemInfo end,
    GetCursorInfo=function() return GetCursorInfo end,
    CheckInteractDistance=function() return CheckInteractDistance end,
    ClearCursor=function() return ClearCursor end,
    CursorHasItem=function() return CursorHasItem end,
    LibStub=function() return LibStub end,
}
function C:Get(name)
    local getter=providers[name]
    return getter and getter()
end
function C:Invoke(fn,...)
    if type(fn)~="function" then return false,nil end
    local result=pack(pcall(fn,...))
    if not result[1] then return false,nil end -- raw API error text can contain identifiers
    for i=2,result.n do if type(issecretvalue)=="function" and issecretvalue(result[i]) then return false,nil end end
    return unpack(result,1,result.n)
end
function C:Call(name,...) return self:Invoke(self:Get(name),...) end
function C:ClockReady()
    local ok,wall=self:Call("GetServerTime")
    local good,uptime=self:Call("GetTime")
    return ok and good and type(wall)=="number" and wall==wall and wall>=0 and wall<math.huge
        and type(uptime)=="number" and uptime==uptime and uptime>=0 and uptime<math.huge
end
function C:ServerTime()
    local ok,value=self:Call("GetServerTime")
    return ok and type(value)=="number" and value==value and value>=0 and value<math.huge and value or 0
end
function C:Uptime()
    local ok,value=self:Call("GetTime")
    return ok and type(value)=="number" and value==value and value>=0 and value<math.huge and value or 0
end
function C:Combat()
    local ok,value=self:Call("InCombatLockdown")
    return not ok or (value~=false and value~=nil) -- nil out-of-combat is a legacy shape; a missing function is not
end
function C:InRaid()
    local ok,value=self:Call("IsInRaid")
    return ok and (value==true or value==1)
end
function C:InGroup()
    if self:InRaid() then return true end
    local ok,value=self:Call("IsInGroup")
    return ok and (value==true or value==1)
end
function C:APIInventory()
    local result={}
    for name in pairs(providers) do result[#result+1]={name=name,available=type(self:Get(name))=="function" or (name=="LibStub" and self:Get(name)~=nil)} end
    table.sort(result,function(a,b) return a.name<b.name end)
    return result
end
