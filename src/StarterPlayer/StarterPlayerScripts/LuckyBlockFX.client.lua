-- Persistent client aura for every Lucky Block in the world (conveyor 03_DogLine.ActiveDogs and
-- workspace.OwnedLuckyBlocks). The server builds static, welded models (LuckyBlockVisuals); all
-- motion and glow is client-local decor that follows the block's RootPart each frame:
--   Rare      thin rotating cyan ring + sparkles
--   Epic      two counter-rotating rune rings + sparkles
--   Legendary orbiting golden gems, golden ground halo, glints and rising sparkles
--   Mythic    rotating crown halo of jewels, crimson light pillar, ember fountain
--   Secret    accretion disk of neon-edged obsidian shards, ForceField gravitational lens,
--             inward particle vortex, event-horizon rings, pulsing light, outline Highlight
-- Decor lives in workspace.DOGROTS_LuckyFX (outside DOGROTS_District, whose WorldDetailQuality
-- throttles lights/emitters, and outside the block models). Only the nearest blocks within range
-- get decor; Low quality (and touch devices by default) gets a cheap ring + light version,
-- ReducedMotion drops bobbing and pulsing. Decor disappears when the pad-opening FX takes over
-- (model attribute LuckyOpening), when the block is Opened/Claimed/Despawning, when it streams
-- out or leaves workspace, and is never built for the opening FX's own clone (LuckyFXClone).
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer

local Show=nil
do
 local ok,mod=pcall(function()return require(RS:WaitForChild('Lucky',10):WaitForChild('LuckyShow',10))end)
 if ok and type(mod)=='table'then Show=mod end
end
local function isLow()
 if Show then return Show.Low()end
 local choice=player:GetAttribute('WorldEventFX')
 return choice=='Low'or player:GetAttribute('LowFX')==true or player:GetAttribute('ReducedMotion')==true or(choice==nil and UIS.TouchEnabled)
end
local function reducedMotion()
 if Show then return Show.ReducedMotion()end
 return player:GetAttribute('ReducedMotion')==true
end
local function rankOf(m:Model):number
 local r=tonumber(m:GetAttribute('LuckyRank'))
 if r then return math.clamp(math.floor(r),1,6)end
 local tier=m:GetAttribute('LuckyBlockRarity')or m:GetAttribute('LuckyBlockTier')
 if Show and tier then return Show.Rank(tier)end
 return 1
end

local RANGE,RANGE_LOW=120,70 -- studs from the camera
local MAX_DECOR=14 -- nearest blocks that get decor
local CHECK=.2 -- seconds between visibility/quality passes
local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local FIRE='rbxasset://textures/particles/fire_main.dds'
local rgb=Color3.fromRGB
local NEON=Enum.Material.Neon
local BEZ=.5523 -- quarter-circle Bezier handle factor

local function fxRoot():Instance
 local root=workspace:FindFirstChild('DOGROTS_LuckyFX')
 if not root then root=Instance.new('Folder');root.Name='DOGROTS_LuckyFX';root.Parent=workspace end
 return root
end

---------------------------------------------------------------- instance helpers
local function newPart(name:string,size:Vector3,color:Color3,material:Enum.Material,shape:Enum.PartType?,transparency:number?):Part
 local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 p.Massless=true;p.Size=size;p.Color=color;p.Material=material;p.Transparency=transparency or 0
 p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if shape then p.Shape=shape end
 return p
end
local function holder(name:string,size:number):Part
 return newPart(name,Vector3.one*size,Color3.new(1,1,1),Enum.Material.SmoothPlastic,nil,1)
end
local function fade(a:number,b:number):NumberSequence
 return NumberSequence.new({NumberSequenceKeypoint.new(0,a),NumberSequenceKeypoint.new(.5,math.min(a,b)),NumberSequenceKeypoint.new(1,b)})
end
-- Circle of four curved FaceCamera beams in the holder's XZ plane. The transparency dips along
-- each quarter, so the rotation reads; an optional texture scrolls (rune/glitter look).
local function beamRing(parent:BasePart,r:number,width:number,c0:Color3,c1:Color3,t0:number,t1:number,texture:string?,texSpeed:number?)
 local atts={}
 for i=0,3 do
  local a=i*math.pi/2
  local at=Instance.new('Attachment');at.Name='Ring'
  at.CFrame=CFrame.fromMatrix(Vector3.new(math.cos(a)*r,0,math.sin(a)*r),Vector3.new(-math.sin(a),0,math.cos(a)),Vector3.yAxis)
  at.Parent=parent;atts[i]=at
 end
 for i=0,3 do
  local b=Instance.new('Beam');b.Attachment0=atts[i];b.Attachment1=atts[(i+1)%4]
  b.CurveSize0=BEZ*r;b.CurveSize1=BEZ*r;b.Segments=14;b.FaceCamera=true
  b.Width0=width;b.Width1=width;b.LightEmission=1;b.LightInfluence=0
  b.Color=ColorSequence.new(c0,c1)
  b.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,t0),NumberSequenceKeypoint.new(.5,t1),NumberSequenceKeypoint.new(1,t0)})
  if texture then b.Texture=texture;b.TextureMode=Enum.TextureMode.Wrap;b.TextureLength=math.max(.5,r*.7);b.TextureSpeed=texSpeed or .5 end
  b.Parent=parent
 end
end
local function sparkles(parent:Instance,color:Color3,rate:number,size:number,speed:number,life:number):ParticleEmitter
 local e=Instance.new('ParticleEmitter');e.Name='AuraSparkles';e.Texture=SPARK;e.Rate=rate
 e.Color=ColorSequence.new(color,Color3.new(1,1,1));e.LightEmission=1;e.LightInfluence=0
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.25,size),NumberSequenceKeypoint.new(1,0)})
 e.Transparency=fade(.1,1);e.Lifetime=NumberRange.new(life*.7,life*1.2);e.Speed=NumberRange.new(speed*.5,speed)
 e.EmissionDirection=Enum.NormalId.Top;e.SpreadAngle=Vector2.new(25,25);e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-90,90)
 e.LockedToPart=false;e.Parent=parent
 return e
end

---------------------------------------------------------------- per-tier decor
-- A decor is {Folder, Root, Movers={{Part,Fn(base,t)->CFrame}}, Pulse=fn(t)?}. All sizes are in
-- unscaled block units (body half-size 2.725) times k, the model's current scale.
type Mover={Part:BasePart,Fn:(CFrame,number)->CFrame}
type Decor={Folder:Folder,Root:BasePart,Movers:{Mover},Low:boolean,Motion:boolean,Pulse:((number)->())?}

local function build(rank:number,root:BasePart,k:number,low:boolean,motion:boolean):Decor?
 if rank<2 then return nil end
 local folder=Instance.new('Folder');folder.Name='LuckyAura'..rank
 local movers:{Mover}={}
 local spin=motion and 1 or .4
 local function bob(t:number,phase:number,amp:number):number
  return motion and math.sin(t*1.6+phase)*amp*k or 0
 end
 local function move(p:BasePart,fn:(CFrame,number)->CFrame)
  table.insert(movers,{Part=p,Fn=fn});p.Parent=folder
 end
 -- Invisible anchor at the block centre (emitter volume + pillar attachments).
 local anchor=holder('AuraAnchor',6*k)
 move(anchor,function(base)return base end)
 local decor:Decor={Folder=folder,Root=root,Movers=movers,Low=low,Motion=motion}

 if rank==2 then
  local ring=holder('CyanRing',.2)
  beamRing(ring,4.7*k,.22*k,rgb(40,226,255),rgb(170,255,255),.05,.75)
  move(ring,function(base,t)return base*CFrame.new(0,-.5*k+bob(t,0,.18),0)*CFrame.Angles(math.rad(10),0,math.rad(6))*CFrame.Angles(0,t*.9*spin,0)end)
  if not low then sparkles(anchor,rgb(80,230,255),3,.28*k,1.2*k,1.4)end

 elseif rank==3 then
  local a=holder('RuneRingA',.2)
  beamRing(a,4.9*k,.34*k,rgb(255,120,246),rgb(190,84,255),.05,.55,SPARK,.7)
  move(a,function(base,t)return base*CFrame.new(0,bob(t,0,.15),0)*CFrame.Angles(math.rad(20),0,0)*CFrame.Angles(0,t*1.1*spin,0)end)
  if not low then
   local b=holder('RuneRingB',.2)
   beamRing(b,4.5*k,.26*k,rgb(170,110,255),rgb(255,170,255),.1,.7,SPARK,-.9)
   move(b,function(base,t)return base*CFrame.new(0,bob(t,2,.15),0)*CFrame.Angles(math.rad(-18),0,math.rad(12))*CFrame.Angles(0,-t*1.4*spin,0)end)
   sparkles(anchor,rgb(255,130,250),6,.3*k,1.4*k,1.3)
  end

 elseif rank==4 then
  local halo=holder('GoldHalo',.2)
  beamRing(halo,4.6*k,.5*k,rgb(255,198,52),rgb(255,248,196),.25,.7,SPARK,.4)
  move(halo,function(base,t)return base*CFrame.new(0,-2.95*k,0)*CFrame.Angles(0,t*.5*spin,0)end)
  if not low then
   for i=0,3 do
    local gem=newPart('OrbitGem',Vector3.one*.55*k,i%2==0 and rgb(255,214,64)or rgb(255,248,196),NEON,Enum.PartType.Ball)
    move(gem,function(base,t)
     local a=t*.8*spin+i*math.pi/2
     return base*CFrame.new(math.cos(a)*4.9*k,.4*k+(motion and math.sin(t*1.7+i)*.55*k or 0),math.sin(a)*4.1*k)
    end)
   end
   local glint=sparkles(anchor,rgb(255,250,220),1.3,1.5*k,0,.32);glint.Name='Glint';glint.Shape=Enum.ParticleEmitterShape.Box;glint.LockedToPart=true
   glint.SpreadAngle=Vector2.new(0,0);glint.RotSpeed=NumberRange.new(0,0);glint.Rotation=NumberRange.new(0,0)
   local rise=sparkles(anchor,rgb(255,206,72),5,.26*k,2.2*k,1.5);rise.Shape=Enum.ParticleEmitterShape.Box
  end

 elseif rank==5 then
  -- Crown halo above the crown: a gold ring with eight rainbow jewels turning around it.
  local crownY=5.2*k
  local halo=holder('CrownHalo',.2)
  beamRing(halo,2.35*k,.18*k,rgb(255,196,48),rgb(255,240,170),.05,.6,SPARK,.8)
  move(halo,function(base,t)return base*CFrame.new(0,crownY+bob(t,0,.12),0)*CFrame.Angles(0,t*1.2*spin,0)end)
  if not low then
   for i=0,7 do
    local jewel=newPart('HaloJewel',Vector3.one*.42*k,Color3.fromHSV(i/8,.7,1),NEON,Enum.PartType.Ball)
    move(jewel,function(base,t)
     local a=t*1.2*spin+i*math.pi/4
     return base*CFrame.new(math.cos(a)*2.35*k,crownY+bob(t,i,.12)+(motion and math.sin(t*3+i)*.12*k or 0),math.sin(a)*2.35*k)
    end)
   end
  end
  -- Crimson light pillar rising from the block.
  local p0=Instance.new('Attachment');p0.CFrame=CFrame.new(0,-2.9*k,0);p0.Parent=anchor
  local p1=Instance.new('Attachment');p1.CFrame=CFrame.new(0,16*k,0);p1.Parent=anchor
  local beam=Instance.new('Beam');beam.Name='CrimsonPillar';beam.Attachment0=p0;beam.Attachment1=p1;beam.FaceCamera=true
  beam.Width0=5.6*k;beam.Width1=1.4*k;beam.LightEmission=1;beam.LightInfluence=0;beam.Segments=4
  beam.Color=ColorSequence.new(rgb(255,56,98),rgb(255,198,52))
  beam.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.5),NumberSequenceKeypoint.new(.35,.72),NumberSequenceKeypoint.new(1,1)})
  beam.Parent=anchor
  if not low then
   local glitter=beam:Clone();glitter.Name='PillarGlitter';glitter.Width0=3.4*k;glitter.Width1=.8*k;glitter.Texture=SPARK
   glitter.TextureMode=Enum.TextureMode.Wrap;glitter.TextureLength=2.5*k;glitter.TextureSpeed=.6
   glitter.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,1)});glitter.Parent=anchor
   -- Ember fountain from the crown.
   local top=Instance.new('Attachment');top.CFrame=CFrame.new(0,4.6*k,0);top.Parent=anchor
   local e=Instance.new('ParticleEmitter');e.Name='Embers';e.Texture=FIRE;e.Rate=16
   e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,rgb(255,236,140)),ColorSequenceKeypoint.new(.5,rgb(255,140,40)),ColorSequenceKeypoint.new(1,rgb(255,40,80))})
   e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.34*k),NumberSequenceKeypoint.new(1,0)})
   e.Transparency=fade(0,1);e.LightEmission=1;e.LightInfluence=0;e.Lifetime=NumberRange.new(1,1.5)
   e.Speed=NumberRange.new(5*k,8*k);e.SpreadAngle=Vector2.new(26,26);e.Acceleration=Vector3.new(0,-9*k,0)
   e.EmissionDirection=Enum.NormalId.Top;e.Drag=.4;e.Parent=top
  end

 else -- Secret: cosmic singularity
  local tilt=CFrame.Angles(math.rad(24),0,math.rad(-7))
  -- Gravitational lens: a shimmering ForceField bubble around the block.
  local lens=newPart('GravityLens',Vector3.one*8.4*k,rgb(150,72,255),Enum.Material.ForceField,Enum.PartType.Ball,.4)
  move(lens,function(base,t)return base*CFrame.Angles(0,t*.25*spin,0)end)
  local horizon=holder('EventHorizon',.2)
  beamRing(horizon,5.3*k,.36*k,rgb(150,70,255),rgb(60,240,255),.0,.5,SPARK,.5)
  move(horizon,function(base,t)return base*CFrame.new(0,-.16*k,0)*tilt*CFrame.Angles(0,t*.45*spin,0)end)
  if not low then
   local outer=holder('OuterHorizon',.2)
   beamRing(outer,6.5*k,.16*k,rgb(60,240,255),rgb(220,200,255),.1,.75,SPARK,-.8)
   move(outer,function(base,t)return base*CFrame.new(0,-.16*k,0)*tilt*CFrame.Angles(0,-t*.3*spin,0)end)
  end
  -- Accretion disk: neon-edged obsidian shards orbiting in the horizon plane, inner ones faster.
  local count=low and 4 or 10
  local rng=Random.new(7)
  for i=1,count do
   local r=(5.0+(i-1)/math.max(1,count-1)*1.9)*k
   local w=1.5*(5.0*k/r)^1.5*spin
   local phase=i*2.39996
   local h=rng:NextNumber(.7,1.15)
   local dark=newPart('ShardCore',Vector3.new(.22,.9*h,.46)*k,rgb(10,4,22),Enum.Material.Glass)
   local fn=function(base:CFrame,t:number):CFrame
    local a=phase+t*w
    return base*CFrame.new(0,-.16*k,0)*tilt*CFrame.Angles(0,-a,0)*CFrame.new(r,(motion and math.sin(t*2+i)*.12*k or 0),0)*CFrame.Angles(t*1.3+i,0,.5)
   end
   if not low then
    local edge=newPart('ShardEdge',Vector3.new(.32,(.9*h+.1),.36)*k,i%2==0 and rgb(60,240,255)or rgb(176,86,255),NEON)
    move(edge,fn)
    move(dark,fn)
   else
    dark.Material=NEON;dark.Color=i%2==0 and rgb(60,240,255)or rgb(176,86,255)
    move(dark,fn)
   end
  end
  if not low then
   -- Inward vortex from the lens surface toward the singularity.
   local v=Instance.new('ParticleEmitter');v.Name='Vortex';v.Texture=SPARK;v.Rate=22
   v.Shape=Enum.ParticleEmitterShape.Sphere;v.ShapeStyle=Enum.ParticleEmitterShapeStyle.Surface;v.ShapeInOut=Enum.ParticleEmitterShapeInOut.Inward
   v.Speed=NumberRange.new(3*k,3.6*k);v.Lifetime=NumberRange.new(1.05,1.25);v.LockedToPart=true
   v.Color=ColorSequence.new(rgb(60,240,255),rgb(176,86,255))
   v.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.1*k),NumberSequenceKeypoint.new(.6,.32*k),NumberSequenceKeypoint.new(1,0)})
   v.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.3,.1),NumberSequenceKeypoint.new(1,.6)})
   v.LightEmission=1;v.LightInfluence=0;v.Rotation=NumberRange.new(0,360);v.RotSpeed=NumberRange.new(-200,200);v.Parent=lens
   local dust=sparkles(anchor,rgb(200,170,255),3,.22*k,.8*k,1.6);dust.Shape=Enum.ParticleEmitterShape.Box
  end
  -- Lens breathing (and the light pulse below) only with motion.
  if motion then
   local baseSize=lens.Size
   decor.Pulse=function(t:number)
    local s=1+math.sin(t*2.2)*.035
    lens.Size=baseSize*s
   end
  end
 end
 return decor
end

---------------------------------------------------------------- registry
type Row={Model:Model,Rank:number,Emitters:{{any}},Lights:{Light},Conns:{RBXScriptConnection},Decor:Decor?,Dist:number,On:boolean}
local rows:{[Model]:Row}={}
local active:{Row}={} -- rows with decor, iterated every frame
local highlight:Highlight?=nil

local function destroyDecor(row:Row)
 local d=row.Decor
 if d then row.Decor=nil;pcall(function()d.Folder:Destroy()end)end
 local i=table.find(active,row);if i then table.remove(active,i)end
end
local function setInModel(row:Row,on:boolean,low:boolean)
 for _,e in row.Emitters do
  local emitter=e[1]
  if emitter.Parent then emitter.Enabled=on and not low;emitter.Rate=math.min(6,e[2])end
 end
 for _,l in row.Lights do if l.Parent then l.Enabled=on end end
end
local function unregister(m:Model)
 local row=rows[m];if not row then return end
 rows[m]=nil
 destroyDecor(row)
 for _,c in row.Conns do c:Disconnect()end
 if highlight and highlight.Adornee==m then highlight.Adornee=nil;highlight.Enabled=false end
end
local function hidden(m:Model):boolean
 if m:GetAttribute('LuckyOpening')==true or m:GetAttribute('LuckyFXClone')then return true end
 local state=m:GetAttribute('BlockState')
 if state=='Opened'then return true end
 local line=m:GetAttribute('State')
 return line=='Claimed'or line=='Despawning'
end
-- Immediate off-switch (the pad-opening FX must never fight our decor for a frame).
local function quickHide(row:Row)
 if not hidden(row.Model)then return end
 destroyDecor(row);setInModel(row,false,true)
 if highlight and highlight.Adornee==row.Model then highlight.Enabled=false;highlight.Adornee=nil end
end
local function register(inst:Instance)
 if not inst:IsA('Model')or rows[inst]or inst:GetAttribute('LuckyVisual')~=true then return end
 local m=inst::Model
 if m:GetAttribute('LuckyFXClone')then return end
 local fx=workspace:FindFirstChild('DOGROTS_LuckyFX')
 if fx and m:IsDescendantOf(fx)then return end
 local row:Row={Model=m,Rank=rankOf(m),Emitters={},Lights={},Conns={},Decor=nil,Dist=math.huge,On=false}
 rows[m]=row
 local function track(d:Instance)
  if d:IsA('ParticleEmitter')then table.insert(row.Emitters,{d,d.Rate})
  elseif d:IsA('Light')then table.insert(row.Lights,d)end
 end
 for _,d in m:GetDescendants()do track(d)end
 table.insert(row.Conns,m.DescendantAdded:Connect(track))
 table.insert(row.Conns,m.AttributeChanged:Connect(function(name)
  if name=='LuckyFXClone'and m:GetAttribute('LuckyFXClone')then unregister(m)
  elseif name=='LuckyRank'then row.Rank=rankOf(m);destroyDecor(row)
  elseif name=='LuckyOpening'or name=='BlockState'or name=='State'then quickHide(row)end
 end))
 table.insert(row.Conns,m.AncestryChanged:Connect(function()
  if not m:IsDescendantOf(workspace)then unregister(m)end
 end))
end
for _,d in workspace:GetDescendants()do register(d)end
workspace.DescendantAdded:Connect(register)

---------------------------------------------------------------- visibility pass (5 Hz)
local function refresh()
 local camera=workspace.CurrentCamera;if not camera then return end
 local low=isLow();local motion=not reducedMotion()
 local range=low and RANGE_LOW or RANGE
 local camPos=camera.CFrame.Position
 local wanted:{Row}={}
 for m,row in rows do
  if not m:IsDescendantOf(workspace)then unregister(m);continue end
  local root=m.PrimaryPart
  local ok=root~=nil and root:IsDescendantOf(m)and not hidden(m)
  row.Dist=if ok then((root::BasePart).Position-camPos).Magnitude else math.huge
  row.On=false
  if ok and row.Dist<range then table.insert(wanted,row)end
 end
 table.sort(wanted,function(a,b)return a.Dist<b.Dist end)
 local secretRow:Row?=nil
 local decorated=0
 for _,row in wanted do
  if row.Rank>=2 then
   if decorated>=MAX_DECOR then continue end
   decorated+=1
  end
  row.On=true
  if row.Rank==6 and not secretRow and row.Dist<90 then secretRow=row end
 end
 for m,row in rows do
  local root=m.PrimaryPart
  setInModel(row,row.On,low)
  if row.On and root then
   local d=row.Decor
   if d and(d.Root~=root or d.Low~=low or d.Motion~=motion or not d.Folder.Parent)then destroyDecor(row);d=nil end
   if not d and row.Rank>=2 then
    local k=math.clamp(root.Size.X/5.45,.2,3)
    local ok,built=pcall(build,row.Rank,root,k,low,motion)
    if ok and built then
     row.Decor=built
     local base=CFrame.new(root.Position);local t=os.clock()
     for _,mv in built.Movers do mv.Part.CFrame=mv.Fn(base,t)end
     built.Folder.Parent=fxRoot()
     table.insert(active,row)
    elseif not ok then warn('LuckyBlockFX:',built)end
   end
  elseif row.Decor then destroyDecor(row)end
 end
 -- One outline Highlight for the nearest Secret block (Roblox renders at most 31 at once).
 if secretRow then
  if not highlight or not highlight.Parent then
   local h=Instance.new('Highlight');h.Name='SecretBlockOutline';h.FillColor=rgb(120,40,255);h.FillTransparency=.82
   h.OutlineColor=rgb(110,255,240);h.OutlineTransparency=.15;h.DepthMode=Enum.HighlightDepthMode.Occluded
   h.Parent=fxRoot();highlight=h
  end
  local h=highlight::Highlight
  if h.Adornee~=secretRow.Model then h.Adornee=secretRow.Model end
  h.Enabled=true
 elseif highlight then highlight.Enabled=false;highlight.Adornee=nil end
end

local elapsed=CHECK
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<CHECK then return end;elapsed=0
 local ok,err=pcall(refresh);if not ok then warn('LuckyBlockFX refresh:',err)end
end)

---------------------------------------------------------------- per-frame motion
local parts:{BasePart}={};local cframes:{CFrame}={}
Run.RenderStepped:Connect(function()
 if #active==0 then return end
 local t=os.clock();local n=0
 for i=#active,1,-1 do
  local row=active[i];local d=row.Decor
  if not d then table.remove(active,i);continue end
  local root=d.Root
  if not root.Parent then continue end
  local base=CFrame.new(root.Position)
  for _,mv in d.Movers do n+=1;parts[n]=mv.Part;cframes[n]=mv.Fn(base,t)end
  if d.Pulse then d.Pulse(t)end
  if row.Rank==6 and d.Motion then
   for _,l in row.Lights do if l.Parent and l:IsA('PointLight')then l.Brightness=1.1+math.sin(t*2.2)*.7 end end
  end
 end
 if n>0 then
  for i=#parts,n+1,-1 do parts[i]=nil;cframes[i]=nil end
  workspace:BulkMoveTo(parts,cframes,Enum.BulkMoveMode.FireCFrameChanged)
 end
end)
