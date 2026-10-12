-- Expected income: the one model behind every income number the game shows or prices with
-- (HUD "+$/min", Yard and dog stats via Runtime.Snapshot/Project, OfflineEarnings.Estimate, which
-- feeds offline coins, boost prices and Robux coin packs). It mirrors Rules.Dig term by term and
-- reuses its helpers (Rules.Cooldown, RollMultiplier, LootLuck, LootWeight, ItemEffects), so a new
-- bonus that reaches Rules.Dig reaches every estimate too. Pure: it never writes the profile.
-- Called as Rules.IncomeModel(p,now,options) (R is passed in; this module must not require Rules).
--   options.AssignedOnly  only dogs at work (team totals always count working dogs only)
--   options.Potential     count discoveries even when item storage is full (offline / pricing)
-- Result: {PerMinute, LootPerMinute, ItemsPerMinute, ItemFull, Layer, Reference, Dogs={[uid]=stats}}
-- stats: {Assigned, Cooldown, Cycle, Overflow, DigsPerMin, Rolls, CoinsPerMin, LootPerMin,
--         ItemsPerMin, ItemFindsPerMin, LuckPct, Efficiency}
local C=require(script.Parent.Config)
local D=require(script.Parent.DogDefinitions)
local I=require(script.Parent.ItemRules)
local Signatures=require(script.Parent.SignatureRules)
local LuckRules=require(script.Parent.LuckRules)
local Bonuses=require(game:GetService('ReplicatedStorage').DogEconomy.Bonuses)
local M={Samples=120}

-- Signature contexts (SignatureRules.Context) are random and depend on the dig number. They are
-- sampled on a sandbox (Context writes TreasureMapUntil/TimePulseUntil on its profile) with a
-- stratified deterministic random source over 120 consecutive digs (every WorkSequence cycle in
-- the catalog divides 60), grouped into distinct shapes and cached for the server per 5 minutes:
-- every clock a context reads (Don Puglione's 300 s rotation, night hours) changes on 300 s marks.
local buckets={}
local function store(now)
 local bucket=math.floor(now/300)
 local s=buckets[bucket]
 if not s or s.Count>4000 then
  s={Shapes={},Finds={},Count=0};buckets[bucket]=s
  -- Keep the live bucket, the one before it, and the fixed offline instant (bucket 0).
  for k in pairs(buckets)do if k~=bucket and k~=0 and k<bucket-1 then buckets[k]=nil end end
 end
 return s
end
local GOLDEN=.6180339887498949
local fmt=tostring
local function pairsKey(t)
 local keys={};for k in pairs(t or {})do table.insert(keys,k)end;table.sort(keys)
 local parts={};for _,k in ipairs(keys)do table.insert(parts,k..'='..fmt(t[k]))end
 return table.concat(parts,',')
end
local SHAPE_FIELDS={'Rolls','Value','Depth','ItemAttempts','ItemScale','WeightLuck','Mutation','MutationChance','MutationValue',
 'BananaCombo','SkeletonChance','SpoilChance','AutoDeposit','Orbit','Protection','BadLuckGuard'}
local function shapeKey(c)
 local parts={}
 for _,k in ipairs(SHAPE_FIELDS)do table.insert(parts,fmt(c[k]))end
 table.insert(parts,pairsKey(c.CategoryLuck));table.insert(parts,pairsKey(c.CategoryValue))
 return table.concat(parts,'|')
end
local function maxDepth(p)
 local deepest=1
 for i=1,#C.Layers do if (p.UnlockedLayers or {})[tostring(i)]then deepest=i else break end end
 return deepest
end
-- {{Ctx=ctx, Weight=share}, ...} for one dog kind in this team/profile state.
local function shapes(p,d,e,now,deepest)
 local s=store(now)
 local mapActive=now<(tonumber(p.TreasureMapUntil)or 0)
 local key=table.concat({d.DogId,tostring(p.CurrentLayer or 1),deepest,tostring(e.FoodCount or 0),tostring(e.EventId or ''),mapActive and 1 or 0},'|')
 local hit=s.Shapes[key];if hit then return hit end
 local sandbox={CurrentLayer=p.CurrentLayer or 1,UnlockedLayers=p.UnlockedLayers or {['1']=true}}
 local dog={DogId=d.DogId,FoodStreak=0,TreasureStreak=0}
 local team={FoodCount=e.FoodCount or 0,EventId=e.EventId}
 local n=M.Samples;local groups,order={},{}
 for sample=1,n do
  local calls=0
  local random=function()calls+=1;return ((sample-.5)/n+(calls-1)*GOLDEN)%1 end
  sandbox.TreasureMapUntil=mapActive and now+60 or 0;sandbox.TimePulseUntil=0;dog.WorkSequence=sample
  local ctx=Signatures.Context(sandbox,dog,team,now,random)
  ctx.Depth=math.min(ctx.Depth,deepest)
  local k=shapeKey(ctx)
  local g=groups[k]
  if g then g.Weight+=1/n else g={Ctx=ctx,Weight=1/n};groups[k]=g;table.insert(order,g)end
 end
 s.Shapes[key]=order;s.Count+=1
 return order
end
-- Expected coins and find chance of one item attempt, cached by everything that changes them.
local FIND_FIELDS={'WeightLuck','SignatureMutation','SignatureMutationChance','SignatureMutationValue','DiscoveryScale','SellValue','Artifact',
 'DigitalLuck','BoostLuck','RareFind','ItemMutation','BonusLuck','IncomeMult','Luck','TreasureMap','Protection','Identification','AlienArtifact',
 'GoldLoot','EventDepth','EventDepthLuck','SecretLuck','EventWeightLuck','Duplicate','Enchant','EventId'}
local function expectedFind(depth,effects,now)
 local s=store(now)
 local parts={tostring(depth)}
 for _,k in ipairs(FIND_FIELDS)do table.insert(parts,fmt(effects[k]))end
 local key=table.concat(parts,'|')
 local hit=s.Finds[key]
 if not hit then
  local found,value=I.ExpectedFind(depth,effects)
  hit={found,value};s.Finds[key]=hit;s.Count+=1
 end
 return hit[1],hit[2]
end
-- Mean coins of one loot roll (before the dog's roll count) and the mean multiplier the dog puts
-- on rare-loot weights (1 = base table): the same weights and factors as Rules.Dig / SignatureRules.Modify.
local function lootRoll(R,p,layer,ctx,e,luck,base)
 local total,value,rare,rareBase=0,0,0,0
 for _,item in ipairs(layer.Loot)do
  local weight,isRare=R.LootWeight(item,luck,ctx,e,p)
  local category=item[2]
  local m=ctx.Value*(ctx.CategoryValue[category]or 1)
  if ctx.BananaCombo and category=='Junk'then m*=1.18 end
  if ctx.SkeletonChance and category=='Bone'then m*=1+ctx.SkeletonChance end
  if ctx.Mutation and (ctx.MutationChance or 0)>0 then m*=1+ctx.MutationChance*((ctx.MutationValue or 1)-1)end
  if ctx.SpoilChance then m*=1-.8*ctx.SpoilChance*(1-math.min(.8,(e.Cleanse or 0)+(e.Protection or 0)))end
  m=math.max(.05,m)
  if category=='Corrupted'then m*=1-math.max(0,.15-(e.Cleanse or 0)-(ctx.Protection or 0))end
  value+=weight*math.max(1,item[4]*base*m-.5);total+=weight
  if isRare then rare+=weight;rareBase+=item[3]end
 end
 return total>0 and value/total or 0,rareBase>0 and rare/rareBase or 1
end
local REFERENCE_DEF={Rank=1,PowerBudget=C.Power[1]}
-- Expected yield of one dog (or the reference dog when def is REFERENCE_DEF).
local function dogStats(R,p,d,def,e,b,now,env,shapeRows)
 local cooldown,overflow=R.Cooldown(env.SpeedView,d,e,b)
 local cycle=cooldown+C.Work.Duration
 local digsPerMin=60/cycle
 local lootPerDig,itemsPerDig,findsPerDig,rollsPerDig,luckMult,weights=0,0,0,0,0,0
 for _,shape in ipairs(shapeRows)do
  local ctx=shape.Ctx;local layer=C.Layers[ctx.Depth]or C.Layers[1]
  local base=R.RollMultiplier(p,d,def,e,b,env.Biscuit,ctx)
  local luck=R.LootLuck(p,e,now,env.BoostLuck,b)
  local roll,rareMult=lootRoll(R,p,layer,ctx,e,luck,base)
  local rolls=(ctx.Rolls or 0)*overflow
  local loot=rolls*roll*(ctx.Orbit and 1+R.OrbitBonus or 1)
  local items,finds=0,0
  if (ctx.ItemAttempts or 0)>0 and (env.Potential or not env.ItemFull)then
   local found,value=expectedFind(ctx.Depth,R.ItemEffects(p,d,e,ctx,b,env.BoostLuck,env.ItemCapacity),now)
   local attempts=ctx.ItemAttempts*overflow
   items=attempts*value;finds=attempts*found
  end
  lootPerDig+=shape.Weight*loot;itemsPerDig+=shape.Weight*items;findsPerDig+=shape.Weight*finds
  rollsPerDig+=shape.Weight*rolls;luckMult+=shape.Weight*rareMult;weights+=shape.Weight
 end
 if weights>0 then
  lootPerDig/=weights;itemsPerDig/=weights;findsPerDig/=weights;rollsPerDig/=weights;luckMult/=weights
 end
 local luckPct=(luckMult-1)*100
 if math.abs(luckPct)<1e-9 then luckPct=0 end
 return {Cooldown=cooldown,Cycle=cycle,Overflow=overflow,DigsPerMin=digsPerMin,Rolls=rollsPerDig,
  CoinsPerMin=(lootPerDig+itemsPerDig)*digsPerMin,LootPerMin=lootPerDig*digsPerMin,ItemsPerMin=itemsPerDig*digsPerMin,
  ItemFindsPerMin=findsPerDig*digsPerMin,LuckPct=luckPct}
end
function M.Compute(R,p,now,options)
 options=options or {}
 now=now or os.time()
 local e=R.Team(p,now)
 local global=Bonuses.Global(p,now)
 local capacity=I.Capacity(p,I.CapacityExtra(p,now,global))
 -- Only dogs at work can be a dog's neighbours (SignatureRules.Speed), so cooldowns read a view of the
 -- profile that lists just them: identical results, without scanning every owned dog for every dog.
 local working={}
 for uid,d in pairs(p.Dogs or {})do if Signatures.Active(d)then working[uid]=d end end
 local env={BoostLuck=LuckRules.Bonus(p,now),Biscuit=((p.Supplies or {}).GoldenBiscuit or 0)>now,ItemCapacity=capacity,
  ItemFull=not I.Free(p,capacity),Potential=options.Potential==true,SpeedView=setmetatable({Dogs=working},{__index=p})}
 local deepest=maxDepth(p)
 local layerIndex=math.clamp(math.floor(tonumber(p.CurrentLayer)or 1),1,#C.Layers)
 local abilityValue=1+C.UpgradeEffects.Ability*((p.Upgrades or {}).Ability or 0)
 -- Plain reference dog: a signature-less Common, Normal, Mastery 0, same team and bonuses.
 local refDog={DogUid='',DogId='',Variant='Normal',Mastery=0,AscensionLevel=0,AssignedSlot='DigSlot_99',State='Digging'}
 local refCtx={Rolls=2,Value=abilityValue,XP=1,Depth=math.min(layerIndex,deepest),CategoryLuck={},CategoryValue={},WeightLuck=0,ItemAttempts=1,ItemScale=1,MutationChance=0,MutationValue=1}
 local reference=dogStats(R,p,refDog,REFERENCE_DEF,e,global,now,env,{{Ctx=refCtx,Weight=1}})
 local result={PerMinute=0,LootPerMinute=0,ItemsPerMinute=0,ItemFull=env.ItemFull,ItemCapacity=capacity,Layer=layerIndex,Reference=reference,Dogs={}}
 for uid,d in pairs(p.Dogs or {})do
  local def=D[d.DogId]
  local assigned=Signatures.Active(d)
  if def and (assigned or not options.AssignedOnly)then
   local rows=shapes(p,d,e,now,deepest)
   -- Each dig multiplies ctx.Value by the Ability upgrade (Rules.Dig); shapes hold the raw context.
   local scaled={}
   for i,shape in ipairs(rows)do
    local ctx=table.clone(shape.Ctx);ctx.Value*=abilityValue
    scaled[i]={Ctx=ctx,Weight=shape.Weight}
   end
   local stats=dogStats(R,p,d,def,e,Bonuses.For(p,d,now,global),now,env,scaled)
   stats.Assigned=assigned
   stats.Efficiency=reference.CoinsPerMin>0 and stats.CoinsPerMin/reference.CoinsPerMin or 0
   result.Dogs[uid]=stats
   if assigned then
    result.PerMinute+=stats.CoinsPerMin;result.LootPerMinute+=stats.LootPerMin;result.ItemsPerMinute+=stats.ItemsPerMin
   end
  end
 end
 return result
end
return M
