local _,A=...
local function int(v,lo,hi) return type(v)=="number" and v%1==0 and v>=lo and v<=hi end
local function clean(v,n,empty)
    if type(v)~="string" or #v>n or v:find("[%c|]") then return end
    v=v:match("^%s*(.-)%s*$");if not empty and v=="" then return end;return v
end
local function call(fn,...)
    local ok,a,b,c,d,e,f,g,h=A.Client:Invoke(fn,...)
    if ok then return a,b,c,d,e,f,g,h end
end
function A:IsLootAwardReason(value)
    return value=="Disenchant" or value=="Guild Bank" or value=="Other"
end
function A:DefaultLootConfiguration()
    local c={collection=true,minimum=4,openWindow=false,automatic=false,rules={}}
    for q=0,5 do c.rules[q+1]={action=q<2 and "ignore" or "council",target="",reason="",note=""} end
    return c
end
function A:CleanLootConfiguration(c)
    if type(c)~="table" or not int(c.minimum,2,5) or type(c.collection)~="boolean" or type(c.openWindow)~="boolean" or type(c.automatic)~="boolean" or type(c.rules)~="table" then return end
    local result={collection=c.collection,minimum=c.minimum,openWindow=c.openWindow,automatic=c.automatic,rules={}}
    for key in pairs(c.rules) do if not int(key,1,6) then return end end
    for i=1,6 do
        local r=c.rules[i]
        if type(r)~="table" or (r.action~="ignore" and r.action~="council" and r.action~="assign") then return end
        local target,reason,note=clean(r.target,80,true),clean(r.reason,60,true),clean(r.note,100,true)
        if not target or not reason or not note or (reason~="" and not self:IsLootAwardReason(reason)) then return end
        if c.automatic and r.action=="assign" and (target=="" or reason=="") then return end
        result.rules[i]={action=r.action,target=target,reason=reason,note=note}
    end
    return result
end
function A:LootConfiguration()
    return self:CleanLootConfiguration(self.state and self.state.lootConfiguration or (SanguineLootCouncilDB and SanguineLootCouncilDB.lootConfiguration)) or self:DefaultLootConfiguration()
end
function A:SaveLootConfiguration(c)
    if not self:CanConfigureRaid() then self:Print("Only the Raid Leader changes Loot Configuration.");return false end
    c=self:CleanLootConfiguration(c)
    if not c then self:Print("Choose a recipient and reason for every automatic assignment before enabling it.");return false end
    if self.state then return self:Act("lootConfiguration",{settings=c,expectedRevision=self.state.lootConfigRevision or 0}) end
    return self:Act("lootConfiguration",{settings=c})
end
function A:AutomaticLootRule(quality)
    local c=self:LootConfiguration();local r=int(quality,0,5) and c.rules[quality+1]
    if c.automatic and r and r.action=="assign" and r.target~="" and r.reason~="" then return r end
end
function A:ShouldCollectLoot(quality)
    if not self.state or self.state.autoCollect==false or not int(quality,0,5) then return false end
    local c=self:LootConfiguration();local r=c.rules[quality+1]
    return r.action~="ignore" and ((r.action=="assign" and c.automatic) or quality>=c.minimum)
end
function A:CaptureLootPolicy(entry)
    local r=self:AutomaticLootRule(entry.quality)
    if r then entry.routePolicy={target=r.target,reason=r.reason,note=r.note,revision=self.state.lootConfigRevision or 0} end
end
function A:PolicyTarget(policy)
    return policy and (policy.target=="@master" and self.state.master or self:Resolve(policy.target))
end
function A:MakeAutomaticAward(entry,policy,by,delivered)
    local s=self.state;local target=self:PolicyTarget(policy)
    local awardTime=policy.nativeAt or self.Client:ServerTime()
    if not target or not self.roster[target] or entry.item or #s.items>=40 then return false,"Recipient unavailable or active item list full." end
    if not self:TrackedByGUID(entry.guid) then s.trackedLoot[#s.trackedLoot+1]=entry end
    local item={id=self:NextIdentity("item"),link=entry.link,lootGUID=entry.guid,status="awarded",winner=target,
        responses={},ballots={},voting="closed",round=1,ballotVersion=0,responseRound=0,
        automaticAssignment=true,awardReason=policy.reason,awardNote=policy.note,awardedAt=awardTime,awardedBy=by,
        awardedVotes=0,awardRevision=1,responseOptions=self.Copy(self:ResponseOptions()),corrections={},
        nativeReceipt=entry.nativeReceipt and entry.nativeReceipt.token or nil,
        nativeTrackedID=entry.nativeReceipt and entry.id or nil,quantity=entry.quantity}
    entry.item=item.id;s.items[#s.items+1]=item
    item.originalAward=self:AwardSnapshot(item);self:UpdateDeliveryAward(item,false)
    if delivered then
        entry.delivery="delivered";entry.deliveredTo=target;entry.deliveredAt=awardTime;entry.deliveredBy=by;entry.deliveryMethod="masterloot"
        entry.deliveryRevision=entry.deliveryRevision+1
        entry.deliveryLog[#entry.deliveryLog+1]={action="delivered",method=entry.nativeReceipt and "masterloot_native" or "masterloot",by=by,to=target,time=awardTime}
        self:CopyDeliveryToItem(entry)
    end
    return true
end
function A:CancelPreparedCorpseRoutes()
    for _,intent in pairs(self.state.corpseRoutes or {}) do
        if not intent.started and not intent.finished then intent.failed=true end
    end
end
local function corpseToken(source,slot,link)
    -- A remaining, different drop can occupy a previously used loot slot.
    -- Do not mistake it for the completed assignment from that position.
    return source..":"..slot..":"..(link:match("item:(%d+)") or "")
end
function A:PreparedCorpseRoute(item)
    local token=corpseToken(item.source,item.slot,item.link)
    local routes=self.state.corpseRoutes or {}
    if routes[token] then return token,routes[token] end
    -- Loot slots may compact after a delivery. Reuse the one prepared baseline
    -- for this source/item ID instead of creating two competing receipts.
    local id=item.link:match("item:(%d+)")
    for key,route in pairs(routes) do
        if route.source==item.source and route.link:match("item:(%d+)")==id
            and not route.finished and not route.failed and not route.cleared and not route.guid
            and not (self.corpseAttempts and self.corpseAttempts[key])
            and (not route.started or (self.corpseActions and self.corpseActions["corpseStarted:"..key]))
            and route.revision==(self.state.lootConfigRevision or 0)
            and self.Client:ServerTime()-route.time<=60 then return key,route end
    end
    return token
end
function A:ReduceLootConfiguration(sender,p)
    local s=self.state
    if p.op=="lootConfiguration" then
        if sender~=self.leader or p.expectedRevision~=(s.lootConfigRevision or 0) then return false,"Only the Raid Leader can change the current Loot Configuration. Reopen the setting and try again." end
        local c=self:CleanLootConfiguration(p.settings);if not c then return false,"Invalid Loot Configuration." end
        if self.RememberNativePolicy then self:RememberNativePolicy() end
        s.lootConfiguration=c;s.autoCollect=c.collection;s.lootConfigRevision=(s.lootConfigRevision or 0)+1
        -- Cancel prepared actions when rules change. Already awarded deliveries retain their recipient.
        self:CancelPreparedCorpseRoutes()
        if not self.demo then SanguineLootCouncilDB.lootConfiguration=self.Copy(c) end
        return true
    end
    if self.demo then return false,"Automatic distribution is disabled in test mode." end
    if p.op=="routeLoot" then
        if sender~=s.master or s.masterBlocked then return false,"Only the Master Looter routes loot." end
        local entry=self:TrackedByID(p.tracked or 0);local policy=entry and entry.routePolicy
        local rule=entry and self:AutomaticLootRule(entry.quality)
        if not entry or entry.item or entry.guid~=p.guid or not policy or not rule or policy.revision~=(s.lootConfigRevision or 0)
            or rule.target~=policy.target or rule.reason~=policy.reason or entry.verifiedHolder~=true or entry.kind=="missing"
            or not entry.observedAt or self.Client:ServerTime()-entry.observedAt>90 then return false,"Loot or its routing rule changed." end
        return self:MakeAutomaticAward(entry,policy,sender,false)
    end
    s.corpseRoutes=s.corpseRoutes or {}
    if p.op=="corpsePrepare" then
        if sender~=s.master or s.masterBlocked or not self:LootConfiguration().automatic then return false,"Master Loot automation is unavailable." end
        local rule=self:AutomaticLootRule(p.quality)
        if not rule or not self:EquipmentLink(p.link) or not int(p.slot,1,40) or type(p.source)~="string" or #p.source>100 or not p.source:match("^[%w%-]+$") then return false,"Invalid corpse item or quality rule." end
        local token=corpseToken(p.source,p.slot,p.link)
        if s.corpseRoutes[token] then return true,nil,true end
        local total=0
        for key,route in pairs(s.corpseRoutes) do
            if (route.finished and not self:TrackedByGUID(route.guid)) or (not route.ready and self.Client:ServerTime()-route.time>60) then s.corpseRoutes[key]=nil else total=total+1 end
        end
        if total>=80 or #s.items>=40 then return false,"Archive completed loot before routing more items." end
        local target=self:PolicyTarget(rule);if not target or not self.roster[target] then return false,"Automatic recipient is not in the raid." end
        s.corpseRoutes[token]={token=token,source=p.source,slot=p.slot,link=p.link,quality=p.quality,target=target,
            reason=rule.reason,note=rule.note,revision=s.lootConfigRevision or 0,by=sender,time=self.Client:ServerTime()}
        return true
    end
    local intent=type(p.token)=="string" and s.corpseRoutes[p.token]
    if not intent or (intent.revision~=(s.lootConfigRevision or 0) and not intent.started) or intent.failed or self.Client:ServerTime()-intent.time>60 then return false,"Corpse assignment is stale or unavailable." end
    if intent.finished then
        if sender~=intent.by and sender~=intent.target then return false,"Only assignment participants can confirm this delivery." end
        return true,nil,true
    end
    if p.op=="corpseReady" then
        if sender~=intent.target then return false,"Only the recipient can verify their bag snapshot." end
        if intent.ready then return true,nil,true end
        intent.ready=true
    elseif p.op=="corpseStarted" then
        if sender~=s.master or sender~=intent.by or s.masterBlocked or not intent.ready or intent.revision~=(s.lootConfigRevision or 0) or not self:LootConfiguration().automatic then return false,"Corpse routing rules or authority changed." end
        if intent.started then return true,nil,true end
        intent.started=true
    elseif p.op=="corpseCleared" then
        if sender~=s.master or sender~=intent.by or s.masterBlocked or not intent.ready or not intent.started then return false,"Master Loot authority changed." end
        if intent.cleared then return true,nil,true end
        intent.cleared=true
    elseif p.op=="corpseFailed" then
        local stacked=sender==intent.target and p.reason=="stacked" and not intent.ready and not intent.started
        if sender~=intent.by and not stacked then return false,"Only the Master Looter can report this attempt." end
        if stacked then intent.failure="stacked" end
        intent.failed=true
    elseif p.op=="corpseReceipt" then
        if sender~=intent.target or not intent.ready or type(p.guid)~="string" or #p.guid>100 or not p.guid:match("^Item%-[%w%-]+$")
            or p.link~=intent.link or self:TrackedByGUID(p.guid) or (s.retiredGUIDs and s.retiredGUIDs[p.guid]) then return false,"Invalid received bag copy." end
        if intent.guid and intent.guid~=p.guid then return false,"An assignment cannot receive two different copies." end
        for token,other in pairs(s.corpseRoutes) do if token~=p.token and other.guid==p.guid then return false,"This bag copy belongs to another assignment." end end
        if intent.guid==p.guid then return true,nil,true end
        intent.guid=p.guid
    else return false,"Unknown loot configuration action." end
    if intent.cleared and intent.guid then
        if #s.trackedLoot>=80 or #s.items>=40 then return false,"Active loot is full; delivery needs review." end
        local entry={id=self:NextIdentity("tracked"),guid=intent.guid,link=intent.link,quality=intent.quality,holder=intent.target,
            kind="unknown",observedAt=self.Client:ServerTime(),verifiedHolder=true,deliveryRevision=0,deliveryLog={}}
        local ok,why=self:MakeAutomaticAward(entry,intent,intent.by,true);if not ok then return false,why end
        intent.finished=true
    end
    return true
end

-- Snapshots are local and short-lived; the recipient proves the *new* copy, not an old identical bag item.
function A:CorpseBagSnapshot(link)
    if not C_Container then return end
    local expected=self:EquipmentLink(link)
    local itemID=expected and expected:match("item:(%d+)")
    if not itemID then return end
    local getter=C_Item and C_Item.GetItemInfo or GetItemInfo
    local _,_,_,_,_,_,_,maxStack=call(getter,expected)
    if int(maxStack,2,1000000) then return nil,"stacked" end
    local result={}
    for bag=0,math.min(NUM_BAG_SLOTS or 4,5) do
        local n=call(C_Container.GetContainerNumSlots,bag);if not int(n,0,100) then return end
        for slot=1,n do
            local info=call(C_Container.GetContainerItemInfo,bag,slot)
            local bagLink=type(info)=="table" and self:EquipmentLink(info.hyperlink)
            if bagLink and bagLink:match("item:(%d+)")==itemID then
                if info.stackCount~=nil and info.stackCount~=1 then return nil,"stacked" end
                local sample=self:ReadManualBagItem(bag,slot);if not sample then return end
                result[sample.guid]=true
            end
        end
    end
    return result
end
function A:CorpseReservation(guid,link)
    local itemID=type(link)=="string" and link:match("item:(%d+)")
    for token,intent in pairs(self.state and self.state.corpseRoutes or {}) do
        if itemID and intent.target==self.me and intent.link:match("item:(%d+)")==itemID and not intent.finished and not intent.failed and self.Client:ServerTime()-intent.time<=60 then
            local snapshot=self.corpseSnapshots and self.corpseSnapshots[token]
            if snapshot and not snapshot[guid] then return true end
        end
    end
    return false
end
function A:NativeCorpseItem(slot,includeUnavailable)
    if not self.corpseOpen or type(GetLootSlotInfo)~="function" or type(GetLootSlotLink)~="function" or type(GetLootSourceInfo)~="function" then return end
    local link=call(GetLootSlotLink,slot)
    local _,_,quantity,fourth,fifth,sixth,seventh=call(GetLootSlotInfo,slot)
    local quality,locked,quest=fifth,sixth,seventh
    if int(fourth,0,5) and type(fifth)=="boolean" then quality,locked,quest=fourth,fifth,sixth end
    local first,second,third,fourthSource=call(GetLootSourceInfo,slot)
    local source,count,extra=first,second,third
    if first==1 and type(second)=="string" then source,count,extra=second,third,fourthSource end
    if extra~=nil then return end
    if not self:EquipmentLink(link) or not int(quantity,1,10000) or not int(quality,0,5) or type(source)~="string" or count~=quantity then return end
    if not includeUnavailable and (locked or quest) then return end
    return {slot=slot,link=link,quality=quality,source=source,quantity=quantity,locked=locked,quest=quest}
end
function A:SendCorpseAction(op,data,key)
    local sid=self.state and self.state.id
    if self.corpseActionSID~=sid then self.corpseActionSID=sid;self.corpseActions={} end
    local now=self.Client:ServerTime()
    local id=op..":"..(key or data.token)
    local sent=self.corpseActions[id]
    if sent and now>=sent and now-sent<5 then return end
    self.corpseActions[id]=now
    self:Act(op,data)
end
function A:TickLootConfiguration()
    if self.TickNativeLoot then return self:TickNativeLoot() end
    local s=self.state;if not s or self.demo or not self.Client:InRaid() then return end
    if self.corpseSID~=s.id then self.corpseSID=s.id;self.corpseSnapshots={};self.corpseAttempts={};self.routeAttempts={} end
    for token in pairs(self.corpseSnapshots) do
        local intent=s.corpseRoutes and s.corpseRoutes[token]
        if not intent or intent.finished or intent.failed or self.Client:ServerTime()-intent.time>60 then self.corpseSnapshots[token]=nil end
    end
    for id in pairs(self.routeAttempts) do if not self:TrackedByID(id) then self.routeAttempts[id]=nil end end
    local recipientRoutes={}
    for token,intent in pairs(s.corpseRoutes or {}) do
        if intent.target==self.me then recipientRoutes[#recipientRoutes+1]={token=token,intent=intent} end
    end
    table.sort(recipientRoutes,function(a,b)
        local x,y=a.intent,b.intent
        if x.time~=y.time then return x.time<y.time end
        if x.source~=y.source then return x.source<y.source end
        return x.slot<y.slot
    end)
    for _,route in ipairs(recipientRoutes) do
        local token,intent=route.token,route.intent
        if not intent.finished and not intent.failed and self.Client:ServerTime()-intent.time<=60
            and (intent.started or intent.revision==(s.lootConfigRevision or 0)) then
            if intent.target==self.me then
                if not self.corpseSnapshots[token] then
                    local snapshot,reason=self:CorpseBagSnapshot(intent.link)
                    if snapshot then self.corpseSnapshots[token]=snapshot;self:SendCorpseAction("corpseReady",{token=token}) end
                    if reason=="stacked" then self:SendCorpseAction("corpseFailed",{token=token,reason="stacked"}) end
                elseif not intent.ready then
                    self:SendCorpseAction("corpseReady",{token=token})
                elseif intent.ready then
                    local current=self:CorpseBagSnapshot(intent.link);local guid,count=nil,0
                    if current then for candidate in pairs(current) do if not self.corpseSnapshots[token][candidate] then guid,count=candidate,count+1 end end end
                    if count==1 and not intent.guid then self:SendCorpseAction("corpseReceipt",{token=token,guid=guid,link=intent.link}) end
                end
            end
        end
    end
    if not self:IsMaster() or s.masterBlocked or self.Client:Combat() then return end
    for _,entry in ipairs(s.trackedLoot or {}) do
        if entry.routePolicy and not entry.item and not entry.bagAdded and not entry.manual and not self.routeAttempts[entry.id] then
            local policy=entry.routePolicy;local target=self:PolicyTarget(policy);local unit=target and self.roster[target]
            if type(unit)=="string" and call(UnitIsConnected,unit)==true then
                self.routeAttempts[entry.id]=true;self:Act("routeLoot",{tracked=entry.id,guid=entry.guid})
            end
        end
    end
    local actual,status=self:ReadGameMaster()
    if not self.corpseOpen or actual~=self.me or status~="game" or not self:LootConfiguration().automatic then return end
    if type(GetMasterLootCandidate)~="function" or type(GiveMasterLoot)~="function" or type(GetLootThreshold)~="function" then self.lootRoutingStatus="Native Master Loot APIs unavailable";return end
    for token in pairs(self.corpseAttempts) do
        local pending=s.corpseRoutes and s.corpseRoutes[token]
        if pending and not pending.finished and not pending.failed and self.Client:ServerTime()-pending.time<=60 then
            self.lootRoutingStatus=pending.cleared and "Awaiting recipient bag confirmation before the next item" or "Awaiting the current Master Loot delivery"
            return
        end
    end
    local n=call(GetNumLootItems);local threshold=call(GetLootThreshold)
    if not int(n,0,40) or not int(threshold,0,5) then return end
    -- Prepare distinct item IDs together so the next recipient snapshot can
    -- finish before the previous award's larger public update is transmitted.
    -- Copies of one ID need separate baselines, even when their links differ.
    local reservedIDs,stackedIDs,prepared={},{},false
    for _,intent in pairs(s.corpseRoutes or {}) do
        if intent.failed and intent.failure=="stacked" and intent.revision==(s.lootConfigRevision or 0) then
            stackedIDs[intent.source..":"..intent.link:match("item:(%d+)")]=true
        end
        if not intent.finished and not intent.failed and self.Client:ServerTime()-intent.time<=60 then
            reservedIDs[intent.link:match("item:(%d+)")]=true
        end
    end
    for slot=1,n do
        local item=self:NativeCorpseItem(slot)
        if item and item.quality>=threshold and self:AutomaticLootRule(item.quality) then
            local token=corpseToken(item.source,slot,item.link)
            local id=item.link:match("item:(%d+)")
            if not (s.corpseRoutes and s.corpseRoutes[token]) and not reservedIDs[id] and not stackedIDs[item.source..":"..id] then
                self:SendCorpseAction("corpsePrepare",item,token)
                reservedIDs[id],prepared=true,true
            end
        end
    end
    if prepared then return end
    for slot=1,n do
        local item=self:NativeCorpseItem(slot)
        if item and item.quality<threshold and self:AutomaticLootRule(item.quality) then self.lootRoutingStatus="Configured item is below the game Master Loot threshold; distribute it manually or adjust the game loot threshold." end
        if item and item.quality>=threshold and self:AutomaticLootRule(item.quality) then
            local token,intent=self:PreparedCorpseRoute(item)
            local stacked=stackedIDs[item.source..":"..item.link:match("item:(%d+)")]
            if stacked then self.lootRoutingStatus="Stacked materials need manual distribution; continuing eligible single-copy items." end
            -- Terminal assignments must not prevent inspection of later slots.
            if intent and not intent.finished and not intent.failed and self.Client:ServerTime()-intent.time<=60 then
                if intent.ready and intent.by==self.me and intent.link==item.link
                    and intent.revision==(s.lootConfigRevision or 0) and not self.corpseAttempts[token] then
                    local unit=self.roster[intent.target];local candidate
                    if type(unit)=="string" and call(UnitIsConnected,unit)==true then
                        for index=1,40 do local name=call(GetMasterLootCandidate,slot,index);if name and self:Resolve(name)==intent.target then candidate=index;break end end
                    end
                    if candidate then
                        if not intent.started then self:SendCorpseAction("corpseStarted",{token=token});return end
                        self.corpseAttempts[token]={slot=slot}
                        local ok=self.Client:Invoke(GiveMasterLoot,slot,candidate)
                        if not ok then self:Act("corpseFailed",{token=token}) end
                        return
                    end
                    self.lootRoutingStatus="Recipient is not eligible for this corpse item"
                elseif not intent.ready then self.lootRoutingStatus="Awaiting recipient addon and bag verification" end
                -- An unready or ineligible, unsent item must not block a
                -- different ready item. Active sends are gated above.
            end
        end
    end
end
function A:LootConfigurationEvent(event,...)
    if self.NativeLootEvent then return self:NativeLootEvent(event,...) end
    if event=="LOOT_OPENED" or event=="LOOT_READY" or event=="LOOT_SLOT_CLEARED" or event=="LOOT_CLOSED"
        or (event=="BAG_UPDATE_DELAYED" and self.state and next(self.state.corpseRoutes or {})) then self.corpseScanSoon=true end
    if event=="LOOT_OPENED" or event=="LOOT_READY" then self.corpseOpen=true
    elseif event=="LOOT_CLOSED" then
        self.corpseOpen=false
        for token,attempt in pairs(self.corpseAttempts or {}) do
            if not attempt.cleared and self.state and not self.demo then self:Act("corpseFailed",{token=token}) end
        end
        self.corpseAttempts={}
    elseif event=="LOOT_SLOT_CLEARED" and self.state and not self.demo then
        local slot=...
        for token,attempt in pairs(self.corpseAttempts or {}) do if attempt.slot==slot and not attempt.cleared then
            attempt.cleared=true;self:Act("corpseCleared",{token=token});break
        end end
    end
end
