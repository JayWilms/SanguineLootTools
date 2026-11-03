local _, A = ...
A.limits = {activeItems=40, activeCopies=80, archivedPerSession=500, retainedArchives=500, maxID=1000000000}

-- Active arrays stay dense; identities never depend on a position or get reused.
function A:ItemByID(id)
    for _, item in ipairs(self.state and self.state.items or {}) do if item.id==id then return item end end
end
function A:TrackedByID(id)
    for _, entry in ipairs(self.state and self.state.trackedLoot or {}) do if entry.id==id then return entry end end
end
function A:PutTracked(entry)
    local entries=self.state.trackedLoot
    for i, old in ipairs(entries) do if old.id==entry.id then entries[i]=entry;return end end
    entries[#entries+1]=entry
end
function A:NextIdentity(kind)
    local s=self.state
    local key=kind=="item" and "nextItemID" or "nextTrackedID"
    local list=kind=="item" and s.items or s.trackedLoot
    local n=s[key] or 0
    for _, value in ipairs(list or {}) do n=math.max(n,value.id) end
    s[key]=n+1
    return s[key]
end
function A:ArchivableItems()
    local result={}
    for _, item in ipairs(self.state and self.state.items or {}) do
        local entry=self:TrackedForItem(item)
        if item.status=="awarded" and entry and entry.delivery=="delivered" and entry.deliveredTo==item.winner then
            result[#result+1]=item
        end
    end
    return result
end
function A:ReduceArchive(sender,p)
    local s=self.state
    if sender~=s.master or s.masterBlocked then return false,"Only the current master looter archives completed loot." end
    if p.expectedRevision~=self.rev then return false,"The session changed. Review completed loot again." end
    local completed=self:ArchivableItems()
    if #completed==0 then return false,"No confirmed deliveries to archive." end
    if (s.archivedCount or 0)+#completed>self.limits.archivedPerSession then
        return false,"Session archive limit reached (500). Resolve pending work before ending this session."
    end
    self:InitStorage()
    local retained=SanguineLootCouncilDB.archives
    local removeItems,removeCopies={},{}
    s.retiredGUIDs=s.retiredGUIDs or {}
    for _, item in ipairs(completed) do
        local entry=self:TrackedForItem(item)
        self:Record(item)
        local key=(s.historyID or s.id)..":"..item.id
        for _, record in ipairs(SanguineLootCouncilDB.history) do
            if record.key==key then record.archivedAt=A.Client:ServerTime() end
        end
        if not self.demo then
            retained[#retained+1]={key=key, archivedAt=A.Client:ServerTime(),
                by=sender,item=self:PublicItem(item),tracked=self.Copy(entry)}
        end
        removeItems[item.id],removeCopies[entry.id]=true,true
        if entry.guid then s.retiredGUIDs[entry.guid]=true end
    end
    local items,copies={},{}
    for _, item in ipairs(s.items) do if not removeItems[item.id] then items[#items+1]=item end end
    for _, entry in ipairs(s.trackedLoot) do if not removeCopies[entry.id] then copies[#copies+1]=entry end end
    -- Freeze next identities before compacting the arrays.
    local maxItem,maxCopy=s.nextItemID or 0,s.nextTrackedID or 0
    for _, item in ipairs(s.items) do maxItem=math.max(maxItem,item.id) end
    for _, entry in ipairs(s.trackedLoot) do maxCopy=math.max(maxCopy,entry.id) end
    s.nextItemID,s.nextTrackedID=maxItem,maxCopy
    s.items,s.trackedLoot=items,copies
    s.archivedCount=(s.archivedCount or 0)+#completed
    while #retained>self.limits.retainedArchives do table.remove(retained,1) end
    return true
end

function A:PruneActiveCaches()
    local s=self.state
    local active={}
    for _, item in ipairs(s and s.items or {}) do
        active[s.id..":"..item.id..":"..(item.responseRound or 0)]=true
        active[s.id..":"..item.id..":"..(item.round or 0)]=true
    end
    for _,name in ipairs({"voteDrafts","candidateOrders","noteDrafts"}) do
        for key in pairs(self[name] or {}) do if not active[key] then self[name][key]=nil end end
    end
    for id in pairs(self.privateVoting or {}) do if not self:ItemByID(id) then self.privateVoting[id]=nil end end
end
function A:ReviewArchive()
    if not self:IsMaster() or not self.state then return end
    local count=#self:ArchivableItems()
    if count==0 then self:Print("No confirmed deliveries to archive.");return end
    local dialog=A:ShowConfirmation("SANGUINELOOTCOUNCIL_ARCHIVE",tostring(count))
    if dialog then dialog.data={sid=self.state.id,expectedRevision=self.rev} end
end
A.confirmationDialogs["SANGUINELOOTCOUNCIL_ARCHIVE"]={
    text="Archive %s confirmed deliveries? Their original awards, corrections and delivery logs remain local audit records. Pending and uncertain work stays active. Archived awards are read-only; finish corrections first.",
    button1="Archive completed",button2="Cancel",timeout=0,whileDead=true,hideOnEscape=true,
    OnAccept=function(dialog)
        local p=dialog.data
        if p and A.state and p.sid==A.state.id then A:Act("archiveCompleted",p) end
    end,
}
