-- Consult Roblox before a paid-random asset enters a player-to-player transfer.
-- The PolicyService lookup and its cache live in PaidRandomPolicy (one request per player
-- answers both "may buy paid random items" and "may trade them").
local PaidRandom=require(script.Parent.PaidRandomPolicy)
local P={}
function P.Allowed(user)return PaidRandom.TradingAllowed(user)end
return P
