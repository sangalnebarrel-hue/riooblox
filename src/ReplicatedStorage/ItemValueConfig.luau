-- Versioned, shared coefficients. Only the server can grant sale proceeds.
local C={
 Version=7,SecretMultiplier=3.6,
 Rarity={{MaxChance=.000001,Name='Secret',Multiplier=3.6},{MaxChance=.0001,Name='Legendary',Multiplier=2.7},{MaxChance=.001,Name='Epic',Multiplier=2},{MaxChance=.01,Name='Rare',Multiplier=1.5},{MaxChance=.05,Name='Uncommon',Multiplier=1.2},{MaxChance=1,Name='Common',Multiplier=1}},
 Depth={1,1.12,1.26,1.42,1.6},
 BaseScale={16,13.33,12,10.67,9.33},
 WeightTier={.62,.83,1,1.55,2.8,5,9,16,28,45},
 WeightExponent=.18,WeightMin=.65,WeightMax=4,
 Mutation={NORMAL=1,SHINY=1.5,GOLDEN=2.5,RAINBOW=8,CURSED=5,CORRUPTED=5,GLITCHED=15,VOID=18,TOASTED=1.35,BURNED=1.45,SPORE=1.4,FROZEN=1.5,INFERNAL=1.7,SOLAR=1.7,RADIOACTIVE=2,SPOILED=.2,HAUNTED=2.5,PUMPKINIZED=4,['BLOOD MOON']=8,ECLIPSED=20},
 EventDefault=1.05,Events={NULL_HOUR=1.15,TREASURE_FEVER=1.1},
 FirstFind=1.08,MaxEarnedBonus=.5,Seasonal=1,
 SoftCapIncomeHours=60,SoftCapStart=.8,
 -- NIGHT OF THE BURIED MOON item mutations: their multiplier applies AFTER the depth soft cap (so x20 stays x20 on
 -- valuable finds too), bounded by PostCapLimit. Permanent: mutated finds keep their value after the event.
 PostCapMutation={HAUNTED=true,PUMPKINIZED=true,['BLOOD MOON']=true,ECLIPSED=true},PostCapLimit=60e6,
}
-- The event config (ReplicatedStorage.Halloween.Config.Mutations) is the source of the event multipliers when present;
-- the literals above are the fallback (the folder may be missing in other places / tests).
do
 local folder=game:GetService('ReplicatedStorage'):FindFirstChild('Halloween')
 local module=folder and folder:FindFirstChild('Config')
 local ok,hw=pcall(function()return module and require(module)end)
 local m=ok and type(hw)=='table'and hw.Mutations
 if type(m)=='table'and type(m.Defs)=='table'then
  for name,def in pairs(m.Defs)do
   if type(name)=='string'and type(def)=='table'and type(def.Mult)=='number'and def.Mult>0 then
    local key=string.upper(name);C.Mutation[key]=def.Mult;C.PostCapMutation[key]=true
   end
  end
  if type(m.PostCapLimit)=='number'and m.PostCapLimit>0 then C.PostCapLimit=m.PostCapLimit end
 end
end
return C
