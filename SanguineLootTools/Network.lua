local addonName, A = ...
local PREFIX, PROTOCOL = "SanguineLC", A.protocol
local queue, incoming, completed, serial = {}, {}, {}, 0
-- One pacing gate for this prefix, shared by every queued message/channel.
local nextSendAt,sendInterval=0,0.10
local sendTokens,tokenTime,throttleAt,cleanSends=8,nil,-math.huge,0
local refillRate,lastRateProbe=1,0
local throttleStreak=0
local bootNonce=tostring(math.random(100000,999999))
local unpack = unpack or table.unpack

function A:ResetTestTransport()
    queue,incoming,completed={},{},{}
    self.publicBaseline=nil
end

-- Length-prefixed values; no executable deserialization and no external libraries.
local function encode(v, depth, dictionary)
    depth = (depth or 0) + 1
    assert(depth < 16, "Too deeply nested")
    local t = type(v)
    if t == "nil" then return "z" end
    if t == "boolean" then return v and "t" or "f" end
    if t == "number" then v = tostring(v); return "n" .. #v .. ":" .. v end
    if t == "string" then
        if dictionary and dictionary[v] then return "r"..dictionary[v]..":" end
        return "s" .. #v .. ":" .. v
    end
    assert(t == "table", "Unsupported wire type")
    local parts, count = {}, 0
    for k, value in pairs(v) do
        count = count + 1
        parts[#parts + 1] = encode(k, depth, dictionary)
        parts[#parts + 1] = encode(value, depth, dictionary)
    end
    return "a" .. count .. ":" .. table.concat(parts)
end

local function decode(s)
    if s:sub(1,1)=="l" then s=A:ExpandWire(s:sub(2)) end
    local pos, nodes, dictionary = 1, 0, nil
    local function read(depth)
        nodes = nodes + 1
        assert(depth < 16 and nodes <= 50000, "Wire complexity exceeded")
        local kind = s:sub(pos, pos); pos = pos + 1
        if kind == "z" then return nil end
        if kind == "t" then return true end
        if kind == "f" then return false end
        assert(kind == "s" or kind == "n" or kind == "a" or kind == "r", "Invalid wire tag")
        local colon = s:find(":", pos, true)
        assert(colon and colon - pos <= 7, "Invalid length")
        local raw = s:sub(pos, colon - 1)
        assert(raw:match("^%d+$"), "Invalid length")
        local n = tonumber(raw)
        pos = colon + 1
        if kind == "r" then assert(dictionary and type(dictionary[n])=="string", "Invalid dictionary reference");return dictionary[n] end
        if kind == "a" then
            assert(n <= 10000, "Table too large")
            local result = {}
            for i = 1, n do
                local k = read(depth + 1)
                assert(type(k) == "string" or (type(k) == "number" and k == k), "Invalid table key")
                result[k] = read(depth + 1)
            end
            return result
        end
        assert(n <= #s - pos + 1, "Truncated string")
        local v = s:sub(pos, pos + n - 1); pos = pos + n
        if kind == "n" then
            v = tonumber(v)
            assert(v and v == v and v ~= math.huge and v ~= -math.huge, "Invalid number")
        end
        return v
    end
    if s:sub(1,1)=="d" then pos=2;dictionary=read(0);assert(type(dictionary)=="table" and #dictionary<=256,"Invalid dictionary") end
    local value = read(0)
    assert(pos == #s + 1, "Trailing data")
    return value
end
A.Encode, A.Decode = encode, decode

function A:DictionaryWireEncode(packet)
    local plain=encode(packet)
    local counts={}
    local function count(v)
        if type(v)=="string" and #v>=8 then counts[v]=(counts[v] or 0)+1
        elseif type(v)=="table" then for k,value in pairs(v) do count(k);count(value) end end
    end
    count(packet)
    local values={};for value,n in pairs(counts) do if n>1 then values[#values+1]=value end end
    table.sort(values,function(a,b) local sa,sb=counts[a]*#a,counts[b]*#b;if sa==sb then return a<b end;return sa>sb end)
    local lookup,list={},{}
    for i=1,math.min(256,#values) do list[i]=values[i];lookup[values[i]]=i end
    local packed="d"..encode(list)..encode(packet,0,lookup)
    return #packed<#plain and packed or plain
end
function A:WireEncode(packet)
    local plain=self:DictionaryWireEncode(packet)
    if #plain>524288 then return plain end
    local compressed="l"..self:CompressWire(plain)
    return #compressed<#plain and compressed or plain
end
local function chunks(packet)
    local payload=A:WireEncode(packet)
    if #payload>524288 then return end
    serial=serial+1
    local id=tostring(A.Client:ServerTime()).."-"..bootNonce.."-"..serial
    local count=math.ceil(#payload/180)
    local parts={}
    for i=1,count do parts[i]=id..":"..i..":"..count..":"..payload:sub((i-1)*180+1,i*180) end
    return parts,#payload
end

function A:NetworkMessagePriority(packet,options)
    if packet.kind=="request" and packet.data and packet.data.op=="respond" then return 0 end
    if packet.kind=="ack" and (packet.op=="respond" or packet.op=="responseBatch") then return 0 end
    if options and options.liveResponse then return 1 end
    return (packet.kind=="request" or packet.kind=="error" or packet.kind=="ack" or packet.kind=="sync") and 1
        or ((packet.kind=="stateDelta" or packet.kind=="lootDelta" or packet.kind=="view" or packet.kind=="privateVoting" or packet.kind=="privateVotingBatch") and 2 or 3)
end

function A:Send(packet,target,options)
    if self:IsSoloTest() or not self.Client:InGroup() then return false end
    if not self.Client:InRaid() and self.state and not self.groupTest and packet.kind~="historySync" then return false end
    packet.protocol=PROTOCOL
    options=options or {}
    local priority=self:NetworkMessagePriority(packet,options)
    local key=options.key or ((packet.kind=="privateVoting" and ("private:"..target..":"..packet.data.item))
        or (packet.kind=="view" and packet.full and ("snapshot:"..tostring(target))))
    local previous
    -- A partially sent snapshot must finish; equal-revision sync requests do
    -- not need another copy behind it. Private packets are handled separately.
    if key and packet.kind=="view" and packet.full then
        for _,batch in ipairs(queue) do
            if batch.key==key and batch.kind=="view" and batch.rev==packet.rev
                and batch.sid==(packet.state and packet.state.id or false) then
                if options.liveResponse then
                    for _,pending in ipairs(queue) do
                        if pending.sid==batch.sid and (pending.kind=="view" or pending.kind=="stateDelta" or pending.kind=="lootDelta") then
                            pending.priority=math.min(pending.priority,priority)
                        end
                    end
                end
                return true
            end
        end
    end
    if key then for _,batch in ipairs(queue) do if batch.key==key and batch.index==1 then previous=batch;break end end end
    -- A response delta cannot overtake its public revision/baseline chain,
    -- including a snapshot needed by a joining player. Preserve their FIFO
    -- order while letting this chain pass unrelated background/private data.
    if options.liveResponse then
        local responseSID=packet.sid or (packet.state and packet.state.id)
        for _,batch in ipairs(queue) do
            if batch.sid==responseSID and (batch.kind=="view" or batch.kind=="stateDelta" or batch.kind=="lootDelta") then
                batch.priority=math.min(batch.priority,priority)
            end
        end
    end
    if previous and options.nextState and previous.baseState then
        packet.baseRev=previous.baseRev
        packet.edits=self:StateChanges(previous.baseState,options.nextState)
    end
    if packet.edits and options.baseState then
        packet.edits,packet.templates,packet.releases=self:CompactStateChanges(packet.edits,previous and previous.baseState or options.baseState)
    end
    local parts,size=chunks(packet)
    if not parts then self:Print("Sync exceeds the size limit. Start a new session.");return false end
    local bytes=0;for _,batch in ipairs(queue) do bytes=bytes+batch.bytes end
    if bytes-(previous and previous.bytes or 0)+size>2097152 then
        self.networkMetrics=self.networkMetrics or {};self.networkMetrics.overflows=(self.networkMetrics.overflows or 0)+1
        self:Print("Network queue is full. This action was not queued; wait and use /slt sync.");return false
    end
    local batch=previous or {created=A.Client:Uptime()}
    batch.release=batch.release or options.release
    if batch.release then
        self.networkMetrics=self.networkMetrics or {}
        self.networkMetrics.lastReleaseFragments,self.networkMetrics.lastReleaseBytes=#parts,size
    end
    -- Coalescing a later timer/background change must not demote live data.
    priority=previous and math.min(previous.priority,priority) or priority
    batch.parts,batch.bytes,batch.index,batch.target,batch.priority,batch.key=parts,size,1,target,priority,key
    batch.baseState=batch.baseState or options.baseState
    batch.baseRev=batch.baseRev or packet.baseRev
    batch.kind,batch.op=packet.kind,(packet.data and packet.data.op) or (packet.kind=="historySync" and packet.op)
    batch.historyToken=packet.kind=="historySync" and packet.token or nil
    batch.responseRequest=packet.data and packet.data.responseRequest
    batch.rev,batch.sid=packet.rev,packet.sid or (packet.state and packet.state.id or false)
    if not previous then queue[#queue+1]=batch end
    return true
end

function A:CancelHistorySyncTransport(token)
    for i=#queue,1,-1 do if queue[i].historyToken==token then table.remove(queue,i) end end
end

function A:ServiceCorpseActions()
    if not self.corpseScanSoon then return end
    self.corpseScanSoon=nil
    if self.recoveryPending then return end
    -- Called by the update loop, never recursively from an event or reducer.
    -- Repeated events coalesce; the normal one-second tick remains a fallback.
    self:TickLootConfiguration()
end

function A:NetworkQueueStats()
    local count,oldest,bytes=0,0,0
    for _,batch in ipairs(queue) do count=count+#batch.parts-batch.index+1;oldest=math.max(oldest,A.Client:Uptime()-batch.created);bytes=bytes+batch.bytes end
    self.networkMetrics=self.networkMetrics or {}
    local m=self.networkMetrics
    m.sendInterval,m.refillRate=sendInterval,refillRate
    m.maxFragments=math.max(m.maxFragments or 0,count);m.maxAge=math.max(m.maxAge or 0,oldest);m.maxBytes=math.max(m.maxBytes or 0,bytes)
    return count,oldest,bytes
end

function A:PumpSender()
    if self:IsSoloTest() or not self.Client:InGroup() then queue={};return end
    -- Target Forever restrictions still need native verification. Until then,
    -- retain the existing combat pause, but never silently hold a response.
    if A.Client:Combat() then
        for i=#queue,1,-1 do if queue[i].op=="respond" then
            self:ClearPendingPersonalResponse(queue[i].responseRequest)
            table.remove(queue,i);self:Print("Response not sent: communications are paused in combat. Ask the master looter to reopen responses after combat.")
        end end
        return
    end
    local now=A.Client:Uptime()
    if tokenTime then sendTokens=math.min(8,sendTokens+math.max(0,now-tokenTime)*refillRate) end
    tokenTime=now
    if now+0.000001<nextSendAt or sendTokens+0.000001<1 then return end
    local selected
    for i,batch in ipairs(queue) do
        if (not batch.retryAt or A.Client:Uptime()>=batch.retryAt) and (not selected or batch.priority<queue[selected].priority) then selected=i end
    end
    if not selected then return end
    self:NetworkQueueStats()
    local batch=queue[selected]
    if batch.target and not self.roster[batch.target] then table.remove(queue,selected);return end
    local ok,first,second=self.Client:Call("C_ChatInfo.SendAddonMessage",PREFIX,batch.parts[batch.index],batch.target and "WHISPER" or (self.Client:InRaid() and "RAID" or "PARTY"),batch.target)
    local result=second~=nil and second or first
    self.networkMetrics=self.networkMetrics or {}
    self.networkMetrics.lastResult=type(result)=="number" and result or (result==true and "true" or result==false and "false" or "nil")
    local codes=Enum and Enum.SendAddonMessageResult
    local success=ok and result~=false and (result==nil or result==true or result==(codes and codes.Success or 0))
    if success then
        sendTokens=math.max(0,sendTokens-1);cleanSends=cleanSends+1
        throttleStreak=0
        -- Keep the sustainable allowance conservative. Burst tokens are
        -- separate; successful sends do not imply ten new tokens per second.
        if cleanSends>=4 and now-throttleAt>=10 and now-lastRateProbe>=10 then
            refillRate=math.min(1,refillRate+0.25);lastRateProbe=now;cleanSends=0
            sendInterval=0.10
        end
        nextSendAt=A.Client:Uptime()+sendInterval
        batch.index=batch.index+1;batch.retries=0
        if batch.index>#batch.parts then
            if batch.kind=="historySync" and batch.op=="hello" and self.historySync and self.historySync.token==batch.historyToken then
                self.historySync.helloSent=true;self.historySync.started=now
            end
            table.remove(queue,selected)
        end
    else
        self.networkMetrics.sendFailures=(self.networkMetrics.sendFailures or 0)+1
        local prefixThrottle=result==(codes and codes.AddonMessageThrottle or 3)
        local channelThrottle=result==(codes and codes.ChannelThrottle or 8)
        local lockdown=result==(codes and codes.AddOnMessageLockdown or 11)
        if ok and (prefixThrottle or channelThrottle or lockdown) then
            sendTokens=0;cleanSends=0;throttleAt=now
            refillRate=math.max(0.25,refillRate/2);lastRateProbe=now
            sendInterval=0.10
            throttleStreak=math.min(4,throttleStreak+1)
            -- Repeated rejections extend the cooldown, without discarding
            -- the current fragment or resetting pacing when test mode starts.
            local cooldown=math.max(1/refillRate,math.min(4,0.5*2^(throttleStreak-1)))
            nextSendAt=now+math.max(lockdown and 2 or 0,cooldown)
            self.networkMetrics.throttleEvents=(self.networkMetrics.throttleEvents or 0)+1
            self.networkMetrics.lastThrottleResult,self.networkMetrics.lastThrottleAt=result,now
            return -- Never count temporary throttling towards permanent drop.
        end
        nextSendAt=A.Client:Uptime()+sendInterval
        batch.retries=(batch.retries or 0)+1
        if batch.retries>=20 then self:ClearPendingPersonalResponse(batch.responseRequest);table.remove(queue,selected);self:Print("A network message failed. Check the raid connection and use /slt sync.") end
    end
end

function A:RequestSync()
    if self.RetryRecovery and self:RetryRecovery() then return end
    if self:IsSoloTest() or self:IsLeader() or not self.leader then return end
    if self.lastSync and A.Client:Uptime() - self.lastSync < 10 then return end
    self.lastSync = A.Client:Uptime()
    local needPrivate = {}
    if self.state and (self:IsCouncil() or self:IsMaster()) then
        for _, item in ipairs(self.state.items) do
            local v = self.privateVoting and self.privateVoting[item.id]
            if item.voting ~= "idle" and (not v or v.sid ~= self.state.id or v.round ~= item.round or v.ballotVersion ~= item.ballotVersion) then needPrivate[item.id] = true end
        end
    end
    self:Send({kind = "sync", rev = self.rev, sid = self.state and self.state.id, needPrivate = needPrivate}, self.leader)
end

-- Public views contain no ballot identities or candidate totals.
function A:PublicItem(item, slim)
    local result = self.Copy(item)
    result.ballots, result.votes, result.closedResults, result.ballotInvalidations = nil, nil, nil, nil
    result.progress = select(3, self:BallotTotals(item))
    if slim then result.link, result.responses = nil, nil end
    return result
end

function A:SendPrivate(target,itemID)
    local state=self.state
    if not self:IsCouncilMember(target) then return end
    local values={}
    for _,item in ipairs(state.items) do
        if item.voting~="idle" and (not itemID or item.id==itemID or (type(itemID)=="table" and itemID[item.id])) then
            local private=self:PrivateVoting(item,target)
            private.sid,private.item,private.round,private.ballotVersion=state.id,item.id,item.round,item.ballotVersion
            values[#values+1]=private
        end
    end
    if #values==1 then self:Send({kind="privateVoting",data=values[1]},target)
    elseif #values>1 then self:Send({kind="privateVotingBatch",data=values},target,{key="privateBatch:"..target}) end
end

function A:SendView(target, full, itemID, slim)
    local projected = false
    if self.state then
        projected = self.Copy(self.state)
        projected.items = {}
        for _, item in ipairs(self.state.items) do
            if full then projected.items[#projected.items+1]=self:PublicItem(item,slim)
            elseif item.id==itemID then projected.items[item.id]=self:PublicItem(item,slim) end
        end
    end
    local options
    if full and not target and projected then
        for _,batch in ipairs(queue) do
            if batch.sid==projected.id and (batch.kind=="stateDelta" or batch.kind=="lootDelta") and batch.priority<=1 then
                options={liveResponse=true};break
            end
        end
    end
    local sent=self:Send({kind = "view", full = full, slim = slim or false, rev = self.rev, state = projected, ended = not projected and self.lastEndedSession or nil}, target,options)
    if sent and full and not target and self:IsLeader() then
        -- This broadcast snapshot contains these edits already. Future deltas
        -- start from it; do not send obsolete unsent edits alongside recovery.
        for i=#queue,1,-1 do
            local batch=queue[i]
            if batch.index==1 and (batch.kind=="stateDelta" or batch.kind=="lootDelta") and batch.rev and batch.rev<=self.rev then table.remove(queue,i) end
        end
        self.publicBaseline=self:PublicState()
    end
    if target then self:SendPrivate(target, full and nil or itemID) end
end

function A:Publish(p)
    if self:IsSoloTest() or self.preparingGroupTest then return end
    self.publishedRoster = self:RosterKey()
    if self.ChooseRecoveryBackup then self:ChooseRecoveryBackup() end
    local current=self:PublicState()
    if not p then
        self:SendView(nil,true);self.publicBaseline=current
        if self.state then for target in pairs(self.roster) do if target~=self.me then self:SendPrivate(target) end end end
        return
    end
    if p and (p.op=="tradeActivity" or p.op=="lootReport") then
        local old=self.publicBaseline
        if old and current and current.id==old.id then
            self:Send({kind="lootDelta",sid=current.id,baseRev=self.rev-1,rev=self.rev,
                edits=self:StateChanges(old,current),entries={},
                activity=p.op=="tradeActivity" and {holder=p.activityHolder,value=self.Copy(self.state.tradeActivity[p.activityHolder])} or nil},nil,
                {key="delta:"..current.id,baseState=old,nextState=current})
        else self:SendView(nil,true) end
        self.publicBaseline=current
        return
    end
    local corpseAction=type(p.op)=="string" and p.op:match("^corpse")~=nil
    local id=p and p.item
    if current and self.publicBaseline and current.id==self.publicBaseline.id then
        local old=self.publicBaseline
        self:Send({kind="stateDelta",sid=current.id,baseRev=self.rev-1,rev=self.rev,edits=self:StateChanges(old,current)},nil,
            {key="delta:"..current.id,baseState=old,nextState=current,liveResponse=corpseAction or p.op=="respond" or p.op=="queueLoot" or p.op=="open",release=p.op=="queueLoot"})
    else self:SendView(nil,true) end
    self.publicBaseline=current
    -- Corpse handshakes do not change private ballots. Their public deltas
    -- carry the receipt/award without resending every council member's view.
    if self.state and not corpseAction then for target in pairs(self.roster) do
        if target~=self.me then self:SendPrivate(target,id) end
    end end
end

-- Combine simultaneous confirmations so a raid's response burst does not
-- require one outbound message per player. Response choices are already public.
function A:QueuePersonalReceipt(sender,item,response,request)
    local sid=self.state.id;local key,rows
    for _,batch in ipairs(queue) do
        if batch.ackSid==sid and batch.index==1 then
            local found
            for i,row in ipairs(batch.receipts) do if row[1]==sender and row[2]==item.id then found=i;break end end
            if found or #batch.receipts<32 then key,rows=batch.key,self.Copy(batch.receipts);break end
        end
    end
    if not key then
        self.receiptBatchSerial=(self.receiptBatchSerial or 0)+1
        key="receipts:"..sid..":"..self.receiptBatchSerial;rows={}
    end
    local value={sender,item.id,item.responseRound,response.choice,response.revision,request}
    local found
    for i,row in ipairs(rows) do if row[1]==sender and row[2]==item.id then rows[i]=value;found=true;break end end
    if not found then rows[#rows+1]=value end
    if self:Send({kind="ack",op="responseBatch",sid=sid,data=rows},nil,{key=key}) then
        for _,batch in ipairs(queue) do if batch.key==key and batch.index==1 then batch.ackSid,batch.receipts=sid,rows;break end end
    end
end

function A:QuietBackgroundRejection(p,why)
    local op=type(p)=="table" and p.op
    local key
    if type(op)=="string" and op:match("^corpse") and why=="Corpse assignment is stale or unavailable." then key="staleCorpseRequests"
    elseif op=="tradeActivity" and why=="No pending award for this trade partner." then key="irrelevantTradeReports" end
    if not key then return false end
    self.networkMetrics=self.networkMetrics or {}
    self.networkMetrics[key]=(self.networkMetrics[key] or 0)+1
    return true
end

function A:HostRequest(sender, p)
    local responseRequest=type(p)=="table" and type(p.responseRequest)=="number" and p.responseRequest%1==0
        and p.responseRequest>=1 and p.responseRequest<=1000000000 and p.responseRequest or nil
    if not self:IsSoloTest() and not self:IsLeader() then return end
    if self.recoveryPending and (type(p)~="table" or p.op~="end") then return false end
    if type(p) == "table" and p.op ~= "syncMaster" then self:SyncGameMaster() end
    if type(p) == "table" and (p.op == "award" or p.op == "correctAward") then
        p.awardedAt, p.awardedVotes = A.Client:ServerTime(), 0
        local it = self.state and type(p.item) == "number" and self:ItemByID(p.item)
        local target = self:Resolve(p.target)
        if it and target then p.awardedVotes = self:BallotTotals(it)[target] or 0 end
    end
    if type(p) == "table" and p.op == "tradeActivity" then p.activityHolder = sender end
    if type(p)=="table" and p.op=="lootReport" then p.reportHolder=sender end
    local replaced = type(p)=="table" and p.op=="start" and not self.state and self.recoveryFailed
    local ok, why, unchanged = self:Reduce(sender, p)
    if not ok then
        if type(p)=="table" and p.op=="corpseNativeReceipt" and self.NativeRecordFailure then
            if sender==self.me then self:NativeRecordFailure(p.token,why)
            else self:Send({kind="nativeReceiptError",sid=self.state and self.state.id,token=p.token,reason=why},sender) end
            return false
        end
        if self:QuietBackgroundRejection(p,why) then return false end
        if sender == self.me then self:Print(why)
        else self:Send({kind = "error", message = why, responseRequest=type(p)=="table" and p.op=="respond" and responseRequest or nil}, sender) end
        return false
    end
    if replaced then
        self.state.replacesSession=replaced
        self:EndRecovery()
    end
    if self.AckNativeReceipt then self:AckNativeReceipt(sender,p) end
    if unchanged==true and type(p.op)=="string" and p.op:match("^corpse") then
        self.networkMetrics=self.networkMetrics or {}
        self.networkMetrics.duplicateCorpseRequests=(self.networkMetrics.duplicateCorpseRequests or 0)+1
        return true
    end
    self.rev = self.rev + 1
    if self.state and (self.raidSetupOperations[p.op] or p.op=="profile") and not self.demo then self:RememberRaidSettings(self.state) end
    if p.op == "end" then
        self.lastEndedSession=p.sid
        if self.EndRecovery then self:EndRecovery() end
        self:ClearCheckpoint()
    end
    if self.state then for _, item in ipairs(self.state.items) do self:Record(item) end end
    if p.op=="respond" and sender~=self.me then
        local item=self:ItemByID(p.item);local response=item.responses[sender]
        self:QueuePersonalReceipt(sender,item,response,responseRequest)
    end
    self:Publish(p)
    self:Changed()
    if p.op=="queueLoot" and sender~=self.me then self:Send({kind="ack",op=p.op,rev=self.rev,count=p.entries and #p.entries or 1},sender) end
    if p.op=="end" and self.groupTest then self.demo,self.groupTest=nil,nil end
    return true
end

function A:SendRequestedPrivate(sender,packet)
    if self.state and packet.sid==self.state.id and type(packet.needPrivate)=="table" then
        self:SendPrivate(sender,packet.needPrivate)
    else self:SendPrivate(sender) end
end
function A:PublicDeliveryPending(sid,revision)
    for _,batch in ipairs(queue) do
        if not batch.target and batch.sid==sid and batch.rev and batch.rev>revision then
            if batch.kind=="view" or ((batch.kind=="stateDelta" or batch.kind=="lootDelta") and batch.baseRev==revision)
                or (batch.kind=="lootDelta" and batch.rev==revision+1) then return true end
        end
    end
    return false
end

function A:Packet(sender, packet, channel)
    if type(packet) ~= "table" or not self.roster[sender] then return end
    if self.ignoredTestSID and ((packet.state and type(packet.state)=="table" and packet.state.id==self.ignoredTestSID) or packet.sid==self.ignoredTestSID) then return end
    if self.WarningPacket and self:WarningPacket(sender, packet) then return end
    if self.FeaturePacket and self:FeaturePacket(sender, packet) then return end
    if packet.protocol ~= PROTOCOL then
        self.networkMetrics=self.networkMetrics or {}
        self.networkMetrics.protocolMismatches=(self.networkMetrics.protocolMismatches or 0)+1
        return
    end
    if self.RecoveryPacket and self:RecoveryPacket(sender,packet,channel) then return end
    if self.HistorySyncPacket and self:HistorySyncPacket(sender,packet) then return end
    if self.NativeLootPacket and self:NativeLootPacket(sender,packet) then return end
    if packet.kind == "request" and self:IsLeader() then
        self:HostRequest(sender, packet.data)
    elseif packet.kind == "sync" and self:IsLeader() then
        if self.recoveryPending then return end
        self.syncLimits = self.syncLimits or {}
        if self.syncLimits[sender] and A.Client:Uptime() - self.syncLimits[sender] < 10 then return end
        self.syncLimits[sender] = A.Client:Uptime()
        if packet.rev == self.rev and packet.sid == (self.state and self.state.id) then
            if self.state then self:SendRequestedPrivate(sender,packet) end
            return
        end
        -- The queued delivery will advance this client already. Replacing it
        -- with another full snapshot on every probe creates a recovery storm.
        if self.state and (packet.sid==nil or packet.sid==self.state.id) and type(packet.rev)=="number"
            and self:PublicDeliveryPending(self.state.id,packet.rev) then
            self:SendRequestedPrivate(sender,packet);return
        end
        -- Recovery state is public. Coalesce simultaneous lagging clients into
        -- a raid snapshot instead of queueing the same large view per whisper.
        -- Private ballots still travel only to the authorised requester.
        self:SendView(nil, true)
        self:SendRequestedPrivate(sender,packet)
    elseif sender == self.leader and sender ~= self.me then
        if packet.kind=="ack" and packet.op=="responseBatch" then
            if packet.sid~= (self.state and self.state.id) or type(packet.data)~="table" or #packet.data>32 then return end
            for _,row in ipairs(packet.data) do
                if type(row)=="table" and row[1]==self.me then self:AcceptPersonalReceipt({packet.sid,row[2],row[3],row[4],row[5],row[6]}) end
            end
        elseif packet.kind=="ack" and packet.op=="respond" then
            self:AcceptPersonalReceipt(packet.data)
        elseif packet.kind=="ack" and packet.op=="queueLoot" then
            self:Print("Queue accepted for "..tostring(packet.count).." item(s). Awaiting session update.")
        elseif packet.kind=="stateDelta" or (packet.kind=="lootDelta" and packet.edits~=nil) then
            if type(packet.sid)~="string" or type(packet.rev)~="number" or type(packet.baseRev)~="number" or type(packet.edits)~="table" then return end
            if not self.state or packet.sid~=self.state.id then self:RequestSync();return end
            if packet.rev<=self.rev then return end
            if self.rev~=packet.baseRev then self:RequestSync();return end
            local updated=self:ApplyStateChanges(self.state,packet.edits,packet.templates,packet.releases)
            if not updated or updated.id~=self.state.id or updated.leader~=self.leader or updated.groupTest~=self.state.groupTest then self:RequestSync();return end
            self.state,self.rev=updated,packet.rev
            for _,item in ipairs(updated.items) do self:Record(item) end
            self:Changed()
        elseif packet.kind == "lootDelta" then
            if not self.state or packet.sid ~= self.state.id or type(packet.rev) ~= "number" or type(packet.entries) ~= "table" then return end
            if packet.rev <= self.rev then return end
            if packet.rev ~= self.rev + 1 then self:RequestSync(); return end
            self.state.trackedLoot = self.state.trackedLoot or {}
            for _, entry in ipairs(packet.entries) do self:PutTracked(entry) end
            if packet.nextTrackedID then self.state.nextTrackedID=packet.nextTrackedID end
            if type(packet.lootSequence)=="table" then
                self.state.lootSequences=self.state.lootSequences or {}
                self.state.lootSequences[packet.lootSequence.holder]=packet.lootSequence.value
            end
            if type(packet.activity) == "table" and type(packet.activity.holder) == "string" and type(packet.activity.value) == "table" then
                self.state.tradeActivity = self.state.tradeActivity or {}
                self.state.tradeActivity[packet.activity.holder] = packet.activity.value
            end
            self.rev = packet.rev
            self:Changed()
        elseif packet.kind == "error" and type(packet.message) == "string" then
            self.pendingVotingAdvance=nil
            if packet.responseRequest then self:ClearPendingPersonalResponse(packet.responseRequest);self:Render() end
            self:Print(packet.message)
        elseif packet.kind=="privateVotingBatch" then
            if type(packet.data)~="table" or #packet.data>40 or not self.state then return end
            self.privateVoting=self.privateVoting or {}
            for _,v in ipairs(packet.data) do
                local item=type(v)=="table" and self:ItemByID(v.item)
                if item and v.sid==self.state.id and item.round==v.round and item.ballotVersion==v.ballotVersion then self.privateVoting[v.item]=v end
            end
            if self.Render then self:Render() end
        elseif packet.kind == "privateVoting" then
            local v = packet.data
            if type(v) ~= "table" or type(v.item) ~= "number" or not self.state or v.sid ~= self.state.id then return end
            local item = self:ItemByID(v.item)
            if not item or item.round ~= v.round or item.ballotVersion ~= v.ballotVersion then return end
            self.privateVoting = self.privateVoting or {}
            self.privateVoting[v.item] = v
            if self.Render then self:Render() end
        elseif packet.kind == "view" then
            if type(packet.rev) ~= "number" or type(packet.full) ~= "boolean" then return end
            local s = packet.state
            if s and (type(s) ~= "table" or s.leader ~= self.leader or type(s.items) ~= "table") then return end
            if self.state and not s and (packet.ended~=self.state.id or (not self.recoveryPending and packet.rev<=self.rev)) then return end
            if s and self.state then
                if s.id==self.state.recoveredFrom then return end
                if (s.historyID or s.id)==(self.state.historyID or self.state.id) and packet.rev<self.rev then return end
                if self.recoveryPending and s.id~=self.state.id and s.recoveredFrom~=self.state.id and s.replacesSession~=self.state.id then return end
                -- Only the original host can resume the same transport session,
                -- after WoW reverses a leadership change.
                if self.recoveryPending and s.id==self.state.id and (sender~=self.state.leader or self.recoveryProbeSeen) then return end
            end
            if s and s.groupTest~=nil and s.groupTest~=true then return end
            if s and not self.Client:InRaid() and not s.groupTest then return end
            if s and s.groupTest and self.state and not self.demo then return end
            if s and self.state and s.id==self.state.id and s.groupTest~=self.state.groupTest then return end
            if s and self.state and s.id == self.state.id and packet.rev < self.rev then return end
            if not packet.full then
                if packet.rev <= self.rev then return end
                if not self.state or not s or self.state.id ~= s.id or packet.rev ~= self.rev + 1 then self:RequestSync(); return end
                local items = self.state.items
                for id, patch in pairs(s.items) do
                    local existing=self:ItemByID(id)
                    if packet.slim then
                        if not existing then self:RequestSync(); return end
                        for key,value in pairs(patch) do existing[key]=value end
                    else
                        local index
                        for i,item in ipairs(items) do if item.id==id then index=i;break end end
                        items[index or (#items+1)]=patch
                    end
                end
                s.items = items
            elseif not self.state or not s or self.state.id ~= s.id then self.privateVoting = {} end
            if self.recoveryPending and self.EndRecovery then
                self:EndRecovery()
                if not s or not self.state or s.id~=self.state.id then self:ResetTestTransport() end
            end
            self.state, self.rev = s or nil, packet.rev
            if s and s.groupTest then self.demo,self.groupTest=true,true
            elseif self.groupTest then self.demo,self.groupTest=nil,nil end
            if self.state then for _, item in ipairs(self.state.items) do self:Record(item) end end
            self:Changed()
        end
    end
end

function A:Receive(prefix, message, channel, rawSender)
    if self:IsSoloTest() or prefix ~= PREFIX or (channel ~= "RAID" and channel ~= "PARTY" and channel ~= "WHISPER") then return end
    if channel=="PARTY" and (self.Client:InRaid() or not self.Client:InGroup()) then return end
    local sender = self:Resolve(rawSender)
    if not sender or sender == self.me or type(message) ~= "string" or #message > 255 then return end
    local id, index, count, chunk = message:match("^([%d%-]+):(%d+):(%d+):(.*)$")
    index, count = tonumber(index), tonumber(count)
    if not id or #id > 40 or not index or not count or index < 1 or index > count or count > 2913 then return end
    -- Only the leader or the explicitly selected recovery source can send
    -- full session snapshots. History and loot requests have smaller limits.
    local historyPeer=self.HistorySyncTransportPeer and self:HistorySyncTransportPeer(sender)
    local largeHistory=historyPeer and count<=365
    local recoveryPeer=channel=="WHISPER" and self.RecoveryTransportPeer and self:RecoveryTransportPeer(sender)
    local largeMaster=sender~=self.leader and count>8
    if largeMaster and not largeHistory and not recoveryPeer and (not self.state or sender~=self.state.master or self.state.masterBlocked or count>48) then return end
    local key = sender .. ":" .. id
    if completed[key] then return end
    local b = incoming[key]
    if not b then
        local active = 0
        for _, batch in pairs(incoming) do if batch.sender == sender then active = active + 1 end end
        if active >= 4 then return end
        b = {history=historyPeer, sender = sender, count = count, parts = {}, received = 0, time = A.Client:Uptime()}
        incoming[key] = b
    end
    if count ~= b.count or b.parts[index] then return end
    b.parts[index], b.received = chunk, b.received + 1
    b.time=A.Client:Uptime() -- expire stalled transfers, not slowly progressing ones
    if historyPeer and self.historySync then self.historySync.activity=b.time;self.historySync.waitSince=b.time end
    if recoveryPeer then self.recovery.untilAt=math.max(self.recovery.untilAt,b.time+30) end
    self.networkMetrics=self.networkMetrics or {}
    self.networkMetrics.receivedFragments=(self.networkMetrics.receivedFragments or 0)+1
    if b.received == count then
        incoming[key] = nil
        completed[key]=A.Client:Uptime()
        local count,oldest,oldestAt=0,nil,math.huge
        for done,at in pairs(completed) do
            if A.Client:Uptime()-at>300 then completed[done]=nil
            else count=count+1;if at<oldestAt then oldest,oldestAt=done,at end end
        end
        if count>512 then completed[oldest]=nil end
        local payload=table.concat(b.parts)
        local limit=(sender==self.leader or recoveryPeer) and 524288 or (largeHistory and 65536 or ((self.state and sender==self.state.master and not self.state.masterBlocked) and 8640 or 1440))
        local expanded=true
        if payload:sub(1,1)=="l" then expanded,payload=pcall(self.ExpandWire,self,payload:sub(2),limit) end
        local ok,packet=false,nil
        local oversized=false
        if expanded and #payload<=limit then
            oversized=sender~=self.leader and #payload>1440
            ok,packet=pcall(decode,payload)
        end
        local metric=ok and "decodedPackets" or "decodeFailures"
        self.networkMetrics[metric]=(self.networkMetrics[metric] or 0)+1
        if ok and (largeMaster or oversized) then
            local request=type(packet)=="table" and packet.kind=="request" and type(packet.data)=="table" and packet.data
            local release=request and request.op=="queueLoot" and type(request.entries)=="table" and #request.entries<=40
            local native=request and request.op=="corpseNativeReceipt" and self.state and sender==self.state.master and #payload<=4096
            local history=historyPeer and type(packet)=="table" and packet.kind=="historySync" and #payload<=65536
            local recovery=recoveryPeer and type(packet)=="table" and packet.kind=="recoveryState"
            if not release and not native and not history and not recovery then return end
        end
        if ok then self:Packet(sender, packet, channel) end
    end
end

local frame = CreateFrame("Frame")
A.events = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
pcall(frame.RegisterEvent,frame,"PARTY_LEADER_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
pcall(frame.RegisterEvent, frame, "PARTY_LOOT_METHOD_CHANGED")
pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_LOOT")
pcall(frame.RegisterEvent, frame, "ITEM_DATA_LOAD_RESULT")
pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
for _,event in ipairs({"LOOT_OPENED","LOOT_READY","LOOT_CLOSED","LOOT_SLOT_CLEARED"}) do pcall(frame.RegisterEvent,frame,event) end
for _, event in ipairs({"TRADE_SHOW", "TRADE_CLOSED", "TRADE_REQUEST_CANCEL","TRADE_ACCEPT_UPDATE","TRADE_PLAYER_ITEM_CHANGED","TRADE_TARGET_ITEM_CHANGED","TRADE_MONEY_CHANGED","UI_INFO_MESSAGE","UI_ERROR_MESSAGE"}) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...)
    if A.DiagnosticEvent then A:DiagnosticEvent(event,(event=="UI_INFO_MESSAGE" or event=="UI_ERROR_MESSAGE") and (...) or nil) end
    if A.TradeEvent and (event:match("^TRADE_") or event=="UI_INFO_MESSAGE" or event=="UI_ERROR_MESSAGE" or event=="BAG_UPDATE_DELAYED") then A:TradeEvent(event,...) end
    if A.LootConfigurationEvent then A:LootConfigurationEvent(event,...) end
    if A.LootEvent then A:LootEvent(event, ...) end
    if event == "ADDON_LOADED" then
        if (...) ~= addonName then return end
        SanguineLootCouncilDB = SanguineLootCouncilDB or {}
        SanguineLootCouncilDB.history = SanguineLootCouncilDB.history or {}
        A:InitStorage()
        local ok,registered=A.Client:Call("C_ChatInfo.RegisterAddonMessagePrefix",PREFIX)
        if not ok or registered==false then A:Print("Addon communication API unavailable. Use /slt diagnostics; live communication is unconfirmed.") end
        A:RefreshRoster()
    elseif event == "CHAT_MSG_ADDON" then A:Receive(...)
    elseif event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
        if A.ItemDataLoaded then A:ItemDataLoaded(...) end
    elseif event == "PARTY_LOOT_METHOD_CHANGED" then A:SyncGameMaster()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        if A:IsSoloTest() and A.Client:InGroup() then A.demo, A.state = nil, nil end
        A:RefreshRoster()
        A:SyncGameMaster()
        A.Client:Call("C_Timer.After",1, function() A:RequestSync() end)
    end
end)
local elapsed, syncElapsed, voteElapsed = 0, 0, 0
frame:SetScript("OnUpdate", function(_, dt)
    elapsed, syncElapsed, voteElapsed = elapsed + dt, syncElapsed + dt, voteElapsed + dt
    if voteElapsed >= 1 then
        voteElapsed = 0
        if A.TickRecovery then A:TickRecovery() end
        if not A.recoveryPending then
            A:SyncGameMaster()
            A:TickResponses()
            A:TickVoting()
            A:TickLoot()
            A:TickWarnings()
            if A.SendRecoveryBallots then A:SendRecoveryBallots() end
        end
        if A.TickHistorySync then A:TickHistorySync() end
        A:TickResponseEligibility()
        A:NetworkQueueStats() -- retain transport metrics for Diagnostics only
        if A.ui and (A.ui.main:IsShown() or A.ui.voting:IsShown()) then A:RenderVotingStatus() end
    end
    if elapsed >= 0.10 then
        elapsed = 0
        A:ServiceCorpseActions()
        A:PumpSender()
    end
    if syncElapsed >= 30 then
        syncElapsed = 0
        for key, b in pairs(incoming) do if A.Client:Uptime() - b.time > 300 then incoming[key] = nil end end
        -- Periodic recovery also catches a lost final event with no later gap.
        A:RequestSync()
    end
end)
