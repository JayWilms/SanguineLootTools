local _, A = ...

local slotsByType = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
    INVTYPE_BODY = {4}, INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5},
    INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7}, INVTYPE_FEET = {8},
    INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12},
    INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15},
    INVTYPE_WEAPON = {16, 17}, INVTYPE_2HWEAPON = {16, 17},
    INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17},
    INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18},
    INVTYPE_RELIC = {18}, INVTYPE_TABARD = {19},
}
local names = {[1] = "Head", [2] = "Neck", [3] = "Shoulders", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrists", [10] = "Hands",
    [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged / relic", [19] = "Tabard"}

function A:ComparisonSlots(item)
    local d = self:ItemDetails(item)
    local slot = d.slot
    if not slotsByType[slot] and item and C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, equip = pcall(C_Item.GetItemInfoInstant, item.link)
        if ok and type(equip) == "string" then slot = equip end
    end
    return slotsByType[slot]
end

function A:EquipmentLink(link)
    if type(link) ~= "string" or #link > 500 or link:find("[%c]") then return end
    if link:match("^|c%x%x%x%x%x%x%x%x|Hitem:%d+:[^|]*|h%[[^%]]+%]|h|r$") or
        link:match("^|Hitem:%d+:[^|]*|h%[[^%]]+%]|h$") then return link end
end

-- Ask only the replying player's own client. Nil inventory results are ambiguous:
-- the slot may be empty, or the client may not have loaded its inventory yet.
function A:CaptureEquipment(item)
    local slots = self:ComparisonSlots(item)
    if not slots then return end
    local result = {}
    for _, slot in ipairs(slots) do
        local ok, link = pcall(function() return GetInventoryItemLink("player", slot) end)
        result[slot] = ok and self:EquipmentLink(link) or false
    end
    return result
end

function A:CleanEquipment(item, supplied)
    if supplied == nil then return nil, true end -- older response clients
    if type(supplied) ~= "table" then return nil, false end
    local result, count, allowed = {}, 0, {}
    local slots = self:ComparisonSlots(item)
    if slots then for _, slot in ipairs(slots) do allowed[slot] = true end end
    for slot, link in pairs(supplied) do
        count = count + 1
        if count > 2 or type(slot) ~= "number" or slot % 1 ~= 0 or not names[slot] or (slots and not allowed[slot]) then return nil, false end
        if link ~= false and not self:EquipmentLink(link) then return nil, false end
        result[slot] = link
    end
    return result, true
end

function A:SameEquipment(a, b)
    if a == nil or b == nil then return a == b end
    for slot, link in pairs(a) do if b[slot] ~= link then return false end end
    for slot, link in pairs(b) do if a[slot] ~= link then return false end end
    return true
end

function A:ComparisonRows(item, candidate)
    local response = item and item.responses[candidate or ""]
    local equipment = response and response.equipment
    local slots = self:ComparisonSlots(item)
    local rows = {}
    if not slots then return rows, "Comparison unavailable: item slot not known." end
    if not equipment then return rows, "No equipment snapshot was supplied with this response." end
    for _, slot in ipairs(slots) do
        rows[#rows + 1] = {slot = slot, label = names[slot], link = self:EquipmentLink(equipment[slot])}
    end
    return rows, "Self-reported when responding" .. (response.equipmentAt and (" at " .. date("%H:%M:%S", response.equipmentAt)) or "") .. ". Resubmit to refresh."
end

function A:AddEquipmentTooltip(tooltip, item, candidate)
    local rows, status = self:ComparisonRows(item, candidate)
    tooltip:AddLine(status, 0.8, 0.8, 0.8, true)
    for _, row in ipairs(rows) do tooltip:AddLine(row.label .. ": " .. (row.link or "Empty or unavailable"), 1, 1, 1, true) end
end

function A:RenderEquipment()
    if not self.ui then return end
    local item = self.state and self:ItemByID(self.selectedItem or 1)
    local rows, status = self:ComparisonRows(item, self.selectedCandidate)
    self.ui.equipmentStatus:SetText(status)
    for i, button in ipairs(self.ui.equipmentRows) do
        local row = rows[i]
        button.link = row and row.link
        button:SetShown(row ~= nil)
        button:SetText(row and (row.label .. ": " .. (row.link or "Empty or unavailable")) or "")
    end
end
