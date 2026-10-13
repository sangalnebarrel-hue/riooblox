-- TOP SUPPORTERS accounting (Lifetime.SupportRobux).
-- Since the payments update every receipt adds SupportRobux inside its single grant
-- transaction (PurchaseService), and the purchase:<PurchaseId> record says Counted=true.
-- Record() below is kept only for LEGACY receipts: granted by the old code (no Counted flag)
-- but never acknowledged because this second transaction failed. Its support-receipt:<id>
-- key keeps the count exactly-once for them.
local Stats=require(script.Parent.LifetimeStats)
local S={}
-- Is any (id=nil) or this developer product configured? Uses PurchaseService's product index.
function S.Configured(id)
 return require(script.Parent.PurchaseService).Configured(id)
end
function S.Record(runtime,receipt)
 if not S.Configured(receipt.ProductId)then return false end
 local amount=receipt.CurrencySpent
 if type(amount)~='number'or amount~=amount or amount<0 or amount%1~=0 or amount>9000000000000000 then return false end
 if receipt.CurrencyType~=Enum.CurrencyType.Robux then return false end
 if type(receipt.PurchaseId)~='string'or #receipt.PurchaseId==0 or #receipt.PurchaseId>100 then return false end
 local id=receipt.PlayerId;local key='support-receipt:'..receipt.PurchaseId;local profile='p:'..id
 local ok=runtime.Tx:Run({profile,key},function(v)
  if v[key]then
   assert(v[key].User==id and v[key].Product==receipt.ProductId and v[key].Amount==amount,'Support receipt mismatch')
   return 'Already counted'
  end
  local p=v[profile];runtime.Engine:Authorize(p,id)
  Stats.Add(p,'SupportRobux',amount)
  v[key]={User=id,Product=receipt.ProductId,Amount=amount,At=os.time()}
  return 'Counted'
 end,nil,{Timeout=45})
 return ok==true
end
return S
