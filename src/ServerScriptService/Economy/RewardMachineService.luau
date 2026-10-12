-- DOG-O-MATIC server core: the per-player odds pool, the info snapshot, the pure transaction
-- body (Resolve) and the activation request.
-- A machine prize never blocks the machine: Coins/Bones are clamped to the wallet, Energy Snack
-- time overflows into SupplyReserve (the Robux supply rule) and past the paid cap it becomes
-- coins, dogs and items may exceed the SOFT storage capacity. Only the hard caps that
-- R.Validate/I.Validate enforce (C.MaxDogs dogs, 1,000 items) stop a spin, and they are checked
-- for every row of the pool at once, so filling storage can never reroll a prize.
local RS=game:GetService('ReplicatedStorage');local Http=game:GetService('HttpService')
local C=require(RS.RewardMachineConfig);local E=require(RS.DogEconomy.Config)
local Odds=require(RS.RewardMachineOdds);local Modifiers=require(RS.WorldEvents.WorldEventModifiers)
local R=require(script.Parent.Rules);local I=require(script.Parent.ItemRules);local D=require(script.Parent.DogDefinitions)
local Tickets=require(script.Parent.RouletteTickets)
local Purchases=require(script.Parent.RoulettePurchases)
local Supply=require(script.Parent.SupplyRules)
local Pricing=require(RS.DogEconomy.BoostPricing);local Format=require(RS.PriceFormat)
local S={ItemHardCap=1000,ReceiptRing=16,FlushInterval=30};local rng=Random.new()
local lastFlush={}
local function count(t)local n=0;for _ in pairs(type(t)=='table'and t or{})do n+=1 end;return n end
local function dogCount(p)return count(p.Dogs)+count(p.Reservations)end
local function itemCount(p)return count(p.Items)+count(p.ItemReservations)end
-- R.Mint/I.Mint check the SOFT capacity (R.Free/I.Free: the dog line, shops and trades).
-- A machine prize is already paid for, so for this one profile, only during this one
-- non-yielding mint, the check is widened to the hard caps R.Validate/I.Validate enforce.
local baseDogFree,baseItemFree=R.Free,I.Free
local function beyondSoftCap(p,fn)
 local dogFree,itemFree=R.Free,I.Free
 R.Free=function(q)if q==p then return dogCount(q)<E.MaxDogs end;return baseDogFree(q)end
 I.Free=function(q)if q==p then return itemCount(q)<S.ItemHardCap end;return baseItemFree(q)end
 local ok,result=pcall(fn)
 R.Free,I.Free=dogFree,itemFree
 if not ok then error(result,0)end
 return result
end
-- Aurion's boost while an ACTIVE world event carries the MachineAurion perk (Rainbow Rift).
-- WorldEventService sets WorldEventModifiers; it is cleared when the event ends.
function S.EventBoost(now)
 local def=Modifiers.Active(now or os.time())
 local mult=def and type(def.Perks)=='table'and tonumber(def.Perks.MachineAurion)
 if not mult or mult~=mult or mult<=1 then return nil end
 return {EventId=def.Id,Name=def.DisplayName,Multiplier=math.min(mult,C.EventBoostCap or 10),EndsAt=Modifiers.EndsAt}
end
-- All released dogs a tier row may award, grouped by rank (the RewardService.Pool grouping:
-- each rarity owns one budget, split evenly between its members).
function S.TierMembers(row,p,runtime,now)
 local wanted={};for _,rank in ipairs(row.Ranks or{})do wanted[rank]=true end
 local groups={}
 for id,def in pairs(D)do
  if wanted[def.Rank]and def.CanDropFromRoulette==true and id~='Aurion'and not def.Jackpot and not def.OG
   and R.Available(def,now,p.CurrentLayer)and runtime.Engine.AssetReady(id)then
   groups[def.Rank]=groups[def.Rank]or{};table.insert(groups[def.Rank],id)
  end
 end
 for _,list in pairs(groups)do table.sort(list)end
 return groups
end
function S.Pool(p,runtime,now,boost)
 local rows,requiredReason={},nil;now=now or os.time()
 local source=boost and Odds.Boost(C.Rewards,boost.Multiplier,C.EventBoostCap)or C.Rewards
 for prizeIndex,row in ipairs(source)do
  local enabled=true;local breakdown
  if row.Kind=='Dog'then
   local d=D[row.Id]
   enabled=d and d.SupplyType=='Permanent'and not d.OG and d.CanDropFromRoulette~=false and R.Available(d,now,p.CurrentLayer)and runtime.Engine.AssetReady(row.Id)
  elseif row.Kind=='DogTier'then
   local groups=S.TierMembers(row,p,runtime,now);breakdown={}
   for _,rank in ipairs(row.Ranks or{})do
    local list=groups[rank]
    if list and #list>0 then table.insert(breakdown,{Rank=rank,Rarity=E.Rarities[rank],Weight=(row.RankWeights and row.RankWeights[rank])or 1,Members=list})end
   end
   enabled=#breakdown>0
  elseif row.Kind=='Item'then
   local d=I.Definitions[row.Id];enabled=d and d.Depth<=p.CurrentLayer and d.Class~='Secret'and d.CanDropFromRoulette~=false
  elseif row.Kind=='Boost'then
   enabled=E.Supplies[row.Id]~=nil
  end
  -- A configured fixed ultra rare reward is never silently removed or renormalized.
  -- Keep its honest advertised chance, but stop the spin before spending if
  -- its imported asset is unavailable on this server.
  if not enabled and row.Required then requiredReason='Aurion is preparing to arrive. Please try again shortly.'end
  if (enabled or row.Required)and(row.Weight>0 or(row.FixedUnits or 0)>0)then
   local view=R.Copy(row);view.PrizeIndex=prizeIndex;view.RankWeights=nil -- sparse keys do not cross remotes; Breakdown carries them
   -- A coin bag holds minutes of this player's income: the same amount is shown and paid.
   if row.Kind=='Cash'and row.Coins then
    view.Amount=Pricing.Coins(row.Coins,p,now);view.Name=Format.Number(view.Amount)..' Coins'
   end
   if row.Kind=='Dog'and D[row.Id]then view.Rarity=D[row.Id].Rarity;view.Rank=D[row.Id].Rank
   elseif row.Kind=='DogTier'then
    view.Breakdown=breakdown;view.Rank=breakdown[1]and breakdown[1].Rank;view.Rarity=breakdown[1]and breakdown[1].Rarity
    local members=0;for _,part in ipairs(breakdown)do members+=#part.Members end;view.MemberCount=members
   elseif row.Kind=='Item'then view.Rarity=I.Definitions[row.Id].Class end
   if view.Multiplier and boost then view.EventBoost=boost.EventId end
   table.insert(rows,view)
  end
 end
 if #rows==0 then return {},0,'Rewards are temporarily unavailable'end
 local pool,total=Odds.Build(rows,C.OddsDenominator)
 for _,row in ipairs(pool)do
  if row.Breakdown then
   Odds.Split(row.Breakdown,row.ChanceUnits)
   for _,part in ipairs(row.Breakdown)do
    part.Chance=part.ChanceUnits/C.OddsDenominator;part.ChanceText=string.format('%.2f%%',part.Chance*100)
    part.EachChance=part.Chance/#part.Members
   end
   row.Featured=require(RS.RewardMachineText).Featured(row,nil,now)
  end
 end
 return pool,total,requiredReason
end
-- A tier win: the rarity by its integer share, then one member uniformly.
function S.PickMember(row,random)
 local units=row.ChanceUnits or 0
 if units<=0 or type(row.Breakdown)~='table'then return nil end
 local slot=random:NextInteger(1,units);local ceiling=0
 for _,part in ipairs(row.Breakdown)do
  ceiling+=part.ChanceUnits or 0
  if slot<=ceiling and #part.Members>0 then return part.Members[random:NextInteger(1,#part.Members)]end
 end
 return nil
end
function S.IsMember(row,dogId)
 for _,part in ipairs(type(row.Breakdown)=='table'and row.Breakdown or{})do
  if table.find(part.Members,dogId)then return true end
 end
 return false
end
-- Only the hard caps, and for every prize row together (no reroll by filling storage).
function S.HardCapReason(p,pool)
 for _,row in ipairs(pool)do
  if(row.Kind=='Dog'or row.Kind=='DogTier')and dogCount(p)>=E.MaxDogs then
   return string.format('You own the maximum of %d dogs. Sell or release a dog to spin.',E.MaxDogs),'DogsHardCap'
  elseif row.Kind=='Item'and itemCount(p)>=S.ItemHardCap then
   return string.format('Your bag holds the maximum of %d items. Sell an item to spin.',S.ItemHardCap),'ItemsHardCap'
  end
 end
end
function S.Info(p,runtime,now,paidAllowed,boost)
 now=now or os.time();local pool,total,requiredReason=S.Pool(p,runtime,now,boost)
 local free,deadline=Tickets.State(p,now);local paid=tonumber(p.PaidRouletteTickets)or 0;local tokens=C.FreeOnly and free or free+paid
 local reason,code
 if requiredReason then reason,code=requiredReason,'AurionPreparing'
 elseif total<=0 then reason,code='Rewards are temporarily unavailable','Unavailable'
 else reason,code=S.HardCapReason(p,pool)end
 if not reason and tokens<C.TicketCost then reason,code='Your free DOG TOKEN is still recharging','Recharging'end
 if not reason and not C.FreeOnly and free<C.TicketCost and paidAllowed~=true then reason,code='Paid random tickets are unavailable for this account; your tickets are kept','PaidRestricted'end
 if not reason and now<(p.NextRouletteAt or 0)then reason,code='Please wait for this activation to finish','Cooldown'end
 local active
 if boost then
  for _,row in ipairs(pool)do if row.Id=='Aurion'and row.Multiplier then
   active={EventId=boost.EventId,Name=boost.Name,Multiplier=row.Multiplier,EndsAt=boost.EndsAt,ChanceUnits=row.ChanceUnits,ChanceText=row.ChanceText,BaseUnits=row.BaseUnits}
  end end
 end
 return {Cost=0,TicketCost=C.TicketCost,Tickets=tokens,FreeTickets=free,PaidTickets=paid,MaxFreeTickets=C.TicketCapacity,MaxTickets=C.TicketCapacity,
  NextTicketAt=deadline,NextFreeTicketAt=deadline,SpendOrder=C.FreeOnly and 'FreeOnly'or'FreeFirst',FreeOnly=C.FreeOnly==true,PaidRandomAllowed=paidAllowed==true,
  PaidRandomRestrictionReason=paidAllowed~=true and 'Paid tickets are unavailable for this account. Free tickets still work.'or nil,
  TicketRefillSeconds=C.TicketRefillSeconds,ServerNow=now,NextSpinAt=p.NextRouletteAt or 0,
  Rewards=pool,OddsDenominator=C.OddsDenominator,CanSpin=reason==nil,UnavailableReason=reason,ReasonCode=code,ActiveBoost=active,
  DogCount=count(p.Dogs),DogCapacity=R.Capacity(p),ItemCount=count(p.Items),ItemCapacity=I.Capacity(p),
  TicketDescription=C.FreeOnly and 'One free DOG TOKEN every 5 hours after use. Holds one. DOG TOKENS cannot be purchased.'
   or 'One free DOG TOKEN every 5 hours after use (holds one). Extra tokens: Lucky Spin packs in the PAW MARKET. Free tokens are always used first.'}
end
-- Durable idempotency: the last ReceiptRing activations live in the profile itself, so a
-- retried request id is answered from the save even after the RAM receipt cache forgot it.
function S.FindReceipt(p,key)
 local ring=p.RouletteReceipts
 if type(ring)~='table'then return nil end
 for _,row in ipairs(ring)do
  if type(row)=='table'and row.Receipt==key then
   for _,old in ipairs(type(p.RewardHistory)=='table'and p.RewardHistory or{})do
    if type(old)=='table'and old.Receipt==key then local copy=R.Copy(old);copy.Duplicate=true;return copy end
   end
   local copy=R.Copy(row);copy.Duplicate=true
   copy.FreeTickets=p.RouletteTickets;copy.PaidTickets=p.PaidRouletteTickets;copy.NextSpinAt=p.NextRouletteAt
   copy.NextTicketAt=p.NextRouletteTicketAt;copy.NextFreeTicketAt=p.NextRouletteTicketAt
   return copy
  end
 end
 return nil
end
function S.RememberReceipt(p,result)
 local ring=type(p.RouletteReceipts)=='table'and p.RouletteReceipts or{}
 table.insert(ring,1,{Receipt=result.Receipt,At=result.At,Kind=result.Kind,Id=result.Id,Name=result.Name,PrizeIndex=result.PrizeIndex,
  Rarity=result.Rarity,ChanceUnits=result.ChanceUnits,TicketType=result.TicketType,Jackpot=result.Jackpot})
 while #ring>S.ReceiptRing do table.remove(ring)end
 p.RouletteReceipts=ring
end
local function credit(p,amount)
 amount=math.max(0,math.min(math.floor(tonumber(amount)or 0),E.MaxCash-p.Cash))
 if amount>0 then R.Credit(p,amount)end
 return amount
end
-- Server-only pure transaction body. It can be tested against the existing
-- transaction journal without bypassing the remote/world authorization gates.
-- `forced` is the row (and dog) pre-picked from the same seed by Request; `boost` is the event
-- boost frozen when the activation started, so an event ending mid-request cannot change odds.
function S.Resolve(v,userId,key,uid,now,runtime,paidAllowed,random,forced,boost)
 local p=v['p:'..userId];runtime.Engine:Authorize(p,userId)
 local delivered=S.FindReceipt(p,key);if delivered then return delivered end
 R.Normalize(p,userId,now)
 local info=S.Info(p,runtime,now,paidAllowed,boost);R.Check(info.CanSpin,info.UnavailableReason)
 local pool=info.Rewards;local roll=function()return random:NextNumber()end
 local chosen,dogId
 if type(forced)=='table'then
  for _,row in ipairs(pool)do
   if row.PrizeIndex==forced.PrizeIndex and row.Kind==forced.Kind and row.Id==forced.Id and row.Name==forced.Name and row.ChanceUnits==forced.ChanceUnits then chosen=row;break end
  end
  R.Check(chosen,'Reward pool changed; please activate again')
  if chosen.Kind=='DogTier'then R.Check(type(forced.DogId)=='string'and S.IsMember(chosen,forced.DogId),'Reward pool changed; please activate again');dogId=forced.DogId end
 else
  -- Exactly one uniformly sampled integer maps to each of the 10,000 slots.
  chosen=Odds.Pick(pool,random:NextInteger(1,C.OddsDenominator),C.OddsDenominator)
  if chosen.Kind=='DogTier'then dogId=S.PickMember(chosen,random);R.Check(dogId,'Rewards are temporarily unavailable')end
 end
 local _,_,ticketType=Tickets.Consume(p,now,paidAllowed)
 local result={Kind=chosen.Kind=='DogTier'and'Dog'or chosen.Kind,Id=dogId or chosen.Id,Name=chosen.Name,Receipt=key,At=now,Chance=chosen.Chance,ChanceUnits=chosen.ChanceUnits,ChanceText=chosen.ChanceText,Jackpot=chosen.Jackpot==true,Rarity=chosen.Rarity,PrizeIndex=chosen.PrizeIndex,
  TicketCost=C.TicketCost,TicketType=ticketType,PaidRandom=ticketType=='Paid',Tier=chosen.Tier,TierName=chosen.Kind=='DogTier'and chosen.Name or nil,
  EventBoost=chosen.EventBoost,Multiplier=chosen.Multiplier}
 if chosen.Kind=='Dog'or chosen.Kind=='DogTier'then
  local id=dogId or chosen.Id
  local supply=v['supply:'..id]or {};v['supply:'..id]=supply
  local dog=beyondSoftCap(p,function()return R.Mint(p,id,uid,supply,now,roll,'Roulette')end)
  dog.PricePaid=0;dog.PaidRandom=ticketType=='Paid';result.Dog=R.Copy(dog)
  result.Name=dog.DisplayName;result.Rarity=dog.Rarity;result.Rank=D[id]and D[id].Rank
  local capacity=R.Capacity(p);local owned=count(p.Dogs)
  if owned>capacity then result.Storage={Kind='Dogs',Count=owned,Capacity=capacity}end
 elseif chosen.Kind=='Item'then
  local item=beyondSoftCap(p,function()return I.Mint(p,I.Definitions[chosen.Id],chosen.Chance,uid,now,roll,{})end)
  item.Origin='Roulette';item.PaidRandom=ticketType=='Paid';result.Item=R.Copy(item)
  local capacity=I.Capacity(p);local owned=count(p.Items)
  if owned>capacity then result.Storage={Kind='Items',Count=owned,Capacity=capacity}end
 elseif chosen.Kind=='Cash'then result.Amount=credit(p,chosen.Amount)
 elseif chosen.Kind=='Bones'then
  local amount=math.max(0,math.min(math.floor(chosen.Amount),E.MaxCash-p.Bones));p.Bones+=amount;result.Amount=amount
 elseif chosen.Kind=='Boost'then
  -- Same rule as Robux supply time: past the one-hour active cap it waits in SupplyReserve
  -- (feeding the timer, counting down offline); past the stored paid cap it becomes coins.
  local def=E.Supplies[chosen.Id];Supply.Normalize(p,now)
  local room=math.max(0,now+Supply.PaidCap-math.max(now,Supply.EndAt(p,chosen.Id)))
  local granted=math.min(chosen.Duration,room)
  if granted>0 then Supply.AddPaid(p,chosen.Id,now,granted)end
  result.Boost=chosen.Id;result.Duration=granted;result.Reserved=(p.SupplyReserve[chosen.Id]or 0)>0 and p.SupplyReserve[chosen.Id]or nil
  local extra=chosen.Duration-granted
  if extra>0 then
   local coins=math.floor((Pricing.Supply(chosen.Id,p,now)or 0)*extra/math.max(1,def.Seconds or 600))
   result.Coins=credit(p,coins)
  end
 end
 p.NextRouletteAt=now+C.Cooldown;p.RewardHistory=type(p.RewardHistory)=='table'and p.RewardHistory or {}
 result.FreeTickets=p.RouletteTickets;result.PaidTickets=p.PaidRouletteTickets;result.Tickets=C.FreeOnly and p.RouletteTickets or p.RouletteTickets+p.PaidRouletteTickets;result.NextSpinAt=p.NextRouletteAt
 result.NextTicketAt=p.NextRouletteTicketAt;result.NextFreeTicketAt=p.NextRouletteTicketAt
 table.insert(p.RewardHistory,1,result);while #p.RewardHistory>12 do table.remove(p.RewardHistory)end
 S.RememberReceipt(p,result)
 R.Validate(p);return result
end
local function serialled(def)
 -- Rank 1/2 permanent dogs have no serial/edition state, so a global supply
 -- counter would only add latency. Epic+ and Aurion keep unique serials.
 return def and(def.Rank>=3 or def.SupplyType~='Permanent'or(def.FirstEditionLimit or 0)>0 or(def.LimitedSupply or 0)>0)
end
-- Durability: the autosave (every 60 s) and BindToClose cover ordinary spins; a big win
-- (Legendary+, Aurion) asks for one early save, at most once per FlushInterval per player.
local function flushBigWin(runtime,userId,result)
 if not(result.Jackpot or(result.Rank or 0)>=4)then return end
 local at=os.clock();if at-(lastFlush[userId]or -math.huge)<S.FlushInterval then return end
 lastFlush[userId]=at
 task.defer(function()
  local ok,saved,err=pcall(function()return runtime.Tx:FlushProfile(userId)end)
  if not ok or saved==false then warn('DOG-O-MATIC early save deferred to autosave:',ok and err or saved)end
 end)
end
function S.Forget(userId)lastFlush[userId]=nil end
function S.Request(player,action,a,worldAuthorized)
 action=({RouletteInfo='RewardMachineInfo',RouletteSpin='RewardMachineActivate',RouletteProduct='RewardMachineProduct'})[action]or action
 local runtime=require(script.Parent.Runtime)
 if not runtime.Ready(player)or not runtime.Allow(player,1)then return false,'Please wait'end
 if action=='RewardMachineProduct'then
  if type(a)~='table'then return false,'Choose a ticket pack'end
  return true,Purchases.Product(player,a.Key)
 end
 if action=='RewardMachineInfo'then
  local products,allowed=Purchases.Catalog(player)
  local now=os.time();local profile=runtime.Engine:Get(player.UserId)
  -- Same view as an activation: normalize this read-only copy first (supply reserve, tokens).
  local ok,normalized=pcall(R.Normalize,profile,player.UserId,now)
  if ok and type(normalized)=='table'then profile=normalized else Supply.Normalize(profile,now)end
  local info=S.Info(profile,runtime,now,allowed,S.EventBoost(now));info.TicketProducts=products
  if S.WorldEligibility then
   local eligible,reason=S.WorldEligibility(player);info.InRange=eligible==true
   if not info.InRange then info.CanSpin=false;info.UnavailableReason=reason or 'Move closer to DOG-O-MATIC';info.ReasonCode='TooFar'end
  end
  return true,info
 end
 if action~='RewardMachineActivate'then return false,'Unknown machine action'end
 if not worldAuthorized then return false,'Use the drum at DOG-O-MATIC PLAZA'end
 if type(a)~='table'or type(a.Request)~='string'or #a.Request~=32 or not a.Request:match('^%x+$')then return false,'Invalid activation'end
 local userId=player.UserId
 local key='rs:'..userId..':'..a.Request:sub(1,26)
 local operation='ra:'..userId..':'..a.Request:sub(1,26)
 local keys={'p:'..userId}
 -- A retried request id returns its original result (RAM receipt, then the profile ring)
 -- without a new roll, even while the 7 s reset or a refusal reason would block a new spin.
 if runtime.Tx.Receipts and runtime.Tx.Receipts[operation]~=nil then
  return runtime.Tx:Run(keys,function()error('Activation already handled',0)end,operation)
 end
 -- Never yield on PolicyService for an activation that cannot spend a paid random ticket.
 local paidAllowed=false;if not C.FreeOnly then paidAllowed=Purchases.Allowed(player)end
 local now=os.time();local profile=runtime.Engine:Get(userId)
 runtime.Engine:Authorize(profile,userId)
 local delivered=S.FindReceipt(profile,key);if delivered then return true,delivered end
 profile=R.Normalize(profile,userId,now)
 local boost=S.EventBoost(now)
 local preview=S.Info(profile,runtime,now,paidAllowed,boost);R.Check(preview.CanSpin,preview.UnavailableReason)
 -- Pre-pick from one seed so the transaction only locks the one supply key that can win.
 local seed=rng:NextInteger(1,2147483646);local picker=Random.new(seed)
 local chosen=Odds.Pick(preview.Rewards,picker:NextInteger(1,C.OddsDenominator),C.OddsDenominator)
 R.Check(chosen,'Rewards are temporarily unavailable')
 local dogId=chosen.Kind=='Dog'and chosen.Id or chosen.Kind=='DogTier'and S.PickMember(chosen,picker)or nil
 if chosen.Kind=='DogTier'then R.Check(dogId,'Rewards are temporarily unavailable')end
 local forced={PrizeIndex=chosen.PrizeIndex,Kind=chosen.Kind,Id=chosen.Id,Name=chosen.Name,ChanceUnits=chosen.ChanceUnits,DogId=dogId}
 if dogId and serialled(D[dogId])then table.insert(keys,'supply:'..dogId)end
 local uid=Http:GenerateGUID(false):gsub('-','')
 local ok,result=runtime.Tx:Run(keys,function(v)
  return S.Resolve(v,userId,key,uid,now,runtime,paidAllowed,Random.new(seed),forced,boost)
 end,operation)
 if ok and type(result)=='table'then
  -- Return to the client first. Projection happens behind the spin, not in front of it.
  task.defer(function()if player.Parent then runtime.Refresh(player)end end)
  flushBigWin(runtime,userId,result)
 end
 return ok,result
end
return S
