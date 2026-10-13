-- One place that asks Roblox PolicyService about paid random items, cached per player.
--  Allowed(player)         ArePaidRandomItemsRestricted == false: the account may BUY or USE
--                          paid random rewards (DOG-O-MATIC paid tokens, paid Lucky Blocks,
--                          future Robux cases). Callers gate prompts AND spending on it.
--  TradingAllowed(user)    IsPaidItemTradingAllowed == true: PaidRandom assets may be traded
--                          or sold to other players (PaidItemPolicy, Market, Trades).
-- A failed lookup counts as "not allowed" (Roblox's rule for unknown policy) and is retried
-- after FailSeconds; a good answer is kept for CacheSeconds. Concurrent callers for the same
-- player share one in-flight request instead of each yielding on PolicyService.
local Players=game:GetService('Players')
local Policy=game:GetService('PolicyService')
local P={Cache={},Pending={},CacheSeconds=120,FailSeconds=15}

local function lookup(player)
 local ok,info=pcall(function()return Policy:GetPolicyInfoForPlayerAsync(player)end)
 if ok and type(info)=='table'then
  return {At=os.clock(),Ok=true,
   PaidRandom=info.ArePaidRandomItemsRestricted==false,
   Trading=info.IsPaidItemTradingAllowed==true}
 end
 return {At=os.clock(),Ok=false,PaidRandom=false,Trading=false,Error=tostring(info)}
end
-- Cached policy row for a Player: {Ok, PaidRandom, Trading, At}.
function P.Info(player)
 if typeof(player)~='Instance'or not player:IsA('Player')then return {Ok=false,PaidRandom=false,Trading=false,At=os.clock()}end
 local uid=player.UserId
 local row=P.Cache[uid]
 if row and os.clock()-row.At<(row.Ok and P.CacheSeconds or P.FailSeconds)then return row end
 if P.Pending[uid]then
  local deadline=os.clock()+10
  while P.Pending[uid]and os.clock()<deadline do task.wait()end
  return P.Cache[uid]or{Ok=false,PaidRandom=false,Trading=false,At=os.clock()}
 end
 P.Pending[uid]=true
 local fresh=lookup(player)
 P.Pending[uid]=nil
 if player.Parent then P.Cache[uid]=fresh end
 return fresh
end
function P.Allowed(player)return P.Info(player).PaidRandom==true end
-- Accepts a Player or a UserId (offline users are never allowed).
function P.TradingAllowed(user)
 local player=user
 if type(user)=='number'then player=Players:GetPlayerByUserId(user)end
 if not player then return false end
 return P.Info(player).Trading==true
end
function P.Forget(player)if player then P.Cache[player.UserId]=nil;P.Pending[player.UserId]=nil end end
Players.PlayerRemoving:Connect(P.Forget)
return P
