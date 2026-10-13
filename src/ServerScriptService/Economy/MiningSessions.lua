-- Active Mining: RAM-only timing-target sessions (one per player, never saved).
local Players=game:GetService('Players')
local Sessions={}
local byUser={}
function Sessions.Get(userId)
 local s=byUser[userId]
 if not s then s={Targets={},NextId=0};byUser[userId]=s end
 return s
end
function Sessions.Clear(userId)byUser[userId]=nil end
Players.PlayerRemoving:Connect(function(player)byUser[player.UserId]=nil end)
return Sessions
