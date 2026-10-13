-- Procedural character animation (no animation assets needed): pickaxe swings and weight lifts
-- are written to the Motor6D.Transform of the arms (and on R15 the waist, hips, knees and root)
-- every frame after the Animator, so they blend over the normal idle animation. Motor transforms
-- are not replicated, so every client also drives the same poses for other players' characters
-- from their corner's replicated hit/rep counters.
-- Swing styles (Config.Mining.Pickaxes[i].Swing): Chop (two-handed overhead), Smash (huge
-- wind-up, heavy pickaxes), Slash (horizontal sweep: scythe, saw), Claw (left / right jabs).
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Anim={}

local rad=math.rad
local function ease(a,b,t)t=math.clamp(t,0,1);t=t*t*(3-2*t);return a+(b-a)*t end
-- Piecewise keyframes: {time, value...}; returns the values at t (smoothstep between keys).
local function keys(list,t)
 if t<=list[1][1]then return table.unpack(list[1],2)end
 for i=2,#list do
  local a,b=list[i-1],list[i]
  if t<=b[1]then
   local f=(t-a[1])/(b[1]-a[1])
   local out={}
   for j=2,#a do out[j-1]=ease(a[j],b[j],f)end
   return table.unpack(out)
  end
 end
 return table.unpack(list[#list],2)
end
local REP_TIME=.55 -- one remote lift: up to the top and back down

-- Swing keyframes: time, right shoulder X, right elbow, left shoulder X, waist twist (Y), lean (X)
local SWINGS={
 Chop={Length=.34,Keys={{0,0,0,0,0,0},{.1,155,45,95,-14,-6},{.17,30,5,40,10,14},{.34,0,0,0,0,0}}},
 Smash={Length=.46,Keys={{0,0,0,0,0,0},{.18,175,60,170,-20,-14},{.26,20,0,25,16,22},{.46,0,0,0,0,0}}},
}
function Anim.new(ctx)
 local self:any={}
 local rigs={} -- character -> pose state
 local function motor(character,...)
  for _,name in ipairs({...})do
   local m=character:FindFirstChild(name,true)
   if m and m:IsA('Motor6D')then return m end
  end
  return nil
 end
 local function rig(character)
  if not character then return nil end
  local r=rigs[character]
  if not r then
   r={SwingStart=-1,SwingPower=1,Style='Chop',Side=1,Lifting=false,LiftTarget=0,LiftValue=0,RepStart=-1,DrawStart=-1,Ready=false,ReadyValue=0}
   r.RS=motor(character,'RightShoulder','Right Shoulder')
   r.RE=motor(character,'RightElbow')
   r.LS=motor(character,'LeftShoulder','Left Shoulder')
   r.LE=motor(character,'LeftElbow')
   r.Waist=motor(character,'Waist')
   r.Root=motor(character,'Root')
   r.RH=motor(character,'RightHip');r.LH=motor(character,'LeftHip')
   r.RK=motor(character,'RightKnee');r.LK=motor(character,'LeftKnee')
   if not r.RS then return nil end
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

 -- One strike. power ~1; style from the pickaxe (Swing). who: nil (local), a Player or a model.
 function self.Swing(power,who,style)
  local r=rig(characterOf(who));if not r then return end
  r.SwingStart=os.clock();r.SwingPower=power or 1;r.Style=style or'Chop'
  r.Side=-r.Side -- Claw / Slash alternate
 end
 -- Draw the pickaxe from the back (session start).
 function self.Draw(who)
  local r=rig(characterOf(who));if not r then return end
  r.DrawStart=os.clock()
 end
 -- Hold the pickaxe up, ready to strike, while a mining session runs.
 function self.SetReady(active,who,style)
  local r=rig(characterOf(who));if not r then return end
  r.Ready=active==true
  if style then r.Style=style end
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

 local function set(m,cf)if m then m.Transform=cf end end
 local function pose(r,dt)
  local rs,re,ls,le=r.RS,r.RE,r.LS,r.LE
  local now=os.clock()
  r.ReadyValue+=((r.Ready and 1 or 0)-r.ReadyValue)*math.min(1,(dt or 1/60)*10)
  local t=now-r.SwingStart
  local style=r.Style
  local spec=SWINGS[style]
  local length=spec and spec.Length or(style=='Slash'and .36 or .26)
  if t>=0 and t<length then
   local p=math.min(1.15,r.SwingPower)
   if spec then
    local a,elbow,left,twist,lean=keys(spec.Keys,t)
    set(rs,CFrame.Angles(rad(a*p),0,rad(-8)))
    set(re,CFrame.Angles(rad(elbow),0,0))
    set(ls,CFrame.Angles(rad(left*p),0,rad(10)))
    set(r.Waist,CFrame.Angles(rad(lean),rad(twist),0))
   elseif style=='Slash'then
    -- Arm forward at shoulder height, sweeping across the body; the waist follows.
    local sweep,raise,twist=keys({{0,0,40,0},{.1,75*r.Side,95,-24*r.Side},{.2,-80*r.Side,85,26*r.Side},{.36,0,40,0}},t)
    set(rs,CFrame.Angles(rad(raise),rad(sweep),0))
    set(re,CFrame.Angles(rad(10),0,0))
    set(ls,CFrame.Angles(rad(raise*.6),rad(sweep*.5),0))
    set(r.Waist,CFrame.Angles(rad(6),rad(twist),0))
   else -- Claw: a forward jab with one arm (alternating), the other pulls back
    local jab,elbow,twist=keys({{0,30,70,0},{.08,95,0,22},{.26,30,70,0}},t)
    local main,other=r.Side>0 and rs or ls,r.Side>0 and ls or rs
    set(main,CFrame.Angles(rad(jab),0,0))
    set(r.Side>0 and re or le,CFrame.Angles(rad(elbow),0,0))
    set(other,CFrame.Angles(rad(40),0,0))
    set(r.Side>0 and le or re,CFrame.Angles(rad(80),0,0))
    set(r.Waist,CFrame.Angles(0,rad(twist*r.Side),0))
   end
  elseif r.DrawStart>=0 and now-r.DrawStart<.45 then
   -- Reach over the shoulder for the pickaxe on the back, then bring it forward.
   local a,z=keys({{0,0,0},{.18,170,-25},{.45,40,0}},now-r.DrawStart)
   set(rs,CFrame.Angles(rad(a),0,rad(z)))
   set(re,CFrame.Angles(rad(a>90 and 60 or 10),0,0))
  elseif r.Lifting then
   if r.RepStart>=0 then
    local a=(now-r.RepStart)/REP_TIME
    if a>=1 then r.RepStart=-1;r.LiftTarget=0 else r.LiftTarget=a<.5 and ease(0,1,a*2)or ease(1,0,(a-.5)*2)end
   end
   r.LiftValue+=(r.LiftTarget-r.LiftValue)*math.min(1,(dt or 1/60)*14)
   local v=r.LiftValue
   local arm=70+v*105
   local bend=(1-v)*85
   set(rs,CFrame.Angles(rad(arm),0,rad(-6)))
   set(re,CFrame.Angles(rad(bend),0,0))
   set(ls,CFrame.Angles(rad(arm),0,rad(6)))
   set(le,CFrame.Angles(rad(bend),0,0))
   -- R15: squat at the bottom of the lift and drive up with the legs; strain wobble at the top.
   local squat=(1-v)*.8
   local strain=v>.85 and math.sin(now*38)*.6 or 0
   set(r.Root,CFrame.new(0,-squat*.55,0)*CFrame.Angles(rad(-squat*8),0,rad(strain)))
   set(r.RH,CFrame.Angles(rad(squat*38),0,0));set(r.LH,CFrame.Angles(rad(squat*38),0,0))
   set(r.RK,CFrame.Angles(rad(-squat*62),0,0));set(r.LK,CFrame.Angles(rad(-squat*62),0,0))
   set(r.Waist,CFrame.Angles(rad(squat*10-v*4),0,0))
  elseif r.ReadyValue>.02 then
   local k=r.ReadyValue
   local breathe=math.sin(now*2.2)*3
   if r.Style=='Claw'then
    set(rs,CFrame.Angles(rad((45+breathe)*k),0,0));set(ls,CFrame.Angles(rad((45-breathe)*k),0,0))
    set(re,CFrame.Angles(rad(60*k),0,0));set(le,CFrame.Angles(rad(60*k),0,0))
   else
    set(rs,CFrame.Angles(rad((38+breathe)*k),0,rad(-6*k)))
    set(ls,CFrame.Angles(rad((26+breathe)*k),0,rad(14*k)))
    set(re,CFrame.Angles(rad(25*k),0,0))
   end
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
  local level=(corner:GetAttribute('PickaxeLevel')or 1)
  local def=ctx.M.Pickaxes[level]
  self.Swing(1+(level-1)*.01,owner,def and def.Swing)
  if ctx.PickFX then ctx.PickFX.HitPulse(owner.Character,1)end
 end
 function self.RemoteTraining(corner,repped)
  local owner=ownerOf(corner);if not owner then return end
  if corner:GetAttribute('Training')==true then
   if repped then self.Rep(owner)else self.SetLift(true,0,owner)end
  else
   self.SetLift(false,0,owner)
  end
 end
 -- Remote miners hold their pickaxe ready while their corner is Active.
 function self.RemoteActive(corner)
  local owner=ownerOf(corner);if not owner then return end
  local level=(corner:GetAttribute('PickaxeLevel')or 1)
  local def=ctx.M.Pickaxes[level]
  local r=rig(owner.Character);if r then r.Style=def and def.Swing or'Chop'end
  self.SetReady(corner:GetAttribute('Active')==true,owner)
 end

 return self
end

return Anim
