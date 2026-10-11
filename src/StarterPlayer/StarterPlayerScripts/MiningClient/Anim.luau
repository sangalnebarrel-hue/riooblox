-- Procedural character animation for the local player (no animation assets needed):
-- pickaxe swings and weight lifts are written to the arm Motor6D.Transform every frame after
-- the Animator, so they blend over the normal idle animation.
local RunService=game:GetService('RunService')
local Anim={}

local rad=math.rad
local function ease(a,b,t)t=math.clamp(t,0,1);t=t*t*(3-2*t);return a+(b-a)*t end

function Anim.new(ctx)
 local self:any={}
 local swingStart,swingPower=-1,1
 local liftTarget,liftValue,lifting=0,0,false
 local cache:any={}
 local function joints()
  local character=ctx.Player.Character
  if cache.Character~=character then
   cache={Character=character}
   if character then
    cache.RS=character:FindFirstChild('RightShoulder',true)or character:FindFirstChild('Right Shoulder',true)
    cache.RE=character:FindFirstChild('RightElbow',true)
    cache.LS=character:FindFirstChild('LeftShoulder',true)or character:FindFirstChild('Left Shoulder',true)
    cache.LE=character:FindFirstChild('LeftElbow',true)
   end
  end
  return cache
 end

 -- Pickaxe swing: wind-up over the head, fast chop, recover. Total ~0.34 s.
 function self.Swing(power)
  swingStart=os.clock();swingPower=power or 1
 end
 -- Lift pose: 0 = weight at the chest, 1 = arms locked overhead.
 function self.SetLift(active,progress)
  lifting=active;liftTarget=math.clamp(progress or 0,0,1)
  if not active then liftValue=0 end
 end

 RunService.Stepped:Connect(function(_,dt)
  local j=joints()
  local rs,re,ls,le=j.RS,j.RE,j.LS,j.LE
  if not rs or not rs:IsA('Motor6D')then return end
  local t=os.clock()-swingStart
  if t>=0 and t<.34 then
   local angle,elbow
   if t<.1 then angle=ease(0,155,t/.1);elbow=ease(0,45,t/.1)
   elseif t<.17 then angle=ease(155,30,(t-.1)/.07);elbow=ease(45,5,(t-.1)/.07)
   else angle=ease(30,0,(t-.17)/.17);elbow=ease(5,0,(t-.17)/.17)end
   rs.Transform=CFrame.Angles(rad(angle*math.min(1.1,swingPower)),0,rad(-8))
   if re and re:IsA('Motor6D')then re.Transform=CFrame.Angles(rad(elbow),0,0)end
   if ls and ls:IsA('Motor6D')then ls.Transform=CFrame.Angles(rad(angle*.55),0,rad(10))end
  elseif lifting then
   liftValue+= (liftTarget-liftValue)*math.min(1,(dt or 1/60)*14)
   local arm=70+liftValue*105
   local bend=(1-liftValue)*85
   rs.Transform=CFrame.Angles(rad(arm),0,rad(-6))
   if re and re:IsA('Motor6D')then re.Transform=CFrame.Angles(rad(bend),0,0)end
   if ls and ls:IsA('Motor6D')then ls.Transform=CFrame.Angles(rad(arm),0,rad(6))end
   if le and le:IsA('Motor6D')then le.Transform=CFrame.Angles(rad(bend),0,0)end
  end
 end)

 return self
end

return Anim
