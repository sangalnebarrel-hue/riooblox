local WorldModifiers=require(game.ReplicatedStorage.WorldEvents.WorldEventModifiers)
-- Pure discovery rules, called only by the existing server economy transaction.
local D=require(script.Parent.ItemDefinitions)
local Depth=require(script.Parent.DepthDefinitions)
local Profiles=require(script.Parent.WeightProfiles)
local Mutations=require(script.Parent.MutationDefinitions)
local Sets=require(script.Parent.SetDefinitions)
local Stats=require(script.Parent.RecordStats)
local I={Definitions=D,Depths=Depth,Profiles=Profiles,Mutations=Mutations,Sets=Sets}
local Economy=require(game.ReplicatedStorage.DogEconomy.Config)
local LuckItemBoost=Economy.LuckItemBoost or .4
local Bonuses=require(game.ReplicatedStorage.DogEconomy.Bonuses)
local Signatures=require(script.Parent.SignatureRules)
local Valuation=require(game.ReplicatedStorage.ItemValuation)
local ValueConfig=require(game.ReplicatedStorage.ItemValueConfig)
local Protection=require(script.Parent.ItemProtection)
local function check(v,s)if not v then error(s,0)end end
local function copy(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function count(t)local n=0;for _ in pairs(t or {})do n+=1 end;return n end
I.Count=count
function I.Normalize(p)
 p.Items=p.Items or {};p.Collection=p.Collection or {};p.MutationJournal=p.MutationJournal or {}
 p.PersonalRecords=p.PersonalRecords or {};p.HeavyCollection=p.HeavyCollection or {};p.ItemSets=p.ItemSets or {}
 p.RecordJobs=p.RecordJobs or {};p.DiscoveryFeed=p.DiscoveryFeed or {};p.ItemReservations=p.ItemReservations or {}
 p.DexFavorites=p.DexFavorites or {};p.TrackedListings=p.TrackedListings or {};for _,x in pairs(p.Items)do x.Locked=nil end;Stats.Normalize(p)
end
-- Discovery (item) slots. I.Validate refuses more than this many items in any profile.
I.HardCap=1000
-- Slots beyond the Storage upgrade: Storage bonuses (Bonuses pipeline, flat units), an active
-- Storage Crate, and the team Storage aura (Black Hole Pug, Taxi Dachshund). Ordinary loot is paid
-- straight into the wallet (Rules.Dig), so storage now means discoveries only.
function I.CapacityExtra(p,now,global)
 now=now or os.time()
 local extra=tonumber((global or Bonuses.Global(p,now)).Storage)or 0
 local crate=type(p.Supplies)=='table'and p.Supplies.StorageCrate
 if type(crate)=='number'and crate>now then extra+=Economy.Supplies.StorageCrate.Magnitude end
 if type(p.Dogs)=='table'then extra+=math.floor(50*(Signatures.Team(p,now).Storage or 0))end
 return math.max(0,math.floor(extra))
end
function I.Capacity(p,extra)
 if extra==nil then extra=I.CapacityExtra(p)end
 return math.min(I.HardCap,50+25*((p.Upgrades or {}).Storage or 0)+math.max(0,math.floor(extra)))
end
-- capacity: optional precomputed I.Capacity(p) (hot paths compute it once per dig).
function I.Free(p,capacity)return count(p.Items)+count(p.ItemReservations)<(capacity or I.Capacity(p))end
-- transfer: the find is about to leave the profile for another player or system (trade offer,
-- market listing, lab catalyst): it must be tradeable, past its record check and not protected
-- (Economy.ItemProtection, 'Transfer' context).
function I.Get(p,uid,transfer)
 check(type(uid)=='string' and #uid<=100,'Invalid ItemUid')
 local x=p.Items[uid];check(x and x.ItemUid==uid and x.OwnerUserId==p.UserId,'Item not owned')
 if transfer then
  check(x.Tradeable,'This item cannot be transferred')
  check(not (p.RecordJobs[x.ItemId] and p.RecordJobs[x.ItemId].ItemUid==uid),'Record check pending; retry shortly')
  local protected=Protection.Reason(p,uid,'Transfer');check(not protected,protected)
 end
 return x
end
function I.Discover(p,x,original)
 I.Normalize(p);p.Collection[x.ItemId]=true
 p.MutationJournal[x.ItemId]=p.MutationJournal[x.ItemId] or {};p.MutationJournal[x.ItemId][x.Mutation]=true
 if x.TierIndex>=4 then p.HeavyCollection[x.ItemId]=true end
 if original then
  local best=p.PersonalRecords[x.ItemId]
  if not best or x.WeightKg>best.WeightKg then
   x.RecordAtCreation.Personal=true
   p.PersonalRecords[x.ItemId]={WeightKg=x.WeightKg,ItemUid=x.ItemUid,Finder=x.OriginalFinderUserId,At=x.FoundAt}
  end
 end
end
function I.Transfer(p,x)
 check(not p.Items[x.ItemUid],'Duplicate ItemUid');x.OwnerUserId=p.UserId;p.Items[x.ItemUid]=x;I.Discover(p,x,false)
end
function I.Weight(profile,random,luck,maxMultiplier,eventLuck)
 local rows=Profiles[profile];check(rows,'Unknown weight profile')
 local boost=1+math.clamp(luck or 0,0,.15)
 local eventBoost=1+math.clamp(eventLuck or 0,0,.15)
 local extra=0;for i=4,10 do extra+=rows[i].Chance*(boost*(i<=6 and eventBoost or 1)-1)end
 local r=random();local sum=0;local index=10;local chance
 for i,v in ipairs(rows)do
  local p=v.Chance*(i>=4 and boost*(i<=6 and eventBoost or 1)or 1)-(i==3 and extra or 0)
  sum+=p;if r<sum then index=i;chance=p;break end
 end
 local row=rows[index];chance=chance or row.Chance*boost
 local lo,hi=row.Min,row.Max
 if maxMultiplier and maxMultiplier>0 then
  -- A statue has a much smaller physical tail. Preserve tier probabilities while
  -- compressing every tier boundary monotonically into its declared mass cap.
  local exponent=math.log(maxMultiplier)/math.log(rows[10].Max)
  lo=lo^exponent;hi=hi^exponent
 end
 local u=random();local ratio
 if index==3 then
  local mode=math.clamp(1,lo,hi);local split=(mode-lo)/(hi-lo)
  ratio=u<split and lo+math.sqrt(u*(hi-lo)*(mode-lo)) or hi-math.sqrt((1-u)*(hi-lo)*(hi-mode))
 elseif index>=5 then ratio=lo*math.exp(math.log(hi/lo)*u*u)
 else ratio=lo+(hi-lo)*u end
 return ratio,index,chance,(ratio-lo)/(hi-lo)
end
function I.ItemChance(def,e)
 e=e or {}
 local boost=1
 if def.BaseDropChance<.01 and def.Class~='Secret' then
  boost+=math.min(.5,(e.Luck or 0)+(e.TreasureMap or 0)+(e.Protection or 0))
  if def.Class=='Artifact'then boost+=math.min(.2,(e.Identification or 0)+(e.Artifact or 0))end
  if def.Depth==5 then boost+=math.min(.15,e.AlienArtifact or 0)end
  if def.Depth==3 or def.Depth==5 then boost+=math.min(.1,e.DigitalLuck or 0)end
  if def.Class=='Treasure'then boost+=math.min(.1,e.GoldLoot or 0)end
 end
 if def.Depth==e.EventDepth then boost*=1+math.min(.15,e.EventDepthLuck or 0)end
 if def.Class=='Secret'then boost=1+math.min(.08,e.SecretLuck or 0)end
 -- Bought luck (LUCK tab) works on top of every capped bonus, on the rare tail only.
 local bought=math.clamp(e.BoostLuck or 0,0,5)
 local extra=def.BaseDropChance<.01 and 1+bought*(def.Class=='Secret'and .1 or LuckItemBoost)or 1
 -- Global Fix 1.1: a small natural boost to valuable non-Secret discoveries.
 local rareTail=def.Class~='Secret'and def.BaseDropChance<.01 and(1.0667+0.0133*math.clamp(def.Depth or 1,1,5))or 1
 -- Bonuses pipeline (upgrade tree, accessories, artifacts), after every legacy cap and on the rare
 -- tail only: RareFind multiplies the chance; Luck works like bought luck (LuckItemBoost per +100%).
 local pipeline=1
 if def.BaseDropChance<.01 then
  local secret=def.Class=='Secret'
  pipeline=(1+math.max(0,tonumber(e.RareFind)or 0)*(secret and .1 or 1))*(1+math.max(0,tonumber(e.BonusLuck)or 0)*(secret and .1 or LuckItemBoost))
 end
 return def.BaseDropChance*math.min(1.75,boost)*extra*rareTail*pipeline*math.clamp(e.DiscoveryScale or 1,0,1)
end
function I.Pick(depth,random,e)
 e=e or {}
 local rows={};local total,common=0,0
 for _,id in ipairs(Depth[tostring(depth)].Items)do
  local def=D[id];local p=I.ItemChance(def,e);table.insert(rows,{def,p});total+=p
  if def.BaseDropChance>=.01 then common+=p end
 end
 -- Luck can lift the rare tail far enough that a whole roll would be spent before reaching it:
 -- the common items give way, so every item stays reachable. Unboosted rolls never get here.
 local over=total-.98
 local scale=over>0 and common>0 and math.max(0,(common-over)/common)or 1
 local r=random();local sum=0
 for _,row in ipairs(rows)do
  local p=row[2]*(row[1].BaseDropChance>=.01 and scale or 1)
  sum+=p;if r<sum then return row[1],p end
 end
 return nil
end
-- The mutation table one discovery rolls on (row order kept: NORMAL first, GLITCHED fifth).
-- e.ItemMutation (Bonuses pipeline) grows every mutated row by (1+bonus); NORMAL stays the
-- remainder and keeps at least half of all finds. The dog's signature mutation procs on top.
function I.MutationRows(e)
 e=e or {}
 local rows={};local signature=string.upper(e.SignatureMutation or '')
 local proc=signature~='' and math.clamp(e.SignatureMutationChance or 0,0,.3)or 0
 local extra=math.min(.0005,(e.Duplicate or 0)*.001+(e.Enchant or 0)*.001)
 local base=WorldModifiers.MutationRows(Mutations,'Name','Chance',os.time())
 local boost=math.max(0,tonumber(e.ItemMutation)or 0);local scale=1;local mutated=0
 for i,m in ipairs(base)do if i>1 then mutated+=m.Chance end end
 if boost>0 and mutated>0 then scale=math.max(1,math.min(1+boost,.5/mutated))end
 local matched=false
 for i,m in ipairs(base)do
  local chance=i>1 and m.Chance*scale or m.Chance-mutated*(scale-1)
  chance=(chance+(i==5 and extra or i==1 and -extra or 0))*(1-proc)
  if m.Name==signature then chance+=proc;matched=true end
  table.insert(rows,{Name=m.Name,Chance=math.max(0,chance),ValueMultiplier=m.ValueMultiplier})
 end
 if proc>0 and not matched then table.insert(rows,{Name=signature,Chance=proc,ValueMultiplier=e.SignatureMutationValue or 1})end
 return rows
end
function I.Mutation(random,e)
 local rows=I.MutationRows(e)
 local r=random();local sum=0
 for _,m in ipairs(rows)do sum+=m.Chance;if r<sum then return m,m.Chance end end
 return rows[#rows],rows[#rows].Chance
end
local values={{.55,.55},{.8,.8},{.9,1.25},{1.5,2.4},{3,6},{8,18},{25,75},{120,400},{800,3000},{5000,25000}}
function I.NPCValue(def,tier,t,mutation,sellBonus)
 local mult=values[tier][1]+(values[tier][2]-values[tier][1])*t
 -- Stable ordinary digging remains the main income source, including endgame.
 local layerValueScale=({1,1,1,.55,.4})[def.Depth]
 local raw=def.BaseValue*layerValueScale*mult*mutation.ValueMultiplier*(1+math.min(.5,sellBonus or 0))
 local cap=Depth[tostring(def.Depth)].IncomeReference*3600*60
 return math.max(1,math.floor(raw<=cap*.8 and raw or cap*.8+cap*.2*(1-math.exp(-(raw-cap*.8)/(cap*.2)))))
end
function I.Mint(p,def,baseChance,uid,now,random,e)
 I.Normalize(p);check(I.Free(p,e.ItemCapacity) and not p.Items[uid],'Item storage full or duplicate ItemUid')
 local ratio,tier,chance,t=I.Weight(def.WeightProfile,random,e.WeightLuck,def.MaxWeightMultiplier,e.EventWeightLuck)
 local mutation,mp=I.Mutation(random,e)
 local weight=def.BaseWeightKg*ratio
 local sell=1
 local x={ItemUid=uid,ItemId=def.Id,DisplayName=def.DisplayName,Depth=def.Depth,Class=def.Class,SetId=def.SetId,
  BaseDropChance=def.BaseDropChance,EffectiveDropChance=baseChance,BaseWeightKg=def.BaseWeightKg,WeightKg=weight,
  WeightMultiplier=ratio,WeightTier=Profiles[def.WeightProfile][tier].Name,TierIndex=tier,WeightProfile=def.WeightProfile,
  WeightTierChance=chance,Mutation=mutation.Name,MutationChance=mp,CombinedOdds=1/(baseChance*chance*mp),
  FoundAt=now,FoundByUserId=p.UserId,OriginalFinderUserId=p.UserId,OwnerUserId=p.UserId,SellValue=math.max(1,sell),
  Tradeable=true,RecordAtCreation={Personal=false,Server=false,Global=false},Favorite=false}
 x.SourceDogUid=e.SourceDogUid
 x.FirstFind=not p.Collection[x.ItemId];x.SellBonus=e.SellValue or 0
 -- Income multipliers of the finder (Bonuses pipeline) are fixed on the item when it is found;
 -- the sale price never reads live bonuses (ItemValuation.Price).
 local incomeMult=tonumber(e.IncomeMult)
 if incomeMult and incomeMult==incomeMult and incomeMult>0 and math.abs(incomeMult-1)>1e-9 then x.IncomeMult=math.clamp(incomeMult,.1,100)end
 local event=WorldModifiers.Current;if event and event~='NORMAL'then x.EventTag=event end
 x.SellValue,x.ValueBreakdown=Valuation.Price(x);x.ValueVersion=x.ValueBreakdown.Version
 p.Items[uid]=x;I.Discover(p,x,true);Stats.Find(p,x)
 local job=p.RecordJobs[x.ItemId]
 if not job or x.WeightKg>job.WeightKg then p.RecordJobs[x.ItemId]=copy(x)end
 table.insert(p.DiscoveryFeed,1,copy(x));while #p.DiscoveryFeed>20 do table.remove(p.DiscoveryFeed)end
 return x
end
function I.Action(p,action,a)
 I.Normalize(p)
 if action=='ItemLock' then local x=I.Get(p,a.Uid,false);x.Locked=nil;return 'Item locking is disabled'
 elseif action=='ItemFavorite' then local x=I.Get(p,a.Uid,false);check(type(a.Enabled)=='boolean','Invalid toggle');x.Favorite=a.Enabled;return 'Updated'
 elseif action=='SellItem'then local x=I.Get(p,a.Uid,true);local cash=x.SellValue;Stats.Sale(p,cash);p.Items[a.Uid]=nil;return 'Sold '..x.DisplayName,cash
 elseif action=='ItemSetClaim'then
  local set=Sets[a.Set];check(set,'Unknown set');local heavy=a.Heavy==true;local key=a.Set..(heavy and ':Heavy' or ':Normal')
  check(not p.ItemSets[key],'Already claimed')
  check(not heavy or p.ItemSets[a.Set..':Normal'],'Complete the ordinary set first')
  for _,id in ipairs(set.Items)do check((heavy and p.HeavyCollection or p.Collection)[id],'Collection incomplete')end
  p.ItemSets[key]=true;p.Cosmetics['Discovery:'..key]=true;p.Bones+=heavy and 20 or 10;return 'Collection title unlocked'
 end
 return nil
end
-- Expected-value helpers for the shared income model (Economy.IncomeModel). Pure and cached.
-- Mean ItemValuation weight factor of one find: tier odds as in I.Weight, each tier integrated
-- over its own ratio curve (64 midpoints).
local weightCache={}
function I.WeightFactor(profile,luck,maxMultiplier,eventLuck)
 local key=table.concat({profile,string.format('%.3f',luck or 0),tostring(maxMultiplier or 0),string.format('%.3f',eventLuck or 0)},'|')
 local hit=weightCache[key];if hit then return hit end
 local rows=Profiles[profile];if not rows then return 1 end
 local boost=1+math.clamp(luck or 0,0,.15);local eventBoost=1+math.clamp(eventLuck or 0,0,.15)
 local extra=0;for i=4,10 do extra+=rows[i].Chance*(boost*(i<=6 and eventBoost or 1)-1)end
 local exponent=maxMultiplier and maxMultiplier>0 and math.log(maxMultiplier)/math.log(rows[10].Max)or nil
 local total,mass=0,0
 for i,v in ipairs(rows)do
  local p=math.max(0,v.Chance*(i>=4 and boost*(i<=6 and eventBoost or 1)or 1)-(i==3 and extra or 0))
  if i==#rows then p=math.max(0,1-mass)end
  mass+=p
  local lo,hi=v.Min,v.Max
  if exponent then lo=lo^exponent;hi=hi^exponent end
  local sum=0
  for k=1,64 do
   local u=(k-.5)/64;local ratio
   if i==3 then
    local mode=math.clamp(1,lo,hi);local split=hi>lo and(mode-lo)/(hi-lo)or 0
    ratio=u<split and lo+math.sqrt(u*(hi-lo)*(mode-lo))or hi-math.sqrt((1-u)*(hi-lo)*(hi-mode))
   elseif i>=5 then ratio=lo*math.exp(math.log(hi/lo)*u*u)
   else ratio=lo+(hi-lo)*u end
   sum+=math.clamp(math.max(.00001,ratio)^ValueConfig.WeightExponent,ValueConfig.WeightMin,ValueConfig.WeightMax)
  end
  total+=p*(ValueConfig.WeightTier[i]or 1)*sum/64
 end
 weightCache[key]=total
 return total
end
-- Mean ItemValuation mutation factor of one find with effects e.
function I.MutationFactor(e)
 local sum=0
 for _,m in ipairs(I.MutationRows(e))do sum+=m.Chance*(ValueConfig.Mutation[string.upper(m.Name)]or 1)end
 return sum
end
-- One item attempt at `depth` with effects e (the per-dog copy Rules.ItemEffects builds):
-- chance that it finds something, and the expected sale value of the attempt (coins).
function I.ExpectedFind(depth,e)
 e=e or {}
 local list=Depth[tostring(depth)];if not list then return 0,0 end
 local rows={};local total,common=0,0
 for _,id in ipairs(list.Items)do
  local def=D[id];local p=I.ItemChance(def,e);table.insert(rows,{def,p});total+=p
  if def.BaseDropChance>=.01 then common+=p end
 end
 local over=total-.98
 local scale=over>0 and common>0 and math.max(0,(common-over)/common)or 1
 local mutation=I.MutationFactor(e)
 local found,value=0,0
 for _,row in ipairs(rows)do
  local def=row[1];local p=row[2]*(def.BaseDropChance>=.01 and scale or 1)
  found+=p
  value+=p*Valuation.Expected(def,{Weight=I.WeightFactor(def.WeightProfile,e.WeightLuck,def.MaxWeightMultiplier,e.EventWeightLuck),
   Mutation=mutation,SellBonus=e.SellValue,IncomeMult=e.IncomeMult,EventTag=e.EventId})
 end
 return math.min(1,found),value
end
function I.Validate(p)
 I.Normalize(p);check(count(p.Items)<=1000,'Item hard cap exceeded')
 for uid,x in pairs(p.Items)do check(D[x.ItemId] and uid==x.ItemUid and x.OwnerUserId==p.UserId and type(x.WeightKg)=='number' and x.WeightKg>0 and x.WeightKg<math.huge,'Invalid item instance')end
end
return I
