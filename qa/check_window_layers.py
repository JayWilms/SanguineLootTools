from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
A={confirmationDialogs={},allWindowFrames={}};SlashCmdList={}
local methods={}
local mt={__index=function(_,key)
    if methods[key] then return methods[key] end
    if key:match('^Set') or key:match('^Enable') or key:match('^Register') or key:match('^Clear') then return function() end end
end}
function CreateFrame(kind,name,parent)
    local f=setmetatable({parent=parent,children={},scripts={},shown=parent~=nil,width=400,height=300,
        level=parent and parent.level+1 or 0,strata=parent and parent.strata or 'MEDIUM'},mt)
    if parent then parent.children[#parent.children+1]=f end
    return f
end
function methods:GetParent() return self.parent end
function methods:GetChildren() return unpack(self.children) end
function methods:GetRegions() end
function methods:GetFrameLevel() return self.level end
function methods:GetFrameStrata() return self.strata end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetFrameLevel(level)
    local delta=level-self.level;self.level=level
    for _,child in ipairs(self.children) do child:SetFrameLevel(child.level+delta) end
end
function methods:SetFrameStrata(strata) self.strata=strata end
function methods:SetParent(parent)
    if self.parent then for i,c in ipairs(self.parent.children) do if c==self then table.remove(self.parent.children,i);break end end end
    self.parent=parent;parent.children[#parent.children+1]=self
end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:HookScript(event,fn)
    local before=self.scripts[event]
    self.scripts[event]=function(...) if before then before(...) end;fn(...) end
end
function methods:Show() local before=self.shown;self.shown=true;if not before and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() local before=self.shown;self.shown=false;if before and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:CreateTexture() return CreateFrame('Texture',nil,self) end
function methods:SetColorTexture(r,g,b,a) self.colour={r,g,b,a} end
function methods:SetBackdropColor(r,g,b,a) self.backdrop={r,g,b,a} end
UIParent=CreateFrame('Frame');UIParent.shown=true
function root()
    local f=CreateFrame('Frame',nil,UIParent);f.shown=false
    A.allWindowFrames[#A.allWindowFrames+1]=f;A:RegisterWindowLayers(f)
    return f
end
function highest(frame)
    local level=frame.level
    for _,child in ipairs(frame.children) do level=math.max(level,highest(child)) end
    return level
end
''')
for name in ['WindowLayouts','UI']:
    lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
lua.execute('''
settings=root();response=root();voting=root();timer=root();correction=root();confirmation=root()
A.ui={settingsHub=settings,popup=response,main=voting,lootTimers=timer,correction=correction,confirmation=confirmation}
local scroll=CreateFrame('ScrollFrame',nil,settings)
underlyingButton=CreateFrame('Button',nil,scroll);underlyingButton:SetFrameLevel(45)
responseButton=CreateFrame('Button',nil,response)
A:StylePanel(settings);A:StylePanel(response)
assert(settings.backdrop[4]==1 and response.backdrop[4]==1)
settings:Show();response:Show()
assert(highest(settings)<response.level)
assert(responseButton.level>response.level and responseButton.strata==response.strata)
-- Clicking an exposed control raises its entire window, not just that control.
underlyingButton.scripts.OnMouseDown(underlyingButton)
assert(highest(response)<settings.level)
-- New or reparented descendants are assigned to their current owner's band.
late=CreateFrame('Button',nil,response)
A:RefreshWindowLayers();assert(highest(response)<settings.level)
late:SetParent(settings);A:RefreshWindowLayers();assert(late.sltFocusRoot==settings)
-- Collapsing/reparenting the body must not break the layer grouping.
settings.sltHeader=CreateFrame('Frame',nil,settings)
A:CaptureWindowBody(settings);settings.sltBody:Hide()
A:RefreshWindowLayers();assert(highest(response)<settings.level)
settings.sltBody:Show()
-- Independent windows such as Timer are never hidden to solve overlap.
timer:Show();assert(timer:IsShown() and settings:IsShown() and response:IsShown())
assert(highest(settings)<timer.level)
''')
print('Opaque backgrounds, complete window focus, late controls, reparenting, collapse and independent Timer passed.')

lua.execute('''
voting:Show();correction:Show()
assert(correction.strata=='FULLSCREEN_DIALOG' and voting.strata=='DIALOG')
assert(voting.sltDialogBlocker:IsShown())
assert(voting.sltDialogBlocker.level>voting.level+200)
confirmation.sltDialogOwner=correction;confirmation:Show()
assert(correction.sltDialogBlocker:IsShown())
assert(highest(correction)<confirmation.level)
A:FocusWindow(voting)
assert(highest(correction)<confirmation.level,'parent click raised a window through its active confirmation')
confirmation:Hide()
assert(not correction.sltDialogBlocker:IsShown())
assert(voting.sltDialogBlocker:IsShown())
correction:Hide()
assert(not voting.sltDialogBlocker:IsShown())
assert(timer:IsShown() and response:IsShown())
-- Repeated focus must use bounded bands instead of accumulating frame levels.
for i=1,300 do A:FocusWindow(i%2==0 and settings or response) end
for _,frame in ipairs(A.allWindowFrames) do assert(highest(frame)<10000) end
''')
print('Parent input blockers, nested confirmations, dismissal, restored input and bounded layer levels passed.')
lua.execute('''
UIParent.width,UIParent.height=1920,1080
function A:WindowTopLeft(frame) return frame.x,frame.y end
local f={x=1520,y=780,GetWidth=function() return 400 end,GetHeight=function() return 300 end,ClearAllPoints=function() end}
function f:SetPoint(_,_,_,x,y) self.x,self.y=x,-y end
A:ClampWindowPosition(f);assert(f.x==1520 and f.y==780)
f.x=-20;f.y=-10;A:ClampWindowPosition(f);assert(f.x==0 and f.y==0)
''')
print('Flush screen-edge positioning and off-screen limits passed.')
for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Window layering and Lua 5.1 checks passed.')
