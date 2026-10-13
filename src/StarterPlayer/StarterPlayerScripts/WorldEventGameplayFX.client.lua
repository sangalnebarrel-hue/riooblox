-- The playable side of world events, drawn on every client (the server applies gravity,
-- movement, the tongue and rewards: ServerScriptService.WorldEventGameplay). Per the active
-- event's Perks.Effects: flashlights in the BLACKOUT, UFO tractor beams that really lift you
-- in low gravity, EARTHQUAKE jolts, trails behind every player, DOG RUSH speed lines, its banner,
-- pup progress chip, runaway pups and catch bursts, and NULL HOUR glitches. Also celebrates server
-- luck (Lucky Server products) for everyone.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Tween=game:GetService('TweenService')
local TextChat=game:GetService('TextChatService')
local package=RS:WaitForChild('WorldEvents')
local Definitions=require(package:WaitForChild('WorldEventDefinitions'))
local stateFolder=package:WaitForChild('State')
local player=Players.LocalPlayer
local C=Color3.fromRGB
local rng=Random.new()
local active -- {Def, Generation, Folder, Connections, Cleanups}

local function reduced()return player:GetAttribute('ReducedMotion')==true end
local function low()return player:GetAttribute('WorldEventFX')=='Low'end
local function part(props,parent)
 local p=Instance.new('Part');p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 p.Material=Enum.Material.Neon;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 for k,v in pairs(props)do (p::any)[k]=v end
 p.Parent=parent;return p
end
local function screen()
 local gui=player:WaitForChild('PlayerGui'):FindFirstChild('DOGROTS_EventGameplay')
 if not gui then gui=Instance.new('ScreenGui');gui.Name='DOGROTS_EventGameplay';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=90;gui:SetAttribute('HideWithUI',true);gui.Parent=player.PlayerGui end
 return gui
end
local function rootOf(character)return character and character:FindFirstChild('HumanoidRootPart')end
local function grounded(character)
 local hum=character and character:FindFirstChildOfClass('Humanoid')
 return hum and hum.FloorMaterial~=Enum.Material.Air
end
local shakeUntil,shakePower=0,0
Run:BindToRenderStep('DOGROTS_EventGameplayShake',Enum.RenderPriority.Camera.Value+3,function()
 local now=os.clock();if now>shakeUntil or reduced()then return end
 local c=workspace.CurrentCamera;if not c or c.CameraType==Enum.CameraType.Scriptable then return end
 local g=math.min(shakeUntil-now,1)*shakePower
 c.CFrame*=CFrame.new(math.noise(now*19)*g,math.noise(0,now*23)*g,0)*CFrame.Angles(0,0,math.noise(now*13,2)*g*.03)
end)
local function shake(power,seconds)shakeUntil=math.max(shakeUntil,os.clock()+seconds);shakePower=math.max(shakePower*.5,power)end

---------------------------------------------------------------- per-character effects
local function eachCharacter(fn)
 local seen={}
 local function bind(p)
  local function apply(character)if character then task.defer(fn,p,character)end end
  table.insert(active.Connections,p.CharacterAdded:Connect(apply))
  apply(p.Character)
 end
 for _,p in ipairs(Players:GetPlayers())do bind(p);seen[p]=true end
 table.insert(active.Connections,Players.PlayerAdded:Connect(bind))
end
-- Deferred per character: the event may have ended (or another begun) before it runs, and a
-- freshly spawned or streamed character may not have its parts yet.
local function trail(p,character,color)
 local mine=active;if not mine then return end
 local root=character:WaitForChild('HumanoidRootPart',5)
 if active~=mine or not root or root:FindFirstChild('DOGROTS_EventTrail')then return end
 local a0=Instance.new('Attachment');a0.Name='DOGROTS_EventTrailTop';a0.Position=Vector3.new(0,1.2,0);a0.Parent=root
 local a1=Instance.new('Attachment');a1.Name='DOGROTS_EventTrailBottom';a1.Position=Vector3.new(0,-1.6,0);a1.Parent=root
 local t=Instance.new('Trail');t.Name='DOGROTS_EventTrail';t.Attachment0=a0;t.Attachment1=a1;t.Lifetime=.55;t.LightEmission=.8;t.FaceCamera=true
 t.MinLength=.2;t.WidthScale=NumberSequence.new(1,0);t.Transparency=NumberSequence.new(.25,1)
 t.Color=color;t.Parent=root
 table.insert(active.Cleanups,function()t:Destroy();a0:Destroy();a1:Destroy()end)
end
local function flashlight(p,character)
 local mine=active;if not mine then return end
 local head=character:WaitForChild('Head',5)or rootOf(character)
 if active~=mine or not head or head:FindFirstChild('DOGROTS_Flashlight')then return end
 local s=Instance.new('SpotLight');s.Name='DOGROTS_Flashlight';s.Face=Enum.NormalId.Front;s.Angle=55;s.Range=58;s.Brightness=p==player and 3.2 or 2
 s.Color=C(255,244,214);s.Shadows=p==player;s.Parent=head
 local glow=Instance.new('PointLight');glow.Name='DOGROTS_FlashlightGlow';glow.Range=10;glow.Brightness=.6;glow.Color=C(200,220,255);glow.Shadows=false;glow.Parent=head
 table.insert(active.Cleanups,function()s:Destroy();glow:Destroy()end)
end

---------------------------------------------------------------- set pieces
local function tractorBeams(def)
 -- Beams sweep down near you; stand in one and the saucer lifts you (you own your character).
 local color=def.ColorTheme
 local nextBeam=os.clock()+3
 local beams={}
 table.insert(active.Connections,Run.Heartbeat:Connect(function(dt)
  local root=rootOf(player.Character)
  if os.clock()>=nextBeam and root then
   nextBeam=os.clock()+rng:NextNumber(7,12)
   local a=rng:NextNumber(0,math.pi*2);local r=rng:NextNumber(6,26)
   local at=root.Position+Vector3.new(math.cos(a)*r,0,math.sin(a)*r)
   local beam=part({Name='TractorBeam',Shape=Enum.PartType.Cylinder,Color=color,Material=Enum.Material.ForceField,Transparency=1,
    Size=Vector3.new(240,1,1),CFrame=CFrame.new(at+Vector3.new(0,100,0))*CFrame.Angles(0,0,math.pi/2)},active.Folder)
   local core=part({Name='TractorCore',Shape=Enum.PartType.Cylinder,Color=color,Transparency=1,Size=Vector3.new(240,1,1),CFrame=beam.CFrame},active.Folder)
   table.insert(beams,{Beam=beam,Core=core,At=at,Born=os.clock(),Life=6,Radius=9})
  end
  for i=#beams,1,-1 do
   local b=beams[i];local age=os.clock()-b.Born
   local s=math.min(age/.6,1)*math.min((b.Life-age)/.6,1)
   if s<=0 and age>1 then b.Beam:Destroy();b.Core:Destroy();table.remove(beams,i)
   else
    s=math.max(s,0)
    b.Beam.Size=Vector3.new(240,b.Radius*2*s+.1,b.Radius*2*s+.1);b.Beam.Transparency=1-.55*s
    b.Core.Size=Vector3.new(240,b.Radius*.5*s+.05,b.Radius*.5*s+.05);b.Core.Transparency=1-.5*s
    if root and s>.5 then
     local d=Vector3.new(root.Position.X-b.At.X,0,root.Position.Z-b.At.Z).Magnitude
     if d<b.Radius then
      local v=root.AssemblyLinearVelocity
      root.AssemblyLinearVelocity=Vector3.new(v.X,math.max(v.Y,14),v.Z)
     end
    end
   end
  end
 end))
 table.insert(active.Cleanups,function()for _,b in ipairs(beams)do b.Beam:Destroy();b.Core:Destroy()end end)
end
local function quakes(def)
 local nextQuake=os.clock()+6
 table.insert(active.Connections,Run.Heartbeat:Connect(function()
  if os.clock()<nextQuake then return end
  nextQuake=os.clock()+rng:NextNumber(18,28)
  shake(.9,1.6)
  local character=player.Character;local root=rootOf(character)
  if root and grounded(character)and not reduced()then
   local v=root.AssemblyLinearVelocity
   root.AssemblyLinearVelocity=v+Vector3.new(rng:NextNumber(-6,6),32,rng:NextNumber(-6,6))
  end
  if root then
   local dust=part({Name='QuakeDust',Size=Vector3.one,Transparency=1,Position=root.Position-Vector3.new(0,3,0)},active.Folder)
   local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/smoke_main.dds';e.Color=ColorSequence.new(def.ColorTheme:Lerp(C(120,96,72),.6))
   e.Size=NumberSequence.new(4,12);e.Transparency=NumberSequence.new(.5,1);e.Lifetime=NumberRange.new(1,2);e.Speed=NumberRange.new(10,24)
   e.SpreadAngle=Vector2.new(80,10);e.Rate=0;e.Parent=dust;e:Emit(low()and 10 or 30)
   task.delay(3,function()dust:Destroy()end)
  end
 end))
end
local function speedLines()
 local gui=screen()
 local frame=Instance.new('Frame');frame.Name='Zoomies';frame.BackgroundTransparency=1;frame.Size=UDim2.fromScale(1,1);frame.Parent=gui
 local lines={}
 for i=1,(low()and 8 or 18)do
  local l=Instance.new('Frame');l.BorderSizePixel=0;l.BackgroundColor3=Color3.new(1,1,1);l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(.5,.5);l.Parent=frame
  lines[i]={Frame=l,Angle=rng:NextNumber(0,math.pi*2),Phase=rng:NextNumber()}
 end
 table.insert(active.Cleanups,function()frame:Destroy()end)
 table.insert(active.Connections,Run.RenderStepped:Connect(function()
  local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
  local speed=hum and hum.MoveDirection.Magnitude>.1 and hum.WalkSpeed or 0
  local k=math.clamp((speed-24)/16,0,1)*(reduced()and 0 or 1)
  for _,l in ipairs(lines)do
   l.Phase=(l.Phase+.04)%1
   local r=.42+.12*l.Phase
   l.Frame.Position=UDim2.fromScale(.5+math.cos(l.Angle)*r,.5+math.sin(l.Angle)*r)
   l.Frame.Size=UDim2.fromOffset(3,60+80*l.Phase);l.Frame.Rotation=math.deg(l.Angle)+90
   l.Frame.BackgroundTransparency=1-k*.45*(1-l.Phase)
  end
 end))
end
local function glitches()
 local gui=screen()
 local lastGravity=workspace.Gravity
 table.insert(active.Connections,workspace:GetPropertyChangedSignal('Gravity'):Connect(function()
  local g=workspace.Gravity
  if math.abs(g-lastGravity)<1 then return end
  lastGravity=g
  if reduced()then return end
  for i=1,3 do
   local bar=Instance.new('Frame');bar.BorderSizePixel=0;bar.BackgroundColor3=i==1 and C(255,40,70)or i==2 and C(40,230,255)or Color3.new(1,1,1)
   bar.BackgroundTransparency=.55;bar.Size=UDim2.new(1,0,0,rng:NextInteger(6,40));bar.Position=UDim2.fromScale(0,rng:NextNumber(0,.95));bar.Parent=gui
   task.delay(.08+i*.04,function()bar:Destroy()end)
  end
  local text=Instance.new('TextLabel');text:SetAttribute('KeepFont',true);text.BackgroundTransparency=1;text.Font=Enum.Font.Code
  text.Text=g<100 and'[ GRAVITY = '..string.format('%.0f',g)..' ]'or'[ GRAVITY RESTORED ]';text.TextColor3=C(220,210,240);text.TextScaled=true
  text.Size=UDim2.fromScale(.5,.05);text.Position=UDim2.fromScale(.25,.18);text.Parent=gui
  Tween:Create(text,TweenInfo.new(1.2),{TextTransparency=1}).Completed:Connect(function()text:Destroy()end)
  shake(.25,.3)
 end))
end

---------------------------------------------------------------- DOG RUSH
-- The big localized "DOG RUSH!" banner, the progress chip "🐶 3/10" with the next chest, the runaway
-- pups' local hop / wag / run-home animation (server models: the client only moves their Visual
-- sub-model), and the catch burst (confetti, hearts, a bark) for the catcher and players nearby.
-- Self-localized (NoTranslate). The HUD hides while a menu is open and respects the safe area.
local Rush=require(package:WaitForChild('DogRush'))
local Localization=game:GetService('LocalizationService')
local SoundService=game:GetService('SoundService')
local Debris=game:GetService('Debris')
local function lang()
 local ok,locale=pcall(function()
  if Run:IsStudio()then return Localization.RobloxLocaleId end
  return player.LocaleId~=''and player.LocaleId or Localization.RobloxLocaleId
 end)
 return ok and type(locale)=='string'and locale:sub(1,2):lower()=='ru'and'ru'or'en'
end
local function T(en,ru)return lang()=='ru'and ru or en end
local function short(n)
 n=math.max(0,math.floor(tonumber(n)or 0))
 for _,u in ipairs({{1e15,'Qa'},{1e12,'T'},{1e9,'B'},{1e6,'M'},{1e3,'K'}})do
  if n>=u[1]then local v=math.floor(n/u[1]*10)/10;return(v%1==0 and string.format('%d',v)or string.format('%.1f',v))..u[2]end
 end
 return tostring(n)
end
local function mainGui()return player:FindFirstChild('PlayerGui')and player.PlayerGui:FindFirstChild('ScreenGui')end
local function menuOpen()local g=mainGui();return g~=nil and g:GetAttribute('OpenMenu')~=nil end
local BARK='rbxasset://sounds/volume_slider.ogg'
local function sound(id,speed,volume,delay,parent,effects)
 task.delay(delay or 0,function()
  local s=Instance.new('Sound');s.SoundId=id;s.PlaybackSpeed=speed;s.Volume=volume;s.RollOffMinDistance=10;s.RollOffMaxDistance=100
  for class,props in pairs(effects or {})do local e=Instance.new(class);for k,v in pairs(props)do(e::any)[k]=v end;e.Parent=s end
  s.Parent=parent or SoundService;s.Ended:Once(function()s:Destroy()end);s:Play();Debris:AddItem(s,3)
 end)
end
local WOOF={DistortionSoundEffect={Level=.45},EqualizerSoundEffect={LowGain=8,MidGain=2,HighGain=-16}}
local CHIME={ReverbSoundEffect={DecayTime=1.6,WetLevel=-5}}
local function barkAt(parent,volume)
 local pitch=.95+rng:NextNumber()*.2
 sound(BARK,.44*pitch,volume,0,parent,WOOF);sound(BARK,.52*pitch,volume*.9,.17,parent,WOOF)
end

local rushHud -- built once: {Gui, Chip, Count, Next, Fill, Pop, Card, CardText, CardPop, Banner}
local function hudLayout()
 if not rushHud then return end
 -- Below the wallet counters (UITheme publishes U.HUD; the currency pills are top-centre on every device).
 local y=8
 local g=mainGui();local modules=g and g:FindFirstChild('Modules');local theme=modules and modules:FindFirstChild('UITheme')
 local ok,U=pcall(function()return theme and require(theme)end)
 if ok and type(U)=='table'and type(U.HUD)=='table'and U.HUD.StatsBottom and U.HUD.Top then y=math.max(8,U.HUD.StatsBottom-U.HUD.Top+8)end
 rushHud.Chip.Position=UDim2.new(.5,0,0,y)
 rushHud.Card.Position=UDim2.new(.5,0,0,y+52)
end
local function buildHud()
 if rushHud then return rushHud end
 local gui=Instance.new('ScreenGui');gui.Name='DOGROTS_DogRushHUD';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=41
 gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Enabled=false;gui:SetAttribute('NoTranslate',true);gui:SetAttribute('HideWithUI',true);gui.Parent=player:WaitForChild('PlayerGui')
 local function text(parent,props)
  local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.Font=Enum.Font.FredokaOne;l.TextColor3=Color3.new(1,1,1);l.TextScaled=true
  l:SetAttribute('KeepFont',true);l:SetAttribute('NoTranslate',true)
  for k,v in pairs(props)do(l::any)[k]=v end;l.Parent=parent;return l
 end
 local function stroke(parent,color,thickness)local s=Instance.new('UIStroke');s.Color=color;s.Thickness=thickness;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;s.Parent=parent;return s end
 local chip=Instance.new('Frame');chip.Name='PupChip';chip.AnchorPoint=Vector2.new(.5,0);chip.Size=UDim2.fromOffset(176,46)
 chip.BackgroundColor3=C(52,30,14);chip.BackgroundTransparency=.12;chip.Visible=false;chip.Parent=gui
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(.5,0);corner.Parent=chip
 local border=Instance.new('UIStroke');border.Color=C(255,196,64);border.Thickness=2.5;border.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;border.Parent=chip
 local pop=Instance.new('UIScale');pop.Parent=chip
 local icon=text(chip,{Name='Icon',Text='🐶',Size=UDim2.fromOffset(34,34),Position=UDim2.fromOffset(8,6)})
 local count=text(chip,{Name='Count',Text='0/10',Size=UDim2.fromOffset(70,26),Position=UDim2.fromOffset(46,4),TextXAlignment=Enum.TextXAlignment.Left})
 stroke(count,C(60,30,10),1.5)
 local nextLabel=text(chip,{Name='Next',Text='',Size=UDim2.fromOffset(120,13),Position=UDim2.fromOffset(46,29),TextXAlignment=Enum.TextXAlignment.Left,TextColor3=C(255,226,160)})
 local chest=text(chip,{Name='Chest',Text='🎁',Size=UDim2.fromOffset(28,28),Position=UDim2.new(1,-38,0,9)})
 local track=Instance.new('Frame');track.Name='Track';track.BackgroundColor3=C(30,16,8);track.BorderSizePixel=0;track.Size=UDim2.new(1,-40,0,4);track.Position=UDim2.new(0,20,1,-6);track.Parent=chip
 local fill=Instance.new('Frame');fill.Name='Fill';fill.BackgroundColor3=C(255,200,70);fill.BorderSizePixel=0;fill.Size=UDim2.fromScale(0,1);fill.Parent=track
 for _,f in ipairs({track,fill})do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=f end
 local card=Instance.new('Frame');card.Name='ChestCard';card.AnchorPoint=Vector2.new(.5,0);card.Size=UDim2.fromOffset(300,58);card.BackgroundColor3=C(255,248,230)
 card.Visible=false;card.Parent=gui
 local cc=Instance.new('UICorner');cc.CornerRadius=UDim.new(0,14);cc.Parent=card
 local cs=Instance.new('UIStroke');cs.Color=C(240,160,40);cs.Thickness=3;cs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;cs.Parent=card
 local cardPop=Instance.new('UIScale');cardPop.Parent=card
 local cardText=text(card,{Name='Text',Text='',Size=UDim2.new(1,-20,1,-10),Position=UDim2.fromOffset(10,5),TextColor3=C(110,60,10),RichText=true})
 local banner=Instance.new('Frame');banner.Name='Banner';banner.BackgroundTransparency=1;banner.AnchorPoint=Vector2.new(.5,.5);banner.Position=UDim2.fromScale(.5,.3)
 banner.Size=UDim2.new(.9,0,0,150);banner.Visible=false;banner.Parent=gui
 local bannerPop=Instance.new('UIScale');bannerPop.Parent=banner
 local title=text(banner,{Name='Title',Text='DOG RUSH!',Size=UDim2.new(1,0,0,96),TextColor3=Color3.new(1,1,1)})
 local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=92;limit.MinTextSize=28;limit.Parent=title
 local titleStroke=stroke(title,C(70,30,6),4)
 local grad=Instance.new('UIGradient');grad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,236,140)),ColorSequenceKeypoint.new(.5,C(255,150,40)),ColorSequenceKeypoint.new(1,C(255,236,140))});grad.Rotation=90;grad.Parent=title
 local sub=text(banner,{Name='Subtitle',Text='',Size=UDim2.new(1,0,0,34),Position=UDim2.fromOffset(0,100)})
 local subLimit=Instance.new('UITextSizeConstraint');subLimit.MaxTextSize=30;subLimit.MinTextSize=14;subLimit.Parent=sub
 local subStroke=stroke(sub,C(60,26,6),2.5)
 local paws={}
 for i,x in ipairs({.04,.96})do paws[i]=text(banner,{Name='Paw',Text='🐾',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(x,.32),Size=UDim2.fromOffset(64,64),Rotation=i==1 and -18 or 18})end
 rushHud={Gui=gui,Chip=chip,Count=count,Next=nextLabel,Chest=chest,Fill=fill,Pop=pop,Card=card,CardText=cardText,CardPop=cardPop,
  Banner=banner,BannerPop=bannerPop,Title=title,TitleStroke=titleStroke,Sub=sub,SubStroke=subStroke,Paws=paws,Grad=grad,CardSerial=0,BannerSerial=0}
 hudLayout()
 gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(hudLayout)
 return rushHud
end
local function refreshChip(animate)
 local hud=rushHud;if not hud then return end
 local generation=stateFolder:GetAttribute('Generation')
 local caught=player:GetAttribute('DogRushGeneration')==generation and(tonumber(player:GetAttribute('DogRushPups'))or 0)or 0
 hud.Count.Text=math.min(caught,Rush.Goal)..'/'..Rush.Goal
 local nextChest=Rush.NextMilestone(caught)
 if nextChest then hud.Next.Text=T('NEXT CHEST AT ','СУНДУК НА ')..nextChest.Count;hud.Chest.Text=nextChest.Icon
 else hud.Next.Text=caught>=Rush.Pups.PerEvent and T('ALL PUPS CAUGHT!','ВСЕ ЩЕНКИ ПОЙМАНЫ!')or T('ALL CHESTS OPEN!','ВСЕ СУНДУКИ ОТКРЫТЫ!');hud.Chest.Text='👑'end
 local value=math.clamp(caught/Rush.Goal,0,1)
 if animate and not reduced()then
  Tween:Create(hud.Fill,TweenInfo.new(.35,Enum.EasingStyle.Quad),{Size=UDim2.fromScale(value,1)}):Play()
  hud.Pop.Scale=1.25;Tween:Create(hud.Pop,TweenInfo.new(.35,Enum.EasingStyle.Back),{Scale=1}):Play()
 else hud.Fill.Size=UDim2.fromScale(value,1)end
end
local function showCard(lines,seconds)
 local hud=rushHud;if not hud or menuOpen()then return end
 hud.CardSerial+=1;local serial=hud.CardSerial
 hud.CardText.Text=table.concat(lines,'\n');hud.Card.Size=UDim2.fromOffset(310,#lines>1 and 70 or 46);hud.Card.Visible=true
 if reduced()then hud.CardPop.Scale=1 else hud.CardPop.Scale=.4;Tween:Create(hud.CardPop,TweenInfo.new(.4,Enum.EasingStyle.Back),{Scale=1}):Play()end
 task.delay(seconds or 3.2,function()if rushHud and rushHud.CardSerial==serial then rushHud.Card.Visible=false end end)
end
local function showBanner(late)
 local hud=rushHud;if not hud or menuOpen()then return end
 hud.BannerSerial+=1;local serial=hud.BannerSerial
 hud.Title.Text=T('DOG RUSH!','СОБАЧИЙ ЗАБЕГ!')
 hud.Sub.Text=T('Catch the runaway golden pups! Chests at 3 · 6 · 10','Лови сбежавших золотых щенков! Сундуки за 3 · 6 · 10')
 hud.Banner.Visible=true
 for _,o in ipairs({hud.Title,hud.Sub})do o.TextTransparency=0 end
 for _,o in ipairs(hud.Paws)do o.TextTransparency=0 end
 hud.TitleStroke.Transparency=0;hud.SubStroke.Transparency=0
 if reduced()then hud.BannerPop.Scale=1 else
  hud.BannerPop.Scale=.35;Tween:Create(hud.BannerPop,TweenInfo.new(.55,Enum.EasingStyle.Back),{Scale=1}):Play()
  for i,paw in ipairs(hud.Paws)do
   paw.Rotation=i==1 and -30 or 30
   Tween:Create(paw,TweenInfo.new(.4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,4,true),{Rotation=i==1 and 6 or -6}):Play()
  end
  hud.Grad.Offset=Vector2.new(0,-1);Tween:Create(hud.Grad,TweenInfo.new(1.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,1,true),{Offset=Vector2.new(0,.6)}):Play()
 end
 task.delay(late and 2 or 3.4,function()
  if not rushHud or rushHud.BannerSerial~=serial then return end
  local info=TweenInfo.new(.6)
  for _,o in ipairs({hud.Title,hud.Sub})do Tween:Create(o,info,{TextTransparency=1}):Play()end
  for _,o in ipairs(hud.Paws)do Tween:Create(o,info,{TextTransparency=1}):Play()end
  Tween:Create(hud.TitleStroke,info,{Transparency=1}):Play();Tween:Create(hud.SubStroke,info,{Transparency=1}):Play()
  task.delay(.65,function()if rushHud and rushHud.BannerSerial==serial then rushHud.Banner.Visible=false end end)
 end)
end
-- Confetti, hearts and a bark where a pup was caught (catcher: also the coins floating up).
local burstFolder
local function burst(position,mine,reward)
 if not burstFolder or not burstFolder.Parent then burstFolder=Instance.new('Folder');burstFolder.Name='DOGROTS_PupBursts';burstFolder.Parent=workspace end
 local anchor=part({Name='PupBurst',Size=Vector3.one,Transparency=1,Position=position+Vector3.new(0,2,0)},burstFolder)
 if not low()then
  local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.LightEmission=.6
  e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,90,120)),ColorSequenceKeypoint.new(.33,C(255,214,60)),ColorSequenceKeypoint.new(.66,C(90,220,255)),ColorSequenceKeypoint.new(1,C(150,255,120))})
  e.Size=NumberSequence.new(.7,0);e.Lifetime=NumberRange.new(1,1.8);e.Speed=NumberRange.new(12,24);e.SpreadAngle=Vector2.new(70,70)
  e.EmissionDirection=Enum.NormalId.Top;e.Acceleration=Vector3.new(0,-28,0);e.Drag=1.5;e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-200,200);e.Rate=0;e.Parent=anchor
  e:Emit(mine and 46 or 18)
 end
 local hearts=mine and(low()and 2 or 5)or 2
 for i=1,hearts do
  local g=Instance.new('BillboardGui');g.Size=UDim2.fromScale(1.6,1.6);g.LightInfluence=0;g.Adornee=anchor;g.AlwaysOnTop=false;g:SetAttribute('NoTranslate',true)
  local x=(i-(hearts+1)/2)*1.1;g.StudsOffsetWorldSpace=Vector3.new(x,0,0)
  local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.TextScaled=true;l.Text=i%3==0 and'🐾'or i%2==0 and'💛'or'❤️';l:SetAttribute('NoTranslate',true);l.Parent=g
  g.Parent=anchor -- goes away with the burst anchor (Debris)
  if not reduced()then Tween:Create(g,TweenInfo.new(1.4,Enum.EasingStyle.Quad),{StudsOffsetWorldSpace=Vector3.new(x*1.6,3.5+i*.3,0)}):Play()end
  Tween:Create(l,TweenInfo.new(1.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{TextTransparency=1}):Play()
 end
 if mine and type(reward)=='table'then
  local g=Instance.new('BillboardGui');g.Size=UDim2.new(6,40,1.4,10);g.LightInfluence=0;g.Adornee=anchor;g.AlwaysOnTop=true;g.StudsOffsetWorldSpace=Vector3.new(0,1.5,0);g:SetAttribute('NoTranslate',true)
  local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.TextScaled=true;l.Font=Enum.Font.FredokaOne;l:SetAttribute('KeepFont',true);l:SetAttribute('NoTranslate',true)
  l.TextColor3=C(255,226,90);l.TextStrokeTransparency=.2;l.TextStrokeColor3=C(70,40,6);l.Text='+'..short(reward.Coins)..' 🪙  +'..short(reward.Bones)..' 🦴';l.Parent=g
  g.Parent=anchor
  if not reduced()then Tween:Create(g,TweenInfo.new(1.6,Enum.EasingStyle.Quad),{StudsOffsetWorldSpace=Vector3.new(0,5,0)}):Play()end
  Tween:Create(l,TweenInfo.new(1.6,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{TextTransparency=1,TextStrokeTransparency=1}):Play()
 end
 barkAt(anchor,mine and .42 or .22)
 Debris:AddItem(anchor,3)
end
local function chestCelebration(chests)
 local lines={}
 for _,c in ipairs(chests)do
  local m=Rush.Milestone(c.Count)
  local name=m and(lang()=='ru'and m.RU or m.Name)or T('CHEST','СУНДУК')
  local line=string.format('<b>%s %s</b>  +%s 🪙  +%s 🦴',m and m.Icon or'🎁',name,short(c.Coins),short(c.Bones))
  if type(c.Block)=='table'then line..=T('  +1 LUCKY BLOCK','  +1 СЧАСТЛИВЫЙ БЛОК')end
  table.insert(lines,line)
 end
 showCard(lines,4)
 for i,step in ipairs({1,1.25,1.5,2})do sound(BARK,step*1.5,.2,(i-1)*.1,nil,CHIME)end
end

-- Runaway pups in the street: hop, wag towards you when you come close, run home when they expire.
local pups={} -- model -> {Visual, Base, Phase, Expires}
local function trackPup(model)
 if not model:IsA('Model')or model:GetAttribute('PupKind')==nil or pups[model]then return end
 -- Streamed in whole (Atomic), but give the descendants a moment if they are still arriving.
 local visual=model:FindFirstChild('Visual')or model:WaitForChild('Visual',3)
 if not visual or not visual:IsA('Model')or not model.Parent or pups[model]then return end
 for _=1,30 do if visual.PrimaryPart then break end;task.wait()end
 if not visual.PrimaryPart or not model.Parent then return end
 local prompt=model:FindFirstChild('WorldEventPickupPrompt',true)
 if prompt and prompt:IsA('ProximityPrompt')then prompt.ActionText=T('CATCH','ПОЙМАТЬ');prompt.ObjectText=T('Runaway pup','Сбежавший щенок')end
 local parts={};for _,d in ipairs(visual:GetDescendants())do if d:IsA('BasePart')then table.insert(parts,d)end end
 pups[model]={Visual=visual,Base=visual:GetPivot(),Phase=rng:NextNumber(0,6),Expires=tonumber(model:GetAttribute('ExpiresAt'))or math.huge,Parts=parts}
end
local function animatePups(now,camPos,me)
 local n=0
 for model,pup in pairs(pups)do
  if not model.Parent or not pup.Visual.Parent then pups[model]=nil
  else
   local at=pup.Base.Position
   if (at-camPos).Magnitude<70 and n<10 then
    n+=1
    local t=now+pup.Phase;local left=pup.Expires-now
    local offset
    if left<1.4 then
     -- Time is up: the pup dashes off home and fades.
     local k=math.clamp(1-left/1.4,0,1)
     offset=CFrame.new(0,math.abs(math.sin(t*14))*.6,-k*11)
     for _,p in ipairs(pup.Parts)do p.LocalTransparencyModifier=k end
    else
     local hop=reduced()and 0 or math.abs(math.sin(t*4.2))*.55
     local turn=math.sin(t*1.3)*.5
     if me and(me-at).Magnitude<22 then
      -- Happy to see you: faces you and bounces faster.
      local look=pup.Base:PointToObjectSpace(me);turn=math.atan2(-look.X,-look.Z);hop=reduced()and 0 or math.abs(math.sin(t*7))*.8
     end
     offset=CFrame.new(0,hop,0)*CFrame.Angles(0,turn,0)*CFrame.Angles(0,0,reduced()and 0 or math.sin(t*9)*.06)
    end
    pup.Visual:PivotTo(pup.Base*offset)
   end
  end
 end
end

local function dogRush(def)
 local hud=buildHud();hud.Gui.Enabled=true;hud.Chip.Visible=not menuOpen();hud.Card.Visible=false
 refreshChip(false);hudLayout()
 local started=tonumber(stateFolder:GetAttribute('StartTimestamp'))or workspace:GetServerTimeNow()
 local late=workspace:GetServerTimeNow()-started>12
 task.delay(late and .5 or 1.2,function()if active and active.Def==def then showBanner(late)end end)
 table.insert(active.Connections,player:GetAttributeChangedSignal('DogRushPups'):Connect(function()refreshChip(true)end))
 table.insert(active.Connections,player:GetAttributeChangedSignal('DogRushGeneration'):Connect(function()refreshChip(false)end))
 local g=mainGui()
 if g then table.insert(active.Connections,g:GetAttributeChangedSignal('OpenMenu'):Connect(function()
  local open=menuOpen();hud.Chip.Visible=not open
  if open then hud.Card.Visible=false;hud.Banner.Visible=false end
 end))end
 -- Pups: server models under workspace.WorldEventFX (streamed whole).
 local mine=active
 task.spawn(function()
  local fxFolder=workspace:FindFirstChild('WorldEventFX')or workspace:WaitForChild('WorldEventFX',10)
  if not fxFolder or active~=mine then return end
  table.insert(mine.Connections,fxFolder.ChildAdded:Connect(function(child)task.spawn(trackPup,child)end))
  table.insert(mine.Connections,fxFolder.ChildRemoved:Connect(function(child)pups[child]=nil end))
  for _,child in ipairs(fxFolder:GetChildren())do task.spawn(trackPup,child)end
 end)
 local acc=0
 table.insert(active.Connections,Run.Heartbeat:Connect(function(dt)
  acc+=dt;if acc<1/30 then return end;acc=0
  if next(pups)==nil then return end
  local camera=workspace.CurrentCamera;if not camera then return end
  local root=rootOf(player.Character)
  animatePups(workspace:GetServerTimeNow(),camera.CFrame.Position,root and root.Position or nil)
 end))
 table.insert(active.Cleanups,function()
  table.clear(pups)
  if rushHud then rushHud.Gui.Enabled=false;rushHud.Chip.Visible=false;rushHud.Card.Visible=false;rushHud.Banner.Visible=false end
 end)
end
package:WaitForChild('Signal').OnClientEvent:Connect(function(data)
 if type(data)~='table'then return end
 if data.Kind=='PupCaught'and typeof(data.Position)=='Vector3'then
  burst(data.Position,true,data.Reward)
  if type(data.Reward)=='table'and type(data.Reward.Chests)=='table'and #data.Reward.Chests>0 then chestCelebration(data.Reward.Chests)end
  refreshChip(true)
 elseif data.Kind=='PupCaughtNearby'and typeof(data.Position)=='Vector3'then
  burst(data.Position,false,nil)
 end
end)

---------------------------------------------------------------- lifecycle
local function stop()
 if not active then return end
 for _,c in ipairs(active.Connections)do c:Disconnect()end
 for _,fn in ipairs(active.Cleanups)do pcall(fn)end
 active.Folder:Destroy()
 active=nil
end
local function start(def,generation)
 stop()
 local folder=Instance.new('Folder');folder.Name='DOGROTS_EventGameplayFX';folder.Parent=workspace
 active={Def=def,Generation=generation,Folder=folder,Connections={},Cleanups={}}
 local effects=(def.Perks or {}).Effects or {}
 if effects.Flashlight then eachCharacter(flashlight)end
 if effects.Trail then
  local color=def.Id=='RAINBOW_RIFT'and ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,80,80)),ColorSequenceKeypoint.new(.25,C(255,220,60)),
   ColorSequenceKeypoint.new(.5,C(80,255,120)),ColorSequenceKeypoint.new(.75,C(80,170,255)),ColorSequenceKeypoint.new(1,C(220,90,255))})
   or ColorSequence.new(def.ColorTheme,Color3.new(1,1,1))
  eachCharacter(function(p,character)trail(p,character,color)end)
 end
 if effects.Tractor then tractorBeams(def)end
 if effects.Quakes then quakes(def)end
 if effects.Zoomies then speedLines()end
 if effects.Glitch then glitches()end
 if effects.Pups then dogRush(def)end
end
local function sync()
 local phase=stateFolder:GetAttribute('State');local def=Definitions.ById[stateFolder:GetAttribute('EventId')or'']
 local generation=stateFolder:GetAttribute('Generation')
 if phase=='ACTIVE'and def then
  if not active or active.Generation~=generation then start(def,generation)end
 else stop()end
end
stateFolder:GetAttributeChangedSignal('Revision'):Connect(sync)
sync()

---------------------------------------------------------------- server luck celebration
task.spawn(function()
 local state=RS:WaitForChild('ServerLuckState',60);if not state then return end
 local seen=state:GetAttribute('Seq')
 state:GetAttributeChangedSignal('Seq'):Connect(function()
  local seq=state:GetAttribute('Seq');if seq==seen then return end;seen=seq
  local added=state:GetAttribute('LastSeconds')or 0;if added<=0 then return end
  local mult=state:GetAttribute('LastMultiplier')or 2;local by=state:GetAttribute('LastBy')or''
  local gui=screen()
  local holder=Instance.new('Frame');holder.BackgroundTransparency=1;holder.AnchorPoint=Vector2.new(.5,.5);holder.Position=UDim2.fromScale(.5,.32)
  holder.Size=UDim2.new(.8,0,0,120);holder.Parent=gui
  local scale=Instance.new('UIScale');scale.Scale=reduced()and 1 or 1.8;scale.Parent=holder
  local title=Instance.new('TextLabel');title:SetAttribute('KeepFont',true);title.BackgroundTransparency=1;title.Font=Enum.Font.FredokaOne
  title.Text='x'..mult..' SERVER LUCK!';title.TextColor3=C(120,255,120);title.TextScaled=true;title.Size=UDim2.new(1,0,0,80);title.Parent=holder
  local stroke=Instance.new('UIStroke');stroke.Thickness=4;stroke.Color=C(10,40,10);stroke.Parent=title
  local g=Instance.new('UIGradient');g.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(120,255,120)),ColorSequenceKeypoint.new(.5,C(255,240,120)),ColorSequenceKeypoint.new(1,C(120,255,200))});g.Parent=title
  local sub=Instance.new('TextLabel');sub:SetAttribute('KeepFont',true);sub.BackgroundTransparency=1;sub.Font=Enum.Font.FredokaOne
  sub.Text=(by~=''and('THANKS TO '..string.upper(by)..'  ·  ')or'')..'RARER DOGS ON THE TONGUE FOR EVERYONE · '..math.floor(added/60)..' MIN';sub.TextColor3=Color3.new(1,1,1)
  sub.TextScaled=true;sub.Size=UDim2.new(1,0,0,30);sub.Position=UDim2.new(0,0,0,84);sub.Parent=holder
  local subStroke=Instance.new('UIStroke');subStroke.Thickness=2;subStroke.Color=C(10,30,10);subStroke.Parent=sub
  Tween:Create(scale,TweenInfo.new(.5,Enum.EasingStyle.Back),{Scale=1}):Play()
  local started=os.clock()
  local con;con=Run.RenderStepped:Connect(function()
   local age=os.clock()-started;g.Offset=Vector2.new(math.sin(age*2)*.5,0)
   if age>4.5 then
    con:Disconnect()
    for _,o in ipairs({title,sub})do Tween:Create(o,TweenInfo.new(.8),{TextTransparency=1}):Play()end
    for _,o in ipairs({stroke,subStroke})do Tween:Create(o,TweenInfo.new(.8),{Transparency=1}):Play()end
    task.delay(.9,function()holder:Destroy()end)
   end
  end)
  -- Clover confetti around this player.
  local root=rootOf(player.Character)
  if root and not low()then
   local anchor=part({Name='LuckConfetti',Size=Vector3.one,Transparency=1,Position=root.Position+Vector3.new(0,14,0)},workspace)
   local e=Instance.new('ParticleEmitter');e.Texture='rbxasset://textures/particles/sparkles_main.dds';e.LightEmission=1
   e.Color=ColorSequence.new(C(120,255,120),C(255,240,120));e.Size=NumberSequence.new(1.2,0);e.Lifetime=NumberRange.new(1.5,3)
   e.Speed=NumberRange.new(14,34);e.SpreadAngle=Vector2.new(180,180);e.Acceleration=Vector3.new(0,-18,0);e.Rate=0;e.Parent=anchor;e:Emit(70)
   task.delay(4,function()anchor:Destroy()end)
  end
  pcall(function()
   local general=TextChat:FindFirstChild('TextChannels')and TextChat.TextChannels:FindFirstChild('RBXGeneral')
   if general then general:DisplaySystemMessage(string.format('<font color="#78FF78"><b>✦ %s activated x%d SERVER LUCK! Rarer dogs for everyone for %d min.</b></font>',by~=''and by or'Someone',mult,math.floor(added/60)))end
  end)
 end)
end)
print('DOGROTS_WORLD_EVENT_GAMEPLAY_FX_READY')
