local Players=game:GetService("Players")
local folder=workspace:WaitForChild("DOGROTS_District"):WaitForChild("04_PlayerYards")
local Allocator=require(script.Parent:WaitForChild("YardAllocator"))
local allocation=Allocator.new({4,8,3,7,2,6,1,5})
local yards={};local waiting={};local registered={}
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local MiningConfig=require(ReplicatedStorage:WaitForChild("DogEconomy"):WaitForChild("Config")).Mining
local miningConnections={}

-- Owner billboard settings.
-- Use the actual Yard bounding-box center for X/Z instead of Model:GetPivot(),
-- because a model pivot can be offset from the visual center of the Yard.
-- Height is 1.5x the previous 18-stud offset.
local OWNER_BILLBOARD_HEIGHT=27
local OWNER_BILLBOARD_MAX_DISTANCE=400

local function ensureOwnerBillboard(yard)
 local anchor=yard:FindFirstChild("OwnerBillboardAnchor")
 if not anchor then
  -- At this point the billboard anchor does not exist yet, so GetBoundingBox()
  -- measures only the Yard itself and gives us its true horizontal center.
  local boundsCFrame=yard:GetBoundingBox()
  local pivotY=yard:GetPivot().Position.Y
  local yardCenter=Vector3.new(boundsCFrame.Position.X,pivotY,boundsCFrame.Position.Z)

  anchor=Instance.new("Part")
  anchor.Name="OwnerBillboardAnchor"
  anchor.Size=Vector3.new(1,1,1)
  anchor.Anchored=true
  anchor.CanCollide=false
  anchor.CanTouch=false
  anchor.CanQuery=false
  anchor.CastShadow=false
  anchor.Transparency=1
  anchor.CFrame=CFrame.new(yardCenter+Vector3.new(0,OWNER_BILLBOARD_HEIGHT,0))
  anchor.Parent=yard
 end

 local billboard=anchor:FindFirstChild("OwnerBillboard")
 if not billboard then
  billboard=Instance.new("BillboardGui")
  billboard.Name="OwnerBillboard"
  billboard.Adornee=anchor
  billboard.Size=UDim2.fromOffset(230,118)
  billboard.StudsOffset=Vector3.zero
  billboard.AlwaysOnTop=true
  billboard.LightInfluence=0
  billboard.MaxDistance=OWNER_BILLBOARD_MAX_DISTANCE
  billboard.Enabled=false
  billboard.Parent=anchor

  local avatar=Instance.new("ImageLabel")
  avatar.Name="Avatar"
  avatar.AnchorPoint=Vector2.new(.5,0)
  avatar.Position=UDim2.new(.5,0,0,0)
  avatar.Size=UDim2.fromOffset(76,76)
  avatar.BackgroundColor3=Color3.fromRGB(20,24,31)
  avatar.BorderSizePixel=0
  avatar.ScaleType=Enum.ScaleType.Crop
  avatar.Parent=billboard

  local avatarCorner=Instance.new("UICorner")
  avatarCorner.CornerRadius=UDim.new(1,0)
  avatarCorner.Parent=avatar

  local avatarStroke=Instance.new("UIStroke")
  avatarStroke.Thickness=4
  avatarStroke.Color=Color3.fromRGB(12,14,18)
  avatarStroke.Parent=avatar

  local name=Instance.new("TextLabel")
  name.Name="Username"
  name.AnchorPoint=Vector2.new(.5,0)
  name.Position=UDim2.new(.5,0,0,78)
  name.Size=UDim2.new(1,0,0,34)
  name.BackgroundTransparency=1
  name.Font=Enum.Font.GothamBold
  name.Text=""
  name.TextColor3=Color3.new(1,1,1)
  name.TextSize=24
  name.TextScaled=false
  name.TextStrokeColor3=Color3.fromRGB(20,20,20)
  name.TextStrokeTransparency=0
  name.TextXAlignment=Enum.TextXAlignment.Center
  name.Parent=billboard
 end
 return billboard
end

local function clearOwnerBillboard(yard)
 local billboard=ensureOwnerBillboard(yard)
 billboard.Enabled=false
 local avatar=billboard:FindFirstChild("Avatar")
 local name=billboard:FindFirstChild("Username")
 if avatar then avatar.Image="" end
 if name then name.Text="" end
end

local function updateOwnerBillboard(yard,player)
 local billboard=ensureOwnerBillboard(yard)
 local avatar=billboard:FindFirstChild("Avatar")
 local name=billboard:FindFirstChild("Username")
 if name then name.Text=player.Name end
 if avatar then avatar.Image="" end
 billboard.Enabled=true

 -- Thumbnail loading can yield, so do it asynchronously and verify that the
 -- same player still owns this Yard before applying the image.
 task.spawn(function()
  local ok,image=pcall(function()
   return Players:GetUserThumbnailAsync(player.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size420x420)
  end)
  if ok and image and yard.Parent and yard:GetAttribute("OwnerUserId")==player.UserId then
   local current=ensureOwnerBillboard(yard):FindFirstChild("Avatar")
   if current then current.Image=image end
  end
 end)
end


local function miningColor(row)
 local c=row and row.Color or{145,145,145};return Color3.fromRGB(c[1],c[2],c[3])
end
local function miningPart(parent,name,size,cf,color,material,shape)
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.Slate
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if shape then p.Shape=shape end;p.Parent=parent;return p
end
local function miningBillboard(part,name,text,color,size,offset)
 local g=Instance.new('BillboardGui');g.Name=name;g.Adornee=part;g.Size=size or UDim2.fromOffset(210,64);g.StudsOffsetWorldSpace=offset or Vector3.new(0,4,0);g.AlwaysOnTop=true;g.LightInfluence=0;g.MaxDistance=110;g.Parent=part
 local t=Instance.new('TextLabel');t.Name='Caption';t.Size=UDim2.fromScale(1,1);t.BackgroundColor3=Color3.fromRGB(16,21,29);t.BackgroundTransparency=.12;t.BorderSizePixel=0
 t.Text=text;t.TextColor3=color or Color3.new(1,1,1);t.Font=Enum.Font.GothamBold;t.TextScaled=true;t.TextWrapped=true;t.TextStrokeTransparency=.65;t.Parent=g
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,9);c.Parent=t
 local s=Instance.new('UIStroke');s.Color=Color3.fromRGB(9,13,19);s.Thickness=2;s.Parent=t
 return g,t
end
local function miningPrompt(parent,name,action,object)
 local p=Instance.new('ProximityPrompt');p.Name=name;p.ActionText=action;p.ObjectText=object;p.KeyboardKeyCode=Enum.KeyCode.E;p.GamepadKeyCode=Enum.KeyCode.ButtonX
 p.HoldDuration=0;p.MaxActivationDistance=10;p.RequiresLineOfSight=false;p.Enabled=false;p.Parent=parent;return p
end
local function horizontalDistance(a,b)local d=Vector3.new(a.X-b.X,0,a.Z-b.Z);return d.Magnitude end
local function miningObjectPosition(o)
 if not o then return nil end
 if o:IsA('BasePart')then return o.Position end
 if o:IsA('Model')then return o:GetPivot().Position end
 local p=o:FindFirstChildWhichIsA('BasePart',true)
 return p and p.Position or nil
end
local function miningPlacement(yard)
 -- Placement is derived from the Lucky Block area on THIS yard.
 -- Mining is mirrored to the opposite side of the central path at the same distance.
 local spawn=yard:FindFirstChild('YardSpawn',true)
 local pads={}
 for _,o in ipairs(yard:GetDescendants())do
  if o.Name:match('^LuckyPad_%d+$')then
   local pos=miningObjectPosition(o)
   if pos then table.insert(pads,{Name=o.Name,Pos=pos})end
  end
 end
 table.sort(pads,function(a,b)return a.Name<b.Name end)
 if #pads==0 then return yard:GetPivot() end

 local luckyCenter=Vector3.zero
 for _,row in ipairs(pads)do luckyCenter+=row.Pos end
 luckyCenter/=#pads

 -- The row of Lucky Pads normally runs parallel to the middle path.
 local pathDir
 if #pads>=2 then
  local d=Vector3.new(pads[#pads].Pos.X-pads[1].Pos.X,0,pads[#pads].Pos.Z-pads[1].Pos.Z)
  if d.Magnitude>.1 then pathDir=d.Unit end
 end
 if not pathDir and spawn then
  local d=Vector3.new(spawn.CFrame.LookVector.X,0,spawn.CFrame.LookVector.Z)
  if d.Magnitude>.1 then pathDir=d.Unit end
 end
 if not pathDir then
  local d=Vector3.new(yard:GetPivot().LookVector.X,0,yard:GetPivot().LookVector.Z)
  pathDir=d.Magnitude>.1 and d.Unit or Vector3.new(0,0,-1)
 end

 -- YardSpawn is on the central walkway and therefore defines its centre line.
 local anchor=spawn and spawn.Position or yard:GetBoundingBox().Position
 local delta=Vector3.new(luckyCenter.X-anchor.X,0,luckyCenter.Z-anchor.Z)
 local along=pathDir*delta:Dot(pathDir)
 local side=delta-along
 if side.Magnitude<.1 then
  local fallback=Vector3.new(-pathDir.Z,0,pathDir.X)
  side=fallback*12
 end

 -- Exact mirror: same longitudinal position, exact same distance from the path, opposite side.
 local mirrored=Vector3.new(anchor.X,0,anchor.Z)+along-side

 -- Put it on the actual yard ground.
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={yard}
 local hit=workspace:Raycast(mirrored+Vector3.new(0,40,0),Vector3.new(0,-100,0),params)
 local y=hit and hit.Position.Y or luckyCenter.Y
 local pos=Vector3.new(mirrored.X,y,mirrored.Z)

 -- Long side of the mining rectangle runs ALONG the central path.
 local up=Vector3.new(0,1,0)
 local back=pathDir:Cross(up)
 if back.Magnitude<.1 then back=Vector3.new(0,0,1)else back=back.Unit end
 local cf=CFrame.fromMatrix(pos,pathDir,up,back)
 local yardNumber=tonumber(yard.Name:match('Yard_(%d+)'))
 if yardNumber and yardNumber>=1 and yardNumber<=4 then
  cf=cf*CFrame.Angles(0,math.pi,0)
 end
 return cf
end
local function ensureMiningCorner(yard)
 local existing=yard:FindFirstChild('MiningCorner')
 if existing and existing:GetAttribute('LayoutVersion')==15 then return existing end
 if existing then existing:Destroy() end
 local root=Instance.new('Model');root.Name='MiningCorner';root.Parent=yard;root:SetAttribute('LayoutVersion',15)
 local cf=miningPlacement(yard)
 local pad=miningPart(root,'MiningPad',Vector3.new(28,.5,18),cf*CFrame.new(0,.25,0),Color3.fromRGB(76,70,64),Enum.Material.Slate);pad.CanQuery=true
 local trim=Color3.fromRGB(103,94,83)
 miningPart(root,'MiningBorderA',Vector3.new(28,.72,.8),cf*CFrame.new(0,.38,-8.6),trim,Enum.Material.Slate)
 miningPart(root,'MiningBorderB',Vector3.new(28,.72,.8),cf*CFrame.new(0,.38,8.6),trim,Enum.Material.Slate)
 miningPart(root,'MiningBorderC',Vector3.new(.8,.72,18),cf*CFrame.new(-13.6,.38,0),trim,Enum.Material.Slate)
 miningPart(root,'MiningBorderD',Vector3.new(.8,.72,18),cf*CFrame.new(13.6,.38,0),trim,Enum.Material.Slate)
 miningPart(root,'MiningLane',Vector3.new(27,.12,3.2),cf*CFrame.new(0,.31,0),Color3.fromRGB(95,88,79),Enum.Material.SmoothPlastic)
 miningPart(root,'MiningAccent',Vector3.new(27,.09,1.35),cf*CFrame.new(0,.35,0),Color3.fromRGB(230,190,76),Enum.Material.Neon)
 local baseCF=cf*CFrame.new(-7.8,.85,0)
 miningPart(root,'OrePedestal',Vector3.new(10.8,1.85,9.2),baseCF,Color3.fromRGB(82,76,71),Enum.Material.Rock)
 miningPart(root,'OrePedestalTop',Vector3.new(9.3,.34,7.8),baseCF*CFrame.new(0,1.02,0),Color3.fromRGB(104,97,90),Enum.Material.Slate)
 local oreCF=cf*CFrame.new(-7.8,3.05,0)
 local core=miningPart(root,'MiningOreCore',Vector3.new(8.4,6.4,7.6),oreCF,Color3.fromRGB(168,165,150),Enum.Material.Slate,Enum.PartType.Ball)
 core:SetAttribute('BaseSize',core.Size);core:SetAttribute('OreVisual',true);core.CanQuery=true
 for i,row in ipairs({
  {off=Vector3.new(-3.4,-1.0,.55),size=Vector3.new(3.9,3.1,3.5),rot=Vector3.new(.2,.5,.1)},
  {off=Vector3.new(3.35,-.8,.95),size=Vector3.new(3.8,3.0,3.2),rot=Vector3.new(.35,.9,.12)},
  {off=Vector3.new(-1.45,1.35,-2.6),size=Vector3.new(3.1,2.7,2.8),rot=Vector3.new(.6,.55,.25)},
  {off=Vector3.new(2.5,1.2,-2.25),size=Vector3.new(3.2,2.8,2.7),rot=Vector3.new(.4,1.1,.35)},
  {off=Vector3.new(.25,-1.2,-2.8),size=Vector3.new(3.8,2.6,3.2),rot=Vector3.new(.25,.35,.2)},
  {off=Vector3.new(-.35,2.35,.45),size=Vector3.new(2.4,2.2,2.2),rot=Vector3.new(.3,.2,.7)},
  {off=Vector3.new(1.45,.5,2.9),size=Vector3.new(2.8,2.4,2.2),rot=Vector3.new(.1,.85,.55)},
  {off=Vector3.new(-2.55,.3,2.55),size=Vector3.new(2.9,2.3,2.4),rot=Vector3.new(.2,.65,.48)},
  {off=Vector3.new(0,2.85,-.2),size=Vector3.new(2.1,2.0,1.9),rot=Vector3.new(.15,.4,.55)},
 })do
  local q=miningPart(root,'OreChunk_'..i,row.size,oreCF*CFrame.new(row.off)*CFrame.Angles(row.rot.X,row.rot.Y,row.rot.Z),core.Color,Enum.Material.Slate,Enum.PartType.Ball)
  q:SetAttribute('OreVisual',true)
 end
 for i,row in ipairs({
  {off=Vector3.new(-1.6,3.5,-.75),size=Vector3.new(.65,1.9,.65),rot=.22},
  {off=Vector3.new(2.1,2.85,.9),size=Vector3.new(.58,1.5,.58),rot=-.35},
  {off=Vector3.new(.7,2.2,-3.0),size=Vector3.new(.5,1.3,.5),rot=.5},
  {off=Vector3.new(-2.55,1.7,2.35),size=Vector3.new(.48,1.15,.48),rot=-.18},
 })do
  local crystal=miningPart(root,'OreCrystal_'..i,row.size,oreCF*CFrame.new(row.off)*CFrame.Angles(0,0,row.rot),Color3.fromRGB(230,230,230),Enum.Material.Glass)
  crystal.Transparency=.1;crystal:SetAttribute('OreVisual',true)
 end
 local glow=miningPart(root,'OreGlow',Vector3.new(1.1,1.1,1.1),oreCF*CFrame.new(0,2.8,-2.7),Color3.fromRGB(238,233,208),Enum.Material.Neon,Enum.PartType.Ball);glow:SetAttribute('OreGlow',true)
 local light=Instance.new('PointLight');light.Name='OreLight';light.Brightness=1.2;light.Range=14;light.Color=glow.Color;light.Parent=glow
 local emitter=Instance.new('ParticleEmitter');emitter.Name='OreHitParticles';emitter.Texture='rbxasset://textures/particles/sparkles_main.dds';emitter.Rate=0;emitter.Lifetime=NumberRange.new(.28,.65);emitter.Speed=NumberRange.new(5,10);emitter.SpreadAngle=Vector2.new(180,180);emitter.RotSpeed=NumberRange.new(-180,180);emitter.Parent=core
 local hitSound=Instance.new('Sound');hitSound.Name='HitSound';hitSound.SoundId='rbxasset://sounds/swordslash.wav';hitSound.Volume=.4;hitSound.Parent=core
 local breakSound=Instance.new('Sound');breakSound.Name='BreakSound';breakSound.SoundId='rbxasset://sounds/collide.wav';breakSound.Volume=.82;breakSound.PlaybackSpeed=.76;breakSound.Parent=core
 local _,oreText=miningBillboard(core,'OreBillboard','МИНИ-ШАХТА',Color3.fromRGB(255,235,181),UDim2.fromOffset(270,76),Vector3.new(0,7.1,0))
 miningPrompt(core,'MiningOrePrompt','ДОБЫВАТЬ','РУДА')
 miningPart(root,'PickaxePad',Vector3.new(5.6,.4,5.0),cf*CFrame.new(8.0,.38,-5.4),Color3.fromRGB(46,58,74),Enum.Material.SmoothPlastic)
 local shopBase=miningPart(root,'MiningPickaxeShop',Vector3.new(5.0,3.2,1.6),cf*CFrame.new(8.0,2.0,-5.4),Color3.fromRGB(25,34,45),Enum.Material.Metal);shopBase.CanQuery=true
 local handle=miningPart(root,'PickaxeHandle',Vector3.new(.36,3.9,.36),shopBase.CFrame*CFrame.new(-.52,.72,-.98)*CFrame.Angles(0,0,-.58),Color3.fromRGB(135,88,50),Enum.Material.Wood)
 miningPart(root,'PickaxeHead',Vector3.new(3.15,.46,.56),handle.CFrame*CFrame.new(0,1.82,0)*CFrame.Angles(0,0,.58),Color3.fromRGB(175,185,195),Enum.Material.Metal)
 local miniPick=miningPart(root,'PickaxeHeadMini',Vector3.new(1.6,.28,.46),shopBase.CFrame*CFrame.new(.95,.88,-.55)*CFrame.Angles(0,0,.18),Color3.fromRGB(103,208,255),Enum.Material.Neon)
 miniPick.Transparency=.08
 local _,shopText=miningBillboard(shopBase,'PickaxeBillboard','⛏ КИРКИ',Color3.fromRGB(110,220,255),UDim2.fromOffset(215,68),Vector3.new(0,3.65,0))
 miningPrompt(shopBase,'MiningPickaxeShopPrompt','ОТКРЫТЬ','КИРКИ')
 miningPart(root,'StrengthPad',Vector3.new(5.6,.4,5.0),cf*CFrame.new(8.0,.38,5.4),Color3.fromRGB(52,60,71),Enum.Material.SmoothPlastic)
 local rack=miningPart(root,'MiningStrengthRack',Vector3.new(5.0,3.2,1.6),cf*CFrame.new(8.0,2.0,5.4),Color3.fromRGB(32,37,45),Enum.Material.Metal);rack.CanQuery=true
 miningPart(root,'WeightRackBar',Vector3.new(5.9,.26,.26),rack.CFrame*CFrame.new(0,.92,-.95),Color3.fromRGB(180,188,197),Enum.Material.Metal)
 for i,w in ipairs(MiningConfig.Weights)do
  local col=miningColor(w);local x=(i-4)*.64
  local p=miningPart(root,'TrainingWeight_'..i,Vector3.new(.5,1.05,.72),rack.CFrame*CFrame.new(x,-.45,-.95),col,i>=5 and Enum.Material.Neon or Enum.Material.Metal)
  if i>=5 then p.Transparency=.05 end
 end
 local _,strengthText=miningBillboard(rack,'StrengthBillboard','🏋️ СИЛА',Color3.fromRGB(141,239,130),UDim2.fromOffset(215,68),Vector3.new(0,3.65,0))
 miningPrompt(rack,'MiningStrengthPrompt','ТРЕНИРОВАТЬ','СИЛА')
 root:SetAttribute('LastHitSerial',0);root:SetAttribute('LastBroken',0)
 return root
end
local function syncMiningVisual(yard,player)
 local root=ensureMiningCorner(yard);local core=root:FindFirstChild('MiningOreCore');local shop=root:FindFirstChild('MiningPickaxeShop');local rack=root:FindFirstChild('MiningStrengthRack')
 if not(core and shop and rack)then return end
 local orePrompt=core:FindFirstChild('MiningOrePrompt');local shopPrompt=shop:FindFirstChild('MiningPickaxeShopPrompt');local strengthPrompt=rack:FindFirstChild('MiningStrengthPrompt')
 local oreText=core:FindFirstChild('OreBillboard')and core.OreBillboard:FindFirstChild('Caption')
 local shopText=shop:FindFirstChild('PickaxeBillboard')and shop.PickaxeBillboard:FindFirstChild('Caption')
 local strengthText=rack:FindFirstChild('StrengthBillboard')and rack.StrengthBillboard:FindFirstChild('Caption')
 if not player then
  if orePrompt then orePrompt.Enabled=false end;if shopPrompt then shopPrompt.Enabled=false end;if strengthPrompt then strengthPrompt.Enabled=false end
  if oreText then oreText.Text='🪨 МИНИ-ШАХТА\nЖДЁТ ИГРОКА' end;if shopText then shopText.Text='⛏ КИРКИ' end;if strengthText then strengthText.Text='🏋️ СИЛА' end
  return
 end
 if orePrompt then orePrompt.Enabled=true end;if shopPrompt then shopPrompt.Enabled=true end;if strengthPrompt then strengthPrompt.Enabled=true end
 local index=math.clamp(math.floor(player:GetAttribute('MiningOreIndex')or 1),1,#MiningConfig.Ores);local def=MiningConfig.Ores[index]
 local col=miningColor(def);local hp=math.max(0,player:GetAttribute('MiningOreHP')or def.HP);local max=math.max(1,player:GetAttribute('MiningOreMaxHP')or def.HP)
 for _,d in ipairs(root:GetChildren())do
  if d:IsA('BasePart')and d:GetAttribute('OreVisual')then d.Color=col end
  if d:IsA('BasePart')and d:GetAttribute('OreGlow')then d.Color=col:Lerp(Color3.new(1,1,1),.35);local l=d:FindFirstChild('OreLight');if l then l.Color=d.Color end end
 end
 if oreText then oreText.Text=(def.Icon or '🪨')..' '..(def.RU or def.Name)..'\n'..hp..' / '..max..' HP' end
 if orePrompt then orePrompt.ObjectText=def.RU or def.Name end
 local pick=player:GetAttribute('MiningPickaxe')or 0;local strength=player:GetAttribute('MiningStrength')or 0
 local pickDef=MiningConfig.Pickaxes[pick];if shopText then shopText.Text=((pickDef and pickDef.Icon)or'⛏')..' КИРКИ\n'..(pick>0 and('УР. '..pick)or'НЕТ КИРКИ')end
 if strengthText then strengthText.Text='🏋️ СИЛА\n'..strength end
 local hitSerial=player:GetAttribute('MiningHitSerial')or 0;local oldHit=root:GetAttribute('LastHitSerial')or 0
 if hitSerial>oldHit then
  root:SetAttribute('LastHitSerial',hitSerial)
  local fx=core:FindFirstChild('OreHitParticles');if fx then fx.Color=ColorSequence.new(col:Lerp(Color3.new(1,1,1),.25));fx:Emit(8+2*math.max(1,pick))end
  local sound=core:FindFirstChild('HitSound');if sound then sound.PlaybackSpeed=1+math.min(.35,pick*.035);sound:Play()end
  local base=core:GetAttribute('BaseSize')or core.Size
  TweenService:Create(core,TweenInfo.new(.06),{Size=base*.9}):Play();task.delay(.07,function()if core.Parent then TweenService:Create(core,TweenInfo.new(.11,Enum.EasingStyle.Back),{Size=base}):Play()end end)
 end
 local broken=player:GetAttribute('MiningOresBroken')or 0;local oldBroken=root:GetAttribute('LastBroken')or 0
 if broken>oldBroken then
  root:SetAttribute('LastBroken',broken)
  local fx=core:FindFirstChild('OreHitParticles');if fx then fx:Emit(35)end
  local sound=core:FindFirstChild('BreakSound');if sound then sound:Play()end
 end
end
local watchedMining={MiningStrength=true,MiningPickaxe=true,MiningPickaxeOwned=true,MiningWeight=true,MiningWeightOwned=true,MiningOreIndex=true,MiningOreHP=true,MiningOreMaxHP=true,MiningOreValue=true,MiningHitSerial=true,MiningOresBroken=true}
local function unbindMining(player)
 local c=miningConnections[player];if c then c:Disconnect();miningConnections[player]=nil end
end
local function bindMining(player,yard)
 unbindMining(player)
 local root=ensureMiningCorner(yard);root:SetAttribute('LastHitSerial',player:GetAttribute('MiningHitSerial')or 0);root:SetAttribute('LastBroken',player:GetAttribute('MiningOresBroken')or 0)
 syncMiningVisual(yard,player)
 miningConnections[player]=player.AttributeChanged:Connect(function(name)if watchedMining[name]and yard.Parent and yard:GetAttribute('OwnerUserId')==player.UserId then syncMiningVisual(yard,player)end end)
end

for _,yard in folder:GetChildren() do
 local id=yard:GetAttribute("YardId")
 if id then
  yards[id]=yard
  yard:SetAttribute("OwnerUserId",0)
  yard:SetAttribute("OwnerDisplayName","")
  ensureOwnerBillboard(yard)
  clearOwnerBillboard(yard)
  ensureMiningCorner(yard)
  syncMiningVisual(yard,nil)
 end
end

local function updateSign(yard,label)
 local p=yard:FindFirstChild("OwnerPlaque")
 local t=p and p:FindFirstChild("OwnerText",true)
 if t then t.Text=label end
end

local function assign(player,moveExisting)
 if not player.Parent then return false end
 local id=allocation:Claim(player.UserId)
 if not id then
  player:SetAttribute("WaitingForYard",true)
  player.RespawnLocation=workspace:FindFirstChild("DistrictSpawn")
  return false
 end
 local yard=yards[id];local spawn=yard:FindFirstChild("YardSpawn")
 yard:SetAttribute("OwnerUserId",player.UserId);yard:SetAttribute("OwnerDisplayName",player.DisplayName)
 player:SetAttribute("YardId",id);player:SetAttribute("YardSpawnPosition",spawn.Position)
 player:SetAttribute("WaitingForYard",false);player.RespawnLocation=workspace:WaitForChild("DistrictSpawn")
 updateSign(yard,player.DisplayName)
 updateOwnerBillboard(yard,player)
 bindMining(player,yard)
 return true
end

local function added(player)
 if registered[player] then return end;registered[player]=true
 if not assign(player,false) then table.insert(waiting,player) end
end

Players.PlayerAdded:Connect(added)
Players.PlayerRemoving:Connect(function(player)
 unbindMining(player)
 registered[player]=nil
 for i=#waiting,1,-1 do if waiting[i]==player then table.remove(waiting,i) end end
 local id=allocation:Release(player.UserId)
 if id and yards[id] then
  yards[id]:SetAttribute("OwnerUserId",0);yards[id]:SetAttribute("OwnerDisplayName","")
  updateSign(yards[id],"AVAILABLE")
  clearOwnerBillboard(yards[id])
  syncMiningVisual(yards[id],nil)
 end
 while id and #waiting>0 do
  local nextPlayer=table.remove(waiting,1)
  if nextPlayer.Parent==Players then
   if not assign(nextPlayer,true) then table.insert(waiting,1,nextPlayer) end
   break
  end
 end
end)

for _,player in Players:GetPlayers() do added(player) end
print("DOGROTS_YARDS_READY: 8 exclusive session yards + centered owner billboards")

