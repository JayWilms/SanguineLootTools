local _, A = ...

local function number(n)
    return type(n) == "number" and not (issecretvalue and issecretvalue(n)) and n == n and n >= 0 and n < 10000000
end
local function clean(s)
    return type(s) == "string" and s:gsub("[%c|]", " "):sub(1, 120) or nil
end

local function nativeItemLink(id)
    local ok, _, link = A.Client:Call("C_Item.GetItemInfo", id)
    if ok and A:EquipmentLink(link) and tonumber(link:match("item:(%d+)")) == id then return link end
end

-- Fixed samples checked against a Forever 16001 client item dump.
-- Include equipment, a relic and profession recipes to exercise different eligibility cases.
function A:TestItems()
    local result = {}
    for _,v in ipairs({
        {279259,"Ironwood Blade"},
        {279265,"Azerothium Legplates"},
        {279266,"Robes of Fiery Devastation"},
        {284716,"Band of the Better Half"},
        {279246,"Torch of Light"},
        {279247,"Steadfast Libram"},
        {279252,"Elderwild Waistcord"},
        {279255,"Eternity Pauldrons"},
        {279260,"Forest Defender's Axe"},
        {279262,"Evergreen Shield"},
        {279269,"Fel Cape"},
        {279273,"Hyper Deluxe Sniper Rifle Mk XVII"},
        {279308,"Plans: Ironwood Blade"},
        {279301,"Pattern: Elderwild Waistcord"},
        {279295,"Formula: Torch of Light"},
        {279315,"Pattern: Robes of Fiery Devastation"},
        {281586,"Elderwild Construction Hammer",3},
        {281636,"Museum Keeper's Chain",3},
        {281637,"Antique Bulwark",3},
        {282007,"Emerald Watcher's Dreamstaff",3},
        {284253,"Eternally Frozen Band",3},
        {284257,"Icesworn Decapitator",3},
        {284261,"Magically Fortified Legguards",3},
    }) do
        local id=v[1]
        local link=nativeItemLink(id)
            or ("|cff"..(v[3]==3 and "0070dd" or "a335ee").."|Hitem:"..id.."::::::::|h["..v[2].."]|h|r")
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

-- Forever launch-client proficiencies by class ID. These are class capabilities,
-- independent of the character's current level and learned weapon skills.
local armorCaps = {4, 4, 3, 2, 1, nil, 3, 1, 1, nil, 2}
local shieldClasses = {[1]=true, [2]=true, [7]=true}
local weaponsByClass = {
    [1] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18},
    [2] = {0, 1, 4, 5, 6, 7, 8},
    [3] = {0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18},
    [4] = {0, 2, 3, 4, 7, 13, 15, 16, 18},
    [5] = {4, 10, 15, 19},
    [7] = {0, 1, 4, 5, 10, 13, 15},
    [8] = {7, 10, 15, 19},
    [9] = {7, 10, 15, 19},
    [11] = {4, 5, 6, 10, 13, 15},
}
local knownWeapons = {}
for _, subclasses in pairs(weaponsByClass) do
    for _, subclass in ipairs(subclasses) do knownWeapons[subclass] = true end
end

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

-- The tooltip's allowed-class text is shared information. Its usability flags
-- describe the viewing player, so they are never used to auto-pass raid members.
local function allowedClasses(label)
    if type(ITEM_CLASSES_ALLOWED) ~= "string" then return end
    local prefix, suffix = ITEM_CLASSES_ALLOWED:match("^(.-)%%s(.*)$")
    if not prefix or label:sub(1,#prefix) ~= prefix then return end
    if suffix ~= "" and label:sub(-#suffix) ~= suffix then return end
    local names = label:sub(#prefix+1, #label-#suffix):gsub("，", ","):gsub("、", ",")
    for _, format in ipairs({LIST_DELIMITER or "", PLAYER_LIST_DELIMITER or ""}) do
        local separator = format:match("^%%s(.-)%%s$")
        if separator and separator ~= "" then
            names = names:gsub(separator:gsub("(%W)", "%%%1"), ",")
        end
    end
    local classes = {}
    for entry in names:gmatch("[^,]+") do
        local name = entry:match("^%s*(.-)%s*$")
        local class
        for _, localized in ipairs({LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {}}) do
            for token, display in pairs(localized) do
                if display == name then class = token; break end
            end
            if class then break end
        end
        if not class then return nil, true end
        classes[class] = true
    end
    if next(classes) then return classes, true end
    return nil, true
end

local function readRestrictions(data, lines)
    local enums = Enum or {}
    local lineTypes = enums.TooltipDataLineType or {}
    local requirements = enums.TooltipDataUsageRequirementType or {}
    local raceClass = requirements.RaceClass
    for _, line in ipairs(lines) do
        if not readable(line) or type(line) ~= "table" then
            data.restrictionsUnknown = true
        else
            local label = line.leftText
            local hasClassList
            if not readable(label) then
                data.restrictionsUnknown = true
            elseif type(label) == "string" then
                local classes
                classes, hasClassList = allowedClasses(label)
                if classes then data.classes = classes
                elseif hasClassList then data.restrictionsUnknown = true end
            end
            if raceClass and readable(line.type) and readable(line.requirementType)
                and line.type == lineTypes.UsageRequirement and line.requirementType == raceClass then
                if not hasClassList then data.restrictionsUnknown = true end
                if readable(line.usable) and line.usable == false then data.localRestriction = true end
            end
        end
    end
end

-- Session rows are short-lived. Keep successful reads for their current link
-- and let the existing response tick retry items the client has yet to cache.
local itemDetails = setmetatable({}, {__mode="k"})
function A:ItemDetails(item)
    if not item or type(item.link) ~= "string" then return {} end
    local cached = itemDetails[item]
    if cached and cached.link == item.link then return cached end

    local id = tonumber(item.link:match("item:(%d+)"))
    local data = {id=id, link=item.link}
    if not id then return data end
    local ok, name, _, quality, level, required, kind, _, _, slot, _, _, classID, subclassID =
        self.Client:Call("C_Item.GetItemInfo", item.link)
    if not ok or type(name) ~= "string" or name == "" then return data end
    data.name, data.quality, data.slot, data.kind = clean(name), quality, clean(slot), clean(kind)
    data.level = number(level) and level or nil
    data.required = number(required) and required or nil
    data.classID, data.subclassID = classID, subclassID
    data.known = number(classID) and number(subclassID)
    local tooltipOK, tooltip = self.Client:Call("C_TooltipInfo.GetHyperlink", item.link)
    if tooltipOK and type(tooltip) == "table" and readable(tooltip.lines)
        and type(tooltip.lines) == "table" and #tooltip.lines > 0 then
        data.tooltipReady = true
        readRestrictions(data, tooltip.lines)
    end
    if data.known and data.tooltipReady and not data.restrictionsUnknown then itemDetails[item] = data end
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

function A:ClassEligibility(item, name, details)
    local unit = name == nil and "player" or self.roster[name]
    if type(unit) ~= "string" then return "Unknown", "Raider class information is unavailable." end
    local ok, _, class, classID = self.Client:Call("UnitClass", unit)
    if not ok or not number(classID) or not armorCaps[classID] or type(class) ~= "string" then
        return "Unknown", "Raider class information is unavailable."
    end
    local data = details or self:ItemDetails(item)
    if not data.known or not data.tooltipReady then return "Unknown", "Item restrictions are unavailable." end
    if data.classes and not data.classes[class] then
        return "Restricted", "The item lists other classes."
    end
    if data.classID == 4 then
        local subclass = data.subclassID
        local isArmor = subclass >= 1 and subclass <= 4 and data.slot and data.slot ~= "" and data.slot ~= "INVTYPE_CLOAK"
        if (isArmor and subclass > armorCaps[classID]) or (subclass == 6 and not shieldClasses[classID]) then
            return "Restricted", "This class cannot wear this armour type."
        end
    elseif data.classID == 2 and knownWeapons[data.subclassID] then
        local canUse = false
        for _, subclass in ipairs(weaponsByClass[classID]) do
            if subclass == data.subclassID then canUse = true; break end
        end
        if not canUse then return "Restricted", "This class cannot use this weapon type." end
    end
    if data.restrictionsUnknown then return "Unknown", "Some item restrictions could not be resolved." end
    return "Eligible", "No class restriction found."
end

function A:ItemEligibility(item, name)
    local unit = name == nil and "player" or self.roster[name]
    local data = self:ItemDetails(item)
    local status, reason = self:ClassEligibility(item, name, data)
    if status == "Restricted" then return status, reason end
    if type(unit) ~= "string" then return status, reason end
    local ok, level = self.Client:Call("UnitLevel", unit)
    if data.required and ok and number(level) and level > 0 and level < data.required then
        return "Restricted", "Requires level " .. data.required .. "; raider is " .. level .. "."
    end
    if (not name or name == self.me) and data.localRestriction then
        return "Restricted", "The game tooltip reports a race or class requirement."
    end
    if status == "Unknown" then return status, reason end
    return status, "No class restriction found. Check the tooltip for other requirements."
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
