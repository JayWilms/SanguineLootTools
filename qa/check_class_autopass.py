from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'SanguineLootTools'

def setup(ready=True):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('A={};SlashCmdList={};function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end')
    for name in ['Core','Client','Features','Archive','Awards','Voting','ResponseConfig','Responses','Items','Equipment','StateDelta','WireCodec','Network','CouncilUI']:
        lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
    lua.globals().ready=ready
    lua.execute('''
now=100000
classes={player=1,raid2=8,raid4=3}
local tokens={[1]='WARRIOR',[3]='HUNTER',[4]='ROGUE',[8]='MAGE'}
function UnitClass(unit) return 'Class',tokens[classes[unit]],classes[unit] end
function UnitLevel(unit) return unit=='raid4' and 20 or 60 end
ITEM_CLASSES_ALLOWED='Classes: %s'
LOCALIZED_CLASS_NAMES_MALE={WARRIOR='Warrior',HUNTER='Hunter',ROGUE='Rogue',MAGE='Mage'}
Enum={TooltipDataLineType={UsageRequirement=99},TooltipDataUsageRequirementType={RaceClass=7}}
local armor, weapon, misc = 4, 2, 15
itemFacts={
 [12345]={armor,4,'INVTYPE_HEAD'},
 [12346]={armor,2,'INVTYPE_HEAD'},
 [12347]={weapon,0,'INVTYPE_WEAPON'},
 [12348]={armor,1,'INVTYPE_CLOAK'},
 [12349]={misc,0,'','Classes: Warrior, Hunter'},
 [12350]={misc,0,'','Classes: Warrior, Unrecognised'},
 [12351]={misc,0,'','Races: Other',false},
 [12352]={misc,0,''},
}
local function itemID(link) return tonumber(link:match('item:(%d+)')) end
C_Item={GetItemInfo=function(link)
 if not ready or type(link)~='string' then return end
 local facts=itemFacts[itemID(link)]
 if not facts then return end
 return 'Item',link,4,60,60,'Gear','Type',1,facts[3],1,0,facts[1],facts[2]
end}
C_TooltipInfo={GetHyperlink=function(link)
 if not ready or tooltipPending then return end
 local facts=itemFacts[itemID(link)]
 if not facts then return end
 return {lines={{leftText='Item'},facts[4] and {leftText=facts[4],type=99,requirementType=7,usable=facts[5]} or nil}}
end}
function A.Client:ServerTime() return now end
function A.Client:ClockReady() return true end
function A.Client:Combat() return false end
function A:SyncGameMaster() end
function A:Record() end
function A:Changed() changed=(changed or 0)+1 end
function A:Publish(p) published=p.op;publishes=(publishes or 0)+1 end
function A:Print(message) lastMessage=message end
A.me='Leader-Realm';A.leader=A.me;A.rev=0
A.roster={[A.me]='player',['Mage-Realm']='raid2',['Unknown-Realm']='raid3'}
A.state={id='session',leader=A.me,master=A.me,responseDuration=120,rules=A:DefaultVoting(),
 responseOptions=A:DefaultResponses(),council={[A.me]=true},items={}}
item={id=1,link='|cffa335ee|Hitem:12345::::|h[Restricted helm]|h|r',status='queued',responses={},ballots={},round=1,ballotVersion=0}
A.state.items={item}
A:StartResponses(item)
''')
    return lua

lua=setup()
lua.execute('''
local response=item.responses['Mage-Realm']
assert(response and response.choice==6 and response.autoPass and response.revision==1)
assert(A:VotingResponseLabel(item,response)=='Auto Pass')
assert(A:VotingResponseLabel(item,{choice=6})=='Pass')
assert(not item.responses[A.me] and not item.responses['Unknown-Realm'])
assert(A:ClassEligibility(item,'Unknown-Realm')=='Unknown')
assert(A:RefreshClassAutoPasses(item,false)==0)
A:FinishResponses(item,'timer')
assert(not item.noResponse['Mage-Realm'])
assert(item.noResponse[A.me] and item.noResponse['Unknown-Realm'])
assert(not A:CanAwardCandidate(item,'Mage-Realm'))
assert(not A:ReduceVoting(A.me,{op='vote',choices={['Mage-Realm']=true}},item))
local decoded=A.Decode(A:WireEncode({responses=item.responses,noResponse=item.noResponse,protocol=A.protocol}))
assert(decoded.responses['Mage-Realm'].autoPass and decoded.responses['Mage-Realm'].choice==6)
assert(not decoded.noResponse['Mage-Realm'])
''')
print('Confirmed class restriction becomes Auto Pass; unknown players still wait; voting/awarding blocked; marker replicates.')

lua=setup(False)
lua.execute('''
assert(not next(item.responses))
ready=true
assert(not A:Reduce('Mage-Realm',{op='classAutoPass',sid=A.state.id}))
assert(not item.responses['Mage-Realm'])
A:TickResponses()
assert(item.responses['Mage-Realm'].autoPass and published=='classAutoPass' and A.rev==1)
local oldPublishes=publishes
A:TickResponses();assert(publishes==oldPublishes)
''')
print('Late client item data adds one leader-authorized update without repeat traffic.')

lua=setup(False)
lua.execute('''
item.responses['Mage-Realm']={choice=6,note='Manual pass',revision=1}
ready=true
A:RefreshClassAutoPasses(item,true)
assert(item.responses['Mage-Realm'].note=='Manual pass' and not item.responses['Mage-Realm'].autoPass)
assert(A:VotingResponseLabel(item,item.responses['Mage-Realm'])=='Pass')
''')
print('Explicit player responses are preserved and remain distinguishable from Auto Pass.')

lua=setup(False)
lua.execute('''
A:FinishResponses(item,'timer');assert(item.noResponse['Mage-Realm'])
ready=true;A:TickResponses()
assert(item.responses['Mage-Realm'].autoPass and not item.noResponse['Mage-Realm'])
classes.raid2=1
A:TickResponses()
assert(not item.responses['Mage-Realm'] and item.noResponse['Mage-Realm'])
''')
print('Closed unawarded rounds resolve late restriction data without reopening the response timer.')

lua=setup()
lua.execute('''
classes.raid2=1
A:TickResponses();assert(not item.responses['Mage-Realm'])
classes.raid2=8;A:TickResponses();assert(item.responses['Mage-Realm'].autoPass)
ready=false;item.link=item.link:gsub('::::',':::::');A:TickResponses();assert(item.responses['Mage-Realm'].autoPass)
ready=true;classes.raid2=1;A:TickResponses();assert(not item.responses['Mage-Realm'])
classes.raid4=8;A.roster['NewMage-Realm']='raid4'
A:TrackResponseMembers();assert(item.responses['NewMage-Realm'].autoPass)
A:StartResponses(item);assert(item.responses['NewMage-Realm'].autoPass and item.responses['NewMage-Realm'].revision==1)
item.status='awarded';item.winner=A.me
local version=item.ballotVersion
classes.raid4=1
assert(A:RefreshClassAutoPasses(item,true)==0 and item.ballotVersion==version)
''')
print('Eligibility changes, transient unknown data, new members, rerolls and immutable awarded rounds passed.')

lua=setup()
lua.execute('''
local function sample(id)
 return {link='|cffa335ee|Hitem:'..id..'::::|h[Sample]|h|r'}
end
local warrior, mage = A.me, 'Mage-Realm'
A.roster['Other-Realm']='raid4'
assert(A:ClassEligibility(sample(12346),warrior)=='Eligible') -- lighter armour
assert(A:ClassEligibility(sample(12348),mage)=='Eligible') -- cloak
assert(A:ClassEligibility(sample(12349),mage)=='Restricted') -- token class list
assert(A:ClassEligibility(sample(12349),warrior)=='Eligible')
assert(A:ClassEligibility(sample(12350),mage)=='Unknown') -- unrecognised localized class
assert(A:ClassEligibility(sample(12351),warrior)=='Unknown') -- local-only flag
assert(A:ItemEligibility(sample(12351),warrior)=='Restricted')
assert(A:ItemEligibility(sample(12351),mage)=='Unknown')
assert(A:ClassEligibility(sample(12346),'Other-Realm')=='Eligible')
assert(A:ItemEligibility(sample(12346),'Other-Realm')=='Restricted') -- level is advisory
classes.raid4=4
assert(A:ClassEligibility(sample(12347),'Other-Realm')=='Eligible') -- Forever rogue axes
assert(A:ClassEligibility(sample(12347),mage)=='Restricted')
assert(A:ClassEligibility(sample(12349),'NotInRoster-Realm')=='Unknown')
local uncached=sample(12346)
tooltipPending=true
assert(A:ClassEligibility(uncached,mage)=='Unknown')
tooltipPending=false
assert(A:ClassEligibility(uncached,mage)=='Restricted')
''')
print('Native item data, localized class lists, Forever proficiencies and safe missing-data behavior passed.')

lua=setup()
lua.execute((SRC/'RaiderUI.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
lua.execute('''
local function recipe(id, subclass)
    itemFacts[id]={9,subclass,''}
    return {id=id,status='open',link='|cffa335ee|Hitem:'..id..'::::|h[Recipe]|h|r'}
end
local leatherworking = recipe(279301,1)
local tailoring = recipe(279315,2)
local enchanting = recipe(279295,8)
local book = recipe(12355,0)
A.state.items={leatherworking,tailoring,enchanting,book}
local first, second = 10, 12
function GetProfessions() return first, second, nil, nil, nil end
function GetProfessionInfo(index)
    if index==10 then return 'Tailoring',1,1,75,1,0,197 end
    if index==12 then return 'Enchanting',1,1,75,1,0,333 end
end
local rows, hidden = A:ResponseItems()
assert(#rows==3 and hidden==1 and rows[1].item==tailoring and rows[2].item==enchanting and rows[3].item==book)
assert(#A.state.items==4) -- presentation only
function GetProfessions() return second end -- trailing empty slots omitted
rows, hidden = A:ResponseItems()
assert(#rows==2 and hidden==2 and rows[1].item==enchanting and rows[2].item==book)
function GetProfessions() end -- no usable data, so keep recipes visible
rows, hidden = A:ResponseItems()
assert(#rows==4 and hidden==0)
function GetProfessions() return first, second, nil, nil, nil end
first, second = nil, nil
rows, hidden = A:ResponseItems()
assert(#rows==1 and hidden==3 and rows[1].item==book)
first = 99 -- profession list returned an index whose info isn't ready
rows, hidden = A:ResponseItems()
assert(#rows==4 and hidden==0)
GetProfessions = nil
rows, hidden = A:ResponseItems()
assert(#rows==4 and hidden==0)
itemFacts[279247]={4,7,'INVTYPE_RELIC'}
local libram = {id=279247,status='open',link='|cffa335ee|Hitem:279247::::|h[Steadfast Libram]|h|r'}
assert(A:ClassEligibility(libram)=='Restricted')
classes.player=2
local originalUnitClass = UnitClass
function UnitClass(unit)
    if unit=='player' then return 'Paladin','PALADIN',2 end
    return originalUnitClass(unit)
end
assert(A:ClassEligibility(libram)=='Eligible')
''')
print('Recipe visibility uses learned professions at skill 1 and keeps unknown recipes visible.')


lua=setup()
for name in ('LootConfiguration','Warnings'):
    lua.execute((SRC/f'{name}.lua').read_text(encoding='utf-8'),'SanguineLootTools',lua.globals().A)
lua.execute('''
SanguineLootCouncilDB={}
item.status,item.voting='queued','idle'
assert(A:EditResponse(0,'addTransmog'))
local choices=A:ResponseOptions()
local transmog=choices[#choices-1]
assert(transmog.label=='Transmog' and transmog.transmog and transmog.enabled and choices[#choices].id==6)
assert(A:EditResponse(0,'addTransmog') and #A:ResponseOptions()==#choices)
assert(SanguineLootCouncilDB.responseOptions[#choices-1].transmog)
assert(A:CleanResponses(A.Decode(A:WireEncode({choices=choices})).choices)[#choices-1].transmog)
item.responseOptions=nil
A:StartResponses(item)
assert(A:ResponseOption(transmog.id,item).transmog)

local collected,ready,learnable=true,true,true
C_TransmogCollection={
    GetItemInfo=function(link) assert(link==item.link);return 50,60 end,
    GetAppearanceInfoBySource=function(source)
        assert(source==60);return {appearanceIsCollected=collected,sourceIsCollected=false}
    end,
    PlayerCanCollectSource=function() return ready,learnable end
}
function A:Render() end
local function widget()
    return setmetatable({},{__index=function() return function() end end})
end
local function responseButton(choice)
    return {choice=choice,SetEnabled=function(self,v) self.enabled=v end,SetText=function(self,v) self.label=v end}
end
local transmogButton,gearButton=responseButton(transmog.id),responseButton(1)
A.ui={responseBar=widget(),responseCountdown=widget(),responseButtons={transmogButton,gearButton},transmogButton=transmogButton}
A.popupItem=item.id
local function refresh()
    A:RefreshTransmogResponse(item)
    A:RenderResponseTimer()
end
local function respond(choice)
    return A:Act('respond',{item=item.id,choice=choice,note=''})
end
refresh()
assert(not transmogButton.enabled and gearButton.enabled and transmogButton.label:find('Already collected'))
assert(not respond(transmog.id) and not item.responses[A.me])
assert(respond(1) and item.responses[A.me].choice==1)
collected=false
refresh()
assert(transmogButton.enabled and transmogButton.label=='Transmog')
assert(respond(transmog.id) and item.responses[A.me].choice==transmog.id)
learnable=false
refresh()
assert(not transmogButton.enabled and transmogButton.label:find('Cannot learn') and not respond(transmog.id))
ready=false
refresh()
assert(transmogButton.enabled and transmogButton.label:find('Unverified') and respond(transmog.id))
C_TransmogCollection=nil
refresh()
assert(transmogButton.enabled and transmogButton.label:find('Unverified'))
item.status='closed'
refresh()
assert(not transmogButton.enabled and not gearButton.enabled)
''')
print('Opt-in Transmog persists through settings and wire data. Local collection gating, alternate sources, unknown data and normal responses passed.')

for file in SRC.glob('*.lua'):
    lua.eval('function(s,n) assert(loadstring(s,n)) end')(file.read_text(encoding='utf-8'),file.name)
print('Class auto-pass and Lua 5.1 checks passed. No installer generated.')
