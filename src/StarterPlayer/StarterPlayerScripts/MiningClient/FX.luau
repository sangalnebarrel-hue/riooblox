-- Client visual effects for Active Mining. Everything lives outside DOGROTS_District
-- (workspace.DOGROTS_MiningFX / Terrain attachments) so WorldDetailQuality's emitter budget does
-- not mute it, and every effect scales down on Low FX / Reduced Motion / touch devices.
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local UIS=game:GetService('UserInputService')
local FX={}

local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local FIRE='rbxasset://textures/particles/fire_main.dds'

function FX.new(ctx)
 local self:any={ShakeAmount=0}
 local player=ctx.Player
 local folder=workspace:FindFirstChild('DOGROTS_MiningFX')
 if not folder then folder=Instance.new('Folder');folder.Name='DOGROTS_MiningFX';folder.Parent=workspace end
 self.Folder=folder

 function self.Low()
  local choice=player:GetAttribute('WorldEventFX')
  return choice=='Low'or player:GetAttribute('LowFX')==true or player:GetAttribute('ReducedMotion')==true
   or(choice==nil and UIS.TouchEnabled)
 end
 function self.ReducedMotion()return player:GetAttribute('ReducedMotion')==true end
 local function n(count)return math.max(1,math.floor(count*(self.Low()and .4 or 1)+.5))end

 -- Particle burst from a temporary Terrain attachment.
 function self.Burst(pos,opts)
  local a=Instance.new('Attachment');a.Parent=workspace.Terrain;a.WorldPosition=pos
  local e=Instance.new('ParticleEmitter')
  e.Texture=opts.Texture or SPARK;e.Rate=0;e.LockedToPart=false
  e.Color=ColorSequence.new(opts.Color or Color3.new(1,1,1),opts.Color2 or opts.Color or Color3.new(1,1,1))
  e.Lifetime=opts.Lifetime or NumberRange.new(.35,.8)
  e.Speed=opts.Speed or NumberRange.new(8,16)
  e.SpreadAngle=opts.Spread or Vector2.new(70,70)
  e.Acceleration=opts.Acceleration or Vector3.new(0,-24,0)
  e.Drag=opts.Drag or 2
  e.LightEmission=opts.LightEmission or .6
  e.Size=opts.Size or NumberSequence.new({NumberSequenceKeypoint.new(0,.45),NumberSequenceKeypoint.new(1,0)})
  e.Transparency=opts.Transparency or NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,.4)})
  e.RotSpeed=NumberRange.new(-200,200);e.Rotation=NumberRange.new(0,360)
  if opts.Direction then a.WorldCFrame=CFrame.lookAt(pos,pos+opts.Direction)*CFrame.Angles(-math.pi/2,0,0)end
  e.Parent=a
  e:Emit(n(opts.Count or 12))
  Debris:AddItem(a,2.5)
 end

 -- Rock chips that fly off and fade. Non-colliding: they spawn inside the ore hitbox.
 function self.Chunks(pos,color,material,count,dir,speed)
  for _=1,n(count or 4)do
   local p=Instance.new('Part');p.Name='OreChip';p.Size=Vector3.new(1,1,1)*(.25+math.random()*.45)
   p.Color=color;p.Material=material or Enum.Material.Slate;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Massless=true
   p.CFrame=CFrame.new(pos)*CFrame.Angles(math.random()*6,math.random()*6,math.random()*6)
   p.Parent=folder
   local d=((dir or Vector3.new(0,1,0))+Vector3.new(math.random()-.5,math.random()*.8,math.random()-.5)).Unit
   p.AssemblyLinearVelocity=d*(speed or 18)*(.6+math.random()*.6)
   p.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*20
   TweenService:Create(p,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.7),{Transparency=1}):Play()
   Debris:AddItem(p,1.3)
  end
 end

 -- Flat neon ring expanding from a point.
 function self.Ring(pos,color,size,duration)
  local ring=Instance.new('Part');ring.Name='HitRing';ring.Shape=Enum.PartType.Cylinder;ring.Anchored=true;ring.CanCollide=false;ring.CanQuery=false;ring.CanTouch=false
  ring.Material=Enum.Material.Neon;ring.Color=color;ring.Transparency=.2;ring.CastShadow=false
  ring.Size=Vector3.new(.15,1,1);ring.CFrame=CFrame.new(pos)*CFrame.Angles(0,0,math.rad(90));ring.Parent=folder
  TweenService:Create(ring,TweenInfo.new(duration or .45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(.05,size or 8,size or 8),Transparency=1}):Play()
  Debris:AddItem(ring,(duration or .45)+.1)
 end

 -- Vertical light pillar (rare ore reveal).
 function self.Pillar(pos,color,height)
  local p=Instance.new('Part');p.Name='RevealPillar';p.Shape=Enum.PartType.Cylinder;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
  p.Material=Enum.Material.Neon;p.Color=color;p.Transparency=.35;p.CastShadow=false
  p.Size=Vector3.new(height or 40,3,3);p.CFrame=CFrame.new(pos+Vector3.new(0,(height or 40)/2,0))*CFrame.Angles(0,0,math.rad(90));p.Parent=folder
  TweenService:Create(p,TweenInfo.new(1.6,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(height or 40,.2,.2),Transparency=1}):Play()
  Debris:AddItem(p,1.7)
 end

 -- Floating text in the world (damage numbers, coins). Pooled to keep text churn low.
 local pool={}
 function self.Popup(pos,text,color,big)
  local g=table.remove(pool)
  if not g then
   g=Instance.new('BillboardGui');g.Name='MiningPopup';g.AlwaysOnTop=true;g.LightInfluence=0;g.MaxDistance=120
   g:SetAttribute('NoTranslate',true)
   local label=Instance.new('TextLabel');label.Name='Text';label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1)
   label.FontFace=ctx.U.FontFace or Font.fromEnum(Enum.Font.FredokaOne);label.TextScaled=true
   label.TextStrokeTransparency=0;label.TextStrokeColor3=Color3.fromRGB(23,43,76);label:SetAttribute('NoTranslate',true)
   label.Parent=g
  end
  local label=g:FindFirstChild('Text')::TextLabel
  local size=big and 64 or 40
  g.Size=UDim2.fromOffset(size*5,size);g.StudsOffsetWorldSpace=Vector3.zero
  label.Text=text;label.TextColor3=color or Color3.new(1,1,1);label.TextTransparency=0;label.TextStrokeTransparency=0
  local anchor=Instance.new('Attachment');anchor.Parent=workspace.Terrain;anchor.WorldPosition=pos
  g.Adornee=anchor;g.Parent=folder
  local rise=Vector3.new((math.random()-.5)*1.5,big and 4.5 or 3.2,0)
  TweenService:Create(g,TweenInfo.new(.75,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{StudsOffsetWorldSpace=rise}):Play()
  TweenService:Create(label,TweenInfo.new(.35,Enum.EasingStyle.Linear,Enum.EasingDirection.In,0,false,.45),{TextTransparency=1,TextStrokeTransparency=1}):Play()
  task.delay(.85,function()
   anchor:Destroy();g.Adornee=nil;g.Parent=nil
   if #pool<16 then table.insert(pool,g)else g:Destroy()end
  end)
 end

 -- Full-screen tint flash.
 local flash=Instance.new('Frame');flash.Name='MiningFlash';flash.Size=UDim2.fromScale(1,1);flash.BackgroundTransparency=1;flash.BorderSizePixel=0
 flash.ZIndex=200;flash.Active=false;flash.Parent=ctx.Gui
 function self.Flash(color,strength)
  if self.ReducedMotion()then return end
  flash.BackgroundColor3=color;flash.BackgroundTransparency=1-(strength or .35)
  TweenService:Create(flash,TweenInfo.new(.4),{BackgroundTransparency=1}):Play()
 end
 function self.Shake(amount)
  -- Only the mining camera consumes shake; outside a session it would just pile up.
  if self.ReducedMotion()or not(ctx.Mine and ctx.Mine.Active)then return end
  self.ShakeAmount=math.min(1.2,self.ShakeAmount+(amount or .3))
 end

 -- Coins pop out of the ore and fly to the player (the "money drops" of every hit).
 local COIN=Color3.fromRGB(255,204,56)
 function self.Coins(fromPos,count,target)
  count=math.clamp(math.floor(count or 1),1,24)
  if self.Low()then count=math.max(1,math.floor(count*.4))end
  for i=1,count do
   local coin=Instance.new('Part');coin.Name='MiningCoin';coin.Shape=Enum.PartType.Cylinder;coin.Size=Vector3.new(.14,.75,.75)
   coin.Material=Enum.Material.Neon;coin.Color=COIN;coin.Anchored=true;coin.CanCollide=false;coin.CanQuery=false;coin.CanTouch=false;coin.CastShadow=false
   local start=fromPos+Vector3.new((math.random()-.5)*1.5,(math.random()-.2)*1.2,(math.random()-.5)*1.5)
   coin.CFrame=CFrame.new(start);coin.Parent=folder
   local apex=start+Vector3.new((math.random()-.5)*4,3+math.random()*2.5,(math.random()-.5)*4)
   local delay=(i-1)*.035;local flight=.55+math.random()*.2
   task.delay(delay,function()
    local t0=os.clock()
    local conn
    conn=game:GetService('RunService').RenderStepped:Connect(function()
     local a=math.clamp((os.clock()-t0)/flight,0,1)
     local goal=(typeof(target)=='Instance'and target.Parent and(target::BasePart).Position)or(typeof(target)=='Vector3'and target)or start
     local p1=start:Lerp(apex,a);local p2=apex:Lerp(goal,a)
     coin.CFrame=CFrame.new(p1:Lerp(p2,a))*CFrame.Angles(0,os.clock()*14,math.rad(90))
     coin.Size=Vector3.new(.14,.75,.75)*(1-.5*a)
     if a>=1 then conn:Disconnect();coin:Destroy()end
    end)
   end)
   Debris:AddItem(coin,2)
  end
 end

 -- Pickaxe-tier hit effect. tier 1..7, quality 1/2, crit bool; remote = another player's hit
-- (particles and rings only, no screen flash or shake).
 local TIER={
  {Texture=SMOKE,Color=Color3.fromRGB(170,150,120),Count=5,Chunks=3,Speed=NumberRange.new(4,9),LightEmission=0},
  {Texture=SMOKE,Color=Color3.fromRGB(160,160,160),Count=6,Chunks=4,Speed=NumberRange.new(5,10),LightEmission=0,Sparks=4},
  {Texture=SPARK,Color=Color3.fromRGB(255,214,120),Count=10,Chunks=4},
  {Texture=SPARK,Color=Color3.fromRGB(190,230,255),Count=14,Chunks=5,Ring=true},
  {Texture=SPARK,Color=Color3.fromRGB(130,240,255),Count=18,Chunks=5,Ring=true,Shards=true},
  {Texture=FIRE,Color=Color3.fromRGB(255,140,50),Color2=Color3.fromRGB(255,60,20),Count=16,Chunks=6,Ring=true,Embers=true},
  {Texture=SPARK,Color=Color3.fromRGB(200,120,255),Color2=Color3.fromRGB(90,30,170),Count=26,Chunks=7,Ring=true,Void=true},
 }
 function self.Hit(pos,normal,oreColor,oreMaterial,tier,quality,crit,remote)
  local row=TIER[math.clamp(tier or 1,1,#TIER)]
  local mult=(quality==2 and 1.5 or 1)*(crit and 1.6 or 1)
  local dir=normal or Vector3.new(0,1,0)
  self.Burst(pos,{Texture=row.Texture,Color=row.Color,Color2=row.Color2,Count=row.Count*mult,Speed=row.Speed,LightEmission=row.LightEmission,Direction=dir})
  if row.Sparks then self.Burst(pos,{Color=Color3.fromRGB(255,230,170),Count=row.Sparks,Speed=NumberRange.new(10,18),Direction=dir})end
  self.Burst(pos,{Texture=SMOKE,Color=oreColor,Count=3,Speed=NumberRange.new(2,5),LightEmission=0,Acceleration=Vector3.new(0,2,0),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.8),NumberSequenceKeypoint.new(1,1.6)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.4),NumberSequenceKeypoint.new(1,1)})})
  self.Chunks(pos,oreColor,oreMaterial,math.floor(row.Chunks*mult),dir,14+(tier or 1)*2)
  if row.Shards then self.Chunks(pos,Color3.fromRGB(170,240,255),Enum.Material.Glass,3,dir,20)end
  if row.Embers then self.Burst(pos,{Texture=FIRE,Color=Color3.fromRGB(255,200,90),Count=8,Speed=NumberRange.new(2,6),Acceleration=Vector3.new(0,8,0),Lifetime=NumberRange.new(.6,1.2)})end
  if row.Void then
   self.Burst(pos,{Color=Color3.fromRGB(240,200,255),Count=14,Speed=NumberRange.new(-14,-8),Spread=Vector2.new(180,180),Acceleration=Vector3.zero,Lifetime=NumberRange.new(.3,.5)})
  end
  if row.Ring or quality==2 then self.Ring(pos,quality==2 and Color3.fromRGB(255,214,80)or row.Color,quality==2 and 7 or 5)end
  if crit then self.Ring(pos,Color3.fromRGB(255,90,60),12,.55)end
  if remote then return end
  if crit then
   self.Flash(Color3.fromRGB(255,220,150),.18)
   self.Shake(.5)
  else
   self.Shake(quality==2 and .22 or .12)
  end
 end

 return self
end

return FX
