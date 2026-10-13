-- Lucky Block arrival on THE DOG's tongue (client only, presentation only).
-- Every lucky block spawns inside DarkMouthTunnel (DogSpawn, z -168) and rides +Z along the
-- tongue. This script watches DOGROTS_District['03_DogLine'].ActiveDogs and, when a fresh
-- block's RootPart reaches the mouth lip (z -146), plays a per-tier entrance:
--   Common    soft glint + dust/sparkle puff
--   Rare      blue ripple rings + sparkle burst + arrive chime
--   Epic      purple double ring, rune sparks spiralling up the block, light flash
--   Legendary golden shockwave, coin + sparkle fountain, warm glow, gold pillar past the head
--   Mythic    crimson-gold double shockwave, crown-jewel lightning, ember fountain, FOV punch,
--             sky-high beam past the head, island banner
--   Secret    mini-cinematic: the mouth turns violet, a void implodes at the lip and explodes
--             along the tongue, reality cracks, screen tint/letterbox nearby, a violet-cyan
--             beam past the head
-- FX live in workspace.DOGROTS_LuckyFX (outside WorldDetailQuality and the block model), the
-- server model is never touched. Geometry limits: under y 23 inside the mouth (z < -146),
-- under 27 below the muzzle (z -149..-129), under 36 below the nose (z -131..-121); tall beams
-- only from z -118 on.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local player=Players.LocalPlayer

local Lucky=RS:WaitForChild('Lucky')
local Show=require(Lucky:WaitForChild('LuckyShow'))
local Audio=require(Lucky:WaitForChild('LuckyAudio'))
local Stream=require(RS:WaitForChild('LuckyBlockConfig')).Stream

-- @timing-begin (pure math; tools smoke-test this block with Lune)
local Timing={}
Timing.SpawnZ=-168 -- DogSpawn, deep in the throat
Timing.LipZ=-146 -- the mouth lip: the block becomes visible
Timing.HeadClearZ=-118 -- past THE DOG's nose: open sky above (beam edges must stay >= -120)
Timing.BaseSpeed=6
-- Tongue speed in studs/s, as DogLineSpawner computes it: Stream.Speed x EventLineScale
-- (clamped .4..2) x the slowest Secret's LineSpeedScale (clamped .2..1); 0 while frozen.
function Timing.Speed(base:number?,eventScale:any,lineScale:any,frozen:boolean?):number
 if frozen then return 0 end
 local e=math.clamp(tonumber(eventScale)or 1,.4,2)
 local l=math.clamp(tonumber(lineScale)or 1,.2,1)
 return(base or Timing.BaseSpeed)*e*l
end
-- Seconds from spawn until the block centre reaches z (math.huge on a stopped tongue).
function Timing.TimeToZ(z:number,speed:number,spawnZ:number?):number
 if speed<=0 then return math.huge end
 return math.max(0,(z-(spawnZ or Timing.SpawnZ))/speed)
end
-- Block age in seconds: from SpawnedAt when the server set it, else from the line's
-- StreamTravel - the block's StreamOffset (both in studs), else from its z position.
function Timing.Age(now:number,spawnedAt:any,travel:any,offset:any,speed:number,z:number?):number?
 if type(spawnedAt)=='number'then return math.max(0,now-spawnedAt)end
 if speed<=0 then return nil end
 if type(travel)=='number'and type(offset)=='number'then return math.max(0,travel-offset)/speed end
 if type(z)=='number'then return math.max(0,z-Timing.SpawnZ)/speed end
 return nil
end
function Timing.Fresh(age:number?,grace:number):boolean
 return age~=nil and age<=grace
end
-- Estimated z of the block centre after `age` seconds on a steady tongue.
function Timing.Z(age:number,speed:number,spawnZ:number?):number
 return(spawnZ or Timing.SpawnZ)+math.max(0,age)*speed
end
-- Seconds until the block (now at z) reaches target (0 if past it, math.huge if stopped).
function Timing.Eta(z:number,target:number,speed:number):number
 if z>=target then return 0 end
 if speed<=0 then return math.huge end
 return(target-z)/speed
end
-- @timing-end

local LIP,HEAD_CLEAR=Timing.LipZ,Timing.HeadClearZ
local TONGUE_Y=2.12 -- tongue / belt surface
local CENTRE_Y=4.5 -- block centre on the belt
local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local FIRE='rbxasset://textures/particles/fire_main.dds'
local NAVY=Color3.fromRGB(23,43,76)
local WHITE=Color3.new(1,1,1)
local rng=Random.new()
local function rand(a:number,b:number):number return rng:NextNumber(a,b)end
local function serverNow()return workspace:GetServerTimeNow()end
local function seq(...)return ColorSequence.new(...)end

local district=workspace:WaitForChild('DOGROTS_District')
local line=district:WaitForChild('03_DogLine')
local active=line:WaitForChild('ActiveDogs')

---------------------------------------------------------------- locale
local isRussian:boolean?=nil
local function russian():boolean
 if isRussian~=nil then return isRussian end
 local ok,locale=pcall(function()
  local LS=game:GetService('LocalizationService')
  if Run:IsStudio()then return LS.RobloxLocaleId end
  return player.LocaleId or LS.RobloxLocaleId
 end)
 isRussian=ok and type(locale)=='string'and locale:sub(1,2):lower()=='ru'or false
 return isRussian==true
end

---------------------------------------------------------------- FX root + scopes
local function fxRoot():Instance
 local root=workspace:FindFirstChild('DOGROTS_LuckyFX')
 if not root then root=Instance.new('Folder');root.Name='DOGROTS_LuckyFX';root.Parent=workspace end
 return root
end

-- Optional: SecretArrivals.Kit layers its world overrides (mouth runes, mist) per object;
-- going through it keeps a Secret DOG cinematic and this script from fighting over them.
local kitCache:any=nil
local function kit():any
 if kitCache~=nil then return kitCache or nil end
 kitCache=false
 local scripts=player:FindFirstChild('PlayerScripts')
 local arrivals=scripts and scripts:FindFirstChild('SecretArrivals')
 local module=arrivals and arrivals:FindFirstChild('Kit')
 if module and module:IsA('ModuleScript')then
  local ok,k=pcall(require,module)
  if ok and type(k)=='table'and type(k.Scope)=='function'then kitCache=k end
 end
 return kitCache or nil
end

local low=false -- refreshed per arrival
local function count(n:number):number return math.max(1,math.floor(n*(low and .35 or 1)+.5))end

type Step={Fn:(number,number)->boolean?,Start:number}
local Scope={}
Scope.__index=Scope
local function newScope(name:string)
 local folder=Instance.new('Folder');folder.Name=name;folder.Parent=fxRoot()
 local self=setmetatable({Folder=folder,Alive=true,Cleanups={},Steps={}::{Step}},Scope)
 self.Connection=Run.RenderStepped:Connect(function(dt)self:Step(dt)end)
 return self
end
function Scope:Step(dt:number)
 if not self.Alive then return end
 local now=os.clock();local steps=self.Steps;local i=1
 while i<=#steps do
  local s=steps[i]
  local ok,keep=pcall(s.Fn,dt,now-s.Start)
  if not ok then warn('LuckyArrivalFX step:',keep)end
  if not ok or keep==false then table.remove(steps,i)else i+=1 end
 end
end
function Scope:Add(x:any)table.insert(self.Cleanups,x);return x end
function Scope:Clean()
 if not self.Alive then return end
 self.Alive=false
 self.Connection:Disconnect()
 for i=#self.Cleanups,1,-1 do
  local x=self.Cleanups[i]
  local ok,err=pcall(function()
   if typeof(x)=='Instance'then x:Destroy()
   elseif typeof(x)=='RBXScriptConnection'then x:Disconnect()
   elseif type(x)=='function'then x()end
  end)
  if not ok then warn('LuckyArrivalFX cleanup:',err)end
 end
 table.clear(self.Cleanups);table.clear(self.Steps)
 self.Folder:Destroy()
end
-- Every(fn): fn(dt, age) each frame until it returns false or the scope ends.
function Scope:Every(fn:(number,number)->boolean?)
 table.insert(self.Steps,{Fn=fn,Start=os.clock()})
end
-- Life(o, seconds, step?): step(alpha 0..1) each frame, then destroy o.
function Scope:Life(o:Instance,seconds:number,step:((number)->())?)
 self:Every(function(_,age)
  local a=math.min(age/seconds,1)
  if step then step(a)end
  if a>=1 then o:Destroy();return false end
  return true
 end)
 return o
end
-- Later(t, fn): run fn after t seconds if the scope is still alive.
function Scope:Later(t:number,fn:()->())
 task.delay(t,function()
  if not self.Alive then return end
  local ok,err=pcall(fn)
  if not ok then warn('LuckyArrivalFX:',err)end
 end)
end
function Scope:Part(props:{[string]:any}):BasePart
 local p=Instance.new('Part')
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 p.Material=Enum.Material.Neon;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 for k,v in pairs(props)do if k~='Parent'then(p::any)[k]=v end end
 p.Parent=props.Parent or self.Folder
 return p
end
function Scope:Anchor(position:Vector3,name:string?):BasePart
 return self:Part({Name=name or'Anchor',Size=Vector3.one*.2,Position=position,Transparency=1})
end
function Scope:Light(parent:Instance,color:Color3,range:number,brightness:number):PointLight
 local l=Instance.new('PointLight');l.Color=color;l.Range=range;l.Brightness=brightness;l.Shadows=false;l.Parent=parent
 return l
end
function Scope:Emitter(parent:Instance,props:{[string]:any}?):ParticleEmitter
 local e=Instance.new('ParticleEmitter')
 e.Texture=SPARK;e.Rate=0;e.LightEmission=1;e.LightInfluence=0;e.Lifetime=NumberRange.new(.6,1.3)
 e.Speed=NumberRange.new(5,12);e.SpreadAngle=Vector2.new(180,180);e.Size=NumberSequence.new(.6,0)
 e.Transparency=NumberSequence.new(0,1);e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-180,180)
 for k,v in pairs(props or{})do(e::any)[k]=v end
 e.Parent=parent
 return e
end
-- A one-shot particle burst at a point.
function Scope:Burst(position:Vector3,color:any,n:number,props:{[string]:any}?):ParticleEmitter
 local a=self:Anchor(position,'Burst')
 local e=self:Emitter(a,props)
 e.Color=typeof(color)=='ColorSequence'and color or seq(color)
 e:Emit(count(n))
 Debris:AddItem(a,4)
 return e
end
-- A flat shockwave: neon segments on a circle growing r0 -> r1 and fading.
function Scope:Ring(center:Vector3,color:Color3,r0:number,r1:number,seconds:number,props:{[string]:any}?)
 local o=props or{}
 local n=low and 14 or(o.Segments or 28)
 local u,w=o.U or Vector3.xAxis,o.W or Vector3.zAxis
 local thick,height,alpha=o.Thickness or .4,o.Height or .22,o.Alpha or .05
 local model=Instance.new('Model');model.Name='Ring';model.Parent=self.Folder
 local parts={}
 for i=1,n do parts[i]=self:Part({Name='Segment',Color=color,Material=o.Material or Enum.Material.Neon,Size=Vector3.new(thick,height,1),Transparency=alpha,Parent=model})end
 local power=o.Ease or 3
 self:Life(model,seconds,function(a)
  local r=r0+(r1-r0)*(1-(1-a)^power)
  local width=2*math.pi*math.max(r,.05)/n*1.1
  local t=alpha+(1-alpha)*(a^(o.FadePower or 1.4))
  for i,p in ipairs(parts)do
   local t0,t1=(i-1)/n*math.pi*2,i/n*math.pi*2
   local a0=center+u*math.cos(t0)*r+w*math.sin(t0)*r
   local a1=center+u*math.cos(t1)*r+w*math.sin(t1)*r
   local up=u:Cross(w).Unit
   p.Size=Vector3.new(thick*(1-a*.5),height,width)
   p.CFrame=CFrame.lookAt((a0+a1)/2,a1,up)
   p.Transparency=t
  end
 end)
 return model
end
-- A flat glowing disc on the ground that grows and fades (the flash under a shockwave).
function Scope:Disc(center:Vector3,color:Color3,d0:number,d1:number,seconds:number,alpha:number?)
 local a0=alpha or .25
 local p=self:Part({Name='Disc',Shape=Enum.PartType.Cylinder,Color=color,Size=Vector3.new(.1,d0,d0),
  CFrame=CFrame.new(center)*CFrame.Angles(0,0,math.pi/2),Transparency=a0})
 self:Life(p,seconds,function(a)
  local d=d0+(d1-d0)*(1-(1-a)^2.5)
  p.Size=Vector3.new(.1,d,d);p.Transparency=a0+(1-a0)*a
 end)
 return p
end
-- A ball growing (or shrinking) s0 -> s1 while fading from alpha to 1.
function Scope:Sphere(center:Vector3,color:Color3,s0:number,s1:number,seconds:number,props:{[string]:any}?)
 local o=props or{}
 local a0=o.Alpha or .2
 local p=self:Part({Name=o.Name or'Sphere',Shape=Enum.PartType.Ball,Color=color,Material=o.Material or Enum.Material.Neon,
  Size=Vector3.one*s0,Position=center,Transparency=a0})
 local style=o.Ease or'Out'
 self:Life(p,seconds,function(a)
  local e=style=='In'and a^2.2 or 1-(1-a)^2.4
  p.Size=Vector3.one*math.max(.05,s0+(s1-s0)*e)
  p.Transparency=o.Hold and(a<.85 and a0 or a0+(1-a0)*(a-.85)/.15)or a0+(1-a0)*a^1.3
  if o.Step then o.Step(p,a)end
 end)
 return p
end
-- A vertical-ish light column from `from` to `to` that swells in, then out.
function Scope:Pillar(from:Vector3,to:Vector3,color:Color3,width:number,seconds:number,props:{[string]:any}?)
 local o=props or{}
 local length=(to-from).Magnitude
 local p=self:Part({Name='Pillar',Shape=Enum.PartType.Cylinder,Color=color,Material=o.Material or Enum.Material.Neon,
  Transparency=1,Size=Vector3.new(length,.1,.1)})
 local up=math.abs((to-from).Unit.Y)>.99 and Vector3.zAxis or Vector3.yAxis
 local base=CFrame.lookAt((from+to)/2,to,up)*CFrame.Angles(0,math.pi/2,0)
 local a0=o.Alpha or .25
 self:Life(p,seconds,function(a)
  local s=math.min(a*(o.In or 7),1)*math.min((1-a)*(o.Out or 2.5),1)
  local wob=1+math.sin(a*40)*.05
  p.Size=Vector3.new(length,width*s*wob+.05,width*s*wob+.05)
  p.CFrame=base*CFrame.Angles(a*6,0,0)
  p.Transparency=1-(1-a0)*s
 end)
 return p
end
-- A jittered electric arc from a to b that flickers out.
function Scope:Bolt(a:Vector3,b:Vector3,color:Color3,width:number,seconds:number)
 local model=Instance.new('Model');model.Name='Bolt';model.Parent=self.Folder
 local prev=a;local steps=7;local len=(b-a).Magnitude
 for i=1,steps do
  local at=a:Lerp(b,i/steps)
  if i<steps then at+=Vector3.new(rand(-1,1),rand(-1,1),rand(-1,1))*len*.09 end
  local seg=(at-prev).Magnitude
  if seg>.01 then
   self:Part({Name='Arc',Color=color,Size=Vector3.new(width,width,seg),CFrame=CFrame.lookAt((at+prev)/2,at),Parent=model})
  end
  prev=at
 end
 -- ReducedMotion: a plain fade instead of the random strobe.
 local calm=Show.ReducedMotion()
 self:Life(model,seconds,function(alpha)
  local flick=calm and alpha or(alpha<.7 and(rng:NextNumber()<.25 and .5 or 0)or alpha)
  for _,p in ipairs(model:GetChildren())do if p:IsA('BasePart')then p.Transparency=math.max(flick,alpha^2)end end
 end)
 return model
end
-- A star glint (billboard cross that blooms and turns), always facing the camera.
function Scope:Glint(position:Vector3,color:Color3,size:number,seconds:number)
 local a=self:Anchor(position,'Glint')
 local bb=Instance.new('BillboardGui');bb.Name='Glint';bb.Adornee=a;bb.LightInfluence=0;bb.Brightness=2.5
 bb.AlwaysOnTop=false;bb.Size=UDim2.fromScale(.01,.01);bb:SetAttribute('NoTranslate',true);bb.Parent=a
 local holder=Instance.new('Frame');holder.BackgroundTransparency=1;holder.Size=UDim2.fromScale(1,1);holder.Parent=bb
 local fade=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})
 local tint=seq({ColorSequenceKeypoint.new(0,color),ColorSequenceKeypoint.new(.5,WHITE),ColorSequenceKeypoint.new(1,color)})
 local function ray(w:number,h:number,rotation:number)
  local f=Instance.new('Frame');f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromScale(w,h)
  f.Rotation=rotation;f.BorderSizePixel=0;f.BackgroundColor3=WHITE;f.Parent=holder
  local g=Instance.new('UIGradient');g.Transparency=fade;g.Color=tint;g.Parent=f
 end
 ray(1,.07,0);ray(.07,1,0);ray(.55,.05,45);ray(.55,.05,-45)
 local core=Instance.new('Frame');core.AnchorPoint=Vector2.new(.5,.5);core.Position=UDim2.fromScale(.5,.5);core.Size=UDim2.fromScale(.2,.2)
 core.BackgroundColor3=WHITE;core.BorderSizePixel=0;core.Parent=holder
 local round=Instance.new('UICorner');round.CornerRadius=UDim.new(.5,0);round.Parent=core
 self:Life(a,seconds,function(t)
  local env=t<.22 and(t/.22)^.6 or(1-(t-.22)/.78)^1.6
  local s=math.max(.01,size*env)
  bb.Size=UDim2.fromScale(s,s);holder.Rotation=t*50
 end)
end
-- Ballistic debris (coins, shards, embers): parts thrown from `origin`, spinning, bouncing
-- once off the tongue, fading out.
function Scope:Toss(origin:Vector3,n:number,o:{[string]:any})
 local list={}
 for i=1,count(n)do
  local angle=rand(0,math.pi*2);local out=rand(o.Out[1],o.Out[2])
  local p=self:Part({Name=o.Name or'Debris',Shape=o.Shape or Enum.PartType.Block,Color=o.Colors and o.Colors[(i-1)%#o.Colors+1]or o.Color,
   Material=o.Material or Enum.Material.Neon,Size=o.Size,CFrame=CFrame.new(origin+Vector3.new(rand(-.6,.6),rand(0,.6),rand(-.6,.6)))})
  table.insert(list,{Part=p,V=Vector3.new(math.cos(angle)*out,rand(o.Up[1],o.Up[2]),math.sin(angle)*out+(o.Forward or 0)),
   Spin=Vector3.new(rand(-12,12),rand(-12,12),rand(-12,12)),Life=rand(o.Life*.8,o.Life),Bounced=false})
 end
 local gravity=o.Gravity or 46;local floor=o.Floor or(TONGUE_Y+.25);local ceiling=o.Ceiling or 22
 self:Every(function(dt,age)
  local alive=false
  for _,d in ipairs(list)do
   local p=d.Part
   if p.Parent then
    local a=age/d.Life
    if a>=1 then p:Destroy()else
     alive=true
     d.V+=Vector3.new(0,-gravity*dt,0)
     local pos=p.Position+d.V*dt
     if pos.Y<floor and d.V.Y<0 then
      if d.Bounced then pos=Vector3.new(pos.X,floor,pos.Z);d.V=Vector3.new(d.V.X*.6,0,d.V.Z*.6)
      else d.Bounced=true;pos=Vector3.new(pos.X,floor,pos.Z);d.V=Vector3.new(d.V.X*.55,-d.V.Y*.38,d.V.Z*.55)end
     end
     if pos.Y>ceiling then pos=Vector3.new(pos.X,ceiling,pos.Z);d.V=Vector3.new(d.V.X,math.min(d.V.Y,0),d.V.Z)end
     p.CFrame=CFrame.new(pos)*(p.CFrame-p.Position)*CFrame.Angles(d.Spin.X*dt,d.Spin.Y*dt,d.Spin.Z*dt)
     p.Transparency=a<.6 and 0 or(a-.6)/.4
    end
   end
  end
  return alive
 end)
end
-- A client-local property override (mouth runes, mist), restored on Clean. Through Kit's
-- layered overrides when available; otherwise restored only if nobody changed it since.
function Scope:Override(o:Instance?,props:{[string]:any})
 if not o then return end
 local k=kit()
 if k then
  if not self.KitScope then
   local ok,ks=pcall(k.Scope,'LuckyArrival')
   if ok and ks then self.KitScope=ks;self:Add(function()ks:Clean()end)end
  end
  if self.KitScope then self.KitScope:Override(o,props);return end
 end
 local saved={}
 for key,value in pairs(props)do
  local ok,old=pcall(function()return(o::any)[key]end)
  if ok then saved[key]=old;pcall(function()(o::any)[key]=value end)end
 end
 self:Add(function()
  if not o.Parent then return end
  for key,value in pairs(props)do
   local ok,current=pcall(function()return(o::any)[key]end)
   if ok and current==value and saved[key]~=nil then pcall(function()(o::any)[key]=saved[key]end)end
  end
 end)
end

---------------------------------------------------------------- sound
local speakers:Folder?=nil
local function cue(name:string,position:Vector3?,...)
 local parent:Instance?=nil
 if position then
  if not speakers or not speakers.Parent then
   local f=Instance.new('Folder');f.Name='ArrivalSpeakers';f.Parent=fxRoot();speakers=f
  end
  local p=Instance.new('Part');p.Name='Speaker';p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
  p.Transparency=1;p.Size=Vector3.one*.2;p.Position=position;p.Parent=speakers
  Debris:AddItem(p,10);parent=p
 end
 local ok,err=pcall(Audio.Play,name,parent,...)
 if not ok then warn('LuckyArrivalFX sound:',err)end
end

---------------------------------------------------------------- camera & screen
local function cameraDistance(position:Vector3):number
 local c=workspace.CurrentCamera
 return c and(c.CFrame.Position-position).Magnitude or math.huge
end
local function nearness(position:Vector3,radius:number):number
 return math.clamp(1-cameraDistance(position)/radius,0,1)
end
-- A Secret DOG cinematic owns the screen and camera while it runs.
local function secretDogBusy():boolean
 local now=serverNow()
 for _,e in ipairs(active:GetChildren())do
  local hold=e:GetAttribute('ArrivalHoldUntil')
  if type(hold)=='number'and hold>now then return true end
 end
 local reveals=workspace:FindFirstChild('DOGROTS_SecretReveals')
 if reveals then
  for _,e in ipairs(reveals:GetChildren())do
   local hold=e:GetAttribute('ArrivalHoldUntil')
   if type(hold)=='number'and hold>now then return true end
  end
 end
 return false
end
local function modalOpen():boolean
 local gui=player:FindFirstChildOfClass('PlayerGui')
 local main=gui and gui:FindFirstChild('ScreenGui')
 return main~=nil and((main:GetAttribute('ModalOwnerCount')or 0)>0 or main:GetAttribute('OpenMenu')~=nil)
end
-- Camera/screen layers: never on Low, ReducedMotion, a scripted camera or a Secret cinematic.
local function cameraAllowed():boolean
 return not low and not Show.ReducedMotion()and Show.CameraFree()and not secretDogBusy()
end
-- Same protocol as SecretArrivals.Kit.FOVPunch: the camera's SecretZoom attribute holds the
-- true FOV while it runs, and any other FOV writer wins at once.
local function fovPunch(delta:number,inSeconds:number,outSeconds:number)
 if math.abs(delta)<.3 or not cameraAllowed()then return end
 local c=workspace.CurrentCamera;if not c then return end
 local base=c.FieldOfView
 c:SetAttribute('SecretZoom',base)
 local peak=math.clamp(base+delta,20,110)
 local written=base;local started=os.clock();local connection
 connection=Run.RenderStepped:Connect(function()
  local age=os.clock()-started
  if not c.Parent or math.abs(c.FieldOfView-written)>.01 or c.CameraType==Enum.CameraType.Scriptable then
   connection:Disconnect();c:SetAttribute('SecretZoom',nil);return
  end
  local a
  if age<inSeconds then a=1-(1-age/inSeconds)^2 else a=1-math.min((age-inSeconds)/outSeconds,1);a=a*a*(3-2*a)end
  written=base+(peak-base)*a;c.FieldOfView=written
  if age>=inSeconds+outSeconds then c.FieldOfView=base;connection:Disconnect();c:SetAttribute('SecretZoom',nil)end
 end)
end
local screenGui:ScreenGui?=nil
local function screen():ScreenGui?
 if screenGui and screenGui.Parent then return screenGui end
 local pg=player:FindFirstChildOfClass('PlayerGui');if not pg then return nil end
 local g=Instance.new('ScreenGui');g.Name='DOGROTS_LuckyArrivalScreen';g.ResetOnSpawn=false;g.IgnoreGuiInset=true
 g.DisplayOrder=38;g:SetAttribute('NoTranslate',true);g.Parent=pg
 screenGui=g
 return g
end
local function flash(color:Color3,alpha:number,seconds:number)
 local g=screen();if not g then return end
 local f=Instance.new('Frame');f.Name='Flash';f.BorderSizePixel=0;f.Size=UDim2.fromScale(1,1);f.BackgroundColor3=color
 f.BackgroundTransparency=alpha;f.Parent=g
 local t=TweenService:Create(f,TweenInfo.new(seconds,Enum.EasingStyle.Quad),{BackgroundTransparency=1})
 t.Completed:Connect(function()f:Destroy()end);t:Play()
end
-- Screen tint + cinema bars, removed with the scope.
function Scope:Cinema(tint:Color3,seconds:number)
 local c=workspace.CurrentCamera;local g=screen()
 if not c or not g then return end
 local cc=Instance.new('ColorCorrectionEffect');cc.Name='DOGROTS_LuckyGrade';cc.Parent=c
 TweenService:Create(cc,TweenInfo.new(.35),{TintColor=tint,Saturation=-.2,Contrast=.18,Brightness=-.03}):Play()
 local bars={}
 for i,anchor in ipairs({0,1})do
  local b=Instance.new('Frame');b.Name='Letterbox';b.BorderSizePixel=0;b.BackgroundColor3=Color3.new(0,0,0)
  b.AnchorPoint=Vector2.new(0,anchor);b.Position=UDim2.fromScale(0,anchor);b.Size=UDim2.fromScale(1,0);b.Parent=g
  TweenService:Create(b,TweenInfo.new(.45,Enum.EasingStyle.Quad),{Size=UDim2.fromScale(1,i==1 and .085 or .05)}):Play()
  bars[i]=b
 end
 local done=false
 local function release()
  if done then return end
  done=true
  local t=TweenService:Create(cc,TweenInfo.new(.8),{TintColor=WHITE,Saturation=0,Contrast=0,Brightness=0})
  t.Completed:Connect(function()cc:Destroy()end);t:Play()
  for _,b in ipairs(bars)do
   local bt=TweenService:Create(b,TweenInfo.new(.6,Enum.EasingStyle.Quad),{Size=UDim2.fromScale(1,0)})
   bt.Completed:Connect(function()b:Destroy()end);bt:Play()
  end
 end
 self:Add(release)
 task.delay(seconds,release)
end

---------------------------------------------------------------- island banner (Mythic/Secret)
local bannerGui:ScreenGui?=nil
local function banner(rank:number)
 -- The roulette / menus and a Secret DOG's island-wide layer keep the screen to themselves.
 if modalOpen()or secretDogBusy()then return end
 local pg=player:FindFirstChildOfClass('PlayerGui');if not pg then return end
 if bannerGui then bannerGui:Destroy();bannerGui=nil end
 local ru=russian()
 local secret=rank>=6
 local title=(ru and Show.Names.RU[rank]or Show.Names.EN[rank])..(ru and' ЛАКИ-БЛОК!'or' LUCKY BLOCK!')
 local sub=secret and(ru and'ПУСТОТА ОТКРЫЛАСЬ НА ЯЗЫКЕ!'or'THE VOID OPENED ON THE TONGUE!')or(ru and'НА ЯЗЫКЕ — СКОРЕЕ!'or'ON THE TONGUE — HURRY!')
 local color,accent=Show.World[rank],Show.Accent[rank]
 local gui=Instance.new('ScreenGui');gui.Name='DOGROTS_LuckyArrivalBanner';gui.ResetOnSpawn=false;gui.DisplayOrder=39
 gui:SetAttribute('NoTranslate',true);gui.Parent=pg;bannerGui=gui
 local card=Instance.new('Frame');card.Name='Banner';card.AnchorPoint=Vector2.new(.5,0);card.Position=UDim2.new(.5,0,0,-140)
 card.Size=UDim2.fromOffset(470,92);card.BackgroundColor3=WHITE;card.BorderSizePixel=0;card.Parent=gui
 local cam=workspace.CurrentCamera
 local scale=Instance.new('UIScale');scale.Scale=math.clamp(((cam and cam.ViewportSize.X or 800)-24)/470,.55,1);scale.Parent=card
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,20);corner.Parent=card
 local stroke=Instance.new('UIStroke');stroke.Color=NAVY;stroke.Thickness=4;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=card
 local grad=Instance.new('UIGradient');grad.Rotation=90
 grad.Color=secret and seq({ColorSequenceKeypoint.new(0,Color3.fromRGB(70,30,140)),ColorSequenceKeypoint.new(.55,Color3.fromRGB(18,8,40)),ColorSequenceKeypoint.new(1,Color3.fromRGB(40,10,80))})
  or seq({ColorSequenceKeypoint.new(0,color:Lerp(WHITE,.35)),ColorSequenceKeypoint.new(.6,color),ColorSequenceKeypoint.new(1,color:Lerp(Color3.new(0,0,0),.25))})
 grad.Parent=card
 -- A shine sweeping across the card.
 local shine=Instance.new('Frame');shine.Name='Shine';shine.BackgroundColor3=WHITE;shine.BorderSizePixel=0;shine.Size=UDim2.fromScale(1,1)
 shine.BackgroundTransparency=0;shine.ZIndex=2;shine.Parent=card
 local sc=Instance.new('UICorner');sc.CornerRadius=UDim.new(0,20);sc.Parent=shine
 local sg=Instance.new('UIGradient');sg.Rotation=20;sg.Offset=Vector2.new(-1.2,0)
 sg.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.42,1),NumberSequenceKeypoint.new(.5,.45),NumberSequenceKeypoint.new(.58,1),NumberSequenceKeypoint.new(1,1)})
 sg.Parent=shine
 local function label(name:string,text:string,y:number,h:number,size:number,textColor:Color3)
  local l=Instance.new('TextLabel');l.Name=name;l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(.5,0)
  l.Position=UDim2.new(.5,0,0,y);l.Size=UDim2.new(1,-70,0,h);l.Font=Enum.Font.FredokaOne;l.Text=text;l.TextColor3=textColor
  l.TextScaled=true;l.TextStrokeColor3=NAVY;l.TextStrokeTransparency=0;l.ZIndex=3;l:SetAttribute('NoTranslate',true)
  local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=size;limit.Parent=l
  local ls=Instance.new('UIStroke');ls.Color=NAVY;ls.Thickness=2.5;ls.Parent=l
  l.Parent=card
  return l
 end
 local head=label('Title',title,8,46,38,secret and Color3.fromRGB(235,215,255)or WHITE)
 label('Subtitle',sub,54,28,22,secret and accent or Color3.fromRGB(255,250,225))
 -- Spinning diamond sparkles at both ends.
 local gems={}
 for i,x in ipairs({0,1})do
  local d=Instance.new('Frame');d.Name='Gem';d.AnchorPoint=Vector2.new(.5,.5);d.Position=UDim2.new(x,x==0 and 32 or-32,.5,0)
  d.Size=UDim2.fromOffset(24,24);d.BackgroundColor3=accent;d.BorderSizePixel=0;d.Rotation=45;d.ZIndex=3;d.Parent=card
  local dc=Instance.new('UICorner');dc.CornerRadius=UDim.new(0,5);dc.Parent=d
  local ds=Instance.new('UIStroke');ds.Color=NAVY;ds.Thickness=3;ds.Parent=d
  gems[i]=d
 end
 TweenService:Create(card,TweenInfo.new(.55,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,64)}):Play()
 local still=Show.ReducedMotion()
 local started=os.clock()
 local connection;connection=Run.RenderStepped:Connect(function()
  if not gui.Parent then connection:Disconnect();return end
  local t=os.clock()-started
  sg.Offset=Vector2.new(-1.2+((t*.9)%1.6)*1.5,0)
  for i,d in ipairs(gems)do d.Rotation=45+t*(i==1 and 120 or-120)end
  if secret and not still then
   head.Position=t<.9 and UDim2.new(.5,math.random(-3,3),0,8+math.random(-2,2))or UDim2.new(.5,0,0,8)
   head.TextColor3=(t<.9 and math.random()<.3)and accent or Color3.fromRGB(235,215,255)
  end
 end)
 task.delay(3.6,function()
  if not gui.Parent then return end
  local t=TweenService:Create(card,TweenInfo.new(.4,Enum.EasingStyle.Back,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-140)})
  t.Completed:Connect(function()gui:Destroy();if bannerGui==gui then bannerGui=nil end end);t:Play()
 end)
 Debris:AddItem(gui,6)
end

---------------------------------------------------------------- line state
local speedCache,speedAt=Stream.Speed,-1
-- The tongue's current speed (same rules as DogLineSpawner's Heartbeat), cached briefly.
local function lineSpeed():number
 local t=os.clock()
 if t-speedAt<.2 then return speedCache end
 speedAt=t
 local now=serverNow();local frozen=false;local slowest=1
 for _,e in ipairs(active:GetChildren())do
  if e:GetAttribute('State')=='OnLine'then
   local hold=e:GetAttribute('ArrivalHoldUntil')
   if e:GetAttribute('FreezeLine')and type(hold)=='number'and hold>now then frozen=true end
   local s=e:GetAttribute('LineSpeedScale')
   if type(s)=='number'then slowest=math.min(slowest,s)end
  end
 end
 speedCache=Timing.Speed(Stream.Speed,line:GetAttribute('EventLineScale'),slowest,frozen)
 return speedCache
end
local function rootOf(model:Model):BasePart?
 if not model.Parent then return nil end
 local r=model.PrimaryPart or model:FindFirstChild('RootPart')
 if r and r:IsA('BasePart')and r.Parent then return r end
 return nil
end

---------------------------------------------------------------- per-block context
type Ctx={Model:Model,Rank:number,Color:Color3,Accent:Color3,Scope:any,Z:number,X:number,Y:number}
local function present(ctx:Ctx):boolean
 return ctx.Model.Parent~=nil and ctx.Model:IsDescendantOf(active)
end
local function pos(ctx:Ctx):Vector3 return Vector3.new(ctx.X,ctx.Y,ctx.Z)end
-- Where the lip FX play: the lip, or the block itself when we are already late.
local function lipPoint(ctx:Ctx,y:number?):Vector3
 return Vector3.new(ctx.X,y or CENTRE_Y,math.clamp(ctx.Z,LIP-.5,LIP+16))
end
-- Yield until the block centre reaches z. False if the scope ended, the block left the
-- line (bought, streamed out) or it took longer than `timeout`.
local function waitZ(ctx:Ctx,z:number,timeout:number?):boolean
 local deadline=os.clock()+(timeout or 45)
 while ctx.Scope.Alive and os.clock()<deadline do
  if not present(ctx)then return false end
  if ctx.Z>=z then return true end
  task.wait()
 end
 return false
end
-- Yield until the block is `seconds` (at the current tongue speed) from the lip.
local function waitEta(ctx:Ctx,seconds:number,timeout:number?):boolean
 local deadline=os.clock()+(timeout or 45)
 while ctx.Scope.Alive and os.clock()<deadline do
  if not present(ctx)then return false end
  if Timing.Eta(ctx.Z,LIP,lineSpeed())<=seconds then return true end
  task.wait()
 end
 return false
end
-- An invisible anchor riding with the block (lights, fountains) until the scope ends.
local function follower(ctx:Ctx,offset:Vector3,name:string):BasePart
 local s=ctx.Scope
 local a=s:Anchor(pos(ctx)+offset,name)
 s:Every(function()
  if not a.Parent then return false end
  a.Position=pos(ctx)+offset
  return true
 end)
 return a
end
local function fadeLight(scope:any,l:PointLight,from:number,seconds:number,delay:number?)
 local started:number?=nil
 scope:Every(function(_,age)
  if not l.Parent then return false end
  local t=age-(delay or 0)
  if t<0 then return true end
  started=started or age
  local a=math.min(t/seconds,1)
  l.Brightness=from*(1-a)^1.5
  return a<1
 end)
end
-- Rising helix of rune sparks around the block (Epic).
local function runeSpiral(ctx:Ctx,n:number,seconds:number,colors:{Color3})
 local s=ctx.Scope
 local sparks={}
 for i=1,count(n)do
  local p=s:Part({Name='RuneSpark',Color=colors[(i-1)%#colors+1],Size=Vector3.new(.38,.38,.38),Position=pos(ctx)})
  if not low then
   local a0=Instance.new('Attachment');a0.Position=Vector3.new(0,.15,0);a0.Parent=p
   local a1=Instance.new('Attachment');a1.Position=Vector3.new(0,-.15,0);a1.Parent=p
   local tr=Instance.new('Trail');tr.Attachment0=a0;tr.Attachment1=a1;tr.Lifetime=.28;tr.LightEmission=1;tr.LightInfluence=0
   tr.Color=seq(p.Color);tr.Transparency=NumberSequence.new(.1,1);tr.WidthScale=NumberSequence.new(1,0);tr.FaceCamera=true;tr.Parent=p
  end
  sparks[i]=p
 end
 local total=#sparks
 s:Every(function(_,age)
  local a=age/seconds
  if a>=1 then for _,p in ipairs(sparks)do p:Destroy()end;return false end
  local c=pos(ctx)
  for i,p in ipairs(sparks)do
   local ang=i/total*math.pi*2+age*(5.5+i%3)
   local r=3.1-a*1.2+math.sin(age*9+i)*.25
   local y=-2.2+a*8.5+(i%2)*.4
   p.CFrame=CFrame.new(c+Vector3.new(math.cos(ang)*r,y,math.sin(ang)*r))*CFrame.Angles(age*7,age*5,0)
   p.Transparency=a<.7 and 0 or(a-.7)/.3
  end
  return true
 end)
end
-- Crown-jewel lightning from the block's crown down onto the tongue (Mythic).
local function jewelBolts(ctx:Ctx,waves:number,perWave:number)
 local s=ctx.Scope
 for w=0,waves-1 do
  s:Later(w*.13,function()
   local top=pos(ctx)+Vector3.new(0,3.4,0)
   for i=1,count(perWave)do
    local ang=rand(0,math.pi*2);local r=rand(5,9.5)
    local target=Vector3.new(top.X+math.cos(ang)*r,TONGUE_Y+.1,top.Z+math.sin(ang)*r)
    local jewel=Color3.fromHSV(((i+w*3)/8)%1,.65,1)
    s:Bolt(top,target,jewel,.24,.22)
    s:Burst(target,seq(jewel,WHITE),5,{Speed=NumberRange.new(3,8),Size=NumberSequence.new(.4,0),Lifetime=NumberRange.new(.25,.5)})
   end
  end)
 end
end

---------------------------------------------------------------- tiers
local Tiers={}

Tiers[1]=function(ctx:Ctx)
 if not waitZ(ctx,LIP-1.2)then return end
 local s=ctx.Scope;local at=lipPoint(ctx)
 s:Glint(at+Vector3.new(1.3,1.9,1.4),WHITE,3.4,.6)
 s:Burst(Vector3.new(at.X,TONGUE_Y+.3,at.Z+1.4),Color3.fromRGB(236,226,206),7,{Texture=SMOKE,LightEmission=0,
  Size=NumberSequence.new(1.1,2.8),Transparency=NumberSequence.new(.55,1),Speed=NumberRange.new(2,5),Drag=3,
  Lifetime=NumberRange.new(.6,1),SpreadAngle=Vector2.new(80,15)})
 s:Burst(at+Vector3.new(0,1,0),seq(WHITE,ctx.Accent),8,{Size=NumberSequence.new(.35,0),Speed=NumberRange.new(4,9),Lifetime=NumberRange.new(.4,.8)})
 cue('Tick',at,1.9)
 task.wait(1.4)
end

Tiers[2]=function(ctx:Ctx)
 if not waitZ(ctx,LIP-1.2)then return end
 local s=ctx.Scope;local at=lipPoint(ctx);local ground=Vector3.new(at.X,TONGUE_Y,at.Z)
 s:Ring(ground,ctx.Color,1.5,9,.75,{Thickness=.4})
 s:Later(.14,function()s:Ring(ground,ctx.Accent,1,6.5,.6,{Thickness=.25})end)
 s:Later(.3,function()s:Ring(ground,ctx.Color:Lerp(WHITE,.4),.8,4.5,.5,{Thickness=.2})end)
 s:Disc(ground+Vector3.new(0,.02,0),ctx.Color,2,9,.45,.45)
 s:Glint(at+Vector3.new(1.2,2,1.5),ctx.Accent,4.8,.65)
 s:Burst(at+Vector3.new(0,1,0),seq(ctx.Color,ctx.Accent),26,{Size=NumberSequence.new(.5,0),Speed=NumberRange.new(6,14),Lifetime=NumberRange.new(.5,1.1),Drag=2})
 cue('Arrive',at,2)
 task.wait(1.6)
end

Tiers[3]=function(ctx:Ctx)
 if not waitZ(ctx,LIP-1.4)then return end
 local s=ctx.Scope;local at=lipPoint(ctx);local ground=Vector3.new(at.X,TONGUE_Y,at.Z)
 s:Ring(ground,ctx.Color,1.5,10,.85,{Thickness=.55})
 s:Later(.18,function()s:Ring(ground+Vector3.new(0,.05,0),ctx.Accent,1,8,.75,{Thickness=.35})end)
 s:Disc(ground+Vector3.new(0,.02,0),ctx.Color,2,10,.5,.35)
 runeSpiral(ctx,10,1.35,{ctx.Color,ctx.Accent,WHITE})
 local flashAnchor=s:Anchor(at+Vector3.new(0,3,0),'Flash')
 fadeLight(s,s:Light(flashAnchor,ctx.Accent,24,5),5,.55)
 s:Glint(at+Vector3.new(1.4,2.2,1.5),ctx.Accent,6,.7)
 s:Burst(at+Vector3.new(0,1,0),seq(ctx.Color,ctx.Accent),36,{Size=NumberSequence.new(.55,0),Speed=NumberRange.new(7,16),Lifetime=NumberRange.new(.5,1.2),Drag=2})
 cue('Arrive',at,3)
 task.wait(2)
end

local GOLD=Color3.fromRGB(255,205,70)
Tiers[4]=function(ctx:Ctx)
 if not waitZ(ctx,LIP-1.4)then return end
 local s=ctx.Scope;local at=lipPoint(ctx);local ground=Vector3.new(at.X,TONGUE_Y,at.Z)
 s:Ring(ground,GOLD,1.5,13,1,{Thickness=.7,Height=.3})
 s:Later(.12,function()s:Ring(ground+Vector3.new(0,.05,0),Color3.fromRGB(255,248,200),1,16,1.1,{Thickness=.3,Alpha=.35})end)
 s:Disc(ground+Vector3.new(0,.02,0),GOLD,2,13,.5,.25)
 s:Glint(at+Vector3.new(1.5,2.4,1.6),Color3.fromRGB(255,230,140),7,.75)
 -- Gold coins tossed out of the block, plus a sparkle fountain riding on it.
 s:Toss(at+Vector3.new(0,2.3,0),14,{Name='Coin',Shape=Enum.PartType.Cylinder,Color=GOLD,Size=Vector3.new(.16,1,1),
  Up={15,21},Out={2,6.5},Life=1.5,Gravity=46,Ceiling=20})
 local top=follower(ctx,Vector3.new(0,2.6,0),'Fountain')
 local fountain=s:Emitter(top,{Color=seq(Color3.fromRGB(255,240,170),GOLD),Size=NumberSequence.new(.55,0),Speed=NumberRange.new(14,22),
  SpreadAngle=Vector2.new(22,22),Acceleration=Vector3.new(0,-38,0),EmissionDirection=Enum.NormalId.Top,Lifetime=NumberRange.new(.9,1.4),Rate=low and 14 or 45})
 s:Later(1.05,function()fountain.Enabled=false end)
 -- Warm glow under the head while the block rides out.
 local glow=s:Light(follower(ctx,Vector3.new(0,1.5,0),'Glow'),Color3.fromRGB(255,190,90),16,2.4)
 cue('Arrive',at,4)
 if not waitZ(ctx,HEAD_CLEAR+1,30)then fadeLight(s,glow,2.4,.8);task.wait(1);return end
 local base=Vector3.new(ctx.X,TONGUE_Y,ctx.Z)
 s:Pillar(base,base+Vector3.new(0,70,0),GOLD,4.6,1.9,{Alpha=.3})
 s:Pillar(base,base+Vector3.new(0,70,0),Color3.fromRGB(255,252,225),1.6,1.9,{Alpha=.05})
 s:Ring(base,GOLD,1,8,.8,{Thickness=.5})
 s:Burst(base+Vector3.new(0,1,0),seq(Color3.fromRGB(255,250,210),GOLD),20,{EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(14,14),
  Speed=NumberRange.new(16,30),Lifetime=NumberRange.new(.8,1.5),Size=NumberSequence.new(.6,0)})
 cue('Reveal',base+Vector3.new(0,3,0),4)
 fadeLight(s,glow,2.4,1.6)
 task.wait(2)
end

local CRIMSON=Color3.fromRGB(255,40,80)
Tiers[5]=function(ctx:Ctx)
 if not waitZ(ctx,LIP-1.5)then return end
 local s=ctx.Scope;local at=lipPoint(ctx);local ground=Vector3.new(at.X,TONGUE_Y,at.Z)
 s:Ring(ground,CRIMSON,1.5,14,1.1,{Thickness=.8,Height=.32})
 s:Later(.16,function()s:Ring(ground+Vector3.new(0,.06,0),GOLD,1,11,.95,{Thickness=.55,Height=.28})end)
 s:Later(.32,function()s:Ring(ground+Vector3.new(0,.1,0),Color3.fromRGB(255,240,200),.8,17,1.1,{Thickness=.25,Alpha=.4})end)
 s:Disc(ground+Vector3.new(0,.02,0),CRIMSON,2,15,.55,.2)
 s:Sphere(ground,CRIMSON,2,16,.55,{Alpha=.35})
 s:Glint(at+Vector3.new(1.6,3.6,1.6),Color3.fromRGB(255,215,140),8.5,.8)
 jewelBolts(ctx,4,low and 2 or 4)
 -- Ember fountain riding the block.
 local top=follower(ctx,Vector3.new(0,3,0),'Embers')
 local embers=s:Emitter(top,{Texture=FIRE,Color=seq(Color3.fromRGB(255,230,120),CRIMSON),Size=NumberSequence.new(.8,0),Speed=NumberRange.new(18,27),
  SpreadAngle=Vector2.new(28,28),Acceleration=Vector3.new(0,-30,0),EmissionDirection=Enum.NormalId.Top,Lifetime=NumberRange.new(.9,1.5),Rate=low and 26 or 90})
 local sparks=s:Emitter(top,{Color=seq(GOLD,Color3.fromRGB(255,120,80)),Size=NumberSequence.new(.45,0),Speed=NumberRange.new(14,24),
  SpreadAngle=Vector2.new(35,35),Acceleration=Vector3.new(0,-34,0),EmissionDirection=Enum.NormalId.Top,Lifetime=NumberRange.new(.8,1.3),Rate=low and 14 or 50})
 s:Later(1.25,function()embers.Enabled=false;sparks.Enabled=false end)
 s:Toss(at+Vector3.new(0,2.5,0),12,{Name='Coin',Shape=Enum.PartType.Cylinder,Colors={GOLD,CRIMSON},Size=Vector3.new(.16,1.05,1.05),
  Up={16,23},Out={2.5,7.5},Life=1.6,Ceiling=22})
 local flashAnchor=s:Anchor(at+Vector3.new(0,4,0),'Flash')
 fadeLight(s,s:Light(flashAnchor,CRIMSON,32,6),6,.75)
 local glow=s:Light(follower(ctx,Vector3.new(0,1.5,0),'Glow'),Color3.fromRGB(255,110,90),18,2.6)
 cue('Arrive',at,5)
 if cameraAllowed()then
  fovPunch(7*nearness(at,150),.12,.6)
 end
 banner(5)
 if not waitZ(ctx,HEAD_CLEAR+2.5,30)then fadeLight(s,glow,2.6,.8);task.wait(1);return end
 local base=Vector3.new(ctx.X,TONGUE_Y,ctx.Z)
 s:Pillar(base,base+Vector3.new(0,400,0),CRIMSON,7.5,3.2,{Alpha=.25,Out=2})
 s:Pillar(base,base+Vector3.new(0,400,0),GOLD,2.8,3.2,{Alpha=.05,Out=2})
 s:Pillar(base,base+Vector3.new(0,400,0),WHITE,.9,3.2,{Alpha=0,Out=2})
 s:Ring(base,GOLD,1,12,.9,{Thickness=.6})
 s:Later(.15,function()s:Ring(base+Vector3.new(0,.05,0),CRIMSON,1,9,.8,{Thickness=.45})end)
 -- Embers spiralling up the beam.
 local climbers={}
 for i=1,count(8)do climbers[i]=s:Part({Name='Climber',Color=i%2==0 and GOLD or CRIMSON,Size=Vector3.one*.6,Position=base})end
 s:Every(function(_,age)
  local a=age/2.6
  if a>=1 then for _,p in ipairs(climbers)do p:Destroy()end;return false end
  for i,p in ipairs(climbers)do
   local ang=i/#climbers*math.pi*2+age*4
   p.Position=base+Vector3.new(math.cos(ang)*4.6,age*55+i*3,math.sin(ang)*4.6)
   p.Transparency=a^2
  end
  return true
 end)
 s:Burst(base+Vector3.new(0,1,0),seq(Color3.fromRGB(255,230,120),CRIMSON),28,{Texture=FIRE,EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(18,18),
  Speed=NumberRange.new(20,34),Lifetime=NumberRange.new(.8,1.5),Size=NumberSequence.new(.9,0)})
 cue('Reveal',base+Vector3.new(0,3,0),5)
 fadeLight(s,glow,2.6,2)
 task.wait(3.2)
end

local VIOLET=Color3.fromRGB(150,72,255)
local CYAN=Color3.fromRGB(70,255,226)
local VOID=Color3.fromRGB(14,4,28)
-- The mouth glows violet: runes flick on from the throat outwards, the mist darkens, and a
-- violet light breathes out of the mouth. Restored when the returned scope is cleaned.
local function violetMouth(ctx:Ctx)
 local mouth=newScope('LuckySecretMouth')
 ctx.Scope:Add(function()mouth:Clean()end)
 local factory=district:FindFirstChild('02_DogFactory')
 local tunnel=factory and factory:FindFirstChild('DarkMouthTunnel')
 if tunnel and not secretDogBusy()then
  local runes={}
  for _,o in ipairs(tunnel:GetChildren())do
   if o.Name=='MouthRune'and o:IsA('BasePart')then table.insert(runes,o)
   elseif o.Name=='MouthMist'then
    for _,e in ipairs(o:GetChildren())do
     if e:IsA('ParticleEmitter')then mouth:Override(e,{Color=seq(VIOLET,VOID)})end
    end
   end
  end
  table.sort(runes,function(a,b)return a.Position.Z<b.Position.Z end)
  for i,rune in ipairs(runes)do
   mouth:Later(math.floor((i-1)/2)*.12,function()if rune.Parent then mouth:Override(rune,{Color=VIOLET})end end)
  end
 end
 local glowAnchor=mouth:Anchor(Vector3.new(0,10,-152),'MouthGlow')
 local glow=mouth:Light(glowAnchor,VIOLET,34,0)
 mouth:Every(function(_,age)
  if not glow.Parent then return false end
  glow.Brightness=math.min(age/1.6,1)*(2.6+math.sin(age*7)*.6)
  return true
 end)
 local breath=mouth:Emitter(mouth:Anchor(Vector3.new(0,5,-151),'VoidBreath'),{Texture=SMOKE,Color=seq(VIOLET,VOID),LightEmission=.2,
  Size=NumberSequence.new(2,5),Transparency=NumberSequence.new(.55,1),Speed=NumberRange.new(3,6),SpreadAngle=Vector2.new(35,20),
  EmissionDirection=Enum.NormalId.Back,Lifetime=NumberRange.new(1.2,2),Rate=low and 5 or 14,Drag=1})
 mouth:Add(function()breath.Enabled=false end)
 return mouth
end
-- The void sucks everything into a point at the lip.
local function implosion(ctx:Ctx,center:Vector3,seconds:number)
 local s=ctx.Scope
 s:Sphere(center,VIOLET,22,1,seconds,{Material=Enum.Material.ForceField,Alpha=.05,Ease='In',Hold=true})
 local still=Show.ReducedMotion()
 s:Sphere(center,VOID,9,.6,seconds,{Material=Enum.Material.Glass,Alpha=.12,Ease='In',Hold=true,Step=function(p:BasePart,a:number)
  -- Inverted colours: the core strobes black / white as it collapses (steady on reduced motion).
  if still then p.Color=VOID else p.Color=(math.floor(a*seconds/.07)%2==0)and VOID or Color3.fromRGB(240,232,255)end
 end})
 local shell=s:Part({Name='Suction',Shape=Enum.PartType.Ball,Size=Vector3.one*20,Position=center,Transparency=1})
 local inward=s:Emitter(shell,{Shape=Enum.ParticleEmitterShape.Sphere,ShapeInOut=Enum.ParticleEmitterShapeInOut.Inward,
  ShapeStyle=Enum.ParticleEmitterShapeStyle.Surface,Speed=NumberRange.new(14,16),Lifetime=NumberRange.new(.6,.7),
  Color=seq(CYAN,VIOLET),Size=NumberSequence.new(.5,.05),Transparency=NumberSequence.new(.1,.6),Rate=low and 35 or 120})
 local smoke=s:Emitter(shell,{Texture=SMOKE,Shape=Enum.ParticleEmitterShape.Sphere,ShapeInOut=Enum.ParticleEmitterShapeInOut.Inward,
  ShapeStyle=Enum.ParticleEmitterShapeStyle.Surface,Speed=NumberRange.new(12,14),Lifetime=NumberRange.new(.65,.75),LightEmission=0,
  Color=seq(VOID),Size=NumberSequence.new(3,.5),Transparency=NumberSequence.new(.4,.9),Rate=low and 6 or 20})
 s:Later(seconds,function()inward.Enabled=false;smoke.Enabled=false end)
 -- Arcs crawling inward from the shell.
 local waves=math.floor(seconds/.1)
 for w=0,waves-1 do
  s:Later(w*.1,function()
   for _=1,(low and 1 or 2)do
    local dir=Vector3.new(rand(-1,1),rand(-.6,1),rand(-1,1))
    if dir.Magnitude<.1 then dir=Vector3.xAxis end
    local r=9*(1-w/waves*.6)
    s:Bolt(center+dir.Unit*r,center,rng:NextNumber()<.5 and CYAN or VIOLET,.16,.12)
   end
  end)
 end
end
-- The void bursts out along the tongue.
local function explosion(ctx:Ctx,center:Vector3)
 local s=ctx.Scope
 local ground=Vector3.new(center.X,TONGUE_Y,center.Z)
 local calm=Show.ReducedMotion() -- no white flash, no blinking cracks
 if not calm then s:Sphere(center,WHITE,2,18,.42,{Alpha=0})end
 s:Sphere(center,VIOLET,3,24,.7,{Material=Enum.Material.ForceField,Alpha=0})
 s:Ring(ground+Vector3.new(0,.08,0),VOID,1.5,16,1.15,{Thickness=1,Height=.35,Material=Enum.Material.SmoothPlastic,Alpha=.05})
 s:Ring(ground+Vector3.new(0,.12,0),VIOLET,2,17.5,1.15,{Thickness=.5,Height=.3})
 s:Later(.1,function()s:Ring(ground+Vector3.new(0,.16,0),CYAN,1,21,.7,{Thickness=.25,Alpha=.2})end)
 s:Disc(ground+Vector3.new(0,.02,0),VIOLET,3,18,.6,.15)
 -- A shock front racing down the tongue.
 for i,c in ipairs({VIOLET,CYAN})do
  s:Later((i-1)*.15,function()
   local bar=s:Part({Name='ShockFront',Color=c,Size=Vector3.new(20,.25,.8),Position=ground+Vector3.new(0,.1,1)})
   s:Life(bar,1.3,function(a)
    bar.Position=ground+Vector3.new(0,.1+math.sin(a*math.pi)*.4,1+a*85*(1-a*.35))
    bar.Size=Vector3.new(20,.25,.8+a*2.4);bar.Transparency=a^1.2
   end)
  end)
 end
 -- Reality cracks: lightning tearing out of the lip, three waves.
 for w=0,2 do
  s:Later(w*.14,function()
   for i=1,count(8)do
    local target=Vector3.new(center.X+rand(-12,12),rand(TONGUE_Y,14),center.Z+rand(-4,12))
    s:Bolt(center,target,({VIOLET,CYAN,WHITE})[(i+w)%3+1],.3,.25)
   end
  end)
 end
 -- Cracks glowing on the tongue surface.
 for i=1,count(6)do
  local ang=(i/6)*math.pi*2+rand(-.3,.3)
  local dir=Vector3.new(math.cos(ang),0,math.sin(ang))
  local side=Vector3.new(-dir.Z,0,dir.X)
  local crack=Instance.new('Model');crack.Name='Crack';crack.Parent=s.Folder
  local prev=ground+Vector3.new(0,.06,0)+dir*1.5
  for k=1,5 do
   local nextPoint=ground+Vector3.new(0,.06,0)+dir*(1.5+k*1.7)+side*rand(-.8,.8)
   if math.abs(nextPoint.X)<10.5 then
    s:Part({Name='Arc',Color=i%2==0 and CYAN or VIOLET,Size=Vector3.new(.22,.06,(nextPoint-prev).Magnitude),
     CFrame=CFrame.lookAt((prev+nextPoint)/2,nextPoint),Parent=crack})
   end
   prev=nextPoint
  end
  s:Life(crack,2.6,function(a)
   for _,p in ipairs(crack:GetChildren())do if p:IsA('BasePart')then p.Transparency=calm and a or(a<.5 and(math.sin(a*30)>.6 and .3 or 0)or(a-.5)/.5)end end
  end)
 end
 s:Burst(center,seq(VIOLET,CYAN),90,{Size=NumberSequence.new(.7,0),Speed=NumberRange.new(10,26),Lifetime=NumberRange.new(.6,1.4),Drag=2})
 s:Burst(center,VOID,24,{Texture=SMOKE,LightEmission=0,Size=NumberSequence.new(3,7),Transparency=NumberSequence.new(.35,1),
  Speed=NumberRange.new(6,14),Lifetime=NumberRange.new(.9,1.6),Drag=3})
 s:Toss(center,10,{Name='VoidShard',Colors={VOID,Color3.fromRGB(60,20,120)},Material=Enum.Material.Glass,Size=Vector3.new(.7,.7,.7),
  Up={10,18},Out={6,12},Life=1.4,Ceiling=20})
 fadeLight(s,s:Light(s:Anchor(center+Vector3.new(0,3,0),'Flash'),VIOLET,40,8),8,1)
end

Tiers[6]=function(ctx:Ctx)
 local s=ctx.Scope
 -- Act 1 (block still in the throat): the mouth turns violet.
 if not waitEta(ctx,2.6)then return end
 local mouth=violetMouth(ctx)
 if not waitEta(ctx,1.6)then return end
 cue('Void',Vector3.new(0,6,-148))
 -- Act 2: the void implodes at the lip.
 if not waitEta(ctx,1.3)then return end
 local center=Vector3.new(ctx.X,7.5,LIP+1)
 local eta=Timing.Eta(ctx.Z,LIP-.4,lineSpeed())
 implosion(ctx,center,math.clamp(eta,.5,1.3))
 -- Act 3: the block bursts out of the void.
 if not waitZ(ctx,LIP-.4)then return end
 explosion(ctx,center)
 cue('Arrive',center,6)
 cue('Burst',center,6)
 local near=nearness(center,180)
 if cameraAllowed()and near>0 and not modalOpen()then
  flash(Color3.fromRGB(235,220,255),.35,.5)
  s:Cinema(Color3.fromRGB(215,195,255),3.2)
  fovPunch(9*nearness(center,160),.14,.75)
 end
 banner(6)
 local glow=s:Light(follower(ctx,Vector3.new(0,1.5,0),'Glow'),VIOLET,18,2.8)
 local aura=s:Emitter(follower(ctx,Vector3.new(0,0,0),'Wake'),{Color=seq(CYAN,VIOLET),Size=NumberSequence.new(.4,0),
  Speed=NumberRange.new(1,3),Lifetime=NumberRange.new(.6,1),Rate=low and 6 or 18})
 s:Later(3.6,function()mouth:Clean()end)
 -- Act 4: past the head a violet-cyan beam tears the sky open.
 if not waitZ(ctx,HEAD_CLEAR+3.5,30)then fadeLight(s,glow,2.8,.8);task.wait(1);return end
 aura.Enabled=false
 local base=Vector3.new(ctx.X,TONGUE_Y,ctx.Z)
 local top=base+Vector3.new(0,500,0)
 s:Pillar(base,top,VIOLET,8,4,{Alpha=.2,Out=2})
 s:Pillar(base,top,CYAN,2.6,4,{Alpha=.05,Out=2})
 s:Pillar(base,top,WHITE,.8,4,{Alpha=0,Out=2})
 s:Pillar(base,base+Vector3.new(0,160,0),VIOLET,10,3.4,{Material=Enum.Material.ForceField,Alpha=.1,Out=2})
 s:Ring(base,VIOLET,1,14,1,{Thickness=.7})
 s:Later(.15,function()s:Ring(base+Vector3.new(0,.06,0),CYAN,1,10,.85,{Thickness=.45})end)
 s:Later(.3,function()s:Ring(base+Vector3.new(0,.1,0),VOID,1,17,1.1,{Thickness=.9,Material=Enum.Material.SmoothPlastic,Alpha=.1})end)
 local climbers={}
 for i=1,count(10)do climbers[i]=s:Part({Name='Climber',Color=i%2==0 and CYAN or VIOLET,Size=Vector3.one*.7,Position=base})end
 s:Every(function(_,age)
  local a=age/3.2
  if a>=1 then for _,p in ipairs(climbers)do p:Destroy()end;return false end
  for i,p in ipairs(climbers)do
   local ang=i/#climbers*math.pi*2+age*(i%2==0 and 4 or-4)
   p.Position=base+Vector3.new(math.cos(ang)*5.5,age*48+i*2.5,math.sin(ang)*5.5)
   p.Transparency=a^2
  end
  return true
 end)
 for w=0,2 do
  s:Later(.2+w*.3,function()
   for _=1,count(4)do
    local h=rand(10,60)
    s:Bolt(base+Vector3.new(0,h,0),base+Vector3.new(rand(-14,14),h+rand(-8,8),rand(-14,14)),rng:NextNumber()<.5 and CYAN or VIOLET,.3,.25)
   end
  end)
 end
 s:Burst(base+Vector3.new(0,1,0),seq(CYAN,VIOLET),40,{EmissionDirection=Enum.NormalId.Top,SpreadAngle=Vector2.new(20,20),
  Speed=NumberRange.new(20,36),Lifetime=NumberRange.new(.8,1.6),Size=NumberSequence.new(.8,0)})
 cue('Reveal',base+Vector3.new(0,3,0),6)
 fadeLight(s,glow,2.8,2.5)
 task.wait(4)
end

---------------------------------------------------------------- scheduling
local heavyUntil=0 -- one heavy (Legendary+) arrival at a time
local played:{[string]:boolean}={}

local function run(model:Model,rank:number)
 low=Show.Low()
 local root=rootOf(model)
 local speed=lineSpeed()
 local ctx:Ctx={Model=model,Rank=rank,Color=Show.World[rank],Accent=Show.Accent[rank],Scope=newScope('LuckyArrival_'..rank),
  Z=root and root.Position.Z or Timing.Z(0,speed),X=root and root.Position.X or 0,Y=root and root.Position.Y or CENTRE_Y}
 if not root then
  local age=Timing.Age(serverNow(),model:GetAttribute('SpawnedAt'),line:GetAttribute('StreamTravel'),model:GetAttribute('StreamOffset'),speed)
  ctx.Z=Timing.Z(age or 0,speed)
 end
 local s=ctx.Scope
 -- Track the block; when its parts are missing, extrapolate along the tongue.
 s:Every(function(dt)
  local r=rootOf(model)
  if r then local p=r.Position;ctx.X,ctx.Y,ctx.Z=p.X,p.Y,p.Z
  else ctx.Z+=lineSpeed()*dt end
  return true
 end)
 s:Add(model.AncestryChanged:Connect(function()
  -- Bought or streamed out before the lip: nothing to show. After the lip the FX finish.
  if not model:IsDescendantOf(active)and ctx.Z<LIP-1 then s:Clean()end
 end))
 -- Pick the ladder step: far away players get a lighter show, and only one heavy arrival
 -- plays at a time (a second Legendary/Mythic falls back to the Epic look in its colours).
 local tier=rank
 local far=cameraDistance(Vector3.new(0,CENTRE_Y,LIP))
 if rank<=3 and far>260 then s:Clean();return end
 if rank>=4 and rank<6 and os.clock()<heavyUntil then tier=3 end
 if tier>=4 then heavyUntil=os.clock()+(tier>=6 and 14 or 9)end
 if far>520 and tier<4 then s:Clean();return end
 local ok,err=xpcall(Tiers[tier],debug.traceback,ctx)
 if not ok then warn('LuckyArrivalFX '..rank..':',err)end
 s:Clean()
end

local function consider(model:Instance)
 if not model:IsA('Model')or model:GetAttribute('DogId')~=nil then return end
 -- LuckyVisual/LuckyRank come with the model; Register's attributes land right after.
 local deadline=os.clock()+1
 while model.Parent and model:GetAttribute('LuckyVisual')~=true and model:GetAttribute('LuckyBlockRarity')==nil and os.clock()<deadline do task.wait(.05)end
 if model:GetAttribute('LuckyVisual')~=true and model:GetAttribute('LuckyBlockRarity')==nil then return end
 deadline=os.clock()+1.5
 while model.Parent and model:GetAttribute('State')==nil and os.clock()<deadline do task.wait(.05)end
 if not model.Parent or model:GetAttribute('State')~='OnLine'then return end
 local uid=model:GetAttribute('BlockUid')
 if type(uid)=='string'then
  if played[uid]then return end
 end
 local rankValue=model:GetAttribute('LuckyRank')
 local rank=type(rankValue)=='number'and Show.Rank(rankValue)or Show.Rank(model:GetAttribute('LuckyBlockRarity')or'Common')
 -- Fresh blocks only: late joiners / blocks streaming in mid-tongue get no arrival.
 local root=rootOf(model)
 local speed=lineSpeed()
 local age=Timing.Age(serverNow(),model:GetAttribute('SpawnedAt'),line:GetAttribute('StreamTravel'),model:GetAttribute('StreamOffset'),
  speed,root and root.Position.Z or nil)
 if not Timing.Fresh(age,Show.Timing.ArrivalGrace)then return end
 if root and root.Position.Z>LIP+14 then return end
 if type(uid)=='string'then
  played[uid]=true
  task.delay(120,function()played[uid]=nil end)
 end
 run(model,rank)
end

active.ChildAdded:Connect(function(model)task.spawn(consider,model)end)
for _,model in ipairs(active:GetChildren())do task.spawn(consider,model)end
