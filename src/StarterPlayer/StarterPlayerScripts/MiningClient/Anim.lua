-- Procedural character animation (no animation assets needed): pickaxe swings and weight lifts
-- are written to the arm Motor6D.Transform every frame after the Animator, so they blend over the
-- normal idle animation. Motor transforms are not replicated, so every client also drives the
-- same poses for other players' characters from their corner's replicated hit/rep counters.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Anim={}

local rad=math.rad
local function ease(a,b,t)t=math.clamp(t,0,1);t=t*t*(3-2*t);return a+(b-a)*t end
local REP_TIME=.55 -- one remote lift: up to the top and back down

function Anim.new(ctx)
 local self:any={}
 local rigs={} -- character -> pose state
 local function rig(character)
  if not character then return nil end
  local r=rigs[character]
  if not r then
   r={SwingStart=-1,SwingPower=1,Lifting=false,LiftTarget=0,LiftValue=0,RepStart=-1}
   r.RS=character:FindFirstChild('RightShoulder',true)or character:FindFirstChild('Right Shoulder',true)
   r.RE=character:FindFirstChild('RightElbow',true)
   r.LS=character:FindFirstChild('LeftShoulder',true)or character:FindFirstChild('Left Shoulder',true)
   r.LE=character:FindFirstChild('LeftElbow',true)
   if not(r.RS and r.RS:IsA('Motor6D'))then return nil end
   rigs[character]=r
   character.Destroying:Once(function()rigs[character]=nil end)
  end
  return r
 end
 local function characterOf(who)
  if who==nil then return ctx.Player.Character end
  if typeof(who)=='Instance'and who:IsA('Player')then return who.Character end
  return who
 end

 -- Pickaxe swing: wind-up over the head, fast chop, recover. Total ~0.34 s.
 -- who: nil (local player), a Player or a character model.
 function self.Swing(power,who)
  local r=rig(characterOf(who));if not r then return end
  r.SwingStart=os.clock();r.SwingPower=power or 1
 end
 -- Lift pose: 0 = weight at the chest, 1 = arms locked overhead.
 function self.SetLift(active,progress,who)
  local r=rig(characterOf(who));if not r then return end
  r.Lifting=active;r.LiftTarget=math.clamp(progress or 0,0,1)
  if not active then r.LiftValue=0;r.RepStart=-1 end
 end
 -- One full repetition for a remote lifter (the local player drives SetLift from the meter).
 function self.Rep(who)
  local r=rig(characterOf(who));if not r then return end
  r.Lifting=true;r.RepStart=os.clock()
 end

 local function pose(r,dt)
  local rs,re,ls,le=r.RS,r.RE,r.LS,r.LE
  local t=os.clock()-r.SwingStart
  if t>=0 and t<.34 then
   local angle,elbow
   if t<.1 then angle=ease(0,155,t/.1);elbow=ease(0,45,t/.1)
   elseif t<.17 then angle=ease(155,30,(t-.1)/.07);elbow=ease(45,5,(t-.1)/.07)
   else angle=ease(30,0,(t-.17)/.17);elbow=ease(5,0,(t-.17)/.17)end
   rs.Transform=CFrame.Angles(rad(angle*math.min(1.1,r.SwingPower)),0,rad(-8))
   if re and re:IsA('Motor6D')then re.Transform=CFrame.Angles(rad(elbow),0,0)end
   if ls and ls:IsA('Motor6D')then ls.Transform=CFrame.Angles(rad(angle*.55),0,rad(10))end
  elseif r.Lifting then
   if r.RepStart>=0 then
    local a=(os.clock()-r.RepStart)/REP_TIME
    if a>=1 then r.RepStart=-1;r.LiftTarget=0 else r.LiftTarget=a<.5 and ease(0,1,a*2)or ease(1,0,(a-.5)*2)end
   end
   r.LiftValue+=(r.LiftTarget-r.LiftValue)*math.min(1,(dt or 1/60)*14)
   local arm=70+r.LiftValue*105
   local bend=(1-r.LiftValue)*85
   rs.Transform=CFrame.Angles(rad(arm),0,rad(-6))
   if re and re:IsA('Motor6D')then re.Transform=CFrame.Angles(rad(bend),0,0)end
   if ls and ls:IsA('Motor6D')then ls.Transform=CFrame.Angles(rad(arm),0,rad(6))end
   if le and le:IsA('Motor6D')then le.Transform=CFrame.Angles(rad(bend),0,0)end
  end
 end

 RunService.Stepped:Connect(function(_,dt)
  for character,r in pairs(rigs)do
   if character.Parent and r.RS.Parent then pose(r,dt)else rigs[character]=nil end
  end
 end)

 -- Remote players: swing on every replicated hit, hold the lift pose while their corner says
 -- Training and do one rep per TrainSerial step. The owner of a corner is found by UserId.
 local function ownerOf(corner)
  local id=corner:GetAttribute('OwnerUserId')or 0
  if id==0 or id==ctx.Player.UserId then return nil end
  return Players:GetPlayerByUserId(id)
 end
 function self.RemoteHit(corner)
  local owner=ownerOf(corner);if not owner then return end
  local tier=(corner:GetAttribute('PickaxeLevel')or 1)
  self.Swing(1+(tier-1)*.02,owner)
 end
 function self.RemoteTraining(corner,repped)
  local owner=ownerOf(corner);if not owner then return end
  if corner:GetAttribute('Training')==true then
   if repped then self.Rep(owner)else self.SetLift(true,0,owner)end
  else
   self.SetLift(false,0,owner)
  end
 end

 return self
end

return Anim
