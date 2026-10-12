-- Shared genetics rules of the laboratory: the server (Economy.LabRules) validates and prices with
-- these functions, and the client (Modules.LabScreen) uses the very same ones to grey out dogs with
-- the real reason, show costs, yields and odds before asking the server, and auto-pick inputs.
-- Pure: reads profile tables, never changes them. Safe on the server and the client.
local RS=game:GetService('ReplicatedStorage')
local C=require(RS.LabConfig)
local Defs=require(RS.DogEconomy.DogDefinitions)
local Base=require(RS.DogEconomy.Config)
local G={}

local function count(t)local n=0;for _ in pairs(type(t)=='table'and t or{})do n+=1 end;return n end
G.Count=count
local function copy(t)local r={};for k,v in pairs(t or{})do r[k]=v end;return r end

function G.Procedure(id)
 for _,v in ipairs(C.Procedures)do if v.Id==id then return v end end
 return nil
end

function G.Rank(d)
 local def=type(d)=='table'and Defs[d.DogId]or Defs[d]
 return def and def.Rank or 1
end

-- Genetic tags (DNA sample keys) of a dog: LabConfig.Genetics wins, else the catalogue tags.
local aliases={CYBER='DIGITAL',EXPLORERS='NORMAL',DACHSHUND='NORMAL'}
function G.Tags(d)
 local id=type(d)=='table'and d.DogId or d
 local override=C.Genetics[id]
 if override then return table.clone(override)end
 local tags={}
 local def=Defs[id]
 for _,tag in ipairs(def and def.Tags or{})do
  local key=string.upper(tostring(tag));key=aliases[key]or key
  if C.DNA[key]and not table.find(tags,key)then table.insert(tags,key)end
 end
 if #tags==0 then tags={'NORMAL'}end
 return tags
end

function G.OnDisplay(p,uid)
 for _,v in pairs(type(p)=='table'and type(p.DisplayDogs)=='table'and p.DisplayDogs or{})do
  if v==uid then return true end
 end
 return false
end

-- Why a dog cannot enter the chamber. The order and the words are the server's (Rules.Dog + LabRules.Dog).
G.Messages={
 Missing='Dog not owned',
 Walking='Wait for delivery',
 Locked='Unlock this dog first',
 Kennel='Remove this dog from its kennel first',
 Busy='Return this dog to storage first',
 Favorite='Remove this dog from favorites before a procedure',
 Display='Remove this dog from its display first',
 Unavailable='This dog is not available for laboratory procedures',
}
-- ok, code, message
function G.Check(p,d)
 if type(d)~='table'or type(d.DogUid)~='string'then return false,'Missing',G.Messages.Missing end
 if d.State=='Walking'then return false,'Walking',G.Messages.Walking end
 if d.Locked then return false,'Locked',G.Messages.Locked end
 if(d.AssignedSlot or'')~=''then return false,'Kennel',G.Messages.Kennel end
 if d.State~='Inventory'then return false,'Busy',G.Messages.Busy end
 if d.Favorite then return false,'Favorite',G.Messages.Favorite end
 if G.OnDisplay(p,d.DogUid)then return false,'Display',G.Messages.Display end
 local def=Defs[d.DogId]
 if not(def and def.Available and def.MutationRules and def.MutationRules.Enabled)then return false,'Unavailable',G.Messages.Unavailable end
 return true,nil,nil
end

-- One-tap fix for a blocked dog: the economy action that clears the block (nil = no remote fix).
function G.Fix(code,d)
 if not d then return nil end
 if code=='Locked'then return {Action='DogLock',Args={Uid=d.DogUid,Enabled=false},Text='UNLOCK'}end
 if code=='Favorite'then return {Action='DogFavorite',Args={Uid=d.DogUid,Enabled=false},Text='UNFAVORITE'}end
 if code=='Kennel'then return {Action='Remove',Args={Uid=d.DogUid},Text='REMOVE FROM KENNEL'}end
 if code=='Busy'then return {Action='Remove',Args={Uid=d.DogUid},Text='RETURN TO STORAGE'}end
 return nil
end

-- Artifacts (equipment feature) equipped on a dog. They point at the dog (p.Equipment.Artifacts[uid].DogUid);
-- when the dog leaves the profile the equipment feature returns them to the inventory.
function G.Artifacts(p,uid)
 local out={}
 local equipment=type(p)=='table'and p.Equipment
 local list=type(equipment)=='table'and equipment.Artifacts
 if type(list)~='table'or uid==nil then return out end
 for key,a in pairs(list)do
  if type(a)=='table'and a.DogUid==uid then table.insert(out,{Uid=a.Uid or key,Id=a.Id,Rarity=a.Rarity})end
 end
 table.sort(out,function(a,b)return tostring(a.Uid)<tostring(b.Uid)end)
 return out
end

-- Reasons a dog counts as valuable (losing it needs a held confirmation). Empty = ordinary.
function G.ValueReasons(p,d)
 local reasons={}
 if type(d)~='table'then return reasons end
 local def=Defs[d.DogId]
 local rare=def~=nil and def.Rank>=C.HighValue.MinRank
 if rare then table.insert(reasons,'Rarity')end
 if(d.Variant or'Normal')~='Normal'then table.insert(reasons,'Variant')end
 if(tonumber(d.AscensionLevel)or 0)>0 then table.insert(reasons,'Ascension')end
 if(tonumber(d.Mastery)or 0)>=C.HighValue.Mastery then table.insert(reasons,'Mastery')end
 if(def and def.SupplyType=='Limited')or d.Edition=='First Edition'or d.OG==true or(not rare and(tonumber(d.SerialNumber)or 0)>0)then table.insert(reasons,'Collectible')end
 if d.LabRecipe~=nil or d.Origin=='LAB_FUSION'or d.Origin=='LAB_EXPERIMENT'then table.insert(reasons,'LabMade')end
 if #G.Artifacts(p,d.DogUid)>0 then table.insert(reasons,'Artifacts')end
 return reasons
end
function G.HighValue(p,d)return #G.ValueReasons(p,d)>0 end

-- Coins / Bones / DNA of a procedure on dog d (Ascend: the main dog).
function G.Cost(procedure,d)
 local rank=G.Rank(d)
 if procedure=='Mutation'or procedure=='Targeting'then
  local c=C.Costs[procedure]
  return {Cash=c.Cash+c.RankCash*rank,Bones=c.RankBones*rank,DNA=copy(c.DNA)}
 elseif procedure=='Extraction'then
  local c=C.Costs.Extraction
  return {Cash=c.Cash+c.RankCash*rank,Bones=0,DNA={}}
 elseif procedure=='Ascend'then
  local step=(tonumber(type(d)=='table'and d.AscensionLevel)or 0)+1
  return {Cash=C.Costs.Ascend.Cash*step,Bones=C.Costs.Ascend.Bones*step,DNA={}}
 end
 return {Cash=0,Bones=0,DNA={}}
end

function G.Stability(procedure,d,stabilizer)
 local s=C.Stability
 return math.clamp((s[procedure]or s.Mutation)+(tonumber(d.Mastery)or 0)*s.MasteryPer+(tonumber(d.AscensionLevel)or 0)*s.AscensionPer+(stabilizer or 0),s.Minimum,s.Maximum)
end

function G.StrangeChance(stability)
 return(100-stability)/100*C.Stability.StrangeRate*100
end

-- Reroll odds. rows = Rules.VariantRows(p) (Config.Variants with world events and the player's DogMutation
-- bonus); target = LabConfig.Affinities[catalyst] or nil; stabilizer = stability bonus of the crystal (0 = none).
-- Returns {{Name, Percent}} in row order.
function G.Chances(rows,target,stability,stabilizer)
 local weights,total={},0
 local w=C.TargetWeights
 stabilizer=stabilizer or 0
 for _,v in ipairs(rows or Base.Variants)do
  local weight=math.max(0,tonumber(v.Weight)or 0)
  if target and v.Name==target.Mutation then weight+=(w.Base+stability*w.PerStability+(stabilizer>0 and w.StabilizerBonus or 0))*target.Power end
  if stabilizer>0 and v.Name~=(target and target.Mutation)and(v.Name=='Void'or v.Name=='Glitched')then weight*=.55 end
  table.insert(weights,{Name=v.Name,Weight=weight});total+=weight
 end
 local out={}
 for _,v in ipairs(weights)do table.insert(out,{Name=v.Name,Percent=total>0 and v.Weight/total*100 or 0})end
 return out
end

-- DNA a dog yields when it is extracted.
function G.Extraction(d)
 local rank=G.Rank(d);local x=C.Extraction
 local bonus=math.floor((tonumber(d.Mastery)or 0)/x.MasteryStep)+(tonumber(d.AscensionLevel)or 0)*x.AscensionBonus
 local rewards={CommonDNA=x.CommonByRank[rank]+bonus}
 local rare=x.RareByRank[rank];if rare>0 then rewards.RareDNA=rare end
 local shards=x.VariantShards[d.Variant or'Normal']or 0;if shards>0 then rewards.MutationShards=shards end
 for _,tag in ipairs(G.Tags(d))do rewards[tag]=x.SamplesByRank[rank]+math.min(bonus,4)end
 if rank>=x.CoreMinimumRank then rewards.CoreFragment=1 end
 return rewards
end

-- Success chance of a recipe at a stability.
function G.Success(stability)return math.min(98,60+stability*.4)end

-- Keys sorted for display: the main resources first, then samples alphabetically.
local DNA_ORDER={CommonDNA=1,RareDNA=2,MutationShards=3,StrangeDNA=4,CoreFragment=5}
function G.SortedKeys(map)
 local keys={}
 for k in pairs(map or{})do table.insert(keys,k)end
 table.sort(keys,function(a,b)
  local x,y=DNA_ORDER[a]or 10,DNA_ORDER[b]or 10
  if x~=y then return x<y end
  return tostring(a)<tostring(b)
 end)
 return keys
end

-- Known recipes (LabRules.Catalog rows) that need a DNA key.
function G.RecipeUses(recipes,key)
 local names={}
 for _,row in ipairs(recipes or{})do
  if row.Known and type(row.RequiredDNA)=='table'and(row.RequiredDNA[key]or 0)>0 then table.insert(names,row.Name)end
 end
 return names
end

-- Lower = cheaper to give up (auto-picks consume the least valuable dogs first).
local VARIANT_RANK={}
for i,v in ipairs(Base.Variants)do VARIANT_RANK[v.Name]=i end
function G.ValueScore(p,d)
 local score=(tonumber(d.AscensionLevel)or 0)*1e7+(VARIANT_RANK[d.Variant or'Normal']or 1)*1e5+(tonumber(d.Mastery)or 0)*100
 if #G.Artifacts(p,d.DogUid)>0 then score+=5e6 end
 if d.LabRecipe~=nil then score+=1e6 end
 return score
end
local function byValue(p,prefer)
 return function(a,b)
  if prefer then
   if a.DogUid==prefer and b.DogUid~=prefer then return true end
   if b.DogUid==prefer and a.DogUid~=prefer then return false end
  end
  local x,y=G.ValueScore(p,a),G.ValueScore(p,b)
  if x~=y then return x<y end
  return a.DogUid<b.DogUid
 end
end

-- Ascension: usable duplicates of the main dog (same DogId, Ascension >= main's), cheapest first, and how
-- many more copies exist but are blocked (locked, working...).
function G.Duplicates(p,main)
 local usable,blocked={},0
 local level=tonumber(main.AscensionLevel)or 0
 for uid,d in pairs(type(p.Dogs)=='table'and p.Dogs or{})do
  if uid~=main.DogUid and type(d)=='table'and d.DogId==main.DogId and(tonumber(d.AscensionLevel)or 0)>=level then
   if G.Check(p,d)then table.insert(usable,d)else blocked+=1 end
  end
 end
 table.sort(usable,byValue(p,nil))
 return usable,blocked
end

-- Affinity catalysts / stabilizer crystals the player can spend, grouped by item: {ItemId, Name, Uids, ...}.
local function grouped(p,accept)
 local groups,by={},{}
 for uid,x in pairs(type(p.Items)=='table'and p.Items or{})do
  if type(x)=='table'and not x.Favorite and x.Tradeable~=false and accept(x.ItemId)then
   local g=by[x.ItemId]
   if not g then g={ItemId=x.ItemId,Name=x.DisplayName or x.ItemId,Uids={},Items={}};by[x.ItemId]=g;table.insert(groups,g)end
   table.insert(g.Items,x)
  end
 end
 for _,g in ipairs(groups)do
  table.sort(g.Items,function(a,b)
   local x,y=tonumber(a.SellValue)or 0,tonumber(b.SellValue)or 0
   if x~=y then return x<y end
   return tostring(a.ItemUid)<tostring(b.ItemUid)
  end)
  for _,x in ipairs(g.Items)do table.insert(g.Uids,x.ItemUid)end
  g.Items=nil
 end
 table.sort(groups,function(a,b)return a.Name<b.Name end)
 return groups
end
function G.Catalysts(p)
 local groups=grouped(p,function(id)return C.Affinities[id]~=nil end)
 for _,g in ipairs(groups)do g.Affinity=C.Affinities[g.ItemId]end
 return groups
end
function G.Stabilizers(p)
 local groups=grouped(p,function(id)return C.Stabilizers[id]~=nil end)
 for _,g in ipairs(groups)do g.Bonus=C.Stabilizers[g.ItemId]end
 return groups
end

-- Auto-fill of a known recipe (a LabRules.Catalog row): eligible dogs that satisfy it (cheapest first,
-- `prefer` first when it fits), the catalysts, and what is missing.
-- Returns {Uids, Items, Missing = {{Kind='Dog'|'Tag'|'Item'|'DNA', ...}}}.
function G.FillRecipe(p,recipe,prefer)
 local result={Uids={},Items={},Missing={}}
 local used={}
 local function fits(d)
  if(tonumber(d.Mastery)or 0)<(recipe.MinimumMastery or 0)then return false end
  if(tonumber(d.AscensionLevel)or 0)<(recipe.MinimumAscension or 0)then return false end
  if recipe.RequiredMutation and d.Variant~=recipe.RequiredMutation then return false end
  return G.Check(p,d)
 end
 local function candidates(accept)
  local list={}
  for uid,d in pairs(type(p.Dogs)=='table'and p.Dogs or{})do
   if not used[uid]and type(d)=='table'and accept(d)and fits(d)then table.insert(list,d)end
  end
  table.sort(list,byValue(p,prefer))
  return list
 end
 if type(recipe.RequiredDogIds)=='table'then
  for _,id in ipairs(recipe.RequiredDogIds)do
   local pick=candidates(function(d)return d.DogId==id end)[1]
   if pick then used[pick.DogUid]=true;table.insert(result.Uids,pick.DogUid)
   else table.insert(result.Missing,{Kind='Dog',DogId=id,MinimumMastery=recipe.MinimumMastery,MinimumAscension=recipe.MinimumAscension})end
  end
 elseif type(recipe.RequiredGeneticTags)=='table'then
  local tags=recipe.RequiredGeneticTags
  local options={}
  for i,tag in ipairs(tags)do
   options[i]=candidates(function(d)return table.find(G.Tags(d),tag)~=nil end)
  end
  local chosen={}
  local function solve(i)
   if i>#tags then return true end
   for _,d in ipairs(options[i])do
    if not used[d.DogUid]then
     used[d.DogUid]=true;chosen[i]=d
     if solve(i+1)then return true end
     used[d.DogUid]=nil;chosen[i]=nil
    end
   end
   return false
  end
  if solve(1)then
   for i=1,#tags do table.insert(result.Uids,chosen[i].DogUid)end
  else
   for i,tag in ipairs(tags)do if #options[i]==0 then table.insert(result.Missing,{Kind='Tag',Tag=tag})end end
   if #result.Missing==0 then table.insert(result.Missing,{Kind='Tag',Tag=tags[#tags]})end
   result.Uids={}
  end
 end
 local catalysts=grouped(p,function(id)return type(recipe.RequiredItems)=='table'and recipe.RequiredItems[id]~=nil end)
 local have={}
 for _,g in ipairs(catalysts)do have[g.ItemId]=g end
 for itemId,need in pairs(type(recipe.RequiredItems)=='table'and recipe.RequiredItems or{})do
  local g=have[itemId];local n=g and #g.Uids or 0
  if n>=need then for i=1,need do table.insert(result.Items,g.Uids[i])end
  else table.insert(result.Missing,{Kind='Item',ItemId=itemId,Need=need,Have=n})end
 end
 local dna=type(p.Lab)=='table'and type(p.Lab.DNA)=='table'and p.Lab.DNA or{}
 for key,need in pairs(type(recipe.RequiredDNA)=='table'and recipe.RequiredDNA or{})do
  local n=tonumber(dna[key])or 0
  if n<need then table.insert(result.Missing,{Kind='DNA',Key=key,Need=need,Have=n})end
 end
 table.sort(result.Items)
 return result
end

-- Where an unowned species can be found (keys; LabScreen words them).
function G.Sources(id)
 local def=Defs[id]
 if not def then return {}end
 local out={}
 if def.CanSpawnOnLine then table.insert(out,'DogLine')end
 if def.CanDropFromLuckyBlock then table.insert(out,'LuckyBlock')end
 if def.CanDropFromRoulette then table.insert(out,'DogOMatic')end
 if def.Acquisition=='Excavation'then table.insert(out,'Excavation')end
 if def.Acquisition=='ServerArrival'then table.insert(out,'ServerArrival')end
 return out
end

-- The one variant colour source of the lab (UI kit Theme.Variant mirrors it; tests/uikit.luau checks).
function G.VariantColor(name)return C.Colors[name or'Normal']or C.Colors.Normal end

return G
