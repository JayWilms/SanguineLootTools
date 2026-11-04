local _, A = ...
local SCHEMA, TIMEOUT = 1, 600

local function integer(v,low,high)
    return type(v)=="number" and v==v and v%1==0 and v>=low and v<=high
end
local function stringValue(v,limit)
    return type(v)=="string" and #v>0 and #v<=limit and not v:find("%c")
end
local function snapshot(v)
    if type(v)~="table" or not stringValue(v.winner,100) or not integer(v.time,0,100000000000) then return false end
    for _,field in ipairs({"responseLabel","awardReason","awardNote","master","timeSource"}) do
        if v[field]~=nil and (type(v[field])~="string" or #v[field]>1024 or v[field]:find("%c")) then return false end
    end
    return (v.response==nil or integer(v.response,1,20)) and (v.votes==nil or integer(v.votes,0,40))
end

-- Bound nested audits before copying any peer-provided record into saved data.
function A:ValidHistorySyncRecord(r)
    if not snapshot(r) or not stringValue(r.key,200) or not stringValue(r.item,1024) or not r.item:match("item:%d+") then return false end
    if r.revision~=nil and not integer(r.revision,1,11) then return false end
    if r.deliveryRevision~=nil and not integer(r.deliveryRevision,0,1000000) then return false end
    if r.quality~=nil and not integer(r.quality,0,8) then return false end
    if r.quantity~=nil and not integer(r.quantity,1,1000000) then return false end
    if r.archivedAt~=nil and not integer(r.archivedAt,0,100000000000) then return false end
    if r.original~=nil and not snapshot(r.original) then return false end
    if r.corrections~=nil then
        if type(r.corrections)~="table" or #r.corrections>10 then return false end
        for _,c in ipairs(r.corrections) do
            if type(c)~="table" or not stringValue(c.from,100) or not stringValue(c.to,100) or not stringValue(c.by,100)
                or not stringValue(c.reason,160) or not integer(c.revision,2,11) or not integer(c.time,0,100000000000) then return false end
        end
    end
    if r.delivery~=nil then
        local d=r.delivery
        if type(d)~="table" or not stringValue(d.status,40) or not stringValue(d.holder,100)
            or (d.log~=nil and (type(d.log)~="table" or #d.log>25)) then return false end
        for _,e in ipairs(d.log or {}) do
            if type(e)~="table" or not stringValue(e.action,100) or not integer(e.time,0,100000000000) then return false end
            for _,field in ipairs({"by","to","from"}) do if e[field]~=nil and not stringValue(e[field],100) then return false end end
        end
    end
    local nodes=0
    local function bounded(v,depth)
        nodes=nodes+1
        if depth>8 or nodes>1500 then return false end
        if type(v)=="table" then
            for k,value in pairs(v) do
                if not ((type(k)=="string" and #k<=100) or integer(k,1,1500)) or not bounded(value,depth+1) then return false end
            end
        elseif type(v)=="string" then return #v<=1024
        elseif type(v)=="number" then return v==v and v~=math.huge and v~=-math.huge
        elseif type(v)~="boolean" then return false end
        return true
    end
    return bounded(r,0)
end

local function version(r)
    return {r.key,r.revision or 1,r.deliveryRevision or 0,r.archivedAt or 0}
end
local function newer(a,b)
    if not b then return true end
    for i=2,4 do if a[i]~=b[i] then return a[i]>b[i] end end
    return false
end
local function sortRecords(records)
    table.sort(records,function(a,b)
        if (a.time or 0)~=(b.time or 0) then return (a.time or 0)>(b.time or 0) end
        return a.key<b.key
    end)
end

local function manifestDigest(rows)
    local parts={}
    for _,v in ipairs(rows) do parts[#parts+1]=#v[1]..":"..v[1]..":"..v[2]..":"..v[3]..":"..v[4] end
    table.sort(parts)
    local first,second=1,7
    local payload=table.concat(parts,";")
    for i=1,#payload do local b=payload:byte(i);first=(first*31+b)%2147483647;second=(second*47+b)%2147483629 end
    return tostring(first).."-"..tostring(second)
end

function A:HistorySyncSnapshot()
    self:InitStorage()
    local records,index,manifest={},{},{}
    for _,r in ipairs(SanguineLootCouncilDB.history) do
        if self:ValidHistorySyncRecord(r) and self:HistoryItemQuality(r.item,r.quality)~=2 then
            local old=index[r.key]
            if not old or newer(version(r),version(old)) then index[r.key]=self.Copy(r) end
        end
    end
    for _,r in pairs(index) do records[#records+1]=r end
    sortRecords(records)
    for i=#records,501,-1 do index[records[i].key]=nil;table.remove(records,i) end
    for _,r in ipairs(records) do manifest[#manifest+1]=version(r) end
    return records,index,manifest
end

function A:MergeHistorySyncRecords(records)
    self:InitStorage()
    local index={}
    for _,r in ipairs(SanguineLootCouncilDB.history) do
        -- Preserve locally retained legacy records even if they cannot be exported.
        if type(r.key)=="string" then index[r.key]=self.Copy(r) end
    end
    local added,updated=0,0
    for _,r in ipairs(records) do
        if not self:ValidHistorySyncRecord(r) then return false end
    end
    for _,r in ipairs(records) do
        if self:HistoryItemQuality(r.item,r.quality)~=2 then
            local old=index[r.key]
            if not old or newer(version(r),version(old)) then
                if old then updated=updated+1 else added=added+1 end
                index[r.key]=self.Copy(r)
            end
        end
    end
    local merged={}
    for _,r in pairs(index) do merged[#merged+1]=r end
    sortRecords(merged)
    while #merged>500 do table.remove(merged) end
    SanguineLootCouncilDB.history=merged
    return true,added,updated
end

function A:CanStartHistorySync(name)
    if self.demo or not name or not self.roster[name] then return false end
    if name==self.leader then return true end
    local settings=self.state or (SanguineLootCouncilDB and SanguineLootCouncilDB.raidSetup) or {}
    return name==settings.master or (settings.council and settings.council[name]==true) or false
end

function A:HistorySyncTransportPeer(sender)
    local s=self.historySync
    return s and self.roster[sender] and (sender==s.host or (s.host==self.me and s.ready[sender])) or false
end

function A:HistorySyncSend(op,fields,target)
    local s=self.historySync
    if not s then return false end
    local p=fields or {};p.kind="historySync";p.schema=SCHEMA;p.op=op;p.token=s.token
    s.activity=self.Client:Uptime()
    if #self.Encode(p)>65000 then return false end
    return self:Send(p,target,{key="historySync:"..s.token..":"..tostring(target)..":"..op..":"..tostring(p.seq or "")})
end

function A:RenderHistorySyncUI()
    local u=self.ui
    if not u or not u.historySync then return end
    u.historySync:SetText(self.historySync and "Syncing…" or "Sync History")
    u.historySync:SetEnabled(not self.historySync and self.Client:InGroup() and self:CanStartHistorySync(self.me))
    u.historySyncStatus:SetText(self.historySyncMessage or "")
end

function A:HistorySyncStatus(message)
    self.historySyncMessage=message
    self:RenderHistorySyncUI()
end

function A:StartHistorySync()
    self:InitStorage()
    if self.historySync then self:Print("History sync is already running.");return false end
    if self.demo or not self.Client:InGroup() or not self:CanStartHistorySync(self.me) then
        self:Print("Join a group as raid leader, master looter or configured council member to sync History.");return false
    end
    if self.Client:Combat() then self:Print("Start History sync after combat.");return false end
    local now=self.Client:Uptime()
    if self.lastHistorySync and now-self.lastHistorySync<30 then self:Print("Please wait 30 seconds between History syncs.");return false end
    self.lastHistorySync=now
    local expected={}
    for name in pairs(self.roster) do if name~=self.me then expected[name]=true end end
    if not next(expected) then self:Print("No other group members are available to sync History.");return false end
    local _,_,manifest=self:HistorySyncSnapshot()
    local known={};for _,row in ipairs(manifest) do known[row[1]]=row end
    self.historySync={digestManifests={[manifestDigest(manifest)]=known},host=self.me,token=tostring(self.Client:ServerTime())..":"..tostring(math.random(100000,999999))..":"..self.me,
        stage="collect",ready={},skippedPeers={},expected=expected,started=now,activity=now,heartbeat=now,manifests={},synced=0,added=0,updated=0,skipped=0}
    self:HistorySyncStatus("Finding History peers…")
    if not self:HistorySyncSend("hello") then self:FinishHistorySync(false,"History sync could not be queued.");return false end
    return true
end

function A:FinishHistorySync(ok,message)
    local s=self.historySync
    if not s then return end
    if self.CancelHistorySyncTransport then self:CancelHistorySyncTransport(s.token) end
    if s.host==self.me then self:HistorySyncSend("finish",{ok=ok,message=message}) end
    self.historySync=nil
    self:HistorySyncStatus(message)
    self:Print(message)
    if self.ui and self.ui.history and self.ui.history:IsShown() then self:ShowHistory(self.historyFilter,self.historyGuildBank) end
end

local function manifestIndex(rows)
    if type(rows)~="table" or #rows>500 then return end
    local result={}
    for _,v in ipairs(rows) do
        if type(v)~="table" or not stringValue(v[1],200) or result[v[1]] or not integer(v[2],1,11)
            or not integer(v[3],0,1000000) or not integer(v[4],0,100000000000) then return end
        result[v[1]]=v
    end
    return result
end

function A:HistorySyncNextPeer()
    local s=self.historySync
    s.peerIndex=(s.peerIndex or 0)+1
    local peer=s.peers[s.peerIndex]
    if not peer then
        if s.stage=="pull" then
            s.records,s.index=self:HistorySyncSnapshot()
            s.stage,s.peerIndex="push",0
            return self:HistorySyncNextPeer()
        end
        local message="History sync finished: "..s.synced.." member(s) updated; "..s.skipped.." unavailable. Latest 500 records retained."
        return self:FinishHistorySync(s.skipped==0,message)
    end
    if not self.roster[peer] then
        if not s.skippedPeers[peer] then s.skipped=s.skipped+1;s.skippedPeers[peer]=true end
        return self:HistorySyncNextPeer()
    end
    s.peer,s.waitSince=peer,self.Client:Uptime()
    self:HistorySyncStatus((s.stage=="pull" and "Collecting History: " or "Sharing History: ")..s.peerIndex.."/"..#s.peers)
    if s.stage=="pull" then
        local cached=s.digestManifests[s.ready[peer]]
        if cached then s.manifests[peer]=cached;return self:HistorySyncNextPeer() end
        s.seq=1
        if not self:HistorySyncSend("scan",nil,peer) then self:FinishHistorySync(false,"History sync incomplete: could not queue request. Try again.") end
    else
        local records={}
        local known=s.manifests[peer] or {}
        for _,r in ipairs(s.records) do if newer(version(r),known[r.key]) then records[#records+1]=r end end
        s.transfer={records=records,cursor=1,seq=1,phase="push",target=peer}
        self:HistorySyncSendPage()
    end
end

-- Stop-and-wait pages bound the queue and leave live loot/response traffic ahead.
function A:HistorySyncSendPage()
    local s=self.historySync;local t=s and s.transfer
    if not t then return end
    local page={}
    while t.cursor<=#t.records and #page<10 do
        page[#page+1]=t.records[t.cursor]
        if #self.Encode(page)>30000 then page[#page]=nil;break end
        t.cursor=t.cursor+1
    end
    if #page==0 and t.cursor<=#t.records then return self:FinishHistorySync(false,"History sync incomplete: an audit exceeds the transfer limit.") end
    t.done=t.cursor>#t.records
    if not self:HistorySyncSend("data",{records=page,seq=t.seq,phase=t.phase,done=t.done},t.target) then
        self:FinishHistorySync(false,"History sync incomplete: network queue full. Try again.")
    end
end

function A:HistorySyncPacket(sender,p)
    if p.kind~="historySync" then return false end
    if p.schema~=SCHEMA or self.demo or not self.roster[sender] or sender==self.me or not stringValue(p.token,200) then return true end
    local now=self.Client:Uptime()
    local s=self.historySync
    if p.op=="hello" then
        if not self:CanStartHistorySync(sender) or s then return true end
        if self.historySyncHelloAt and now-self.historySyncHelloAt<30 then return true end
        self.historySyncHelloAt=now
        local _,export,manifest=self:HistorySyncSnapshot()
        s={host=sender,token=p.token,activity=now,ready={},added=0,updated=0,export=export,manifest=manifest}
        self.historySync=s
        self:HistorySyncStatus("History sync in progress…")
        if not self:HistorySyncSend("ready",{digest=manifestDigest(manifest)},sender) then self:FinishHistorySync(false,"History sync incomplete: network queue full.") end
        return true
    end
    if not s or s.token~=p.token then return true end
    if s.host~=self.me and sender~=s.host then return true end
    if s.host==self.me and not s.expected[sender] then return true end
    s.activity=now
    if p.op=="ready" and s.host==self.me and s.stage=="collect" then
        if type(p.digest)=="string" and #p.digest<=30 and p.digest:match("^%d+%-%d+$") then s.ready[sender]=p.digest end
    elseif p.op=="keepalive" and sender==s.host then
        -- Keep waiting peers alive while the coordinator visits other members.
    elseif p.op=="scan" and sender==s.host then
        if not self:HistorySyncSend("manifest",{rows=s.manifest},sender) then
            self:FinishHistorySync(false,"History sync incomplete: manifest could not be queued. Try again.")
        end
    elseif p.op=="manifest" and s.host==self.me and s.stage=="pull" and s.peer==sender then
        local remote=manifestIndex(p.rows)
        if not remote or manifestDigest(p.rows)~=s.ready[sender] then return true end
        s.manifests[sender]=remote
        s.digestManifests[s.ready[sender]]=remote
        local _,localIndex=self:HistorySyncSnapshot();local keys={};s.requested={}
        for key,v in pairs(remote) do
            if newer(v,localIndex[key] and version(localIndex[key])) then keys[#keys+1]=key;s.requested[key]=true end
        end
        table.sort(keys)
        if not self:HistorySyncSend("fetch",{keys=keys},sender) then
            self:FinishHistorySync(false,"History sync incomplete: request could not be queued. Try again.")
        end
    elseif p.op=="fetch" and sender==s.host and s.export then
        if type(p.keys)~="table" or #p.keys>500 then return true end
        local records,seen={},{}
        for _,key in ipairs(p.keys) do
            if not stringValue(key,200) or seen[key] or not s.export[key] then return true end
            seen[key]=true;records[#records+1]=s.export[key]
        end
        s.transfer={records=records,cursor=1,seq=1,phase="pull",target=sender}
        self:HistorySyncSendPage()
    elseif p.op=="data" then
        local pulling=s.host==self.me and s.stage=="pull" and s.peer==sender and p.phase=="pull" and s.requested
        local pushing=s.host~=self.me and sender==s.host and p.phase=="push"
        if not (pulling or pushing) or not integer(p.seq,1,501) or type(p.done)~="boolean" or type(p.records)~="table" or #p.records>10 then return true end
        local expected=pulling and s.seq or (s.pushSeq or 1)
        if p.seq~=expected then return true end
        for _,r in ipairs(p.records) do
            if not self:ValidHistorySyncRecord(r) or (pulling and not s.requested[r.key]) then return true end
        end
        local ok,added,updated=self:MergeHistorySyncRecords(p.records)
        if not ok then return true end
        s.added,s.updated=s.added+added,s.updated+updated
        for _,r in ipairs(p.records) do if pulling then s.requested[r.key]=nil end end
        if pulling and p.done and next(s.requested) then return true end
        self:HistorySyncSend("ack",{seq=p.seq,phase=p.phase},sender)
        if pulling then
            s.seq=s.seq+1;s.waitSince=now
            if p.done then self:HistorySyncNextPeer() end
        else
            s.pushSeq=expected+1
        end
    elseif p.op=="ack" then
        local t=s.transfer
        if not t or t.target~=sender or t.seq~=p.seq or t.phase~=p.phase then return true end
        s.waitSince=now
        if t.done then
            s.transfer=nil
            if s.host==self.me then s.synced=s.synced+1;self:HistorySyncNextPeer() end
        else t.seq=t.seq+1;self:HistorySyncSendPage() end
    elseif p.op=="finish" and sender==s.host and type(p.ok)=="boolean" and stringValue(p.message,250) then
        self:FinishHistorySync(p.ok,p.message)
    end
    return true
end

function A:TickHistorySync()
    local s=self.historySync
    if not s then return end
    local now=self.Client:Uptime()
    if self.demo or not self.Client:InGroup() or (s.host~=self.me and not self.roster[s.host]) then
        return self:FinishHistorySync(false,"History sync stopped: group changed. Received records were retained.")
    end
    if self.Client:Combat() then
        s.activity=now;s.waitSince=now;s.wasCombat=true
        if s.stage=="collect" then s.started=now end
        self:HistorySyncStatus("History sync paused in combat")
        return
    end
    if s.wasCombat then s.wasCombat=nil;self:HistorySyncStatus("History sync resumed…") end
    if now-(s.waitSince or s.activity)>TIMEOUT then
        return self:FinishHistorySync(false,"History sync incomplete: peer timed out. Received records were retained; try again.")
    end
    if s.host==self.me then
        if now-s.heartbeat>=60 then s.heartbeat=now;self:HistorySyncSend("keepalive") end
        if s.stage=="collect" and s.helloSent and now-s.started>=15 then
            s.peers={}
            for name in pairs(s.expected) do if s.ready[name] and self.roster[name] then s.peers[#s.peers+1]=name else s.skipped=s.skipped+1 end end
            table.sort(s.peers)
            if #s.peers==0 then return self:FinishHistorySync(false,"History sync unavailable: no compatible group members replied.") end
            s.stage,s.peerIndex="pull",0
            self:HistorySyncNextPeer()
        end
    end
end
