local _,A=...
local function integer(n,lo,hi) return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi end
local function invoke(fn,...)
    local ok,a,b,c,d,e,f,g,h=A.Client:Invoke(fn,...)
    if ok then return a,b,c,d,e,f,g,h end
end
local function itemID(link) return type(link)=="string" and link:match("item:(%d+)") end

-- Council collection selects a holder, never an award winner. It uses the
-- collection switch independently of final automatic assignments.
function A:NativeLootPolicy(quality)
    local c=self:LootConfiguration()
    local rule=integer(quality,0,5) and c.rules[quality+1]
    if rule and rule.action=="council" and c.collection then
        return {action="council",target="@master"}
    end
    return self:AutomaticLootRule(quality)
end

function A:RememberNativeCouncilPickup(data)
    local now=self.Client:Uptime()
    self.pendingLootItems=self.pendingLootItems or {}
    local id=itemID(data.link)
    local old=self.pendingLootItems[id]
    self.pendingLootItems[id]={at=old and old.expires>=now and old.at or now,
        expires=now+30,remaining=data.quantity+(old and old.expires>=now and old.remaining or 0),
        claims=old and old.expires>=now and old.claims or {}}
    self.scanLootSoon=true
end

-- Native receipts identify a distribution event, never a physical bag GUID.
function A:ReduceNativeReceipt(sender,p)
    local s=self.state
    if self.demo or s.groupTest or sender~=s.master or s.masterBlocked then return false,"Only the authorised Master Looter records native deliveries." end
    if type(p.token)~="string" or #p.token>100 or not p.token:match("^[%w%-:]+$")
        or not self:EquipmentLink(p.link) or not integer(p.quality,0,5) or not integer(p.quantity,1,10000)
        or type(p.source)~="string" or #p.source>100 or not p.source:match("^[%w%-]+$")
        or not integer(p.slot,1,40) or not integer(p.revision,0,1000000000) or not integer(p.at,0,self.Client:ServerTime()+5)
        or self.Client:ServerTime()-p.at>43200 then return false,"Invalid native delivery record." end
    s.nativeReceipts=s.nativeReceipts or {}
    local previous=s.nativeReceipts[p.token]
    if previous then
        if previous.target~=p.target or previous.link~=p.link or previous.quantity~=p.quantity
            or previous.source~=p.source or previous.slot~=p.slot or previous.quality~=p.quality
            or previous.reason~=p.reason or previous.note~=p.note or previous.revision~=p.revision or previous.at~=p.at then return false,"Conflicting native delivery record." end
        return true,nil,true
    end
    local config=p.revision==(s.lootConfigRevision or 0) and self:LootConfiguration()
        or s.nativePolicyHistory and s.nativePolicyHistory[p.revision]
    local rule=config and config.automatic and config.rules[p.quality+1]
    if not rule or rule.action~="assign" or self:PolicyTarget(rule)~=p.target
        or rule.reason~=p.reason or rule.note~=p.note then return false,"Native delivery policy requires review." end
    if #s.items>=40 or #s.trackedLoot>=80 then return false,"Active loot is full; native delivery recording is pending." end
    local entry={id=self:NextIdentity("tracked"),link=p.link,quality=p.quality,holder=p.target,
        manual=true,verifiedHolder=false,kind="unknown",observedAt=p.at,quantity=p.quantity,
        nativeReceipt={token=p.token,source=p.source,slot=p.slot,at=p.at,quantity=p.quantity},
        deliveryRevision=0,deliveryLog={}}
    local ok,why=self:MakeAutomaticAward(entry,{target=p.target,reason=p.reason,note=p.note,nativeAt=p.at},sender,true)
    if not ok then return false,why end
    entry.deliveryMethod="masterloot_native"
    self:CopyDeliveryToItem(entry)
    s.nativeReceipts[p.token]={target=p.target,link=p.link,quantity=p.quantity,item=entry.item,tracked=entry.id,
        source=p.source,slot=p.slot,quality=p.quality,reason=p.reason,note=p.note,revision=p.revision,at=p.at}
    return true
end

function A:RememberNativePolicy()
    if not self.state then return end
    self.state.nativePolicyHistory=self.state.nativePolicyHistory or {}
    self.state.nativePolicyHistory[self.state.lootConfigRevision or 0]=self.Copy(self:LootConfiguration())
end

function A:AckNativeReceipt(sender,p)
    if p.op=="corpseNativeReceipt" and sender~=self.me then
        self:Send({kind="nativeReceiptAck",sid=self.state.id,token=p.token},sender,{key="nativeAck:"..p.token})
    end
end
function A:NativeLootPacket(sender,packet)
    if packet.kind~="nativeReceiptAck" and packet.kind~="nativeReceiptError" then return false end
    if sender==self.leader and self.state and packet.sid==self.state.id
        and type(packet.token)=="string" and self.nativeLoot and self.nativeLoot.pending[packet.token] then
        if packet.kind=="nativeReceiptAck" then self.nativeLoot.pending[packet.token]=nil
        else self:NativeRecordFailure(packet.token,packet.reason) end
    end
    return true
end

function A:NativeRecordFailure(token,reason)
    local result=self.nativeLoot and self.nativeLoot.pending[token]
    if not result then return end
    if not result.needsReview then
        result.needsReview=true
        self.nativeLoot.recordErrors=(self.nativeLoot.recordErrors or 0)+1
        self:Print("A native delivery completed but its history record needs review. Check /slt diagnostics.")
    end
    result.retryAt=self.Client:Uptime()+30
    self.lootRoutingStatus="Native delivery confirmed; history recording needs review"
end

function A:NativeLootState()
    local sid=self.state and self.state.id
    if not self.nativeLoot or self.nativeLoot.sid~=sid then
        local pending={}
        if sid and type(SanguineLootCouncilDB)=="table" then
            SanguineLootCouncilDB.nativePendingReceipts=SanguineLootCouncilDB.nativePendingReceipts or {}
            pending=SanguineLootCouncilDB.nativePendingReceipts[sid] or {}
            SanguineLootCouncilDB.nativePendingReceipts[sid]=pending
            for _,result in pairs(pending) do result.retryAt=nil end
        end
        self.nativeLoot={sid=sid,generation=0,serial=0,nonce=tostring(math.random(100000,999999)),
            pending=pending,rejected={},confirmed=0,failed=0}
    end
    return self.nativeLoot
end

function A:FlushNativeReceipts()
    local native=self:NativeLootState()
    local now=self.Client:Uptime()
    for token,result in pairs(native.pending) do
        if self.state.nativeReceipts and self.state.nativeReceipts[token] then native.pending[token]=nil
        elseif not result.retryAt or now>=result.retryAt then
            result.retryAt=now+5
            self:Act("corpseNativeReceipt",self.Copy(result.data))
            if self.state.nativeReceipts and self.state.nativeReceipts[token] then native.pending[token]=nil end
            return -- Recording is background work, independent of handovers.
        end
    end
end

local function total(items,source,id)
    local count=0
    for _,item in ipairs(items) do
        if item.source==source and itemID(item.link)==id then count=count+(item.quantity or 1) end
    end
    return count
end
function A:NativeCorpseContents()
    local n=invoke(GetNumLootItems)
    if not integer(n,0,40) then return end
    local items={}
    for slot=1,n do
        local item=self:NativeCorpseItem(slot,true)
        if item then items[#items+1]=item end
    end
    return items
end

function A:ConfirmNativeClear(items)
    local native=self:NativeLootState()
    local attempt=native.active
    if not attempt or not attempt.cleared or not items then return end
    if total(items,attempt.data.source,itemID(attempt.data.link))~=attempt.before-attempt.data.quantity then return end
    native.active=nil;native.confirmed=native.confirmed+1
    attempt.data.at=self.Client:ServerTime()
    if attempt.data.action=="council" then
        self:RememberNativeCouncilPickup(attempt.data)
    else native.pending[attempt.data.token]={data=attempt.data} end
    self.corpseScanSoon=true
    self.lootRoutingStatus=attempt.data.action=="council" and "Council loot collected by Master Looter; awaiting bag tracking, not awarded"
        or "Master Loot delivery confirmed; records synchronise in the background"
end

function A:TickNativeLoot()
    if not self.state or self.demo or self.state.groupTest or not self.Client:InRaid() or not self.Client:ClockReady() then return end
    local native=self:NativeLootState()
    self:FlushNativeReceipts()
    local items=self:NativeCorpseContents()
    self:ConfirmNativeClear(items)
    if native.active then
        if self.Client:Uptime()-native.active.sentAt>=3 then
            native.rejected[native.active.key]=true;native.active=nil;native.failed=native.failed+1
            self.lootRoutingStatus="Native delivery not confirmed; check recipient bag space or distribute that item manually."
        end
        return
    end
    if not self:IsMaster() or self.Client:Combat() or not self.corpseOpen then return end
    local actual,status=self:ReadGameMaster()
    if actual~=self.me or status~="game" then return end
    if type(GetMasterLootCandidate)~="function" or type(GiveMasterLoot)~="function" then
        self.lootRoutingStatus="Native Master Loot APIs unavailable";return
    end
    local threshold=invoke(GetLootThreshold)
    if not items or not integer(threshold,0,5) then return end
    for _,item in ipairs(items) do
        local policy=self:NativeLootPolicy(item.quality)
        if policy and policy.action=="council" then
            local snapshot,why=self:CorpseBagSnapshot(item.link)
            if item.quantity~=1 or why=="stacked" then
                policy=nil
                self.lootRoutingStatus="Council stacks require splitting into single copies; distribute these manually or use Assign automatically"
            elseif not snapshot then
                policy=nil
                self.lootRoutingStatus="Council bag tracking unavailable; collect this item manually"
            end
        end
        if policy and not item.locked and not item.quest and item.quality>=threshold then
            local key=item.source..":"..item.slot..":"..itemID(item.link)
            if not native.rejected[key] then
                local target=self:PolicyTarget(policy)
                local unit=target and self.roster[target]
                local candidate
                if type(unit)=="string" and invoke(UnitIsConnected,unit)==true then
                    for index=1,40 do
                        local name=invoke(GetMasterLootCandidate,item.slot,index)
                        if name and self:Resolve(name)==target then candidate=index;break end
                    end
                end
                if candidate then
                    if policy.action=="council" and self.PrimeLootBagSnapshot then self:PrimeLootBagSnapshot() end
                    -- Recheck native authority and the current item immediately
                    -- before the call. Event handlers never issue nested gives.
                    local current=self:NativeCorpseItem(item.slot)
                    local master,mode=self:ReadGameMaster()
                    if not current or current.source~=item.source or current.link~=item.link
                        or current.quantity~=item.quantity or not self.corpseOpen or master~=self.me or mode~="game"
                        or not self:IsMaster() or self.Client:Combat() then return end
                    native.serial=native.serial+1
                    if type(SanguineLootCouncilDB)=="table" then
                        local previous=SanguineLootCouncilDB.nativeSequence
                        SanguineLootCouncilDB.nativeSequence=(integer(previous,0,1000000000) and previous or 0)+1
                        native.serial=SanguineLootCouncilDB.nativeSequence
                    end
                    local token=tostring(self.Client:ServerTime())..":"..native.nonce..":"..native.generation..":"..native.serial
                    local data={token=token,source=item.source,slot=item.slot,link=item.link,quality=item.quality,
                        quantity=item.quantity or 1,target=target,reason=policy.reason,note=policy.note,
                        action=policy.action,revision=self.state.lootConfigRevision or 0,at=self.Client:ServerTime()}
                    local attempt={data=data,key=key,generation=native.generation,sentAt=self.Client:Uptime(),
                        before=total(items,item.source,itemID(item.link))}
                    native.active=attempt
                    local ok=self.Client:Invoke(GiveMasterLoot,item.slot,candidate)
                    if not ok and native.active==attempt then
                        native.active=nil;native.rejected[key]=true;native.failed=native.failed+1
                        self.lootRoutingStatus="Native Master Loot call failed; distribute that item manually."
                    end
                    return
                end
                self.lootRoutingStatus="Automatic recipient is unavailable or not eligible for this item"
            end
        elseif policy then self.lootRoutingStatus="Configured item is below the game Master Loot threshold" end
    end
end

function A:NativeLootEvent(event,...)
    local native=self:NativeLootState()
    if event=="LOOT_OPENED" then
        if not self.corpseOpen then
            native.generation=native.generation+1;native.active=nil;native.settling=nil;native.rejected={}
        end
        self.corpseOpen=true;self.corpseScanSoon=true
    elseif event=="LOOT_READY" then self.corpseScanSoon=true
    elseif event=="LOOT_CLOSED" then
        self:ConfirmNativeClear(self:NativeCorpseContents())
        self.corpseOpen=false
        if native.active then native.failed=native.failed+1 end
        native.active=nil;native.settling=nil;self.corpseScanSoon=true
    elseif event=="LOOT_SLOT_CLEARED" then
        local slot=...
        local attempt=native.active
        if attempt and self.corpseOpen and attempt.generation==native.generation and slot==attempt.data.slot then
            attempt.cleared=true
            -- Capture a confirmed final drop before the client automatically
            -- closes an empty corpse. Never issue another give from this event.
            self:ConfirmNativeClear(self:NativeCorpseContents())
            self.corpseScanSoon=true
        end
    elseif event=="BAG_UPDATE_DELAYED" then self.corpseScanSoon=true end
end

-- Assigned native drops are recorded from native results, not independently
-- added again as fresh bag pickups while the ledger broadcast is still queued.
function A:IsNativeAutomaticRecipient(quality)
    if self.demo or not self.state then return false end
    local policy=self:AutomaticLootRule(quality)
    if not policy or self:PolicyTarget(policy)~=self.me or not self.ReadGameMaster then return false end
    local _,status=self:ReadGameMaster()
    return status=="game"
end
