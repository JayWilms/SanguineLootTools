local _,A=...
local function read(fn,...)
    if type(fn)~="function" then return nil,false end
    local ok,value=A.Client:Invoke(fn,...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil,false end
    return value,true
end
local function baseID(link)
    return type(link)=="string" and link:match("item:(%d+)")
end
local function matchesEvent(constant,...)
    local text,id=_G[constant],_G["LE_GAME_"..constant]
    for i=1,select("#",...) do
        local value=select(i,...)
        if not issecretvalue or not issecretvalue(value) then
            if type(id)=="number" and type(value)=="number" and value==id then return true end
            if type(text)=="string" and text~="" and type(value)=="string" and value==text then return true end
        end
    end
    return false
end
-- Presence is tri-state: false only after a complete readable carried-bag scan.
function A:TradeGUIDPresent(guid)
    if not C_Container or not C_Item or not ItemLocation then return nil end
    for bag=0,math.min(NUM_BAG_SLOTS or 4,5) do
        local count,ok=read(C_Container.GetContainerNumSlots,bag)
        if not ok or type(count)~="number" or count%1~=0 or count<0 or count>100 then return nil end
        for slot=1,count do
            local info,readable=read(C_Container.GetContainerItemInfo,bag,slot)
            if not readable then return nil end
            local loc,located=read(function() return ItemLocation:CreateFromBagAndSlot(bag,slot) end)
            if not located or not loc then return nil end
            local id,known=read(C_Item.GetItemGUID,loc)
            if not known then return nil end
            if id~=nil and (type(id)~="string" or id=="") then return nil end
            if type(id)=="string" and id==guid then return true end
            if info~=nil then
                if type(info)~="table" then return nil end
                if not known or type(id)~="string" or id=="" then return nil end
            end
        end
    end
    return false
end
function A:RememberTradeOffer(intent,slot)
    self.tradeOfferSlots=self.tradeOfferSlots or {}
    self.tradeOfferSlots[slot]=self.Copy(intent)
    self.acceptedTrade=nil
end
function A:CaptureAcceptedTrade(playerAccepted,targetAccepted)
    self.acceptedTrade=nil
    if issecretvalue and (issecretvalue(playerAccepted) or issecretvalue(targetAccepted)) then return end
    if playerAccepted~=1 and playerAccepted~=true and targetAccepted~=1 and targetAccepted~=true then return end
    local partner=self:TradePartner()
    if not partner or not self.state then return end
    local copies={}
    for slot,intent in pairs(self.tradeOfferSlots or {}) do
        local link,ok=read(GetTradePlayerItemLink,slot)
        if ok and baseID(link) and baseID(link)==baseID(intent.link) and intent.target==partner and self:TradeIntentValid(intent) then
            copies[#copies+1]={guid=intent.guid,tracked=intent.tracked or self:TrackedByGUID(intent.guid).id,
                expectedRevision=intent.deliveryRevision,expectedAwardRevision=intent.awardRevision,expectedWinner=partner}
        end
    end
    if #copies==0 then return end
    self.completionSequence=(self.completionSequence or 0)+1
    self.completionNonce=self.completionNonce or tostring(math.random(100000,999999))
    self.acceptedTrade={sid=self.state.id,target=partner,copies=copies,serial=self.tradeSerial,
        token=tostring(A.Client:ServerTime())..":"..self.completionNonce..":"..self.completionSequence}
end
function A:DeliveryReceiptContextValid(receipt)
    local s=self.state
    local entry=s and receipt.sid==s.id and self:TrackedByID(receipt.tracked)
    local item=entry and entry.item and self:ItemByID(entry.item)
    return entry and entry.guid==receipt.guid and entry.holder==self.me and entry.delivery~="delivered" and
        entry.deliveryRevision==receipt.expectedRevision and item and item.status=="awarded" and item.winner==receipt.expectedWinner and
        (item.awardRevision or 1)==receipt.expectedAwardRevision
end
function A:TradeCompletionEvent(event,...)
    if event=="TRADE_SHOW" then
        if not self.tradeShown then self.acceptedTrade=nil;self.tradeOfferSlots={} end
    elseif event=="TRADE_ACCEPT_UPDATE" then self:CaptureAcceptedTrade(...)
    elseif event=="TRADE_PLAYER_ITEM_CHANGED" or event=="TRADE_TARGET_ITEM_CHANGED" or event=="TRADE_MONEY_CHANGED" then
        -- Changes before closure invalidate acceptance. Do not discard a final
        -- snapshot when the game clears slots while hiding the native frame.
        if self:TradePartner() then self.acceptedTrade=nil end
    elseif event=="TRADE_REQUEST_CANCEL" then self.acceptedTrade=nil
    elseif event=="TRADE_CLOSED" then
        if self.acceptedTrade and not self.acceptedTrade.expires then self.acceptedTrade.expires=A.Client:Uptime()+10 end
    elseif event=="UI_INFO_MESSAGE" or event=="UI_ERROR_MESSAGE" then
        for _,failure in ipairs({"ERR_TRADE_CANCELLED","ERR_TRADE_BAG_FULL","ERR_TRADE_TARGET_BAG_FULL","ERR_TRADE_MAX_COUNT_EXCEEDED","ERR_TRADE_TARGET_MAX_COUNT_EXCEEDED","ERR_TRADE_BOUND_ITEM","ERR_TRADE_NOT_ON_TAPLIST"}) do
            if matchesEvent(failure,...) then self.acceptedTrade=nil;return end
        end
        if event~="UI_INFO_MESSAGE" or not matchesEvent("ERR_TRADE_COMPLETE",...) then return end
        local snapshot=self.acceptedTrade
        self.acceptedTrade=nil
        if not snapshot or not self.state or snapshot.sid~=self.state.id or (snapshot.expires and A.Client:Uptime()>snapshot.expires) then return end
        self.pendingTradeReceipts=self.pendingTradeReceipts or {}
        for _,copy in ipairs(snapshot.copies) do
            local receipt=self.Copy(copy)
            receipt.op,receipt.sid,receipt.token="tradeReceipt",snapshot.sid,snapshot.token
            receipt.completedAt=A.Client:ServerTime()
            local key=receipt.token..":"..receipt.guid
            self.pendingTradeReceipts[key]={receipt=receipt,verifyUntil=A.Client:Uptime()+10,retryUntil=A.Client:Uptime()+70,nextSend=0}
        end
        self:TickTradeCompletions()
    elseif event=="BAG_UPDATE_DELAYED" then self:TickTradeCompletions() end
end
function A:TickTradeCompletions()
    if self.demo then return end
    local now=A.Client:Uptime()
    if self.acceptedTrade and self.acceptedTrade.expires and now>self.acceptedTrade.expires then self.acceptedTrade=nil end
    for key,pending in pairs(self.pendingTradeReceipts or {}) do
        local receipt=pending.receipt
        local entry=self.state and receipt.sid==self.state.id and self:TrackedByID(receipt.tracked)
        if entry and entry.delivery=="delivered" and entry.deliveryToken==receipt.token and entry.deliveredBy==self.me then
            self.pendingTradeReceipts[key]=nil
        elseif not self:DeliveryReceiptContextValid(receipt) then self.pendingTradeReceipts[key]=nil
        else
            if not pending.verified then
                pending.verified=self:TradeGUIDPresent(receipt.guid)==false
                if not pending.verified and now>pending.verifyUntil then
                    self:Print("Trade finished, but the exact item transfer could not be verified. Delivery stays pending for review.")
                    self.pendingTradeReceipts[key]=nil
                end
            end
            if pending.verified then
                if now>pending.retryUntil then
                    self:Print("Delivery confirmation has not synchronized. Resync or review the pending item.")
                    self.pendingTradeReceipts[key]=nil
                elseif now>=pending.nextSend then
                    pending.nextSend=now+5
                    self:Act("tradeReceipt",self.Copy(receipt))
                end
            end
        end
    end
end
