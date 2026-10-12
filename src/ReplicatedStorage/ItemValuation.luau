local RS=game:GetService('ReplicatedStorage')
local C=require(RS.ItemValueConfig);local D=require(RS.DogEconomy.ItemDefinitions);local Depth=require(RS.DogEconomy.DepthDefinitions)
local V={}
local function rarityOf(d)
 if d.Class=='Secret'then return 'Secret',C.SecretMultiplier end
 for _,row in ipairs(C.Rarity)do if d.BaseDropChance<=row.MaxChance then return row.Name,row.Multiplier end end
 return 'Common',1
end
-- Rarity of an item definition (ItemValueConfig.Rarity: Class 'Secret', then by BaseDropChance) and
-- its price multiplier. The one rule behind prices and ReplicatedStorage.ItemRarity.
V.Rarity=rarityOf
local function softCap(raw,d)
 local cap=Depth[tostring(d.Depth)].IncomeReference*3600*C.SoftCapIncomeHours
 local threshold=cap*C.SoftCapStart
 return raw<=threshold and raw or threshold+(cap-threshold)*(1-math.exp(-(raw-threshold)/(cap-threshold))),cap
end
-- Income multiplier fixed on the item when it was found (Bonuses pipeline; nil = 1). It applies
-- after the soft cap, like every new bonus, and is never read from live gear at sale time.
local function income(m)
 m=tonumber(m)
 if not m or m~=m then return 1 end
 return math.clamp(m,.1,100)
end
function V.Price(x)
 local d=D[x.ItemId];assert(d,'Unknown item')
 local rarity,rarityMultiplier=rarityOf(d)
 local ratio=math.max(.00001,(x.WeightKg or d.BaseWeightKg)/d.BaseWeightKg)
 local weight=(C.WeightTier[math.clamp(x.TierIndex or 3,1,10)]or 1)*math.clamp(ratio^C.WeightExponent,C.WeightMin,C.WeightMax)
 local event=x.EventTag or (type(x.Origin)=='string'and x.Origin:match('^WorldEvent:(.+)$'))
 local factors={Base=d.BaseValue*(C.BaseScale[d.Depth]or 1),Rarity=rarityMultiplier,Depth=C.Depth[d.Depth]or 1,Weight=weight,Mutation=C.Mutation[string.upper(x.Mutation or 'NORMAL')]or 1,Event=event and (C.Events[event]or C.EventDefault)or 1,Bonus=(x.FirstFind and C.FirstFind or 1)*(1+math.clamp(x.SellBonus or 0,0,C.MaxEarnedBonus))*C.Seasonal,Income=income(x.IncomeMult)}
 local raw=factors.Base*factors.Rarity*factors.Depth*factors.Weight*factors.Mutation*factors.Event*factors.Bonus
 local result,cap=softCap(raw,d)
 return math.max(1,math.floor(result*factors.Income)),{Version=C.Version,Rarity=rarity,Factors=factors,Raw=raw,Cap=cap}
end
-- Expected sale value of a find of `d` before it is rolled: the same formula as V.Price with the
-- mean weight and mutation factors (ItemRules.WeightFactor / MutationFactor). Used only for
-- income estimates (Economy.IncomeModel), never to pay.
function V.Expected(d,f)
 f=f or {}
 local _,rarityMultiplier=rarityOf(d)
 local event=f.EventTag and (C.Events[f.EventTag]or C.EventDefault)or 1
 local raw=d.BaseValue*(C.BaseScale[d.Depth]or 1)*rarityMultiplier*(C.Depth[d.Depth]or 1)*(f.Weight or 1)*(f.Mutation or 1)*event
  *(1+math.clamp(f.SellBonus or 0,0,C.MaxEarnedBonus))*C.Seasonal
 return (softCap(raw,d))*income(f.IncomeMult)
end
return V
