-- NUCLEAR MUTATION TOWER: the client cinematic of a mutation (the lab is a nuclear cooling tower; geometry
-- in ReplicatedStorage.NuclearLayout, built by ServerScriptService.NuclearTowerBuild). Client only.
--   P.Play(result)   yields while the cinematic plays (LabConfig.Tower; Reduced Motion: a short version).
--                    Beats and shots (cameras: NuclearLayout.Shots, chosen per frame by direct() in P.Play):
--                      operator   over the owner's shoulder at the console: guard, START, levers, screens
--                      place      the dog comes out of the inventory and trots onto the loading pad
--                      door       behind the dog: the WARNING blast door rises, the nuclear alarm starts
--                      grab       a high security-camera angle: the mechanical arm takes the dog
--                      look       over the owner's shoulder: the dog in the claw turns and looks at you
--                      intake     from the pad: the dog is pulled in, the door slams (a camera kick)
--                      crane      up the tower: steam, dust, the colour reel starts
--                      hero       the tower, its crown and the beam rising into the sky
--                      chamber    inside: the reel colours strobe over the dog in the claw ...
--                      burst      ... it bursts into its new colours (Normal: it fizzles in grey smoke)
--                      variant    the variant's own sequence:
--                        Normal     MUTATION FAILED on the screens, the beam dies, a grey mood
--                        Golden     coins burst from the crown, gold streams run down the tower
--                        Shiny      white flashes, the tower cracks, light beams from the cracks and the door
--                        Corrupted  silence... a huge red beam, a cola-and-mentos eruption, drops around you
--                        Glitched   a Windows error window over the tower fills up and overflows, a 5 s
--                                   blue error screen types "restart game", the window vanishes
--                        Void       darkness, the camera flies to the Void island, a spinning portal fires a
--                                   beam at the tower, clouds, lightning, glyphs, the ground turns purple,
--                                   glyphs morph letter by letter into VOID MUTATION
--                      exit door  the door opens (steam in the new colour) on the mutated dog
--                      walk       it walks out at you and stops on the pad, facing the cameras
--                      close-ups  slow dollies while it stands still: paws, head (face + glow), tail
--                      orbit      the pad lights up in its colour, a slow arc round the dog (showcase)
--                      home       it walks back to its owner and jumps into the inventory
--                    North of the plaza stands a 50-stud black box (GlobalEventComingSoon): low shots look
--                    east-south-east .. south-west only (NuclearLayout.Shots).
--   P.Skip()         tap / click / Space also skips: to the burst, to the exit, to the end
--   P.Release()      the result card closed (kept for the window; the dog is already back home)
--   P.StartWorld()   once per client (LabPrompt.client): the idle tower (screens, keys, lamps, the emblem,
--                    the pad) and the public show when another player mutates a dog (beam, colours and a
--                    short variant effect for everyone within LabConfig.Tower.ShowRange; no camera)
--   P.PublicShow(v)  Studio / tests: play the public show of a variant now
--   P.ReelSteps(result, duration)  the colour reel (NuclearLayout.ReelSteps)
--   P.Cue(key, part) a lab sound (LabAudioConfig), quieter during world events
-- Everything the cinematic changes on the server's tower parts is remembered and restored (CFrames, sizes of
-- the telescopic arm, colours, lights); effects live in one pooled folder (+ a scene folder destroyed after
-- each show); the dog clone exists only while shown. The owner's pickaxe goes back into the hotbar and its
-- welded model is hidden on this client for the whole cinematic; a reset or death of the owner ends it at
-- once; a public show still running when it starts is ended first.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local TweenService=game:GetService('TweenService')
local Lighting=game:GetService('Lighting')
local SoundService=game:GetService('SoundService')
local C=require(RS.LabConfig);local AC=require(RS.LabAudioConfig);local Access=require(RS.LabAccess)
local L=require(RS:WaitForChild('NuclearLayout'))
local Glow=require(RS:WaitForChild('MutationGlow'))
local Base=require(RS.DogEconomy.Config)
local Definitions=require(RS.DogEconomy.DogDefinitions)
local Rig=require(RS.DogRig)
local Animation=require(RS.DogAnimationPlayer)
local Dict=require(RS:WaitForChild('Localization'):WaitForChild('Lab'))
local Lang=require(script.Parent.Kit.Lang)
local Motion=require(script.Parent.Kit.Motion)
local player=Players.LocalPlayer
local P={Seen={},Playing=false,AutoRelease=45,WorldStarted=false,SkipRequested=false}

local TW=C.Tower or{Place=1.6,Door=4.6,Grab=6.6,Look=8.4,Intake=10.0,Reactor=11.8,Reel=13.0,Reveal=17.0,Burst=1.2,Exit=11.5,Reduced=4.5,
 Variant={Normal=5,Shiny=7,Golden=7,Corrupted=8,Glitched=12,Void=10},PublicShow=7,ShowRange=900}
local G=L.Ground
local CENTER=L.Center
local HEIGHT=L.Tower.Height
local CROWN=CENTER+Vector3.new(0,HEIGHT,0)
local WHITE=Color3.new(1,1,1)
local BLACK=Color3.new(0,0,0)
local V3=Vector3.new
local CF=CFrame.new
local ANG=CFrame.Angles
local FONT=Enum.Font.FredokaOne

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
local function lin(t,a,b)return math.clamp((t-a)/math.max(b-a,1e-3),0,1)end
local function lerp(a,b,x)return a+(b-a)*x end
local function outBack(x)local c1=1.70158;local c3=c1+1;x=math.clamp(x,0,1);return 1+c3*(x-1)^3+c1*(x-1)^2 end
local function flat(v)return V3(v.X,0,v.Z)end
local function facing(dir)
 local f=flat(dir)
 if f.Magnitude<1e-3 then f=V3(-1,0,0)end
 return CFrame.lookAt(Vector3.zero,f.Unit)
end
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
local function loop(name,parent)
 local ok,handle=pcall(AC.Loop,name,parent,activeEvent()and .2 or 1)
 if ok and handle then return handle end
 return {Stop=function()end}
end
function P.Skip()P.SkipRequested=true end
local function colorOf(v)return(L.Colors::any)[v or'Normal']or L.Colors.Normal end
local function bannerOf(v)
 if v=='Normal'or not v then return upper(T('MUTATION FAILED'))end
 return upper(T(string.upper(v)..' MUTATION'))
end

local function tower(wait)
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

------------------------------------------------------------------------------------------------
-- Remembered tower state (everything is put back exactly)
------------------------------------------------------------------------------------------------
local saved={}
local function touch(o,...)
 if not o then return end
 local s=saved[o];if not s then s={};saved[o]=s end
 for _,key in{...}do
  if s[key]==nil then
   if key=='Pivot'then s.Pivot=o:GetPivot()else s[key]=(o::any)[key]end
  end
 end
end
local function restoreAll()
 for o,s in pairs(saved)do
  if o.Parent then
   for key,v in pairs(s)do
    pcall(function()if key=='Pivot'then o:PivotTo(v)else(o::any)[key]=v end end)
   end
  end
 end
 table.clear(saved)
end
local function set(o,key,v)if o and o.Parent then touch(o,key);(o::any)[key]=v end end
local function pivot(o,cf)if o and o.Parent then touch(o,'Pivot');o:PivotTo(cf)end end

------------------------------------------------------------------------------------------------
-- The tower parts the shows drive (NuclearTowerBuild names)
------------------------------------------------------------------------------------------------
local function guiLabels(part,guiName)
 local out={}
 local g=part and part:FindFirstChild(guiName)
 local bg=g and g:FindFirstChild('Bg')
 if bg then for _,d in bg:GetDescendants()do if d:IsA('TextLabel')then out[d.Name]=d end end end
 return out,bg
end
local function partsOf(model)
 local out={}
 if model then for _,d in model:GetChildren()do if d:IsA('BasePart')then table.insert(out,d)end end end
 return out
end
local function rig(m)
 local k={M=m}
 local portal=m:FindFirstChild('Portal')
 k.Door=portal and portal:FindFirstChild('BlastDoor')
 k.DoorBase=k.Door and k.Door:GetPivot()
 k.DoorFace=k.Door and k.Door:FindFirstChild('LeafFace')
 k.DoorText=guiLabels(k.DoorFace,'WarningGui')
 k.DoorSteam=all(portal,'DoorSteam')
 k.PortalBeacons={}
 for _,b in all(portal,'Beacon')do table.insert(k.PortalBeacons,{P=b,L=b:FindFirstChild('BeaconLight')})end
 local con=m:FindFirstChild('Console')
 k.Console=con
 k.ConsoleBeacons={}
 for _,b in all(con,'Beacon')do table.insert(k.ConsoleBeacons,{P=b,L=b:FindFirstChild('BeaconLight')})end
 k.Start=find(con,'StartButton');k.Guard=find(con,'StartGuard')
 k.Keys={}
 for i=1,18 do
  local p=find(con,'Key'..i)
  if p then table.insert(k.Keys,{P=p,Base=p:GetAttribute('BaseColor')or p.Color,Phase=math.random()*6.28,F=.6+math.random()*1.6,I=i})end
 end
 k.Levers={}
 for i=1,4 do
  local p=find(con,'Lever'..i)
  if p then table.insert(k.Levers,{P=p,Knob=find(con,'LeverKnob'..i),Base=p:GetAttribute('Base'),I=i})end
 end
 k.Needles={}
 for i=1,2 do local p=find(con,'Needle'..i);if p then table.insert(k.Needles,{P=p,Base=p:GetAttribute('Base'),I=i})end end
 k.Led=find(con,'LedStrip')
 k.Main=find(con,'MainScreen')
 k.MainText,k.MainBg=guiLabels(k.Main,'MainScreenGui')
 k.Bars={}
 local bars=k.MainBg and k.MainBg:FindFirstChild('Bars')
 if bars then for i=1,16 do local f=bars:FindFirstChild('Bar'..i);if f then table.insert(k.Bars,{F=f,I=i,Seed=math.random()*10})end end end
 local left=find(con,'LeftScreen')
 local lt,lbg=guiLabels(left,'ScreenGui')
 k.MeterValue=lt.Value
 local meter=lbg and lbg:FindFirstChild('Meter');k.MeterFill=meter and meter:FindFirstChild('Fill')
 local right=find(con,'RightScreen')
 local _,rbg=guiLabels(right,'ScreenGui')
 k.Helix={}
 local hx=rbg and rbg:FindFirstChild('Helix')
 if hx then for i=1,10 do local a,b=hx:FindFirstChild('DotA'..i),hx:FindFirstChild('DotB'..i);if a and b then table.insert(k.Helix,{A=a,B=b,I=i})end end end
 k.WingLamps={}
 for _,p in all(con,'WingLamp')do table.insert(k.WingLamps,{P=p,Base=p:GetAttribute('BaseColor')or p.Color,Phase=math.random()})end
 local t=m:FindFirstChild('Tower')
 k.Rim=all(t,'RimGlow');k.Core=find(t,'CoreColumn');k.CoreLight=find(t,'CoreLight');k.Pool=find(t,'CoolantPool')
 local steam=find(t,'CrownSteam');k.Steam=steam and steam:FindFirstChild('Steam')
 local e=m:FindFirstChild('Emblem')
 k.Ring=all(e,'EmblemRing');k.Paw=partsOf(e and e:FindFirstChild('Paw'));k.EmblemDisc=find(e,'EmblemDisc')
 k.Arm=m:FindFirstChild('MutationArm');k.ArmParts=partsOf(k.Arm);k.ArmEye=find(k.Arm,'ArmEye');k.Palm=find(k.Arm,'Palm')
 local ch=m:FindFirstChild('Chamber')
 k.ChamberLight=find(ch,'ChamberLight');k.ChamberLamp=find(ch,'ChamberLamp');k.ChamberStrips=all(ch,'ChamberStrip')
 local pad=m:FindFirstChild('LoadingPad')
 k.PadLights=all(pad,'PadLight');k.PadPaw=partsOf(pad and pad:FindFirstChild('PadPaw'))
 k.Floods={}
 local fl=m:FindFirstChild('Floodlights')
 if fl then for _,d in fl:GetDescendants()do if d:IsA('SpotLight')then table.insert(k.Floods,d)end end end
 k.Hiss=all(m:FindFirstChild('Pipes'),'Hiss')
 k.Center=CENTER+V3(0,40,0)
 return k
end

-- The arm: L.PoseArm writes the CFrames and the telescopic links' sizes (remembered here first); the red eye
-- follows the palm.
local function poseArm(k,target,open)
 if not k.Arm then return target end
 for _,p in k.ArmParts do touch(p,'CFrame','Size')end
 local wrist=L.PoseArm(k.Arm,target,open)
 if k.ArmEye and k.Palm then k.ArmEye.CFrame=k.Palm.CFrame*CF(-0.9,0,0)end
 return wrist
end
local function doorTo(k,x)
 if k.Door and k.DoorBase then pivot(k.Door,k.DoorBase+V3(0,L.Door.Rise*x,0))end
end

------------------------------------------------------------------------------------------------
-- Effect pool (created once) and the 2D layer
------------------------------------------------------------------------------------------------
local fx=nil
local function newPart(parent,name,size,cf,color,mat,tr,shape)
 local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
 p.Material=mat or Enum.Material.Neon;p.Color=color or WHITE;p.Transparency=tr or 0;p.Size=size
 if shape then p.Shape=shape end
 p.CFrame=cf or CF();p.Parent=parent;return p
end
local function emitter(parent,name,props)
 local e=Instance.new('ParticleEmitter');e.Name=name;e.Rate=props.Rate or 0;e.Enabled=props.Enabled==true;e.LightEmission=props.Light or 1;e.LightInfluence=props.Influence or 0
 e.Lifetime=props.Lifetime;e.Speed=props.Speed;e.Size=props.Size;e.SpreadAngle=props.Spread or Vector2.new(180,180)
 e.Drag=props.Drag or 0;e.Acceleration=props.Acceleration or Vector3.zero;e.Transparency=props.Transparency or NumberSequence.new(0,1)
 e.RotSpeed=props.RotSpeed or NumberRange.new(-120,120);e.Rotation=NumberRange.new(0,360)
 if props.Texture then e.Texture=props.Texture end
 if props.Color then e.Color=props.Color end
 if props.Shape then e.Shape=props.Shape;e.ShapeStyle=props.ShapeStyle or Enum.ParticleEmitterShapeStyle.Volume;e.EmissionDirection=props.Direction or Enum.NormalId.Top end
 e.Parent=parent;return e
end
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local SPARKLE='rbxasset://textures/particles/sparkles_main.dds'
local function text2D(parent,name,props)
 local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Font=FONT;t.TextScaled=props.Scaled~=false;t.Text=props.Text or''
 t.TextColor3=props.Color or WHITE;t.TextStrokeTransparency=props.Stroke or 0;t.TextStrokeColor3=props.StrokeColor or Color3.fromRGB(14,22,34)
 t.AnchorPoint=props.Anchor or Vector2.new(.5,.5);t.Position=props.Position or UDim2.fromScale(.5,.5);t.Size=props.Size or UDim2.fromScale(.5,.1)
 t.TextXAlignment=props.AlignX or Enum.TextXAlignment.Center;t.TextYAlignment=props.AlignY or Enum.TextYAlignment.Center
 t.ZIndex=props.Z or 5;t.RichText=props.Rich==true;t.TextWrapped=true
 if props.TextSize then t.TextSize=props.TextSize end
 t.Parent=parent;return t
end
local function frame2D(parent,name,pos,size,color,props)
 props=props or{}
 local f=Instance.new('Frame');f.Name=name;f.Position=pos;f.Size=size;f.BackgroundColor3=color or BLACK;f.BorderSizePixel=0
 f.BackgroundTransparency=props.Transparency or 0;f.AnchorPoint=props.Anchor or Vector2.zero;f.ZIndex=props.Z or 3;f.Parent=parent
 return f
end
local function pool()
 if fx and fx.Folder.Parent and fx.Gui.Parent then return fx end
 if fx then pcall(function()fx.Folder:Destroy();fx.Gui:Destroy();fx.CC:Destroy();fx.Blur:Destroy()end)end
 local folder=Instance.new('Folder');folder.Name='NuclearMutationFX';folder.Parent=workspace
 fx={Folder=folder}
 fx.Beam=newPart(folder,'SkyBeam',V3(1,8,8),CF(CROWN),WHITE,nil,1,Enum.PartType.Cylinder)
 fx.BeamCore=newPart(folder,'SkyBeamCore',V3(1,3,3),CF(CROWN),WHITE,nil,1,Enum.PartType.Cylinder)
 fx.BeamLight=Instance.new('PointLight');fx.BeamLight.Range=60;fx.BeamLight.Brightness=0;fx.BeamLight.Shadows=false;fx.BeamLight.Parent=fx.BeamCore
 fx.Anchor=newPart(folder,'FXAnchor',V3(.2,.2,.2),nil,nil,nil,1)
 fx.Sparks=emitter(fx.Anchor,'Sparks',{Lifetime=NumberRange.new(.35,.9),Speed=NumberRange.new(14,34),Drag=4,Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.6),NumberSequenceKeypoint.new(1,0)}),Texture=SPARKLE})
 fx.Burst=emitter(fx.Anchor,'Burst',{Lifetime=NumberRange.new(.6,1.4),Speed=NumberRange.new(30,70),Drag=2.5,Size=NumberSequence.new({NumberSequenceKeypoint.new(0,2.2),NumberSequenceKeypoint.new(1,0)}),Texture=SPARKLE})
 fx.Dust=emitter(fx.Anchor,'Dust',{Lifetime=NumberRange.new(1,2),Speed=NumberRange.new(4,10),Drag=1.5,Light=0,Influence=1,Texture=SMOKE,
  Size=NumberSequence.new(1.2,4),Transparency=NumberSequence.new(.35,1),Color=ColorSequence.new(Color3.fromRGB(150,146,140)),Acceleration=V3(0,2,0)})
 fx.Rings={}
 for i=1,2 do
  local r=Instance.new('CylinderHandleAdornment');r.Name='Shockwave'..i;r.Adornee=fx.Anchor;r.CFrame=ANG(math.pi/2,0,0)
  r.Radius=1;r.InnerRadius=.5;r.Height=.6;r.Visible=false;r.AlwaysOnTop=false;r.Parent=fx.Anchor;fx.Rings[i]=r
 end
 local cc=Instance.new('ColorCorrectionEffect');cc.Name='NuclearMutationGrade';cc.Enabled=false;cc.Parent=Lighting;fx.CC=cc
 local blur=Instance.new('BlurEffect');blur.Name='NuclearMutationBlur';blur.Size=0;blur.Enabled=false;blur.Parent=Lighting;fx.Blur=blur
 local gui=Instance.new('ScreenGui');gui.Name='NuclearMutationGui';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=92;gui.Enabled=false
 gui:SetAttribute('NoTranslate',true)
 fx.Gui=gui
 fx.Flash=frame2D(gui,'Flash',UDim2.fromScale(0,0),UDim2.fromScale(1,1),WHITE,{Transparency=1,Z=20})
 fx.Flash.Active=false
 fx.BarTop=frame2D(gui,'LetterboxTop',UDim2.fromScale(0,0),UDim2.fromScale(1,0),BLACK,{Z=8})
 fx.BarBottom=frame2D(gui,'LetterboxBottom',UDim2.fromScale(0,1),UDim2.fromScale(1,0),BLACK,{Z=8,Anchor=Vector2.new(0,1)})
 fx.Banner=text2D(gui,'Banner',{Position=UDim2.fromScale(.5,.2),Size=UDim2.fromScale(.8,.11),Z=12})
 fx.BannerScale=Instance.new('UIScale');fx.BannerScale.Parent=fx.Banner
 fx.Sub=text2D(gui,'Sub',{Position=UDim2.fromScale(.5,.29),Size=UDim2.fromScale(.6,.045),Z=12,Stroke=.3})
 fx.Ticker=text2D(gui,'Reel',{Anchor=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-96),Size=UDim2.fromOffset(460,64),Z=12})
 fx.TickerScale=Instance.new('UIScale');fx.TickerScale.Parent=fx.Ticker
 fx.Center=text2D(gui,'Center',{Position=UDim2.fromScale(.5,.45),Size=UDim2.fromScale(.86,.14),Z=14,Stroke=.2})
 fx.Hint=text2D(gui,'SkipHint',{Anchor=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-28),Size=UDim2.fromOffset(320,26),Z=12,Stroke=.6})
 fx.Hint.TextTransparency=.35
 fx.Layer=frame2D(gui,'Layer',UDim2.fromScale(0,0),UDim2.fromScale(1,1),BLACK,{Transparency=1,Z=15})
 gui.Parent=player:WaitForChild('PlayerGui')
 return fx
end
local function resetPool()
 if not fx then return end
 fx.Beam.Transparency=1;fx.BeamCore.Transparency=1;fx.BeamLight.Brightness=0
 for _,r in fx.Rings do r.Visible=false end
 fx.Sparks:Clear();fx.Burst:Clear();fx.Dust:Clear()
 fx.CC.Enabled=false;fx.CC.Brightness=0;fx.CC.Contrast=0;fx.CC.Saturation=0;fx.CC.TintColor=WHITE
 fx.Blur.Enabled=false;fx.Blur.Size=0
 fx.Gui.Enabled=false;fx.Flash.BackgroundTransparency=1
 fx.Banner.Text='';fx.Sub.Text='';fx.Ticker.Text='';fx.Center.Text='';fx.Hint.Text=''
 fx.BarTop.Size=UDim2.fromScale(1,0);fx.BarBottom.Size=UDim2.fromScale(1,0)
 for _,c in fx.Layer:GetChildren()do c:Destroy()end
 fx.Layer.BackgroundTransparency=1
end

-- 2D and world helpers shared by the shows
local function flash2D(color,from,dur)
 local f=pool()
 f.Flash.BackgroundColor3=color;f.Flash.BackgroundTransparency=from or .1
 TweenService:Create(f.Flash,TweenInfo.new(dur or .45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
end
local function banner(text,color,sub,calm)
 local f=pool()
 f.Banner.Text=text;f.Banner.TextColor3=color;f.Sub.Text=sub or'';f.Sub.TextColor3=color:Lerp(WHITE,.55)
 f.BannerScale.Scale=calm and 1 or 1.6
 if not calm then TweenService:Create(f.BannerScale,TweenInfo.new(.35,Enum.EasingStyle.Back),{Scale=1}):Play()end
end
local function grade(props,dur)
 local f=pool()
 f.CC.Enabled=true
 TweenService:Create(f.CC,TweenInfo.new(dur or .4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props):Play()
end
local function shock(pos,color,to,dur,both)
 local f=pool()
 f.Anchor.CFrame=CF(pos)
 for i,r in f.Rings do
  if i==1 or both then
   r.Color3=color;r.Radius=4;r.InnerRadius=3;r.Height=.8;r.Transparency=0;r.Visible=true
   local goal=to*(i==1 and 1 or .6)
   TweenService:Create(r,TweenInfo.new(dur or .8,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Radius=goal,InnerRadius=goal-3,Transparency=1}):Play()
  end
 end
end
local function sparksAt(pos,color,n,big)
 local f=pool()
 f.Anchor.CFrame=CF(pos)
 local e=big and f.Burst or f.Sparks
 e.Color=ColorSequence.new(WHITE,color);e:Emit(n)
end
local function dustAt(pos,n)
 local f=pool()
 f.Anchor.CFrame=CF(pos);f.Dust:Emit(n)
end
-- The sky beam from the crown (Cylinder: X is the axis).
local function setBeam(color,width,height,tr)
 local f=pool()
 if tr>=1 or height<=0.5 or width<=0.05 then f.Beam.Transparency=1;f.BeamCore.Transparency=1;f.BeamLight.Brightness=0;return end
 local cf=CF(CROWN+V3(0,height/2-4,0))*ANG(0,0,math.pi/2)
 f.Beam.Size=V3(height,width,width);f.Beam.CFrame=cf;f.Beam.Color=color;f.Beam.Transparency=tr
 f.BeamCore.Size=V3(height+.2,width*.38,width*.38);f.BeamCore.CFrame=cf;f.BeamCore.Color=color:Lerp(WHITE,.7);f.BeamCore.Transparency=math.min(1,tr*.6)
 f.BeamLight.Color=color;f.BeamLight.Brightness=4*(1-tr)
end

------------------------------------------------------------------------------------------------
-- The living tower: console screens, keys, lamps, the emblem, the pad (idle, cinematic, public show)
------------------------------------------------------------------------------------------------
local DIM=Color3.fromRGB(16,24,30)
local function hsv(h,s,v)return Color3.fromHSV(h%1,s,math.clamp(v,0,1))end
local function touchShow(k)
 for _,e in k.Keys do touch(e.P,'Color')end
 for _,e in k.WingLamps do touch(e.P,'Color')end
 for _,e in k.Bars do touch(e.F,'Size','BackgroundColor3')end
 for _,e in k.Helix do touch(e.A,'Position');touch(e.B,'Position')end
 for _,e in k.Needles do touch(e.P,'CFrame')end
 for _,p in k.Ring do touch(p,'Color','Transparency')end
 for _,p in k.Paw do touch(p,'Color','Transparency')end
 for _,p in k.Rim do touch(p,'Color','Transparency')end
 for _,p in k.PadLights do touch(p,'Color','Transparency')end
 for _,p in k.PadPaw do touch(p,'Color','Transparency')end
 touch(k.Led,'Color');touch(k.Start,'Color');touch(k.MeterFill,'Size','BackgroundColor3');touch(k.MeterValue,'Text')
 touch(k.Pool,'Color','Transparency');touch(k.Core,'Color','Transparency');touch(k.CoreLight,'Color','Brightness')
 touch(k.DoorText.Warning,'TextColor3','TextTransparency')
end
-- level 0..1: how wild the console is; color: the colour it flashes (reel / result) or nil.
local function consoleShow(k,t,calm,level,color)
 local s=calm and .3 or 1
 local fast=1+level*4
 for _,e in k.Keys do
  if e.P.Parent then
   local v=calm and .9 or .45+.55*math.max(0,math.sin(t*e.F*fast+e.Phase))
   local c=DIM:Lerp(e.Base,v)
   if color and level>0 then c=c:Lerp(color,level*(math.sin(t*16+e.Phase)>0 and .8 or .25))end
   e.P.Color=c
  end
 end
 for _,e in k.WingLamps do
  if e.P.Parent then
   local on=calm or((t*(1+level*5)+e.Phase)%1)<.5
   e.P.Color=on and(color and level>.4 and color or e.Base)or DIM
  end
 end
 if k.Led and k.Led.Parent then k.Led.Color=color and level>0 and color or hsv(.33+math.sin(t*.4*s)*.04,.7,.7+.3*math.sin(t*2*fast))end
 if k.Start and k.Start.Parent then k.Start.Color=Color3.fromRGB(255,40,40):Lerp(WHITE,calm and 0 or math.max(0,math.sin(t*3*fast))*.35)end
 for _,e in k.Bars do
  if e.F.Parent then
   local h=calm and .5 or math.clamp(.15+.9*math.abs(math.noise(t*(1.6+level*3),e.Seed))+level*.3,.06,1)
   e.F.Size=UDim2.fromScale(1/16-.01,h);e.F.Position=UDim2.fromScale((e.I-1)/16+.005,1-h)
   e.F.BackgroundColor3=color and level>.3 and color:Lerp(WHITE,e.I/40)or hsv(.33-e.I/16*.33*h,.8,1)
  end
 end
 for _,e in k.Helix do
  if e.A.Parent then
   local a=t*(1.4+level*5)*s+e.I*.62
   e.A.Position=UDim2.fromScale((e.I-1)/10,.45+.33*math.sin(a))
   e.B.Position=UDim2.fromScale((e.I-1)/10,.45-.33*math.sin(a))
  end
 end
 if k.MeterFill and k.MeterFill.Parent then
  local v=calm and .3 or math.clamp(.25+.15*math.noise(t*.8,3.3)+level*.75,0,1)
  k.MeterFill.Size=UDim2.fromScale(v,1)
  k.MeterFill.BackgroundColor3=v>.75 and Color3.fromRGB(255,60,60)or v>.5 and Color3.fromRGB(255,200,40)or L.Toxic
  if k.MeterValue then k.MeterValue.Text=string.format('%.1f Sv',v*12)end
 end
 for _,e in k.Needles do
  if e.P.Parent and typeof(e.Base)=='CFrame'then
   local a=calm and 0 or(-40+80*math.clamp(.3+level*.7+.2*math.noise(t*(1+level*4),e.I*3.1),0,1))
   e.P.CFrame=e.Base*ANG(0,math.rad(a),0)*CF(0,0,.2)
  end
 end
end
-- The emblem ring, the paw, the crown rim, the pool and the core glow in `color` (pulse 0..1 = brighter).
local function towerGlow(k,color,pulse)
 local tr=math.clamp(.35-.35*pulse,0,1)
 for _,p in k.Ring do if p.Parent then p.Color=color;p.Transparency=tr*.6 end end
 for _,p in k.Paw do if p.Parent then p.Color=color:Lerp(WHITE,.15*pulse);p.Transparency=0 end end
 for _,p in k.Rim do if p.Parent then p.Color=color;p.Transparency=tr*.5 end end
 if k.Pool and k.Pool.Parent then k.Pool.Color=color:Lerp(BLACK,.15);k.Pool.Transparency=.1 end
 if k.Core and k.Core.Parent then k.Core.Color=color;k.Core.Transparency=.55-.35*pulse end
 if k.CoreLight and k.CoreLight.Parent then k.CoreLight.Color=color;k.CoreLight.Brightness=1.5+4*pulse end
end
-- Idle: the pad lights chase, the emblem breathes, the WARNING sign glows.
local function idleTower(k,t,calm)
 local breathe=calm and .5 or .5+.5*math.sin(t*1.3)
 towerGlow(k,L.Toxic,breathe*.6)
 for i,p in k.PadLights do if p.Parent then p.Transparency=calm and 0 or(((t*2+i/4)%1)<.5 and 0 or .7)end end
 for _,p in k.PadPaw do if p.Parent then p.Transparency=.2-.2*breathe end end
 local w=k.DoorText.Warning
 if w and w.Parent then w.TextTransparency=calm and 0 or .25-.25*math.sin(t*2.4)end
end
local function beacons(k,on,t,color)
 for i,b in k.PortalBeacons do
  if b.P.Parent then
   set(b.P,'Color',color or Color3.fromRGB(230,40,40))
   set(b.P,'Transparency',on and((math.floor(t*6+i)%2==0)and 0 or .35)or .15)
   if b.L then
    set(b.L,'Brightness',on and 7 or 0);set(b.L,'Color',color or Color3.fromRGB(230,40,40))
    -- the beam sweeps round
    touch(b.P,'CFrame')
    local s=saved[b.P]and saved[b.P].CFrame or b.P.CFrame
    b.P.CFrame=on and CF(s.Position)*ANG(0,t*7+i*math.pi,0)*ANG(math.rad(-20),0,0)or s
   end
  end
 end
 for i,b in k.ConsoleBeacons do
  if b.P.Parent then
   set(b.P,'Transparency',on and((math.floor(t*5+i)%2==0)and 0 or .5)or .15)
   if b.L then set(b.L,'Brightness',on and 4 or 0)end
  end
 end
end

------------------------------------------------------------------------------------------------
-- The dog clone (MenuModels, the same source as the window previews)
------------------------------------------------------------------------------------------------
local shown=nil -- {Model, Anim, Variant, Height, Size, Clip}
local function makeDog(d)
 local models=RS:FindFirstChild('MenuModels');local def=d and Definitions[d.DogId]
 local source=models and def and models:FindFirstChild(def.VisualAsset or d.DogId)or(models and d and models:FindFirstChild(d.DogId))
 if not source then return nil end
 local m=source:Clone()
 for _,o in m:GetDescendants()do
  if o:IsA('LuaSourceContainer')or o:IsA('ProximityPrompt')or o:IsA('BillboardGui')or o:IsA('SurfaceGui')or o:IsA('Sound')or o:IsA('ParticleEmitter')or o:IsA('Highlight')then o:Destroy()end
 end
 local prepared=Rig.Prepare(m,L.DogLimits)
 if not prepared then m:Destroy();return nil end
 m.Name='TowerDog';m.Parent=pool().Folder
 local anim=nil
 local ok,p2=pcall(Animation.new,m,d.DogId)
 if ok and p2 then anim=p2 end
 local dog={Model=m,Anim=anim,DogId=d.DogId,Variant=d.Variant or'Normal',Height=prepared.Size.Y,Size=prepared.Size,Clip=nil}
 return dog
end
local function clip(dog,role,speed)
 if not(dog and dog.Anim)or dog.Clip==role then return end
 local name=Animation.ResolveName(dog.DogId,role)or(role~='Idle'and Animation.ResolveName(dog.DogId,'Idle'))
 if name then pcall(function()dog.Anim:Play(name,{FadeTime=.2,Looped=true})end)end
 dog.Model:SetAttribute('LocomotionSpeed',speed or 0)
 dog.Clip=role
end
local function dogVisible(dog,alpha)
 for _,o in dog.Model:GetDescendants()do if o:IsA('BasePart')then o.LocalTransparencyModifier=1-alpha end end
end
local function placeDog(dog,ground,rot)
 if dog and dog.Model.Parent then Rig.Place(dog.Model,ground,rot)end
end
-- Points on the dog for the close-ups (rot: the dog's rotation; it faces rot.LookVector).
local function dogPoint(dog,ground,rot,part)
 local s=dog.Size
 local o
 if part=='Head'then o=V3(0,s.Y*.74,-s.Z*.36)
 elseif part=='Tail'then o=V3(0,s.Y*.55,s.Z*.46)
 elseif part=='Paws'then o=V3(0,s.Y*.12,-s.Z*.22)
 else o=V3(0,s.Y*.5,0)end
 return ground+rot:VectorToWorldSpace(o)
end
local function dropDog()
 if not shown then return end
 if shown.Anim then pcall(function()shown.Anim:Destroy()end)end
 if shown.Model then Glow.Remove(shown.Model);shown.Model:Destroy()end
 shown=nil
end

------------------------------------------------------------------------------------------------
-- Scene helpers: a folder of temporary parts and simple ballistic bodies
------------------------------------------------------------------------------------------------
local function newScene()
 local folder=Instance.new('Folder');folder.Name='Scene';folder.Parent=pool().Folder
 return {Folder=folder,Bodies={},Items={},Loops={}}
end
local function endScene(sc)
 if not sc then return end
 for _,h in sc.Loops do pcall(h.Stop,.4)end
 if sc.Folder then sc.Folder:Destroy()end
 table.clear(sc.Bodies)
end
local GRAVITY=70
local function launch(sc,p,vel,spin,ground,onLand)
 local b={P=p,V=vel,Spin=spin or Vector3.zero,Rot=p.CFrame-p.CFrame.Position,Ground=ground or G,Land=onLand,Rest=false}
 table.insert(sc.Bodies,b)
 return b
end
local function stepBodies(sc,dt)
 for _,b in sc.Bodies do
  if not b.Rest and b.P.Parent then
   b.V+=V3(0,-(b.Gravity or GRAVITY),0)*dt
   local pos=b.P.CFrame.Position+b.V*dt
   b.Rot=b.Rot*ANG(b.Spin.X*dt,b.Spin.Y*dt,b.Spin.Z*dt)
   if pos.Y<=b.Ground then
    pos=V3(pos.X,b.Ground,pos.Z);b.Rest=true
    if b.Land then b.Land(b,pos)else b.P.CFrame=CF(pos)*b.Rot end
   else
    b.P.CFrame=CF(pos)*b.Rot
   end
  end
 end
end
-- A flat splash that spreads and fades (drops, gold, cola).
local function puddle(sc,pos,color,size,life)
 local p=newPart(sc.Folder,'Puddle',V3(.05,.2,.2),CF(pos+V3(0,.04,0))*ANG(0,0,math.pi/2),color,Enum.Material.Neon,.15,Enum.PartType.Cylinder)
 TweenService:Create(p,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=V3(.05,size,size)}):Play()
 task.delay(life or 2,function()if p.Parent then TweenService:Create(p,TweenInfo.new(.8),{Transparency=1}):Play()end end)
 return p
end
-- A zigzag line of neon segments from a to b (lightning, cracks).
local function zigzag(parent,name,a,b,n,jitter,width,color,tr)
 local list={}
 local prev=a
 local dir=b-a
 local side=dir:Cross(V3(0,1,0));if side.Magnitude<1e-3 then side=V3(1,0,0)end;side=side.Unit
 local up=side:Cross(dir.Unit).Unit
 for i=1,n do
  local q=a+dir*(i/n)
  if i<n then q+=side*(math.random()-.5)*2*jitter+up*(math.random()-.5)*2*jitter*.6 end
  local d=q-prev
  if d.Magnitude>1e-3 then
   table.insert(list,newPart(parent,name,V3(width,width,d.Magnitude+width*.5),CFrame.lookAt((prev+q)/2,q),color,Enum.Material.Neon,tr or 0))
  end
  prev=q
 end
 return list
end
-- Positions on the shell: angle a (0 = +X, pi = west), height y, outward offset extra.
local function shellPoint(a,y,extra)return L.Shell(a,y,extra or 0)end

------------------------------------------------------------------------------------------------
-- The variant sequences. Each: Start(ctx), Update(ctx, lt, dt) -> eye, focus, fov, shake; Stop(ctx).
-- ctx: K (rig), F (pool), Sc (scene), Calm, Low, Color, Owner, Public (another player's show: no camera,
-- no 2D, no silence), Siren/Rumble loops.
------------------------------------------------------------------------------------------------
local S=L.Shots
local SCENES={}
local function ease(x)x=math.clamp(x,0,1);return x*x*x*(x*(x*6-15)+10)end -- smootherstep
-- A shot from NuclearLayout.Shots moving from Eye/Focus/Fov to Eye1/Focus1/Fov1 over dur (eased).
local function shotMove(s,lt,dur)
 local x=ease(lt/math.max(dur,1e-3))
 local f=s.Focus or CENTER
 return s.Eye:Lerp(s.Eye1 or s.Eye,x),f:Lerp(s.Focus1 or f,x),lerp(s.Fov,s.Fov1 or s.Fov,x)
end
-- The tower, its crown and the sky beam (from the north-west, looking south-east).
local function wideShot(lt,dur)return shotMove(S.Hero,lt,dur)end
-- Over the owner's right shoulder (ctx.Owner faces the pad): back / side / up in the owner's frame.
local function overShoulder(ctx,back,side,up)
 local o=ctx.Owner;local f=flat(L.Pad.Center-o).Unit;local r=f:Cross(V3(0,1,0))
 return o-f*back+r*side+V3(0,up,0)
end
local function nearOwner(ctx,lt,look)
 local f=flat(L.Pad.Center-ctx.Owner).Unit
 return overShoulder(ctx,5.2,3.0,4.2),look or(ctx.Owner+f*16+f:Cross(V3(0,1,0))*4+V3(0,9,0)),64
end

-- NORMAL: MUTATION FAILED.
SCENES.Normal={
 Start=function(ctx)
  if ctx.Siren then ctx.Siren.Stop(1.2,true)end
  if not ctx.Public then
   P.Cue('Fail',ctx.K.Main)
   banner(upper(T('MUTATION FAILED')),Color3.fromRGB(255,80,80),upper(T('NO MUTATION')),ctx.Calm)
   -- a flat, grey mood (resetPool turns it off at the exit)
   grade({Saturation=-.4,Brightness=-.04,Contrast=.08},.6)
  end
  if ctx.K.Steam then touch(ctx.K.Steam,'Color','Rate');ctx.K.Steam.Color=ColorSequence.new(Color3.fromRGB(150,150,150),Color3.fromRGB(90,90,90));ctx.K.Steam:Emit(ctx.Low and 6 or 16)end
 end,
 Update=function(ctx,lt,dt)
  local k=ctx.K
  -- the beam sputters and dies
  local alive=1-span(lt,.4,2.2)
  local flick=(math.random()<.35)and .5 or 0
  setBeam(Color3.fromRGB(150,160,150),10*alive,700*alive,math.clamp(.25+flick+(1-alive)*.75,0,1))
  towerGlow(k,Color3.fromRGB(120,130,120):Lerp(Color3.fromRGB(255,60,60),(math.floor(lt*3)%2==0)and .7 or 0),.2)
  if k.MainText.Reel then
   set(k.MainText.Reel,'Text',upper(T('MUTATION FAILED')));set(k.MainText.Reel,'TextColor3',(math.floor(lt*3)%2==0)and Color3.fromRGB(255,70,70)or Color3.fromRGB(120,20,20))
   set(k.MainText.Status,'Text',upper(T('NO MUTATION')))
  end
  if lt<2.4 then
   -- the beam sputters and dies over the tower
   local eye,focus,fov=wideShot(lt,2.4)
   return eye,focus,fov,.06
  end
  -- a close look at the console screen: MUTATION FAILED
  local scr=k.Main and k.Main.CFrame.Position or S.Screen.Focus
  return S.Screen.Eye:Lerp(scr,.2*span(lt,2.4,5)),scr,S.Screen.Fov,.03
 end,
}

-- GOLDEN: coins burst from the crown, gold streams run down the shell, coins rain round the owner.
SCENES.Golden={
 Start=function(ctx)
  local sc=ctx.Sc
  local gold=L.Colors.Golden
  if ctx.Siren then ctx.Siren.Stop(.6)end
  if not ctx.Public then
   flash2D(Color3.fromRGB(255,230,140),ctx.Calm and .6 or .05,.6)
   banner(upper(T('GOLDEN MUTATION')),gold,nil,ctx.Calm)
   grade({TintColor=Color3.fromRGB(255,236,190),Brightness=.05,Saturation=.15},.6)
   P.Cue('Rare',nil);P.Cue('Coins',nil)
  end
  shock(CROWN,gold,90,1,true)
  sparksAt(CROWN+V3(0,4,0),gold,ctx.Low and 30 or 90,true)
  -- the gold streams (segments revealed from the crown down)
  sc.Streams={}
  local n=ctx.Low and 6 or 14
  for i=1,n do
   local a=(i-.5)/n*math.pi*2+.12
   local delta=math.abs(((a-L.West+math.pi)%(math.pi*2))-math.pi)
   if delta>.42 then
    local segs={}
    local w=1.1+math.random()*1.1
    local y=HEIGHT-1
    while y>8 do
     local y2=math.max(8,y-6)
     local p0,p1=shellPoint(a,y,.35),shellPoint(a,y2,.35)
     local wob=V3(-math.sin(a),0,math.cos(a))*(math.random()-.5)*.8
     local seg=newPart(sc.Folder,'GoldStream',V3(w,.3,(p1-p0).Magnitude+.3),CFrame.lookAt((p0+p1)/2+wob,p1+wob),Color3.fromRGB(255,196,40),Enum.Material.Neon,1)
     table.insert(segs,{P=seg,Y=y})
     y=y2
    end
    table.insert(sc.Streams,segs)
   end
  end
  sc.Coins=0;sc.Rain=0;sc.NextCoin=0
 end,
 Update=function(ctx,lt,dt)
  local sc=ctx.Sc
  local gold=L.Colors.Golden
  local k=ctx.K
  stepBodies(sc,dt)
  setBeam(gold,14+4*math.sin(lt*9),900,.15)
  towerGlow(k,gold,.6+.4*math.sin(lt*6))
  -- streams flow down
  local head=HEIGHT-(lt-.5)/3*(HEIGHT-8)
  for _,segs in sc.Streams do for _,s in segs do s.P.Transparency=s.Y>=head and .05 or 1 end end
  -- coins from the crown
  local maxCoins=ctx.Low and 24 or(ctx.Public and 30 or 70)
  if lt>.15 and lt<3.2 and sc.Coins<maxCoins and lt>=sc.NextCoin then
   sc.NextCoin=lt+.035
   for _=1,2 do
    if sc.Coins<maxCoins then
     sc.Coins+=1
     local a=math.random()*math.pi*2
     local r=12+math.random()*5
     local start=CROWN+V3(math.cos(a)*r,2,math.sin(a)*r)
     local coin=newPart(sc.Folder,'Coin',V3(.35,2.4,2.4),CF(start),Color3.fromRGB(255,200,40),Enum.Material.Metal,0,Enum.PartType.Cylinder)
     coin.Reflectance=.35
     local out=V3(math.cos(a),0,math.sin(a))
     launch(sc,coin,out*(16+math.random()*26)+V3(0,26+math.random()*24,0),V3(math.random()*8,math.random()*8,math.random()*8),G+.2,function(b,pos)
      b.P.CFrame=CF(pos+V3(0,.0,0))*ANG(0,math.random()*6.28,math.pi/2)
     end)
    end
   end
  end
  -- coins rain round the owner
  if not ctx.Public and lt>3.0 and lt<6.4 and sc.Rain<(ctx.Low and 10 or 28)and lt>=sc.NextCoin then
   sc.NextCoin=lt+.09;sc.Rain+=1
   local o=ctx.Owner
   local p=o+V3((math.random()-.5)*26,46+math.random()*20,(math.random()-.5)*26)
   local coin=newPart(sc.Folder,'Coin',V3(.3,2,2),CF(p),Color3.fromRGB(255,206,60),Enum.Material.Metal,0,Enum.PartType.Cylinder)
   coin.Reflectance=.35
   launch(sc,coin,V3(0,-12,0),V3(math.random()*10,math.random()*10,0),G+.2,function(b,pos)
    b.P.CFrame=CF(pos)*ANG(0,math.random()*6.28,math.pi/2)
    P.Cue('Coins',nil)
   end)
  end
  if ctx.Public then return nil end
  if lt<3.4 then
   local eye,focus,fov=wideShot(lt,3.4)
   return eye,focus,fov,.12
  end
  local eye,focus,fov=nearOwner(ctx,lt)
  return eye,focus+V3(0,lerp(0,10,span(lt,3.4,7)),0),fov,.06
 end,
}

-- SHINY: flashes, the tower cracks, light breaks out of the cracks and round the door.
SCENES.Shiny={
 Start=function(ctx)
  local sc=ctx.Sc
  if ctx.Siren then ctx.Siren.Stop(.6)end
  if not ctx.Public then
   flash2D(WHITE,ctx.Calm and .6 or 0,.7)
   banner(upper(T('SHINY MUTATION')),Color3.fromRGB(190,240,255),nil,ctx.Calm)
   grade({Brightness=.08,Contrast=.1,Saturation=-.1},.5)
   P.Cue('Flash',nil);P.Cue('Rare',nil)
  end
  -- cracks on the side the cameras see (south-west) and their light beams
  sc.Cracks={}
  local n=ctx.Low and 5 or 10
  for i=1,n do
   local a=1.55+(i-.5)/n*1.7+(math.random()-.5)*.15
   local y=18+((i*37)%80)
   local start=shellPoint(a,y,.2)
   local segs={}
   local prev=start
   local frameCF=L.ShellFrame(a,y,.2)
   for s=1,7 do
    local q=frameCF*CF((math.random()-.5)*2.4*s*.6,(math.random()-.5)*1.4-s*1.4,0)
    local qp=q.Position
    -- keep on the surface
    local qa=math.atan2(qp.Z-CENTER.Z,qp.X-CENTER.X)
    qp=shellPoint(qa,qp.Y-CENTER.Y,.2)
    local d=qp-prev
    if d.Magnitude>.2 then
     table.insert(segs,newPart(sc.Folder,'Crack',V3(.35,.25,d.Magnitude+.3),CFrame.lookAt((prev+qp)/2,qp),Color3.fromRGB(235,250,255),Enum.Material.Neon,1))
    end
    prev=qp
   end
   local out=V3(math.cos(a),0,math.sin(a))
   local rays={}
   for r=1,(ctx.Low and 1 or 3)do
    local dir=(out+V3((math.random()-.5)*.7,(math.random()-.2)*.6,(math.random()-.5)*.7)).Unit
    local len=24+math.random()*26
    local mid=(start+prev)/2
    local ray=newPart(sc.Folder,'LightRay',V3(len,1.4,1.4),CFrame.lookAt(mid+dir*len/2,mid+dir*len)*ANG(0,math.pi/2,0),Color3.fromRGB(225,245,255),Enum.Material.Neon,1,Enum.PartType.Cylinder)
    table.insert(rays,{P=ray,Len=len,Dir=dir,Mid=mid})
   end
   local glow=Instance.new('PointLight');glow.Color=Color3.fromRGB(220,240,255);glow.Range=26;glow.Brightness=0;glow.Shadows=false
   glow.Parent=segs[1]or sc.Folder
   table.insert(sc.Cracks,{Segs=segs,Rays=rays,At=.25+i*.26,Light=glow,Done=false,Pos=start})
  end
  -- light from the door edges
  local D=L.Door;local x=L.Portal.Front-.3;local z=CENTER.Z
  sc.Seams={}
  local function seam(size,cf)table.insert(sc.Seams,newPart(sc.Folder,'DoorSeam',size,cf,Color3.fromRGB(230,248,255),Enum.Material.Neon,1))end
  seam(V3(.3,D.Height,.35),CF(x,G+D.Height/2,z-D.Width/2-.1))
  seam(V3(.3,D.Height,.35),CF(x,G+D.Height/2,z+D.Width/2+.1))
  seam(V3(.3,.35,D.Width+.4),CF(x,G+D.Height+.1,z))
  sc.Fans={}
  for i=1,(ctx.Low and 4 or 10)do
   local edge=i%3
   local base=edge==0 and V3(x,G+D.Height,z+(math.random()-.5)*D.Width)or V3(x,G+math.random()*D.Height,z+(edge==1 and -1 or 1)*D.Width/2)
   local dir=(V3(-1,(math.random()-.3)*.5,(edge==1 and -1 or edge==2 and 1 or 0)*.5+(math.random()-.5)*.4)).Unit
   local len=10+math.random()*10
   table.insert(sc.Fans,newPart(sc.Folder,'DoorRay',V3(.15,3.5,len),CFrame.lookAt(base+dir*len/2,base+dir*len),Color3.fromRGB(235,250,255),Enum.Material.Neon,1))
  end
  sc.DoorLight=Instance.new('PointLight');sc.DoorLight.Range=24;sc.DoorLight.Brightness=0;sc.DoorLight.Color=Color3.fromRGB(230,245,255);sc.DoorLight.Shadows=false
  sc.DoorLight.Parent=sc.Seams[1]
  sc.NextFlash=1.4
 end,
 Update=function(ctx,lt,dt)
  local sc=ctx.Sc
  local k=ctx.K
  local c=L.Colors.Shiny
  setBeam(c,12+3*math.sin(lt*14),900,.1)
  towerGlow(k,c,.5+.5*math.sin(lt*8))
  for _,cr in sc.Cracks do
   local x=lin(lt,cr.At,cr.At+.5)
   if x>0 and not cr.Done then
    cr.Done=true
    if not ctx.Public then P.Cue('Crack',nil)end
    sparksAt(cr.Pos,c,ctx.Low and 6 or 16)
    dustAt(cr.Pos,ctx.Low and 2 or 5)
   end
   local shown2=math.floor(x*#cr.Segs+.5)
   for i,s in cr.Segs do s.Transparency=i<=shown2 and 0 or 1 end
   local beam=span(lt,cr.At+.3,cr.At+.9)
   for _,r in cr.Rays do
    r.P.Transparency=1-beam*(.55+.25*math.sin(lt*20+r.Len))
   end
   cr.Light.Brightness=beam*3
  end
  local seams=span(lt,2.6,3.2)
  for _,s in sc.Seams do s.Transparency=1-seams*(.85+.15*math.sin(lt*30))end
  for i,f in sc.Fans do f.Transparency=1-seams*(.35+.25*math.sin(lt*9+i))end
  sc.DoorLight.Brightness=seams*(5+3*math.sin(lt*12))
  if not ctx.Public and not ctx.Calm and lt>=sc.NextFlash and lt<6.5 then
   sc.NextFlash=lt+.9+math.random()*.5
   flash2D(WHITE,.35,.35);P.Cue('Flash',nil)
  end
  if ctx.Public then return nil end
  if lt<3 then
   local eye,focus,fov=wideShot(lt,3)
   return eye,focus,fov,.12
  end
  local eye,focus,fov=shotMove(S.DoorLow,lt-3,4)
  return eye,focus,fov,.18
 end,
}

-- CORRUPTED: silence, a huge red beam, the eruption, drops round the owner.
local ducked={}
local function duck(on)
 if on then
  for _,g in SoundService:GetDescendants()do
   if g:IsA('SoundGroup')and ducked[g]==nil then ducked[g]=g.Volume;g.Volume=0 end
  end
 else
  for g,v in pairs(ducked)do if g.Parent then g.Volume=v end end
  table.clear(ducked)
 end
end
SCENES.Corrupted={
 Start=function(ctx)
  local sc=ctx.Sc
  if ctx.Siren then ctx.Siren.Stop(.05)end
  if ctx.Rumble then ctx.Rumble.Stop(.05)end
  if not ctx.Public then
   duck(true);sc.Ducked=true
   grade({Saturation=-.75,Brightness=-.12,Contrast=.15},.25)
  end
  setBeam(WHITE,1,1,1)
  sc.Boom=false;sc.Drops=0;sc.Rain=0;sc.Next=0
  local red=L.Colors.Corrupted
  -- the cola column over the crown (grows after the boom)
  sc.Column=newPart(sc.Folder,'Eruption',V3(1,14,14),CF(CROWN)*ANG(0,0,math.pi/2),Color3.fromRGB(120,10,24),Enum.Material.Neon,1,Enum.PartType.Cylinder)
  sc.Foam=newPart(sc.Folder,'Foam',V3(30,4,30),CF(CROWN+V3(0,2,0)),WHITE,Enum.Material.SmoothPlastic,1)
  sc.FoamFX=emitter(sc.Foam,'FoamFX',{Texture=SMOKE,Rate=0,Lifetime=NumberRange.new(1.4,2.6),Speed=NumberRange.new(40,70),Spread=Vector2.new(25,25),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,6),NumberSequenceKeypoint.new(1,18)}),Transparency=NumberSequence.new(.1,1),
   Color=ColorSequence.new(Color3.fromRGB(255,140,150),Color3.fromRGB(110,10,20)),Acceleration=V3(0,-40,0),Light=.2,Influence=.6,
   Shape=Enum.ParticleEmitterShape.Disc,Direction=Enum.NormalId.Top})
  sc.Red=red
 end,
 Update=function(ctx,lt,dt)
  local sc=ctx.Sc
  local k=ctx.K
  local red=sc.Red
  stepBodies(sc,dt)
  local boomAt=ctx.Public and .6 or 2
  if lt<boomAt then
   towerGlow(k,Color3.fromRGB(40,10,14),0)
   if ctx.Public then return nil end
   local eye,focus,fov=wideShot(lt,2)
   return eye,focus,fov,0
  end
  if not sc.Boom then
   sc.Boom=true
   if sc.Ducked then duck(false);sc.Ducked=false end
   if not ctx.Public then
    grade({Saturation=.2,Brightness=0,Contrast=.2,TintColor=Color3.fromRGB(255,200,200)},.3)
    flash2D(Color3.fromRGB(255,40,40),.05,.6)
    banner(upper(T('CORRUPTED MUTATION')),red,nil,ctx.Calm)
    P.Cue('Boom',nil);P.Cue('Rare',nil)
   end
   shock(CROWN,red,140,1.2,true)
   sparksAt(CROWN+V3(0,6,0),red,ctx.Low and 30 or 100,true)
   sc.FoamFX.Enabled=not ctx.Low;sc.FoamFX.Rate=ctx.Public and 10 or 26
   if not ctx.Public then P.Cue('Eruption',nil)end
  end
  local e=lt-boomAt
  -- the huge red beam
  local grow=span(e,0,.35)
  setBeam(red,lerp(10,36,grow)+3*math.sin(lt*17),1200*grow,.05)
  towerGlow(k,red,.6+.4*math.sin(lt*11))
  -- the eruption column (rises, wobbles, falls back)
  local h=70*span(e,.4,1.1)*(1-.35*span(e,4,6))
  local w=14+3*math.sin(lt*7)
  sc.Column.Size=V3(math.max(1,h),w,w)
  sc.Column.CFrame=CF(CROWN+V3(math.sin(lt*3)*1.5,h/2,0))*ANG(0,0,math.pi/2)
  sc.Column.Transparency=h>1 and .1 or 1
  -- drops from the crown
  local maxDrops=ctx.Low and 14 or(ctx.Public and 16 or 40)
  if e>.5 and e<3.5 and sc.Drops<maxDrops and lt>=sc.Next then
   sc.Next=lt+.06;sc.Drops+=1
   local a=math.random()*math.pi*2
   local d=newPart(sc.Folder,'Drop',V3(1,1,1)*(1.4+math.random()*1.6),CF(CROWN+V3(math.cos(a)*6,h*.8+4,math.sin(a)*6)),Color3.fromRGB(190,20,40),Enum.Material.Neon,.05,Enum.PartType.Ball)
   launch(sc,d,V3(math.cos(a),0,math.sin(a))*(14+math.random()*30)+V3(0,20+math.random()*30,0),Vector3.zero,G+.3,function(b,pos)
    b.P:Destroy();puddle(sc,pos,Color3.fromRGB(150,10,30),3+math.random()*3,2.4)
   end)
  end
  -- drops round the owner
  if not ctx.Public and e>3 and sc.Rain<(ctx.Low and 10 or 26)and lt>=sc.Next then
   sc.Next=lt+.11;sc.Rain+=1
   local o=ctx.Owner
   local p=o+V3((math.random()-.5)*28,52+math.random()*16,(math.random()-.5)*28)
   if sc.Rain==6 then p=overShoulder(ctx,2.6,1.2,40)end -- one lands right by the camera
   local d=newPart(sc.Folder,'Drop',V3(1,1,1)*(1+math.random()*1.4),CF(p),Color3.fromRGB(200,24,44),Enum.Material.Neon,.05,Enum.PartType.Ball)
   launch(sc,d,V3(0,-18,0),Vector3.zero,G+.3,function(b,pos)
    b.P:Destroy();puddle(sc,pos,Color3.fromRGB(160,12,32),2.6+math.random()*2.4,2.6);P.Cue('Splat',nil)
    sparksAt(pos+V3(0,.5,0),Color3.fromRGB(200,24,44),ctx.Low and 3 or 8)
   end)
  end
  if ctx.Public then return nil end
  -- the boom: the hero shot (the crown in mid-frame) kicks; turning towards the crown would show the black
  -- box north of the plaza on wide phones
  if e<.6 then return S.Hero.Eye1,S.Hero.Focus1,S.Hero.Fov,1.1-1.5*e end
  if e<3.2 then
   local eye,_,fov=shotMove(S.Crown,e-.6,2.6)
   return eye,CROWN+V3(0,30*span(e,.6,3.2),0),fov,.4
  end
  local eye=overShoulder(ctx,5.4,3.0,3.2)
  return eye,ctx.Owner+flat(L.Pad.Center-ctx.Owner).Unit*6+V3(0,3.5+2*span(e,3.2,6),0),66,.1
 end,
 Stop=function(ctx)
  if ctx.Sc.Ducked then duck(false)end
 end,
}

-- GLITCHED: a Windows error over the tower, overflow, a 5 s blue screen that types "restart game".
local ITEMS={'🐶','🦴','🪙','⭐','💎','🐾','🍖','🎁'}
local function errorWindow(parent,title,line1,line2)
 local win=frame2D(parent,'Window',UDim2.fromScale(.5,.5),UDim2.fromScale(.8,.62),Color3.fromRGB(240,240,240),{Anchor=Vector2.new(.5,.5),Z=2})
 local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(0,84,227);stroke.Thickness=3;stroke.Parent=win
 local bar=frame2D(win,'TitleBar',UDim2.fromScale(0,0),UDim2.fromScale(1,.17),Color3.fromRGB(0,84,227),{Z=3})
 local grad=Instance.new('UIGradient');grad.Color=ColorSequence.new(Color3.fromRGB(0,70,215),Color3.fromRGB(70,150,255));grad.Parent=bar
 text2D(bar,'Title',{Anchor=Vector2.new(0,.5),Position=UDim2.fromScale(.03,.5),Size=UDim2.fromScale(.7,.7),Text=title,AlignX=Enum.TextXAlignment.Left,Z=4,Stroke=1})
 local x=frame2D(bar,'Close',UDim2.fromScale(.985,.5),UDim2.fromScale(.11,.78),Color3.fromRGB(232,17,35),{Anchor=Vector2.new(1,.5),Z=4})
 text2D(x,'X',{Text='✕',Size=UDim2.fromScale(1,1),Z=5,Stroke=1})
 local icon=frame2D(win,'Icon',UDim2.fromScale(.1,.42),UDim2.fromScale(.13,.22),Color3.fromRGB(232,17,35),{Anchor=Vector2.new(.5,.5),Z=3})
 local ar=Instance.new('UIAspectRatioConstraint');ar.Parent=icon
 local rc=Instance.new('UICorner');rc.CornerRadius=UDim.new(1,0);rc.Parent=icon
 text2D(icon,'Mark',{Text='✕',Size=UDim2.fromScale(.8,.8),Z=4,Stroke=1})
 text2D(win,'Message',{Anchor=Vector2.new(0,.5),Position=UDim2.fromScale(.2,.42),Size=UDim2.fromScale(.76,.3),Text=line1..'\n'..line2,
  Color=Color3.fromRGB(20,20,20),Stroke=1,AlignX=Enum.TextXAlignment.Left,Z=3})
 for i,name in{T('OK'),T('Cancel')}do
  local b=frame2D(win,'Button'..i,UDim2.fromScale(i==1 and .52 or .76,.86),UDim2.fromScale(.2,.14),Color3.fromRGB(225,225,225),{Anchor=Vector2.new(.5,.5),Z=3})
  local s=Instance.new('UIStroke');s.Color=i==1 and Color3.fromRGB(0,120,215)or Color3.fromRGB(160,160,160);s.Thickness=2;s.Parent=b
  text2D(b,'Text',{Text=name,Size=UDim2.fromScale(.9,.8),Color=Color3.fromRGB(20,20,20),Stroke=1,Z=4})
 end
 local tray=frame2D(win,'Tray',UDim2.fromScale(0,.17),UDim2.fromScale(1,.83),BLACK,{Transparency=1,Z=6})
 tray.ClipsDescendants=true
 return win,tray
end
SCENES.Glitched={
 Start=function(ctx)
  local sc=ctx.Sc
  if ctx.Siren then ctx.Siren.Stop(.3)end
  local anchor=newPart(sc.Folder,'ErrorAnchor',V3(.2,.2,.2),CF(CROWN+V3(0,44,0)),WHITE,nil,1)
  local bb=Instance.new('BillboardGui');bb.Name='ErrorWindow';bb.Adornee=anchor;bb.Size=UDim2.fromScale(76,46);bb.LightInfluence=0;bb.MaxDistance=5000
  bb.AlwaysOnTop=false;bb.ResetOnSpawn=false;bb:SetAttribute('NoTranslate',true);bb.Parent=sc.Folder
  sc.BB=bb;sc.Anchor=anchor
  sc.Windows={}
  local win,tray=errorWindow(bb,'DOGROTS.exe',T('DOGROTS.exe has stopped responding.'),T('Too many dogs in memory.'))
  sc.Main=win;sc.Tray=tray;sc.Items={};sc.Next=0;sc.NextWin=2.4;sc.Pile=0
  win.Size=UDim2.fromScale(.05,.05)
  TweenService:Create(win,TweenInfo.new(.25,Enum.EasingStyle.Back),{Size=UDim2.fromScale(.8,.62)}):Play()
  if not ctx.Public then P.Cue('ErrorBeep',nil)end
  setBeam(L.Colors.Glitched,8,900,.3)
 end,
 Update=function(ctx,lt,dt)
  local sc=ctx.Sc
  local k=ctx.K
  local cyan,mag=L.Colors.Glitched,Color3.fromRGB(255,60,220)
  local glitchC=(math.random()<.5)and cyan or mag
  towerGlow(k,glitchC,math.random())
  local beamOn=lt<10 and(math.random()<.8)
  setBeam(glitchC,8+math.random()*6,900,beamOn and .25 or 1)
  local over=ctx.Public and 3 or 4.8
  -- items fall into the window, faster and faster
  if lt<over and lt>=sc.Next and sc.Tray.Parent then
   sc.Next=lt+math.max(.025,.3-lt*.07)
   local item=text2D(sc.Tray,'Item',{Text=ITEMS[math.random(1,#ITEMS)],Anchor=Vector2.new(.5,1),Position=UDim2.fromScale(.05+math.random()*.9,-.1),
    Size=UDim2.fromScale(.09,.15),Z=7,Stroke=1})
   table.insert(sc.Items,{L=item,Y=-.1,V=0,Rest=false})
  end
  local pileTop=1-sc.Pile
  for _,it in sc.Items do
   if not it.Rest and it.L.Parent then
    it.V+=2.6*dt;it.Y+=it.V*dt
    if it.Y>=pileTop then it.Y=pileTop;it.Rest=true;sc.Pile=math.min(.95,sc.Pile+.006)end
    it.L.Position=UDim2.fromScale(it.L.Position.X.Scale,it.Y)
   end
  end
  -- the error trail: copies of the window cascade down
  if lt>=sc.NextWin and lt<over and #sc.Windows<(ctx.Low and 6 or 16)then
   sc.NextWin=lt+math.max(.08,.3-(lt-2.4)*.1)
   local n=#sc.Windows+1
   local copy=sc.Main:Clone()
   local tray2=copy:FindFirstChild('Tray');if tray2 then tray2:Destroy()end
   copy.Position=UDim2.fromScale(.5-n*.022,.5-n*.022);copy.ZIndex=1
   copy.Parent=sc.BB
   table.insert(sc.Windows,copy)
   if not ctx.Public then P.Cue('ErrorBeep',nil)end
  end
  -- jitter
  if sc.Main.Parent then
   local j=lt>2 and .012*(lt/over)or .002
   sc.Main.Position=UDim2.fromScale(.5+(math.random()-.5)*j,.5+(math.random()-.5)*j)
  end
  if ctx.Public then
   if lt>3.2 and sc.BB.Parent then sc.BB:Destroy()end
   return nil
  end
  local f=pool()
  -- overflow -> the blue screen (5 s) -> "restart game" -> gone
  if lt>=over and not sc.Overflow then
   sc.Overflow=true
   flash2D(Color3.fromRGB(0,120,215),.2,.2)
   P.Cue('ErrorBeep',nil)
   for _,c in f.Layer:GetChildren()do c:Destroy()end
   for i=1,14 do
    frame2D(f.Layer,'GlitchBar',UDim2.fromScale(0,math.random()),UDim2.fromScale(1,.01+math.random()*.04),(i%2==0)and cyan or mag,{Z=16})
   end
  end
  if lt>=over and lt<over+.25 then
   for _,c in f.Layer:GetChildren()do if c.Name=='GlitchBar'then c.Position=UDim2.fromScale((math.random()-.5)*.1,math.random())end end
  end
  local bsodAt=over+.25
  if lt>=bsodAt and not sc.Bsod then
   for _,c in f.Layer:GetChildren()do c:Destroy()end
   sc.Bsod=true
   local blue=frame2D(f.Layer,'BlueScreen',UDim2.fromScale(0,0),UDim2.fromScale(1,1),Color3.fromRGB(0,120,215),{Z=16})
   text2D(blue,'Sad',{Text=':(',Anchor=Vector2.new(0,0),Position=UDim2.fromScale(.1,.12),Size=UDim2.fromScale(.2,.2),AlignX=Enum.TextXAlignment.Left,Z=17,Stroke=1})
   text2D(blue,'Line1',{Text=T('Your dog ran into a problem and needs to restart.'),Anchor=Vector2.new(0,0),Position=UDim2.fromScale(.1,.36),Size=UDim2.fromScale(.75,.08),AlignX=Enum.TextXAlignment.Left,Z=17,Stroke=1})
   text2D(blue,'Line2',{Text=T("We're just collecting some dog info, and then we'll restart for you."),Anchor=Vector2.new(0,0),Position=UDim2.fromScale(.1,.45),Size=UDim2.fromScale(.75,.05),AlignX=Enum.TextXAlignment.Left,Z=17,Stroke=1})
   sc.Pct=text2D(blue,'Percent',{Text='',Anchor=Vector2.new(0,0),Position=UDim2.fromScale(.1,.53),Size=UDim2.fromScale(.4,.05),AlignX=Enum.TextXAlignment.Left,Z=17,Stroke=1})
   local qr=frame2D(blue,'QR',UDim2.fromScale(.1,.64),UDim2.fromScale(.1,.1),WHITE,{Z=17})
   local ar=Instance.new('UIAspectRatioConstraint');ar.Parent=qr
   for qx=0,6 do for qy=0,6 do if math.random()<.5 then frame2D(qr,'Q',UDim2.fromScale(qx/7,qy/7),UDim2.fromScale(1/7,1/7),BLACK,{Z=18})end end end
   text2D(blue,'Stop',{Text='STOP CODE: DOG_MEMORY_OVERFLOW',Anchor=Vector2.new(0,0),Position=UDim2.fromScale(.23,.68),Size=UDim2.fromScale(.6,.04),AlignX=Enum.TextXAlignment.Left,Z=17,Stroke=1})
   sc.Prompt=text2D(blue,'Prompt',{Text='',Anchor=Vector2.new(0,0),Position=UDim2.fromScale(.1,.82),Size=UDim2.fromScale(.7,.06),AlignX=Enum.TextXAlignment.Left,Z=17,Stroke=1,
    Color=Color3.fromRGB(230,240,255)})
   sc.Typed=0
   if sc.BB.Parent then sc.BB.Enabled=false end
  end
  if sc.Bsod and sc.Pct and sc.Pct.Parent then
   local x=lin(lt,bsodAt,bsodAt+4.6)
   sc.Pct.Text=string.format(T('%d%% complete'),math.floor(x*100))
   local word='restart game'
   local typeAt=bsodAt+2.2
   local n=math.clamp(math.floor((lt-typeAt)/.13),0,#word)
   if n~=sc.Typed then sc.Typed=n;P.Cue('Key',nil)end
   local caret=(math.floor(lt*3)%2==0)and'_'or' '
   sc.Prompt.Text='C:\\DOGROTS> '..string.sub(word,1,n)..(n<#word and caret or'')
   if lt>=bsodAt+4.2 then sc.Prompt.Text='C:\\DOGROTS> restart game\n'..T('Restarting…')end
  end
  local endAt=bsodAt+5
  if lt>=endAt and not sc.Restored then
   sc.Restored=true
   for _,c in f.Layer:GetChildren()do c:Destroy()end
   if sc.BB.Parent then sc.BB:Destroy()end
   flash2D(WHITE,.2,.4)
   sparksAt(CROWN+V3(0,44,0),cyan,ctx.Low and 20 or 60,true)
   banner(upper(T('GLITCHED MUTATION')),cyan,nil,ctx.Calm)
   P.Cue('Rare',nil)
  end
  if lt<over then
   local x=span(lt,0,over)
   return V3(20,70,400):Lerp(V3(50,95,425),x),CROWN+V3(0,40,0),62-8*x,lt>2 and .1 or 0
  end
  local eye,focus,fov=wideShot(lt-over,6)
  return eye,focus,fov,.05
 end,
}

-- VOID: darkness, the Void island's portal, the beam, clouds, lightning, glyphs, purple ground.
local GLYPHS={'⍙','⟟','⏃','⌇','⍜','⟒','⏚','⋔','⌖','⊑','⍀','⟊','⎍','⏁','⋉','⍾','⏆','⌰','⟟','⍓'}
local function glyph()return GLYPHS[math.random(1,#GLYPHS)]end
SCENES.Void={
 Start=function(ctx)
  local sc=ctx.Sc
  local purple=L.Colors.Void
  if ctx.Siren then ctx.Siren.Stop(.4,true)end
  if ctx.Rumble then ctx.Rumble.Stop(.4)end
  if not ctx.Public then
   grade({Brightness=-.5,Saturation=-.45,Contrast=.25,TintColor=Color3.fromRGB(200,170,255)},.8)
   table.insert(sc.Loops,loop('VoidHum',nil))
  end
  for _,l in ctx.K.Floods do set(l,'Enabled',false)end
  set(ctx.K.CoreLight,'Enabled',false)
  -- the spinning portal at the Void island, facing the tower
  local vp=L.VoidPortal
  local n=(CENTER+V3(0,60,0)-vp).Unit
  sc.PortalFrame=CFrame.lookAt(vp,vp+n)
  sc.Portal={}
  local ringN=ctx.Low and 16 or 28
  for i=1,ringN do
   local p=newPart(sc.Folder,'PortalRing',V3(9,3,3),CF(vp),purple,Enum.Material.Neon,1)
   table.insert(sc.Portal,{P=p,A=(i-1)/ringN*math.pi*2})
  end
  sc.Swirl={}
  for i=1,3 do
   local d=newPart(sc.Folder,'PortalSwirl',V3(.4,70-i*16,70-i*16),CF(vp),i==2 and Color3.fromRGB(20,0,40)or purple:Lerp(BLACK,i*.2),Enum.Material.Neon,1,Enum.PartType.Cylinder)
   table.insert(sc.Swirl,d)
  end
  sc.PortalBeam=newPart(sc.Folder,'PortalBeam',V3(1,6,6),CF(vp),purple,Enum.Material.Neon,1,Enum.PartType.Cylinder)
  -- clouds round the crown
  sc.Cloud=newPart(sc.Folder,'Clouds',V3(140,8,140),CF(CENTER+V3(0,138,0)),WHITE,Enum.Material.SmoothPlastic,1)
  sc.CloudFX=emitter(sc.Cloud,'CloudFX',{Texture=SMOKE,Rate=0,Lifetime=NumberRange.new(4,7),Speed=NumberRange.new(1,4),Spread=Vector2.new(60,60),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,18),NumberSequenceKeypoint.new(1,44)}),Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.2,.35),NumberSequenceKeypoint.new(1,1)}),
   Color=ColorSequence.new(Color3.fromRGB(70,20,120),Color3.fromRGB(20,0,40)),Light=.15,Influence=.5,RotSpeed=NumberRange.new(-20,20),
   Shape=Enum.ParticleEmitterShape.Box,Direction=Enum.NormalId.Top})
  -- floating glyphs round the tower
  sc.Glyphs={}
  for i=1,(ctx.Low and 6 or 14)do
   local a=i/14*math.pi*2
   local r=L.Radius(30)+10+math.random()*14
   local holder=newPart(sc.Folder,'GlyphAnchor',V3(.2,.2,.2),CF(CENTER+V3(math.cos(a)*r,20+math.random()*80,math.sin(a)*r)),WHITE,nil,1)
   local bb=Instance.new('BillboardGui');bb.Adornee=holder;bb.Size=UDim2.fromScale(9,9);bb.LightInfluence=0;bb.MaxDistance=2000;bb.Enabled=false
   bb:SetAttribute('NoTranslate',true);bb.Parent=sc.Folder
   local t=text2D(bb,'Glyph',{Text=glyph(),Size=UDim2.fromScale(1,1),Color=Color3.fromRGB(200,150,255),StrokeColor=Color3.fromRGB(60,0,120),Stroke=.2})
   table.insert(sc.Glyphs,{BB=bb,T=t,H=holder,Base=holder.CFrame.Position,Ph=math.random()*6})
  end
  -- the purple ground under the owner, its cracks
  local o=ctx.Owner
  sc.Ground=newPart(sc.Folder,'VoidGround',V3(.08,1,1),CF(o+V3(0,.06,0))*ANG(0,0,math.pi/2),Color3.fromRGB(90,30,170),Enum.Material.Neon,1,Enum.PartType.Cylinder)
  sc.GroundCracks={}
  for i=1,(ctx.Low and 6 or 12)do
   local a=i/12*math.pi*2+math.random()*.3
   local len=7+math.random()*8
   local segs=zigzag(sc.Folder,'VoidCrack',o+V3(0,.12,0),o+V3(math.cos(a)*len,.12,math.sin(a)*len),6,1,.32,Color3.fromRGB(220,160,255),1)
   table.insert(sc.GroundCracks,segs)
  end
  sc.Bolts={};sc.NextBolt=4.8;sc.Fired=false
  sc.Center=''
 end,
 Update=function(ctx,lt,dt)
  local sc=ctx.Sc
  local k=ctx.K
  local purple=L.Colors.Void
  local vp=L.VoidPortal
  local pf=sc.PortalFrame
  -- the portal spins
  local open=span(lt,ctx.Public and 0 or 1.4,ctx.Public and .6 or 2.6)
  for _,r in sc.Portal do
   local a=r.A+lt*1.6
   local rr=34*open+2
   r.P.CFrame=pf*CF(math.cos(a)*rr,math.sin(a)*rr,0)*ANG(0,0,a+math.pi/2)
   r.P.Transparency=1-open*.9
  end
  for i,d in sc.Swirl do
   d.CFrame=pf*ANG(0,math.pi/2,0)*ANG(lt*(i%2==0 and -2 or 2.6),0,0)*CF(-i*.3,0,0)
   d.Transparency=1-open*(i==2 and .9 or .55)
  end
  -- the beam from the portal to the tower
  local fireAt=ctx.Public and .8 or 3.8
  local beam=span(lt,fireAt,fireAt+.4)
  if beam>0 then
   if not sc.Fired then
    sc.Fired=true
    if not ctx.Public then P.Cue('Portal',nil);P.Cue('Thunder',nil)end
   end
   local target=CROWN+V3(0,6,0)
   local a,b=vp,vp:Lerp(target,beam)
   local len=(b-a).Magnitude
   sc.PortalBeam.Size=V3(len,7+2*math.sin(lt*20),7+2*math.sin(lt*20))
   sc.PortalBeam.CFrame=CFrame.lookAt((a+b)/2,b)*ANG(0,math.pi/2,0)
   sc.PortalBeam.Transparency=.15
   setBeam(purple,10+3*math.sin(lt*13),900*span(lt,fireAt+.4,fireAt+.8),.2)
  end
  local storm=span(lt,ctx.Public and 1 or 4.6,ctx.Public and 1.6 or 5.4)
  sc.CloudFX.Enabled=storm>0 and not ctx.Low;sc.CloudFX.Rate=ctx.Public and 4 or 10
  towerGlow(k,purple:Lerp(BLACK,.3),.3+.4*math.sin(lt*5)*storm)
  for _,g in sc.Glyphs do
   g.BB.Enabled=storm>0
   g.H.CFrame=CF(g.Base+V3(0,math.sin(lt*1.3+g.Ph)*3,0))
   if math.random()<.08 then g.T.Text=glyph()end
   g.T.TextTransparency=1-storm*(.6+.4*math.sin(lt*4+g.Ph))
  end
  -- lightning
  if storm>0 and lt>=sc.NextBolt then
   sc.NextBolt=lt+.3+math.random()*.5
   for _,b in sc.Bolts do b:Destroy()end
   table.clear(sc.Bolts)
   local a=math.random()*math.pi*2
   local from=CENTER+V3(math.cos(a)*50,136,math.sin(a)*50)
   local toTower=math.random()<.5
   local b2=math.random()*math.pi*2
   local to=toTower and shellPoint(b2,30+math.random()*70,.5)or(CENTER+V3(math.cos(b2)*(32+math.random()*25),G,math.sin(b2)*(32+math.random()*25)))
   for _,p in zigzag(sc.Folder,'Bolt',from,to,10,6,.7,Color3.fromRGB(225,190,255),0)do table.insert(sc.Bolts,p)end
   if not ctx.Public then P.Cue('Thunder',nil);flash2D(Color3.fromRGB(190,150,255),.6,.2)end
  elseif #sc.Bolts>0 and math.random()<.3 then
   for _,b in sc.Bolts do b:Destroy()end
   table.clear(sc.Bolts)
  end
  if ctx.Public then return nil end
  -- the ground under the owner
  local spread=span(lt,5.2,6.4)
  local o=ctx.Owner
  sc.Ground.Size=V3(.08,1+32*spread,1+32*spread)
  sc.Ground.Transparency=1-spread*(.55+.15*math.sin(lt*6))
  for _,segs in sc.GroundCracks do
   local n=math.floor(#segs*span(lt,5.4,6.6)+.5)
   for i,s in segs do s.Transparency=i<=n and(.1+.3*math.sin(lt*8+i))or 1 end
  end
  -- the glyph text morphs into VOID MUTATION letter by letter
  local f=pool()
  if lt>=7.8 then
   local target=upper(T('VOID MUTATION'))
   local chars={}
   for _,code in utf8.codes(target)do table.insert(chars,utf8.char(code))end
   local out={}
   for i,ch in chars do
    local settle=8.0+i*.1
    if lt>=settle or ch==' 'then table.insert(out,ch)else table.insert(out,glyph())end
   end
   f.Center.Text=table.concat(out)
   f.Center.TextColor3=Color3.fromRGB(205,160,255);f.Center.TextStrokeColor3=Color3.fromRGB(60,0,120)
   if lt>=8.0+#chars*.1 and not sc.Settled then sc.Settled=true;P.Cue('Rare',nil);flash2D(purple,.4,.5)end
  end
  -- cameras: dark tower -> pull away -> the island and its portal -> the beam reaches the tower ->
  -- the storm -> the owner on purple ground -> the title
  if lt<1.2 then local eye,focus,fov=wideShot(0,1);return eye,focus,fov,0 end
  if lt<2.0 then
   local x=span(lt,1.2,2.0)
   return S.Hero.Eye:Lerp(V3(60,260,360),x),S.Hero.Focus:Lerp(vp,x*.4),S.Hero.Fov+10*x,0
  end
  if lt<4.6 then
   local x=span(lt,2.0,4.6)
   local far=pf*CF(40,40,-260)
   local near=pf*CF(12,10,-95)
   return far.Position:Lerp(near.Position,x),vp,60,lt>3.8 and .3 or .05
  end
  if lt<5.6 then
   local eye,focus,fov=wideShot(lt-4.6,1)
   return eye,focus,fov,.35
  end
  if lt<7.8 then
   local x=span(lt,5.6,7.8)
   -- (the tilt up ends on the tower's south side: further north a phone's wide frame shows the black box)
   return overShoulder(ctx,6.5,2,6.5):Lerp(overShoulder(ctx,5.5,1.6,4.5),x),o:Lerp(CENTER+V3(-20,40,-15),x*.8),66,.3
  end
  local eye,focus,fov=wideShot(lt-7.8,2.2)
  return eye,focus,fov,.15
 end,
 Stop=function(ctx)
  local f=pool();f.Center.Text=''
 end,
}

------------------------------------------------------------------------------------------------
-- Idle (near the tower) and the public show when someone else mutates a dog
------------------------------------------------------------------------------------------------
local idle={Running=false,Machine=nil,Show=nil}
local function stopIdle()
 if idle.Show then idle.Show:Disconnect();idle.Show=nil end
 if idle.Running then restoreAll()end
 idle.Running=false
end
local function startIdle(m)
 if idle.Running or P.Playing or shown then return end
 local k=rig(m);idle.Running=true;idle.Machine=m
 touchShow(k)
 local still=reduced();local low=lowFX()
 local last=0
 idle.Show=Run.Heartbeat:Connect(function()
  local now=os.clock()
  local camera=workspace.CurrentCamera
  local dist=camera and(camera.CFrame.Position-k.Center).Magnitude or math.huge
  local step=(dist<160 and 1/24 or dist<450 and 1/10 or 1/4)*(low and 2 or 1)
  if now-last<step then return end
  last=now
  idleTower(k,now,still)
  if dist<170 then consoleShow(k,now,still,0,nil)end
 end)
end

local publicBusy=false
-- The running public show's teardown (nil when none runs): P.Play calls it before it remembers anything, so
-- the show's restoreAll (which forgets everything remembered) can never run in the middle of the cinematic.
local publicStop=nil
local function publicShow(m,variant)
 if publicBusy or P.Playing or not m.Parent then return end
 local camera=workspace.CurrentCamera
 local k=rig(m)
 local dist=camera and(camera.CFrame.Position-k.Center).Magnitude or math.huge
 if dist>(TW.ShowRange or 900)then return end
 publicBusy=true
 local wasIdle=idle.Running;stopIdle()
 touchShow(k)
 local scene=SCENES[variant]or SCENES.Normal
 local sc=newScene()
 local ctx={K=k,F=pool(),Sc=sc,Calm=reduced(),Low=lowFX()or dist>400,Color=colorOf(variant),Owner=L.OwnerSpot,Public=true}
 local near=dist<220
 if near then ctx.Siren=loop('Siren',k.Door and k.Door.PrimaryPart)end
 local start=os.clock();local total=TW.PublicShow or 7;local last=0;local begun=false
 local conn=nil
 local stopped=false
 -- the end of the show (runs once): the tower and the effects back; resume: restart the idle tower
 local function stop(resume)
  if stopped then return end
  stopped=true
  if publicStop==stop then publicStop=nil end
  if conn then conn:Disconnect()end
  pcall(function()if scene.Stop then scene.Stop(ctx)end end)
  if ctx.Siren then ctx.Siren.Stop(.5)end
  endScene(sc);setBeam(WHITE,0,0,1);restoreAll();publicBusy=false
  if resume and wasIdle then task.defer(function()local mm=tower();if mm and not P.Playing and not publicBusy then startIdle(mm)end end)end
 end
 publicStop=stop
 conn=Run.Heartbeat:Connect(function(dt)
  if stopped then return end
  local t=os.clock()-start
  if not m.Parent or P.Playing or t>=total then
   stop(not P.Playing)
   return
  end
  -- 0..1.4 s: alarm and charge, then the variant's own show
  beacons(k,t<total-1,t)
  if t<1.4 then
   towerGlow(k,L.Toxic:Lerp(WHITE,t/1.4*.5),t/1.4)
   setBeam(L.Toxic,6*t,500*t/1.4,.4)
   return
  end
  if not begun then
   begun=true
   if ctx.Siren and variant~='Normal'then ctx.Siren.Stop(.6);ctx.Siren=nil end
   pcall(scene.Start,ctx)
   if near then P.Cue(variant=='Normal'and'Fail'or'Pulse',k.Main)end
  end
  local lt=t-1.4
  local fade=1-span(t,total-1,total)
  local ok,err=pcall(scene.Update,ctx,lt,dt)
  if not ok then warn('Tower public show: '..tostring(err));start=-math.huge end
  if fade<1 then setBeam(ctx.Color,10*fade,900*fade,1-fade*.8)end
 end)
end

-- Studio / tests: play the public show of a variant now (as if another player had mutated a dog).
function P.PublicShow(variant)
 local m=tower()
 if m then publicShow(m,variant or'Normal')end
end

-- Tower screens in the player's language (server texts are English; labels carry NoTranslate).
local function localizeScreens(m)
 if Lang.Get()~='ru'then return end
 for _,t in m:GetDescendants()do
  if t:IsA('TextLabel')and t:GetAttribute('Localized')~=true then
   local ru=Dict.Machine and Dict.Machine[t.Text]
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
   local m,lab=tower()
   if lab and lastPulse==nil then
    lastPulse=lab:GetAttribute('MachinePulse')or 0
    lab:GetAttributeChangedSignal('MachinePulse'):Connect(function()
     local seq=lab:GetAttribute('MachinePulse')
     local at=tonumber(lab:GetAttribute('MachinePulseAt'))or 0
     if seq==lastPulse then return end;lastPulse=seq
     if lab:GetAttribute('MachinePulseUser')==player.UserId then return end
     if math.abs(workspace:GetServerTimeNow()-at)>3 then return end
     local mm=tower();if mm then publicShow(mm,tostring(lab:GetAttribute('MachinePulseVariant')or'Normal'))end
    end)
   end
   if m then
    localizeScreens(m)
    local camera=workspace.CurrentCamera
    local near=camera~=nil and(camera.CFrame.Position-m:GetPivot().Position).Magnitude<(TW.ShowRange or 900)
    if near and not idle.Running and not P.Playing and not publicBusy then startIdle(m)
    elseif(not near or idle.Machine~=m)and idle.Running then stopIdle()end
   elseif idle.Running then
    if idle.Show then idle.Show:Disconnect();idle.Show=nil end
    idle.Running=false;table.clear(saved)
   end
   task.wait(2)
  end
 end)
end

------------------------------------------------------------------------------------------------
-- The cinematic
------------------------------------------------------------------------------------------------
-- Colour reel steps (NuclearLayout.ReelSteps): slows down and lands on the server's result.
function P.ReelSteps(result,duration)
 local names={};for _,v in ipairs(Base.Variants)do table.insert(names,v.Name)end
 return L.ReelSteps(result,duration,names)
end

local function controls(enable)
 pcall(function()
  local scripts=player:FindFirstChildOfClass('PlayerScripts')
  local module=scripts and scripts:FindFirstChild('PlayerModule')
  if not module then return end
  local c=require(module):GetControls()
  if enable then c:Enable()else c:Disable()end
 end)
end

-- The owner's own pickaxe during the cinematic. MiningWorld welds it to the character as the model
-- "MiningHeldPickaxe" (across the back, or in the hand while its Tool is equipped; "MiningHeldPickaxeL" is
-- the left claw). The over-the-shoulder shots look right past the back mount, so for the whole cinematic it
-- is hidden on this client only: every frame, also a model the server rebuilds or re-mounts mid-show and
-- anything that shows it again (the camera's TransparencyController, PickFX's trail); put back exactly at
-- the end.
local HELD={MiningHeldPickaxe=true,MiningHeldPickaxeL=true}
local HIDE={{'BasePart','LocalTransparencyModifier',1},{'Decal','LocalTransparencyModifier',1},{'ParticleEmitter','Enabled',false},
 {'Trail','Enabled',false},{'Beam','Enabled',false},{'LayerCollector','Enabled',false},{'Light','Enabled',false}}
local function heldHider()
 local list,seen={},{} -- {O, K, W (the value before)}; seen: instance -> remembered
 local self={}
 function self.Hide(character)
  if not(character and character.Parent)then return end
  for _,c in character:GetChildren()do
   if HELD[c.Name]then
    for _,o in c:GetDescendants()do
     for _,r in HIDE do
      if o:IsA(r[1])then
       local key,value=r[2],r[3]
       if(o::any)[key]~=value then
        if not seen[o]then seen[o]=true;table.insert(list,{O=o,K=key,W=(o::any)[key]})end
        (o::any)[key]=value
        if o:IsA('ParticleEmitter')or o:IsA('Trail')then pcall(function()(o::any):Clear()end)end
       end
       break
      end
     end
    end
   end
  end
 end
 -- newest first: the oldest record of a thing holds its value from before the show
 function self.Restore()
  for i=#list,1,-1 do
   local r=list[i]
   if r.O.Parent then pcall(function()(r.O::any)[r.K]=r.W;if r.O:IsA('Trail')then(r.O::any):Clear()end end)end
  end
  table.clear(list);table.clear(seen)
 end
 return self
end

-- A walk along a polyline: f(x 0..1) -> position, direction; and its length.
local function polyPath(pts)
 local lens={};local total=0
 for i=1,#pts-1 do local l=(pts[i+1]-pts[i]).Magnitude;lens[i]=l;total+=l end
 return function(x)
  local s=math.clamp(x,0,1)*total
  for i=1,#pts-1 do
   if s<=lens[i]or i==#pts-1 then
    local u=lens[i]>0 and math.clamp(s/lens[i],0,1)or 1
    return pts[i]:Lerp(pts[i+1],u),(pts[i+1]-pts[i])
   end
   s-=lens[i]
  end
  return pts[#pts],pts[#pts]-pts[#pts-1]
 end,total
end

function P.Play(result)
 if type(result)~='table'or P.Seen[result.Token or'']then return end
 if result.Token then P.Seen[result.Token]=true end
 local m=tower(2)
 if not m or P.Playing then return end
 -- another player's public show still running ends here: its teardown puts the tower back (and forgets
 -- everything remembered) before this cinematic remembers anything
 if publicStop then publicStop(false)end
 publicBusy=false
 stopIdle()
 P.Release(true)
 local k=rig(m);local f=pool();resetPool()
 local calm=reduced();local low=lowFX()
 touchShow(k)
 local before=result.BeforeDog or result.Dog
 local after=result.Dog or result.BeforeDog
 local fromVariant=before and before.Variant or'Normal'
 local toVariant=after and after.Variant or'Normal'
 if not SCENES[toVariant]then toVariant='Normal'end
 local toColor=colorOf(toVariant)
 if toVariant=='Void'then task.spawn(function()pcall(function()player:RequestStreamAroundAsync(L.VoidPortal,3)end)end)end
 -- timeline
 local tPlace,tDoor,tGrab,tLook,tIntake,tReactor,tReel,tReveal=TW.Place,TW.Door,TW.Grab,TW.Look,TW.Intake,TW.Reactor,TW.Reel,TW.Reveal
 local vDur=(TW.Variant and TW.Variant[toVariant])or 6
 -- the burst: inside the chamber the dog takes its new colours, then the variant's own show
 local tScene=tReveal+(TW.Burst or 1.2)
 local tExit=tScene+vDur
 -- exit beats (seconds after tExit): out of the door and onto the pad, the close-ups while it stands
 -- still (paws, head, tail), the showcase orbit, home to the owner (1 s) and into the inventory
 local EX={Out=1.4,OnPad=3.8,Paws=4.0,Head=5.1,Tail=6.4,Orbit=7.5}
 EX.Home=math.max((TW.Exit or 11.5)-2.0,EX.Orbit+1.2)
 local tEnd=tExit+EX.Home+2.0
 if calm then tEnd=TW.Reduced or 4.5 end
 local steps=P.ReelSteps(toVariant,tReveal-.2-tReel)
 local camera=workspace.CurrentCamera
 local oldType,oldSubject,oldCF,oldFov=camera.CameraType,camera.CameraSubject,camera.CFrame,camera:GetAttribute('SecretZoom')or camera.FieldOfView
 -- the owner: moved beside the pad (a cut hides it) and put back at the end
 local character=player.Character
 local humanoid=character and character:FindFirstChildOfClass('Humanoid')
 local hrp=character and character:FindFirstChild('HumanoidRootPart')
 local savedCF=hrp and hrp.CFrame
 local savedAnchored=hrp and hrp.Anchored
 local owner=L.OwnerSpot
 local hipY=hrp and math.clamp(hrp.CFrame.Position.Y-G,1.5,6)or 3
 local ownerCF=CFrame.lookAt(owner+V3(0,hipY,0),V3(L.Pad.Center.X,owner.Y+hipY,L.Pad.Center.Z))
 local ownerLook=flat(L.Pad.Center-owner).Unit
 local connections={}
 local ctx={K=k,F=f,Sc=nil,Calm=calm,Low=low,Color=toColor,Owner=owner,Public=false}
 local scene=SCENES[toVariant]
 local held=heldHider()
 -- The owner reset, died or got a new character: the show ends (the end puts back what still exists and
 -- the camera follows the new humanoid).
 local function ownerLost()
  if not character then return false end
  if player.Character~=character or not character.Parent then return true end
  if humanoid then
   if not humanoid.Parent then return true end
   local okH,hp=pcall(function()return humanoid.Health end)
   if okH and type(hp)=='number'and hp<=0 then return true end
  end
  return false
 end
 -- The owner's pickaxe stays out of the shots: its Tool back in the hotbar (a tap to skip never swings it;
 -- also after a hotbar key mid-show) and the welded model hidden (heldHider).
 local heldWarned=false
 local function keepOwnerClear()
  local okC,errC=pcall(function()
   if not(character and character.Parent)then return end
   if humanoid and character:FindFirstChildOfClass('Tool')then humanoid:UnequipTools()end
   held.Hide(character)
  end)
  if not okC and not heldWarned then heldWarned=true;warn('Tower: owner pickaxe: '..tostring(errC))end
 end
 P.Playing=true;P.SkipRequested=false
 local ok,err=xpcall(function()
  controls(false)
  keepOwnerClear()
  -- the dog
  shown=makeDog(before or after)
  if shown then dogVisible(shown,0)end
  local H=shown and shown.Height or 3
  local padTop=G+.38
  local grabY=padTop+H*.86+1.25
  local grabAt=V3(L.Pad.Center.X,grabY,L.Pad.Center.Z)
  local holdAt=L.Arm.Hold
  local putX=98.2
  local putAt=V3(putX,G+.3+H*.86+1.25,CENTER.Z)
  -- the way home: chamber floor -> door -> the pad (it stops there) -> beside the owner
  local padTopPos=L.Pad.Center+V3(0,.38,0)
  local besideOwner=owner+(L.Pad.Center-owner).Unit*2.4
  local walkOut,walkOutLen=polyPath({V3(putX,G+.3,CENTER.Z),V3(L.Portal.Front-1.2,G,CENTER.Z),padTopPos})
  local walkHome,walkHomeLen=polyPath({padTopPos,V3(besideOwner.X,G,besideOwner.Z)})
  -- on the pad it stands facing its owner (north-west): the close-up cameras stand on that side and look
  -- east-south-east .. south-west, away from the black box north of the plaza
  local standRot=facing(owner-padTopPos)
  -- inside the chamber it hangs turned towards the chamber camera (the burst is seen from the front)
  local chamberRot=facing(V3(-1,0,-.45))
  -- the colour it shows off in after the burst (a failed mutation: grey)
  local showC=toVariant=='Normal'and Color3.fromRGB(150,150,150)or toColor
  local hangRot=nil -- the dog's rotation while it hangs in the claw (it turns to look at you)
  local wristAt=nil -- the claw this frame
  local hangOffset=1.25+H*.86
  local glowHandle=nil
  local function glowDog(variant)
   if not shown then return end
   glowHandle=Glow.Apply(shown.Model,variant,{Strong=true})
  end
  -- input: tap / click / Space skips
  local startedAt=os.clock()
  table.insert(connections,UIS.InputBegan:Connect(function(input)
   local kind=input.UserInputType
   if kind==Enum.UserInputType.MouseButton1 or kind==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.Space or input.KeyCode==Enum.KeyCode.ButtonA or input.KeyCode==Enum.KeyCode.Return then
    if os.clock()-startedAt>.4 then P.SkipRequested=true end
   end
  end))
  f.Gui.Enabled=true;f.Hint.Text=T('TAP TO SKIP')
  if not calm then
   TweenService:Create(f.BarTop,TweenInfo.new(.5),{Size=UDim2.fromScale(1,.085)}):Play()
   TweenService:Create(f.BarBottom,TweenInfo.new(.5),{Size=UDim2.fromScale(1,.085)}):Play()
  end
  local cueDoor=k.Door and k.Door.PrimaryPart
  local phase={}
  local function once(key,fn)if not phase[key]then phase[key]=true;fn()end end
  local skipOffset=0;local lastT=0;local reelIndex=0
  local dogRot=facing(ownerLook)
  local dogGround=owner+ownerLook*2.4+V3(0,1.8,0) -- where it pops out of the inventory (the place shot aims here)
  local lastEye,lastFocus=nil,nil
  local lastReelColor=nil
  ------------------------------------------------------------------ camera direction (NuclearLayout.Shots)
  local oLook=ownerLook;local oRight=oLook:Cross(V3(0,1,0))
  local function ots(back,side,up)return owner-oLook*back+oRight*side+V3(0,up,0)end
  local function dogAt(part,rot)
   if not shown then return L.Pad.Center+V3(0,2,0)end
   return dogPoint(shown,dogGround,rot or dogRot,part)
  end
  local function move(sh,t0,t1,t)
   local x=ease(lin(t,t0,t1))
   local fo=sh.Focus or CENTER
   return sh.Eye:Lerp(sh.Eye1 or sh.Eye,x),fo:Lerp(sh.Focus1 or fo,x),lerp(sh.Fov,sh.Fov1 or sh.Fov,x)
  end
  -- A close-up of the dog standing on the pad (facing its owner, standRot): the camera at azimuth a (radians,
  -- from the dog's front towards its right side), distance d and height up over the dog point (scaled by the
  -- dog's size), aimed at the point + aim (in the dog's frame: X right, Y up, -Z forward); a0/d0/up0/fov0 ->
  -- a1/d1/up1/fov1 eased over x 0..1: a slow dolly on a fixed frame (the dog's idle animation never drags
  -- the camera, no pans).
  local closeK=shown and math.clamp(math.sqrt(shown.Size.Y/4*shown.Size.Z/4.9),.55,1.15)or 1
  local function closeUp(part,a0,a1,d0,d1,up0,up1,aim,fov0,fov1,x)
   x=ease(x)
   local p=shown and dogPoint(shown,padTopPos,standRot,part)or padTopPos+V3(0,2,0)
   local fw,rt=standRot.LookVector,standRot.RightVector
   local a,d=lerp(a0,a1,x),lerp(d0,d1,x)*closeK
   return p+(fw*math.cos(a)+rt*math.sin(a))*d+V3(0,lerp(up0,up1,x)*closeK,0),p+standRot:VectorToWorldSpace(aim)*closeK,lerp(fov0,fov1,x)
  end
  -- -> shot name, eye, focus, fov, shake (0..1), track (smooth the focus), follow (smooth the eye too)
  local function direct(t)
   if t<tPlace then -- over the owner's shoulder at the console: START
    local eye,focus,fov=move(S.Operator,0,tPlace,t)
    return 'operator',eye,focus,fov,(t>.72 and t<.95)and .25 or 0
   elseif t<tDoor then -- the dog comes out of the inventory and trots onto the pad
    local x=ease(lin(t,tPlace,tDoor))
    -- in front of the owner, on the pad side (north-east): the owner, the dog popping out, the pad
    local eye=(owner+oLook*5.2+oRight*7.0+V3(0,4.6,0)):Lerp(owner+oLook*4.8+oRight*6.4+V3(0,4.3,0),x)
    return 'place',eye,dogAt('Body'):Lerp(owner+V3(0,3,0),.4),50,0,true
   elseif t<tGrab then -- behind the dog on the pad: the WARNING door rises
    local eye,focus,fov=move(S.Door,tDoor,tGrab,t)
    return 'door',eye,focus,fov,(t>tDoor+.2 and t<tDoor+1.7)and .12 or .03
   elseif t<tLook then -- high security-camera angle: the claw comes out and takes the dog
    local eye,_,fov=move(S.Grab,tGrab,tLook,t)
    return 'grab',eye,(wristAt or L.Arm.Rest):Lerp(dogAt('Body'),.55),fov,.03,true
   elseif t<tIntake then -- over the owner's shoulder: the dog in the claw turns and looks at you
    local x=ease(lin(t,tLook,tIntake))
    return 'look',ots(2.2,1.4,5.95):Lerp(ots(1.6,1.3,5.85),x),dogAt('Head',hangRot),lerp(38,31,x),.02,true
   elseif t<tReactor then -- from the pad: the dog is pulled in, the door slams (kick)
    local eye,focus,fov=move(S.Intake,tIntake,tReactor,t)
    local slam=tIntake+1.3
    return 'intake',eye,focus,fov,(t>=slam and t<slam+.5)and .9*(1-lin(t,slam,slam+.5))or .05
   elseif t<tReel+.6 then -- a crane up the tower: steam, dust, the reel starts
    local eye,focus,fov=move(S.Crane,tReactor,tReel+.6,t)
    return 'crane',eye,focus,fov,.15
   elseif t<tReveal-1.4 then -- the tower, the crown, the beam goes up
    local eye,focus,fov=move(S.Hero,tReel+.6,tReveal-1.4,t)
    return 'hero',eye,focus,fov,.1+.25*span(t,tReel+1.2,tReel+2.0)
   elseif t<tScene then -- inside the chamber: the reel colours strobe over the dog, it bursts (tReveal)
    local x=ease(lin(t,tReveal-1.4,tScene))
    local kick=t>=tReveal and .8*(1-lin(t,tReveal,tReveal+.5))or .05
    return 'chamber',S.Chamber.Eye:Lerp(S.Chamber.Eye+V3(.4,-.5,.3),x),dogAt('Body',hangRot),lerp(S.Chamber.Fov,S.Chamber.Fov-8,x),kick,true
   elseif t>=tExit then
    local e=t-tExit
    if e<2.2 then -- the door opens on the dog in its new colours
     local eye,_,fov=move(S.ExitDoor,0,2.2,e)
     return 'exitDoor',eye,dogAt('Body'):Lerp(S.ExitDoor.Focus,.4),fov,.02,true
    elseif e<EX.Paws then -- it walks out at you (a low shot ahead of it) and stops on the pad
     local body=dogAt('Body')
     local eye=body+V3(-7.2,1.5,2.6)
     return 'exitWalk',V3(math.max(eye.X,81.8),eye.Y,eye.Z),body,50,0,true,true -- (stops short of the owner)
    elseif e<EX.Head then -- close-up: the front paws on the lit pad, from its front left (low, slow push-in)
     local eye,focus,fov=closeUp('Paws',math.rad(-30),math.rad(-21),4.0,3.4,.7,.55,V3(0,.3,0),42,38,lin(e,EX.Paws,EX.Head))
     return 'paws',eye,focus,fov,0
    elseif e<EX.Tail then -- close-up: the face and the mutation glow, from its front right (eye level, the
     -- tower and the open door behind it, slow push-in)
     local eye,focus,fov=closeUp('Head',math.rad(34),math.rad(25),4.0,3.4,.25,.15,V3(0,-.1,0),42,39,lin(e,EX.Head,EX.Tail))
     return 'head',eye,focus,fov,0
    elseif e<EX.Orbit then -- close-up: the tail and hind legs, from behind its left side (looking west ..
     -- south-west, away from the black box north of the plaza), a slow arc round towards its back
     local eye,focus,fov=closeUp('Tail',math.rad(-112),math.rad(-126),4.5,4.2,.7,.9,V3(0,-.05,-.15),40,40,lin(e,EX.Tail,EX.Orbit))
     return 'tail',eye,focus,fov,0
    elseif e<EX.Home then -- the showcase: the pad lights up, a slow arc round the dog (north-east -> north)
     local body=dogAt('Body')
     local a=lerp(math.rad(60),math.rad(92),ease(lin(e,EX.Orbit,EX.Home)))
     return 'orbit',body+V3(math.cos(a)*8.6,2.0,math.sin(a)*8.6),body,50,0
    end -- home to the owner, into the inventory
    return 'final',S.Final.Eye,dogAt('Body'):Lerp(owner+V3(0,4.4,0),.5),S.Final.Fov,0,true
   end
   return 'hold',S.Hero.Eye1,S.Hero.Focus1,S.Hero.Fov,0
  end
  local shotName,lastShot,track,follow=nil,nil,false,false
  local camEye,camFocus,camEyeV,camFocusV=nil,nil,Vector3.zero,Vector3.zero
  -- critically damped spring towards target (smoothing of tracked subjects)
  local function spring(x,v,target,omega,dt)
   local f=1+2*dt*omega;local oo=omega*omega;local hoo=dt*oo;local hhoo=dt*hoo
   local det=1/(f+hhoo)
   local nx=(x*f+v*dt+target*hhoo)*det
   local nv=(v+(target-x)*hoo)*det
   return nx,nv
  end
  while true do
   -- the owner reset or died: the show ends now
   if ownerLost()then break end
   keepOwnerClear()
   local t=os.clock()-startedAt+skipOffset
   if P.SkipRequested then
    P.SkipRequested=false
    if calm then break end
    if t<tReveal-.05 then skipOffset+=tReveal-t;t=tReveal
    elseif t<tExit-.05 then skipOffset+=tExit-t;t=tExit
    else break end
   end
   if t>=tEnd then break end
   local dt=math.clamp(t-lastT,0,.1);lastT=t
   local now=os.clock()
   local eye,focus,fov,shake
   if calm then
    ------------------------------------------------------------------ the short version
    local m1=1.2
    if t<m1 then
     eye,focus,fov=S.Operator.Eye,S.Operator.Focus,S.Operator.Fov
     once('calmStart',function()P.Cue('Activate',k.Main)end)
    else
     once('calmReveal',function()
      if shown then dogVisible(shown,1);glowDog(toVariant)end
      banner(bannerOf(toVariant),toVariant=='Normal'and Color3.fromRGB(255,90,90)or toColor,nil,true)
      P.Cue(toVariant=='Normal'and'Fail'or'Reveal',nil)
      towerGlow(k,toColor,.6)
     end)
     if shown then placeDog(shown,L.Pad.Center+V3(0,.38,0),facing(owner-L.Pad.Center))end
     eye,focus,fov=S.Door.Eye,L.Pad.Center+V3(0,2,0),56
    end
    shake=0
    consoleShow(k,now,true,0,nil)
   else
    ------------------------------------------------------------------ console: START
    local level=0
    if t<tReveal then level=math.clamp(span(t,.8,1.6)*.4+span(t,tReactor,tReveal)*.6,0,1)end
    local reelColor=nil
    local reelColorNow=lastReelColor
    -- the guard flips up, the button is pressed, the levers go forward
    if k.Guard then
     touch(k.Guard,'CFrame')
     local hinge=k.Guard:GetAttribute('Hinge')
     local g0=saved[k.Guard].CFrame
     if typeof(hinge)=='CFrame'then
      local a=math.rad(115)*(span(t,.15,.5)-span(t,tPlace,tPlace+.4))
      k.Guard.CFrame=hinge*ANG(0,0,-a)*hinge:Inverse()*g0
     end
    end
    if k.Start then
     touch(k.Start,'CFrame')
     local press=(span(t,.72,.8)-span(t,.9,1.2))*.25
     k.Start.CFrame=saved[k.Start].CFrame*CF(-press,0,0) -- a Y cylinder: its X axis points up
    end
    for _,lv in k.Levers do
     if lv.P.Parent and typeof(lv.Base)=='CFrame'then
      touch(lv.P,'CFrame');if lv.Knob then touch(lv.Knob,'CFrame')end
      local a=math.rad(38)*(span(t,.95+lv.I*.12,1.2+lv.I*.12)-span(t,tExit+1,tExit+2))
      local cf=lv.Base*ANG(0,0,a)
      lv.P.CFrame=cf*CF(0,.5,0)
      if lv.Knob then lv.Knob.CFrame=cf*CF(0,1.02,0)end
     end
    end
    if t>=.78 and t<tPlace then once('start',function()
     P.Cue('Activate',k.Main)
     sparksAt(k.Start and k.Start.CFrame.Position or L.Anchor,Color3.fromRGB(255,70,70),low and 6 or 16)
     if k.MainText.Reel then set(k.MainText.Reel,'Text',upper(T('START')));set(k.MainText.Reel,'TextColor3',Color3.fromRGB(255,90,90))end
     if k.MainText.Status then set(k.MainText.Status,'Text',upper(T('REACTOR STARTING')))end
    end)end
    ------------------------------------------------------------------ the owner and the dog
    -- the owner stands at the console for START (over-the-shoulder shot), then beside the pad
    once('operator',function()
     local op=L.OperatorSpot or V3(74.2,G,477)
     if hrp and hrp.Parent then hrp.Anchored=true;hrp.CFrame=CFrame.lookAt(op+V3(0,hipY,0),op+V3(5,hipY,0))end
    end)
    if t>=tPlace then once('owner',function()
     if hrp and hrp.Parent then hrp.Anchored=true;hrp.CFrame=ownerCF end
    end)end
    if shown then
     local appear=tPlace+.15
     if t<appear then
      dogVisible(shown,0)
     elseif t<tPlace+.9 then
      -- out of the inventory: in front of the owner at hand height, set down on the ground
      once('appear',function()
       glowDog(fromVariant)
       P.Cue('Pop',nil)
       sparksAt(owner+ownerLook*2.4+V3(0,2.4,0),WHITE,low and 8 or 24)
      end)
      dogVisible(shown,span(t,appear,appear+.35))
      local x=span(t,appear+.15,tPlace+.9)
      dogGround=owner+ownerLook*2.4+V3(0,lerp(1.8,0,x),0)
      dogRot=facing(ownerLook)
      clip(shown,'Idle',0)
     elseif t<tDoor-.3 then
      dogVisible(shown,1)
      once('landed',function()dustAt(owner+ownerLook*2.4,low and 2 or 5)end)
      local x=span(t,tPlace+1.0,tDoor-.6)
      local from=owner+ownerLook*2.4
      local to=V3(L.Pad.Center.X,padTop,L.Pad.Center.Z)
      dogGround=from:Lerp(to,x)
      if x>0 and x<1 then clip(shown,'Walk',3);dogRot=facing(to-from)else clip(shown,'Idle',0)end
      if x>=1 then dogRot=facing(owner-L.Pad.Center)end
     elseif t<tGrab+1.35 then
      -- on the pad: it watches the WARNING door open
      dogGround=V3(L.Pad.Center.X,padTop,L.Pad.Center.Z)
      clip(shown,'Idle',0)
      dogRot=facing(owner-L.Pad.Center):Lerp(facing(V3(1,0,0)),span(t,tDoor+.3,tDoor+1.0))
     end
     if t<tGrab+1.35 then placeDog(shown,dogGround,dogRot)end
    end
    ------------------------------------------------------------------ the door, the alarm
    if t>=tDoor and t<tReveal then once('siren',function()
     ctx.Siren=loop('Siren',cueDoor)
     P.Cue('DoorOpen',cueDoor)
     for _,e in k.DoorSteam do e:Emit(low and 8 or 22)end
     if k.MainText.Status then set(k.MainText.Status,'Text',upper(T('DOOR OPENING')))end
    end)end
    local doorX=0
    if t<tExit then
     doorX=span(t,tDoor+.2,tDoor+1.7)*(1-span(t,tIntake+1.0,tIntake+1.3))
    else
     doorX=span(t,tExit+.1,tExit+1.1)*(1-span(t,tEnd-.9,tEnd-.2))
    end
    doorTo(k,doorX)
    if t>=tIntake+1.3 and t<tReveal then once('slam',function()
     P.Cue('DoorSlam',cueDoor)
     dustAt(V3(L.Portal.Front-1,G+.5,CENTER.Z),low and 6 or 18)
     shock(V3(L.Portal.Front-1,G+.3,CENTER.Z),Color3.fromRGB(200,200,200),18,.5)
    end)end
    if t>=tExit and t<tExit+1 then once('reopen',function()
     P.Cue('DoorOpen',cueDoor)
     -- the steam comes out in the new colour
     for _,e in k.DoorSteam do touch(e,'Color');e.Color=ColorSequence.new(showC:Lerp(WHITE,.5),showC);e:Emit(low and 8 or 22)end
    end)end
    local alarm=t>=tDoor and t<tReveal
    beacons(k,alarm,now,nil)
    local w=k.DoorText.Warning
    if w then set(w,'TextColor3',alarm and((math.floor(now*4)%2==0)and Color3.fromRGB(255,40,40)or Color3.fromRGB(255,206,0))or Color3.fromRGB(230,40,40))end
    local chamberC,chamberB=Color3.fromRGB(230,40,40),(t>=tDoor and t<tReveal)and 4 or 1.4
    if t>=tReveal-1.6 and t<tReveal then
     chamberC=reelColorNow or L.Toxic;chamberB=6+3*math.sin(now*22)
    elseif t>=tReveal then
     chamberC=showC
     chamberB=t<tScene and lerp(14,6,span(t,tReveal,tReveal+.8))or 5
    end
    if k.ChamberLight then set(k.ChamberLight,'Brightness',chamberB);set(k.ChamberLight,'Color',chamberC)end
    if k.ChamberLamp then set(k.ChamberLamp,'Color',chamberC)end
    for _,s in k.ChamberStrips do set(s,'Color',chamberC)end
    ------------------------------------------------------------------ the arm
    local armTarget,armOpen=L.Arm.Rest,.2
    if t>=tGrab and t<tReveal then
     local high=grabAt+V3(0,3.2,0)
     if t<tGrab+.9 then armTarget=L.Arm.Rest:Lerp(high,span(t,tGrab,tGrab+.9));armOpen=span(t,tGrab,tGrab+.6)
     elseif t<tGrab+1.3 then armTarget=high:Lerp(grabAt,span(t,tGrab+.9,tGrab+1.3));armOpen=1
     elseif t<tLook then armTarget=grabAt+V3(0,.9*span(t,tGrab+1.55,tLook),0);armOpen=1-span(t,tGrab+1.3,tGrab+1.55)
     elseif t<tIntake then armTarget=grabAt+V3(0,.9,0)+V3(0,math.sin(now*3)*.12,0);armOpen=0
     else armTarget=(grabAt+V3(0,.9,0)):Lerp(holdAt,span(t,tIntake,tIntake+1.0));armOpen=0 end
    elseif t>=tReveal and t<tExit then armTarget=holdAt;armOpen=0
    elseif t>=tExit then
     if t<tExit+.6 then armTarget=holdAt:Lerp(putAt,span(t,tExit,tExit+.6));armOpen=0
     else armTarget=putAt:Lerp(L.Arm.Rest,span(t,tExit+.8,tExit+1.6));armOpen=span(t,tExit+.6,tExit+.8)*(1-span(t,tExit+1.4,tExit+1.8))end
    end
    if t>=tGrab-.1 then
     local wrist=poseArm(k,armTarget,armOpen)
     wristAt=wrist
     if t>=tGrab+.1 and t<tGrab+.2 then once('servo',function()P.Cue('Servo',cueDoor)end)end
     -- the dog hangs from the claw (grab -> chamber -> put down)
     if shown and t>=tGrab+1.35 and t<tExit+.6 then
      once('hangVisible',function()dogVisible(shown,1)end) -- (also after a skip past the pad)
      -- behind the shut door it turns towards the chamber camera (unseen), for the burst
      if t>=tIntake+1.3 and t<tExit then dogRot=chamberRot end
      local swing=math.sin(now*2.4)*.08
      local look=dogRot
      if t>=tLook-.2 and t<tIntake+1.3 then
       -- it turns to look at you, and keeps looking at you while it is pulled in
       local eyePos=owner+V3(0,4.4,0)
       local target=facing(eyePos-wrist)
       local x=span(t,tLook-.2,tLook+.4)
       look=dogRot:Lerp(target,x)
      end
      dogGround=wrist-V3(0,hangOffset,0)
      hangRot=look
      placeDog(shown,dogGround,look*ANG(swing,0,swing*.6))
      if t>=tGrab+1.35 then once('grabbed',function()
       P.Cue('Lock',cueDoor)
       if k.MainText.Status then set(k.MainText.Status,'Text',upper(T('SUBJECT CAPTURED')))end
      end)end
     end
    end
    ------------------------------------------------------------------ reactor: rumble, reel, beam
    if t>=tLook and t<tReveal then once('rumble',function()ctx.Rumble=loop('Rumble',k.Main)end)end
    if t>=tReactor and t<tReveal then
     once('charge',function()
      P.Cue('Charge',nil)
      for _,h in k.Hiss do h:Emit(low and 3 or 8)end
      if k.Steam then touch(k.Steam,'Rate');k.Steam.Rate=low and 10 or 22 end
      if k.MainText.Status then set(k.MainText.Status,'Text',upper(T('SUBJECT LOADED')))end
     end)
     if not low and math.random()<.06 then dustAt(L.Shell(math.random()*math.pi*2,20+math.random()*60,.5),3)end
    end
    if t>=tReel and t<tReveal-.2 then
     local x=t-tReel
     local idx=1
     for i,s in steps do if x>=s.At-.0001 then idx=math.min(i+1,#steps)end end
     if x<steps[1].At then idx=1 end
     local name=steps[idx]and steps[idx].Name or toVariant
     reelColor=colorOf(name)
     if idx~=reelIndex then
      reelIndex=idx
      f.Ticker.Text=variantName(name);f.Ticker.TextColor3=reelColor;f.TickerScale.Scale=1.25
      TweenService:Create(f.TickerScale,TweenInfo.new(.12),{Scale=1}):Play()
      if k.MainText.Reel then set(k.MainText.Reel,'Text',variantName(name));set(k.MainText.Reel,'TextColor3',reelColor)end
      P.Cue('Tick',nil,.8+idx/#steps*.9)
     end
     if k.MainText.Status then set(k.MainText.Status,'Text',upper(T('CRITICAL MASS')))end
    elseif t>=tReveal-.2 and t<tReveal then
     reelColor=toColor
    end
    if t>=tReveal-.2 then f.Ticker.Text=''end
    if t>=tReactor and t<tReveal then
     local c=reelColor or L.Toxic
     towerGlow(k,c,.5+.5*math.sin(now*9))
     local beamUp=span(t,tReel+1.2,tReel+2.0)
     if beamUp>0 then
      once('beam',function()P.Cue('Beam',nil);shock(CROWN,c,60,.8)end)
      setBeam(c,(9+3*math.sin(now*15))*beamUp,900*beamUp,.15)
     end
    end
    consoleShow(k,now,false,level,reelColor or(t>=tReveal and toColor or nil))
    lastReelColor=reelColor
    ------------------------------------------------------------------ the burst (inside the chamber)
    if t>=tReveal and t<tScene then once('burst',function()
     local body=shown and dogPoint(shown,dogGround,hangRot or dogRot,'Body')or L.Arm.Hold
     f.Ticker.Text=''
     if toVariant=='Normal'then
      -- it fizzles: grey smoke, a zap and a low buzz, no new colours (the scene's Fail sting follows); a
      -- mutated dog rerolled to Normal loses its old glow here
      glowDog(toVariant)
      P.Cue('Arc',nil);P.Cue('Deny',nil)
      dustAt(body,low and 6 or 18)
      sparksAt(body,Color3.fromRGB(150,150,150),low and 6 or 14)
      flash2D(Color3.fromRGB(255,70,70),.6,.35)
     else
      -- it bursts into its new mutation
      glowDog(toVariant)
      P.Cue('Reveal',nil)
      flash2D(toColor:Lerp(WHITE,.45),calm and .6 or .05,.55)
      sparksAt(body,toColor,low and 30 or 90,true)
      sparksAt(body,WHITE,low and 8 or 24)
      shock(body,toColor,16,.7,true)
     end
    end)end
    ------------------------------------------------------------------ the variant sequence
    if t>=tScene and t<tExit then
     if not ctx.Sc then
      ctx.Sc=newScene()
      if ctx.Rumble and toVariant~='Corrupted'and toVariant~='Void'then ctx.Rumble.Stop(1)end
      local okS,errS=pcall(scene.Start,ctx)
      if not okS then warn('Tower scene start: '..tostring(errS))end
     end
     local okU,e1,e2,e3,e4=pcall(scene.Update,ctx,t-tScene,dt)
     if okU and e1 then eye,focus,fov,shake=e1,e2,e3,e4 elseif not okU then warn('Tower scene: '..tostring(e1))end
    elseif t>=tExit then once('exitStart',function()
     -- a skip (or a long frame) jumped over the burst: the dog still takes its new look (no fanfare now)
     if not phase.burst then phase.burst=true;glowDog(toVariant)end
     if ctx.Sc then
      pcall(function()if scene.Stop then scene.Stop(ctx)end end)
      endScene(ctx.Sc);ctx.Sc=nil
     end
     if ctx.Siren then ctx.Siren.Stop(.3)end
     if ctx.Rumble then ctx.Rumble.Stop(.3)end
     setBeam(toColor,0,0,1)
     resetPool();f.Gui.Enabled=true;f.Hint.Text=T('TAP TO SKIP')
     f.BarTop.Size=UDim2.fromScale(1,.085);f.BarBottom.Size=UDim2.fromScale(1,.085)
     banner(bannerOf(toVariant),toVariant=='Normal'and Color3.fromRGB(255,110,110)or toColor,after and(after.DisplayName or after.DogId)or nil,false)
     f.Banner.Position=UDim2.fromScale(.5,.16)
    end)end
    if t>=tExit then
     towerGlow(k,toColor,.4+.3*math.sin(now*4))
     if k.MainText.Reel then
      set(k.MainText.Reel,'Text',toVariant=='Normal'and upper(T('MUTATION FAILED'))or variantName(toVariant))
      set(k.MainText.Reel,'TextColor3',toColor)
      if k.MainText.Status then set(k.MainText.Status,'Text',upper(T('MUTATION COMPLETE')))end
     end
    end
    ------------------------------------------------------------------ exit: the dog walks home
    local e=t-tExit
    if shown and t>=tExit then once('exitVisible',function()dogVisible(shown,1)end)end
    if shown and t>=tExit+.6 then
     -- out of the door onto the pad (EX.Out..OnPad), it stands still there for the close-ups and the
     -- showcase (OnPad..Home), home to its owner (Home..Home+1), into the inventory (Home+1.3)
     local pos,dir,moving,speed
     if e<EX.Home then
      local x=lin(e,EX.Out,EX.OnPad);pos,dir=walkOut(x);moving=x>0 and x<1;speed=walkOutLen/(EX.OnPad-EX.Out)
     else
      local x=lin(e,EX.Home,EX.Home+1);pos,dir=walkHome(x);moving=x>0 and x<1;speed=walkHomeLen
     end
     dogGround=pos
     if moving then
      clip(shown,'Walk',speed)
      -- the last steps onto the pad already turn it towards its owner (it arrives facing the cameras)
      local want=facing(dir)
      if e<EX.Home then want=want:Lerp(standRot,span(e,EX.OnPad-.8,EX.OnPad))end
      dogRot=dogRot:Lerp(want,math.clamp(dt*8,0,1))
     else
      clip(shown,'Idle',0)
      if e>=EX.OnPad then
       -- standing still, facing its owner; exactly so from the first close-up on (the cut hides the rest)
       dogRot=e>=EX.Paws and standRot or dogRot:Lerp(standRot,math.clamp(dt*10,0,1))
      end
     end
     if e>=EX.OnPad then once('padLights',function()
      -- the pad lights up in its colour under it
      for _,p in k.PadLights do set(p,'Color',showC);set(p,'Transparency',0)end
      for _,p in k.PadPaw do set(p,'Color',showC);set(p,'Transparency',0)end
     end)end
     if e>=EX.Orbit then once('showcase',function()
      local body=dogPoint(shown,dogGround,dogRot,'Body')
      if toVariant=='Normal'then
       P.Cue('Pop',nil)
       dustAt(padTopPos+V3(0,.3,0),low and 2 or 5)
      else
       shock(padTopPos+V3(0,.1,0),toColor,10,.6)
       sparksAt(body,toColor,low and 10 or 30)
       sparksAt(body,WHITE,low and 4 or 10)
       f.BannerScale.Scale=1.35
       TweenService:Create(f.BannerScale,TweenInfo.new(.35,Enum.EasingStyle.Back),{Scale=1}):Play()
       P.Cue('Rare',nil)
      end
     end)end
     local absorb=EX.Home+1.3
     if e>=absorb then
      -- back into the inventory
      once('absorb',function()
       P.Cue('Pop',nil)
       sparksAt(owner+V3(0,2.5,0),showC,low and 10 or 30)
       f.Sub.Text=upper(T('BACK TO THE INVENTORY'))
      end)
      dogVisible(shown,1-span(e,absorb,absorb+.4))
      -- the glow (its Highlight, light and particles) goes with it
      if e>=absorb+.35 then once('unglow',function()Glow.Remove(shown.Model);glowHandle=nil end)end
     end
     placeDog(shown,dogGround,dogRot)
    end
    ------------------------------------------------------------------ cameras
    if not eye then shotName,eye,focus,fov,shake,track,follow=direct(t)else shotName,track,follow='scene',false,false end
    -- the console screen line under the reel
    if t>=tPlace and t<tDoor and k.MainText.Status then set(k.MainText.Status,'Text',upper(T('PLACE THE DOG')))end
    if t>=tDoor-.4 and t<tDoor and k.MainText.Status then set(k.MainText.Status,'Text',upper(T('SUBJECT ON THE PAD')))end
   end
   if shown and shown.Anim then pcall(function()shown.Anim:Step(workspace:GetServerTimeNow())end)end
   -- camera
   eye=eye or lastEye or camera.CFrame.Position
   focus=focus or lastFocus or(eye+camera.CFrame.LookVector)
   lastEye,lastFocus=eye,focus
   -- a cut resets the smoothing; tracked shots ease the focus (and the eye when following) on springs
   if shotName~=lastShot or not camEye then
    lastShot=shotName;camEye,camFocus=eye,focus;camEyeV,camFocusV=Vector3.zero,Vector3.zero
   end
   if track then camFocus,camFocusV=spring(camFocus,camFocusV,focus,7,dt)else camFocus=focus end
   if follow then camEye,camEyeV=spring(camEye,camEyeV,eye,5,dt)else camEye=eye end
   local cf=CFrame.lookAt(camEye,camFocus)
   -- shake = a small rotation (the eye never moves into a wall)
   local amp=calm and 0 or math.clamp(shake or 0,0,1.2)
   if amp>0 then
    local r=math.rad(2.4)*amp
    cf=cf*ANG(math.noise(now*9,1.3)*r*.75,math.noise(now*9,7.1)*r,math.noise(now*7,3.7)*r*.35)
   end
   camera.CameraType=Enum.CameraType.Scriptable
   camera.FieldOfView=fov or 60
   if(camEye-camFocus).Magnitude>.01 then camera.CFrame=cf end
   Run.RenderStepped:Wait()
  end
 end,debug.traceback)
 -- End (also after an error, a reset or a death): camera, owner, tower and effects back; the dog is home (in
 -- the inventory). Every step on its own, so one failing never keeps the camera or the controls.
 local function step(name,fn)
  local okS,errS=pcall(fn)
  if not okS then warn('Tower end ('..name..'): '..tostring(errS))end
 end
 step('input',function()for _,c in connections do c:Disconnect()end end)
 step('scene',function()
  if ctx.Sc then pcall(function()if scene.Stop then scene.Stop(ctx)end end);endScene(ctx.Sc);ctx.Sc=nil end
  if ctx.Siren then ctx.Siren.Stop(.3)end
  if ctx.Rumble then ctx.Rumble.Stop(.3)end
 end)
 step('sound',function()duck(false)end)
 P.Playing=false;P.SkipRequested=false
 step('dog',dropDog)
 step('tower',function()setBeam(WHITE,0,0,1);resetPool()end)
 step('restore',restoreAll)
 step('owner',function()
  -- back where it stood, unless it reset / died meanwhile (a new character stands where it spawned)
  local lost=ownerLost()
  if hrp and hrp.Parent then
   if savedCF and not lost then hrp.CFrame=savedCF end
   hrp.Anchored=savedAnchored==true
  end
 end)
 step('pickaxe',held.Restore)
 step('controls',function()controls(true)end)
 step('camera',function()
  camera.CameraType=oldType==Enum.CameraType.Scriptable and Enum.CameraType.Custom or oldType
  -- the player's current humanoid (after a reset: the new one, which the engine already follows)
  local now=player.Character
  local subject=now and now.Parent and now:FindFirstChildOfClass('Humanoid')
  if not subject and oldSubject and oldSubject.Parent then subject=oldSubject end
  if subject then camera.CameraSubject=subject end
  camera.FieldOfView=oldFov
  if oldType==Enum.CameraType.Scriptable then camera.CFrame=oldCF end
 end)
 task.defer(function()local mm=tower();if mm and not P.Playing and not publicBusy then startIdle(mm)end end)
 if not ok then error(err)end
end

-- The result card closed (the dog is already back in the inventory): make sure nothing is left over.
function P.Release(instant)
 if P.Playing then return end
 dropDog()
 if fx then resetPool()end
 local _=instant
end

return P
