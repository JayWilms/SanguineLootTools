local _,A=...

function A:PublicState()
    if not self.state then return false end
    local state=self.Copy(self.state)
    for id,item in pairs(self.state.items) do state.items[id]=self:PublicItem(item) end
    return state
end

-- Ordered structural edits carry only changed public fields. Explicit deletion
-- avoids retaining old winners, responses or role memberships on recipients.
function A:StateChanges(old,new)
    local edits={}
    local function walk(before,after,path)
        if type(before)=="table" and type(after)=="table" then
            for key in pairs(before) do
                if after[key]==nil then local p=self.Copy(path);p[#p+1]=key;edits[#edits+1]={path=p,remove=true} end
            end
            for key,value in pairs(after) do
                local p=self.Copy(path);p[#p+1]=key;walk(before[key],value,p)
            end
        elseif before~=after then edits[#edits+1]={path=path,value=self.Copy(after)} end
    end
    walk(old,new,{})
    return edits
end

-- A release already has a baseline of physical/simulated tracked copies.
-- Reuse their links/GUIDs, and send identical round settings just once.
function A:CompactStateChanges(edits,base)
    local packed,templates,releases,byGUID,links={},{},{},{},{}
    local stable=true
    for _,edit in ipairs(edits) do
        if edit.path[1]=="trackedLoot" and (#edit.path<=2 or edit.path[3]=="guid") then stable=false end
    end
    for index,entry in ipairs(base and base.trackedLoot or {}) do if entry.guid then byGUID[entry.guid]=index end end
    for i,edit in ipairs(edits) do
        local value=edit.value
        local index=type(value)=="table" and byGUID[value.lootGUID]
        local entry=index and base.trackedLoot[index]
        if #edit.path==2 and edit.path[1]=="items" and entry and entry.link==value.link and value.id then
            local template=self.Copy(value)
            template.id,template.link,template.lootGUID=nil,nil,nil
            local options=type(base.responseOptions)=="table" and #self:StateChanges(base.responseOptions,template.responseOptions)==0
            local rules=type(base.rules)=="table" and #self:StateChanges(base.rules,template.votingRules)==0
            if options then template.responseOptions=nil end
            if rules then template.votingRules=nil end
            template={template,options,rules}
            local found
            for n,existing in ipairs(templates) do
                if #self:StateChanges(existing,template)==0 then found=n;break end
            end
            if not found then templates[#templates+1]=template;found=#templates end
            releases[#releases+1]=table.concat({edit.path[2],index,value.id,found,stable and 1 or 0},",")
            links[index]=value.id
        else packed[#packed+1]=self.Copy(edit) end
    end
    if stable then
        for i=#packed,1,-1 do
            local edit=packed[i]
            if #edit.path==3 and edit.path[1]=="trackedLoot" and edit.path[3]=="item" and links[edit.path[2]]==edit.value and not edit.remove then table.remove(packed,i) end
        end
    end
    return packed,#templates>0 and templates or nil,#releases>0 and table.concat(releases,";") or nil
end

function A:ApplyStateChanges(state,edits,templates,releases)
    local result=self.Copy(state)
    for _,edit in ipairs(edits) do
        local at=result
        if type(edit.path)~="table" or #edit.path==0 or #edit.path>14 then return end
        for i=1,#edit.path-1 do
            at=type(at)=="table" and at[edit.path[i]] or nil
            if type(at)~="table" then return end
        end
        local key=edit.path[#edit.path]
        if type(at)~="table" or (type(key)~="string" and type(key)~="number") then return end
        if edit.remove then at[key]=nil else at[key]=self.Copy(edit.value) end
    end
    if releases~=nil then
        if type(releases)~="string" or #releases==0 or #releases>2000 or releases:find("[^%d,;]") or releases:find(";;") or releases:sub(1,1)==";" or releases:sub(-1)==";"
            or type(templates)~="table" or #templates>40 or type(result.items)~="table" then return end
        local seen,count={},0
        for row in releases:gmatch("[^;]+") do
            local at,index,id,n,link=row:match("^(%d+),(%d+),(%d+),(%d+),([01])$")
            at,index,id,n=tonumber(at),tonumber(index),tonumber(id),tonumber(n)
            count=count+1
            if not at or count>40 or at<1 or at>40 or index<1 or index>80 or id<1 or id>1000000000 or n<1 or n>40 or seen[at] then return end
            seen[at]=true
            local entry=state.trackedLoot and state.trackedLoot[index]
            local template=templates[n]
            if not entry or type(entry.link)~="string" or type(entry.guid)~="string" or type(template)~="table" or type(template[1])~="table" then return end
            local value=self.Copy(template[1])
            if template[2] then value.responseOptions=self.Copy(state.responseOptions) end
            if template[3] then value.votingRules=self.Copy(state.rules) end
            value.id,value.link,value.lootGUID=id,entry.link,entry.guid
            result.items[at]=value
            if link=="1" then
                local tracked=result.trackedLoot and result.trackedLoot[index]
                if not tracked or tracked.guid~=entry.guid then return end
                tracked.item=id
            end
        end
    end
    return result
end
