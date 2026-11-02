local _,A=...
-- Bounded LZ references reuse repeated schemas, settings and roster data.
-- Tokens contain printable characters; no third-party compression dependency.
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-"
local digits={};for i=1,#alphabet do digits[alphabet:sub(i,i)]=i-1 end
local function pair(n) return alphabet:sub(math.floor(n/64)+1,math.floor(n/64)+1)..alphabet:sub(n%64+1,n%64+1) end
function A:CompressWire(source)
    local parts,positions={},{};local at,size=1,#source
    while at<=size do
        local key=source:sub(at,at+2);local candidates=positions[key]
        local length,distance=0,0
        if candidates then
            for i=#candidates,1,-1 do
                local before=candidates[i];local offset=at-before
                if offset>4095 then break end
                local n,maximum=0,math.min(4095,size-at+1)
                while n<maximum and source:byte(before+n)==source:byte(at+n) do n=n+1 end
                if n>=8 and n>length then length,distance=n,offset end
                if length==maximum then break end
            end
        end
        local count=length>=8 and length or 1
        if length>=8 then parts[#parts+1]="~"..pair(distance)..pair(length)
        else local ch=source:sub(at,at);parts[#parts+1]=ch=="~" and "~~" or ch end
        for position=at,at+count-1 do
            local hash=source:sub(position,position+2)
            local list=positions[hash] or {};positions[hash]=list
            list[#list+1]=position;if #list>16 then table.remove(list,1) end
        end
        at=at+count
    end
    return table.concat(parts)
end
function A:ExpandWire(source,limit)
    limit=limit or 524288
    assert(#source<=524288,"Compressed wire limit exceeded")
    local parts,window,total,at={},"",0,1
    local function append(value)
        total=total+#value;assert(total<=limit,"Expanded wire limit exceeded")
        parts[#parts+1]=value;window=(window..value):sub(-4095)
    end
    local function number(position)
        local a,b=digits[source:sub(position,position)],digits[source:sub(position+1,position+1)]
        assert(a and b,"Invalid compressed reference");return a*64+b
    end
    while at<=#source do
        local token=source:find("~",at,true)
        if not token then append(source:sub(at));break end
        if token>at then append(source:sub(at,token-1)) end
        if source:sub(token+1,token+1)=="~" then append("~");at=token+2
        else
            local distance,length=number(token+1),number(token+3)
            assert(distance>0 and distance<=#window and length>=8,"Invalid compressed distance/length")
            local seed=window:sub(-distance)
            append(seed:rep(math.ceil(length/#seed)):sub(1,length));at=token+5
        end
    end
    return table.concat(parts)
end
