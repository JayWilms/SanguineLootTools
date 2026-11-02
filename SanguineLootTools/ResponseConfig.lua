local _,A=...
-- iconOnly remains legacy wire/profile metadata; the UI now always uses labels.
function A:DefaultResponses()
    local labels={"BIS","Upgrade","Minor Upgrade","Off-Spec","PvP","Pass"}
    local colors={"4dcc73","9be65b","d7d65b","edaa55","74b3ed","999999"}
    local options={}
    for i,label in ipairs(labels) do options[i]={id=i,label=label,color=colors[i],enabled=true,iconOnly=false} end
    return options
end
function A:CleanResponses(options)
    if type(options)~="table" then return end
    local n,ids,labels,result,nonpass=0,{},{},{},0
    for k in pairs(options) do if type(k)~="number" or k%1~=0 or k<1 or k>9 then return end;n=n+1 end
    if n<2 or n~=#options then return end
    for i,v in ipairs(options) do
        if type(v)~="table" or type(v.id)~="number" or v.id%1~=0 or v.id<1 or v.id>100000 or ids[v.id]
            or type(v.label)~="string" or #v.label<1 or #v.label>18 or v.label:find("[%c|]") or v.label:match("^%s") or v.label:match("%s$")
            or labels[v.label:lower()] or type(v.color)~="string" or not v.color:match("^%x%x%x%x%x%x$")
            or type(v.enabled)~="boolean" or type(v.iconOnly)~="boolean" then return end
        if v.id==6 and (i~=#options or v.label~="Pass" or not v.enabled) then return end
        if v.id~=6 and v.enabled then nonpass=nonpass+1 end
        result[i]={id=v.id,label=v.label,color=v.color:lower(),enabled=v.enabled,iconOnly=v.iconOnly}
        ids[v.id],labels[v.label:lower()]=true,true
    end
    if not ids[6] or nonpass==0 then return end
    return result
end
function A:ResponseOptions(item)
    return item and item.responseOptions or self.state and self.state.responseOptions or SanguineLootCouncilDB and SanguineLootCouncilDB.responseOptions or self:DefaultResponses()
end
function A:ResponseOption(id,item)
    for _,v in ipairs(self:ResponseOptions(item)) do if v.id==id then return v end end
end
function A:ResponseLabel(id,item)
    local v=self:ResponseOption(id,item)
    return v and v.label or self.responses[id] or "Unknown"
end
function A:ResponseRank(id,item)
    for i,v in ipairs(self:ResponseOptions(item)) do if v.id==id then return i end end
    return 1000000
end
function A:ResponseRGB(id,item)
    local v=self:ResponseOption(id,item)
    local db=SanguineLootCouncilDB
    local colors=db and type(db.responseColors)=="table" and db.responseColors[self.me or "local"]
    local personal=type(colors)=="table" and colors[id]
    local hex=type(personal)=="string" and personal:match("^%x%x%x%x%x%x$") and personal or (v and v.color or "e64033")
    return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255
end

function A:PersonalResponseColors()
    self:InitStorage()
    local db=SanguineLootCouncilDB
    if type(db.responseColors)~="table" then db.responseColors={} end
    local key=self.me or "local"
    if type(db.responseColors[key])~="table" then db.responseColors[key]={} end
    return db.responseColors[key]
end

function A:SetPersonalResponseColor(id,hex)
    if not self:ResponseOption(id) or (hex~=nil and (type(hex)~="string" or not hex:match("^%x%x%x%x%x%x$"))) then return false end
    self:PersonalResponseColors()[id]=hex and hex:lower() or nil
    if self.Render then self:Render() end
    return true
end

function A:PickResponseColor(id)
    local option=self:ResponseOption(id)
    if not option then return false end
    self:BuildUI()
    if self.personalColorDraft then self:FocusWindow(self.ui.personalColor);return false end
    local r,g,b=self:ResponseRGB(id)
    self.personalColorDraft={id=id,previous=self:PersonalResponseColors()[id]}
    self.ui.personalColor.title:SetText("Response colour — "..option.label)
    self:ApplyPersonalPickerRGB(math.floor(r*255+0.5),math.floor(g*255+0.5),math.floor(b*255+0.5))
    self.ui.personalColor:ClearAllPoints();self.ui.personalColor:SetPoint("CENTER",self.ui.settingsHub,"CENTER",0,0)
    self.ui.personalColor:Show();self:FocusWindow(self.ui.personalColor)
    return true
end
function A:ApplyPersonalPickerRGB(red,green,blue)
    local d=self.personalColorDraft
    local function valid(v) return type(v)=="number" and v==v and v>=0 and v<=255 end
    if not d or d.updating or not valid(red) or not valid(green) or not valid(blue) then return false end
    d.values={math.floor(red+0.5),math.floor(green+0.5),math.floor(blue+0.5)}
    local hex=string.format("%02x%02x%02x",d.values[1],d.values[2],d.values[3])
    d.updating=true
    if not d.fromWheel then self.ui.personalColorWheel:SetColorRGB(d.values[1]/255,d.values[2]/255,d.values[3]/255) end
    for i,row in ipairs(self.ui.personalColorChannels) do
        row.slider:SetValue(d.values[i])
        if row.input:HasFocus()~=true then row.input:SetText(tostring(d.values[i])) end
    end
    if self.ui.personalColorHex:HasFocus()~=true then self.ui.personalColorHex:SetText(hex) end
    self.ui.personalColorPreview:SetColorTexture(d.values[1]/255,d.values[2]/255,d.values[3]/255,1)
    d.updating=nil
    return self:SetPersonalResponseColor(d.id,hex)
end
function A:SetPersonalPickerChannel(index,value)
    local d=self.personalColorDraft
    if not d or d.updating or not d.values or index<1 or index>3 then return false end
    local values={d.values[1],d.values[2],d.values[3]};values[index]=tonumber(value)
    return self:ApplyPersonalPickerRGB(values[1],values[2],values[3])
end
function A:ApplyPersonalPickerHex(value)
    if type(value)~="string" then return false end
    local hex=value:gsub("^#","")
    if not hex:match("^%x%x%x%x%x%x$") then return false end
    return self:ApplyPersonalPickerRGB(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))
end
function A:FinishPersonalColor(accept)
    local d=self.personalColorDraft
    self.personalColorDraft=nil
    if self.ui and self.ui.personalColor then self.ui.personalColor:Hide() end
    if d and not accept then self:SetPersonalResponseColor(d.id,d.previous) end
    return d~=nil
end
function A:ResponseConfigEditable()
    return self:CanConfigureRaid() and (not self.state or not self:VotingLocked())
end
function A:EditResponse(index,field,value)
    if not self:ResponseConfigEditable() then self:Print("The raid leader edits responses before opening rounds. Finish or reset active rounds first.");return false end
    local options=self.Copy(self:ResponseOptions())
    local selected=options[index]
    if field=="add" then
        if #options>=9 then self:Print("Up to eight choices plus Pass are supported.");return false end
        local highest=math.max(6,self.state and self.state.responseNextID or 6)
        for _,v in ipairs(options) do highest=math.max(highest,v.id) end
        local label="New response";local suffix=1
        local used={};for _,v in ipairs(options) do used[v.label:lower()]=true end
        while used[label:lower()] do suffix=suffix+1;label="New response "..suffix end
        table.insert(options,#options,{id=highest+1,label=label,color="c58aee",enabled=true,iconOnly=false})
    elseif field=="reset" then options=self:DefaultResponses()
    elseif not selected or selected.id==6 then return false
    elseif field=="delete" then table.remove(options,index)
    elseif field=="move" then local dest=index+value;if dest<1 or dest>=#options then return false end;options[index],options[dest]=options[dest],options[index]
    elseif field=="update" and type(value)=="table" then selected.label=value.label;selected.color=value.color
    elseif field=="label" or field=="color" or field=="enabled" or field=="iconOnly" then selected[field]=value
    else return false end
    if not self:CleanResponses(options) then self:Print("Use unique labels of 1–18 bytes and six-digit hex colors. Keep at least one enabled choice and Pass.");return false end
    self:Act("responseOptions",{options=options,expectedRevision=self.state and self.state.responseConfigRevision or 0})
    return true
end
