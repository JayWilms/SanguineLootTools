from pathlib import Path

from lupa.lua51 import LuaRuntime

source = Path(__file__).resolve().parent.parent / 'SanguineLootTools'
lua = LuaRuntime()
lua.execute("""
A={}; SlashCmdList={}
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
""")
for line in (source / 'SanguineLootTools.toc').read_text().splitlines():
    if line.endswith('.lua'):
        lua.execute((source / line).read_text(encoding='utf-8'), 'SanguineLootTools', lua.globals().A)

lua.execute("""
local player='Leader-Forever'
local grouped=false
function A.Client:ClockReady() return true end
function A.Client:Combat() return false end
function A.Client:InGroup() return grouped end
function A.Client:InRaid() return false end
function A.Client:ServerTime() return 100 end
function A:Name(unit) if unit=='player' then return player end end
function UnitIsGroupLeader(unit) return grouped and unit=='player' end
function A:Print() end
function A:Publish() end
function A:Changed() self:Render() end
function A:RequestSync() end

local launcher={sltManagedWindow=true,Show=function(self) self.shown=true end, IsShown=function(self) return self.shown end}
local other={sltManagedWindow=true, IsShown=function() return true end}
local text={SetText=function(self,value) self.value=value end}
A.ui={launcher=launcher,masterStatus=text,masterCouncil={SetText=function() end}}
function A:BuildUI() end
function A:Render() self:RenderMasterSettings() end
function A:RefreshWindowLayers() end

local slash=SlashCmdList.SANGUINELOOTTOOLS
A:RefreshRoster()
assert(A.gameLeader==false)
for attempt=1,2 do
    slash('test')
    assert(A:IsSoloTest() and A.state.master==player)
    assert(A.state.responseDuration==60 and #A.state.trackedLoot>0)
end
slash('leave-test')
assert(not A.demo and not A.state)

grouped=true
for attempt=1,2 do
    slash('test')
    assert(A.groupTest and A.state.groupTest and A.state.master==player)
    assert(A.state.responseDuration==60 and #A.state.trackedLoot>0)
end
slash('leave-test')
assert(not A.demo and not A.state)

slash('')
assert(launcher.shown and A.windowStack[#A.windowStack]==launcher)
A:FocusWindow(other)
assert(A.windowStack[#A.windowStack]==other)
slash('')
assert(A.windowStack[#A.windowStack]==launcher)
""")
