-- Active Mining: procedural models built from plain Parts (no external assets).
-- Shared by the server (held pickaxe / weight, world props) and the client (ore piles, previews).
local Models={}

local function rgb(t,fallback)
 t=t or fallback or{150,150,150};return Color3.fromRGB(t[1],t[2],t[3])
end
Models.RGB=rgb
local function material(name,fallback)
 local ok,m=pcall(function()return Enum.Material[name]end)
 if ok and m then return m end
 return fallback or Enum.Material.Slate
end
local function part(parent,name,size,cf,color,mat,props)
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=mat or Enum.Material.SmoothPlastic
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=true
 p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if props then for k,v in pairs(props)do(p::any)[k]=v end end
 p.Parent=parent;return p
end
Models.Part=part
local function wedge(parent,name,size,cf,color,mat,props)
 local p=Instance.new('WedgePart');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=mat or Enum.Material.SmoothPlastic
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
 if props then for k,v in pairs(props)do(p::any)[k]=v end end
 p.Parent=parent;return p
end
-- Rotation that turns +Y into dir.
local function alignY(dir)
 local up=Vector3.new(0,1,0);local d=dir.Unit;local dot=math.clamp(up:Dot(d),-1,1)
 if dot>.9999 then return CFrame.identity end
 if dot<-.9999 then return CFrame.Angles(math.pi,0,0)end
 return CFrame.fromAxisAngle(up:Cross(d).Unit,math.acos(dot))
end
Models.AlignY=alignY

local PARTICLES={
 Sparkle={Texture='rbxasset://textures/particles/sparkles_main.dds',Rate=6,Lifetime=NumberRange.new(.6,1.2),Speed=NumberRange.new(.5,1.5),Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,0)}),LightEmission=.9},
 Ember={Texture='rbxasset://textures/particles/fire_main.dds',Rate=14,Lifetime=NumberRange.new(.5,1.1),Speed=NumberRange.new(1.5,3.5),Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.9),NumberSequenceKeypoint.new(1,0)}),LightEmission=1,Acceleration=Vector3.new(0,4,0)},
 Void={Texture='rbxasset://textures/particles/sparkles_main.dds',Rate=12,Lifetime=NumberRange.new(.8,1.6),Speed=NumberRange.new(.4,1.2),Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,0)}),LightEmission=1,Acceleration=Vector3.new(0,1.5,0)},
}
local function emitter(parent,kind,color)
 local def=PARTICLES[kind];if not def then return nil end
 local e=Instance.new('ParticleEmitter');e.Name='Ambient'..kind
 for k,v in pairs(def)do(e::any)[k]=v end
 e.Color=ColorSequence.new(color);e.SpreadAngle=Vector2.new(180,180);e.LockedToPart=false;e.Parent=parent;return e
end
Models.Emitter=emitter

-- ORE PILE ---------------------------------------------------------------------------------------
-- def = Config.Mining.Ores[i]; seed keeps every client's pile identical for the same ore serial.
-- Returns Model (PrimaryPart = OreRoot at the pile's ground centre) and a list of hit points
-- (Attachments on OreRoot, pointing outwards) used to place the timing circles.
-- lite = a satellite outcrop: the same ore without the small surface details.
function Models.Ore(def,seed,rootCF,scale,lite)
 scale=scale or 1
 local v=def.Visual or{}
 local rng=Random.new(seed or 1)
 local model=Instance.new('Model');model.Name='OrePile'
 local root=part(model,'OreRoot',Vector3.new(1,1,1),rootCF,Color3.new(1,1,1),Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
 model.PrimaryPart=root
 local rock=rgb(v.Rock);local rockMat=material(v.RockMaterial or'Slate')
 local accent=rgb(v.Accent,v.Rock);local accentMat=material(v.AccentMaterial or'Glass',Enum.Material.Glass)
 local style=v.Style or'Plain'
 local hitPoints={}
 local function shade(c)
  local k=rng:NextNumber(-.14,.14)
  return k>0 and c:Lerp(Color3.new(1,1,1),k) or c:Lerp(Color3.new(0,0,0),-k)
 end
 -- Two-tone rock: every third chunk takes the lighter second rock colour.
 local rock2=v.Rock2 and rgb(v.Rock2)or rock
 local chunkCount=0
 local function chunk(offset,size)
  chunkCount+=1
  local cf=rootCF*CFrame.new(offset*scale)*CFrame.Angles(rng:NextNumber(-.6,.6),rng:NextNumber(0,math.pi*2),rng:NextNumber(-.6,.6))
  local p=part(model,'Chunk',size*scale,cf,shade(chunkCount%3==0 and rock2 or rock),rockMat)
  p:SetAttribute('OreChunk',true)
  return p
 end
 -- Base ring, middle ring, crown: a wide, tall, readable pile (~11 x 7 studs).
 for i=1,4 do
  local a=(i/4)*math.pi*2+rng:NextNumber(-.3,.3)
  chunk(Vector3.new(math.cos(a)*3.1,1.05,math.sin(a)*3.1),Vector3.new(rng:NextNumber(4.4,5.6),rng:NextNumber(2.2,2.9),rng:NextNumber(4.2,5.4)))
 end
 chunk(Vector3.new(0,1.4,0),Vector3.new(5.6,2.8,5.6))
 for i=1,6 do
  local a=(i/6)*math.pi*2+rng:NextNumber(-.35,.35)
  chunk(Vector3.new(math.cos(a)*2.2,3.0+rng:NextNumber(-.3,.4),math.sin(a)*2.2),Vector3.new(rng:NextNumber(2.8,3.8),rng:NextNumber(2.4,3.2),rng:NextNumber(2.8,3.6)))
 end
 chunk(Vector3.new(rng:NextNumber(-.5,.5),4.9,rng:NextNumber(-.5,.5)),Vector3.new(3.2,2.6,3.0))
 chunk(Vector3.new(rng:NextNumber(-.9,.9),6.0,rng:NextNumber(-.9,.9)),Vector3.new(2.1,1.8,2.0))
 -- Surface points (outward normals) shared by accents and hit circles.
 local surface={}
 for i=1,18 do
  local a=(i/18)*math.pi*2*3+rng:NextNumber(-.2,.2)
  local h=1.2+((i-1)%6)*.95
  local r=math.max(1.2,4.6-h*.48)
  local dir=Vector3.new(math.cos(a),.35+h*.08,math.sin(a)).Unit
  table.insert(surface,{Pos=Vector3.new(math.cos(a)*r,h,math.sin(a)*r),Dir=dir})
 end
 for i,s in ipairs(surface)do
  local att=Instance.new('Attachment');att.Name='HitPoint';att.Position=s.Pos*scale;att.Parent=root
  att:SetAttribute('Normal',s.Dir)
  hitPoints[i]=att
 end
 -- Facets, speckles, veins and loose pebbles: the pile reads as real, mineral-rich rock.
 do
  for i=1,lite and 3 or 7 do
   local s=surface[(i*3)%#surface+1]
   local w=rng:NextNumber(1.2,2.2)
   local cf=rootCF*CFrame.new((s.Pos+s.Dir*.9)*scale)*alignY(s.Dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
   local f=wedge(model,'Facet',Vector3.new(w,rng:NextNumber(.5,1.0),w*.8)*scale,cf,shade(rock2),rockMat)
   f:SetAttribute('OreChunk',true)
  end
  if not lite then
   local speck=v.Speckle and rgb(v.Speckle)or rock2
   for i=1,12 do
    local s=surface[(i*7+3)%#surface+1]
    local sz=rng:NextNumber(.22,.5)
    local cf=rootCF*CFrame.new((s.Pos+s.Dir*1.15)*scale)*alignY(s.Dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
    local sp=part(model,'Speckle',Vector3.new(sz,.08,sz*.8)*scale,cf,speck,(v.Glow or 0)>0 and Enum.Material.Glass or Enum.Material.SmoothPlastic,{Reflectance=.2,CastShadow=false})
    sp:SetAttribute('OreAccent',true)
   end
   if v.Vein then
    for i=1,5 do
     local s=surface[(i*5+1)%#surface+1]
     local cf=rootCF*CFrame.new((s.Pos+s.Dir*1.2)*scale)*alignY(s.Dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
     local glow=(v.Glow or 0)>=1
     local vn=part(model,'Vein',Vector3.new(rng:NextNumber(1.6,2.8),.1,.18)*scale,cf,rgb(v.Vein),glow and Enum.Material.Neon or Enum.Material.Metal,{CastShadow=false,Reflectance=.3})
     vn:SetAttribute('OreAccent',true)
    end
   end
   for i=1,8 do
    local a=i/8*math.pi*2+rng:NextNumber(-.3,.3);local r=rng:NextNumber(4.6,5.6)
    local sz=rng:NextNumber(.45,.9)
    part(model,'Pebble',Vector3.new(sz,sz*.6,sz*.8)*scale,rootCF*CFrame.new(math.cos(a)*r*scale,sz*.25*scale,math.sin(a)*r*scale)*CFrame.Angles(rng:NextNumber(0,1),rng:NextNumber(0,6),0),shade(i%2==0 and rock2 or rock),rockMat)
   end
   -- Ore specials.
   if v.Fossil then
    for i=1,2 do
     local s=surface[(i*9)%#surface+1]
     local cf=rootCF*CFrame.new((s.Pos+s.Dir*1.15)*scale)*alignY(s.Dir)*CFrame.Angles(math.rad(90),0,0)
     for k=0,6 do
      local a=k*.9;local r=(.15+k*.08)*scale
      part(model,'Fossil',Vector3.new(.12,.22,.22)*scale,cf*CFrame.new(math.cos(a)*r,math.sin(a)*r,0),rgb(v.Fossil),Enum.Material.Marble,{CastShadow=false})
     end
    end
   end
   if v.Ember then
    for i=1,6 do
     local s=surface[(i*11)%#surface+1]
     local e=part(model,'Ember',Vector3.new(.45,.14,.45)*scale,rootCF*CFrame.new((s.Pos+s.Dir*1.15)*scale),rgb(v.Ember),Enum.Material.Neon,{CastShadow=false})
     e:SetAttribute('OreAccent',true)
    end
   end
   if v.Geode then
    local s=surface[5]
    local cf=rootCF*CFrame.new((s.Pos+s.Dir*1.0)*scale)*alignY(s.Dir)
    local shell=part(model,'Geode',Vector3.new(2.2,2.2,2.2)*scale,cf*CFrame.new(0,-.5*scale,0),rock2,rockMat,{Shape=Enum.PartType.Ball})
    shell:SetAttribute('OreChunk',true)
    for k=1,7 do
     local a=k/7*math.pi*2
     local c=part(model,'GeodeCrystal',Vector3.new(.3,.7,.3)*scale,cf*CFrame.new(math.cos(a)*.55*scale,.45*scale,math.sin(a)*.55*scale)*CFrame.Angles(math.cos(a)*.5,0,math.sin(a)*.5),rgb(v.Speckle or v.Accent),Enum.Material.Neon,{CastShadow=false})
     c:SetAttribute('OreAccent',true)
    end
   end
   if v.Prism then
    local holder=part(model,'PrismFX',Vector3.new(6,4,6)*scale,rootCF*CFrame.new(0,3.5*scale,0),Color3.new(1,1,1),Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
    local e=emitter(holder,'Sparkle',Color3.new(1,1,1))
    if e then
     e.Rate=10;e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,120,200)),ColorSequenceKeypoint.new(.33,Color3.fromRGB(255,240,120)),
      ColorSequenceKeypoint.new(.66,Color3.fromRGB(120,255,220)),ColorSequenceKeypoint.new(1,Color3.fromRGB(150,160,255))})
    end
   end
  end
 end
 if style=='Nugget'then
  for i=1,(lite and 6 or 13)do
   local s=surface[(i*5)%#surface+1]
   local sz=rng:NextNumber(.9,1.7)
   local cf=rootCF*CFrame.new((s.Pos+s.Dir*1.0)*scale)*CFrame.Angles(rng:NextNumber(0,6),rng:NextNumber(0,6),rng:NextNumber(0,6))
   local p=part(model,'Accent',Vector3.new(sz,sz*.8,sz)*scale,cf,accent,accentMat,{Reflectance=v.Reflectance or .15})
   p:SetAttribute('OreAccent',true)
  end
 elseif style=='Crystal'or style=='Void'then
  local count=lite and math.ceil((v.Crystals or 8)*.5)or(v.Crystals or 8)
  for i=1,count do
   local s=surface[(i*7)%#surface+1]
   local dir=(s.Dir+Vector3.new(0,.9,0)).Unit
   local w=rng:NextNumber(.75,1.25);local h=rng:NextNumber(2.4,4.4)*(i==1 and 1.35 or 1)
   local base=rootCF*CFrame.new((s.Pos+s.Dir*.7)*scale)*alignY(dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
   local body=part(model,'Crystal',Vector3.new(w,h,w)*scale,base*CFrame.new(0,h*.5*scale,0),accent,accentMat,{Transparency=v.CrystalTransparency or .12})
   body:SetAttribute('OreAccent',true)
   local tip=part(model,'CrystalTip',Vector3.new(w*.72,w*.72,w*.72)*scale,base*CFrame.new(0,h*scale,0)*CFrame.Angles(math.rad(45),0,math.rad(45)),accent,accentMat,{Transparency=v.CrystalTransparency or .12})
   tip:SetAttribute('OreAccent',true)
   if v.Core then
    local core=part(model,'CrystalCore',Vector3.new(w*.38,h*.82,w*.38)*scale,base*CFrame.new(0,h*.5*scale,0),rgb(v.Core),Enum.Material.Neon,{CastShadow=false})
    core:SetAttribute('OreAccent',true)
   end
  end
 elseif style=='Meteor'then
  for i=1,16 do
   local s=surface[(i*5)%#surface+1]
   local len=rng:NextNumber(1.8,3.2)
   local cf=rootCF*CFrame.new((s.Pos+s.Dir*1.1)*scale)*alignY(s.Dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
   local p=part(model,'Vein',Vector3.new(len,.34,.5)*scale,cf,accent,Enum.Material.Neon,{CastShadow=false})
   p:SetAttribute('OreAccent',true)
  end
 elseif style=='Banded'then
  for i=1,12 do
   local s=surface[(i*5)%#surface+1]
   local cf=rootCF*CFrame.new((s.Pos+s.Dir*1.1)*scale)*alignY(s.Dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
   local p=part(model,'Band',Vector3.new(rng:NextNumber(1.8,2.8),.45,rng:NextNumber(1,1.6))*scale,cf,accent,accentMat,{Reflectance=v.Reflectance or .2})
   p:SetAttribute('OreAccent',true)
  end
 end
 if (v.Glow or 0)>0 and not lite then
  local glowPart=part(model,'OreGlow',Vector3.new(.4,.4,.4)*scale,rootCF*CFrame.new(0,4.2*scale,0),accent,Enum.Material.Neon,{Transparency=1,CastShadow=false})
  local light=Instance.new('PointLight');light.Name='OreLight';light.Color=accent;light.Brightness=v.Glow;light.Range=14*scale;light.Shadows=false;light.Parent=glowPart
 end
 if v.FX then
  local holder=part(model,'OreFX',Vector3.new(7,5,7)*scale,rootCF*CFrame.new(0,3.2*scale,0),accent,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
  emitter(holder,v.FX,v.FXColor and rgb(v.FXColor) or accent)
 end
 return model,hitPoints
end

-- PICKAXE ----------------------------------------------------------------------------------------
-- Model with Handle; the handle's +Y runs from the grip to the head. Grip point = Handle CFrame
-- shifted by -Y * (length * .32). Faces, eyes and screens look along +Z (the side the camera sees
-- in the hand, on the back and in the market preview); the striking tips point along +-X.
-- Parts that move carry attributes the client animates (MiningClient.PickFX):
--   PickAnim  = comma list of motion names ("Flutter,Bob")    PickPhase = number (seconds)
--   PickJoint = Vector3 pivot in model space (default: the part's own centre)
--   PickRainbow = true (colour cycles)   PickPulse = true (neon glow pulses)   PickFlicker = true
-- Models.WeldToSelf joins such parts with Motor6Ds, so every client can drive Motor6D.Transform
-- (not replicated, like character animation); anchored previews are moved directly.
local function ball(parent,name,d,cf,color,mat,props)
 local p=part(parent,name,Vector3.new(d,d,d),cf,color,mat,props);p.Shape=Enum.PartType.Ball;return p
end
local function blob(parent,name,size,cf,color,mat,props)
 local p=part(parent,name,size,cf,color,mat,props)
 local mesh=Instance.new('SpecialMesh');mesh.MeshType=Enum.MeshType.Sphere;mesh.Parent=p
 return p
end
-- Cylinder along the model Y axis (Roblox cylinders run along local X).
local function cylY(parent,name,height,d,cf,color,mat,props)
 local p=part(parent,name,Vector3.new(height,d,d),cf*CFrame.Angles(0,0,math.pi/2),color,mat,props);p.Shape=Enum.PartType.Cylinder;return p
end
-- Cylinder along the model Z axis (discs facing the camera).
local function cylZ(parent,name,depth,d,cf,color,mat,props)
 local p=part(parent,name,Vector3.new(depth,d,d),cf*CFrame.Angles(0,math.pi/2,0),color,mat,props);p.Shape=Enum.PartType.Cylinder;return p
end
-- Box from a to b (width w, depth h).
local function bar(parent,name,a,b,w,h,color,mat,props)
 local mid=(a+b)/2;local len=(b-a).Magnitude
 return part(parent,name,Vector3.new(w,len,h),CFrame.new(mid)*alignY(b-a),color,mat,props)
end
local function rod(parent,name,a,b,d,color,mat,props)
 local mid=(a+b)/2;local len=(b-a).Magnitude
 local p=part(parent,name,Vector3.new(len,d,d),CFrame.new(mid)*alignY(b-a)*CFrame.Angles(0,0,math.pi/2),color,mat,props)
 p.Shape=Enum.PartType.Cylinder;return p
end
-- Ring of n boxes in the XY plane of cf (opening facing +-Z); skip(i) leaves gaps.
local function ring(parent,name,cf,radius,thick,depth,n,color,mat,skip,props)
 local out={}
 local len=2*radius*math.tan(math.pi/n)+.04
 for i=0,n-1 do
  if not(skip and skip(i))then
   local a=i/n*math.pi*2
   table.insert(out,part(parent,name,Vector3.new(thick,len,depth),cf*CFrame.new(math.cos(a)*radius,math.sin(a)*radius,0)*CFrame.Angles(0,0,a),color,mat,props))
  end
 end
 return out
end
local function anim(p,kind,phase,joint)
 p:SetAttribute('PickAnim',kind)
 if phase then p:SetAttribute('PickPhase',phase)end
 if joint then p:SetAttribute('PickJoint',joint)end
 return p
end
local function eye(parent,name,d,cf,white,pupil,kind,phase)
 local e=ball(parent,name,d,cf,white or Color3.fromRGB(250,250,245),Enum.Material.SmoothPlastic)
 local p=ball(parent,name..'Pupil',d*.48,cf*CFrame.new(0,0,d*.36),pupil or Color3.fromRGB(16,16,20),Enum.Material.SmoothPlastic)
 local g=ball(parent,name..'Glint',d*.16,cf*CFrame.new(d*.12,d*.14,d*.48),Color3.new(1,1,1),Enum.Material.Neon,{CastShadow=false})
 if kind then for _,x in ipairs({e,p,g})do anim(x,kind,phase,cf.Position)end end
 return e,p,g
end
local function text(p,face,s,color,font)
 local g=Instance.new('SurfaceGui');g.Name='PickLabel';g.Face=face;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=80
 g.LightInfluence=0;g:SetAttribute('NoTranslate',true);g.Parent=p
 local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.Text=s;l.TextScaled=true;l.TextColor3=color
 l.Font=font or Enum.Font.FredokaOne;l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true);l.Parent=g
 return g
end
local function trailPoints(handle,a,b)
 local p1=Instance.new('Attachment');p1.Name='TrailA';p1.Position=a;p1.Parent=handle
 local p2=Instance.new('Attachment');p2.Name='TrailB';p2.Position=b;p2.Parent=handle
end
local function stripes(parent,len,colors,mat,d,from,to)
 local n=#colors;local y0=from or -len*.5;local y1=to or len*.5;local step=(y1-y0)/n
 for i=1,n do
  cylY(parent,'Stripe',step+.01,d or .36,CFrame.new(0,y0+step*(i-.5),0),colors[i],mat,{Massless=true})
 end
end

local DESIGNS={}
-- The original look (the Wooden starter and any def without a Kind).
DESIGNS.Classic=function(model,v,def,len,top)
 -- The starter: a chunky stone head lashed to a knotty stick with rope, a chipped edge, nails and
 -- a little green sprout ("every legend starts with a stick").
 local shaft=rgb(v.Shaft,{120,82,48});local trim=rgb(v.Trim,{60,60,64})
 local stoneHead=Color3.fromRGB(150,146,138)
 for i=1,3 do ball(model,'Knot',.42,CFrame.new((i%2==0 and .12 or-.12),-len*.3+i*.8,.1),shaft:Lerp(Color3.new(0,0,0),.25),Enum.Material.Wood)end
 part(model,'Grip',Vector3.new(.44,len*.26,.44),CFrame.new(0,-len*.33,0),trim,material(v.GripMaterial or'Fabric'))
 for i=0,3 do cylY(model,'GripBand',.08,.5,CFrame.new(0,-len*.44+i*.32,0),Color3.fromRGB(196,160,110),Enum.Material.Fabric)end
 local span=v.Span or 1.7
 part(model,'HeadCore',Vector3.new(1.0,.9,.8),top*CFrame.new(0,.05,0),stoneHead,Enum.Material.Slate)
 for side=-1,1,2 do
  local arm=part(model,'HeadArm',Vector3.new(span,.62,.66),top*CFrame.new(side*(span*.5+.3),.08,0)*CFrame.Angles(0,0,side*math.rad(-14)),stoneHead,Enum.Material.Slate)
  local tipCF=arm.CFrame*CFrame.new(side*(span*.5+.36),-.06,0)*CFrame.Angles(0,side>0 and math.pi*.5 or-math.pi*.5,0)
  wedge(model,'HeadTip',Vector3.new(.66,.56,.8),tipCF*CFrame.Angles(math.pi*.5,0,0),stoneHead:Lerp(Color3.new(1,1,1),.12),Enum.Material.Slate)
  part(model,'Chip',Vector3.new(.3,.18,.7),arm.CFrame*CFrame.new(side*.2,.3,0)*CFrame.Angles(0,0,side*.5),stoneHead:Lerp(Color3.new(0,0,0),.25),Enum.Material.Slate)
 end
 for i=-1,1 do
  part(model,'Rope',Vector3.new(.14,1.0,1.0),top*CFrame.new(i*.24,0,0),Color3.fromRGB(214,184,128),Enum.Material.Fabric,{Shape=Enum.PartType.Cylinder})
 end
 for i=1,3 do part(model,'Nail',Vector3.new(.09,.09,.08),top*CFrame.new((i-2)*.2,.22,.42),Color3.fromRGB(70,70,74),Enum.Material.Metal)end
 local sprout=top*CFrame.new(-.2,.62,0)
 rod(model,'SproutStem',sprout.Position,(sprout*CFrame.new(-.1,.5,0)).Position,.07,Color3.fromRGB(90,170,70),Enum.Material.Grass)
 for side=-1,1,2 do
  local leaf=blob(model,'SproutLeaf',Vector3.new(.34,.12,.22),sprout*CFrame.new(-.1+side*.17,.5,0)*CFrame.Angles(0,0,side*.5),Color3.fromRGB(120,210,90),Enum.Material.SmoothPlastic)
  anim(leaf,'Bob',side)
 end
 return Vector3.new(-span-.6,len*.5-.2,0),Vector3.new(span+.6,len*.5-.2,0)
end

-- Butterfly Catcher ("Сачок Ловец Бабочек" concept sheet, Uncommon / Cute Weird): a voxel butterfly
-- net. A round hoop of lavender stone bricks (an inner wall and staggered front / back lips) overgrown
-- with blocky leaves, cream blocks and little white flowers (a bigger one on top); inside, the magic
-- film: a glowing back film, a stepped voxel dome bulging forward (iridescent, MiningClient.PickFX),
-- a bright edge and a sheen, where five glowing butterflies, fireflies and four-point stars live; a
-- blue butterfly sits on the rim. Behind the film the shaft runs on up as a vine-wrapped spine with a
-- big cream flower (blue centre, gold ring) on the back. At the neck a cream block collar and a chunky
-- sky-blue bow with a gold flower medallion (blue gem) and two long V-notched tails that sway; a square
-- shaft of pale-blue / white blocks (cream ones under the bow) wound with a leafy vine and flowers;
-- a yellow block pommel with a blue gem tile on every side, leaves under it and a blue flower on the end.
DESIGNS.Net=function(model,v,def,len,top)
 local SP,GL,NE=Enum.Material.SmoothPlastic,Enum.Material.Glass,Enum.Material.Neon
 local brick=rgb(v.Head)                          -- lavender stone bricks
 local filmC=rgb(v.Film)                          -- the glowing magic film
 local ribbon=rgb(v.Accent)                       -- sky-blue bow
 local leafC=rgb(v.Trim)                          -- spring-green leaves
 local gold=rgb(v.Gold,{246,204,86})              -- yellow pommel / medallion
 local pale=rgb(v.Shaft)                          -- pale-blue shaft blocks
 local snow=Color3.fromRGB(242,248,252)
 local cream=Color3.fromRGB(246,228,150)
 local deepBlue=Color3.fromRGB(72,150,236)
 local greens={leafC,leafC:Lerp(Color3.fromRGB(196,242,112),.4),leafC:Lerp(Color3.fromRGB(40,112,44),.32)}
 local small={CastShadow=false}
 local glow={CastShadow=false}
 model.PrimaryPart.Transparency=1                -- the thin Handle hides inside the block shaft
 -- deterministic "random" (every peer builds the identical model)
 local seed=0
 local function rnd()seed+=1;local x=math.sin(seed*12.9898+78.233)*43758.5453;return x-math.floor(x)end
 local function shade(c,amount)local k=(rnd()-.5)*(amount or .16);return k>0 and c:Lerp(Color3.new(1,1,1),k*.6)or c:Lerp(Color3.new(0,0,0),-k)end
 local function green()return shade(greens[1+math.floor(rnd()*3)],.07)end
 local RF,RI,RO=.96,1.16,1.3                      -- film, inner wall and outer band radii
 local nb=len*.5                                  -- top of the shaft
 local H=Vector3.new(0,nb+RO-.12,0)              -- hoop centre
 local HC=CFrame.new(H)
 local function at(x,y,z)return CFrame.new(H+Vector3.new(x,y,z))end
 -- a box on the hoop: X points out from the centre at angle a, radius r, depth z
 local function polar(a,r,z)return HC*CFrame.new(math.cos(a)*r,math.sin(a)*r,z)*CFrame.Angles(0,0,a)end
 local function ringOf(name,n,r,radial,depth,z,color,mat,offset,fill,props)
  local out={}
  local seg=2*r*math.tan(math.pi/n)*(fill or .9)
  for i=0,n-1 do
   local c=typeof(color)=='Color3'and color or color()
   table.insert(out,part(model,name,Vector3.new(radial,seg,depth),polar((i+(offset or 0))/n*math.pi*2,r,z),c,mat or SP,props))
  end
  return out
 end
 -- A blocky flower facing +Z of cf: n square petals (corner out) round a cube heart; d = width.
 local function flower(name,cf,d,petal,heart,n)
  n=n or 5
  local out={}
  for k=0,n-1 do
   local a=k/n*math.pi*2+math.pi/2
   table.insert(out,part(model,name,Vector3.new(d*.4,d*.4,d*.14),cf*CFrame.new(math.cos(a)*d*.3,math.sin(a)*d*.3,0)*CFrame.Angles(0,0,a+math.pi/4),shade(petal,.05),SP,small))
  end
  table.insert(out,part(model,name..'Heart',Vector3.new(d*.3,d*.3,d*.2),cf*CFrame.new(0,0,d*.05),heart,SP,small))
  return out
 end
 -- a flower stuck on a surface at pos, facing out along n (spun by a little at random)
 local function stuck(name,pos,n,d,petal,heart,petals)
  return flower(name,CFrame.lookAt(pos,pos-n)*CFrame.Angles(0,0,rnd()*6.28),d,petal,heart,petals)
 end

 -- HOOP: an inner wall of bricks, staggered lighter front lip and back lip, a darker band below the leaves
 ringOf('HoopBrick',26,(RF+RI)*.5,RI-RF+.02,.42,0,function()return shade(brick,.1)end,SP,.5)
 ringOf('HoopLip',24,1.1,.3,.1,.24,function()return shade(brick:Lerp(Color3.new(1,1,1),.28),.08)end,SP,0)
 ringOf('HoopLip',24,1.1,.3,.1,-.24,function()return shade(brick,.08)end,SP,.5)
 ringOf('HoopBand',22,RI+.06,.16,.4,0,brick:Lerp(Color3.fromRGB(96,104,176),.22),SP,0,1.02)
 -- LEAVES all round the hoop (thinner on the right, where the bricks show), cream blocks among them
 for i=1,60 do
  local a=i/60*math.pi*2+(rnd()-.5)*.1
  if rnd()<.8+.3*math.cos(a-math.pi)then
   local s=.15+rnd()*.12
   local c=rnd()<.14 and shade(cream,.08)or green()
   part(model,'HoopLeaf',Vector3.new(s,s*(1+rnd()*.4),s),polar(a,RO+rnd()*.07,(rnd()-.5)*.5)*CFrame.Angles(rnd()*.5,rnd()*.5,rnd()*.6),c,SP)
  end
 end
 -- leaves spilling over the front lip
 for i=1,24 do
  local a=i/24*math.pi*2+rnd()*.2
  if rnd()<.62+.35*math.cos(a-math.pi)then
   local s=.13+rnd()*.08
   part(model,'HoopLeaf',Vector3.new(s,s*1.3,s*.6),polar(a,1.24+rnd()*.05,.31)*CFrame.Angles(0,0,rnd()-.5),green(),SP,small)
  end
 end
 -- little white / blush flowers round the rim, a bigger one on top
 for _,f in ipairs({{math.pi*.5,.4,snow},{2.15,.28,Color3.fromRGB(255,236,226)},{2.7,.3,snow},{3.35,.26,cream:Lerp(snow,.55)},{3.95,.3,snow},
  {4.6,.26,Color3.fromRGB(255,232,240)},{5.35,.24,snow},{.6,.25,snow},{.05,.23,Color3.fromRGB(255,240,228)},{1.15,.27,snow}})do
  local a,d=f[1],f[2]
  local out=Vector3.new(math.cos(a),math.sin(a),0)
  stuck('HoopFlower',H+out*(RO+.04)+Vector3.new(0,0,.2),(Vector3.zAxis+out*.7).Unit,d,f[3],Color3.fromRGB(255,206,64))
 end

 -- FILM: a glowing back film, a stepped voxel dome bulging forward, a bright edge and a sheen
 local back=cylZ(model,'NetFilm',.04,RF*2+.04,at(0,0,-.08),filmC,NE,{Transparency=.38,CastShadow=false})
 back:SetAttribute('PickPulse',true)
 local DOME,DEPTH=6,.78
 for i=1,DOME do
  local z=(i-.5)/DOME*DEPTH
  local r=RF*math.sqrt(math.max(.06,1-(z/(DEPTH+.06))^2))
  local s=cylZ(model,'NetDome',DEPTH/DOME+.005,r*2,at(0,0,z-.03),filmC:Lerp(Color3.fromRGB(228,190,255),i/DOME*.7),SP,{Transparency=.8,CastShadow=false})
  s:SetAttribute('NetIri',i/DOME)
 end
 ringOf('NetEdge',20,RF-.02,.05,.06,.03,Color3.fromRGB(214,236,255),NE,0,1.02,{Transparency=.25,CastShadow=false})
 blob(model,'NetSheen',Vector3.new(.5,.2,.06),at(-.4,.4,DEPTH*.6)*CFrame.Angles(.3,-.3,.75),Color3.new(1,1,1),SP,{Transparency=.55,CastShadow=false})
 -- glowing butterflies in the film (they drift and flutter: NetFly + NetWingL/R, MiningClient.PickFX)
 local WINGS={Color3.fromRGB(130,206,255),Color3.fromRGB(255,150,222),Color3.fromRGB(255,226,118),Color3.fromRGB(150,248,200),Color3.fromRGB(196,160,255)}
 local function butterfly(cf,s,color,ph,fly,wingL,wingR)
  local j=cf.Position
  local body=part(model,'ButterflyBody',Vector3.new(.05*s,.24*s,.05*s),cf,color:Lerp(Color3.new(1,1,1),.45),NE,glow)
  if fly then anim(body,fly,ph,j)end
  for _,side in ipairs({-1,1})do
   local kinds=(fly and(fly..',')or'')..(side<0 and wingL or wingR)
   anim(part(model,'ButterflyWing',Vector3.new(.21*s,.19*s,.02*s),cf*CFrame.new(side*.115*s,.055*s,0)*CFrame.Angles(0,0,-side*.35),color,NE,glow),kinds,ph,j)
   anim(part(model,'ButterflyWing',Vector3.new(.14*s,.13*s,.02*s),cf*CFrame.new(side*.085*s,-.075*s,0)*CFrame.Angles(0,0,side*.4),color:Lerp(Color3.new(1,1,1),.22),NE,glow),kinds,ph,j)
  end
 end
 for i,b in ipairs({{-.36,.3,.3,1.35},{.34,.16,.42,1.2},{-.04,-.38,.36,1.45},{.1,.44,.2,1.05},{.42,-.34,.22,1.1}})do
  butterfly(at(b[1],b[2],b[3])*CFrame.Angles(0,0,(rnd()-.5)*.3),b[4],WINGS[i],i*1.37,'NetFly','NetWingL','NetWingR')
 end
 -- a blue butterfly sitting on the right of the rim, slowly opening and closing its wings
 butterfly(at(RO+.1,.26,.16)*CFrame.Angles(0,-.35,-.2),1.5,WINGS[1],.4,nil,'NetPerchL','NetPerchR')
 -- fireflies wandering in the film and twinkling four-point stars
 for i=1,6 do
  local a=i*2.1;local r=.25+rnd()*.4
  local f=part(model,'NetFirefly',Vector3.new(.07,.07,.07),at(math.cos(a)*r,math.sin(a)*r,.12+rnd()*.4),i%2==0 and Color3.fromRGB(255,244,150)or Color3.fromRGB(206,255,170),NE,glow)
  anim(f,'NetFirefly',i*1.9);f:SetAttribute('NetTwinkle',i*.9)
 end
 for i=1,6 do
  local a=i*1.05+.4;local r=.2+rnd()*.55
  local cf=at(math.cos(a)*r,math.sin(a)*r,.08+rnd()*.42)*CFrame.Angles(0,0,rnd()*.4)
  local s=.13+rnd()*.08
  for _,size in ipairs({Vector3.new(s,.03,.02),Vector3.new(.03,s,.02)})do
   part(model,'NetStar',size,cf,Color3.fromRGB(255,250,226),NE,glow):SetAttribute('NetTwinkle',i*1.3+.5)
  end
 end

 -- SPINE behind the film: the shaft runs on up, wound with leaves; a big cream flower on the back
 part(model,'NetSpine',Vector3.new(.22,RI*2+.04,.16),at(0,0,-.3),pale,SP)
 for i=0,9 do
  part(model,'SpineVine',Vector3.new(.12,.14,.12),at((i%2*2-1)*.1,-RI+.12+i*.24,-.37),green(),SP)
 end
 do
  local cf=at(0,0,-.44)*CFrame.Angles(0,math.pi,0)
  for k=0,7 do
   local a=k/8*math.pi*2
   part(model,'BackPetal',Vector3.new(.24,.24,.08),cf*CFrame.new(math.cos(a)*.27,math.sin(a)*.27,0)*CFrame.Angles(0,0,a+math.pi/4),shade(Color3.fromRGB(250,234,182),.05),SP)
  end
  cylZ(model,'BackRing',.08,.34,cf*CFrame.new(0,0,.03),gold,SP)
  cylZ(model,'BackGem',.1,.2,cf*CFrame.new(0,0,.05),deepBlue,GL,{CastShadow=false,Reflectance=.15})
  part(model,'BackGlint',Vector3.new(.05,.05,.02),cf*CFrame.new(-.04,.04,.11),Color3.new(1,1,1),NE,small)
 end

 -- NECK: a cream block collar where the hoop sits on the shaft, a few leaves
 part(model,'NeckBlock',Vector3.new(.46,.3,.46),CFrame.new(0,nb-.02,0),shade(cream,.05),SP)
 part(model,'NeckBlock',Vector3.new(.3,.22,.5),CFrame.new(.1,nb+.2,-.02),shade(cream,.05),SP)
 for _,o in ipairs({{-.24,nb+.08,.1},{.22,nb-.1,-.12},{-.1,nb+.26,-.2}})do
  part(model,'NeckLeaf',Vector3.new(.18,.16,.16),CFrame.new(o[1],o[2],o[3])*CFrame.Angles(rnd(),rnd(),rnd()),green(),SP)
 end
 -- BOW: knot, two chunky loops (an inner fold each), two long V-notched tails, a gold flower medallion
 local K=CFrame.new(0,nb-.3,.27)
 part(model,'BowKnot',Vector3.new(.26,.26,.18),K,ribbon,SP)
 for _,s in ipairs({-1,1})do
  local loop=K*CFrame.new(s*.3,.08,-.02)*CFrame.Angles(0,0,s*.38)
  part(model,'BowLoop',Vector3.new(.46,.3,.16),loop,shade(ribbon,.05),SP)
  part(model,'BowLoop',Vector3.new(.12,.4,.18),loop*CFrame.new(s*.24,.02,0),ribbon:Lerp(Color3.new(1,1,1),.15),SP)
  part(model,'BowFold',Vector3.new(.26,.1,.04),loop*CFrame.new(-s*.01,0,.08),ribbon:Lerp(Color3.fromRGB(40,92,164),.35),SP,small)
  for k=1,3 do
   local seg=K*CFrame.new(s*(.08+k*.06),-.12-k*.26,-.01)*CFrame.Angles(0,0,s*.22)
   local p=anim(part(model,'BowTail',Vector3.new(.17,.3,.05),seg,shade(ribbon,.05),SP),'NetRibbon',s*.6,K.Position)
   p:SetAttribute('PickAmp',s*(.7+k*.3))
   if k==3 then -- the V-notched end
    for _,e in ipairs({-1,1})do
     local tip=anim(part(model,'BowTail',Vector3.new(.07,.13,.05),seg*CFrame.new(e*.05,-.19,0)*CFrame.Angles(0,0,e*.35),shade(ribbon,.05),SP,small),'NetRibbon',s*.6,K.Position)
     tip:SetAttribute('PickAmp',s*1.6)
    end
   end
  end
 end
 do
  local m=K*CFrame.new(0,0,.12)
  cylZ(model,'Medallion',.07,.3,m,gold,SP)
  for k=0,7 do
   local a=k/8*math.pi*2
   part(model,'MedallionPetal',Vector3.new(.08,.08,.06),m*CFrame.new(math.cos(a)*.16,math.sin(a)*.16,0)*CFrame.Angles(0,0,a+math.pi/4),gold:Lerp(Color3.new(1,1,1),.2),SP,small)
  end
  cylZ(model,'MedallionGem',.09,.15,m*CFrame.new(0,0,.02),deepBlue:Lerp(Color3.new(1,1,1),.2),GL,{CastShadow=false,Reflectance=.15})
  part(model,'MedallionGlint',Vector3.new(.04,.04,.02),m*CFrame.new(-.03,.03,.07),Color3.new(1,1,1),NE,small)
 end

 local BOW={BowKnot=true,BowLoop=true,BowFold=true,BowTail=true,Medallion=true,MedallionPetal=true,MedallionGem=true,MedallionGlint=true}
 -- the bow is built small and scaled up round its knot (the sheet's bow is half as wide as the hoop)
 for _,p in ipairs(model:GetChildren())do
  if p:IsA('BasePart')and BOW[p.Name]then
   local rel=K:ToObjectSpace(p.CFrame)
   p.Size*=1.3;p.CFrame=K*CFrame.new(rel.Position*1.3)*rel.Rotation
  end
 end

 -- SHAFT: square pale-blue / white blocks (cream ones under the bow) over the core
 local sb=-len*.5
 local cols={pale,snow,pale:Lerp(Color3.fromRGB(110,180,236),.3),snow,pale:Lerp(snow,.4)}
 local y,i=sb+.13,0
 while y<nb-.12 do
  i+=1
  local c=y>nb-.8 and(i%2==0 and shade(cream,.05)or pale)or shade(cols[(i%#cols)+1],.04)
  part(model,'ShaftBlock',Vector3.new(.36,.25,.36),CFrame.new(0,y,0),c,SP)
  y+=.27
 end
 -- a leafy vine winding up the shaft above the hand, flowers on it
 for k=0,22 do
  local yy=sb+.8+k*(len-1.1)/22
  local a=k*.62
  local o=Vector3.new(math.cos(a),0,math.sin(a))
  local p=Vector3.new(0,yy,0)+o*.21
  part(model,'Vine',Vector3.new(.12,.15,.12),CFrame.new(p),shade(greens[3],.06),SP)
  part(model,'VineLeaf',Vector3.new(.24,.07,.17),CFrame.new(p+o*.11)*CFrame.Angles(0,-a,0)*CFrame.Angles(0,0,k%2==0 and .5 or -.4),green(),SP,small)
  if k%3==1 then
   part(model,'VineLeaf',Vector3.new(.17,.17,.07),CFrame.new(p+Vector3.new(0,.1,0)-o*.02)*CFrame.Angles(0,-a+1.2,.6),green(),SP,small)
  end
  if k==3 or k==8 or k==13 or k==17 or k==21 then
   stuck('ShaftFlower',p+o*.1,o,.26,k==17 and Color3.fromRGB(160,212,250)or snow,Color3.fromRGB(255,206,64))
  end
 end

 -- POMMEL: a yellow block with a blue gem tile on every side, leaves under it, a blue flower on the end
 part(model,'PommelCollar',Vector3.new(.44,.12,.44),CFrame.new(0,sb-.02,0),pale:Lerp(Color3.fromRGB(110,180,236),.3),SP)
 local py=sb-.3
 part(model,'Pommel',Vector3.new(.62,.42,.62),CFrame.new(0,py,0),gold,SP)
 part(model,'PommelRim',Vector3.new(.66,.08,.66),CFrame.new(0,py+.2,0),gold:Lerp(Color3.new(1,1,1),.25),SP)
 part(model,'PommelRim',Vector3.new(.66,.08,.66),CFrame.new(0,py-.2,0),gold:Lerp(Color3.fromRGB(190,128,30),.3),SP)
 for k=0,3 do
  local f=CFrame.new(0,py,0)*CFrame.Angles(0,k*math.pi/2,0)*CFrame.new(0,0,.31)
  part(model,'PommelTile',Vector3.new(.3,.3,.04),f,ribbon:Lerp(Color3.new(1,1,1),.3),SP,small)
  part(model,'PommelGem',Vector3.new(.17,.17,.06),f*CFrame.new(0,0,.02)*CFrame.Angles(0,0,math.pi/4),deepBlue,GL,{CastShadow=false,Reflectance=.15})
  part(model,'PommelGlint',Vector3.new(.04,.04,.02),f*CFrame.new(-.035,.035,.055),Color3.new(1,1,1),NE,small)
 end
 part(model,'PommelBase',Vector3.new(.42,.14,.42),CFrame.new(0,py-.27,0),greens[3],SP)
 for k=0,3 do
  local a=k*math.pi/2+math.pi/4
  part(model,'PommelLeaf',Vector3.new(.26,.08,.16),CFrame.new(math.cos(a)*.24,py-.27,math.sin(a)*.24)*CFrame.Angles(0,-a,0)*CFrame.Angles(0,0,-.45),green(),SP)
 end
 flower('PommelFlower',CFrame.new(0,py-.35,0)*CFrame.Angles(math.pi/2,0,0),.28,Color3.fromRGB(150,206,250),gold,4)

 -- IDLE FX: the film's soft light and a few firefly sparkles drifting out of it (PickFX does the rest)
 local holder=part(model,'NetGlow',Vector3.new(1.6,1.6,.6),at(0,0,.3),filmC,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='NetLight';light.Color=Color3.fromRGB(150,200,255);light.Range=6;light.Brightness=.8;light.Shadows=false;light.Parent=holder
 local fx=emitter(holder,'Sparkle',Color3.fromRGB(255,240,150))
 if fx then
  fx.Name='NetFireflies';fx.Rate=1.6;fx.Speed=NumberRange.new(.2,.7);fx.Lifetime=NumberRange.new(.9,1.6)
  fx.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(1,0)})
  fx.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,244,150)),ColorSequenceKeypoint.new(.5,Color3.fromRGB(190,236,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,190,236))})
 end
 -- In the hand it leans a little forward (the film toward the holder's camera); on the back it sits a
 -- little lower and further out; the market stall shows it smaller (it is a big net).
 model:SetAttribute('HandTilt',18)
 model:SetAttribute('BackC0',CFrame.new(.1,-.3,.25))
 model:SetAttribute('DisplayScale',.82)
 return(at(-RO,0,0)).Position,(at(RO,0,0)).Position
end

-- LEGO Hand ("LEGO-Рука" concept sheet, RARE / MEME): a giant minifig hand turned into a pickaxe,
-- built brick by brick. HEAD: the C-shaped minifig hand (front +Z) laid out from the sheet's front
-- view (LEGO_HAND, one cell = one voxel): a thick lower-left palm, the curled finger arching over the
-- top and hanging down on the right into a rounded tip, the thumb jutting out to the right at the
-- bottom, the deep cavity between them. Every row is laid in staggered yellow 1x2 bricks (slightly
-- uneven, a darker core shows the seams), the outer rim steps in (voxel rounding), studs on every
-- upward face, loose studs on the front and the back. Stickers on the front as on the sheet: the
-- yellow smiley, the red splat with a cheeky face, the red "LEGO" seal, a white disc sticker; a
-- small "LEGO" seal on the left side. WRIST: a yellow stub, a blue 2x2 band (orange studs on the
-- front, blue on the back, dark technic pins on the sides) and a red band with studs. SHAFT: stacked
-- black 1x2 bricks, a vertical red "LEGO" logo, dark grey and blue studs. POMMEL: a yellow 2x2x2
-- cube (blue round "C" clip on the front, studs round it) on two offset black bricks.
-- SmoothPlastic with a little Reflectance everywhere (glossy ABS), Neon only for the faint glow.
-- Moving parts (MiningClient.PickFX): LegoHand (the whole hand turns on the wrist like a real
-- minifig hand: a slow idle sway, a click round on a hit, the ratchet spin of the inspect, a snap in
-- on the draw), LegoFinger (the curled finger also clacks shut toward the thumb on a strike;
-- PickHang = its knuckle, relative to the wrist joint).
local LEGO_HAND={ -- top row first; '#' = brick, '.' = empty (front view, the C opens to +X)
 '.......#####......',
 '....###########...',
 '..##############..',
 '.################.',
 '#################.',
 '########....######',
 '#######......#####',
 '#######.......####',
 '#######.......####',
 '#######.......###.',
 '########......###.',
 '########..........',
 '#########.........',
 '###############...',
 '################..',
 '.###############..',
 '..############....',
}
DESIGNS.Lego=function(model,v,def,len,top)
 local SP,NE=Enum.Material.SmoothPlastic,Enum.Material.Neon
 local yellow,red,blue=rgb(v.Head,{255,200,24}),rgb(v.Trim,{222,32,36}),rgb(v.Accent,{28,98,214})
 local black,white,orange=rgb(v.Shaft,{34,36,46}),rgb(v.White,{242,242,236}),rgb(v.Stud,{255,150,32})
 local dgrey,ink=Color3.fromRGB(82,84,92),Color3.fromRGB(20,18,22)
 local gloss={Reflectance=.06}
 local seed=0
 local function rnd()seed+=1;return(math.sin(seed*12.9898+78.233)*43758.5453)%1 end -- same on every peer
 local function shade(c,k)return c:Lerp(k>0 and Color3.new(1,1,1)or Color3.new(0,0,0),math.abs(k))end
 local function yel()local r=rnd();return r<.35 and yellow or(r<.7 and shade(yellow,-.06)or(r<.9 and shade(yellow,.07)or shade(yellow,-.12)))end
 local function plastic(name,size,cf,color,props)return part(model,name,size,cf,color,SP,props or gloss)end
 local function studZ(name,cf,d,color,f)            -- a stud on a face (+Z of cf, f = -1 for -Z)
  local p=cylZ(model,name,.07,d,cf*CFrame.new(0,0,.035*(f or 1)),color,SP,gloss)
  cylZ(model,name,.012,d*.62,cf*CFrame.new(0,0,(.07+.006)*(f or 1)),shade(color,.12),SP,gloss) -- the moulded rim
  return p
 end
 local function studX(name,cf,d,color,f)            -- a stud on a side (+X of cf, f = -1 for -X)
  return part(model,name,Vector3.new(.07,d,d),cf*CFrame.new(.035*(f or 1),0,0),color,SP,{Shape=Enum.PartType.Cylinder,Reflectance=.06})
 end
 local function studY(name,cf,d,color)
  return cylY(model,name,.07,d,cf*CFrame.new(0,.035,0),color,SP,gloss)
 end
 local handParts={}
 local function hand(p)table.insert(handParts,p);return p end

 -- HEAD: the voxel C ---------------------------------------------------------------------------
 local S=.16
 local rows=#LEGO_HAND
 local yb=1.52                                         -- bottom of the hand (on the wrist stub)
 local function X(c)return(c-5.5)*S end
 local function Y(r)return yb+(rows-r+.5)*S end        -- r = 1 is the top row
 local filled={}
 for r,line in ipairs(LEGO_HAND)do
  for c=0,#line-1 do if line:sub(c+1,c+1)=='#'then filled[r*100+c]=true end end
 end
 local function at(c,r)return filled[r*100+c]==true end
 -- distance (in cells) to the outside: the rim steps in, the middle is the full thickness
 local function rim(c,r)
  for d=1,2 do
   for dc=-d,d do for dr=-d,d do
    if math.abs(dc)+math.abs(dr)<=d and not at(c+dc,r+dr)then return d end
   end end
  end
  return 3
 end
 local DEPTH={1.0,1.2,1.3}
 local front={} -- cell -> z of its front face (stickers and studs sit on it)
 for r,line in ipairs(LEGO_HAND)do
  -- the darker core behind each run (the brick seams show it)
  local c=0
  while c<#line do
   if at(c,r)then
    local c2=c;while at(c2+1,r)do c2+=1 end
    hand(plastic('LegoCore',Vector3.new((c2-c+1)*S-.03,S-.03,DEPTH[1]-.06),CFrame.new((X(c)+X(c2))/2,Y(r),0),shade(yellow,-.32),{Reflectance=0}))
    c=c2+1
   else c+=1 end
  end
  -- staggered 1x2 bricks, split where the thickness changes
  c=0
  while c<#line do
   if at(c,r)then
    local d=rim(c,r)
    local n=1
    local pair=(c+r)%2==0
    if pair and at(c+1,r)and rim(c+1,r)==d then n=2 end
    local depth=DEPTH[d]+(rnd()-.5)*.07
    local x=X(c)+(n-1)*S*.5
    hand(plastic('LegoBrick',Vector3.new(n*S-.016,S-.016,depth),CFrame.new(x,Y(r),(rnd()-.5)*.012),yel()))
    for k=0,n-1 do front[r*100+c+k]=depth*.5 end
    c+=n
   else c+=1 end
  end
 end
 local function fz(c,r)return front[r*100+math.floor(c+.5)]or front[r*100+math.floor(c)]or .5 end
 -- the highest front face under a sticker of radius rad (cells)
 local function faceZ(c,r,rad)
  local z=0
  for dc=-rad,rad do for dr=-rad,rad do local q=front[(math.floor(r+.5)+dr)*100+math.floor(c+.5)+dc];if q then z=math.max(z,q)end end end
  return z
 end
 -- studs on every upward face (2 across the thickness), the inside of the C included
 for r,line in ipairs(LEGO_HAND)do
  for c=0,#line-1 do
   if at(c,r)and not at(c,r-1)then
    local d=rim(c,r)
    local w=DEPTH[d]*.5
    for _,z in ipairs({-w*.5,w*.5})do hand(studY('LegoStud',CFrame.new(X(c),Y(r)+S*.5,z),.1,yel()))end
   end
  end
 end
 -- loose studs on the front and the back (the sheet's knuckle bumps)
 for _,s in ipairs({{14.5,15},{16,9},{14,6.5},{9,16},{5,4.5},{11.5,3},{7,9}})do
  hand(studZ('LegoFaceStud',CFrame.new(X(s[1]),Y(s[2]),fz(s[1],s[2])),.15,shade(yellow,.03)))
 end
 for _,s in ipairs({{2,13},{2,8},{6,3},{11,3},{15,7},{11,15},{6,16},{16,10},{4,11},{8,5}})do
  hand(studZ('LegoFaceStud',CFrame.new(X(s[1]),Y(s[2]),-fz(s[1],s[2])),.15,shade(yellow,.03),-1))
 end
 -- the thumb's end and the fingertip carry a stud facing out (+X)
 hand(studX('LegoTipStud',CFrame.new(X(15)+S*.5,Y(15),0),.22,shade(yellow,.03)))
 hand(studX('LegoTipStud',CFrame.new(X(17)+S*.5,Y(8),0),.22,shade(yellow,.03)))
 hand(studX('LegoTipStud',CFrame.new(X(0)-S*.5,Y(7),.3),.18,shade(yellow,.03),-1))

 -- STICKERS on the front ------------------------------------------------------------------------
 local function onFront(c,r,rad,dx,dy)return CFrame.new(X(c)+(dx or 0),Y(r)+(dy or 0),faceZ(c,r,rad)+.012)end
 -- the smiley: a pale disc, a black ring, oval eyes, a curved grin
 do
  local F=onFront(3,8.5,2)
  hand(cylZ(model,'LegoSmileyRim',.02,.6,F,ink,SP))
  hand(cylZ(model,'LegoSmiley',.03,.54,F*CFrame.new(0,0,.008),Color3.fromRGB(255,226,72),SP,gloss))
  for s=-1,1,2 do hand(part(model,'LegoSmileyEye',Vector3.new(.05,.1,.02),F*CFrame.new(s*.085,.07,.026),ink,SP))end
  for i=-3,3 do
   local a=math.rad(i*22)
   hand(part(model,'LegoSmileyGrin',Vector3.new(.06,.03,.02),F*CFrame.new(math.sin(a)*.14,-.02-math.cos(a)*.1,.026)*CFrame.Angles(0,0,a),ink,SP))
  end
 end
 -- the red splat with a cheeky face (a white-edged eight-point star)
 do
  local F=onFront(2,12.4,1)*CFrame.Angles(0,0,math.rad(-8))
  for k=0,1 do
   hand(part(model,'LegoSplatEdge',Vector3.new(.38,.38,.02),F*CFrame.Angles(0,0,k*math.pi/4),white,SP))
   hand(part(model,'LegoSplat',Vector3.new(.32,.32,.03),F*CFrame.new(0,0,.006)*CFrame.Angles(0,0,k*math.pi/4),red,SP,gloss))
  end
  for s=-1,1,2 do
   hand(part(model,'LegoSplatEye',Vector3.new(.08,.08,.02),F*CFrame.new(s*.07,.05,.027),white,SP))
   hand(part(model,'LegoSplatEye',Vector3.new(.04,.04,.02),F*CFrame.new(s*.07+.01,.04,.033),ink,SP))
   hand(part(model,'LegoSplatBrow',Vector3.new(.08,.025,.02),F*CFrame.new(s*.07,.11,.03)*CFrame.Angles(0,0,s*math.rad(-20)),shade(red,-.5),SP))
  end
  hand(part(model,'LegoSplatMouth',Vector3.new(.12,.05,.02),F*CFrame.new(0,-.07,.027),shade(red,-.55),SP))
  hand(part(model,'LegoSplatTongue',Vector3.new(.05,.025,.02),F*CFrame.new(.02,-.085,.032),Color3.fromRGB(255,140,150),SP))
 end
 -- the red "LEGO" seal (white edge, cut corners)
 local function seal(F,w,h,name)
  for k=0,1 do
   local cut=k==0 and Vector3.new(w,h-.08,.02)or Vector3.new(w-.08,h,.02)
   hand(part(model,name..'Edge',cut,F,white,SP))
   hand(part(model,name,cut-Vector3.new(.05,.05,-.01),F*CFrame.new(0,0,.006),red,SP,gloss))
  end
  local face=part(model,name..'Text',Vector3.new(w-.1,h-.12,.01),F*CFrame.new(0,0,.017),red,SP,gloss)
  local g=text(face,Enum.NormalId.Back,'LEGO',white,Enum.Font.FredokaOne)
  local l=g:FindFirstChildOfClass('TextLabel');if l then l.TextStrokeTransparency=0;l.TextStrokeColor3=ink end
  return hand(face)
 end
 seal(onFront(5.6,13.4,1)*CFrame.Angles(0,0,math.rad(7)),.5,.36,'LegoSeal')
 -- the white disc sticker by the palm's bottom edge
 do
  local F=onFront(2.2,15.5,1)
  hand(cylZ(model,'LegoDisc',.02,.28,F,white,SP,gloss))
  hand(cylZ(model,'LegoDisc',.02,.17,F*CFrame.new(0,0,.008),Color3.fromRGB(190,192,200),SP))
  hand(cylZ(model,'LegoDisc',.02,.07,F*CFrame.new(0,0,.016),white,SP))
 end
 -- a small seal on the left side (the sheet's side view)
 do
  local r=11
  local c=0;while not at(c,r)do c+=1 end
  local F=CFrame.new(X(c)-S*.5-.012,Y(r)-.05,.05)*CFrame.Angles(0,-math.pi/2,0)
  seal(F,.36,.26,'LegoSideSeal')
 end

 -- WRIST: a yellow stub, the blue band, the red band ----------------------------------------------
 hand(plastic('LegoWristStub',Vector3.new(.46,.2,.46),CFrame.new(0,yb-.09,0),shade(yellow,-.05)))
 local blueY,redY=1.12,.74
 for s=-1,1,2 do
  part(model,'LegoBlueBrick',Vector3.new(.66,.43,.325),CFrame.new(0,blueY,s*.168),s>0 and blue or shade(blue,-.08),SP,gloss)
  part(model,'LegoRedBrick',Vector3.new(.312,.36,.62),CFrame.new(s*.16,redY,0),s>0 and red or shade(red,-.07),SP,gloss)
 end
 for s=-1,1,2 do
  studZ('LegoBandStud',CFrame.new(s*.16,blueY+.02,.33),.17,orange)
  studZ('LegoBandStud',CFrame.new(s*.16,blueY+.02,-.33),.17,shade(blue,.08),-1)
  studZ('LegoBandStud',CFrame.new(s*.15,redY,.31),.15,shade(red,.06))
  studZ('LegoBandStud',CFrame.new(s*.15,redY,-.31),.15,shade(red,.06),-1)
  studX('LegoBandStud',CFrame.new(s*.31,redY,0),.15,shade(red,.06),s)
  -- dark technic pins on both sides of the blue band
  local pin=CFrame.new(s*.33,blueY,0)
  studX('LegoPin',pin,.26,dgrey,s)
  part(model,'LegoPinHole',Vector3.new(.02,.12,.12),pin*CFrame.new(s*.075,0,0),ink,SP,{Shape=Enum.PartType.Cylinder})
 end
 for s=-1,1,2 do for t=-1,1,2 do studY('LegoBandStud',CFrame.new(s*.2,redY+.18,t*.2),.1,shade(red,.06))end end

 -- SHAFT: stacked black 1x2 bricks -----------------------------------------------------------------
 local y0,y1=-1.55,.56
 local n=8;local h=(y1-y0)/n
 for i=0,n-1 do
  local y=y0+h*(i+.5)
  for s=-1,1,2 do
   local c=((i+(s>0 and 1 or 0))%2==0)and black or shade(black,.07)
   if i%2==0 then plastic('LegoShaftBrick',Vector3.new(.245,h-.012,.5),CFrame.new(s*.126,y,0),c)
   else plastic('LegoShaftBrick',Vector3.new(.5,h-.012,.245),CFrame.new(0,y,s*.126),c)end
  end
 end
 -- the vertical "LEGO" logo on the front (white edge, red badge), dark grey studs beside it
 do
  local F=CFrame.new(-.05,-.15,.262)
  part(model,'LegoLogoEdge',Vector3.new(.3,.98,.02),F,white,SP)
  part(model,'LegoLogoEdge',Vector3.new(.22,1.04,.02),F,white,SP)
  part(model,'LegoLogo',Vector3.new(.25,.92,.03),F*CFrame.new(0,0,.005),red,SP,gloss)
  local face=part(model,'LegoLogoText',Vector3.new(.2,.84,.01),F*CFrame.new(0,0,.016),red,SP,gloss)
  local g=text(face,Enum.NormalId.Back,'LEGO',white,Enum.Font.FredokaOne)
  local l=g:FindFirstChildOfClass('TextLabel')
  if l then -- the word runs up the shaft
   l.Size=UDim2.fromScale(4.2,.24);l.AnchorPoint=Vector2.new(.5,.5);l.Position=UDim2.fromScale(.5,.5);l.Rotation=-90
   l.TextStrokeTransparency=0;l.TextStrokeColor3=ink
  end
  for _,y in ipairs({.2,-.52})do studZ('LegoShaftStud',CFrame.new(.17,y,.25),.12,dgrey)end
  studZ('LegoShaftStud',CFrame.new(0,-1.22,.25),.15,blue)
  for _,y in ipairs({.3,-.8})do studZ('LegoShaftStud',CFrame.new(0,y,-.25),.15,shade(blue,-.1),-1)end
  for s=-1,1,2 do studX('LegoShaftStud',CFrame.new(s*.25,.1,0),.13,dgrey,s)end
 end

 -- POMMEL: a yellow 2x2x2 cube, the blue round "C" clip, black end bricks --------------------------
 local pc=CFrame.new(0,-1.78,0)
 part(model,'LegoCubeCore',Vector3.new(.62,.42,.62),pc,shade(yellow,-.32),SP)
 for i=0,7 do
  local sx,sy,sz=(i%2)*2-1,(math.floor(i/2)%2)*2-1,(math.floor(i/4))*2-1
  plastic('LegoCube',Vector3.new(.32,.22,.32),pc*CFrame.new(sx*.165,sy*.112,sz*.165),yel())
 end
 for s=-1,1,2 do for t=-1,1,2 do studY('LegoCubeStud',pc*CFrame.new(s*.2,.225,t*.2),.12,yel())end end
 for s=-1,1,2 do studX('LegoCubeStud',pc*CFrame.new(s*.33,0,0),.2,shade(yellow,.03),s)end
 do -- the blue "C" clip on the front, a blue stud on the back
  local F=pc*CFrame.new(0,0,.33)
  cylZ(model,'LegoClip',.06,.3,F*CFrame.new(0,0,.03),blue,SP,gloss)
  ring(model,'LegoClipRing',F*CFrame.new(0,0,.07),.1,.055,.04,12,shade(blue,.18),SP,function(i)return i==0 or i==11 end,gloss)
  cylZ(model,'LegoClipHole',.02,.09,F*CFrame.new(0,0,.065),shade(blue,-.45),SP)
  studZ('LegoCubeStud',pc*CFrame.new(0,0,-.33),.22,blue,-1)
 end
 plastic('LegoEndBrick',Vector3.new(.5,.13,.5),CFrame.new(.02,-2.065,0),black)
 plastic('LegoEndBrick',Vector3.new(.44,.12,.48),CFrame.new(-.04,-2.19,.01),shade(black,.06))
 for s=-1,1,2 do studZ('LegoEndStud',CFrame.new(s*.12,-2.065,.25),.08,dgrey)end

 -- a soft warm glow and a few idle sparkles round the hand (PickFX LegoGlow)
 local glow=part(model,'LegoGlow',Vector3.new(.4,.4,.4),CFrame.new(X(9),Y(9),0),yellow,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='LegoLight';light.Color=Color3.fromRGB(255,214,110);light.Range=6;light.Brightness=.5;light.Shadows=false;light.Parent=glow
 local sp=emitter(glow,'Sparkle',Color3.fromRGB(255,236,140))
 if sp then
  sp.Name='LegoSparkles';sp.Rate=1.2;sp.Lifetime=NumberRange.new(.6,1.1);sp.Speed=NumberRange.new(.6,1.4)
  sp.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.3,.32),NumberSequenceKeypoint.new(1,0)})
  sp.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,244,170)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,190,40))})
 end

 -- living parts: the hand turns on the wrist, the curled finger also clacks shut (knuckle K)
 local wrist=Vector3.new(0,yb-.09,0)
 local knuckle=Vector3.new(X(6),Y(6),0)
 for _,p in ipairs(handParts)do
  local pos=p.CFrame.Position
  local finger=pos.Y>knuckle.Y-.02 and pos.X>knuckle.X-.05
  anim(p,finger and'LegoFinger'or'LegoHand',0,wrist)
  if finger then p:SetAttribute('PickHang',knuckle-wrist)end
 end

 model:SetAttribute('BackC0',CFrame.new(.15,-.45,.25)) -- the big hand sits clear of the head on the back
 model:SetAttribute('DisplayScale',.8)
 return Vector3.new(X(4),Y(1)+.1,0),Vector3.new(X(16)+.1,Y(15),0)
end

-- Pickaxe 67 ("КИРКА 67" concept sheet, EPIC / MEME-CORE): a meme digit-pickaxe built round a big 6
-- and a big 7, voxel by voxel. HEAD (front +Z, SIX_SEVEN = the sheet's front view, one cell = one voxel):
-- the white 6 on the left (its top hooks over to the right into the 7, a square hole in the bowl) and
-- the glossy black 7 on the right (a thick top bar, the stem running down-left). Every row is laid in
-- staggered 1x2 blocks (slightly uneven whites / blacks, a dark core shows the seams), the rim steps
-- in (voxel bevel), a glowing red seam runs round both digits half-way through (the sheet's side
-- view) and red neon piping traces every front and back edge, the hole included. Voxel spikes (dark
-- red, a glowing tip) stud the crest of the 6 and the top of the 7. On the 6: two yellow smileys, a
-- black skull sticker, black graffiti, a dark "67" tag, scratches and red glowing cracks; on the 7:
-- the red crown graffiti, a big white "67", the red devil-spider tag, a small "67" with a red arrow,
-- scratches; a chrome bracket with bolts joins them (front and back); the back carries its own
-- graffiti (a red X, a smiley, "67"s, a crown). Under the stem of the 7 a dark chain with a white "67"
-- tag in a red-rimmed black frame. HANDLE (top to bottom): a chrome dial ring, a chrome collar with
-- bolts, a red wrap with a white "67" label, a black block with a white inlay and a red crack, a chrome
-- clamp, white / black checker blocks, the long red grip wrapped in black crossed straps, a chrome
-- clamp, a chrome pommel block with bolts on every side, a red glowing band and a gold bottom bolt.
-- SmoothPlastic (white paint / glossy black plastic, a little Reflectance), Metal for chrome and the
-- chain, Neon only for the red glow (seams, piping, spike tips, cracks, graffiti).
-- Moving parts (MiningClient.PickFX): SixDigit6 / SixDigit7 (the digits breathe apart and glitch,
-- jumping a few hundredths sideways for a frame now and then and hard on a hit; PickPhase 6 / 7),
-- SixChain (the chain swings from its eye under the 7, streams back while running, whips on a hit),
-- SixTag (the tag swings with it and spins round on the inspect; PickHang = its centre from the
-- chain's eye), SixDial (the chrome dial ring clicks round on a hit and ratchets on the inspect).
local SIX_SEVEN={ -- top row first; '6' = a voxel of the six, '7' = a voxel of the seven, '.' = empty
 '....666666............',
 '..6666666666..........',
 '.6666...6666..........',
 '6666.....6667777777777',
 '6666......667777777777',
 '6666.........777777777',
 '6666.........777777777',
 '6666.66666.......77777',
 '66666666666......77777',
 '666666666666....77777.',
 '6666....6666....77777.',
 '6666....6666...77777..',
 '6666....6666...77777..',
 '6666....6666..77777...',
 '666666666666..77777...',
 '.66666666666.77777....',
 '..666666666..77777....',
 '....66666.............',
}
DESIGNS.SixSeven=function(model,v,def,len,top)
 local SP,NE,ME=Enum.Material.SmoothPlastic,Enum.Material.Neon,Enum.Material.Metal
 local white,black,red=rgb(v.Head,{242,242,238}),rgb(v.Black,{26,24,28}),rgb(v.Trim,{235,40,52})
 local chrome=rgb(v.Chrome,{206,210,218})
 local glowRed=Color3.fromRGB(255,40,52)
 local darkRed,ink=Color3.fromRGB(140,14,22),Color3.fromRGB(16,14,18)
 local yellow,gold=Color3.fromRGB(255,212,40),Color3.fromRGB(236,186,58)
 local gunmetal=Color3.fromRGB(70,70,78)
 local seed=0
 local function rnd()seed+=1;return(math.sin(seed*12.9898+78.233)*43758.5453)%1 end -- same on every peer
 local function shade(c,k)return c:Lerp(k>0 and Color3.new(1,1,1)or Color3.new(0,0,0),math.abs(k))end
 local function whiteVox()local r=rnd();return r<.4 and white or(r<.7 and shade(white,-.05)or(r<.9 and shade(white,.04)or shade(white,-.11)))end
 local function blackVox()local r=rnd();return r<.4 and black or(r<.7 and shade(black,.05)or(r<.9 and shade(black,-.3)or shade(black,.1)))end
 local chromeProps={Reflectance=.42}
 local six,seven,chain,tag={},{},{},{}
 local function add(list,p)table.insert(list,p);return p end

 -- HEAD: the voxel 6 and 7 ----------------------------------------------------------------------------
 local S=.15
 local rows=#SIX_SEVEN
 local yb=1.0                                          -- bottom of the head
 local function X(c)return(c-10.5)*S end               -- the handle runs up between columns 10 and 11
 local function Y(r)return yb+(rows-r+.5)*S end        -- r = 1 is the top row
 local cell={}
 for r,line in ipairs(SIX_SEVEN)do
  for c=0,#line-1 do local ch=line:sub(c+1,c+1);if ch~='.'then cell[r*100+c]=ch end end
 end
 local function at(c,r,d)return cell[r*100+c]==d end
 -- distance (in cells) to the outside of its own digit: the rim steps in (voxel bevel)
 local function rim(c,r,d)
  for k=1,2 do
   for dc=-k,k do for dr=-k,k do
    if math.abs(dc)+math.abs(dr)<=k and not at(c+dc,r+dr,d)then return k end
   end end
  end
  return 3
 end
 local DEPTH={.72,.84,.9}
 local front={} -- cell -> z of its front face (stickers sit on it)
 for _,d in ipairs({'6','7'})do
  local list=d=='6'and six or seven
  local base=d=='6'and white or black
  for r,line in ipairs(SIX_SEVEN)do
   -- the dark core behind each run (the seams show it) and the glowing red seam through its middle
   local c=0
   while c<#line do
    if at(c,r,d)then
     local c2=c;while at(c2+1,r,d)do c2+=1 end
     local x=(X(c)+X(c2))/2;local w=(c2-c+1)*S
     add(list,part(model,d=='6'and'SixCore'or'SevenCore',Vector3.new(w-.02,S-.02,DEPTH[1]-.05),CFrame.new(x,Y(r),0),d=='6'and shade(white,-.42)or Color3.fromRGB(10,9,12),SP))
     add(list,part(model,'SixSeam',Vector3.new(w+.03,S+.03,.05),CFrame.new(x,Y(r),0),glowRed,NE,{CastShadow=false}))
     c=c2+1
    else c+=1 end
   end
   -- staggered 1x2 blocks, split where the thickness changes
   c=0
   while c<#line do
    if at(c,r,d)then
     local k=rim(c,r,d)
     local n=1
     if (c+r)%2==0 and at(c+1,r,d)and rim(c+1,r,d)==k then n=2 end
     local depth=DEPTH[k]+(k>1 and(rnd()-.5)*.06 or 0)
     local x=X(c)+(n-1)*S*.5
     add(list,part(model,d=='6'and'SixVoxel'or'SevenVoxel',Vector3.new(n*S-.018,S-.018,depth),CFrame.new(x,Y(r),0),
      d=='6'and whiteVox()or blackVox(),SP,{Reflectance=d=='6'and .03 or .1}))
     for j=0,n-1 do front[r*100+c+j]=depth*.5 end
     c+=n
    else c+=1 end
   end
  end
  -- red neon piping along every front / back edge of the digit (runs merged)
  local W=.04
  local zf=DEPTH[1]*.5
  for _,f in ipairs({1,-1})do
   for r=1,rows do -- top / bottom edges, merged along the row
    for _,dr in ipairs({-1,1})do
     local c=0
     while c<22 do
      if at(c,r,d)and not at(c,r+dr,d)then
       local c2=c;while at(c2+1,r,d)and not at(c2+1,r+dr,d)do c2+=1 end
       local y=Y(r)-dr*(S*.5-W*.5)
       add(list,part(model,'SixEdge',Vector3.new((c2-c+1)*S+.01,W,W),CFrame.new((X(c)+X(c2))/2,y,f*zf),glowRed,NE,{CastShadow=false}))
       c=c2+1
      else c+=1 end
     end
    end
   end
   for c=0,21 do -- left / right edges, merged down the column
    for _,dc in ipairs({-1,1})do
     local r=1
     while r<=rows do
      if at(c,r,d)and not at(c+dc,r,d)then
       local r2=r;while at(c,r2+1,d)and not at(c+dc,r2+1,d)do r2+=1 end
       local x=X(c)+dc*(S*.5-W*.5)
       add(list,part(model,'SixEdge',Vector3.new(W,(r2-r+1)*S+.01,W),CFrame.new(x,(Y(r)+Y(r2))/2,f*zf),glowRed,NE,{CastShadow=false}))
       r=r2+1
      else r+=1 end
     end
    end
   end
  end
 end
 for _,p in ipairs(six)do if p.Name=='SixEdge'then p:SetAttribute('SixEdge',true)end end
 for _,p in ipairs(seven)do if p.Name=='SixEdge'then p:SetAttribute('SixEdge',true)end end
 local function fz(c,r)return front[math.floor(r+.5)*100+math.floor(c+.5)]or DEPTH[1]*.5 end
 -- the highest front face under a sticker of radius rad (cells)
 local function faceZ(c,r,rad)
  local z=0
  for dc=-rad,rad do for dr=-rad,rad do local q=front[(math.floor(r+.5)+dr)*100+math.floor(c+.5)+dc];if q then z=math.max(z,q)end end end
  return z>0 and z or DEPTH[1]*.5
 end
 -- a frame on the front (f = 1) or the back (f = -1) face at cell (c, r), facing out
 local function onFace(c,r,rad,f,dx,dy)
  local z=faceZ(c,r,rad)+.012
  local F=CFrame.new(X(c)+(dx or 0),Y(r)+(dy or 0),f*z)
  if f<0 then F=F*CFrame.Angles(0,math.pi,0)end
  return F
 end
 -- a thin flat stroke between two points of a face frame (graffiti, scratches, cracks)
 local function stroke(list,name,F,a,b,w,color,mat,props)
  local A=(F*CFrame.new(a[1],a[2],0)).Position;local B=(F*CFrame.new(b[1],b[2],0)).Position
  local p=bar(model,name,A,B,w,.02,color,mat or SP,props)
  return add(list,p)
 end
 local function poly(list,name,F,pts,w,color,mat,props)
  for i=2,#pts do stroke(list,name,F,pts[i-1],pts[i],w,color,mat,props)end
 end

 -- voxel spikes: three shrinking cubes along dir, a glowing tip (the sheet's red spikes)
 local function spike(list,base,dir,s)
  local R=CFrame.new(base)*alignY(dir)
  add(list,part(model,'SixSpike',Vector3.new(s,s*.8,s),R*CFrame.new(0,s*.3,0),darkRed,SP,{Reflectance=.05}))
  add(list,part(model,'SixSpike',Vector3.new(s*.66,s*.7,s*.66),R*CFrame.new(0,s*.95,0),Color3.fromRGB(214,28,40),SP,{Reflectance=.05}))
  add(list,part(model,'SixSpikeTip',Vector3.new(s*.36,s*.62,s*.36),R*CFrame.new(0,s*1.55,0),glowRed,NE,{CastShadow=false}))
 end
 local zs=.17
 spike(six,Vector3.new(X(4.5),Y(1)+S*.5,zs),Vector3.new(-.4,1,0),.19)
 spike(six,Vector3.new(X(6.5),Y(1)+S*.5,-zs),Vector3.new(-.1,1,0),.21)
 spike(six,Vector3.new(X(8.5),Y(1)+S*.5,zs),Vector3.new(.25,1,0),.2)
 spike(six,Vector3.new(X(2.5),Y(2)+S*.5,-zs),Vector3.new(-.75,.8,0),.18)
 spike(six,Vector3.new(X(1),Y(3)+S*.2,zs),Vector3.new(-1,.55,0),.17)
 spike(six,Vector3.new(X(11)+S*.5,Y(2),-zs),Vector3.new(.8,.75,0),.17)
 spike(six,Vector3.new(X(0)-S*.5,Y(6.5),.05),Vector3.new(-1,.12,0),.16)
 spike(seven,Vector3.new(X(14),Y(4)+S*.5,zs),Vector3.new(-.15,1,0),.18)
 spike(seven,Vector3.new(X(17),Y(4)+S*.5,-zs),Vector3.new(.05,1,0),.2)
 spike(seven,Vector3.new(X(20),Y(4)+S*.5,zs),Vector3.new(.3,1,0),.19)
 spike(seven,Vector3.new(X(21)+S*.5,Y(5.5),0),Vector3.new(1,.25,0),.17)

 -- STICKERS / GRAFFITI on the 6 (front) ---------------------------------------------------------------
 local function smiley(list,F,d)
  add(list,cylZ(model,'SixSmileyRim',.02,d+.05,F,ink,SP))
  add(list,cylZ(model,'SixSmiley',.03,d,F*CFrame.new(0,0,.008),yellow,SP,{Reflectance=.08}))
  for s=-1,1,2 do add(list,part(model,'SixSmileyEye',Vector3.new(d*.1,d*.2,.02),F*CFrame.new(s*d*.17,d*.12,.026),ink,SP))end
  for i=-2,2 do
   local a=math.rad(i*26)
   add(list,part(model,'SixSmileyGrin',Vector3.new(d*.13,d*.06,.02),F*CFrame.new(math.sin(a)*d*.27,-d*.05-math.cos(a)*d*.2,.026)*CFrame.Angles(0,0,a),ink,SP))
  end
 end
 smiley(six,onFace(1.5,6.5,1,1)*CFrame.Angles(0,0,math.rad(-10)),.5)
 smiley(six,onFace(1.6,12.4,1,1)*CFrame.Angles(0,0,math.rad(12)),.38)
 do -- the black skull sticker on the bowl
  local F=onFace(2.6,16,1,1)*CFrame.Angles(0,0,math.rad(-6))
  add(six,cylZ(model,'SixSkullSticker',.02,.36,F,ink,SP))
  add(six,cylZ(model,'SixSkull',.02,.2,F*CFrame.new(0,.03,.01),Color3.fromRGB(236,236,232),SP))
  add(six,part(model,'SixSkullJaw',Vector3.new(.12,.07,.02),F*CFrame.new(0,-.07,.01),Color3.fromRGB(236,236,232),SP))
  for s=-1,1,2 do add(six,part(model,'SixSkullEye',Vector3.new(.05,.05,.02),F*CFrame.new(s*.045,.04,.022),ink,SP))end
  add(six,part(model,'SixSkullTeeth',Vector3.new(.008,.05,.02),F*CFrame.new(0,-.07,.021),ink,SP))
 end
 do -- a dark "67" tag on the bowl's bottom wall
  local F=onFace(7.6,16.1,1,1)*CFrame.Angles(0,0,math.rad(-8))
  local face=add(six,part(model,'SixTagText',Vector3.new(.62,.3,.01),F,shade(white,-.04),SP))
  text(face,Enum.NormalId.Back,'67',ink,Enum.Font.GothamBlack)
 end
 do -- black graffiti strokes, an X, scratches and red glowing cracks
  local F=onFace(7,2.2,1,1)
  poly(six,'SixGraffiti',F,{{-.36,-.03},{-.24,.07},{-.13,-.05},{-.02,.06},{.1,-.04},{.22,.06}},.03,ink)
  local G=onFace(9.6,9.6,1,1)
  stroke(six,'SixGraffiti',G,{-.1,-.1},{.1,.1},.035,ink);stroke(six,'SixGraffiti',G,{-.1,.1},{.1,-.1},.035,ink)
  local H=onFace(9.6,12.5,1,1)
  poly(six,'SixGraffiti',H,{{-.05,.2},{.06,.08},{-.05,-.02},{.06,-.14},{-.02,-.24}},.025,ink)
  local K=onFace(2,9.8,1,1)
  stroke(six,'SixScratch',K,{-.2,.06},{.18,-.08},.012,Color3.fromRGB(150,150,152))
  stroke(six,'SixScratch',K,{-.14,.13},{.2,.02},.01,Color3.fromRGB(160,160,160))
  local L=onFace(1.6,3.6,1,1)
  stroke(six,'SixScratch',L,{-.15,-.05},{.14,.07},.012,Color3.fromRGB(150,150,152))
  local M1=onFace(0.9,14.6,1,1)
  poly(six,'SixCrack',M1,{{-.08,.16},{.02,.06},{-.04,-.04},{.06,-.16}},.025,glowRed,NE,{CastShadow=false})
  local M2=onFace(5.5,8.4,1,1)
  poly(six,'SixCrack',M2,{{-.18,.02},{-.06,-.04},{.04,.03},{.16,-.03}},.022,glowRed,NE,{CastShadow=false})
 end
 -- the inside of the bowl's hole: dark (its rim glows with the piping)
 add(six,part(model,'SixHole',Vector3.new(4*S-.02,4*S-.02,.06),CFrame.new((X(4)+X(7))/2,(Y(11)+Y(14))/2,0),Color3.fromRGB(34,8,12),SP))

 -- STICKERS / GRAFFITI on the 7 (front) ---------------------------------------------------------------
 local function crown(list,F,s)
  local c=Color3.fromRGB(240,34,48)
  add(list,part(model,'SevenCrown',Vector3.new(.44*s,.07*s,.02),F*CFrame.new(0,-.08*s,0),c,NE,{CastShadow=false}))
  for i=-1,1 do
   local h=(i==0 and .22 or .16)*s
   add(list,part(model,'SevenCrown',Vector3.new(.06*s,h,.02),F*CFrame.new(i*.17*s,-.08*s+h*.5,0)*CFrame.Angles(0,0,-i*.25),c,NE,{CastShadow=false}))
   add(list,part(model,'SevenCrown',Vector3.new(.07*s,.07*s,.02),F*CFrame.new(i*.2*s,-.08*s+h+.02*s,0)*CFrame.Angles(0,0,math.rad(45)),c,NE,{CastShadow=false}))
  end
  add(list,part(model,'SevenCrown',Vector3.new(.3*s,.03*s,.02),F*CFrame.new(0,-.15*s,0),c,NE,{CastShadow=false}))
 end
 crown(seven,onFace(14.2,5.6,1,1)*CFrame.Angles(0,0,math.rad(8)),1)
 do -- the big white "67" on the bar
  local F=onFace(18.4,5.6,1,1)*CFrame.Angles(0,0,math.rad(-5))
  local face=add(seven,part(model,'SevenLabel',Vector3.new(.78,.44,.01),F,black,SP))
  text(face,Enum.NormalId.Back,'67',Color3.fromRGB(248,248,246),Enum.Font.GothamBlack)
 end
 do -- the red devil-spider tag on the stem
  local F=onFace(18,11.3,1,1)
  local c=Color3.fromRGB(232,30,44)
  for i=0,5 do
   local a=i/6*math.pi*2;local b=(i+1)/6*math.pi*2
   stroke(seven,'SevenTag',F,{math.cos(a)*.11,math.sin(a)*.1},{math.cos(b)*.11,math.sin(b)*.1},.03,c,NE,{CastShadow=false})
  end
  for s=-1,1,2 do
   stroke(seven,'SevenTag',F,{s*.07,.08},{s*.14,.22},.03,c,NE,{CastShadow=false})            -- horns
   add(seven,part(model,'SevenTag',Vector3.new(.04,.04,.02),F*CFrame.new(s*.045,.02,.004),c,NE,{CastShadow=false})) -- eyes
   for k=0,2 do stroke(seven,'SevenTag',F,{s*.1,-.02-k*.04},{s*(.22+k*.02),-.06-k*.08+(k==0 and .06 or 0)},.022,c,NE,{CastShadow=false})end -- legs
  end
 end
 do -- the small white "67" near the foot of the stem and the red arrow above it
  local F=onFace(15.6,15.6,1,1)*CFrame.Angles(0,0,math.rad(6))
  local face=add(seven,part(model,'SevenSmallLabel',Vector3.new(.44,.26,.01),F,black,SP))
  text(face,Enum.NormalId.Back,'67',Color3.fromRGB(240,240,238),Enum.Font.GothamBlack)
  local A=onFace(17.3,13.5,1,1)*CFrame.Angles(0,0,math.rad(-24))
  local c=Color3.fromRGB(232,30,44)
  stroke(seven,'SevenArrow',A,{0,-.14},{0,.12},.03,c,NE,{CastShadow=false})
  stroke(seven,'SevenArrow',A,{0,.13},{-.07,.05},.03,c,NE,{CastShadow=false})
  stroke(seven,'SevenArrow',A,{0,.13},{.07,.05},.03,c,NE,{CastShadow=false})
 end
 do -- scratches on the black
  local F=onFace(16,6.6,1,1)
  stroke(seven,'SevenScratch',F,{-.3,.02},{.05,-.07},.012,Color3.fromRGB(120,118,126))
  stroke(seven,'SevenScratch',F,{-.22,-.04},{.1,-.12},.01,Color3.fromRGB(104,102,110))
  local G=onFace(18.8,9.4,1,1)
  stroke(seven,'SevenScratch',G,{-.08,.12},{.1,-.1},.012,Color3.fromRGB(120,118,126))
  local K=onFace(14.8,14.6,1,1)
  poly(seven,'SevenCrack',K,{{-.04,.12},{.03,.03},{-.02,-.05},{.05,-.13}},.022,glowRed,NE,{CastShadow=false})
 end

 -- THE BACK (its own graffiti, mirrored like the sheet's back view) -------------------------------------
 do
  local F=onFace(2,10.5,1,-1)
  stroke(six,'SixGraffiti',F,{-.16,-.16},{.16,.16},.05,Color3.fromRGB(232,30,44),NE,{CastShadow=false})
  stroke(six,'SixGraffiti',F,{-.16,.16},{.16,-.16},.05,Color3.fromRGB(232,30,44),NE,{CastShadow=false})
  smiley(six,onFace(1.6,5.5,1,-1)*CFrame.Angles(0,0,math.rad(14)),.4)
  local face=add(six,part(model,'SixTagText',Vector3.new(.62,.3,.01),onFace(6.4,16.1,1,-1)*CFrame.Angles(0,0,math.rad(7)),shade(white,-.04),SP))
  text(face,Enum.NormalId.Back,'67',ink,Enum.Font.GothamBlack)
  poly(six,'SixGraffiti',onFace(7,2.2,1,-1),{{-.3,.05},{-.18,-.05},{-.05,.06},{.08,-.05},{.2,.05}},.03,ink)
  local G=onFace(17.8,5.6,1,-1)*CFrame.Angles(0,0,math.rad(4))
  local lab=add(seven,part(model,'SevenLabel',Vector3.new(.78,.44,.01),G,black,SP))
  text(lab,Enum.NormalId.Back,'67',Color3.fromRGB(248,248,246),Enum.Font.GothamBlack)
  crown(seven,onFace(14.4,5.6,1,-1)*CFrame.Angles(0,0,math.rad(-8)),.85)
  local K=onFace(16.6,12,1,-1)
  poly(seven,'SevenCrack',K,{{-.05,.14},{.04,.04},{-.03,-.05},{.05,-.15}},.022,glowRed,NE,{CastShadow=false})
 end

 -- the chrome bracket where the hook of the 6 meets the bar of the 7 (front and back)
 for _,f in ipairs({1,-1})do
  local F=CFrame.new(X(11.5),Y(4.5),f*(DEPTH[2]*.5+.03))
  part(model,'SixBracket',Vector3.new(.36,.3,.05),F,chrome,ME,chromeProps)
  for s=-1,1,2 do part(model,'SixBolt',Vector3.new(.03,.08,.08),F*CFrame.new(s*.11,0,f*.03)*CFrame.Angles(0,math.pi/2,0),gunmetal,ME,{Shape=Enum.PartType.Cylinder,Reflectance=.2})end
 end
 -- a chrome socket where the handle meets the head
 part(model,'SixSocket',Vector3.new(.42,.3,.5),CFrame.new(.08,yb+.3,0),chrome,ME,chromeProps)

 -- THE CHAIN AND THE "67" TAG under the stem of the 7 ---------------------------------------------------
 local eye=Vector3.new(X(15),Y(17)-S*.5,0)
 part(model,'SixChainEye',Vector3.new(.14,.08,.14),CFrame.new(eye+Vector3.new(0,-.02,0)),chrome,ME,chromeProps)
 local y=eye.Y-.08
 for k=0,4 do
  local cy=y-.07-k*.12
  local w,h,t=.11,.16,.03
  local turn=k%2==0 and CFrame.identity or CFrame.Angles(0,math.pi/2,0)
  local C=CFrame.new(eye.X,cy,0)*turn
  for s=-1,1,2 do
   add(chain,part(model,'SixChainLink',Vector3.new(t,h,t),C*CFrame.new(s*(w*.5-t*.5),0,0),gunmetal,ME,{Reflectance=.25}))
   add(chain,part(model,'SixChainLink',Vector3.new(w,t,t),C*CFrame.new(0,s*(h*.5-t*.5),0),gunmetal,ME,{Reflectance=.25}))
  end
 end
 local tc=Vector3.new(eye.X,y-.07-4*.12-.08-.27,0)
 local T=CFrame.new(tc)
 add(tag,cylZ(model,'SixTagRing',.08,.1,T*CFrame.new(0,.27,0),chrome,ME,chromeProps))
 add(tag,part(model,'SixTagRim',Vector3.new(.48,.52,.04),T,glowRed,NE,{CastShadow=false}))
 add(tag,part(model,'SixTagFrame',Vector3.new(.44,.48,.08),T,Color3.fromRGB(24,22,26),SP,{Reflectance=.1}))
 for _,f in ipairs({1,-1})do
  local face=add(tag,part(model,'SixTagFace',Vector3.new(.34,.38,.02),T*CFrame.new(0,-.01,f*.045),Color3.fromRGB(240,240,236),SP))
  text(face,f>0 and Enum.NormalId.Back or Enum.NormalId.Front,'67',ink,Enum.Font.GothamBlack)
  for s=-1,1,2 do add(tag,part(model,'SixTagRivet',Vector3.new(.04,.04,.02),T*CFrame.new(s*.16,.19,f*.05),chrome,ME,chromeProps))end
 end

 -- HANDLE ---------------------------------------------------------------------------------------------
 local function bolt(F,d)return part(model,'SixBolt',Vector3.new(.04,d or .09,d or .09),F*CFrame.Angles(0,math.pi/2,0),gunmetal,ME,{Shape=Enum.PartType.Cylinder,Reflectance=.25})end
 local function boltX(F,s,d)return part(model,'SixBolt',Vector3.new(.04,d or .09,d or .09),F*CFrame.new(s*.02,0,0),gunmetal,ME,{Shape=Enum.PartType.Cylinder,Reflectance=.25})end
 local function clamp(name,y0,y1,w)
  local h=y1-y0;local cy=(y0+y1)/2
  part(model,name,Vector3.new(w,h,w),CFrame.new(0,cy,0),chrome,ME,chromeProps)
  part(model,name..'Lip',Vector3.new(w+.04,.05,w+.04),CFrame.new(0,y1-.03,0),shade(chrome,-.12),ME,chromeProps)
  for _,f in ipairs({1,-1})do for s=-1,1,2 do bolt(CFrame.new(s*w*.27,cy,f*(w*.5+.02)))end end
 end
 -- the dial ring (it turns) and the collar under the head
 local dial={}
 for i=0,7 do
  local a=i/8*math.pi*2
  table.insert(dial,part(model,'SixDial',Vector3.new(.22,.13,.09),CFrame.new(0,1.075,0)*CFrame.Angles(0,a,0)*CFrame.new(0,0,.25),i%2==0 and chrome or shade(chrome,-.15),ME,chromeProps))
 end
 for _,a in ipairs({0,math.pi})do
  table.insert(dial,part(model,'SixDialMark',Vector3.new(.04,.09,.02),CFrame.new(0,1.075,0)*CFrame.Angles(0,a,0)*CFrame.new(0,0,.3),glowRed,NE,{CastShadow=false}))
 end
 part(model,'SixDialCore',Vector3.new(.42,.13,.42),CFrame.new(0,1.075,0),shade(chrome,-.35),ME)
 clamp('SixCollar',.72,1.01,.56)
 -- upper red wrap with a white "67" label
 for i=0,2 do
  part(model,'SixWrap',Vector3.new(i%2==0 and .44 or .42,.14,i%2==0 and .44 or .42),CFrame.new(0,.37+i*.14,0),i%2==0 and red or Color3.fromRGB(176,18,28),SP,{Reflectance=.05})
 end
 for _,f in ipairs({1,-1})do
  local face=part(model,'SixHandleLabel',Vector3.new(.26,.2,.01),CFrame.new(0,.51,f*.226)*(f<0 and CFrame.Angles(0,math.pi,0)or CFrame.identity),red,SP)
  text(face,Enum.NormalId.Back,'67',Color3.fromRGB(248,248,246),Enum.Font.GothamBlack)
 end
 -- a black block with a white inlay and a red crack
 part(model,'SixHandleBlock',Vector3.new(.42,.2,.42),CFrame.new(0,.2,0),black,SP,{Reflectance=.1})
 part(model,'SixInlay',Vector3.new(.1,.1,.02),CFrame.new(-.08,.2,.215),Color3.fromRGB(240,240,236),SP)
 part(model,'SixHandleCrack',Vector3.new(.025,.16,.02),CFrame.new(.1,.2,.215)*CFrame.Angles(0,0,.4),glowRed,NE,{CastShadow=false})
 clamp('SixClamp',-.12,.1,.5)
 -- white / black checker blocks (2 x 2 x 2)
 for i=0,7 do
  local sx,sy,sz=(i%2)*2-1,math.floor(i/2)%2,(math.floor(i/4))*2-1
  local wht=((i%2)+sy+math.floor(i/4))%2==0
  part(model,'SixChecker',Vector3.new(.21,.235,.21),CFrame.new(sx*.105,-.24-sy*.24,sz*.105),wht and whiteVox()or blackVox(),SP,{Reflectance=wht and .03 or .1})
 end
 part(model,'SixHandleCrack',Vector3.new(.022,.2,.02),CFrame.new(-.1,-.48,-.212)*CFrame.Angles(0,0,-.35),glowRed,NE,{CastShadow=false})
 -- the long red grip, wrapped in black crossed straps
 local g0,g1=-1.85,-.6
 local n=10;local gh=(g1-g0)/n
 for i=0,n-1 do
  local wide=i%2==0
  part(model,'SixGrip',Vector3.new(wide and .44 or .42,gh-.006,wide and .44 or .42),CFrame.new(0,g0+gh*(i+.5),0),wide and red or Color3.fromRGB(176,18,28),SP,{Reflectance=.04})
 end
 for _,f in ipairs({1,-1})do
  for k=0,2 do
   local cy=g0+.22+k*.4
   for s=-1,1,2 do
    bar(model,'SixStrap',Vector3.new(-.17*s,cy-.16,f*.228),Vector3.new(.17*s,cy+.16,f*.228),.05,.02,ink,SP)
   end
  end
 end
 clamp('SixClamp',-2.07,-1.85,.5)
 -- the chrome pommel: bolts on every side, a red glowing band, a gold bolt underneath
 local pc=CFrame.new(0,-2.29,0)
 part(model,'SixPommel',Vector3.new(.54,.38,.44),pc,chrome,ME,chromeProps)
 part(model,'SixPommel',Vector3.new(.44,.38,.54),pc,chrome,ME,chromeProps)
 part(model,'SixPommelCap',Vector3.new(.46,.06,.46),pc*CFrame.new(0,.21,0),shade(chrome,-.12),ME,chromeProps)
 part(model,'SixPommelBand',Vector3.new(.56,.05,.56),pc*CFrame.new(0,-.06,0),glowRed,NE,{CastShadow=false})
 for _,f in ipairs({1,-1})do
  bolt(pc*CFrame.new(0,.06,f*.28),.12)
  boltX(pc*CFrame.new(f*.28,.06,0),f,.12)
 end
 cylY(model,'SixPommelBolt',.06,.2,pc*CFrame.new(0,-.22,0),gold,ME,{Reflectance=.3})
 cylY(model,'SixPommelBolt',.04,.09,pc*CFrame.new(0,-.26,0),Color3.fromRGB(150,110,30),ME)

 -- the red glow of the head and a few idle sparks (PickFX SixGlow)
 local glow=part(model,'SixGlow',Vector3.new(.4,.4,.4),CFrame.new(X(10.5),Y(9),0),red,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='SixLight';light.Color=Color3.fromRGB(255,56,64);light.Range=7;light.Brightness=.9;light.Shadows=false;light.Parent=glow
 local sp=emitter(glow,'Sparkle',Color3.fromRGB(255,80,90))
 if sp then
  sp.Name='SixSparks';sp.Rate=1.2;sp.Lifetime=NumberRange.new(.6,1.1);sp.Speed=NumberRange.new(.6,1.4)
  sp.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.3,.3),NumberSequenceKeypoint.new(1,0)})
  sp.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,236,236)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,30,44))})
 end

 -- living parts
 for _,p in ipairs(six)do anim(p,'SixDigit6',6)end
 for _,p in ipairs(seven)do anim(p,'SixDigit7',7)end
 for _,p in ipairs(chain)do anim(p,'SixChain',0,eye)end
 for _,p in ipairs(tag)do anim(p,'SixTag',0,eye);p:SetAttribute('PickHang',tc-eye)end
 for _,p in ipairs(dial)do anim(p,'SixDial',0,Vector3.new(0,1.075,0))end

 model:SetAttribute('HandTilt',16) -- in the hand the head leans a little forward (out in front of the holder, into the first-person view)
 model:SetAttribute('BackC0',CFrame.new(.15,-.45,.25)) -- the big head sits clear of the head on the back
 model:SetAttribute('DisplayScale',.8)
 return Vector3.new(X(0)-.1,Y(4),0),Vector3.new(X(21)+.2,Y(5.5),0)
end

-- Gummy Horror ("Кирка Мармеладный ужас", EPIC concept sheet): a living gummy monster on a stick.
-- Front (+Z): one huge lemon eye with a lime iris under a pink lid, a wide mouth of candy fangs
-- (cream, caramel roots) with lime drool. Two glossy gummy horns arch out of the head and droop
-- down into sharp points (the left one fades pink -> caramel -> lime, the right one stays pink with
-- a lemon tip), lime / lemon under-layers, candy cubes stuck on top and drips hanging everywhere.
-- The stick is wrapped in crossing pink / lime gummy worms with a pink and a green gummy bear stuck
-- to it; a lumpy lemon-pink pommel with caramel holes at the bottom. Glass (glossy candy) for the
-- gummy, translucent Glass for drips, tips and bears, Neon only for the inner glow.
-- Moving parts (MiningClient.PickFX): GummyWobble (whole head jiggles), GummyArm (horns bend from
-- the root, PickAmp = signed share along the horn), GummyEye / GummyLidTop / GummyLidBot (look,
-- blink, squint), GummyJaw (chew, chomp on a hit, chomps on inspect), GummyDrop (drops stretch on
-- PickDropK necks and fall, PickGoo fades them).
local function spike(model,name,base,dir,normal,length,width,thick,color,mat,props)
 -- a flat pointed tip from base along dir (two mirrored wedges), broad side across normal
 local T=dir.Unit;local out={}
 for _,s in ipairs({1,-1})do
  local Y=normal.Unit*s;local Z=-T;local X=Y:Cross(Z)
  local pos=base+T*length*.5+Y*width*.25
  table.insert(out,wedge(model,name,Vector3.new(thick,width*.5,length),CFrame.fromMatrix(pos,X,Y,Z),color,mat,props))
 end
 return out
end
DESIGNS.Gummy=function(model,v,def,len,top)
 local pink=rgb(v.Head)                          -- hot pink gummy
 local lime=rgb(v.Accent)                        -- sour lime
 local lemon=rgb(v.Trim)                         -- lemon yellow
 local pale=Color3.fromRGB(255,150,206)          -- pale pink (gloss, palette)
 local deep=pink:Lerp(Color3.fromRGB(150,0,80),.35)
 local cream=Color3.fromRGB(252,242,218)
 local caramel=Color3.fromRGB(255,158,40)
 local olive=Color3.fromRGB(112,148,30)
 local gum=Color3.fromRGB(96,6,48)
 local GL,SP,NE=Enum.Material.Glass,Enum.Material.SmoothPlastic,Enum.Material.Neon
 local clear={Transparency=.18,Reflectance=.06}
 local gloss={Transparency=.45,CastShadow=false}
 local hc=CFrame.new(0,len*.5+.3,0)               -- the monster head's centre
 local hp=hc.Position
 local function at(x,y,z)return hc*CFrame.new(x,y,z)end
 local function wob(p,extra,phase,joint)
  return anim(p,'GummyWobble'..(extra and(','..extra)or''),phase or 0,joint or hp)
 end
 -- a hanging drip: a neck and a round drop, straight down from top (model space)
 local function drip(name,top,length,d,color,kind,amp,joint)
  local neck=blob(model,name,Vector3.new(d*.8,length*1.1,d*.8),CFrame.new(top-Vector3.new(0,length*.45,0)),color,GL,clear)
  local drop=blob(model,name..'Drop',Vector3.new(d*1.05,d*1.25,d*1.05),CFrame.new(top-Vector3.new(0,length,0)),color,GL,clear)
  local cap=blob(model,name,Vector3.new(d*1.3,d*.9,d*1.3),CFrame.new(top-Vector3.new(0,d*.15,0)),color,GL)
  if kind then
   for _,p in ipairs({neck,drop,cap})do anim(p,kind,0,joint);if amp then p:SetAttribute('PickAmp',amp)end end
  end
  return neck,drop,cap
 end

 -- HEAD: lumpy pink skull --------------------------------------------------------------------
 wob(blob(model,'GummySkull',Vector3.new(1.84,1.5,1.16),at(0,-.04,0),pink,GL))
 wob(blob(model,'GummySkull',Vector3.new(1.2,.7,.8),at(0,.22,-.36),pink,GL))
 for _,s in ipairs({-1,1})do
  wob(blob(model,'GummyCheek',Vector3.new(.78,.8,.9),at(s*.62,-.18,.06),deep,GL))
  wob(blob(model,'GummyLump',Vector3.new(.55,.5,.6),at(s*.5,.5,-.28),pink,GL))
 end
 wob(blob(model,'GummyBack',Vector3.new(1.2,1.0,.6),at(0,-.05,-.42),deep,GL))
 wob(blob(model,'Gloss',Vector3.new(.5,.12,.3),at(-.42,.66,.18)*CFrame.Angles(0,0,.35),pale,SP,gloss))
 -- slime coating running down the head
 wob(blob(model,'SlimeCoat',Vector3.new(.5,.7,.5),at(-.72,-.42,.18),lime,GL,{Transparency=.12}))
 wob(blob(model,'SlimeCoat',Vector3.new(.42,.5,.4),at(.74,-.38,.12),lemon,GL,{Transparency=.12}))
 wob(blob(model,'SlimeCoat',Vector3.new(.6,.32,.5),at(.55,.18,-.38),lime,GL,{Transparency=.12}))
 local core=wob(ball(model,'GummyCore',.7,at(0,0,-.05),pink,NE,{CastShadow=false,Transparency=.3}))
 core:SetAttribute('PickPulse',true)
 local light=Instance.new('PointLight');light.Name='GummyGlow';light.Color=Color3.fromRGB(255,80,190);light.Range=7;light.Brightness=.75;light.Shadows=false;light.Parent=core

 -- EYE: lemon ball, lime iris, black pupil, glint; pink lids ------------------------------------
 local E=at(0,.5,.4);local D=1.0
 wob(blob(model,'EyeSocket',Vector3.new(1.3,1.22,.62),E*CFrame.new(0,-.02,-.16),deep,GL))
 local ej=E.Position
 wob(ball(model,'Eye',D,E,Color3.fromRGB(255,224,46),GL),'GummyEye',0,ej)
 wob(blob(model,'EyeIrisRing',Vector3.new(.6,.6,.1),E*CFrame.new(0,0,D*.43),olive,GL),'GummyEye',0,ej)
 wob(blob(model,'EyeIris',Vector3.new(.54,.54,.12),E*CFrame.new(0,0,D*.45),lime,GL),'GummyEye',0,ej)
 wob(blob(model,'EyePupil',Vector3.new(.2,.34,.08),E*CFrame.new(0,0,D*.51),Color3.fromRGB(14,10,16),SP),'GummyEye',0,ej)
 wob(ball(model,'EyeGlint',.12,E*CFrame.new(.11,.12,D*.52),Color3.new(1,1,1),NE,{CastShadow=false}),'GummyEye',0,ej)
 wob(blob(model,'EyeLidTop',Vector3.new(1.12,.34,.78),E*CFrame.new(0,.44,.02),pink,GL),'GummyLidTop',0,ej)
 wob(blob(model,'EyeLidTop',Vector3.new(.5,.07,.24),E*CFrame.new(-.14,.56,.28)*CFrame.Angles(0,0,.2),pale,SP,gloss),'GummyLidTop',0,ej)
 wob(blob(model,'EyeLidBot',Vector3.new(1.1,.34,.74),E*CFrame.new(0,-.47,.06),pink,GL),'GummyLidBot',0,ej)

 -- MOUTH: dark gums, cream candy fangs with caramel roots, a hinged lower jaw, lime drool -------
 local M=at(0,-.46,.5)
 wob(blob(model,'MouthInside',Vector3.new(1.42,.66,.4),M*CFrame.new(0,-.06,-.06),gum,SP))
 wob(blob(model,'LipTop',Vector3.new(1.6,.26,.46),M*CFrame.new(0,.22,.02),pink,GL))
 local fangs={{-.58,.19,.46},{-.36,.16,.36},{-.13,.14,.28},{.11,.14,.3},{.34,.16,.38},{.57,.2,.48}}
 for _,f in ipairs(fangs)do
  local root=(M*CFrame.new(f[1],.12,.13)).Position
  wob(ball(model,'FangRoot',f[2]*1.05,CFrame.new(root),Color3.fromRGB(255,196,130),SP))
  for _,w in ipairs(spike(model,'Fang',root,Vector3.new(f[1]*.12,-1,.12),Vector3.new(1,0,0),f[3],f[2],f[2]*.8,cream,SP,{Reflectance=.12}))do wob(w)end
 end
 local hinge=(M*CFrame.new(0,.05,-.45)).Position
 local function jaw(p)return wob(p,'GummyJaw',0,hinge)end
 jaw(blob(model,'Jaw',Vector3.new(1.5,.42,.78),M*CFrame.new(0,-.4,-.12),pink,GL))
 jaw(blob(model,'LipBottom',Vector3.new(1.44,.22,.4),M*CFrame.new(0,-.3,.06),deep,GL))
 for i,x in ipairs({-.46,-.22,.04,.28,.5})do
  local root=(M*CFrame.new(x,-.26,.12)).Position
  local h=i%2==0 and .22 or .3
  for _,w in ipairs(spike(model,'Tooth',root,Vector3.new(-x*.1,1,.1),Vector3.new(1,0,0),h,.16,.13,cream,SP,{Reflectance=.12}))do jaw(w)end
 end
 for _,x in ipairs({-.27,.21})do -- sticky saliva threads across the mouth
  jaw(blob(model,'Drool',Vector3.new(.06,.36,.06),M*CFrame.new(x,-.02,.1),lime,GL,{Transparency=.15}))
 end
 do
  for _,p in ipairs({drip('DroolDrip',(M*CFrame.new(-.38,-.52,.16)).Position,.4,.17,lime)})do jaw(p)end
  for _,p in ipairs({drip('DroolDrip',(M*CFrame.new(.46,-.5,.1)).Position,.26,.14,lemon)})do jaw(p)end
 end
 -- an animated drool drop (stretches on its neck, falls, comes back)
 local dropTop=(M*CFrame.new(.08,-.58,.2)).Position
 for i,f in ipairs({.33,.66,1})do
  local p=i<3 and blob(model,'DroolNeck',Vector3.new(.08,.18,.08),CFrame.new(dropTop-Vector3.new(0,.06*i,0)),lime,GL,clear)
   or ball(model,'DroolDrop',.17,CFrame.new(dropTop-Vector3.new(0,.18,0)),lime,GL,clear)
  anim(p,'GummyDrop',.15,dropTop);p:SetAttribute('PickDropK',f)
  if i==3 then p:SetAttribute('PickGoo',true)end
 end

 -- HORNS: glossy gummy arches drooping into points ---------------------------------------------
 local function bez(p0,p1,p2,p3,t)local u=1-t;return p0*u*u*u+p1*3*u*u*t+p2*3*u*t*t+p3*t*t*t end
 local tips={}
 local N=14
 for _,side in ipairs({-1,1})do
  local P0,P1,P2,P3=hp+Vector3.new(side*.5,.12,0),hp+Vector3.new(side*1.6,.8,0),hp+Vector3.new(side*2.6,.35,0),hp+Vector3.new(side*2.28,-1.3,0)
  local function pt(t)return bez(P0,P1,P2,P3,math.clamp(t,0,1))end
  local root=P0
  local function horn(p,amp,extra)
   anim(p,'GummyWobble,GummyArm'..(extra and(','..extra)or''),0,root);p:SetAttribute('PickAmp',side*amp);return p
  end
  local seg=0;for i=1,40 do seg+=(pt(i/40)-pt((i-1)/40)).Magnitude end;seg=seg/N
  local frames={}
  for i=1,N do
   local t=(i-.5)/N
   local pos=pt(t);local tan=(pt(t+.01)-pt(t-.01)).Unit
   local X=tan*side;local Y=Vector3.zAxis:Cross(X).Unit
   local cf=CFrame.fromMatrix(pos,X,Y,Vector3.zAxis)
   local th=.82+(.16-.82)*t^1.25;local dp=.72+(.22-.72)*t^1.1
   frames[i]={CF=cf,T=t,Th=th,Dp=dp,Pos=pos,Tan=tan,N=Y}
   -- top layer: pink, the left horn turns caramel then lime towards its point
   local topCol=pink
   if side<0 then
    if t>.5 then topCol=t<.75 and pink:Lerp(caramel,(t-.5)/.25)or caramel:Lerp(lime,(t-.75)/.25)end
   elseif t>.72 then topCol=pink:Lerp(lemon,(t-.72)/.28)end
   horn(part(model,'Horn',Vector3.new(seg*1.32,th,dp),cf,topCol,GL),t)
   local underCol=(side<0 and lemon or lime):Lerp(side<0 and lime or lemon,t)
   horn(part(model,'HornUnder',Vector3.new(seg*1.3,th*.46,dp*.86),cf*CFrame.new(0,-th*.4,0),underCol,GL),t)
   if i%2==1 and t<.85 then
    horn(part(model,'Gloss',Vector3.new(seg*1.1,.05,dp*.34),cf*CFrame.new(0,th*.5+.01,dp*.16),pale,SP,gloss),t)
   end
   if i<=N-3 and i%3==1 then -- gummy bulges on top
    horn(blob(model,'HornLump',Vector3.new(seg*1.6,th*.55,dp*.9),cf*CFrame.new(0,th*.38,0),topCol,GL),t)
   end
   if i<=6 then -- inner glow (shows through the candy at the root)
    local g=horn(part(model,'HornGlow',Vector3.new(seg*1.2,th*.3,.05),cf*CFrame.new(0,0,dp*.5+.01),Color3.fromRGB(255,110,200),NE,{CastShadow=false,Transparency=.55}),t)
    g:SetAttribute('PickPulse',true)
   end
  end
  -- the point
  local last=frames[N]
  local tipBase=last.Pos+last.Tan*seg*.5
  local tipCol=side<0 and lime or lemon
  for _,w in ipairs(spike(model,'HornTip',tipBase,last.Tan,last.N,.62,last.Th*1.05,last.Dp,tipCol,GL,{Transparency=.12}))do horn(w,1)end
  tips[side]=tipBase+last.Tan*.62
  -- candy cubes stuck on top
  local candies=side<0 and{{3,lemon},{6,lime},{9,pale}}or{{2,lime},{5,lemon},{8,caramel},{11,pale}}
  for k,cd in ipairs(candies)do
   local f=frames[cd[1]]
   local s=.2+(k%2)*.06
   horn(part(model,'Candy',Vector3.new(s,s,s),f.CF*CFrame.new((k%2==0 and .05 or -.05),f.Th*.52+s*.3,(k%3-1)*.12)*CFrame.Angles(.5,.7*k,.4),cd[2],GL,{Reflectance=.15}),f.T)
  end
  -- drips hanging from the underside (they bend with the horn)
  local drips=side<0 and{{2,.5,pink},{4,.32,lime},{5,.75,lemon},{7,.45,pink},{9,.62,lime},{11,.36,caramel},{13,.3,lemon}}
   or{{2,.42,lime},{3,.7,pink},{5,.38,lemon},{7,.8,pink},{9,.5,lime},{10,.3,pale},{12,.44,pink}}
  for _,dd in ipairs(drips)do
   local f=frames[dd[1]]
   local under=f.Pos-f.N*f.Th*.42
   for _,p in ipairs({drip('HornDrip',under,dd[2],.16+dd[2]*.1,dd[3])})do horn(p,f.T)end
  end
  -- one live drop per horn
  local f=frames[side<0 and 6 or 8]
  local dt=f.Pos-f.N*f.Th*.42
  for i,k in ipairs({.33,.66,1})do
   local p=i<3 and blob(model,'HornNeck',Vector3.new(.09,.2,.09),CFrame.new(dt-Vector3.new(0,.07*i,0)),side<0 and lemon or pink,GL,clear)
    or ball(model,'HornLiveDrop',.19,CFrame.new(dt-Vector3.new(0,.2,0)),side<0 and lemon or pink,GL,clear)
   horn(p,f.T,'GummyDrop');p:SetAttribute('PickDropK',k);p:SetAttribute('PickPhase',side<0 and .45 or .8)
   if i==3 then p:SetAttribute('PickGoo',true)end
  end
 end

 -- COLLAR: slime pouring off the head down the stick -------------------------------------------
 local cy=hp.Y-.78
 blob(model,'Collar',Vector3.new(.8,.46,.8),CFrame.new(0,cy,0),lime,GL)
 blob(model,'Collar',Vector3.new(.66,.5,.66),CFrame.new(.05,cy-.3,.02),pink,GL)
 for i,a in ipairs({.4,1.9,3.3,4.8})do
  local top=Vector3.new(math.cos(a)*.27,cy-.3,math.sin(a)*.27)
  drip('CollarDrip',top,.3+(i%2)*.32,.15,i%2==0 and lime or pink)
 end

 -- STICK: wood core, crossing gummy worms, bears ------------------------------------------------
 local sTop,sBot=cy-.3,-len*.5+.05
 cylY(model,'GummyStick',sTop-sBot,.46,CFrame.new(0,(sTop+sBot)*.5,0),rgb(v.Shaft),Enum.Material.Wood)
 local function helix(name,color,d,turns,phase,y0,y1,segments,r)
  local prev
  for i=0,segments do
   local t=i/segments;local a=phase+t*turns*math.pi*2
   local q=Vector3.new(math.cos(a)*r,y0+(y1-y0)*t,math.sin(a)*r)
   if prev then local dir=(q-prev).Unit;rod(model,name,prev-dir*d*.35,q+dir*d*.35,d,color,GL)end
   prev=q
  end
 end
 helix('GummyWorm',pink,.2,2.6,0,sTop,sBot+.25,20,.25)
 helix('GummyWorm',lime,.19,-2.6,math.pi,sTop-.1,sBot+.3,20,.25)
 helix('GummyWorm',lemon,.1,1.4,1.6,sTop-.2,sBot+.6,10,.27)
 for i,y in ipairs({.9,-.2,-1.25})do ball(model,'GummyBead',.2,CFrame.new(math.cos(i*2.1)*.3,y,math.sin(i*2.1)*.3),i==2 and lemon or lime,GL)end
 local function bear(cf,color,name)
  local bp={Transparency=.14,Reflectance=.08}
  local light2=color:Lerp(Color3.new(1,1,1),.3)
  blob(model,name,Vector3.new(.34,.4,.24),cf,color,GL,bp)
  ball(model,name,.3,cf*CFrame.new(0,.3,0),color,GL,bp)
  for _,s in ipairs({-1,1})do
   ball(model,name,.12,cf*CFrame.new(s*.11,.44,0),color,GL,bp)
   blob(model,name,Vector3.new(.11,.2,.11),cf*CFrame.new(s*.18,.06,.04)*CFrame.Angles(0,0,s*.6),color,GL,bp)
   blob(model,name,Vector3.new(.13,.17,.13),cf*CFrame.new(s*.1,-.2,.05),color,GL,bp)
  end
  blob(model,name,Vector3.new(.14,.09,.08),cf*CFrame.new(0,.26,.13),light2,GL,bp)
  blob(model,name,Vector3.new(.14,.18,.04),cf*CFrame.new(0,.02,.11),light2,GL,{Transparency=.3})
 end
 bear(CFrame.new(.14,-.75,.36)*CFrame.Angles(0,.25,-.15),Color3.fromRGB(255,96,180),'GummyBear')
 bear(CFrame.new(-.16,.45,.35)*CFrame.Angles(0,-.3,.2)*CFrame.new(0,0,0),Color3.fromRGB(150,230,60),'GummyBearGreen')

 -- POMMEL: lumpy lemon-pink gummy with caramel holes -------------------------------------------
 local py=-len*.5
 blob(model,'Pommel',Vector3.new(.86,.62,.86),CFrame.new(0,py-.18,0),lemon,GL)
 blob(model,'Pommel',Vector3.new(.74,.4,.74),CFrame.new(0,py+.08,0),pink,GL)
 cylY(model,'PommelRing',.1,.66,CFrame.new(0,py+.26,0),lime,GL)
 blob(model,'Pommel',Vector3.new(.42,.36,.42),CFrame.new(.24,py-.12,.2),pink,GL)
 blob(model,'Pommel',Vector3.new(.36,.3,.36),CFrame.new(-.26,py-.24,-.12),lime,GL)
 blob(model,'Pommel',Vector3.new(.5,.26,.5),CFrame.new(0,py-.44,0),pink,GL)
 for i,a in ipairs({.6,2.2,3.7,5.2})do
  blob(model,'PommelHole',Vector3.new(.13,.1,.06),CFrame.new(math.cos(a)*.42,py-.2+(i%2)*.1,math.sin(a)*.42)*CFrame.Angles(0,-a+math.pi/2,0),Color3.fromRGB(200,120,20),SP)
 end
 drip('PommelDrip',Vector3.new(-.12,py-.5,.12),.3,.15,lime)
 drip('PommelDrip',Vector3.new(.18,py-.42,-.08),.22,.13,pink)

 -- IDLE FX: a few faint sugar sparkles around the head ---------------------------------------
 local holder=part(model,'GummySparkles',Vector3.new(2.6,1.6,1.2),at(0,.1,0),pink,SP,{Transparency=1,CastShadow=false})
 local fx=emitter(holder,'Sparkle',Color3.fromRGB(255,170,220));if fx then fx.Rate=1.4 end
 return tips[-1],tips[1]
end

-- Rotten Slime Slug ("Кирка Слизень-Гнилушка" concept sheet, Epic / Мерзкая / Гнилостная): a fat living slug
-- riding a rotten voxel pickaxe. The head: two crescent blades of mossy grey-olive stone curving down to
-- sharp points, a band of rotten bricks under them, a thick lime slime coat on top pouring off in long
-- drips; on it the slug's glossy khaki dome with one BIG cream eye (purple-red iris, lime socket) in the
-- middle of the face, a sleepy half-lidded eye to its right, three small eyes round them, a gaping mouth
-- with a long pink tongue hanging out, six eyes on slimy stalks on top, warts, moss, rotten bricks and
-- little mushrooms, and a snail-shell spiral on the back. The handle: stacked rotten planks with loose
-- bricks, moss cubes and two mushrooms, wound with a lime slime spiral, a little bone skull on a chunky
-- brick pommel sunk in a pool of slime. Moving parts (MiningClient.PickFX "Slug*" motions): the body
-- breathes / twitches / bounces, the stalks sway and shoot the eyes out on slime threads (a Beam from
-- the stalk to the eye) on a strike, the eyes look round, the big eye twitches, the sleepy lid blinks,
-- the tongue sways, live drops stretch and fall off the blades, the mouth and the pommel.
local function slugBez(p0,p1,p2,p3,t)local u=1-t;return p0*u*u*u+p1*3*u*u*t+p2*3*u*t*t+p3*t*t*t end
-- frame at pos whose +Z looks along dir (Y as close to up as possible)
local function slugFace(pos,dir)
 local Z=dir.Unit;local X=Vector3.yAxis:Cross(Z)
 X=X.Magnitude<1e-3 and Vector3.xAxis or X.Unit
 return CFrame.fromMatrix(pos,X,Z:Cross(X),Z)
end
DESIGNS.Slug=function(model,v,def,len,top)
 local lime=rgb(v.Accent,{152,214,71})           -- slime (palette 2)
 local lime2=Color3.fromRGB(127,173,39)           -- deep slime (palette 1)
 local acid=Color3.fromRGB(222,238,62)            -- acid yellow-lime (palette 3)
 local skin=rgb(v.Head,{168,166,96})               -- slug skin (palette 5)
 local skin2=Color3.fromRGB(194,188,116)           -- light skin / shell (palette 7)
 local skin3=Color3.fromRGB(128,124,78)            -- dark skin, lids, warts
 local stone=rgb(v.Trim,{120,112,92})              -- blade stone (palette 4)
 local stone2=Color3.fromRGB(166,156,118)
 local bone=Color3.fromRGB(213,198,165)            -- bone / cream (palette 8)
 local wood=rgb(v.Shaft,{92,74,62})
 local wood2=Color3.fromRGB(112,103,94)
 local rot=Color3.fromRGB(131,91,81)               -- rotten brown (palette 6)
 local brick=Color3.fromRGB(170,108,68)
 local brickD=Color3.fromRGB(66,50,44)
 local moss=Color3.fromRGB(104,126,44)
 local eyeW=Color3.fromRGB(248,238,208)
 local iris=Color3.fromRGB(112,18,50)
 local irisR=Color3.fromRGB(178,48,80)
 local pupilC=Color3.fromRGB(22,8,16)
 local tongueC=Color3.fromRGB(240,124,152)
 local tongue2=Color3.fromRGB(204,82,114)
 local GL,SP,NE=Enum.Material.Glass,Enum.Material.SmoothPlastic,Enum.Material.Neon
 local goo={Transparency=.06,Reflectance=.1}       -- thick slime
 local thin={Transparency=.12,Reflectance=.1}      -- drips
 local wet={Reflectance=.07}                       -- glossy slug skin
 local rng=Random.new(66)
 local function r(a,b)return a+(b-a)*rng:NextNumber()end

 local hb=len*.5-.85                               -- underside of the head (top of the handle)
 local C=CFrame.new(0,hb+.8,0)                     -- the slug's body centre
 local cp=C.Position
 local function at(x,y,z)return C*CFrame.new(x,y,z)end
 local function body(p,extra,phase,joint)
  return anim(p,'SlugBody'..(extra and(','..extra)or''),phase or 0,joint or cp)
 end
 -- a hanging drip: neck, cap and a round drop straight down from top (model space)
 local function drip(name,topPos,length,d,color,ride)
  local neck=blob(model,name,Vector3.new(d*.78,length*1.1,d*.78),CFrame.new(topPos-Vector3.new(0,length*.45,0)),color,GL,thin)
  local drop=blob(model,name..'Drop',Vector3.new(d*1.05,d*1.3,d*1.05),CFrame.new(topPos-Vector3.new(0,length,0)),color,GL,thin)
  local cap=blob(model,name,Vector3.new(d*1.35,d*.8,d*1.35),CFrame.new(topPos-Vector3.new(0,d*.12,0)),color,GL,goo)
  if ride then for _,p in ipairs({neck,drop,cap})do body(p)end end
  return neck,drop,cap
 end
 -- a live drop: stretches on its neck, falls off, comes back (MiningClient.PickFX GummyDrop + PickGoo)
 local function liveDrop(topPos,color,phase,d)
  d=d or .17
  for i,k in ipairs({.33,.66,1})do
   local p=i<3 and blob(model,'SlimeNeck',Vector3.new(d*.5,d*1.1,d*.5),CFrame.new(topPos-Vector3.new(0,.065*i,0)),color,GL,thin)
    or blob(model,'SlimeLiveDrop',Vector3.new(d,d*1.25,d),CFrame.new(topPos-Vector3.new(0,.2,0)),color,GL,thin)
   anim(p,'GummyDrop',phase,topPos);p:SetAttribute('PickDropK',k)
   if i==3 then p:SetAttribute('PickGoo',true)end
  end
 end
 -- an eye looking along look (model space): white, iris ring, iris, pupil, glint; returns the parts
 local function slugEye(name,pos,look,d,irisCol,ring)
  local cf=slugFace(pos,look)                    -- +Z of cf = where it looks
  local list={}
  table.insert(list,ball(model,name,d,cf,eyeW,SP,{Reflectance=.1}))
  local ir={}
  table.insert(ir,blob(model,name..'IrisRing',Vector3.new(d*.62,d*.62,d*.12),cf*CFrame.new(0,0,d*.45),ring or irisR,SP))
  table.insert(ir,blob(model,name..'Iris',Vector3.new(d*.5,d*.5,d*.14),cf*CFrame.new(0,0,d*.47),irisCol or iris,SP,{Reflectance=.08}))
  table.insert(ir,blob(model,name..'Pupil',Vector3.new(d*.3,d*.3,d*.1),cf*CFrame.new(0,0,d*.52),pupilC,SP))
  table.insert(ir,ball(model,name..'Glint',math.max(.05,d*.13),cf*CFrame.new(d*.13,d*.15,d*.53),Color3.new(1,1,1),NE,{CastShadow=false}))
  for _,p in ipairs(ir)do table.insert(list,p)end
  return list,ir,cf
 end
 local function mushroom(base,up,s,capCol)
  local u=up.Unit
  local stem=rod(model,'Mushroom',base,base+u*s*.55,s*.22,bone,SP)
  local cap=blob(model,'MushroomCap',Vector3.new(s*.62,s*.3,s*.62),CFrame.new(base+u*s*.6)*alignY(u),capCol or Color3.fromRGB(196,106,54),SP)
  local spot=blob(model,'MushroomSpot',Vector3.new(s*.14,s*.06,s*.14),CFrame.new(base+u*s*.72+Vector3.new(s*.1,0,s*.08))*alignY(u),bone,SP)
  return stem,cap,spot
 end

 -- HANDLE: stacked rotten planks, loose bricks and moss, a slime spiral -------------------------
 local y0,y1=-len*.5+.32,hb+.15
 local n=math.floor((y1-y0)/.34)
 local step=(y1-y0)/n
 local planks={wood,wood2,rot,wood,brickD,wood2}
 for i=0,n-1 do
  local y=y0+step*(i+.5)
  part(model,'RotPlank',Vector3.new(.56,step+.02,.56),CFrame.new(r(-.03,.03),y,r(-.03,.03))*CFrame.Angles(0,math.rad(r(-6,6)),0),planks[i%#planks+1],Enum.Material.Wood)
 end
 -- loose voxels on the corners (none in the grip band, -1.95 .. -0.9, where the hand holds it)
 local cubeCols={brick,rot,brickD,moss,wood2,brick}
 local ys={-2.15,-.75,-.5,-.2,.1,.35,.65,.95,1.2,1.42}
 for i,y in ipairs(ys)do
  local a=i*1.9+r(-.3,.3)
  local s=r(.16,.26)
  local col=cubeCols[i%#cubeCols+1]
  part(model,'RotBrick',Vector3.new(s,s*.8,s),CFrame.new(math.cos(a)*.32,y,math.sin(a)*.32)*CFrame.Angles(0,-a,math.rad(r(-10,10))),col,col==moss and Enum.Material.Grass or Enum.Material.Wood)
  if i%3==0 then
   part(model,'RotBrick',Vector3.new(s*.7,s*.6,s*.7),CFrame.new(math.cos(a+2.4)*.32,y+.18,math.sin(a+2.4)*.32)*CFrame.Angles(0,-a,0),brick,Enum.Material.Wood)
  end
 end
 -- the slime spiral (thick over the top, thinner through the grip)
 local function helix(name,d,turns,phase,ya,yb,segs,rad,color)
  local prev
  for i=0,segs do
   local t=i/segs;local a=phase+t*turns*math.pi*2
   local q=Vector3.new(math.cos(a)*rad,ya+(yb-ya)*t,math.sin(a)*rad)
   if prev then local dir=(q-prev).Unit;rod(model,name,prev-dir*d*.4,q+dir*d*.4,d,color,GL,goo)end
   prev=q
  end
 end
 helix('SlimeSpiral',.27,1.6,.4,y1-.05,-.7,14,.34,lime)
 helix('SlimeSpiral',.16,1.1,2.2,-.7,-len*.5+.3,9,.34,lime2)
 for i,y in ipairs({.95,.05,-.62})do -- slime blobs stuck on the handle, each with a drip
  local a=i*2.3+.6
  local p=Vector3.new(math.cos(a)*.34,y,math.sin(a)*.34)
  blob(model,'HandleSlime',Vector3.new(.36,.3,.36),CFrame.new(p),i==2 and acid or lime,GL,goo)
  drip('HandleDrip',p+Vector3.new(math.cos(a)*.08,-.1,math.sin(a)*.08),.26+i*.08,.12,lime)
 end
 mushroom(Vector3.new(.24,.55,.12),Vector3.new(1,.55,.2),.42)
 mushroom(Vector3.new(-.22,-.35,.14),Vector3.new(-1,.4,.3),.34,Color3.fromRGB(170,92,48))
 mushroom(Vector3.new(.06,1.25,-.25),Vector3.new(.2,.5,-1),.3)
 -- POMMEL: a chunky knot of rotten bricks sunk in slime, a little bone skull on the front
 local py=-len*.5
 part(model,'PommelBrick',Vector3.new(.9,.44,.9),CFrame.new(0,py-.02,0)*CFrame.Angles(0,.2,0),brickD,Enum.Material.Wood)
 part(model,'PommelBrick',Vector3.new(.46,.36,.5),CFrame.new(.36,py+.08,-.22)*CFrame.Angles(0,.5,.12),rot,Enum.Material.Wood)
 part(model,'PommelBrick',Vector3.new(.44,.32,.42),CFrame.new(-.38,py+.02,.14)*CFrame.Angles(.1,-.4,0),brick,Enum.Material.Wood)
 part(model,'PommelBrick',Vector3.new(.36,.28,.36),CFrame.new(-.1,py-.12,-.3)*CFrame.Angles(0,.9,-.1),wood2,Enum.Material.Wood)
 part(model,'PommelBrick',Vector3.new(.8,.26,.8),CFrame.new(0,py-.3,0)*CFrame.Angles(0,-.3,0),rot,Enum.Material.Wood)
 part(model,'PommelMoss',Vector3.new(.24,.16,.24),CFrame.new(.3,py-.14,.26),moss,Enum.Material.Grass)
 blob(model,'PommelSlime',Vector3.new(1.1,.36,1.1),CFrame.new(0,py+.26,0),lime,GL,goo)
 blob(model,'PommelSlime',Vector3.new(.5,.3,.5),CFrame.new(.32,py-.05,.18),acid,GL,goo)
 blob(model,'PommelSlime',Vector3.new(.46,.28,.5),CFrame.new(-.3,py-.16,-.1),lime,GL,goo)
 drip('PommelDrip',Vector3.new(.38,py-.12,.24),.32,.14,lime)
 drip('PommelDrip',Vector3.new(-.35,py-.22,-.12),.22,.12,acid)
 liveDrop(Vector3.new(.05,py-.42,.05),lime,.3,.15)
 do -- the skull
  local sk=CFrame.new(0,py+.02,.5)*CFrame.Angles(0,0,math.rad(-6))
  part(model,'Skull',Vector3.new(.3,.26,.16),sk,bone,SP)
  part(model,'SkullJaw',Vector3.new(.2,.08,.14),sk*CFrame.new(0,-.16,0),bone:Lerp(Color3.new(0,0,0),.1),SP)
  for s=-1,1,2 do part(model,'SkullEye',Vector3.new(.08,.08,.03),sk*CFrame.new(s*.07,.03,.08),brickD,SP)end
 end

 -- BLADES: two crescents of mossy stone curving down to sharp points -----------------------------
 local tips={}
 local N=11
 for _,side in ipairs({-1,1})do
  local P0,P1,P2,P3=Vector3.new(side*.45,hb+.5,0),Vector3.new(side*1.65,hb+1.0,0),Vector3.new(side*2.3,hb+.4,0),Vector3.new(side*2.12,hb-1.2,0)
  local function pt(t)return slugBez(P0,P1,P2,P3,math.clamp(t,0,1))end
  local seg=0;for i=1,40 do seg+=(pt(i/40)-pt((i-1)/40)).Magnitude end;seg=seg/N
  local frames={}
  for i=1,N do
   local t=(i-.5)/N
   local pos=pt(t);local tan=(pt(t+.01)-pt(t-.01)).Unit
   local X=tan*side;local Y=Vector3.zAxis:Cross(X).Unit
   local cf=CFrame.fromMatrix(pos,X,Y,Vector3.zAxis)
   local th=.8+(.2-.8)*t^1.2;local dp=.92+(.34-.92)*t
   frames[i]={CF=cf,T=t,Th=th,Dp=dp,Pos=pos,Tan=tan,N=Y}
   local core=t<.45 and wood2:Lerp(stone,t/.45)or stone:Lerp(stone2,(t-.45)/.55)
   part(model,'BladeStone',Vector3.new(seg*1.3,th,dp),cf,core,t<.45 and Enum.Material.Wood or Enum.Material.Slate)
   if t<.62 then -- rotten bricks on the front and back faces
    for _,zs in ipairs({1,-1})do
     local bc=({brick,brickD,rot,wood2,brick,brickD,rot})[(i+(zs>0 and 0 or 3))%7+1]
     part(model,'BladeBrick',Vector3.new(seg*.8,th*.42,.12),cf*CFrame.new(r(-.05,.05),(i%2==0 and -.12 or .08)*th,zs*(dp*.5+.03)),bc,Enum.Material.Wood)
    end
   end
   if i<=N-2 then -- the slime coat on top
    part(model,'BladeSlime',Vector3.new(seg*1.34,th*.32,dp*1.08),cf*CFrame.new(0,th*.5,0),i==N-2 and acid or lime,GL,goo)
    if i%2==1 then blob(model,'BladeSlimeLump',Vector3.new(seg*1.6,th*.42,dp*.9),cf*CFrame.new(0,th*.62,r(-.1,.1)),lime,GL,goo)end
   end
   if i<=6 then -- rotten bricks under the blade
    local bc=({brick,brickD,rot,brick,wood2,brickD})[i]
    part(model,'BladeBrick',Vector3.new(seg*.95,.24,dp*.86),cf*CFrame.new(r(-.04,.04),-th*.5-.08,r(-.06,.06))*CFrame.Angles(0,math.rad(r(-8,8)),0),bc,Enum.Material.Wood)
    if i%2==0 then part(model,'BladeBrick',Vector3.new(seg*.6,.2,dp*.5),cf*CFrame.new(0,-th*.5-.26,dp*.18),brick,Enum.Material.Wood)end
   end
   if i==4 or i==8 then -- a stone chip on the edge
    part(model,'BladeChip',Vector3.new(seg*.7,th*.35,dp*.4),cf*CFrame.new(0,-th*.32,dp*.42)*CFrame.Angles(0,0,side*.4),stone:Lerp(Color3.new(0,0,0),.2),Enum.Material.Slate)
   end
  end
  -- the point
  local last=frames[N]
  local tipBase=last.Pos+last.Tan*seg*.55
  spike(model,'BladeTip',tipBase,last.Tan,last.N,.7,last.Th*1.05,last.Dp,stone2,Enum.Material.Slate)
  tips[side]=tipBase+last.Tan*.7
  -- slime pouring off the blade: drips hanging from the coat's edge (front and back), long ones lower down
  local drips=side<0 and{{1,.75,lime},{2,.45,acid},{3,.95,lime},{4,.38,lime2},{5,.7,acid},{6,.5,lime},{7,.85,lime}}
   or{{1,.55,acid},{2,.9,lime},{3,.4,lime},{4,.8,acid},{5,.42,lime2},{6,.68,lime},{8,.5,lime}}
  for k,dd in ipairs(drips)do
   local f=frames[dd[1]]
   local edge=f.Pos+Vector3.new(0,0,(k%2==0 and -1 or 1)*f.Dp*.4)-f.N*f.Th*.25
   drip('BladeDrip',edge,dd[2],.15+dd[2]*.08,dd[3])
  end
  -- moss and debris on top
  local f3,f6=frames[3],frames[6]
  part(model,'BladeMoss',Vector3.new(.26,.16,.3),f3.CF*CFrame.new(0,f3.Th*.78,.18),moss,Enum.Material.Grass)
  part(model,'BladeDebris',Vector3.new(.22,.18,.22),f6.CF*CFrame.new(.05,f6.Th*.72,-.15)*CFrame.Angles(.3,.5,.2),side<0 and brick or rot,Enum.Material.Wood)
  local fl=frames[side<0 and 5 or 7]
  liveDrop(fl.Pos-fl.N*fl.Th*.45+Vector3.new(0,0,.15),side<0 and acid or lime,side<0 and .1 or .6,.18)
 end
 -- a bone bead stuck on the right blade (hero view)
 ball(model,'BoneBead',.26,CFrame.new(1.95,hb+.62,.28),bone,SP)

 -- SLUG BODY: the glossy khaki dome, warts, moss, mushrooms, the slime skirt ---------------------
 body(blob(model,'SlugBody',Vector3.new(2.4,1.5,2.2),at(0,.05,-.05),skin,SP,wet))
 body(blob(model,'SlugDome',Vector3.new(1.75,.92,1.62),at(0,.52,-.18),skin2,SP,wet))
 body(blob(model,'SlugFace',Vector3.new(1.95,1.25,1.0),at(0,-.06,.68),skin,SP,wet))
 body(blob(model,'SlugCheek',Vector3.new(.8,.7,.7),at(-.88,-.18,.55),skin3,SP,wet))
 body(blob(model,'SlugCheek',Vector3.new(.72,.62,.66),at(.95,-.2,.5),skin3,SP,wet))
 body(blob(model,'Gloss',Vector3.new(.7,.1,.35),at(-.35,.95,.05)*CFrame.Angles(0,0,.25),Color3.fromRGB(240,240,200),SP,{Transparency=.5,CastShadow=false}))
 for i,w in ipairs({{-.7,.55,-.4,.3},{.62,.62,-.35,.26},{.15,.92,-.55,.22},{-.35,.45,-.95,.24},{.85,.2,-.7,.2},{-.98,.15,-.55,.22}})do
  body(blob(model,'Wart',Vector3.new(w[4],w[4]*.7,w[4]),at(w[1],w[2],w[3]),i%2==0 and skin3 or skin2,SP,wet))
 end
 for _,m in ipairs({{-.55,.78,.05},{.62,.66,.3},{.2,.92,-.5}})do
  body(part(model,'HeadMoss',Vector3.new(.28,.14,.24),at(m[1],m[2],m[3])*CFrame.Angles(0,m[1]*2,.15),moss,Enum.Material.Grass))
 end
 for _,b in ipairs({{.9,.55,.15,brick},{-.95,.48,-.2,rot},{.55,.88,-.15,brickD}})do
  body(part(model,'HeadBrick',Vector3.new(.24,.2,.24),at(b[1],b[2],b[3])*CFrame.Angles(.3,b[1],.2),b[4],Enum.Material.Wood))
 end
 for _,mm in ipairs({{-.72,.72,-.25,.38},{.75,.6,-.3,.32},{.05,.98,-.42,.36}})do
  for _,p in ipairs({mushroom(at(mm[1],mm[2],mm[3]).Position,Vector3.new(mm[1]*.4,1,-.2),mm[4])})do body(p)end
 end
 -- slime skirt oozing out under the body onto the blades, lumps and drips round its rim
 body(blob(model,'SlimeSkirt',Vector3.new(2.7,.55,2.35),at(0,-.66,0),lime,GL,goo))
 for i,a in ipairs({.3,1.1,1.9,2.6,3.5,4.4,5.2,5.9})do
  local p=at(math.cos(a)*1.12,-.62,math.sin(a)*1.0)
  body(blob(model,'SlimeLump',Vector3.new(.55,.36,.5),p,i%3==0 and acid or lime,GL,goo))
 end
 for i,dd in ipairs({{-.85,.95,.5},{-.45,1.08,.35},{.62,1.02,.6},{1.0,.75,.3},{.15,1.12,.25},{-1.15,.4,.42}})do
  drip('SkirtDrip',at(dd[1],-.82,dd[3]*1.5).Position,dd[2]*.6,.16,i%2==0 and acid or lime,true)
 end
 -- the snail shell spiral on the back (back view)
 do
  local S=at(0,.3,-1.0).Position
  local Z=Vector3.new(0,.3,-1).Unit;local X=Vector3.xAxis;local Y=Z:Cross(X).Unit
  local sc=CFrame.fromMatrix(S,X,Y,Z)
  body(blob(model,'ShellBase',Vector3.new(1.35,1.3,.55),sc,skin2,SP,wet))
  local turns=2.3
  local segs=30
  for i=0,segs-1 do
   local k=i/segs
   local ang=k*turns*math.pi*2
   local rr=.58*(1-k*.88)
   local d=.36-.24*k
   body(ball(model,'ShellCoil',d,sc*CFrame.new(math.cos(ang)*rr,math.sin(ang)*rr,.16+k*.26),bone:Lerp(skin2,(i%6)/6),SP,wet))
   if i%2==0 and k<.8 then -- the groove between the turns
    local rg=rr-d*.5
    body(ball(model,'ShellGroove',d*.42,sc*CFrame.new(math.cos(ang+.3)*rg,math.sin(ang+.3)*rg,.1+k*.26),skin3,SP))
   end
  end
  body(ball(model,'ShellCoil',.12,sc*CFrame.new(0,0,.44),skin3,SP))
 end

 -- FACE ----------------------------------------------------------------------------------------
 -- the BIG eye in the middle, in a lime socket; it twitches (SlugBigEye) and looks round (SlugLook)
 local E=at(-.08,.24,1.1).Position
 local ej=E
 body(blob(model,'BigEyeSocket',Vector3.new(1.28,1.24,.55),CFrame.new(E+Vector3.new(0,-.02,-.24)),lime,GL,goo),'SlugBigEye',0,ej)
 body(blob(model,'BigEyeSocket',Vector3.new(1.36,.36,.5),CFrame.new(E+Vector3.new(0,.5,-.16)),acid,GL,goo),'SlugBigEye',0,ej)
 local list,ir=slugEye('BigEye',E,Vector3.new(0,.05,1),1.02)
 for _,p in ipairs(list)do body(p,'SlugBigEye',0,ej)end
 for _,p in ipairs(ir)do p:SetAttribute('PickAnim','SlugBody,SlugBigEye,SlugLook')end
 -- the sleepy half-lidded eye on its right
 local D=at(.74,.22,.96).Position
 list,ir=slugEye('SleepyEye',D,Vector3.new(.35,0,1),.6,Color3.fromRGB(176,64,40),Color3.fromRGB(236,170,80))
 for _,p in ipairs(list)do body(p)end
 for _,p in ipairs(ir)do p:SetAttribute('PickAnim','SlugBody,SlugLook');p:SetAttribute('PickPhase',1.7)end
 local lidCF=slugFace(D,Vector3.new(.35,0,1))*CFrame.Angles(0,0,math.rad(-14))
 body(blob(model,'SleepyLid',Vector3.new(.7,.4,.7),lidCF*CFrame.new(0,.15,.03),skin3,SP,wet),'SlugLid',.8,D)
 body(blob(model,'SleepyLid',Vector3.new(.66,.12,.62),lidCF*CFrame.new(0,-.02,.1),skin3:Lerp(Color3.new(0,0,0),.15),SP),'SlugLid',.8,D)
 body(blob(model,'SleepyLidLow',Vector3.new(.62,.18,.6),lidCF*CFrame.new(0,-.26,.04),skin3,SP,wet))
 -- small eyes round them
 for i,se in ipairs({{-.86,.16,.84,.4,-.6},{.3,.76,.84,.32,.3},{-.58,.74,.6,.28,-.5},{1.02,-.18,.62,.24,.9}})do
  local pos=at(se[1],se[2],se[3]).Position
  list,ir=slugEye('SmallEye'..i,pos,Vector3.new(se[5],.2,1),se[4])
  for _,p in ipairs(list)do body(p)end
  for _,p in ipairs(ir)do p:SetAttribute('PickAnim','SlugBody,SlugLook');p:SetAttribute('PickPhase',i*1.3)end
  if i==1 then body(blob(model,'SmallEyeRim',Vector3.new(.5,.5,.24),slugFace(pos,Vector3.new(se[5],.2,1))*CFrame.new(0,0,-.1),lime,GL,goo))end
 end
 -- the gaping mouth and the long pink tongue hanging out of it
 local Mo=at(-.04,-.42,1.06)
 body(blob(model,'Mouth',Vector3.new(1.0,.38,.34),Mo,Color3.fromRGB(70,30,34),SP))
 body(blob(model,'LipTop',Vector3.new(1.16,.2,.34),Mo*CFrame.new(0,.18,.05),skin,SP,wet))
 body(blob(model,'LipBottom',Vector3.new(1.04,.2,.32),Mo*CFrame.new(0,-.18,.03),skin3,SP,wet))
 local tr=(Mo*CFrame.new(-.12,-.06,.14)).Position
 local function tongue(p)return body(p,'SlugTongue',0,tr)end
 -- a wide flat tongue flopping out of the mouth over the lip, curling forward at the tip
 tongue(blob(model,'Tongue',Vector3.new(.52,.42,.32),CFrame.new(tr+Vector3.new(0,-.1,.12)),tongueC,SP,{Reflectance=.12}))
 tongue(blob(model,'Tongue',Vector3.new(.48,1.02,.22),CFrame.new(tr+Vector3.new(-.03,-.55,.24))*CFrame.Angles(.12,0,0),tongueC,SP,{Reflectance=.12}))
 tongue(blob(model,'TongueTip',Vector3.new(.44,.32,.26),CFrame.new(tr+Vector3.new(-.04,-1.0,.2))*CFrame.Angles(-.3,0,0),tongueC,SP,{Reflectance=.12}))
 tongue(part(model,'TongueGroove',Vector3.new(.045,.72,.03),CFrame.new(tr+Vector3.new(-.03,-.6,.35))*CFrame.Angles(.12,0,0),tongue2,SP))
 tongue(blob(model,'TongueGloss',Vector3.new(.12,.3,.03),CFrame.new(tr+Vector3.new(.1,-.42,.34)),Color3.fromRGB(255,190,205),SP,{Transparency=.3}))
 drip('DroolDrip',(Mo*CFrame.new(.36,-.24,.12)).Position,.42,.14,lime,true)
 drip('DroolDrip',(Mo*CFrame.new(-.42,-.22,.1)).Position,.28,.12,acid,true)
 liveDrop((Mo*CFrame.new(.22,-.28,.16)).Position,lime,.85,.15)

 -- EYE STALKS: eyes on slimy stalks; a strike shoots them out on slime threads -------------------
 local stalks={ -- base, tip (body space), eye size
  {Vector3.new(-.55,.62,.22),Vector3.new(-1.32,1.82,.5),.56},
  {Vector3.new(-.9,.38,.18),Vector3.new(-1.78,1.0,.42),.4},
  {Vector3.new(-.12,.8,.08),Vector3.new(-.3,1.62,.32),.36},
  {Vector3.new(.32,.78,-.02),Vector3.new(.48,1.5,.22),.3},
  {Vector3.new(.78,.55,.02),Vector3.new(1.28,1.22,.3),.38},
  {Vector3.new(-.32,.66,-.58),Vector3.new(-.52,1.3,-.82),.27},
 }
 for i,s in ipairs(stalks)do
  local base,tip=at(s[1].X,s[1].Y,s[1].Z).Position,at(s[2].X,s[2].Y,s[2].Z).Position
  local out=(tip-base).Unit
  local bend=base+(tip-base)*.5+Vector3.new(-out.X*.12,.12,0)
  local pts={}
  for k=0,3 do local t=k/3;pts[k]=(base*(1-t)*(1-t)+bend*2*(1-t)*t+tip*t*t)end
  local topSeg
  for k=1,3 do
   local d=.15-.025*k
   local seg=rod(model,'EyeStalk',pts[k-1],pts[k]-(k==3 and out*s[3]*.3 or Vector3.zero),d,k==1 and lime2 or lime,GL,{Transparency=.1,Reflectance=.08})
   body(seg,'SlugStalk',i*.9,base)
   seg:SetAttribute('PickPop',out);seg:SetAttribute('PickAmp',k/3*.6)
   topSeg=seg
  end
  body(blob(model,'StalkBase',Vector3.new(.3,.18,.3),CFrame.new(base),lime,GL,goo))
  local look=(out*.45+Vector3.new(0,0,s[2].Z>=0 and 1 or -1)).Unit
  local eyes,irs=slugEye('StalkEye'..i,tip,look,s[3])
  for _,p in ipairs(eyes)do
   body(p,'SlugStalk',i*.9,base)
   p:SetAttribute('PickPop',out);p:SetAttribute('PickAmp',1)
  end
  for _,p in ipairs(irs)do p:SetAttribute('PickAnim','SlugBody,SlugStalk,SlugLook')end
  -- the slime thread: stalk top -> eye (it shows when the eye is shot out)
  local a0=Instance.new('Attachment');a0.Name='SlugThreadA';a0.Parent=topSeg
  a0.Position=topSeg.CFrame:PointToObjectSpace(tip-out*s[3]*.3)
  local a1=Instance.new('Attachment');a1.Name='SlugThreadB';a1.Parent=eyes[1]
  local beam=Instance.new('Beam');beam.Name='SlugThread';beam.Attachment0=a0;beam.Attachment1=a1
  beam.Width0=.09;beam.Width1=.05;beam.FaceCamera=true;beam.Segments=1;beam.LightEmission=.35
  beam.Color=ColorSequence.new(lime);beam.Transparency=NumberSequence.new(.15);beam.Parent=eyes[1]
 end

 -- GLOW and IDLE FX: a lime light in the slime, drops falling off the underside -----------------
 local glow=part(model,'SlugGlow',Vector3.new(.4,.4,.4),at(0,-.5,.2),lime,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='SlugLight';light.Color=Color3.fromRGB(170,240,70);light.Range=6.5;light.Brightness=.6;light.Shadows=false;light.Parent=glow
 local under=part(model,'SlugDrips',Vector3.new(3.6,.1,.9),CFrame.new(0,hb-.15,0),lime,SP,{Transparency=1,CastShadow=false})
 local pe=Instance.new('ParticleEmitter');pe.Name='SlugDripFX';pe.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pe.Rate=1.6;pe.Lifetime=NumberRange.new(.7,1.1);pe.Speed=NumberRange.new(0,.2);pe.Acceleration=Vector3.new(0,-14,0)
 pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.16),NumberSequenceKeypoint.new(1,.08)});pe.LightEmission=.6
 pe.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.8,.2),NumberSequenceKeypoint.new(1,1)})
 pe.Color=ColorSequence.new(acid,lime);pe.SpreadAngle=Vector2.new(5,5);pe.EmissionDirection=Enum.NormalId.Bottom;pe.Parent=under
 -- On the back: a bit higher and further out, so the fat head clears the character's own head.
 model:SetAttribute('BackC0',CFrame.new(.35,.1,.3))
 return tips[-1],tips[1]
end

-- Toothy Alarm Clock ("Зубастый Будильник" concept sheet, Epic): a living voxel alarm clock on a club.
-- The head: a round, glossy red voxel clock body (stepped layers, lighter / darker red voxels on the
-- surface, scuffs); on the front a huge open mouth wrapped round the face with sharp cream fangs on
-- top and a biting lower jaw, a cream clock dial deep inside it with red knife hands; two big mad
-- cream eyes (red irises, veins, angry dark brows and lids) over it and a smaller third eye low on the
-- right; cream-white metal spikes round the rim; grey bolts; an orange side plate with the alarm
-- knob on each side; on top two riveted grey bells, the striker between them and the red snooze
-- light; on the back a dark plate with an X brace, a turning gear and the gold winding key. Under
-- the head a grey collar with a gold pocket watch hanging off it on a chain. The handle: stacked red,
-- black and grey voxel blocks with bolts and three little clock dials, a black / dark red wrapped
-- grip and a chunky red pommel block with grey corners, bolts and a glowing core.
-- Moving parts (MiningClient.PickFX "Alarm*" motions): the head rattles while it rings (AlarmBody),
-- the bells shake (AlarmBell) and the striker hammers between them (AlarmHammer), the jaw bites
-- (AlarmJaw), the knife hands spin (AlarmHand, s.AlarmMin / s.AlarmHour), the eyes look round, pop
-- out on a hit and blink (AlarmLook / AlarmPop / AlarmLid), the winding key and the back gear turn
-- (AlarmKey / AlarmGear), the handle dials tick (AlarmTick), the pocket watch swings on its chain
-- (AlarmWatch) and its hands turn (AlarmWatchHand).
DESIGNS.Alarm=function(model,v,def,len,top)
 local SP,ME,FO,NE=Enum.Material.SmoothPlastic,Enum.Material.Metal,Enum.Material.Foil,Enum.Material.Neon
 local red=rgb(v.Head,{224,32,36})                 -- palette 1: clock red
 local red2=Color3.fromRGB(176,20,26)              -- shade
 local red3=Color3.fromRGB(246,78,66)              -- highlight voxels
 local cream=rgb(v.Accent,{244,226,206})           -- palette 2: cream (eyes, teeth, dials)
 local grey=Color3.fromRGB(128,126,130)            -- palette 3: metal grey
 local grey2=Color3.fromRGB(84,82,88)              -- palette 4: dark metal
 local black=rgb(v.Shaft,{38,36,40})
 local gold=rgb(v.Trim,{246,196,82})               -- palette 5: gold
 local orange=Color3.fromRGB(236,128,40)
 local maw=Color3.fromRGB(64,10,14)
 local bone=Color3.fromRGB(240,232,216)            -- spikes / fangs
 local gloss={Reflectance=.06}
 local rng=Random.new(707)
 local function r(a,b)return a+(b-a)*rng:NextNumber()end

 local RX,RY,RZ=1.36,1.26,1.06                     -- the clock body (an ellipsoid of voxel layers)
 local C=CFrame.new(0,len*.5+.62,0)
 local cp=C.Position
 local function at(x,y,z)return C*CFrame.new(x,y,z)end
 local function body(p,extra,joint,phase)
  return anim(p,'AlarmBody'..(extra and(','..extra)or''),phase or 0,joint or cp)
 end
 -- point on the body surface in direction (x,y,z) (body space) and its outward normal
 local function surf(x,y,z,out)
  local d=Vector3.new(x/RX,y/RY,z/RZ).Unit
  local p=Vector3.new(d.X*RX,d.Y*RY,d.Z*RZ)
  local nrm=Vector3.new(p.X/(RX*RX),p.Y/(RY*RY),p.Z/(RZ*RZ)).Unit
  return cp+p+nrm*(out or 0),nrm
 end
 -- front of the body at (x,y): z on the surface
 local function frontZ(x,y)
  local k=1-(x/RX)^2-(y/RY)^2
  return k>0 and RZ*math.sqrt(k)or 0
 end
 -- frame at pos looking along n (+Z), Y as close to up as possible
 local function face(pos,n,upHint)
  local Z=n.Unit;local X=(upHint or Vector3.yAxis):Cross(Z)
  X=X.Magnitude<1e-3 and Vector3.xAxis or X.Unit
  return CFrame.fromMatrix(pos,X,Z:Cross(X),Z)
 end
 -- a chunky voxel ball (a cube and three crossing slabs)
 local function vball(name,cf,d,color,mat,props,extra,joint,phase)
  local list={}
  table.insert(list,part(model,name,Vector3.new(d*.8,d*.8,d*.8),cf,color,mat,props))
  table.insert(list,part(model,name,Vector3.new(d,d*.56,d*.56),cf,color,mat,props))
  table.insert(list,part(model,name,Vector3.new(d*.56,d,d*.56),cf,color,mat,props))
  table.insert(list,part(model,name,Vector3.new(d*.56,d*.56,d),cf,color,mat,props))
  for _,p in ipairs(list)do body(p,extra,joint,phase)end
  return list
 end
 -- an octagonal voxel slab (two crossing boxes) of width w, height h at cf
 local function oct(name,cf,w,h,color,mat,props)
  return{part(model,name,Vector3.new(w,h,w*.62),cf,color,mat,props),part(model,name,Vector3.new(w*.62,h,w),cf,color,mat,props),
   part(model,name,Vector3.new(w*.86,h,w*.86),cf,color,mat,props)}
 end
 -- a little clock dial facing along the cf's +Z: rim, face, 4 hour marks and two red hands
 local function dial(name,cf,d,rim,motion,hang)
  local list={}
  table.insert(list,cylZ(model,name..'Rim',.08,d,cf,rim,FO))
  table.insert(list,cylZ(model,name,.06,d*.8,cf*CFrame.new(0,0,.03),cream,SP))
  for i=0,3 do
   local a=i*math.pi/2
   table.insert(list,part(model,name..'Mark',Vector3.new(d*.07,d*.13,.03),cf*CFrame.new(math.cos(a)*d*.3,math.sin(a)*d*.3,.065)*CFrame.Angles(0,0,a+math.pi/2),black,SP))
  end
  local hands={}
  table.insert(hands,part(model,name..'Hand',Vector3.new(d*.07,d*.32,.03),cf*CFrame.new(0,d*.14,.085),red2,SP))
  table.insert(hands,part(model,name..'Hand',Vector3.new(d*.07,d*.24,.03),cf*CFrame.new(d*.1,-d*.03,.085)*CFrame.Angles(0,0,math.rad(-100)),red2,SP))
  table.insert(hands,part(model,name..'Pin',Vector3.new(d*.12,d*.12,.04),cf*CFrame.new(0,0,.09),gold,FO))
  if motion then for _,p in ipairs(hands)do anim(p,motion,0,cf.Position);if hang then p:SetAttribute('PickHang',hang)end end end
  return list,hands
 end

 -- HANDLE: stacked red / black / grey voxel blocks, bolts, three little clock dials, the grip ------
 local function seg(name,y0,y1,w,color,mat,props)
  return part(model,name,Vector3.new(w,y1-y0,w),CFrame.new(0,(y0+y1)*.5,0),color,mat,props)
 end
 local function bolts(y,w,n,col)
  for i=0,n-1 do
   local a=i/n*math.pi*2+math.pi/4
   local p=Vector3.new(math.cos(a)*w*.5,y,math.sin(a)*w*.5)
   part(model,'HandleBolt',Vector3.new(.12,.12,.12),CFrame.lookAt(p,p+Vector3.new(p.X,0,p.Z)),col or grey,ME,{Reflectance=.15})
  end
 end
 local hTop=cp.Y-RY+.12
 seg('NeckRed',hTop-.22,hTop+.12,.74,red,SP,gloss)
 seg('Collar',hTop-.42,hTop-.22,.86,grey,ME,{Reflectance=.12})
 part(model,'Collar',Vector3.new(.62,.2,.98),CFrame.new(0,hTop-.32,0),grey,ME,{Reflectance=.12})
 part(model,'Collar',Vector3.new(.98,.2,.62),CFrame.new(0,hTop-.32,0),grey,ME,{Reflectance=.12})
 bolts(hTop-.32,1.0,6,grey2)
 local y=hTop-.42
 local plan={ -- {height, width, color, material, kind}
  {.42,.6,red,SP,'dial'},{.2,.52,black,ME},{.2,.64,grey,ME,'bolts'},{.44,.56,red,SP,'dial'},{.18,.5,black,ME},
  {.4,.56,red,SP,'dial'},{.16,.64,grey,ME,'bolts'},
 }
 local dials=0
 for i,s in ipairs(plan)do
  local y0=y-s[1]
  local b=seg(s[5]=='bolts'and'HandleBand'or'HandleBlock',y0,y,s[2],s[3],s[4],s[4]==SP and gloss or{Reflectance=.1})
  if s[3]==red then -- voxel bevel: darker red corner blocks
   for k=0,3 do
    local a=k*math.pi/2+math.pi/4
    part(model,'HandleCorner',Vector3.new(.12,s[1]-.04,.12),CFrame.new(math.cos(a)*s[2]*.62,(y0+y)*.5,math.sin(a)*s[2]*.62),red2,SP)
   end
  end
  if s[5]=='bolts'then bolts((y0+y)*.5,s[2],4)end
  if s[5]=='dial'then
   dials+=1
   local yaw=({0,math.rad(-18),math.rad(14)})[dials]
   local cf=CFrame.new(0,(y0+y)*.5,0)*CFrame.Angles(0,yaw,0)*CFrame.new(0,0,s[2]*.5+.02)
   dial('HandleDial',cf,math.min(.36,s[1]*.86),gold,'AlarmTick')
  end
  y=y0
 end
 -- the grip (the hand holds the handle round -1.4): flat wrapped bands, no knobs
 local gTop,gBot=y,-len*.5+.42
 local nb=7
 for i=0,nb-1 do
  local a=gTop-(gTop-gBot)*i/nb;local b=gTop-(gTop-gBot)*(i+1)/nb
  part(model,'GripWrap',Vector3.new(.5,a-b+.01,.5),CFrame.new(0,(a+b)*.5,0)*CFrame.Angles(0,i%2==0 and 0 or math.rad(45),0),i%2==0 and black or Color3.fromRGB(120,18,24),Enum.Material.Fabric)
 end
 seg('GripRing',gTop-.06,gTop+.04,.6,grey,ME)
 -- POMMEL: a chunky red block, grey corner posts, bolts, a glowing core and a grey foot
 local py=gBot-.36
 seg('GripRing',gBot-.02,gBot+.08,.62,grey,ME)
 part(model,'Pommel',Vector3.new(.78,.62,.78),CFrame.new(0,py,0),red,SP,gloss)
 for k=0,3 do
  local a=k*math.pi/2+math.pi/4
  part(model,'PommelCorner',Vector3.new(.24,.7,.24),CFrame.new(math.cos(a)*.52,py,math.sin(a)*.52),grey,ME,{Reflectance=.12})
  part(model,'PommelBolt',Vector3.new(.1,.1,.1),CFrame.new(math.cos(a)*.6,py+.22,math.sin(a)*.6),grey2,ME)
 end
 for k=0,3 do
  local a=k*math.pi/2
  local n=Vector3.new(math.sin(a),0,math.cos(a))
  local core=part(model,'PommelCore',Vector3.new(.3,.26,.04),CFrame.lookAt(Vector3.new(0,py,0)+n*.4,Vector3.new(0,py,0)+n),Color3.fromRGB(255,96,52),NE,{CastShadow=false})
  core:SetAttribute('PickPulse',true)
 end
 part(model,'PommelFoot',Vector3.new(.86,.16,.86),CFrame.new(0,py-.38,0),grey2,ME,{Reflectance=.1})
 part(model,'PommelFoot',Vector3.new(.6,.12,.6),CFrame.new(0,py-.5,0),grey,ME)
 for k=0,3 do local a=k*math.pi/2+math.pi/4;part(model,'PommelBolt',Vector3.new(.1,.06,.1),CFrame.new(math.cos(a)*.3,py-.57,math.sin(a)*.3),cream,ME)end
 -- scuffs on the handle
 part(model,'Scuff',Vector3.new(.04,.18,.02),CFrame.new(.14,hTop-.68,.31)*CFrame.Angles(0,0,.6),red2,SP)
 part(model,'Scuff',Vector3.new(.03,.14,.02),CFrame.new(-.12,hTop-1.55,.29)*CFrame.Angles(0,0,-.5),red2,SP)

 -- POCKET WATCH on a gold chain off the collar (swings: AlarmWatch about the hook) ----------------
 local hook=Vector3.new(.36,hTop-.36,.34)
 local W=Vector3.new(.62,hTop-1.22,.4)
 local links=5
 for i=1,links do
  local p=hook:Lerp(W+Vector3.new(0,.36,0),(i-.5)/links)
  local l=part(model,'WatchChain',Vector3.new(.06,.16,i%2==0 and .1 or .04),CFrame.lookAt(p,p+Vector3.new(0,0,1))*CFrame.Angles(0,i%2==0 and math.pi/2 or 0,0),gold,FO)
  anim(l,'AlarmWatch',0,hook)
 end
 local wcf=CFrame.new(W)*CFrame.Angles(0,math.rad(-10),math.rad(6))
 local wl={}
 table.insert(wl,cylZ(model,'WatchCase',.14,.66,wcf,gold,FO))
 table.insert(wl,cylZ(model,'WatchBack',.06,.56,wcf*CFrame.new(0,0,-.09),Color3.fromRGB(200,150,60),FO))
 table.insert(wl,part(model,'WatchCrown',Vector3.new(.12,.12,.1),wcf*CFrame.new(0,.38,0),gold,FO))
 table.insert(wl,part(model,'WatchBow',Vector3.new(.2,.06,.05),wcf*CFrame.new(0,.47,0),gold,FO))
 local list,hands=dial('WatchDial',wcf*CFrame.new(0,0,.04),.54,Color3.fromRGB(214,160,60),'AlarmWatch,AlarmWatchHand',W-hook)
 for _,p in ipairs(list)do table.insert(wl,p)end
 for _,p in ipairs(wl)do anim(p,'AlarmWatch',0,hook)end
 for _,p in ipairs(hands)do p:SetAttribute('PickJoint',hook)end

 -- BODY: stepped voxel layers ------------------------------------------------------------------
 local H=.21
 local nL=math.floor(RY*2/H+.5)
 for i=0,nL-1 do
  local yy=-RY+H*(i+.5)
  local f=math.sqrt(math.max(.04,1-(yy/RY)^2))
  local w,dp=RX*2*f,RZ*2*f
  local col=(i==nL-1 or i==0)and red2 or red
  body(part(model,'ClockBody',Vector3.new(w,H+.01,dp*.6),at(0,yy,0),col,SP,gloss))
  body(part(model,'ClockBody',Vector3.new(w*.6,H+.01,dp),at(0,yy,0),col,SP,gloss))
  body(part(model,'ClockBody',Vector3.new(w*.87,H+.01,dp*.87),at(0,yy,0),col,SP,gloss))
 end
 -- surface voxels (lighter and darker red), kept off the face
 for i=1,40 do
  local x,yv,z=r(-1,1),r(-1,1),r(-1,.5)
  if not(z>.2 and math.abs(x)<.75 and yv<.75)then
   local p,nrm=surf(x,yv,z)
   local s=r(.16,.3)
   body(part(model,'BodyVoxel',Vector3.new(s,s,s*.6),face(p,nrm)*CFrame.new(0,0,-s*.12),i%3==0 and red2 or red3,SP,gloss))
  end
 end
 -- scuffs and scratches
 for _,sc in ipairs({{-.95,.35,.6,.5},{.9,-.55,.55,-.7},{-.4,-.9,.55,.2},{.55,.95,.3,-.3},{-1.0,-.4,-.4,.9}})do
  local p,nrm=surf(sc[1],sc[2],sc[3],.01)
  body(part(model,'Scratch',Vector3.new(.04,.3,.02),face(p,nrm)*CFrame.Angles(0,0,sc[4]),red2:Lerp(Color3.new(0,0,0),.3),SP))
 end

 -- MOUTH: a huge open maw wrapped round the face, fangs on top, a biting jaw below ---------------
 local my=-.3                                      -- mouth centre height (body space)
 local jaw=at(0,my-.05,.35).Position               -- the jaw's hinge
 local function jawPart(p)return body(p,'AlarmJaw',jaw)end
 local mouthSegs={-.95,-.55,-.18,.18,.55,.95}
 for i=1,#mouthSegs-1 do
  local x0,x1=mouthSegs[i],mouthSegs[i+1]
  local xm=(x0+x1)*.5
  local z0,z1=frontZ(x0,my),frontZ(x1,my)
  local a=Vector3.new(x0,my,z0-.06);local b=Vector3.new(x1,my,z1-.06)
  local mid=(a+b)*.5;local dir=(b-a).Unit
  local n=Vector3.yAxis:Cross(dir).Unit*-1
  if n.Z<0 then n=-n end
  local cf=C*CFrame.fromMatrix(mid,dir,Vector3.yAxis,dir:Cross(Vector3.yAxis))
  body(part(model,'Maw',Vector3.new((b-a).Magnitude+.04,1.0,.24),cf,maw,SP))
  -- upper lip and the fangs hanging from it
  body(part(model,'LipTop',Vector3.new((b-a).Magnitude+.06,.2,.32),cf*CFrame.new(0,.5,.06),red2,SP,gloss))
  -- lower lip / jaw
  jawPart(part(model,'LipBottom',Vector3.new((b-a).Magnitude+.06,.22,.34),cf*CFrame.new(0,-.52,.07),red2,SP,gloss))
  jawPart(part(model,'Jaw',Vector3.new((b-a).Magnitude+.04,.24,.26),cf*CFrame.new(0,-.68,-.02),red,SP,gloss))
  -- fangs: two per segment on top (one big, one small), one or two on the jaw
  local per={{-.24,.5,.34},{.22,.38,.26}}
  if i==3 then per={{-.62,.34,.22},{.62,.3,.2}}end
  for k,ft in ipairs(per)do
   local base=(cf*CFrame.new(ft[1]*(b-a).Magnitude,.42,.16)).Position
   for _,p in ipairs(spike(model,'Fang',base,-(cf.UpVector),cf.RightVector,ft[2],ft[3],.16,bone,SP,{Reflectance=.04}))do body(p)end
  end
  local lper=i==3 and{{-.6,.26,.2},{.62,.3,.2}}or{{.0,.34+(i%2)*.08,.3}}
  for _,ft in ipairs(lper)do
   local base=(cf*CFrame.new(ft[1]*(b-a).Magnitude,-.44,.17)).Position
   for _,p in ipairs(spike(model,'Fang',base,cf.UpVector,cf.RightVector,ft[2],ft[3],.16,bone,SP,{Reflectance=.04}))do jawPart(p)end
  end
 end
 -- mouth corners (dark red cheeks fold in)
 for s=-1,1,2 do
  local p=at(s*1.0,my,frontZ(1.0,my)-.02)
  body(part(model,'MouthCorner',Vector3.new(.2,1.1,.3),p*CFrame.Angles(0,s*-.75,0),red2,SP,gloss))
 end
 -- the clock dial deep in the mouth with its red knife hands (AlarmHand)
 local D=at(0,my+.02,frontZ(0,my)+.03)
 body(cylZ(model,'MawDialRim',.08,.9,D,gold,FO))
 body(cylZ(model,'MawDial',.06,.78,D*CFrame.new(0,0,.04),cream,SP))
 for i=0,11 do
  local a=i/12*math.pi*2
  local big=i%3==0
  body(part(model,'MawDialMark',Vector3.new(big and .05 or .03,big and .11 or .07,.03),D*CFrame.new(math.cos(a)*.3,math.sin(a)*.3,.085)*CFrame.Angles(0,0,a+math.pi/2),black,SP))
 end
 local dc=D.Position
 local function knife(name,length,width,col,amp,angle)
  local k=D*CFrame.Angles(0,0,angle)
  local list={
   part(model,name,Vector3.new(width,length*.72,.04),k*CFrame.new(0,length*.36-.04,.11),col,ME,{Reflectance=.12}),
   part(model,name,Vector3.new(width*.4,length*.2,.045),k*CFrame.new(-width*.1,length*.5,.115),cream,ME,{Reflectance=.2}),
  }
  for _,p in ipairs(spike(model,name..'Tip',(k*CFrame.new(0,length*.72-.04,.11)).Position,k.UpVector,k.RightVector,length*.3,width,.04,col,ME,{Reflectance=.12}))do table.insert(list,p)end
  for _,p in ipairs(list)do body(p,'AlarmHand',dc);p:SetAttribute('PickAmp',amp)end
 end
 knife('KnifeMinute',.42,.1,Color3.fromRGB(214,26,32),1,math.rad(-30))
 knife('KnifeHour',.3,.12,Color3.fromRGB(150,14,20),0,math.rad(110))
 -- the star on the pin (concept detail: the white star on the knife hands)
 for k=0,1 do body(part(model,'DialStar',Vector3.new(.16,.05,.03),D*CFrame.new(0,0,.15)*CFrame.Angles(0,0,k*math.pi/2+math.pi/4),Color3.new(1,1,1),SP),'AlarmHand',dc):SetAttribute('PickAmp',1)end
 body(part(model,'DialPin',Vector3.new(.1,.1,.06),D*CFrame.new(0,0,.14),gold,FO),'AlarmHand',dc):SetAttribute('PickAmp',1)

 -- EYES: two big mad eyes over the mouth, a small third one low on the right ---------------------
 local eyes={ -- body-space centre, look, size, brow tilt
  {Vector3.new(-.6,.52,1.0),Vector3.new(-.22,.1,1),.9,.38},
  {Vector3.new(.6,.6,.96),Vector3.new(.28,.12,1),.78,-.46},
  {Vector3.new(1.12,-.02,.66),Vector3.new(1,.05,.85),.44,-.2},
 }
 for i,e in ipairs(eyes)do
  local pos=cp+e[1];local look=e[2].Unit;local d=e[3]
  local cf=face(pos,look)
  -- socket: a dark red ring of blocks round it
  for k=0,5 do
   local a=k/6*math.pi*2
   body(part(model,'EyeSocket',Vector3.new(d*.4,d*.24,d*.3),cf*CFrame.new(math.cos(a)*d*.5,math.sin(a)*d*.5,-d*.22)*CFrame.Angles(0,0,a+math.pi/2),red2,SP,gloss))
  end
  local pop=look
  for _,p in ipairs(vball('Eye',cf,d,cream,SP,{Reflectance=.05},'AlarmPop',pos,i))do p:SetAttribute('PickPop',pop);p:SetAttribute('PickAmp',1)end
  local iris={
   part(model,'EyeIris',Vector3.new(d*.5,d*.5,.05),cf*CFrame.new(0,0,d*.5),Color3.fromRGB(214,30,34),SP),
   part(model,'EyeIris',Vector3.new(d*.36,d*.62,.045),cf*CFrame.new(0,0,d*.495),Color3.fromRGB(214,30,34),SP),
   part(model,'EyeIris',Vector3.new(d*.62,d*.36,.045),cf*CFrame.new(0,0,d*.495),Color3.fromRGB(214,30,34),SP),
   part(model,'EyeIrisRing',Vector3.new(d*.5,d*.12,.04),cf*CFrame.new(0,d*.22,d*.51),Color3.fromRGB(150,14,20),SP),
   part(model,'EyePupil',Vector3.new(d*.22,d*.22,.06),cf*CFrame.new(0,-d*.02,d*.53),Color3.fromRGB(26,8,10),SP),
   part(model,'EyeGlint',Vector3.new(d*.1,d*.1,.07),cf*CFrame.new(d*.12,d*.12,d*.54),Color3.new(1,1,1),NE,{CastShadow=false}),
  }
  for _,p in ipairs(iris)do body(p,'AlarmPop,AlarmLook',pos,i*1.7);p:SetAttribute('PickPop',pop);p:SetAttribute('PickAmp',1)end
  if d>.5 then -- red veins on the white
   for k,vv in ipairs({{-.36,.2,.5},{.34,-.22,-.6},{-.3,-.3,.9}})do
    local p=part(model,'EyeVein',Vector3.new(d*.22,.025,.03),cf*CFrame.new(vv[1]*d,vv[2]*d,d*.44)*CFrame.Angles(0,0,vv[3]),Color3.fromRGB(220,60,60),SP)
    body(p,'AlarmPop',pos,i);p:SetAttribute('PickPop',pop);p:SetAttribute('PickAmp',1)
   end
  end
  -- the mad brow and the blinking lid
  local brow=cf*CFrame.new(0,d*.66,-d*.05)*CFrame.Angles(0,0,e[4])
  body(part(model,'Brow',Vector3.new(d*1.0,d*.16,d*.4),brow,Color3.fromRGB(60,12,16),SP))
  local lid=part(model,'EyeLid',Vector3.new(d*.84,d*.16,d*.46),cf*CFrame.new(0,d*.5,d*.2),red2,SP,gloss)
  body(lid,'AlarmLid',pos,i*1.3)
 end

 -- RIM SPIKES (cream-white metal) and BOLTS ------------------------------------------------------
 for _,a in ipairs({8,-22,-52,172,202,232,38,142})do
  local rad_=math.rad(a)
  local p,nrm=surf(math.cos(rad_),math.sin(rad_)*.95,.12,-.05)
  local small=(a==38 or a==142)
  local L=small and .34 or .48
  local wdt=small and .22 or .3
  body(part(model,'SpikeBase',Vector3.new(wdt*1.1,wdt*1.1,.12),face(p,nrm),grey2,ME,{Reflectance=.12}))
  local side=nrm:Cross(Vector3.zAxis).Unit
  for _,q in ipairs(spike(model,'Spike',p+nrm*.04,nrm,side,L,wdt,wdt*.6,bone,ME,{Reflectance=.18}))do body(q)end
  for _,q in ipairs(spike(model,'Spike',p+nrm*.04,nrm,Vector3.zAxis,L,wdt*.6,wdt*.6,bone,ME,{Reflectance=.18}))do body(q)end
 end
 for _,b in ipairs({{-1.1,.05,.55},{1.05,.5,.45},{-.95,-.75,.45},{.85,-.85,.5},{-.25,1.0,.55},{.35,-1.1,.5},{-1.25,.3,-.4},{1.2,-.3,-.45},{0,.9,-.75},{-.6,-.6,-.85}})do
  local p,nrm=surf(b[1],b[2],b[3],.02)
  local f=face(p,nrm)
  body(part(model,'Bolt',Vector3.new(.2,.2,.1),f,grey,ME,{Reflectance=.2}))
  body(part(model,'BoltSlot',Vector3.new(.13,.035,.03),f*CFrame.new(0,0,.06)*CFrame.Angles(0,0,math.pi/4),grey2,ME))
  body(part(model,'BoltSlot',Vector3.new(.13,.035,.03),f*CFrame.new(0,0,.06)*CFrame.Angles(0,0,-math.pi/4),grey2,ME))
 end

 -- SIDE PLATES: orange plates with the alarm-set knob ---------------------------------------------
 for s=-1,1,2 do
  local p=at(s*(RX-.02),-.05,-.12)
  local f=p*CFrame.Angles(0,s*math.pi/2,0)
  body(part(model,'SidePlate',Vector3.new(.78,.92,.12),f,orange,ME,{Reflectance=.1}))
  body(part(model,'SidePlateEdge',Vector3.new(.86,.12,.14),f*CFrame.new(0,.48,0),grey,ME))
  body(part(model,'SidePlateEdge',Vector3.new(.86,.12,.14),f*CFrame.new(0,-.48,0),grey,ME))
  for _,q in ipairs({{-.3,.3},{.3,.3},{-.3,-.3},{.3,-.3}})do body(part(model,'SideRivet',Vector3.new(.08,.08,.06),f*CFrame.new(q[1],q[2],.08),grey2,ME))end
  body(cylZ(model,'AlarmKnob',.16,.3,f*CFrame.new(0,0,.14),gold,FO))
  body(part(model,'AlarmKnobGrip',Vector3.new(.08,.26,.08),f*CFrame.new(0,0,.25),Color3.fromRGB(200,150,60),FO))
 end

 -- BACK: a dark plate, an X brace, the turning gear and the gold winding key ---------------------
 local B=at(0,.05,-(RZ-.02))*CFrame.Angles(0,math.pi,0)
 body(part(model,'BackPlate',Vector3.new(1.34,1.3,.12),B,grey2,ME,{Reflectance=.08}))
 for _,q in ipairs({{-.58,.56},{.58,.56},{-.58,-.56},{.58,-.56}})do
  body(part(model,'BackCorner',Vector3.new(.32,.32,.14),B*CFrame.new(q[1],q[2],.04),grey,ME,{Reflectance=.12}))
  body(part(model,'BackBolt',Vector3.new(.1,.1,.06),B*CFrame.new(q[1],q[2],.13),grey2,ME))
 end
 for k=-1,1,2 do body(part(model,'BackBrace',Vector3.new(.14,1.62,.06),B*CFrame.new(0,0,.08)*CFrame.Angles(0,0,k*math.pi/4),black,ME))end
 local gc=(B*CFrame.new(0,0,.12)).Position
 for _,p in ipairs(ring(model,'BackGear',B*CFrame.new(0,0,.13),.36,.12,.08,12,Color3.fromRGB(58,56,62),ME))do body(p,'AlarmGear',gc)end
 for k=0,9 do
  local a=k/10*math.pi*2
  body(part(model,'BackGearTooth',Vector3.new(.12,.12,.08),B*CFrame.new(math.cos(a)*.47,math.sin(a)*.47,.13)*CFrame.Angles(0,0,a),Color3.fromRGB(58,56,62),ME),'AlarmGear',gc)
 end
 local kc=(B*CFrame.new(0,0,.2)).Position
 local key={
  cylZ(model,'WindKeyStem',.36,.12,B*CFrame.new(0,0,.3),gold,FO),
  part(model,'WindKeyBow',Vector3.new(.28,.42,.07),B*CFrame.new(-.2,0,.5),gold,FO),
  part(model,'WindKeyBow',Vector3.new(.28,.42,.07),B*CFrame.new(.2,0,.5),gold,FO),
  part(model,'WindKeyBow',Vector3.new(.16,.2,.08),B*CFrame.new(0,0,.5),Color3.fromRGB(214,160,60),FO),
 }
 for _,p in ipairs(key)do body(p,'AlarmKey',kc)end

 -- TOP: two riveted bells, the striker between them, the red snooze light ------------------------
 for s=-1,1,2 do
  local base=at(s*.72,RY-.14,-.06)*CFrame.Angles(0,0,s*-math.rad(30))
  local bj=base.Position
  local function bell(p)return body(p,'AlarmBell',bj,s)end
  bell(rod(model,'BellLeg',base.Position,(base*CFrame.new(0,.34,0)).Position,.14,grey2,ME))
  local bc=base*CFrame.new(0,.36,0)
  for _,p in ipairs(oct('BellRim',bc*CFrame.new(0,.04,0),1.0,.12,gold,FO))do bell(p)end
  for _,p in ipairs(oct('Bell',bc*CFrame.new(0,.18,0),.92,.2,grey,ME,{Reflectance=.16}))do bell(p)end
  for _,p in ipairs(oct('Bell',bc*CFrame.new(0,.36,0),.82,.18,grey,ME,{Reflectance=.16}))do bell(p)end
  for _,p in ipairs(oct('Bell',bc*CFrame.new(0,.5,0),.64,.12,Color3.fromRGB(146,144,150),ME,{Reflectance=.16}))do bell(p)end
  for _,p in ipairs(oct('Bell',bc*CFrame.new(0,.6,0),.4,.1,Color3.fromRGB(160,158,164),ME,{Reflectance=.16}))do bell(p)end
  bell(part(model,'BellKnob',Vector3.new(.18,.14,.18),bc*CFrame.new(0,.71,0),grey2,ME))
  for k=0,7 do
   local a=k/8*math.pi*2
   bell(part(model,'BellRivet',Vector3.new(.09,.09,.09),bc*CFrame.new(math.cos(a)*.47,.24,math.sin(a)*.47),grey2,ME))
  end
 end
 -- the striker (swings between the bells: AlarmHammer about its foot)
 local hb=at(0,RY-.08,-.3).Position
 for _,p in ipairs({
  part(model,'StrikerPost',Vector3.new(.1,.6,.1),CFrame.new(hb+Vector3.new(0,.3,0)),grey2,ME),
  part(model,'Striker',Vector3.new(.24,.2,.2),CFrame.new(hb+Vector3.new(0,.66,0)),grey,ME,{Reflectance=.2}),
 })do body(p,'AlarmHammer',hb)end
 -- snooze button and its light
 for _,p in ipairs(oct('Snooze',at(0,RY+.02,.12),.62,.16,grey,ME,{Reflectance=.12}))do body(p)end
 for _,p in ipairs(oct('Snooze',at(0,RY+.14,.12),.42,.12,grey2,ME))do body(p)end
 local lamp=part(model,'SnoozeLight',Vector3.new(.22,.16,.22),at(0,RY+.26,.12),Color3.fromRGB(255,40,40),NE,{CastShadow=false})
 lamp:SetAttribute('PickPulse',true);body(lamp)

 -- GLOW and IDLE FX: a red light in the head, a few faint red sparks round it --------------------
 local glow=part(model,'AlarmGlow',Vector3.new(.4,.4,.4),at(0,0,.6),red,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='AlarmLight';light.Color=Color3.fromRGB(255,70,56);light.Range=7;light.Brightness=.7;light.Shadows=false;light.Parent=glow
 local sp=part(model,'AlarmSparks',Vector3.new(3,2.6,1.6),C,red,SP,{Transparency=1,CastShadow=false})
 local pe=Instance.new('ParticleEmitter');pe.Name='AlarmSparkFX';pe.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pe.Rate=1.2;pe.Lifetime=NumberRange.new(.5,.9);pe.Speed=NumberRange.new(.3,1);pe.SpreadAngle=Vector2.new(180,180)
 pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
 pe.Color=ColorSequence.new(Color3.fromRGB(255,120,90),Color3.fromRGB(255,40,40));pe.Parent=sp
 -- On the back: a bit higher and further out, so the big head clears the character's own head.
 model:SetAttribute('BackC0',CFrame.new(.35,.1,.3))
 return (C*CFrame.new(-RX-.5,0,0)).Position,(C*CFrame.new(RX+.5,0,0)).Position
end

-- Ponycorn-Dolphoodle ("Кирка Понирог-Дельфудель", MYTHIC concept sheet): a magic pony head on a
-- twisted caramel stick. Front (+Z): a cream-gold pony face with huge magenta anime eyes (lashes,
-- two glints), heart blushes, a cream muzzle with a smile; golden ears, a gold tiara with a pink
-- heart gem, a rainbow spiral unicorn horn with glowing edges tilted forward. Pink poodle fluff
-- (cotton-candy balls with gold stars) frames the face and piles up behind. The pick arms are two
-- golden dolphin fins (glossy caramel crescents curling down into points, pearlescent pink ->
-- lilac -> sky membranes, gold rims, little hearts) with gold chains of heart and star charms; a
-- golden dolphin body arcs behind the head into a pearly dorsal fin. Under the head: a pink bow with
-- a gold-framed heart, pearl leaf cuffs and a heart gem; the stick is two twisted strands of pink and
-- gold candy. Bottom: a poodle pompom with a gold heart, stars, golden tail crescents and a gold
-- point. Glass = glossy candy / gems, Foil = jewellery gold, Fabric = fluff, Neon = horn energy only.
-- Moving parts (MiningClient.PickFX): PonyFluff (fluff breathes, bounces on a run / a strike),
-- PonyFin (fins flap from the root, PickAmp = side), PonyCharm (charms swing on PickHang below the
-- fin), PonyBlink (lids), PonyHalo (the inspect halo turns round the horn, PickPop = horn axis),
-- PonyTail (the pommel fluke wags). The horn's slices cycle the rainbow (PickRainbow); its core
-- pulses (PickPulse) and its light / halo flare up during the inspect (PickFX e.Pony).
DESIGNS.Ponycorn=function(model,v,def,len,top)
 local GL,SP,FO,FA,NE=Enum.Material.Glass,Enum.Material.SmoothPlastic,Enum.Material.Foil,Enum.Material.Fabric,Enum.Material.Neon
 local caramel=rgb(v.Shaft)                      -- glossy caramel gold
 local face=rgb(v.Head)                          -- cream-gold pony face
 local pink=rgb(v.Accent)                        -- candy pink
 local fin=rgb(v.Fin)                            -- sky blue (membrane end)
 local pearl=rgb(v.Trim)                         -- pearl white
 local gold=Color3.fromRGB(255,190,56)           -- jewellery gold
 local deepGold=Color3.fromRGB(232,150,30)
 local muzzle=Color3.fromRGB(255,240,214)
 local fluffA,fluffB,fluffC=Color3.fromRGB(255,178,214),Color3.fromRGB(255,206,228),Color3.fromRGB(252,148,196)
 local lilac=Color3.fromRGB(206,168,255)
 local mint=Color3.fromRGB(140,236,190)
 local gemPink=Color3.fromRGB(255,62,150)
 local small={CastShadow=false}
 local K=1.2                                      -- the head assembly is built at 1/K and scaled up
 local C=CFrame.new(0,len*.5-.12,0)               -- head centre (model space)
 model.PrimaryPart.Transparency=1                 -- the thin Handle hides inside the candy stick
 local cp=C.Position
 local function at(x,y,z)return C*CFrame.new(x,y,z)end
 local function each(list,fn)for _,p in ipairs(list)do fn(p)end;return list end
 -- A flat heart in the XY plane of cf (facing +Z): a diamond and two half-sunk domes; w = width.
 local function heart(name,cf,w,depth,color,mat,props)
  local a=w/1.71;local h=a/math.sqrt(2);local c=cf*CFrame.new(0,-.073*a,0)
  return{
   part(model,name,Vector3.new(a,a,depth),c*CFrame.Angles(0,0,math.pi/4),color,mat,props),
   blob(model,name,Vector3.new(a,a,depth),c*CFrame.new(-h/2,h/2,0),color,mat,props),
   blob(model,name,Vector3.new(a,a,depth),c*CFrame.new(h/2,h/2,0),color,mat,props),
  }
 end
 -- A gold-framed gem heart (rim behind, glossy pink in front).
 local function gemHeart(name,cf,w,depth)
  local out=heart(name..'Rim',cf*CFrame.new(0,0,-depth*.3),w*1.3,depth,gold,FO,small)
  for _,p in ipairs(heart(name,cf*CFrame.new(0,0,depth*.25),w,depth,gemPink,GL,{CastShadow=false,Reflectance=.12}))do table.insert(out,p)end
  return out
 end
 -- A five-point star in the XY plane of cf: a disc and five flat points (two wedges each).
 local function star(name,cf,r,thick,color,mat)
  local out={cylZ(model,name,thick,r*.86,cf,color,mat,small)}
  local zx=cf.ZVector
  for k=0,4 do
   local a=math.pi/2+k*math.pi*2/5
   local dir=cf:VectorToWorldSpace(Vector3.new(math.cos(a),math.sin(a),0))
   for _,w in ipairs(spike(model,name,cf.Position+dir*r*.28,dir,zx:Cross(dir),r*.78,r*.62,thick,color,mat,small))do table.insert(out,w)end
  end
  return out
 end
 local function bez(p0,p1,p2,p3,t)local u=1-t;return p0*u*u*u+p1*3*u*u*t+p2*3*u*t*t+p3*t*t*t end
 -- Frames along a cubic curve lying in a plane with normal pn: X along the curve, Y = pn x X.
 local function frames(p0,p1,p2,p3,n,pn,flip)
  local function pt(t)return bez(p0,p1,p2,p3,math.clamp(t,0,1))end
  local total=0;for i=1,40 do total+=(pt(i/40)-pt((i-1)/40)).Magnitude end
  local out={}
  for i=1,n do
   local t=(i-.5)/n;local pos=pt(t);local tan=(pt(t+.01)-pt(t-.01)).Unit
   local Y=pn:Cross(tan).Unit*(flip or 1)
   out[i]={T=t,Pos=pos,Tan=tan,N=Y,CF=CFrame.fromMatrix(pos,tan,Y,tan:Cross(Y)),Seg=total/n}
  end
  return out,pt
 end
 -- Poodle fluff: a big cotton ball and n smaller ones round it (golden-angle spread, identical on
 -- every peer), all breathing together (PonyFluff, phase ph).
 local fluffCount=0
 local function fluff(center,r,n,ph,colors)
  fluffCount+=1
  local out={}
  local cols=colors or{fluffA,fluffB,fluffC}
  table.insert(out,anim(ball(model,'Fluff',r,CFrame.new(center),cols[1],FA),'PonyFluff',ph))
  for i=1,n do
   local a=i*2.39996+fluffCount;local yy=.55-(i-.5)/n*1.1
   local rr=math.sqrt(1-yy*yy)
   local dir=Vector3.new(math.cos(a)*rr,yy*.8,math.sin(a)*rr)
   local d=r*(.52+(i%3)*.07)
   table.insert(out,anim(ball(model,'Fluff',d,CFrame.new(center+dir*r*.42),cols[(i%#cols)+1],FA),'PonyFluff',ph))
  end
  return out
 end

 -- HEAD: cream-gold pony skull, cheeks and a long cream muzzle ------------------------------------
 blob(model,'PonySkull',Vector3.new(.98,.92,.9),at(0,.14,-.02),face,SP)
 blob(model,'PonyCheeks',Vector3.new(.9,.74,.82),at(0,-.1,.1),face,SP)
 blob(model,'PonyMuzzle',Vector3.new(.62,.46,.66),at(0,-.4,.42),muzzle,SP)
 blob(model,'PonyNose',Vector3.new(.46,.28,.32),at(0,-.32,.58),muzzle,SP)
 blob(model,'PonyGloss',Vector3.new(.3,.1,.2),at(-.18,.5,.24)*CFrame.Angles(.5,0,.3),Color3.fromRGB(255,246,220),SP,small)
 for _,s in ipairs({-1,1})do blob(model,'Nostril',Vector3.new(.06,.035,.03),at(s*.1,-.32,.735)*CFrame.Angles(0,0,s*.4),Color3.fromRGB(226,140,160),SP,small)end
 local smile={at(-.15,-.5,.66),at(-.06,-.55,.7),at(.06,-.55,.7),at(.15,-.5,.66)}
 for i=1,3 do rod(model,'Smile',smile[i].Position,smile[i+1].Position,.035,Color3.fromRGB(196,84,120),SP,small)end
 -- EYES: big magenta anime eyes (outline, iris, light lower iris, pupil, two glints, lash line,
 -- three lashes) under face-coloured lids that blink (PonyBlink).
 for _,s in ipairs({-1,1})do
  local E=at(s*.25,.06,.4)*CFrame.Angles(0,s*.34,0)
  blob(model,'EyeLine',Vector3.new(.31,.37,.08),E,Color3.fromRGB(56,16,56),SP,small)
  blob(model,'EyeIris',Vector3.new(.26,.32,.08),E*CFrame.new(0,-.005,.014),Color3.fromRGB(206,40,156),GL,small)
  blob(model,'EyeIrisLight',Vector3.new(.19,.13,.06),E*CFrame.new(0,-.08,.035),Color3.fromRGB(255,124,214),GL,small)
  blob(model,'EyePupil',Vector3.new(.12,.16,.06),E*CFrame.new(0,.01,.045),Color3.fromRGB(64,8,64),SP,small)
  ball(model,'EyeGlint',.08,E*CFrame.new(s*-.045,.075,.065),Color3.new(1,1,1),NE,small)
  ball(model,'EyeGlint',.04,E*CFrame.new(s*.05,-.07,.062),Color3.new(1,1,1),NE,small)
  part(model,'EyeLash',Vector3.new(.2,.05,.05),E*CFrame.new(-s*.04,.168,.03),Color3.fromRGB(40,14,40),SP,small)
  part(model,'EyeLash',Vector3.new(.13,.045,.05),E*CFrame.new(s*.1,.16,.03)*CFrame.Angles(0,0,s*.45),Color3.fromRGB(40,14,40),SP,small)
  for k=1,2 do
   local base=(E*CFrame.new(s*(.07+k*.045),.16+k*.008,.04)).Position
   spike(model,'EyeLash',base,Vector3.new(s*.75,.66,0),Vector3.new(-.66,s*.75,0),.07+k*.015,.045,.03,Color3.fromRGB(40,14,40),SP,small)
  end
  anim(blob(model,'EyeLid',Vector3.new(.34,.38,.1),E*CFrame.new(0,.37,-.03),face,SP),'PonyBlink',0,E.Position)
  -- a pink heart blush on each cheek
  heart('Blush',at(s*.37,-.19,.37)*CFrame.Angles(0,s*.62,0),.14,.04,Color3.fromRGB(255,112,166),SP,small)
 end
 -- EARS: golden points with pink insides, tilted out.
 for _,s in ipairs({-1,1})do
  local base=at(s*.32,.56,-.04).Position
  local dir=Vector3.new(s*.42,1,-.1).Unit
  local nrm=Vector3.new(1,-s*.42,0).Unit;nrm=(nrm-dir*nrm:Dot(dir)).Unit
  spike(model,'PonyEar',base,dir,nrm,.56,.32,.13,Color3.fromRGB(255,206,100),GL)
  spike(model,'PonyEarIn',base+Vector3.new(0,.03,.07),dir,nrm,.44,.2,.05,Color3.fromRGB(255,150,190),SP,small)
 end
 -- TIARA: a gold band round the forehead, three points, a pink heart gem and two small gems.
 for i=-2,2 do
  local a=i*.42
  part(model,'Tiara',Vector3.new(.2,.08,.05),C*CFrame.new(0,.5,-.04)*CFrame.Angles(0,a,0)*CFrame.new(0,0,.43)*CFrame.Angles(-.25,0,0),gold,FO,small)
 end
 for _,pt in ipairs({{0,.3,.24},{-.17,.18,.14},{.17,.18,.14}})do
  local base=(C*CFrame.new(pt[1],.52,.4)).Position
  local dir=Vector3.new(pt[1]*.6,1,.15).Unit
  spike(model,'TiaraPoint',base,dir,(Vector3.xAxis-dir*dir.X).Unit,pt[2],pt[3],.05,gold,FO,small)
 end
 gemHeart('TiaraHeart',at(0,.62,.44)*CFrame.Angles(-.2,0,0),.15,.06)
 ball(model,'TiaraGem',.07,at(-.24,.56,.38),mint,GL,small)
 ball(model,'TiaraGem',.07,at(.24,.56,.38),Color3.fromRGB(120,200,255),GL,small)

 -- HORN: rainbow spiral slices round a glowing core, a pearly spiral ridge, a crystal point ------
 local hornDir=Vector3.new(0,.9,.43).Unit
 local hornBase=at(0,.6,.14).Position
 local hornLen=1.36
 local HN=9
 local hues={Color3.fromRGB(255,130,200),Color3.fromRGB(255,176,120),Color3.fromRGB(255,232,110),Color3.fromRGB(150,240,170),
  Color3.fromRGB(120,206,255),Color3.fromRGB(176,150,255),Color3.fromRGB(230,140,255),Color3.fromRGB(255,140,210),Color3.fromRGB(255,230,150)}
 for i=0,HN-1 do
  local f=(i+.5)/HN
  local d=.48*(1-f*.76)
  local c=CFrame.new(hornBase+hornDir*hornLen*f*.92)*alignY(hornDir)*CFrame.Angles(0,i*.7,0)
  local sl=part(model,'HornSlice',Vector3.new(hornLen/HN*1.08,d,d),c*CFrame.Angles(i%2==0 and .1 or -.1,0,math.pi/2),hues[i+1],GL,{Transparency=.18,CastShadow=false,Shape=Enum.PartType.Cylinder})
  sl:SetAttribute('PickRainbow',true);sl:SetAttribute('PickPhase',i*.09)
  ball(model,'HornRidge',d*.3,c*CFrame.new(math.cos(i*1.9)*d*.46,0,math.sin(i*1.9)*d*.46),pearl,GL,small)
 end
 local hornTip=hornBase+hornDir*hornLen
 local tipBase=hornBase+hornDir*hornLen*.86
 for _,nrm in ipairs({Vector3.new(1,0,0),hornDir:Cross(Vector3.new(1,0,0))})do
  spike(model,'HornTip',tipBase,hornDir,nrm,hornLen*.18,.13,.12,Color3.fromRGB(240,190,255),GL,small)
 end
 local core=part(model,'HornCore',Vector3.new(.13,hornLen*.84,.13),CFrame.new(hornBase+hornDir*hornLen*.42)*alignY(hornDir),Color3.fromRGB(255,214,250),NE,{CastShadow=false,Transparency=.15})
 core:SetAttribute('PickPulse',true)
 local glow=Instance.new('PointLight');glow.Name='HornGlow';glow.Color=Color3.fromRGB(255,170,230);glow.Range=7;glow.Brightness=.8;glow.Shadows=false;glow.Parent=core
 -- inspect halo (hidden until PickFX shows it): a gold ring round the upper horn
 local haloC=CFrame.new(hornBase+hornDir*hornLen*.78)*alignY(hornDir)*CFrame.Angles(math.pi/2,0,0)
 for _,p in ipairs(ring(model,'HornHalo',haloC,.5,.06,.06,10,Color3.fromRGB(255,232,130),NE,nil,{Transparency=1,CastShadow=false}))do
  anim(p,'PonyHalo',0,haloC.Position);p:SetAttribute('PickPop',hornDir)
 end

 -- POODLE FLUFF with gold stars -------------------------------------------------------------------
 fluff(at(-.6,-.16,-.06).Position,.66,5,0)
 fluff(at(.6,-.16,-.06).Position,.66,5,.9)
 fluff(at(-.42,-.58,.02).Position,.44,3,.4)
 fluff(at(.42,-.58,.02).Position,.44,3,1.3)
 fluff(at(-.22,.4,.26).Position,.32,2,.2,{fluffB,fluffA})
 fluff(at(.2,.42,.22).Position,.29,2,.7,{fluffB,fluffA})
 fluff(at(-.5,.38,-.1).Position,.42,2,1.1)
 fluff(at(.5,.36,-.1).Position,.4,2,1.9)
 fluff(at(0,.52,-.36).Position,.66,4,1.6)
 fluff(at(0,.16,-.6).Position,.7,4,2.1)
 fluff(at(-.3,.88,-.55).Position,.5,2,2.6)
 fluff(at(.32,.82,-.48).Position,.46,2,3.1)
 local function stuck(cf,r,color,ph)each(star('FluffStar',cf,r,.06,color,color==gold and FO or GL),function(p)anim(p,'PonyFluff',ph)end)end
 stuck(at(-.7,-.06,.28)*CFrame.Angles(0,-.5,.2),.13,gold,0)
 stuck(at(-.4,.66,.16)*CFrame.Angles(0,-.3,-.3),.11,gold,1.6)
 stuck(at(.66,-.3,.26)*CFrame.Angles(0,.55,.4),.1,mint,.9)

 -- FINS: golden dolphin crescents with pearlescent membranes, gold rims, hearts and charms --------
 local FN=9
 local tips={}
 for _,s in ipairs({-1,1})do
  local P0,P1,P2,P3=cp+Vector3.new(s*.4,-.24,-.16),cp+Vector3.new(s*.88,.14,-.26),cp+Vector3.new(s*1.34,.12,-.42),cp+Vector3.new(s*1.38,-.46,-.5)
  local fr=frames(P0,P1,P2,P3,FN,Vector3.zAxis,s)
  local root=P0
  local function flap(p,extra)anim(p,'PonyFin'..(extra and(','..extra)or''),0,root);p:SetAttribute('PickAmp',s);return p end
  for i,f in ipairs(fr)do
   local t=f.T
   local th=.25*(1-t*.45);local dp=.26*(1-t*.35)
   flap(part(model,'FinBand',Vector3.new(f.Seg*1.3,th,dp),f.CF,caramel:Lerp(deepGold,t*.35),GL))
   local w=.4*(1-t)^.75*math.min(1,(t+.12)*2.6)+.03
   local mc=t<.5 and pink:Lerp(lilac,t*2)or lilac:Lerp(fin,(t-.5)*2)
   flap(part(model,'FinMembrane',Vector3.new(f.Seg*1.24,w,.06),f.CF*CFrame.new(0,th*.45+w*.5,-.02),mc:Lerp(pearl,.18),GL,{Transparency=.2,CastShadow=false}))
   if i<FN then
    flap(part(model,'FinRim',Vector3.new(f.Seg*1.2,.05,.08),f.CF*CFrame.new(0,th*.45+w+.01,-.02),gold,FO,small))
   end
   if i%3==2 then -- pearly fin rays
    flap(part(model,'FinRay',Vector3.new(.03,w*.8,.07),f.CF*CFrame.new(0,th*.45+w*.45,-.01)*CFrame.Angles(0,0,-.35),pearl,GL,{Transparency=.35,CastShadow=false}))
   end
  end
  local last=fr[FN]
  local tipBase=last.Pos+last.Tan*last.Seg*.5
  for _,w in ipairs(spike(model,'FinTip',tipBase,last.Tan,last.N,.34,.13,.15,deepGold,GL))do flap(w)end
  tips[s]=tipBase+last.Tan*.34
  -- a heart and a little star stuck on the band
  local hf=fr[4]
  each(heart('FinHeart',CFrame.new(hf.Pos+Vector3.new(0,0,.14))*CFrame.Angles(0,0,-s*.2),.17,.06,gemPink,GL,small),flap)
  flap(ball(model,'FinGem',.08,CFrame.new(fr[6].Pos+Vector3.new(0,0,.12)),s<0 and mint or Color3.fromRGB(120,200,255),GL,small))
  -- charm chains hanging under the fin: gold links, a gem heart, a gold star
  local function chain(f,links,withStar,ph)
   local hang=f.Pos-f.N*.1
   local y=0
   local function charm(p)flap(p,'PonyCharm');p:SetAttribute('PickHang',hang-root);p:SetAttribute('PickPhase',ph);return p end
   for k=1,links do
    y+=.1
    charm(part(model,'ChainLink',Vector3.new(.05,.13,.09),CFrame.new(hang-Vector3.new(0,y,0))*CFrame.Angles(0,k%2==0 and math.pi/2 or 0,0),gold,FO,small))
   end
   y+=.13
   each(gemHeart('CharmHeart',CFrame.new(hang-Vector3.new(0,y,0)),.17,.06),charm)
   if withStar then
    for k=1,2 do y+=.1;charm(part(model,'ChainLink',Vector3.new(.05,.13,.09),CFrame.new(hang-Vector3.new(0,y,0))*CFrame.Angles(0,k%2==0 and math.pi/2 or 0,0),gold,FO,small))end
    y+=.12
    each(star('CharmStar',CFrame.new(hang-Vector3.new(0,y,0)),.12,.06,gold,FO),charm)
   end
  end
  chain(fr[8],3,true,s<0 and 0 or 1.3)
  if s<0 then chain(fr[5],2,false,.7)end
 end

 -- DOLPHIN BODY: a golden crescent arching behind the head into a pearly dorsal fin ---------------
 do
  local fr=frames(cp+Vector3.new(0,.62,-.42),cp+Vector3.new(0,1.08,-1.0),cp+Vector3.new(0,-.1,-1.22),cp+Vector3.new(0,-.88,-.5),7,Vector3.xAxis,1)
  for i,f in ipairs(fr)do
   local th=.3*(1-math.abs(f.T-.4)*.9)
   part(model,'DolphinBody',Vector3.new(f.Seg*1.3,th,.3*(1-f.T*.3)),f.CF,caramel:Lerp(deepGold,f.T*.4),GL)
   if i>=2 and i<=5 then
    local w=.42*math.sin((i-1.5)/4.5*math.pi)
    part(model,'DorsalFin',Vector3.new(f.Seg*1.2,w,.06),f.CF*CFrame.new(0,th*.45+w*.5,0),lilac:Lerp(fin,(i-2)/3):Lerp(pearl,.2),GL,{Transparency=.2,CastShadow=false})
   end
  end
 end

 -- Scale the whole head assembly (face, fluff, horn, fins, charms, dolphin body) by K round its
 -- centre: the concept's head is big against the stick. Joints / hang points scale with it.
 for _,p in ipairs(model:GetChildren())do
  if p:IsA('BasePart')and p~=model.PrimaryPart then
   local rel=C:ToObjectSpace(p.CFrame)
   p.Size*=K;p.CFrame=C*CFrame.new(rel.Position*K)*rel.Rotation
   local j=p:GetAttribute('PickJoint');if typeof(j)=='Vector3'then p:SetAttribute('PickJoint',cp+(j-cp)*K)end
   local h=p:GetAttribute('PickHang');if typeof(h)=='Vector3'then p:SetAttribute('PickHang',h*K)end
  end
 end
 tips[-1]=cp+(tips[-1]-cp)*K;tips[1]=cp+(tips[1]-cp)*K
 glow.Range=7*K

 -- NECK, BOW, CUFFS, HEART GEM -----------------------------------------------------------------
 local neckTop,neckBot=cp.Y-.62*K,cp.Y-1.02*K
 cylY(model,'Neck',neckTop-neckBot+.1,.44,CFrame.new(0,(neckTop+neckBot)*.5,0),caramel,GL)
 blob(model,'Neck',Vector3.new(.5,.5,.5),CFrame.new(0,neckTop+.05,-.02),caramel,GL)
 blob(model,'NeckBelly',Vector3.new(.3,.5,.12),CFrame.new(0,neckTop-.12,.2),Color3.fromRGB(255,236,190),GL,small)
 local by=neckBot-.06
 cylY(model,'Collar',.1,.52,CFrame.new(0,by+.14,0),gold,FO)
 local bow={blob(model,'BowKnot',Vector3.new(.2,.18,.14),CFrame.new(0,by,.25),gemPink,GL)}
 for _,s in ipairs({-1,1})do
  table.insert(bow,blob(model,'BowLoop',Vector3.new(.38,.26,.13),CFrame.new(s*.22,by+.03,.21)*CFrame.Angles(0,-s*.25,s*.35),gemPink,GL))
  table.insert(bow,blob(model,'BowLoopIn',Vector3.new(.16,.1,.06),CFrame.new(s*.24,by+.03,.28)*CFrame.Angles(0,-s*.25,s*.35),Color3.fromRGB(200,30,110),SP,small))
  table.insert(bow,blob(model,'BowTail',Vector3.new(.12,.3,.06),CFrame.new(s*.13,by-.2,.22)*CFrame.Angles(0,0,s*.45),gemPink,GL))
 end
 for _,p in ipairs(gemHeart('BowHeart',CFrame.new(0,by,.33),.17,.06))do table.insert(bow,p)end
 for _,p in ipairs(bow)do -- the bow is built small and scaled up round its knot
  local rel=CFrame.new(0,by,.25):ToObjectSpace(p.CFrame)
  p.Size*=1.3;p.CFrame=CFrame.new(0,by,.25)*CFrame.new(rel.Position*1.3)*rel.Rotation
 end
 local cy=by-.26
 cylY(model,'Collar',.1,.46,CFrame.new(0,cy,0),gold,FO)
 for k=0,3 do
  local a=math.pi/4+k*math.pi/2
  local o=Vector3.new(math.cos(a),0,math.sin(a))
  spike(model,'Cuff',Vector3.new(0,cy-.02,0)+o*.16,(o*.32+Vector3.new(0,-1,0)).Unit,Vector3.new(-o.Z,0,o.X),.38,.2,.05,pearl:Lerp(Color3.fromRGB(255,190,225),.3),GL,small)
 end
 cylY(model,'Ferrule',.34,.4,CFrame.new(0,cy-.22,0),caramel,GL)
 gemHeart('ShaftHeart',CFrame.new(0,cy-.22,.21),.15,.05)
 spike(model,'ShaftHeartDrop',Vector3.new(0,cy-.33,.22),Vector3.new(0,-1,0),Vector3.new(1,0,0),.14,.08,.04,gold,FO,small)
 cylY(model,'Collar',.08,.44,CFrame.new(0,cy-.42,0),gold,FO)

 -- STICK: two twisted candy strands (pink and gold) round a caramel core ---------------------------
 local sTop,sBot=cy-.44,-len*.5+.18
 cylY(model,'CandyCore',sTop-sBot,.3,CFrame.new(0,(sTop+sBot)*.5,0),caramel,GL)
 local SN=15
 for _,strand in ipairs({{pink,0},{caramel:Lerp(Color3.fromRGB(255,232,150),.25),math.pi}})do
  local prev
  for i=0,SN do
   local t=i/SN;local a=strand[2]+t*2.6*math.pi*2
   local q=Vector3.new(math.cos(a)*.1,sTop+(sBot-sTop)*t,math.sin(a)*.1)
   if prev then local dir=(q-prev).Unit;rod(model,'CandyStrand',prev-dir*.06,q+dir*.06,.27,strand[1],GL,{Reflectance=.06})end
   prev=q
  end
 end
 cylY(model,'Collar',.09,.44,CFrame.new(0,sBot,0),gold,FO)

 -- POMMEL: poodle pompom, gold heart, stars, golden tail crescents and a gold point ---------------
 local pb=Vector3.new(0,-len*.5-.38,0)
 cylY(model,'PommelCap',.14,.5,CFrame.new(0,sBot-.09,0),gold,FO)
 local pom=fluff(pb,1.0,8,.5)
 for _,p in ipairs(pom)do p.Name='PomFluff' end
 for _,o in ipairs({Vector3.new(-.22,.36,.1),Vector3.new(.24,.34,-.08),Vector3.new(0,-.36,.05)})do
  anim(ball(model,'PomFluff',.46,CFrame.new(pb+o),fluffB,FA),'PonyFluff',.5)
 end
 each(gemHeart('PommelHeart',CFrame.new(pb+Vector3.new(.06,.08,.5)),.26,.08),function(p)anim(p,'PonyFluff',.5)end)
 each(star('PommelStar',CFrame.new(pb+Vector3.new(-.3,.38,.32))*CFrame.Angles(-.3,-.3,.2),.13,.06,gold,FO),function(p)anim(p,'PonyFluff',.5)end)
 each(star('PommelStar',CFrame.new(pb+Vector3.new(-.26,-.26,.42))*CFrame.Angles(0,-.4,-.3),.12,.06,Color3.fromRGB(110,206,255),GL),function(p)anim(p,'PonyFluff',.5)end)
 -- golden crescents hugging the pompom (front view) and the dolphin fluke curling behind it (side)
 for _,s in ipairs({-1,1})do
  local fr=frames(pb+Vector3.new(s*.22,.5,.08),pb+Vector3.new(s*.66,.48,.12),pb+Vector3.new(s*.78,.02,.14),pb+Vector3.new(s*.5,-.34,.2),4,Vector3.zAxis,-s)
  for _,f in ipairs(fr)do part(model,'PommelCrescent',Vector3.new(f.Seg*1.3,.15*(1-f.T*.5),.18),f.CF,caramel:Lerp(deepGold,f.T*.4),GL,small)end
 end
 do
  local root=pb+Vector3.new(0,.05,-.4)
  local fr=frames(root,pb+Vector3.new(0,.45,-.95),pb+Vector3.new(0,-.2,-1.12),pb+Vector3.new(0,-.5,-.7),5,Vector3.xAxis,1)
  for i,f in ipairs(fr)do
   anim(part(model,'TailFluke',Vector3.new(f.Seg*1.3,.16*(1-f.T*.4),.16),f.CF,caramel:Lerp(deepGold,f.T*.4),GL),'PonyTail',0,root)
   if i<=4 then
    local w=.3*(1-f.T)
    anim(part(model,'TailMembrane',Vector3.new(f.Seg*1.2,w,.05),f.CF*CFrame.new(0,-.08-w*.5,0),pink:Lerp(fin,f.T):Lerp(pearl,.2),GL,{Transparency=.2,CastShadow=false}),'PonyTail',0,root)
   end
  end
 end
 local tipTop=pb+Vector3.new(0,-.5,0)
 for _,nrm in ipairs({Vector3.new(1,0,0),Vector3.new(0,0,1)})do
  spike(model,'PommelPoint',tipTop,Vector3.new(0,-1,0),nrm,.36,.24,.22,gold,FO)
 end

 -- IDLE FX: a few soft sparkles round the head (the floating stars are PickFX glyphs) --------------
 local holder=part(model,'PonySparkles',Vector3.new(2.6,2,1.4),at(0,.3,0),pink,SP,{Transparency=1,CastShadow=false})
 local fx=emitter(holder,'Sparkle',Color3.fromRGB(255,170,225))
 if fx then
  fx.Rate=2.2
  fx.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,150,220)),ColorSequenceKeypoint.new(.5,Color3.fromRGB(255,236,140)),ColorSequenceKeypoint.new(1,Color3.fromRGB(170,210,255))})
 end
 -- On the back: a little higher and further out, so the fluffy head clears the wearer's head.
 model:SetAttribute('BackC0',CFrame.new(.3,-.1,.45))
 return tips[-1],tips[1]
end

-- Zombie-Frankenstein ("Кирка Зомби-Франкенштейн" concept sheet, Legendary / Undead): a cursed pickaxe
-- stitched together from dead flesh, old machines and forgotten experiments. The head: a blocky zombie
-- skull of mottled rotten-green skin with pink flesh patches, uneven stitches with bone-white staples,
-- rusty plates, bolts and slime running over it; a yellow, half-lidded living eye on the left and a big
-- glowing blue MECHANICAL eye in a bolted rusty socket on the right; a bony nose hole and a wide jaw of
-- crooked bone teeth over a dark maw. Out of the left of the skull grows the long rising FLESH BLADE
-- (stitched skin, rusty blocks and bolts along its top, bone shards along the cutting edge, slime
-- dripping off it); on the right a cluster of rusty blocks with a big hex neck bolt and a down-curving
-- slime-coated CLAW with a bone point. On top a Tesla coil (rusty hex cap, coil rings, red and blue
-- wires) crackling with blue sparks; on the back a pink stitched flesh panel, rusty plates and a second
-- bolt. Under the jaw a rusty collar; off it on chains hang the glowing green SUBSTANCE VIAL (rusty
-- caps, a skull mark) and a little bone skull charm. The shaft: bone vertebrae with knobs, rusty
-- bolted brackets and red / blue wires winding round it, slime runs; dark metal straps on the grip; a
-- rusty pommel block with bone knuckles and a loose red wire.
-- Materials: Leather (skin, flesh), Limestone (bone), SmoothPlastic (teeth enamel, eyes),
-- CorrodedMetal (rust), Metal (dark steel, coil), Rubber (wires), Glass (slime, the vial), Neon only
-- for the energy (mechanical iris, sparks, the substance).
-- Moving parts (MiningClient.PickFX "Zombie*" motions): the whole head twitches (ZombieHead, a
-- translation, so it stacks with any joint), the jaw chews / bites / growls (ZombieJaw), the living eye
-- rolls and the lid blinks (ZombieEyeL / ZombieLid), the mechanical iris scans (ZombieEyeR), the blade
-- and the claw flex like a nervous tic (ZombieBlade / ZombieClaw), the coil rings bounce
-- (ZombieCoil, PickAmp = ring), the neck bolt turns (ZombieBolt), shaft segments tic (ZombieTic), loose
-- wires sway (ZombieWire), the vial and the charm swing on their chains (ZombieJar), live slime drops
-- stretch and fall (GummyDrop + PickGoo). Seam parts carry ZombieSeam (0..1 along the stitches): the
-- blue lightning runs along them (PickFX).
DESIGNS.Zombie=function(model,v,def,len,top)
 local SP,ME,CM,NE,GL=Enum.Material.SmoothPlastic,Enum.Material.Metal,Enum.Material.CorrodedMetal,Enum.Material.Neon,Enum.Material.Glass
 local LE,BO,RB=material('Leather',SP),material('Limestone',SP),material('Rubber',SP)
 local skin=rgb(v.Head,{132,170,64})               -- palette 1: rotten green
 local skin2=Color3.fromRGB(102,134,50)            -- dark rot
 local skin3=Color3.fromRGB(162,196,82)            -- light rot
 local olive=Color3.fromRGB(124,116,72)            -- bruise
 local flesh=rgb(v.Flesh,{186,112,112})            -- stitched-on pink flesh
 local flesh2=Color3.fromRGB(150,84,88)
 local dark=rgb(v.Dark,{70,68,74})                 -- palette 2: dark grey
 local rust=rgb(v.Trim,{166,84,44})                -- palette 3: rusty metal
 local rust2=Color3.fromRGB(112,64,46)
 local rust3=Color3.fromRGB(190,112,62)
 local blue=rgb(v.Accent,{60,150,255})             -- palette 4: dead blue (energy)
 local bone=rgb(v.Shaft,{232,220,186})             -- palette 5: bone white
 local bone2=Color3.fromRGB(206,188,142)
 local enamel=Color3.fromRGB(240,232,206)
 local slime=rgb(v.Slime,{168,232,40})             -- rotten-green slime
 local slimeHot=Color3.fromRGB(214,255,96)
 local maw=Color3.fromRGB(46,22,26)
 local seamCol=Color3.fromRGB(96,30,36)
 local wireR,wireB=Color3.fromRGB(176,36,40),Color3.fromRGB(44,92,204)
 local goo={Transparency=.12,Reflectance=.12,CastShadow=false}
 local rng=Random.new(909)
 local function r(a,b)return a+(b-a)*rng:NextNumber()end
 local function pickc(list)return list[rng:NextInteger(1,#list)]end
 local SKINS={skin,skin,skin2,skin3,olive}

 local C=CFrame.new(0,len*.5+.55,0)                -- head centre
 local cp=C.Position
 local HX,HY0,HY1,HZ=1.0,-.86,1.0,.72               -- head half width, bottom, top, half depth
 local function at(x,y,z)return C*CFrame.new(x,y,z)end
 local function P(x,y,z)return(C*CFrame.new(x,y,z)).Position end
 local function head(p,extra,joint,phase)
  return anim(p,'ZombieHead'..(extra and(','..extra)or''),phase or 0,joint or cp)
 end
 local seamOrder=0
 local function seamTag(p,k)p:SetAttribute('ZombieSeam',k);return p end
 -- stitches from a to b (head space) on a face whose outward normal is n: a dark seam and bone-white
 -- staples across it (uneven, the sheet's "неровные стежки"); ride = how the parts move
 local function seam(a,b,n,count,ride,k0,k1)
  local A,B=P(a.X,a.Y,a.Z),P(b.X,b.Y,b.Z)
  local N=C:VectorToWorldSpace(n).Unit
  local d=(B-A);local L=d.Magnitude;local T=d.Unit
  local X=T:Cross(N).Unit
  local mid=(A+B)*.5
  local line=part(model,'Seam',Vector3.new(.06,L,.035),CFrame.fromMatrix(mid,X,T,N),seamCol,LE)
  ride(line);seamTag(line,k0 or 0)
  for i=1,count do
   local f=(i-.5)/count
   local pos=A:Lerp(B,f)+N*.02
   local tw=r(-.35,.35)
   local s=part(model,'Stitch',Vector3.new(r(.2,.27),.055,.05),CFrame.fromMatrix(pos,X,T,N)*CFrame.Angles(0,0,tw),bone2:Lerp(enamel,rng:NextNumber()),SP)
   ride(s);seamTag(s,(k0 or 0)+((k1 or 1)-(k0 or 0))*f)
  end
 end
 local function headRide(p)return head(p)end
 -- a hex nut / bolt head (three crossed boxes) at cf, axis along cf's Z
 local function hexBolt(name,cf,d,depth,color,mat,props)
  local list={}
  for i=0,2 do table.insert(list,part(model,name,Vector3.new(d*.58,d,depth),cf*CFrame.Angles(0,0,i*math.pi/3),color,mat or CM,props))end
  return list
 end
 local function rivet(cf,s,col)return part(model,'Bolt',Vector3.new(s,s,s*.6),cf,col or dark,ME,{Reflectance=.08})end

 -- HEAD MASS: a lumpy skull of mottled voxels ------------------------------------------------------
 head(part(model,'ZombieSkull',Vector3.new(HX*2-.12,HY1-HY0-.1,HZ*2-.1),at(0,(HY0+HY1)*.5,0),skin,LE))
 -- stepped corners and lumps on every side (kept off the face windows)
 local function faceFree(x,y)return not((y>-1 and y<.55 and math.abs(x)<.92))end
 for i=1,46 do
  local side=rng:NextInteger(1,6)
  local s=r(.26,.5)
  local x,y,z
  if side==1 then x,y,z=r(-HX,HX),HY1-s*.3,r(-HZ,HZ)                  -- top
  elseif side==2 then x,y,z=HX-s*.3,r(HY0+.1,HY1),r(-HZ,HZ)          -- right
  elseif side==3 then x,y,z=-HX+s*.3,r(HY0+.1,HY1),r(-HZ,HZ)         -- left
  elseif side==4 then x,y,z=r(-HX,HX),r(HY0+.2,HY1),-HZ+s*.3          -- back
  else x,y,z=r(-HX,HX),r(.5,HY1),HZ-s*.3 end                          -- front, above the eyes
  if side<5 or faceFree(x,y)or y>.55 then
   head(part(model,'SkinVoxel',Vector3.new(s,s*r(.7,1.1),s),at(x,y,z)*CFrame.Angles(0,r(-.15,.15),0),pickc(SKINS),LE))
  end
 end
 -- brow ridge: a heavy bruised ledge, lower over the living eye (the sheet's frown)
 head(part(model,'Brow',Vector3.new(.78,.2,.24),at(-.5,.5,HZ-.02)*CFrame.Angles(0,0,-.22),skin2,LE))
 head(part(model,'Brow',Vector3.new(.66,.16,.2),at(.48,.62,HZ-.04)*CFrame.Angles(0,0,.1),skin2,LE))
 head(part(model,'Brow',Vector3.new(.26,.24,.2),at(0,.42,HZ-.02),olive,LE))
 -- the forehead: green skin, a pink flesh patch sewn on, a rusty plate
 head(part(model,'Forehead',Vector3.new(1.86,.44,.1),at(0,.8,HZ-.03),skin,LE))
 head(part(model,'FleshPatch',Vector3.new(.62,.42,.08),at(-.5,.78,HZ+.01)*CFrame.Angles(0,0,.12),flesh,LE))
 head(part(model,'FleshPatch',Vector3.new(.34,.22,.06),at(-.62,.64,HZ+.03)*CFrame.Angles(0,0,-.2),flesh2,LE))
 head(part(model,'RustPlate',Vector3.new(.5,.38,.09),at(.56,.86,HZ+.01)*CFrame.Angles(0,0,-.08),rust,CM))
 for _,o in ipairs({{.37,.98},{.75,.98},{.4,.72},{.74,.73}})do head(rivet(at(o[1],o[2],HZ+.07),.08))end
 -- cheeks: the left one torn open to the bone, the right one darker round the machine
 head(part(model,'Cheek',Vector3.new(.42,.5,.14),at(-.78,-.2,HZ-.04),skin,LE))
 head(part(model,'CheekBone',Vector3.new(.3,.22,.1),at(-.74,-.26,HZ+.03)*CFrame.Angles(0,0,.25),bone,BO))
 head(part(model,'CheekBone',Vector3.new(.16,.14,.1),at(-.86,-.08,HZ+.03),bone2,BO))
 head(part(model,'Cheek',Vector3.new(.3,.56,.14),at(.84,-.22,HZ-.06),skin2,LE))
 head(part(model,'CheekFlesh',Vector3.new(.22,.2,.06),at(-.66,-.46,HZ+.04),flesh2,LE))

 -- LIVING EYE (left): yellow, bloodshot, small pupil, a heavy lid ------------------------------------
 local eL=at(-.44,.12,HZ-.04)
 head(part(model,'EyeSocket',Vector3.new(.74,.66,.1),eL*CFrame.new(0,0,-.03),Color3.fromRGB(58,40,36),LE))
 head(blob(model,'EyeL',Vector3.new(.66,.62,.4),eL*CFrame.new(0,0,.06),Color3.fromRGB(238,190,74),SP,{Reflectance=.1}))
 head(blob(model,'EyeLRim',Vector3.new(.58,.12,.3),eL*CFrame.new(0,-.27,.1),Color3.fromRGB(196,104,64),SP))
 local pupL={}
 table.insert(pupL,blob(model,'EyeLIris',Vector3.new(.28,.3,.06),eL*CFrame.new(.06,-.02,.255),Color3.fromRGB(196,112,30),SP))
 table.insert(pupL,blob(model,'EyeLPupil',Vector3.new(.13,.15,.05),eL*CFrame.new(.06,-.02,.28),Color3.fromRGB(26,16,12),SP))
 table.insert(pupL,ball(model,'EyeLGlint',.07,eL*CFrame.new(.13,.05,.3),Color3.new(1,1,1),NE,{CastShadow=false}))
 for _,p in ipairs(pupL)do head(p,'ZombieEyeL',eL.Position,.3)end
 for i=1,3 do -- red veins
  head(part(model,'EyeVein',Vector3.new(.12,.025,.02),eL*CFrame.new(-.18+i*.02,-.1+i*.06,.17)*CFrame.Angles(0,0,r(-.6,.6)),Color3.fromRGB(196,40,40),SP))
 end
 local lid=part(model,'EyeLLid',Vector3.new(.7,.18,.42),eL*CFrame.new(0,.29,.06)*CFrame.Angles(0,0,-.16),skin2,LE)
 head(lid,'ZombieLid',eL.Position,.6)

 -- MECHANICAL EYE (right): a big glowing blue eye in a bolted rusty socket ---------------------------
 local eR=at(.44,.16,HZ)
 for _,p in ipairs(ring(model,'EyeRing',eR*CFrame.new(0,0,.02),.36,.13,.2,12,rust,CM))do head(p)end
 for _,p in ipairs(ring(model,'EyeRing',eR*CFrame.new(0,0,.1),.3,.06,.06,12,dark,ME,nil,{Reflectance=.1}))do head(p)end
 for i=0,5 do
  local a=i/6*math.pi*2+.3
  head(rivet(eR*CFrame.new(math.cos(a)*.38,math.sin(a)*.38,.13),.09,Color3.fromRGB(150,140,128)))
 end
 head(ball(model,'EyeR',.58,eR*CFrame.new(0,0,-.02),Color3.fromRGB(232,238,244),SP,{Reflectance=.15}))
 local irisR={}
 table.insert(irisR,cylZ(model,'EyeRIrisRing',.04,.36,eR*CFrame.new(0,0,.26),Color3.fromRGB(150,206,255),SP))
 local iris=cylZ(model,'EyeRIris',.04,.28,eR*CFrame.new(0,0,.275),blue,NE,{CastShadow=false})
 iris:SetAttribute('PickPulse',true);table.insert(irisR,iris)
 table.insert(irisR,cylZ(model,'EyeRPupil',.04,.11,eR*CFrame.new(0,0,.295),Color3.fromRGB(14,36,90),SP))
 table.insert(irisR,ball(model,'EyeRGlint',.07,eR*CFrame.new(.08,.08,.3),Color3.new(1,1,1),NE,{CastShadow=false}))
 for _,p in ipairs(irisR)do head(p,'ZombieEyeR',eR.Position,.7)end
 -- cables out of the socket into the skull
 head(rod(model,'EyeCable',P(.78,.34,HZ-.02),P(.92,.6,HZ-.2),.07,wireR,RB))
 head(rod(model,'EyeCable',P(.8,.0,HZ-.02),P(.95,-.2,HZ-.25),.06,wireB,RB))

 -- NOSE and MOUTH -------------------------------------------------------------------------------------
 for s=-1,1,2 do head(part(model,'NoseHole',Vector3.new(.09,.18,.06),at(s*.07,-.2,HZ+.01)*CFrame.Angles(0,0,s*.25),maw,SP))end
 head(part(model,'NoseBone',Vector3.new(.3,.1,.08),at(0,-.08,HZ+.01),bone2,BO))
 local my=-.56
 head(part(model,'Maw',Vector3.new(1.36,.5,.24),at(0,my-.12,HZ-.12),maw,SP))
 head(part(model,'Gum',Vector3.new(1.46,.16,.26),at(0,my+.06,HZ-.02),bone2,BO))
 head(part(model,'Lip',Vector3.new(1.6,.12,.2),at(0,my+.17,HZ-.04),skin2,LE))
 -- upper teeth: crooked, uneven, one missing, two long fangs
 local upper={{-.62,.26,.15},{-.44,.32,.17},{-.24,.44,.18},{-.04,.3,.16},{.15,.36,.17},{.36,.48,.19},{.56,.3,.15}}
 for i,tth in ipairs(upper)do
  if i~=4 then
   local base=at(tth[1],my+.02,HZ+.03)*CFrame.Angles(0,0,r(-.12,.12))
   head(part(model,'Tooth',Vector3.new(tth[3],tth[2]*.55,.14),base*CFrame.new(0,-tth[2]*.27,0),enamel,SP,{Reflectance=.04}))
   for _,p in ipairs(spike(model,'Tooth',(base*CFrame.new(0,-tth[2]*.5,0)).Position,-base.UpVector,base.RightVector,tth[2]*.5,tth[3],.13,enamel,SP))do head(p)end
  else
   head(part(model,'ToothStub',Vector3.new(.13,.08,.12),at(tth[1],my-.02,HZ+.02),bone2,BO))
  end
 end
 -- the lower jaw (bites on the hinge at the back of the mouth)
 local hinge=P(0,my-.2,0)
 local function jaw(p)return head(p,'ZombieJaw',hinge)end
 jaw(part(model,'Jaw',Vector3.new(1.42,.24,.62),at(0,my-.5,HZ-.3),bone,BO))
 jaw(part(model,'Jaw',Vector3.new(1.2,.14,.3),at(0,my-.62,HZ-.18),bone2,BO))
 jaw(part(model,'JawSkin',Vector3.new(.5,.2,.5),at(-.45,my-.48,HZ-.34),skin2,LE))
 for s=-1,1,2 do jaw(part(model,'JawSide',Vector3.new(.22,.42,.5),at(s*.7,my-.36,HZ-.36),bone2,BO))end
 local lower={{-.55,.2},{-.33,.26},{-.12,.2},{.1,.3},{.32,.22},{.52,.26}}
 for _,tth in ipairs(lower)do
  local base=at(tth[1],my-.38,HZ-.06)*CFrame.Angles(0,0,r(-.15,.15))
  jaw(part(model,'Tooth',Vector3.new(.15,tth[2]*.5,.13),base*CFrame.new(0,tth[2]*.25,0),enamel,SP,{Reflectance=.04}))
  for _,p in ipairs(spike(model,'Tooth',(base*CFrame.new(0,tth[2]*.5,0)).Position,base.UpVector,base.RightVector,tth[2]*.45,.15,.12,enamel,SP))do jaw(p)end
 end
 -- slime oozing out of the mouth corners
 for s=-1,1,2 do jaw(blob(model,'MouthSlime',Vector3.new(.24,.3,.2),at(s*.66,my-.3,HZ),slime,GL,goo))end

 -- STITCHES on the face and over the skull ----------------------------------------------------------
 seam(Vector3.new(-.98,.98,HZ+.05),Vector3.new(-.02,.38,HZ+.05),Vector3.new(0,0,1),6,headRide,0,.3)    -- forehead diagonal
 seam(Vector3.new(.12,1.0,HZ+.05),Vector3.new(.2,.6,HZ+.05),Vector3.new(0,0,1),2,headRide,.3,.38)
 seam(Vector3.new(-.9,-.02,HZ+.07),Vector3.new(-.66,-.4,HZ+.07),Vector3.new(0,0,1),3,headRide,.38,.48)  -- left cheek
 seam(Vector3.new(-.6,HY1+.06,.5),Vector3.new(.3,HY1+.06,-.5),Vector3.new(0,1,0),6,headRide,.48,.7)     -- over the top

 -- BACK: the pink stitched flesh panel, rusty plates, a second bolt ----------------------------------
 head(part(model,'BackFlesh',Vector3.new(1.3,1.3,.1),at(-.12,.1,-HZ-.02),flesh,LE))
 for i=1,9 do head(part(model,'FleshLump',Vector3.new(r(.2,.36),r(.2,.36),.08),at(r(-.65,.4),r(-.45,.65),-HZ-.07),i%3==0 and flesh2 or flesh:Lerp(Color3.new(1,1,1),.08),LE))end
 seam(Vector3.new(-.6,.7,-HZ-.12),Vector3.new(.3,-.5,-HZ-.12),Vector3.new(0,0,-1),7,headRide,.7,.88)
 seam(Vector3.new(-.7,-.2,-HZ-.12),Vector3.new(.35,.45,-HZ-.12),Vector3.new(0,0,-1),5,headRide,.88,1)
 head(part(model,'BackPlate',Vector3.new(.56,.9,.12),at(.7,.25,-HZ-.03)*CFrame.Angles(0,0,.06),rust2,CM))
 head(part(model,'BackPlate',Vector3.new(.5,.4,.12),at(.66,-.55,-HZ-.03)*CFrame.Angles(0,0,-.1),rust,CM))
 head(part(model,'BackPlate',Vector3.new(.42,.36,.12),at(-.72,.78,-HZ-.03),rust,CM))
 for _,o in ipairs({{.52,.62},{.88,.62},{.52,-.1},{.88,-.12},{.55,-.62},{.8,-.66}})do head(rivet(at(o[1],o[2],-HZ-.11)*CFrame.Angles(0,math.pi,0),.09))end
 for _,p in ipairs(hexBolt('BackBolt',at(.7,.25,-HZ-.18)*CFrame.Angles(0,math.pi,0),.34,.18,rust3))do head(p)end

 -- NECK BOLTS (Frankenstein): a big rusty hex bolt out of the right side, a small one on the left -----
 local boltCF=at(HX+.12,.06,-.05)*CFrame.Angles(0,math.pi/2,0)
 head(part(model,'BoltCollar',Vector3.new(.62,.62,.12),boltCF*CFrame.new(0,0,-.08),dark,ME,{Reflectance=.08}))
 local bolt={}
 table.insert(bolt,cylZ(model,'NeckBoltShaft',.38,.26,boltCF*CFrame.new(0,0,.12),Color3.fromRGB(120,110,104),ME))
 for _,p in ipairs(hexBolt('NeckBolt',boltCF*CFrame.new(0,0,.36),.52,.26,rust3))do table.insert(bolt,p)end
 table.insert(bolt,part(model,'NeckBoltCap',Vector3.new(.3,.3,.05),boltCF*CFrame.new(0,0,.5),rust2,CM))
 for _,p in ipairs(bolt)do head(p,'ZombieBolt',boltCF.Position)end
 local lb=at(-HX-.04,-.3,-.2)*CFrame.Angles(0,-math.pi/2,0)
 head(cylZ(model,'NeckBoltShaft',.24,.16,lb*CFrame.new(0,0,.08),Color3.fromRGB(120,110,104),ME))
 for _,p in ipairs(hexBolt('NeckBolt',lb*CFrame.new(0,0,.22),.3,.16,rust))do head(p)end

 -- RUSTY BLOCKS on the top edge and round the right side ---------------------------------------------
 for _,b in ipairs({{-.75,HY1+.12,.35,.34,.2},{-.25,HY1+.14,-.25,.3,-.3},{.15,HY1+.1,.42,.28,.15},{.82,HY1+.06,.4,.36,.4},
  {.92,.62,.45,.4,.1},{.98,-.5,.35,.38,-.2},{-.88,HY1-.05,-.4,.3,.5}})do
  head(part(model,'RustBlock',Vector3.new(b[4],b[4]*.9,b[4]),at(b[1],b[2],b[3])*CFrame.Angles(r(-.2,.2),b[5],r(-.2,.2)),pickc({rust,rust2,rust3}),CM))
 end

 -- SLIME: a lime goo cap over the top-left, runs down the face, drips -------------------------------
 for _,g in ipairs({{-.55,HY1+.05,.25,.9,.2,.8},{-.1,HY1+.02,.45,.6,.16,.5},{-.98,.78,HZ-.04,.3,.36,.24},{-.2,.62,HZ+.06,.3,.14,.1},
  {.3,HY1+.02,-.1,.5,.14,.5},{-.95,.2,.3,.16,.6,.4}})do
  head(blob(model,'SlimeCoat',Vector3.new(g[4],g[5],g[6]),at(g[1],g[2],g[3]),slime,GL,goo))
 end
 -- static drips (neck + drop) and live drops that stretch and fall (GummyDrop + PickGoo)
 local function drip(name,pos,length,d,ride)
  local a=blob(model,name,Vector3.new(d*.75,length,d*.75),CFrame.new(pos-Vector3.new(0,length*.45,0)),slime,GL,goo)
  local b=blob(model,name..'Drop',Vector3.new(d,d*1.3,d),CFrame.new(pos-Vector3.new(0,length*.95,0)),slimeHot,GL,goo)
  if ride then ride(a);ride(b)end
  return a,b
 end
 local function liveDrop(pos,phase,d,extra,joint)
  d=d or .15
  for i,k in ipairs({.33,.66,1})do
   local p=i<3 and blob(model,'SlimeNeck',Vector3.new(d*.5,d*1.1,d*.5),CFrame.new(pos-Vector3.new(0,.06*i,0)),slime,GL,goo)
    or blob(model,'SlimeLiveDrop',Vector3.new(d,d*1.25,d),CFrame.new(pos-Vector3.new(0,.18,0)),slimeHot,GL,goo)
   anim(p,'ZombieHead,GummyDrop'..(extra and(','..extra)or''),phase,joint or pos);p:SetAttribute('PickDropK',k)
   if i==3 then p:SetAttribute('PickGoo',true)end
  end
 end
 drip('FaceDrip',P(-.98,.62,HZ+.04),.42,.14,headRide)
 drip('FaceDrip',P(-.22,.55,HZ+.1),.26,.11,headRide)
 drip('FaceDrip',P(.98,.3,HZ-.1),.36,.12,headRide)
 liveDrop(P(-.94,-.05,.4),.1,.15)
 liveDrop(P(-.3,.48,HZ+.12),.55,.12)

 -- TESLA COIL on top (rings bounce, sparks crackle) ---------------------------------------------------
 local cb=P(.5,HY1+.12,-.08)
 head(part(model,'CoilBase',Vector3.new(.5,.2,.5),CFrame.new(cb),rust2,CM))
 head(part(model,'CoilBase',Vector3.new(.36,.12,.36),CFrame.new(cb+Vector3.new(0,.15,0)),dark,ME))
 head(cylY(model,'CoilCore',.95,.14,CFrame.new(cb+Vector3.new(0,.6,0)),Color3.fromRGB(58,56,62),ME))
 for i=1,4 do
  local y=.3+i*.15
  for _,p in ipairs(ring(model,'CoilRing',CFrame.new(cb+Vector3.new(0,y,0))*CFrame.Angles(math.pi/2,0,0),.17+(i%2)*.02,.07,.08,10,
   i%2==0 and Color3.fromRGB(170,150,128)or Color3.fromRGB(140,120,104),ME,nil,{Reflectance=.15}))do
   head(p,'ZombieCoil',cb);p:SetAttribute('PickAmp',i/4)
  end
 end
 local capY=cb+Vector3.new(0,1.12,0)
 for _,p in ipairs(hexBolt('CoilCap',CFrame.new(capY)*CFrame.Angles(math.pi/2,0,0),.36,.2,rust3))do head(p,'ZombieCoil',cb):SetAttribute('PickAmp',1)end
 head(part(model,'CoilTip',Vector3.new(.12,.14,.12),CFrame.new(capY+Vector3.new(0,.16,0)),Color3.fromRGB(150,140,128),ME),'ZombieCoil',cb):SetAttribute('PickAmp',1)
 -- wires: a red loop from the coil over to the right, a blue one into the skull (they sway)
 local function wire(name,pts,d,col,sway,joint)
  for i=1,#pts-1 do
   local p=rod(model,name,pts[i],pts[i+1],d,col,RB)
   if sway then head(p,'ZombieWire',joint or pts[1],i*.4)else head(p)end
  end
 end
 wire('Wire',{cb+Vector3.new(.12,.1,.12),cb+Vector3.new(.45,.25,.2),cb+Vector3.new(.62,.05,.25),P(1.0,.75,.25),P(1.02,.45,.1)},.09,wireR,true)
 wire('Wire',{cb+Vector3.new(-.12,.12,.1),cb+Vector3.new(-.42,.22,.3),P(-.15,HY1+.04,.55)},.08,wireB,true)
 wire('Wire',{cb+Vector3.new(.05,.1,-.16),cb+Vector3.new(.2,.3,-.5),P(.85,.75,-HZ-.05)},.08,wireB,true)
 -- the sparks: thin blue zigzags round the coil (PickFlicker) and an emitter
 for i=1,3 do
  local a=i/3*math.pi*2
  local o=capY+Vector3.new(math.cos(a)*.22,-.1,math.sin(a)*.22)
  local q1=o+Vector3.new(math.cos(a)*.25,.18,math.sin(a)*.25)
  local q2=q1+Vector3.new(math.cos(a+.8)*.2,.15,math.sin(a+.8)*.2)
  for _,seg in ipairs({{o,q1},{q1,q2}})do
   local s=bar(model,'Spark',seg[1],seg[2],.05,.05,blue:Lerp(Color3.new(1,1,1),.35),NE,{CastShadow=false})
   s:SetAttribute('PickFlicker',true);head(s,'ZombieCoil',cb):SetAttribute('PickAmp',1)
  end
 end

 -- FLESH BLADE (left): a long rising blade of stitched skin with a bone cutting edge -----------------
 local b0,b1,b2,b3=Vector3.new(-.82,.45,0),Vector3.new(-1.9,.95,0),Vector3.new(-2.8,1.45,0),Vector3.new(-3.55,1.22,0)
 local function bez(t)local u=1-t;return b0*u*u*u+b1*3*u*u*t+b2*3*u*t*t+b3*t*t*t end
 local bladeRoot=P(-.8,.45,0)
 local function blade(p,phase)return head(p,'ZombieBlade',bladeRoot,phase)end
 local N=10
 local tipPos
 for i=0,N-1 do
  local t0,t1=i/N,(i+1)/N
  local a,b=bez(t0),bez(t1)
  local mid=(a+b)*.5;local dir=(b-a).Unit
  local tm=(t0+t1)*.5
  local h=1.3*(1-tm)^.7+.16
  local d=.92*(1-tm*.7)
  local up=Vector3.new(-dir.Y,dir.X,0)                 -- in-plane normal (up-ish)
  if up.Y<0 then up=-up end
  local cf=C*CFrame.fromMatrix(mid,dir,up,dir:Cross(up))
  local segL=(b-a).Magnitude+.04
  -- upper skin and lower bone edge (stepped: a voxel blade)
  blade(part(model,'BladeSkin',Vector3.new(segL,h*.7,d),cf*CFrame.new(0,h*.15,0),SKINS[(i%#SKINS)+1],LE))
  blade(part(model,'BladeBone',Vector3.new(segL,h*.32,d*.72),cf*CFrame.new(0,-h*.34,0),i%2==0 and bone or bone2,BO))
  if i%3==1 then blade(part(model,'BladeVoxel',Vector3.new(segL*.7,h*.3,d*1.08),cf*CFrame.new(r(-.05,.05),h*.2,0),skin3,LE))end
  -- bone shards along the cutting edge
  if i==2 or i==4 or i==6 or i==8 then
   local base=(cf*CFrame.new(r(-.06,.06),-h*.48,0)).Position
   for _,p in ipairs(spike(model,'BoneShard',base,(-up+dir*-.25).Unit,dir,.26+h*.25,.34,.18,i%2==0 and enamel or bone,BO))do blade(p)end
  end
  -- rusty blocks and bolts along the top
  if i==1 or i==4 or i==6 then
   local s=.34-i*.025
   blade(part(model,'BladeRust',Vector3.new(s*1.2,s,s*1.1),cf*CFrame.new(0,h*.5+s*.3,0)*CFrame.Angles(0,0,r(-.2,.2)),pickc({rust,rust2,rust3}),CM))
   for z=-1,1,2 do blade(rivet(cf*CFrame.new(0,h*.5+s*.3,z*s*.56),.08,Color3.fromRGB(150,140,128)))end
  end
  if i==N-1 then tipPos=(cf*CFrame.new(segL*.5,0,0)).Position end
 end
 -- the point: a long bone shard
 do
  local a,b=bez(.96),bez(1)
  local dir=(b-a).Unit
  for _,p in ipairs(spike(model,'BladeTip',C*(b-dir*.05),C:VectorToWorldSpace(dir),Vector3.zAxis:Cross(dir),.5,.24,.16,enamel,BO))do blade(p)end
  tipPos=(C*(b+dir*.45))
 end
 -- a pink flesh patch sewn onto both faces, with stitches
 for z=-1,1,2 do
  local pm=bez(.32)
  local fcf=C*CFrame.new(pm.X,pm.Y+.12,z*.43)*CFrame.Angles(0,0,math.rad(26))
  blade(part(model,'BladeFlesh',Vector3.new(.62,.34,.05),fcf,flesh,LE))
  local a1,a2=bez(.08),bez(.62)
  seam(Vector3.new(a1.X,a1.Y+.18,z*.47),Vector3.new(a2.X,a2.Y+.12,z*.36),Vector3.new(0,0,z),5,function(p)return blade(p)end,z>0 and .2 or .6,z>0 and .5 or .9)
 end
 -- slime running off the blade's underside
 for _,t in ipairs({.3,.55,.78})do
  local pos=C*(bez(t)-Vector3.new(0,(1.3*(1-t)^.7+.16)*.5,0))
  blade(blob(model,'BladeSlime',Vector3.new(.3,.14,.4),CFrame.new(pos),slime,GL,goo))
  drip('BladeDrip',pos,.34-t*.15,.12,function(p)return blade(p)end)
 end
 for _,t in ipairs({.15,.5})do
  local pos=C*(bez(t)+Vector3.new(0,(1.3*(1-t)^.7+.16)*.45,.1))
  blade(blob(model,'BladeSlime',Vector3.new(.42,.12,.5),CFrame.new(pos),slime,GL,goo))
 end

 -- CLAW (right): rusty blocks, then a down-curving slime-coated hook with a bone point --------------
 local clawRoot=P(1.12,.12,0)
 local function claw(p,phase)return head(p,'ZombieClaw',clawRoot,phase)end
 claw(part(model,'ClawRust',Vector3.new(.5,.5,.56),at(1.2,.24,.08)*CFrame.Angles(0,0,-.1),rust,CM))
 claw(part(model,'ClawRust',Vector3.new(.4,.38,.46),at(1.55,.1,-.02)*CFrame.Angles(0,0,-.35),rust2,CM))
 for z=-1,1,2 do claw(rivet(at(1.22,.28,z*.3+.08),.09,Color3.fromRGB(150,140,128)))end
 local c0,c1,c2,c3=Vector3.new(1.62,.0,0),Vector3.new(2.05,-.2,0),Vector3.new(2.15,-.8,0),Vector3.new(1.86,-1.4,0)
 local function cbez(t)local u=1-t;return c0*u*u*u+c1*3*u*u*t+c2*3*u*t*t+c3*t*t*t end
 local clawTip
 for i=0,6 do
  local t0,t1=i/7,(i+1)/7
  local a,b=cbez(t0),cbez(t1)
  local dir=(b-a).Unit;local tm=(t0+t1)*.5
  local w=.6*(1-tm)+.12
  local side=Vector3.new(dir.Y,-dir.X,0)          -- outward (to the right of the curve)
  local cf=C*CFrame.fromMatrix((a+b)*.5,side,dir,Vector3.zAxis)
  local L=(b-a).Magnitude+.04
  claw(part(model,'ClawFlesh',Vector3.new(w,L,w*1.1),cf,i%2==0 and skin2 or olive,LE))
  claw(part(model,'ClawSlime',Vector3.new(w*.6,L*.95,w*1.18),cf*CFrame.new(w*.25,0,0),slime,GL,goo))
  if i==2 or i==4 then
   for _,p in ipairs(spike(model,'ClawShard',(cf*CFrame.new(-w*.48,0,0)).Position,-cf.RightVector,cf.UpVector,.18+w*.2,.26,.15,bone,BO))do claw(p)end
  end
 end
 do
  local a,b=cbez(.95),cbez(1)
  local dir=C:VectorToWorldSpace((b-a).Unit)
  for _,p in ipairs(spike(model,'ClawTip',C*b,dir,Vector3.zAxis,.42,.2,.14,enamel,BO))do claw(p)end
  clawTip=C*b+dir*.38
 end
 drip('ClawDrip',C*cbez(.45)+Vector3.new(.15,-.1,0),.3,.12,function(p)return claw(p)end)

 -- COLLAR and NECK -----------------------------------------------------------------------------------
 local hTop=cp.Y+HY0-.06
 local function seg(name,y0,y1,w,color,mat,props)
  return part(model,name,Vector3.new(w,y1-y0,w),CFrame.new(0,(y0+y1)*.5,0),color,mat,props)
 end
 seg('Neck',hTop-.1,hTop+.3,.62,skin2,LE)
 seg('Collar',hTop-.36,hTop-.1,.86,rust,CM)
 part(model,'Collar',Vector3.new(.64,.22,1.0),CFrame.new(0,hTop-.23,0),rust2,CM)
 part(model,'Collar',Vector3.new(1.0,.22,.64),CFrame.new(0,hTop-.23,0),rust2,CM)
 for i=0,5 do
  local a=i/6*math.pi*2+.4
  local p=Vector3.new(math.cos(a)*.5,hTop-.23,math.sin(a)*.5)
  part(model,'Bolt',Vector3.new(.11,.11,.11),CFrame.lookAt(p,p+Vector3.new(p.X,0,p.Z)),Color3.fromRGB(150,140,128),ME)
 end

 -- SHAFT: bone vertebrae, rusty brackets, red / blue wires, slime ------------------------------------
 local y=hTop-.36
 local gTop=-.82                                    -- the hand holds round -1.4: slim straps there
 local plan={{'v',.34},{'band',.16,rust},{'v',.38},{'v',.3},{'band',.2,dark},{'v',.36},{'clamp',.22},{'v',.34},{'v',.3},{'band',.16,rust2},{'v',.36}}
 local k=0
 for _,s in ipairs(plan)do
  if y-s[2]<gTop then break end
  local y0=y-s[2]
  k+=1
  if s[1]=='v'then -- a vertebra: knobby bone block, darker joint, side processes
   local tw=r(-.18,.18)
   local vb=part(model,'Vertebra',Vector3.new(.5,s[2]-.06,.48),CFrame.new(r(-.02,.02),(y0+y)*.5,0)*CFrame.Angles(0,tw,0),k%2==0 and bone or bone2,BO)
   anim(vb,'ZombieTic',k*.37,vb.CFrame.Position)
   local j=part(model,'VertebraJoint',Vector3.new(.4,.08,.4),CFrame.new(0,y0+.02,0),Color3.fromRGB(170,150,110),BO)
   anim(j,'ZombieTic',k*.37,vb.CFrame.Position)
   for sd=-1,1,2 do
    local kn=part(model,'VertebraKnob',Vector3.new(.16,.14,.18),CFrame.new(0,(y0+y)*.5,0)*CFrame.Angles(0,tw,0)*CFrame.new(sd*.3,r(-.04,.04),0),bone2,BO)
    anim(kn,'ZombieTic',k*.37,vb.CFrame.Position)
   end
   if k%2==1 then anim(part(model,'VertebraKnob',Vector3.new(.14,.16,.12),CFrame.new(0,(y0+y)*.5,0)*CFrame.Angles(0,tw,0)*CFrame.new(0,0,.28),enamel,BO),'ZombieTic',k*.37,vb.CFrame.Position)end
  elseif s[1]=='band'then
   part(model,'ShaftBand',Vector3.new(.66,s[2],.66),CFrame.new(0,(y0+y)*.5,0)*CFrame.Angles(0,r(-.3,.3),0),s[3],s[3]==dark and ME or CM)
   for i=0,3 do
    local a=i/4*math.pi*2+math.pi/4
    local p=Vector3.new(math.cos(a)*.34,(y0+y)*.5,math.sin(a)*.34)
    part(model,'Bolt',Vector3.new(.09,.09,.09),CFrame.lookAt(p,p+Vector3.new(p.X,0,p.Z)),Color3.fromRGB(150,140,128),ME)
   end
  else -- a bracket clamp with tabs and a screw
   part(model,'Clamp',Vector3.new(.7,s[2],.6),CFrame.new(0,(y0+y)*.5,0)*CFrame.Angles(0,.4,0),rust,CM)
   part(model,'ClampTab',Vector3.new(.22,s[2]*.8,.3),CFrame.new(0,(y0+y)*.5,0)*CFrame.Angles(0,.4,0)*CFrame.new(.44,0,0),rust2,CM)
   part(model,'ClampScrew',Vector3.new(.1,.3,.1),CFrame.new(0,(y0+y)*.5,0)*CFrame.Angles(0,.4,0)*CFrame.new(.44,0,0)*CFrame.Angles(math.pi/2,0,0),Color3.fromRGB(150,140,128),ME)
  end
  y=y0
 end
 -- the grip: dark metal straps over bone
 local gBot=-len*.5+.5
 local nb=6
 for i=0,nb-1 do
  local a=y-(y-gBot)*i/nb;local b=y-(y-gBot)*(i+1)/nb
  if i%2==0 then
   local col=i==2 and rust2 or dark
   part(model,'GripStrap',Vector3.new(.52,(a-b)*.8,.52),CFrame.new(0,(a+b)*.5,0)*CFrame.Angles(0,math.rad(8*(i-2)),math.rad(i==2 and 6 or -4)),col,col==dark and ME or CM,{Reflectance=.04})
  else
   part(model,'GripBone',Vector3.new(.46,(a-b)*1.25,.46),CFrame.new(0,(a+b)*.5,0),i%4==1 and bone or bone2,BO)
  end
 end
 part(model,'GripStrap',Vector3.new(.08,(y-gBot)*.9,.54),CFrame.new(.2,(y+gBot)*.5,.02)*CFrame.Angles(0,0,.08),Color3.fromRGB(52,50,56),ME)
 -- wires winding down the shaft (stop above the grip)
 for _,w in ipairs({{wireR,0,.3},{wireB,math.pi,.31}})do
  local prev
  local n=22
  for i=0,n do
   local f=i/n
   local yy=hTop-.4-(hTop-.4-gTop-.05)*f
   local a=w[2]+f*math.pi*2*2.1
   local p=Vector3.new(math.cos(a)*w[3],yy,math.sin(a)*w[3])
   if prev then rod(model,'ShaftWire',prev,p,.075,w[1],RB)end
   prev=p
  end
 end
 -- slime running down the upper shaft
 for _,g in ipairs({{.18,hTop-.5,.22,.18,.5},{-.2,hTop-.95,.2,.14,.36},{.12,hTop-1.6,.24,.12,.3}})do
  part(model,'ShaftSlime',Vector3.new(g[4],g[5],.1),CFrame.lookAt(Vector3.new(g[1],g[2],g[3]),Vector3.new(g[1]*3,g[2],g[3]*3)),slime,GL,goo)
 end
 drip('ShaftDrip',Vector3.new(.24,hTop-.72,.24),.3,.11)

 -- POMMEL: a rusty block, bolts, bone knuckles, a loose red wire ------------------------------------
 local py=gBot-.36
 part(model,'PommelRing',Vector3.new(.64,.12,.64),CFrame.new(0,gBot-.02,0),rust2,CM)
 part(model,'Pommel',Vector3.new(.8,.62,.8),CFrame.new(0,py,0)*CFrame.Angles(0,.12,0),rust,CM)
 part(model,'Pommel',Vector3.new(.64,.5,.9),CFrame.new(.04,py-.04,0)*CFrame.Angles(0,.12,0),rust2,CM)
 for i=0,3 do
  local a=i/4*math.pi*2+math.pi/4+.12
  part(model,'Bolt',Vector3.new(.11,.11,.11),CFrame.new(math.cos(a)*.42,py+.16,math.sin(a)*.42),Color3.fromRGB(150,140,128),ME)
 end
 for _,kb in ipairs({{-.26,-.24},{.28,-.2},{-.2,.26},{.24,.28}})do
  part(model,'Knuckle',Vector3.new(.24,.3,.24),CFrame.new(kb[1],py-.38,kb[2])*CFrame.Angles(r(-.2,.2),r(-.4,.4),r(-.2,.2)),bone,BO)
 end
 part(model,'Knuckle',Vector3.new(.26,.24,.26),CFrame.new(.02,py-.56,0)*CFrame.Angles(0,.5,0),bone2,BO)
 part(model,'PommelBone',Vector3.new(.18,.5,.18),CFrame.new(-.46,py+.02,.1)*CFrame.Angles(0,0,.5),bone,BO)
 do
  local pts={Vector3.new(.42,py+.12,.2),Vector3.new(.62,py-.12,.32),Vector3.new(.55,py-.42,.38),Vector3.new(.3,py-.4,.42)}
  for i=1,#pts-1 do anim(rod(model,'PommelWire',pts[i],pts[i+1],.08,wireR,RB),'ZombieWire',i*.5,pts[1])end
 end

 -- THE SUBSTANCE VIAL and the bone skull charm on chains off the collar (they swing) ----------------
 local hook=Vector3.new(.46,hTop-.3,.2)
 local jarTop=hook-Vector3.new(-.05,.62,0)
 local function jar(p)return anim(p,'ZombieJar',0,hook)end
 for i=1,4 do
  local p=hook:Lerp(jarTop+Vector3.new(0,.08,0),(i-.5)/4)
  jar(part(model,'Chain',Vector3.new(.07,.17,i%2==0 and .12 or .05),CFrame.new(p)*CFrame.Angles(0,i%2==0 and math.pi/2 or 0,0),rust2,CM))
 end
 local jc=CFrame.new(jarTop-Vector3.new(0,.42,0))
 jar(cylY(model,'VialCap',.12,.36,jc*CFrame.new(0,.36,0),rust,CM))
 jar(cylY(model,'VialCap',.06,.24,jc*CFrame.new(0,.45,0),dark,ME))
 jar(cylY(model,'VialGlass',.62,.3,jc,Color3.fromRGB(196,240,255),GL,{Transparency=.55,Reflectance=.2,CastShadow=false}))
 local liquid=cylY(model,'VialSubstance',.5,.22,jc*CFrame.new(0,-.04,0),Color3.fromRGB(110,255,80),NE,{Transparency=.12,CastShadow=false})
 liquid:SetAttribute('PickPulse',true);jar(liquid)
 for i=1,3 do jar(ball(model,'VialBubble',.06,jc*CFrame.new(r(-.05,.05),-.15+i*.1,r(-.05,.05)),Color3.fromRGB(220,255,190),NE,{CastShadow=false}))end
 -- the skull mark on the glass
 jar(part(model,'VialSkull',Vector3.new(.13,.12,.02),jc*CFrame.new(0,.08,.16),Color3.fromRGB(200,236,255),NE,{CastShadow=false}))
 jar(part(model,'VialSkull',Vector3.new(.08,.05,.02),jc*CFrame.new(0,0,.16),Color3.fromRGB(200,236,255),NE,{CastShadow=false}))
 for s=-1,1,2 do jar(part(model,'VialSkullEye',Vector3.new(.035,.035,.025),jc*CFrame.new(s*.03,.08,.17),Color3.fromRGB(20,60,110),SP))end
 jar(cylY(model,'VialCap',.12,.36,jc*CFrame.new(0,-.36,0),rust,CM))
 for _,p in ipairs({drip('VialDrip',(jc*CFrame.new(.04,-.42,0)).Position,.26,.1)})do jar(p)end
 -- the skull charm on its own short chain, beside the vial
 local sk=jarTop+Vector3.new(.3,-.38,.02)
 for i=1,3 do jar(part(model,'Chain',Vector3.new(.06,.14,i%2==0 and .1 or .04),CFrame.new(jarTop:Lerp(sk+Vector3.new(0,.18,0),(i-.5)/3)+Vector3.new(.06,0,0)),rust2,CM))end
 jar(part(model,'CharmSkull',Vector3.new(.3,.26,.26),CFrame.new(sk),bone,BO))
 jar(part(model,'CharmJaw',Vector3.new(.22,.1,.22),CFrame.new(sk-Vector3.new(0,.17,-.02)),bone2,BO))
 for s=-1,1,2 do jar(part(model,'CharmEye',Vector3.new(.08,.08,.03),CFrame.new(sk+Vector3.new(s*.07,.03,.13)),maw,SP))end
 jar(part(model,'CharmNose',Vector3.new(.04,.05,.03),CFrame.new(sk+Vector3.new(0,-.05,.13)),maw,SP))

 -- GLOW and IDLE FX: the blue light of the machine eye, the green of the vial, sparks and drips ------
 local glow=part(model,'ZombieGlow',Vector3.new(.3,.3,.3),eR*CFrame.new(0,0,.45),blue,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='ZombieLight';light.Color=Color3.fromRGB(90,170,255);light.Range=7;light.Brightness=.8;light.Shadows=false;light.Parent=glow
 head(glow)
 local jg=part(model,'ZombieJarGlow',Vector3.new(.2,.2,.2),jc,Color3.fromRGB(110,255,80),SP,{Transparency=1,CastShadow=false})
 local jl=Instance.new('PointLight');jl.Name='ZombieJarLight';jl.Color=Color3.fromRGB(130,255,90);jl.Range=4;jl.Brightness=.6;jl.Shadows=false;jl.Parent=jg
 jar(jg)
 local sp=part(model,'ZombieSparks',Vector3.new(.9,.6,.9),CFrame.new(capY),blue,SP,{Transparency=1,CastShadow=false})
 local pe=Instance.new('ParticleEmitter');pe.Name='ZombieSparkFX';pe.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pe.Rate=2;pe.Lifetime=NumberRange.new(.2,.45);pe.Speed=NumberRange.new(1,3);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=4
 pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
 pe.Color=ColorSequence.new(Color3.fromRGB(210,240,255),Color3.fromRGB(60,150,255));pe.Parent=sp
 head(sp,'ZombieCoil',cb):SetAttribute('PickAmp',1)
 local under=part(model,'ZombieDrips',Vector3.new(2.6,.1,.5),C*CFrame.new(-1.8,.15,0),slime,SP,{Transparency=1,CastShadow=false})
 local pd=Instance.new('ParticleEmitter');pd.Name='ZombieDripFX';pd.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pd.Rate=1.2;pd.Lifetime=NumberRange.new(.6,1);pd.Speed=NumberRange.new(0,.2);pd.Acceleration=Vector3.new(0,-14,0)
 pd.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(1,.07)});pd.LightEmission=.6
 pd.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.8,.2),NumberSequenceKeypoint.new(1,1)})
 pd.Color=ColorSequence.new(slimeHot,slime);pd.SpreadAngle=Vector2.new(5,5);pd.EmissionDirection=Enum.NormalId.Bottom;pd.Parent=under
 blade(under)
 -- On the back: a bit higher and further out, so the big head clears the character's own head.
 model:SetAttribute('BackC0',CFrame.new(.35,.1,.3))
 return tipPos,clawTip
end

-- Clown Chronomord ("Клоун-Хрономорд" concept sheet, LEGENDARY / CURSED FUNNY): a mad clown riding a big clock.
-- The head (top): a blocky cream voxel clown face with two HUGE bulging eyes (red-rimmed sockets, brown irises, the
-- right one a little smaller and higher: the sheet's crazy asymmetric stare), a glossy round red nose, red cheeks, a
-- wide grin of red lips round a dark maw full of crooked sharp teeth, and a long red TONGUE lolling out of the right
-- corner, hanging down beside the clock and curling up at the end, a little red diamond charm dangling off it. On top
-- a voxel jester hat: a band (red / blue in front, cream with a gold plate behind) and three floppy lobes: a big RED
-- one arcing up and over to the left, a BLUE one drooping to the right and a CREAM one curling up behind, each with a
-- gold voxel bell (dark slot, holes) at its tip. The body: a big round CLOCK (a dark bronze drum, a chunky gold
-- voxel bezel with bolts, a cream dial with a hairline crack, Roman numerals, black spade hands, a glass cover; the
-- back a red plate with gold bolts, a brace and a winding key), crowded by gold gears round the rim and behind the
-- head, a small watch stuck in the left cluster. Off the bottom on chains hang a gold pocket watch (gold chain) and a
-- red one (dark iron chain, longer). The shaft: a harlequin of red / cream / blue voxel tiles with gold bands (bolts,
-- cream plates); the pommel a blue block, a gold collar with fins and a stepped gold spike.
-- Materials: SmoothPlastic (face, eyes, teeth, tongue: glossy), Fabric (the jester hat), Metal (gold, bronze, iron),
-- Glass (the dial cover, the charm), Neon only for the eye glints.
-- Moving parts (MiningClient.PickFX "Clown*" / "Chrono" motions): the head giggles and bobs (ClownHead, a translation
-- so it stacks with any joint), the jaw opens to laugh / bite (ClownJaw), the eyeballs bulge out (ClownEyePop) and
-- the irises roll each their own way (ClownEye), the tongue wags and lashes out on a strike (ClownTongue, PickAmp =
-- share along it), the hat lobes flop (ClownHat, PickAmp = side) and the bells jingle on their hooks (ClownBell,
-- PickHang = the hook), the clock hands run BACKWARDS (ClownMinute / ClownHour), the gears turn (ClownGear, PickAmp =
-- speed and direction), the pocket watches swing on their chains (ClownWatch) and their hands spin (ClownWatchHand,
-- PickHang = the watch centre, PickAmp = rate).
DESIGNS.Clown=function(model,v,def,len,top)
 local SP,ME,GL,NE,FA=Enum.Material.SmoothPlastic,Enum.Material.Metal,Enum.Material.Glass,Enum.Material.Neon,Enum.Material.Fabric
 local red=rgb(v.Trim,{214,48,52})                 -- palette 1: clown red
 local red2=Color3.fromRGB(160,26,34)
 local red3=Color3.fromRGB(238,86,82)
 local cream=rgb(v.Head,{246,232,210})             -- palette 2: cream face
 local cream2=Color3.fromRGB(226,208,176)
 local cream3=Color3.fromRGB(252,244,228)
 local blue=rgb(v.Accent,{60,110,220})             -- palette 3: jester blue
 local blue2=Color3.fromRGB(38,74,168)
 local blue3=Color3.fromRGB(92,140,232)
 local gold=rgb(v.Gold,{222,168,58})               -- palette 4: brass / gold
 local gold2=Color3.fromRGB(170,118,40)
 local gold3=Color3.fromRGB(248,208,106)
 local bronze=Color3.fromRGB(92,62,44)             -- palette 5: dark bronze case
 local iron=Color3.fromRGB(58,52,54)               -- palette 6: iron / ink
 local ink=Color3.fromRGB(28,22,24)
 local dialC=Color3.fromRGB(244,234,212)
 local enamel=Color3.fromRGB(248,244,230)
 local maw=Color3.fromRGB(72,12,22)
 local tongueC=Color3.fromRGB(224,52,66)
 local tongue2=Color3.fromRGB(176,30,44)
 local rng=Random.new(1010)
 local function r(a,b)return a+(b-a)*rng:NextNumber()end
 local function pickc(list)return list[rng:NextInteger(1,#list)]end

 local CC=CFrame.new(0,1.55,0)                     -- clock centre (dial faces +Z)
 local cc=CC.Position
 local RR=1.02                                     -- clock radius
 local HC=CFrame.new(.04,3.25,.08)                 -- head centre
 local hc=HC.Position
 local HX,HY,HZ=.9,.82,.72                         -- head half width, half height, half depth
 local function at(x,y,z)return HC*CFrame.new(x,y,z)end
 local function P(x,y,z)return(HC*CFrame.new(x,y,z)).Position end
 local function head(p,extra,joint,phase)
  return anim(p,'ClownHead'..(extra and(','..extra)or''),phase or 0,joint or hc)
 end

 -- HEAD MASS: a lumpy cream voxel skull ---------------------------------------------------------------
 head(part(model,'ClownSkull',Vector3.new(HX*2-.1,HY*2-.1,HZ*2-.1),HC,cream,SP))
 local SKIN={cream,cream,cream2,cream3}
 for _=1,30 do
  local side=rng:NextInteger(1,5)
  local s=r(.24,.44)
  local x,y,z
  if side==1 then x,y,z=HX-s*.3,r(-HY+.1,HY-.1),r(-HZ,HZ)                         -- right
  elseif side==2 then x,y,z=-HX+s*.3,r(-HY+.1,HY-.1),r(-HZ,HZ)                    -- left
  elseif side==3 then x,y,z=r(-HX,HX),r(-HY+.1,HY),-HZ+s*.3                       -- back
  elseif side==4 then x,y,z=r(-HX,HX),-HY+s*.3,r(-HZ,HZ*.3)                       -- under the jaw line
  else x,y,z=(rng:NextNumber()<.5 and-1 or 1)*r(.8,HX),r(-.3,.6),HZ-s*.3 end      -- face edges only
  head(part(model,'SkinVoxel',Vector3.new(s,s*r(.75,1.1),s),at(x,y,z)*CFrame.Angles(0,r(-.12,.12),r(-.08,.08)),pickc(SKIN),SP))
 end
 -- forehead: a stepped row of voxels over the eyes, a few red make-up blocks at the temples
 for i=0,6 do
  head(part(model,'FaceVoxel',Vector3.new(.27,.24,.12),at(-.78+i*.26,.68+(i%2)*.06,HZ-.01),i%3==0 and cream2 or cream3,SP))
 end
 for s=-1,1,2 do
  head(part(model,'FacePaint',Vector3.new(.2,.24,.1),at(s*.8,.5,HZ-.02),red3,SP))
  head(part(model,'Cheek',Vector3.new(.3,.22,.1),at(s*.68,-.2,HZ+.01)*CFrame.Angles(0,0,s*.2),red3,SP))
 end

 -- EYES: huge bulging eyeballs, red-rimmed sockets, brown irises rolling each their own way --------------
 local function bigEye(name,ec,d,ph)
  head(cylZ(model,name..'Socket',.08,d*1.14,ec*CFrame.new(0,0,-d*.22),Color3.fromRGB(150,40,46),SP))
  for _,p in ipairs(ring(model,name..'Rim',ec*CFrame.new(0,0,-d*.16),d*.53,.08,.1,8,red2,SP))do head(p,'ClownEyePop',ec.Position,ph)end
  head(ball(model,name,d,ec,Color3.fromRGB(250,248,240),SP,{Reflectance=.12}),'ClownEyePop',ec.Position,ph)
  for i=1,3 do -- bloodshot veins
   local a=ph*2+i*1.9
   head(part(model,name..'Vein',Vector3.new(.03,d*.22,.02),ec*CFrame.Angles(0,0,a)*CFrame.new(0,d*.36,d*.33)*CFrame.Angles(-.7,0,0),Color3.fromRGB(206,50,56),SP),'ClownEyePop',ec.Position,ph)
  end
  local iris={}
  table.insert(iris,cylZ(model,name..'Iris',.05,d*.5,ec*CFrame.new(0,0,d*.47),Color3.fromRGB(170,92,40),SP))
  table.insert(iris,cylZ(model,name..'IrisRing',.04,d*.56,ec*CFrame.new(0,0,d*.455),Color3.fromRGB(110,56,28),SP))
  table.insert(iris,cylZ(model,name..'Pupil',.05,d*.24,ec*CFrame.new(0,0,d*.5),ink,SP))
  table.insert(iris,ball(model,name..'Glint',d*.1,ec*CFrame.new(d*.1,d*.11,d*.52),Color3.new(1,1,1),NE,{CastShadow=false}))
  for _,p in ipairs(iris)do head(p,'ClownEyePop,ClownEye',ec.Position,ph)end
 end
 bigEye('EyeL',at(-.42,.22,HZ+.08),.8,0)
 bigEye('EyeR',at(.45,.2,HZ+.12),.72,1.7)

 -- NOSE: a glossy round red clown nose ---------------------------------------------------------------
 head(ball(model,'Nose',.54,at(.02,-.07,HZ+.3),Color3.fromRGB(226,30,40),SP,{Reflectance=.22}))
 head(part(model,'NoseVoxel',Vector3.new(.2,.18,.16),at(-.14,.04,HZ+.4),Color3.fromRGB(240,60,64),SP,{Reflectance=.15}))
 head(ball(model,'NoseShine',.1,at(.1,.06,HZ+.55),Color3.fromRGB(255,190,190),SP,{Reflectance=.3,CastShadow=false}))

 -- MOUTH: a wide grin, red lips, a dark maw, rows of crooked sharp teeth -----------------------------------
 local my=-.44
 local function smile(x,k)return my+k*(x/.7)^2 end
 head(part(model,'Maw',Vector3.new(1.36,.64,.3),at(0,my-.16,HZ-.12),maw,SP))
 head(part(model,'Gum',Vector3.new(1.38,.1,.2),at(0,smile(0,.18)+.06,HZ-.02),red2,SP))
 for i=-4,4 do -- the upper lip curls up into the cheeks
  local x=i*.17;local y=smile(x,.2)+.2
  head(part(model,'Lip',Vector3.new(.2,.13,.18),at(x,y,HZ+.02)*CFrame.Angles(0,0,math.atan(2*.2*x/.49)),i%2==0 and red or red2,SP,{Reflectance=.06}))
 end
 for i=1,8 do -- upper teeth: sharp, uneven, pointing down
  local x=-.6+(i-1)*.172
  local base=P(x,smile(x,.18)+.08,HZ+.03)
  for _,p in ipairs(spike(model,'Tooth',base,Vector3.new(r(-.15,.15),-1,0).Unit,Vector3.xAxis,r(.17,.28),.15,.1,enamel,SP))do head(p)end
 end
 -- the lower jaw (opens on the hinge at the back of the mouth)
 local hinge=P(0,my-.02,-.15)
 local jawDrop=-.07
 local function jaw(p)return head(p,'ClownJaw',hinge)end
 jaw(part(model,'Jaw',Vector3.new(1.34,.26,.62),at(0,my+jawDrop-.38,HZ-.32),cream,SP))
 jaw(part(model,'Jaw',Vector3.new(1.1,.16,.3),at(0,my+jawDrop-.48,HZ-.2),cream2,SP))
 jaw(part(model,'JawGum',Vector3.new(1.2,.08,.18),at(0,my+jawDrop-.28,HZ-.06),red2,SP))
 for i=-4,4 do
  local x=i*.16;local y=smile(x,.14)-.36+jawDrop
  jaw(part(model,'Lip',Vector3.new(.19,.14,.18),at(x,y,HZ-.02)*CFrame.Angles(0,0,math.atan(2*.14*x/.49)),i%2==0 and red2 or red,SP,{Reflectance=.06}))
 end
 for i=1,7 do -- lower teeth pointing up
  local x=-.54+(i-1)*.18
  local base=P(x,smile(x,.14)-.27+jawDrop,HZ-.02)
  for _,p in ipairs(spike(model,'Tooth',base,Vector3.new(r(-.15,.15),1,0).Unit,Vector3.xAxis,r(.13,.22),.14,.1,enamel,SP))do jaw(p)end
 end

 -- TONGUE: lolling out of the right corner, down beside the clock, curling up at the end ------------------
 local tongueRoot=P(.3,my-.14,HZ-.04)
 local TP={tongueRoot,Vector3.new(.78,2.5,1.02),Vector3.new(1.14,1.98,.86),Vector3.new(1.24,1.4,.7),Vector3.new(1.12,1.0,.62),
  Vector3.new(.9,.96,.6),Vector3.new(.8,1.16,.6)}
 local segs={}
 for i=1,#TP-1 do
  local a,b=TP[i],TP[i+1]
  table.insert(segs,{a,a:Lerp(b,.5)});table.insert(segs,{a:Lerp(b,.5),b})
 end
 local tipPos
 for i,sg in ipairs(segs)do
  local k=i/#segs
  local w=.38-k*.16
  local function tongue(p)head(p,'ClownTongue',tongueRoot,0);p:SetAttribute('PickAmp',k);return p end
  local a,b=sg[1],sg[2]
  local dir=(b-a).Unit
  tongue(bar(model,'Tongue',a-dir*.05,b+dir*.05,w,.17,i%3==0 and Color3.fromRGB(236,70,80)or tongueC,SP,{Reflectance=.12}))
  tongue(bar(model,'TongueGroove',a,b,.05,.18+.02,tongue2,SP))
  if i%2==0 then
   tongue(part(model,'TongueVoxel',Vector3.new(w*.55,w*.55,.12),CFrame.new(b+Vector3.new(r(-.05,.05),0,.06))*CFrame.Angles(0,0,r(-.4,.4)),Color3.fromRGB(240,92,98),SP,{Reflectance=.12}))
  end
  if i==#segs then tipPos=b end
 end
 -- the red diamond charm dangling off the curl on a gold thread
 do
  local hang=TP[5]+Vector3.new(0,-.06,.02)
  local k=1
  local function charm(p)head(p,'ClownTongue',tongueRoot,0);p:SetAttribute('PickAmp',k);return p end
  charm(bar(model,'CharmThread',hang,hang-Vector3.new(0,.34,0),.03,.03,gold3,ME))
  charm(part(model,'CharmCap',Vector3.new(.08,.06,.08),CFrame.new(hang-Vector3.new(0,.36,0)),gold,ME))
  charm(part(model,'Charm',Vector3.new(.16,.16,.1),CFrame.new(hang-Vector3.new(0,.5,0))*CFrame.Angles(0,0,math.pi/4),Color3.fromRGB(230,28,44),GL,{Reflectance=.2}))
  charm(part(model,'Charm',Vector3.new(.1,.1,.12),CFrame.new(hang-Vector3.new(0,.5,0))*CFrame.Angles(0,0,math.pi/4),Color3.fromRGB(255,120,120),SP))
 end
 model:SetAttribute('ChronoTongueTip',tipPos)

 -- JESTER HAT: a band, three floppy voxel lobes, gold bells -----------------------------------------------
 for i=0,15 do
  local a=i/16*math.pi*2
  local x,z=math.cos(a)*(HX-.08),math.sin(a)*(HZ-.06)
  local col=z<-.25 and(i%2==0 and cream or cream2)or(x<0 and(i%2==0 and red or red2)or(i%2==0 and blue or blue2))
  local pos=P(x,HY+.02,z)
  head(part(model,'HatBand',Vector3.new(.36,.28,.3),CFrame.lookAt(pos,pos+Vector3.new(x,0,z))*CFrame.Angles(0,0,r(-.1,.1)),col,FA))
 end
 head(part(model,'HatPlate',Vector3.new(.44,.26,.06),at(0,HY+.04,-HZ-.12),gold,ME,{Reflectance=.15}))
 for s=-1,1,2 do head(part(model,'Bolt',Vector3.new(.07,.07,.05),at(s*.15,HY+.04,-HZ-.16),gold3,ME))end
 head(part(model,'HatCrown',Vector3.new(1.3,.34,1.0),at(0,HY+.24,-.05),red,FA))
 head(part(model,'HatCrown',Vector3.new(.6,.3,.7),at(.42,HY+.3,0),blue,FA))
 local function bez4(a,b,c,d,t)local u=1-t;return a*u*u*u+b*3*u*u*t+c*3*u*t*t+d*t*t*t end
 local function bell(tip,base,amp,ph)
  local pos=tip-Vector3.new(0,.34,0)
  local list={}
  table.insert(list,part(model,'BellLoop',Vector3.new(.08,.16,.14),CFrame.new(tip-Vector3.new(0,.06,0)),gold2,ME))
  table.insert(list,ball(model,'BellCore',.46,CFrame.new(pos),gold,ME,{Reflectance=.18}))
  for k=0,5 do
   local a=k/6*math.pi*2
   table.insert(list,part(model,'BellVoxel',Vector3.new(.17,.17,.17),CFrame.new(pos+Vector3.new(math.cos(a)*.2,(k%2==0)and .1 or -.1,math.sin(a)*.2))*CFrame.Angles(0,-a,0),
    k%3==0 and gold3 or gold2,ME,{Reflectance=.12}))
  end
  table.insert(list,part(model,'BellVoxel',Vector3.new(.22,.12,.22),CFrame.new(pos+Vector3.new(0,.21,0)),gold3,ME,{Reflectance=.12}))
  table.insert(list,part(model,'BellVoxel',Vector3.new(.2,.1,.2),CFrame.new(pos-Vector3.new(0,.21,0)),gold2,ME))
  table.insert(list,part(model,'BellSlot',Vector3.new(.3,.05,.06),CFrame.new(pos+Vector3.new(0,-.07,.21)),ink,SP))
  for s=-1,1,2 do table.insert(list,part(model,'BellHole',Vector3.new(.07,.07,.05),CFrame.new(pos+Vector3.new(s*.1,.08,.2)),ink,SP))end
  for _,p in ipairs(list)do
   head(p,'ClownHat,ClownBell',base,ph);p:SetAttribute('PickAmp',amp);p:SetAttribute('PickHang',tip-base)
  end
  return pos
 end
 local function lobe(p0,p1,p2,p3,r0,r1,cols,amp,ph)
  local base=P(p0.X,p0.Y,p0.Z)
  local N=10
  for i=0,N do
   local t=i/N
   local q=HC*bez4(p0,p1,p2,p3,t)
   local rad=r0+(r1-r0)*t
   local s=rad*1.7
   head(part(model,'HatVoxel',Vector3.new(s,s,s),CFrame.new(q)*CFrame.Angles(r(-.3,.3),r(-.3,.3),r(-.3,.3)),cols[(i%#cols)+1],FA),'ClownHat',base,ph):SetAttribute('PickAmp',amp)
   if i<N then
    for _=1,1 do
     local o=Vector3.new(r(-1,1),r(-1,1),r(-1,1)).Unit*rad*.75
     head(part(model,'HatVoxel',Vector3.new(s,s,s)*r(.42,.6),CFrame.new(q+o)*CFrame.Angles(r(-.4,.4),r(-.4,.4),r(-.4,.4)),pickc(cols),FA),'ClownHat',base,ph):SetAttribute('PickAmp',amp)
    end
   end
  end
  return bell(HC*p3,base,amp,ph)
 end
 local bellL=lobe(Vector3.new(-.35,HY+.15,0),Vector3.new(-.5,HY+1.35,.1),Vector3.new(-1.55,HY+1.35,.12),Vector3.new(-1.9,HY+.3,.16),.4,.16,{red,red2,red,red3},-1,0)
 local bellR=lobe(Vector3.new(.45,HY+.1,0),Vector3.new(1.0,HY+.8,-.1),Vector3.new(1.7,HY+.6,-.1),Vector3.new(1.85,-.12,.02),.36,.15,{blue,blue2,blue,blue3},1,1.1)
 lobe(Vector3.new(.05,HY+.2,-.3),Vector3.new(.15,HY+1.3,-.5),Vector3.new(.7,HY+1.65,-.9),Vector3.new(1.0,HY+1.0,-1.25),.34,.15,{cream,cream2,red,cream3},.4,2.3)

 -- THE CLOCK: bronze drum, gold voxel bezel, cream dial, Roman numerals, hands running backwards -----------
 cylZ(model,'ClockCase',.56,RR*2,CC,bronze,ME,{Reflectance=.05})
 ring(model,'ClockBezel',CC*CFrame.new(0,0,.2),RR-.08,.26,.28,16,gold,ME,nil,{Reflectance=.15})
 cylZ(model,'DialLip',.05,(RR-.24)*2,CC*CFrame.new(0,0,.25),gold2,ME,{Reflectance=.1})
 ring(model,'ClockBezel',CC*CFrame.new(0,0,-.2),RR-.08,.26,.28,16,gold2,ME,nil,{Reflectance=.1})
 for i=0,7 do
  local a=i/8*math.pi*2+.2
  part(model,'Bolt',Vector3.new(.14,.14,.1),CC*CFrame.new(math.cos(a)*(RR-.08),math.sin(a)*(RR-.08),.37)*CFrame.Angles(0,0,a+.4),gold3,ME,{Reflectance=.2})
 end
 for _=1,8 do -- chunky voxel lumps on the rim
  local a=r(0,math.pi*2)
  part(model,'BezelVoxel',Vector3.new(r(.16,.26),r(.16,.26),r(.2,.3)),CC*CFrame.new(math.cos(a)*(RR-.02),math.sin(a)*(RR-.02),r(-.15,.2))*CFrame.Angles(0,0,a+r(-.3,.3)),pickc({gold,gold2,gold3}),ME,{Reflectance=.12})
 end
 local dial=cylZ(model,'Dial',.04,(RR-.3)*2,CC*CFrame.new(0,0,.27),dialC,SP)
 part(model,'DialCrack',Vector3.new(.022,.46,.012),CC*CFrame.new(-.26,-.3,.295)*CFrame.Angles(0,0,.5),Color3.fromRGB(160,140,118),SP,{CastShadow=false})
 part(model,'DialCrack',Vector3.new(.02,.24,.012),CC*CFrame.new(-.4,-.12,.295)*CFrame.Angles(0,0,-.3),Color3.fromRGB(160,140,118),SP,{CastShadow=false})
 local ROMAN={'I','II','III','IIII','V','VI','VII','VIII','IX','X','XI','XII'}
 for i=1,12 do
  local a=i/12*math.pi*2
  local s=ROMAN[i]
  local np=part(model,'Numeral',Vector3.new(.06+#s*.06,.17,.02),CC*CFrame.new(math.sin(a)*.55,math.cos(a)*.55,.3)*CFrame.Angles(0,0,-a),ink,SP,{Transparency=1,CastShadow=false})
  text(np,Enum.NormalId.Back,s,ink,Enum.Font.Antique)
  part(model,'HourTick',Vector3.new(.04,.08,.02),CC*CFrame.new(math.sin(a)*.69,math.cos(a)*.69,.3)*CFrame.Angles(0,0,-a),ink,SP,{CastShadow=false})
 end
 local hp=CC*CFrame.new(0,0,.33)
 local function hand(name,a,l,w,z,kind)
  local base=hp*CFrame.new(0,0,z)*CFrame.Angles(0,0,-a)
  local list={part(model,name,Vector3.new(w,l,.03),base*CFrame.new(0,l*.5-.06,0),ink,SP),
   part(model,name..'Spade',Vector3.new(w*1.9,w*1.9,.03),base*CFrame.new(0,l-.1,0)*CFrame.Angles(0,0,math.pi/4),ink,SP),
   part(model,name..'Tail',Vector3.new(w*1.6,w*1.6,.03),base*CFrame.new(0,-.1,0)*CFrame.Angles(0,0,math.pi/4),ink,SP)}
  for _,p in ipairs(list)do anim(p,kind,0,hp.Position)end
 end
 hand('MinuteHand',0,.6,.06,0,'ClownMinute')
 hand('HourHand',math.rad(60),.4,.08,.02,'ClownHour')
 ball(model,'HandPin',.13,hp*CFrame.new(0,0,.05),gold3,ME,{Reflectance=.25})
 cylZ(model,'ClockGlass',.03,(RR-.28)*2,CC*CFrame.new(0,0,.4),Color3.fromRGB(220,236,255),GL,{Transparency=.84,Reflectance=.3,CastShadow=false})
 -- the back: a red plate with gold bolts, a cross brace and a winding key
 cylZ(model,'ClockBack',.06,(RR-.18)*2,CC*CFrame.new(0,0,-.31),red,SP,{Reflectance=.05})
 for i=0,7 do
  local a=i/8*math.pi*2
  part(model,'Bolt',Vector3.new(.13,.13,.08),CC*CFrame.new(math.cos(a)*.62,math.sin(a)*.62,-.36)*CFrame.Angles(0,0,a),gold3,ME)
 end
 for k=0,1 do part(model,'BackBrace',Vector3.new(1.3,.12,.05),CC*CFrame.new(0,0,-.35)*CFrame.Angles(0,0,math.pi/4+k*math.pi/2),gold2,ME)end
 cylZ(model,'BackBoss',.12,.34,CC*CFrame.new(0,0,-.38),gold,ME,{Reflectance=.2})
 part(model,'WindKey',Vector3.new(.08,.08,.24),CC*CFrame.new(0,0,-.5),gold2,ME)
 for s=-1,1,2 do part(model,'WindKey',Vector3.new(.18,.26,.06),CC*CFrame.new(s*.13,0,-.62),gold,ME,{Reflectance=.15})end
 -- the neck: a gold collar joining the clock to the head, voxels of brass under the chin
 part(model,'NeckCollar',Vector3.new(.9,.3,.6),CFrame.new(0,2.5,-.02),gold2,ME)
 for _=1,6 do part(model,'NeckVoxel',Vector3.new(r(.18,.3),r(.18,.3),r(.18,.3)),CFrame.new(r(-.5,.5),r(2.4,2.62),r(-.3,.15))*CFrame.Angles(r(-.3,.3),r(-.3,.3),0),pickc({gold,gold2,bronze}),ME)end

 -- GEARS: gold gears crowding the rim and the back of the head (they turn) --------------------------------
 local function gear(cf,rd,n,depth,col,spin)
  local list={cylZ(model,'Gear',depth,rd*1.6,cf,col,ME,{Reflectance=.14}),
   cylZ(model,'GearHub',depth+.04,rd*.6,cf,gold2,ME,{Reflectance=.1}),
   cylZ(model,'GearHole',depth+.06,rd*.26,cf,bronze,ME)}
  local ph=r(0,1)
  for k=0,n-1 do
   local a=k/n*math.pi*2+ph
   table.insert(list,part(model,'GearTooth',Vector3.new(rd*.36,rd*.4,depth),cf*CFrame.Angles(0,0,a)*CFrame.new(0,rd*.86,0),col,ME,{Reflectance=.14}))
  end
  for _,p in ipairs(list)do anim(p,'ClownGear',0,cf.Position);p:SetAttribute('PickAmp',spin)end
 end
 for _,g in ipairs({
  {-1.08,2.3,.12,.34,8,1.5},{-1.24,1.66,.04,.28,7,-1.9},{-1.14,1.0,.14,.3,8,1.7},{-.78,.58,.18,.24,6,-2.2},
  {1.04,.82,.1,.27,7,2},{1.12,2.3,-.08,.3,8,-1.6},{-.6,2.72,-.2,.3,8,1.4},{.62,2.74,-.26,.26,7,-1.8},
  {.02,.4,.38,.2,6,2.4},{1.3,1.5,-.15,.22,6,2.1}})do
  gear(CFrame.new(g[1],g[2],g[3]),g[4],g[5],.14,pickc({gold,gold,gold3,gold2}),g[6])
 end

 -- POCKET WATCHES: a small one stuck in the left gears, a gold and a red one swinging on chains -------------
 local function pocketWatch(name,center,d,caseCol,motion,joint)
  local cf=CFrame.new(center)
  local list,hands={},{}
  table.insert(list,cylZ(model,name..'Case',.16,d,cf,caseCol,ME,{Reflectance=.18}))
  for _,p in ipairs(ring(model,name..'Rim',cf*CFrame.new(0,0,.07),d*.45,d*.1,.06,8,gold3,ME,nil,{Reflectance=.2}))do table.insert(list,p)end
  table.insert(list,cylZ(model,name..'Face',.02,d*.76,cf*CFrame.new(0,0,.085),dialC,SP))
  for k=0,3 do
   local a=k/4*math.pi*2
   table.insert(list,part(model,name..'Tick',Vector3.new(.025,d*.1,.015),cf*CFrame.new(math.sin(a)*d*.3,math.cos(a)*d*.3,.1)*CFrame.Angles(0,0,-a),ink,SP,{CastShadow=false}))
  end
  table.insert(list,cylY(model,name..'Crown',.08,d*.16,cf*CFrame.new(0,d*.54,0),gold2,ME))
  for _,p in ipairs(ring(model,name..'Bow',cf*CFrame.new(0,d*.68,0)*CFrame.Angles(0,math.pi/2,0),d*.13,.04,.04,6,gold3,ME))do table.insert(list,p)end
  table.insert(hands,part(model,name..'Hand',Vector3.new(.03,d*.3,.015),cf*CFrame.new(0,d*.13,.11),ink,SP,{CastShadow=false}))
  table.insert(hands,part(model,name..'Hand',Vector3.new(.035,d*.2,.015),cf*CFrame.new(d*.07,.03,.115)*CFrame.Angles(0,0,-1),ink,SP,{CastShadow=false}))
  if motion then
   for _,p in ipairs(list)do anim(p,motion,0,joint)end
   for i,p in ipairs(hands)do
    anim(p,motion..',ClownWatchHand',0,joint);p:SetAttribute('PickHang',center-joint);p:SetAttribute('PickAmp',i==1 and 1 or .08)
   end
  end
  return center+Vector3.new(0,d*.8,0)
 end
 pocketWatch('MiniWatch',Vector3.new(-1.42,1.32,.26),.42,gold,nil)
 local function chain(a,b,col,n,joint,ph)
  for i=1,n do
   local p=a:Lerp(b,(i-.5)/n)
   local link=part(model,'Chain',Vector3.new(.07,(b-a).Magnitude/n+.03,i%2==0 and .13 or .05),CFrame.new(p)*CFrame.Angles(0,i%2==0 and math.pi/2 or 0,0),col,ME,{Reflectance=.1})
   anim(link,'ClownWatch',ph,joint)
  end
 end
 do -- the gold watch on a gold chain (right)
  local hook=Vector3.new(.5,.66,.22)
  local center=Vector3.new(.66,-.12,.24)
  chain(hook,center+Vector3.new(0,.42,0),gold3,5,hook,0)
  part(model,'ChainHook',Vector3.new(.14,.12,.14),CFrame.new(hook),gold2,ME)
  pocketWatch('GoldWatch',center,.6,gold,'ClownWatch',hook)
 end
 do -- the red watch on a long dark iron chain (left)
  local hook=Vector3.new(-.36,.6,.22)
  local center=Vector3.new(-.6,-.9,.26)
  chain(hook,center+Vector3.new(0,.36,0),iron,8,hook,1.3)
  part(model,'ChainHook',Vector3.new(.14,.12,.14),CFrame.new(hook),gold2,ME)
  pocketWatch('RedWatch',center,.5,Color3.fromRGB(210,36,44),'ClownWatch',hook)
 end
 -- the watches swing with their own phase (the parts were tagged with phase 0: give the red one its own)
 for _,d in ipairs(model:GetChildren())do
  if d:IsA('BasePart')and string.sub(d.Name,1,8)=='RedWatch'then d:SetAttribute('PickPhase',1.3)end
 end

 -- SHAFT: a harlequin of red / cream / blue voxel tiles, gold bands with bolts and cream plates -------------
 local sTop,sBot=.62,-2.3
 part(model,'ShaftCore',Vector3.new(.44,sTop-sBot,.44),CFrame.new(0,(sTop+sBot)*.5,0),cream,SP)
 local rowH=.25
 local rows=math.floor((sTop-sBot)/rowH)
 local FACES={{Vector3.zAxis,Vector3.xAxis},{Vector3.xAxis,-Vector3.zAxis},{-Vector3.zAxis,-Vector3.xAxis},{-Vector3.xAxis,Vector3.zAxis}}
 for row=0,rows-1 do
  local y=sTop-(row+.5)*rowH
  for f,fc in ipairs(FACES)do
   local n,side=fc[1],fc[2]
   local wide=f%2==0 -- the side faces get one tile per row, front and back two
   for col=0,wide and 0 or 1 do
    local idx=row+col+f
    local c=(idx%2==0)and((row%3==0)and red2 or red)or((row+f)%3==0 and blue or cream3)
    local pos=Vector3.new(0,y,0)+n*.235+side*(wide and 0 or(col-.5)*.24)
    part(model,'Harlequin',Vector3.new(wide and .47 or .23,rowH-.02,.06),CFrame.fromMatrix(pos,side,Vector3.yAxis,n),c,SP,{Reflectance=.04})
   end
  end
 end
 local function band(y,h)
  part(model,'ShaftBand',Vector3.new(.64,h,.64),CFrame.new(0,y,0),gold,ME,{Reflectance=.15})
  part(model,'ShaftBand',Vector3.new(.56,h+.06,.56),CFrame.new(0,y,0)*CFrame.Angles(0,math.pi/4,0),gold2,ME)
  for _,fc in ipairs(FACES)do
   local n,side=fc[1],fc[2]
   part(model,'BandPlate',Vector3.new(.26,h*.62,.04),CFrame.fromMatrix(Vector3.new(0,y,0)+n*.34,side,Vector3.yAxis,n),cream3,SP)
   for s=-1,1,2 do part(model,'Bolt',Vector3.new(.07,.07,.05),CFrame.fromMatrix(Vector3.new(0,y,0)+n*.35+side*s*.22,side,Vector3.yAxis,n),gold3,ME)end
  end
 end
 band(.5,.24);band(-.42,.2);band(-1.0,.2);band(-2.12,.22)

 -- POMMEL: a blue block, a gold collar with fins, a stepped gold spike ---------------------------------------
 part(model,'PommelBlock',Vector3.new(.58,.3,.58),CFrame.new(0,-2.4,0),blue,SP,{Reflectance=.05})
 part(model,'PommelBlock',Vector3.new(.5,.32,.5),CFrame.new(0,-2.4,0)*CFrame.Angles(0,math.pi/4,0),blue2,SP)
 part(model,'PommelCollar',Vector3.new(.74,.14,.74),CFrame.new(0,-2.6,0),gold,ME,{Reflectance=.18})
 for k=0,3 do
  local a=k/4*math.pi*2
  part(model,'PommelFin',Vector3.new(.12,.26,.32),CFrame.new(math.cos(a)*.42,-2.66,math.sin(a)*.42)*CFrame.Angles(0,-a,0),gold2,ME)
 end
 local y=-2.72
 for i,w in ipairs({.52,.4,.28,.16})do
  local h=.14
  part(model,'PommelSpike',Vector3.new(w,h,w),CFrame.new(0,y-h*.5,0)*CFrame.Angles(0,i%2==0 and math.pi/4 or 0,0),i%2==0 and gold3 or gold,ME,{Reflectance=.18})
  y-=h
 end
 part(model,'PommelTip',Vector3.new(.08,.12,.08),CFrame.new(0,y-.05,0),gold3,ME)

 -- GLOW and IDLE FX: a warm light on the dial, slow gold sparks round the clock ------------------------------
 local glow=part(model,'ChronoGlow',Vector3.new(.3,.3,.3),CC*CFrame.new(0,0,.7),gold3,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='ChronoLight';light.Color=Color3.fromRGB(255,196,120);light.Range=6;light.Brightness=.55;light.Shadows=false;light.Parent=glow
 local sp=part(model,'ChronoSparks',Vector3.new(2.4,2.4,.6),CC,gold,SP,{Transparency=1,CastShadow=false})
 local pe=Instance.new('ParticleEmitter');pe.Name='ChronoSparkFX';pe.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pe.Rate=1.4;pe.Lifetime=NumberRange.new(.6,1.2);pe.Speed=NumberRange.new(.3,1);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=1.5
 pe.Acceleration=Vector3.new(0,.8,0)
 pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
 pe.Color=ColorSequence.new(Color3.fromRGB(255,226,140),Color3.fromRGB(255,120,70));pe.Parent=sp
 -- On the back: higher and further out, so the big head clears the character's own head.
 model:SetAttribute('BackC0',CFrame.new(.35,.15,.3))
 return bellL,bellR
end

-- Nasty Octopus ("Кирка Мерзкий Спрут" / GROSS OCTOPICK concept sheet, LEGENDARY / OCEAN HORROR, "It watches. It drips. It
-- digs."): a grotesque voxel octopus fused into a pickaxe. The head: a fat glossy blue voxel MANTLE (stepped octagon layers,
-- lumpy blue / light-blue / deep-blue voxels, wet highlights, violet patches low down) leaning a little back, with ONE HUGE
-- YELLOW EYE on the front (a domed eyeball of pixel tiles: pale-yellow glowing centre, gold, orange, a burnt-orange edge; a
-- tall black slit pupil with a burnt-red outline; glints) in a dark socket, framed by a heavy blue / violet voxel lid and a
-- thick brow, a tentacle curling up each side of it with pink suckers; two small tentacles curl on top. Out of the sides of
-- the head two curved lilac-grey crescent PICK BLADES (pale wet top edge, dark slate underside, voxel shading, sharp organic
-- points) sweep out and down, each with a tentacle lying along its root. Under the head the tentacles hang and curl: a long
-- one down the right (a strange CURSED PEARL grows in its curl during the inspect), a curl on the left, two more behind; on
-- the back hangs the INK SAC (a glossy, slightly transparent black-violet bulb with dark ink inside). Two tentacles spiral
-- down the brown voxel wooden SHAFT (wet slime streaks) with pink suckers outside and end in a coil round the bottom whose
-- tip curls out. Seawater DRIPS everywhere: glossy icicles under the head, the eye, the blades and the tentacles, and live
-- drops that stretch, fall and come back (GummyDrop + PickGoo).
-- Materials: Glass (the wet glossy body, drips, the ink sac), SmoothPlastic (eye, suckers), Limestone / Slate (the organic
-- blades), Wood (the shaft), Neon only for the eye's glowing centre, its glints and the ink's inner gleam.
-- Moving parts (MiningClient.PickFX "Octo*" motions): the whole head breathes (OctoMantle, a translation so it stacks with any
-- joint); the eye rolls, wanders, stares at you and bulges on a strike (OctoEye); every free tentacle wiggles and drips,
-- sways harder while running and SPREADS OPEN on a strike (OctoArm, PickAmp = share along it, PickPop = the axis it opens
-- round); the spiral tentacles slither round the shaft (OctoWrap) and the bottom coil curls (OctoCoil); the ink sac pulses
-- (OctoSac). The cursed pearl (OctoPearl) is hidden until the inspect.
DESIGNS.Octopus=function(model,v,def,len,top)
 local SP,GL,NE,LI,SL,WO=Enum.Material.SmoothPlastic,Enum.Material.Glass,Enum.Material.Neon,Enum.Material.Limestone,Enum.Material.Slate,Enum.Material.Wood
 local blue=rgb(v.Head,{64,120,236})               -- palette 1: wet ocean blue
 local blue2=Color3.fromRGB(42,82,200)
 local blue3=Color3.fromRGB(98,160,252)
 local shine=Color3.fromRGB(178,224,255)
 local navy=Color3.fromRGB(32,42,128)
 local violet=rgb(v.Trim,{124,72,220})             -- palette 2: violet
 local violet2=Color3.fromRGB(88,48,172)
 local pink=rgb(v.Sucker,{232,112,230})            -- palette 3: sucker pink
 local pink2=Color3.fromRGB(184,74,196)
 local hole=Color3.fromRGB(80,26,98)
 local gold=rgb(v.Accent,{255,206,48})             -- palette 4: the eye
 local grey=rgb(v.Blade,{198,188,214})             -- palette 5: blade lilac-grey
 local wood=rgb(v.Shaft,{118,76,44})
 local DRIP=Color3.fromRGB(150,214,255)
 local DRIP2=Color3.fromRGB(204,238,255)
 local wet={Transparency=.28,Reflectance=.2,CastShadow=false}
 local rng=Random.new(1111)
 local function r(a,b)return a+(b-a)*rng:NextNumber()end
 local function pickc(list)return list[rng:NextInteger(1,#list)]end
 local function tag(p,kinds,joint,amp,axis,phase)
  anim(p,kinds,phase or 0,joint)
  if amp then p:SetAttribute('PickAmp',amp)end
  if axis then p:SetAttribute('PickPop',axis)end
  return p
 end

 -- MANTLE: a fat glossy voxel dome leaning back ------------------------------------------------------------
 local MC=Vector3.new(0,2.88,-.1)                 -- mantle centre
 local RX,RY,RZ=1.1,1.04,.9
 local function mz(y)return MC.Z-(y-MC.Y)*.14 end   -- the dome leans back
 local function head(p)return anim(p,'OctoMantle',0,MC)end
 local LH=.2
 for i=0,math.floor(RY*2/LH)-1 do
  local y=MC.Y-RY+(i+.5)*LH
  local f=math.sqrt(math.max(0,1-((y-MC.Y)/RY)^2))
  local w,d=RX*f,RZ*f
  if w>.1 then
   local cf=CFrame.new(MC.X,y,mz(y))
   head(part(model,'Mantle',Vector3.new(w*2,LH+.01,d*1.66),cf,blue,GL,{Reflectance=.08}))
   head(part(model,'Mantle',Vector3.new(w*1.66,LH+.01,d*2),cf,blue,GL,{Reflectance=.08}))
  end
 end
 local function surface(dir,k)
  local y=MC.Y+dir.Y*RY*k
  return Vector3.new(MC.X+dir.X*RX*k,y,mz(y)+dir.Z*RZ*k)
 end
 local NV=72
 for k=0,NV-1 do
  local yy=1-(k+.5)/NV*2
  local rr=math.sqrt(1-yy*yy)
  local th=k*2.39996
  local dir=Vector3.new(math.cos(th)*rr,yy,math.sin(th)*rr)
  local eyeZone=dir.Z>.42 and math.abs(dir.X)<.66 and yy>-.55 and yy<.72
  if not eyeZone and yy>-.86 then
   local s=r(.2,.32)
   local pos=surface(dir,.92)
   local nrm=Vector3.new(dir.X/RX,dir.Y/RY,dir.Z/RZ).Unit
   local col
   if yy>.45 then col=pickc({blue3,blue3,blue,shine})
   elseif yy<-.35 then col=pickc({blue2,violet,blue2,navy})
   else col=pickc({blue,blue,blue3,blue2})end
   local cf=math.abs(nrm.Y)>.97 and CFrame.new(pos)or CFrame.lookAt(pos,pos+nrm)
   head(part(model,'MantleVoxel',Vector3.new(s,s*r(.8,1.1),s),cf*CFrame.Angles(0,0,r(-.25,.25)),col,GL,{Reflectance=.08}))
  end
 end
 -- wet highlights on the dome (the sheet's bright glossy spots)
 for _,g in ipairs({{-.42,.7,.42},{-.2,.86,.3},{.36,.62,.6},{-.7,.3,.55},{.62,.12,.68},{-.1,.55,-.75},{.5,.55,-.6}})do
  local dir=Vector3.new(g[1],g[2],g[3]).Unit
  local pos=surface(dir,1.0)
  head(part(model,'MantleShine',Vector3.new(.13,.13,.06),CFrame.lookAt(pos,pos+dir),Color3.fromRGB(226,244,255),GL,{Reflectance=.3,CastShadow=false}))
 end

 -- THE EYE: one huge yellow eye with a slit pupil, a dark socket, a heavy lid -----------------------------
 local E=CFrame.new(.04,2.98,.64)                   -- eyeball centre (looks along +Z)
 local ER=.52
 local function eye(p)return anim(p,'OctoMantle,OctoEye',0,E.Position)end
 head(cylZ(model,'EyeSocket',.12,ER*2.42,E*CFrame.new(0,0,.12),Color3.fromRGB(30,20,70),SP))
 for i,p in ipairs(ring(model,'EyeLid',E*CFrame.new(0,0,.2),ER+.09,.22,.26,14,blue2,GL,nil,{Reflectance=.1}))do
  p.Color=(i%3==0)and violet2 or((i%3==1)and navy or blue2)
  head(p)
 end
 for i=0,5 do -- the heavy brow over the eye
  local a=math.rad(38+i*21)
  local s=r(.24,.3)
  head(part(model,'EyeBrow',Vector3.new(s,s,s*1.1),E*CFrame.new(math.cos(a)*(ER+.24),math.sin(a)*(ER+.22),.18)*CFrame.Angles(0,0,a+r(-.2,.2)),
   (i%2==0)and blue or blue3,GL,{Reflectance=.08}))
 end
 for i=0,3 do -- the lower lid
  local a=math.rad(232+i*25)
  head(part(model,'EyeLidLow',Vector3.new(.22,.2,.24),E*CFrame.new(math.cos(a)*(ER+.16),math.sin(a)*(ER+.14),.2)*CFrame.Angles(0,0,a),
   (i%2==0)and violet2 or blue2,GL,{Reflectance=.08}))
 end
 eye(ball(model,'EyeBall',ER*2,E,Color3.fromRGB(232,122,22),SP,{Reflectance=.12}))
 local TS=.14
 for gx=-3,3 do
  for gy=-3,3 do
   local x,y=gx*TS,gy*TS
   local rr=math.sqrt(x*x+y*y)
   if rr<=ER*.9 then
    local z=math.sqrt(ER*ER-rr*rr)
    local q=rr/(ER*.9)-y*.5+x*.12
    local col,mat
    if q<.4 then col,mat=Color3.fromRGB(255,222,92),NE
    elseif q<.7 then col,mat=gold,SP
    elseif q<.92 then col,mat=Color3.fromRGB(252,162,30),SP
    else col,mat=Color3.fromRGB(222,98,18),SP end
    local lp=Vector3.new(x,y,z*.985)
    eye(part(model,'Iris',Vector3.new(TS+.02,TS+.02,.06),E*CFrame.lookAt(lp,lp*2),col,mat,{Reflectance=mat==SP and .1 or 0,CastShadow=false}))
   end
  end
 end
 for _,s in ipairs({{.41,.032},{.28,.07},{.14,.1},{0,.112},{-.14,.1},{-.28,.07},{-.41,.032}})do
  local y,w=s[1],s[2]
  local th=-math.asin(math.clamp(y/ER,-1,1))
  local z=math.sqrt(math.max(0,ER*ER-y*y))
  eye(part(model,'PupilRim',Vector3.new(w+.07,.15,.05),E*CFrame.new(0,y,z+.02)*CFrame.Angles(th,0,0),Color3.fromRGB(150,46,16),SP,{CastShadow=false}))
  eye(part(model,'Pupil',Vector3.new(w,.155,.05),E*CFrame.new(0,y,z+.045)*CFrame.Angles(th,0,0),Color3.fromRGB(18,6,12),SP,{CastShadow=false}))
 end
 eye(part(model,'EyeGlint',Vector3.new(.12,.12,.04),E*CFrame.new(-.2,.22,.44)*CFrame.Angles(.45,-.4,0),Color3.new(1,1,1),NE,{CastShadow=false}))
 eye(part(model,'EyeGlint',Vector3.new(.06,.06,.04),E*CFrame.new(-.07,.31,.42)*CFrame.Angles(.6,-.15,0),Color3.new(1,1,1),NE,{CastShadow=false}))
 eye(part(model,'EyeGlint',Vector3.new(.05,.05,.04),E*CFrame.new(.22,-.24,.4)*CFrame.Angles(-.5,.45,0),Color3.fromRGB(255,240,200),NE,{CastShadow=false}))

 -- DRIPS: glossy seawater icicles and live drops -----------------------------------------------------------
 local function drip(pos,length,d,ride)
  local a=part(model,'Drip',Vector3.new(d*.62,length,d*.62),CFrame.new(pos-Vector3.new(0,length*.5,0)),DRIP,GL,wet)
  local b=blob(model,'DripDrop',Vector3.new(d,d*1.35,d),CFrame.new(pos-Vector3.new(0,length+d*.3,0)),DRIP2,GL,wet)
  if ride then ride(a);ride(b)end
 end
 local function liveDrop(pos,phase,d,kinds,joint,amp,axis)
  d=d or .14
  for i,k in ipairs({.33,.66,1})do
   local p=i<3 and part(model,'DripNeck',Vector3.new(d*.5,d*1.1,d*.5),CFrame.new(pos-Vector3.new(0,.06*i,0)),DRIP,GL,wet)
    or blob(model,'DripLive',Vector3.new(d,d*1.3,d),CFrame.new(pos-Vector3.new(0,.18,0)),DRIP2,GL,wet)
   tag(p,(kinds and(kinds..',')or'')..'GummyDrop',joint or pos,amp,axis,phase)
   p:SetAttribute('PickDropK',k)
   if i==3 then p:SetAttribute('PickGoo',true)end
  end
 end
 drip(E*CFrame.new(-.22,-.62,.22).Position,.26,.12,head)
 drip(E*CFrame.new(.18,-.6,.24).Position,.16,.1,head)
 liveDrop(E*CFrame.new(-.02,-.66,.24).Position,.1,.13,'OctoMantle',MC)
 for _,g in ipairs({{-.62,1.9,.5,.3},{.7,1.92,.42,.22},{-.2,1.88,-.5,.26},{.3,1.9,.62,.18}})do
  drip(Vector3.new(g[1],g[2],g[3]),g[4],.13,head)
 end

 -- PICK BLADES: two curved lilac-grey crescents with pale wet top edges and sharp organic points ---------------
 local function bez(a,b,c,d,t)local u=1-t;return a*u*u*u+b*3*u*u*t+c*3*u*t*t+d*t*t*t end
 local BL={grey:Lerp(Color3.new(1,1,1),.28),grey,Color3.fromRGB(164,150,190),Color3.fromRGB(126,112,150),Color3.fromRGB(222,206,236)}
 local tips,bladeTop={},{}
 for _,s in ipairs({-1,1})do
  local P0,P1,P2,P3=Vector3.new(s*.5,1.9,0),Vector3.new(s*1.55,2.42,.02),Vector3.new(s*2.62,2.24,.04),Vector3.new(s*3.06,1.0,.06)
  local function frame(t)
   local a,b=bez(P0,P1,P2,P3,math.max(0,t-.01)),bez(P0,P1,P2,P3,math.min(1,t+.01))
   local tan=(b-a).Unit
   local n=Vector3.new(-tan.Y,tan.X,0).Unit;if n.Y<0 then n=-n end
   local h=.8*(1-t)^.85+.05
   return bez(P0,P1,P2,P3,t),tan,n,h,.5-.34*t
  end
  bladeTop[s]=function(t)local c,_,n,h=frame(t);return c+n*h*.5 end
  local N=9
  for i=1,N do
   local t0,t1=(i-1)/N,i/N
   local a,b=bez(P0,P1,P2,P3,t0),bez(P0,P1,P2,P3,t1)
   local _,tan,n,h,d=frame((t0+t1)/2)
   local mid=(a+b)/2
   local L=(b-a).Magnitude+.05
   local base=CFrame.fromMatrix(mid,tan,n)
   part(model,'Blade',Vector3.new(L,h,d),base,i%2==0 and BL[2]or BL[1]:Lerp(BL[2],.5),LI)
   part(model,'BladeEdge',Vector3.new(L,.075,d*.84),base*CFrame.new(0,h*.5+.02,0),BL[5],GL,{Reflectance=.15})
   part(model,'BladeUnder',Vector3.new(L,.09,d*.9),base*CFrame.new(0,-h*.5,0),Color3.fromRGB(100,88,124),SL)
   if h>.2 then part(model,'BladeBelly',Vector3.new(L,h*.34,d+.02),base*CFrame.new(0,-h*.27,0),i%2==0 and BL[4]or BL[3],LI)end
   if h>.16 then
    for side=-1,1,2 do
     if(i+side)%2==0 then
      local w=r(.14,.24)
      part(model,'BladeVoxel',Vector3.new(w,r(.12,h*.55),.05),base*CFrame.new(r(-.1,.1),r(-h*.28,h*.28),side*(d*.5+.012)),pickc({BL[1],BL[3],BL[4],BL[5]}),LI)
     end
    end
   end
  end
  local c,tan,n=frame(1)
  spike(model,'BladeTip',c-tan*.06,tan,n,.32,.13,.13,BL[1],LI)
  tips[s]=c+tan*.26
  for _,t in ipairs({.3,.56,.8})do
   local cc,_,nn,hh=frame(t)
   drip(cc-nn*hh*.5,r(.16,.34),.12)
  end
  for i,t in ipairs({.44,.7})do
   local cc,_,nn,hh=frame(t)
   liveDrop(cc-nn*hh*.5-Vector3.new(0,.05,0),(s>0 and .3 or .75)+i*.37,.12)
  end
 end

 -- TENTACLES: voxel segments, a violet underside, pink suckers, wet highlights ------------------------------
 local function curve(pts,n)
  local dense={}
  for i=1,#pts-1 do
   local p0,p1,p2,p3=pts[math.max(1,i-1)],pts[i],pts[i+1],pts[math.min(#pts,i+2)]
   for k=0,9 do
    local t=k/10;local t2,t3=t*t,t*t*t
    table.insert(dense,(p1*2+(p2-p0)*t+(p0*2-p1*5+p2*4-p3)*t2+(p1*3-p0-p2*3+p3)*t3)*.5)
   end
  end
  table.insert(dense,pts[#pts])
  local acc={0}
  for i=2,#dense do acc[i]=acc[i-1]+(dense[i]-dense[i-1]).Magnitude end
  local out,j={},1
  for s=0,n do
   local want=acc[#acc]*s/n
   while j<#dense-1 and acc[j+1]<want do j+=1 end
   local f=(want-acc[j])/math.max(1e-6,acc[j+1]-acc[j])
   table.insert(out,dense[j]:Lerp(dense[j+1],math.clamp(f,0,1)))
  end
  return out
 end
 -- o: n, r0, r1, side(k,pos,tan) -> sucker side or nil, every, under, kinds, joint / jointAt(pos), amp, axis, phase
 local function arm(name,pts,o)
  local path=curve(pts,o.n)
  local every=o.every or 2
  for i,pos in ipairs(path)do
   local k=(i-1)/math.max(1,#path-1)
   local tan=(path[math.min(#path,i+1)]-path[math.max(1,i-1)]).Unit
   local rad=o.r0+(o.r1-o.r0)*k
   local s=rad*2
   local cf=CFrame.new(pos)*alignY(tan)*CFrame.Angles(0,r(-.3,.3),0)
   local list={}
   local col=(i%4==0)and blue3 or((i%3==0)and blue2 or blue)
   if o.bands and i%o.bands==0 then col=(i%2==0)and violet or violet2 end
   table.insert(list,part(model,name,Vector3.new(s,s*1.05,s),cf,col,GL,{Reflectance=.08}))
   local sn=o.side and o.side(k,pos,tan)
   if sn then
    sn-=tan*sn:Dot(tan)
    if sn.Magnitude>.01 then
     sn=sn.Unit
     if o.under~=false and rad>.09 then
      table.insert(list,part(model,name..'Under',Vector3.new(s*.9,s*1.02,s*.9),cf+sn*s*.26,(i%2==0)and violet or violet2,GL,{Reflectance=.06}))
     end
     if(i-1)%every==0 and rad>.06 then
      local sp=pos+sn*s*.58
      local scf=CFrame.fromMatrix(sp,sn,tan)
      local d=s*.96
      table.insert(list,part(model,'Sucker',Vector3.new(.07,d,d),scf,pink,SP,{Reflectance=.05,Shape=Enum.PartType.Cylinder}))
      if rad>.165 then table.insert(list,part(model,'SuckerIn',Vector3.new(.075,d*.62,d*.62),scf*CFrame.new(.01,0,0),pink2,SP,{Shape=Enum.PartType.Cylinder}))end
      table.insert(list,part(model,'SuckerHole',Vector3.new(.08,d*.34,d*.34),scf*CFrame.new(.02,0,0),hole,SP,{Shape=Enum.PartType.Cylinder}))
     end
     if i%4==0 and rad>.11 then
      table.insert(list,part(model,'TentacleShine',Vector3.new(s*.34,s*.34,s*.2),cf-sn*s*.48,shine,GL,{Reflectance=.25,CastShadow=false}))
     end
    end
   end
   if o.kinds then
    for _,p in ipairs(list)do
     tag(p,o.kinds,o.jointAt and o.jointAt(pos)or o.joint or pts[1],(o.amp or 1)*k,o.axis,o.phase)
    end
   end
  end
  return path
 end
 local function toward(c,front)return function(_,pos)return(c-pos).Unit+(front or Vector3.zero)end end

 -- the long one hanging down the right, curling in at the end (the cursed pearl grows in its curl)
 local rootR=Vector3.new(.55,1.98,.28)
 local hang=arm('Tentacle',{rootR,Vector3.new(1.02,1.62,.44),Vector3.new(1.34,1.0,.52),Vector3.new(1.3,.42,.52),
  Vector3.new(1.06,.16,.5),Vector3.new(.84,.3,.48),Vector3.new(.88,.56,.46)},
  {n=14,r0=.23,r1=.08,side=toward(Vector3.new(.98,.62,.46),Vector3.new(0,0,.8)),kinds='OctoMantle,OctoArm',joint=rootR,amp=1,axis=Vector3.zAxis,phase=.3})
 local curl=hang[#hang]
 tag(ball(model,'OctoPearl',.05,CFrame.new(curl+Vector3.new(.13,-.05,.13)),Color3.fromRGB(250,232,246),SP,{Reflectance=.45,Transparency=1,CastShadow=false}),
  'OctoMantle,OctoArm',rootR,.95,Vector3.zAxis,.3)
 liveDrop(hang[11]-Vector3.new(0,.14,0),.55,.13,'OctoMantle,OctoArm',rootR,.75,Vector3.zAxis)
 -- the curl on the left
 local rootL=Vector3.new(-.48,1.96,.3)
 local left=arm('Tentacle',{rootL,Vector3.new(-.86,1.64,.46),Vector3.new(-1.06,1.2,.52),Vector3.new(-.94,.96,.54),
  Vector3.new(-.72,1.04,.52),Vector3.new(-.7,1.26,.5)},
  {n=11,r0=.19,r1=.07,side=toward(Vector3.new(-.86,1.2,.5),Vector3.new(0,0,.8)),kinds='OctoMantle,OctoArm',joint=rootL,amp=1,axis=-Vector3.zAxis,phase=1.4})
 liveDrop(left[7]-Vector3.new(0,.12,0),.2,.12,'OctoMantle,OctoArm',rootL,.6,-Vector3.zAxis)
 -- two behind
 local rootB=Vector3.new(-.22,1.95,-.42)
 local back=arm('Tentacle',{rootB,Vector3.new(-.4,1.5,-.62),Vector3.new(-.36,1.0,-.66),Vector3.new(-.14,.78,-.6),Vector3.new(-.02,.96,-.54)},
  {n=10,r0=.18,r1=.07,side=toward(Vector3.new(-.2,1.1,-.4),Vector3.new(0,0,-.8)),kinds='OctoMantle,OctoArm',joint=rootB,amp=1,axis=Vector3.xAxis,phase=2.3})
 drip(back[6]-Vector3.new(0,.12,0),.2,.11)
 local rootB2=Vector3.new(.46,1.98,-.36)
 arm('Tentacle',{rootB2,Vector3.new(.86,1.7,-.5),Vector3.new(1.02,1.3,-.5),Vector3.new(.9,1.06,-.44),Vector3.new(.74,1.14,-.4)},
  {n=7,r0=.16,r1=.07,side=toward(Vector3.new(.8,1.3,-.35),Vector3.new(0,0,-.6)),kinds='OctoMantle,OctoArm',joint=rootB2,amp=.8,axis=Vector3.new(.6,0,.8),phase=3.1})
 -- one along the root of each blade, its tip curling down over the front edge
 for _,s in ipairs({-1,1})do
  local top=bladeTop[s]
  local b,c=top(.14),top(.27)
  local root=Vector3.new(s*.52,2.28,.16)
  local pts={root,Vector3.new(b.X,b.Y+.14,.18),Vector3.new(c.X,c.Y+.12,.22),Vector3.new(c.X+s*.22,c.Y-.06,.36),Vector3.new(c.X+s*.08,c.Y-.3,.42)}
  local path=arm('Tentacle',pts,{n=9,r0=.17,r1=.07,side=function()return Vector3.new(0,.35,1)end,kinds='OctoMantle,OctoArm',joint=root,amp=.4,
   axis=Vector3.new(0,0,s),phase=s>0 and .9 or 2})
  drip(path[#path]-Vector3.new(0,.1,0),.16,.1)
 end
 -- one up each side of the eye, suckers to the front
 local rootFL=Vector3.new(-.5,2.24,.7)
 arm('Tentacle',{rootFL,Vector3.new(-.84,2.62,.62),Vector3.new(-.9,3.12,.5),Vector3.new(-.72,3.48,.46),Vector3.new(-.52,3.54,.52)},
  {n=9,r0=.17,r1=.08,under=false,side=function()return Vector3.new(.35,0,1)end,kinds='OctoMantle,OctoArm',joint=rootFL,amp=.25,axis=-Vector3.zAxis,phase=.6})
 local rootFR=Vector3.new(.58,2.3,.68)
 arm('Tentacle',{rootFR,Vector3.new(.88,2.68,.6),Vector3.new(.88,3.06,.52),Vector3.new(.72,3.24,.56)},
  {n=7,r0=.16,r1=.08,under=false,side=function()return Vector3.new(-.35,0,1)end,kinds='OctoMantle,OctoArm',joint=rootFR,amp=.25,axis=Vector3.zAxis,phase=1.7})
 -- two little curls on top of the head
 local rootT=Vector3.new(.3,3.78,.02)
 arm('Tentacle',{rootT,Vector3.new(.46,4.04,.12),Vector3.new(.66,4.06,.32),Vector3.new(.64,3.9,.46)},
  {n=6,r0=.14,r1=.06,side=toward(Vector3.new(.5,3.9,.3)),kinds='OctoMantle,OctoArm',joint=rootT,amp=.6,axis=Vector3.zAxis,phase=2.6})
 local rootT2=Vector3.new(-.18,3.66,-.52)
 arm('Tentacle',{rootT2,Vector3.new(-.26,3.9,-.72),Vector3.new(-.36,3.84,-.96),Vector3.new(-.4,3.62,-1.02)},
  {n=5,r0=.13,r1=.06,side=toward(Vector3.new(-.3,3.7,-.8)),kinds='OctoMantle,OctoArm',joint=rootT2,amp=.6,axis=-Vector3.zAxis,phase=.4})

 -- INK SAC: a glossy, slightly transparent black-violet bulb on the back, dark ink inside ---------------------
 local SC=Vector3.new(.08,2.16,-.8)
 local function sac(p)return anim(p,'OctoMantle,OctoSac',0,SC)end
 sac(ball(model,'InkSac',.66,CFrame.new(SC),Color3.fromRGB(46,22,74),GL,{Transparency=.2,Reflectance=.3}))
 sac(ball(model,'InkCore',.48,CFrame.new(SC+Vector3.new(0,-.02,.02)),Color3.fromRGB(18,8,28),SP))
 sac(ball(model,'InkGleam',.2,CFrame.new(SC+Vector3.new(.1,.06,-.18)),Color3.fromRGB(118,58,196),NE,{CastShadow=false,Transparency=.2}))
 sac(part(model,'InkGlint',Vector3.new(.08,.08,.04),CFrame.new(SC+Vector3.new(-.12,.2,-.27))*CFrame.Angles(.5,.3,0),Color3.new(1,1,1),NE,{CastShadow=false}))
 for i=-1,1 do -- the strap of flesh that holds it
  sac(part(model,'InkStrap',Vector3.new(.2,.2,.22),CFrame.new(SC+Vector3.new(i*.2,.3-math.abs(i)*.06,-.04+math.abs(i)*.05))*CFrame.Angles(0,0,i*.4),i==0 and blue or blue2,GL,{Reflectance=.08}))
 end

 -- SHAFT: brown voxel planks, wet slime streaks ------------------------------------------------------------
 local sTop,sBot=1.95,-2.5
 local WOODS={wood,wood:Lerp(Color3.new(0,0,0),.18),wood:Lerp(Color3.fromRGB(190,140,90),.25)}
 local FACES={{Vector3.zAxis,Vector3.xAxis},{Vector3.xAxis,-Vector3.zAxis},{-Vector3.zAxis,-Vector3.xAxis},{-Vector3.xAxis,Vector3.zAxis}}
 local rowH=.5
 for row=0,math.floor((sTop-sBot)/rowH)-1 do
  local y=sTop-(row+.5)*rowH
  for f,fc in ipairs(FACES)do
   local n,side=fc[1],fc[2]
   part(model,'ShaftPlank',Vector3.new(.3,rowH-.03,.05),CFrame.fromMatrix(Vector3.new(0,y,0)+n*.17,side,Vector3.yAxis,n)*CFrame.new(r(-.02,.02),0,0),WOODS[(row+f)%3+1],WO)
  end
 end
 part(model,'ShaftEnd',Vector3.new(.38,.14,.38),CFrame.new(0,sBot-.02,0),WOODS[2],WO)
 for _,g in ipairs({{.07,.95,.2,1.1},{-.2,-.2,.06,.9},{.04,-1.05,-.2,.8},{.2,.2,-.05,.7}})do
  local p=Vector3.new(g[1],g[2],g[3])
  local n=Vector3.new(g[1],0,g[3]).Unit
  part(model,'ShaftSlime',Vector3.new(.09,g[4],.035),CFrame.lookAt(p,p+n),DRIP,GL,{Transparency=.35,Reflectance=.25,CastShadow=false})
 end

 -- the two tentacles spiralling down the shaft, the coil round the bottom, its tip curling out ----------------
 local function spiral(y0,y1,turns,a0,rad)
  local pts={}
  for i=0,24 do
   local t=i/24
   local a=a0+turns*math.pi*2*t
   table.insert(pts,Vector3.new(math.cos(a)*rad,y0+(y1-y0)*t,math.sin(a)*rad))
  end
  return pts
 end
 local function outward(_,pos)return Vector3.new(pos.X,0,pos.Z)end
 local function onAxis(pos)return Vector3.new(0,pos.Y,0)end
 local wrapA=spiral(1.9,-2.18,3.15,math.pi*.3,.33)
 arm('Wrap',wrapA,{n=26,r0=.19,r1=.13,bands=3,side=outward,every=3,under=false,kinds='OctoWrap',jointAt=onAxis,amp=1,phase=0})
 arm('Wrap',spiral(1.72,-1.28,2.15,math.pi*1.3,.34),{n=18,r0=.18,r1=.12,bands=3,side=outward,every=3,under=false,kinds='OctoWrap',jointAt=onAxis,amp=1,phase=1.6})
 local endA=wrapA[#wrapA]
 local a0=math.atan2(endA.Z,endA.X)
 local coilPts={endA}
 for i=1,6 do
  local a=a0+i/6*math.pi*1.7
  table.insert(coilPts,Vector3.new(math.cos(a)*.4,-2.24-i*.05,math.sin(a)*.4))
 end
 local last=coilPts[#coilPts]
 local outDir=Vector3.new(last.X,0,last.Z).Unit
 table.insert(coilPts,last+outDir*.32+Vector3.new(0,-.08,0))
 table.insert(coilPts,last+outDir*.56+Vector3.new(0,.12,0))
 table.insert(coilPts,last+outDir*.5+Vector3.new(0,.34,0))
 local coil=arm('Coil',coilPts,{n=13,r0=.15,r1=.06,side=function(k,pos)return k<.6 and Vector3.new(pos.X,-.6,pos.Z)or-outDir end,every=2,
  kinds='OctoCoil',joint=Vector3.new(0,-2.4,0),amp=1,axis=Vector3.new(-outDir.Z,0,outDir.X),phase=.8})
 liveDrop(coil[6]-Vector3.new(0,.14,0),.85,.12,'OctoCoil',Vector3.new(0,-2.4,0),.4,Vector3.new(-outDir.Z,0,outDir.X))

 -- GLOW and IDLE FX: a warm light in the eye, seawater dripping off the head -----------------------------------
 local glow=part(model,'OctoGlow',Vector3.new(.3,.3,.3),E*CFrame.new(0,0,.9),gold,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='OctoLight';light.Color=Color3.fromRGB(255,200,96);light.Range=5.5;light.Brightness=.5;light.Shadows=false;light.Parent=glow
 local under=part(model,'OctoDrips',Vector3.new(3.4,.1,.8),CFrame.new(0,1.62,0),DRIP,SP,{Transparency=1,CastShadow=false})
 local pe=Instance.new('ParticleEmitter');pe.Name='OctoDripFX';pe.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pe.Rate=1.4;pe.Lifetime=NumberRange.new(.7,1.1);pe.Speed=NumberRange.new(0,.2);pe.Acceleration=Vector3.new(0,-14,0)
 pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(1,.07)});pe.LightEmission=.5
 pe.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(.8,.2),NumberSequenceKeypoint.new(1,1)})
 pe.Color=ColorSequence.new(DRIP2,DRIP);pe.SpreadAngle=Vector2.new(5,5);pe.EmissionDirection=Enum.NormalId.Bottom;pe.Parent=under
 -- On the back: higher and further out, so the fat head clears the character's own head.
 model:SetAttribute('BackC0',CFrame.new(.35,.15,.3))
 return tips[-1],tips[1]
end

-- Hand of Fate ("Кирка Рука Судьбы" concept sheet, LEGENDARY: "a giant living palm with long fingers and a cursed eye in
-- the centre; the fingers are the pickaxe's teeth"): a voxel hand of pale pink flesh (the sheet's ПАЛИТРА: pale pink, dark
-- mauve-grey, cursed purple, bone cream) speckled with dark mauve voxels and creeping purple stains. HEAD: a thick rounded
-- PALM (stepped voxel layers, lumpy surface voxels) with ONE CURSED EYE in its centre: an almond of glowing purple pixel
-- tiles (bright pink-violet core, purple, deep violet rim) with a tall black slit pupil and a notch, glints, a dark purple lid
-- ring, a raised ring of flesh round it and two dark lids that close over it to blink. Five long jointed FINGERS fan out of
-- the palm (the thumb up and out to the left, three up, the little finger out to the right), each of voxel segments with dark
-- knuckle bands, curling forward like a grabbing hand and ending in a big hooked black voxel CLAW with a purple glow under
-- its point; a cream BONE SPIKE juts out of the lower right of the palm under the little finger (the hero render); on the
-- back of the hand dark tendons fan from the wrist to the fingers with cross stitches (the sheet's BACK view); glowing purple
-- SLIME DRIPS hang under the palm, the fingers and the claws, some stretch and fall. SHAFT: a voxel forearm bone of the same
-- flesh, a big bolted iron CUFF at the wrist with a short chain and a dark iron TAG with a glowing purple hourglass rune on
-- both faces (the sheet's detail close-up), iron bands, crossed leather straps, a dark chain wound twice round it, and a
-- bolted iron POMMEL over a ring of glowing purple voxels and a dark cap with a red-orange ember at the very end (the BOTTOM
-- view).
-- Materials: SmoothPlastic (flesh voxels), Slate (dark mauve flesh, the claws' horn), Neon only for the eye, the rune, the
-- stains' inner glow, the claw glow and the pommel ring, Glass (glossy slime), CorrodedMetal / Metal (the cuff, bands, chain,
-- tag, bolts), Leather (the straps).
-- Moving parts (MiningClient.PickFX "Fate*" motions): every head part breathes with the palm (FatePalm, a translation so it
-- stacks with any joint); every finger flexes slowly in a creeping wave, flails while running, SQUEEZES on a strike, spreads
-- open on the draw and closes into a fist one finger after another in the inspect (FateFinger, PickAmp = share along it,
-- PickPop = the axis it curls round); the eye looks round, glares at the camera and bulges (FateEye); the lids blink
-- (FateLid, PickAmp = their travel); the tag swings on its chain (FateTag); live drips stretch and fall (GummyDrop + PickGoo).
DESIGNS.Fate=function(model,v,def,len,top)
 local SP,SL,NE,GL=Enum.Material.SmoothPlastic,Enum.Material.Slate,Enum.Material.Neon,Enum.Material.Glass
 local ME,CM=Enum.Material.Metal,material('CorrodedMetal',Enum.Material.Metal)
 local LE=material('Leather',Enum.Material.Fabric)
 local skin=rgb(v.Head,{215,181,186})             -- palette 1: pale flesh pink
 local mauve=rgb(v.Trim,{78,64,72})               -- palette 2: dark mauve-grey
 local purple=rgb(v.Accent,{155,47,214})          -- palette 3: cursed purple
 local cream=rgb(v.Bone,{242,223,191})            -- palette 4: bone cream
 local iron=rgb(v.Iron,{54,48,58})
 local iron2=iron:Lerp(Color3.fromRGB(140,130,146),.18)
 local bolt=Color3.fromRGB(122,114,128)
 local claw=Color3.fromRGB(40,36,44)
 local claw2=Color3.fromRGB(62,56,68)
 local clawHi=Color3.fromRGB(98,90,106)
 local slime=Color3.fromRGB(176,64,236)
 local slime2=Color3.fromRGB(214,130,255)
 local FLESH={skin,skin:Lerp(Color3.new(1,1,1),.14),skin:Lerp(Color3.new(0,0,0),.07),Color3.fromRGB(226,198,198),Color3.fromRGB(198,162,172)}
 local DARK={Color3.fromRGB(150,120,134),Color3.fromRGB(118,94,110),mauve:Lerp(Color3.fromRGB(150,120,134),.3)}
 local STAIN={purple,purple:Lerp(Color3.new(0,0,0),.22),purple:Lerp(Color3.new(1,1,1),.22),Color3.fromRGB(128,62,150)}
 local rng=Random.new(1212)
 local function r(a,b)return a+(b-a)*rng:NextNumber()end
 local function pickc(list)return list[rng:NextInteger(1,#list)]end
 -- a flesh voxel colour: mostly pale pink, dark mauve specks, purple stains (more where stain is high)
 local function fleshC(stain)
  local x=rng:NextNumber()
  if x<(stain or .12)then return pickc(STAIN),SP end
  if x<(stain or .12)+.22 then return pickc(DARK),SL end
  return pickc(FLESH),SP
 end
 local small={CastShadow=false}
 local function tag(p,kinds,joint,amp,axis,phase)
  anim(p,kinds,phase or 0,joint)
  if amp then p:SetAttribute('PickAmp',amp)end
  if axis then p:SetAttribute('PickPop',axis)end
  return p
 end
 model.PrimaryPart.Transparency=1                 -- the thin Handle hides inside the bone shaft

 -- PALM: a thick rounded voxel palm --------------------------------------------------------------------------
 local PC=Vector3.new(0,2.0,0)                    -- palm centre
 local RX,RY,RZ=.86,.78,.36
 local function head(p)return anim(p,'FatePalm',0,PC)end
 local LH=.19
 for i=0,math.floor(RY*2/LH)-1 do
  local y=PC.Y-RY+(i+.5)*LH
  local q=math.abs((y-PC.Y)/RY)
  local f=(1-q^2.6)^(1/2.6)                        -- a squarish palm, rounded off
  local w,d=RX*f,RZ*math.max(.62,f)
  if w>.12 then
   local c=FLESH[1+i%3]
   head(part(model,'Palm',Vector3.new(w*2,LH+.01,d*1.62),CFrame.new(PC.X,y,PC.Z),c,SP))
   head(part(model,'Palm',Vector3.new(w*1.7,LH+.01,d*2),CFrame.new(PC.X,y,PC.Z),c,SP))
  end
 end
 local function palmSurface(dir,k)
  local q=math.abs(dir.Y)
  local f=(1-q^2.6)^(1/2.6)
  local h=math.sqrt(math.max(0,1-dir.Y*dir.Y))
  local sx,sz=h>1e-3 and dir.X/h or 0,h>1e-3 and dir.Z/h or 0
  return Vector3.new(PC.X+sx*RX*f*k,PC.Y+dir.Y*RY*k,PC.Z+sz*RZ*math.max(.62,f)*k)
 end
 local EYE_W,EYE_H=.56,.34                         -- the almond's half width / half height
 local E=CFrame.new(0,2.06,.2)                     -- eye centre (looks along +Z)
 local NV=118
 for k=0,NV-1 do
  local yy=1-(k+.5)/NV*2
  local rr=math.sqrt(1-yy*yy)
  local th=k*2.39996
  local dir=Vector3.new(math.cos(th)*rr,yy,math.sin(th)*rr)
  local pos=palmSurface(dir,.93)
  local eyeZone=dir.Z>.2 and math.abs(pos.X-E.X)<EYE_W+.34 and math.abs(pos.Y-E.Y)<EYE_H+.3
  local wrist=yy<-.78 and math.abs(dir.X)<.5
  if not eyeZone and not wrist then
   local s=r(.19,.29)
   local nrm=(pos-PC)*Vector3.new(1/RX^2,1/RY^2,1/RZ^2)
   nrm=nrm.Magnitude>1e-3 and nrm.Unit or Vector3.yAxis
   local edge=1-math.abs(dir.Z)                      -- stains creep in from the rim
   local col,mat=fleshC(.06+edge*.16)
   local cf=math.abs(nrm.Y)>.97 and CFrame.new(pos)or CFrame.lookAt(pos,pos+nrm)
   head(part(model,'PalmVoxel',Vector3.new(s,s*r(.8,1.1),s*r(.8,1.05)),cf*CFrame.Angles(0,0,r(-.25,.25)),col,mat))
  end
 end
 -- a few stains glow from inside (the sheet's purple patches)
 for _,g in ipairs({{-.78,.38,.16},{.8,-.32,.12},{-.5,-.62,.2},{.62,.5,.1},{.2,-.72,.18}})do
  local dir=Vector3.new(g[1],g[2],g[3]).Unit
  local pos=palmSurface(dir,1.0)
  local p=head(part(model,'PalmStain',Vector3.new(.17,.17,.06),CFrame.lookAt(pos,pos+(pos-PC).Unit),purple:Lerp(Color3.new(1,1,1),.1),NE,small))
  p:SetAttribute('PickPulse',true)
 end

 -- BACK OF THE HAND: dark tendons from the wrist to every finger, cross stitches between them ------------------
 local function backAt(x,y)
  local q=math.clamp(1-(x/RX)^2-((y-PC.Y)/RY)^2,0,1)
  return Vector3.new(x,y,PC.Z-RZ*math.max(.62,math.sqrt(q))-.05)
 end
 local tendonC=Color3.fromRGB(96,72,88)
 local roots={}
 for _,f in ipairs({{-.66,1.84},{-.44,2.56},{-.08,2.7},{.34,2.62},{.68,2.24}})do
  local a=backAt(0,1.38);table.insert(roots,f)
  local prev=a
  for i=1,3 do
   local q=backAt(f[1]*i/3,1.38+(f[2]-1.38)*i/3)
   head(bar(model,'Tendon',prev,q,.07,.05,tendonC,SL,small))
   prev=q
  end
 end
 for i=1,#roots-1 do -- the web of cross stitches
  for _,k in ipairs({.45,.75})do
   local a=backAt(roots[i][1]*k,1.38+(roots[i][2]-1.38)*k)
   local b=backAt(roots[i+1][1]*k,1.38+(roots[i+1][2]-1.38)*k)
   head(bar(model,'Tendon',a,b,.05,.04,tendonC:Lerp(Color3.new(0,0,0),.15),SL,small))
  end
 end

 -- THE CURSED EYE: an almond of glowing purple pixels, a black slit pupil, a dark lid ring ---------------------
 local function halfH(x)local u=math.clamp(math.abs(x)/EYE_W,0,1);return EYE_H*(1-u^2)^.82 end
 local function eyeParts(p)return anim(p,'FatePalm,FateEye',0,E.Position)end
 head(part(model,'EyeCore',Vector3.new(EYE_W*2.3,EYE_H*2.5,.12),E*CFrame.new(0,0,.06),Color3.fromRGB(34,10,46),SP))
 -- the dark purple lid ring along the almond, then a raised ring of flesh round it
 local RING=22
 for i=0,RING-1 do
  local a=i/RING*math.pi*2
  local x=math.cos(a)*EYE_W*1.06
  local y=(math.sin(a)>=0 and 1 or -1)*(halfH(x)+.05)
  local nx,ny=math.cos(a)*.08,math.sin(a)*.09
  local c=(i%3==0)and Color3.fromRGB(70,26,92)or((i%3==1)and Color3.fromRGB(104,44,128)or Color3.fromRGB(86,58,98))
  head(part(model,'EyeRim',Vector3.new(.15,.15,.16),E*CFrame.new(x+nx,y+ny,.17)*CFrame.Angles(0,0,a),c,SL))
 end
 local FR=20
 for i=0,FR-1 do
  local a=(i+.5)/FR*math.pi*2
  local x=math.cos(a)*(EYE_W+.22)
  local y=(math.sin(a)>=0 and 1 or -1)*(halfH(math.cos(a)*EYE_W)+.2)+math.sin(a)*.06
  local col,mat=fleshC(.18)
  local s=r(.2,.26)
  head(part(model,'EyeFlesh',Vector3.new(s,s,s*1.1),E*CFrame.new(x,y,.14)*CFrame.Angles(r(-.2,.2),r(-.2,.2),a+r(-.3,.3)),col,mat))
 end
 -- iris pixels on a shallow dome: bright pink-violet core, purple, deep violet edge
 local TS=.09
 for gx=-6,6 do
  for gy=-4,4 do
   local x,y=gx*TS,gy*TS
   local hh=halfH(x)
   if math.abs(y)<=hh*.98 then
    local q=math.sqrt((x/EYE_W)^2+(y/math.max(.05,EYE_H))^2)
    local col,mat
    if q<.42 then col,mat=Color3.fromRGB(240,172,255),NE
    elseif q<.68 then col,mat=Color3.fromRGB(206,96,250),NE
    elseif q<.86 then col,mat=Color3.fromRGB(160,52,222),NE
    else col,mat=Color3.fromRGB(104,26,150),SP end
    local z=.21+.07*(1-math.min(1,q*q))
    eyeParts(part(model,'Iris',Vector3.new(TS+.012,TS+.012,.05),E*CFrame.new(x,y,z),col,mat,small))
   end
  end
 end
 for _,s in ipairs({{.25,.035},{.17,.06},{.08,.08},{0,.09},{-.08,.08},{-.17,.06},{-.25,.035}})do
  eyeParts(part(model,'Pupil',Vector3.new(s[2],.095,.04),E*CFrame.new(0,s[1],.3),Color3.fromRGB(16,6,22),SP,small))
 end
 eyeParts(part(model,'PupilNotch',Vector3.new(.16,.05,.04),E*CFrame.new(-.03,.03,.3),Color3.fromRGB(16,6,22),SP,small))
 eyeParts(part(model,'PupilNotch',Vector3.new(.1,.04,.04),E*CFrame.new(.02,.19,.3),Color3.fromRGB(16,6,22),SP,small))
 eyeParts(part(model,'EyeGlint',Vector3.new(.07,.07,.03),E*CFrame.new(-.2,.12,.31),Color3.new(1,1,1),NE,small))
 eyeParts(part(model,'EyeGlint',Vector3.new(.04,.04,.03),E*CFrame.new(-.12,.18,.31),Color3.fromRGB(255,230,255),NE,small))
 -- the lids: open they hide behind the rim and the flesh ring; FateLid slides them down / up and forward over the eye (PickAmp = travel)
 local lidC={Color3.fromRGB(150,112,140),Color3.fromRGB(128,92,122),Color3.fromRGB(170,130,156)}
 for _,side in ipairs({1,-1})do
  for i=-2,2 do
   local x=i*EYE_W*.4
   local hh=halfH(x)+.06
   local p=part(model,side>0 and'LidTop'or'LidLow',Vector3.new(EYE_W*.42,hh,.08),E*CFrame.new(x,side*(hh*.5+halfH(x)*.98),.12),lidC[(i+3)%3+1],SL,small)
   tag(head(p),'FatePalm,FateLid',E.Position,side*(halfH(x)*1.02+.03))
  end
 end

 -- FINGERS: voxel segments with knuckle bands, curling forward, hooked black claws ---------------------------
 local function curve(pts,n)
  local dense={}
  for i=1,#pts-1 do
   local p0,p1,p2,p3=pts[math.max(1,i-1)],pts[i],pts[i+1],pts[math.min(#pts,i+2)]
   for k=0,9 do
    local t=k/10;local t2,t3=t*t,t*t*t
    table.insert(dense,(p1*2+(p2-p0)*t+(p0*2-p1*5+p2*4-p3)*t2+(p1*3-p0-p2*3+p3)*t3)*.5)
   end
  end
  table.insert(dense,pts[#pts])
  local acc={0}
  for i=2,#dense do acc[i]=acc[i-1]+(dense[i]-dense[i-1]).Magnitude end
  local out,j={},1
  for s=0,n do
   local want=acc[#acc]*s/n
   while j<#dense-1 and acc[j+1]<want do j+=1 end
   local f=(want-acc[j])/math.max(1e-6,acc[j+1]-acc[j])
   table.insert(out,dense[j]:Lerp(dense[j+1],math.clamp(f,0,1)))
  end
  return out
 end
 local FINGERS={ -- control points (front view, fanned out like a star, curling forward), base / tip radius, the way its claw hooks
  {Name='Thumb',P={Vector3.new(-.72,1.74,.08),Vector3.new(-1.2,1.95,.1),Vector3.new(-1.62,2.3,.2),Vector3.new(-1.84,2.78,.38),Vector3.new(-1.74,3.14,.62)},
   R0=.27,R1=.19,Hook=Vector3.new(.62,-.32,.7),Phase=0},
  {Name='Index',P={Vector3.new(-.5,2.6,.04),Vector3.new(-.84,3.1,.08),Vector3.new(-1.1,3.62,.2),Vector3.new(-1.14,4.08,.42),Vector3.new(-.96,4.32,.7)},
   R0=.25,R1=.18,Hook=Vector3.new(.3,-.62,.7),Phase=.7},
  {Name='Middle',P={Vector3.new(-.06,2.74,.04),Vector3.new(-.06,3.34,.08),Vector3.new(-.02,3.94,.2),Vector3.new(.06,4.42,.44),Vector3.new(.2,4.6,.74)},
   R0=.26,R1=.19,Hook=Vector3.new(0,-.7,.7),Phase=1.4},
  {Name='Ring',P={Vector3.new(.38,2.64,.04),Vector3.new(.74,3.1,.08),Vector3.new(1.06,3.56,.2),Vector3.new(1.2,3.98,.42),Vector3.new(1.1,4.22,.7)},
   R0=.25,R1=.18,Hook=Vector3.new(-.32,-.62,.7),Phase=2.1},
  {Name='Little',P={Vector3.new(.76,2.2,.06),Vector3.new(1.22,2.36,.1),Vector3.new(1.66,2.56,.2),Vector3.new(1.94,2.72,.38),Vector3.new(2.02,2.66,.62)},
   R0=.24,R1=.17,Hook=Vector3.new(-.18,-.8,.5),Phase=2.8},
 }
 local tips={}
 for fi,F in ipairs(FINGERS)do
  local root=F.P[1]
  local flat=Vector3.new(F.P[#F.P].X-root.X,F.P[#F.P].Y-root.Y,0).Unit
  local axis=flat:Cross(Vector3.zAxis)             -- turning round it curls the finger forward (+Z)
  local function fing(p,k)return tag(p,'FatePalm,FateFinger',root,k,axis,F.Phase)end
  local n=12
  local path=curve(F.P,n)
  for i,pos in ipairs(path)do
   local k=(i-1)/n
   local tan=(path[math.min(#path,i+1)]-path[math.max(1,i-1)]).Unit
   local s=(F.R0+(F.R1-F.R0)*k)*2
   local cf=CFrame.new(pos)*alignY(tan)*CFrame.Angles(0,r(-.25,.25),0)
   local col,mat=fleshC(.08+k*.18)
   fing(part(model,F.Name,Vector3.new(s,s*.95,s),cf,col,mat),k)
   -- lumpy voxels on the sides (two per segment, a different side each time)
   for j=1,2 do
    local a=(i*2+j)*1.9+fi
    local off=cf*CFrame.new(math.cos(a)*s*.42,r(-.05,.05),math.sin(a)*s*.42)
    local c2,m2=fleshC(.1+k*.2)
    local ss=s*r(.42,.58)
    fing(part(model,F.Name..'Voxel',Vector3.new(ss,ss,ss),off*CFrame.Angles(0,a,0),c2,m2,ss<.16 and small or nil),k)
   end
   if i==5 or i==9 then -- the knuckles: a dark band
    fing(part(model,'Knuckle',Vector3.new(s*1.12,s*.32,s*1.12),cf,Color3.fromRGB(104,80,98),SL),k)
   end
  end
  -- THE CLAW: a dark cap over the fingertip, then a hooked horn of shrinking voxels and a sharp point
  local tipPos=path[#path]
  local tan=(path[#path]-path[#path-1]).Unit
  local hook=F.Hook.Unit
  local s1=F.R1*2
  fing(part(model,'ClawCap',Vector3.new(s1*1.18,s1*.62,s1*1.18),CFrame.new(tipPos)*alignY(tan),claw2,SL,{Reflectance=.06}),1)
  local prev=tipPos
  local dir=tan
  local sizes={.35,.3,.25,.19}
  for c=1,#sizes do
   dir=(dir+hook*.55).Unit
   local step=sizes[c]*.82
   local pos=prev+dir*step
   local cs=sizes[c]*(s1/.34)
   fing(part(model,'Claw',Vector3.new(cs,step+.04,cs*.92),CFrame.new((prev+pos)/2)*alignY(dir),c%2==0 and claw or claw2,SL,{Reflectance=.08}),1)
   if c<=2 then fing(part(model,'ClawShine',Vector3.new(cs*.35,step*.7,cs*.2),CFrame.new((prev+pos)/2)*alignY(dir)*CFrame.new(0,0,-cs*.46),clawHi,SL,small),1)end
   prev=pos
  end
  dir=(dir+hook*.55).Unit
  local side=dir:Cross(Vector3.zAxis);if side.Magnitude<.1 then side=Vector3.xAxis end
  for _,p in ipairs(spike(model,'ClawTip',prev-dir*.02,dir,side,.38,.19,.14,claw,SL,{Reflectance=.08}))do fing(p,1)end
  -- the purple glow under the point (the sheet's claw close-up)
  local under=(hook-dir*hook:Dot(dir));under=under.Magnitude>.05 and under.Unit or -Vector3.yAxis
  fing(part(model,'ClawGlow',Vector3.new(.05,.24,.07),CFrame.new(prev+under*.06)*alignY(dir),slime2,NE,small),1)
  tips[fi]=prev+dir*.36
 end

 -- BONE SPIKE out of the lower right of the palm, under the little finger -------------------------------------
 do
  local base=Vector3.new(.66,1.5,.06)
  local dir=Vector3.new(.72,-.66,.1).Unit
  local prev=base
  for i,s in ipairs({.3,.25,.2})do
   local pos=prev+dir*.2
   head(part(model,'BoneSpike',Vector3.new(s,.24,s),CFrame.new((prev+pos)/2)*alignY(dir)*CFrame.Angles(0,i*.4,0),i==2 and cream:Lerp(Color3.new(0,0,0),.08)or cream,SP))
   prev=pos
  end
  for _,p in ipairs(spike(model,'BoneTip',prev-dir*.03,dir,Vector3.new(0,0,1):Cross(dir),.36,.17,.14,cream,SP))do head(p)end
  head(part(model,'BoneRing',Vector3.new(.36,.08,.36),CFrame.new(base+dir*.02)*alignY(dir),Color3.fromRGB(196,168,150),SP))
 end

 -- SLIME: glowing purple drips under the palm, the fingers and the claws, a few live drops ---------------------
 local wet={Transparency=.12,Reflectance=.18,CastShadow=false}
 local function drip(pos,length,d,ride)
  local a=part(model,'Drip',Vector3.new(d*.62,length,d*.62),CFrame.new(pos-Vector3.new(0,length*.5,0)),slime,GL,wet)
  local b=blob(model,'DripDrop',Vector3.new(d,d*1.35,d),CFrame.new(pos-Vector3.new(0,length+d*.3,0)),slime2,NE,small)
  if ride then ride(a);ride(b)end
  return a,b
 end
 local function liveDrop(pos,phase,d,kinds,joint,amp,axis)
  d=d or .13
  for i,k in ipairs({.33,.66,1})do
   local p=i<3 and part(model,'DripNeck',Vector3.new(d*.5,d*1.1,d*.5),CFrame.new(pos-Vector3.new(0,.06*i,0)),slime,GL,wet)
    or blob(model,'DripLive',Vector3.new(d,d*1.3,d),CFrame.new(pos-Vector3.new(0,.18,0)),slime2,NE,small)
   tag(p,(kinds and(kinds..',')or'')..'GummyDrop',joint or pos,amp,axis,phase)
   p:SetAttribute('PickDropK',k)
   if i==3 then p:SetAttribute('PickGoo',true)end
  end
 end
 for _,g in ipairs({{-.56,1.42,.2,.52},{-.22,1.3,.26,.72},{.12,1.28,.27,.4},{.44,1.36,.24,.62},{-.8,1.7,.12,.34},{.3,1.33,-.2,.3},{-.36,1.34,-.18,.36}})do
  drip(Vector3.new(g[1],g[2],g[3]),g[4],.13,head)
 end
 liveDrop(Vector3.new(-.04,1.3,.24),.2,.14,'FatePalm',PC)
 liveDrop(Vector3.new(.56,1.42,.18),.65,.12,'FatePalm',PC)
 drip(E*CFrame.new(-.3,-.36,.3).Position,.14,.09,head)  -- a tear of slime under the eye
 -- under the claws and the fingers
 for fi,F in ipairs(FINGERS)do
  if fi~=3 then
   local root=F.P[1]
   local flat=Vector3.new(F.P[#F.P].X-root.X,F.P[#F.P].Y-root.Y,0).Unit
   local axis=flat:Cross(Vector3.zAxis)
   local function ride(p)tag(p,'FatePalm,FateFinger',root,.85,axis,F.Phase)end
   local q=F.P[3]
   drip(q+Vector3.new(0,-F.R0*.9,.05),fi==1 and .3 or .2,.1,ride)
  end
 end
 do
  local F=FINGERS[5]
  local flat=Vector3.new(F.P[#F.P].X-F.P[1].X,F.P[#F.P].Y-F.P[1].Y,0).Unit
  liveDrop(tips[5]-Vector3.new(0,.06,0),1.1,.12,'FatePalm,FateFinger',F.P[1],1,flat:Cross(Vector3.zAxis))
 end

 -- SHAFT: a voxel forearm bone of the same flesh, flaring into the wrist ------------------------------------
 local sTop,sBot=1.32,-2.2
 local rowH=.2
 local FACES={{Vector3.zAxis,Vector3.xAxis},{Vector3.xAxis,-Vector3.zAxis},{-Vector3.zAxis,-Vector3.xAxis},{-Vector3.xAxis,Vector3.zAxis}}
 local covered={{.66,1.06},{-.36,-.18},{-1.2,-1.02}}  -- under the cuff and the bands
 local function hidden(y)for _,c in ipairs(covered)do if y>c[1]-.02 and y<c[2]+.02 then return true end end;return false end
 for row=0,math.floor((sTop-sBot)/rowH)-1 do
  local y=sTop-(row+.5)*rowH
  local flare=math.clamp((y-.95)/.35,0,1)
  local w=.42+flare*.3
  local col,mat=fleshC(.1)
  part(model,'Bone',Vector3.new(w,rowH+.01,w),CFrame.new(0,y,0)*CFrame.Angles(0,(row%2)*.06,0),col,mat)
  if not hidden(y)then
   for f,fc in ipairs(FACES)do
    local n,side=fc[1],fc[2]
    local c2,m2=fleshC(.14)
    local o=((row+f)%2==0 and .1 or -.1)+r(-.03,.03)
    local ss=r(.17,.22)
    part(model,'BoneVoxel',Vector3.new(ss,rowH*r(.8,1),.08),CFrame.fromMatrix(Vector3.new(0,y,0)+n*(w*.5+.02)+side*o,side,Vector3.yAxis,n),c2,m2,small)
   end
  end
 end

 -- the bolted iron CUFF at the wrist, its chain and the rune TAG ------------------------------------------------
 local cuffY=.86
 part(model,'Cuff',Vector3.new(.74,.4,.74),CFrame.new(0,cuffY,0),iron,CM)
 for _,dy in ipairs({-.2,.2})do part(model,'CuffLip',Vector3.new(.8,.06,.8),CFrame.new(0,cuffY+dy,0),iron2,ME,{Reflectance=.08})end
 for f,fc in ipairs(FACES)do
  local n,side=fc[1],fc[2]
  for _,o in ipairs({-.22,0,.22})do
   part(model,'Bolt',Vector3.new(.09,.09,.06),CFrame.fromMatrix(Vector3.new(0,cuffY,0)+n*.39+side*o,side,Vector3.yAxis,n),bolt,ME,{Reflectance=.15,CastShadow=false})
  end
 end
 local HOOK=Vector3.new(.3,cuffY-.24,.3)
 local function tagPart(p)return tag(p,'FateTag',HOOK,1,nil,.4)end
 part(model,'TagHook',Vector3.new(.06,.12,.12),CFrame.new(HOOK+Vector3.new(0,.04,0)),iron2,ME)
 for i=1,3 do
  local p=part(model,'TagLink',Vector3.new(.06,.16,.1),CFrame.new(HOOK-Vector3.new(0,.1+(i-1)*.13,0))*CFrame.Angles(0,i%2==0 and math.pi/2 or 0,0),iron2,ME,{Reflectance=.1,CastShadow=false})
  tagPart(p)
 end
 local TC=HOOK-Vector3.new(0,.68,0)
 tagPart(part(model,'Tag',Vector3.new(.38,.52,.07),CFrame.new(TC),iron,CM))
 tagPart(part(model,'TagRing',Vector3.new(.1,.08,.1),CFrame.new(TC+Vector3.new(0,.28,0)),iron2,ME))
 for _,f in ipairs({1,-1})do
  tagPart(part(model,'TagPanel',Vector3.new(.3,.44,.02),CFrame.new(TC+Vector3.new(0,0,f*.035)),Color3.fromRGB(28,18,34),SP,small))
  -- the hourglass rune of fate: a stem, a bar on top and at the bottom, the two crossing strokes, the waist
  local z=f*.05
  local glow=Color3.fromRGB(206,96,255)
  local function rune(name,size,cf)local p=part(model,name,size,CFrame.new(TC+Vector3.new(0,0,z))*cf,glow,NE,small);p:SetAttribute('PickPulse',true);tagPart(p)end
  rune('TagRune',Vector3.new(.03,.06,.012),CFrame.new(0,.16,0))
  rune('TagRune',Vector3.new(.18,.03,.012),CFrame.new(0,.12,0))
  rune('TagRune',Vector3.new(.18,.03,.012),CFrame.new(0,-.15,0))
  rune('TagRune',Vector3.new(.03,.29,.012),CFrame.Angles(0,0,math.rad(31)))
  rune('TagRune',Vector3.new(.03,.29,.012),CFrame.Angles(0,0,math.rad(-31)))
  rune('TagRune',Vector3.new(.09,.025,.012),CFrame.new(0,-.01,0))
 end

 -- iron bands and the crossed leather straps -----------------------------------------------------------------
 for _,y in ipairs({-.27,-1.11})do
  part(model,'Band',Vector3.new(.58,.16,.58),CFrame.new(0,y,0),iron,CM)
  for _,n in ipairs({Vector3.zAxis,-Vector3.zAxis,Vector3.xAxis,-Vector3.xAxis})do
   part(model,'Bolt',Vector3.new(.08,.08,.05),CFrame.lookAt(Vector3.new(0,y,0)+n*.3,Vector3.new(0,y,0)+n*2),bolt,ME,{Reflectance=.15,CastShadow=false})
  end
 end
 local strapC=Color3.fromRGB(52,38,44)
 for _,y in ipairs({.3,-.7,-1.62})do
  for _,f in ipairs({1,-1})do
   for _,s in ipairs({1,-1})do
    part(model,'Strap',Vector3.new(.07,.46,.03),CFrame.new(0,y,f*.27)*CFrame.Angles(0,0,s*math.rad(38)),strapC,LE,small)
   end
   part(model,'StrapStud',Vector3.new(.07,.07,.03),CFrame.new(0,y,f*.29),bolt,ME,small)
  end
 end

 -- the dark CHAIN wound twice round the shaft --------------------------------------------------------------
 do
  local y0,y1,turns,rad0=.56,-1.9,2.1,.33
  local N=26
  local prev=nil
  for i=0,N do
   local t=i/N
   local a=math.pi*.15+turns*math.pi*2*t
   local pos=Vector3.new(math.cos(a)*rad0,y0+(y1-y0)*t,math.sin(a)*rad0)
   if prev then
    local mid=(prev+pos)/2
    local dir=(pos-prev).Unit
    local out=Vector3.new(mid.X,0,mid.Z).Unit
    local cf=CFrame.fromMatrix(mid,dir,out)
    part(model,'ChainLink',Vector3.new((pos-prev).Magnitude+.05,i%2==0 and .15 or .07,i%2==0 and .07 or .15),cf,i%2==0 and iron2 or iron,ME,{Reflectance=.12,CastShadow=false})
   end
   prev=pos
  end
 end

 -- POMMEL: a bolted iron block, a ring of glowing purple voxels, a dark cap with a red-orange ember ------------
 local pY=sBot-.18
 part(model,'Pommel',Vector3.new(.66,.36,.66),CFrame.new(0,pY,0),iron,CM)
 part(model,'PommelLip',Vector3.new(.7,.06,.7),CFrame.new(0,pY+.18,0),iron2,ME,{Reflectance=.08})
 for f,fc in ipairs(FACES)do
  local n,side=fc[1],fc[2]
  for _,o in ipairs({-.18,.18})do
   part(model,'Bolt',Vector3.new(.09,.09,.06),CFrame.fromMatrix(Vector3.new(0,pY,0)+n*.35+side*o,side,Vector3.yAxis,n),bolt,ME,{Reflectance=.15,CastShadow=false})
  end
 end
 for i=0,3 do
  local a=i*math.pi/2
  local p=part(model,'PommelGlow',Vector3.new(.2,.14,.52),CFrame.new(0,pY-.25,0)*CFrame.Angles(0,a,0)*CFrame.new(.17,0,0),i%2==0 and purple or purple:Lerp(Color3.new(1,1,1),.2),NE,small)
  p:SetAttribute('PickPulse',true)
 end
 part(model,'PommelCap',Vector3.new(.48,.18,.48),CFrame.new(0,pY-.4,0),Color3.fromRGB(44,34,40),SL)
 part(model,'PommelEmber',Vector3.new(.24,.04,.24),CFrame.new(0,pY-.49,0),Color3.fromRGB(255,96,44),NE,small)

 -- GLOW and IDLE FX: the eye's purple light, purple motes rising off the palm, slime dripping ---------------------
 local glow=part(model,'FateGlow',Vector3.new(.3,.3,.3),E*CFrame.new(0,0,.8),purple,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='FateLight';light.Color=Color3.fromRGB(196,90,255);light.Range=6;light.Brightness=.6;light.Shadows=false;light.Parent=glow
 local motes=Instance.new('ParticleEmitter');motes.Name='FateMotes';motes.Texture='rbxasset://textures/particles/sparkles_main.dds'
 motes.Rate=1.5;motes.Lifetime=NumberRange.new(1,1.8);motes.Speed=NumberRange.new(.2,.6);motes.Acceleration=Vector3.new(0,.8,0)
 motes.SpreadAngle=Vector2.new(180,180);motes.LightEmission=1;motes.Drag=1
 motes.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(.3,.18),NumberSequenceKeypoint.new(1,0)})
 motes.Color=ColorSequence.new(Color3.fromRGB(236,170,255),purple);motes.Parent=glow
 local under=part(model,'FateDrips',Vector3.new(1.4,.1,.5),CFrame.new(0,1.22,.1),slime,SP,{Transparency=1,CastShadow=false})
 local pe=Instance.new('ParticleEmitter');pe.Name='FateDripFX';pe.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pe.Rate=1;pe.Lifetime=NumberRange.new(.6,1);pe.Speed=NumberRange.new(0,.2);pe.Acceleration=Vector3.new(0,-14,0)
 pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.14),NumberSequenceKeypoint.new(1,.06)});pe.LightEmission=.8
 pe.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(.8,.2),NumberSequenceKeypoint.new(1,1)})
 pe.Color=ColorSequence.new(slime2,slime);pe.SpreadAngle=Vector2.new(5,5);pe.EmissionDirection=Enum.NormalId.Bottom;pe.Parent=under
 -- On the back: higher and further out, so the big hand clears the character's own head. In the hand the palm leans
 -- forward, out in front of the holder, so the cursed eye sits in the first-person view (upper right, as on the sheet's
 -- "ПЕРСПЕКТИВА ОТ 1 ЛИЦА") and stays 1.3+ studs clear of the head (checked on the R15 tool hold).
 model:SetAttribute('BackC0',CFrame.new(.3,.1,.32))
 model:SetAttribute('HandTilt',28)
 return tips[1],tips[5]
end

-- Laughsaw ("Кирка Смехопила" concept sheet, LEGENDARY): half pickaxe, half circular saw, with a mad
-- grin. HEAD: a chunky box of lacquered red and charcoal voxel bricks with a bolted red frame and the
-- same face on both sides (the sheet's FRONT and BACK): one big voxel eyeball (red iris, black pupil)
-- under an angry red brow, a red upper-lip band with hex bolts at its ends and a huge curved grin of
-- crooked cream teeth (two rows) in a black mouth; the lower lip and the lower teeth are the jaw that
-- drops open on every hit. Top: dark emblem tiles and a black post with a red cap. Right (+X): a big
-- voxel saw blade through the middle of the head (bone-white outer bricks, grey inner rings, a dark
-- bolted hub, splashes of blood on both faces, 18 hooked teeth, some with bloody tips) behind a red
-- bolted hub housing; it spins all the time. Left (-X): a red shoulder block with an orange warning
-- diamond and a grey bolted bracket arm curling round the top-left corner with a chain hanging off
-- it. Under the head a bolted grey collar: a chain on the left, a chain with a dog tag (grey frame,
-- red pixel skull) on the right. SHAFT: a square charcoal pole in red brick bands, red cloth X wraps,
-- grey bolted bands, a chain wound round it, a grey band with a glowing orange flame badge; POMMEL:
-- a grey bolted clamp, a red block with a yellow warning triangle and a dark cap with an orange
-- glowing core. SmoothPlastic = lacquered bricks / bone teeth, Slate = worn charcoal, Metal = bolts,
-- bands, chains and the blade, Fabric = wraps, Glass = wet blood, Neon = the glow only.
-- Moving parts (MiningClient.PickFX): SawSpin (the blade, its teeth and blood: spins slowly in idle,
-- faster while running, screams round on a hit and in the inspect), SawJaw (the lower lip and teeth:
-- open on a hit, chatter in the inspect "laugh"), SawIris (the iris looks round, darts on a hit),
-- SawChain / SawTag (the chains and the tag swing at their hooks, stream back while running).
-- SawGlow (a red light and the idle embers at the hub) and SawSparks (the blade's edge) are driven by
-- PickFX.
DESIGNS.Saw=function(model,v,def,len,top)
 local SP,SL,MT,FB,NE,GL=Enum.Material.SmoothPlastic,Enum.Material.Slate,Enum.Material.Metal,Enum.Material.Fabric,Enum.Material.Neon,Enum.Material.Glass
 local red,darkRed,char=rgb(v.Head,{226,30,36}),rgb(v.Red2,{150,16,22}),rgb(v.Trim,{36,32,36})
 local grey,steel,bone=rgb(v.Iron,{148,144,146}),rgb(v.Accent,{226,222,216}),rgb(v.Teeth,{240,224,184})
 local blood,ember=rgb(v.Blood,{170,12,18}),rgb(v.Glow,{255,138,36})
 local dgrey=Color3.fromRGB(70,64,66)
 local seed=0
 local function rnd()seed+=1;return(math.sin(seed*12.9898+78.233)*43758.5453)%1 end -- same on every peer
 local function mottle()
  local r=rnd()
  if r<.42 then return red,SP elseif r<.62 then return darkRed,SP elseif r<.86 then return char,SL end
  return dgrey,SL
 end
 local function bolt(cf,d,props)
  cylZ(model,'SawBolt',.07,d,cf,grey,MT,props)
  cylZ(model,'SawBolt',.06,d*.55,cf*CFrame.new(0,0,.04),dgrey,MT,props)
 end
 -- a run of chain links from a to b (alternately flat and edge-on); kind = PickAnim of every link
 local function chain(name,a,b,n,kind,phase,joint,props)
  local list={}
  for i=0,n-1 do
   local p=a:Lerp(b,(i+.5)/n)
   local link=part(model,name,Vector3.new(i%2==0 and .17 or .06,(b-a).Magnitude/n+.05,i%2==0 and .06 or .17),CFrame.new(p)*alignY(b-a),grey:Lerp(dgrey,(i%3)*.2),MT,props)
   if kind then anim(link,kind,phase,joint)end
   table.insert(list,link)
  end
  return list
 end

 -- HEAD ---------------------------------------------------------------------------------------
 local W,HH,D=2.3,2.0,1.1
 local H=top*CFrame.new(0,1.0,0)
 part(model,'SawCore',Vector3.new(W,HH,D),H,char,SL)
 -- the bolted frame round the sides and the top (red bricks of uneven lengths)
 for s=-1,1,2 do
  for i=0,3 do
   local c,m=(i%2==0)and red or darkRed,SP
   part(model,'SawFrame',Vector3.new(.16,.5+(i%2)*.04,D+.08),H*CFrame.new(s*(W*.5+.04),-.75+i*.5,0),c,m)
  end
 end
 for i=0,4 do part(model,'SawFrame',Vector3.new(.47,.16,D+.08),H*CFrame.new(-.94+i*.47,HH*.5+.04,0),(i%2==0)and red or darkRed,SP)end
 for i=0,4 do part(model,'SawFrame',Vector3.new(.47,.14,D+.06),H*CFrame.new(-.94+i*.47,-HH*.5-.03,0),(i%2==1)and red or char,i%2==1 and SP or SL)end

 -- one face (front +Z / back -Z): F at the face plane, its X to the viewer's right
 local function face(F,jawPhase,side)
  -- outer red rim on the face (proud)
  for i=0,5 do
   part(model,'SawRim',Vector3.new(.4,.14,.08),F*CFrame.new(-1.0+i*.4,.93,.04),(i%2==0)and red or darkRed,SP)
  end
  for s=-1,1,2 do for i=0,4 do
   part(model,'SawRim',Vector3.new(.14,.38,.08),F*CFrame.new(s*1.08,.72-i*.4,.04),(i%2==1)and red or darkRed,SP)
  end end
  -- upper panel: mottled bricks round the eye
  local E=Vector3.new(.3,.5,0)
  for row=0,2 do
   for col=0,7 do
    local x=-.86+col*.246+(row%2)*.06;local y=.26+row*.21
    if(Vector3.new(x,y,0)-E).Magnitude>.5 and x<.9 then
     local c,m=mottle()
     part(model,'SawBrick',Vector3.new(.23,.19,.05+rnd()*.05),F*CFrame.new(x,y,.03),c,m)
    end
   end
  end
  -- eye socket, voxel eyeball, iris, pupil, glint
  local eyeCF=F*CFrame.new(E.X,E.Y,.12)
  cylZ(model,'SawSocket',.08,.96,F*CFrame.new(E.X,E.Y,.04),Color3.fromRGB(22,14,16),SL)
  ball(model,'SawEyeball',.8,eyeCF,Color3.fromRGB(246,244,238),SP)
  for i=0,11 do
   local a=i/12*math.pi*2
   part(model,'SawEyePixel',Vector3.new(.15,.15,.16),eyeCF*CFrame.new(math.cos(a)*.35,math.sin(a)*.35,.08)*CFrame.Angles(0,0,a),
    Color3.fromRGB(236,232,226):Lerp(Color3.fromRGB(205,200,196),(i%3)*.3),SP)
  end
  local irisAt=eyeCF*CFrame.new(0,0,.37)
  for _,p in ipairs({cylZ(model,'SawIris',.05,.46,irisAt,darkRed,SP),cylZ(model,'SawIris',.05,.37,irisAt*CFrame.new(0,0,.02),Color3.fromRGB(232,24,30),SP),
   part(model,'SawPupil',Vector3.new(.13,.13,.05),irisAt*CFrame.new(0,0,.045),Color3.fromRGB(12,8,10),SP),
   part(model,'SawGlint',Vector3.new(.05,.05,.03),irisAt*CFrame.new(.07,.08,.06),Color3.new(1,1,1),NE,{CastShadow=false})})do
   anim(p,'SawIris',jawPhase,eyeCF.Position)
  end
  -- angry red brow over the eye
  for i=0,2 do
   part(model,'SawBrow',Vector3.new(.3,.13,.12),F*CFrame.new(E.X-.32+i*.29,E.Y+.47-i*.05,.1)*CFrame.Angles(0,0,math.rad(-10)),(i==1)and darkRed or red,SP)
  end
  -- MOUTH: a black curved grin with crooked teeth; columns follow the smile
  local cols=10;local cw=.19
  for i=0,cols-1 do
   local x=-.855+i*cw;local k=(x/.95)^2
   local yTop=.04+.2*k;local yBot=-.86+.46*k
   part(model,'SawMouth',Vector3.new(cw+.01,yTop-yBot,.06),F*CFrame.new(x,(yTop+yBot)*.5,.01),Color3.fromRGB(18,6,8),SP)
   -- upper lip band (red, proud) and its bolted ends
   part(model,'SawLip',Vector3.new(cw+.01,.16,.12),F*CFrame.new(x,yTop+.08,.06),(i%3==1)and darkRed or red,SP)
   -- upper tooth (hangs from the lip)
   if i~=7 then
    local th=.24+rnd()*.09
    part(model,'SawTooth',Vector3.new(cw-.025,th,.13),F*CFrame.new(x+(rnd()-.5)*.02,yTop-th*.5+.01,.06)*CFrame.Angles(0,0,(rnd()-.5)*.14),
     bone:Lerp(Color3.fromRGB(214,190,140),rnd()*.35),SP)
   else
    part(model,'SawTooth',Vector3.new(cw-.04,.16,.12),F*CFrame.new(x,yTop-.07,.06),bone:Lerp(Color3.fromRGB(200,170,120),.4),SP) -- a broken one
   end
   -- the jaw: lower lip and lower teeth (open on a hit, PickFX SawJaw)
   local lip=part(model,'SawJawLip',Vector3.new(cw+.01,.15,.14),F*CFrame.new(x,yBot-.07,.07),(i%3==2)and darkRed or red,SP)
   anim(lip,'SawJaw',jawPhase,(F*CFrame.new(0,-.2,-.3)).Position);lip:SetAttribute('PickAmp',side)
   local lh=.2+rnd()*.08
   local tooth=part(model,'SawJawTooth',Vector3.new(cw-.03,lh,.12),F*CFrame.new(x+(rnd()-.5)*.02,yBot+lh*.5,.06)*CFrame.Angles(0,0,(rnd()-.5)*.16),
    bone:Lerp(Color3.fromRGB(214,190,140),rnd()*.35),SP)
   anim(tooth,'SawJaw',jawPhase,(F*CFrame.new(0,-.2,-.3)).Position);tooth:SetAttribute('PickAmp',side)
  end
  -- chin bricks under the grin
  for i=0,4 do
   local x=-.76+i*.38;local k=(x/.95)^2
   local c,m=mottle()
   local h=math.max(.08,.46*k+.02);part(model,'SawBrick',Vector3.new(.36,h,.05),F*CFrame.new(x,-.94+h*.5,.02),c,m)
  end
  -- hex bolts: the frame corners and both ends of the upper lip
  for _,p in ipairs({{-1.02,.88},{1.02,.88},{-1.02,-.86},{1.02,-.86},{-.98,.2}})do
   bolt(F*CFrame.new(p[1],p[2],.1),.2)
  end
  -- a few splashes of blood on the bricks
  for i=1,4 do
   local x=-.8+rnd()*1.6;local y=-.95+rnd()*.25
   if i<=2 then y=.25+rnd()*.5;x=-.85+rnd()*.7 end
   part(model,'SawBloodSpot',Vector3.new(.1+rnd()*.1,.07+rnd()*.06,.03),F*CFrame.new(x,y,.1),blood,GL)
  end
 end
 face(H*CFrame.new(0,0,D*.5),0,1)
 face(H*CFrame.Angles(0,math.pi,0)*CFrame.new(0,0,D*.5),1.7,-1)

 -- TOP: emblem tiles, a black post with a red cap
 for i,x in ipairs({-.78,-.18})do
  part(model,'SawTopTile',Vector3.new(.46,.07,.6),H*CFrame.new(x,HH*.5+.15,0),Color3.fromRGB(28,24,28),SL)
  local icon=part(model,'SawTopIcon',Vector3.new(.22,.05,.22),H*CFrame.new(x,HH*.5+.2,0)*CFrame.Angles(0,math.rad(45),0),red,SP)
  part(model,'SawTopIcon',Vector3.new(.08,.06,.08),icon.CFrame*CFrame.new(0,.02,0),Color3.fromRGB(28,24,28),SP)
  for s=-1,1,2 do bolt(H*CFrame.new(x+s*.16,HH*.5+.2,.22)*CFrame.Angles(math.rad(-90),0,0),.1)end
 end
 part(model,'SawPost',Vector3.new(.26,.36,.26),H*CFrame.new(-.48,HH*.5+.3,-.28),char,SL)
 part(model,'SawPostCap',Vector3.new(.32,.12,.32),H*CFrame.new(-.48,HH*.5+.52,-.28),red,SP)

 -- LEFT: shoulder block with a warning diamond, the bracket arm and its hanging chain
 local sh=H*CFrame.new(-W*.5-.2,-.15,0)
 part(model,'SawShoulder',Vector3.new(.34,1.15,D+.14),sh,red,SP)
 for s=-1,1,2 do
  part(model,'SawShoulder',Vector3.new(.36,.12,D+.16),sh*CFrame.new(0,s*.5,0),darkRed,SP)
  part(model,'SawWarn',Vector3.new(.3,.3,.05),sh*CFrame.new(0,.02,s*(D*.5+.09))*CFrame.Angles(0,0,math.rad(45)),Color3.fromRGB(255,150,26),SP)
  part(model,'SawWarnMark',Vector3.new(.05,.13,.02),sh*CFrame.new(0,.05,s*(D*.5+.12)),Color3.fromRGB(30,20,14),SP)
  part(model,'SawWarnMark',Vector3.new(.05,.04,.02),sh*CFrame.new(0,-.07,s*(D*.5+.12)),Color3.fromRGB(30,20,14),SP)
 end
 local arm={Vector3.new(-.85,1.18,0),Vector3.new(-1.45,1.05,0),Vector3.new(-1.78,.55,0),Vector3.new(-1.8,-.05,0),Vector3.new(-1.62,-.5,0)}
 for i=1,#arm-1 do
  local a,b=(H*CFrame.new(arm[i])).Position,(H*CFrame.new(arm[i+1])).Position
  local seg=bar(model,'SawBracket',a,b,.26,.36,i%2==0 and grey or grey:Lerp(dgrey,.25),MT)
  part(model,'SawBracketJoint',Vector3.new(.32,.2,.42),CFrame.new(b)*(seg.CFrame-seg.CFrame.Position),dgrey,MT)
  bolt(CFrame.new((a+b)/2)*(seg.CFrame-seg.CFrame.Position)*CFrame.new(0,0,.19),.13)
  bolt(CFrame.new((a+b)/2)*(seg.CFrame-seg.CFrame.Position)*CFrame.Angles(0,math.pi,0)*CFrame.new(0,0,.19),.13)
 end
 local hookL=(H*CFrame.new(arm[#arm])).Position
 chain('SawChain',hookL,hookL+Vector3.new(.05,-1.55,.05),9,'SawChain',.3,hookL)

 -- RIGHT: the saw blade (spins round the hub, PickFX SawSpin) and the hub housing
 local R=1.28
 local hub=H*CFrame.new(1.0,.22,0)
 local hubPos=hub.Position
 local function spin(p)return anim(p,'SawSpin',0,hubPos)end
 local rings={{R-.13,.26,steel,26},{R-.39,.26,Color3.fromRGB(196,192,190),20},{R-.65,.26,Color3.fromRGB(150,146,146),14},{R-.88,.2,Color3.fromRGB(104,98,100),10}}
 for ri,rg in ipairs(rings)do
  local r,w,c,n=rg[1],rg[2],rg[3],rg[4]
  local seg=2*r*math.tan(math.pi/n)+.03
  for i=0,n-1 do
   local a=(i+(ri%2)*.5)/n*math.pi*2
   local shade=c:Lerp(Color3.fromRGB(120,116,118),((i*7+ri*3)%5)*.06)
   local m=((i+ri)%6==0)and Enum.Material.CorrodedMetal or MT
   spin(part(model,'SawBlade',Vector3.new(w,seg,.12+((i+ri)%3)*.015),hub*CFrame.new(math.cos(a)*r,math.sin(a)*r,0)*CFrame.Angles(0,0,a),shade,m))
  end
 end
 spin(cylZ(model,'SawBladeHub',.16,.5,hub,Color3.fromRGB(46,42,44),MT))
 -- blood on the blade (both faces), part of it on the teeth
 for i=0,13 do
  local a=i/14*math.pi*2+rnd()*.4;local r=.55+rnd()*.65;local s=(i%2==0)and 1 or -1
  spin(part(model,'SawBladeBlood',Vector3.new(.12+rnd()*.16,.08+rnd()*.12,.04),hub*CFrame.new(math.cos(a)*r,math.sin(a)*r,s*.075)*CFrame.Angles(0,0,a+rnd()),blood:Lerp(red,rnd()*.4),GL))
 end
 -- 18 hooked teeth round the rim
 for i=0,17 do
  local a=i/18*math.pi*2
  local tcf=hub*CFrame.new(math.cos(a)*(R+.1),math.sin(a)*(R+.1),0)*CFrame.Angles(0,0,a-math.pi/2)
  spin(wedge(model,'SawBladeTooth',Vector3.new(.1,.34,.34),tcf*CFrame.new(-.04,0,0)*CFrame.Angles(0,math.pi/2,0)*CFrame.Angles(0,0,0),steel:Lerp(Color3.new(1,1,1),.3),MT))
  if i%3==0 then
   spin(wedge(model,'SawBladeTooth',Vector3.new(.105,.12,.14),tcf*CFrame.new(-.1,.07,0)*CFrame.Angles(0,math.pi/2,0),blood,GL))
  end
 end
 -- the hub on both faces: a big bolted hex nut at the right end of the upper lip
 for f=-1,1,2 do
  local hcf=hub*CFrame.new(0,0,f*(D*.5+.06))*CFrame.Angles(0,f<0 and math.pi or 0,0)
  part(model,'SawHousing',Vector3.new(.5,.5,.12),hcf*CFrame.new(0,0,-.02),darkRed,SP)
  for i=0,5 do part(model,'SawHubNut',Vector3.new(.2,.12,.12),hcf*CFrame.Angles(0,0,i/6*math.pi*2)*CFrame.new(0,.14,.06),grey,MT)end
  cylZ(model,'SawHubCap',.12,.16,hcf*CFrame.new(0,0,.08),dgrey,MT)
  for _,c in ipairs({{-.19,.19},{.19,-.19}})do bolt(hcf*CFrame.new(c[1],c[2],.04),.09)end
 end
 -- glow and the idle embers at the hub (PickFX SawGlow)
 local glow=part(model,'SawGlow',Vector3.new(.4,.4,.4),hub,red,SP,{Transparency=1,CastShadow=false})
 local light=Instance.new('PointLight');light.Name='SawLight';light.Color=Color3.fromRGB(255,40,36);light.Range=7;light.Brightness=.9;light.Shadows=false;light.Parent=glow
 local embers=emitter(glow,'Ember',Color3.fromRGB(255,60,40))
 if embers then
  embers.Name='SawEmbers';embers.Rate=2.5;embers.Speed=NumberRange.new(.6,1.6);embers.Lifetime=NumberRange.new(.5,1)
  embers.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(1,0)});embers.Acceleration=Vector3.new(0,1.5,0)
  embers.Color=ColorSequence.new(Color3.fromRGB(255,190,120),Color3.fromRGB(255,30,30))
 end

 -- UNDER THE HEAD: the collar, two chains, the dog tag
 local collarY=H.Position.Y-HH*.5-.16
 local col=CFrame.new(0,collarY,0)
 part(model,'SawCollar',Vector3.new(.86,.3,.86),col,grey,MT)
 part(model,'SawCollar',Vector3.new(.9,.08,.9),col*CFrame.new(0,-.16,0),dgrey,MT)
 for s=-1,1,2 do bolt(col*CFrame.new(s*.25,0,.44),.12);bolt(col*CFrame.Angles(0,math.pi,0)*CFrame.new(s*.25,0,.44),.12)end
 local hookA=Vector3.new(-.47,collarY-.05,.2)
 chain('SawChain',hookA,hookA+Vector3.new(-.02,-.9,0),6,'SawChain',1.1,hookA)
 local hookB=Vector3.new(.47,collarY-.05,.2)
 chain('SawTagChain',hookB,hookB+Vector3.new(.03,-.62,0),4,'SawTag',0,hookB)
 local tagCF=CFrame.new(hookB+Vector3.new(.03,-1.05,0))
 local tagParts={
  part(model,'SawTagRing',Vector3.new(.16,.16,.05),tagCF*CFrame.new(0,.44,0)*CFrame.Angles(0,0,math.rad(45)),grey,MT),
  part(model,'SawTag',Vector3.new(.52,.7,.06),tagCF,Color3.fromRGB(28,24,28),SL),
 }
 for s=-1,1,2 do
  table.insert(tagParts,part(model,'SawTagFrame',Vector3.new(.06,.76,.09),tagCF*CFrame.new(s*.27,0,0),grey,MT))
  table.insert(tagParts,part(model,'SawTagFrame',Vector3.new(.6,.06,.09),tagCF*CFrame.new(0,s*.36,0),grey,MT))
 end
 -- pixel skull on both faces
 local SKULL={'.###.','#####','#.#.#','#####','.#.#.'}
 for f=-1,1,2 do
  for r,line in ipairs(SKULL)do
   for c=1,5 do
    if line:sub(c,c)=='#'then
     table.insert(tagParts,part(model,'SawTagSkull',Vector3.new(.075,.075,.02),tagCF*CFrame.new((c-3)*.075,(3-r)*.075+.02,f*.04),Color3.fromRGB(236,28,34),SP))
    end
   end
  end
 end
 for _,p in ipairs(tagParts)do anim(p,'SawTag',0,hookB)end

 -- SHAFT ----------------------------------------------------------------------------------------
 local y0,y1=-len*.5+.25,collarY-.16
 part(model,'SawShaft',Vector3.new(.48,y1-y0,.48),CFrame.new(0,(y0+y1)*.5,0),char,SL)
 local function band(y,h,c,m,w)return part(model,'SawBand',Vector3.new(w or .54,h,w or .54),CFrame.new(0,y,0),c,m)end
 local function pixels(y,h)
  for f=0,3 do
   local face=CFrame.Angles(0,f*math.pi/2,0)
   for i=1,2 do
    local c=mottle()
    part(model,'SawPixel',Vector3.new(.11,.1,.03),face*CFrame.new((rnd()-.5)*.3,y+(rnd()-.5)*h*.7,.25),c,SP)
   end
  end
 end
 local function metalBand(y,h)
  band(y,h,grey,MT,.6)
  for f=0,3 do bolt(CFrame.new(0,y,0)*CFrame.Angles(0,f*math.pi/2,0)*CFrame.new(.18,0,.3),.1);bolt(CFrame.new(0,y,0)*CFrame.Angles(0,f*math.pi/2,0)*CFrame.new(-.18,0,.3),.1)end
 end
 local function xwrap(y,h)
  band(y,h,darkRed,FB,.52)
  for f=0,3 do
   local face=CFrame.new(0,y,0)*CFrame.Angles(0,f*math.pi/2,0)*CFrame.new(0,0,.27)
   for s=-1,1,2 do part(model,'SawWrap',Vector3.new(.09,h*1.25,.04),face*CFrame.Angles(0,0,s*math.rad(36)),red,FB)end
   part(model,'SawWrapKnot',Vector3.new(.13,.13,.05),face*CFrame.new(0,0,.02),darkRed,FB)
  end
 end
 metalBand(collarY-.42,.16)
 band(1.42,.28,red,SP);pixels(1.42,.28)
 metalBand(1.0,.14)
 xwrap(.62,.36)
 band(.27,.2,red,SP);pixels(.27,.2)
 xwrap(-.1,.36)
 band(-.55,.24,red,SP);pixels(-.55,.24)
 -- a chain wound round the upper shaft
 do
  local n=12
  for i=0,n-1 do
   local a=i/n*math.pi*2*1.15;local y=1.3-i*.06
   part(model,'SawShaftChain',Vector3.new(i%2==0 and .16 or .06,.17,i%2==0 and .06 or .16),CFrame.new(0,y,0)*CFrame.Angles(0,a,0)*CFrame.new(0,0,.31)*CFrame.Angles(0,0,math.rad(70)),grey:Lerp(dgrey,(i%3)*.2),MT)
  end
 end
 -- the badge band (orange flame emblem, front and back)
 band(-1.05,.38,grey,MT,.6)
 for s=-1,1,2 do
  local b=CFrame.new(0,-1.05,s*.31)*CFrame.Angles(0,s<0 and math.pi or 0,0)
  part(model,'SawBadge',Vector3.new(.3,.3,.04),b,Color3.fromRGB(40,26,22),SL)
  local flame=part(model,'SawBadgeFlame',Vector3.new(.14,.18,.03),b*CFrame.new(0,-.02,.025),ember,NE,{CastShadow=false})
  flame:SetAttribute('PickPulse',true)
  part(model,'SawBadgeFlame',Vector3.new(.07,.09,.03),b*CFrame.new(.02,.09,.025)*CFrame.Angles(0,0,math.rad(20)),Color3.fromRGB(255,200,90),NE,{CastShadow=false})
 end
 band(-1.42,.22,red,SP);pixels(-1.42,.22)
 -- POMMEL: a bolted clamp, a red block with a warning triangle, the glowing cap
 metalBand(-1.72,.22)
 band(-1.98,.3,red,SP,.58)
 for s=-1,1,2 do
  local w=CFrame.new(0,-1.98,s*.3)*CFrame.Angles(0,s<0 and math.pi or 0,0)
  wedge(model,'SawWarnTri',Vector3.new(.03,.22,.13),w*CFrame.new(-.065,0,.005)*CFrame.Angles(0,math.pi/2,0),Color3.fromRGB(255,206,30),SP)
  wedge(model,'SawWarnTri',Vector3.new(.03,.22,.13),w*CFrame.new(.065,0,.005)*CFrame.Angles(0,-math.pi/2,0),Color3.fromRGB(255,206,30),SP)
  part(model,'SawWarnMark',Vector3.new(.03,.1,.02),w*CFrame.new(0,-.02,.02),Color3.fromRGB(24,20,16),SP)
 end
 band(-len*.5+.02,.16,char,SL,.5)
 local core=part(model,'SawPommelGlow',Vector3.new(.3,.06,.3),CFrame.new(0,-len*.5-.07,0),ember,NE,{CastShadow=false})
 core:SetAttribute('PickPulse',true)

 model:SetAttribute('BackC0',CFrame.new(.5,-.7,.5)) -- the wide head hangs clear of the head
 model:SetAttribute('DisplayScale',.8)
 return (H*CFrame.new(-1.85,.3,0)).Position,(hub*CFrame.new(R+.25,.5,0)).Position
end

-- Scarlet Anime Scythe ("Алая Аниме-Коса", MYTHIC / ANIME concept sheet): a demonic voxel scythe.
-- HEAD: a dark iron block wrapped in a shell of scarlet and grey voxel bricks (rivets, uneven
-- depths, gaps); on the front (+Z) a square brick frame round a recessed violet socket with a
-- glowing magenta demon eye (bright pixel ring, black slit pupil, brick lids that blink), a smaller
-- red eye on the back; blocky scarlet horns on both top corners, grey spikes between them and a
-- horn pointing out to the left; on the right a grey iron clamp (holes, rivets) gripping the blade.
-- BLADE: a long crescent sweeping out over +X and curling down into a point: a jagged stepped
-- scarlet spine, a crimson band, a dark violet panel carrying glowing pixel glyphs on both faces,
-- a violet neon line and a pink-lavender neon cutting edge with a soft glow, a pink neon tip.
-- Under the head: a grey chain with violet links swinging on the left and a scarlet talisman on a
-- chain (dark glyph, ragged dripping hem) on the right. POLE: dark voxel segments with scarlet
-- cloth X-wraps, scarlet collars, violet glowing runes, a scarlet chain coiled under the head and
-- one hanging on the left; POMMEL: a scarlet block with grey corner studs and a blocky spike.
-- SmoothPlastic = lacquered bricks, Slate / Metal = worn iron, Fabric = cloth wraps and talisman,
-- Neon = energy only (eye, glyphs, runes, edge).
-- Moving parts (MiningClient.PickFX): ScytheEye (the iris looks round, darts on a strike),
-- ScytheLidTop / ScytheLidBot (blink), ScytheChain (chains swing at their hook), ScytheTalisman
-- (the talisman swings and flutters), ScytheHalo (the inspect ring of glyphs, hidden until the
-- inspect, PickPop = axis). Glyphs carry PickRune (their place along the blade, 0..1) for the
-- energy wave PickFX runs through them; runes and the edge pulse (PickPulse).
DESIGNS.Scythe=function(model,v,def,len,top)
 local SP,SL,ME,FA,NE=Enum.Material.SmoothPlastic,Enum.Material.Slate,Enum.Material.Metal,Enum.Material.Fabric,Enum.Material.Neon
 local red=rgb(v.Head)                          -- scarlet bricks
 local violet=rgb(v.Accent)                     -- glyph / rune energy
 local lavender=rgb(v.Trim)                     -- the hot core of the glow
 local iron=rgb(v.Iron,{130,122,130})           -- worn grey iron
 local dark=rgb(v.Shaft)                        -- dark iron pole / core
 local crimson=red:Lerp(Color3.new(0,0,0),.42)
 local blood=Color3.fromRGB(150,12,26)
 local panelC=Color3.fromRGB(92,28,156)
 local lilac=Color3.fromRGB(168,82,240)
 local magenta=Color3.fromRGB(240,56,206)
 local pink=Color3.fromRGB(255,128,232)
 local black=Color3.fromRGB(16,10,16)
 local small={CastShadow=false}
 local glow={CastShadow=false}
 model.PrimaryPart.Transparency=1                -- the thin Handle hides inside the voxel pole
 -- deterministic "random" (every peer builds the identical model)
 local seed=0
 local function rnd()seed+=1;local x=math.sin(seed*12.9898+78.233)*43758.5453;return x-math.floor(x)end
 local function shade(c,amount)local k=(rnd()-.5)*(amount or .16);return k>0 and c:Lerp(Color3.new(1,1,1),k*.6)or c:Lerp(Color3.new(0,0,0),-k)end
 local H=Vector3.new(0,len*.5+.06,0)             -- head centre
 local function at(x,y,z)return CFrame.new(H+Vector3.new(x,y,z))end
 local HX,HY,HZ=.58,.6,.4                       -- head core half sizes

 -- HEAD CORE + VOXEL SHELL --------------------------------------------------------------------
 part(model,'ScytheCore',Vector3.new(HX*2,HY*2,HZ*2),at(0,0,0),Color3.fromRGB(40,30,40),SL)
 local CELL=.2
 -- one brick of the shell: face normal axis ('X','Y','Z'), sign, the two in-face coordinates
 local function brick(axis,sgn,a,b,colorPick,depth,name)
  local d=depth or(.1+rnd()*.12)
  local col=colorPick
  local mat=(col==iron or col==dark)and SL or SP
  col=shade(col)
  local size,pos
  if axis=='Z'then size=Vector3.new(CELL-.012,CELL-.012,d);pos=Vector3.new(a,b,sgn*(HZ+d*.5-.03))
  elseif axis=='X'then size=Vector3.new(d,CELL-.012,CELL-.012);pos=Vector3.new(sgn*(HX+d*.5-.03),b,a)
  else size=Vector3.new(CELL-.012,d,CELL-.012);pos=Vector3.new(a,sgn*(HY+d*.5-.03),b)end
  local p=part(model,name or'HeadBrick',size,at(pos.X,pos.Y,pos.Z),col,mat)
  -- a rivet on some scarlet bricks (the concept's little dark dots)
  if colorPick==red and rnd()<.22 then
   local o=axis=='Z'and Vector3.new(0,0,sgn*(d*.5+.004))or(axis=='X'and Vector3.new(sgn*(d*.5+.004),0,0)or Vector3.new(0,sgn*(d*.5+.004),0))
   part(model,'Rivet',Vector3.new(.04,.04,.04),at(pos.X+o.X,pos.Y+o.Y,pos.Z+o.Z),black,SP,small)
  end
  return p
 end
 -- FRONT (+Z) and BACK (-Z): a 6 x 6 grid; the centre 2 x 2 is the eye socket. The frame's grey
 -- iron bricks sit where the concept has them (upper right corner, the right edge by the clamp).
 local ironCells={['5,6']=true,['6,6']=true,['6,5']=true,['6,3']=true,['1,1']=true,['4,1']=true,['1,4']=true}
 for _,sgn in ipairs({1,-1})do
  for i=1,6 do for j=1,6 do
   local inner=(i==3 or i==4)and(j==3 or j==4)
   if not inner then
    local key=(sgn>0 and i or 7-i)..','..j
    local col=ironCells[key]and iron or red
    local ring=(i==1 or i==6 or j==1 or j==6)
    brick('Z',sgn,(i-3.5)*CELL,(j-3.5)*CELL,col,ring and(.14+rnd()*.1)or(.1+rnd()*.05),'FrameBrick')
   end
  end end
 end
 -- SIDES (+-X), TOP (+Y), BOTTOM (-Y): 4 x 6 / 6 x 4 grids with gaps (the dark core shows through).
 for _,sgn in ipairs({1,-1})do
  for i=1,4 do for j=1,6 do
   if rnd()>.22 then brick('X',sgn,(i-2.5)*CELL,(j-3.5)*CELL,(sgn>0 or rnd()<.3)and iron or red)end
  end end
 end
 for i=1,6 do for j=1,4 do
  if rnd()>.2 then brick('Y',1,(i-3.5)*CELL,(j-2.5)*CELL,rnd()<.3 and iron or red)end
  if rnd()>.45 then brick('Y',-1,(i-3.5)*CELL,(j-2.5)*CELL,rnd()<.5 and iron or red)end
 end end

 -- DEMON EYE (front): violet socket, magenta iris, a bright pixel ring, black slit, brick lids ----
 local FZ=HZ+.02
 local E=at(0,0,FZ)
 part(model,'EyeSocket',Vector3.new(.42,.42,.06),E,Color3.fromRGB(34,8,46),SP)
 local eyeParts={}
 local iris=cylZ(model,'EyeIris',.04,.34,E*CFrame.new(0,0,.04),magenta,NE,glow)
 table.insert(eyeParts,iris)
 table.insert(eyeParts,part(model,'EyeIrisHot',Vector3.new(.2,.2,.04),E*CFrame.new(0,0,.05)*CFrame.Angles(0,0,math.pi/4),pink,NE,glow))
 for k=0,11 do
  local a=k/12*math.pi*2
  table.insert(eyeParts,part(model,'EyeRing',Vector3.new(.05,.05,.04),E*CFrame.new(math.cos(a)*.15,math.sin(a)*.15,.06),k%3==0 and lavender or pink,NE,glow))
 end
 table.insert(eyeParts,part(model,'EyePupil',Vector3.new(.06,.24,.04),E*CFrame.new(0,0,.08),black,SP,small))
 table.insert(eyeParts,part(model,'EyePupil',Vector3.new(.035,.07,.04),E*CFrame.new(0,.14,.075),black,SP,small))
 table.insert(eyeParts,part(model,'EyePupil',Vector3.new(.035,.07,.04),E*CFrame.new(0,-.14,.075),black,SP,small))
 table.insert(eyeParts,part(model,'EyeGlint',Vector3.new(.04,.04,.03),E*CFrame.new(-.07,.07,.09),Color3.new(1,1,1),NE,small))
 for _,p in ipairs(eyeParts)do anim(p,'ScytheEye',0,E.Position)end
 local eyeGlow=Instance.new('PointLight');eyeGlow.Name='EyeGlow';eyeGlow.Color=Color3.fromRGB(255,60,210);eyeGlow.Range=6;eyeGlow.Brightness=1.1;eyeGlow.Shadows=false;eyeGlow.Parent=iris
 -- lids: scarlet bricks hidden inside the frame, sliding over the socket on a blink
 anim(part(model,'EyeLidTop',Vector3.new(.42,.22,.05),E*CFrame.new(0,.32,.07),red,SP),'ScytheLidTop',0,E.Position)
 anim(part(model,'EyeLidBot',Vector3.new(.42,.22,.05),E*CFrame.new(0,-.32,.07),red,SP),'ScytheLidBot',0,E.Position)
 -- back eye: smaller, blood red
 local B=at(0,0,-FZ)
 part(model,'EyeSocketBack',Vector3.new(.42,.42,.06),B,Color3.fromRGB(34,8,30),SP)
 local backIris=cylZ(model,'EyeBack',.04,.28,B*CFrame.new(0,0,-.04),Color3.fromRGB(255,40,70),NE,glow)
 backIris:SetAttribute('PickPulse',true)
 part(model,'EyeBackPupil',Vector3.new(.05,.2,.04),B*CFrame.new(0,0,-.07),black,SP,small)
 for k=0,7 do
  local a=k/8*math.pi*2
  part(model,'EyeBackRing',Vector3.new(.045,.045,.04),B*CFrame.new(math.cos(a)*.17,math.sin(a)*.17,-.05),Color3.fromRGB(255,96,120),NE,glow)
 end

 -- HORNS AND SPIKES: blocky voxel horns (stacked shrinking cubes and a wedge point) --------------
 local function horn(name,base,dir,n,size,color,mat,tipColor)
  dir=dir.Unit
  local p=base;local s=size
  local rot=CFrame.new(Vector3.zero)*alignY(dir)
  for k=1,n do
   part(model,name,Vector3.new(s,s*1.05,s),CFrame.new(p)*rot,shade(color,.1),mat)
   p+=dir*s*.86;s*=.78
  end
  local nrm=dir:Cross(Vector3.zAxis);if nrm.Magnitude<.1 then nrm=Vector3.xAxis end
  spike(model,name..'Tip',p-dir*s*.3,dir,nrm,s*2.1,s*1.05,s*.95,tipColor or color,mat)
 end
 horn('HornL',H+Vector3.new(-.44,HY+.08,.06),Vector3.new(-.42,1,.05),3,.28,red,SP)
 horn('HornR',H+Vector3.new(.43,HY+.06,.08),Vector3.new(.3,1,.08),3,.24,red,SP)
 horn('HornBack',H+Vector3.new(.06,HY+.06,-.24),Vector3.new(.08,1,-.35),2,.2,iron,SL,red)
 horn('SpikeTop',H+Vector3.new(-.08,HY+.04,.18),Vector3.new(-.05,1,.12),1,.15,iron,SL)
 horn('SpikeTop',H+Vector3.new(.18,HY+.04,.1),Vector3.new(.15,1,0),1,.13,iron,SL,red)
 horn('HornSide',H+Vector3.new(-HX-.06,.24,0),Vector3.new(-1,.5,0),2,.22,red,SP)
 horn('HornSide',H+Vector3.new(-HX-.04,-.3,-.1),Vector3.new(-1,-.2,-.25),1,.14,iron,SL)

 -- CLAMP (right): grey iron bricks gripping the blade root, holes and rivets ----------------------
 for col=0,1 do for row=0,4 do
  local x=HX+.1+col*.2;local y=-.34+row*.2
  local d=.58+rnd()*.08
  part(model,'Clamp',Vector3.new(.19,.19,d),at(x,y,0),shade(iron,.18),col==1 and ME or SL,{Reflectance=col==1 and .05 or 0})
  if(row+col)%2==0 then
   part(model,'ClampHole',Vector3.new(.08,.08,.02),at(x,y,d*.5+.005),black,SP,small)
   part(model,'ClampHole',Vector3.new(.08,.08,.02),at(x,y,-d*.5-.005),black,SP,small)
  end
 end end
 part(model,'ClampCap',Vector3.new(.46,.1,.7),at(HX+.2,.66,0),shade(iron,.1),ME,{Reflectance=.06})
 part(model,'ClampCap',Vector3.new(.46,.1,.7),at(HX+.2,-.46,0),shade(iron,.1),ME,{Reflectance=.06})
 for _,y in ipairs({.5,-.3})do for _,z in ipairs({.37,-.37})do part(model,'ClampRivet',Vector3.new(.07,.07,.04),at(HX+.32,y,z),Color3.fromRGB(200,196,204),ME,small)end end

 -- BLADE: a crescent in the XY plane, built along a cubic spine curve ----------------------------
 local function bez(p0,p1,p2,p3,t)local u=1-t;return p0*u*u*u+p1*3*u*u*t+p2*3*u*t*t+p3*t*t*t end
 local P0,P1,P2,P3=H+Vector3.new(.72,.46,0),H+Vector3.new(1.9,1.05,0),H+Vector3.new(3.4,.4,0),H+Vector3.new(2.9,-2.1,0)
 local function spineAt(t)return bez(P0,P1,P2,P3,math.clamp(t,0,1))end
 local N=24
 local function widthAt(t)return 1.02*(1-t)^.62+.02 end
 local frames={}
 for i=1,N do
  local t=(i-.5)/N
  local pos=spineAt(t);local tan=(spineAt(t+.01)-spineAt(t-.01)).Unit
  local nrm=Vector3.new(tan.Y,-tan.X,0)          -- inward: toward the concave (cutting) side
  frames[i]={T=t,Pos=pos,Tan=tan,N=nrm,W=widthAt(t),Seg=(spineAt(i/N)-spineAt((i-1)/N)).Magnitude}
 end
 -- a box spanning the band a..b (distances from the spine along the inward normal), a touch longer
 -- toward the spine (the convex side, where the curve would open gaps between the boxes)
 local function band(f,name,a,b,depth,color,mat,props,lenK)
  local c=f.Pos+f.N*(a+b)*.5
  local stretch=1+math.max(0,.5-(a+b)*.5)*.25
  return part(model,name,Vector3.new(f.Seg*(lenK or 1.14)*stretch,math.max(.02,b-a),depth),CFrame.fromMatrix(c,f.Tan,f.N,f.Tan:Cross(f.N)),color,mat,props)
 end
 local edgeParts={}
 for i,f in ipairs(frames)do
  local w=f.W;local t=f.T
  local rim=math.max(.07,math.min(.17,w*.26))
  -- jagged stepped scarlet spine: each brick sticks out a little differently
  local out=.02+rnd()*.07
  band(f,'BladeSpine',-out,rim,.24-t*.08,shade(red,.14),SP,nil,1.08)
  if i%2==0 and t<.86 then band(f,'BladeTooth',-out-.07,-out+.02,.18,shade(red,.1),SP,nil,.5)end
  if i%3==1 and t<.8 then band(f,'BladeRivet',rim*.3,rim*.3+.05,.27-t*.08,black,SP,small,.18)end
  band(f,'BladeBand',rim,rim+w*.06,.19-t*.06,shade(crimson,.1),SP)
  local p0,p1=rim+w*.06,w*.66
  if p1>p0+.02 then band(f,'BladePanel',p0,p1,.13-t*.04,shade(panelC,.06),SP)end
  band(f,'BladeGlass',w*.66,w*.76,.11-t*.03,lilac,Enum.Material.Glass,{CastShadow=false,Transparency=.1})
  local line=band(f,'BladeLine',w*.76,w*.8,.1-t*.03,violet,NE,glow)
  line:SetAttribute('PickPulse',true)
  local edge=band(f,'BladeEdge',w*.8,w,.06,pink:Lerp(lavender,.3),NE,glow)
  table.insert(edgeParts,edge)
  band(f,'BladeAura',w,w+.08,.03,magenta,NE,{CastShadow=false,Transparency=.55})
 end
 -- the point: scarlet spine and a pink neon tip
 do
  local last=frames[N]
  local tipBase=last.Pos+last.Tan*last.Seg*.45
  spike(model,'BladeTip',tipBase,last.Tan,last.N,.42,.12,.16,red,SP)
  spike(model,'BladeTipEdge',tipBase+last.N*.05,last.Tan,last.N,.5,.1,.06,pink,NE,glow)
 end
 -- GLYPHS: 5 x 5 pixel runes along the panel (front) and a different line on the back. Rows are
 -- merged into bars. Baseline along the blade, "up" toward the spine.
 local GLYPHS={
  {'.###.','.#.#.','.#.#.','.#.#.','##.##'},   -- Л
  {'.###.','....#','.####','#...#','.####'},   -- Ә
  {'.###.','#...#','#####','#...#','.###.'},   -- Ө
  {'.....','.....','.###.','.....','.....'},   -- -
  {'####.','#....','###..','#..#.','#...#'},   -- Ӷ
 }
 local BACK={
  {'#.#.#','.###.','..#..','.###.','#.#.#'},   -- Ж
  {'#.#.#','.###.','..#..','.###.','#.#.#'},
  {'####.','#....','###..','#....','####.'},   -- Е
  {'.....','..#..','.###.','..#..','.....'},
 }
 local function glyphAt(rows,t,size,face,mirror)
  local pos=spineAt(t);local tan=(spineAt(t+.01)-spineAt(t-.01)).Unit
  local nrm=Vector3.new(tan.Y,-tan.X,0)
  local w=widthAt(t);local rim=math.max(.07,math.min(.17,w*.26))
  local mid=(rim+w*.06+w*.66)*.5
  local center=pos+nrm*mid
  local px=size/5
  local depth=.13-t*.04
  local z=face*(depth*.5+.012)
  local up=-nrm
  local list={}
  for r=1,5 do
   local row=rows[r];local c=1
   while c<=5 do
    if string.sub(row,c,c)=='#'then
     local e=c;while e<5 and string.sub(row,e+1,e+1)=='#'do e+=1 end
     local cx=((c+e)*.5-3)*px*(mirror and -1 or 1)
     local cy=(3-r)*px
     local p=center+tan*cx+up*cy+Vector3.new(0,0,z)
     local g=part(model,'Glyph',Vector3.new((e-c+1)*px-.006,px-.006,.025),CFrame.fromMatrix(p,tan,up,tan:Cross(up)),lavender,NE,glow)
     g:SetAttribute('PickRune',t);table.insert(list,g)
     c=e+1
    else c+=1 end
   end
  end
  return list
 end
 local front={{.15,.34},{.28,.32},{.41,.28},{.52,.2},{.61,.22}}
 for k,g in ipairs(front)do glyphAt(GLYPHS[k],g[1],g[2],1,false)end
 local back={{.17,.33},{.31,.3},{.44,.26},{.56,.2}}
 for k,g in ipairs(back)do glyphAt(BACK[k],g[1],g[2],-1,true)end
 local bladeGlow=Instance.new('PointLight');bladeGlow.Name='BladeGlow';bladeGlow.Color=Color3.fromRGB(214,80,255);bladeGlow.Range=7;bladeGlow.Brightness=.9;bladeGlow.Shadows=false
 bladeGlow.Parent=edgeParts[math.floor(N*.45)]

 -- UNDER THE HEAD: collar, coiled scarlet chain ------------------------------------------------
 local hb=H.Y-HY                                 -- head bottom
 part(model,'Collar',Vector3.new(.54,.24,.54),CFrame.new(0,hb-.1,0),shade(dark,.1),SL)
 for _,c in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}})do part(model,'CollarBrick',Vector3.new(.14,.14,.14),CFrame.new(c[1]*.25,hb-.06,c[2]*.25),shade(red,.1),SP)end
 part(model,'Collar',Vector3.new(.42,.12,.42),CFrame.new(0,hb-.28,0),shade(iron,.1),SL)
 local function link(name,cf,color,mat,props)
  return part(model,name,Vector3.new(.06,.15,.1),cf,color,mat or ME,props or small)
 end
 for k=0,7 do -- a scarlet chain coiled round the pole under the collar
  local a=k*.95;local y=hb-.42-k*.07
  link('CoilChain',CFrame.new(math.cos(a)*.2,y,math.sin(a)*.2)*CFrame.Angles(0,-a,0)*CFrame.Angles(0,k%2==0 and 0 or math.pi/2,math.pi/2.4),shade(red,.1),SP)
 end

 -- HANGING CHAINS: grey with violet links (left), the talisman (right) -------------------------
 local function chain(name,hang,links,colors,ph,kind)
  local list={}
  for k=1,links do
   local cf=CFrame.new(hang-Vector3.new(0,.06+(k-1)*.12,0))*CFrame.Angles(0,k%2==0 and math.pi/2 or 0,0)
   local col=colors[k]or colors[#colors]
   local neon=col==violet or col==lavender
   table.insert(list,anim(link(name,cf,col,neon and NE or ME,neon and glow or{CastShadow=false,Reflectance=.08}),kind or'ScytheChain',ph,hang))
  end
  return list,hang-Vector3.new(0,.06+(links-1)*.12+.08,0)
 end
 do
  local hang=H+Vector3.new(-HX-.02,-HY+.12,.16)
  local _,endPos=chain('ChainL',hang,8,{iron,iron,iron,iron,violet,iron,violet,iron},0)
  for _,w in ipairs(spike(model,'ChainWeight',endPos+Vector3.new(0,.02,0),Vector3.new(0,-1,0),Vector3.xAxis,.22,.12,.1,iron,ME))do anim(w,'ScytheChain',0,hang)end
 end
 do
  local hang=H+Vector3.new(.52,-HY-.02,.24)
  part(model,'TalismanHook',Vector3.new(.1,.1,.1),CFrame.new(hang+Vector3.new(0,.04,0)),iron,ME,small)
  local _,endPos=chain('TalismanChain',hang,5,{iron},.8,'ScytheTalisman')
  local tal={}
  local function t(p)table.insert(tal,p);return p end
  local topY=endPos.Y-.02
  local cx,cz=hang.X,hang.Z
  t(part(model,'TalismanBar',Vector3.new(.44,.07,.08),CFrame.new(cx,topY,cz),shade(iron,.08),ME))
  local plateH=1.0
  local pc=CFrame.new(cx,topY-.03-plateH*.5,cz)
  t(part(model,'Talisman',Vector3.new(.38,plateH,.05),pc,Color3.fromRGB(200,20,36),FA))
  t(part(model,'TalismanTrim',Vector3.new(.38,.05,.06),pc*CFrame.new(0,plateH*.5-.04,0),blood,FA))
  -- the dark glyph painted on the talisman (both faces)
  local rune={{0,.24,.16,.05},{0,.14,.05,.18},{-.06,.02,.05,.1},{.06,.02,.05,.1},{0,-.08,.16,.05},{-.04,-.18,.05,.14},{.05,-.22,.08,.05}}
  for _,r in ipairs(rune)do
   for _,s in ipairs({1,-1})do t(part(model,'TalismanGlyph',Vector3.new(r[3],r[4],.02),pc*CFrame.new(r[1]*s,r[2],s*.034),Color3.fromRGB(40,6,12),SP,small))end
  end
  -- ragged dripping hem: strips of different lengths ending in a point
  local hemY=-plateH*.5
  local drops={.26,.12,.34,.18,.3,.16}
  for k,dl in ipairs(drops)do
   local x=-.16+(k-1)*.064
   t(part(model,'TalismanDrip',Vector3.new(.06,dl,.05),pc*CFrame.new(x,hemY-dl*.5+.01,0),Color3.fromRGB(196,18,34):Lerp(blood,(k%2)*.4),FA,small))
   for _,w in ipairs(spike(model,'TalismanDrip',(pc*CFrame.new(x,hemY-dl+.01,0)).Position,Vector3.new(0,-1,0),Vector3.xAxis,.07,.06,.05,blood,FA,small))do t(w)end
  end
  for _,p in ipairs(tal)do anim(p,'ScytheTalisman',.8,hang)end
 end

 -- POLE: dark voxel segments, cloth X-wraps, scarlet collars, glowing runes --------------------
 local sTop,sBot=hb-.34,-len*.5+.18
 local nSeg=math.floor((sTop-sBot)/.27+.5)
 local segH=(sTop-sBot)/nSeg
 for k=0,nSeg-1 do
  local y=sTop-(k+.5)*segH
  local wd=(k%3==1)and .33 or .35
  part(model,'Pole',Vector3.new(wd,segH-.01,wd),CFrame.new(0,y,0)*CFrame.Angles(0,(k%2)*.04-.02,0),shade(dark,.22),SL)
  if rnd()<.35 then -- a chipped voxel on a corner
   local sx,sz=rnd()<.5 and 1 or -1,rnd()<.5 and 1 or -1
   part(model,'PoleChip',Vector3.new(.08,.1,.08),CFrame.new(sx*.15,y+(rnd()-.5)*.1,sz*.15),shade(iron,.2),SL,small)
  end
 end
 -- scarlet cloth X-wraps on all four faces (one of them is the grip, round y = -1.4)
 local function wrap(y,h)
  for _,dy in ipairs({h*.5,-h*.5})do part(model,'Wrap',Vector3.new(.37,.07,.37),CFrame.new(0,y+dy,0),shade(red,.12),FA)end
  local diag=math.sqrt(.34*.34+h*h)
  local ang=math.atan2(h,.34)
  for f=0,3 do
   local face=CFrame.Angles(0,f*math.pi/2,0)*CFrame.new(0,0,.172)
   for _,s in ipairs({1,-1})do
    part(model,'WrapX',Vector3.new(diag,.07,.025),CFrame.new(0,y,0)*face*CFrame.Angles(0,0,s*ang),shade(red,.12),FA,small)
   end
  end
 end
 wrap(sTop-.42,.36)
 wrap(.42,.34)
 wrap(-1.4,.46)
 wrap(-2.3,.34)
 for _,y in ipairs({1.05,-.42,-1.8})do
  part(model,'Band',Vector3.new(.38,.12,.38),CFrame.new(0,y,0),shade(red,.1),SP)
  part(model,'BandRivet',Vector3.new(.05,.05,.03),CFrame.new(0,y,.2),Color3.fromRGB(190,186,194),ME,small)
 end
 -- violet runes glowing out of the pole (front and back)
 local runes={{1.55,1},{1.32,1},{-.12,1},{-.66,1},{-.88,1},{.0,-1},{-2.6,1},{1.45,-1},{-.76,-1}}
 for i,r in ipairs(runes)do
  local y,s=r[1],r[2]
  local tall=i%2==0
  local g=part(model,'PoleRune',Vector3.new(tall and .05 or .14,tall and .16 or .05,.02),CFrame.new((i%3-1)*.04,y,s*.165),violet,NE,glow)
  g:SetAttribute('PickPulse',true)
  if tall then part(model,'PoleRune',Vector3.new(.09,.04,.02),CFrame.new(.04,y+.05,s*.165),lavender,NE,glow):SetAttribute('PickPulse',true)end
 end
 -- a scarlet chain hanging off the left of the pole
 do
  local hang=Vector3.new(-.19,.98,.04)
  part(model,'ChainHook',Vector3.new(.08,.1,.1),CFrame.new(hang+Vector3.new(.02,.03,0)),shade(red,.1),SP,small)
  local _,endPos=chain('ChainR',hang,6,{shade(red,.1)},1.7)
  for _,w in ipairs(spike(model,'ChainWeight',endPos+Vector3.new(0,.02,0),Vector3.new(0,-1,0),Vector3.zAxis,.18,.1,.08,red,SP))do anim(w,'ScytheChain',1.7,hang)end
  for _,p in ipairs(model:GetChildren())do if p.Name=='ChainR'then p.Material=SP end end
 end

 -- POMMEL: scarlet block, grey corner studs, violet pixel, a blocky spike ------------------------
 local pb=-len*.5
 part(model,'PommelCollar',Vector3.new(.42,.1,.42),CFrame.new(0,pb+.12,0),shade(dark,.1),SL)
 part(model,'Pommel',Vector3.new(.48,.32,.48),CFrame.new(0,pb-.1,0),shade(red,.08),SP)
 part(model,'PommelBand',Vector3.new(.5,.06,.5),CFrame.new(0,pb-.1,0),shade(dark,.1),SL)
 for _,c in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}})do part(model,'PommelStud',Vector3.new(.13,.13,.13),CFrame.new(c[1]*.24,pb-.02,c[2]*.24),shade(iron,.15),SL)end
 local gem=part(model,'PommelGem',Vector3.new(.1,.1,.03),CFrame.new(0,pb-.1,.25),violet,NE,glow);gem:SetAttribute('PickPulse',true)
 part(model,'PommelBase',Vector3.new(.34,.1,.34),CFrame.new(0,pb-.31,0),shade(dark,.1),SL)
 horn('PommelSpike',Vector3.new(0,pb-.44,0),Vector3.new(0,-1,0),1,.2,red,SP)

 -- INSPECT RING: six pixel glyphs circling the scythe (hidden until PickFX shows them) ---------
 local ringC=CFrame.new(0,H.Y-1.15,0)
 local RUNES={{'#.#','.#.','#.#'},{'###','.#.','.#.'},{'#..','###','..#'},{'.#.','###','.#.'},{'##.','.##','#.#'},{'#.#','###','#.#'}}
 for k=1,6 do
  local a=(k-1)/6*math.pi*2
  local c=ringC*CFrame.Angles(0,a,0)*CFrame.new(0,math.sin(a*2)*.12,1.55)
  local px=.08
  for r=1,3 do for cc=1,3 do
   if string.sub(RUNES[k][r],cc,cc)=='#'then
    local p=part(model,'ScytheHalo',Vector3.new(px,px,.02),c*CFrame.new((cc-2)*px,(2-r)*px,0),lavender,NE,{CastShadow=false,Transparency=1})
    anim(p,'ScytheHalo',0,ringC.Position);p:SetAttribute('PickPop',Vector3.yAxis)
   end
  end end
 end

 -- IDLE FX: a few slow violet motes drifting off the blade (the floating glyphs are PickFX) -----
 local holder=part(model,'ScytheMotes',Vector3.new(2.2,2.4,.3),at(2.05,-.15,0),violet,SP,{Transparency=1,CastShadow=false})
 local fx=emitter(holder,'Void',violet)
 if fx then
  fx.Rate=2.5;fx.Speed=NumberRange.new(.2,.7);fx.Lifetime=NumberRange.new(1,1.8)
  fx.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,140,240)),ColorSequenceKeypoint.new(1,Color3.fromRGB(150,60,255))})
 end
 -- on the back: a little higher and further out, so the head and blade clear the wearer's head
 model:SetAttribute('BackC0',CFrame.new(.15,-.35,.2))
 model:SetAttribute('HandYaw',45)
 model:SetAttribute('HandTilt',28)
 return H+Vector3.new(.9,.3,0),P3
end

-- Twin Claws ("Кирка Когти-Близнецы" concept sheet, Mythic / Combat): a PAIR of voxel combat
-- gauntlets, one per hand. Models.Pickaxe builds the right one (rune 右, scarlet accents),
-- Models.PickaxeOffhand the left one (rune 左, violet accents). Handle space (Models.ToolGrip.Glove):
-- +Y runs along the fingers out to the claws, -Y back up the forearm, +Z is the back of the hand
-- (forward with the arm hanging), -Z the palm; side 1 / -1 mirrors X (+x = the outer side, the
-- thumb sits on the inner side). Built from every view of the sheet:
--   back of the hand: the dark rune plate in a black riveted rim, framed by white "Г" stone blocks,
--   the kanji drawn as glowing neon strokes, a neon bar on the wrist edge;
--   the cuff: black steel, a white cracked strap, a glowing ring on the outer side and exhaust
--   tubes along the forearm (three on the right gauntlet, four on the left);
--   four fingers: a white knuckle block, a neon tube in a steel recess, a white armour plate, a
--   round actuator at the claw root, neon slits between the fingers;
--   four long curved talons (white battle-worn steel with cracks, a bevelled ridge, neon cutting
--   edges, a glowing point) fanning out and curling toward the palm; a blocky thumb, palm plates.
-- Living parts (MiningClient.PickFX): the claws slide in and out (TwinClaw), the actuators turn
-- (TwinActuator), the kanji strokes flash (TwinRune); ClawTrailA / ClawTrailB on every claw tip carry
-- the air scratch trails; TwinVent puffs smoke out of the tubes on a strike.
local KANJI={
 -- strokes as polylines in the plate's own (u right, v up) square, -1..1
 [1]={{{.15,.95},{-.18,.28},{-.86,-.86}},{{-.86,.42},{.86,.42}},{{-.3,-.1},{-.3,-.9}},{{-.3,-.08},{.8,-.08}},{{.8,-.08},{.8,-.9}},{{-.3,-.86},{.8,-.86}}}, -- 右
 [-1]={{{.1,.95},{-.2,.25},{-.86,-.86}},{{-.86,.42},{.86,.42}},{{-.16,-.08},{.78,-.08}},{{.31,-.08},{.31,-.86}},{{-.36,-.86},{.94,-.86}}}, -- 左
}
local function twinGauntlet(model,v,side)
 local SP,SL,ME,NE=Enum.Material.SmoothPlastic,Enum.Material.Slate,Enum.Material.Metal,Enum.Material.Neon
 local right=side>0
 local accent=rgb(right and v.Accent or v.Trim)
 local hot=accent:Lerp(Color3.new(1,1,1),.45)
 local steelC=rgb(v.Shaft)                       -- black steel
 local stoneC=rgb(v.Head)                        -- white cracked armour
 local clawC=rgb(v.Claw,{206,206,214})           -- the talons
 local dark=Color3.fromRGB(16,14,20)
 local crackC=Color3.fromRGB(50,46,56)
 local rivetC=Color3.fromRGB(100,98,108)
 local tipRed=Color3.fromRGB(255,64,84)
 local glow={CastShadow=false}
 local small={CastShadow=false}
 local handle=model.PrimaryPart
 handle.Size=Vector3.new(.9,.8,.8);handle.Transparency=1;handle.CastShadow=false
 model:SetAttribute('TwinSide',side)
 -- deterministic "random" (every peer builds the identical pair; the two hands differ)
 local seed=right and 0 or 400
 local function rnd()seed+=1;local x=math.sin(seed*12.9898+78.233)*43758.5453;return x-math.floor(x)end
 local function shade(c,amount)local k=(rnd()-.5)*(amount or .14);return k>0 and c:Lerp(Color3.new(1,1,1),k*.6)or c:Lerp(Color3.new(0,0,0),-k)end
 local X0=.05                                    -- the whole gauntlet sits a little outward (clears the hip)
 local function P(x,y,z)return Vector3.new((x+X0)*side,y,z)end
 local function at(x,y,z)return CFrame.new(P(x,y,z))end
 local function steel(name,size,cf)return part(model,name,size,cf,shade(steelC,.12),ME,{Reflectance=.06})end
 -- a dark crack on the face (block-space normal) of a block: a line and now and then a branch
 local function crack(p,face,len)
  local s=p.Size
  local u=math.abs(face.X)>.5 and Vector3.yAxis or Vector3.xAxis
  local w=face:Cross(u)
  local half=Vector3.new(math.abs(s.X),math.abs(s.Y),math.abs(s.Z))*.5
  local depth=math.abs(face:Dot(half))
  local su,sw=math.abs(u:Dot(half)),math.abs(w:Dot(half))
  local c=face*(depth+.004)+u*(rnd()-.5)*su*1.1+w*(rnd()-.5)*sw*1.1
  local a=rnd()*math.pi
  local d=u*math.cos(a)+w*math.sin(a)
  local l=(len or math.min(su,sw)*1.2)*(.6+rnd()*.6)
  part(model,'Crack',Vector3.new(.018,l,.012),p.CFrame*CFrame.fromMatrix(c,d:Cross(face),d),crackC,SP,small)
  if rnd()<.35 then
   local b=a+(rnd()<.5 and .7 or -.7)
   local e=u*math.cos(b)+w*math.sin(b)
   part(model,'Crack',Vector3.new(.016,l*.45,.012),p.CFrame*CFrame.fromMatrix(c+d*l*.15+e*l*.2,e:Cross(face),e),crackC,SP,small)
  end
 end
 -- a white cracked armour block; face = the block-space side that looks out (gets the cracks)
 local function stone(name,size,cf,face)
  local p=part(model,name,size,cf,shade(stoneC,.12),SL)
  face=face or Vector3.zAxis
  crack(p,face)
  if rnd()<.4 then crack(p,face)end
  -- a chipped corner
  if rnd()<.3 then
   local o=Vector3.new(size.X*(rnd()<.5 and .5 or -.5),size.Y*(rnd()<.5 and .5 or -.5),size.Z*(rnd()<.5 and .5 or -.5))
   part(model,'Chip',Vector3.new(.06,.06,.06),cf*CFrame.new(o*.92),crackC,SP,small)
  end
  return p
 end
 local outX=Vector3.new(side,0,0)                -- the outer side's normal (block space = model space here)

 -- FOREARM HOUSING (the hand sits in its finger end, the forearm runs up to the elbow end) -----
 -- y: -1.1 elbow end .. 0 knuckle line (Models.ToolGrip.Glove puts the hand round y = -.2)
 steel('Housing',Vector3.new(1.26,1.0,1.0),at(0,-.5,.02))
 -- back of the hand: the rune plate in a black riveted rim
 local zp=.53
 local yc=-.5                                   -- plate centre
 part(model,'RunePlate',Vector3.new(.76,.68,.06),at(0,yc,zp+.03),dark,SP)
 steel('RuneRim',Vector3.new(.88,.07,.09),at(0,yc-.375,zp+.045))
 steel('RuneRim',Vector3.new(.88,.07,.09),at(0,yc+.375,zp+.045))
 for s=-1,1,2 do steel('RuneRim',Vector3.new(.07,.82,.09),at(s*.415,yc,zp+.045))end
 for _,c in ipairs({{-1,-1},{1,-1},{-1,1},{1,1},{-1,0},{1,0}})do
  part(model,'Rivet',Vector3.new(.05,.05,.03),at(c[1]*.33,yc+c[2]*.28,zp+.07),rivetC,ME,small)
 end
 -- the kanji: neon strokes over a soft glow (never mirrored: both runes read the right way round)
 do
  local zk=zp+.072
  local function pt(q,z)return Vector3.new(X0*side-q[1]*.29,yc-q[2]*.27,z)end
  for _,stroke in ipairs(KANJI[side])do
   for k=1,#stroke-1 do
    local a,b=stroke[k],stroke[k+1]
    local s=bar(model,'TwinRune',pt(a,zk),pt(b,zk),.066,.022,hot,NE,glow);s:SetAttribute('TwinRune',true)
    bar(model,'TwinRuneGlow',pt(a,zk-.008),pt(b,zk-.008),.13,.012,accent,NE,{CastShadow=false,Transparency=.45})
    if k>1 then part(model,'TwinRune',Vector3.new(.066,.066,.022),CFrame.new(pt(a,zk)),hot,NE,glow):SetAttribute('TwinRune',true)end
   end
  end
 end
 -- the white "Г" stone frame round the plate (the sheet's FRONT / RUNE close-ups)
 for s=-1,1,2 do
  stone('FrameTop',Vector3.new(.34,.16,.17),at(s*.36,yc-.47,.5))
  stone('FrameSide',Vector3.new(.16,.46,.17),at(s*.58,yc-.28,.5))
  steel('FrameLow',Vector3.new(.16,.3,.15),at(s*.58,yc+.25,.49))
 end
 -- neon bar on the elbow edge, a short one under the plate
 steel('BarSocket',Vector3.new(.46,.12,.1),at(0,yc-.46,.565))
 part(model,'RuneBar',Vector3.new(.34,.055,.05),at(0,yc-.46,.6),accent,NE,glow):SetAttribute('PickPulse',true)
 part(model,'RuneBarLow',Vector3.new(.2,.05,.04),at(0,yc+.45,.535),accent,NE,glow):SetAttribute('PickPulse',true)
 -- outer side: white armour, a black block with a neon slit, the glowing ring
 stone('SideArmor',Vector3.new(.14,.36,.42),at(.7,-.62,.18),outX)
 stone('SideArmor',Vector3.new(.14,.3,.38),at(.7,-.22,.2),outX)
 steel('SideBlock',Vector3.new(.12,.5,.36),at(.69,-.36,-.27))
 part(model,'SideSlit',Vector3.new(.04,.36,.05),at(.76,-.36,-.27),accent,NE,glow)
 do
  local rc=P(.6,-.84,.06)
  local o=Vector3.new(side,0,0)
  rod(model,'WristDisc',rc,rc+o*.11,.46,shade(steelC,.06),ME,{Reflectance=.1})
  for _,r in ipairs(ring(model,'WristRing',CFrame.new(rc+o*.12)*CFrame.Angles(0,math.pi/2,0),.16,.05,.03,10,accent,NE,nil,glow))do r:SetAttribute('PickPulse',true)end
  rod(model,'WristCap',rc+o*.1,rc+o*.15,.15,rivetC,ME,small)
  part(model,'WristCore',Vector3.new(.02,.07,.07),CFrame.new(rc+o*.155),hot,NE,glow)
 end
 -- inner side: armour and the blocky thumb curling toward the palm
 stone('SideArmor',Vector3.new(.14,.34,.4),at(-.7,-.66,.2),-outX)
 steel('ThumbBase',Vector3.new(.3,.42,.42),at(-.7,-.36,-.22))
 stone('Thumb',Vector3.new(.26,.3,.34),at(-.74,-.06,-.34),-outX)
 steel('ThumbTip',Vector3.new(.24,.26,.26),at(-.66,.16,-.5)*CFrame.Angles(math.rad(-25),0,0))
 part(model,'ThumbJoint',Vector3.new(.05,.05,.03),at(-.75,-.06,-.15),rivetC,ME,small)
 -- palm: segmented black plates with bolts, a white guard block
 for ix=-1,1,2 do for iy=0,1 do
  steel('PalmPlate',Vector3.new(.55,.42,.07),at(ix*.29,-.74+iy*.46,-.5))
  part(model,'PalmBolt',Vector3.new(.05,.05,.03),at(ix*.29+.18,-.86+iy*.46,-.545),rivetC,ME,small)
 end end
 stone('PalmGuard',Vector3.new(.36,.28,.1),at(0,-.32,-.56),-Vector3.zAxis)
 -- chunky corner knobs
 for s=-1,1,2 do steel('Knob',Vector3.new(.2,.2,.2),at(s*.6,-.02,.4))end

 -- ELBOW END: the white cracked strap, a rim, blocks round the opening, exhaust tubes -------------
 stone('CuffStrap',Vector3.new(1.32,.2,1.12),at(0,-.9,.02))
 steel('CuffRim',Vector3.new(1.28,.08,1.08),at(0,-1.03,.02))
 for _,c in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}})do
  if c[2]>0 then stone('RimBlock',Vector3.new(.3,.12,.22),at(c[1]*.46,-1.08,c[2]*.4+.02),Vector3.new(0,-1,0))
  else steel('RimBlock',Vector3.new(.3,.12,.24),at(c[1]*.46,-1.08,c[2]*.4+.02))end
 end
 part(model,'CuffOpening',Vector3.new(1.04,.02,.9),at(0,-1.08,.02),dark,SP,small)
 for s=-1,1,2 do
  part(model,'Rivet',Vector3.new(.05,.05,.03),at(s*.3,-.9,.585),rivetC,ME,small)
  steel('CuffBack',Vector3.new(.5,.28,.08),at(s*.28,-.9,-.56))
 end
 -- exhaust tubes along the top (three right, four left), red-hot tips on some
 do
  local tubes=right and{-.3,0,.3}or{-.36,-.12,.12,.36}
  for k,tx in ipairs(tubes)do
   local base=P(tx,-.7,.63)
   local top=P(tx*1.15,-1.12-(k%2)*.05,.68)
   bar(model,'Tube',base,top,.13,.13,shade(steelC,.1),ME,{Reflectance=.08})
   local d=(top-base).Unit
   bar(model,'TubeBand',top-d*.16,top-d*.1,.15,.15,rivetC,ME,small)
   local red=(k%2==1)~=right
   local cap=bar(model,'TubeTip',top-d*.01,top+d*.05,.11,.11,red and tipRed or dark,red and NE or ME,glow)
   if red then cap:SetAttribute('PickPulse',true)end
  end
  local vent=part(model,'TwinVent',Vector3.new(.8,.1,.2),at(0,-1.2,.68),accent,SP,{Transparency=1,CastShadow=false})
  local pe=Instance.new('ParticleEmitter');pe.Name='TwinVentSmoke';pe.Texture='rbxasset://textures/particles/smoke_main.dds'
  pe.Rate=0;pe.Lifetime=NumberRange.new(.4,.7);pe.Speed=NumberRange.new(1.5,3);pe.SpreadAngle=Vector2.new(20,20)
  pe.EmissionDirection=Enum.NormalId.Bottom;pe.Drag=3;pe.LightEmission=.15
  pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,.7)})
  pe.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.45),NumberSequenceKeypoint.new(1,1)})
  pe.Color=ColorSequence.new(Color3.fromRGB(70,64,74),Color3.fromRGB(30,28,34));pe.Parent=vent
 end

 -- FINGERS, ACTUATORS AND CLAWS ------------------------------------------------------------------
 local FINGERS={-.47,-.16,.15,.46}               -- inner -> outer
 local LEN={1.08,1.24,1.22,1.06}
 local FAN={-.2,-.065,.065,.2}
 for i,fx in ipairs(FINGERS)do
  stone('Knuckle',Vector3.new(.27,.2,.3),at(fx,.1,.36))
  steel('Finger',Vector3.new(.27,.6,.6),at(fx,.33,.04))
  for s=-1,1,2 do steel('TubeRail',Vector3.new(.05,.24,.1),at(fx+s*.1,.28,.36))end
  local tube=part(model,'FingerTube',Vector3.new(.08,.2,.07),at(fx,.28,.37),accent,NE,glow);tube:SetAttribute('PickPulse',true)
  for _,y in ipairs({.17,.39})do steel('TubeCap',Vector3.new(.11,.03,.09),at(fx,y,.37))end
  steel('FingerPlate',Vector3.new(.25,.22,.12),at(fx,.51,.36)*CFrame.Angles(math.rad(-8),0,0))
  part(model,'FingerBolt',Vector3.new(.05,.05,.03),at(fx,.51,.43),rivetC,ME,small)
  steel('FingerUnder',Vector3.new(.25,.22,.12),at(fx,.45,-.28)*CFrame.Angles(math.rad(10),0,0))
  if i<#FINGERS then part(model,'FingerSlit',Vector3.new(.03,.34,.34),at((fx+FINGERS[i+1])/2,.35,.1),accent,NE,glow)end
  -- the outer fingers glow along their outside edge (the sheet's FRONT view)
  if i==1 or i==#FINGERS then
   local s=i==1 and -1 or 1
   part(model,'FingerSideGlow',Vector3.new(.035,.5,.3),at(fx+s*.15,.33,.08),accent,NE,glow):SetAttribute('PickPulse',true)
  end
  -- the actuator at the claw root (turns as the claw slides)
  do
   local ac=P(fx,.63,-.02)
   local X=Vector3.xAxis
   local list={}
   table.insert(list,rod(model,'Actuator',ac-X*.105,ac+X*.105,.32,shade(steelC,.08),ME,{Reflectance=.1}))
   for s=-1,1,2 do
    table.insert(list,rod(model,'ActuatorRim',ac+X*s*.1,ac+X*s*.13,.26,Color3.fromRGB(128,126,136),ME,{Reflectance=.25,CastShadow=false}))
    table.insert(list,rod(model,'ActuatorCap',ac+X*s*.125,ac+X*s*.145,.11,Color3.fromRGB(184,182,192),ME,{Reflectance=.3,CastShadow=false}))
    table.insert(list,part(model,'ActuatorBolt',Vector3.new(.03,.05,.05),CFrame.new(ac+X*s*.135+Vector3.new(0,.08,0)),dark,SP,small))
   end
   for _,p in ipairs(list)do anim(p,'TwinActuator',i*.9,ac)end
  end
  -- the talon
  local root=P(fx,.65,.02)
  local L=LEN[i]
  local N=6
  local function pos(t)return root+Vector3.new(FAN[i]*side*L*t,L*t,-.36*L*t^2.3)end
  local clawParts={}
  local function keep(p)table.insert(clawParts,p);return p end
  local last=nil
  for k=1,N do
   local t0,t1=(k-1)/N,k/N
   local a,b=pos(t0),pos(t1)
   local tm=(t0+t1)/2
   local T=(b-a).Unit
   local W=(Vector3.xAxis-T*Vector3.xAxis:Dot(T)).Unit
   local cf=CFrame.fromMatrix((a+b)/2,W,T)        -- z = W x T: the broad face looks to the back of the hand
   local w=.03+.27*(1-tm^1.9)              -- a broad talon that narrows in its last third
   local th=.14*(1-tm*.55)
   local seg=(b-a).Magnitude*1.07
   last=keep(part(model,'Claw',Vector3.new(w,seg,th),cf,shade(clawC,.06),ME,{Reflectance=.12}))
   keep(part(model,'ClawRidge',Vector3.new(w*.4,seg,.03),cf*CFrame.new(0,0,th*.5+.008),clawC:Lerp(Color3.new(1,1,1),.4),ME,{Reflectance=.2,CastShadow=false}))
   keep(part(model,'ClawBevel',Vector3.new(w*.45,seg,.025),cf*CFrame.new(0,0,-th*.5-.006),clawC:Lerp(Color3.new(0,0,0),.35),ME,small))
   for s=-1,1,2 do
    keep(part(model,'ClawEdge',Vector3.new(.04,seg,th*.7),cf*CFrame.new(s*(w*.5+.014),0,-th*.08),s==-side and hot or accent,NE,glow))
   end
   if k<N and rnd()<.6 then
    keep(part(model,'Crack',Vector3.new(.016,.08+rnd()*.12,.012),cf*CFrame.new((rnd()-.5)*w*.7,(rnd()-.5)*seg*.6,th*.5+.012)*CFrame.Angles(0,0,(rnd()-.5)*1.6),crackC,SP,small))
   end
  end
  do
   local tip=pos(1);local T=(pos(1)-pos(.96)).Unit
   local W=(Vector3.xAxis-T*Vector3.xAxis:Dot(T)).Unit
   for _,p in ipairs(spike(model,'ClawTip',tip-T*.03,T,W,.32,.11,.06,hot,NE,glow))do keep(p)end
   -- air scratch trail points on the claw tip (MiningClient.PickFX)
   local a=Instance.new('Attachment');a.Name='ClawTrailA';a.Position=last.CFrame:PointToObjectSpace(tip+T*.2);a.Parent=last
   local b=Instance.new('Attachment');b.Name='ClawTrailB';b.Position=last.CFrame:PointToObjectSpace(pos(.7));b.Parent=last
  end
  for _,p in ipairs(clawParts)do anim(p,'TwinClaw',i*.37,root);p:SetAttribute('PickAmp',(i-2.5)/1.5*side)end
 end

 -- GLOW AND IDLE FX: an accent light on the claws, a few slow sparks drifting off them -------------
 local holder=part(model,'ClawGlow',Vector3.new(1.3,1.1,.5),at(0,1.2,-.15),accent,SP,{Transparency=1,CastShadow=false})
 local l=Instance.new('PointLight');l.Name='ClawLight';l.Color=accent;l.Range=7;l.Brightness=1.2;l.Shadows=false;l.Parent=holder
 local fx=emitter(holder,'Sparkle',accent)
 if fx then
  fx.Rate=2;fx.Speed=NumberRange.new(.3,1);fx.Lifetime=NumberRange.new(.5,.9);fx.Acceleration=Vector3.new(0,1.5,0)
  fx.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,0)})
  fx.Color=ColorSequence.new(hot,accent)
 end
 local plateLight=Instance.new('PointLight');plateLight.Name='RuneLight';plateLight.Color=accent;plateLight.Range=4;plateLight.Brightness=.8;plateLight.Shadows=false
 plateLight.Parent=model:FindFirstChild('RunePlate')
end
DESIGNS.Claws=function(model,v,def,len,top)
 twinGauntlet(model,v,1)
end

-- TV-Head ("Retro Horror" concept sheet): a beaten-up CRT on a strapped black pipe.
-- Front (+Z, faces the player holding it): the evil pixel face on the curved screen inside a dark
-- stepped bezel, two knobs and a slatted vent on the right panel. Left (-X): a slatted side unit
-- glowing green inside, with the flat pick blade. Right (+X): a narrow switch box. Top: two bent
-- antennas with glowing tips. Back: a mesh grille and a slatted vent. Red and black cables loop
-- under the case and spiral down the pipe; a riveted collar on top, a riveted pommel with a green
-- glow ring at the bottom. Rust, scratches and rivets everywhere.
-- The screen (SurfaceGui "ScreenGui": Noise > Static, GhostA, GhostB, Face, FaceInspect, Scan,
-- Roll) and the moving parts (AntennaLow / AntennaHigh, Knob, PixelDrip) are driven by
-- MiningClient.PickFX. The face bitmaps are drawn from shapes once (TV_FACES) and stored as
-- merged rectangles (a few dozen Frames per face).
local TV_W,TV_H=32,24
local tvFaces=nil
local function tvFaceRects()
 if tvFaces then return tvFaces end
 local function inPoly(px,py,poly)
  local inside=false;local j=#poly
  for i=1,#poly do
   local xi,yi,xj,yj=poly[i][1],poly[i][2],poly[j][1],poly[j][2]
   if((yi>py)~=(yj>py))and(px<(xj-xi)*(py-yi)/(yj-yi)+xi)then inside=not inside end
   j=i
  end
  return inside
 end
 local function mirror(poly)local out={};for i=#poly,1,-1 do table.insert(out,{1-poly[i][1],poly[i][2]})end;return out end
 local function tri(x)x=x%1;return 1-math.abs(2*x-1)end
 -- A grin: lit between two lip curves (corners up); triangle teeth (unlit) bite in from both lips.
 local function grin(u,v,topC,topE,botC,botE,period,depth)
  local s=(u-.5)/.4
  if math.abs(s)>1 then return false end
  local top=topC-(topC-topE)*s*s
  local bot=botC-(botC-botE)*s*s
  if v<top or v>bot then return false end
  if v-top<depth*tri((u-.1)/period+.5)then return false end
  if bot-v<depth*tri((u-.1)/period)then return false end
  return true
 end
 local eyeL={{.05,.09},{.29,.21},{.48,.39},{.45,.52},{.26,.50},{.09,.30}}
 local squintL={{.05,.27},{.30,.34},{.47,.42},{.45,.49},{.25,.46},{.07,.35}}
 local wideR=mirror({{.05,.07},{.28,.16},{.47,.32},{.45,.55},{.26,.56},{.09,.36}})
 local layers={
  Normal={
   Eyes=function(u,v)return inPoly(u,v,eyeL)or inPoly(u,v,mirror(eyeL))end,
   Mouth=function(u,v)return grin(u,v,.58,.42,.95,.5,.1,.13)end,
  },
  Inspect={
   Eyes=function(u,v)
    if inPoly(u,v,squintL)then return true end
    if inPoly(u,v,wideR)then return(u-.69)^2*1.8+(v-.42)^2>.005 end -- the pupil stays dark
    return false
   end,
   Mouth=function(u,v)return grin(u,v,.6,.5,.95,.62,.125,.17)end,
  },
 }
 -- Rows of lit cells -> horizontal runs -> runs merged downwards into rectangles {x,y,w,h}.
 local function rects(lit)
  local out,open={},{}
  for y=0,TV_H-1 do
   local runs={}
   local x=0
   while x<TV_W do
    if lit((x+.5)/TV_W,(y+.5)/TV_H)then
     local x0=x
     while x<TV_W and lit((x+.5)/TV_W,(y+.5)/TV_H)do x+=1 end
     table.insert(runs,{x0,x-x0})
    else x+=1 end
   end
   local nextOpen={}
   for _,r in ipairs(runs)do
    local key=r[1]..':'..r[2]
    local rect=open[key]
    if rect then rect[4]+=1 else rect={r[1],y,r[2],1};table.insert(out,rect)end
    nextOpen[key]=rect
   end
   open=nextOpen
  end
  return out
 end
 tvFaces={}
 for name,layer in pairs(layers)do tvFaces[name]={Eyes=rects(layer.Eyes),Mouth=rects(layer.Mouth)}end
 return tvFaces
end
Models.TVFaceRects=tvFaceRects

local function tvFrame(parent,name,x,y,w,h,color,z,transparency)
 local f=Instance.new('Frame');f.Name=name;f.BorderSizePixel=0;f.BackgroundColor3=color
 f.BackgroundTransparency=transparency or 0;f.Position=UDim2.fromScale(x,y);f.Size=UDim2.fromScale(w,h);f.ZIndex=z or 1
 f.Parent=parent;return f
end
-- One face (eyes + mouth) as a full-size transparent holder of cell rectangles.
local function tvFace(parent,name,layers,color,z,visible)
 local holder=tvFrame(parent,name,0,0,1,1,color,z,1);holder.Visible=visible~=false
 for _,part in ipairs({'Eyes','Mouth'})do
  local group=tvFrame(holder,part,0,0,1,1,color,z,1)
  for _,r in ipairs(layers[part])do tvFrame(group,'Px',r[1]/TV_W,r[2]/TV_H,r[3]/TV_W,r[4]/TV_H,color,z)end
 end
 return holder
end
local function tvScreen(screen,green)
 local faces=tvFaceRects()
 local g=Instance.new('SurfaceGui');g.Name='ScreenGui';g.Face=Enum.NormalId.Front
 g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=64;g.LightInfluence=0;g.Brightness=2
 g.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;g:SetAttribute('NoTranslate',true);g.Parent=screen
 local noise=tvFrame(g,'Noise',0,0,1,1,Color3.fromRGB(14,34,18),1)
 noise.ClipsDescendants=true
 local grad=Instance.new('UIGradient');grad.Color=ColorSequence.new(Color3.fromRGB(70,120,70),Color3.fromRGB(26,60,30));grad.Rotation=90;grad.Parent=noise
 local edge=Instance.new('UIStroke');edge.Color=Color3.fromRGB(4,10,6);edge.Thickness=5;edge.Transparency=.25
 edge.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;edge.Parent=noise
 -- Static: fixed grain (dim) and blocks PickFX moves around.
 local static=tvFrame(noise,'Static',0,0,1,1,green,2,1)
 for i=1,14 do
  local f=tvFrame(static,'Block',((i*.37)%1),((i*.61)%1),.04+(i%3)*.03,.015,green:Lerp(Color3.new(1,1,1),.5),2,.7)
  f.Visible=i%2==0
 end
 tvFace(noise,'GhostA',faces.Normal,Color3.fromRGB(255,70,210),3,false)
 tvFace(noise,'GhostB',faces.Normal,Color3.fromRGB(80,220,255),3,false)
 tvFace(noise,'Face',faces.Normal,green,4,true)
 tvFace(noise,'FaceInspect',faces.Inspect,green,4,false)
 local scan=tvFrame(noise,'Scan',0,0,1,1,Color3.new(0,0,0),5,1)
 for i=0,11 do tvFrame(scan,'Line',0,(i+.6)/12,1,.012,Color3.new(0,0,0),5,.55)end
 tvFrame(noise,'Roll',0,.2,1,.07,Color3.fromRGB(200,255,200),6,.88)
 return g
end

DESIGNS.TV=function(model,v,def,len,top)
 local case=rgb(v.Head)                      -- worn brown-grey steel
 local green=rgb(v.Accent)                   -- CRT lime
 local dark=rgb(v.Trim)                      -- gunmetal
 local pipe=rgb(v.Shaft)                     -- black pipe
 local edge=case:Lerp(Color3.fromRGB(206,198,186),.35) -- rubbed-off edges
 local inner=case:Lerp(Color3.new(0,0,0),.32)
 local steel=Color3.fromRGB(150,144,136)
 local strap=Color3.fromRGB(124,120,114)
 local rust=Color3.fromRGB(124,70,40)
 local red=Color3.fromRGB(178,32,28)
 local black=Color3.fromRGB(20,20,22)
 local CM,MT,PL,NE=Enum.Material.CorrodedMetal,Enum.Material.Metal,Enum.Material.Plastic,Enum.Material.Neon
 local glow={CastShadow=false}
 local W,H,D=2.5,1.62,1.3
 local zf=D*.5
 local c=CFrame.new(0,len*.5-.05,0)          -- the CRT's centre (handle centre = origin)
 local function at(x,y,z)return c*CFrame.new(x,y,z)end
 local function rivet(cf,d)return ball(model,'Rivet',d or .075,cf,steel,MT)end

 -- CASE ---------------------------------------------------------------------------------------
 part(model,'TVCase',Vector3.new(W,H,D),c,case,CM)
 for _,s in ipairs({1,-1})do -- front and back rims, rubbed light
  local z=s*zf
  part(model,'CaseRim',Vector3.new(W+.06,.14,.12),at(0,H*.5-.05,z),edge,MT)
  part(model,'CaseRim',Vector3.new(W+.06,.14,.12),at(0,-H*.5+.05,z),edge,MT)
  part(model,'CaseRim',Vector3.new(.14,H-.2,.12),at(-W*.5+.05,0,z),edge,MT)
  part(model,'CaseRim',Vector3.new(.14,H-.2,.12),at(W*.5-.05,0,z),edge,MT)
 end
 for _,x in ipairs({-1,1})do for _,y in ipairs({-1,1})do
  part(model,'CaseEdge',Vector3.new(.1,.1,D-.1),at(x*(W*.5-.02),y*(H*.5-.02),0),edge:Lerp(case,.4),MT)
 end end
 for i=0,7 do
  local x=-1.05+i*.3
  rivet(at(x,H*.5-.05,zf+.07));rivet(at(x,-H*.5+.05,zf+.07))
 end
 for _,y in ipairs({-.42,.42})do rivet(at(-W*.5+.05,y,zf+.07));rivet(at(W*.5-.05,y,zf+.07))end

 -- SCREEN: dark stepped bezel, recessed CRT with the face, a glass pane and a soft glow --------
 local bx,bw,bh=-.36,1.54,1.24
 local bezel=Color3.fromRGB(46,44,46)
 part(model,'Bezel',Vector3.new(bw,.11,.1),at(bx,bh*.5-.055,zf+.03),bezel,MT)
 part(model,'Bezel',Vector3.new(bw,.11,.1),at(bx,-bh*.5+.055,zf+.03),bezel,MT)
 part(model,'Bezel',Vector3.new(.11,bh-.2,.1),at(bx-bw*.5+.055,0,zf+.03),bezel,MT)
 part(model,'Bezel',Vector3.new(.11,bh-.2,.1),at(bx+bw*.5-.055,0,zf+.03),bezel,MT)
 for _,sx in ipairs({-1,1})do for _,sy in ipairs({-1,1})do -- voxel-rounded inner corners
  part(model,'BezelCorner',Vector3.new(.1,.1,.09),at(bx+sx*(bw*.5-.16),sy*(bh*.5-.16),zf+.025),bezel,MT)
 end end
 local screen=part(model,'Screen',Vector3.new(bw-.18,bh-.18,.04),at(bx,0,zf+.01),Color3.fromRGB(14,30,16),Enum.Material.SmoothPlastic,glow)
 tvScreen(screen,green)
 local light=Instance.new('SurfaceLight');light.Name='ScreenGlow';light.Face=Enum.NormalId.Front;light.Color=green
 light.Range=7;light.Brightness=1.2;light.Angle=120;light.Shadows=false;light.Parent=screen
 part(model,'ScreenGlass',Vector3.new(bw-.18,bh-.18,.02),at(bx,0,zf+.045),Color3.fromRGB(200,255,210),Enum.Material.Glass,{Transparency=.88,Reflectance=.3,CastShadow=false})
 part(model,'ScreenGlare',Vector3.new(.5,.06,.01),at(bx-.38,.4,zf+.06)*CFrame.Angles(0,0,math.rad(12)),Color3.new(1,1,1),Enum.Material.SmoothPlastic,{Transparency=.82,CastShadow=false})

 -- RIGHT CONTROL PANEL: two knobs and a vent ----------------------------------------------------
 local px=.81
 part(model,'ControlPanel',Vector3.new(.6,1.24,.04),at(px,0,zf+.01),inner,CM)
 part(model,'PanelRim',Vector3.new(.06,1.24,.07),at(px-.33,0,zf+.03),bezel,MT)
 for i,y in ipairs({.31,-.09})do
  local kc=at(px,y,0)
  cylZ(model,'KnobRing',.05,.42,kc*CFrame.new(0,0,zf+.04),bezel,MT)
  local knobPos=kc*CFrame.new(0,0,zf+.12)
  anim(cylZ(model,'Knob',.13,.32,knobPos,black,PL),'Knob',i*1.3,knobPos.Position)
  for k=0,3 do -- grip ridges
   local a=k/4*math.pi*2+math.pi/4
   anim(part(model,'KnobGrip',Vector3.new(.05,.05,.12),knobPos*CFrame.new(math.cos(a)*.16,math.sin(a)*.16,0),black,PL),'Knob',i*1.3,knobPos.Position)
  end
  anim(part(model,'KnobPointer',Vector3.new(.05,.26,.03),knobPos*CFrame.new(0,0,.075)*CFrame.Angles(0,0,math.rad(i==1 and 35 or -50)),Color3.fromRGB(226,222,212),PL),'Knob',i*1.3,knobPos.Position)
 end
 part(model,'VentPlate',Vector3.new(.48,.28,.03),at(px,-.46,zf+.025),black,MT)
 for i=0,4 do part(model,'VentSlat',Vector3.new(.44,.032,.05),at(px,-.36-i*.052,zf+.045),edge,MT)end

 -- LEFT SIDE UNIT with the pick blade ---------------------------------------------------------
 local ux=-W*.5-.18
 part(model,'SideUnit',Vector3.new(.36,1.0,.92),at(ux,.1,-.02),inner,CM)
 part(model,'SideUnitRim',Vector3.new(.38,.08,.94),at(ux,.6,-.02),edge,MT)
 part(model,'SideUnitRim',Vector3.new(.38,.08,.94),at(ux,-.4,-.02),edge,MT)
 part(model,'SideGlow',Vector3.new(.02,.66,.66),at(ux-.17,.1,-.02),green,NE,{CastShadow=false,Transparency=.15}):SetAttribute('PickPulse',true)
 for i=0,4 do part(model,'SideSlat',Vector3.new(.05,.065,.74),at(ux-.19,.36-i*.13,-.02),dark,MT)end
 part(model,'SideGlow',Vector3.new(.24,.62,.02),at(ux,.1,.45),green,NE,{CastShadow=false,Transparency=.15}):SetAttribute('PickPulse',true)
 for i=-1,1 do part(model,'SideSlat',Vector3.new(.055,.66,.04),at(ux+i*.085,.1,.47),dark,MT)end
 for _,y in ipairs({.5,-.3})do for _,z in ipairs({.36,-.4})do rivet(at(ux-.19,y,z),.06)end end
 -- The blade: a flat steel point out of the unit, tilted up, in voxel steps with a green edge.
 local bc=at(ux-.18,.3,.02)*CFrame.Angles(0,0,math.rad(-24))*CFrame.Angles(math.rad(58),0,0) -- broad face turned to the front, as on the sheet
 local bladeCol=Color3.fromRGB(140,134,126)
 part(model,'BladeMount',Vector3.new(.22,.3,.74),bc*CFrame.new(-.11,0,0),dark,MT)
 rivet(bc*CFrame.new(-.11,.16,.18),.06);rivet(bc*CFrame.new(-.11,.16,-.18),.06)
 local widths={.84,.74,.62,.5}
 for i,w in ipairs(widths)do
  local x=-.22-(i-.5)*.2
  part(model,'Blade',Vector3.new(.205,.15-i*.008,w),bc*CFrame.new(x,0,0),bladeCol:Lerp(edge,i*.08),MT)
  part(model,'BladeEdge',Vector3.new(.205,.035,.03),bc*CFrame.new(x,-.05,w*.5),green,NE,glow)
 end
 local tipX,tipL,tipW,tipT=-1.02,.4,.5,.13
 -- two right-triangle wedges lying flat (thickness along Y) meet in the point at -X
 wedge(model,'BladeTip',Vector3.new(tipT,tipW*.5,tipL),bc*CFrame.fromMatrix(Vector3.new(tipX-tipL*.5,0,tipW*.25),Vector3.yAxis,Vector3.zAxis,Vector3.xAxis),edge,MT)
 wedge(model,'BladeTip',Vector3.new(tipT,tipW*.5,tipL),bc*CFrame.fromMatrix(Vector3.new(tipX-tipL*.5,0,-tipW*.25),-Vector3.yAxis,-Vector3.zAxis,Vector3.xAxis),edge,MT)
 part(model,'Scratch',Vector3.new(.5,.01,.02),bc*CFrame.new(-.6,.075,.08)*CFrame.Angles(0,.3,0),Color3.fromRGB(214,210,204),MT)
 part(model,'Scratch',Vector3.new(.34,.01,.02),bc*CFrame.new(-.75,.072,-.12)*CFrame.Angles(0,-.5,0),Color3.fromRGB(214,210,204),MT)

 -- RIGHT SWITCH BOX ---------------------------------------------------------------------------
 local rx=W*.5+.1
 part(model,'SwitchBox',Vector3.new(.2,.66,.62),at(rx,.05,0),inner,CM)
 part(model,'SwitchBoxRim',Vector3.new(.22,.06,.64),at(rx,.36,0),edge,MT)
 cylZ(model,'SwitchBase',.05,.14,at(rx+.11,.16,.12)*CFrame.Angles(0,math.pi/2,0),bezel,MT)
 part(model,'Switch',Vector3.new(.16,.05,.05),at(rx+.17,.18,.12)*CFrame.Angles(0,0,math.rad(25)),steel,MT)
 ball(model,'SwitchLED',.07,at(rx+.1,-.12,.18),green,NE,glow):SetAttribute('PickPulse',true)
 rivet(at(rx+.1,-.18,-.18),.06);rivet(at(rx+.1,.26,-.18),.06)

 -- ANTENNAS: bent, alive; the tips glow --------------------------------------------------------
 local rodCol=Color3.fromRGB(158,150,140)
 local antennas={
  {x=-.5,phase=0,path={Vector3.new(0,.3,0),Vector3.new(-.3,.26,0),Vector3.new(-.12,.22,0)}},
  {x=.28,phase=1.7,path={Vector3.new(0,.22,0),Vector3.new(.3,.34,0),Vector3.new(.2,.06,0)}},
 }
 for _,a in ipairs(antennas)do
  part(model,'AntennaMount',Vector3.new(.38,.14,.34),at(a.x,H*.5+.07,0),dark,MT)
  part(model,'AntennaMount',Vector3.new(.22,.1,.22),at(a.x,H*.5+.19,0),steel,MT)
  rivet(at(a.x-.14,H*.5+.07,.18),.05);rivet(at(a.x+.14,H*.5+.07,.18),.05)
  local base=(at(a.x,H*.5+.24,0)).Position
  local p=base
  for i,step in ipairs(a.path)do
   local q=p+step
   local kind=i==1 and'AntennaLow'or'AntennaHigh'
   anim(rod(model,'Antenna',p,q,.065,rodCol,MT),kind,a.phase,base)
   anim(ball(model,'AntennaJoint',i==1 and .1 or .09,CFrame.new(q),dark,MT),kind,a.phase,base)
   p=q
  end
  anim(ball(model,'AntennaTip',.16,CFrame.new(p),green,NE,glow),'AntennaHigh',a.phase,base)
 end

 -- BOTTOM: plate, feet, neck and the looping cables --------------------------------------------
 part(model,'CaseBottom',Vector3.new(W-.2,.1,D-.12),at(0,-H*.5-.05,0),inner,CM)
 for _,x in ipairs({-.95,.95})do for _,z in ipairs({-.35,.35})do part(model,'Foot',Vector3.new(.22,.1,.22),at(x,-H*.5-.13,z),dark,MT)end end
 part(model,'Neck',Vector3.new(.5,.2,.5),at(0,-H*.5-.18,0),dark,MT)
 for _,s in ipairs({-1,1})do part(model,'Bracket',Vector3.new(.07,.34,.42),at(s*.3,-H*.5-.14,0)*CFrame.Angles(0,0,s*.55),dark,MT)end
 local function cable(name,points,d,color,segments)
  -- cubic Bezier through 4 control points (in CRT space), built from short rods
  local a,b,cc,dd=points[1],points[2],points[3],points[4]
  local function bez(t)local u=1-t;return a*u*u*u+b*3*u*u*t+cc*3*u*t*t+dd*t*t*t end
  local prev=(c*CFrame.new(bez(0))).Position
  for i=1,segments do
   local q=(c*CFrame.new(bez(i/segments))).Position
   local dir=(q-prev).Unit
   rod(model,name,prev-dir*d*.4,q+dir*d*.4,d,color,PL)
   prev=q
  end
  part(model,'CablePlug',Vector3.new(.13,.13,.13),c*CFrame.new(a),black,MT)
  part(model,'CablePlug',Vector3.new(.13,.13,.13),c*CFrame.new(dd),black,MT)
 end
 cable('Cable',{Vector3.new(-1.44,-.42,.22),Vector3.new(-1.62,-1.15,.3),Vector3.new(-1.05,-1.25,.32),Vector3.new(-.9,-.86,.3)},.09,red,6)
 cable('Cable',{Vector3.new(-1.36,-.42,-.12),Vector3.new(-1.8,-1.05,-.08),Vector3.new(-.95,-1.4,-.05),Vector3.new(-.62,-.86,-.06)},.1,black,6)
 cable('Cable',{Vector3.new(.85,-.86,.26),Vector3.new(1.05,-1.35,.32),Vector3.new(1.7,-1.0,.25),Vector3.new(1.38,-.28,.16)},.09,red,6)
 cable('Cable',{Vector3.new(-.28,-.86,.32),Vector3.new(-.55,-1.2,.42),Vector3.new(-.4,-1.42,.3),Vector3.new(-.26,-1.4,.12)},.08,red,4)

 -- BACK: a mesh grille and a slatted vent --------------------------------------------------------
 local zb=-zf-.07
 part(model,'BackPanel',Vector3.new(2.16,1.28,.12),at(0,0,-zf-.02),inner,CM)
 part(model,'GrilleFrame',Vector3.new(.92,.94,.04),at(.55,0,zb),bezel,MT)
 for i=-2,2 do
  part(model,'Grille',Vector3.new(.03,.84,.03),at(.55+i*.16,0,zb-.03),edge,MT)
  part(model,'Grille',Vector3.new(.82,.03,.03),at(.55,i*.16,zb-.035),edge,MT)
 end
 part(model,'VentFrame',Vector3.new(.86,.94,.04),at(-.5,0,zb),bezel,MT)
 for i=0,6 do part(model,'BackSlat',Vector3.new(.7,.045,.06),at(-.5,.36-i*.12,zb-.03),edge,MT)end
 for _,x in ipairs({-1.0,0,1.0})do rivet(at(x,.58,zb-.02),.06);rivet(at(x,-.58,zb-.02),.06)end

 -- WEAR: rust patches and scratches --------------------------------------------------------------
 local wear={
  {'Rust',Vector3.new(.42,.012,.3),at(-.7,H*.5+.006,.12)},{'Rust',Vector3.new(.3,.012,.22),at(.75,H*.5+.006,-.25)},
  {'Rust',Vector3.new(.012,.36,.28),at(W*.5+.006,-.45,-.25)},{'Rust',Vector3.new(.012,.26,.4),at(ux-.181,-.28,.1)},
  {'Rust',Vector3.new(.3,.2,.012),at(.75,.42,-zf-.085)},{'Rust',Vector3.new(.22,.12,.012),at(.95,-.62,zf+.065)},
  {'Rust',Vector3.new(.2,.08,.012),at(-1.0,-.74,zf+.065)},
  {'Scratch',Vector3.new(.6,.012,.025),at(-.1,H*.5+.007,.25)*CFrame.Angles(0,.4,0)},
  {'Scratch',Vector3.new(.012,.025,.5),at(-W*.5-.001,.0,.1)*CFrame.Angles(.6,0,0)},
  {'Scratch',Vector3.new(.45,.025,.012),at(.2,-.55,-zf-.085)*CFrame.Angles(0,0,.35)},
  {'Scratch',Vector3.new(.4,.025,.012),at(-.9,.73,zf+.065)*CFrame.Angles(0,0,-.2)},
 }
 for _,w in ipairs(wear)do
  part(model,w[1],w[2],w[3],w[1]=='Rust'and rust or Color3.fromRGB(196,190,180),w[1]=='Rust'and CM or MT,{CastShadow=false})
 end

 -- COLLAR, PIPE, STRAPS, SPIRAL CABLES, POMMEL --------------------------------------------------
 local collarY=len*.5-1.32
 part(model,'Collar',Vector3.new(.6,.45,.6),CFrame.new(0,collarY,0),strap:Lerp(case,.4),MT)
 part(model,'CollarBand',Vector3.new(.64,.08,.64),CFrame.new(0,collarY+.2,0),dark,MT)
 part(model,'CollarBand',Vector3.new(.64,.08,.64),CFrame.new(0,collarY-.2,0),dark,MT)
 for _,f in ipairs({Vector3.new(0,0,1),Vector3.new(1,0,0),Vector3.new(0,0,-1),Vector3.new(-1,0,0)})do
  local side=Vector3.new(f.Z,0,-f.X)
  rivet(CFrame.new(f*.31+side*.16+Vector3.new(0,collarY+.04,0)),.07)
 end
 part(model,'CollarLED',Vector3.new(.12,.06,.02),CFrame.new(0,collarY-.1,.31),green,NE,glow):SetAttribute('PickPulse',true)
 local pipeTop,pipeBottom=collarY-.22,-len*.5+.1
 cylY(model,'Pipe',pipeTop-pipeBottom,.42,CFrame.new(0,(pipeTop+pipeBottom)*.5,0),pipe,MT)
 for i,y in ipairs({pipeTop-.2,pipeTop-.58,pipeTop-.96,pipeTop-1.34,pipeTop-1.72,pipeBottom+.36})do
  cylY(model,'Strap',.13,.47,CFrame.new(0,y,0)*CFrame.Angles(0,i*1.05,0)*CFrame.Angles(math.rad(16),0,0),strap,MT)
 end
 local function helix(name,color,d,turns,phase,y0,y1,segments)
  local prev
  for i=0,segments do
   local t=i/segments
   local a=phase+t*turns*math.pi*2
   local q=Vector3.new(math.cos(a)*.235,y0+(y1-y0)*t,math.sin(a)*.235)
   if prev then local dir=(q-prev).Unit;rod(model,name,prev-dir*d*.3,q+dir*d*.3,d,color,PL)end
   prev=q
  end
 end
 helix('SpiralCable',red,.08,1.6,.6,pipeTop+.05,pipeBottom+.15,12)
 helix('SpiralCable',black,.085,1.15,.6+math.pi,pipeTop+.05,pipeBottom+.45,9)
 local py=-len*.5-.1
 part(model,'PommelTop',Vector3.new(.56,.08,.56),CFrame.new(0,py+.06,0),dark,MT)
 part(model,'Pommel',Vector3.new(.66,.32,.66),CFrame.new(0,py-.14,0),strap:Lerp(case,.4),MT)
 for _,f in ipairs({Vector3.new(0,0,1),Vector3.new(1,0,0),Vector3.new(0,0,-1),Vector3.new(-1,0,0)})do
  local side=Vector3.new(f.Z,0,-f.X)
  rivet(CFrame.new(f*.34+Vector3.new(0,py-.12,0)),.08)
 end
 part(model,'PommelGlow',Vector3.new(.7,.06,.7),CFrame.new(0,py-.33,0),green,NE,{CastShadow=false,Transparency=.05}):SetAttribute('PickPulse',true)
 part(model,'PommelBase',Vector3.new(.58,.1,.58),CFrame.new(0,py-.41,0),dark,MT)
 part(model,'PommelFoot',Vector3.new(.42,.05,.42),CFrame.new(0,py-.48,0),inner,MT)
 part(model,'Rust',Vector3.new(.3,.14,.012),CFrame.new(-.1,py-.16,.336),rust,CM,{CastShadow=false})

 -- IDLE FX: green pixels dripping off the case and the blade, faint specks around the screen ---
 local drips={at(-2.0,.02,.12),at(-2.35,.15,-.1),at(-1.1,-.92,.3),at(.95,-.92,.22),at(ux,-.48,.15),at(.45,-.92,-.32)}
 for i,cf in ipairs(drips)do
  local d=part(model,'PixelDrip',Vector3.one*(.07+(i%3)*.02),cf,green,NE,{CastShadow=false})
  d:SetAttribute('PickDrip',true);anim(d,'PixelDrip',i*.17)
 end
 local holder=part(model,'Pixels',Vector3.new(1.6,1.2,.3),at(bx,0,zf+.3),green,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
 local fx=emitter(holder,'Sparkle',green);if fx then fx.Rate=1.5 end
 -- On the back: higher and further out, the head beside the head (MiningModels.MountJoint).
 model:SetAttribute('BackC0',CFrame.new(1,0,.25))
 return (bc*CFrame.new(tipX-tipL,0,0)).Position,at(rx+.12,0,0).Position
end

-- Polish shared by every design: a pommel with a glowing gem, neon inlays along the shaft
-- (Epic+), a rarity aura (sparkles from Rare, a light from Legendary) and, for Mythic pieces,
-- three gems orbiting the head. Gloves (the Twin Claws pair) keep their own look.
local RARITY_RANK={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6}
local function polish(model,v,def,len,top)
 if v.Grip=='Glove'or v.Polish==false then return end -- gloves and TV-Head keep their own look
 local rank=RARITY_RANK[def.Rarity or'Common']or 1
 local accent=rgb(v.Accent or v.Trim or def.Color,def.Color)
 local glowColor=rgb(def.Color,v.Head)
 local metal=Color3.fromRGB(196,200,210)
 local bottom=-len*.5
 ball(model,'PommelCap',.56,CFrame.new(0,bottom-.02,0),metal,Enum.Material.Metal,{Reflectance=.3})
 local gem=ball(model,'PommelGem',.34,CFrame.new(0,bottom-.28,0),rank>=3 and glowColor or accent,rank>=3 and Enum.Material.Neon or Enum.Material.Glass,{CastShadow=false})
 if rank>=4 then gem:SetAttribute('PickPulse',true)end
 if rank>=4 then
  for side=-1,1,2 do
   local inlay=part(model,'ShaftInlay',Vector3.new(.06,len*.42,.06),CFrame.new(side*.17,-len*.12,.16),accent,Enum.Material.Neon,{CastShadow=false})
   inlay:SetAttribute('PickPulse',true)
  end
 end
 if rank>=3 then
  local holder=part(model,'Aura',Vector3.new(1.4,1.4,1.4),top*CFrame.new(0,.6,0),glowColor,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
  local e=emitter(holder,rank>=6 and'Void'or'Sparkle',glowColor:Lerp(Color3.new(1,1,1),.25))
  if e then e.Rate=rank>=5 and 5 or 2.5 end
  if rank>=5 then
   local l=Instance.new('PointLight');l.Color=glowColor;l.Range=6;l.Brightness=.9;l.Shadows=false;l.Parent=holder
  end
 end
 if rank>=6 then
  local center=top*CFrame.new(0,.7,0)
  for i=0,2 do
   local a=i/3*math.pi*2
   local g=part(model,'OrbitGem',Vector3.new(.22,.36,.22),center*CFrame.new(math.cos(a)*1.6,math.sin(a*2)*.25,math.sin(a)*1.6)*CFrame.Angles(0,a,math.rad(45)),
    i==1 and glowColor or accent,Enum.Material.Neon,{CastShadow=false})
   anim(g,'Orbit',i/3,center.Position)
  end
 end
end

function Models.Pickaxe(def,level)
 local v=def.Visual or{}
 local model=Instance.new('Model');model.Name='Pickaxe'
 local len=v.Length or 4.2
 local kind=DESIGNS[v.Kind or'Classic']and(v.Kind or'Classic')or'Classic'
 local handle=part(model,'Handle',Vector3.new(.32,len,.32),CFrame.identity,rgb(v.Shaft,{120,82,48}),material(v.ShaftMaterial or'Wood'),{Massless=true})
 model.PrimaryPart=handle
 model:SetAttribute('Kind',kind);model:SetAttribute('Theme',def.Theme or'Wood');model:SetAttribute('Level',level)
 if v.Grip then model:SetAttribute('Grip',v.Grip)end
 local top=CFrame.new(0,len*.5-.2,0)
 local a,b=DESIGNS[kind](model,v,def,len,top)
 if a and b then trailPoints(handle,a,b)end
 polish(model,v,def,len,top)
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA('BasePart')then
   d.Massless=true;d:SetAttribute('PickaxeLevel',level)
   if d~=handle and d:GetAttribute('PickAnim')then d:SetAttribute('PickBase',handle.CFrame:ToObjectSpace(d.CFrame))end
  end
 end
 return model
end
-- Second hand of a paired pickaxe (Twin Claws): the left gauntlet (rune 左, violet accents).
function Models.PickaxeOffhand(def,level)
 local v=def.Visual or{}
 if v.Kind~='Claws'then return nil end
 local model=Instance.new('Model');model.Name='PickaxeOffhand'
 local handle=part(model,'Handle',Vector3.new(.9,.8,.8),CFrame.identity,rgb(v.Shaft),Enum.Material.Metal,{Massless=true})
 model.PrimaryPart=handle
 model:SetAttribute('Kind','Claws');model:SetAttribute('Theme',def.Theme or'Claws');model:SetAttribute('Level',level);model:SetAttribute('Grip','Glove')
 twinGauntlet(model,v,-1)
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA('BasePart')then
   d.Massless=true;d:SetAttribute('PickaxeLevel',level)
   if d~=handle and d:GetAttribute('PickAnim')then d:SetAttribute('PickBase',handle.CFrame:ToObjectSpace(d.CFrame))end
  end
 end
 return model
end

-- TRAINING WEIGHT ------------------------------------------------------------------------------
-- Model with Handle (the bar the hands hold, along X).
function Models.Weight(def,level)
 local v=def.Visual or{}
 local model=Instance.new('Model');model.Name='TrainingWeight'
 local main=rgb(def.Color);local mat=material(v.Material or'Metal')
 local trim=rgb(v.Trim,{40,44,50})
 local shape=v.Shape or'Dumbbell'
 local handle=part(model,'Handle',Vector3.new(2.2,.26,.26),CFrame.identity,Color3.fromRGB(190,196,204),Enum.Material.Metal,{Massless=true})
 model.PrimaryPart=handle
 if shape=='Dumbbell'then
  for s=-1,1,2 do part(model,'Plate',Vector3.new(.5,1.15,1.15),CFrame.new(s*1.05,0,0),main,mat,{Massless=true,Shape=Enum.PartType.Cylinder})end
 elseif shape=='Kettlebell'then
  handle.Size=Vector3.new(1.3,.26,.26)
  part(model,'Bell',Vector3.new(1.9,1.9,1.9),CFrame.new(0,-1.25,0),main,mat,{Massless=true,Shape=Enum.PartType.Ball})
  for s=-1,1,2 do part(model,'Horn',Vector3.new(.26,.9,.26),CFrame.new(s*.6,-.4,0),main,mat,{Massless=true})end
 elseif shape=='Barbell'then
  handle.Size=Vector3.new(4.2,.24,.24)
  for s=-1,1,2 do
   part(model,'Plate',Vector3.new(.42,1.9,1.9),CFrame.new(s*1.75,0,0),main,mat,{Massless=true,Shape=Enum.PartType.Cylinder})
   part(model,'Plate',Vector3.new(.32,1.45,1.45),CFrame.new(s*1.4,0,0),trim,mat,{Massless=true,Shape=Enum.PartType.Cylinder})
  end
 elseif shape=='Block'then
  handle.Size=Vector3.new(2.6,.26,.26)
  part(model,'Block',Vector3.new(2.3,1.5,1.5),CFrame.new(0,-1.0,0),main,mat,{Massless=true})
  for s=-1,1,2 do part(model,'Post',Vector3.new(.24,.8,.24),CFrame.new(s*1.0,-.45,0),trim,Enum.Material.Metal,{Massless=true})end
 elseif shape=='Orb'then
  handle.Size=Vector3.new(2.4,.26,.26)
  local orb=part(model,'Orb',Vector3.new(2.1,2.1,2.1),CFrame.new(0,-1.3,0),main,mat,{Massless=true,Shape=Enum.PartType.Ball,Transparency=v.Transparency or 0})
  for s=-1,1,2 do part(model,'Post',Vector3.new(.22,.9,.22),CFrame.new(s*1.05,-.5,0),trim,Enum.Material.Metal,{Massless=true})end
  if v.Ring then
   part(model,'Ring',Vector3.new(.18,2.9,2.9),orb.CFrame*CFrame.Angles(0,0,math.rad(70)),rgb(v.Ring),Enum.Material.Neon,{Massless=true,Shape=Enum.PartType.Cylinder,Transparency=.2,CastShadow=false})
  end
  if v.Glow then local l=Instance.new('PointLight');l.Color=rgb(v.Glow);l.Range=8;l.Brightness=1.6;l.Shadows=false;l.Parent=orb end
 end
 if v.FX then
  local holder=part(model,'WeightFX',Vector3.new(2,2,2),CFrame.new(0,-1,0),main,Enum.Material.SmoothPlastic,{Transparency=1,Massless=true,CastShadow=false})
  emitter(holder,v.FX,v.Glow and rgb(v.Glow) or main)
 end
 return model
end

-- Place a built model (anchored parts, relative to its PrimaryPart at identity) at cf.
function Models.Place(model,cf)
 model:PivotTo(cf);return model
end

-- Weld every part of a model to its PrimaryPart and unanchor (for attaching to a character).
-- The joints are explicit Welds ("PickWeld", C0 = the part's offset from the root): the offset is
-- a stored number, identical on every peer, never captured from wherever the parts happen to be
-- when the joint switches on (as a WeldConstraint would). A second call replaces the joints.
-- Animated pickaxe parts (PickAnim) get a Motor6D "PickJoint" instead, pivoting at PickJoint (a
-- model-space point; default the part's centre) with model-aligned axes, so clients can move
-- them through Motor6D.Transform (MiningClient.PickFX).
function Models.WeldToSelf(model)
 local root=model.PrimaryPart
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA('BasePart')then
   d.Anchored=false;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true
   if d~=root then
    for _,j in ipairs(d:GetChildren())do if j:IsA('JointInstance')or j:IsA('WeldConstraint')then j:Destroy()end end
    if d:GetAttribute('PickAnim')then
     local joint=d:GetAttribute('PickJoint')
     local pivot=root.CFrame*CFrame.new(typeof(joint)=='Vector3'and joint or root.CFrame:PointToObjectSpace(d.CFrame.Position))
     local m=Instance.new('Motor6D');m.Name='PickJoint'
     m.C0=root.CFrame:ToObjectSpace(pivot);m.C1=d.CFrame:ToObjectSpace(pivot)
     m.Part0=root;m.Part1=d;m.Parent=d
    else
     local w=Instance.new('Weld');w.Name='PickWeld'
     w.C0=root.CFrame:ToObjectSpace(d.CFrame);w.C1=CFrame.identity
     w.Part0=root;w.Part1=d;w.Parent=d
    end
   end
  end
 end
 return model
end

-- HELD MOUNTS -------------------------------------------------------------------------------------
-- Where a held pickaxe sits on a character. Hand / Glove reproduce the engine's own tool grip
-- (GripAttachment * Tool.Grip:Inverse(), the old hand mount exactly), so every swing pose still
-- fits and scaled / Rthro grip attachments are followed; Back hangs it across the back.
-- The server (MiningWorld) welds the visible model straight to the limb; the inventory Tool is only
-- a hotbar entry. The client predicts a re-mount with the same numbers (MiningClient.Tool).
Models.ToolGrip={Pick=CFrame.new(0,-1.4,.1),Glove=CFrame.Angles(math.rad(90),0,0)*CFrame.new(0,0,.05)}
Models.Mounts={
 Hand={Limb={'RightHand','Right Arm'},Attachment='RightGripAttachment',Grip='Pick'},
 Glove={Limb={'RightHand','Right Arm'},Attachment='RightGripAttachment',Grip='Glove'},
 GloveL={Limb={'LeftHand','Left Arm'},Attachment='LeftGripAttachment',Grip='Glove'},
 Back={Limb={'UpperTorso','Torso'},C0=CFrame.new(0,.1,.78)*CFrame.Angles(0,0,math.rad(-38))},
}
-- The engine's grip points when a rig has no grip attachment (R15 hand / R6 arm).
local R15_GRIP=CFrame.new(0,-.15,0)*CFrame.Angles(math.rad(-90),0,0)
local R6_GRIP=CFrame.new(0,-1,0)*CFrame.Angles(math.rad(-90),0,0)
-- limb, C0 (handle = limb.CFrame * C0) of a mount on this character; nil without the limb.
-- model (optional): a pickaxe whose BackC0 attribute (a torso-space offset) moves it on the back
-- (TV-Head: its big CRT sits beside the head instead of inside it); in the hand, HandTilt (degrees)
-- leans it forward and HandYaw (degrees) turns it round its own pole, both round the grip point so
-- the hand stays on the pole (Scarlet Anime Scythe: the head leans out in front and the blade points
-- forward-right, so the swing leads with the point and the glyph face stays toward the camera).
function Models.MountJoint(character,mount,model)
 local m=Models.Mounts[mount]
 if not(m and character)then return nil end
 local limb=character:FindFirstChild(m.Limb[1])or character:FindFirstChild(m.Limb[2])
 if not(limb and limb:IsA('BasePart'))then return nil end
 if m.C0 then
  local offset=model and model:GetAttribute('BackC0')
  return limb,typeof(offset)=='CFrame'and offset*m.C0 or m.C0
 end
 local att=limb:FindFirstChild(m.Attachment)
 local base=(att and att:IsA('Attachment'))and att.CFrame or(limb.Name==m.Limb[2]and R6_GRIP or R15_GRIP)
 local grip=Models.ToolGrip[m.Grip]
 local yaw=model and m.Grip=='Pick'and model:GetAttribute('HandYaw')
 local tilt=model and m.Grip=='Pick'and model:GetAttribute('HandTilt')
 if type(yaw)=='number'or type(tilt)=='number'then
  local at=CFrame.new(grip.Position)
  local turn=CFrame.Angles(math.rad(-(tonumber(tilt)or 0)),0,0)*CFrame.Angles(0,math.rad(tonumber(yaw)or 0),0)
  return limb,base*grip:Inverse()*at*turn*at:Inverse()
 end
 return limb,base*grip:Inverse()
end
local function sameCF(a,b)
 return(a.Position-b.Position).Magnitude<1e-3 and a.LookVector:Dot(b.LookVector)>.99999 and a.UpVector:Dot(b.UpVector)>.99999
end
-- Welds a pickaxe model (Models.Pickaxe / PickaxeOffhand) to a character at mount ('Hand',
-- 'Glove', 'GloveL', 'Back') through one Weld "HandGrip" on its Handle. A model that is not in the
-- world (new, or kept off the character since it was last worn) is first moved to the limb, so it
-- never shows up (or streams in) at the map origin or where it came off; a mounted model only has
-- its HandGrip retargeted (never rebuilt, PickFX keeps tracking it). Writes nothing when nothing
-- changed (the server re-checks every second); force rewrites the joint (new limbs / avatar
-- scale). Returns false when the character has no such limb.
function Models.Mount(character,model,mount,force)
 local handle=model.PrimaryPart or model:FindFirstChild('Handle')
 local limb,c0=Models.MountJoint(character,mount,model)
 if not(handle and handle:IsA('BasePart')and limb)then return false end
 if model.PrimaryPart~=handle then model.PrimaryPart=handle end
 if not model:GetAttribute('Welded')then Models.WeldToSelf(model);model:SetAttribute('Welded',true)end
 if not model:IsDescendantOf(workspace)then model:PivotTo(limb.CFrame*c0)end
 local grip=handle:FindFirstChild('HandGrip')
 if grip and not grip:IsA('Weld')then grip:Destroy();grip=nil end
 if not grip then
  grip=Instance.new('Weld');grip.Name='HandGrip'
  grip.C0=c0;grip.C1=CFrame.identity;grip.Part0=limb;grip.Part1=handle;grip.Parent=handle
 elseif force or grip.Part0~=limb or grip.Part1~=handle or not sameCF(grip.C0,c0)then
  grip.C0=c0;grip.C1=CFrame.identity;grip.Part1=handle;grip.Part0=limb
 end
 if model:GetAttribute('Mount')~=mount then model:SetAttribute('Mount',mount)end
 return true
end

-- 2D pickaxe icon drawn with frames (used on the world sign and in GUIs). size in pixels.
function Models.PickaxeIcon(parent,size,headColor,shaftColor,z)
 local holder=Instance.new('Frame');holder.Name='PickaxeIcon';holder.BackgroundTransparency=1;holder.Size=UDim2.fromOffset(size,size);holder.ZIndex=z or 1;holder.Parent=parent
 local function bar(name,w,h,x,y,rot,color,round)
  local f=Instance.new('Frame');f.Name=name;f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(x,y);f.Size=UDim2.fromScale(w,h);f.Rotation=rot
  f.BackgroundColor3=color;f.BorderSizePixel=0;f.ZIndex=(z or 1)+1;f.Parent=holder
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(round or .5,0);c.Parent=f
  local s=Instance.new('UIStroke');s.Color=Color3.fromRGB(20,16,12);s.Thickness=math.max(1,size/40);s.Parent=f
  return f
 end
 -- Shaft runs bottom-left -> top-right; the head crosses it near the top end.
 bar('Shaft',.12,.86,.47,.53,45,shaftColor or Color3.fromRGB(150,98,52),.4)
 local headFrame=bar('Head',.8,.15,.68,.32,45,headColor or Color3.fromRGB(185,192,202),.5)
 headFrame.ZIndex=(z or 1)+2
 bar('Bind',.17,.17,.68,.32,45,Color3.fromRGB(70,60,52),.25).ZIndex=(z or 1)+3
 return holder
end

return Models
