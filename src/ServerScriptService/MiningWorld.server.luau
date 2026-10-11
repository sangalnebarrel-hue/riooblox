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

local LAYOUT_VERSION=21
local PAD_SIZE=Vector3.new(23,.5,18)

local function part(parent,name,size,cf,color,mat,props)
 local p=Models.Part(parent,name,size,cf,color,mat,props);return p
end
local function rgb(r,g,b)return Color3.fromRGB(r,g,b)end

-- PLACEMENT ------------------------------------------------------------------------------------
-- Right next to kennel 1 (DigSlot_1), at the kennel end of the cosmetic garden. This 23x18 spot
-- stays clear of every PlotAppearance stage (levels 1-9) and skin (14) in all 8 yards, unlike
-- the old spot mirrored from the Lucky Pads, which skins and the level-8 pavilion covered.
-- Returns the corner CFrame and sx: LookVector points to the central walkway; local +X*sx points
-- towards the kennels / street (yards 5-8 are mirror images of yards 1-4).
local function placement(yard)
 local foundation=yard:FindFirstChild('YardFoundation',true)
 local storage=yard:FindFirstChild('StorageAnchor')
 local slot=yard:FindFirstChild('DigSlot_1')
 local pit=slot and slot:FindFirstChild('DarkExcavation')
 local spawn=yard:FindFirstChild('YardSpawn',true)
 local frame,sx
 if foundation and storage and foundation:IsA('BasePart')and storage:IsA('BasePart')then
  local c=Vector3.new(foundation.Position.X,1.2,foundation.Position.Z)
  local t=Vector3.new(storage.Position.X,1.2,storage.Position.Z)
  frame=CFrame.lookAt(c,t)
  sx=(pit and pit:IsA('BasePart')and frame:PointToObjectSpace(pit.Position).X>0)and-1 or 1
 end
 local center
 if frame then
  center=frame:PointToWorldSpace(Vector3.new(-18*sx,0,4.5))
 else
  -- Fallback with the same result for the standard yards.
  local x=foundation and foundation.Position.X or yard:GetPivot().Position.X
  local z=spawn and spawn.Position.Z or yard:GetPivot().Position.Z
  center=Vector3.new((x<0 and-1 or 1)*100.5,1.13,z+18)
  sx=x<0 and 1 or-1
  frame=CFrame.lookAt(Vector3.new(x,1.2,z),Vector3.new(x+(x<0 and-1 or 1),1.2,z))
 end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={yard:FindFirstChild('YardLandscape')or yard}
 local hit=workspace:Raycast(Vector3.new(center.X,40,center.Z),Vector3.new(0,-80,0),params)
 local ground=hit and hit.Position.Y or 1.13
 local pos=Vector3.new(center.X,ground,center.Z)
 return CFrame.lookAt(pos,pos+frame.RightVector*sx),sx
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
local function prompt(parent,name,action,object,distance)
 local p=Instance.new('ProximityPrompt');p.Name=name;p.ActionText=action;p.ObjectText=object
 p.KeyboardKeyCode=Enum.KeyCode.E;p.GamepadKeyCode=Enum.KeyCode.ButtonX;p.HoldDuration=0
 p.MaxActivationDistance=distance or 8;p.RequiresLineOfSight=false;p.Enabled=false;p.Parent=parent
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
 -- Streams as one piece; always present for the owner once AddPersistentPlayer is called.
 pcall(function()root.ModelStreamingMode=Enum.ModelStreamingMode.PersistentPerPlayer end)
 local cf,sx=placement(yard)
 local function at(k,h,d)return cf*CFrame.new(sx*k,h,-d)end -- k: towards kennels, d: towards walkway
 root:SetAttribute('LayoutVersion',LAYOUT_VERSION)
 local top=PAD_SIZE.Y*.5+.12
 local stone,trim,dark=rgb(92,84,76),rgb(118,104,88),rgb(58,52,48)
 part(root,'MiningPad',PAD_SIZE,cf*CFrame.new(0,.12,0),stone,Enum.Material.Slate,{CanCollide=true,CanQuery=true})
 local hx,hz=PAD_SIZE.X*.5,PAD_SIZE.Z*.5
 for i,row in ipairs({{0,-hz+.4,PAD_SIZE.X+.6,.8},{0,hz-.4,PAD_SIZE.X+.6,.8},{-hx+.4,0,.8,PAD_SIZE.Z},{hx-.4,0,.8,PAD_SIZE.Z}})do
  part(root,'Border'..i,Vector3.new(row[3],.7,row[4]),cf*CFrame.new(row[1],top,row[2]),trim,Enum.Material.Slate,{CanCollide=true})
 end
 -- Gold guide stripe from the walkway edge to the strike spot.
 part(root,'GuideStripe',Vector3.new(1.1,.06,4.2),at(0,top+.02,7),rgb(232,190,80),Enum.Material.Neon,{CastShadow=false})
 -- ORE: pedestal + invisible collidable hitbox. The pile itself is drawn by each client.
 local oreCF=at(0,top,-3.5)
 part(root,'OrePedestal',Vector3.new(.9,10.4,10.4),oreCF*CFrame.new(0,.35,0)*CFrame.Angles(0,0,math.rad(90)),dark,Enum.Material.Basalt,{Shape=Enum.PartType.Cylinder,CanCollide=true})
 part(root,'OrePedestalRim',Vector3.new(.45,11.2,11.2),oreCF*CFrame.new(0,.15,0)*CFrame.Angles(0,0,math.rad(90)),trim,Enum.Material.Cobblestone,{Shape=Enum.PartType.Cylinder,CanCollide=true})
 local core=part(root,'MiningOreCore',Vector3.new(8.6,7,8.6),oreCF*CFrame.new(0,4.3,0),Color3.new(1,1,1),Enum.Material.SmoothPlastic,
  {Transparency=1,CanCollide=true,CanQuery=true,CastShadow=false})
 local oreRoot=Instance.new('Attachment');oreRoot.Name='OreRoot';oreRoot.Position=Vector3.new(0,-3.5+.8,0);oreRoot.Parent=core
 local stand=Instance.new('Attachment');stand.Name='MinerStand';stand.Parent=core
 local standPos=at(0,top+3,4.5).Position
 stand.WorldCFrame=CFrame.lookAt(standPos,Vector3.new(oreCF.Position.X,standPos.Y,oreCF.Position.Z))
 prompt(core,'MiningOrePrompt','Mine','Ore pile',10)
 click(core,'MiningOreClick')
 -- PICKAXE PLAQUE: a sign with a pickaxe icon; pressing it opens the pickaxe market.
 local signCF=at(8.6,top,.5)
 for s=-1,1,2 do part(root,'SignPost',Vector3.new(.4,5.4,.4),signCF*CFrame.new(s*2.05,2.7,.25),rgb(84,58,36),Enum.Material.WoodPlanks,{CanCollide=true})end
 local board=part(root,'MiningPickaxeShop',Vector3.new(4.4,3.5,.35),signCF*CFrame.new(0,3.55,0),rgb(110,76,46),Enum.Material.WoodPlanks,{CanCollide=true,CanQuery=true})
 part(root,'SignRoof',Vector3.new(5.1,.3,1.2),signCF*CFrame.new(0,5.5,.1),rgb(70,46,30),Enum.Material.WoodPlanks)
 signGui(board,Enum.NormalId.Front,'PICKAXES','Tap to open',rgb(120,220,255),function(bg)
  local icon=Models.PickaxeIcon(bg,150,rgb(190,200,212),rgb(156,104,56),2)
  icon.AnchorPoint=Vector2.new(.5,0);icon.Position=UDim2.fromScale(.5,.04);icon.Size=UDim2.fromScale(.6,.6)
  icon.SizeConstraint=Enum.SizeConstraint.RelativeYY
 end)
 local lamp=part(root,'SignLamp',Vector3.new(.6,.3,.6),signCF*CFrame.new(0,5.3,-.6),rgb(255,214,140),Enum.Material.Neon,{CastShadow=false})
 local light=Instance.new('SpotLight');light.Face=Enum.NormalId.Bottom;light.Range=8;light.Brightness=1.5;light.Angle=70;light.Color=rgb(255,214,160);light.Parent=lamp
 prompt(board,'MiningPickaxeShopPrompt','Open','Pickaxes',7)
 click(board,'MiningPickaxeShopClick')
 -- STRENGTH STATION: rubber platform, two-shelf rack with the 7 weights, and a sign.
 local gymCF=at(-8.4,top,1)
 part(root,'GymMat',Vector3.new(5.6,.16,6),gymCF*CFrame.new(0,.08,0),rgb(36,40,46),Enum.Material.Rubber)
 local rackCF=at(-8.4,top,-2.4)
 local rack=part(root,'MiningStrengthRack',Vector3.new(5.6,.3,1.2),rackCF*CFrame.new(0,2.9,0),rgb(54,58,66),Enum.Material.Metal,{CanCollide=true,CanQuery=true})
 for s=-1,1,2 do part(root,'RackPost',Vector3.new(.35,3.1,1.2),rackCF*CFrame.new(s*2.65,1.55,0),rgb(44,48,54),Enum.Material.Metal,{CanCollide=true})end
 part(root,'RackShelf',Vector3.new(5.6,.25,1.3),rackCF*CFrame.new(0,1.05,0),rgb(54,58,66),Enum.Material.Metal,{CanCollide=true})
 for i,w in ipairs(M.Weights)do
  local model=Models.Weight(w,i)
  model.Name='RackWeight_'..i
  local upper=i<=4
  local x=upper and(-1.95+(i-1)*1.3)or(-1.3+(i-5)*1.3)
  local shelfTop=upper and 3.05 or 1.18
  model:PivotTo(rackCF*CFrame.new(x*sx,shelfTop+1,0)*CFrame.Angles(0,math.rad(90),0))
  model:ScaleTo(.34)
  -- Rest the weight on its shelf whatever its shape.
  local boxCF,boxSize=model:GetBoundingBox()
  local bottom=boxCF.Position.Y-boxSize.Y*.5
  model:PivotTo(model:GetPivot()+Vector3.new(0,(rackCF*CFrame.new(0,shelfTop,0)).Position.Y-bottom,0))
  for _,d in ipairs(model:GetDescendants())do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false end end
  model:SetAttribute('WeightLevel',i)
  model.Parent=root
 end
 local gymSign=part(root,'StrengthSign',Vector3.new(4.4,1.9,.3),rackCF*CFrame.new(0,4.85,.2),rgb(110,76,46),Enum.Material.WoodPlanks)
 for s=-1,1,2 do part(root,'GymSignPost',Vector3.new(.3,1.5,.3),rackCF*CFrame.new(s*2,3.65,.2),rgb(84,58,36),Enum.Material.WoodPlanks)end
 signGui(gymSign,Enum.NormalId.Front,'STRENGTH','Lift weights',rgb(141,239,130),function(bg)
  local t=Instance.new('TextLabel');t.BackgroundTransparency=1;t.Size=UDim2.fromScale(1,.6);t.Position=UDim2.fromScale(0,.03)
  t.Text='💪';t.TextScaled=true;t.Font=Enum.Font.GothamBlack;t.Parent=bg
 end)
 prompt(rack,'MiningStrengthPrompt','Train','Weights',7)
 click(rack,'MiningStrengthClick')
 -- Decor in the free back corners: a loaded mine cart (kennel side) and a lantern with crates.
 local cartCF=at(8.4,top,-6.4)*CFrame.Angles(0,math.rad(8),0)
 part(root,'CartBody',Vector3.new(3,1.7,2.1),cartCF*CFrame.new(0,1.35,0),rgb(96,70,48),Enum.Material.WoodPlanks,{CanCollide=true})
 part(root,'CartRim',Vector3.new(3.2,.28,2.3),cartCF*CFrame.new(0,2.25,0),rgb(70,70,74),Enum.Material.Metal)
 for _,o in ipairs({{-1,-1.1},{1,-1.1},{-1,1.1},{1,1.1}})do
  part(root,'CartWheel',Vector3.new(.3,.95,.95),cartCF*CFrame.new(o[1],.5,o[2]),rgb(40,40,44),Enum.Material.Metal,{Shape=Enum.PartType.Cylinder})
 end
 for i=1,4 do
  part(root,'CartOre',Vector3.new(.95,.75,.85),cartCF*CFrame.new(-1.05+i*.42,2.4+(i%2)*.2,(i%2==0)and .4 or-.3)*CFrame.Angles(i,i*.7,0),rgb(150,140,130),Enum.Material.Slate)
 end
 local postCF=at(-10.3,top,-7.4)
 local post=part(root,'LanternPost',Vector3.new(.45,6.2,.45),postCF*CFrame.new(0,3.1,0),rgb(40,36,34),Enum.Material.Metal,{CanCollide=true})
 local lantern=part(root,'Lantern',Vector3.new(1,1.2,1),post.CFrame*CFrame.new(0,3.55,0),rgb(255,196,110),Enum.Material.Neon,{CastShadow=false})
 local l=Instance.new('PointLight');l.Range=13;l.Brightness=1.1;l.Color=rgb(255,190,120);l.Shadows=false;l.Parent=lantern
 for i,o in ipairs({{-7,-7.3,0},{-7.9,-6.6,.4},{-7.4,-7,1.1}})do
  part(root,'Crate'..i,Vector3.new(1.3,1.1,1.3),at(o[1],top+.55+(i==3 and 1.1 or 0),o[2])*CFrame.Angles(0,o[3],0),rgb(150,110,70),Enum.Material.WoodPlanks,{CanCollide=i~=3})
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
-- Detail attributes first; serials last (BreakSerial before OreSerial) so a client reacting to a
-- serial reads fresh details.
local ORDER={'OreId','OreHP','OreMaxHP','HitQuality','HitCrit','HitPayout','HitDamage','Combo','BrokenId','BrokenValue','PickaxeLevel',
 'Strength','WeightLevel','WeightOwned','BreakSerial','OreSerial','HitSerial','TrainSerial'}

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
 local root=yard:FindFirstChild('MiningCorner')
 if b then
  for _,c in ipairs(b.Connections)do c:Disconnect()end
  if b.Player.Character then clearHeld(b.Player.Character,'MiningHeldPickaxe');clearHeld(b.Player.Character,'MiningHeldWeight')end
  if root then pcall(function()(root::Model):RemovePersistentPlayer(b.Player)end)end
 end
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
 -- The owner always has their own corner streamed in (tutorial markers, mining from afar).
 pcall(function()root:AddPersistentPlayer(player)end)
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
