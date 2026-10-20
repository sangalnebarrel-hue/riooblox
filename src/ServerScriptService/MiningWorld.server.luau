-- Active Mining world: builds the ORE QUARRY of every yard (the old Mining Corner, now filling the
-- quiet corner of the yard between the walkway, the fence, kennel 1 and the service row), mirrors
-- the owner's mining state onto it (so every client can render the ore piles and hit effects) and
-- gives every player their pickaxe as a Tool in the inventory (Backpack / hotbar): it can be held
-- anywhere, it is drawn automatically when a mining session starts, and it hangs on the back while
-- it is not in the hand. The pickaxe you see is welded to the character by this script (hand or
-- back); the Tool itself is only the hotbar entry.
-- Ore piles themselves are rendered client-side (StarterPlayerScripts.MiningClient).
-- The weight rack (strength training) was removed: Strength is bought in the UPGRADE TREE.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Config=require(RS:WaitForChild('DogEconomy'):WaitForChild('Config'))
local Models=require(RS:WaitForChild('Mining'):WaitForChild('MiningModels'))
-- Halloween pickaxe skins (cosmetic: model / swing / sounds only, stats stay the tier's). Register() teaches Models.Pickaxe the skin designs before any held model is built.
local Skins=(function()local ok,m=pcall(function()return require(RS:WaitForChild('Halloween',10):WaitForChild('PickaxeSkins',10))end);if ok and type(m)=='table'then m.Register();return m end;return{Of=function()return nil end,Resolve=function(d)return d end}end)()
local M=Config.Mining
local yardsFolder=workspace:WaitForChild('DOGROTS_District'):WaitForChild('04_PlayerYards')

local LAYOUT_VERSION=30
-- v30: the ORE QUARRY. Yard-frame rectangle (PlotAppearance.Frame: x' = local x, every yard has the
-- same layout now; z towards the gate +64 / storage -64): from the walkway strip (x' -7.6, the small
-- decor spots at x' -5.9 stay free) to the fence-side plant strip (x' -29), and from the big decor
-- spots L3/L4 (z 6.5) to the corridor in front of the collector (z -38.5).
local SITE={X0=-29,X1=-7.6,Z0=-38.5,Z1=6.5}
local SITE_W,SITE_L=SITE.X1-SITE.X0,SITE.Z1-SITE.Z0
local SITE_X,SITE_Z=(SITE.X0+SITE.X1)/2,(SITE.Z0+SITE.Z1)/2
-- The dig field: the main pile in front of the miner, four outcrops in an arc behind it.
local MAIN={X=-18.3,Z=-18}
local STAND={X=-18.3,Z=-9.6}
local SATS={{X=-25.4,Z=-13.2,S=.5},{X=-11.2,Z=-13.2,S=.5},{X=-25,Z=-24.6,S=.42},{X=-11.6,Z=-24.6,S=.42}}

local function part(parent,name,size,cf,color,mat,props)
 return Models.Part(parent,name,size,cf,color,mat,props)
end
local function rgb(r,g,b)return Color3.fromRGB(r,g,b)end

-- PLACEMENT ------------------------------------------------------------------------------------
-- Returns the yard-frame CFrame at ground height (D(x',h,z) = base * CFrame.new(x',h,z)).
local function placement(yard)
 local foundation=yard:FindFirstChild('YardFoundation',true)
 local storage=yard:FindFirstChild('StorageAnchor')
 local frame
 if foundation and storage and foundation:IsA('BasePart')and storage:IsA('BasePart')then
  local fp,sp=foundation.CFrame.Position,storage.CFrame.Position
  frame=CFrame.lookAt(Vector3.new(fp.X,1.2,fp.Z),Vector3.new(sp.X,1.2,sp.Z))
 else
  local p=yard:GetPivot().Position
  frame=CFrame.lookAt(Vector3.new(p.X,1.2,p.Z),Vector3.new(p.X+(p.X<0 and-1 or 1),1.2,p.Z))
 end
 local center=frame:PointToWorldSpace(Vector3.new(SITE_X,0,SITE_Z))
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={yard:FindFirstChild('YardLandscape')or yard}
 local hit=workspace:Raycast(Vector3.new(center.X,40,center.Z),Vector3.new(0,-80,0),params)
 local ground=hit and hit.Position.Y or 1.13
 return CFrame.new(frame.Position.X,ground,frame.Position.Z)*frame.Rotation
end

-- BUILD ----------------------------------------------------------------------------------------
local function signGui(board,face,title,sub,accent,icon,ppm)
 local g=Instance.new('SurfaceGui');g.Name='Face';g.Face=face;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=ppm or 60
 g.LightInfluence=.15;g.MaxDistance=110;g.Parent=board
 local bg=Instance.new('Frame');bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=rgb(52,36,24);bg.BorderSizePixel=0;bg.Parent=g
 local grad=Instance.new('UIGradient');grad.Color=ColorSequence.new(rgb(74,52,34),rgb(40,27,18));grad.Rotation=90;grad.Parent=bg
 local stroke=Instance.new('UIStroke');stroke.Color=accent;stroke.Thickness=10;stroke.Parent=bg
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,18);corner.Parent=bg
 if icon then icon(bg)end
 local t=Instance.new('TextLabel');t.Name='Title';t.BackgroundTransparency=1;t.Size=UDim2.fromScale(.92,.24);t.Position=UDim2.fromScale(.04,.6)
 t.Font=Enum.Font.FredokaOne;t.TextScaled=true;t.TextColor3=rgb(255,236,190);t.Text=title;t.TextStrokeTransparency=.4;t.Parent=bg
 local s=Instance.new('TextLabel');s.Name='Sub';s.BackgroundTransparency=1;s.Size=UDim2.fromScale(.92,.12);s.Position=UDim2.fromScale(.04,.85)
 s.Font=Enum.Font.FredokaOne;s.TextScaled=true;s.TextColor3=accent;s.Text=sub;s.Parent=bg
 return g
end
local function prompt(parent,name,action,object,distance)
 local p=Instance.new('ProximityPrompt');p.Name=name;p.ActionText=action;p.ObjectText=object
 p.KeyboardKeyCode=Enum.KeyCode.E;p.GamepadKeyCode=Enum.KeyCode.ButtonX;p.HoldDuration=0
 p.MaxActivationDistance=distance or 8;p.RequiresLineOfSight=false;p.Enabled=false;p.Parent=parent
 return p
end
-- 18 studs: every clickable piece is within ~20 studs of MiningPad's centre, and Runtime accepts
-- mining actions up to 32 studs from it, so a click can never open something whose actions fail.
local function click(parent,name)
 local c=Instance.new('ClickDetector');c.Name=name;c.MaxActivationDistance=18;c.Parent=parent;return c
end
local function cyl(parent,name,len,d,cf,color,mat,props)
 -- vertical cylinder (Roblox cylinders run along local X)
 local p=part(parent,name,Vector3.new(len,d,d),cf*CFrame.Angles(0,0,math.rad(90)),color,mat,props);p.Shape=Enum.PartType.Cylinder;return p
end

local function build(yard:Model):Model
 local existing=yard:FindFirstChild('MiningCorner')::Model?
 if existing and existing:GetAttribute('LayoutVersion')==LAYOUT_VERSION then return existing end
 if existing then existing:Destroy()end
 local root=Instance.new('Model');root.Name='MiningCorner'
 -- Streams as one piece; always present for the owner once AddPersistentPlayer is called.
 local okMode,errMode=pcall(function()root.ModelStreamingMode=Enum.ModelStreamingMode.PersistentPerPlayer end)
 if not okMode then warn('DOGROTS mining: ModelStreamingMode not set on '..yard.Name..': '..tostring(errMode))end
 local base=placement(yard)
 local function D(x,h,z)return base*CFrame.new(x,h,z)end
 local FACE_WALK=CFrame.Angles(0,-math.pi/2,0) -- a model's front (-Z) towards the central walkway (+x')
 root:SetAttribute('LayoutVersion',LAYOUT_VERSION)
 local PAD_H=.5
 local top=PAD_H*.5+.12
 local stone,trim,dark,timber=rgb(96,88,80),rgb(122,108,92),rgb(58,52,48),rgb(110,76,46)
 -- Slab, inlaid quarry floor, raised timber-and-stone border with an opening to the walkway.
 local pad=part(root,'MiningPad',Vector3.new(SITE_W,PAD_H,SITE_L),D(SITE_X,.12,SITE_Z),stone,Enum.Material.Slate,{CanCollide=true,CanQuery=true})
 pad:SetAttribute('SiteX0',SITE.X0);pad:SetAttribute('SiteX1',SITE.X1);pad:SetAttribute('SiteZ0',SITE.Z0);pad:SetAttribute('SiteZ1',SITE.Z1)
 part(root,'QuarryFloor',Vector3.new(SITE_W-2.4,.06,SITE_L-12),D(SITE_X,top+.01,SITE_Z-3),rgb(118,104,88),Enum.Material.Ground,{CastShadow=false})
 local function border(name,x0,z0,x1,z1)
  local len=math.max(math.abs(x1-x0),math.abs(z1-z0))
  local alongX=math.abs(x1-x0)>math.abs(z1-z0)
  local size=alongX and Vector3.new(len,.55,.9)or Vector3.new(.9,.55,len)
  local cf=D((x0+x1)/2,top+.25,(z0+z1)/2)
  part(root,name..'Stone',size+Vector3.new(.2,0,.2),cf,trim,Enum.Material.Slate,{CanCollide=true})
  part(root,name..'Beam',(alongX and Vector3.new(len,.35,.6)or Vector3.new(.6,.35,len)),cf*CFrame.new(0,.42,0),timber,Enum.Material.WoodPlanks,{CanCollide=true})
 end
 local x0,x1,z0,z1=SITE.X0+.45,SITE.X1-.45,SITE.Z0+.45,SITE.Z1-.45
 border('BorderFence',x0,z0,x0,z1)
 border('BorderBack',x0,z0,x1,z0)
 border('BorderFront',x0,z1,x1,z1)
 -- walkway side: two runs with the entrance gap (z -4.5 .. 2.5)
 border('BorderWalkA',x1,z0,x1,-4.5)
 border('BorderWalkB',x1,2.5,x1,z1)
 -- Gravel patches and quarry cracks so the site reads as a dig field, not a slab.
 for i,g in ipairs({{-24,-17,5,3.6,20},{-12.5,-19,6,3.2,-14},{-19,-30,4.2,2.6,8},{-11,-6,3.6,2.4,30},{-26,-6,3.2,2.2,-25},{-15,-27,4.4,3,40}})do
  part(root,'Gravel'..i,Vector3.new(g[3],.08,g[4]),D(g[1],top+.03,g[2])*CFrame.Angles(0,math.rad(g[5]),0),rgb(112,100,88),Enum.Material.Pebble,{CastShadow=false})
 end
 for i,c in ipairs({{-21,-21.5,3.4,60},{-14.5,-22,2.8,-40},{-26.4,-19,2.6,15},{-10.4,-17.6,3,75},{-18,-26,3.2,-10}})do
  part(root,'Crack'..i,Vector3.new(.22,.05,c[3]),D(c[1],top+.04,c[2])*CFrame.Angles(0,math.rad(c[4]),0),rgb(36,30,28),Enum.Material.Slate,{CastShadow=false})
 end
 -- Gold guide stripe from the entrance to the miner's spot.
 local gx=(SITE.X1+STAND.X)/2
 part(root,'GuideStripe',Vector3.new(math.abs(SITE.X1-STAND.X)-1.5,.06,1.1),D(gx,top+.05,-1),rgb(232,190,80),Enum.Material.Neon,{CastShadow=false})
 part(root,'GuideStripe',Vector3.new(1.1,.06,8.6),D(STAND.X,top+.05,-5.1),rgb(232,190,80),Enum.Material.Neon,{CastShadow=false})
 part(root,'StandMark',Vector3.new(.12,3,3),D(STAND.X,top+.05,STAND.Z)*CFrame.Angles(0,0,math.rad(90)),rgb(255,214,90),Enum.Material.Neon,{Shape=Enum.PartType.Cylinder,CastShadow=false,Transparency=.25})

 -- ORE: pedestal + invisible collidable hitbox. The pile itself is drawn by each client.
 local oreCF=D(MAIN.X,top,MAIN.Z)
 part(root,'OrePedestal',Vector3.new(.9,10.4,10.4),oreCF*CFrame.new(0,.35,0)*CFrame.Angles(0,0,math.rad(90)),dark,Enum.Material.Basalt,{Shape=Enum.PartType.Cylinder,CanCollide=true})
 part(root,'OrePedestalRim',Vector3.new(.45,11.2,11.2),oreCF*CFrame.new(0,.15,0)*CFrame.Angles(0,0,math.rad(90)),trim,Enum.Material.Cobblestone,{Shape=Enum.PartType.Cylinder,CanCollide=true})
 for i=0,7 do
  local a=i/8*math.pi*2
  part(root,'PedestalStud',Vector3.new(.7,.5,.7),oreCF*CFrame.new(math.cos(a)*5.5,.55,math.sin(a)*5.5)*CFrame.Angles(0,a,0),rgb(70,64,58),Enum.Material.Basalt)
 end
 local core=part(root,'MiningOreCore',Vector3.new(8.6,7,8.6),oreCF*CFrame.new(0,4.3,0),Color3.new(1,1,1),Enum.Material.SmoothPlastic,
  {Transparency=1,CanCollide=true,CanQuery=true,CastShadow=false})
 local oreRoot=Instance.new('Attachment');oreRoot.Name='OreRoot';oreRoot.Position=Vector3.new(0,-3.5+.8,0);oreRoot.Parent=core
 local stand=Instance.new('Attachment');stand.Name='MinerStand';stand.Parent=core
 local standPos=D(STAND.X,top+3,STAND.Z).Position
 stand.WorldCFrame=CFrame.lookAt(standPos,Vector3.new(oreCF.Position.X,standPos.Y,oreCF.Position.Z))
 -- Satellite outcrops: smaller piles of the same ore around the main one (drawn by the client,
 -- every circle may land on any of them). Attachment CFrame = pile ground centre; Scale = size.
 for i,o in ipairs(SATS)do
  local padCF=D(o.X,top,o.Z)
  part(root,'OreSatBase'..i,Vector3.new(.5,6.4*o.S+1.2,6.4*o.S+1.2),padCF*CFrame.new(0,.15,0)*CFrame.Angles(0,0,math.rad(90)),dark,Enum.Material.Basalt,{Shape=Enum.PartType.Cylinder,CanCollide=true})
  part(root,'OreSatRim'..i,Vector3.new(.3,6.4*o.S+2,6.4*o.S+2),padCF*CFrame.new(0,.05,0)*CFrame.Angles(0,0,math.rad(90)),trim,Enum.Material.Cobblestone,{Shape=Enum.PartType.Cylinder,CanCollide=true})
  local a=Instance.new('Attachment');a.Name='OreSat'..i;a:SetAttribute('Scale',o.S);a.Parent=core
  a.WorldCFrame=padCF*CFrame.new(0,.42,0)
 end
 prompt(core,'MiningOrePrompt','Mine','Ore pile',12)
 click(core,'MiningOreClick')

 -- QUARRY WALL at the back: a rock mound with a timber tunnel mouth, rails and a loaded mine cart.
 local wallZ=SITE.Z0+3.2
 local rocks={{-26.6,2.6,4.4,3.8,.3},{-23,3.4,5,4.8,-.2},{-14,3.6,5.2,5,.25},{-10.2,2.4,4,3.6,-.35},{-21.4,1.6,3,2.6,.5},{-15.6,1.5,3.2,2.4,-.4},{-28,1.2,2.6,2.2,.8},{-9,1.3,2.8,2.4,-.7}}
 for i,r in ipairs(rocks)do
  part(root,'QuarryRock'..i,Vector3.new(r[3],r[2]*2,r[4]),D(r[1],top+r[2]*.75,wallZ-1+(i%3)*.6)*CFrame.Angles(r[5]*.4,r[5],r[5]*.3),
   i%2==0 and rgb(104,94,84)or rgb(88,80,74),Enum.Material.Rock,{CanCollide=true})
 end
 local tunnel=D(MAIN.X,top,wallZ)
 for s=-1,1,2 do part(root,'TunnelPost',Vector3.new(.8,6.2,.8),tunnel*CFrame.new(s*2.6,3.1,.6),timber,Enum.Material.WoodPlanks,{CanCollide=true})end
 part(root,'TunnelLintel',Vector3.new(6.8,.9,1.1),tunnel*CFrame.new(0,6.5,.6),timber,Enum.Material.WoodPlanks,{CanCollide=true})
 part(root,'TunnelDark',Vector3.new(4.6,5.8,.3),tunnel*CFrame.new(0,2.95,-.4),rgb(12,10,10),Enum.Material.SmoothPlastic,{CanCollide=true,CastShadow=false})
 local mineSign=part(root,'TunnelSign',Vector3.new(4.6,1.3,.25),tunnel*CFrame.new(0,7.7,.95),timber,Enum.Material.WoodPlanks)
 signGui(mineSign,Enum.NormalId.Front,'ORE QUARRY','',rgb(255,196,80),nil,70).Name='TunnelFace'
 local tunnelLamp=part(root,'TunnelLamp',Vector3.new(.7,.9,.7),tunnel*CFrame.new(0,5.6,1.4),rgb(255,200,120),Enum.Material.Neon,{CastShadow=false})
 local tl=Instance.new('PointLight');tl.Range=14;tl.Brightness=1.2;tl.Color=rgb(255,190,120);tl.Shadows=false;tl.Parent=tunnelLamp
 for _,x in ipairs({-.8,.8})do part(root,'Rail',Vector3.new(.22,.2,7.5),tunnel*CFrame.new(x,.1,4),rgb(120,110,100),Enum.Material.Metal)end
 for i=0,5 do part(root,'Sleeper',Vector3.new(2.4,.16,.45),tunnel*CFrame.new(0,.03,1+i*1.25),rgb(86,58,36),Enum.Material.WoodPlanks)end
 local cartCF=tunnel*CFrame.new(0,0,5.6)
 part(root,'CartBody',Vector3.new(3,1.7,2.1),cartCF*CFrame.new(0,1.35,0)*CFrame.Angles(0,math.rad(90),0),rgb(96,70,48),Enum.Material.WoodPlanks,{CanCollide=true})
 part(root,'CartRim',Vector3.new(3.2,.28,2.3),cartCF*CFrame.new(0,2.25,0)*CFrame.Angles(0,math.rad(90),0),rgb(70,70,74),Enum.Material.Metal)
 for _,o in ipairs({{-1.1,-1},{1.1,-1},{-1.1,1},{1.1,1}})do
  part(root,'CartWheel',Vector3.new(.3,.95,.95),cartCF*CFrame.new(o[1],.5,o[2]),rgb(40,40,44),Enum.Material.Metal,{Shape=Enum.PartType.Cylinder})
 end
 for i=1,5 do
  part(root,'CartOre',Vector3.new(.95,.75,.85),cartCF*CFrame.new((i%2==0)and .4 or-.3,2.4+(i%2)*.2,-1.2+i*.42)*CFrame.Angles(i,i*.7,0),
   i==3 and rgb(255,200,70)or rgb(150,140,130),i==3 and Enum.Material.Foil or Enum.Material.Slate)
 end
 -- Crates and barrels in the back corners.
 for i,o in ipairs({{-27.2,wallZ+3.2,0},{-26.6,wallZ+4.6,.4},{-27,wallZ+3.9,1.1},{-9.4,wallZ+3.4,.2},{-10.6,wallZ+3.6,-.3}})do
  part(root,'Crate'..i,Vector3.new(1.3,1.1,1.3),D(o[1],top+.55+(i==3 and 1.1 or 0),o[2])*CFrame.Angles(0,o[3],0),rgb(150,110,70),Enum.Material.WoodPlanks,{CanCollide=i~=3})
 end
 for i,o in ipairs({{-9.2,wallZ+5.2},{-10.4,wallZ+5.6}})do
  cyl(root,'Barrel'..i,1.5,1.1,D(o[1],top+.75,o[2]),rgb(120,82,50),Enum.Material.WoodPlanks,{CanCollide=true})
  cyl(root,'BarrelHoop'..i,.12,1.18,D(o[1],top+1.1,o[2]),rgb(60,60,64),Enum.Material.Metal)
 end

 -- PICKAXE STALL by the entrance: a little market booth; pressing its sign opens the pickaxe market.
 local stallCF=D(-25.6,top,1.4)*FACE_WALK
 part(root,'StallFloor',Vector3.new(6.2,.25,4.2),stallCF*CFrame.new(0,.12,0),rgb(92,66,42),Enum.Material.WoodPlanks,{CanCollide=true})
 part(root,'StallCounter',Vector3.new(5.6,1.5,1.1),stallCF*CFrame.new(0,1,-1.2),rgb(120,84,52),Enum.Material.WoodPlanks,{CanCollide=true})
 part(root,'StallCounterTop',Vector3.new(6,.2,1.4),stallCF*CFrame.new(0,1.85,-1.2),rgb(70,48,30),Enum.Material.WoodPlanks)
 part(root,'StallBackWall',Vector3.new(5.8,4.6,.3),stallCF*CFrame.new(0,2.4,1.9),rgb(104,72,44),Enum.Material.WoodPlanks,{CanCollide=true})
 for s=-1,1,2 do
  part(root,'StallPost',Vector3.new(.35,5.2,.35),stallCF*CFrame.new(s*2.85,2.6,-1.8),rgb(84,58,36),Enum.Material.WoodPlanks,{CanCollide=true})
  part(root,'StallPost',Vector3.new(.35,5.2,.35),stallCF*CFrame.new(s*2.85,2.6,1.8),rgb(84,58,36),Enum.Material.WoodPlanks,{CanCollide=true})
 end
 -- striped awning (orange / cream), sloping to the front
 for i=0,6 do
  part(root,'Awning',Vector3.new(.85,.12,4.8),stallCF*CFrame.new(-2.55+i*.85,5.15,0)*CFrame.Angles(math.rad(-10),0,0),
   i%2==0 and rgb(242,146,38)or rgb(255,240,214),Enum.Material.Fabric)
 end
 part(root,'AwningTrim',Vector3.new(6.1,.4,.15),stallCF*CFrame.new(0,4.6,-2.45),rgb(242,146,38),Enum.Material.Fabric)
 -- the pickaxes on display (static copies of the first three designs)
 for i=1,3 do
  local def=M.Pickaxes[i]
  if def then
   local ok,model=pcall(Models.Pickaxe,def,i)
   if ok and model then
    model.Name='StallDisplay'..i
    for _,d in ipairs(model:GetDescendants())do if d:IsA('BasePart')then d.Anchored=true;d.CanCollide=false;d.CanQuery=false end end
    model:PivotTo(stallCF*CFrame.new(-1.8+(i-1)*1.8,2.9,1.55)*CFrame.Angles(0,math.pi,math.rad(-14+(i-2)*14))*CFrame.new(0,0,0))
    pcall(function()model:ScaleTo(.62*(tonumber(model:GetAttribute('DisplayScale'))or 1))end) -- DisplayScale: a big design (Butterfly Catcher) shows smaller
    model.Parent=root
   end
  end
 end
 local board=part(root,'MiningPickaxeShop',Vector3.new(5,2.6,.35),stallCF*CFrame.new(0,6.6,-1.9),timber,Enum.Material.WoodPlanks,{CanCollide=true,CanQuery=true})
 for s=-1,1,2 do part(root,'SignPost',Vector3.new(.3,1.4,.3),stallCF*CFrame.new(s*2,5.6,-1.9),rgb(84,58,36),Enum.Material.WoodPlanks)end
 signGui(board,Enum.NormalId.Front,'PICKAXES','Tap to open',rgb(120,220,255),function(bg)
  local icon=Models.PickaxeIcon(bg,150,rgb(190,200,212),rgb(156,104,56),2)
  icon.AnchorPoint=Vector2.new(.5,0);icon.Position=UDim2.fromScale(.5,.04);icon.Size=UDim2.fromScale(.56,.56)
  icon.SizeConstraint=Enum.SizeConstraint.RelativeYY
 end,48)
 local lamp=part(root,'SignLamp',Vector3.new(.6,.3,.6),stallCF*CFrame.new(0,8.05,-2.3),rgb(255,214,140),Enum.Material.Neon,{CastShadow=false})
 local light=Instance.new('SpotLight');light.Face=Enum.NormalId.Bottom;light.Range=10;light.Brightness=1.6;light.Angle=80;light.Color=rgb(255,214,160);light.Parent=lamp
 prompt(board,'MiningPickaxeShopPrompt','Open','Pickaxes',10)
 local counterPrompt=part(root,'StallCounterPrompt',Vector3.new(3,1,1),stallCF*CFrame.new(0,2,-2),Color3.new(1,1,1),Enum.Material.SmoothPlastic,{Transparency=1,CanCollide=false,CastShadow=false})
 prompt(counterPrompt,'MiningPickaxeShopPrompt','Open','Pickaxes',9)
 click(board,'MiningPickaxeShopClick')

 -- ENTRANCE ARCH on the walkway side.
 local arch=D(SITE.X1-.45,top,-1)*FACE_WALK
 for s=-1,1,2 do
  part(root,'ArchPost',Vector3.new(.7,7,.7),arch*CFrame.new(s*3.6,3.5,0),timber,Enum.Material.WoodPlanks,{CanCollide=true})
  part(root,'ArchFoot',Vector3.new(1.3,.6,1.3),arch*CFrame.new(s*3.6,.3,0),trim,Enum.Material.Slate,{CanCollide=true})
 end
 local header=part(root,'ArchHeader',Vector3.new(8.6,1.6,.4),arch*CFrame.new(0,6.9,0),timber,Enum.Material.WoodPlanks)
 local hg=signGui(header,Enum.NormalId.Front,'ORE QUARRY','',rgb(255,196,80),function(bg)
  local pick=Instance.new('TextLabel');pick.Name='Icon';pick.BackgroundTransparency=1;pick.Size=UDim2.fromScale(.16,.9);pick.Position=UDim2.fromScale(.02,.05)
  pick.Text='⛏';pick.TextScaled=true;pick.Font=Enum.Font.FredokaOne;pick.Parent=bg
 end,60)
 hg.Name='ArchFace'
 local title=hg:FindFirstChildWhichIsA('Frame')and hg:FindFirstChildWhichIsA('Frame'):FindFirstChild('Title')
 if title then title.Size=UDim2.fromScale(.78,.8);title.Position=UDim2.fromScale(.2,.1)end
 local back=header:Clone();back.Name='ArchHeaderBack';back.CFrame=header.CFrame*CFrame.new(0,0,.05)*CFrame.Angles(0,math.pi,0);back.Parent=root
 for _,s in ipairs({-1,1})do
  local bulb=part(root,'ArchLamp',Vector3.new(.6,.6,.6),arch*CFrame.new(s*3.6,7.4,0),rgb(255,206,130),Enum.Material.Neon,{CastShadow=false,Shape=Enum.PartType.Ball})
  local pl=Instance.new('PointLight');pl.Range=12;pl.Brightness=.9;pl.Color=rgb(255,196,130);pl.Shadows=false;pl.Parent=bulb
 end

 -- Floodlights on poles light the bigger site at night.
 for i,o in ipairs({{SITE.X0+.9,SITE.Z0+.9},{SITE.X1-.9,SITE.Z0+.9},{SITE.X0+.9,-6},{SITE.X1-.9,-8.5}})do
  local lp=D(o[1],top,o[2])
  part(root,'SiteLampPost'..i,Vector3.new(.35,7.4,.35),lp*CFrame.new(0,3.7,0),rgb(40,36,34),Enum.Material.Metal,{CanCollide=true})
  local head=part(root,'SiteLamp'..i,Vector3.new(1.2,.5,.8),lp*CFrame.new(0,7.5,0),rgb(255,214,150),Enum.Material.Neon,{CastShadow=false})
  local spot=Instance.new('SpotLight');spot.Face=Enum.NormalId.Bottom;spot.Range=22;spot.Angle=85;spot.Brightness=1.1;spot.Color=rgb(255,206,150);spot.Shadows=false;spot.Parent=head
 end
 root:SetAttribute('OwnerUserId',0)
 root.Parent=yard
 return root
end

-- STATE MIRROR -----------------------------------------------------------------------------------
local DEFAULTS={OreId=M.Ores[1].Id,OreHP=M.Ores[1].HP,OreMaxHP=M.Ores[1].HP,OreSerial=0,HitSerial=0,HitQuality=1,HitCrit=false,
 HitPayout=0,HitDamage=0,Combo=0,BreakSerial=0,BrokenId='',BrokenValue=0,PickaxeLevel=0,Strength=0,Active=false}
local MAP={OreId='MiningOreId',OreHP='MiningOreHP',OreMaxHP='MiningOreMaxHP',OreSerial='MiningOreSerial',HitQuality='MiningLastQuality',
 HitCrit='MiningLastCrit',HitPayout='MiningLastPayout',HitDamage='MiningLastDamage',Combo='MiningCombo',BrokenId='MiningBrokenId',
 BrokenValue='MiningBrokenValue',PickaxeLevel='MiningPickaxe',Strength='MiningStrength',BreakSerial='MiningOresBroken',HitSerial='MiningHitSerial'}
-- Detail attributes first; serials last (BreakSerial before OreSerial) so a client reacting to a
-- serial reads fresh details.
local ORDER={'OreId','OreHP','OreMaxHP','HitQuality','HitCrit','HitPayout','HitDamage','Combo','BrokenId','BrokenValue','PickaxeLevel',
 'Strength','BreakSerial','OreSerial','HitSerial'}

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
 root:SetAttribute('OwnerUserId',player.UserId)
 root:SetAttribute('Revision',player:GetAttribute('MiningRevision')or 0)
end
local function setPrompts(root,enabled)
 for _,d in ipairs(root:GetDescendants())do if d:IsA('ProximityPrompt')then d.Enabled=enabled end end
end

-- THE PICKAXE TOOL ---------------------------------------------------------------------------
-- Every player who owns a pickaxe has it as a Tool (Backpack / hotbar). The Tool is only the hotbar
-- entry: an invisible stand-in Handle (so the default Animate plays the hold-a-tool arm pose) and
-- no visible parts. The pickaxe you see is one model, "MiningHeldPickaxe", welded by this script
-- straight to the character with fixed offsets (Models.Mount): in the right hand while the Tool is
-- equipped or a mining session is running, on the back otherwise. Equipping only retargets its one
-- HandGrip weld. Twin Claws are gloves: both hands while in the hand ("MiningHeldPickaxeL" is the
-- left one), nothing on the back. A model that has to come off (unequipped claws, a worn Back
-- accessory) is kept off the character and put back on the next equip, never rebuilt per toggle.
local TOOL_ICON='rbxassetid://105611091036304' -- the game's DIG icon
local function clearHeld(character,name)
 local old=character and character:FindFirstChild(name);if old then old:Destroy()end
end
-- Limbs whose replacement (avatar loading, ApplyDescription) needs the mount rewritten.
local LIMBS={RightHand=true,LeftHand=true,UpperTorso=true,['Right Arm']=true,['Left Arm']=true,Torso=true}
local forceMount=setmetatable({},{__mode='k'}) -- player -> rewrite the joints on the next sync
local mountedAt={} -- held model -> os.clock() when it was parented (dropped when it leaves the game)

local function russian(player)
 local ok,locale=pcall(function()return player.LocaleId end)
 return ok and type(locale)=='string'and string.lower(string.sub(locale,1,2))=='ru'
end
local function findTool(player)
 local character=player.Character
 for _,holder in ipairs({character,player:FindFirstChildOfClass('Backpack')})do
  if holder then
   for _,c in ipairs(holder:GetChildren())do
    if c:IsA('Tool')and c:GetAttribute('MiningPickaxeTool')then return c end
   end
  end
 end
 return nil
end
local syncHeld -- forward
-- One sync per player per frame, whoever asks (attributes, the Tool moving, the avatar, the 1 s loop):
-- equip / unequip spam (hotbar mashing, an exploit calling EquipTool every frame) is coalesced here.
local pendingSync=setmetatable({},{__mode='k'})
local function requestSync(player)
 if pendingSync[player]then return end
 pendingSync[player]=true
 task.defer(function()pendingSync[player]=nil;if player.Parent and syncHeld then syncHeld(player)end end)
end
-- Name, tooltip and attributes of the hotbar entry (renamed in place on a level or language change).
local function dressTool(tool,player,def,level)
 tool.Name=russian(player)and(def.RU or def.Name)or def.Name
 tool.ToolTip=(def.Icon and(def.Icon..' ')or'')..tool.Name
 tool:SetAttribute('Level',level);tool:SetAttribute('Theme',def.Theme or'Wood')
 tool:SetAttribute('Kind',(def.Visual or{}).Kind or'Classic');tool:SetAttribute('Swing',def.Swing or'Chop')
 tool:SetAttribute('Skin',def.SkinId) -- Halloween skin shown on the hotbar entry (nil = none)
end
local function buildTool(player,def,level)
 local tool=Instance.new('Tool')
 tool.TextureId=TOOL_ICON;tool.CanBeDropped=false;tool.RequiresHandle=true;tool.Grip=CFrame.identity
 tool:SetAttribute('MiningPickaxeTool',true);dressTool(tool,player,def,level)
 -- Invisible stand-in: the default Animate plays the hold-a-tool arm pose only for a Tool with a
 -- Handle. The pickaxe you see is the welded MiningHeldPickaxe, never this Tool's physics.
 local h=Instance.new('Part');h.Name='Handle';h.Size=Vector3.new(.2,.2,.2);h.Transparency=1;h.Anchored=false
 h.CanCollide=false;h.CanQuery=false;h.CanTouch=false;h.Massless=true;h.CastShadow=false;h.Parent=tool
 tool.AncestryChanged:Connect(function()requestSync(player)end)
 return tool
end
-- A held model whose HandGrip lost its limb (the avatar replaced it) or that no longer moves with
-- that limb (its joint broke) is rebuilt. A limb that is itself cut off is not this script's business.
local function healthy(character,model)
 local handle=model.PrimaryPart or model:FindFirstChild('Handle')
 local grip=handle and handle:FindFirstChild('HandGrip')
 if not(handle and grip and grip:IsA('Weld')and grip.Part1==handle and grip.Part0 and grip.Part0.Parent==character)then return false end
 if os.clock()-(mountedAt[model]or 0)>2 then
  local limb=grip.Part0
  local ok,apart=pcall(function()return handle.AssemblyRootPart~=limb.AssemblyRootPart end)
  if ok and apart then return false end
 end
 return true
end
-- A model that comes off the character (no mount: unequipped Twin Claws, a worn Back accessory) is
-- kept here, out of the world, and put back on the next equip instead of building a new one (18-95
-- parts with emitters and lights each time). A model goes on or comes off at most once per SWAP_GAP
-- per player and name; a toggle inside the gap is applied when it ends (equip spam).
local SWAP_GAP=.25
local spares={} -- player -> {Character=, Models={name -> model}} (server only, parented to nil)
local swappedAt={} -- player -> {name -> os.clock() of the last time it went on or came off}
local retrying={} -- player -> true while a delayed sync is scheduled
local function spareBox(player,character)
 local box=spares[player]
 if box and box.Character~=character then -- welded to an old character: of no use any more
  for _,m in pairs(box.Models)do m:Destroy()end
  box=nil
 end
 if not box then box={Character=character,Models={}};spares[player]=box end
 return box
end
local function dropSpares(player)
 local box=spares[player];spares[player]=nil
 if box then for _,m in pairs(box.Models)do m:Destroy()end end
end
local function retryLater(player,delay)
 if retrying[player]then return end
 retrying[player]=true
 task.delay(delay,function()retrying[player]=nil;requestSync(player)end)
end
-- Keeps exactly one welded model `name` on the character at `mount` (nil: none).
local function keep(player,character,name,level,mount,factory,force)
 local box=spareBox(player,character)
 local cur=character:FindFirstChild(name)
 if cur and(not cur:IsA('Model')or cur:GetAttribute('Level')~=level or not healthy(character,cur))then cur:Destroy();cur=nil end
 local spare=box.Models[name]
 if spare and(cur or spare.Parent~=nil or spare:GetAttribute('Level')~=level)then spare:Destroy();box.Models[name]=nil;spare=nil end
 -- On and staying on (equip / unequip of an ordinary pickaxe, a session): only the joint moves.
 if cur and mount then Models.Mount(character,cur,mount,force);return end
 if not cur and not mount then return end
 -- It goes on or comes off.
 local stamps=swappedAt[player];if not stamps then stamps={};swappedAt[player]=stamps end
 local wait=(stamps[name]or-math.huge)+SWAP_GAP-os.clock()
 if wait>0 then retryLater(player,wait+.02);return end
 stamps[name]=os.clock()
 if cur then cur.Parent=nil;box.Models[name]=cur;return end -- off: kept for the next equip
 local model=spare;box.Models[name]=nil
 if not model then
  model=factory();if not model then return end
  model.Name=name;model:SetAttribute('Level',level)
  model.AncestryChanged:Connect(function()if not model:IsDescendantOf(game)then mountedAt[model]=nil end end)
 end
 -- Welded and placed at the limb BEFORE it enters the world: it never appears at the map origin
 -- (a kept model is moved there from wherever it came off; force: the limb may have changed since).
 if not Models.Mount(character,model,mount,spare~=nil)then model:Destroy();return end
 mountedAt[model]=os.clock()
 model.Parent=character
end
syncHeld=function(player)
 local character=player.Character;if not character or not character.Parent then return end
 local hum=character:FindFirstChildOfClass('Humanoid')
 if hum and hum.Health<=0 then return end -- the joints break on death; the next character gets a new one
 local backpack=player:FindFirstChildOfClass('Backpack')
 local level=player:GetAttribute('MiningPickaxe')or 0
 local def=M.Pickaxes[level]
 local tool=findTool(player)
 if not def then
  if tool then tool:Destroy()end
  clearHeld(character,'MiningHeldPickaxe');clearHeld(character,'MiningHeldPickaxeL')
  dropSpares(player)
  return
 end
 local skin=Skins.Of(player);local vdef=Skins.Resolve(def,skin);local key=skin and(level..'|'..skin)or level -- Halloween skin: visual def + held-model key
 -- A new level only renames the Tool (it stays in the hand); the visible model is rebuilt below.
 if tool then
  if tool:GetAttribute('Level')~=level or tool:GetAttribute('Skin')~=skin then dressTool(tool,player,vdef,level)end
 elseif backpack then
  tool=buildTool(player,vdef,level);tool.Parent=backpack
 end
 -- In the hand while the Tool is equipped or a mining session runs (also when the equip failed);
 -- otherwise on the back, unless a worn Back accessory takes the back. Claws are never on the back.
 local inHand=(tool~=nil and tool.Parent==character)or(player:GetAttribute('MiningActiveUntil')or 0)>=os.time()
 local glove=(vdef.Visual or{}).Grip=='Glove'
 local mount=nil
 if inHand then mount=glove and'Glove'or'Hand'
 elseif not glove and not character:FindFirstChild('DOGROTS_Accessory_Back')then mount='Back'end
 local force=forceMount[player];forceMount[player]=nil
 keep(player,character,'MiningHeldPickaxe',key,mount,function()return Models.Pickaxe(vdef,level)end,force)
 keep(player,character,'MiningHeldPickaxeL',key,(glove and inHand)and'GloveL'or nil,function()return Models.PickaxeOffhand(vdef,level)end,force)
end

local function watchPlayer(player)
 local function queue()requestSync(player)end
 -- New limbs or a new avatar scale: rewrite the joints even if the limb names did not change.
 local function remount()forceMount[player]=true;queue()end
 player:GetAttributeChangedSignal('MiningPickaxe'):Connect(queue)
 player:GetAttributeChangedSignal('PickaxeSkin'):Connect(queue) -- Halloween skin equipped / removed: rebuild the held model
 player:GetAttributeChangedSignal('MiningRevision'):Connect(queue)
 player:GetAttributeChangedSignal('MiningActiveUntil'):Connect(queue)
 -- A language change only renames the Tool (no rebuild, no re-equip).
 player:GetPropertyChangedSignal('LocaleId'):Connect(function()
  local level=player:GetAttribute('MiningPickaxe')or 0
  local tool=findTool(player);local def=M.Pickaxes[level]
  if tool and def then dressTool(tool,player,Skins.Resolve(def,Skins.Of(player)),level)end
 end)
 player.CharacterAppearanceLoaded:Connect(remount)
 player.CharacterAdded:Connect(function(character)
  character.ChildAdded:Connect(function(c)
   if c.Name=='DOGROTS_Accessory_Back'then queue()
   elseif LIMBS[c.Name]and c:IsA('BasePart')then remount()end
  end)
  character.ChildRemoved:Connect(function(c)if c.Name=='DOGROTS_Accessory_Back'then queue()end end)
  task.wait(.5);queue()
 end)
 if player.Character then queue()end
end
for _,p in ipairs(Players:GetPlayers())do task.spawn(watchPlayer,p)end
Players.PlayerAdded:Connect(watchPlayer)

-- BINDING ----------------------------------------------------------------------------------------
local function unbind(yard)
 local b=bindings[yard];bindings[yard]=nil
 local root=yard:FindFirstChild('MiningCorner')
 if b then
  for _,c in ipairs(b.Connections)do c:Disconnect()end
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
  apply(root,player)
 end
 table.insert(b.Connections,player:GetAttributeChangedSignal('MiningRevision'):Connect(function()
  if not queued then queued=true;task.defer(refresh)end
 end))
 -- The owner always has their own quarry streamed in (tutorial markers, mining from afar).
 local okPersist,errPersist=pcall(function()root:AddPersistentPlayer(player)end)
 if not okPersist then warn('DOGROTS mining: AddPersistentPlayer failed for '..yard.Name..': '..tostring(errPersist))end
 apply(root,player);setPrompts(root,true);syncHeld(player)
end

-- Flat ground decoration of yard skins (the Earthquake crack) that runs under the pad would poke
-- through the slab; it is hidden where the pad covers it. PlotAppearance rebuilds
-- yard.PlotDevelopment on every level/skin change, so new pieces are checked as they appear.
local function coverGround(yard,d)
 if not d:IsA('BasePart')or d.Transparency>=1 then return end
 local corner=yard:FindFirstChild('MiningCorner');local pad=corner and corner:FindFirstChild('MiningPad')
 if not(pad and pad:IsA('BasePart'))then return end
 local cf,size=d.CFrame,d.Size
 local up=math.abs(cf.UpVector.Y)*size.Y/2+math.abs(cf.RightVector.Y)*size.X/2+math.abs(cf.LookVector.Y)*size.Z/2
 local padTop=pad.CFrame.Position.Y+pad.Size.Y/2
 if cf.Position.Y+up>padTop+.6 or up*2>1.4 then return end -- only flat pieces near the ground
 -- Hidden when its centre or a quarter point is under the slab (a piece that only grazes the
 -- border with its end stays visible).
 local hx,hz=pad.Size.X/2,pad.Size.Z/2
 for i=-1,1 do for j=-1,1 do
  local p=pad.CFrame:PointToObjectSpace(cf:PointToWorldSpace(Vector3.new(size.X*i/4,0,size.Z*j/4)))
  if math.abs(p.X)<=hx and math.abs(p.Z)<=hz then
   d.Transparency=1;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d:SetAttribute('CoveredByMiningCorner',true)
   return
  end
 end end
end
local function watchGround(yard)
 local function watch(dev)
  for _,d in ipairs(dev:GetDescendants())do coverGround(yard,d)end
  dev.DescendantAdded:Connect(function(d)task.defer(coverGround,yard,d)end)
 end
 local dev=yard:FindFirstChild('PlotDevelopment');if dev then watch(dev)end
 yard.ChildAdded:Connect(function(child)if child.Name=='PlotDevelopment'then task.defer(watch,child)end end)
end

local function track(yard)
 if not yard:GetAttribute('YardId')then return end
 local corner=build(yard);apply(corner,nil);setPrompts(corner,false)
 watchGround(yard)
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
 dropSpares(player);swappedAt[player]=nil;forceMount[player]=nil
end)
-- Sessions expire on the server clock (os.time) without any request: re-check the Active flag
-- and every player's pickaxe tool once a second (this also repairs a held pickaxe whose joint
-- lost its limb, see healthy()).
task.spawn(function()
 while true do
  task.wait(1)
  for yard,b in pairs(bindings)do
   local root=yard:FindFirstChild('MiningCorner')
   if root then
    local active=(b.Player:GetAttribute('MiningActiveUntil')or 0)>=os.time()
    if root:GetAttribute('Active')~=active then root:SetAttribute('Active',active)end
   end
  end
  for _,p in ipairs(Players:GetPlayers())do pcall(syncHeld,p)end
 end
end)
