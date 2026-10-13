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
local function wedge(parent,name,size,cf,color,mat)
 local p=Instance.new('WedgePart');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=mat or Enum.Material.SmoothPlastic
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Parent=parent;return p
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
function Models.Ore(def,seed,rootCF,scale)
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
 local function chunk(offset,size)
  local cf=rootCF*CFrame.new(offset*scale)*CFrame.Angles(rng:NextNumber(-.6,.6),rng:NextNumber(0,math.pi*2),rng:NextNumber(-.6,.6))
  local p=part(model,'Chunk',size*scale,cf,shade(rock),rockMat)
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
 if style=='Nugget'then
  for i=1,13 do
   local s=surface[(i*5)%#surface+1]
   local sz=rng:NextNumber(.7,1.35)
   local cf=rootCF*CFrame.new((s.Pos+s.Dir*.25)*scale)*CFrame.Angles(rng:NextNumber(0,6),rng:NextNumber(0,6),rng:NextNumber(0,6))
   local p=part(model,'Accent',Vector3.new(sz,sz*.8,sz)*scale,cf,accent,accentMat,{Reflectance=v.Reflectance or .15})
   p:SetAttribute('OreAccent',true)
  end
 elseif style=='Crystal'or style=='Void'then
  local count=v.Crystals or 8
  for i=1,count do
   local s=surface[(i*7)%#surface+1]
   local dir=(s.Dir+Vector3.new(0,.9,0)).Unit
   local w=rng:NextNumber(.75,1.25);local h=rng:NextNumber(2.4,4.4)*(i==1 and 1.35 or 1)
   local base=rootCF*CFrame.new(s.Pos*scale)*alignY(dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
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
   local cf=rootCF*CFrame.new((s.Pos+s.Dir*.35)*scale)*alignY(s.Dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
   local p=part(model,'Vein',Vector3.new(len,.34,.5)*scale,cf,accent,Enum.Material.Neon,{CastShadow=false})
   p:SetAttribute('OreAccent',true)
  end
 elseif style=='Banded'then
  for i=1,12 do
   local s=surface[(i*5)%#surface+1]
   local cf=rootCF*CFrame.new((s.Pos+s.Dir*.4)*scale)*alignY(s.Dir)*CFrame.Angles(0,rng:NextNumber(0,6),0)
   local p=part(model,'Band',Vector3.new(rng:NextNumber(1.8,2.8),.45,rng:NextNumber(1,1.6))*scale,cf,accent,accentMat,{Reflectance=v.Reflectance or .2})
   p:SetAttribute('OreAccent',true)
  end
 end
 if (v.Glow or 0)>0 then
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
-- shifted by -Y * (length * .32).
function Models.Pickaxe(def,level)
 local v=def.Visual or{}
 local model=Instance.new('Model');model.Name='Pickaxe'
 local len=v.Length or 4.2
 local shaft=rgb(v.Shaft,{120,82,48});local head=rgb(v.Head,def.Color);local trim=rgb(v.Trim,{60,60,64})
 local handle=part(model,'Handle',Vector3.new(.32,len,.32),CFrame.identity,shaft,material(v.ShaftMaterial or'Wood'),{Massless=true})
 model.PrimaryPart=handle
 local top=CFrame.new(0,len*.5-.2,0)
 part(model,'Grip',Vector3.new(.4,len*.28,.4),CFrame.new(0,-len*.32,0),trim,material(v.GripMaterial or'Fabric'),{Massless=true})
 part(model,'Binding',Vector3.new(.62,.58,.62),top,trim,material(v.TrimMaterial or'Metal'),{Massless=true})
 local headMat=material(v.HeadMaterial or'Metal')
 local span=v.Span or 1.55
 for side=-1,1,2 do
  local arm=part(model,'HeadArm',Vector3.new(span,.46,.5),top*CFrame.new(side*span*.5,0,0)*CFrame.Angles(0,0,side*math.rad(-12)),head,headMat,{Massless=true})
  local tipCF=arm.CFrame*CFrame.new(side*(span*.5+.32),-.04,0)*CFrame.Angles(0,side>0 and math.pi*.5 or-math.pi*.5,0)
  wedge(model,'HeadTip',Vector3.new(.5,.42,.66),tipCF*CFrame.Angles(math.pi*.5,0,0),head,headMat).Massless=true
 end
 if v.Glow then
  -- Glowing edge along the underside of each arm.
  for side=-1,1,2 do
   part(model,'HeadGlow',Vector3.new(span*.8,.1,.3),top*CFrame.new(side*span*.5,-.27,0)*CFrame.Angles(0,0,side*math.rad(-12)),rgb(v.Glow),Enum.Material.Neon,{Massless=true,CastShadow=false})
  end
  local light=Instance.new('PointLight');light.Color=rgb(v.Glow);light.Range=7;light.Brightness=1.4;light.Shadows=false;light.Parent=model:FindFirstChild('Binding')
 end
 if v.Gem then
  part(model,'Gem',Vector3.new(.62,.62,.62),top*CFrame.new(0,.42,0),rgb(v.Gem),Enum.Material.Neon,{Massless=true,Shape=Enum.PartType.Ball,CastShadow=false})
 end
 if v.Spikes then
  for i=1,v.Spikes do
   local x=(i-(v.Spikes+1)/2)*.42
   wedge(model,'Spike',Vector3.new(.22,.55,.36),top*CFrame.new(x,.48,0)*CFrame.Angles(0,math.pi*.5,0),rgb(v.SpikeColor or v.Glow,v.Head),Enum.Material.Neon).Massless=true
  end
 end
 if v.Halo then
  part(model,'Halo',Vector3.new(.12,2.2,2.2),top*CFrame.new(0,.15,0)*CFrame.Angles(0,math.rad(90),0),rgb(v.Halo),Enum.Material.Neon,{Massless=true,Shape=Enum.PartType.Cylinder,Transparency=.25,CastShadow=false})
 end
 if v.FX then
  local holder=part(model,'PickFX',Vector3.new(span*2,.6,.6),top,head,Enum.Material.SmoothPlastic,{Transparency=1,Massless=true,CastShadow=false})
  local e=emitter(holder,v.FX,v.Glow and rgb(v.Glow) or head);if e then e.Rate=e.Rate*.6 end
 end
 for _,d in ipairs(model:GetDescendants())do if d:IsA('BasePart')then d:SetAttribute('PickaxeLevel',level)end end
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
function Models.WeldToSelf(model)
 local root=model.PrimaryPart
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA('BasePart')then
   d.Anchored=false;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true
   if d~=root then
    local w=Instance.new('WeldConstraint');w.Part0=root;w.Part1=d;w.Parent=d
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
