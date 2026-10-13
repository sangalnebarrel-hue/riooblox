
local Run=game:GetService('RunService')
local map=workspace:WaitForChild('DOGROTS_District');local line=map:WaitForChild('03_DogLine')
local portal=line:FindFirstChild('BeltEndPortal',true)
while not portal do line.DescendantAdded:Wait();portal=line:FindFirstChild('BeltEndPortal',true) end
local anchor=portal:WaitForChild('SwirlAnchor')
local pieces={}
for i=1,18 do local p=Instance.new('Part');p.Size=Vector3.new(.5,.5,.5);p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Material=Enum.Material.Neon;p.Color=Color3.fromRGB(190,119,255);p.Parent=portal;pieces[i]=p end
Run.Heartbeat:Connect(function()
 local cam=workspace.CurrentCamera;if not cam or (cam.CFrame.Position-anchor.Position).Magnitude>350 then return end
 local t=workspace:GetServerTimeNow()
 for i,p in ipairs(pieces)do local a=t*.7+i*math.pi*2/18;local r=4+i%3*1.3;p.Position=anchor.Position+Vector3.new(math.cos(a)*r,math.sin(a)*r*1.5,math.sin(t+i)*.6)end
end)

local Audio=require(game.ReplicatedStorage.RewardAudio)
Audio.Ambience(anchor,'NULL_HOUR/ambient')
local active=line:WaitForChild('ActiveDogs')
-- The lucky block's arrival sound now plays with its mouth-lip FX (LuckyArrivalFX: LuckyAudio
-- Arrive when the block leaves the mouth), not here at spawn deep inside the throat.
local mouth=map:WaitForChild('02_DogFactory'):FindFirstChild('MouthAmbienceAnchor',true)
if mouth then Audio.Ambience(mouth,'lucky/ambience')end

---------------------------------------------------------------- lucky block exits
-- Client-only FX when a lucky block leaves the tongue: swallowed by the BeltEndPortal
-- (State 'Despawning' at the end of the line) or bought (State 'Claimed', destroyed by the
-- server in the same frame, so its last pivot is captured on the attribute change).
-- Everything lives in workspace.DOGROTS_LuckyFX, outside WorldDetailQuality and the model.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local player=Players.LocalPlayer
local Show,LuckyAudio
do
 local lucky=RS:WaitForChild('Lucky',30)
 if lucky then
  local okShow,s=pcall(require,lucky:WaitForChild('LuckyShow',10))
  local okAudio,a=pcall(require,lucky:WaitForChild('LuckyAudio',10))
  if okShow then Show=s end
  if okAudio then LuckyAudio=a end
 end
end
if not Show then warn('DogLinePortalFX: LuckyShow missing, block exit FX disabled');return end

local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local WHITE=Color3.new(1,1,1)
local GOLD=Color3.fromRGB(255,205,70)
local NAVY=Color3.fromRGB(23,43,76)
local rng=Random.new()
local function rand(a,b)return rng:NextNumber(a,b)end
local energy=portal:FindFirstChild('PortalEnergy',true)
local PORTAL=(energy and energy:IsA('BasePart'))and energy.Position or Vector3.new(0,8.84,136.5)

local function fxRoot()
 local root=workspace:FindFirstChild('DOGROTS_LuckyFX')
 if not root then root=Instance.new('Folder');root.Name='DOGROTS_LuckyFX';root.Parent=workspace end
 return root
end
local function near(position,radius)
 local cam=workspace.CurrentCamera
 return cam~=nil and(cam.CFrame.Position-position).Magnitude<=radius
end
local function part(folder,props)
 local p=Instance.new('Part')
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 p.Material=Enum.Material.Neon;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 for k,v in pairs(props)do(p::any)[k]=v end
 p.Parent=folder
 return p
end
-- One self-cleaning FX group: steps run each frame until they return false; the folder is
-- destroyed after `seconds` whatever happens.
local function group(name,seconds)
 local folder=Instance.new('Folder');folder.Name=name;folder.Parent=fxRoot()
 local steps={}
 local started=os.clock()
 local connection;connection=Run.RenderStepped:Connect(function(dt)
  if not folder.Parent then connection:Disconnect();return end
  local age=os.clock()-started
  local i=1
  while i<=#steps do
   local ok,keep=pcall(steps[i],dt,age)
   if not ok then warn('DogLinePortalFX:',keep)end
   if not ok or keep==false then table.remove(steps,i)else i+=1 end
  end
 end)
 task.delay(seconds,function()connection:Disconnect();folder:Destroy()end)
 return folder,function(fn)table.insert(steps,fn)end
end
local function burst(folder,position,color,count,props)
 local a=part(folder,{Name='Burst',Size=Vector3.one*.2,Position=position,Transparency=1})
 local e=Instance.new('ParticleEmitter')
 e.Texture=SPARK;e.Rate=0;e.LightEmission=1;e.LightInfluence=0;e.Lifetime=NumberRange.new(.5,1.1)
 e.Speed=NumberRange.new(5,12);e.SpreadAngle=Vector2.new(180,180);e.Size=NumberSequence.new(.55,0)
 e.Transparency=NumberSequence.new(0,1);e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-180,180)
 if typeof(color)=='ColorSequence'then e.Color=color else e.Color=ColorSequence.new(color::Color3)end
 for k,v in pairs(props or{})do(e::any)[k]=v end
 e.Parent=a
 e:Emit(Show.Low()and math.max(1,math.floor(count*.35))or count)
 Debris:AddItem(a,3)
end
-- A ring of neon segments in the plane (u, w) around `center`, radius r0 -> r1, fading.
local function ring(folder,every,center,u,w,color,r0,r1,seconds,thick)
 local n=Show.Low()and 12 or 22
 local parts={}
 for i=1,n do parts[i]=part(folder,{Name='Segment',Color=color,Size=Vector3.new(thick,thick,1)})end
 local up=u:Cross(w).Unit
 every(function(_,age)
  local a=math.min(age/seconds,1)
  local r=r0+(r1-r0)*(1-(1-a)^2.6)
  local width=2*math.pi*math.max(r,.05)/n*1.1
  for i,p in ipairs(parts)do
   local t0,t1=(i-1)/n*math.pi*2,i/n*math.pi*2
   local a0=center+u*math.cos(t0)*r+w*math.sin(t0)*r
   local a1=center+u*math.cos(t1)*r+w*math.sin(t1)*r
   p.Size=Vector3.new(thick,thick,width);p.CFrame=CFrame.lookAt((a0+a1)/2,a1,up);p.Transparency=a^1.3
  end
  if a>=1 then for _,p in ipairs(parts)do p:Destroy()end;return false end
  return true
 end)
end
local function sound(cue,position,...)
 if not LuckyAudio then return end
 local speaker=part(fxRoot(),{Name='LuckyExitSpeaker',Size=Vector3.one*.2,Position=position,Transparency=1})
 Debris:AddItem(speaker,8)
 local ok,err=pcall(LuckyAudio.Play,cue,speaker,...)
 if not ok then warn('DogLinePortalFX sound:',err)end
end
local function rankOf(model)
 local r=model:GetAttribute('LuckyRank')
 if type(r)=='number'then return Show.Rank(r)end
 return Show.Rank(model:GetAttribute('LuckyBlockRarity')or'Common')
end
local function pivotOf(model)
 local root=model.PrimaryPart or model:FindFirstChild('RootPart')
 if root and root:IsA('BasePart')then return root.Position end
 local ok,cf=pcall(function()return model:GetPivot()end)
 return ok and cf.Position or nil
end
local function isRussian()
 local ok,locale=pcall(function()
  local LS=game:GetService('LocalizationService')
  if Run:IsStudio()then return LS.RobloxLocaleId end
  return player.LocaleId or LS.RobloxLocaleId
 end)
 return ok and type(locale)=='string'and locale:sub(1,2):lower()=='ru'
end

-- The block is pulled apart into shards that spiral into the portal, which gulps them with
-- a contracting ring, a flash and a sparkle spray.
local function swallowed(model)
 local from=pivotOf(model);if not from or not near(from,260)then return end
 local rank=rankOf(model);local color,accent=Show.World[rank],Show.Accent[rank]
 local folder,every=group('LuckyPortalSwallow',3)
 local toPortal=(from-PORTAL).Magnitude<40
 local target=toPortal and PORTAL or from+Vector3.new(0,6,0)
 local shards={}
 for i=1,(Show.Low()and 5 or 11)do
  shards[i]={Part=part(folder,{Name='Shard',Color=i%3==0 and WHITE or(i%2==0 and accent or color),Size=Vector3.one*rand(.35,.7),
   Position=from+Vector3.new(rand(-1.6,1.6),rand(-1.2,1.6),rand(-1.6,1.6))}),Delay=rand(0,.18),Spin=rand(5,9)*(i%2==0 and 1 or-1)}
  shards[i].Start=shards[i].Part.Position
 end
 every(function(_,age)
  local alive=false
  for _,s in ipairs(shards)do
   local p=s.Part
   if p.Parent then
    local a=math.clamp((age-s.Delay)/.6,0,1)
    if a>=1 then p:Destroy()else
     alive=true
     local e=a*a*(3-2*a)
     local base=s.Start:Lerp(target,e)
     local swirl=(1-e)*1.8
     local ang=age*s.Spin
     p.CFrame=CFrame.new(base+Vector3.new(math.cos(ang)*swirl,math.sin(ang)*swirl,0))*CFrame.Angles(age*8,age*6,0)
     p.Size=Vector3.one*math.max(.05,.7*(1-a*.85))
     p.Transparency=a^3
    end
   end
  end
  return alive
 end)
 -- The portal gulps: a ring contracting on its face, then a flash and a spray.
 if toPortal then
  ring(folder,every,PORTAL+Vector3.new(0,0,-.6),Vector3.xAxis,Vector3.yAxis,color,9,.6,.55,.35)
 end
 task.delay(.55,function()
  if not folder.Parent then return end
  local disc=part(folder,{Name='Gulp',Shape=Enum.PartType.Cylinder,Color=accent,Size=Vector3.new(.2,2,2),
   CFrame=CFrame.new(target+Vector3.new(0,0,-.5))*CFrame.Angles(0,math.pi/2,0),Transparency=.2})
  TweenService:Create(disc,TweenInfo.new(.45,Enum.EasingStyle.Quad),{Size=Vector3.new(.2,14,14),Transparency=1}):Play()
  local light=Instance.new('PointLight');light.Color=color;light.Range=22;light.Brightness=4;light.Shadows=false;light.Parent=disc
  TweenService:Create(light,TweenInfo.new(.6),{Brightness=0}):Play()
  burst(folder,target,ColorSequence.new(color,accent),18+rank*4,{Speed=NumberRange.new(6,14),Drag=2})
 end)
 sound('Whoosh',from,1.3)
 task.delay(.5,function()sound('Tick',target,.55+rank*.05)end)
end

-- Bought: the block pops with a ring, a sparkle spray and gold coins that hop up and fly
-- to the buyer (the nearest character, who triggered the 12-stud prompt), plus a '+1' tag.
local function claimed(model,from)
 if not from or not near(from,180)then return end
 local rank=rankOf(model);local color,accent=Show.World[rank],Show.Accent[rank]
 local folder,every=group('LuckyBuyPop',2.6)
 local buyer
 local best=16
 for _,p in ipairs(Players:GetPlayers())do
  local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
  if root and root:IsA('BasePart')and(root.Position-from).Magnitude<best then best=(root.Position-from).Magnitude;buyer=root end
 end
 local ground=Vector3.new(from.X,from.Y-2.2,from.Z)
 ring(folder,every,ground,Vector3.xAxis,Vector3.zAxis,GOLD,.6,7,.45,.35)
 ring(folder,every,ground+Vector3.new(0,.05,0),Vector3.xAxis,Vector3.zAxis,color,.4,4.5,.4,.25)
 burst(folder,from,ColorSequence.new(GOLD,color),26,{Speed=NumberRange.new(8,16),Drag=2.5})
 local flash=part(folder,{Name='Pop',Shape=Enum.PartType.Ball,Color=accent:Lerp(WHITE,.5),Size=Vector3.one*3,Position=from,Transparency=.2})
 TweenService:Create(flash,TweenInfo.new(.3,Enum.EasingStyle.Quad),{Size=Vector3.one*7.5,Transparency=1}):Play()
 local coins={}
 for i=1,(Show.Low()and 5 or 10)do
  local ang=rand(0,math.pi*2)
  coins[i]={Part=part(folder,{Name='Coin',Shape=Enum.PartType.Cylinder,Color=i%4==0 and accent or GOLD,Size=Vector3.new(.15,.9,.9),Position=from}),
   V=Vector3.new(math.cos(ang)*rand(3,6),rand(12,17),math.sin(ang)*rand(3,6)),Delay=rand(0,.12)}
 end
 every(function(dt,age)
  local alive=false
  for _,c in ipairs(coins)do
   local p=c.Part
   if p.Parent then
    local t=age-c.Delay
    if t>=1.25 then p:Destroy()elseif t>0 then
     alive=true
     local position
     if t<.45 or not buyer or not buyer.Parent then
      c.V+=Vector3.new(0,-40*dt,0);position=p.Position+c.V*dt
      c.Home=position
     else
      -- Homing into the buyer, shrinking as it is 'collected'.
      local a=math.min((t-.45)/.5,1)
      position=(c.Home or p.Position):Lerp(buyer.Position+Vector3.new(0,1,0),a*a)
      p.Size=Vector3.new(.15,.9,.9)*(1-a*.7)
     end
     p.CFrame=CFrame.new(position)*CFrame.Angles(0,age*12,math.pi/2+age*3)
     p.Transparency=t>1 and(t-1)/.25 or 0
    end
   end
  end
  return alive
 end)
 -- '+1 LUCKY BLOCK' tag floating up (world text, so it picks its own language).
 local tagAnchor=part(folder,{Name='Tag',Size=Vector3.one*.2,Position=from+Vector3.new(0,2.5,0),Transparency=1})
 local bb=Instance.new('BillboardGui');bb.Name='LuckyBuyTag';bb.Adornee=tagAnchor;bb.Size=UDim2.fromOffset(220,54)
 bb.LightInfluence=0;bb.AlwaysOnTop=true;bb.MaxDistance=90;bb:SetAttribute('NoTranslate',true)
 local label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.Font=Enum.Font.FredokaOne
 label.TextScaled=true;label.TextColor3=color:Lerp(WHITE,.35);label.TextStrokeTransparency=1
 label.Text=isRussian()and'+1 ЛАКИ-БЛОК!'or'+1 LUCKY BLOCK!';label:SetAttribute('NoTranslate',true)
 local stroke=Instance.new('UIStroke');stroke.Color=NAVY;stroke.Thickness=3;stroke.Parent=label
 label.Parent=bb;bb.Parent=tagAnchor
 every(function(_,age)
  local a=math.min(age/1.6,1)
  tagAnchor.Position=from+Vector3.new(0,2.5+a*3.5,0)
  local pop=age<.15 and age/.15*1.2 or math.max(1,1.2-(age-.15)*2)
  bb.Size=UDim2.fromOffset(220*pop,54*pop)
  label.TextTransparency=a<.7 and 0 or(a-.7)/.3;stroke.Transparency=label.TextTransparency
  return a<1
 end)
 sound('Buy',from)
end

local function watchBlock(model)
 if not model:IsA('Model')then return end
 if model:GetAttribute('LuckyVisual')~=true and model:GetAttribute('LuckyBlockRarity')==nil then
  if model:GetAttribute('DogId')~=nil then return end
  -- Lucky attributes ride with the model; wait a moment in case they are late.
  local deadline=os.clock()+1
  while model.Parent and model:GetAttribute('LuckyVisual')~=true and model:GetAttribute('LuckyBlockRarity')==nil and os.clock()<deadline do task.wait(.1)end
  if model:GetAttribute('LuckyVisual')~=true and model:GetAttribute('LuckyBlockRarity')==nil then return end
 end
 local done=false
 local stateChanged,ancestry
 local function finish()
  done=true
  if stateChanged then stateChanged:Disconnect()end
  if ancestry then ancestry:Disconnect()end
 end
 stateChanged=model:GetAttributeChangedSignal('State'):Connect(function()
  if done then return end
  local state=model:GetAttribute('State')
  if state=='Claimed'then
   -- Read the pivot now: the server destroys the model in the same frame.
   local from=pivotOf(model);finish()
   task.spawn(claimed,model,from)
  elseif state=='Despawning'then
   finish()
   task.spawn(swallowed,model)
  end
 end)
 ancestry=model.AncestryChanged:Connect(function()
  if not model:IsDescendantOf(active)then finish()end
 end)
end
active.ChildAdded:Connect(function(model)task.spawn(watchBlock,model)end)
for _,model in ipairs(active:GetChildren())do task.spawn(watchBlock,model)end
