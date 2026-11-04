from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parent.parent
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('A={}')
for module in ('LootConfiguration','NativeLoot'):
    lua.execute((root/'SanguineLootTools'/f'{module}.lua').read_text(),'SanguineLootTools',lua.globals().A)
lua.execute('''
local defaults=A:DefaultLootConfiguration()
assert(defaults.minimum==nil)
for q=0,5 do
 assert(defaults.rules[q+1].action==(q>=4 and 'council' or 'ignore'),'new defaults changed effective epic-only council collection')
end
local saved=A:DefaultLootConfiguration()
saved.minimum=5
saved.rules[3]={action='council',target='',reason='',note='Prepared green rule'}
saved.rules[4]={action='assign',target='Bank-Realm',reason='Guild Bank',note='Prepared bank rule'}
saved.automatic=true
local migrated=A:CleanLootConfiguration(saved)
assert(migrated and migrated.minimum==nil)
assert(migrated.rules[3].action=='council' and migrated.rules[3].note=='Prepared green rule')
assert(migrated.rules[4].action=='assign' and migrated.rules[4].target=='Bank-Realm' and migrated.rules[4].reason=='Guild Bank')
-- The obsolete field is ignored even in malformed older saves; the rules are validated.
saved.minimum='obsolete';assert(A:CleanLootConfiguration(saved))
saved.rules[3].action='invalid';assert(not A:CleanLootConfiguration(saved))

A.state={autoCollect=true}
function A:LootConfiguration() return self.config end
for quality=0,5 do
 for _,action in ipairs({'ignore','council','assign'}) do
  for _,collection in ipairs({false,true}) do
   for _,automatic in ipairs({false,true}) do
    local c=A:DefaultLootConfiguration()
    c.collection=collection;c.automatic=automatic;c.minimum=5
    c.rules[quality+1]={action=action,target='Bank-Realm',reason='Guild Bank',note=''}
    A.config=A:CleanLootConfiguration(c);A.state.autoCollect=collection
    local expected=(action=='council' and collection) or (action=='assign' and automatic)
    assert(A:ShouldCollectLoot(quality)==expected,'bag collection did not follow the enabled rule')
    local native=A:NativeLootPolicy(quality)
    assert((native~=nil)==expected,'native routing disagrees with collection rules')
    if native then
     assert(native.target==(action=='council' and '@master' or 'Bank-Realm'))
    end
   end
  end
 end
end
A.config=A:DefaultLootConfiguration()
A.config.rules[3]={action='council',target='',reason='',note=''}
A.state.autoCollect=false
assert(not A:ShouldCollectLoot(2),'explicit collection-off session flag was bypassed')
assert(not A:ShouldCollectLoot(-1) and not A:ShouldCollectLoot(6))
A.state=nil;assert(not A:ShouldCollectLoot(2))
''')
print('Legacy saves retain rules; fresh defaults preserve epic-only collection; every quality/action/switch combination routes consistently.')
