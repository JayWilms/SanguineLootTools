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

function A:ApplyStateChanges(state,edits)
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
    return result
end
