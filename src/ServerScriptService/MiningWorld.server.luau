-- Active Mining world: builds the Mining Corner of every yard, mirrors the owner's mining state
-- onto it (so every client can render the ore pile and hit effects), and puts the pickaxe /
-- training weight in the owner's hand while they mine or lift.
-- Ore piles themselves are rendered client-side (StarterPlayerScripts.MiningClient).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Config=require(RS:WaitForChild('DogEconomy'):WaitForChild('Config'))
local Models=require(RS:WaitForChild('Mining'):WaitForChild('MiningModels'))
local M=Config.Mining
local yardsFolder=workspace:WaitForChild('DOGROTS_District'):WaitForChild('04_PlayerYards')

local LAYOUT_VERSION=20
local PAD_SIZE=Vector3.new(28,.5,18)

local function part(parent,name,size,cf,color,mat,props)
 local p=Models.Part(parent,name,size,cf,color,mat,props);return p
end
local function rgb(r,g,b)return Color3.fromRGB(r,g,b)end

-- PLACEMENT ------------------------------------------------------------------------------------
-- The corner mirrors the yard's Lucky Pad row across the central walkway (YardSpawn line), on
-- the kennel side. Returns the corner CFrame: LookVector points from the corner towards the
-- walkway (the side players arrive from), RightVector runs along the walkway.
local function objectPosition(o)
 if o:IsA('BasePart')then return o.Position end
 if o:IsA('Model')then return o:GetPivot().Position end
 local p=o:FindFirstChildWhichIsA('BasePart',true);return p and p.Position
end
local function placement(yard)
 local spawn=yard:FindFirstChild('YardSpawn',true)
 local pads={}
 for _,o in ipairs(yard:GetDescendants())do
  if o.Name:match('^LuckyPad_%d+$')then local pos=objectPosition(o);if pos then table.insert(pads,{Name=o.Name,Pos=pos})end end
 end
 table.sort(pads,function(a,b)return a.Name<b.Name end)
 local anchor=spawn and(spawn::BasePart).Position or(yard::Model):GetBoundingBox().Position
 if #pads==0 then return CFrame.new(anchor) end
 local center=Vector3.zero
 for _,row in ipairs(pads)do center+=row.Pos end
 center/=#pads
 local pathDir
 if #pads>=2 then
  local d=Vector3.new(pads[#pads].Pos.X-pads[1].Pos.X,0,pads[#pads].Pos.Z-pads[1].Pos.Z)
  if d.Magnitude>.1 then pathDir=d.Unit end
 end
 if not pathDir and spawn then
  local d=Vector3.new(spawn.CFrame.LookVector.X,0,spawn.CFrame.LookVector.Z);if d.Magnitude>.1 then pathDir=d.Unit end
 end
 pathDir=pathDir or Vector3.new(1,0,0)
 local delta=Vector3.new(center.X-anchor.X,0,center.Z-anchor.Z)
 local along=pathDir*delta:Dot(pathDir)
 local side=delta-along
 if side.Magnitude<.1 then side=Vector3.new(-pathDir.Z,0,pathDir.X)*12 end
 local mirrored=Vector3.new(anchor.X,0,anchor.Z)+along-side
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={yard}
 local hit=workspace:Raycast(mirrored+Vector3.new(0,40,0),Vector3.new(0,-100,0),params)
 local pos=Vector3.new(mirrored.X,hit and hit.Position.Y or center.Y,mirrored.Z)
 -- Face the walkway: from the corner centre towards the walkway line.
 local toward=Vector3.new(side.X,0,side.Z).Unit
 return CFrame.lookAt(pos,pos+toward)
end

-- BUILD ----------------------------------------------------------------------------------------
local function signGui(board,face,title,sub,accent,icon)
 local g=Instance.new('SurfaceGui');g.Name='Face';g.Face=face;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=60
 g.LightInfluence=.15;g.MaxDistance=90;g.Parent=board
 local bg=Instance.new('Frame');bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=rgb(52,36,24);bg.BorderSizePixel=0;bg.Parent=g
 local stroke=Instance.new('UIStroke');stroke.Color=accent;stroke.Thickness=10;stroke.Parent=bg
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,18);corner.Parent=bg
 if icon then icon(bg)end
 local t=Instance.new('TextLabel');t.Name='Title';t.BackgroundTransparency=1;t.Size=UDim2.fromScale(.92,.22);t.Position=UDim2.fromScale(.04,.64)
 t.Font=Enum.Font.GothamBlack;t.TextScaled=true;t.TextColor3=rgb(255,236,190);t.Text=title;t.TextStrokeTransparency=.4;t.Parent=bg
 local s=Instance.new('TextLabel');s.Name='Sub';s.BackgroundTransparency=1;s.Size=UDim2.fromScale(.92,.11);s.Position=UDim2.fromScale(.04,.86)
 s.Font=Enum.Font.GothamBold;s.TextScaled=true;s.TextColor3=accent;s.Text=sub;s.Parent=bg
 return g
end
local function prompt(parent,name,action,object)
 local p=Instance.new('ProximityPrompt');p.Name=name;p.ActionText=action;p.ObjectText=object
 p.KeyboardKeyCode=Enum.KeyCode.E;p.GamepadKeyCode=Enum.KeyCode.ButtonX;p.HoldDuration=0
 p.MaxActivationDistance=11;p.RequiresLineOfSight=false;p.Enabled=false;p.Parent=parent
 return p
end
local function click(parent,name)
 local c=Instance.new('ClickDetector');c.Name=name;c.MaxActivationDistance=26;c.Parent=parent;return c
end

local function build(yard:Model):Model
 local existing=yard:FindFirstChild('MiningCorner')::Model?
 if existing and existing:GetAttribute('LayoutVersion')==LAYOUT_VERSION then return existing end
 if existing then existing:Destroy()end
 local root=Instance.new('Model');root.Name='MiningCorner'
 pcall(function()root.ModelStreamingMode=Enum.ModelStreamingMode.Atomic end)
 local cf=placement(yard)
 root:SetAttribute('LayoutVersion',LAYOUT_VERSION)
 local stone,trim,dark=rgb(92,84,76),rgb(118,104,88),rgb(58,52,48)
 local pad=part(root,'MiningPad',PAD_SIZE,cf*CFrame.new(0,PAD_SIZE.Y*.5,0),stone,Enum.Material.Slate,{CanCollide=true,CanQuery=true})
 for i,row in ipairs({{0,-8.7,28.6,.9},{0,8.7,28.6,.9},{-13.9,0,.9,18.3},{13.9,0,.9,18.3}})do
  part(root,'Border'..i,Vector3.new(row[3],.8,row[4]),cf*CFrame.new(row[1],.4,row[2]),trim,Enum.Material.Slate,{CanCollide=true})
 end
 -- Gold guide line from the walkway edge to the ore.
 part(root,'GuideStripe',Vector3.new(1.1,.06,7),cf*CFrame.new(-6,.53,-5.4),rgb(232,190,80),Enum.Material.Neon,{CastShadow=false})
 -- ORE: pedestal + invisible hitbox. The pile itself is drawn by each client.
 local oreCF=cf*CFrame.new(-6,PAD_SIZE.Y,1.6)
 part(root,'OrePedestal',Vector3.new(1.1,13,13),oreCF*CFrame.new(0,.45,0)*CFrame.Angles(0,0,math.rad(90)),dark,Enum.Material.Basalt,{Shape=Enum.PartType.Cylinder,CanCollide=true})
 part(root,'OrePedestalRim',Vector3.new(.5,14,14),oreCF*CFrame.new(0,.2,0)*CFrame.Angles(0,0,math.rad(90)),trim,Enum.Material.Cobblestone,{Shape=Enum.PartType.Cylinder,CanCollide=true})
 local core=part(root,'MiningOreCore',Vector3.new(9.5,7,9.5),oreCF*CFrame.new(0,4.4,0),Color3.new(1,1,1),Enum.Material.SmoothPlastic,
  {Transparency=1,CanCollide=true,CanQuery=true,CastShadow=false})
 local oreRoot=Instance.new('Attachment');oreRoot.Name='OreRoot';oreRoot.Position=Vector3.new(0,-3.5+.9,0);oreRoot.Parent=core
 local stand=Instance.new('Attachment');stand.Name='MinerStand';stand.Parent=core
 stand.WorldCFrame=CFrame.lookAt((oreCF*CFrame.new(0,3,-6.6)).Position,(oreCF*CFrame.new(0,3,0)).Position)
 prompt(core,'MiningOrePrompt','Mine','Ore pile')
 click(core,'MiningOreClick')
 -- PICKAXE SIGN: a plaque with a pickaxe icon; clicking it opens the pickaxe market.
 local signCF=cf*CFrame.new(7.2,PAD_SIZE.Y,-5.6)
 for s=-1,1,2 do part(root,'SignPost',Vector3.new(.45,6.4,.45),signCF*CFrame.new(s*2.7,3.2,.25),rgb(84,58,36),Enum.Material.WoodPlanks,{CanCollide=true})end
 local board=part(root,'MiningPickaxeShop',Vector3.new(5.8,4.4,.35),signCF*CFrame.new(0,4.15,0),rgb(110,76,46),Enum.Material.WoodPlanks,{CanCollide=true,CanQuery=true})
 part(root,'SignRoof',Vector3.new(6.6,.35,1.3),signCF*CFrame.new(0,6.55,.1),rgb(70,46,30),Enum.Material.WoodPlanks)
 signGui(board,Enum.NormalId.Front,'PICKAXES','Tap to open',rgb(120,220,255),function(bg)
  local icon=Models.PickaxeIcon(bg,150,rgb(190,200,212),rgb(156,104,56),2)
  icon.AnchorPoint=Vector2.new(.5,0);icon.Position=UDim2.fromScale(.5,.04);icon.Size=UDim2.fromScale(.56,.6)
  icon.SizeConstraint=Enum.SizeConstraint.RelativeYY
 end)
 local lamp=part(root,'SignLamp',Vector3.new(.6,.35,.6),signCF*CFrame.new(0,6.3,-.6),rgb(255,214,140),Enum.Material.Neon,{CastShadow=false})
 local light=Instance.new('SpotLight');light.Face=Enum.NormalId.Bottom;light.Range=9;light.Brightness=1.6;light.Angle=70;light.Color=rgb(255,214,160);light.Parent=lamp
 prompt(board,'MiningPickaxeShopPrompt','Open','Pickaxes')
 click(board,'MiningPickaxeShopClick')
 -- STRENGTH STATION: rubber mat, rack with the 7 weights, and a sign.
 local gymCF=cf*CFrame.new(7.6,PAD_SIZE.Y,3.4)
 part(root,'GymMat',Vector3.new(9.6,.18,7.4),gymCF*CFrame.new(0,.09,0),rgb(36,40,46),Enum.Material.Rubber)
 local rack=part(root,'MiningStrengthRack',Vector3.new(8.8,.35,1.2),gymCF*CFrame.new(0,2.6,2.6),rgb(54,58,66),Enum.Material.Metal,{CanCollide=true,CanQuery=true})
 for s=-1,1,2 do part(root,'RackPost',Vector3.new(.4,3.2,1.2),gymCF*CFrame.new(s*4.2,1.2,2.6),rgb(44,48,54),Enum.Material.Metal,{CanCollide=true})end
 part(root,'RackShelf',Vector3.new(8.8,.25,1.4),gymCF*CFrame.new(0,.9,2.6),rgb(54,58,66),Enum.Material.Metal)
 for i,w in ipairs(M.Weights)do
  local model=Models.Weight(w,i)
  model.Name='RackWeight_'..i
  local x=-3.6+(i-1)*1.2
  model:PivotTo(gymCF*CFrame.new(x,(i<=3)and 3.15 or 1.45,2.6)*CFrame.Angles(0,math.rad(90),0))
  model:ScaleTo(.42)
  for _,d in ipairs(model:GetDescendants())do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false end end
  model:SetAttribute('WeightLevel',i)
  model.Parent=root
 end
 local gymSign=part(root,'StrengthSign',Vector3.new(5.6,2.4,.3),gymCF*CFrame.new(0,5.0,3.1),rgb(110,76,46),Enum.Material.WoodPlanks)
 for s=-1,1,2 do part(root,'GymSignPost',Vector3.new(.35,2.0,.35),gymCF*CFrame.new(s*2.5,3.8,3.1),rgb(84,58,36),Enum.Material.WoodPlanks)end
 signGui(gymSign,Enum.NormalId.Front,'STRENGTH','Lift weights',rgb(141,239,130),function(bg)
  local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,.6);t.Position=UDim2.fromScale(0,.03)
  t.Text='💪';t.TextScaled=true;t.Font=Enum.Font.GothamBlack;t.Parent=bg
 end)
 prompt(rack,'MiningStrengthPrompt','Train','Weights')
 click(rack,'MiningStrengthClick')
 -- Decor: lantern posts and a mine cart.
 for _,x in ipairs({-13.2,13.2})do
  local post=part(root,'LanternPost',Vector3.new(.5,7,.5),cf*CFrame.new(x,3.9,-8.4),rgb(40,36,34),Enum.Material.Metal,{CanCollide=true})
  local lantern=part(root,'Lantern',Vector3.new(1.1,1.3,1.1),post.CFrame*CFrame.new(0,3.9,0),rgb(255,196,110),Enum.Material.Neon,{CastShadow=false})
  local l=Instance.new('PointLight');l.Range=14;l.Brightness=1.1;l.Color=rgb(255,190,120);l.Shadows=false;l.Parent=lantern
 end
 local cartCF=cf*CFrame.new(-12,PAD_SIZE.Y,6.2)*CFrame.Angles(0,math.rad(12),0)
 part(root,'CartBody',Vector3.new(3.2,1.8,2.2),cartCF*CFrame.new(0,1.5,0),rgb(96,70,48),Enum.Material.WoodPlanks,{CanCollide=true})
 part(root,'CartRim',Vector3.new(3.4,.3,2.4),cartCF*CFrame.new(0,2.45,0),rgb(70,70,74),Enum.Material.Metal)
 for _,o in ipairs({{-1,-1.15},{1,-1.15},{-1,1.15},{1,1.15}})do
  part(root,'CartWheel',Vector3.new(.3,1,1),cartCF*CFrame.new(o[1],.55,o[2]),rgb(40,40,44),Enum.Material.Metal,{Shape=Enum.PartType.Cylinder})
 end
 for i=1,4 do
  part(root,'CartOre',Vector3.new(1,.8,.9),cartCF*CFrame.new(-1+i*.45,2.6+(i%2)*.2,(i%2==0)and .4 or-.3)*CFrame.Angles(i,i*.7,0),rgb(150,140,130),Enum.Material.Slate)
 end
 root:SetAttribute('OwnerUserId',0)
 root.Parent=yard
 return root
end

-- STATE MIRROR -----------------------------------------------------------------------------------
local DEFAULTS={OreId=M.Ores[1].Id,OreHP=M.Ores[1].HP,OreMaxHP=M.Ores[1].HP,OreSerial=0,HitSerial=0,HitQuality=1,HitCrit=false,
 HitPayout=0,HitDamage=0,Combo=0,BreakSerial=0,BrokenId='',BrokenValue=0,PickaxeLevel=0,Strength=0,WeightLevel=0,WeightOwned=0,
 TrainSerial=0,Active=false,Training=false}
local MAP={OreId='MiningOreId',OreHP='MiningOreHP',OreMaxHP='MiningOreMaxHP',OreSerial='MiningOreSerial',HitQuality='MiningLastQuality',
 HitCrit='MiningLastCrit',HitPayout='MiningLastPayout',HitDamage='MiningLastDamage',Combo='MiningCombo',BrokenId='MiningBrokenId',
 BrokenValue='MiningBrokenValue',PickaxeLevel='MiningPickaxe',Strength='MiningStrength',WeightLevel='MiningWeight',WeightOwned='MiningWeightOwned',
 TrainSerial='MiningTrainingReps',BreakSerial='MiningOresBroken',HitSerial='MiningHitSerial'}
-- Detail attributes first; serials last so a client reacting to a serial reads fresh details.
local ORDER={'OreId','OreHP','OreMaxHP','HitQuality','HitCrit','HitPayout','HitDamage','Combo','BrokenId','BrokenValue','PickaxeLevel',
 'Strength','WeightLevel','WeightOwned','OreSerial','BreakSerial','HitSerial','TrainSerial'}

local bindings={} -- yard -> {Player, Connections}
local function apply(root,player)
 if not player then
  for key,value in pairs(DEFAULTS)do root:SetAttribute(key,value)end
  root:SetAttribute('OwnerUserId',0)
  return
 end
 for _,key in ipairs(ORDER)do
  local v=player:GetAttribute(MAP[key]);if v==nil then v=DEFAULTS[key]end
  root:SetAttribute(key,v)
 end
 root:SetAttribute('Active',(player:GetAttribute('MiningActiveUntil')or 0)>=os.time())
 root:SetAttribute('Training',(player:GetAttribute('MiningTrainingUntil')or 0)>=os.time())
 root:SetAttribute('OwnerUserId',player.UserId)
 root:SetAttribute('Revision',player:GetAttribute('MiningRevision')or 0)
end
local function setPrompts(root,enabled)
 for _,d in ipairs(root:GetDescendants())do if d:IsA('ProximityPrompt')then d.Enabled=enabled end end
end

-- HELD ITEMS ----------------------------------------------------------------------------------
local function hand(character)
 return character and(character:FindFirstChild('RightHand')or character:FindFirstChild('Right Arm'))
end
local function clearHeld(character,name)
 local old=character and character:FindFirstChild(name);if old then old:Destroy()end
end
local function attach(character,name,model,gripCF)
 local h=hand(character);if not h then return end
 clearHeld(character,name)
 model.Name=name;Models.WeldToSelf(model)
 local handle=model.PrimaryPart
 local weld=Instance.new('Weld');weld.Name='HandGrip';weld.Part0=h;weld.Part1=handle;weld.C0=gripCF;weld.Parent=handle
 model.Parent=character
end
local PICK_GRIP=CFrame.new(0,-.25,-.1)*CFrame.Angles(-math.pi/2,0,0)*CFrame.new(0,1.3,0)
local WEIGHT_GRIP=CFrame.new(0,-.3,0)
local function syncHeld(player)
 local character=player.Character;if not character then return end
 local active=(player:GetAttribute('MiningActiveUntil')or 0)>=os.time()
 local level=player:GetAttribute('MiningPickaxe')or 0
 local held=character:FindFirstChild('MiningHeldPickaxe')
 if active and M.Pickaxes[level]then
  if not held or held:GetAttribute('Level')~=level then
   local model=Models.Pickaxe(M.Pickaxes[level],level);model:SetAttribute('Level',level)
   attach(character,'MiningHeldPickaxe',model,PICK_GRIP)
  end
 elseif held then held:Destroy()end
 local lifting=(player:GetAttribute('MiningTrainingUntil')or 0)>=os.time()
 local weightLevel=player:GetAttribute('MiningWeight')or 0
 local weight=character:FindFirstChild('MiningHeldWeight')
 if lifting and M.Weights[weightLevel]and not active then
  if not weight or weight:GetAttribute('Level')~=weightLevel then
   local model=Models.Weight(M.Weights[weightLevel],weightLevel);model:SetAttribute('Level',weightLevel)
   attach(character,'MiningHeldWeight',model,WEIGHT_GRIP)
  end
 elseif weight then weight:Destroy()end
end

-- BINDING ----------------------------------------------------------------------------------------
local function unbind(yard)
 local b=bindings[yard];bindings[yard]=nil
 if b then for _,c in ipairs(b.Connections)do c:Disconnect()end;if b.Player.Character then clearHeld(b.Player.Character,'MiningHeldPickaxe');clearHeld(b.Player.Character,'MiningHeldWeight')end end
 local root=yard:FindFirstChild('MiningCorner')
 if root then apply(root,nil);setPrompts(root,false)end
end
local function bind(yard,player)
 unbind(yard)
 local root=build(yard)
 local b={Player=player,Connections={}};bindings[yard]=b
 local queued=false
 local function refresh()
  queued=false
  if bindings[yard]~=b then return end
  apply(root,player);syncHeld(player)
 end
 table.insert(b.Connections,player:GetAttributeChangedSignal('MiningRevision'):Connect(function()
  if not queued then queued=true;task.defer(refresh)end
 end))
 table.insert(b.Connections,player.CharacterAdded:Connect(function()task.wait(.5);if bindings[yard]==b then syncHeld(player)end end))
 apply(root,player);setPrompts(root,true);syncHeld(player)
end

local function track(yard)
 if not yard:GetAttribute('YardId')then return end
 local corner=build(yard);apply(corner,nil);setPrompts(corner,false)
 local function ownerChanged()
  local id=yard:GetAttribute('OwnerUserId')or 0
  local player=id~=0 and Players:GetPlayerByUserId(id)or nil
  local current=bindings[yard]
  if player and(not current or current.Player~=player)then bind(yard,player)
  elseif not player and current then unbind(yard)end
 end
 yard:GetAttributeChangedSignal('OwnerUserId'):Connect(ownerChanged)
 ownerChanged()
end

for _,yard in ipairs(yardsFolder:GetChildren())do task.spawn(track,yard)end
yardsFolder.ChildAdded:Connect(function(yard)task.defer(track,yard)end)
Players.PlayerRemoving:Connect(function(player)
 for yard,b in pairs(bindings)do if b.Player==player then unbind(yard)end end
end)
-- Sessions expire on the server clock (os.time) without any request: re-check held items.
task.spawn(function()
 while true do
  task.wait(1)
  for yard,b in pairs(bindings)do
   local root=yard:FindFirstChild('MiningCorner')
   if root then
    local active=(b.Player:GetAttribute('MiningActiveUntil')or 0)>=os.time()
    if root:GetAttribute('Active')~=active then root:SetAttribute('Active',active)end
    local training=(b.Player:GetAttribute('MiningTrainingUntil')or 0)>=os.time()
    if root:GetAttribute('Training')~=training then root:SetAttribute('Training',training)end
   end
   syncHeld(b.Player)
  end
 end
end)
