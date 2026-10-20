-- DogEconomyRequest 'Tutorial' {Action, Key?} (Runtime.Request routes it here). The rules live in OnboardingRules;
-- this module adds what only the live server knows: where the character stands (Arrive: a Lucky Pad of the
-- player's own yard, the Mutation Lab) and the free tutorial Lucky Block (LuckyLifecycle.AddStored inside the
-- same profile transaction). Replies are OnboardingRules.View (+ FreeBlock when one was granted).
-- S.World is replaceable (tests): Position(player) -> Vector3?, Points(player, key) -> {Vector3}.
local O=require(script.Parent.OnboardingRules)
local R=require(script.Parent.Rules)
local TC=O.Config
local S={}
local function lucky()return require(script.Parent.LuckyLifecycle)end
local function commerce()return require(script.Parent.YardCommerce)end
S.World={}
-- The character's server position (alive characters only).
function S.World.Position(player)
 local character=player.Character
 local root=character and character:FindFirstChild('HumanoidRootPart')
 local humanoid=character and character:FindFirstChildOfClass('Humanoid')
 if not root or not root:IsA('BasePart')or not humanoid or humanoid.Health<=0 then return nil end
 return root.Position
end
-- World points an Arrive key is measured against.
function S.World.Points(player,key)
 local points={}
 if key=='LuckyPad'then
  local yard=commerce().Yard(player)
  local slots=tonumber(require(game:GetService('ReplicatedStorage'):WaitForChild('LuckyLifecycleConfig')).PlacementSlots)or 3
  for slot=1,slots do
   local pad=yard and yard:FindFirstChild('LuckyPad_'..slot)
   if pad and pad:IsA('BasePart')then table.insert(points,pad.Position)end
  end
 elseif key=='Lab'then
  local spec=TC.Arrive.Lab
  local map=workspace:FindFirstChild('DOGROTS_District')
  local lab=map and map:FindFirstChild('05_MutationLab')
  for _,name in ipairs(spec.Anchors)do
   local anchor=lab and lab:FindFirstChild(name)
   if anchor and anchor:IsA('BasePart')then table.insert(points,anchor.Position)end
  end
  -- the lab model streams on the server too: its saved anchor positions are the fallback
  if #points==0 then for _,point in ipairs(spec.Fallback)do table.insert(points,point)end end
 end
 return points
end
-- Is the player's character within the accepted radius of the place `key`?
function S.Near(player,key)
 local spec=TC.Arrive[key];if not spec then return false end
 local position=S.World.Position(player);if not position then return false end
 return O.WithinAny(position,S.World.Points(player,key),spec.Radius+spec.Slack)
end
function S.Request(runtime,player,args,receiptId)
 R.Check(type(args)=='table'and type(args.Action)=='string'and O.Actions[args.Action],'Invalid tutorial action')
 local action=args.Action
 if action=='Seen'or action=='Arrive'then R.Check(type(args.Key)=='string'and #args.Key<=24,'Invalid tutorial step')end
 if action=='Arrive'then R.Check(TC.Arrive[args.Key]~=nil,'Invalid tutorial step')end
 -- live world facts, measured before the transaction (positions are not profile data)
 local opts={}
 if action=='Arrive'then opts.Near=S.Near(player,args.Key)end
 if action=='Claim'then opts.NoPad=#S.World.Points(player,'LuckyPad')==0 end
 if action=='Arrive'or action=='Claim'then
  opts.AddBlock=function(p,tier,count,origin,paid)return lucky().AddStored(p,tier,count,origin,paid)end
 end
 local key='p:'..player.UserId
 return runtime.Tx:Run({key},function(values)
  local p=values[key];runtime.Engine:Authorize(p,player.UserId)
  local result=O.Apply(p,action,os.time(),{Key=args.Key},opts)
  R.Validate(p)
  return result
 end,receiptId)
end
return S
