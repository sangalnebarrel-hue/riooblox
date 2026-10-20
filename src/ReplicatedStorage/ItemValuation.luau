local RS=game:GetService('ReplicatedStorage')
local C=require(RS.ItemValueConfig);local D=require(RS.DogEconomy.ItemDefinitions);local Depth=require(RS.DogEconomy.DepthDefinitions)
local V={}
local function rarityOf(d)
 if d.Class=='Secret'then return 'Secret',C.SecretMultiplier end
 for _,row in ipairs(C.Rarity)do if d.BaseDropChance<=row.MaxChance then return row.Name,row.Multiplier end end
 return 'Common',1
end
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
-- Event mutations (C.PostCapMutation, NIGHT OF THE BURIED MOON) multiply AFTER the soft cap, like Income, so x20
-- really is x20 on a valuable find; the result never exceeds C.PostCapLimit (and never drops below the plain price).
local function postCap(price,mult)
 if mult==1 then return price end
 return math.max(price,math.min(price*mult,C.PostCapLimit or math.huge))
end
V.PostCap=postCap
function V.MutationFactors(name)
 local key=string.upper(tostring(name or 'NORMAL'))
 local m=C.Mutation[key]or 1
 if C.PostCapMutation and C.PostCapMutation[key]then return 1,m end
 return m,1
end
function V.Price(x)
 local d=D[x.ItemId];assert(d,'Unknown item')
 local rarity,rarityMultiplier=rarityOf(d)
 local ratio=math.max(.00001,(x.WeightKg or d.BaseWeightKg)/d.BaseWeightKg)
 local weight=(C.WeightTier[math.clamp(x.TierIndex or 3,1,10)]or 1)*math.clamp(ratio^C.WeightExponent,C.WeightMin,C.WeightMax)
 local event=x.EventTag or (type(x.Origin)=='string'and x.Origin:match('^WorldEvent:(.+)$'))
 local preMutation,postMutation=V.MutationFactors(x.Mutation)
 local factors={Base=d.BaseValue*(C.BaseScale[d.Depth]or 1),Rarity=rarityMultiplier,Depth=C.Depth[d.Depth]or 1,Weight=weight,Mutation=preMutation,Event=event and (C.Events[event]or C.EventDefault)or 1,Bonus=(x.FirstFind and C.FirstFind or 1)*(1+math.clamp(x.SellBonus or 0,0,C.MaxEarnedBonus))*C.Seasonal,Income=income(x.IncomeMult),PostMutation=postMutation}
 local raw=factors.Base*factors.Rarity*factors.Depth*factors.Weight*factors.Mutation*factors.Event*factors.Bonus
 local result,cap=softCap(raw,d)
 return math.max(1,math.floor(postCap(result*factors.Income,postMutation))),{Version=C.Version,Rarity=rarity,Factors=factors,Raw=raw,Cap=cap}
end
-- Expected sale value of a find of `d` before it is rolled: the same formula as V.Price with the
-- mean weight and mutation factors (ItemRules.WeightFactor / MutationFactor). Used only for
-- income estimates (Economy.IncomeModel), never to pay.
-- f.PostMutation: mean post-cap factor of the event mutation rows (ItemRules.MutationFactor's second value).
function V.Expected(d,f)
 f=f or {}
 local _,rarityMultiplier=rarityOf(d)
 local event=f.EventTag and (C.Events[f.EventTag]or C.EventDefault)or 1
 local raw=d.BaseValue*(C.BaseScale[d.Depth]or 1)*rarityMultiplier*(C.Depth[d.Depth]or 1)*(f.Weight or 1)*(f.Mutation or 1)*event
  *(1+math.clamp(f.SellBonus or 0,0,C.MaxEarnedBonus))*C.Seasonal
 return postCap((softCap(raw,d))*income(f.IncomeMult),math.max(1,tonumber(f.PostMutation)or 1))
end
return V
