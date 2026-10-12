-- Paid-ticket catalog and fulfillment (Lucky Spin packs). Only PurchaseService.ProcessReceipt grants:
-- it runs Grant inside its single receipt transaction (grant + dedupe mark + supporter total)
-- and After once that transaction is saved.
local RS=game:GetService('ReplicatedStorage')
local C=require(RS.RewardMachineConfig)
local R=require(script.Parent.Rules)
local Tickets=require(script.Parent.RouletteTickets)
local PaidRandom=require(script.Parent.PaidRandomPolicy)
local P={}
-- Paid DOG TOKENS are paid random items: Roblox policy decides who may buy or spend them.
function P.Allowed(player)
 if C.FreeOnly then return false end
 return PaidRandom.Allowed(player)
end
function P.Catalog(player)
 local allowed=P.Allowed(player);local rows={}
 for _,product in ipairs(C.TicketProducts or{})do
  local configured=R.Int(product.Id,1,9007199254740990)and R.Int(product.Count,1,1000000)
  local active=not C.FreeOnly and configured and product.Enabled==true
  table.insert(rows,{Key=product.Key,Name=product.Name,Count=product.Count,ProductId=product.Id,
   Configured=configured==true,CanPurchase=active and allowed,
   UnavailableReason=C.FreeOnly and 'DOG TOKENS are free and cannot be purchased'or not configured and 'Coming soon' or not active and 'Not on sale' or not allowed and 'Unavailable for this account' or nil})
 end
 return rows,allowed
end
function P.Product(player,key)
 R.Check(not C.FreeOnly,'DOG TOKENS are free and cannot be purchased')
 R.Check(type(key)=='string'and #key<=60,'Choose a ticket pack')
 local rows=P.Catalog(player)
 for _,row in ipairs(rows)do if row.Key==key then
  R.Check(row.CanPurchase,row.UnavailableReason)
  return {ProductId=row.ProductId,Key=row.Key,Count=row.Count}
 end end
 error('Unknown ticket pack',0)
end
-- Profile mutation for one paid receipt (inside PurchaseService's durable transaction).
-- Receipt fulfillment deliberately ignores present-day policy and sale switches:
-- a completed purchase always credits the balance; use stays policy-gated.
function P.Grant(p,product,context)
 R.Check(R.Int(product.Count,1,1000000),'Invalid ticket quantity')
 Tickets.GrantPaid(p,product.Count,context.Now)
 return {Message=product.Count..(product.Count==1 and ' DOG TOKEN added'or ' DOG TOKENS added')..' · spin at the DOG-O-MATIC',
  Count=product.Count,PaidTickets=p.PaidRouletteTickets}
end
-- After the grant is saved: show the player what arrived (also after a retried receipt).
function P.After(_runtime,player,_product,result)
 local presentation=RS:FindFirstChild('RewardPresentation')
 if presentation and player.Parent and type(result)=='table'and result.Message then
  presentation:FireClient(player,{Cue='Reward',Message=result.Message})
 end
end
return P
