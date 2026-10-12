-- PAW MARKET developer products (CommerceConfig). Product() answers the client's BUY request
-- with the product ID to prompt; Grant() runs inside PurchaseService's single receipt
-- transaction (grant + purchase mark + supporter total together) and After() runs once that
-- transaction is saved. Only the single ProcessReceipt owner (PurchaseService) calls them.
local RS=game:GetService('ReplicatedStorage')
local C=require(RS.CommerceConfig)
local Pricing=require(RS.DogEconomy.BoostPricing)
local Config=require(script.Parent.Config)
local R=require(script.Parent.Rules)
local Supplies=require(script.Parent.SupplyRules)
local Luck=require(script.Parent.LuckRules)
local ServerLuck=require(script.Parent.ServerLuck)
local P={}
-- Older duplicate offers share their original's one-per-player slot.
local function onceKey(product)return product.Alias or product.Key end
P.OnceKey=onceKey
-- Coins a bundle grants this player right now (fixed Cash plus income-scaled Coins).
function P.Coins(product,p,now)
 local rewards=product.Rewards or {}
 return (rewards.Cash or 0)+(rewards.Coins and Pricing.Coins(rewards.Coins,p,now)or 0)
end
-- Prompt-time gate. Robux is never taken for something that cannot be delivered right now:
-- an offer made only of timed boosts is refused when none of its parts has room. Bundles
-- with coins/bones are always sold; their timed parts never lose a second (reserves/credits).
function P.Product(runtime,player,key)
 R.Check(type(key)=='string'and #key<=60,'Choose an offer')
 local product=C.Find(key)
 R.Check(product and product.Enabled==true and R.Int(product.Id,1,9007199254740990),'Coming soon')
 local p=runtime.Engine:Get(player.UserId);local now=os.time()
 if product.Supply then R.Check(Supplies.CanAddPaid(p,product.Supply,now,product.Seconds),'Six hours already stored; use some before adding more')end
 if product.Once then R.Check(not(p.CommercePurchases or {})[onceKey(product)],'You already own this pack')end
 local rewards=product.Rewards
 -- Only bundles that grant coins care about a full wallet (server luck never does).
 if rewards and(rewards.Coins or rewards.Cash)then R.Check(p.Cash<Config.MaxCash,'Coin storage is full')end
 if rewards and not(rewards.Coins or rewards.Cash or rewards.Bones)then
  local room=false
  if rewards.ServerLuck and ServerLuck.Room(rewards.ServerLuck.Multiplier,now)>0 then room=true end
  if rewards.Luck and Luck.CanAddPaid(p,rewards.Luck.Tier,now,rewards.Luck.Seconds)then room=true end
  for supply,seconds in pairs(rewards.Supplies or {})do if Supplies.CanAddPaid(p,supply,now,seconds)then room=true end end
  if not room then
   R.Check(not rewards.ServerLuck,'Server luck is at its limit right now. Try again in a few minutes.')
   R.Check(false,'This boost already has the most time stored; use some first')
  end
 end
 return {ProductId=product.Id,Key=key}
end
-- Profile mutation for one receipt. context = {Now, PurchaseId, Player}.
function P.Grant(p,product,context)
 local now=context.Now
 local result={Message=product.Name..' added',Key=product.Key}
 if product.Supply then
  Supplies.AddPaid(p,product.Supply,now,product.Seconds)
 else
  local rewards=assert(product.Rewards,'Missing rewards')
  -- A paid receipt never fails on a full wallet: the coins fill it to the brim instead.
  local coins=math.clamp(P.Coins(product,p,now),0,Config.MaxCash-p.Cash)
  R.Check(R.Int(coins,0,Config.MaxCash)and R.Int(rewards.Bones or 0,0,1000000),'Invalid bundle')
  if coins>0 then R.Credit(p,coins,false)end
  p.Bones+=(rewards.Bones or 0)
  for supply,seconds in pairs(rewards.Supplies or {})do Supplies.AddPaid(p,supply,now,seconds)end
  -- Paid luck keeps every second: what passes the active cap waits in LuckReserve.
  if rewards.Luck then Luck.AddPaid(p,rewards.Luck.Tier,rewards.Luck.Seconds,now)end
  -- Server luck is saved as a credit in the profile; After() starts it on this server.
  if rewards.ServerLuck then
   local player=context.Player
   ServerLuck.QueueCredit(p,'r:'..context.PurchaseId,rewards.ServerLuck.Multiplier,rewards.ServerLuck.Seconds,now,player and player.DisplayName or nil)
   result.ServerLuck={Multiplier=rewards.ServerLuck.Multiplier,Seconds=rewards.ServerLuck.Seconds}
  end
  -- Paying again for a one-per-player pack (a duplicate prompt) still delivers it.
  if product.Once then p.CommercePurchases=p.CommercePurchases or {};p.CommercePurchases[onceKey(product)]=now end
  result.Coins=coins;result.Bones=rewards.Bones
 end
 return result
end
-- After the receipt is saved (also for a retried receipt that was already granted).
function P.After(runtime,player,product,result)
 if product.Rewards and product.Rewards.ServerLuck then
  -- Idempotent: starts whatever this buyer's credits still hold, as far as the pool has room.
  local ok,err=ServerLuck.ActivateFor(runtime,player)
  if not ok then warn('[DOGROTS commerce] server luck start deferred for',player.UserId,err)end
 end
 local presentation=RS:FindFirstChild('RewardPresentation')
 if presentation and player.Parent then
  presentation:FireClient(player,{Cue='Reward',Message=type(result)=='table'and result.Message or product.Name..' added'})
 end
end
return P
