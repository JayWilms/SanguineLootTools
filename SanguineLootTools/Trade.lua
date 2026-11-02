local _, A = ...

local function call(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, a, b, c = A.Client:Invoke(fn, ...)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b) or issecretvalue(c))) then return nil, false end
    return a, true, b, c
end

function A:TradePartner()
    if not TradeFrame or TradeFrame:IsShown() ~= true then return end
    local name = call(function() return self:Name("NPC") end)
    return name and self:Resolve(name)
end

function A:CanViewLoot()
    if not self.state then return false end
    if self:IsLeader() or self:IsMaster() then return true end
    for _, entry in ipairs(self.state.trackedLoot or {}) do
        local item = entry.item and self:ItemByID(entry.item)
        if entry.holder == self.me and entry.delivery ~= "delivered" then return true end
    end
    return false
end

function A:FindTradeItem(entry)
    if not C_Container or not C_Item or not ItemLocation then return nil, nil, "Bag APIs unavailable." end
    for bag = 0, math.min(NUM_BAG_SLOTS or 4, 5) do
        local count = call(C_Container.GetContainerNumSlots, bag)
        if type(count) == "number" and count >= 0 and count <= 100 then
            for slot = 1, count do
                local info = call(C_Container.GetContainerItemInfo, bag, slot)
                if type(info) == "table" then
                    local location = call(function() return ItemLocation:CreateFromBagAndSlot(bag, slot) end)
                    local guid = location and call(C_Item.GetItemGUID, location)
                    if guid == entry.guid then
                        if issecretvalue and (issecretvalue(info.isLocked) or issecretvalue(info.stackCount) or issecretvalue(info.hyperlink)) then return nil, nil, "Item information is restricted." end
                        if info.isLocked then return nil, nil, "Item is locked or already offered." end
                        if info.stackCount and info.stackCount ~= 1 then return nil, nil, "Split stacked items manually first." end
                        if not self:EquipmentLink(info.hyperlink) or info.hyperlink:match("item:(%d+)") ~= entry.link:match("item:(%d+)") then return nil, nil, "Item information changed." end
                        local kind, seconds = self:ReadTradeTimer(bag, slot, location)
                        if entry.bagAdded and kind~="unbound" and not (kind=="timed" and type(seconds)=="number" and seconds>0) then return nil,nil,"This bag item has no verified trade eligibility. It may be bound or its trade timer is unavailable." end
                        if kind == "timed" and seconds == 0 then return nil, nil, "The item reports no trade time remaining." end
                        return bag, slot
                    end
                end
            end
        end
    end
    return nil, nil, "This item copy is not in your carried bags."
end

function A:TradeIntentValid(intent)
    if self.demo then return end
    local entry = self.state and intent.sid == self.state.id and self:TrackedByGUID(intent.guid)
    local item = entry and entry.item and self:ItemByID(entry.item)
    if not entry or entry.holder ~= self.me or not item or item.status ~= "awarded" or item.winner ~= intent.target or
        (item.awardRevision or 1) ~= intent.awardRevision or entry.deliveryRevision ~= intent.deliveryRevision or entry.delivery == "delivered" then return end
    return entry, item
end

-- Range is meaningful on the physical holder's client, not a remote controller's.
function A:WinnerInTradeRange(winner)
    local unit = self.roster[winner]
    return winner ~= self.me and type(unit) == "string" and not A.Client:Combat()
        and call(UnitIsConnected, unit) ~= false and call(CheckInteractDistance, unit, 2) == true
end

-- Remote controllers count only the selected holder's awards; another holder
-- cannot offer those items. Local counts omit copies already in the offer.
function A:ReconcileTradeOffers()
    if self.demo then return end
    if not self:TradePartner() then return end -- preserve close-before-success evidence
    for guid,slot in pairs(self.tradeOffered or {}) do
        local entry=self:TrackedByGUID(guid)
        local bag=entry and self:FindTradeItem(entry)
        local link,readable=call(GetTradePlayerItemLink,slot)
        if bag~=nil then
            -- An unlocked, readable exact GUID is back in carried inventory.
            -- A matching link alone cannot prove an identical replacement.
            self.tradeOffered[guid]=nil
            if self.tradeOfferSlots then self.tradeOfferSlots[slot]=nil end
            self.acceptedTrade=nil
        elseif readable and (not link or not entry or link~=entry.link) then
            if self.tradeOfferSlots then self.tradeOfferSlots[slot]=nil end
            self.acceptedTrade=nil
        end
    end
end

function A:PendingTradeCount(winner, holder)
    if holder==self.me then self:ReconcileTradeOffers() end
    local count=0
    for _,entry in ipairs(self.state and self.state.trackedLoot or {}) do
        local item=entry.item and self:ItemByID(entry.item)
        if not entry.manual and entry.holder==holder and entry.delivery~="delivered" and item and item.status=="awarded" and item.winner==winner
            and winner~=holder and not (holder==self.me and (self.tradeOffered or {})[entry.guid]) then count=count+1 end
    end
    return count
end

function A:PendingTradeItems(winner, first)
    self:ReconcileTradeOffers()
    local intents = {}
    for _, entry in ipairs(self.state and self.state.trackedLoot or {}) do
        local item = entry.item and self:ItemByID(entry.item)
        if not entry.manual and entry.holder == self.me and entry.delivery ~= "delivered" and item and item.status == "awarded" and item.winner == winner
            and winner ~= self.me and not (self.tradeOffered or {})[entry.guid] then
            intents[#intents+1] = {sid=self.state.id,guid=entry.guid,target=winner,awardRevision=item.awardRevision or 1,
                deliveryRevision=entry.deliveryRevision,expires=A.Client:Uptime()+15,link=entry.link,tracked=entry.id}
        end
    end
    table.sort(intents,function(a,b) if a.tracked==b.tracked then return false elseif a.tracked==first then return true elseif b.tracked==first then return false end;return a.tracked<b.tracked end)
    return intents
end

function A:BeginTradeItems(intents)
    self.tradeBatch = {intents=intents,index=1}
    self.tradeIntent = intents[1]
end

function A:PlaceTradeItems()
    local batch = self.tradeBatch
    if not batch then return self:PlaceTradeItem() end
    if batch.running then return false end
    batch.running = true
    local function nextItem()
        if self.tradeBatch ~= batch then return false end
        local intent = batch.intents[batch.index]
        if not intent then return true end
        self.tradeIntent = intent
        if not self:PlaceTradeItem() then batch.running=false;return false end
        batch.index = batch.index+1
        if batch.intents[batch.index] then
            -- Let the game update bag locks and trade slots between offers.
            C_Timer.After(0.2,nextItem)
        end
        return true
    end
    return nextItem()
end

function A:PromptTradeItems()
    if self.demo then return end
    if self.tradePromptShown or A.Client:Combat() then return end
    local partner = self:TradePartner()
    if not partner then return end
    local intents = self:PendingTradeItems(partner)
    if #intents == 0 then return end
    self.tradePromptShown = true
    local context = {sid=self.state.id,target=partner,serial=self.tradeSerial,intents=intents,expires=A.Client:Uptime()+60}
    local lines = {}
    for i=1,math.min(#intents,6) do lines[#lines+1]=intents[i].link end
    local message = partner.." has won "..#intents.." pending item(s). Add them to this trade?\n\n"..table.concat(lines,"\n")
        .."\n\nOnly free normal trade slots are used. Any remaining items need another trade."
    local dialog = A:ShowConfirmation("SANGUINELOOTCOUNCIL_TRADE_ITEMS",message)
    if dialog then dialog.data=context end
end

function A:AcceptTradeItems(context)
    if not context or not self.state or context.sid~=self.state.id or context.serial~=self.tradeSerial
        or A.Client:Uptime()>context.expires or A.Client:Combat() or self:TradePartner()~=context.target then
        self:Print("The trade changed. Click Trade to review the current items.");return false
    end
    for _,intent in ipairs(context.intents) do
        if not self:TradeIntentValid(intent) or (self.tradeOffered or {})[intent.guid] then
            self:Print("An award or holder changed. Click Trade to review the current items.");return false
        end
    end
    for _,intent in ipairs(context.intents) do intent.expires=A.Client:Uptime()+15 end
    self:BeginTradeItems(context.intents)
    return self:PlaceTradeItems()
end

A.confirmationDialogs["SANGUINELOOTCOUNCIL_TRADE_ITEMS"] = {
    text="%s",button1="Add items",button2="Cancel",timeout=60,whileDead=true,hideOnEscape=true,
    OnAccept=function(dialog) A:AcceptTradeItems(dialog.data) end,
}

function A:StartTrade(tracked)
    if self.demo then self:Print("Test loot cannot be traded. Use Loot > Manage to simulate delivery confirmation."); return false end
    if self.tradeBatch and self.tradeBatch.running and self.tradeBatch.intents[self.tradeBatch.index] then
        self:Print("Items are being added to the trade.");return false
    end
    local entry = self.state and self.state.trackedLoot and self:TrackedByID(tracked)
    local item = entry and entry.item and self:ItemByID(entry.item)
    if not entry or not item or item.status ~= "awarded" or not item.winner or entry.delivery == "delivered" then self:Print("Select an awarded item awaiting delivery."); return false end
    if entry.manual then self:Print("Manual loot has no verified bag copy. Trade it yourself, then confirm delivery through Manage.");return false end
    if entry.holder ~= self.me then self:Print("The item holder must click Trade from their own addon."); return false end
    if item.winner == self.me then self:Print("You already hold your own awarded item."); return false end
    if A.Client:Combat() then self:Print("Click Trade again after combat."); return false end
    local unit = self.roster[item.winner]
    if type(unit) ~= "string" then self:Print("The awarded winner must be in your raid."); return false end
    if call(UnitIsConnected, unit) == false then self:Print("The awarded winner is offline."); return false end
    local cursor, readable = call(GetCursorInfo)
    if not readable or cursor ~= nil then self:Print("Clear your cursor before clicking Trade."); return false end
    local bag, slot, why = self:FindTradeItem(entry)
    if bag == nil then self:Print(why); return false end
    local partner = self:TradePartner()
    if TradeFrame and TradeFrame:IsShown() == true and partner ~= item.winner then self:Print("A different or unidentified trade is already open."); return false end
    local intents = self:PendingTradeItems(item.winner,tracked)
    if #intents==0 then self:Print("These items have already been offered in this trade. Check the offer manually.");return false end
    self:BeginTradeItems(intents)
    if partner == item.winner then return self:PlaceTradeItems() end
    if not self:WinnerInTradeRange(item.winner) then self.tradeIntent,self.tradeBatch = nil,nil; self:Print("Move into trade range of the winner, then click Trade."); return false end
    local _, ok = call(InitiateTrade, unit)
    if not ok then self.tradeIntent,self.tradeBatch = nil,nil; self:Print("The client could not open the trade. Open it manually and click Trade again."); return false end
    return true
end

function A:PlaceTradeItem()
    local intent = self.tradeIntent
    if not intent or intent.attempted or (self.tradeOffered or {})[intent.guid] or A.Client:Uptime() > intent.expires then return false end
    local entry = self:TradeIntentValid(intent)
    if not entry or A.Client:Combat() or self:TradePartner() ~= intent.target then return false end
    local cursor, readable = call(GetCursorInfo)
    if not readable or cursor then self:Print("Clear your cursor, then click Trade again."); return false end
    local bag, slot, why = self:FindTradeItem(entry)
    if bag == nil then self:Print(why); return false end
    local free
    for i = 1, 6 do
        local link, linkOK = call(GetTradePlayerItemLink, i)
        local name, nameOK = call(GetTradePlayerItemInfo, i)
        if linkOK and nameOK and not link and not name then free = i; break end
    end
    if not free then self:Print("No normal trade slot is available. The enchant slot is never used."); return false end
    if type(C_Container.PickupContainerItem) ~= "function" or type(ClickTradeButton) ~= "function" then self:Print("Item placement APIs are unavailable."); return false end
    intent.attempted = true
    local _, picked = call(C_Container.PickupContainerItem, bag, slot)
    local kind, cursorOK, id = call(GetCursorInfo)
    if not picked or not cursorOK or kind ~= "item" or tonumber(id) ~= tonumber(entry.link:match("item:(%d+)")) then
        if picked and cursorOK and kind == "item" then call(ClearCursor) end
        self:Print("The client blocked item pickup. Click Trade again in the open trade window."); return false
    end
    -- Recheck after pickup; never place into an unrelated or newly occupied offer.
    local offerLink, linkOK = call(GetTradePlayerItemLink, free)
    local offerName, nameOK = call(GetTradePlayerItemInfo, free)
    if not self:TradeIntentValid(intent) or self:TradePartner() ~= intent.target or not linkOK or not nameOK or offerLink or offerName then
        call(ClearCursor); self:Print("The trade changed; the item was returned to your bags."); return false
    end
    local _, placed = call(ClickTradeButton, free)
    if call(GetCursorInfo) ~= nil then call(ClearCursor); self:Print("Item placement was blocked. Click Trade again to retry."); return false end
    if not placed then self:Print("The client could not place the item. Check the offer manually."); return false end
    intent.placed = true
    self.tradeOffered = self.tradeOffered or {};self.tradeOffered[intent.guid]=free
    if self.RememberTradeOffer then self:RememberTradeOffer(intent,free) end
    self:Print("Item placed for " .. intent.target .. ". Check the offer and accept the trade in WoW.")
    return true
end

function A:ReportTradeActivity(force)
    if self.demo then return end
    if not self.state then return end
    local partner = self:TradePartner()
    if not force and partner == self.lastReportedPartner and A.Client:Uptime() < (self.nextTradeReport or 0) then return end
    if not partner and not self.lastReportedPartner then return end
    self.tradeSequence = math.max(self.tradeSequence or 0, ((self.state.tradeActivity or {})[self.me] or {}).seq or 0) + 1
    self.lastReportedPartner, self.nextTradeReport = partner, A.Client:Uptime() + 5
    self:Act("tradeActivity", {seq = self.tradeSequence, active = partner ~= nil, partner = partner})
end

function A:TradeEvent(event,...)
    if self.demo then return end
    if self.TradeCompletionEvent then self:TradeCompletionEvent(event,...) end
    if event=="TRADE_PLAYER_ITEM_CHANGED" or event=="BAG_UPDATE_DELAYED" then self:ReconcileTradeOffers() end
    if event == "TRADE_SHOW" then
        if not self.tradeShown then self.tradeSerial=(self.tradeSerial or 0)+1;self.tradeShown=true end
        if self.tradeIntent then self:PlaceTradeItems() else self:PromptTradeItems() end
        self:ReportTradeActivity(true)
    elseif event == "TRADE_CLOSED" or event == "TRADE_REQUEST_CANCEL" then
        self.tradeIntent,self.tradeBatch,self.tradeOffered,self.tradeShown,self.tradePromptShown = nil,nil,nil,nil,nil
        self.tradeSerial=(self.tradeSerial or 0)+1
        if self.confirmationContext and self.confirmationContext.kind=="SANGUINELOOTCOUNCIL_TRADE_ITEMS" then self:CloseConfirmation() end
        if self.lastReportedPartner and self.state then
            self.tradeSequence = (self.tradeSequence or 0) + 1
            self:Act("tradeActivity", {seq = self.tradeSequence, active = false})
        end
        self.lastReportedPartner = nil
    end
    if self.RenderLootWindows then self:RenderLootWindows() end
end

function A:EntryInTrade(entry, winner)
    if not winner then return false end
    if entry.holder == self.me and self:TradePartner() == winner then return true end
    local state = self.state and (self.state.tradeActivity or {})[entry.holder]
    return state and state.active and state.partner == winner and A.Client:ServerTime() >= state.time and A.Client:ServerTime() - state.time <= 15 or false
end
