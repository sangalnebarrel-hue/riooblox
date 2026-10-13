-- Per-player percentages come from the same exact integer slots as the roll.
-- Board rows and drum faces are written by RewardMachineText (matched by PrizeIndex); this
-- script refreshes them every 10 s near the machine and at once when the Aurion boost flips.
local RS=game:GetService('ReplicatedStorage');local player=game.Players.LocalPlayer
local rig=workspace:WaitForChild('DOGROTS_District'):WaitForChild('37_AttractionRefresh'):WaitForChild('RewardMachineRig')
local Text=require(RS.RewardMachineText)
Text.SetupVisibility(rig)
local board=rig:WaitForChild('StatusBoard',60):WaitForChild('OddsDisplay')
local focus=rig:WaitForChild('CameraHooks'):WaitForChild('RevealFocus',60)
local remote=RS:WaitForChild('RewardRequest');local motion=require(RS.RewardMachineMotion)
local prompt=workspace.DOGROTS_District:WaitForChild('27_RewardMachinePlaza'):WaitForChild('RewardMachine'):FindFirstChild('RewardMachinePrompt',true)
local snapshot;local fetchedAt=-30;local fetching=false
local function clockText(s)s=math.max(0,math.ceil(s));return string.format('%02d:%02d:%02d',math.floor(s/3600),math.floor(s/60)%60,s%60)end
local function refresh()
 if fetching then return end;fetching=true
 local good,ok,info=pcall(function()return remote:InvokeServer('RewardMachineInfo',{})end)
 fetching=false
 -- A failed read retries in a few seconds instead of leaving a stale board for 10 s.
 if not good or not ok or type(info)~='table'or type(info.Rewards)~='table'then fetchedAt=os.clock()-7;return end
 snapshot=info;fetchedAt=os.clock()
 Text.Apply(rig,info.Rewards)
 local rows=board:FindFirstChild('Rows')
 for _,row in ipairs(info.Rewards)do
  local label=rows and row.PrizeIndex and rows:FindFirstChild('Row'..row.PrizeIndex)
  if label then label.TextColor3=row.Multiplier and Color3.fromRGB(255,86,140)or motion.Color(row)end
 end
end
rig:GetAttributeChangedSignal('AurionBoost'):Connect(function()fetchedAt=-30 end)
while player.Parent do
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if root and(root.Position-focus.Position).Magnitude<160 then
  if os.clock()-fetchedAt>=10 then refresh()end
  if snapshot then
   local now=snapshot.ServerNow+(os.clock()-fetchedAt);local free=snapshot.FreeTickets or 0
   local usable=free+(snapshot.FreeOnly==false and snapshot.PaidRandomAllowed==true and(tonumber(snapshot.PaidTickets)or 0)or 0)
   local boost=type(snapshot.ActiveBoost)=='table'and snapshot.ActiveBoost
   local second
   if boost and(tonumber(boost.EndsAt)or 0)>now then
    local left=math.max(0,boost.EndsAt-now)
    second='AURION x'..string.format('%g',boost.Multiplier)..' · '..tostring(boost.Name or'Rainbow Rift'):upper()..' '..string.format('%02d:%02d',math.floor(left/60),math.floor(left)%60)
   else second=free>=1 and 'READY TO ACTIVATE'or 'NEXT FREE DOG TOKEN  '..clockText(snapshot.NextTicketAt-now)end
   board.Status.Text='FREE DOG TOKEN '..free..'/1\n'..second
   if prompt then prompt.ActionText=usable>=1 and 'ACTIVATE · 1 DOG TOKEN'or 'VIEW';prompt.ObjectText='DOG-O-MATIC'end
  else board.Status.Text='Open DOG-O-MATIC to view reward chances'end
 end
 task.wait(1)
end
