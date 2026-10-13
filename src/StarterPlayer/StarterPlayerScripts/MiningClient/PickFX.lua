-- DOGROTS pickaxe pack, client side: every pickaxe's own hit / crit effects (Theme in
-- Config.Mining.Pickaxes), the living models (idle motion, rainbow / pulsing / flickering parts,
-- the TV screen, a trail while swinging or running) for every held pickaxe in the world and for
-- the market previews, and a short "hit" boost that exaggerates the motion on every strike
-- (eyes pop out, fingers squeeze, the saw spins faster...).
-- Animated parts carry the attributes MiningModels.Pickaxe writes (PickAnim, PickJoint, PickBase,
-- PickPhase, PickPop, PickRainbow, PickPulse, PickFlicker). Held models move through their
-- Motor6D.Transform (local only, written after the Animator in Stepped, like MiningClient.Anim);
-- anchored previews are moved directly.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local PickFX={}

local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local FIRE='rbxasset://textures/particles/fire_main.dds'
local C=Color3.fromRGB
local rad=math.rad
local sin,cos=math.sin,math.cos

-- MOTIONS ----------------------------------------------------------------------------------------
-- Each returns a CFrame in model axes applied at the part's joint. t = clock, ph = phase,
-- h = hit boost 0..1 (decays after every strike), pop = PickPop direction or nil.
local function blink(t,ph)return((t+ph)%3.4)<.14 and 1 or 0 end
local function twitch(t,ph)
 local k=math.floor(t*2.6+ph)
 return math.noise(k*.37,ph*1.7)>.18 and math.noise(k*.91,ph)*.9 or 0
end
local MOTIONS={
 Bob=function(t,ph,h)return CFrame.new(0,sin(t*3+ph)*.07,0)end,
 FlutterL=function(t,ph,h)return CFrame.Angles(0,sin(t*26+ph)*.85,0)end,
 FlutterR=function(t,ph,h)return CFrame.Angles(0,-sin(t*26+ph)*.85,0)end,
 ClenchL=function(t,ph,h)return CFrame.Angles(0,0,-(sin(t*1.6)+1)*.07-h*.32)end,
 ClenchR=function(t,ph,h)return CFrame.Angles(0,0,(sin(t*1.6)+1)*.07+h*.32)end,
 BobA=function(t,ph,h)return CFrame.new(0,sin(t*2.6)*.08+h*.25,0)end,
 BobB=function(t,ph,h)return CFrame.new(0,sin(t*2.6+math.pi)*.08+h*.25,0)end,
 Jiggle=function(t,ph,h)return CFrame.new(sin(t*7+ph)*.03+h*sin(t*41)*.12,sin(t*5+ph)*.05+h*sin(t*37)*.14,0)end,
 EyeLook=function(t,ph,h)return CFrame.Angles(sin(t*.7+ph)*.25+h*.3,sin(t*.53+ph*2)*.4,0)end,
 EyeTwitch=function(t,ph,h)local j=twitch(t,ph)*.35+h*sin(t*55)*.25;return CFrame.Angles(j,j*.7,0)end,
 Wave=function(t,ph,h)return CFrame.new(0,sin(t*3+ph)*.08*(1+h*3),sin(t*2.2+ph)*.06)end,
 Drip=function(t,ph,h)local k=(t*.55+ph)%1;return CFrame.new(0,-k*k*.6,0)end,
 Breathe=function(t,ph,h)return CFrame.new(0,sin(t*1.5)*.05+h*.12,0)end,
 Stalk=function(t,ph,h,pop)
  local r=CFrame.Angles(sin(t*1.3+ph)*.2,0,sin(t*1.1+ph*1.7)*.25)
  if pop and h>0 then return CFrame.new(pop*h*1.6)*r end
  return r
 end,
 HandSlow=function(t,ph,h)return CFrame.Angles(0,0,-t*.9)end,
 HandFast=function(t,ph,h)return CFrame.Angles(0,0,-t*5-h*25)end,
 HandBack=function(t,ph,h)return CFrame.Angles(0,0,t*4+h*20)end,
 Shake=function(t,ph,h)return CFrame.Angles(0,0,sin(t*42+ph)*(.04+h*.35))end,
 Fluff=function(t,ph,h)return CFrame.new(0,sin(t*2+ph)*.05,0)end,
 Twitch=function(t,ph,h)local j=twitch(t,ph)*.35+h*sin(t*60)*.4;return CFrame.Angles(j*.4,0,j)end,
 Tongue=function(t,ph,h)return CFrame.Angles(sin(t*4+ph)*.2+h*.7,0,sin(t*3+ph)*.15)end,
 Tentacle=function(t,ph,h)local k=.12*(1+h*2.5);return CFrame.Angles(sin(t*1.8+ph)*k,0,cos(t*1.5+ph)*k)end,
 Curl=function(t,ph,h)return CFrame.Angles((sin(t*1.2+ph)+1)*.1+h*.95,0,0)end,
 BlinkLow=function(t,ph,h)return CFrame.new(0,math.max(blink(t,ph),h>.6 and 1 or 0)*.3,0)end,
 BlinkHigh=function(t,ph,h)return CFrame.new(0,-math.max(blink(t,ph),h>.6 and 1 or 0)*.3,0)end,
 Spin=function(t,ph,h)return CFrame.Angles(0,0,-t*12)end,
 ClawOut=function(t,ph,h)return CFrame.new(0,(sin(t*1.4+ph)+1)*.18-.42+h*.5,0)end,
 Antenna=function(t,ph,h)return CFrame.Angles(0,0,sin(t*3+ph)*.12+h*.45*sin(t*44))end,
}

-- THEMES (hit / crit effects and trail colours) -------------------------------------------------
local THEMES={
 Wood={C(176,124,74),C(214,170,110),C(120,84,50)},
 Butterfly={C(150,230,255),C(255,214,90),C(255,150,220)},
 Brick={C(230,40,40),C(40,110,230),C(255,206,30),C(60,190,70),C(250,250,250)},
 Digits={C(235,40,52),C(250,250,250),C(30,30,34)},
 Gummy={C(255,92,190),C(170,255,90),C(255,236,90)},
 Slime={C(170,230,70),C(120,170,60),C(220,255,120)},
 Alarm={C(232,48,48),C(255,206,64),C(250,250,245)},
 Rainbow={C(255,120,200),C(255,230,110),C(130,210,255),C(190,140,255)},
 Zombie={C(90,170,255),C(150,230,255),C(120,170,110)},
 Clown={C(214,58,58),C(60,110,220),C(255,214,60),C(246,232,210)},
 Ink={C(70,96,220),C(140,80,200),C(20,20,40)},
 Fate={C(170,80,255),C(90,30,140),C(240,200,255)},
 Saw={C(255,170,60),C(255,230,140),C(220,226,236)},
 Anime={C(186,90,255),C(255,40,80),C(255,200,255)},
 Claws={C(240,244,255),C(255,40,90),C(160,90,255)},
 TV={C(110,255,130),C(255,80,220),C(90,220,255)},
}
PickFX.Colors=THEMES

function PickFX.new(ctx)
 local self:any={}
 local player=ctx.Player
 local FX=ctx.FX
 local folder=FX.Folder
 local function low()return FX.Low()end
 local function n(x)return math.max(1,math.floor(x*(low()and .45 or 1)+.5))end
 local function pal(theme)return THEMES[theme]or THEMES.Wood end
 local function pick(list)return list[math.random(1,#list)]end

 -- PRIMITIVE EFFECTS ----------------------------------------------------------------------------
 -- Text particles (digits, hearts, stars, clocks): pooled BillboardGuis that fly out and fade.
 local glyphPool={}
 local function glyph(pos,text,color,size,dir,life)
  local g=table.remove(glyphPool)
  if not g then
   g=Instance.new('BillboardGui');g.Name='PickGlyph';g.AlwaysOnTop=true;g.LightInfluence=0;g.MaxDistance=110
   g:SetAttribute('NoTranslate',true)
   local l=Instance.new('TextLabel');l.Name='T';l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.TextScaled=true
   l.FontFace=Font.fromEnum(Enum.Font.Arcade);l.TextStrokeTransparency=0;l.TextStrokeColor3=C(20,24,40)
   l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true);l.Parent=g
  end
  local l=g:FindFirstChild('T')::TextLabel
  size=size or 34
  g.Size=UDim2.fromOffset(size*math.max(1,#text*.7),size);g.StudsOffsetWorldSpace=Vector3.zero
  l.Text=text;l.TextColor3=color;l.TextTransparency=0;l.TextStrokeTransparency=0;l.Rotation=math.random(-25,25)
  local anchor=Instance.new('Attachment');anchor.Parent=workspace.Terrain;anchor.WorldPosition=pos
  g.Adornee=anchor;g.Parent=folder
  life=life or .8
  dir=dir or Vector3.new(math.random()-.5,math.random()*.8+.4,math.random()-.5)
  TweenService:Create(g,TweenInfo.new(life,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{StudsOffsetWorldSpace=dir*(2.5+math.random()*2)}):Play()
  TweenService:Create(l,TweenInfo.new(life*.45,Enum.EasingStyle.Linear,Enum.EasingDirection.In,0,false,life*.55),{TextTransparency=1,TextStrokeTransparency=1,Rotation=l.Rotation+math.random(-60,60)}):Play()
  task.delay(life+.05,function()
   anchor:Destroy();g.Adornee=nil;g.Parent=nil
   if #glyphPool<40 then table.insert(glyphPool,g)else g:Destroy()end
  end)
 end
 self.Glyph=glyph
 -- Small physical bits (bricks, pixels, drops, confetti) that fly, fall and fade.
 local function bits(pos,colors,count,size,speed,mat,shape,opts)
  opts=opts or{}
  for _=1,n(count)do
   local p=Instance.new('Part');p.Name='PickBit';p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Massless=true;p.CastShadow=false
   local s=size*(.7+math.random()*.6)
   p.Size=opts.Flat and Vector3.new(s,s*.25,s*.7)or Vector3.new(s,s,s)
   if shape then p.Shape=shape end
   p.Material=mat or Enum.Material.SmoothPlastic;p.Color=pick(colors);p.Transparency=opts.Transparency or 0
   p.CFrame=CFrame.new(pos)*CFrame.Angles(math.random()*6,math.random()*6,math.random()*6);p.Parent=folder
   local d=(Vector3.new(math.random()-.5,math.random()*.9+(opts.Up or .3),math.random()-.5)).Unit
   p.AssemblyLinearVelocity=d*speed*(.6+math.random()*.7)
   p.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*18
   TweenService:Create(p,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,opts.Life or .65),{Transparency=1}):Play()
   Debris:AddItem(p,(opts.Life or .65)+.5)
  end
 end
 self.Bits=bits
 -- Neon line pieces (lightning, scratches, slashes) that flash and fade.
 local function line(a,b,width,color,life,props)
  local len=(b-a).Magnitude;if len<.01 then return end
  local p=Instance.new('Part');p.Name='PickLine';p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
  p.Material=Enum.Material.Neon;p.Color=color;p.Size=Vector3.new(width,width,len)
  p.CFrame=CFrame.lookAt((a+b)/2,b);p.Parent=folder
  if props then for k,v in pairs(props)do(p::any)[k]=v end end
  TweenService:Create(p,TweenInfo.new(life or .25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=1,Size=Vector3.new(width*.2,width*.2,len)}):Play()
  Debris:AddItem(p,(life or .25)+.05)
  return p
 end
 local function bolt(a,b,color,segments)
  local prev=a
  segments=segments or 5
  for i=1,segments do
   local f=i/segments
   local q=a:Lerp(b,f)
   if i<segments then q+=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*1.1 end
   line(prev,q,.12,color,.18+math.random()*.08)
   prev=q
  end
 end
 local function camFacing(pos)
  local cam=workspace.CurrentCamera
  if not cam then return CFrame.new(pos)end
  return CFrame.lookAt(pos,cam.CFrame.Position)
 end
 -- A crescent (anime slash) in the plane facing the camera.
 local function slash(pos,color,radius,tilt,life)
  local f=camFacing(pos)*CFrame.Angles(0,0,tilt or 0)
  local segs=9;local prev
  for i=0,segs do
   local a=rad(-70+i*140/segs)
   local q=(f*CFrame.new(cos(a)*radius,sin(a)*radius,0)).Position
   if prev then line(prev,q,.16+.22*sin(i/segs*math.pi),color,life or .3)end
   prev=q
  end
 end
 local function scratches(pos,color,cross)
  local f=camFacing(pos)
  for i=-1,1 do
   local o=f*CFrame.new(i*.55,0,0)
   line((o*CFrame.new(-1.3,1.6,0)).Position,(o*CFrame.new(1.3,-1.6,0)).Position,.13,color,.32)
   if cross then line((o*CFrame.new(1.3,1.6,0)).Position,(o*CFrame.new(-1.3,-1.6,0)).Position,.13,color,.32)end
  end
 end
 local function shock(pos,color,size,life)
  local p=Instance.new('Part');p.Name='PickShock';p.Shape=Enum.PartType.Ball;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
  p.CastShadow=false;p.Material=Enum.Material.Neon;p.Color=color;p.Transparency=.45;p.Size=Vector3.one*.5;p.CFrame=CFrame.new(pos);p.Parent=folder
  TweenService:Create(p,TweenInfo.new(life or .35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.one*(size or 6),Transparency=1}):Play()
  Debris:AddItem(p,(life or .35)+.05)
 end
 local function burst(pos,colors,count,speed,tex,dir,opts)
  opts=opts or{}
  FX.Burst(pos,{Texture=tex or SPARK,Color=colors[1],Color2=colors[2]or colors[1],Count=count,Speed=NumberRange.new(speed*.5,speed),
   Direction=dir,Spread=opts.Spread,Acceleration=opts.Acceleration,Lifetime=opts.Lifetime,LightEmission=opts.LightEmission or .8,Size=opts.Size})
 end

 -- HIT EFFECTS PER THEME ------------------------------------------------------------------------
 -- (pos, dir, quality, crit, remote) -> world effects only (the 2D layer is MiningClient.Combo).
 local HIT={}
 HIT.Wood=function(pos,dir,q,crit)
  local c=pal('Wood')
  bits(pos,c,crit and 8 or 4,.22,16,Enum.Material.WoodPlanks,nil,{Flat=true})
  burst(pos,{C(190,160,120)},crit and 10 or 5,6,SMOKE,dir,{LightEmission=0})
 end
 HIT.Butterfly=function(pos,dir,q,crit)
  local c=pal('Butterfly')
  burst(pos,{c[1],C(255,255,255)},crit and 26 or 14,9,SPARK,dir)
  for i=1,n(crit and 6 or 3)do glyph(pos,pick({'🦋','✦','✧'}),pick(c),26,nil,.9)end
  bits(pos,{C(255,240,140),C(200,255,150)},crit and 10 or 5,.14,5,Enum.Material.Neon,Enum.PartType.Ball,{Up=1.2,Life=.9})
 end
 HIT.Brick=function(pos,dir,q,crit)
  local c=pal('Brick')
  bits(pos,c,crit and 18 or 9,.32,20,Enum.Material.SmoothPlastic,nil,{Up=.6})
  if crit then glyph(pos,'CLICK!',C(255,206,30),40)end
 end
 HIT.Digits=function(pos,dir,q,crit)
  local c=pal('Digits')
  for i=1,n(crit and 8 or 4)do glyph(pos,pick({'6','7','67','6','7'}),pick(c),pick({26,30,36}),nil,.7)end
  burst(pos,{C(255,60,70),C(255,255,255)},crit and 18 or 8,12,SPARK,dir)
  if crit then
   glyph(pos+Vector3.new(0,2,0),'67',C(235,40,52),150,Vector3.new(0,1,0),1.3)
   shock(pos,C(235,40,52),9)
  end
 end
 HIT.Gummy=function(pos,dir,q,crit)
  local c=pal('Gummy')
  bits(pos,c,crit and 16 or 8,.34,15,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.15,Up=.5})
  FX.Ring(pos,C(255,170,80),crit and 9 or 5,.4)
  burst(pos,{c[1],c[3]},crit and 14 or 6,7,SPARK,dir)
 end
 HIT.Slime=function(pos,dir,q,crit)
  local c=pal('Slime')
  bits(pos,c,crit and 18 or 9,.3,12,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.25,Up=.2,Life=.8})
  burst(pos,{C(150,200,70),C(80,110,40)},crit and 10 or 5,4,SMOKE,dir,{LightEmission=0})
  FX.Ring(pos-Vector3.new(0,1,0),C(170,230,70),crit and 10 or 6,.5)
 end
 HIT.Alarm=function(pos,dir,q,crit)
  local c=pal('Alarm')
  for i=0,(crit and 2 or 1)do task.delay(i*.08,function()FX.Ring(pos,i%2==0 and c[1]or c[2],5+i*3,.35)end)end
  for i=1,n(crit and 5 or 2)do glyph(pos,pick({'⏰','!','!!','⏱'}),pick(c),28)end
  if crit then glyph(pos+Vector3.new(0,1.5,0),'DRRRING!',C(255,206,64),60,Vector3.new(0,1,0),1)end
  burst(pos,{c[2],c[3]},crit and 16 or 8,10,SPARK,dir)
 end
 HIT.Rainbow=function(pos,dir,q,crit)
  for i=1,(crit and 6 or 3)do task.delay(i*.04,function()FX.Ring(pos,Color3.fromHSV((i/6+os.clock())%1,.6,1),3+i*1.6,.45)end)end
  for i=1,n(crit and 8 or 4)do glyph(pos,pick({'★','♥','✦','☁'}),Color3.fromHSV(math.random(),.55,1),pick({24,30,34}),nil,.9)end
  burst(pos,{C(255,140,220),C(255,240,120)},crit and 30 or 14,11,SPARK,dir)
  burst(pos,{C(255,255,255)},crit and 4 or 2,2,SMOKE,Vector3.new(0,1,0),{LightEmission=.2,Size=NumberSequence.new(1.2,2.2)})
 end
 HIT.Zombie=function(pos,dir,q,crit)
  local c=pal('Zombie')
  for i=1,(crit and 4 or 2)do bolt(pos,pos+Vector3.new(math.random()-.5,math.random()*.8+.2,math.random()-.5).Unit*(3+math.random()*2),pick({c[1],c[2]}),5)end
  burst(pos,{c[1],c[2]},crit and 18 or 9,14,SPARK,dir)
  bits(pos,{C(120,170,100),C(90,130,80)},crit and 6 or 3,.22,9,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.2})
 end
 HIT.Clown=function(pos,dir,q,crit)
  local c=pal('Clown')
  bits(pos,{C(255,60,80),C(60,160,255),C(255,220,60),C(120,255,120),C(220,120,255)},crit and 22 or 10,.2,14,Enum.Material.SmoothPlastic,nil,{Flat=true,Up=.9,Life=.9})
  for i=1,n(crit and 4 or 2)do glyph(pos,pick({'🕐','🕑','🕓','🕖','HA','HA!'}),pick(c),30)end
  if crit then glyph(pos+Vector3.new(0,1.6,0),'HONK!',C(255,214,60),70,Vector3.new(0,1,0),1.1)end
 end
 HIT.Ink=function(pos,dir,q,crit)
  local c=pal('Ink')
  bits(pos,c,crit and 18 or 9,.26,13,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.4,Life=.7})
  burst(pos,{C(40,30,80),C(20,20,40)},crit and 10 or 5,5,SMOKE,dir,{LightEmission=0})
  FX.Ring(pos,C(90,120,240),crit and 9 or 5,.4)
 end
 HIT.Fate=function(pos,dir,q,crit)
  local c=pal('Fate')
  for i=1,(crit and 5 or 2)do bolt(pos,pos+Vector3.new(math.random()-.5,math.random()-.2,math.random()-.5).Unit*(2+math.random()*2),c[1],4)end
  burst(pos,{c[2],C(30,10,50)},crit and 10 or 5,4,SMOKE,dir,{LightEmission=.1})
  shock(pos,c[1],crit and 8 or 4)
  if crit then glyph(pos+Vector3.new(0,1.5,0),'👁',C(255,255,255),80,Vector3.new(0,1,0),1)end
 end
 HIT.Saw=function(pos,dir,q,crit)
  local c=pal('Saw')
  burst(pos,{c[1],c[2]},crit and 50 or 26,30,SPARK,dir,{Spread=Vector2.new(25,25),Acceleration=Vector3.new(0,-60,0),Lifetime=NumberRange.new(.3,.6)})
  bits(pos,{C(200,206,214),C(140,146,156)},crit and 8 or 4,.18,22,Enum.Material.Metal)
  if crit then glyph(pos+Vector3.new(0,1.5,0),'HA-HA!',C(255,60,60),64,Vector3.new(0,1,0),1)end
 end
 HIT.Anime=function(pos,dir,q,crit)
  local c=pal('Anime')
  slash(pos,c[1],2.4,rad(math.random(-40,40)),.3)
  if crit or q==2 then slash(pos,c[2],2.9,rad(math.random(100,160)),.35)end
  burst(pos,{c[1],c[3]},crit and 24 or 12,12,SPARK,dir)
  if crit then glyph(pos+Vector3.new(0,1.6,0),'斬',C(255,60,90),90,Vector3.new(0,1,0),1.1)end
 end
 HIT.Claws=function(pos,dir,q,crit)
  local c=pal('Claws')
  scratches(pos,crit and c[2]or c[1],crit)
  burst(pos,{c[1],c[3]},crit and 20 or 10,15,SPARK,dir)
 end
 HIT.TV=function(pos,dir,q,crit)
  local c=pal('TV')
  bits(pos,c,crit and 22 or 11,.26,17,Enum.Material.Neon,nil,{Up=.5})
  for i=1,n(crit and 4 or 2)do glyph(pos,pick({'▣','■','▒','ERR'}),pick(c),26,nil,.6)end
  if crit then glyph(pos+Vector3.new(0,1.6,0),'NO SIGNAL',C(110,255,130),56,Vector3.new(0,1,0),1)end
 end

 -- theme, world position, surface normal, quality (1/2), crit, remote (another player's hit)
 function self.Hit(theme,pos,dir,quality,crit,remote)
  local fn=HIT[theme]or HIT.Wood
  if remote and low()then return end
  local ok,err=pcall(fn,pos,dir or Vector3.new(0,1,0),quality,crit,remote)
  if not ok and ctx.Report then ctx.Report('PickFX '..tostring(theme)..': '..tostring(err))end
  if crit and not remote then shock(pos,pal(theme)[1],7,.3)end
 end
 function self.Palette(theme)return pal(theme)end

 -- LIVING MODELS --------------------------------------------------------------------------------
 local tracked={} -- model -> entry
 local function build(model,anchored)
  local root=model.PrimaryPart or model:FindFirstChild('Handle')
  if not root then return nil end
  local e={Model=model,Root=root,Anchored=anchored,Parts={},Rainbow={},Pulse={},Flicker={},Hit=0,Theme=model:GetAttribute('Theme')or'Wood'}
  for _,d in ipairs(model:GetDescendants())do
   if d:IsA('BasePart')then
    local kinds=d:GetAttribute('PickAnim')
    if kinds then
     local list={}
     for k in string.gmatch(kinds,'[^,]+')do if MOTIONS[k]then table.insert(list,MOTIONS[k])end end
     local joint=d:GetAttribute('PickJoint')
     local base=d:GetAttribute('PickBase')
     table.insert(e.Parts,{Part=d,Motor=d:FindFirstChild('PickJoint'),Motions=list,Phase=d:GetAttribute('PickPhase')or 0,
      Joint=typeof(joint)=='Vector3'and CFrame.new(joint)or(typeof(base)=='CFrame'and CFrame.new(base.Position)or CFrame.identity),
      Base=typeof(base)=='CFrame'and base or CFrame.identity,Pop=d:GetAttribute('PickPop')})
    end
    if d:GetAttribute('PickRainbow')then table.insert(e.Rainbow,{Part=d,Phase=d:GetAttribute('PickPhase')or 0})end
    if d:GetAttribute('PickPulse')then table.insert(e.Pulse,{Part=d,Base=d.Transparency})end
    if d:GetAttribute('PickFlicker')then table.insert(e.Flicker,d)end
   end
  end
  local screen=model:FindFirstChild('ScreenGui',true)
  if screen then e.Noise=screen:FindFirstChild('Noise');e.Face=e.Noise and e.Noise:FindFirstChild('Face')end
  -- Trail between the head's two ends (held models only): the swing and the run leave a streak.
  if not anchored then
   local a,b=root:FindFirstChild('TrailA'),root:FindFirstChild('TrailB')
   if a and b then
    local colors=pal(e.Theme)
    local tr=Instance.new('Trail');tr.Name='PickTrail';tr.Attachment0=a;tr.Attachment1=b
    tr.Lifetime=.28;tr.MinLength=.05;tr.LightEmission=.9;tr.FaceCamera=false
    tr.Color=ColorSequence.new(colors[1],colors[2]or colors[1])
    tr.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,1)})
    tr.WidthScale=NumberSequence.new(1,.2);tr.Parent=root
    e.Trail=tr
   end
  end
  return e
 end
 function self.Track(model,anchored)
  if tracked[model]then return tracked[model]end
  local e=build(model,anchored)
  if not e then return nil end
  tracked[model]=e
  model.AncestryChanged:Connect(function()if not model:IsDescendantOf(game)then tracked[model]=nil end end)
  return e
 end
 function self.Untrack(model)tracked[model]=nil end
 -- Exaggerates the motion of a character's held pickaxe(s) for a moment (every strike).
 function self.HitPulse(character,strength)
  if not character then return end
  for _,name in ipairs({'MiningHeldPickaxe','MiningHeldPickaxeL'})do
   local m=character:FindFirstChild(name)
   local e=m and(tracked[m]or self.Track(m,false))
   if e then e.Hit=math.max(e.Hit,strength or 1)end
  end
 end
 function self.PreviewPulse(model)local e=tracked[model];if e then e.Hit=1 end end

 local function watchCharacter(character)
  local function add(child)
   if child:IsA('Model')and(child.Name=='MiningHeldPickaxe'or child.Name=='MiningHeldPickaxeL')then
    task.defer(function()if child.Parent then self.Track(child,false)end end)
   end
  end
  for _,c in ipairs(character:GetChildren())do add(c)end
  character.ChildAdded:Connect(add)
 end
 local function watchPlayer(p)
  if p.Character then watchCharacter(p.Character)end
  p.CharacterAdded:Connect(watchCharacter)
 end
 for _,p in ipairs(Players:GetPlayers())do watchPlayer(p)end
 Players.PlayerAdded:Connect(watchPlayer)

 local function reduced()return FX.ReducedMotion and FX.ReducedMotion()end
 local lastFar=0
 local function animate(e,t,dt)
  e.Hit=math.max(0,e.Hit-dt*2.2)
  local h=e.Hit*e.Hit
  local still=reduced()
  for _,p in ipairs(e.Parts)do
   local T=CFrame.identity
   if not still then for _,fn in ipairs(p.Motions)do T=T*fn(t,p.Phase,h,p.Pop)end end
   if p.Motor then
    p.Motor.Transform=T
   elseif e.Anchored and p.Part.Parent then
    p.Part.CFrame=e.Root.CFrame*p.Joint*T*p.Joint:Inverse()*p.Base
   end
  end
  for _,r in ipairs(e.Rainbow)do r.Part.Color=Color3.fromHSV((t*.3+r.Phase)%1,.6,1)end
  for _,r in ipairs(e.Pulse)do r.Part.Transparency=math.clamp(r.Base+(sin(t*3.2)+1)*.18-h*.3,0,.95)end
  for _,f in ipairs(e.Flicker)do f.Transparency=(math.random()<.35 and h<.2)and 1 or 0 end
  if e.Noise then
   local g=math.random()
   e.Noise.BackgroundColor3=Color3.new(.04+g*.06,.12+g*.14,.07+g*.06)
   if e.Face then e.Face.Position=UDim2.fromOffset((math.random()-.5)*(2+h*14),(math.random()-.5)*(1+h*8))end
  end
 end
 RunService.Stepped:Connect(function(_,dt)
  local cam=workspace.CurrentCamera;if not cam then return end
  local t=os.clock()
  local far=t-lastFar>.1;if far then lastFar=t end
  local camPos=cam.CFrame.Position
  for model,e in pairs(tracked)do
   if not model.Parent or not e.Root.Parent then tracked[model]=nil
   elseif e.Anchored then -- previews (in a ViewportFrame) always
    animate(e,t,dt)
   else
    local d=(e.Root.Position-camPos).Magnitude
    -- Nearby every frame, far away at 10 Hz, very far not at all.
    if d<70 then animate(e,t,dt)elseif d<160 and far then animate(e,t,.1)end
   end
  end
 end)

 return self
end

return PickFX
