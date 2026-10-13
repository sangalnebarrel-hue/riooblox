-- NUCLEAR MUTATION MACHINE: the client cinematic of a lab result (docs/LAB.md). Client only.
--   P.Play(result)   yields while the cinematic plays (6-9 s, LabConfig.Machine; Reduced Motion: a short
--                    version). The button, the placer arm putting the dog on the lift, the lift carrying it
--                    into the tube, liquid, spinning rings, the energy core, arcs and a colour reel that slows
--                    down like a slot reel and lands on the server's result, then the transformation burst.
--                    The dog stays in the tube (with the world's variant highlight) until P.Release().
--   P.Skip()         tap / click / Space during the cinematic also skips (straight to the burst, then out)
--   P.Release()      the result card closed: the dog leaves, the machine returns to idle
--   P.StartWorld()   once per client (LabPrompt.client): idle motion while near the machine, localized
--                    screens, and the short public effect when another player mutates a dog
--   P.Cue(key, part) a lab sound (LabAudioConfig), quieter during world events
-- Everything the cinematic changes on the server's machine parts is remembered and restored; effect parts
-- are pooled (one folder, created once); a dog clone and its animation player exist only while shown.
-- Without the machine (LabConfig.MachineWorld off or not streamed in) the old chamber camera plays.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local TweenService=game:GetService('TweenService')
local Lighting=game:GetService('Lighting')
local C=require(RS.LabConfig);local AC=require(RS.LabAudioConfig);local Access=require(RS.LabAccess)
local L=require(RS.MutationMachineLayout)
local Base=require(RS.DogEconomy.Config)
local Definitions=require(RS.DogEconomy.DogDefinitions)
local Rig=require(RS.DogRig)
local Animation=require(RS.DogAnimationPlayer)
local Dict=require(RS:WaitForChild('Localization'):WaitForChild('Lab'))
local Lang=require(script.Parent.Kit.Lang)
local Motion=require(script.Parent.Kit.Motion)
local player=Players.LocalPlayer
local P={Seen={},Playing=false,AutoRelease=45,WorldStarted=false,SkipRequested=false}

------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------
local function T(en)if Lang.Get()=='ru'then return Dict.UI[en]or Dict.Exact[en]or en end;return en end
local function upper(s)
 local out={}
 for _,code in utf8.codes(tostring(s or''))do
  if code>=0x430 and code<=0x44F then code-=0x20 elseif code==0x451 then code=0x401 elseif code>=97 and code<=122 then code-=32 end
  table.insert(out,utf8.char(code))
 end
 return table.concat(out)
end
local function variantName(v)return upper(T(v or'Normal'))end
local function smooth(x)x=math.clamp(x,0,1);return x*x*(3-2*x)end
local function span(t,a,b)return smooth((t-a)/math.max(b-a,1e-3))end
local function lerp(a,b,x)return a+(b-a)*x end
local function activeEvent()
 local events=RS:FindFirstChild('WorldEvents');local state=events and events:FindFirstChild('State')
 local value=state and state:GetAttribute('State');return value=='ACTIVE'or value=='ENDING'or value=='WARNING'
end
-- Roblox Reduced Motion (Kit.Motion) or the game's ReducedMotion attribute: the short version.
local function reduced()return player:GetAttribute('ReducedMotion')==true or Motion.Reduced()end
-- Low FX: the game's switches or a low graphics quality.
local function lowFX()
 if player:GetAttribute('LowFX')==true or player:GetAttribute('WorldEventFX')=='Low'then return true end
 local ok,level=pcall(function()return UserSettings():GetService('UserGameSettings').SavedQualityLevel.Value end)
 return ok and type(level)=='number'and level>0 and level<=3
end
function P.Cue(key,parent,pitch)
 local ok,err=pcall(AC.Play,key,parent,activeEvent()and .2 or 1,pitch)
 if not ok then warn('Lab cue '..tostring(key)..': '..tostring(err))end
end
function P.Skip()P.SkipRequested=true end

local function machine(wait)
 local lab=Access.Model()
 if not lab then return nil,nil end
 local m=lab:FindFirstChild(L.Name)
 if not m and wait then m=lab:WaitForChild(L.Name,wait)end
 return m,lab
end
local function find(root,name)return root and root:FindFirstChild(name,true)end
local function all(root,name)
 local out={}
 if root then for _,d in root:GetDescendants()do if d.Name==name then table.insert(out,d)end end end
 return out
end
local function colorOf(v)return(L.WorldColors::any)[v or'Normal']or L.Teal end
-- The world's variant look (EconomyVisuals: a Highlight on dogs in kennels and on the conveyor).
local function tint(model,variant,fill)
 local h=model:FindFirstChild('EconomyVariant')
 if variant=='Normal'or not(L.WorldColors::any)[variant]then if h then h.Enabled=false end;return h end
 if not h then h=Instance.new('Highlight');h.Name='EconomyVariant';h.DepthMode=Enum.HighlightDepthMode.Occluded;h.Parent=model end
 local c=colorOf(variant);h.FillColor=c;h.OutlineColor=c;h.FillTransparency=fill or .85;h.OutlineTransparency=.2;h.Enabled=true
 return h
end

------------------------------------------------------------------------------------------------
-- Remembered machine state (everything is put back exactly)
------------------------------------------------------------------------------------------------
local saved={}
local function touch(o,...)
 if not o then return end
 local s=saved[o];if not s then s={};saved[o]=s end
 for _,k in{...}do
  if s[k]==nil then
   if k=='Pivot'then s.Pivot=o:GetPivot()else s[k]=(o::any)[k]end
  end
 end
end
local function restoreAll()
 for o,s in pairs(saved)do
  if o.Parent then
   for k,v in pairs(s)do
    pcall(function()if k=='Pivot'then o:PivotTo(v)else(o::any)[k]=v end end)
   end
  end
 end
 table.clear(saved)
end
local function set(o,k,v)if o and o.Parent then touch(o,k);(o::any)[k]=v end end
local function pivot(o,cf)if o and o.Parent then touch(o,'Pivot');o:PivotTo(cf)end end

------------------------------------------------------------------------------------------------
-- Effect pool (created once)
------------------------------------------------------------------------------------------------
local fx=nil
local function newPart(folder,name,shape)
 local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
 p.Material=Enum.Material.Neon;p.Transparency=1;p.Size=Vector3.one;if shape then p.Shape=shape end;p.Parent=folder;return p
end
local function emitter(parent,name,props)
 local e=Instance.new('ParticleEmitter');e.Name=name;e.Rate=0;e.Enabled=false;e.LightEmission=1;e.LightInfluence=0
 e.Lifetime=props.Lifetime;e.Speed=props.Speed;e.Size=props.Size;e.SpreadAngle=props.Spread or Vector2.new(180,180)
 e.Drag=props.Drag or 0;e.Acceleration=props.Acceleration or Vector3.zero;e.Transparency=props.Transparency or NumberSequence.new(0,1)
 e.RotSpeed=NumberRange.new(-120,120);e.Rotation=NumberRange.new(0,360)
 if props.Texture then e.Texture=props.Texture end
 if props.Shape then e.Shape=props.Shape;e.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume;e.EmissionDirection=Enum.NormalId.Top end
 e.Parent=parent;return e
end
local function pool()
 if fx and fx.Folder.Parent then return fx end
 local folder=Instance.new('Folder');folder.Name='MutationMachineFX';folder.Parent=workspace
 fx={Folder=folder}
 fx.Flash=newPart(folder,'FlashBall',Enum.PartType.Ball)
 fx.Beam=newPart(folder,'InjectorBeam',Enum.PartType.Cylinder)
 fx.Anchor=newPart(folder,'FXAnchor');fx.Anchor.Size=Vector3.new(.2,.2,.2)
 fx.Floor=newPart(folder,'FXFloor');fx.Floor.Size=Vector3.new(.2,.2,.2)
 fx.Rings={}
 for i,holder in{fx.Anchor,fx.Floor}do
  local r=Instance.new('CylinderHandleAdornment');r.Name='Shockwave'..i;r.Adornee=holder;r.CFrame=CFrame.Angles(math.pi/2,0,0)
  r.Radius=1;r.InnerRadius=.5;r.Height=.5;r.Visible=false;r.AlwaysOnTop=false;r.Parent=holder;fx.Rings[i]=r
 end
 fx.Sparks=emitter(fx.Anchor,'Sparks',{Lifetime=NumberRange.new(.35,.8),Speed=NumberRange.new(14,30),Drag=4,Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,0)})})
 fx.Burst=emitter(fx.Anchor,'Burst',{Lifetime=NumberRange.new(.6,1.3),Speed=NumberRange.new(28,58),Drag=2.5,Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.6),NumberSequenceKeypoint.new(1,0)})})
 fx.Bubbles=emitter(fx.Floor,'Bubbles',{Lifetime=NumberRange.new(1.6,2.6),Speed=NumberRange.new(5,9),Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,.45)}),
  Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(1,1)}),Spread=Vector2.new(4,4),Shape=Enum.ParticleEmitterShape.Cylinder})
 fx.Arcs={}
 fx.ArcHolder=newPart(folder,'ArcHolder');fx.ArcHolder.Size=Vector3.new(.2,.2,.2)
 for i=1,4 do
  local a0=Instance.new('Attachment');a0.Name='Arc'..i..'A';a0.Parent=fx.ArcHolder
  local a1=Instance.new('Attachment');a1.Name='Arc'..i..'B';a1.Parent=fx.ArcHolder
  local b=Instance.new('Beam');b.Name='Arc'..i;b.Attachment0=a0;b.Attachment1=a1;b.FaceCamera=true;b.LightEmission=1;b.LightInfluence=0
  b.Segments=10;b.Width0=.35;b.Width1=.12;b.Enabled=false;b.Parent=fx.ArcHolder
  fx.Arcs[i]={Beam=b,A=a0,B=a1}
 end
 local cc=Instance.new('ColorCorrectionEffect');cc.Name='MutationMachineFlash';cc.Enabled=false;cc.Parent=Lighting;fx.CC=cc
 local gui=Instance.new('ScreenGui');gui.Name='MutationMachineFlash';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=92;gui.Enabled=false
 gui:SetAttribute('NoTranslate',true)
 local flash=Instance.new('Frame');flash.Name='Flash';flash.Size=UDim2.fromScale(1,1);flash.BackgroundColor3=Color3.new(1,1,1);flash.BackgroundTransparency=1;flash.BorderSizePixel=0;flash.Active=false;flash.Parent=gui
 local ticker=Instance.new('TextLabel');ticker.Name='Reel';ticker.AnchorPoint=Vector2.new(.5,1);ticker.Position=UDim2.new(.5,0,1,-90);ticker.Size=UDim2.fromOffset(420,64)
 ticker.BackgroundTransparency=1;ticker.Font=Enum.Font.FredokaOne;ticker.TextScaled=true;ticker.Text='';ticker.TextColor3=Color3.new(1,1,1);ticker.TextStrokeTransparency=0;ticker.TextStrokeColor3=Color3.fromRGB(14,22,34);ticker.Parent=gui
 local scale=Instance.new('UIScale');scale.Parent=ticker
 local hint=Instance.new('TextLabel');hint.Name='SkipHint';hint.AnchorPoint=Vector2.new(.5,1);hint.Position=UDim2.new(.5,0,1,-28);hint.Size=UDim2.fromOffset(300,26)
 hint.BackgroundTransparency=1;hint.Font=Enum.Font.FredokaOne;hint.TextScaled=true;hint.TextColor3=Color3.new(1,1,1);hint.TextTransparency=.35;hint.TextStrokeTransparency=.6;hint.Parent=gui
 gui.Parent=player:WaitForChild('PlayerGui')
 fx.Gui=gui;fx.Flash2D=flash;fx.Ticker=ticker;fx.TickerScale=scale;fx.Hint=hint
 return fx
end
local function resetPool()
 if not fx then return end
 fx.Flash.Transparency=1;fx.Beam.Transparency=1
 for _,r in fx.Rings do r.Visible=false end
 for _,a in fx.Arcs do a.Beam.Enabled=false end
 fx.Bubbles.Enabled=false;fx.Sparks:Clear();fx.Burst:Clear()
 fx.CC.Enabled=false;fx.Gui.Enabled=false;fx.Flash2D.BackgroundTransparency=1;fx.Ticker.Text=''
end

------------------------------------------------------------------------------------------------
-- The dog clone (MenuModels, the same source as the window previews)
------------------------------------------------------------------------------------------------
local shown=nil -- {Model, Anim, Conn, Variant}
local function makeDog(d)
 local models=RS:FindFirstChild('MenuModels');local def=d and Definitions[d.DogId]
 local source=models and def and models:FindFirstChild(def.VisualAsset or d.DogId)or(models and d and models:FindFirstChild(d.DogId))
 if not source then return nil end
 local m=source:Clone()
 for _,o in m:GetDescendants()do
  if o:IsA('LuaSourceContainer')or o:IsA('ProximityPrompt')or o:IsA('BillboardGui')or o:IsA('SurfaceGui')or o:IsA('Sound')or o:IsA('ParticleEmitter')then o:Destroy()end
 end
 local prepared=Rig.Prepare(m,L.DogLimits)
 if not prepared then m:Destroy();return nil end
 m.Name='MachineDog';m.Parent=pool().Folder
 local anim=nil
 local idle=Animation.ResolveName(d.DogId,'Idle')
 if idle then
  local ok,player2=pcall(Animation.new,m,d.DogId)
  if ok and player2 and player2:Play(idle,{FadeTime=0})then anim=player2 end
 end
 return {Model=m,Anim=anim,Variant=d.Variant or'Normal',Height=prepared.Size.Y}
end
local function dropDog()
 if not shown then return end
 if shown.Conn then shown.Conn:Disconnect()end
 if shown.Anim then pcall(function()shown.Anim:Destroy()end)end
 if shown.Model then shown.Model:Destroy()end
 shown=nil
end

------------------------------------------------------------------------------------------------
-- Machine parts the cinematic drives
------------------------------------------------------------------------------------------------
local function rig(m)
 local k={M=m}
 local root=m.PrimaryPart
 k.Frame=root and root.CFrame or L.Frame
 k.W=function(v)return k.Frame:PointToWorldSpace(v)end
 k.CF=function(cf)return k.Frame*cf end
 k.Lift=m:FindFirstChild('Lift')
 k.Carriage=k.Lift and k.Lift:FindFirstChild('Carriage')
 k.Mast=k.Lift and k.Lift:FindFirstChild('Mast')
 k.Platform=k.Lift and k.Lift:FindFirstChild('Platform')
 k.Door=find(m,'IntakeDoor')
 k.Rotors={};for _,r in L.Tube.Rotors do local model=m:FindFirstChild(r.Name);if model and model.PrimaryPart then table.insert(k.Rotors,{Hub=model.PrimaryPart,Y=r.Y})end end
 k.Liquid=find(m,'ChamberLiquid');k.Surface=find(m,'LiquidSurface');k.CoreBeam=find(m,'CoreBeam')
 k.Rails={};for i=1,L.Tube.Rails do local p=find(m,'EnergyRail'..i);if p then table.insert(k.Rails,p)end end
 k.Glow={}
 for _,name in{'Membrane','EnergyFloor','InjectorTip','RotorLamp','DeckGlow','ClawLamp','RoofGlow','UpperBandGlow','CapGlow','CoilSpark','PedestalGlow'}do
  for _,p in all(m,name)do table.insert(k.Glow,p)end
 end
 k.Light=find(m,'ChamberLight');k.CoreLight=find(m,'CoreLight');k.Core=find(m,'Core');k.UpperLiquid=find(m,'UpperLiquid')
 k.Beacon=find(m,'Beacon');k.Warnings={};for i=1,4 do local p=find(m,'WarningLight'..i);if p then table.insert(k.Warnings,p)end end
 k.Arm=m:FindFirstChild('PlacerArm')
 k.ArmParts={};if k.Arm then for _,n in{'Turret','Upper','Fore','Claw'}do k.ArmParts[n]=k.Arm:FindFirstChild(n)end end
 k.Guard=find(m,'ButtonGuard');k.Dome=find(m,'ButtonDome');k.LeverL=find(m,'LeverL');k.LeverR=find(m,'LeverR')
 k.Needles={};for i=1,4 do local p=find(m,'GaugeNeedle'..i);if p then table.insert(k.Needles,p)end end
 k.Labels={}
 for _,screen in{'ScreenL','ScreenR','MainSign','DeskPlate'}do
  local part=find(m,screen);local gui=part and part:FindFirstChild('Display')
  if gui then for _,t in gui:GetChildren()do if t:IsA('TextLabel')then k.Labels[screen..'.'..t.Name]=t end end end
 end
 return k
end
local function label(k,key,text,color)
 local t=k.Labels[key];if not t then return end
 set(t,'Text',text);if color then set(t,'TextColor3',color)end
end
local function setGlow(k,color,transparencyBoost)
 for _,p in k.Glow do set(p,'Color',color)end
 for _,p in k.Rails do set(p,'Color',color);set(p,'Transparency',transparencyBoost or .15)end
 if k.Light then set(k.Light,'Color',color)end
 if k.Surface then set(k.Surface,'Color',color)end
 if k.UpperLiquid then set(k.UpperLiquid,'Color',color:Lerp(L.Liquid,.55))end
 if k.Liquid then set(k.Liquid,'Color',color:Lerp(L.Liquid,.35))end
end
local function setLiquid(k,level,visible)
 if not(k.Liquid and k.Surface)then return end
 local floor=L.Tube.FloorTop;local h=math.max(.05,level-floor)
 set(k.Liquid,'Size',Vector3.new(h,L.Tube.LiquidRadius*2,L.Tube.LiquidRadius*2))
 set(k.Liquid,'CFrame',k.CF(CFrame.new(0,floor+h/2,0)*CFrame.Angles(0,0,math.pi/2)))
 set(k.Surface,'CFrame',k.CF(CFrame.new(0,floor+h,0)*CFrame.Angles(0,0,math.pi/2)))
 set(k.Liquid,'Transparency',visible and .55 or 1)
 set(k.Surface,'Transparency',visible and .25 or 1)
end
-- Lift: carriage on the rails at x, platform bottom at deckY.
local function setLift(k,x,deckY)
 local Lf=L.Lift
 if k.Carriage then pivot(k.Carriage,k.CF(CFrame.new(x,Lf.RailTop,0)))end
 if k.Platform then pivot(k.Platform,k.CF(CFrame.new(x,deckY,0)))end
 if k.Mast then
  local h=math.max(.2,deckY-Lf.CarriageTop)
  set(k.Mast,'Size',Vector3.new(h,1.3,1.3))
  set(k.Mast,'CFrame',k.CF(CFrame.new(x,Lf.CarriageTop+h/2,0)*CFrame.Angles(0,0,math.pi/2)))
  set(k.Mast,'Transparency',h>.3 and 0 or 1)
 end
end
local function setArm(k,target)
 if not k.Arm then return end
 local pose=L.ArmPose(target)
 for name,model in k.ArmParts do pivot(model,k.CF((pose::any)[name]))end
end
local function setRotors(k,angle)
 for i,r in k.Rotors do set(r.Hub,'CFrame',k.CF(CFrame.new(0,r.Y,0)*CFrame.Angles(0,angle*(i==1 and 1 or -1.3),0)))end
end
-- Dog standing on the platform.
local function placeDog(k,x,deckY,yaw)
 if not(shown and shown.Model.Parent)then return end
 local top=deckY+L.Lift.DeckThickness
 Rig.Place(shown.Model,k.W(Vector3.new(x,top,0)),CFrame.Angles(0,yaw,0))
end

------------------------------------------------------------------------------------------------
-- Idle motion (near the machine) and the public pulse for other players
------------------------------------------------------------------------------------------------
local idle={Tweens={},Running=false,Machine=nil}
local function stopIdle()
 for _,t in idle.Tweens do t:Cancel()end
 table.clear(idle.Tweens)
 if idle.Running then restoreAll()end
 if fx then fx.Bubbles.Enabled=false end
 idle.Running=false
end
local function startIdle(m)
 if idle.Running or P.Playing or shown then return end
 local k=rig(m);idle.Running=true;idle.Machine=m
 local still=reduced()
 local function loop(o,props,info)
  if not(o and o.Parent)then return end
  for key in pairs(props)do touch(o,key)end
  local t=TweenService:Create(o,info,props);t:Play();table.insert(idle.Tweens,t)
 end
 if not still then
  for i,r in k.Rotors do
   touch(r.Hub,'CFrame')
   local base=k.CF(CFrame.new(0,r.Y,0))
   r.Hub.CFrame=base
   loop(r.Hub,{CFrame=base*CFrame.Angles(0,(i==1 and 1 or -1)*2*math.pi/3,0)},TweenInfo.new(i==1 and 9 or 12,Enum.EasingStyle.Linear,Enum.EasingDirection.InOut,-1))
  end
 end
 loop(k.Core,{Transparency=.35},TweenInfo.new(1.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true))
 loop(k.Beacon,{Transparency=.85},TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut,-1,true))
 loop(k.CoreBeam,{Transparency=.65},TweenInfo.new(1.2,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true))
 for _,p in k.Rails do loop(p,{Transparency=.55},TweenInfo.new(1.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true))end
 if not lowFX()then
  local f=pool()
  f.Floor.CFrame=k.CF(CFrame.new(0,L.Tube.FloorTop+.3,0));f.Floor.Size=Vector3.new(12,.2,12)
  f.Bubbles.Color=ColorSequence.new(L.Teal);f.Bubbles.Rate=5;f.Bubbles.Enabled=true
 end
end

-- Another player's mutation: the chamber charges up and bursts in the result colour (cheap).
local publicBusy=false
local publicConn=nil
local function burst(k,color,big,low)
 local f=pool()
 local center=k.W(Vector3.new(0,16,0))
 f.Anchor.CFrame=CFrame.new(center);f.Floor.CFrame=CFrame.new(k.W(Vector3.new(0,.6,0)))
 f.Flash.Color=color;f.Flash.Size=Vector3.one*3;f.Flash.CFrame=CFrame.new(center);f.Flash.Transparency=.05
 TweenService:Create(f.Flash,TweenInfo.new(big and .55 or .4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.one*(big and 34 or 22),Transparency=1}):Play()
 for i,r in f.Rings do
  if i==1 or big then
   r.Color3=color;r.Radius=8;r.InnerRadius=7;r.Height=.6;r.Transparency=0;r.Visible=true
   local goal=big and 64 or 40
   TweenService:Create(r,TweenInfo.new(.75,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Radius=goal,InnerRadius=goal-2.4,Transparency=1}):Play()
  end
 end
 f.Burst.Color=ColorSequence.new(color,Color3.new(1,1,1));f.Sparks.Color=ColorSequence.new(Color3.new(1,1,1),color)
 f.Burst:Emit(low and 22 or(big and 90 or 40));f.Sparks:Emit(low and 10 or 36)
end
local function publicPulse(m,variant)
 if publicBusy or P.Playing or not m.Parent then return end
 local camera=workspace.CurrentCamera
 local k=rig(m)
 if not camera or(camera.CFrame.Position-k.W(Vector3.new(0,16,0))).Magnitude>170 then return end
 publicBusy=true
 local wasIdle=idle.Running;stopIdle()
 local color=colorOf(variant);local low=lowFX();local calm=reduced()
 local total=C.Machine.PublicBurst;local start=os.clock();local fired=false;local angle=0
 local conn
 conn=Run.Heartbeat:Connect(function(dt)
  if conn~=publicConn then return end
  local t=os.clock()-start
  if not m.Parent or P.Playing then t=total+2 end
  if t<total then
   local x=t/total
   setGlow(k,L.Teal:Lerp(Color3.new(1,1,1),x*.35),.15-.15*x)
   if k.Light then set(k.Light,'Brightness',1.4+x*3)end
   if not calm then angle+=dt*(0.6+x*12);setRotors(k,angle)end
  elseif not fired then
   fired=true;setGlow(k,color,0)
   if k.Light then set(k.Light,'Brightness',7)end
   burst(k,color,false,low or calm)
   P.Cue('Pulse',k.M:FindFirstChild('ChamberLightPart',true))
  elseif t<total+1.4 then
   if k.Light then set(k.Light,'Brightness',lerp(7,1.4,(t-total)/1.4))end
  else
   conn:Disconnect();publicConn=nil;restoreAll();publicBusy=false
   if wasIdle then task.defer(function()local mm=machine();if mm then startIdle(mm)end end)end
  end
 end)
 publicConn=conn
end
-- The local player's own cinematic replaces a public pulse at once.
local function stopPublic()
 if publicConn then publicConn:Disconnect();publicConn=nil end
 publicBusy=false
end

-- Machine screens in the player's language (server texts are English; labels carry NoTranslate).
local function localizeScreens(m)
 if Lang.Get()~='ru'then return end
 for _,t in m:GetDescendants()do
  if t:IsA('TextLabel')and t:GetAttribute('Localized')~=true then
   local ru=Dict.Machine and Dict.Machine[t.Text]or Dict.UI[t.Text]
   if ru then t.Text=upper(ru)end
   t:SetAttribute('Localized',true)
  end
 end
end

function P.StartWorld()
 if P.WorldStarted then return end;P.WorldStarted=true
 task.spawn(function()
  local lastPulse=nil
  while true do
   local m,lab=machine()
   if lab and lastPulse==nil then
    lastPulse=lab:GetAttribute('MachinePulse')or 0
    lab:GetAttributeChangedSignal('MachinePulse'):Connect(function()
     local seq=lab:GetAttribute('MachinePulse')
     local at=tonumber(lab:GetAttribute('MachinePulseAt'))or 0
     if seq==lastPulse then return end;lastPulse=seq
     if lab:GetAttribute('MachinePulseUser')==player.UserId then return end
     if math.abs(workspace:GetServerTimeNow()-at)>3 then return end
     local mm=machine();if mm then publicPulse(mm,tostring(lab:GetAttribute('MachinePulseVariant')or'Normal'))end
    end)
   end
   if m then
    localizeScreens(m)
    local camera=workspace.CurrentCamera
    local near=camera~=nil and(camera.CFrame.Position-m:GetPivot().Position).Magnitude<220
    if near and not idle.Running and not P.Playing and not publicBusy and not shown then startIdle(m)
    elseif(not near or idle.Machine~=m)and idle.Running then stopIdle()end
   elseif idle.Running then
    idle.Running=false;table.clear(idle.Tweens);table.clear(saved)
   end
   task.wait(2)
  end
 end)
end

------------------------------------------------------------------------------------------------
-- The cinematic
------------------------------------------------------------------------------------------------
-- Colour reel steps (MutationMachineLayout.ReelSteps): slows down and lands on the server's result.
function P.ReelSteps(result,duration)
 local names={};for _,v in ipairs(Base.Variants)do table.insert(names,v.Name)end
 return L.ReelSteps(result,duration,names)
end

local function legacyPlay(result)
 -- The old chamber camera (LabConfig.MachineWorld off): a short look at the chamber while the result lands.
 local lab=Access.Model();local chamber=lab and lab:FindFirstChild('CentralChamber');local anchor=chamber and chamber:FindFirstChild('DisplayAnchor')
 local cam=lab and lab:FindFirstChild('PresentationCamera')
 if not(anchor and cam)then return end
 local camera=workspace.CurrentCamera;local oldType,oldCF=camera.CameraType,camera.CFrame
 P.Playing=true;P.SkipRequested=false
 local start=os.clock();local duration=reduced()and 1 or(result.Duration or C.Duration)
 P.Cue('Lock',lab:FindFirstChild('AudioAnchor'))
 while os.clock()-start<duration and not P.SkipRequested do
  camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=CFrame.lookAt(cam.Position,anchor.Position+Vector3.new(0,5,0))
  Run.RenderStepped:Wait()
 end
 camera.CameraType=oldType;camera.CFrame=oldCF
 P.Playing=false;P.SkipRequested=false
end

local function shotCF(k,eye,focus,shake,time)
 local e,f=k.W(eye),k.W(focus)
 if shake>0 then
  local n=Vector3.new(math.noise(time*9,1.3),math.noise(time*9,7.1),math.noise(time*9,3.7))
  e+=n*shake;f+=n*shake*.5
 end
 return CFrame.lookAt(e,f)
end
local function orbit(t0,t1,t)
 local s=L.Shots.Chamber;local a=math.rad(lerp(s.From,s.To,span(t,t0,t1)))
 return s.Center+Vector3.new(math.cos(a)*s.Radius,s.Height,math.sin(a)*s.Radius),s.Center
end

function P.Play(result)
 if type(result)~='table'or P.Seen[result.Token or'']then return end
 if result.Token then P.Seen[result.Token]=true end
 local m=machine(2)
 if not m then legacyPlay(result);return end
 if P.Playing then return end
 stopPublic()
 stopIdle()
 P.Release(true)
 local k=rig(m);local f=pool();resetPool()
 local calm=reduced();local low=lowFX()
 local before=result.BeforeDog or result.Dog
 local after=result.Dog or result.BeforeDog
 local fromVariant=before and before.Variant or'Normal'
 local toVariant=after and after.Variant or'Normal'
 local toColor=colorOf(toVariant)
 local Mc=C.Machine
 local t1=Mc.Activate;local t2=t1+Mc.Load;local t3=t2+Mc.Rise;local t4=t3+Mc.Reel;local t5=t4+Mc.Hold;local t6=t5+Mc.Reveal
 if calm then t1,t2,t3=0,0,.6;t4=t3+.8;t5=t4;t6=Mc.Reduced end
 local steps=calm and{}or P.ReelSteps(toVariant,Mc.Reel)
 local camera=workspace.CurrentCamera
 local oldType,oldSubject,oldCF,oldFov=camera.CameraType,camera.CameraSubject,camera.CFrame,camera:GetAttribute('SecretZoom')or camera.FieldOfView
 P.Playing=true;P.SkipRequested=false
 local connections={}
 local Lf=L.Lift;local A=L.Arm
 -- The dog (before), materialized on the platform.
 if after then shown=makeDog(before or after)end
 local dogHighlight=nil
 if shown then tint(shown.Model,fromVariant,.85);dogHighlight=shown.Model:FindFirstChild('EconomyVariant')end
 local materialize=nil
 if shown then
  materialize=Instance.new('Highlight');materialize.Name='Materialize';materialize.FillColor=Color3.new(1,1,1);materialize.OutlineColor=L.Teal
  materialize.FillTransparency=0;materialize.OutlineTransparency=0;materialize.DepthMode=Enum.HighlightDepthMode.Occluded;materialize.Enabled=false;materialize.Parent=shown.Model
  for _,o in shown.Model:GetDescendants()do if o:IsA('BasePart')then o.LocalTransparencyModifier=1 end end
 end
 f.Gui.Enabled=true;f.Hint.Text=T('TAP TO SKIP');f.Ticker.Text=''
 local skipOffset=0;local startedAt=os.clock()
 table.insert(connections,UIS.InputBegan:Connect(function(input)
  local kind=input.UserInputType
  if kind==Enum.UserInputType.MouseButton1 or kind==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.Space or input.KeyCode==Enum.KeyCode.ButtonA or input.KeyCode==Enum.KeyCode.Return then
   if os.clock()-startedAt>.35 then P.SkipRequested=true end
  end
 end))
 local cueParent=find(m,'ChamberLightPart')
 local consoleParent=find(m,'ConsoleLamp')
 local phase={}
 local function once(key,fn)if not phase[key]then phase[key]=true;fn()end end
 local reelIndex=0;local arcAt=0;local rotor=0;local lastT=0;local shownDog=false
 local yaw=math.pi/2
 local ok,err=xpcall(function()
  if calm then
   setLift(k,Lf.InsideX,Lf.RaisedDeck)
   if k.CoreBeam then set(k.CoreBeam,'Transparency',1)end
  end
  while true do
   local t=os.clock()-startedAt+skipOffset
   if P.SkipRequested then
    P.SkipRequested=false
    if t<t5-.05 then skipOffset+=t5-t;t=t5 else break end
   end
   if t>=t6 then break end
   local dt=math.max(0,t-lastT);lastT=t
   -- Console: guard, button, levers, gauges, screens.
   if not calm then
    if k.Guard then pivot(k.Guard,(saved[k.Guard]and saved[k.Guard].Pivot or k.Guard:GetPivot())*CFrame.Angles(0,0,-math.rad(105)*span(t,0,.3)))end
    if k.Dome then
     local press=(span(t,.3,.42)-span(t,.5,.7))*(k.Dome:GetAttribute('Press')or .28)
     local base=saved[k.Dome]and saved[k.Dome].CFrame or k.Dome.CFrame
     set(k.Dome,'CFrame',base*CFrame.new(0,-press,0))
     set(k.Dome,'Color',t<.9 and(math.floor(t*12)%2==0 and Color3.new(1,1,1)or Color3.fromRGB(255,52,52))or Color3.fromRGB(255,52,52))
    end
    for i,lever in{k.LeverL,k.LeverR}do
     if lever then
      local base=saved[lever]and saved[lever].Pivot or lever:GetPivot()
      pivot(lever,base*CFrame.Angles(0,0,math.rad(38)*span(t,.12+i*.08,.5+i*.08)))
     end
    end
   end
   for i,needle in k.Needles do
    local p=needle:GetAttribute('Pivot')
    if typeof(p)=='CFrame'then
     local level=span(t,t1,t4)
     local wobble=math.sin(t*(7+i))*.12*level
     set(needle,'CFrame',p*CFrame.Angles(math.rad(-60+level*120)+wobble,0,0)*CFrame.new(0,.25,0))
    end
   end
   for i,w in k.Warnings do set(w,'Transparency',(math.floor(t*4+i*.5)%2==0)and 0 or .8)end
   if k.Beacon then set(k.Beacon,'Transparency',(math.floor(t*6)%2==0)and 0 or .85)end
   -- Status texts.
   local status
   if t<t1 then status=T('ACTIVATED')elseif t<t2 then status=T('LOADING')elseif t<t3 then status=T('CHARGING')
   elseif t<t5 then status=nil else status=toVariant=='Normal'and T('STABLE')or(variantName(toVariant)..'!')end
   if status then label(k,'MainSign.Status',status,t>=t5 and toColor or nil)end
   label(k,'ScreenL.Line2',string.format('%s %d%%',T('ENERGY'),math.floor(100+180*span(t,t2,t5))),nil)
   label(k,'ScreenL.Line1',t<t5 and T('CORE CHARGING')or T('CORE STABLE'),nil)
   -- Arm, dog, door, lift.
   if not calm then
    local armTarget
    if t<t1 then armTarget=A.Rest
    elseif t<t1+.5 then armTarget=A.Rest:Lerp(A.Place,span(t,t1,t1+.5))
    elseif t<t1+.65 then armTarget=A.Place
    else armTarget=A.Place:Lerp(A.Rest,span(t,t1+.65,t1+1.05))end
    setArm(k,armTarget)
    if k.Door then
     local drop=(span(t,t1+.55,t1+.8)-span(t,t2-.2,t2))*L.Door.Drop
     local base=saved[k.Door]and saved[k.Door].CFrame or k.Door.CFrame
     set(k.Door,'CFrame',base-Vector3.new(0,drop,0))
    end
   end
   local x=calm and Lf.InsideX or lerp(Lf.RestX,Lf.InsideX,span(t,t1+.8,t2-.2))
   local deck=calm and Lf.RaisedDeck or lerp(Lf.RestDeck,Lf.RaisedDeck,span(t,t2,t3))
   if not calm then setLift(k,x,deck)end
   if t>=t2 then once('coreOff',function()if k.CoreBeam then set(k.CoreBeam,'Transparency',1)end end)end
   if shown and not shownDog and(calm or t>=t1+.42)then
    shownDog=true
    for _,o in shown.Model:GetDescendants()do if o:IsA('BasePart')then o.LocalTransparencyModifier=0 end end
    if materialize then materialize.Enabled=true end
    f.Anchor.CFrame=CFrame.new(k.W(Vector3.new(x,deck+2.5,0)));f.Sparks.Color=ColorSequence.new(Color3.new(1,1,1),L.Teal);f.Sparks:Emit(low and 8 or 24)
    P.Cue('Select',consoleParent)
   end
   if materialize then materialize.FillTransparency=span(t,(calm and 0 or t1+.42),(calm and .5 or t1+.95));materialize.OutlineTransparency=materialize.FillTransparency
    if materialize.FillTransparency>=.99 then materialize.Enabled=false end end
   if shown then
    yaw=math.pi/2+(t>t2 and(t-t2)*.45 or 0)
    placeDog(k,x,deck,yaw)
    if shown.Anim then shown.Anim:Step(workspace:GetServerTimeNow())end
   end
   -- Liquid.
   local fill=calm and span(t,0,.6)or span(t,t2+.15,t3+.5)
   local drain=calm and span(t,t5,t6-.2)or span(t,t5+.12,t5+.95)
   local level=lerp(L.Tube.FloorTop,L.Tube.LiquidFull,fill*(1-drain))
   setLiquid(k,level,level>L.Tube.FloorTop+.1)
   if not low and t>=t2+.2 and t<t5 and not f.Bubbles.Enabled then
    f.Floor.CFrame=k.CF(CFrame.new(0,L.Tube.FloorTop+.3,0));f.Floor.Size=Vector3.new(12,.2,12);f.Bubbles.Rate=calm and 6 or 26;f.Bubbles.Enabled=true
   elseif t>=t5 then f.Bubbles.Enabled=false end
   -- Rotors (spin up, burst, settle).
   if not calm then
    local speed=.4+11*span(t,t2,t4)+(t>t5 and 8*(1-span(t,t5,t6))or 0)
    rotor+=dt*speed;setRotors(k,rotor)
   end
   -- Colour: teal until the reel, the reel steps, then the result.
   local color=L.Teal
   if calm then color=L.Teal:Lerp(toColor,span(t,t3,t4))
   elseif t>=t3 and t<t4 then
    local idx=1;for i,s in steps do if t-t3>=s.At-.0001 then idx=math.min(i+1,#steps)end end
    if t-t3<steps[1].At then idx=1 end
    local stepName=steps[idx]and steps[idx].Name or toVariant
    color=colorOf(stepName)
    if idx~=reelIndex then
     reelIndex=idx
     f.Ticker.Text=variantName(stepName);f.Ticker.TextColor3=color;f.TickerScale.Scale=1.25
     TweenService:Create(f.TickerScale,TweenInfo.new(.12),{Scale=1}):Play()
     label(k,'MainSign.Status',variantName(stepName),color)
     P.Cue('Tick',consoleParent,.8+idx/#steps*.9)
     if not low then f.Anchor.CFrame=CFrame.new(k.W(Vector3.new(0,deck+2.5,0)));f.Sparks.Color=ColorSequence.new(Color3.new(1,1,1),color);f.Sparks:Emit(4)end
    end
   elseif t>=t4 then color=toColor end
   local pulse=(t>=t4 and t<t5)and(math.floor(t*14)%2==0 and 0 or .3)or(.15-.15*span(t,t2,t4))
   setGlow(k,color,pulse)
   if k.Light then
    local b=1.4+3*span(t,t2,t4)
    if t>=t5 then b=lerp(10,2.6,span(t,t5,t5+.8))end
    set(k.Light,'Brightness',b)
   end
   if k.Core then set(k.Core,'Color',color:Lerp(Color3.new(1,1,1),.5))end
   -- Injector beam and arcs during the energy phase.
   if not calm and t>=t3-.2 and t<t5 then
    local tip=k.W(Vector3.new(0,L.Tube.InjectorTip,0))
    local head=k.W(Vector3.new(0,deck+L.Lift.DeckThickness+(shown and shown.Height or 3)+.2,0))
    local len=(tip-head).Magnitude;local w=.35+.35*math.abs(math.sin(t*23))
    f.Beam.Size=Vector3.new(len,w,w);f.Beam.CFrame=CFrame.lookAt((tip+head)/2,head)*CFrame.Angles(0,math.pi/2,0)
    f.Beam.Color=color;f.Beam.Transparency=.15
    if not low and t-arcAt>.07 then
     arcAt=t
     for i,a in f.Arcs do
      local on=math.random()<.75
      a.Beam.Enabled=on
      if on then
       local rail=k.Rails[(i-1)%math.max(1,#k.Rails)+1]
       local ry=lerp(L.Tube.IntakeTop+1,L.Tube.GlassTop-1,math.random())
       local ra=math.rad(45+((i-1)%4)*90)
       a.A.WorldPosition=rail and k.W(Vector3.new(math.cos(ra)*L.Tube.RailRadius,ry,math.sin(ra)*L.Tube.RailRadius))or tip
       a.B.WorldPosition=k.W(Vector3.new((math.random()-.5)*2,deck+1+math.random()*(shown and shown.Height or 3),(math.random()-.5)*2))
       a.Beam.CurveSize0=(math.random()-.5)*6;a.Beam.CurveSize1=(math.random()-.5)*6
       a.Beam.Color=ColorSequence.new(Color3.new(1,1,1),color)
      end
     end
     if math.random()<.25 then P.Cue('Arc',cueParent)end
    end
   else
    f.Beam.Transparency=1
    for _,a in f.Arcs do a.Beam.Enabled=false end
   end
   -- Sounds of the phases.
   if t>=0 then once('activate',function()P.Cue('Activate',consoleParent)end)end
   if not calm and t>=t1+.8 then once('servo',function()P.Cue('Servo',cueParent)end)end
   if t>=t2+.1 then once('fill',function()P.Cue('Fill',cueParent)end)end
   if t>=t3-.3 then once('charge',function()P.Cue('Charge',cueParent)end)end
   -- The burst.
   if t>=t5 then
    once('burst',function()
     f.Ticker.Text=toVariant=='Normal'and T('STABLE')or(variantName(toVariant)..'!');f.Ticker.TextColor3=toColor;f.TickerScale.Scale=1.6
     TweenService:Create(f.TickerScale,TweenInfo.new(.3,Enum.EasingStyle.Back),{Scale=1.15}):Play()
     if shown then
      dogHighlight=tint(shown.Model,toVariant,calm and .6 or .1)
      if dogHighlight and toVariant~='Normal'then TweenService:Create(dogHighlight,TweenInfo.new(1.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{FillTransparency=.85}):Play()end
     end
     burst(k,toColor,not calm,low or calm)
     f.Anchor.CFrame=CFrame.new(k.W(Vector3.new(0,deck+2.5,0)))
     f.Flash2D.BackgroundColor3=toColor:Lerp(Color3.new(1,1,1),.6);f.Flash2D.BackgroundTransparency=calm and .55 or .05
     TweenService:Create(f.Flash2D,TweenInfo.new(calm and .5 or .45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
     if not calm then
      f.CC.TintColor=Color3.new(1,1,1):Lerp(toColor,.25);f.CC.Brightness=.3;f.CC.Saturation=.3;f.CC.Contrast=.1;f.CC.Enabled=true
      TweenService:Create(f.CC,TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Brightness=0,Saturation=0,Contrast=0,TintColor=Color3.new(1,1,1)}):Play()
     end
     P.Cue('Pulse',cueParent);P.Cue(C.HighValueVariants[toVariant]and'Rare'or'Reveal',nil)
    end)
   end
   -- Camera.
   local S=L.Shots;local eye,focus,fov,shake
   if calm then eye,focus,fov,shake=S.Reveal.Eye,S.Reveal.Focus,S.Reveal.Fov+4,0
   elseif t<t1 then
    local x2=span(t,0,t1);eye=S.Activate.Eye:Lerp(S.Activate.Eye+Vector3.new(1.2,-.4,-.6),x2);focus=S.Activate.Focus;fov=S.Activate.Fov;shake=(t>.3 and t<.55)and .08 or 0
   elseif t<t2 then
    local x2=span(t,t1,t2);eye=S.Load.Eye:Lerp(S.Load.Eye+Vector3.new(2.5,0,-2),x2);focus=S.Load.Focus:Lerp(Vector3.new(-6,8.5,0),x2);fov=S.Load.Fov;shake=0
   elseif t<t3 then
    local oe,of=orbit(t3,t4+Mc.Hold,t3)
    local x2=span(t,t2,t3);eye=(S.Load.Eye+Vector3.new(2.5,0,-2)):Lerp(oe,x2);focus=Vector3.new(-6,8.5,0):Lerp(of,x2);fov=lerp(S.Load.Fov,S.Chamber.Fov,x2);shake=0
   elseif t<t4 then
    eye,focus=orbit(t3,t4+Mc.Hold,t);fov=S.Chamber.Fov;shake=.05+.18*span(t,t3,t4)
   elseif t<t5 then
    local oe,of=orbit(t3,t4+Mc.Hold,t)
    local x2=span(t,t4,t5);eye=oe:Lerp(S.Reveal.Eye,x2);focus=of:Lerp(S.Reveal.Focus,x2);fov=lerp(S.Chamber.Fov,S.Reveal.Fov+4,x2);shake=.25
   else
    local x2=span(t,t5,t6);eye=S.Reveal.Eye:Lerp(S.Reveal.Eye+Vector3.new(2.2,-.3,-.6),x2);focus=S.Reveal.Focus;fov=lerp(S.Reveal.Fov+4,S.Reveal.Fov,x2);shake=.9*(1-span(t,t5,t5+.6))
   end
   camera.CameraType=Enum.CameraType.Scriptable
   camera.FieldOfView=fov
   camera.CFrame=shotCF(k,eye,focus,shake,t)
   Run.RenderStepped:Wait()
  end
 end,debug.traceback)
 -- End of the cinematic: camera and console back, the chamber keeps the dog in its new colour.
 for _,c in connections do c:Disconnect()end
 P.Playing=false;P.SkipRequested=false
 for _,a in f.Arcs do a.Beam.Enabled=false end
 f.Beam.Transparency=1;f.Bubbles.Enabled=false;f.Gui.Enabled=false;f.Ticker.Text=''
 if materialize then materialize:Destroy()end
 if shown then
  for _,o in shown.Model:GetDescendants()do if o:IsA('BasePart')then o.LocalTransparencyModifier=0 end end
  tint(shown.Model,toVariant,.85)
 end
 pcall(function()
  setLiquid(k,L.Tube.FloorTop,false)
  if not calm then setLift(k,Lf.InsideX,Lf.RaisedDeck);setArm(k,A.Rest)end
  setGlow(k,toColor,.15)
  if k.Light then set(k.Light,'Brightness',2.6)end
  label(k,'MainSign.Status',toVariant=='Normal'and T('STABLE')or(variantName(toVariant)..'!'),toColor)
 end)
 -- The console controls go back now; the chamber waits for P.Release().
 for _,o in{k.Guard,k.Dome,k.LeverL,k.LeverR}do
  local s=o and saved[o]
  if s and o.Parent then pcall(function()if s.Pivot then o:PivotTo(s.Pivot)end;if s.CFrame then o.CFrame=s.CFrame end;if s.Color then o.Color=s.Color end end);saved[o]=nil end
 end
 local character=player.Character;local humanoid=character and character:FindFirstChildOfClass('Humanoid')
 camera.CameraType=oldType==Enum.CameraType.Scriptable and Enum.CameraType.Custom or oldType
 camera.CameraSubject=humanoid or oldSubject;camera.FieldOfView=oldFov
 if oldType==Enum.CameraType.Scriptable then camera.CFrame=oldCF end
 if shown then
  local yawNow=yaw;local current=shown
  -- Callers release when their result card closes; the old lab window never does, so a timeout too.
  task.delay(P.AutoRelease,function()if shown==current and not P.Playing then P.Release()end end)
  shown.Conn=Run.Heartbeat:Connect(function(dt2)
   if not(shown and shown.Model.Parent)then return end
   yawNow+=dt2*.5
   placeDog(k,Lf.InsideX,Lf.RaisedDeck,yawNow)
   if shown.Anim then shown.Anim:Step(workspace:GetServerTimeNow())end
  end)
 else
  task.delay(1.5,function()if not P.Playing then P.Release()end end)
 end
 if not ok then
  P.Release(true)
  error(err)
 end
end

-- The result card closed: the dog dissolves and the machine goes back to idle.
function P.Release(instant)
 if shown and shown.Model.Parent and not instant then
  local f=pool()
  local cf,size=shown.Model:GetBoundingBox()
  f.Anchor.CFrame=cf;f.Sparks.Color=ColorSequence.new(Color3.new(1,1,1),L.Teal);f.Sparks:Emit(lowFX()and 6 or 20)
  local _=size
 end
 dropDog()
 restoreAll()
 resetPool()
 local m=machine()
 if m and not instant then task.defer(function()if not P.Playing and not publicBusy then startIdle(m)end end)end
end

return P
