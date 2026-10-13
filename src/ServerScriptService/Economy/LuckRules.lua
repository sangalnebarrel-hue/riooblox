-- Personal luck tiers (LUCK tab). One expiry per tier, saved in the profile; the highest
-- active tier is the one that counts, so a short 5x on top of a long 1x falls back to 1x.
-- Paid luck (Robux bundles) is never cut off: the timer may run up to PaidActiveCap ahead and
-- anything beyond waits in p.LuckReserve[tier] (seconds), feeding the timer automatically
-- (same model as SupplyRules / p.SupplyReserve). Active and reserved time are one continuous
-- timeline: EndAt = active expiry + reserve, and both count down offline like before.
local C=require(script.Parent.Config)
local L={}
L.PaidActiveCap=6*3600
-- Prompt-time limit for luck-only offers: stop selling a tier once this much is stored.
L.PaidStoreCap=24*3600
local function seconds(v)
 return type(v)=='number'and v==v and v>0 and v<math.huge
end
function L.Normalize(p,now)
 local boosts=type(p.LuckBoosts)=='table'and p.LuckBoosts or {}
 local reserve=type(p.LuckReserve)=='table'and p.LuckReserve or nil
 if reserve then
  for key,stored in pairs(reserve)do
   if not seconds(stored)then reserve[key]=nil
   elseif C.LuckTiers[tonumber(key)or 0]then
    -- Unknown tiers keep their reserve untouched (paid time is never dropped).
    local at=boosts[key]
    local base=type(at)=='number'and at or now
    local finish=base+stored
    local active=math.max(now,math.min(finish,now+L.PaidActiveCap))
    boosts[key]=active>now and active or nil
    local rest=math.floor(finish-active)
    reserve[key]=rest>0 and rest or nil
   end
  end
  p.LuckReserve=reserve
 end
 for key,at in pairs(boosts)do
  if not C.LuckTiers[tonumber(key)or 0]or type(at)~='number'or at<=now then boosts[key]=nil end
 end
 p.LuckBoosts=boosts
 return boosts
end
-- Highest active tier (0 = none) and when it ends.
function L.Active(p,now)
 local best,ends=0,0
 for key,at in pairs(p.LuckBoosts or {})do
  local tier=tonumber(key)
  if tier and type(at)=='number'and at>now and tier>best then best,ends=tier,at end
 end
 return best,ends
end
function L.Bonus(p,now)
 local tier=L.Active(p,now);local def=C.LuckTiers[tier]
 return def and def.Bonus or 0
end
-- Paid time stored behind the active timer (seconds).
function L.Reserve(p,tier)
 local v=(type(p.LuckReserve)=='table'and p.LuckReserve or {})[tostring(tier)]
 return seconds(v)and math.floor(v)or 0
end
-- When this tier's time (active + reserve) runs out.
function L.EndAt(p,tier)
 local at=(p.LuckBoosts or {})[tostring(tier)]
 local reserve=L.Reserve(p,tier)
 if type(at)~='number'then at=0 end
 if reserve<=0 then return at end
 -- Reserve continues the active timer (Normalize uses the same rule).
 return (at>0 and at or os.time())+reserve
end
function L.CanAdd(p,tier,now,seconds)
 local def=C.LuckTiers[tier];if not def then return false end
 return math.max(now,L.EndAt(p,tier))+(seconds or def.Seconds)<=now+def.MaxSeconds
end
-- Adds time to a tier (capped at `cap` seconds of stored time, default its MaxSeconds);
-- returns the new expiry. Coin purchases only (they check CanAdd first). Robux time uses AddPaid.
function L.Add(p,tier,seconds,now,cap)
 local def=assert(C.LuckTiers[tier],'Unknown luck tier')
 L.Normalize(p,now)
 local finish=math.min(math.max(now,L.EndAt(p,tier))+seconds,now+(cap or def.MaxSeconds))
 p.LuckBoosts[tostring(tier)]=math.max(finish,p.LuckBoosts[tostring(tier)]or 0)
 return finish
end
-- Prompt-time check for offers that only sell luck time.
function L.CanAddPaid(p,tier,now,seconds)
 local def=C.LuckTiers[tier];if not def then return false end
 return math.max(now,L.EndAt(p,tier))+(seconds or def.Seconds)<=now+L.PaidStoreCap
end
-- Robux luck: every second is kept. The timer runs up to PaidActiveCap ahead, the rest waits
-- in LuckReserve. Returns when the tier's time now ends (active + reserve).
function L.AddPaid(p,tier,seconds,now)
 assert(C.LuckTiers[tier],'Unknown luck tier')
 assert(type(seconds)=='number'and seconds>0 and seconds<math.huge,'Invalid luck time')
 L.Normalize(p,now)
 local key=tostring(tier)
 local finish=math.max(now,L.EndAt(p,tier))+math.floor(seconds)
 local active=math.min(finish,now+L.PaidActiveCap)
 p.LuckBoosts[key]=math.max(active,p.LuckBoosts[key]or 0)
 local rest=math.floor(finish-p.LuckBoosts[key])
 p.LuckReserve=type(p.LuckReserve)=='table'and p.LuckReserve or {}
 p.LuckReserve[key]=rest>0 and rest or nil
 return finish
end
return L
