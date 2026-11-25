local H=dofile('tests/helper.lua')
md5=md5 or select(2,pcall(require,'md5'))
lfs=lfs or select(2,pcall(require,'lfs'))
-- LuaTeX bundles both; the standalone Lua 5.4 target has neither.
if type(md5)~='table' or type(lfs)~='table' then
  print('cache_key: skipped, needs LuaTeX md5 and lfs')
  return
end
local Cache=assert(loadfile('lua/flora/cache.lua'))('flora.cache','./lua/flora/cache.lua')
local Tune=require('flora.tune')
local spec={width=400,height=300,seed=7,text={x0=40,y0=30,x1=360,y1=270}}
local key=Cache.key(spec,{})
H.check(type(key)=='string' and #key==32,'cache cannot hash tuning with private helpers')
H.check(Cache.key(spec,{})==key,'cache key is unstable')
local other=Tune._with({compose={leaves=Tune.compose.leaves+1}},function() return Cache.key(spec,{}) end)
H.check(other~=key and Cache.key(spec,{})==key,'cache ignored or retained temporary tuning')
-- Flora in a perimeter band: its width, form, density and edge each change
-- the key, so a page cached under one is not used for another.
local band={width=400,height=300,seed=7,text={x0=60,y0=50,x1=340,y1=250},layout='perimeter'}
local function with(k,v) local s={} for a,b in pairs(band) do s[a]=b end s[k]=v return Cache.key(s,{}) end
local plain=Cache.key(band,{})
H.check(with('perimeter_width',8)~=plain and with('perimeter_width',8)~=with('perimeter_width',18),'perimeterwidth does not change the key')
H.check(with('perimeter_flora','vine')~=plain and with('perimeter_flora','vine')~=with('perimeter_flora','pinwheel'),'perimeterflora does not change the key')
H.check(with('perimeter_density','sparse')~=plain and with('perimeter_density','sparse')~=with('perimeter_density','open'),'perimeterdensity does not change the key')
H.check(with('pattern_edge','border')~=plain and with('pattern_edge','border')~=with('pattern_edge','cell'),'edge does not change the key')
H.done('cache_key')
