-- Static Lucky Block models, one look per tier. Built on the server (conveyor, pads) and on the
-- client for ViewportFrame art, so the look is carried by silhouette, material and colour only:
-- viewports render no lights, particles or bloom. Motion and glow live in the client aura
-- (StarterPlayerScripts/LuckyBlockFX), never here: every part is anchored and static so the
-- conveyor can weld the whole block to RootPart (no LuckyFloat parts any more).
-- Contract: PrimaryPart 'RootPart' (5.45 body cube, faces ~±2.8 before ScaleTo(.8)),
-- 4 'InsetPanel' + 1 'Lid', attributes LuckyVisual/LuckyRank/GroundLocal (pivot -> bottom),
-- Attachments 'LuckyCore' (centre) and 'DogLabelAnchor' (1.5 studs above the top after scaling).
local C=require(script.Parent.LuckyBlockConfig)
local V={}

local SCALE=.8
local H=2.725 -- half of the 5.45 body
local FOOT=-3.1 -- bottom of every tier (pads seat blocks at 3*scale+.1 above the pad)
local rgb=Color3.fromRGB
local M=Enum.Material

-- Per-tier style. Colours are tuned for the bright candy look of the island.
local Styles={
 { -- Common: sturdy wooden crate, steel straps and corner brackets, stencilled '?'
  Body=rgb(150,96,52),BodyMat=M.WoodPlanks,
  Panel=rgb(214,156,92),PanelMat=M.WoodPlanks,
  Edge=rgb(110,66,34),EdgeMat=M.Wood,EdgeThick=.66,
  Corner=rgb(178,188,198),CornerMat=M.DiamondPlate,Cap=1.4,
  Glyph=rgb(255,246,222),GlyphMat=M.SmoothPlastic,Outline=rgb(70,40,20),
  Straps=rgb(150,160,170),StrapMat=M.Metal,Rivet=rgb(222,230,238),
  Lid=rgb(190,132,76),LidMat=M.WoodPlanks,
  Foot=rgb(120,130,140),FootMat=M.Metal,
 },
 { -- Rare: sleek blue tech crate, glowing cyan seams, white bumpers, ringed badge
  Body=rgb(18,52,104),BodyMat=M.SmoothPlastic,
  Panel=rgb(30,98,196),PanelMat=M.SmoothPlastic,
  Edge=rgb(232,240,252),EdgeMat=M.SmoothPlastic,EdgeThick=.54,
  Corner=rgb(255,255,255),CornerMat=M.SmoothPlastic,Ball=1.5,
  Glyph=rgb(150,250,255),GlyphMat=M.Neon,
  Badge=rgb(12,30,70),BadgeMat=M.SmoothPlastic,Rim=rgb(40,230,255),RimMat=M.Neon,
  Seam=rgb(40,226,255),
  Lid=rgb(36,110,214),LidMat=M.SmoothPlastic,
  Seal=rgb(90,240,255),SealMat=M.Neon,
  Foot=rgb(200,214,232),FootMat=M.SmoothPlastic,
 },
 { -- Epic: purple arcane box, rune circles, neon crystal corners and a crystal cluster on top
  Body=rgb(58,22,98),BodyMat=M.Slate,
  Panel=rgb(110,48,178),PanelMat=M.Slate,
  Edge=rgb(42,16,74),EdgeMat=M.Slate,EdgeThick=.62,
  Corner=rgb(255,120,246),CornerMat=M.Neon,Crystal=1.15,Cap=1.3,CapColor=rgb(42,16,74),
  Glyph=rgb(255,176,255),GlyphMat=M.Neon,
  Badge=rgb(30,10,56),BadgeMat=M.Slate,Rim=rgb(214,92,255),RimMat=M.Neon,
  Runes=rgb(255,140,250),
  Lid=rgb(84,34,140),LidMat=M.Slate,
  Foot=rgb(42,16,74),FootMat=M.Slate,
  Cluster=rgb(255,150,250),
 },
 { -- Legendary: ornate gold-and-ivory treasure chest with gem studs and a domed lid
  Body=rgb(246,234,206),BodyMat=M.Marble,
  Panel=rgb(255,246,226),PanelMat=M.Marble,
  Edge=rgb(255,186,36),EdgeMat=M.Metal,EdgeThick=.7,
  Corner=rgb(255,214,84),CornerMat=M.Metal,Ball=1.4,
  Glyph=rgb(255,214,64),GlyphMat=M.Neon,
  Badge=rgb(36,62,160),BadgeMat=M.SmoothPlastic,Rim=rgb(255,190,40),RimMat=M.Metal,
  Gems={rgb(255,50,90),rgb(40,200,255),rgb(70,230,110),rgb(190,90,255)},
  Lid=rgb(255,246,226),LidMat=M.Marble,Dome=true,
  Foot=rgb(255,186,36),FootMat=M.Metal,
 },
 { -- Mythic: crimson-and-gold royal crate, rainbow gem arcs, a jewelled crown with orb
  Body=rgb(150,14,46),BodyMat=M.Fabric,
  Panel=rgb(200,26,64),PanelMat=M.Fabric,
  Edge=rgb(255,190,40),EdgeMat=M.Metal,EdgeThick=.7,
  Corner=rgb(255,226,120),CornerMat=M.Metal,Cap=1.35,
  Glyph=rgb(255,226,96),GlyphMat=M.Neon,
  Badge=rgb(70,6,26),BadgeMat=M.Fabric,Rim=rgb(255,196,48),RimMat=M.Metal,
  Rainbow=true,
  Lid=rgb(255,190,40),LidMat=M.Metal,Crown=true,
  Foot=rgb(255,190,40),FootMat=M.Metal,
 },
 { -- Secret: cosmic singularity. Obsidian glass, violet/cyan seams, starfield panels, a
   -- black-hole badge on every face, a black hole on top and an event-horizon ring.
  Body=rgb(8,4,18),BodyMat=M.Glass,
  Panel=rgb(40,16,92),PanelMat=M.Glass,
  Edge=rgb(14,8,30),EdgeMat=M.Glass,EdgeThick=.5,
  Corner=rgb(110,255,240),CornerMat=M.Neon,Crystal=1.45,Cap=1.3,CapColor=rgb(110,255,240),
  Glyph=rgb(240,222,255),GlyphMat=M.Neon,
  Badge=rgb(0,0,0),BadgeMat=M.SmoothPlastic,Rim=rgb(176,86,255),RimMat=M.Neon,
  Seam=rgb(150,70,255),Seam2=rgb(60,240,255),
  Stars=true,
  Lid=rgb(22,10,52),LidMat=M.Glass,
  Foot=rgb(14,8,30),FootMat=M.Glass,
  Horizon=true,
 },
}
V.Styles=Styles

-- Pixel '?' in viewer space (x to the viewer's right, y up) in units of u: {x,y,w,h}.
-- Top bar, left nub, right hook, middle bar, stem, dot.
local GLYPH={{0,3,3,1},{-2,2,1,1},{2,1.5,1,2},{.5,0,2,1},{0,-1,1,1},{0,-3,1,1}}

function V.Build(tier)
 local rank=C.Rank(tier)or 1
 local s=Styles[rank]or Styles[1]
 local m=Instance.new('Model');m.Name=tostring(tier)..'LuckyBlock'
 m:SetAttribute('LuckyVisual',true);m:SetAttribute('LuckyRank',rank)
 local bottom,top=0,0
 local function part(name,cf,size,col,mat,shape)
  local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=col;p.Material=mat or M.SmoothPlastic
  if shape then p.Shape=shape end
  p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
  p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
  -- Vertical extent (the model is authored around the origin) for GroundLocal and the label.
  local ey=math.abs(cf.RightVector.Y)*size.X/2+math.abs(cf.UpVector.Y)*size.Y/2+math.abs(cf.LookVector.Y)*size.Z/2
  bottom=math.min(bottom,cf.Y-ey);top=math.max(top,cf.Y+ey)
  p.Parent=m;return p
 end
 local function box(name,x,y,z,w,h,d,col,mat)return part(name,CFrame.new(x,y,z),Vector3.new(w,h,d),col,mat)end
 local function ball(name,pos,d,col,mat)return part(name,CFrame.new(pos),Vector3.new(d,d,d),col,mat,Enum.PartType.Ball)end
 -- Disc facing along cf's look vector (a cylinder's axis is X, so turn it onto Z).
 local function disc(name,cf,d,thick,col,mat)return part(name,cf*CFrame.Angles(0,math.pi/2,0),Vector3.new(thick,d,d),col,mat,Enum.PartType.Cylinder)end
 -- Flat disc lying in the XZ plane at height y.
 local function plate(name,y,d,thick,col,mat)return part(name,CFrame.new(0,y,0)*CFrame.Angles(0,0,math.pi/2),Vector3.new(thick,d,d),col,mat,Enum.PartType.Cylinder)end
 -- Ring of n flat neon segments of radius r in cf's XZ plane.
 local function ring(name,cf,n,r,width,thick,colorAt)
  for k=0,n-1 do
   local a=(k+.5)/n*math.pi*2
   part(name,cf*CFrame.Angles(0,-a,0)*CFrame.new(r,0,0),Vector3.new(width,thick,2*math.pi*r/n+.05),colorAt(a),M.Neon)
  end
 end

 local root=box('RootPart',0,0,0,H*2,H*2,H*2,s.Body,s.BodyMat);m.PrimaryPart=root

 -- Frame: 12 edge beams (outer surface at ~2.97) and 8 corner pieces.
 local e=s.EdgeThick;local c=H-e/2+.24
 for _,a in {-1,1}do for _,b in {-1,1}do
  box('FrameEdge',0,a*c,b*c,c*2,e,e,s.Edge,s.EdgeMat)
  box('FrameEdge',a*c,0,b*c,e,c*2,e,s.Edge,s.EdgeMat)
  box('FrameEdge',a*c,b*c,0,e,e,c*2,s.Edge,s.EdgeMat)
 end end
 for _,x in {-1,1}do for _,y in {-1,1}do for _,z in {-1,1}do
  local pos=Vector3.new(x,y,z)*c
  if s.Ball then ball('CornerCap',pos,e*s.Ball,s.Corner,s.CornerMat)
  elseif s.Crystal and y>0 then
   -- Gem-cut cube standing on its point.
   part('CornerCrystal',CFrame.new(pos)*CFrame.Angles(math.rad(45),0,0)*CFrame.Angles(0,0,math.rad(35.26)),Vector3.one*e*s.Crystal,s.Corner,s.CornerMat)
  else box('CornerCap',pos.X,pos.Y,pos.Z,e*s.Cap,e*s.Cap,e*s.Cap,s.CapColor or s.Corner,s.CapColor and M.Neon or s.CornerMat)end
 end end end

 -- Faces. face*(x,y,-z) sits on the outward side; the viewer's right on each face is local -X.
 local u=.44
 for i=0,3 do
  local face=CFrame.Angles(0,i*math.pi/2,0)
  local function at(x,y,z)return face*CFrame.new(-x,y,z)end
  part('InsetPanel',at(0,0,-2.74),Vector3.new(4.36,4.36,.2),s.Panel,s.PanelMat)
  if s.Badge then
   disc('BadgeRim',at(0,0,-2.87),4.12,.06,s.Rim,s.RimMat)
   disc('Badge',at(0,0,-2.9),3.78,.06,s.Badge,s.BadgeMat)
  end
  for _,g in GLYPH do
   part('QuestionMark',at(g[1]*u,g[2]*u,-2.98),Vector3.new(g[3]*u,g[4]*u,.14),s.Glyph,s.GlyphMat)
   if s.Outline then
    part('QuestionOutline',at(g[1]*u,g[2]*u,-2.9),Vector3.new(g[3]*u+.22,g[4]*u+.22,.1),s.Outline,M.SmoothPlastic)
   end
  end
  if s.Runes then
   for k=0,3 do
    local a=k*math.pi/2+math.pi/4
    part('RuneMark',at(math.cos(a)*1.98,math.sin(a)*1.98,-2.9)*CFrame.Angles(0,0,a),Vector3.new(.52,.16,.08),s.Runes,M.Neon)
   end
  end
  if s.Gems then
   for k,col in s.Gems do
    local x=(k==1 or k==4)and -1.72 or 1.72;local y=k<=2 and 1.72 or -1.72
    ball('GemStud',at(x,y,-2.86).Position,.5,col,M.Glass)
   end
  end
  if s.Rainbow then
   for k=0,4 do
    local a=math.rad(150-k*30)
    ball('RainbowGem',at(math.cos(a)*2.02,math.sin(a)*2.02+.02,-2.92).Position,.42,Color3.fromHSV(k/5*.8,.75,1),M.Neon)
   end
  end
  if s.Stars then
   for k,st in {{-1.84,1.8,.22},{1.62,-1.86,.18},{1.88,1.15,.13}}do
    part('StarStud',at(st[1],st[2],-2.86)*CFrame.Angles(0,0,math.rad(45)),Vector3.new(st[3],st[3],.06),k==2 and s.Seam2 or rgb(255,255,255),M.Neon)
   end
  end
 end

 -- Straps and seams: one slab per line through the body pokes out around the sides.
 if s.Straps then
  for _,x in {-1.72,1.72}do
   box('SteelStrap',x,0,0,.36,5.86,5.86,s.Straps,s.StrapMat)
   box('SteelStrap',0,0,x,5.86,5.86,.36,s.Straps,s.StrapMat)
  end
  for i=0,3 do
   local face=CFrame.Angles(0,i*math.pi/2,0)
   for _,x in {-1.72,1.72}do for _,y in {-1.75,1.75}do
    part('Rivet',face*CFrame.new(x,y,-2.95),Vector3.new(.18,.18,.1),s.Rivet,M.Metal)
   end end
  end
 end
 if s.Seam then
  local s2=s.Seam2 or s.Seam
  for _,y in {-2.28,2.28}do box('LuminousSeam',0,y,0,5.76,.1,5.76,s.Seam,M.Neon)end
  for _,a in {-2.28,2.28}do
   box('LuminousSeam',a,0,0,.1,4.46,5.76,s2,M.Neon)
   box('LuminousSeam',0,0,a,5.76,4.46,.1,s2,M.Neon)
  end
 end

 -- Top.
 if s.Dome then
  -- Treasure chest: barrel lid with gold straps and royal gems.
  part('Lid',CFrame.new(0,1.75,0),Vector3.new(5.3,4.6,4.6),s.Lid,s.LidMat,Enum.PartType.Cylinder)
  for _,x in {-1.55,1.55}do part('DomeBand',CFrame.new(x,1.75,0),Vector3.new(.44,4.84,4.84),s.Edge,s.EdgeMat,Enum.PartType.Cylinder)end
  part('DomeBand',CFrame.new(0,1.75,0),Vector3.new(.3,4.76,4.76),s.Edge,s.EdgeMat,Enum.PartType.Cylinder)
  ball('TopGem',Vector3.new(0,4.12,0),.7,rgb(255,40,80),M.Glass)
  for _,z in {-1,1}do ball('TopGem',Vector3.new(0,3.86,z),.42,rgb(40,200,255),M.Glass)end
 else
  box('Lid',0,2.76,0,4.36,.2,4.36,s.Lid,s.LidMat)
 end
 if s.Seal then
  for _,p in {{0,.65,1.4,1.1},{-.95,-.3,.62,.72},{-.34,-.8,.6,.65},{.34,-.8,.6,.65},{.95,-.3,.62,.72}}do
   box('PawSeal',p[1],2.9,p[2],p[3],.12,p[4],s.Seal,s.SealMat)
  end
 end
 if s.Cluster then
  -- Crystal cluster: a rune plate with three gem-cut crystals.
  plate('RunePlate',2.9,2.6,.1,s.Corner,M.Neon)
  plate('RunePlate',2.94,2.3,.1,s.Badge,s.BadgeMat)
  -- Each crystal is a diamond-section shaft with a point (a cube standing on its corner).
  for k,cr in {{0,0,.82,1.5,0},{.66,.3,.5,.85,-24},{-.58,-.42,.46,.7,26}}do
   local base=CFrame.new(cr[1],2.95,cr[2])*CFrame.Angles(math.rad(cr[5]*.6),0,math.rad(cr[5]))
   local col=k==1 and s.Cluster or rgb(255,214,255)
   part('TopCrystal',base*CFrame.new(0,cr[4]/2,0)*CFrame.Angles(0,math.rad(45),0),Vector3.new(cr[3],cr[4],cr[3]),col,M.Neon)
   part('TopCrystal',base*CFrame.new(0,cr[4],0)*CFrame.Angles(0,math.rad(45),0)*CFrame.Angles(math.rad(45),0,0)*CFrame.Angles(0,0,math.rad(35.26)),Vector3.one*cr[3]*.82,col,M.Neon)
  end
 end
 if s.Crown then
  -- Velvet cushion, gold band of 8 plates, 8 tines with rainbow jewels, orb and cross.
  plate('CrownCushion',3.05,3.5,.62,rgb(176,20,58),M.Fabric)
  local r=1.86
  for k=0,7 do
   local a=(k+.5)*math.pi/4;local dir=Vector3.new(math.cos(a),0,math.sin(a))
   local pos=dir*r+Vector3.new(0,3.3,0)
   part('CrownBand',CFrame.lookAt(pos,Vector3.new(0,3.3,0)),Vector3.new(1.5,.72,.3),rgb(255,196,44),M.Metal)
   -- Diamond points half sunk into the band make the classic zig-zag crown edge.
   local tip=CFrame.lookAt(dir*(r+.02)+Vector3.new(0,3.7,0),Vector3.new(0,3.7,0))*CFrame.Angles(0,0,math.rad(45))
   part('CrownPoint',tip,Vector3.new(.82,.82,.26),rgb(255,214,84),M.Metal)
   ball('CrownJewel',dir*(r+.08)+Vector3.new(0,4.36,0),.4,Color3.fromHSV(k/8,.72,1),M.Neon)
  end
  ball('CrownOrb',Vector3.new(0,3.95,0),1.25,rgb(255,200,50),M.Metal)
  box('CrownCross',0,4.85,0,.26,.8,.26,rgb(255,214,84),M.Metal)
  box('CrownCross',0,4.92,0,.64,.24,.24,rgb(255,214,84),M.Metal)
 end
 if s.Horizon then
  -- A small black hole above the lid: void sphere in a tilted neon ring on a cyan halo.
  plate('SingularityHalo',2.9,3.1,.08,s.Seam2,M.Neon)
  plate('SingularityHalo',2.94,2.7,.08,rgb(0,0,0),M.SmoothPlastic)
  ball('Singularity',Vector3.new(0,3.95,0),1.45,rgb(0,0,0),M.SmoothPlastic)
  ring('SingularityRing',CFrame.new(0,3.95,0)*CFrame.Angles(math.rad(24),0,math.rad(-12)),8,1.18,.3,.12,function(a)
   return s.Seam:Lerp(rgb(255,255,255),(math.cos(a)+1)/4)end)
  -- Event horizon: a tilted violet-to-cyan ring around the waist.
  ring('EventHorizon',CFrame.new(0,-.2,0)*CFrame.Angles(math.rad(24),0,math.rad(-7)),16,4.45,.52,.14,function(a)
   return s.Seam:Lerp(s.Seam2,(math.cos(a)+1)/2)end)
 end

 -- Feet: every tier stands on the same bottom plane.
 for _,x in {-1,1}do for _,z in {-1,1}do
  box('Foot',x*2.2,FOOT+.1,z*2.2,.9,.2,.9,s.Foot,s.FootMat)
 end end

 if rank>=2 then
  local l=Instance.new('PointLight');l.Name='LuckyGlow';l.Color=C.VisualConfig.Colors[rank];l.Brightness=rank>=4 and .8 or .5
  l.Range=11;l.Shadows=false;l.Enabled=false;l.Parent=root
 end
 local core=Instance.new('Attachment');core.Name='LuckyCore';core.Position=Vector3.zero;core.Parent=root
 local label=Instance.new('Attachment');label.Name='DogLabelAnchor';label.Position=Vector3.new(0,top+1.5/SCALE,0);label.Parent=root
 m:ScaleTo(SCALE)
 m:SetAttribute('GroundLocal',Vector3.new(0,bottom*SCALE,0))
 return m
end
return V
