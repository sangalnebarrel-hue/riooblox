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
 l.Font=font or Enum.Font.GothamBlack;l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true);l.Parent=g
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
 local shaft=rgb(v.Shaft,{120,82,48});local head=rgb(v.Head,def.Color);local trim=rgb(v.Trim,{60,60,64})
 part(model,'Grip',Vector3.new(.4,len*.28,.4),CFrame.new(0,-len*.32,0),trim,material(v.GripMaterial or'Fabric'))
 part(model,'Binding',Vector3.new(.62,.58,.62),top,trim,material(v.TrimMaterial or'Metal'))
 local headMat=material(v.HeadMaterial or'Metal')
 local span=v.Span or 1.55
 for side=-1,1,2 do
  local arm=part(model,'HeadArm',Vector3.new(span,.46,.5),top*CFrame.new(side*span*.5,0,0)*CFrame.Angles(0,0,side*math.rad(-12)),head,headMat)
  local tipCF=arm.CFrame*CFrame.new(side*(span*.5+.32),-.04,0)*CFrame.Angles(0,side>0 and math.pi*.5 or-math.pi*.5,0)
  wedge(model,'HeadTip',Vector3.new(.5,.42,.66),tipCF*CFrame.Angles(math.pi*.5,0,0),head,headMat)
  part(model,'HeadBand',Vector3.new(.14,.5,.54),top*CFrame.new(side*.62,0,0)*CFrame.Angles(0,0,side*math.rad(-12)),trim,Enum.Material.Metal)
 end
 for i=1,3 do part(model,'Nail',Vector3.new(.08,.08,.06),top*CFrame.new((i-2)*.18,.12,.33),Color3.fromRGB(60,60,64),Enum.Material.Metal)end
 return Vector3.new(-span-.4,len*.5-.2,0),Vector3.new(span+.4,len*.5-.2,0)
end

-- Butterfly catcher: a glowing hoop with a magic film, a net bag and live butterflies.
DESIGNS.Net=function(model,v,def,len,top)
 local hoopC=top*CFrame.new(0,1.15,0)
 local gold=rgb(v.Head);local film=rgb(v.Film);local trim=rgb(v.Trim)
 stripes(model,len,{trim,rgb(v.Shaft),trim,rgb(v.Shaft)},Enum.Material.SmoothPlastic,.36,-len*.5,-len*.1)
 cylY(model,'Ferrule',.5,.44,top*CFrame.new(0,-.05,0),gold,Enum.Material.Foil)
 ring(model,'Hoop',hoopC,1.2,.16,.2,16,gold,Enum.Material.Foil)
 -- Teeth round the hoop: it is still a pickaxe.
 for i=0,9 do
  local a=i/10*math.pi*2
  if math.cos(a)<.92 then
   local cf=hoopC*CFrame.new(math.cos(a)*1.4,math.sin(a)*1.4,0)*CFrame.Angles(0,0,a-math.pi/2)
   wedge(model,'Tooth',Vector3.new(.12,.3,.22),cf*CFrame.Angles(0,0,math.pi),gold,Enum.Material.Foil)
  end
 end
 local f=cylZ(model,'Film',.05,2.3,hoopC,film,Enum.Material.Neon,{Transparency=.55,CastShadow=false})
 f:SetAttribute('PickPulse',true)
 blob(model,'NetBag',Vector3.new(2.2,2.2,1.8),hoopC*CFrame.new(0,0,-.75),Color3.fromRGB(240,250,255),Enum.Material.Glass,{Transparency=.65,CastShadow=false})
 local wings={Color3.fromRGB(255,140,220),Color3.fromRGB(255,214,90),Color3.fromRGB(140,220,255)}
 for i,pos in ipairs({Vector3.new(-.45,.35,.18),Vector3.new(.5,-.25,.2),Vector3.new(.05,.55,-.3)})do
  local c=hoopC*CFrame.new(pos)
  local body=blob(model,'Butterfly',Vector3.new(.06,.26,.06),c,Color3.fromRGB(30,26,40),Enum.Material.SmoothPlastic)
  anim(body,'Bob',i*.7)
  for side=-1,1,2 do
   local w=part(model,'Wing',Vector3.new(.3,.26,.02),c*CFrame.new(side*.16,.02,0),wings[i],Enum.Material.Neon,{CastShadow=false})
   anim(w,'Bob,'..(side<0 and'FlutterL'or'FlutterR'),i*.7,c.Position)
  end
 end
 return hoopC*CFrame.new(-1.3,0,0).Position,hoopC*CFrame.new(1.3,0,0).Position
end

-- LEGO hand: a giant yellow minifig C-hand on a plastic arm, sticker and cracks.
DESIGNS.Lego=function(model,v,def,len,top)
 local yellow=rgb(v.Head);local red=rgb(v.Trim)
 local props={Reflectance=.08}
 cylY(model,'ArmPlastic',len*.92,.5,CFrame.new(0,-.05,0),yellow,Enum.Material.SmoothPlastic,props)
 cylY(model,'Cuff',.5,.64,top*CFrame.new(0,-.1,0),red,Enum.Material.SmoothPlastic,props)
 cylY(model,'Wrist',.4,.46,top*CFrame.new(0,.3,0),yellow,Enum.Material.SmoothPlastic,props)
 local c=top*CFrame.new(0,1.15,0)
 local pivot=c*CFrame.new(0,-.8,0)
 -- The C opens upwards (gap at the top): left / right halves clench.
 for i=0,11 do
  local a=i/12*math.pi*2
  if not(a>math.rad(50)and a<math.rad(130))then
   local seg=part(model,'Finger',Vector3.new(.5,.46,.7),c*CFrame.new(math.cos(a)*.78,math.sin(a)*.78,0)*CFrame.Angles(0,0,a),yellow,Enum.Material.SmoothPlastic,props)
   anim(seg,math.cos(a)<0 and'ClenchL'or'ClenchR',0,pivot.Position)
  end
 end
 local sticker=part(model,'Sticker',Vector3.new(.5,.36,.03),top*CFrame.new(0,-.1,.33),Color3.fromRGB(40,120,240),Enum.Material.SmoothPlastic)
 text(sticker,Enum.NormalId.Front,'★',Color3.new(1,1,1))
 for i=1,3 do part(model,'Crack',Vector3.new(.03,.26,.02),c*CFrame.new(-.55+i*.22,-.62+(i%2)*.1,.36)*CFrame.Angles(0,0,i*.6),Color3.fromRGB(150,110,10),Enum.Material.SmoothPlastic)end
 return c*CFrame.new(-1.1,0,0).Position,c*CFrame.new(1.1,0,0).Position
end

-- 67: chunky 7-segment digits joined into a pick head; stickers and graffiti.
local SEGMENTS={a={0,1,true},b={.5,.5,false},c={.5,-.5,false},d={0,-1,true},e={-.5,-.5,false},f={-.5,.5,false},g={0,0,true}}
local function digit(model,name,cf,segs,color,mat,kind,phase)
 local w,h=.95,.85
 for _,s in ipairs(segs)do
  local seg=SEGMENTS[s]
  local size=seg[3]and Vector3.new(w,.28,.42)or Vector3.new(.28,h,.42)
  local p=part(model,name,size,cf*CFrame.new(seg[1]*w,seg[2]*h,0),color,mat,{Reflectance=.25})
  anim(p,kind,phase,cf.Position)
 end
end
DESIGNS.SixSeven=function(model,v,def,len,top)
 local black,white,red=rgb(v.Shaft),rgb(v.Head),rgb(v.Trim)
 stripes(model,len,{black,white,black,white,black},Enum.Material.SmoothPlastic,.36)
 local hub=part(model,'Hub',Vector3.new(.8,.7,.62),top*CFrame.new(0,.15,0),Color3.fromRGB(200,206,214),Enum.Material.Metal,{Reflectance=.35})
 for i=-1,1,2 do part(model,'Bolt',Vector3.new(.16,.16,.66),hub.CFrame*CFrame.new(i*.24,0,0),Color3.fromRGB(60,60,66),Enum.Material.Metal)end
 local six=top*CFrame.new(-1.15,.55,0)*CFrame.Angles(0,0,math.rad(18))
 local seven=top*CFrame.new(1.15,.55,0)*CFrame.Angles(0,0,math.rad(-18))
 digit(model,'Six',six,{'a','f','g','e','d','c'},white,Enum.Material.SmoothPlastic,'BobA',0)
 digit(model,'Seven',seven,{'a','b','c'},red,Enum.Material.SmoothPlastic,'BobB',0)
 -- Stickers and graffiti on the front faces.
 local colors={Color3.fromRGB(255,220,40),Color3.fromRGB(40,200,255),Color3.fromRGB(120,255,90)}
 for i,pos in ipairs({six*CFrame.new(-.2,.6,.23),seven*CFrame.new(.1,.95,.23),six*CFrame.new(.2,-.7,.23)})do
  part(model,'Sticker',Vector3.new(.24,.2,.02),pos*CFrame.Angles(0,0,i*.4),colors[i],Enum.Material.SmoothPlastic)
 end
 for i=1,4 do part(model,'Scratch',Vector3.new(.5,.025,.02),six*CFrame.new(-.1+i*.05,-.95+i*.38,.22)*CFrame.Angles(0,0,.5+i*.2),Color3.fromRGB(60,60,60),Enum.Material.SmoothPlastic)end
 return six*CFrame.new(-.6,1.1,0).Position,seven*CFrame.new(.6,-.9,0).Position
end

-- Gummy horror: a translucent sweet blob with candy teeth, googly eyes and sticky strands.
DESIGNS.Gummy=function(model,v,def,len,top)
 local pink,lime,yellow=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 local glass={Transparency=.18,Reflectance=.12}
 cylY(model,'GummyShaft',len*.95,.44,CFrame.new(0,-.05,0),rgb(v.Shaft),Enum.Material.Glass,glass)
 cylY(model,'GummyCore',len*.9,.18,CFrame.new(0,-.05,0),pink,Enum.Material.Neon,{CastShadow=false})
 local c=top*CFrame.new(0,.75,0)
 anim(blob(model,'Blob',Vector3.new(2.1,1.7,1.6),c,pink,Enum.Material.Glass,glass),'Jiggle',0,c.Position)
 anim(blob(model,'Blob',Vector3.new(1.1,1.0,1.0),c*CFrame.new(-.75,.55,.1),lime,Enum.Material.Glass,glass),'Jiggle',.4,c.Position)
 anim(blob(model,'Blob',Vector3.new(1.0,.9,.9),c*CFrame.new(.8,.5,-.1),yellow,Enum.Material.Glass,glass),'Jiggle',.8,c.Position)
 eye(model,'GooglyL',.5,c*CFrame.new(-.38,.28,.72),nil,nil,'EyeLook',0)
 eye(model,'GooglyR',.42,c*CFrame.new(.38,.34,.7),nil,nil,'EyeLook',1.3)
 local candy={Color3.fromRGB(255,255,255),Color3.fromRGB(255,170,220),Color3.fromRGB(190,255,190),Color3.fromRGB(255,240,150)}
 for i=-2,2 do
  wedge(model,'CandyTooth',Vector3.new(.16,.26,.14),c*CFrame.new(i*.2,-.22,.78)*CFrame.Angles(0,0,math.pi),candy[(i+3)%4+1],Enum.Material.SmoothPlastic)
 end
 part(model,'Mouth',Vector3.new(1.1,.12,.05),c*CFrame.new(0,-.08,.77),Color3.fromRGB(110,10,60),Enum.Material.SmoothPlastic)
 -- Worm arms (the pick tips) and sticky strands.
 for side=-1,1,2 do
  for i=1,3 do
   anim(ball(model,'GummyWorm',.62-i*.1,c*CFrame.new(side*(.9+i*.42),-.1-i*.18,0),i%2==0 and lime or pink,Enum.Material.Glass,glass),'Wave',i*.35+(side+1),c.Position)
  end
 end
 for i=1,3 do
  local s=blob(model,'Strand',Vector3.new(.12,.7,.12),c*CFrame.new(-.5+i*.28,-.95,.25),lime,Enum.Material.Glass,{Transparency=.3})
  anim(s,'Drip',i*.5)
 end
 return c*CFrame.new(-2.2,-.6,0).Position,c*CFrame.new(2.2,-.6,0).Position
end

-- Rotten slime slug: a fat slug riding the pick head, eyes on stalks, slime dripping.
DESIGNS.Slug=function(model,v,def,len,top)
 local body,lime,dark=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 local slime={Transparency=.28,Reflectance=.15}
 cylY(model,'MossShaft',len*.95,.4,CFrame.new(0,-.05,0),rgb(v.Shaft),Enum.Material.Slate)
 for i=1,4 do blob(model,'ShaftSlime',Vector3.new(.5,.36,.5),CFrame.new(0,-len*.4+i*.7,.02),lime,Enum.Material.Glass,slime)end
 local c=top*CFrame.new(0,.55,0)
 local slug=blob(model,'SlugBody',Vector3.new(3.1,1.4,1.2),c*CFrame.new(0,.15,0),body,Enum.Material.Slate)
 anim(slug,'Breathe',0,c.Position)
 anim(blob(model,'SlugStripe',Vector3.new(2.7,.45,.7),c*CFrame.new(0,.75,0),dark,Enum.Material.Slate),'Breathe',0,c.Position)
 anim(blob(model,'SlugFoot',Vector3.new(3.3,.45,1.25),c*CFrame.new(0,-.45,0),lime,Enum.Material.Glass,slime),'Breathe',0,c.Position)
 for i=1,4 do blob(model,'SlugSpot',Vector3.new(.35,.22,.08),c*CFrame.new(-1.1+i*.45,.35+(i%2)*.2,.6),dark,Enum.Material.Slate)end
 -- Four eyes on stalks at the head end (+X): one big, one half shut.
 local stalks={{.9,1.0,.25,.5},{1.25,1.15,-.1,.42},{1.5,.85,.4,.68},{1.1,.75,-.45,.38}}
 for i,s in ipairs(stalks)do
  local base=c*CFrame.new(s[1],.6,s[3]*.6)
  local tip=c*CFrame.new(s[1]+.3,.6+s[2],s[3])
  local stalk=rod(model,'EyeStalk',base.Position,tip.Position,.1,lime,Enum.Material.Glass,slime)
  anim(stalk,'Stalk',i*.9,base.Position)
  local e,p,g=eye(model,'SlugEye'..i,s[4],tip,Color3.fromRGB(240,244,200),nil,'Stalk',i*.9)
  for _,x in ipairs({e,p,g})do x:SetAttribute('PickJoint',base.Position);x:SetAttribute('PickPop',(tip.Position-base.Position).Unit)end
  if i==4 then anim(part(model,'Eyelid',Vector3.new(s[4]+.04,s[4]*.5,s[4]+.04),tip*CFrame.new(0,s[4]*.22,0),body,Enum.Material.Slate),'Stalk',i*.9,base.Position)end
 end
 for i=1,3 do
  anim(blob(model,'SlimeDrop',Vector3.new(.2,.34,.2),c*CFrame.new(-1+i*.6,-.75,.2),lime,Enum.Material.Glass,slime),'Drip',i*.6)
 end
 return c*CFrame.new(-1.9,0,0).Position,c*CFrame.new(1.9,0,0).Position
end

-- Toothy alarm clock: a screaming red clock with knife hands, bells and teeth.
DESIGNS.Alarm=function(model,v,def,len,top)
 local red,white,gold=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 cylY(model,'Shaft',len*.95,.38,CFrame.new(0,-.05,0),rgb(v.Shaft),Enum.Material.Metal)
 stripes(model,len,{red,Color3.fromRGB(40,40,44),red},Enum.Material.SmoothPlastic,.42,-len*.5,-len*.15)
 local c=top*CFrame.new(0,1.0,0)
 cylZ(model,'ClockBody',.8,2.2,c,red,Enum.Material.Metal,{Reflectance=.1})
 cylZ(model,'Dial',.06,1.9,c*CFrame.new(0,0,.42),white,Enum.Material.SmoothPlastic)
 ring(model,'Rim',c*CFrame.new(0,0,.43),1.0,.12,.1,16,gold,Enum.Material.Foil)
 for i=0,3 do local a=i*math.pi/2;part(model,'Tick',Vector3.new(.08,.2,.04),c*CFrame.new(math.cos(a)*.78,math.sin(a)*.78,.46)*CFrame.Angles(0,0,a+math.pi/2),Color3.fromRGB(30,30,30),Enum.Material.SmoothPlastic)end
 local hour=wedge(model,'KnifeHour',Vector3.new(.06,.62,.14),c*CFrame.new(0,.26,.5),Color3.fromRGB(190,196,206),Enum.Material.Metal)
 anim(hour,'HandSlow',0,c.Position)
 local minute=wedge(model,'KnifeMinute',Vector3.new(.05,.85,.12),c*CFrame.new(0,.38,.53),Color3.fromRGB(220,226,236),Enum.Material.Metal)
 anim(minute,'HandFast',0,c.Position)
 ball(model,'Pin',.14,c*CFrame.new(0,0,.56),gold,Enum.Material.Foil)
 eye(model,'ClockEyeL',.32,c*CFrame.new(-.4,.36,.48),nil,nil,'EyeLook',.2)
 eye(model,'ClockEyeR',.32,c*CFrame.new(.4,.36,.48),nil,nil,'EyeLook',.9)
 for side=-1,1,2 do part(model,'Brow',Vector3.new(.36,.07,.05),c*CFrame.new(side*.4,.6,.5)*CFrame.Angles(0,0,side*-.4),Color3.fromRGB(20,20,20),Enum.Material.SmoothPlastic)end
 part(model,'Gums',Vector3.new(1.0,.28,.05),c*CFrame.new(0,-.45,.47),Color3.fromRGB(150,20,30),Enum.Material.SmoothPlastic)
 for i=-3,3 do wedge(model,'Tooth',Vector3.new(.12,.18,.08),c*CFrame.new(i*.14,-.36,.5)*CFrame.Angles(0,0,math.pi),Color3.new(1,1,1),Enum.Material.SmoothPlastic)end
 for side=-1,1,2 do
  local bell=ball(model,'Bell',.7,c*CFrame.new(side*.72,1.0,0),gold,Enum.Material.Foil)
  anim(bell,'Shake',side,c*CFrame.new(side*.72,1.0,0).Position)
  wedge(model,'Spike',Vector3.new(.4,.9,.5),c*CFrame.new(side*1.45,-.1,0)*CFrame.Angles(0,0,side*math.pi/2),Color3.fromRGB(200,206,214),Enum.Material.Metal)
 end
 anim(part(model,'Hammer',Vector3.new(.12,.5,.12),c*CFrame.new(0,1.15,0),gold,Enum.Material.Foil),'Shake',2,c*CFrame.new(0,.95,0).Position)
 return c*CFrame.new(-1.9,-.1,0).Position,c*CFrame.new(1.9,-.1,0).Position
end

-- Ponycorn-Dolphoodle: pony head, unicorn horn, dolphin tail and poodle fluff on caramel.
DESIGNS.Ponycorn=function(model,v,def,len,top)
 local yellow,pink,fin,white=rgb(v.Head),rgb(v.Accent),rgb(v.Fin),rgb(v.Trim)
 stripes(model,len,{pink,rgb(v.Shaft),pink,rgb(v.Shaft),pink,rgb(v.Shaft)},Enum.Material.Glass,.4)
 local c=top*CFrame.new(0,.75,0)
 blob(model,'PonyHead',Vector3.new(1.9,1.6,1.45),c,yellow,Enum.Material.SmoothPlastic)
 blob(model,'Snout',Vector3.new(1.0,.8,1.0),c*CFrame.new(.85,-.22,.12),pink,Enum.Material.SmoothPlastic)
 for side=-1,1,2 do wedge(model,'PonyEar',Vector3.new(.14,.45,.3),c*CFrame.new(-.15,.85,side*.38)*CFrame.Angles(side*.2,0,0),yellow,Enum.Material.SmoothPlastic)end
 for side=-1,1,2 do ball(model,'Nostril',.1,c*CFrame.new(1.0,-.12,.3+side*.12),Color3.fromRGB(120,40,80),Enum.Material.SmoothPlastic)end
 eye(model,'PonyEye',.55,c*CFrame.new(.15,.25,.6),Color3.fromRGB(30,20,50),Color3.fromRGB(90,60,180))
 ball(model,'Blush',.3,c*CFrame.new(.55,-.15,.62),Color3.fromRGB(255,140,190),Enum.Material.SmoothPlastic)
 -- Horn: a rainbow spiral cone pointing forward-up (one pick tip).
 for i=0,4 do
  local h=ball(model,'Horn',.42-i*.07,c*CFrame.new(.45+i*.24,.55+i*.24,0),Color3.fromHSV(i/5,.6,1),Enum.Material.Neon,{CastShadow=false})
  h:SetAttribute('PickRainbow',true);h:SetAttribute('PickPhase',i*.2)
 end
 -- Poodle fluff on the crown and the back.
 for i,o in ipairs({{-.3,.62,.1},{-.62,.35,0},{-.15,.7,-.25},{-.75,0,.2},{.1,.68,.3}})do
  anim(ball(model,'Fluff',.5,c*CFrame.new(o[1],o[2],o[3]),i%2==0 and white or pink,Enum.Material.Fabric),'Fluff',i*.5,c.Position)
 end
 -- Dolphin body curving back into a tail fin (the other pick tip).
 for i=1,4 do
  anim(blob(model,'Dolphin',Vector3.new(.75-i*.1,.55-i*.06,.55-i*.06),c*CFrame.new(-.75-i*.42,-.3-i*.12+(i*i)*.03,0),fin,Enum.Material.SmoothPlastic),'Wave',i*.3,c.Position)
 end
 for side=-1,1,2 do
  anim(wedge(model,'TailFin',Vector3.new(.08,.45,.5),c*CFrame.new(-2.55,-.55,side*.25)*CFrame.Angles(side*.5,0,math.rad(70)),fin,Enum.Material.SmoothPlastic),'Wave',1.5,c.Position)
 end
 local holder=part(model,'Sparkles',Vector3.new(.3,.3,.3),c*CFrame.new(1.3,1.6,0),white,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
 local e=emitter(holder,'Sparkle',pink);if e then e.Color=ColorSequence.new(Color3.fromRGB(255,140,220),Color3.fromRGB(255,240,120));e.Rate=5 end
 return c*CFrame.new(-2.7,-.55,0).Position,c*CFrame.new(1.6,1.6,0).Position
end

-- Zombie-Frankenstein: stitched meat, rusty plates, bolts, bone and blue sparks.
DESIGNS.Zombie=function(model,v,def,len,top)
 local bone,flesh,blue,rust=rgb(v.Shaft),rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 cylY(model,'BoneShaft',len*.95,.4,CFrame.new(0,-.05,0),bone,Enum.Material.Marble)
 for i=1,3 do cylY(model,'RustBand',.18,.48,CFrame.new(0,-len*.35+i*.9,0),rust,Enum.Material.CorrodedMetal)end
 local c=top*CFrame.new(0,.65,0)
 part(model,'Flesh',Vector3.new(1.3,1.2,1.0),c,flesh,Enum.Material.Slate)
 anim(part(model,'CrookedMeat',Vector3.new(.9,.8,.9),c*CFrame.new(-1.0,.15,0)*CFrame.Angles(0,0,.25),flesh:Lerp(Color3.fromRGB(150,90,90),.4),Enum.Material.Slate),'Twitch',0,c*CFrame.new(-.6,.1,0).Position)
 part(model,'RustPlate',Vector3.new(1.0,1.0,1.05),c*CFrame.new(1.0,0,0),rust,Enum.Material.CorrodedMetal)
 wedge(model,'BoneSpike',Vector3.new(.6,1.1,.6),c*CFrame.new(1.9,0,0)*CFrame.Angles(0,0,-math.pi/2),bone,Enum.Material.Marble)
 anim(wedge(model,'MeatHook',Vector3.new(.5,1.0,.5),c*CFrame.new(-1.85,.1,0)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(160,166,176),Enum.Material.Metal),'Twitch',0,c*CFrame.new(-.6,.1,0).Position)
 for i=1,5 do
  part(model,'Stitch',Vector3.new(.04,.32,.04),c*CFrame.new(-.5,-.4+i*.15,.52)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(20,20,20),Enum.Material.SmoothPlastic)
  part(model,'Stitch',Vector3.new(.04,.32,.04),c*CFrame.new(.48,-.4+i*.15,.52)*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(20,20,20),Enum.Material.SmoothPlastic)
 end
 for side=-1,1,2 do
  cylZ(model,'NeckBolt',.9,.24,c*CFrame.new(side*.35,.75,0),Color3.fromRGB(110,116,126),Enum.Material.Metal)
  local spark=part(model,'Spark',Vector3.new(.06,.6,.06),c*CFrame.new(side*.2,1.05,.3)*CFrame.Angles(0,0,side*.6),blue,Enum.Material.Neon,{CastShadow=false})
  spark:SetAttribute('PickFlicker',true)
 end
 local holder=part(model,'Sparks',Vector3.new(.6,.6,.6),c*CFrame.new(0,.9,0),blue,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
 local e=emitter(holder,'Sparkle',blue);if e then e.Rate=4 end
 return c*CFrame.new(-2.3,.1,0).Position,c*CFrame.new(2.4,0,0).Position
end

-- Clown Chronomord: a mad clown on a clock torso, tongue out.
DESIGNS.Clown=function(model,v,def,len,top)
 local cream,red,blue=rgb(v.Head),rgb(v.Trim),rgb(v.Accent)
 stripes(model,len,{red,cream,red,cream,red,cream},Enum.Material.SmoothPlastic,.4)
 local c=top*CFrame.new(0,.75,0)
 cylY(model,'Torso',1.3,1.5,c,blue,Enum.Material.SmoothPlastic)
 cylZ(model,'ClockFace',.08,1.15,c*CFrame.new(0,0,.74),Color3.fromRGB(252,246,226),Enum.Material.SmoothPlastic)
 ring(model,'ClockRim',c*CFrame.new(0,0,.76),.6,.1,.08,14,Color3.fromRGB(212,170,60),Enum.Material.Foil)
 anim(part(model,'ClockHand',Vector3.new(.05,.48,.04),c*CFrame.new(0,.22,.82),Color3.fromRGB(20,20,20),Enum.Material.SmoothPlastic),'HandBack',0,c*CFrame.new(0,0,.82).Position)
 anim(part(model,'ClockHand',Vector3.new(.05,.34,.04),c*CFrame.new(0,.15,.84),Color3.fromRGB(150,20,20),Enum.Material.SmoothPlastic),'HandSlow',0,c*CFrame.new(0,0,.84).Position)
 for i=0,9 do local a=i/10*math.pi*2;ball(model,'Ruffle',.36,c*CFrame.new(math.cos(a)*.66,.72,math.sin(a)*.66),i%2==0 and Color3.new(1,1,1)or Color3.fromRGB(255,214,230),Enum.Material.Fabric)end
 local h=c*CFrame.new(0,1.35,0)
 ball(model,'ClownHead',1.1,h,cream,Enum.Material.SmoothPlastic)
 ball(model,'Nose',.36,h*CFrame.new(0,-.02,.55),Color3.fromRGB(240,30,40),Enum.Material.SmoothPlastic)
 eye(model,'MadEyeL',.46,h*CFrame.new(-.25,.18,.4),nil,nil,'EyeTwitch',0)
 eye(model,'MadEyeR',.3,h*CFrame.new(.26,.2,.45),nil,nil,'EyeLook',1)
 for i=1,3 do anim(blob(model,'Tongue',Vector3.new(.28,.42,.2),h*CFrame.new(0,-.35-i*.3,.5+i*.05),Color3.fromRGB(230,60,90),Enum.Material.SmoothPlastic),'Tongue',i*.25,h*CFrame.new(0,-.3,.5).Position)end
 for i=0,2 do cylY(model,'Hat',.3,.55-i*.15,h*CFrame.new(0,.55+i*.25,0),Color3.fromRGB(150,60,200),Enum.Material.SmoothPlastic)end
 ball(model,'Pompom',.26,h*CFrame.new(0,1.35,0),Color3.fromRGB(255,214,60),Enum.Material.Fabric)
 for side=-1,1,2 do
  wedge(model,'JesterPoint',Vector3.new(.4,1.1,.4),c*CFrame.new(side*1.3,.05,0)*CFrame.Angles(0,0,side*math.pi/2),Color3.fromRGB(212,170,60),Enum.Material.Foil)
  ball(model,'JesterBell',.26,c*CFrame.new(side*1.95,.05,0),Color3.fromRGB(255,214,60),Enum.Material.Foil)
 end
 return c*CFrame.new(-2.1,0,0).Position,c*CFrame.new(2.1,0,0).Position
end

-- Nasty octopus: fat blue body, one big yellow eye, tentacles everywhere.
DESIGNS.Octopus=function(model,v,def,len,top)
 local blue,yellow,purple=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 cylY(model,'Shaft',len*.95,.38,CFrame.new(0,-.05,0),rgb(v.Shaft),Enum.Material.Slate)
 for i=0,9 do local a=i*.95;ball(model,'WrapTentacle',.32,CFrame.new(math.cos(a)*.2,-len*.42+i*.32,math.sin(a)*.2),i%2==0 and blue or purple,Enum.Material.Glass,{Reflectance=.1})end
 local c=top*CFrame.new(0,1.0,0)
 blob(model,'Mantle',Vector3.new(1.9,2.0,1.6),c*CFrame.new(0,.25,-.1),blue,Enum.Material.Glass,{Reflectance=.12})
 for i=1,5 do ball(model,'Wart',.18,c*CFrame.new(-.6+i*.22,.75+math.sin(i)*.25,.55),purple,Enum.Material.SmoothPlastic)end
 local e=ball(model,'BigEye',.9,c*CFrame.new(0,.15,.55),yellow,Enum.Material.Neon,{CastShadow=false})
 anim(e,'EyeLook',0,c*CFrame.new(0,.15,.55).Position)
 anim(part(model,'Slit',Vector3.new(.1,.55,.06),c*CFrame.new(0,.15,1.0),Color3.fromRGB(10,10,10),Enum.Material.SmoothPlastic),'EyeLook',0,c*CFrame.new(0,.15,.55).Position)
 -- Six tentacles: overlapping, tapering bead chains that curl at the ends; the two long side
 -- ones are the pick tips.
 for t=1,6 do
  local a=(t/6)*math.pi*2+.3
  local dir=Vector3.new(math.cos(a)*.8,-1,math.sin(a)*.6)
  local reach=6
  if t==1 then dir=Vector3.new(1,-.25,0);reach=8 elseif t==4 then dir=Vector3.new(-1,-.25,0);reach=8 end
  local p=c.Position+Vector3.new(0,-.45,0)
  local d=dir.Unit
  for i=1,reach do
   local size=math.max(.16,.58-i*.055)
   p+=d*size*.62
   d=(d+Vector3.new(0,(t==1 or t==4)and .09 or .16,0)+Vector3.new(math.cos(a+i),0,math.sin(a+i))*.05).Unit
   anim(ball(model,'Tentacle',size,CFrame.new(p),i%3==0 and purple or blue,Enum.Material.Glass,{Reflectance=.1}),'Tentacle',t*.6+i*.25,c.Position)
   if i%2==1 and size>.3 then ball(model,'Sucker',size*.35,CFrame.new(p+Vector3.new(0,-size*.35,size*.25)),Color3.fromRGB(230,190,240),Enum.Material.SmoothPlastic)end
  end
 end
 return c*CFrame.new(-2.4,-.9,0).Position,c*CFrame.new(2.4,-.9,0).Position
end

-- Hand of Fate: a living palm, long clawed fingers, purple veins and an eye in the palm.
DESIGNS.Hand=function(model,v,def,len,top)
 local skin,purple,black=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 cylY(model,'Shaft',len*.95,.4,CFrame.new(0,-.05,0),rgb(v.Shaft),Enum.Material.Fabric)
 cylY(model,'WristBone',.6,.62,top*CFrame.new(0,-.05,0),skin:Lerp(black,.3),Enum.Material.Slate)
 local c=top*CFrame.new(0,.8,0)
 blob(model,'Palm',Vector3.new(1.8,1.5,.75),c,skin,Enum.Material.Slate)
 local e=ball(model,'PalmEye',.62,c*CFrame.new(0,0,.3),Color3.fromRGB(245,240,236),Enum.Material.SmoothPlastic)
 local iris=ball(model,'Iris',.36,c*CFrame.new(0,0,.52),purple,Enum.Material.Neon,{CastShadow=false})
 ball(model,'Pupil',.18,c*CFrame.new(0,0,.62),Color3.fromRGB(10,8,14),Enum.Material.SmoothPlastic)
 anim(iris,'EyeLook',0,c.Position)
 for side=-1,1,2 do anim(part(model,'Eyelid',Vector3.new(.68,.2,.36),c*CFrame.new(0,side*.42,.32),skin,Enum.Material.Slate),side<0 and'BlinkLow'or'BlinkHigh',0,c*CFrame.new(0,0,.32).Position)end
 -- Four fingers up (the teeth), thumb and pinky out sideways.
 local fingers={{-.6,1.0,-.18},{-.2,1.25,-.05},{.2,1.3,.05},{.6,1.1,.18}}
 for i,f in ipairs(fingers)do
  local base=c*CFrame.new(f[1],.65,0)
  local joint=base.Position
  for s=1,3 do
   local seg=cylY(model,'Finger',.5,.28-s*.03,base*CFrame.new(f[3]*s*.3,s*.42-.2,0),skin,Enum.Material.Slate)
   anim(seg,'Curl',i*.3,joint)
  end
  anim(wedge(model,'Claw',Vector3.new(.16,.42,.2),base*CFrame.new(f[3]*1.0,1.42,0),black,Enum.Material.Metal),'Curl',i*.3,joint)
 end
 for side=-1,1,2 do
  local base=c*CFrame.new(side*.85,0,0)
  for s=1,2 do anim(cylY(model,'Thumb',.48,.28,base*CFrame.new(side*s*.4,s*.18,0)*CFrame.Angles(0,0,side*-1.1),skin,Enum.Material.Slate),'Curl',2,base.Position)end
  wedge(model,'ThumbClaw',Vector3.new(.16,.42,.2),base*CFrame.new(side*1.2,.5,0)*CFrame.Angles(0,0,side*-1.1),black,Enum.Material.Metal)
 end
 for i=1,5 do
  local vein=part(model,'Vein',Vector3.new(.05,.6,.04),c*CFrame.new(-.7+i*.25,-.35,.33)*CFrame.Angles(0,0,(i-3)*.25),purple,Enum.Material.Neon,{CastShadow=false})
  vein:SetAttribute('PickPulse',true)
 end
 local holder=part(model,'Doom',Vector3.new(1,1,1),c,purple,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
 local fx=emitter(holder,'Void',purple);if fx then fx.Rate=4 end
 return c*CFrame.new(-1.9,.4,0).Position,c*CFrame.new(1.9,.4,0).Position
end

-- Laughsaw: a grinning red body with a spinning circular blade.
DESIGNS.Saw=function(model,v,def,len,top)
 local red,steel,black=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 stripes(model,len,{black,red,black,red,black},Enum.Material.SmoothPlastic,.4)
 local c=top*CFrame.new(0,.75,0)
 part(model,'SawBody',Vector3.new(1.7,1.3,.95),c,red,Enum.Material.Metal,{Reflectance=.1})
 part(model,'Mouth',Vector3.new(1.2,.4,.05),c*CFrame.new(0,-.25,.49),Color3.fromRGB(20,10,10),Enum.Material.SmoothPlastic)
 for i=-4,4 do
  wedge(model,'GrinTooth',Vector3.new(.11,.16,.06),c*CFrame.new(i*.13,-.12,.51)*CFrame.Angles(0,0,math.pi),Color3.new(1,1,1),Enum.Material.SmoothPlastic)
  wedge(model,'GrinTooth',Vector3.new(.11,.16,.06),c*CFrame.new(i*.13,-.38,.51),Color3.new(1,1,1),Enum.Material.SmoothPlastic)
 end
 eye(model,'SawEyeL',.36,c*CFrame.new(-.38,.32,.46),nil,nil,'EyeTwitch',0)
 eye(model,'SawEyeR',.36,c*CFrame.new(.38,.32,.46),nil,nil,'EyeTwitch',.6)
 local hub=c*CFrame.new(1.45,0,0)
 cylZ(model,'Axle',1.1,.34,hub,black,Enum.Material.Metal)
 anim(cylZ(model,'Blade',.1,2.3,hub*CFrame.new(0,0,.3),steel,Enum.Material.Metal,{Reflectance=.35}),'Spin',0,hub.Position)
 for i=0,11 do
  local a=i/12*math.pi*2
  anim(wedge(model,'SawTooth',Vector3.new(.06,.26,.24),hub*CFrame.new(math.cos(a)*1.2,math.sin(a)*1.2,.3)*CFrame.Angles(0,0,a-math.pi/2)*CFrame.Angles(0,math.pi/2,0),steel,Enum.Material.Metal),'Spin',0,hub.Position)
 end
 wedge(model,'BackSpike',Vector3.new(.5,1.1,.6),c*CFrame.new(-1.35,0,0)*CFrame.Angles(0,0,math.pi/2),steel,Enum.Material.Metal)
 return c*CFrame.new(-2.0,0,0).Position,c*CFrame.new(2.7,0,0).Position
end

-- Scarlet anime scythe: long wrapped pole, a curved red blade, glowing purple glyphs, demon eye.
DESIGNS.Scythe=function(model,v,def,len,top)
 local red,purple,dark=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 for i=1,9 do cylY(model,'Wrap',.22,.42,CFrame.new(0,-len*.42+i*.32,0)*CFrame.Angles(0,i*.4,0),i%2==0 and dark or Color3.fromRGB(20,20,24),Enum.Material.Fabric)end
 local c=top*CFrame.new(0,.25,0)
 cylY(model,'Collar',.45,.6,c,Color3.fromRGB(200,160,60),Enum.Material.Foil)
 local e=ball(model,'DemonEye',.42,c*CFrame.new(.2,.35,.25),Color3.fromRGB(255,40,40),Enum.Material.Neon,{CastShadow=false})
 anim(e,'EyeLook',0,e.CFrame.Position)
 anim(part(model,'DemonSlit',Vector3.new(.06,.3,.05),c*CFrame.new(.2,.35,.47),Color3.new(0,0,0),Enum.Material.SmoothPlastic),'EyeLook',0,e.CFrame.Position)
 -- Blade: an arc sweeping out over +X and curling down, tapering to a point.
 local last=c.Position+Vector3.new(.2,.35,0)
 for i=1,8 do
  local a=math.rad(100-i*19)
  local p=c.Position+Vector3.new(.3+math.cos(a)*2.4+1.0,.35+math.sin(a)*1.6,0)
  local w=.55-i*.05
  bar(model,'Blade',last,p,w,.14,red,Enum.Material.Metal,{Reflectance=.25})
  bar(model,'BladeEdge',last+Vector3.new(0,-w*.45,0),p+Vector3.new(0,-w*.45,0),.06,.16,Color3.fromRGB(240,240,246),Enum.Material.Metal)
  if i%2==0 then
   local g=part(model,'Glyph',Vector3.new(.22,.12,.02),CFrame.new((last+p)/2+Vector3.new(0,0,.09))*CFrame.Angles(0,0,i*.7),purple,Enum.Material.Neon,{CastShadow=false})
   g:SetAttribute('PickPulse',true)
   local g2=part(model,'Glyph',Vector3.new(.04,.18,.02),CFrame.new((last+p)/2+Vector3.new(.06,.05,.09))*CFrame.Angles(0,0,-i*.5),purple,Enum.Material.Neon,{CastShadow=false})
   g2:SetAttribute('PickPulse',true)
  end
  last=p
 end
 wedge(model,'BackSpike',Vector3.new(.3,.8,.3),c*CFrame.new(-.6,.3,0)*CFrame.Angles(0,0,math.pi/2),dark,Enum.Material.Metal)
 local holder=part(model,'Wisps',Vector3.new(2,.6,.4),c*CFrame.new(1.6,.8,0),purple,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
 local fx=emitter(holder,'Void',purple);if fx then fx.Rate=5 end
 return c*CFrame.new(-.6,.3,0).Position,last
end

-- Twin claws: a gauntlet (Handle) worn on the hand, three claws along +Y and a kanji plate.
local function gauntlet(model,v,len,mark)
 local black,steel,red,purple=rgb(v.Shaft),rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 local handle=model.PrimaryPart
 handle.Size=Vector3.new(1.1,1.0,1.15);handle.Color=black;handle.Material=Enum.Material.Metal
 part(model,'Knuckles',Vector3.new(1.2,.32,1.25),CFrame.new(0,.48,0),steel,Enum.Material.DiamondPlate)
 part(model,'Cuff',Vector3.new(1.2,.36,1.25),CFrame.new(0,-.5,0),steel,Enum.Material.Metal)
 local plate=part(model,'KanjiPlate',Vector3.new(.8,.6,.06),CFrame.new(0,0,.6),Color3.fromRGB(16,16,20),Enum.Material.SmoothPlastic)
 text(plate,Enum.NormalId.Front,mark,Color3.new(1,1,1))
 for i=1,3 do
  local rune=part(model,'Rune',Vector3.new(.06,.26,.03),CFrame.new(-.42+i*.21,-.38,.6)*CFrame.Angles(0,0,i*.8),i%2==0 and red or purple,Enum.Material.Neon,{CastShadow=false})
  rune:SetAttribute('PickPulse',true)
 end
 for i=-1,1 do
  local x=i*.36
  for s=1,3 do
   local seg=part(model,'Claw',Vector3.new(.12,.8,.24-s*.04),CFrame.new(x,.5+s*.62,s*s*.05)*CFrame.Angles(math.rad(-s*6),0,0),steel,Enum.Material.Metal,{Reflectance=.3})
   anim(seg,'ClawOut',i*.15)
  end
  anim(wedge(model,'ClawTip',Vector3.new(.12,.5,.2),CFrame.new(x,2.6,.55)*CFrame.Angles(math.rad(-20),0,0),steel,Enum.Material.Metal,{Reflectance=.3}),'ClawOut',i*.15)
 end
 return Vector3.new(-.4,2.6,.5),Vector3.new(.4,2.6,.5)
end
DESIGNS.Claws=function(model,v,def,len,top)
 return gauntlet(model,v,len,'右')
end

-- TV-Head: an old CRT with an angry face, antennas and metal spikes.
DESIGNS.TV=function(model,v,def,len,top)
 local case,green,dark=rgb(v.Head),rgb(v.Accent),rgb(v.Trim)
 cylY(model,'Pipe',len*.95,.36,CFrame.new(0,-.05,0),rgb(v.Shaft),Enum.Material.Metal)
 for i=0,10 do local a=i*1.2;ball(model,'Cable',.14,CFrame.new(math.cos(a)*.25,-len*.4+i*.25,math.sin(a)*.25),dark,Enum.Material.SmoothPlastic)end
 local c=top*CFrame.new(0,1.05,0)
 part(model,'TVCase',Vector3.new(2.3,1.8,1.5),c,case,Enum.Material.SmoothPlastic)
 part(model,'TVBack',Vector3.new(1.6,1.3,.6),c*CFrame.new(0,0,-1.0),case:Lerp(dark,.3),Enum.Material.SmoothPlastic)
 local screen=part(model,'Screen',Vector3.new(1.65,1.3,.06),c*CFrame.new(-.2,0,.77),Color3.fromRGB(20,30,24),Enum.Material.Glass,{Reflectance=.15})
 local g=Instance.new('SurfaceGui');g.Name='ScreenGui';g.Face=Enum.NormalId.Front;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=60
 g.LightInfluence=0;g:SetAttribute('NoTranslate',true);g.Parent=screen
 local back=Instance.new('Frame');back.Name='Noise';back.Size=UDim2.fromScale(1,1);back.BackgroundColor3=Color3.fromRGB(12,26,16);back.BorderSizePixel=0;back.Parent=g
 local grad=Instance.new('UIGradient');grad.Color=ColorSequence.new(Color3.fromRGB(40,90,50),Color3.fromRGB(10,30,16));grad.Rotation=90;grad.Parent=back
 local face=Instance.new('Frame');face.Name='Face';face.BackgroundTransparency=1;face.Size=UDim2.fromScale(1,1);face.Parent=back
 for side=-1,1,2 do
  local e=Instance.new('Frame');e.Name='Eye';e.AnchorPoint=Vector2.new(.5,.5);e.Position=UDim2.fromScale(.5+side*.2,.36);e.Size=UDim2.fromScale(.2,.12)
  e.Rotation=side*-14;e.BackgroundColor3=green;e.BorderSizePixel=0;e.Parent=face
 end
 for i=0,5 do
  local m=Instance.new('Frame');m.Name='Mouth';m.AnchorPoint=Vector2.new(.5,.5);m.Position=UDim2.fromScale(.28+i*.088,.7+(i%2)*.06);m.Size=UDim2.fromScale(.1,.06)
  m.Rotation=i%2==0 and 30 or-30;m.BackgroundColor3=green;m.BorderSizePixel=0;m.Parent=face
 end
 for i=1,2 do cylZ(model,'Knob',.25,.28,c*CFrame.new(.88,.35-i*.4,.76),dark,Enum.Material.SmoothPlastic)end
 for side=-1,1,2 do
  local base=c*CFrame.new(side*.3,.9,0)
  local tip=c*CFrame.new(side*1.0,2.0,0)
  anim(rod(model,'Antenna',base.Position,tip.Position,.07,Color3.fromRGB(200,204,210),Enum.Material.Metal),'Antenna',side,base.Position)
  anim(ball(model,'AntennaTip',.18,tip,green,Enum.Material.Neon,{CastShadow=false}),'Antenna',side,base.Position)
  wedge(model,'Spike',Vector3.new(.45,.95,.5),c*CFrame.new(side*1.55,-.2,0)*CFrame.Angles(0,0,side*math.pi/2),Color3.fromRGB(180,186,196),Enum.Material.Metal)
 end
 local holder=part(model,'Pixels',Vector3.new(1.6,1.2,.3),c*CFrame.new(0,0,.9),green,Enum.Material.SmoothPlastic,{Transparency=1,CastShadow=false})
 local fx=emitter(holder,'Sparkle',green);if fx then fx.Rate=3;fx.Texture='rbxasset://textures/particles/sparkles_main.dds' end
 return c*CFrame.new(-2.0,-.2,0).Position,c*CFrame.new(2.0,-.2,0).Position
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
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA('BasePart')then
   d.Massless=true;d:SetAttribute('PickaxeLevel',level)
   if d~=handle and d:GetAttribute('PickAnim')then d:SetAttribute('PickBase',handle.CFrame:ToObjectSpace(d.CFrame))end
  end
 end
 return model
end
-- Second hand of a paired pickaxe (Twin Claws): the left gauntlet ("left").
function Models.PickaxeOffhand(def,level)
 local v=def.Visual or{}
 if v.Kind~='Claws'then return nil end
 local model=Instance.new('Model');model.Name='PickaxeOffhand'
 local handle=part(model,'Handle',Vector3.new(1.1,1,1.15),CFrame.identity,rgb(v.Shaft),Enum.Material.Metal,{Massless=true})
 model.PrimaryPart=handle
 model:SetAttribute('Kind','Claws');model:SetAttribute('Theme',def.Theme or'Claws');model:SetAttribute('Level',level);model:SetAttribute('Grip','Glove')
 local a,b=gauntlet(model,v,1,'左')
 trailPoints(handle,a,b)
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
-- Animated pickaxe parts (PickAnim) get a Motor6D "PickJoint" instead, pivoting at PickJoint (a
-- model-space point; default the part's centre) with model-aligned axes, so clients can move
-- them through Motor6D.Transform (MiningClient.PickFX).
function Models.WeldToSelf(model)
 local root=model.PrimaryPart
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA('BasePart')then
   d.Anchored=false;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true
   if d~=root then
    if d:GetAttribute('PickAnim')then
     local joint=d:GetAttribute('PickJoint')
     local pivot=root.CFrame*CFrame.new(typeof(joint)=='Vector3'and joint or root.CFrame:PointToObjectSpace(d.CFrame.Position))
     local m=Instance.new('Motor6D');m.Name='PickJoint'
     m.C0=root.CFrame:ToObjectSpace(pivot);m.C1=d.CFrame:ToObjectSpace(pivot)
     m.Part0=root;m.Part1=d;m.Parent=d
    else
     local w=Instance.new('WeldConstraint');w.Part0=root;w.Part1=d;w.Parent=d
    end
   end
  end
 end
 return model
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
