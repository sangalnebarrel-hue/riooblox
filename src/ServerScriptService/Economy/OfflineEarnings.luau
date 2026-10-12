-- Pure profile accounting, called inside the existing durable transactions.
local C=require(game:GetService('ReplicatedStorage').OfflineEarningsConfig)
local Economy=require(script.Parent.Config)
local R=require(script.Parent.Rules)
local Definitions=require(script.Parent.DogDefinitions)
local Signatures=require(script.Parent.SignatureRules)
local Pricing=require(game:GetService('ReplicatedStorage').DogEconomy.BoostPricing)
local Bonuses=require(game:GetService('ReplicatedStorage').DogEconomy.Bonuses)
local O={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function bounded(n,limit)return finite(n)and math.clamp(math.floor(n),0,limit)or 0 end
function O.Normalize(p)
 local o=p.OfflineEarnings
 if type(o)~='table'then o={} end
 o.Version=C.Version;o.PendingCoins=bounded(o.PendingCoins,C.MaxPendingCoins);o.PendingSeconds=bounded(o.PendingSeconds,C.MaxAwaySeconds)
 o.Revision=bounded(o.Revision,9007199254740000);o.CheckpointAt=bounded(o.CheckpointAt,9007199254740000)
 o.Rate=finite(o.Rate)and math.clamp(o.Rate,0,C.MaxPendingCoins)or 0
 o.BaseRate=finite(o.BaseRate)and math.clamp(o.BaseRate,0,C.MaxPendingCoins)or 0
 o.Dogs=type(o.Dogs)=='table'and o.Dogs or{};o.Contributors=type(o.Contributors)=='table'and o.Contributors or{}
 p.OfflineEarnings=o;return o
end
-- The team's steady income in coins per second (BaseRate; it also prices boosts and Robux coin
-- packs, BoostPricing) and the offline rate (BaseRate x Efficiency x (1+Offline bonus)).
-- The same model as the HUD income (Rules.IncomeModel), on a quiet copy of the profile:
-- 41 is a quiet phase for every periodic aura, and sale/pulse/map timestamps, supplies, bought luck
-- and world events are cleared instead of freezing a temporary bonus. Discoveries count at their
-- expected sale value even when storage is full (Potential).
function O.Estimate(p)
 local clean={}
 for k,v in pairs(p)do clean[k]=v end
 clean.Dogs={};clean.Upgrades=p.Upgrades or{};clean.Supplies={};clean.LuckBoosts={};clean.Loot={};clean.Items={};clean.ItemReservations={}
 clean.LastDig=41;clean.LastSaleAt=-100000;clean.TimePulseUntil=0;clean.TreasureMapUntil=0;clean.Pity=0
 for uid,dog in pairs(p.Dogs or{})do
  if Definitions[dog.DogId]and Signatures.Active(dog)then clean.Dogs[uid]=dog end
 end
 if not Economy.Layers[p.CurrentLayer or 1]then return 0,{},0 end
 local model=R.IncomeModel(clean,41,{AssignedOnly=true,Potential=true})
 local efficiency=C.Efficiency*math.max(0,1+Bonuses.Global(clean,41).Offline)
 local rows,baseTotal={},0
 for uid,stats in pairs(model.Dogs)do
  local def=Definitions[clean.Dogs[uid].DogId]
  local base=stats.CoinsPerMin/60
  baseTotal+=base
  table.insert(rows,{Uid=uid,DogId=def.Id,Name=def.DisplayName,BaseRate=base,Rate=base*efficiency})
 end
 table.sort(rows,function(a,b)return a.Uid<b.Uid end)
 return baseTotal*efficiency,rows,baseTotal
end
function O.Checkpoint(p,now)
 local o=O.Normalize(p)
 o.Rate,o.Dogs,o.BaseRate=O.Estimate(p);o.CheckpointAt=now
 -- Boost prices follow the recent peak of this rate (BoostPricing).
 Pricing.Track(p,now)
 return o
end
local function addContributors(o,seconds,coins)
 local allocations,total,left={},0,coins
 for _,dog in ipairs(o.Dogs)do total+=dog.Rate or 0 end
 if total<=0 then return end
 for _,dog in ipairs(o.Dogs)do
  local exact=coins*(dog.Rate or 0)/total;local amount=math.floor(exact);left-=amount
  table.insert(allocations,{Dog=dog,Coins=amount,Fraction=exact-amount})
 end
 table.sort(allocations,function(a,b)if a.Fraction~=b.Fraction then return a.Fraction>b.Fraction end;return a.Dog.Uid<b.Dog.Uid end)
 for i=1,left do allocations[(i-1)%#allocations+1].Coins+=1 end
 for _,row in ipairs(allocations)do
  local dog=row.Dog;local prior=o.Contributors[dog.Uid]or{Uid=dog.Uid,DogId=dog.DogId,Name=dog.Name,Coins=0,Seconds=0}
  prior.Coins+=row.Coins;prior.Seconds+=seconds;o.Contributors[dog.Uid]=prior
 end
end
function O.Join(p,now,sessionId)
 local o=O.Normalize(p);local from=o.CheckpointAt;local prior=p.Session
 -- Same-server Join replays are online time, never another offline reward.
 if prior and prior.Id==sessionId then from=now
 elseif prior then from=math.max(from,prior.Expires or now)end
 local away=from>0 and math.max(0,now-from)or 0
 local seconds,coins=0,0
 if C.Enabled and o.CheckpointAt>0 and away>=C.MinAwaySeconds and o.Rate>0 then
  seconds=math.min(away,math.max(0,C.MaxAwaySeconds-o.PendingSeconds))
  coins=math.min(math.floor(seconds*o.Rate),math.max(0,C.MaxPendingCoins-o.PendingCoins))
  if seconds>0 then o.PendingSeconds+=seconds end
  if coins>0 then addContributors(o,seconds,coins);o.PendingCoins+=coins;o.Revision+=1 end
 end
 o.LastAwaySeconds=away;o.LastCreditedSeconds=seconds;o.LastAddedCoins=coins;o.LastReturnAt=now
 o.WasCapped=away>=C.MinAwaySeconds and o.Rate>0 and(seconds<away or o.PendingCoins>=C.MaxPendingCoins)
 return O.Checkpoint(p,now)
end
function O.Id(p,o)return 'offline:'..p.UserId..':'..o.Revision end
function O.Report(p)
 local o=O.Normalize(p);local dogs={}
 for _,dog in pairs(o.Contributors)do table.insert(dogs,R.Copy(dog))end
 table.sort(dogs,function(a,b)if a.Coins~=b.Coins then return a.Coins>b.Coins end;return a.Uid<b.Uid end)
 return {PendingCoins=o.PendingCoins,PendingId=O.Id(p,o),CanClaim=o.PendingCoins>0,PendingSeconds=o.PendingSeconds,
  AwaySeconds=o.LastAwaySeconds or 0,CreditedSeconds=o.LastCreditedSeconds or 0,AddedCoins=o.LastAddedCoins or 0,WasCapped=o.WasCapped==true,
  BaseRate=o.BaseRate,Rate=o.Rate,Efficiency=o.BaseRate>0 and o.Rate/o.BaseRate or C.Efficiency,CapSeconds=C.MaxAwaySeconds,MinAwaySeconds=C.MinAwaySeconds,
  Eligible=#o.Dogs>0,Dogs=dogs,CurrentDogs=R.Copy(o.Dogs),Description=C.Description}
end
function O.Claim(p,pendingId,now)
 local o=O.Normalize(p)
 R.Check(type(pendingId)=='string'and pendingId==O.Id(p,o),'Offline earnings changed; review the new amount')
 R.Check(o.PendingCoins>0,'No offline coins to claim')
 local coins=o.PendingCoins
 -- R.Credit validates wallet capacity before anything pending is cleared.
 R.Credit(p,coins);o.PendingCoins=0;o.PendingSeconds=0;o.Contributors={};o.LastClaimAt=now;o.Revision+=1
 return {Message='Claimed '..coins..' offline Coins',Coins=coins,ClaimedPendingId=pendingId}
end
return O
