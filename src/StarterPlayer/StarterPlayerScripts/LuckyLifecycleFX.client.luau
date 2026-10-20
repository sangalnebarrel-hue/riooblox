-- Lucky Block pad presentation (client only; nothing here replicates or touches the economy).
--  * Placed/Ready blocks: timer text, progress cracks, warming panels and a lid that wakes up.
--  * Local OPEN (E on the pad prompt here, or LuckyBlockUI's OPEN button; both set the player
--    attributes LuckyBlockOpeningUid/At): a CHARGE on a local clone of the block (it rises,
--    shakes, spins up, cracks glow, light leaks out, a rarity beam shoots up, sparks get sucked
--    in), published as LuckyChargeUid/LuckyChargeAt so the roulette pops in on the BURST.
--  * Opened (server attributes RewardDogId/RewardRank/RewardVariant/RewardName/OpenedAt): every
--    client within NEAR studs that did not charge it plays a short charge synced to OpenedAt,
--    then the burst; non-Secret dogs pop out as a spinning hologram with a nameplate (the
--    Secret's own yard cinematic is SecretReveal's job).
-- FX live in workspace.DOGROTS_LuckyFX (never the district, never the server block model).
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local PPS=game:GetService('ProximityPromptService')
local TweenService=game:GetService('TweenService')
local RS=game:GetService('ReplicatedStorage')
local player=Players.LocalPlayer
local Lucky=RS:WaitForChild('Lucky')
local Show=require(Lucky:WaitForChild('LuckyShow'))
local Audio=require(Lucky:WaitForChild('LuckyAudio'))

local NEAR=120            -- studs from the camera: who watches an opening
local PROGRESS_NEAR=100   -- studs: progress cracks / panel warmth
local SPECTATOR_CHARGE=.6 -- seconds of charge when the open was not predicted here
local PREDICT_WINDOW=6    -- a prediction older than this is stale
local HOLD_TIMEOUT=6      -- no Opened this long after the charge started: the open failed
local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local FIRE='rbxasset://textures/particles/fire_main.dds'
local WHITE=Color3.new(1,1,1)
local NAVY=Color3.fromRGB(23,43,76)
local VOID_BLACK=Color3.fromRGB(10,2,22)
local rng=Random.new()

--@pure-begin  (no Instances; smoke-tested with Lune from the scratch dir)
local P={}
P.LateLimit=1.6 -- Opened seen this late (streaming, lag): skip the show
-- Burst intensity per rank: shockwave rings, their reach, sparks, flash size, light, chunk speed;
-- Pillar = height of the rarity beam that shoots up during the charge.
P.Profiles={
 {Rings=1,Reach=9,Sparks=26,Flash=5,Light=5,Chunk=15,Pillar=18},
 {Rings=1,Reach=11,Sparks=42,Flash=6,Light=6,Chunk=17,Pillar=26},
 {Rings=2,Reach=14,Sparks=64,Flash=8,Light=7,Chunk=20,Pillar=36},
 {Rings=2,Reach=17,Sparks=92,Flash=10,Light=8,Chunk=23,Pillar=48},
 {Rings=3,Reach=22,Sparks=140,Flash=13,Light=10,Chunk=27,Pillar=64},
 {Rings=3,Reach=26,Sparks=120,Flash=15,Light=10,Chunk=27,Pillar=84,Void=true},
}
function P.Profile(rank,low)
 local base=P.Profiles[math.clamp(math.floor(tonumber(rank)or 1),1,6)]
 local out=table.clone(base)
 if low then
  out.Rings=math.min(out.Rings,2);out.Sparks=math.ceil(out.Sparks*.35);out.Reach*=.85
 end
 return out
end
-- The charge, t in 0..1: rise (block-scale studs), spin speed (rad/s), shake (block-scale
-- studs), glow 0..1. Everything accelerates towards the burst.
function P.ChargeCurve(t)
 t=math.clamp(t,0,1)
 local e=t*t
 return {Rise=1.6*(1-(1-t)^2),Spin=.6+16*e*t,Shake=.03+.22*e,Glow=t^1.5}
end
-- Camera offsets for the opener: FOV delta (degrees) and shake (studs).
-- phase 'charge' (t 0..1), 'hold' (waiting for the server), 'burst' (age in seconds).
function P.CameraCurve(phase,t,age)
 if phase=='charge'then t=math.clamp(t,0,1);return -5*t*t,.025+.11*t*t,false end
 if phase=='hold'then return -5,.13,false end
 age=math.max(0,age or 0)
 local fov
 if age<.12 then fov=-5+12*(age/.12)
 else local a=math.clamp((age-.12)/.7,0,1);fov=7*(1-a*a*(3-2*a))end
 local shake=age<.55 and .42*(1-age/.55)^2 or 0
 return fov,shake,age>=.85
end
-- Deterministic crack network for a block: segments on the 4 side faces, in face units
-- (x right, y up, the 5.45 authored face spans about +-2.4). At = when it lights (0..1).
function P.Seed(uid)
 local h=7
 for i=1,#tostring(uid)do h=(h*31+string.byte(tostring(uid),i))%2147483646 end
 return h+1
end
function P.Cracks(seed,branches,steps)
 local r=Random.new(seed)
 local out={}
 for face=0,3 do
  for b=1,branches do
   local x,y=r:NextNumber(-.35,.35),r:NextNumber(-.35,.35)
   local angle=(b-1)/branches*math.pi*2+r:NextNumber(-.6,.6)+face
   for k=1,steps do
    local len=r:NextNumber(.5,.9)
    angle+=r:NextNumber(-.65,.65)
    local nx,ny=x+math.cos(angle)*len,y+math.sin(angle)*len
    if math.abs(nx)>2.35 or math.abs(ny)>2.35 then break end
    table.insert(out,{Face=face,X=(x+nx)/2,Y=(y+ny)/2,Len=len+.06,Angle=angle,
     Width=.17*(1-(k-1)/steps*.55),At=math.clamp(.06+.82*((k-1)+r:NextNumber(0,.6))/steps,0,.95)})
    x,y=nx,ny
   end
  end
 end
 return out
end
-- When the burst happens: never before the charge ends, never before the server said Opened.
function P.BurstAt(startAt,length,openedSeenAt)
 local due=startAt+length
 if not openedSeenAt then return nil end
 return math.max(due,openedSeenAt)
end
-- What a client does when it sees BlockState=Opened without a running charge.
-- Returns 'charge' (start the short charge at startAt), 'burst' (burst at once) or 'skip'.
function P.LatePlan(now,openedAt,length)
 openedAt=openedAt or now
 local age=now-openedAt
 if age<0 then return 'charge',openedAt end
 if age<length then return 'charge',openedAt end
 if age<P.LateLimit then return 'burst',now end
 return 'skip',nil
end
-- LuckyChargeAt for a charge that bursts at burstAt (the roulette starts at ChargeAt+Charge).
function P.ChargeAt(burstAt,charge)return burstAt-charge end
local VARIANTS={Shiny={'SHINY','СИЯЮЩИЙ'},Golden={'GOLDEN','ЗОЛОТОЙ'},Corrupted={'CORRUPTED','ИСКАЖЁННЫЙ'},
 Glitched={'GLITCHED','СБОЙНЫЙ'},Void={'VOID','ПУСТОТНЫЙ'}}
P.VariantColors={Shiny=Color3.fromRGB(210,235,255),Golden=Color3.fromRGB(255,193,44),
 Corrupted=Color3.fromRGB(188,56,81),Glitched=Color3.fromRGB(210,87,255),Void=Color3.fromRGB(104,38,164)}
-- Nameplate text: rarity line (with the variant) and the dog's name.
function P.Label(names,rank,name,variant,ru)
 local lang=ru and 2 or 1
 local list=ru and names.RU or names.EN
 local rarity=list[math.clamp(math.floor(tonumber(rank)or 1),1,6)]
 local v=VARIANTS[variant or '']
 if v then rarity=v[lang]..' · '..rarity end
 return rarity,tostring(name or '')
end
local function smooth(a)a=math.clamp(a,0,1);return a*a*(3-2*a)end
local function backOut(a)a=math.clamp(a,0,1);local c=1.9;return 1+(c+1)*(a-1)^3+c*(a-1)^2 end
P.Smooth=smooth;P.BackOut=backOut
--@pure-end

---------------------------------------------------------------- small helpers
local function now()return workspace:GetServerTimeNow()end
local function fxRoot()
 local root=workspace:FindFirstChild('DOGROTS_LuckyFX')
 if not root then root=Instance.new('Folder');root.Name='DOGROTS_LuckyFX';root.Parent=workspace end
 return root
end
local function part(props:{[string]:any}):Part
 local p=Instance.new('Part')
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 p.Material=Enum.Material.Neon;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 for k,v in pairs(props)do if k~='Parent'then(p::any)[k]=v end end
 p.Parent=props.Parent
 return p
end
local function tween(o:Instance,seconds:number,props:{[string]:any},style:Enum.EasingStyle?,dir:Enum.EasingDirection?)
 local t=TweenService:Create(o,TweenInfo.new(seconds,style or Enum.EasingStyle.Quad,dir or Enum.EasingDirection.Out),props)
 t:Play();return t
end
local function emitter(parent:Instance,props:{[string]:any}):ParticleEmitter
 local e=Instance.new('ParticleEmitter')
 e.Texture=SPARK;e.Rate=0;e.LightEmission=1;e.LightInfluence=0;e.Lifetime=NumberRange.new(.6,1.3)
 e.Speed=NumberRange.new(6,14);e.SpreadAngle=Vector2.new(180,180);e.Size=NumberSequence.new(.5,0)
 e.Transparency=NumberSequence.new(0,1)
 for k,v in pairs(props)do(e::any)[k]=v end
 e.Parent=parent
 return e
end
local function colors(...):ColorSequence
 local list={...}
 if #list==1 then return ColorSequence.new(list[1])end
 local keys={}
 for i,c in ipairs(list)do table.insert(keys,ColorSequenceKeypoint.new((i-1)/(#list-1),c))end
 return ColorSequence.new(keys)
end
local function cameraDistance(position:Vector3):number
 local cam=workspace.CurrentCamera
 return cam and(cam.CFrame.Position-position).Magnitude or math.huge
end
local ruCache
local function isRussian():boolean
 if ruCache~=nil then return ruCache end
 local ok,locale=pcall(function()
  local LS=game:GetService('LocalizationService')
  if Run:IsStudio()then return LS.RobloxLocaleId end
  return player.LocaleId or LS.RobloxLocaleId
 end)
 ruCache=ok and type(locale)=='string'and locale:sub(1,2):lower()=='ru'or false
 return ruCache::boolean
end
local defsCache,rigCache
local function definitions()
 if defsCache==nil then
  local ok,d=pcall(function()return require(RS:WaitForChild('DogEconomy',5):WaitForChild('DogDefinitions',5)::any)end)
  defsCache=ok and type(d)=='table'and d or false
 end
 return defsCache or nil
end
local function dogRig()
 if rigCache==nil then
  local ok,r=pcall(function()return require(RS:WaitForChild('DogRig',5)::any)end)
  rigCache=ok and type(r)=='table'and r or false
 end
 return rigCache or nil
end

-- One Heartbeat drives every animation: fn(dt) returns false when finished. Errors end only
-- that animation (its cleanup still runs).
local anims={}
local function animate(fn:(number)->boolean?,cleanup:(()->())?)
 table.insert(anims,{Step=fn,Cleanup=cleanup})
end
Run.Heartbeat:Connect(function(dt)
 for i=#anims,1,-1 do
  local a=anims[i]
  local ok,keep=pcall(a.Step,dt)
  if not ok then warn('LuckyLifecycleFX:',keep)end
  if not ok or keep==false then
   table.remove(anims,i)
   if a.Cleanup then local good,err=pcall(a.Cleanup);if not good then warn('LuckyLifecycleFX cleanup:',err)end end
  end
 end
end)

---------------------------------------------------------------- shared world FX
-- Flat shockwave ring of neon segments on the ground, growing r0 -> r1.
local function shockRing(folder:Instance,center:Vector3,color:Color3,r0:number,r1:number,life:number,segments:number,thick:number,material:Enum.Material?)
 local parts,frames={},{}
 for i=1,segments do
  parts[i]=part({Name='Shockwave',Color=color,Material=material or Enum.Material.Neon,Size=Vector3.new(thick,.22,1),Transparency=.05,Parent=folder})
 end
 local age=0
 animate(function(dt)
  age+=dt
  if not parts[1].Parent then return false end
  local a=math.min(age/life,1)
  local r=r0+(r1-r0)*(1-(1-a)^3)
  local len=2*math.pi*r/segments*1.1
  for i,p in ipairs(parts)do
   local ang=i/segments*math.pi*2
   local pos=center+Vector3.new(math.cos(ang)*r,0,math.sin(ang)*r)
   frames[i]=CFrame.lookAt(pos,pos+Vector3.new(-math.sin(ang),0,math.cos(ang)))
   p.Size=Vector3.new(thick*(1-.55*a),.22,len)
   p.Transparency=.05+.95*a^1.6
  end
  workspace:BulkMoveTo(parts,frames,Enum.BulkMoveMode.FireCFrameChanged)
  return a<1
 end,function()for _,p in ipairs(parts)do p:Destroy()end end)
end
-- Flat glowing disc lying on the ground.
local function groundDisc(folder:Instance,center:Vector3,color:Color3,diameter:number,alpha:number):Part
 return part({Name='GroundGlow',Shape=Enum.PartType.Cylinder,Color=color,Transparency=alpha,
  Size=Vector3.new(.08,diameter,diameter),CFrame=CFrame.new(center)*CFrame.Angles(0,0,math.pi/2),Parent=folder})
end

---------------------------------------------------------------- per-model progress visuals
local rows={}       -- pad model -> progress state
local stages={}     -- block uid -> opening show
local startLate     -- forward declarations
local onOpened

local function modelForUid(uid:string):Model?
 for m in pairs(rows)do
  if m.Parent and m:GetAttribute('OwnedBlockUid')==uid then return m end
 end
 return nil
end
local function clearCracks(row)
 if row.Cracks then row.Cracks:Destroy();row.Cracks=nil;row.CrackParts=nil end
end

---------------------------------------------------------------- camera (the opener only)
local CAMERA_BIND='DOGROTS_LuckyOpenCamera'
local camState:any=nil
local function cameraRelease()
 local st=camState;if not st then return end
 camState=nil
 Run:UnbindFromRenderStep(CAMERA_BIND)
 local c=st.Cam
 if c and c.Parent and math.abs(c.FieldOfView-st.Written)<.01 then c.FieldOfView=st.Base end
 if c and c:GetAttribute('SecretZoom')==st.Base then c:SetAttribute('SecretZoom',nil)end
end
local function cameraStart(stage:any)
 if camState or stage.Low or stage.Reduced or not Show.CameraFree()then return end
 local c=workspace.CurrentCamera;if not c then return end
 camState={Stage=stage,Base=c.FieldOfView,Written=c.FieldOfView,Cam=c}
 -- SecretZoom marks the FOV as borrowed (other FOV owners keep the true value), like Kit.FOVPunch.
 c:SetAttribute('SecretZoom',c.FieldOfView)
 Run:BindToRenderStep(CAMERA_BIND,Enum.RenderPriority.Camera.Value+5,function()
  local st=camState;if not st then return end
  local cam=st.Cam
  if workspace.CurrentCamera~=cam or cam.CameraType==Enum.CameraType.Scriptable or math.abs(cam.FieldOfView-st.Written)>.01
   or not st.Stage.Alive and st.Stage.Phase~='burst'then cameraRelease();return end
  local s=st.Stage;local fov,shake,done
  if s.Phase=='burst'then fov,shake,done=P.CameraCurve('burst',0,os.clock()-s.BurstClock)
  elseif s.Phase=='hold'then fov,shake,done=P.CameraCurve('hold',1,0)
  else fov,shake,done=P.CameraCurve('charge',(now()-s.StartAt)/s.Len,0)end
  if done then cameraRelease();return end
  st.Written=math.clamp(st.Base+fov,20,110);cam.FieldOfView=st.Written
  if shake>0 then
   local t=os.clock()
   cam.CFrame*=CFrame.new(math.noise(t*21,.3)*shake,math.noise(.7,t*24)*shake,0)*CFrame.Angles(0,0,math.noise(t*15,1.9)*shake*.05)
  end
 end)
end

---------------------------------------------------------------- the opening show
local function publishCharge(uid:string,chargeAt:number)
 -- At first: the roulette reads both when the uid changes.
 player:SetAttribute('LuckyChargeAt',chargeAt)
 player:SetAttribute('LuckyChargeUid',uid)
end
local function clearCharge(uid:string)
 if player:GetAttribute('LuckyChargeUid')==uid then
  player:SetAttribute('LuckyChargeUid',nil);player:SetAttribute('LuckyChargeAt',nil)
 end
end
-- While a local open charges, the player's own pad prompts are out of reach: the roulette takes
-- the screen only on the burst, and a second E in between would open another block or the pad
-- picker underneath it. The server never writes MaxActivationDistance, so the local 0 sticks
-- until finish() puts the old value back.
local holders={}
local heldPrompts={}
local function holdPrompts(stage:any)
 if holders[stage]then return end
 holders[stage]=true
 local map=workspace:FindFirstChild('DOGROTS_District');local yards=map and map:FindFirstChild('04_PlayerYards')
 if not yards then return end
 for _,yard in ipairs(yards:GetChildren())do
  for _,pad in ipairs(yard:GetChildren())do
   if pad.Name:sub(1,9)=='LuckyPad_'and pad:GetAttribute('LuckyPadOwner')==player.UserId then
    local prompt=pad:FindFirstChild('PlaceLuckyBlock')
    if prompt and prompt:IsA('ProximityPrompt')and heldPrompts[prompt]==nil then
     heldPrompts[prompt]=prompt.MaxActivationDistance;prompt.MaxActivationDistance=0
    end
   end
  end
 end
end
local function releasePrompts(stage:any)
 if not holders[stage]then return end
 holders[stage]=nil
 if next(holders)then return end
 for prompt,distance in pairs(heldPrompts)do if prompt.Parent then prompt.MaxActivationDistance=distance end end
 table.clear(heldPrompts)
end
local function readOpened(m:Model)
 local id=m:GetAttribute('RewardDogId')
 local defs=definitions()
 local def=defs and type(id)=='string'and defs[id]
 return {DogId=id,Rank=tonumber(m:GetAttribute('RewardRank'))or(def and def.Rank)or 1,
  Variant=tostring(m:GetAttribute('RewardVariant')or'Normal'),Name=m:GetAttribute('RewardName')or(def and def.DisplayName)or id,
  OpenedAt=tonumber(m:GetAttribute('OpenedAt'))or now()}
end
local function hide(stage:any,d:Instance)
 if d:IsA('BasePart')or d:IsA('Decal')then(d::any).LocalTransparencyModifier=1;stage.Hidden[d]=true end
end
-- Hide the server block for this client while the clone performs (C3: LuckyOpening).
local function adopt(stage:any,m:Model)
 if stage.Original==m then return end
 stage.Original=m
 m:SetAttribute('LuckyOpening',true)
 for _,d in ipairs(m:GetDescendants())do hide(stage,d)end
 table.insert(stage.Conns,m.DescendantAdded:Connect(function(d)hide(stage,d)end))
 local row=rows[m];if row then clearCracks(row)end
end
local function restoreOriginal(stage:any)
 for d in pairs(stage.Hidden)do if d.Parent then(d::any).LocalTransparencyModifier=0 end end
 table.clear(stage.Hidden)
 local m=stage.Original
 if m and m.Parent then m:SetAttribute('LuckyOpening',nil)end
end
local function finish(stage:any)
 if not stage.Alive then return end
 stage.Alive=false
 releasePrompts(stage)
 for _,c in ipairs(stage.Conns)do c:Disconnect()end
 table.clear(stage.Conns)
 -- The server deletes an opened block; anything else gets its look back.
 local m=stage.Original
 if m and m.Parent and m:GetAttribute('BlockState')~='Opened'then restoreOriginal(stage)end
 if stage.Folder then stage.Folder:Destroy()end
 if stages[stage.Uid]==stage then stages[stage.Uid]=nil end
end

-- Clone the pad block locally and keep the parts the charge and the burst animate.
local function makeClone(stage:any,m:Model)
 local ok,clone=pcall(function()return m:Clone()end)
 if not ok or not clone then return end
 for _,d in ipairs(clone:GetDescendants())do
  if d:IsA('LayerCollector')or d:IsA('ParticleEmitter')or d:IsA('Light')or d:IsA('Sound')or d:IsA('ProximityPrompt')
   or d:IsA('LuaSourceContainer')or d:IsA('Beam')or d:IsA('Trail')or d:IsA('Highlight')then d:Destroy()end
 end
 for _,name in ipairs({'OwnedBlockUid','OwnerUserId','BlockState','LuckyVisual','LuckyOpening','OpenMessage','RewardDogId'})do clone:SetAttribute(name,nil)end
 clone:SetAttribute('LuckyFXClone',true) -- before parenting: LuckyBlockFX never dresses it
 clone.Name='LuckyOpeningClone'
 local parts={}
 for _,d in ipairs(clone:GetDescendants())do
  if d:IsA('BasePart')then
   d.Anchored=true;d.CanCollide=false;d.CanTouch=false;d.CanQuery=false;d.CastShadow=false;d.LocalTransparencyModifier=0
   table.insert(parts,d)
  end
 end
 if #parts==0 then clone:Destroy();return end
 clone.Parent=stage.Folder
 stage.Clone=clone;stage.CloneParts=parts;stage.CloneScale=clone:GetScale()
 stage.Panels={}
 for _,p in ipairs(parts)do
  if p.Name=='InsetPanel'or p.Name=='Lid'or p.Name=='Badge'then table.insert(stage.Panels,{Part=p,Color=p.Color})end
 end
end

local function buildCharge(stage:any)
 local s,rank,color,accent=stage.Scale,stage.Rank,Show.World[stage.Rank],Show.Accent[stage.Rank]
 local folder=stage.Folder
 local anchor=part({Name='LuckyCore',Size=Vector3.one*.2,Transparency=1,CFrame=stage.Pivot,Parent=folder})
 stage.Anchor=anchor
 stage.Light=Instance.new('PointLight');stage.Light.Color=color;stage.Light.Range=6;stage.Light.Brightness=0;stage.Light.Shadows=false;stage.Light.Parent=anchor
 -- Sparks sucked into the block from a sphere around it.
 local radius=3.6*s/.68
 local well=part({Name='SuckWell',Shape=Enum.PartType.Ball,Size=Vector3.one*radius*2,Transparency=1,CFrame=CFrame.new(stage.Center),Parent=folder})
 stage.Suck=emitter(well,{Shape=Enum.ParticleEmitterShape.Sphere,ShapeInOut=Enum.ParticleEmitterShapeInOut.Inward,
  ShapeStyle=Enum.ParticleEmitterShapeStyle.Surface,Lifetime=NumberRange.new(.42,.5),Speed=NumberRange.new(radius/.46),
  SpreadAngle=Vector2.zero,Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(.6,.3),NumberSequenceKeypoint.new(1,.05)}),
  Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.25,.1),NumberSequenceKeypoint.new(1,.2)}),
  Color=rank==6 and colors(accent,color,VOID_BLACK)or colors(WHITE,accent,color)})
 -- Glowing cracks spreading over the four faces of the clone (they ride with it).
 stage.Cracks={}
 if stage.Clone then
  local list=P.Cracks(P.Seed(stage.Uid),stage.Low and 1 or 3,stage.Low and 3 or 4)
  local hot=color:Lerp(WHITE,.55)
  for _,c in ipairs(list)do
   local cf=stage.Pivot*CFrame.Angles(0,c.Face*math.pi/2,0)*CFrame.new(c.X*s,c.Y*s,-3.08*s)*CFrame.Angles(0,0,c.Angle)
   local p=part({Name='ChargeCrack',Color=hot,Size=Vector3.new(c.Len*s,c.Width*s,.06*s),CFrame=cf,Transparency=1,Parent=stage.Clone})
   table.insert(stage.CloneParts,p)
   table.insert(stage.Cracks,{Part=p,At=c.At})
  end
 end
 -- Light leaking out of the seams: rays from the core that grow with the charge.
 stage.Rays={}
 local core=Instance.new('Attachment');core.Name='RayCore';core.Parent=anchor
 for k=1,(stage.Low and 4 or 8)do
  local yaw=(k/(stage.Low and 4 or 8))*math.pi*2+rng:NextNumber(-.3,.3)
  local pitch=rng:NextNumber(-.15,.75)
  local dir=Vector3.new(math.cos(yaw)*math.cos(pitch),math.sin(pitch),math.sin(yaw)*math.cos(pitch))
  local tip=Instance.new('Attachment');tip.Name='RayTip';tip.Position=dir*2*s;tip.Parent=anchor
  local beam=Instance.new('Beam');beam.Attachment0=core;beam.Attachment1=tip;beam.FaceCamera=true;beam.Segments=1
  beam.LightEmission=1;beam.LightInfluence=0;beam.Color=colors(WHITE,accent,color);beam.Width0=.1*s;beam.Width1=.6*s
  beam.Transparency=NumberSequence.new(1);beam.Parent=anchor
  table.insert(stage.Rays,{Beam=beam,Tip=tip,Dir=dir,Length=rng:NextNumber(5,8)*s/.68})
 end
 -- The rarity beam shooting up into the sky, and a glow pooling on the pad.
 stage.Pillar=part({Name='ChargePillar',Shape=Enum.PartType.Cylinder,Color=color:Lerp(WHITE,.25),Transparency=1,Size=Vector3.new(.1,.1,.1),
  CFrame=CFrame.new(stage.Center)*CFrame.Angles(0,0,math.pi/2),Parent=folder})
 if not stage.Low then
  stage.Halo=part({Name='ChargePillarGlow',Shape=Enum.PartType.Cylinder,Color=color,Transparency=1,Size=Vector3.new(.1,.1,.1),
   CFrame=CFrame.new(stage.Center)*CFrame.Angles(0,0,math.pi/2),Parent=folder})
 end
 stage.Pool=groundDisc(folder,stage.Ground+Vector3.new(0,.06,0),color,4.8*s/.68,1)
 -- A rune ring turning under Epic and better blocks.
 stage.Runes={}
 if rank>=3 and not stage.Low then
  for i=1,12 do
   table.insert(stage.Runes,part({Name='ChargeRune',Color=i%2==0 and accent or color,Size=Vector3.new(.12,.1,.62)*s/.68,Transparency=1,Parent=folder}))
  end
 end
 if rank==6 then
  stage.VoidCore=part({Name='VoidCore',Shape=Enum.PartType.Ball,Color=VOID_BLACK,Material=Enum.Material.SmoothPlastic,Transparency=1,Size=Vector3.one*.2,CFrame=CFrame.new(stage.Center),Parent=folder})
  stage.VoidRim=part({Name='VoidRim',Shape=Enum.PartType.Ball,Color=color,Transparency=1,Size=Vector3.one*.2,CFrame=CFrame.new(stage.Center),Parent=folder})
 end
end

-- One charge frame. t = 0..1 of the charge; hold = seconds spent waiting at full charge.
local function stepCharge(stage:any,t:number,hold:number,dt:number)
 local s=stage.Scale
 local c=P.ChargeCurve(t)
 if hold>0 then c.Shake+=.04*math.sin(hold*30)^2 end
 if stage.Reduced then c.Shake=0;c.Spin*=.45 end
 stage.Angle+=c.Spin*dt
 local rise=c.Rise*s
 local jitter=Vector3.new(rng:NextNumber(-1,1),rng:NextNumber(-.4,1),rng:NextNumber(-1,1))*c.Shake*s
 local tilt=stage.Low and CFrame.identity or CFrame.Angles(rng:NextNumber(-1,1)*c.Shake*.3,0,rng:NextNumber(-1,1)*c.Shake*.3)
 local pivot=CFrame.new(stage.Center+Vector3.new(0,rise,0)+jitter)*stage.Pivot.Rotation*CFrame.Angles(0,stage.Angle,0)*tilt
 -- Secret blocks collapse into a void in the last third before they burst.
 local implode=stage.Rank==6 and math.clamp((t-.62)/.38,0,1)or 0
 if implode>0 and not stage.VoidCue then stage.VoidCue=true;Audio.Play('Void',stage.Anchor)end
 if stage.Clone and stage.Clone.Parent then
  if implode>0 then
   local k=1-.85*implode*implode
   if math.abs(k-(stage.LastScale or 1))>.01 then stage.LastScale=k;stage.Clone:ScaleTo(stage.CloneScale*k)end
  end
  stage.Clone:PivotTo(pivot)
  -- Light pushes out through the panels.
  if t>.45 then
   local g=math.clamp((t-.45)/.55,0,1)
   local hot=Show.World[stage.Rank]:Lerp(WHITE,.15)
   for _,info in ipairs(stage.Panels)do
    if not info.Neon then info.Neon=true;info.Part.Material=Enum.Material.Neon end
    info.Part.Color=info.Color:Lerp(hot,.25+.6*g)
   end
  end
  for _,crack in ipairs(stage.Cracks)do
   crack.Part.Transparency=math.clamp(1-(t-crack.At)/.08,0,1)
  end
 end
 stage.Anchor.CFrame=pivot
 for _,ray in ipairs(stage.Rays)do
  local g=math.clamp((t-.3)/.7,0,1)*(1-implode)
  ray.Tip.Position=ray.Dir*(1.5*s+ray.Length*g)
  ray.Beam.Width1=(.4+1.6*g)*s/.68
  ray.Beam.Transparency=NumberSequence.new(1-.75*g,1)
 end
 stage.Light.Brightness=(.5+6*c.Glow)*(stage.Reduced and .6 or 1)
 stage.Light.Range=6+10*c.Glow
 stage.Suck.Rate=(stage.Low and 22 or 70)*math.min(1,t*1.6)*(1+implode)
 -- Beam of light: shoots up over the second half of the charge.
 local b=math.clamp((t-.35)/.65,0,1)
 local height=math.max(.1,stage.Profile.Pillar*(1-(1-b)^2))
 local width=(.25+.9*b)*s/.68
 local base=stage.Center+Vector3.new(0,rise,0)
 stage.Pillar.Size=Vector3.new(height,width,width)
 stage.Pillar.CFrame=CFrame.new(base+Vector3.new(0,height/2,0))*CFrame.Angles(0,0,math.pi/2)
 stage.Pillar.Transparency=b>0 and .55-.4*b or 1
 if stage.Halo then
  stage.Halo.Size=Vector3.new(height*.96,width*2.6,width*2.6)
  stage.Halo.CFrame=stage.Pillar.CFrame
  stage.Halo.Transparency=b>0 and .9-.12*b or 1
 end
 stage.Pool.Transparency=.92-.5*c.Glow
 if #stage.Runes>0 then
  local r=2.9*s/.68
  local frames={}
  for i,p in ipairs(stage.Runes)do
   local a=i/#stage.Runes*math.pi*2-stage.Angle*.35
   local pos=stage.Ground+Vector3.new(math.cos(a)*r,.1,math.sin(a)*r)
   frames[i]=CFrame.lookAt(pos,pos+Vector3.new(-math.sin(a),0,math.cos(a)))
   p.Transparency=1-.85*math.min(1,t*2)
  end
  workspace:BulkMoveTo(stage.Runes,frames,Enum.BulkMoveMode.FireCFrameChanged)
 end
 if stage.VoidCore then
  local v=implode
  local size=(7-5.8*v*v)*s/.68
  stage.VoidCore.Size=Vector3.one*size*.82;stage.VoidCore.CFrame=CFrame.new(pivot.Position)
  stage.VoidCore.Transparency=v>0 and math.max(.04,1-v*3)or 1
  stage.VoidRim.Size=Vector3.one*size;stage.VoidRim.CFrame=CFrame.new(pivot.Position)
  stage.VoidRim.Transparency=v>0 and math.max(.55,1-v*2)or 1
 end
 -- Sound beats: shakes speed up, cracks snap at three moments.
 local beat=.26-.14*t
 if os.clock()-(stage.LastShake or 0)>beat then stage.LastShake=os.clock();Audio.Play('Shake',stage.Anchor,t)end
 local snap=t>=.78 and 3 or t>=.52 and 2 or t>=.26 and 1 or 0
 if snap>(stage.Snaps or 0)then stage.Snaps=snap;Audio.Play('Crack',stage.Anchor)end
end

---------------------------------------------------------------- the dog hologram
local holograms=0
local function rewardOverlay():boolean
 local gui=player:FindFirstChildOfClass('PlayerGui')
 local screen=gui and gui:FindFirstChild('ScreenGui')
 return screen~=nil and screen:FindFirstChild('RewardReveal')~=nil
end
local function popDog(info,ground:Vector3)
 if holograms>=4 or not info or type(info.DogId)~='string'or(info.Rank or 1)>=6 then return end
 if cameraDistance(ground)>NEAR then return end
 local defs=definitions();local def=defs and defs[info.DogId]
 local menu=RS:FindFirstChild('MenuModels')
 local source=def and menu and menu:FindFirstChild(tostring(def.VisualAsset))
 local Rig=dogRig()
 if not source or not source:IsA('Model')or not Rig then return end
 local ok,model=pcall(function()return source:Clone()end)
 if not ok or not model then return end
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA('LuaSourceContainer')or d:IsA('Sound')or d:IsA('ProximityPrompt')or d:IsA('LayerCollector')or d:IsA('ParticleEmitter')
   or d:IsA('Beam')or d:IsA('Trail')or d:IsA('Highlight')or d:IsA('ClickDetector')or d:IsA('Light')then d:Destroy()end
 end
 local good,bounds=pcall(Rig.Prepare,model,Vector3.new(4.2,3.4,4.6))
 if not good or not bounds then model:Destroy();return end
 for _,name in ipairs({'DogId','DogUid'})do model:SetAttribute(name,nil)end
 model:SetAttribute('LuckyFXClone',true);model.Name='LuckyDogHologram'
 local low=Show.Low()
 local rank=math.clamp(math.floor(info.Rank or 1),1,6)
 local color,accent=Show.World[rank],Show.Accent[rank]
 local folder=Instance.new('Folder');folder.Name='LuckyDogPop';folder.Parent=fxRoot()
 local parts,alpha={},{}
 for _,d in ipairs(model:GetDescendants())do if d:IsA('BasePart')then table.insert(parts,d);alpha[d]=d.Transparency end end
 local base=model:GetScale()
 local groundLocal=model:GetAttribute('GroundLocal')
 local g:Vector3=typeof(groundLocal)=='Vector3'and groundLocal or Vector3.zero
 local height=(bounds.Size and bounds.Size.Y)or 3
 local cam=workspace.CurrentCamera
 local toCam=cam and(cam.CFrame.Position-ground)*Vector3.new(1,0,1)or Vector3.zAxis
 local facing=toCam.Magnitude>.01 and CFrame.lookAt(Vector3.zero,toCam.Unit)or CFrame.identity
 model:ScaleTo(base*.2)
 model:PivotTo(CFrame.new(ground)*facing*CFrame.new(-g*.2))
 model.Parent=folder
 local hl=Instance.new('Highlight');hl.Adornee=model;hl.DepthMode=Enum.HighlightDepthMode.Occluded
 hl.FillColor=P.VariantColors[info.Variant]or color;hl.FillTransparency=.78;hl.OutlineColor=accent:Lerp(WHITE,.4);hl.OutlineTransparency=.15
 hl.Parent=folder
 -- Aura on the pad: a turning ring, a soft disc and sparks rising off it.
 local ring={}
 for i=1,(low and 8 or 16)do table.insert(ring,part({Name='AuraRing',Color=i%2==0 and accent or color,Size=Vector3.new(.16,.12,.9),Transparency=.15,Parent=folder}))end
 local disc=groundDisc(folder,ground+Vector3.new(0,.05,0),color,.5,.55)
 local riser=part({Name='AuraSparks',Size=Vector3.new(3.6,.2,3.6),Transparency=1,CFrame=CFrame.new(ground+Vector3.new(0,.2,0)),Parent=folder})
 local rise=emitter(riser,{Rate=low and 4 or 12,EmissionDirection=Enum.NormalId.Top,Speed=NumberRange.new(2,5),SpreadAngle=Vector2.new(12,12),
  Lifetime=NumberRange.new(1,1.6),Size=NumberSequence.new(.28,0),Color=colors(WHITE,accent,color)})
 if not low then local l=Instance.new('PointLight');l.Color=color;l.Range=12;l.Brightness=2.2;l.Shadows=false;l.Parent=riser end
 -- Nameplate: the rarity pill picks its own language (NoTranslate); the dog name is left to
 -- DOGROTS_AutoTranslateUI, which holds the Russian dog names and also watches workspace.
 local tag=part({Name='NameAnchor',Size=Vector3.one*.2,Transparency=1,CFrame=CFrame.new(ground),Parent=folder})
 local bb=Instance.new('BillboardGui');bb.Name='LuckyDogNameplate'
 bb.Size=UDim2.fromOffset(280,88);bb.AlwaysOnTop=true;bb.LightInfluence=0;bb.MaxDistance=NEAR;bb.Adornee=tag;bb.Parent=folder
 local scale=Instance.new('UIScale');scale.Scale=0;scale.Parent=bb
 local rarityText,nameText=P.Label(Show.Names,rank,info.Name,info.Variant,isRussian())
 local pill=Instance.new('TextLabel');pill.Name='Rarity';pill:SetAttribute('NoTranslate',true)
 pill.AnchorPoint=Vector2.new(.5,0);pill.Position=UDim2.fromScale(.5,0);pill.Size=UDim2.fromOffset(0,28);pill.AutomaticSize=Enum.AutomaticSize.X
 pill.BackgroundColor3=Show.UI[rank];pill.Font=Enum.Font.FredokaOne;pill.TextSize=18;pill.TextColor3=WHITE
 pill.TextStrokeColor3=NAVY;pill.TextStrokeTransparency=0;pill.Text=rarityText;pill.Parent=bb
 local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,14);pad.PaddingRight=UDim.new(0,14);pad.Parent=pill
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(.5,0);corner.Parent=pill
 local edge=Instance.new('UIStroke');edge.Color=NAVY;edge.Thickness=2.5;edge.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;edge.Parent=pill
 local label=Instance.new('TextLabel');label.Name='DogName'
 label.BackgroundTransparency=1;label.Position=UDim2.fromOffset(0,32);label.Size=UDim2.new(1,0,0,50)
 label.Font=Enum.Font.FredokaOne;label.TextScaled=true;label.TextColor3=WHITE;label.Text=nameText;label.Parent=bb
 local stroke=Instance.new('UIStroke');stroke.Color=NAVY;stroke.Thickness=3;stroke.Parent=label
 local shine=Instance.new('UIGradient');shine.Color=colors(WHITE,(P.VariantColors[info.Variant]or accent):Lerp(WHITE,.55));shine.Rotation=90;shine.Parent=label
 tween(scale,.35,{Scale=1},Enum.EasingStyle.Back)
 Audio.Play('Reveal',riser,rank)
 local burst=emitter(riser,{Speed=NumberRange.new(5,12),Lifetime=NumberRange.new(.5,1),Size=NumberSequence.new(.4,0),Color=colors(WHITE,accent,color)})
 burst:Emit(low and 10 or 28)
 local FLOAT=1.15+height*.15
 local age,lastK,dissolving=0,.2,false
 holograms+=1
 animate(function(dt)
  age+=dt
  if not model.Parent then return false end
  local k,y,yaw
  if age<.5 then
   local a=age/.5
   k=.2+.8*backOut(a);y=.3+FLOAT*smooth(a);yaw=(1-smooth(a))*math.pi*4
  elseif age<3.5 then
   local b=age-.5
   k=1;y=FLOAT+math.abs(math.sin(b*3.1))*.55*(1-b/6);yaw=math.sin(b*1.3)*.75
  else
   local a=math.min((age-3.5)/.6,1)
   k=1-.8*a*a;y=FLOAT+a*1.6;yaw=a*math.pi*3
   if not dissolving then
    dissolving=true;rise.Rate=0
    tween(scale,.3,{Scale=0},Enum.EasingStyle.Back,Enum.EasingDirection.In)
    local fizz=emitter(riser,{Rate=0,Shape=Enum.ParticleEmitterShape.Sphere,Speed=NumberRange.new(1,4),Lifetime=NumberRange.new(.5,1.1),
     Size=NumberSequence.new(.35,0),Color=colors(WHITE,accent)})
    riser.CFrame=CFrame.new(ground+Vector3.new(0,y+height*.4,0));riser.Size=Vector3.one*2.5
    fizz:Emit(low and 14 or 40)
   end
   for _,p in ipairs(parts)do p.Transparency=(alpha[p]or 0)+(1-(alpha[p]or 0))*a end
   hl.FillTransparency=.78+.22*a;hl.OutlineTransparency=.15+.85*a
   if a>=1 then return false end
  end
  if math.abs(k-lastK)>.004 then lastK=k;model:ScaleTo(base*k)end
  model:PivotTo(CFrame.new(ground+Vector3.new(0,y,0))*facing*CFrame.Angles(0,yaw,0)*CFrame.new(-g*k))
  tag.CFrame=CFrame.new(ground+Vector3.new(0,y+height*k+.6,0))
  -- Aura ring opens out and turns.
  local r=.4+2.1*smooth(math.min(age/.4,1))
  local frames={}
  for i,p in ipairs(ring)do
   local a=i/#ring*math.pi*2+age*.9
   local pos=ground+Vector3.new(math.cos(a)*r,.1,math.sin(a)*r)
   frames[i]=CFrame.lookAt(pos,pos+Vector3.new(-math.sin(a),0,math.cos(a)))
   p.Size=Vector3.new(.16,.12,2*math.pi*r/#ring*.8)
   if dissolving then p.Transparency=math.min(1,p.Transparency+dt*2)end
  end
  workspace:BulkMoveTo(ring,frames,Enum.BulkMoveMode.FireCFrameChanged)
  disc.Size=Vector3.new(.08,r*2.3,r*2.3)
  if dissolving then disc.Transparency=math.min(1,disc.Transparency+dt*1.5)end
  return true
 end,function()
  holograms-=1
  -- Let the last sparks fade before the folder goes.
  model:Destroy()
  for _,p in ipairs(ring)do p:Destroy()end
  disc:Destroy();bb:Destroy();hl:Destroy()
  task.delay(1.4,function()folder:Destroy()end)
 end)
end

---------------------------------------------------------------- burst
local function chunks(stage:any,power:number)
 local list=stage.CloneParts
 if not list or #list==0 then return end
 local center=stage.Anchor.Position
 local flying={}
 if stage.Low then
  -- Phones: the biggest pieces fly, the rest vanish in the flash.
  table.sort(list,function(a,b)return a.Size.Magnitude>b.Size.Magnitude end)
  for i,p in ipairs(list)do if i>18 then p.Transparency=1 end end
 end
 for i,p in ipairs(list)do
  if p.Parent and(not stage.Low or i<=18)then
   local off=p.Position-center
   local dir=off.Magnitude>.05 and off.Unit or Vector3.new(rng:NextNumber(-1,1),rng:NextNumber(0,1),rng:NextNumber(-1,1)).Unit
   local axis=Vector3.new(rng:NextNumber(-1,1),rng:NextNumber(-1,1),rng:NextNumber(-1,1))
   table.insert(flying,{Part=p,Pos=p.Position,Rot=p.CFrame.Rotation,V=dir*rng:NextNumber(.55,1)*power+Vector3.new(0,rng:NextNumber(5,13),0),
    Axis=axis.Magnitude>.01 and axis.Unit or Vector3.yAxis,W=rng:NextNumber(5,14),Life=rng:NextNumber(.7,1.15),Alpha=p.Transparency})
  end
 end
 local age=0
 local parts,frames={},{}
 for i,f in ipairs(flying)do parts[i]=f.Part end
 animate(function(dt)
  age+=dt
  if not stage.Clone or not stage.Clone.Parent then return false end
  local alive=false
  for i,f in ipairs(flying)do
   f.V+=Vector3.new(0,-46,0)*dt;f.V*=(1-.6*dt)
   f.Pos+=f.V*dt
   f.Rot*=CFrame.fromAxisAngle(f.Axis,f.W*dt)
   frames[i]=CFrame.new(f.Pos)*f.Rot
   local a=math.min(age/f.Life,1)
   f.Part.Transparency=f.Alpha+(1-f.Alpha)*a^1.8
   if a<1 then alive=true end
  end
  if #parts>0 then workspace:BulkMoveTo(parts,frames,Enum.BulkMoveMode.FireCFrameChanged)end
  return alive
 end,function()if stage.Clone then stage.Clone:Destroy()end end)
end

local function burst(stage:any)
 if stage.Phase=='burst'then return end
 stage.Phase='burst';stage.BurstClock=os.clock()
 local info=stage.Opened
 local tierRank=stage.Rank
 -- The opener's burst follows the block (no spoiler ahead of the roulette); spectators feel the dog.
 local rank=stage.Local and tierRank or math.max(tierRank,info and info.Rank or 1)
 local prof=P.Profile(rank,stage.Low)
 local color,accent=Show.World[rank],Show.Accent[rank]
 local void=rank==6
 local folder=stage.Folder
 local center=stage.Anchor.Position
 local ground=stage.Ground
 stage.Suck.Rate=0
 for _,ray in ipairs(stage.Rays)do ray.Beam:Destroy()end
 table.clear(stage.Rays)
 Audio.Play('Burst',stage.Anchor,rank)
 -- Flash and light spike.
 stage.Light.Range=prof.Light*3;stage.Light.Brightness=stage.Reduced and 3 or prof.Light
 tween(stage.Light,.7,{Brightness=0})
 if not stage.Reduced then
  local flash=part({Name='BurstFlash',Shape=Enum.PartType.Ball,Color=void and Show.Accent[6]or color:Lerp(WHITE,.5),Transparency=.05,
   Size=Vector3.one*1.2,CFrame=CFrame.new(center),Parent=folder})
  tween(flash,.32,{Size=Vector3.one*prof.Flash,Transparency=1})
 end
 if void then
  -- The collapsed singularity blows out: a black sphere in a violet shell, then darkness rings.
  if stage.VoidCore and stage.VoidRim then
   stage.VoidCore.Transparency=.05;stage.VoidRim.Transparency=.5
   tween(stage.VoidCore,.55,{Size=Vector3.one*prof.Flash*.9,Transparency=1},Enum.EasingStyle.Quart)
   tween(stage.VoidRim,.65,{Size=Vector3.one*prof.Flash*1.25,Transparency=1},Enum.EasingStyle.Quart)
  end
  local smoke=emitter(stage.Anchor,{Texture=SMOKE,LightEmission=.15,Speed=NumberRange.new(6,14),Drag=3,Lifetime=NumberRange.new(.9,1.6),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.5),NumberSequenceKeypoint.new(1,5)}),Color=colors(Color3.fromRGB(60,20,110),VOID_BLACK),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,1)}),RotSpeed=NumberRange.new(-60,60)})
  smoke:Emit(stage.Low and 5 or 14)
 end
 if stage.Rank==6 then
  -- A Secret block already collapsed into its void; nothing is left to fly apart.
  if stage.Clone then stage.Clone:Destroy();stage.Clone=nil end
 else
  chunks(stage,prof.Chunk)
 end
 -- Shockwaves on the pad.
 local segs=stage.Low and 12 or(rank>=5 and 32 or 24)
 local ringColors=void and{VOID_BLACK,color,accent}or{color,accent,WHITE}
 for i=1,prof.Rings do
  task.delay((i-1)*.09,function()
   if not folder.Parent then return end
   local c=ringColors[i]
   shockRing(folder,ground+Vector3.new(0,.12+i*.03,0),c,1,prof.Reach*(1-(i-1)*.18),.55+i*.12,segs,(.7-(i-1)*.15)*(stage.Scale/.68),
    c==VOID_BLACK and Enum.Material.SmoothPlastic or nil)
  end)
 end
 local shock=groundDisc(folder,ground+Vector3.new(0,.08,0),color,1.5,.35)
 tween(shock,.5,{Size=Vector3.new(.08,prof.Reach*1.4,prof.Reach*1.4),Transparency=1})
 -- Sparkles and confetti (Mythic gets the rainbow).
 local rainbow=rank==5 and colors(Color3.fromRGB(255,70,90),Color3.fromRGB(255,200,40),Color3.fromRGB(80,230,120),Color3.fromRGB(60,180,255),Color3.fromRGB(200,90,255))
 local sparks=emitter(stage.Anchor,{Speed=NumberRange.new(14,30),Drag=2.2,Acceleration=Vector3.new(0,-22,0),Lifetime=NumberRange.new(.7,1.5),
  Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,0)}),RotSpeed=NumberRange.new(-200,200),
  Rotation=NumberRange.new(0,360),Color=rainbow or colors(WHITE,accent,color)})
 sparks:Emit(prof.Sparks)
 if rank>=4 and not stage.Low then
  local embers=emitter(stage.Anchor,{Texture=FIRE,Speed=NumberRange.new(8,18),Drag=1.5,Acceleration=Vector3.new(0,6,0),Lifetime=NumberRange.new(.5,1),
   Size=NumberSequence.new(1.2,0),Color=void and colors(Show.Accent[6],color)or colors(Color3.fromRGB(255,240,180),color),LightEmission=.9})
  embers:Emit(math.floor(prof.Sparks*.25))
 end
 -- The beam flares and fades.
 local pillar=stage.Pillar
 if pillar.Transparency<1 then
  local tall=pillar.Size.X*1.25
  tween(pillar,.75,{Size=Vector3.new(tall,pillar.Size.Y*2.6,pillar.Size.Z*2.6),Transparency=1,
   CFrame=CFrame.new(center+Vector3.new(0,tall/2,0))*CFrame.Angles(0,0,math.pi/2)})
  if stage.Halo then tween(stage.Halo,.75,{Size=Vector3.new(tall,stage.Halo.Size.Y*2.2,stage.Halo.Size.Z*2.2),Transparency=1,
   CFrame=CFrame.new(center+Vector3.new(0,tall/2,0))*CFrame.Angles(0,0,math.pi/2)})end
 end
 tween(stage.Pool,.6,{Transparency=1})
 for _,p in ipairs(stage.Runes)do tween(p,.4,{Transparency=1})end
 -- The dog: spectators see it now; the opener after the roulette card (no spoiler through it).
 if info and(info.Rank or 1)<6 then
  local spot=ground
  if stage.Local then
   task.spawn(function()
    local t0=os.clock()
    while os.clock()-t0<1.5 and not rewardOverlay()do task.wait(.1)end
    while rewardOverlay()and os.clock()-t0<45 do task.wait(.25)end
    popDog(info,spot)
   end)
  else
   task.delay(.08,popDog,info,spot)
  end
 end
 task.delay(2.6,finish,stage)
end

---------------------------------------------------------------- abort
local function abort(stage:any)
 if not stage.Alive or stage.Phase=='burst'or stage.Opened then return end
 if stage.Local then clearCharge(stage.Uid)end
 -- A fizzle: the clone deflates in a puff of smoke and the real block comes back.
 local puffAt=stage.Anchor and stage.Anchor.Position
 restoreOriginal(stage)
 finish(stage)
 if puffAt then
  local folder=Instance.new('Folder');folder.Name='LuckyFizzle';folder.Parent=fxRoot()
  local a=part({Name='Fizzle',Size=Vector3.one*.2,Transparency=1,CFrame=CFrame.new(puffAt),Parent=folder})
  emitter(a,{Texture=SMOKE,LightEmission=0,Speed=NumberRange.new(1,4),Lifetime=NumberRange.new(.6,1),Size=NumberSequence.new(1,2.5),
   Color=colors(Color3.fromRGB(200,205,215)),Transparency=NumberSequence.new(.4,1)}):Emit(6)
  Audio.Play('Shake',a,.2)
  task.delay(1.6,function()folder:Destroy()end)
 end
end

---------------------------------------------------------------- start
local function startStage(m:Model,uid:string,isLocal:boolean,startAt:number,length:number)
 if m:GetAttribute('LuckyShowStyle')then return nil end -- event blocks (pumpkins): StarterPlayerScripts.PumpkinBlockFX
 local pivot=m:GetPivot()
 if cameraDistance(pivot.Position)>NEAR then return nil end
 local scale=m:GetScale()
 local okBox,boxCf,boxSize=pcall(function()return m:GetBoundingBox()end)
 local bottom=okBox and boxCf.Position.Y-boxSize.Y/2 or pivot.Position.Y-(3*scale+.1)
 local stage:any={Uid=uid,Local=isLocal,StartAt=startAt,Len=length,Phase='charge',Alive=true,Conns={},Hidden={},Angle=0,
  Rank=Show.Rank(m:GetAttribute('LuckyBlockTier')or m:GetAttribute('LuckyRank')or 1),Low=Show.Low(),Reduced=Show.ReducedMotion(),
  Pivot=pivot,Center=pivot.Position,Ground=Vector3.new(pivot.Position.X,bottom,pivot.Position.Z),Scale=scale>0 and scale or .68,CloneParts={},Panels={}}
 stage.Profile=P.Profile(stage.Rank,stage.Low)
 stage.Folder=Instance.new('Folder');stage.Folder.Name='LuckyOpening';stage.Folder.Parent=fxRoot()
 stages[uid]=stage
 local built,err=pcall(function()
  makeClone(stage,m)
  adopt(stage,m)
  buildCharge(stage)
 end)
 if not built then
  -- Never leave the real block hidden behind a half-built show.
  warn('LuckyLifecycleFX opening:',err)
  restoreOriginal(stage);finish(stage)
  return nil
 end
 table.insert(stage.Conns,m:GetAttributeChangedSignal('OpenMessage'):Connect(function()if stage.Original==m then abort(stage)end end))
 Audio.Play('Charge',stage.Anchor,stage.Rank,math.max(.3,startAt+length-now()))
 if isLocal then
  publishCharge(uid,startAt)
  holdPrompts(stage)
  cameraStart(stage)
 end
 local last=os.clock()
 animate(function()
  if not stage.Alive or stage.Phase~='charge'and stage.Phase~='hold'then return false end
  local clock=os.clock();local dt=clock-last;last=clock
  local t=(now()-stage.StartAt)/stage.Len
  if t>=1 then
   if stage.Opened then burst(stage);return false
   end
   stage.Phase='hold'
   if now()-stage.StartAt>HOLD_TIMEOUT then abort(stage);return false end
  end
  stepCharge(stage,math.min(t,1),math.max(0,(t-1)*stage.Len),dt)
  return true
 end,function()
  -- A charge that ended without a burst or an abort (an error) must not leave the block hidden.
  if stage.Alive and stage.Phase~='burst'then
   if stage.Local then clearCharge(stage.Uid)end
   restoreOriginal(stage);finish(stage)
  end
 end)
 return stage
end

-- Local prediction: the player just pressed OPEN on one of their own ready blocks.
local function onPrediction()
 local uid=player:GetAttribute('LuckyBlockOpeningUid')
 if type(uid)~='string'or uid==''then
  -- Cleared: by GUIIntegration on success (OpenedBlock) or by LuckyBlockUI on failure.
  for _,stage in pairs(stages)do
   if stage.Local and not stage.Opened then
    task.delay(1.2,function()if stages[stage.Uid]==stage and not stage.Opened and player:GetAttribute('LuckyBlockOpeningUid')~=stage.Uid then abort(stage)end end)
   end
  end
  return
 end
 local at=tonumber(player:GetAttribute('LuckyBlockOpeningAt'))
 local t=now()
 if at and t-at>PREDICT_WINDOW then return end
 if stages[uid]then return end
 local m=modelForUid(uid)
 if not m or m:GetAttribute('OwnerUserId')~=player.UserId then return end
 local state=m:GetAttribute('BlockState')
 if state~='Ready'and state~='Placed'then return end
 startStage(m,uid,true,t,Show.Timing.Charge)
end

-- BlockState became Opened: feed a running charge, or play the short version.
onOpened=function(m:Model)
 local uid=m:GetAttribute('OwnedBlockUid')
 if type(uid)~='string'then return end
 local info=readOpened(m)
 local stage=stages[uid]
 if stage and stage.Alive then
  if not stage.Opened then stage.Opened=info end
  return
 end
 startLate(m,uid,info)
end
startLate=function(m:Model,uid:string,info)
 local mine=m:GetAttribute('OwnerUserId')==player.UserId
 local t=now()
 local plan,startAt=P.LatePlan(t,info.OpenedAt,SPECTATOR_CHARGE)
 if plan=='skip'then return end
 if mine then startAt=t end -- the opener's clock: the burst lands SPECTATOR_CHARGE from now
 local length=plan=='burst'and .05 or SPECTATOR_CHARGE
 local stage=startStage(m,uid,false,startAt or t,length)
 if not stage then return end
 stage.Opened=info
 if mine then
  -- No prediction was seen here: still tell the roulette when the burst lands.
  stage.Local=true
  publishCharge(uid,P.ChargeAt((startAt or t)+length,Show.Timing.Charge))
  holdPrompts(stage)
 end
end

---------------------------------------------------------------- pad models
local function watch(m:Instance)
 if not m:IsA('Model')or rows[m]or m:GetAttribute('LuckyFXClone')or not m:GetAttribute('OwnedBlockUid')then return end
 local row={Parts={},Phase=0}
 rows[m]=row
 row.Conn=m:GetAttributeChangedSignal('BlockState'):Connect(function()
  if m:GetAttribute('BlockState')=='Opened'then onOpened(m)end
 end)
 local uid=m:GetAttribute('OwnedBlockUid')
 local stage=stages[uid]
 -- The server rebuilt this block (Placed -> Ready) while it was charging: hide the new one too.
 if stage and stage.Alive and stage.Phase~='burst'and m:GetAttribute('BlockState')~='Opened'then
  adopt(stage,m)
  table.insert(stage.Conns,m:GetAttributeChangedSignal('OpenMessage'):Connect(function()if stage.Original==m then abort(stage)end end))
 end
 if m:GetAttribute('BlockState')=='Opened'then task.defer(onOpened,m)end
end
local function hookFolder(folder:Instance)
 for _,m in ipairs(folder:GetChildren())do watch(m)end
 folder.ChildAdded:Connect(watch)
end
local blocks=workspace:FindFirstChild('OwnedLuckyBlocks')
if blocks then hookFolder(blocks)else
 local conn;conn=workspace.ChildAdded:Connect(function(c)
  if c.Name=='OwnedLuckyBlocks'and c:IsA('Folder')then conn:Disconnect();hookFolder(c)end
 end)
end

-- Opening prediction from the pad prompt (LuckyBlockUI sets the same attributes for its button).
PPS.PromptTriggered:Connect(function(prompt)
 if prompt.Name~='PlaceLuckyBlock'or prompt.ActionText~='OPEN BLOCK'then return end
 local pad=prompt.Parent;local uid=pad and pad:GetAttribute('LuckyBlockUid')
 -- At before Uid: listeners of the uid read a fresh timestamp.
 if type(uid)=='string'and uid~=''then player:SetAttribute('LuckyBlockOpeningAt',workspace:GetServerTimeNow());player:SetAttribute('LuckyBlockOpeningUid',uid)end
end)
player:GetAttributeChangedSignal('LuckyBlockOpeningUid'):Connect(onPrediction)
player:GetAttributeChangedSignal('LuckyBlockOpeningAt'):Connect(onPrediction)

-- Server answers: the reward card confirms an open even if the model never replicates
-- Opened here; a plain Message while a local charge waits means the open failed.
task.spawn(function()
 local remote=RS:WaitForChild('RewardPresentation',30)
 if not remote or not remote:IsA('RemoteEvent')then return end
 remote.OnClientEvent:Connect(function(data)
  if type(data)~='table'then return end
  local opened=data.OpenedBlock
  if type(opened)=='table'and type(opened.BlockUid)=='string'then
   local stage=stages[opened.BlockUid]
   local dog=type(opened.Dog)=='table'and opened.Dog
   if stage and stage.Alive and not stage.Opened and dog then
    local defs=definitions();local def=defs and defs[dog.DogId]
    stage.Opened={DogId=dog.DogId,Rank=def and def.Rank or 1,Variant=tostring(dog.Variant or'Normal'),Name=dog.DisplayName or dog.DogId,OpenedAt=now()}
   end
   return
  end
  if type(data.Message)=='string'and not data.Credits and not data.Message:find('reward: %+')then
   for _,stage in pairs(stages)do if stage.Local and not stage.Opened then abort(stage)end end
  end
 end)
end)

---------------------------------------------------------------- timer text + progress look
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<.12 then return end;elapsed=0
 local camera=workspace.CurrentCamera;if not camera then return end
 local t=now();local low=Show.Low()
 local pendingUid=player:GetAttribute('LuckyBlockOpeningUid');local pendingAt=tonumber(player:GetAttribute('LuckyBlockOpeningAt'))or 0
 for m,row in pairs(rows)do
  if not m.Parent then rows[m]=nil;clearCracks(row);if row.Conn then row.Conn:Disconnect()end;continue end
  local ok,err=pcall(function()
   local ready=m:GetAttribute('ReadyAt');local placed=m:GetAttribute('PlacedAt');local state=m:GetAttribute('BlockState');local text=m:FindFirstChild('TimerText',true)
   local uid=m:GetAttribute('OwnedBlockUid')
   local predicted=pendingUid==uid and pendingAt>0 and t-pendingAt<PREDICT_WINDOW
   local progress=ready and placed and math.clamp((t-placed)/math.max(1,ready-placed),0,1)or 0
   if text and text:IsA('TextLabel')then
    text.Text=predicted and 'OPENING…'or state=='Carried'and 'CARRY TO YOUR YARD'or state=='Opened'and 'GOOD FIND!'or m:GetAttribute('OpenMessage')
     or(state=='Ready'or ready and ready<=t)and 'READY · PRESS E TO OPEN'or('PREPARING · '..math.max(0,math.ceil((ready or t)-t))..'s')
   end
   if m:GetAttribute('LuckyShowStyle')then clearCracks(row);return end -- pumpkins: PumpkinBlockFX owns the progress look
   if stages[uid]then clearCracks(row);return end -- the opening show owns this block
   local pivot=m:GetPivot()
   local near=(camera.CFrame.Position-pivot.Position).Magnitude<PROGRESS_NEAR
   if not near or(state~='Placed'and state~='Ready')then clearCracks(row);return end
   local phase=math.floor(progress*4)
   if phase>=2 and(not row.Cracks or(row.CrackPivot.Position-pivot.Position).Magnitude>.05)then
    clearCracks(row)
    local folder=Instance.new('Folder');folder.Name='OpeningCrackFX';folder.Parent=fxRoot()
    row.Cracks=folder;row.CrackPivot=pivot;row.CrackParts={}
    local scale=m:GetScale()
    for face=0,(low and 1 or 3)do for i=1,3 do
     local crack=part({Name='OpeningCrackFX',Color=Color3.fromRGB(255,216,123),Size=Vector3.new(.06,1.1,.035)*scale,
      CFrame=pivot*CFrame.Angles(0,face*math.pi/2,0)*CFrame.new((i%2)*.3*scale,(i-2)*.85*scale,-3.08*scale)*CFrame.Angles(0,0,i%2==0 and -.4 or .4),
      Parent=folder})
     table.insert(row.CrackParts,crack)
    end end
   end
   if row.CrackParts then for _,crack in ipairs(row.CrackParts)do crack.Transparency=math.clamp(1-progress,0,.8)end end
   if phase>row.Phase then row.Phase=phase;if phase>=2 and m:GetAttribute('OwnerUserId')==player.UserId then Audio.Play('Crack',m.PrimaryPart)end end
   for _,p in ipairs(m:GetDescendants())do if p:IsA('BasePart')and(p.Name=='InsetPanel'or p.Name=='Lid')then
    row.Parts[p]=row.Parts[p]or{CFrame=p.CFrame,Color=p.Color}
    local original=row.Parts[p];p.Color=original.Color:Lerp(Color3.fromRGB(255,220,146),math.max(0,progress-.55)*.8)
    if not low and p.Name=='Lid'then local shake=predicted and math.sin(t*48)*.14 or math.sin(t*12)*progress*.035;p.CFrame=original.CFrame*CFrame.new(0,math.max(0,progress-.85)*2+shake,0)end
   end end
  end)
  if not ok then warn('LuckyLifecycleFX progress:',err)end
 end
end)

-- Warm the roulette early so its dog cards are prepared during the very first charge
-- (RewardScreens, which also warms it, is only loaded when the first reward arrives).
task.spawn(function()
 local gui=player:WaitForChild('PlayerGui'):WaitForChild('ScreenGui',60)
 local modules=gui and gui:WaitForChild('Modules',30)
 local reel=modules and modules:WaitForChild('LuckyReel',30)
 if not reel then return end
 local ok,module=pcall(require,reel)
 if ok and type(module)=='table'and module.Warm then pcall(module.Warm)end
end)
