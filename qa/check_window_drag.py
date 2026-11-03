from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parent.parent
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
A={}; mouseX,mouseY=500,600; mouseDown=true
function GetCursorPosition() return mouseX,mouseY end
function IsMouseButtonDown() return mouseDown end
UIParent={width=1920,height=1080,scale=1}
function UIParent:GetWidth() return self.width end
function UIParent:GetHeight() return self.height end
function UIParent:GetEffectiveScale() return self.scale end
''')
lua.execute((root/'SanguineLootTools/WindowLayouts.lua').read_text(encoding='utf-8'), 'SanguineLootTools', lua.globals().A)
lua.execute('''
local store={}
function A:WindowLayoutStore() return store end
function A:WindowLocked(f) return f.locked==true end
function A:FocusWindow() end
function A:IsReadableWindow() return false end
local function near(a,b) assert(math.abs(a-b)<.00001,tostring(a)..' ~= '..tostring(b)) end
function frame()
    local f={x=300,y=200,width=400,height=300,scripts={},sltWindowName='test'}
    function f:GetPoint() return 'TOPLEFT',UIParent,'TOPLEFT',self.x,-self.y end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:GetScale() return 1 end
    function f:ClearAllPoints() end
    function f:SetPoint(p,parent,r,x,y)
        assert(p=='TOPLEFT' and parent==UIParent and r=='TOPLEFT')
        self.x,self.y=x,-y
    end
    function f:HookScript(event,fn)
        local before=self.scripts[event]
        self.scripts[event]=function(...) if before then before(...) end;fn(...) end
    end
    -- The fix must not invoke native dragging or depend on its changing bounds.
    function f:StartMoving() error('native StartMoving switches coordinate space') end
    function f:GetLeft() error('native bounds must not drive mouse deltas') end
    function f:GetTop() error('native bounds must not drive mouse deltas') end
    return f
end
for _,scale in ipairs({.64,.8,1,1.25}) do
    UIParent.scale=scale
    local f=frame();local previousUpdates=0
    f:HookScript('OnUpdate',function() previousUpdates=previousUpdates+1 end)
    mouseX,mouseY=500,600;mouseDown=true
    assert(A:BeginWindowMove(f))
    assert(not A:BeginWindowMove(f),'duplicate drag replaced origin')
    f.scripts.OnUpdate(f);near(f.x,300);near(f.y,200)
    mouseX,mouseY=500+150*scale,600-75*scale
    f.scripts.OnUpdate(f);near(f.x,450);near(f.y,275)
    -- A normal render/save request must not rewrite anchors or saved geometry.
    store.test=nil;A:ClampWindowPosition(f);A:SaveWindowLayout(f,'test')
    assert(store.test==nil);near(f.x,450);near(f.y,275)
    -- Include final mouse travel between the last frame and button release.
    mouseX=500+170*scale;mouseDown=false;f.scripts.OnUpdate(f)
    near(f.x,470);near(f.y,275);assert(not f.sltMoving)
    near(store.test.x,470);near(store.test.y,-275)
    local saved=store.test;A:FinishWindowMove(f);assert(store.test==saved)
    assert(previousUpdates==3,'existing OnUpdate handler lost')
    -- Repeated movement starts from the most recently saved location.
    for i=1,20 do
        mouseDown=true;assert(A:BeginWindowMove(f));mouseX=mouseX+scale
        A:FinishWindowMove(f)
    end
    near(f.x,490);near(f.y,275)
    -- Each edge, reverse direction while still holding, and all corners.
    for _,target in ipairs({{-100,-100},{2500,-100},{-100,1500},{2500,1500}}) do
        mouseDown=true;local startX,startY=mouseX,mouseY
        local left,top=f.x,f.y;A:BeginWindowMove(f)
        mouseX=startX+(target[1]-left)*scale
        mouseY=startY-(target[2]-top)*scale
        f.scripts.OnUpdate(f)
        near(f.x,math.max(0,math.min(1520,target[1])))
        near(f.y,math.max(0,math.min(780,target[2])))
        mouseX,mouseY=startX,startY;f.scripts.OnUpdate(f)
        near(f.x,left);near(f.y,top);A:FinishWindowMove(f)
    end
    -- Hiding and locking terminate a drag and prevent later pointer travel.
    mouseDown=true;A:BeginWindowMove(f);f.scripts.OnHide(f)
    local left,top=f.x,f.y;mouseX=mouseX+100;f.scripts.OnUpdate(f)
    near(f.x,left);near(f.y,top)
    A:BeginWindowMove(f);f.locked=true;f.scripts.OnUpdate(f)
    assert(not f.sltMoving);assert(not A:BeginWindowMove(f));f.locked=false
    -- Scale changes finish without applying deltas from the old coordinate space.
    A:BeginWindowMove(f);left,top=f.x,f.y
    UIParent.scale=scale+.1;mouseX,mouseY=9000,9000;A:FinishWindowMove(f)
    near(f.x,left);near(f.y,top)
    UIParent.scale=scale;f.sltResizing=true;assert(not A:BeginWindowMove(f));f.sltResizing=false
    mouseX=0/0;assert(not A:BeginWindowMove(f))
end
''')
print('Cursor tracking, four UI scales, final release, repeated drags, edges, render guards, hide/lock, scale changes and existing update hooks passed.')
