-- Paid-data fields of the payments update (feature module, see Economy.FeatureRegistry):
--   p.Passes            {[tostring(gamePassId)]=true}  game-pass entitlements, never removed
--   p.LuckReserve       {[tostring(tier)]=seconds}     paid luck waiting behind the timer (LuckRules)
--   p.ServerLuckCredits {[creditId]={Multiplier,Queued,Active,Server,At,Name}}  (ServerLuck)
-- All three are optional (nil on profiles that never paid); every reader is nil-safe.
-- Normalize keeps them well-formed without dropping a valid entry and re-derives pass
-- benefits from ownership, so a rollback or reset of a benefit can never lose it.
local Definitions=require(script.Parent.Parent.ShopDefinitions)
local F={Name='Payments',Order=5}
local function positive(v)return type(v)=='number'and v==v and v>0 and v<math.huge end
-- Benefits follow ownership: every owned pass's cosmetic is present.
function F.Apply(p)
 local passes=type(p.Passes)=='table'and p.Passes or nil
 if not passes or next(passes)==nil then return end
 for _,row in ipairs(Definitions)do
  if row.Kind=='Pass'and type(row.Id)=='number'and row.Id>0 and passes[tostring(row.Id)]==true then
   local reward=row.Rewards
   if type(reward)=='table'and type(reward.Cosmetic)=='string'then
    p.Cosmetics=type(p.Cosmetics)=='table'and p.Cosmetics or {}
    p.Cosmetics[reward.Cosmetic]=true
   end
  end
 end
end
function F.Normalize(_R,p,_now)
 if p.Passes~=nil then
  if type(p.Passes)~='table'then p.Passes=nil
  else
   -- DataStore-safe string keys only (numeric keys are converted, never dropped).
   local numeric={}
   for k,v in pairs(p.Passes)do if type(k)=='number'then numeric[k]=v end end
   for k,v in pairs(numeric)do p.Passes[k]=nil;if v then p.Passes[tostring(math.floor(k))]=true end end
   F.Apply(p)
  end
 end
 if p.LuckReserve~=nil and type(p.LuckReserve)~='table'then p.LuckReserve=nil end
 if p.ServerLuckCredits~=nil and type(p.ServerLuckCredits)~='table'then p.ServerLuckCredits=nil end
end
-- Small read-only summary for the client (snapshot.Features.Payments), only when there is one.
function F.Snapshot(_R,p,view,_now)
 local reserve,queued,passes={},0,0
 for tier,seconds in pairs(type(p.LuckReserve)=='table'and p.LuckReserve or {})do
  if positive(seconds)then reserve[tostring(tier)]=math.floor(seconds)end
 end
 for _,row in pairs(type(p.ServerLuckCredits)=='table'and p.ServerLuckCredits or {})do
  if type(row)=='table'and positive(row.Queued)then queued+=math.floor(row.Queued)end
 end
 for _,owned in pairs(type(p.Passes)=='table'and p.Passes or {})do if owned==true then passes+=1 end end
 if next(reserve)==nil and queued==0 and passes==0 then return end
 view.Payments={LuckReserve=reserve,ServerLuckQueued=queued,Passes=passes}
end
return F
