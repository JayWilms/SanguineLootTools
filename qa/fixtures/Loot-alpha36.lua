local _, A = ...

local function plain(value)
    return not issecretvalue or not issecretvalue(value)
end
local function integer(value, low, high)
    return plain(value) and type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end
local function invoke(object, method, ...)
    if not object or type(object[method]) ~= "function" then return end
    local ok, value = A.Client:Invoke(object[method], ...)
    if ok and plain(value) then return value end
end
local function pattern(text)
    return text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- Interpret localized Blizzard duration formats, not English-only tooltip text.
function A:DurationSeconds(text)
    if not plain(text) or type(text) ~= "string" or #text > 1000 then return end
    local total, found = 0, false
    for _, unit in ipairs({{INT_SPELL_DURATION_HOURS, 3600}, {INT_SPELL_DURATION_MIN, 60}, {INT_SPELL_DURATION_SEC, 1}}) do
        local fmt = unit[1]
        if type(fmt) == "string" then
            local prefix, suffix = fmt:match("^(.-)%%d(.*)$")
            if prefix then
                local variants = {}
                local before, forms, after = suffix:match("^(.-)|4(.-);(.*)$")
                if forms then for form in forms:gmatch("[^:]+") do variants[#variants + 1] = before .. form .. after end
                else variants[1] = suffix end
                for _, ending in ipairs(variants) do
                    local value = text:match(pattern(prefix) .. "(%d+)" .. pattern(ending))
                    if value then total, found = total + tonumber(value) * unit[2], true; break end
                end
            end
        end
    end
    if found and integer(total, 0, 604800) then return total end
end

function A:ReadTradeTimer(bag, slot, location)
    local data = invoke(C_TooltipInfo, "GetBagItem", bag, slot)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        if invoke(C_Item,"IsBound",location)==false then return "unbound" end
        return "unknown"
    end
    local tradeType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.TradeTimeRemaining
    local format = BIND_TRADE_TIME_REMAINING
    if type(format) == "string" then format = format:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    local prefix, suffix
    if type(format) == "string" then prefix, suffix = format:match("^(.-)%%s(.*)$") end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if plain(text) and type(text) == "string" then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local content
            if prefix then content = text:match("^" .. pattern(prefix) .. "(.-)" .. pattern(suffix) .. "$") end
            if not content and tradeType and plain(line.type) and line.type == tradeType then content = text end
            if content then
                local seconds = self:DurationSeconds(content)
                if seconds ~= nil then return "timed", seconds end
                return "unknown" -- recognized timer, unsupported duration text
            end
        end
    end
    if invoke(C_Item, "IsBound", location) == false then return "unbound" end
    return "unknown" -- no text is not proof that the item expired
end

-- Read only carried bags. A link is never sufficient evidence of a particular copy.
function A:ReadManualBagItem(bag,slot)
    if not integer(bag,0,math.min(NUM_BAG_SLOTS or 4,5)) or not integer(slot,1,100)
        or not C_Container or not C_Item or not ItemLocation then return end
    local info=invoke(C_Container,"GetContainerItemInfo",bag,slot)
    if type(info)~="table" or not plain(info) or not plain(info.hyperlink) or not plain(info.stackCount) or not plain(info.isLocked) then return end
    local link=self:EquipmentLink(info.hyperlink)
    if not link or info.isLocked or (info.stackCount~=nil and info.stackCount~=1) then return end
    local ok,location=pcall(function() return ItemLocation:CreateFromBagAndSlot(bag,slot) end)
    local guid=ok and invoke(C_Item,"GetItemGUID",location)
    if type(guid)~="string" or #guid>100 or not guid:match("^Item%-[%w%-]+$") then return end
    local kind,seconds=self:ReadTradeTimer(bag,slot,location)
    return {guid=guid,link=link,kind=kind,seconds=seconds,sampledAt=A.Client:ServerTime()}
end

function A:FindManualBagItem(link,guid)
    if not C_Container then return nil,"Bag APIs unavailable. Reopen your bags and try again." end
    local found
    for bag=0,math.min(NUM_BAG_SLOTS or 4,5) do
        local count=invoke(C_Container,"GetContainerNumSlots",bag)
        if not integer(count,0,100) then return nil,"Bag information is unavailable. Try again." end
        for slot=1,count do
            local sample=self:ReadManualBagItem(bag,slot)
            if sample and sample.link==link and (not guid or sample.guid==guid) then
                if found and found.guid~=sample.guid then return nil,"More than one matching copy is in your bags. Shift-click the exact copy to add." end
                found=sample
            end
        end
    end
    if not found then return nil,"That item copy is unavailable in your carried bags. Split stacks into single items and Shift-click an unlocked bag item again." end
    return found
end

function A:TrackedByGUID(guid)
    for _, entry in ipairs(self.state and self.state.trackedLoot or {}) do if entry.guid == guid then return entry end end
end

function A:TrackedForItem(item)
    return item and item.lootGUID and self:TrackedByGUID(item.lootGUID)
end

function A:ReduceLoot(sender, p)
    local s = self.state
    s.trackedLoot = s.trackedLoot or {}
    if p.op=="tradeReceipt" then
        local entry=integer(p.tracked,1,self.limits.maxID) and self:TrackedByID(p.tracked)
        local item=entry and entry.item and self:ItemByID(entry.item)
        if entry and entry.manual then return false,"Manual loot has no verified bag copy; confirm delivery through Manage." end
        if not entry or p.guid~=entry.guid or type(p.token)~="string" or #p.token>80 or not p.token:match("^%d+:%d+:%d+$")
            or not integer(p.expectedRevision,0,1000) or not integer(p.expectedAwardRevision,1,1000)
            or not integer(p.completedAt,A.Client:ServerTime()-86400,A.Client:ServerTime()+5) then return false,"Invalid completed-trade receipt." end
        if not item or item.status~="awarded" or item.winner~=p.expectedWinner or (item.awardRevision or 1)~=p.expectedAwardRevision then return false,"The award changed before delivery was recorded." end
        -- A lost acknowledgement can cause a retry. Never duplicate delivery logs.
        if entry.delivery=="delivered" and entry.deliveryToken==p.token and entry.deliveredBy==sender
            and entry.deliveredTo==p.expectedWinner and entry.deliveryMethod=="automatic" and entry.deliveryRevision==p.expectedRevision+1 then return true end
        if sender~=entry.holder or sender==item.winner or entry.delivery=="delivered" or p.expectedRevision~=entry.deliveryRevision then return false,"The recorded holder or delivery changed." end
        if #entry.deliveryLog>=25 then return false,"Delivery log is full; review this item manually." end
        entry.deliveryLog[#entry.deliveryLog+1]={action="delivered",method="automatic",evidence="trade_complete",token=p.token,
            from=entry.holder,to=item.winner,by=sender,time=p.completedAt}
        entry.delivery,entry.deliveredTo,entry.deliveredAt,entry.deliveredBy="delivered",item.winner,p.completedAt,sender
        entry.deliveryMethod,entry.deliveryToken="automatic",p.token
        entry.holder,entry.kind,entry.seconds,entry.verifiedHolder=item.winner,"unknown",nil,false
        entry.deliveryRevision=entry.deliveryRevision+1
        self:CopyDeliveryToItem(entry)
        return true
    end
    if p.op == "tradeActivity" then
        if not integer(p.seq, 1, 1000000000) or type(p.active) ~= "boolean" then return false, "Invalid trade activity." end
        s.tradeActivity = s.tradeActivity or {}
        local previous = s.tradeActivity[sender]
        if previous and p.seq <= previous.seq then return false, "Old trade activity." end
        local partner = p.active and self:Resolve(p.partner)
        if p.active then
            local held = false
            for _, entry in ipairs(s.trackedLoot) do
                local item = entry.item and self:ItemByID(entry.item)
                if entry.holder == sender and item and item.status == "awarded" and item.winner == partner and entry.delivery ~= "delivered" then held = true end
            end
            if not partner or not held then return false, "No pending award for this trade partner." end
        end
        s.tradeActivity[sender] = {seq = p.seq, active = p.active, partner = partner or nil, time = A.Client:ServerTime()}
        return true
    elseif p.op == "autoCollect" then
        if sender ~= self.leader then return false, "Only the raid leader controls automatic loot collection." end
        s.autoCollect = not s.autoCollect
        local config=self:LootConfiguration();config.collection=s.autoCollect;s.lootConfiguration=config
        if not self.demo then SanguineLootCouncilDB.lootConfiguration=self.Copy(config) end
        return true
    elseif p.op == "lootReport" then
        if not integer(p.seq, 1, 1000000000) or type(p.entries) ~= "table" then return false, "Invalid loot report." end
        local now = A.Client:ServerTime()
        if not integer(p.sampledAt, now - 86400, now + 5) then return false, "Invalid reading timestamp." end
        s.lootSequences = s.lootSequences or {}
        if p.seq <= (s.lootSequences[sender] or 0) then return false, "Stale loot report." end
        local cleaned, seen, count, additions = {}, {}, 0, 0
        for key, value in pairs(p.entries) do
            count = count + 1
            if not integer(key, 1, 80) or count > 80 or type(value) ~= "table" then return false, "Invalid loot report size." end
            local guid = value.guid
            if type(guid) ~= "string" or #guid > 100 or #guid < 6 or not guid:match("^Item%-[%w%-]+$") or seen[guid] then return false, "Invalid item identity." end
            seen[guid] = true
            if not self:EquipmentLink(value.link) or (value.kind ~= "timed" and value.kind ~= "unbound" and value.kind ~= "unknown" and value.kind ~= "missing") then return false, "Invalid item reading." end
            if value.kind == "timed" and not integer(value.seconds, 0, 604800) then return false, "Invalid trade duration." end
            if value.quality~=nil and not integer(value.quality,0,5) then return false,"Invalid item quality." end
            local old = self:TrackedByGUID(guid)
            if old and old.holder ~= sender then return false, "Only the recorded holder may report this item. The master looter can correct its holder." end
            if old and old.link:match("item:(%d+)") ~= value.link:match("item:(%d+)") then return false, "An item identity cannot change its base item." end
            local retired=s.retiredGUIDs and s.retiredGUIDs[guid]
            if not old and not retired and value.kind ~= "missing" and self:ShouldCollectLoot(value.quality) then
                additions = additions + 1
            end
            cleaned[#cleaned + 1] = {guid = guid, link = value.link, kind = value.kind, seconds = value.kind == "timed" and value.seconds or nil, old = old, retired=retired,quality=value.quality}
        end
        if #s.trackedLoot + additions > 80 then return false, "Active collection is full (80 copies). Archive confirmed deliveries in Loot History." end
        for _, value in ipairs(cleaned) do
            local entry = value.old
            if not entry and not value.retired and value.kind ~= "missing" and self:ShouldCollectLoot(value.quality) then
                entry = {id = self:NextIdentity("tracked"), guid = value.guid, link = value.link, holder = sender, quality=value.quality,deliveryRevision = 0, deliveryLog = {}}
                self:CaptureLootPolicy(entry)
                s.trackedLoot[#s.trackedLoot + 1] = entry
            end
            if entry then
                entry.link = value.link
                entry.quality=value.quality or entry.quality
                entry.kind, entry.seconds, entry.observedAt = value.kind, value.seconds, math.min(now, p.sampledAt)
                entry.verifiedHolder = true
                entry.maxSeconds = math.max(entry.maxSeconds or 1, value.seconds or 1)
            end
        end
        s.lootSequences[sender] = p.seq
        return true
    end
    if sender ~= s.master or s.masterBlocked then return false, "Only the current master looter controls loot and delivery records." end
    if p.op=="manualLoot" then return false,"Add loot now requires a verified bag item. Use the latest addon and Shift-click the item from your bags." end
    if p.op=="bagLoot" then
        local link=self:EquipmentLink(p.link)
        local now=A.Client:ServerTime()
        if not link or type(p.guid)~="string" or #p.guid>100 or not p.guid:match("^Item%-[%w%-]+$")
            or not integer(p.sampledAt,now-30,now+5)
            or (p.kind~="timed" and p.kind~="unbound" and p.kind~="unknown")
            or (p.kind=="timed" and not integer(p.seconds,0,604800)) then return false,"A fresh bag item reading is required." end
        if s.retiredGUIDs and s.retiredGUIDs[p.guid] then return false,"That item copy has already been archived." end
        local existing=self:TrackedByGUID(p.guid)
        if existing then
            if existing.holder~=sender or existing.link~=link then return false,"This item copy is already tracked with a different holder or item link." end
            return true -- Detection and manual Add can arrive in either order; never duplicate a copy.
        end
        if #s.trackedLoot>=80 then return false,"Loot is full (80 copies). Archive confirmed deliveries first." end
        s.trackedLoot[#s.trackedLoot+1]={id=self:NextIdentity("tracked"),guid=p.guid,link=link,
            holder=sender,bagAdded=true,demo=self.demo and true or nil,kind=p.kind,
            seconds=p.kind=="timed" and p.seconds or nil,maxSeconds=p.kind=="timed" and math.max(1,p.seconds) or 1,
            observedAt=math.min(now,p.sampledAt),verifiedHolder=true,deliveryRevision=0,deliveryLog={}}
        return true
    end
    if p.op=="queueLoot" and A.Client:Combat() then return false,"Queue loot after combat." end
    if p.op == "queueLoot" and p.entries ~= nil then
        if p.release ~= true or type(p.entries) ~= "table" then return false, "Invalid loot release." end
        local count, seen = 0, {}
        for key, value in pairs(p.entries) do
            count = count + 1
            if not integer(key, 1, 40) or type(value) ~= "table" or not integer(value.tracked, 1, self.limits.maxID) or seen[value.tracked] then return false, "Invalid loot selection." end
            local entry = self:TrackedByID(value.tracked)
            if not entry or entry.guid ~= value.guid or entry.item then return false, "The selected loot changed. Queue again." end
            if self.demo and not entry.demo then return false,"Tests can release simulated loot only." end
            seen[value.tracked] = true
        end
        if count == 0 or count ~= #p.entries or #s.items + count > 40 then return false, "Select loot within the 40 active item limit; archive confirmed deliveries first." end
        -- Validate the complete selection before creating any rounds. Retries cannot reset live items.
        for _, value in ipairs(p.entries) do
            self:ReduceLoot(sender, {op="queueLoot",tracked=value.tracked,release=true})
        end
        return true
    end
    local entry = integer(p.tracked, 1, self.limits.maxID) and self:TrackedByID(p.tracked)
    if not entry then return false, "Select a tracked item." end
    if p.op == "queueLoot" then
        if self.demo and not entry.demo then return false,"Tests can release simulated loot only." end
        if entry.item then return false, "This item copy is already in the loot session." end
        if p.attach then
            local item = integer(p.item, 1, self.limits.maxID) and self:ItemByID(p.item)
            if not item or item.lootGUID or item.link ~= entry.link then return false, "Select an untracked session item with the exact same item link." end
            entry.item, item.lootGUID = item.id, entry.guid
            if item.status == "awarded" then self:UpdateDeliveryAward(item, false) end
        else
            if #s.items >= 40 then return false, "Active queue is full (40 items). Archive confirmed deliveries first." end
            local item = {id = self:NextIdentity("item"), link = entry.link, status = "queued", responses = {}, ballots = {}, voting = "idle", deadline = false, round = 1, ballotVersion = 0, lootGUID = entry.guid}
            s.items[#s.items + 1], entry.item = item, item.id
            if p.release == true then self:StartResponses(item);self:SeedSoloTestResponses(item) end
        end
        return true
    end
    if p.expectedRevision ~= entry.deliveryRevision then return false, "This delivery changed. Review it again." end
    if #entry.deliveryLog >= 25 then return false, "Manual changes are limited once this item's delivery log has 25 entries." end
    if p.op == "lootHolder" then
        local holder = self:Resolve(p.target)
        if not holder or holder == entry.holder then return false, "Choose a different current raid member as holder." end
        entry.deliveryLog[#entry.deliveryLog + 1] = {action = "holder", from = entry.holder, to = holder, by = sender, time = A.Client:ServerTime()}
        entry.holder, entry.kind, entry.seconds, entry.verifiedHolder = holder, "unknown", nil, false
    else
        local item = entry.item and self:ItemByID(entry.item)
        if not item or item.status ~= "awarded" or p.expectedWinner ~= item.winner or p.expectedAwardRevision ~= (item.awardRevision or 1) then return false, "The award changed. Review the current winner before confirming delivery." end
        if p.op == "confirmDelivery" then
            if entry.delivery == "delivered" then return false, "Delivery is already confirmed." end
            entry.deliveryLog[#entry.deliveryLog + 1] = {action = "delivered", from = entry.holder, to = item.winner, by = sender, time = A.Client:ServerTime()}
            entry.delivery, entry.deliveredTo, entry.deliveredAt, entry.deliveredBy = "delivered", item.winner, A.Client:ServerTime(), sender
            entry.deliveryMethod="manual"
            entry.holder, entry.kind, entry.seconds, entry.verifiedHolder = item.winner, "unknown", nil, false
        elseif p.op == "reopenDelivery" then
            if entry.delivery ~= "delivered" and entry.delivery ~= "review" then return false, "This delivery is already pending." end
            entry.deliveryLog[#entry.deliveryLog + 1] = {action = "reopened", by = sender, time = A.Client:ServerTime(), to = item.winner}
            entry.delivery = "pending"
        else return false, "Unknown delivery operation." end
    end
    entry.deliveryRevision = entry.deliveryRevision + 1
    self:CopyDeliveryToItem(entry)
    return true
end

function A:CopyDeliveryToItem(entry)
    local item = entry.item and self:ItemByID(entry.item)
    if item then
        item.delivery = {status = entry.delivery or "unawarded", holder = entry.holder, deliveredTo = entry.deliveredTo,
            deliveredAt = entry.deliveredAt, deliveredBy = entry.deliveredBy, method=entry.deliveryMethod,token=entry.deliveryToken,revision = entry.deliveryRevision, log = self.Copy(entry.deliveryLog)}
    end
end

function A:UpdateDeliveryAward(item, correction)
    local entry = self:TrackedForItem(item)
    -- Solo awards have no physical bag copy. Keep their simulated tracking in
    -- the disposable demo state, using an identity that cannot be a real GUID.
    if not entry and self.demo and item.status == "awarded" then
        item.lootGUID = "Demo-" .. self.state.id .. "-" .. item.id
        entry = {id = self:NextIdentity("tracked"), guid = item.lootGUID,
            link = item.link, item = item.id, holder = self.me, demo = true,
            kind = "timed", seconds = 7200, maxSeconds = 7200,
            observedAt = A.Client:ServerTime(), verifiedHolder = true,
            deliveryRevision = 0, deliveryLog = {}}
        self.state.trackedLoot = self.state.trackedLoot or {}
        self.state.trackedLoot[#self.state.trackedLoot + 1] = entry
    end
    if not entry then return end
    local previous = entry.delivery
    entry.delivery = (previous == "delivered" or previous == "review") and "review" or "pending"
    entry.deliveryRevision = entry.deliveryRevision + 1
    entry.deliveryLog[#entry.deliveryLog + 1] = {action = correction and "award corrected" or "awarded", to = item.winner,
        by = item.awardedBy, time = A.Client:ServerTime()}
    self:CopyDeliveryToItem(entry)
end

function A:TradeRemaining(entry)
    if entry.manual then return nil,"Unknown — manual item" end
    if entry.verifiedHolder == false or not entry.observedAt then return nil, "Awaiting holder reading" end
    local age = A.Client:ServerTime() - entry.observedAt
    local unit = self.roster[entry.holder]
    local online
    if type(unit) == "string" then
        local ok, connected = pcall(function() return UnitIsConnected(unit) end)
        if ok and plain(connected) then online = connected end
    end
    local simulated = self.demo and entry.demo == true
    if age < 0 or (not simulated and (age > 90 or not unit or online == false)) then return nil, "Stale — awaiting holder" end
    if entry.kind == "missing" then return nil, "Not in holder's bags" end
    if entry.kind == "unbound" then return nil, "Unbound — no BoP timer" end
    if entry.kind ~= "timed" then return nil, "Trade time unknown" end
    local remaining = math.max(0, entry.seconds - age)
    if remaining == 0 then return 0, entry.seconds == 0 and "Timer reports zero" or "Elapsed — refresh needed" end
    return remaining, string.format("~%d:%02d:%02d", math.floor(remaining / 3600), math.floor(remaining / 60) % 60, remaining % 60)
end

function A:LootEvent(event, ...)
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then self.scanLootSoon = true end
    if event ~= "CHAT_MSG_LOOT" or not self.state then return end
    local text = ...
    if not plain(text) or type(text) ~= "string" then return end
    -- Match localized SELF variants, so another player's loot message cannot seed a bag scan.
    for _, format in ipairs({LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE}) do
        if type(format) == "string" then
            local prefix, suffix = format:match("^(.-)%%s(.*)$")
            if prefix then
                local ending = pattern(suffix):gsub("%%%%d", "%%d+")
                local link = text:match("^" .. pattern(prefix) .. "(.-)" .. ending .. "$")
                link = self:EquipmentLink(link)
                if link then
                    self.pendingLootLinks = self.pendingLootLinks or {}
                    self.pendingLootLinks[link] = A.Client:Uptime() + 15
                    self.scanLootSoon = true
                    return
                end
            end
        end
    end
end

function A:ScanLoot()
    if self.demo or not self.state or not A.Client:InRaid() or not self.roster[self.me] then return end
    if not C_Container or not ItemLocation or not C_Item then self.lootScanStatus = "Bag APIs unavailable"; return end
    local seen, report, complete = {}, {}, true
    for bag = 0, math.min(NUM_BAG_SLOTS or 4, 5) do
        local slots = invoke(C_Container, "GetContainerNumSlots", bag)
        if not integer(slots, 0, 100) then complete = false
        else for slot = 1, slots do
            local infoOK, info = pcall(function() return C_Container.GetContainerItemInfo(bag, slot) end)
            if not infoOK or not plain(info) then complete = false
            elseif type(info) == "table" then
                local ok, location = pcall(function() return ItemLocation:CreateFromBagAndSlot(bag, slot) end)
                local guid = ok and invoke(C_Item, "GetItemGUID", location)
                local link = plain(info.hyperlink) and self:EquipmentLink(info.hyperlink)
                if type(guid) == "string" and link then
                    seen[guid] = true
                    local known = self:TrackedByGUID(guid)
                    if not known or known.holder == self.me then
                        local kind, seconds = self:ReadTradeTimer(bag, slot, location)
                        local pending = self.pendingLootLinks and (self.pendingLootLinks[link] or 0) >= A.Client:Uptime()
                        local quality = plain(info.quality) and info.quality
                        local single = plain(info.stackCount) and (info.stackCount == nil or info.stackCount == 1)
                        if not single then kind, seconds = "unknown", nil end
                        if not (self.state.retiredGUIDs and self.state.retiredGUIDs[guid]) and not self:CorpseReservation(guid,link) and (known or (single and self:ShouldCollectLoot(quality) and (kind == "timed" or pending))) then
                            report[#report + 1] = {guid = guid, link = link, quality=quality,kind = kind, seconds = seconds}
                        end
                    end
                else complete = false end
            end
        end end
    end
    if complete then
        for _, entry in ipairs(self.state.trackedLoot or {}) do
            if not entry.manual and entry.holder == self.me and not seen[entry.guid] then report[#report + 1] = {guid = entry.guid, link = entry.link, kind = "missing"} end
        end
    end
    self.lootScanStatus = complete and "Holder bag scan active" or "Some bag data unavailable"
    -- Bag events can be frequent. New copies/status changes publish promptly;
    -- otherwise refresh a reading at most every 30 seconds.
    local filtered = {}
    for _, sample in ipairs(report) do
        local old = self:TrackedByGUID(sample.guid)
        local changed = not old or old.verifiedHolder == false or old.kind ~= sample.kind or
            (sample.kind == "timed" and sample.seconds == 0 and old.seconds ~= 0) or
            (sample.kind == "timed" and math.abs((old.seconds or 0) - math.max(0, A.Client:ServerTime() - (old.observedAt or 0)) - sample.seconds) > 120)
        if changed or A.Client:ServerTime() - (old and old.observedAt or 0) >= 30 then filtered[#filtered + 1] = sample end
    end
    report = filtered
    if #report == 0 then return end
    if #report > 80 then self.lootScanStatus = "Tracking limit reached (80 item copies)"; return end
    self:SendLootSamples(report)
end

function A:SendLootSamples(samples)
    if not self.state or #samples == 0 then return end
    self.localLootSeq = math.max(self.localLootSeq or 0, (self.state.lootSequences or {})[self.me] or 0)
    local sampledAt, batch = A.Client:ServerTime(), {}
    local function size(entries)
        return #self.Encode({kind = "request", protocol = self.protocol, data = {op = "lootReport", sid = self.state.id,
            seq = self.localLootSeq + 1, sampledAt = sampledAt, entries = entries}})
    end
    local function send()
        self.localLootSeq = self.localLootSeq + 1
        self:Act("lootReport", {seq = self.localLootSeq, sampledAt = sampledAt, entries = batch})
        batch = {}
    end
    -- Receive deliberately limits non-leader requests to 8 x 180 bytes. Preserve
    -- that safety bound and split by encoded bytes, not an assumed item count.
    for _, sample in ipairs(samples) do
        batch[#batch + 1] = sample
        if size(batch) > 1440 then
            batch[#batch] = nil
            if #batch > 0 then send() end
            batch[1] = sample
            if size(batch) > 1440 then
                self.lootScanStatus = "An item report exceeds the request size limit"
                return
            end
        end
    end
    if #batch > 0 then send() end
end

function A:TickLoot()
    if not self.state then return end
    self:TickLootConfiguration()
    if self.ui and self.ui.settingsHub:IsShown() and self.settingsPage=="Loot Configuration" then self:RenderLootConfigurationUI() end
    if self.TickTradeCompletions then self:TickTradeCompletions() end
    if self.ReportTradeActivity then self:ReportTradeActivity() end
    if self.lootScanSID ~= self.state.id then self.lootScanSID, self.nextLootScan, self.localLootSeq = self.state.id, 0, 0 end
    local now = A.Client:Uptime()
    if (self.scanLootSoon or now >= (self.nextLootScan or 0)) and now >= (self.lastLootScan or -10) + 2 then
        self.scanLootSoon, self.lastLootScan, self.nextLootScan = false, now, now + 20
        self:ScanLoot()
    end
    if self.RenderLootWindows then self:RenderLootWindows() end
end
