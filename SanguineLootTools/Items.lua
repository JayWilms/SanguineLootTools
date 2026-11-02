local _, A = ...

-- This adapter only supplies information. Responses, ballots and awards never
-- depend on its availability, and no scoring/BIS API is called.
local function call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return end
    local ok, a, b, c, d, e, f, g = A.Client:Invoke(object[method], object, ...)
    if ok then return a, b, c, d, e, f, g end
end
local function number(n)
    return type(n) == "number" and not (issecretvalue and issecretvalue(n)) and n == n and n >= 0 and n < 10000000
end
local function clean(s)
    return type(s) == "string" and s:gsub("[%c|]", " "):sub(1, 120) or nil
end

function A:ItemLibrary()
    if not LibStub then return end
    local ok, db = pcall(function() return LibStub("LibItemDB-1.0", true) end)
    if ok and db and call(db, "IsReady") == true then return db end
end

-- Verified against ItemDB-v1.8.0 Data/Forever. Resolve links through the installed
-- library; the fallback only names those same real IDs when loading is pending.
function A:ForeverDemoItems()
    local db=self:ItemLibrary()
    local result={}
    for _,v in ipairs({{279259,"Ironwood Blade"},{279265,"Azerothium Legplates"},{279266,"Robes of Fiery Devastation"},{284716,"Band of the Better Half"}}) do
        result[#result+1]={id=v[1],link=call(db,"GetLink",v[1]) or ("|cffa335ee|Hitem:"..v[1].."::::::::|h["..v[2].."]|h|r")}
    end
    return result
end

local function demoItemLink(link,id)
    if type(link)~="string" then return end
    -- ItemDB GetLink uses |Hitem:ID|h; the normal queue accepts a complete
    -- item payload with a colon after ID. Normalize only this demo adapter.
    link=link:gsub("(|Hitem:%d+)(|h)","%1:%2",1)
    if A:EquipmentLink(link) and tonumber(link:match("item:(%d+)"))==id then return link end
end
local function nativeItemLink(id)
    local getter=C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok,_,link=A.Client:Invoke(getter,id)
    if ok then return demoItemLink(link,id) end
end

-- Fixed, researched Classic Era test fixtures. Recipe/relic cases are deliberate.
function A:TestItems()
    local db,result=self:ItemLibrary(),{}
    for _,v in ipairs({
        {226486,"Gauntlets of Might"},
        {226591,"Lawbringer Gauntlets"},
        {226532,"Giantstalker's Leggings"},
        {226615,"Earthfury Gauntlets"},
        {226446,"Nightslayer Cover"},
        {226648,"Cenarion Gloves"},
        {226562,"Arcanist Crown"},
        {226572,"Gloves of Prophecy"},
        {226551,"Felheart Belt"},
        {228239,"Robe of Volatile Power"},
        {228257,"Aged Core Leather Gloves"},
        {228258,"Deep Earth Spaulders"},
        {228260,"Flameguard Gauntlets"},
        {228265,"Brutality Blade"},
        {228267,"Gutgore Ripper"},
        {228160,"Faithbringer"},
        {228519,"Striker's Mark"},
        {228262,"Crimson Shocker"},
        {229909,"Staff of Order"},
        {228142,"Earth and Fire"},
    }) do
        local id=v[1]
        local link=nativeItemLink(id) or demoItemLink(call(db,"GetLink",id),id)
            or ("|cff"..(v[3]==3 and "0070dd" or "a335ee").."|Hitem:"..id.."::::::::|h["..v[2].."]|h|r")
        result[#result+1]={id=id,link=link}
    end
    return result
end

function A:RandomDemoItems()
    local db=self:ItemLibrary()
    local iterator=call(db,"Iterate")
    local picks,seen,total={},{},0
    if type(iterator)=="function" then
        -- Reservoir sampling avoids allocating a frame/list for the whole DB.
        -- The scan is bounded even if a provider has a faulty iterator.
        for _=1,50000 do
            local ok,id,_,quality,class,_,slot=self.Client:Invoke(iterator)
            if not ok or id==nil then break end
            if number(id) and id%1==0 and id>0 and not seen[id] and number(quality) and quality>=2
                and (class==2 or class==4) and type(slot)=="string" and slot~="" then
                seen[id]=true;total=total+1
                local at=total<=4 and total or math.random(total)
                if at<=4 then picks[at]=id end
            end
        end
    end
    -- Stable Classic equipment IDs, not Forever-only examples. No invented
    -- item names/stats: the installed DB or client supplies the real link.
    local fallback={18816,18803,18805,18806,18812,18820,18821,18822,18823,18832,18842,17063,17065,17066,17069,17103,17105,17106,17107,17109,17110}
    for i=#fallback,2,-1 do local j=math.random(i);fallback[i],fallback[j]=fallback[j],fallback[i] end
    for _,id in ipairs(fallback) do
        if #picks>=4 then break end
        local duplicate=false;for _,picked in ipairs(picks) do if picked==id then duplicate=true end end
        if not duplicate then picks[#picks+1]=id end
    end
    local result={}
    for _,id in ipairs(picks) do
        local link=nativeItemLink(id) or demoItemLink(call(db,"GetLink",id),id)
        if not link then
            link="|cffffffff|Hitem:"..id.."::::::::|h[Item "..id.."]|h|r"
        end
        result[#result+1]={id=id,link=link}
    end
    return result
end

function A:RefreshDemoItems()
    if not self.demo or not self.state or (self.groupTest and not self:IsLeader()) then return false end
    local changed=false
    for _,item in ipairs(self.state.items) do
        local id=tonumber(item.link:match("item:(%d+)"))
        local link=id and nativeItemLink(id)
        if link and link~=item.link then
            item.link=link;changed=true
            local entry=self:TrackedForItem(item)
            if entry and entry.demo then entry.link=link end
        end
    end
    for _,entry in ipairs(self.state.trackedLoot or {}) do
        if entry.demo then
            local id=tonumber(entry.link:match("item:(%d+)"))
            local link=id and nativeItemLink(id)
            if link and entry.link~=link then entry.link=link;changed=true end
        end
    end
    return changed
end

function A:ItemDetails(item)
    local id = item and type(item.link) == "string" and tonumber(item.link:match("item:(%d+)"))
    local data = {id = id}
    local db = self:ItemLibrary()
    if id and db and call(db, "HasItem", id) == true then
        local name, quality, classID, subClassID, slot, level, required = call(db, "GetInfo", id)
        data.name, data.quality, data.slot = clean(name), quality, clean(slot)
        data.level, data.required = number(level) and level or nil, number(required) and required or nil
        data.kind = clean(call(db, "GetItemType", id))
        data.db, data.known = db, number(classID) and number(subClassID)
    end
    return data
end

function A:ItemSummary(item)
    local d, parts = self:ItemDetails(item), {}
    if d.kind then parts[#parts + 1] = d.kind end
    local slots={INVTYPE_HEAD="Head",INVTYPE_NECK="Neck",INVTYPE_SHOULDER="Shoulders",INVTYPE_BODY="Shirt",
        INVTYPE_CHEST="Chest",INVTYPE_ROBE="Chest",INVTYPE_WAIST="Waist",INVTYPE_LEGS="Legs",INVTYPE_FEET="Feet",
        INVTYPE_WRIST="Wrists",INVTYPE_HAND="Hands",INVTYPE_FINGER="Finger",INVTYPE_TRINKET="Trinket",
        INVTYPE_CLOAK="Back",INVTYPE_WEAPON="One-Hand",INVTYPE_2HWEAPON="Two-Hand",INVTYPE_WEAPONMAINHAND="Main Hand",
        INVTYPE_WEAPONOFFHAND="Off Hand",INVTYPE_SHIELD="Off Hand",INVTYPE_HOLDABLE="Held In Off-hand",
        INVTYPE_RANGED="Ranged",INVTYPE_RANGEDRIGHT="Ranged",INVTYPE_THROWN="Thrown",INVTYPE_RELIC="Relic",INVTYPE_TABARD="Tabard"}
    if slots[d.slot] then parts[#parts+1]=clean(_G[d.slot]) or slots[d.slot] end
    if d.level and d.level>0 then parts[#parts + 1] = "Item level " .. d.level end
    if d.required and d.required>0 then parts[#parts + 1] = "Requires level " .. d.required end
    if not d.known then parts[#parts+1]="Item details unavailable" end
    return table.concat(parts, " | ")
end

function A:ItemIcon(item)
    local id = item and type(item.link) == "string" and tonumber(item.link:match("item:(%d+)"))
    if id and C_Item and type(C_Item.GetItemIconByID) == "function" then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        if ok and number(icon) and icon > 0 then return icon end
    end
    return 134400 -- question mark while the client has no icon
end

-- This filter is only class tags and armour/weapon proficiency. Required item
-- level, faction/race and preference remain notices, never inferred BIS choices.
function A:ClassEligibility(item,name)
    local details=self:ItemDetails(item)
    if not details.known then return "Unknown","Item class information is unavailable." end
    local unit=name and self.roster[name] or "player"
    if type(unit)~="string" then return "Unknown","Raider class information is unavailable." end
    local ok,_,_,classID=self.Client:Call("UnitClass",unit)
    local levelOK,level=self.Client:Call("UnitLevel",unit)
    if not ok or not number(classID) or classID<1 or classID%1~=0
        or not levelOK or not number(level) or level<1 then
        return "Unknown","Your class or level is unavailable."
    end
    local proficiency=details.db.PROFICIENCY
    if type(proficiency)=="table" and type(proficiency.armorCap)=="table" and not proficiency.armorCap[classID] then
        return "Unknown","Your class is not covered by the item database."
    end
    local usable=call(details.db,"CanUse",details.id,classID,level)
    if usable==false then return "Restricted","Your class cannot use this item type or class-restricted item." end
    if usable~=true then return "Unknown","Class usability could not be checked." end
    return "Eligible","Usable by your class according to item database rules."
end

function A:ItemEligibility(item, name)
    local d = self:ItemDetails(item)
    if not d.known then return "Unknown", "No database entry available." end
    local unit = self.roster[name]
    if type(unit) ~= "string" or type(UnitClass) ~= "function" or type(UnitLevel) ~= "function" then
        return "Unknown", "Raider class or level unavailable."
    end
    local ok, _, _, classID = pcall(UnitClass, unit)
    local levelOK, level = pcall(UnitLevel, unit)
    if not ok or not number(classID) or classID < 1 or not levelOK or not number(level) or level < 1 then
        return "Unknown", "Raider class or level unavailable."
    end
    local usable = call(d.db, "CanUse", d.id, classID, level)
    local reasons, incomplete = {}, usable ~= true and usable ~= false
    if usable == false then reasons[#reasons + 1] = "Class restriction or armour/weapon proficiency." end
    if d.required == nil then incomplete = true
    elseif level < d.required then reasons[#reasons + 1] = "Requires level " .. d.required .. "; raider is " .. level .. "." end
    local factionOK, faction
    if type(d.db.GetItemFaction) == "function" then factionOK, faction = pcall(d.db.GetItemFaction, d.db, d.id) end
    if not factionOK then incomplete = true end
    if factionOK and faction then
        local factionOK, own = pcall(function() return UnitFactionGroup(unit) end)
        if not factionOK or (own ~= "Horde" and own ~= "Alliance") then incomplete = true
        elseif own ~= faction then reasons[#reasons + 1] = "Restricted to " .. clean(faction) .. "." end
    end
    if type(d.db.GetItemRaces) ~= "function" then incomplete = true
    else
        local maskOK, mask = pcall(d.db.GetItemRaces, d.db, d.id)
        if not maskOK then incomplete = true
        elseif mask then
            local raceOK, _, _, raceID = pcall(function() return UnitRace(unit) end)
            if not raceOK or not number(raceID) or raceID < 1 then incomplete = true
            else
                local raceUsable = call(d.db, "RaceUsable", d.id, raceID)
                if raceUsable == false then reasons[#reasons + 1] = "Race restriction."
                elseif raceUsable ~= true then incomplete = true end
            end
        end
    end
    if #reasons > 0 then return "Restricted", table.concat(reasons, " ") end
    if incomplete then return "Unknown", "Some eligibility information is unavailable." end
    return "Eligible", "Passes database class, level, faction and race checks; learned skills and other requirements are unverified."
end

function A:EligibilityText(item, name)
    local status, reason = self:ItemEligibility(item, name)
    return status .. ": " .. reason
end

function A:AwardEligibilityNotice(item, name)
    local status, reason = self:ItemEligibility(item, name)
    return "\n\n" .. (status == "Restricted" and "WARNING - " or "") .. status .. ": " .. reason
end

function A:AddItemFacts(tooltip, item)
    tooltip:AddLine(self:ItemSummary(item), 1, 1, 1, true)
    local d = self:ItemDetails(item)
    local stats = d.known and call(d.db, "GetStats", d.id)
    if type(stats) ~= "table" then return end
    local keys = {}
    for key, value in pairs(stats) do
        if type(key) == "string" and number(value) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for i = 1, math.min(#keys, 16) do
        local key = keys[i]
        tooltip:AddLine((clean(_G[key]) or clean(key)) .. ": " .. stats[key], 1, 1, 1, true)
    end
end

-- Populate only disposable tracking; nothing enters Responses before Queue.
function A:SeedTestLoot()
    if not self.demo or not self.state or not self:IsMaster() then return end
    for _,sample in ipairs(self:TestItems()) do
        if self:EquipmentLink(sample.link) then
        local id=self:NextIdentity("tracked")
        self.state.trackedLoot[#self.state.trackedLoot+1]={id=id,guid="Demo-"..self.state.id.."-copy-"..id,
            link=sample.link,holder=self.state.master,demo=true,kind="timed",seconds=7200,maxSeconds=7200,
            observedAt=self.Client:ServerTime(),verifiedHolder=true,deliveryRevision=0,deliveryLog={}}
        end
    end
end

function A:SeedSoloTestResponses(item)
    if not self:IsSoloTest() then return end
    local first=6
    for _,v in ipairs(self:ResponseOptions(item)) do if v.id~=6 and v.enabled then first=v.id;break end end
    local off=self:ResponseOption(4,item)
    self:ApplyResponse(item,"Warrior-Test",first,"Sample chosen response")
    self:ApplyResponse(item,"Priest-Test",off and off.enabled and 4 or 6,"Sample chosen response")
end
