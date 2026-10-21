-- Halloween timing-hit sessions (StarterPlayerScripts.MiningClient.HalloweenStrike), started by MiningClient with its
-- shared ctx (FX, Combo, PickFX, Anim, Audio, Tool, World, Hud, Text). The SAME feel as the Mining Corner: the circles,
-- judging, swing, PickFX hit effects, sound kits and the 2D combo juice are copied from MiningClient.Mine (circle code:
-- Mine L21-24, L106-116, L167-386, L389-513, L774-827), but the targets are the server's Halloween targets
-- (Workspace.HalloweenLive.Targets, tag "HalloweenTarget", ServerScriptService.Halloween.Strike) of every kind: ore,
-- haunted dig spots, boss armor / mounds / skeletons / rocks, mini bosses. Kinds only provide their visuals
-- (HalloweenClient.SpotFX / BossFX) and server logic.
--   * a ProximityPrompt (client-side) on every target part: ActionText = its Verb (MINE / DIG / STRIKE / BREAK);
--     clicking with the pickaxe near a target starts too
--   * the camera stays player-controlled (no orbit), movement stays free (dodging the boss); Space / F / A / R2 hit the
--     circle closest to its gold ring (no jump during a session), Esc / B / EXIT leave, walking out of range leaves
--   * the server judges every click (Perfect is claimed here, confirmed there; crits are rolled there) and pays
--     Config.Candy.PerfectHit per confirmed Perfect: sound + flash + PERFECT stamp + particles + hit pause, the candy
--     number pops and the HUD candy icon flies (Bus CandyGain)
--   * other players' swings / hits come from Signal StrikeFx
-- Bus events for visual modules: StrikeBegin {Part, TargetId, Kind, Variant, Extra}, StrikeSwing {Part, TargetId, Kind,
-- Position, Normal, Perfect, Crit, HitStop, Remote, UserId}, StrikeResult {Part, TargetId, Kind, Quality, Crit, Damage, HP,
-- MaxHP, Broke, Candy, Extra, Position}, StrikeEnd {Part, TargetId, Kind, Reason}.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Lighting=game:GetService('Lighting')
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local TweenService=game:GetService('TweenService')
local CollectionService=game:GetService('CollectionService')
local Debris=game:GetService('Debris')
local Strike={}

local CIRCLE_MAX=118 -- px, outer ring at the moment a circle opens (shrinks on small screens)
local JITTER=.42 -- circles land up to this many circle sizes away from their hit point (random)
local IDLE_EXIT=22 -- seconds without a hit before the session closes itself
local HIT_SOUND_DELAY=.11 -- the strike sound lands with FX.Hit (the swing whoosh plays on the click)
local HIT_STOP=.075 -- perfect-hit pause (target model + FOV hold)
local TAG='HalloweenTarget'
local ACTION='DOGROTS_HalloweenHit'

local VERBS={MINE={'MINE','ДОБЫТЬ'},DIG={'DIG','КОПАТЬ'},STRIKE={'STRIKE','УДАРИТЬ'},BREAK={'BREAK','РАЗБИТЬ'}}
local CODES={
 ['HW:FAR']={'Move closer','Подойди ближе'},
 ['HW:GONE']={'It is gone','Цель исчезла'},
 ['HW:NEED_PICKAXE']={'Buy a pickaxe at your Mining Corner first','Сначала купи кирку в своём Шахтёрском уголке'},
 ['HW:NOT_YOURS']={'This one is haunting another player','Это чужая цель'},
 ['HW:OFF']={'The Night of the Buried Moon has ended','Ночь Погребённой Луны закончилась'},
 ['HW:WAIT']={'Catch your breath...','Переведи дух...'},
 ['HW:CANT']={'Not now','Сейчас нельзя'},
 ['HW:DOWNED']={'You are downed: wait for a revive','Ты повержен: дождись, пока тебя поднимут'}, -- [WP-B] Event HP downed lockout
 ['Please wait a moment']={'Please wait a moment','Подожди немного'},
}

function Strike.new(ctx)
 local self:any={Active=false,Target=nil}
 local player=ctx.Player
 local M,Text,Audio,U=ctx.M,ctx.Text,ctx.Audio,ctx.U
 local World,FX,Hud,Anim=ctx.World,ctx.FX,ctx.Hud,ctx.Anim
 local Combo,PickFX=ctx.Combo,ctx.PickFX
 local TM=M.Timing
 local CIRCLE=CIRCLE_MAX
 local gui=ctx.Gui::ScreenGui
 gui.IgnoreGuiInset=true
 pcall(function()gui.ScreenInsets=Enum.ScreenInsets.None end)
 local font=U.FontFace or Font.fromEnum(Enum.Font.FredokaOne)
 local function L(en,ru)return Text.L(en,ru)end

 -- Halloween modules arrive with ReplicatedStorage (the event may be switched off: then nothing ever starts)
 local Shared,Bus,HFX,HAudio,Remotes,Skins=nil,nil,nil,nil,nil,nil
 local function enabled()return Shared~=nil and Shared.Enabled()end

 -- OVERLAY ------------------------------------------------------------------------------------
 local C3=Color3.fromRGB
 local overlay=Instance.new('Frame');overlay.Name='HalloweenStrike';overlay.Size=UDim2.fromScale(1,1);overlay.BackgroundTransparency=1
 overlay.Visible=false;overlay.ZIndex=10;overlay.Parent=gui
 local circles=Instance.new('Frame');circles.Name='Circles';circles.Size=UDim2.fromScale(1,1);circles.BackgroundTransparency=1;circles.ZIndex=20;circles.Parent=overlay
 -- target card: dark purple glass, pumpkin outline (Halloween HUD look)
 local panel=Instance.new('Frame');panel.Name='TargetPanel';panel.AnchorPoint=Vector2.new(.5,0);panel.Position=UDim2.new(.5,0,0,58)
 panel.Size=UDim2.fromOffset(400,78);panel.BackgroundColor3=C3(34,16,52);panel.BackgroundTransparency=.12;panel.BorderSizePixel=0;panel.ZIndex=30;panel.Parent=overlay
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,14);c.Parent=panel
  local s=Instance.new('UIStroke');s.Color=C3(255,128,24);s.Thickness=3;s.Parent=panel
  local g=Instance.new('UIGradient');g.Color=ColorSequence.new(C3(255,255,255),C3(170,150,200));g.Rotation=90;g.Parent=panel end
 local function text(parent,name,x,y,w,h,size,color,align)
  local l=Instance.new('TextLabel');l.Name=name;l.BackgroundTransparency=1;l.Position=UDim2.fromOffset(x,y);l.Size=UDim2.fromOffset(w,h)
  l.FontFace=font;l.TextSize=size;l.TextColor3=color or Color3.new(1,1,1);l.TextXAlignment=align or Enum.TextXAlignment.Left
  l.TextTruncate=Enum.TextTruncate.AtEnd;l.ZIndex=31;l.Text='';l:SetAttribute('NoTranslate',true);l.Parent=parent;return l
 end
 local title=text(panel,'Title',16,6,368,26,22,C3(255,236,200))
 title.TextScaled=true;title.TextTruncate=Enum.TextTruncate.None
 do local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=22;limit.MinTextSize=12;limit.Parent=title end
 local hpBack=Instance.new('Frame');hpBack.Name='HP';hpBack.Position=UDim2.fromOffset(16,34);hpBack.Size=UDim2.new(1,-32,0,14)
 hpBack.BackgroundColor3=C3(18,10,28);hpBack.BorderSizePixel=0;hpBack.ZIndex=31;hpBack.Parent=panel
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=hpBack end
 local hpFill=Instance.new('Frame');hpFill.Name='Fill';hpFill.Size=UDim2.fromScale(1,1);hpFill.BorderSizePixel=0;hpFill.BackgroundColor3=C3(255,140,40);hpFill.ZIndex=32;hpFill.Parent=hpBack
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=hpFill
  local g=Instance.new('UIGradient');g.Color=ColorSequence.new(C3(255,220,120),C3(255,110,30));g.Parent=hpFill end
 local hpText=text(hpBack,'HPText',0,0,0,0,12,Color3.new(1,1,1),Enum.TextXAlignment.Center);hpText.Size=UDim2.fromScale(1,1);hpText.ZIndex=33
 local info=text(panel,'Info',16,52,368,22,14,C3(210,196,236))
 info.TextScaled=true;info.TextTruncate=Enum.TextTruncate.None
 do local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=15;limit.MinTextSize=10;limit.Parent=info end
 local hint=text(overlay,'Hint',0,0,0,0,20,Color3.new(1,1,1),Enum.TextXAlignment.Center)
 hint.AnchorPoint=Vector2.new(.5,1);hint.Position=UDim2.new(.5,0,1,-86);hint.Size=UDim2.fromOffset(620,30);hint.TextStrokeTransparency=0
 hint.TextScaled=true;hint.TextTruncate=Enum.TextTruncate.None;hint.TextStrokeColor3=C3(34,16,52);hint.ZIndex=30
 do local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=20;limit.MinTextSize=11;limit.Parent=hint end
 local exitButton
 if U.Button then exitButton=U.Button(overlay,'Exit',Text.Get('EXIT'),0,0,150,48,function()self.Exit('button')end,U.Colors.red)
 else
  exitButton=Instance.new('TextButton');exitButton.Size=UDim2.fromOffset(150,48);exitButton.Text=Text.Get('EXIT');exitButton.FontFace=font;exitButton.TextSize=22
  exitButton.BackgroundColor3=U.Colors.red;exitButton.TextColor3=Color3.new(1,1,1);exitButton.Parent=overlay
  pcall(function()exitButton.Activated:Connect(function()self.Exit('button')end)end)
 end
 exitButton.AnchorPoint=Vector2.new(.5,1);exitButton.Position=UDim2.new(.5,0,1,-24);exitButton.ZIndex=40
 for _,d in ipairs(exitButton:GetDescendants())do if d:IsA('GuiObject')then d.ZIndex=41 end end
 local function reducedMotion()
  if FX.ReducedMotion and FX.ReducedMotion()then return true end
  local ok,v=pcall(function()return(game:GetService('GuiService')::any).ReducedMotionEnabled end)
  return ok and v==true
 end
 -- (pcall: identical in Roblox; lets the offline smoke test run without a layout engine)
 local function screenSize()
  local ok,v=pcall(function()return gui.AbsoluteSize end)
  return ok and v or Vector2.new(1280,720)
 end
 local function layout()
  local size=screenSize()
  panel.Size=UDim2.fromOffset(math.clamp(size.X-24,280,420),78)
  local top=UIS.TouchEnabled and 46 or 58
  panel.Position=UDim2.new(.5,0,0,top)
  CIRCLE=math.clamp(math.floor(math.min(size.X,size.Y)*.22),72,CIRCLE_MAX)
  hint.Size=UDim2.fromOffset(math.min(size.X-24,640),30)
 end
 gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(layout);layout()

 -- STATE ------------------------------------------------------------------------------------
 local view=nil -- {Part, HitPoints, Kind, Color, Material, Id}
 local active={} -- circle id -> circle
 local judged={}
 local lastActivity=0
 local sendQueue,sending,lastSent={},false,0
 local connections={}
 local resyncing=false
 local hp,maxHP=0,1
 local baseFOV=nil
 local function pick()
  local d=M.Pickaxes[player:GetAttribute('MiningPickaxe')or 1]or M.Pickaxes[1]
  if Skins and Skins.For then local ok,v=pcall(Skins.For,player,d);if ok and v then return v end end
  return d
 end
 local function tier()return pick().FX or 1 end
 local function theme()return pick().Theme or'Wood'end
 local function pickColor()return Color3.fromRGB(table.unpack(pick().Color or{110,220,255}))end
 local function targetColor()return view and view.Color or C3(180,160,140)end
 local function message(code)
  if type(code)~='string'then return L('Connection problem; try again','Проблема со связью, попробуй ещё раз')end
  local row=CODES[code];if row then return L(row[1],row[2])end
  if string.sub(code,1,2)=='M:'then return Text.Message(code)end
  -- server strings of other kinds: the Halloween localization table first, then every other Localization module
  -- (Chapter II refusals live in Localization.Boss / Seals2 / Underyard)
  local ok,res=pcall(function()
   if not Text.IsRussian()then return nil end
   local loc=RS:FindFirstChild('Localization');if not loc then return nil end
   local first=loc:FindFirstChild('Halloween')
   local list={first}
   for _,m in ipairs(loc:GetChildren())do if m~=first and m:IsA('ModuleScript')then table.insert(list,m)end end
   for _,m in ipairs(list)do
    local okR,t=pcall(require,m);local exact=okR and type(t)=='table'and t.Exact
    if type(exact)=='table'and type(exact[code])=='string'then return exact[code]end
   end
   return nil
  end)
  return (ok and type(res)=='string')and res or code
 end
 local function invoke(action,args)
  if not Remotes then return false,'HW:OFF'end
  local remote=Remotes:FindFirstChild('Request');if not remote then return false,'HW:OFF'end
  local transport,ok,res=pcall(function()return remote:InvokeServer(action,args or{})end)
  if not transport then return false,nil end
  return ok==true,res
 end
 local function fire(name,data)if Bus then Bus.Fire(name,data)end end
 local KIND_NAMES={Ore={'HALLOWEEN ORE','ХЭЛЛОУИНСКАЯ РУДА'},DigSpot={'HAUNTED DIG SPOT','ПРОКЛЯТОЕ МЕСТО'},MiniBoss={'HAUNTED SKELETON','ПРИЗРАЧНЫЙ СКЕЛЕТ'}}
 local function labelOf(part)
  local ru=Text.IsRussian()
  local l=ru and part:GetAttribute('LabelRU')or part:GetAttribute('Label')
  if type(l)=='string'and l~=''then return l end
  local kind=part:GetAttribute('Kind')
  local row=KIND_NAMES[kind or'']
  return row and L(row[1],row[2])or string.upper(tostring(kind or''))
 end
 local function refreshPanel()
  if not view then return end
  title.Text=labelOf(view.Part)
  title.TextColor3=targetColor():Lerp(C3(255,240,214),.45)
  hpFill.Size=UDim2.fromScale(math.clamp(hp/math.max(maxHP,1e-3),0,1),1)
  hpText.Text=Text.Get('HP',math.max(0,math.ceil(hp)),math.ceil(maxHP))
  local p=pick()
  local perfect=Shared and Shared.Config.Candy.PerfectHit or 1
  info.Text=(p.Icon or'⛏')..' '..Text.Name(p)..'  ·  '..L('PERFECT = +'..perfect..' 🍬','ИДЕАЛЬНО = +'..perfect..' 🍬')
 end

 -- CIRCLES (MiningClient.Mine) -------------------------------------------------------------------
 local GOLD,GOLD_HOT,INK=C3(255,206,64),C3(255,244,170),C3(18,24,48)
 local function disc(parent,name,scale,color,transparency,z)
  local f=Instance.new('Frame');f.Name=name;f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromScale(scale,scale)
  f.BackgroundColor3=color;f.BackgroundTransparency=transparency;f.BorderSizePixel=0;f.ZIndex=z;f.Parent=parent
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=f
  return f
 end
 local function ring(parent,name,size,color,thickness,z,transparency)
  local f=Instance.new('Frame');f.Name=name;f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromScale(size,size)
  f.BackgroundTransparency=1;f.ZIndex=z;f.Parent=parent
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=f
  local s=Instance.new('UIStroke');s.Color=color;s.Thickness=thickness;s.Transparency=transparency or 0;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=f
  return f,s
 end
 local function ringScale(f)return 1-.75*f end
 local MID=(TM.PerfectFrom+TM.PerfectTo)/2
 -- blur blink on hits (shared with Mine by name); the FOV kick is applied to the player's own camera
 local blur=Lighting:FindFirstChild('DOGROTS_MiningBlur')
 if not blur then blur=Instance.new('BlurEffect');blur.Name='DOGROTS_MiningBlur';blur.Size=0;blur.Enabled=false;blur.Parent=Lighting end
 -- the FOV is only touched while a kick is live (base captured at the kick), so other camera users are never fought
 local blurAmount,fovKick,holdUntil,kicking=0,0,0,false
 function self.Kick(strength)
  if reducedMotion()then return end
  blurAmount=math.max(blurAmount,6*strength)
  local cam=workspace.CurrentCamera
  if not kicking and cam then baseFOV=cam.FieldOfView end
  kicking=cam~=nil
  fovKick=math.max(fovKick,2.6*strength)
 end
 local usedPoints={}
 -- world position of a hit point (= Attachment.WorldPosition; computed from the parent so it also works offline)
 local function wpos(att)
  local parent=att.Parent
  if parent and parent:IsA('BasePart')then return(parent.CFrame*att.CFrame).Position end
  return att.WorldPosition
 end
 local function screenPos(cam,att)
  local p,on=cam:WorldToViewportPoint(wpos(att))
  return Vector2.new(p.X,p.Y),on
 end
 local function pickPoint(jitter)
  local cam=workspace.CurrentCamera
  if not view then return nil end
  if not cam then return World.HitPoint(view,nil,usedPoints)end
  local live={}
  for _,c in pairs(active)do
   if not c.Removed and c.Point and c.Point.Parent then table.insert(live,screenPos(cam,c.Point)+(c.Jitter or Vector2.zero)*CIRCLE)end
  end
  local own=(jitter or Vector2.zero)*CIRCLE
  local avoid={};local free=0;local fallback,fallbackGap=nil,-1
  for _,att in ipairs(view.HitPoints or{})do
   if att.Parent then
    local p=screenPos(cam,att)+own
    local gap=math.huge
    for _,q in ipairs(live)do gap=math.min(gap,(p-q).Magnitude)end
    if usedPoints[att]or gap<CIRCLE*.9 then avoid[att]=true else free+=1 end
    if not usedPoints[att]and gap>fallbackGap then fallback,fallbackGap=att,gap end
   end
  end
  local att=if free>0 then World.HitPoint(view,cam.CFrame.Position,avoid)else fallback
  if att then usedPoints[att]=true end
  return att
 end
 local judgeAt
 local function burst2D(center,color,perfect)
  if reducedMotion()then return end
  local size=CIRCLE*(perfect and 2.6 or 1.9)
  local flash=disc(circles,'HitFlash',1,Color3.new(1,1,1),.05,90)
  flash.Size=UDim2.fromOffset(CIRCLE*.4,CIRCLE*.4);flash.Position=UDim2.fromOffset(center.X,center.Y)
  TweenService:Create(flash,TweenInfo.new(.28,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(size*.62,size*.62),BackgroundTransparency=1}):Play()
  Debris:AddItem(flash,.32)
  local blast,stroke=ring(circles,'HitBlast',1,perfect and GOLD_HOT or color,perfect and 10 or 7,91)
  blast.Size=UDim2.fromOffset(CIRCLE*.6,CIRCLE*.6);blast.Position=UDim2.fromOffset(center.X,center.Y)
  TweenService:Create(blast,TweenInfo.new(.36,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(size,size)}):Play()
  TweenService:Create(stroke,TweenInfo.new(.36,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Transparency=1,Thickness=1}):Play()
  Debris:AddItem(blast,.4)
  local count=perfect and 14 or 9
  local base=math.random()*360
  for i=1,count do
   local a=math.rad(base+i*360/count+math.random(-6,6))
   local line=Instance.new('Frame');line.Name='SpeedLine';line.AnchorPoint=Vector2.new(0,.5);line.BorderSizePixel=0;line.ZIndex=92
   line.BackgroundColor3=i%3==0 and color or(perfect and GOLD_HOT or Color3.new(1,1,1));line.Rotation=math.deg(a)
   local r0=CIRCLE*.28
   line.Position=UDim2.fromOffset(center.X+math.cos(a)*r0,center.Y+math.sin(a)*r0);line.Size=UDim2.fromOffset(CIRCLE*.18,perfect and 5 or 4)
   local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=line
   line.Parent=circles
   local r1=CIRCLE*(perfect and 1.25 or .95)*(0.8+math.random()*.4)
   TweenService:Create(line,TweenInfo.new(.26,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
    {Position=UDim2.fromOffset(center.X+math.cos(a)*r1,center.Y+math.sin(a)*r1),Size=UDim2.fromOffset(CIRCLE*(perfect and .5 or .36),1),BackgroundTransparency=1}):Play()
   Debris:AddItem(line,.3)
  end
 end
 local function removeCircle(c,resultColor,how)
  if c.Removed then return end
  c.Removed=true
  active[c.Id]=nil
  if c.Point then usedPoints[c.Point]=nil end
  local frame=c.Frame
  if not resultColor or reducedMotion()then frame:Destroy();return end
  local quick=TweenInfo.new(.22,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
  for _,s in ipairs(c.Strokes)do s.Color=resultColor;TweenService:Create(s,quick,{Transparency=1}):Play()end
  for _,d in ipairs(c.Discs)do TweenService:Create(d,quick,{BackgroundTransparency=1}):Play()end
  if c.Icon then TweenService:Create(c.Icon,quick,{TextTransparency=1}):Play()end
  if how=='hit'then
   TweenService:Create(c.Pop,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.42}):Play()
  elseif how=='early'then
   for i=-1,1,2 do
    local crack=Instance.new('Frame');crack.Name='Crack';crack.AnchorPoint=Vector2.new(.5,.5);crack.Position=UDim2.fromScale(.5,.5)
    crack.Size=UDim2.new(.9,0,0,3);crack.Rotation=45*i+math.random(-10,10);crack.BackgroundColor3=resultColor;crack.BorderSizePixel=0
    crack.ZIndex=frame.ZIndex+8;crack.Parent=frame
    TweenService:Create(crack,quick,{BackgroundTransparency=1}):Play()
   end
   local p0=frame.Position
   task.spawn(function()
    for k=1,5 do if not frame.Parent then return end;frame.Position=p0+UDim2.fromOffset((k%2==0 and 1 or-1)*(9-k*1.5),0);task.wait(.025)end
   end)
   TweenService:Create(c.Pop,TweenInfo.new(.22,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.6}):Play()
  else
   TweenService:Create(c.Pop,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.72}):Play()
  end
  task.delay(.26,function()frame:Destroy()end)
 end
 local function sendHit(c,quality,miss)
  table.insert(sendQueue,{Circle=c,Quality=quality,Miss=miss,Point=c.Point and c.Point:GetAttribute('Index')or nil,Token=self.Token})
  if sending then return end
  sending=true
  task.spawn(function()
   while #sendQueue>0 and self.Active do
    local item=table.remove(sendQueue,1)
    local wait=(M.MinHitGap+.02)-(os.clock()-lastSent)
    if wait>0 then task.wait(wait)end
    if item.Token==self.Token and self.Active then -- a hit queued in an earlier session is never sent
     lastSent=os.clock()
     task.spawn(function()self.OnResult(item,invoke('StrikeHit',{Target=item.Circle.Id,Quality=item.Quality,Miss=item.Miss,Point=item.Point}))end)
    end
   end
   sending=false
  end)
 end
 local function circleCenter(c)
  local ok,v=pcall(function()return c.Frame.AbsolutePosition+c.Frame.AbsoluteSize/2 end)
  return ok and v or screenSize()/2
 end
 -- the striker turns to the struck point (yaw only) so every swing lands where the circle was
 local function faceTowards(pos)
  local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
  if not(root and root:IsA('BasePart')and pos)then return nil end
  local flat=Vector3.new(pos.X,root.Position.Y,pos.Z)
  if(flat-root.Position).Magnitude<.5 then return root end
  root.CFrame=CFrame.lookAt(root.Position,flat)
  return root
 end
 -- a ground shockwave in the pickaxe's colours from the feet to a point out of reach (boss plates, big ores)
 local function strikeWave(root,pos,colors,perfect)
  if not root or FX.Low()then return end
  local from=root.Position+root.CFrame.LookVector*2.2-Vector3.new(0,2.4,0)
  local to=Vector3.new(pos.X,math.min(pos.Y,from.Y+1.2),pos.Z)
  local dist=(to-from).Magnitude
  if dist<6 then return end
  local head=Instance.new('Part');head.Name='StrikeWave';head.Anchored=true;head.CanCollide=false;head.CanQuery=false;head.CanTouch=false;head.CastShadow=false
  head.Material=Enum.Material.Neon;head.Color=colors[1];head.Size=Vector3.new(1.4,.5,2.2);head.Transparency=.1
  head.CFrame=CFrame.lookAt(from,to);head.Parent=FX.Folder
  local a0=Instance.new('Attachment');a0.Position=Vector3.new(-.9,0,0);a0.Parent=head
  local a1=Instance.new('Attachment');a1.Position=Vector3.new(.9,0,0);a1.Parent=head
  local trail=Instance.new('Trail');trail.Attachment0=a0;trail.Attachment1=a1;trail.Lifetime=.22;trail.LightEmission=1
  trail.Color=ColorSequence.new(colors[1],colors[2]or colors[1]);trail.Transparency=NumberSequence.new(.1,1);trail.Parent=head
  local t=math.clamp(dist/120,.06,.12)
  TweenService:Create(head,TweenInfo.new(t,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{CFrame=CFrame.lookAt(to,to+(to-from).Unit),Size=Vector3.new(perfect and 3 or 2,.3,1)}):Play()
  task.delay(t,function()
   FX.Ring(to+Vector3.new(0,.3,0),colors[1],perfect and 9 or 6,.35)
   TweenService:Create(head,TweenInfo.new(.12),{Transparency=1}):Play()
  end)
  Debris:AddItem(head,t+.4)
 end
 -- Perfect Hit: flash + particles + hit pause on top of the Mine feedback (PERFECT stamp, kit sound)
 local function perfectJuice(pos,normal)
  if HFX then
   HFX.Flash(C3(255,214,110),.13,.22)
   if pos then
    HFX.Burst(pos,{Color=C3(255,150,40),Color2=C3(255,236,140),Count=16,Speed={10,20},Lifetime={.35,.7},Size={.35,.7,0},Drag=4,
     Acceleration=Vector3.new(0,-18,0),Direction=normal,Spread=70})
    HFX.Burst(pos,{Color=C3(190,110,255),Color2=C3(255,255,255),Count=8,Speed={4,9},Lifetime={.4,.8},Size={.25,.5,0},Drag=3,Acceleration=Vector3.zero})
   end
  end
  -- [WP-P] the sparkle is part of the kit's Perfect stack now (MiningAudio PERFECT_STACK): no second Sparkle cue
  if not reducedMotion()then holdUntil=os.clock()+HIT_STOP end
 end
 local function judge(c)
  if c.Removed or c.Judged then return end
  local f=(os.clock()-c.LocalSpawn)/c.Window
  if f<0 then return end
  c.Judged=true;judged[c.Id]=true
  lastActivity=os.clock()
  local pos=c.Point and wpos(c.Point)
  local screen=circleCenter(c)
  if f<TM.GoodFrom then
   removeCircle(c,U.Colors.red,'early')
   if pos then FX.Popup(pos,Text.Get('TOO_EARLY'),U.Colors.red)end
   if Combo then Combo.Miss(screen)end
   Audio.Play('Miss')
   sendHit(c,1,true)
   return
  end
  local perfect=f>=TM.PerfectFrom and f<=TM.PerfectTo
  local color=pickColor()
  removeCircle(c,perfect and GOLD_HOT or color:Lerp(Color3.new(1,1,1),.4),'hit')
  burst2D(screen,color,perfect)
  self.Kick(perfect and 1 or .55)
  local def=pick()
  local root=pos and faceTowards(pos)
  Anim.Swing(1+tier()*.02,nil,def.Swing)
  Audio.Pickaxe('Swing',def)
  local n=1
  if Combo then n=Combo.Hit(screen,perfect and 2 or 1,color)end
  if HFX then HFX.Shake((perfect and .4 or .25)+math.min(.5,n*.02),.25)end
  if PickFX then PickFX.HitPulse(player.Character,perfect and 1 or .7)end
  if def.Theme=='TV'and Combo then Combo.Glitch()end
  if pos and view then
   local normal=c.Point:GetAttribute('Normal')
   local palette=PickFX and PickFX.Palette(theme())or{color}
   task.delay(.05,function()if self.Active then strikeWave(root,pos,palette,perfect)end end)
   task.delay(.11,function()
    if not self.Active or not view then return end
    FX.Hit(pos,normal,targetColor(),view.Material,tier(),perfect and 2 or 1,false,false,theme())
    if perfect then perfectJuice(pos,normal)end
    fire('StrikeSwing',{Part=view.Part,TargetId=view.Id,Kind=view.Kind,Position=pos,Normal=normal,Perfect=perfect,HitStop=perfect and HIT_STOP or 0})
   end)
  end
  task.delay(HIT_SOUND_DELAY,function()if self.Active then Audio.Pickaxe(perfect and'Perfect'or'Hit',def,nil,{Combo=n})end end)
  sendHit(c,perfect and 2 or 1,false)
 end
 local lastInput,lastInputAt=nil,0
 function judgeAt(input,hit)
  if input==lastInput and os.clock()-lastInputAt<.05 then return end
  lastInput,lastInputAt=input,os.clock()
  local tap=Vector2.new(input.Position.X,input.Position.Y)
  local now=os.clock();local mid=(TM.PerfectFrom+TM.PerfectTo)/2
  local best,bestScore,near,nearDist=nil,math.huge,nil,math.huge
  for _,c in pairs(active)do
   if not c.Judged and not c.Removed and c.Frame.Visible then
    local center=c.Frame.AbsolutePosition+c.Frame.AbsoluteSize/2
    local dist=(center-tap).Magnitude
    if dist<=c.Frame.AbsoluteSize.X/2+2 then
     local f=(now-c.LocalSpawn)/c.Window
     if f>=TM.GoodFrom and math.abs(f-mid)<bestScore then best,bestScore=c,math.abs(f-mid)end
     if dist<nearDist then near,nearDist=c,dist end
    end
   end
  end
  judge(best or near or hit)
 end
 local function makeCircle(t)
  if active[t.Id]or judged[t.Id]then return end
  local c={Id=t.Id,Window=t.Window,LocalSpawn=t.LocalSpawn,Slot=t.Slot,Strokes={},Discs={}}
  local a=math.random()*math.pi*2
  c.Jitter=Vector2.new(math.cos(a),math.sin(a)*.8)*(math.random()*JITTER)
  c.Point=pickPoint(c.Jitter)
  local color=pickColor()
  local palette=PickFX and PickFX.Palette(theme())or{color,color}
  local frame=Instance.new('Frame');frame.Name='Circle'..t.Id;frame.AnchorPoint=Vector2.new(.5,.5);frame.Size=UDim2.fromOffset(CIRCLE,CIRCLE)
  frame.BackgroundTransparency=1;frame.Visible=false;frame.ZIndex=math.max(21,1000000-t.Id*12);frame.Parent=circles
  local z=frame.ZIndex
  local pop=Instance.new('UIScale');pop.Scale=.2;pop.Parent=frame
  c.Pop=pop;c.Shown=false
  local function keep(d)table.insert(c.Discs,d);return d end
  local function keepRing(f,s)table.insert(c.Strokes,s);return f,s end
  c.Glow={}
  for i,g in ipairs({{1.34,.93},{1.18,.88},{1.04,.84}})do
   local d=keep(disc(frame,'Glow'..i,g[1],color,g[2],z));table.insert(c.Glow,{Disc=d,Base=g[2],Size=g[1]})
  end
  local plate=keep(disc(frame,'Plate',.84,INK,.32,z+1))
  local pg=Instance.new('UIGradient');pg.Color=ColorSequence.new(color:Lerp(Color3.new(1,1,1),.25),INK);pg.Rotation=90;pg.Parent=plate
  local well=keep(disc(frame,'Well',.6,color:Lerp(INK,.45),.35,z+2))
  local wg=Instance.new('UIGradient');wg.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,.6)});wg.Rotation=90;wg.Parent=well
  keepRing(ring(frame,'PlateEdge',.84,color:Lerp(Color3.new(1,1,1),.5),2,z+2,.35))
  local goldScale=ringScale(MID)
  local _,goldSoft=keepRing(ring(frame,'GoldSoft',goldScale,GOLD,12,z+3,.72))
  local _,gold=keepRing(ring(frame,'Gold',goldScale,GOLD,5,z+3,.15))
  local _,goldLine=keepRing(ring(frame,'GoldLine',goldScale,GOLD_HOT,1.5,z+4,0))
  c.GoldSoft,c.Gold,c.GoldLine=goldSoft,gold,goldLine
  c.Ticks={}
  for i=0,3 do
   local tick=Instance.new('Frame');tick.Name='Tick';tick.AnchorPoint=Vector2.new(.5,.5);tick.BorderSizePixel=0;tick.BackgroundColor3=GOLD_HOT
   local ang=i*math.pi/2;local r=goldScale*.5
   tick.Position=UDim2.fromScale(.5+math.cos(ang)*r,.5+math.sin(ang)*r);tick.Size=UDim2.fromOffset(4,10);tick.Rotation=math.deg(ang)+90;tick.ZIndex=z+4
   local cc=Instance.new('UICorner');cc.CornerRadius=UDim.new(1,0);cc.Parent=tick;tick.Parent=frame;keep(tick);table.insert(c.Ticks,tick)
  end
  local approach=Instance.new('Frame');approach.Name='Approach';approach.AnchorPoint=Vector2.new(.5,.5);approach.Position=UDim2.fromScale(.5,.5)
  approach.Size=UDim2.fromScale(1,1);approach.BackgroundTransparency=1;approach.ZIndex=z+5;approach.Parent=frame
  local _,apGlow=keepRing(ring(approach,'Glow',1,color,10,z+5,.7))
  local _,apLine=keepRing(ring(approach,'Line',1,Color3.new(1,1,1),3.5,z+6,0))
  local keys={}
  for i,col in ipairs(palette)do keys[#keys+1]=ColorSequenceKeypoint.new((i-1)/math.max(1,#palette-1),col:Lerp(Color3.new(1,1,1),.55))end
  if #keys<2 then keys={ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),ColorSequenceKeypoint.new(1,color)}end
  local apGrad=Instance.new('UIGradient');apGrad.Color=ColorSequence.new(keys);apGrad.Parent=apLine
  c.Approach,c.ApGlow,c.ApLine,c.ApGrad=approach,apGlow,apLine,apGrad
  local comet=Instance.new('Frame');comet.Name='Comet';comet.AnchorPoint=Vector2.new(.5,.5);comet.Position=UDim2.fromScale(.5,.5)
  comet.Size=UDim2.fromScale(1,1);comet.BackgroundTransparency=1;comet.ZIndex=z+7;comet.Parent=approach
  local head=disc(comet,'Head',.11,Color3.new(1,1,1),0,z+7);head.Position=UDim2.fromScale(.5,0);keep(head)
  local tail=disc(comet,'Tail',.075,color:Lerp(Color3.new(1,1,1),.4),.35,z+7);tail.Position=UDim2.fromScale(.5+math.sin(.22)*.5,.5-math.cos(.22)*.5);keep(tail)
  c.Comet=comet
  c.Sparks={}
  for i=1,3 do
   local orbit=Instance.new('Frame');orbit.Name='Orbit';orbit.AnchorPoint=Vector2.new(.5,.5);orbit.Position=UDim2.fromScale(.5,.5)
   orbit.Size=UDim2.fromScale(.72,.72);orbit.BackgroundTransparency=1;orbit.ZIndex=z+3;orbit.Rotation=i*120;orbit.Parent=frame
   local dot=disc(orbit,'Spark',.07,palette[(i-1)%#palette+1]:Lerp(Color3.new(1,1,1),.3),.1,z+3);dot.Position=UDim2.fromScale(.5,0);keep(dot)
   table.insert(c.Sparks,orbit)
  end
  local core=keep(disc(frame,'Core',.34,Color3.new(1,1,1),0,z+8))
  local cg=Instance.new('UIGradient');cg.Color=ColorSequence.new(Color3.new(1,1,1),color:Lerp(Color3.new(1,1,1),.25));cg.Rotation=90;cg.Parent=core
  local _,coreEdge=keepRing(ring(frame,'CoreEdge',.34,color,2.5,z+8,0))
  local coreScale=Instance.new('UIScale');coreScale.Parent=core
  local icon=Instance.new('TextLabel');icon.Name='Icon';icon.BackgroundTransparency=1;icon.Size=UDim2.fromScale(.8,.8);icon.AnchorPoint=Vector2.new(.5,.5)
  icon.Position=UDim2.fromScale(.5,.5);icon.TextScaled=true;icon.Text=pick().Icon or'⛏';icon.ZIndex=z+9;icon:SetAttribute('NoTranslate',true);icon.Parent=core
  c.Core,c.CoreScale,c.CoreEdge,c.Icon=core,coreScale,coreEdge,icon
  local button=Instance.new('TextButton');button.Name='Hit';button.Text='';button.BackgroundTransparency=1;button.AutoButtonColor=false
  button.AnchorPoint=Vector2.new(.5,.5);button.Position=UDim2.fromScale(.5,.5);button.Size=UDim2.fromScale(1.08,1.08);button.ZIndex=z+10;button.Parent=frame
  button.InputBegan:Connect(function(input)
   if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then judgeAt(input,c)end
  end)
  c.Frame=frame
  c.Color=color
  active[t.Id]=c
 end
 -- server targets -> local clock (never Net.SetTargets: that is Mine's list)
 local function syncTargets(list)
  if not self.Active or type(list)~='table'then return end
  local now=workspace:GetServerTimeNow()
  local live={}
  for _,t in ipairs(list)do
   if type(t)=='table'and tonumber(t.Id)and tonumber(t.SpawnAt)and tonumber(t.Window)then
    live[t.Id]=true
    makeCircle({Id=t.Id,Slot=t.Slot or 1,Window=t.Window,LocalSpawn=os.clock()+(t.SpawnAt-now)})
   end
  end
  for id,c in pairs(active)do if not live[id]and not c.Judged then removeCircle(c,nil)end end
  for id in pairs(judged)do if not live[id]then judged[id]=nil end end
 end
 local function hitBest()
  local best,bestScore=nil,math.huge
  local now=os.clock()
  for _,c in pairs(active)do
   if not c.Judged and not c.Removed then
    local f=(now-c.LocalSpawn)/c.Window
    if f>=0 then
     local score=math.abs(f-(TM.PerfectFrom+TM.PerfectTo)/2)
     if score<bestScore then best,bestScore=c,score end
    end
   end
  end
  if best then judge(best)end
 end

 -- RESULTS ------------------------------------------------------------------------------------
 local function resync(delay)
  if resyncing or not self.Active then return end
  resyncing=true
  local token=self.Token
  task.delay(delay or 0,function()
   if not self.Active or not view or self.Token~=token then resyncing=false;return end
   local ok,res=invoke('StrikeBegin',{Target=view.Id})
   resyncing=false
   if not self.Active or self.Token~=token then return end
   if ok and type(res)=='table'then syncTargets(res.Targets);hp,maxHP=res.HP or hp,res.MaxHP or maxHP;refreshPanel();return end
   if res=='HW:FAR'or res=='HW:GONE'or res=='HW:NEED_PICKAXE'or res=='HW:NOT_YOURS'or res=='HW:OFF'or res=='HW:DOWNED'then
    if res~='HW:GONE'then Hud.Toast(message(res),U.Colors.red)end
    self.Exit('resync');return
   end
   resync(1)
  end)
 end
 local function candyGain(amount,pos)
  if not amount or amount<=0 then return end
  if pos then FX.Popup(pos+Vector3.new(0,1.2,0),'+'..amount..' 🍬',C3(255,170,60),true)end
  if HAudio then HAudio.Play('CandyTick')end
  fire('CandyGain',{Amount=amount,From=pos,Source='Perfect',Played=true})
 end
 local breakPlayed=false
 local function playBreak(pos,color)
  if breakPlayed then return end
  breakPlayed=true
  local def=pick()
  Audio.Pickaxe('Break',def)
  if HFX then HFX.Shake(1.0,.5);HFX.Flash(color,.22,.35)end
  if Combo then
   local cam=workspace.CurrentCamera
   local p2=cam and pos and cam:WorldToViewportPoint(pos)
   Combo.Break(p2 and Vector2.new(p2.X,p2.Y)or screenSize()/2,color)
  end
  for _,c in pairs(active)do removeCircle(c,color,'hit')end
  local token=self.Token
  task.delay(.85,function()if self.Active and self.Token==token then self.Exit('broke')end end)
 end
 function self.OnResult(item,ok,result)
  if not self.Active or item.Token~=self.Token then return end -- a reply from an earlier session
  local c=item.Circle
  local pos=c.Point and wpos(c.Point) or(view and view.Part and view.Part.CFrame.Position)
  if not ok then
   if result=='HW:FAR'or result=='HW:NEED_PICKAXE'or result=='HW:NOT_YOURS'or result=='HW:OFF'or result=='HW:DOWNED'then Hud.Toast(message(result),U.Colors.red);self.Exit('denied');return end
   if result=='HW:GONE'then self.Exit('gone');return end
   local key=type(result)=='string'and string.sub(result,1,2)=='M:'and Text.Key(result)
   if pos and(key=='TOO_EARLY'or key=='NOT_READY')then FX.Popup(pos,message(result),U.Colors.red)
   elseif key~='SESSION_OVER'and key~='TARGET_GONE'and result~=nil then Hud.Toast(message(result),U.Colors.red)end
   judged[c.Id]=nil
   resync(key and 0 or 1)
   return
  end
  if type(result)~='table'then return end
  if result.Targets then syncTargets(result.Targets)end
  if result.HP then hp,maxHP=result.HP,result.MaxHP or maxHP end
  local msg=result.Message
  if item.Miss or msg=='MISS'or msg=='STALE'then refreshPanel();return end
  if msg=='TOO_LATE'then
   if pos then FX.Popup(pos,Text.Get('TOO_LATE'),U.Colors.red)end
   if Combo then Combo.Miss()end
   refreshPanel();return
  end
  local def=pick()
  local extra=type(result.Extra)=='table'and result.Extra or nil
  if pos then
   if extra and extra.Miss then
    FX.Popup(pos,L('MISS','МИМО'),C3(170,220,255),false)
   elseif result.Crit then
    FX.Popup(pos,Text.Get('CRIT',Text.Short(result.Damage or 0)),C3(255,110,70),true)
    FX.Hit(pos,c.Point and c.Point:GetAttribute('Normal'),targetColor(),view and view.Material or Enum.Material.Slate,tier(),2,true,false,theme())
    Audio.Pickaxe('Crit',def)
    if Combo then
     local cam=workspace.CurrentCamera
     local p2=cam and cam:WorldToViewportPoint(pos)
     local crit=nil
     if Skins and Skins.CritText then local okC,v=pcall(Skins.CritText,theme());if okC then crit=v end end
     local th=theme()
     crit=crit or(th=='Digits'and'67!!'or(th=='Alarm'and'DRRRING!')or(th=='Zombie'and'ZZT!!')or(th=='Clown'and'HA-HA-HA!')or(th=='Ink'and'SPLOOSH!')or nil)
     Combo.Crit(p2 and Vector2.new(p2.X,p2.Y)or screenSize()/2,pickColor(),crit)
    end
    if HFX then HFX.Shake(.9,.4)end
   else
    FX.Popup(pos,'-'..Text.Short(math.max(1,math.floor((result.Damage or 0)+.5))),result.Quality==2 and U.Colors.gold or C3(150,235,255),result.Quality==2)
   end
  end
  -- [WP-P] a weak point took the hit (Boss weak spots and Chapter II weak kinds reply Extra.Weak = true; plates only
  -- carry BossDamage): its own juicy cue (crack + low punch + bright tick) and a short camera kick
  if extra and extra.Weak==true and not extra.Miss then
   Audio.Play('WeakPoint')
   if not reducedMotion()then
    local hc=script.Parent.Parent:FindFirstChild('HalloweenClient')
    local cinemaMod=hc and hc:FindFirstChild('Cinema')
    local okC,Cinema=pcall(function()return cinemaMod and require(cinemaMod)end)
    local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    if okC and Cinema and Cinema.Impulse then Cinema.Impulse(result.Crit and 1.2 or .85,pos and root and(pos-root.Position)or nil)
    elseif HFX and HFX.Punch then HFX.Punch(result.Crit and .9 or .65)end
   end
  end
  candyGain(result.Candy,pos)
  fire('StrikeResult',{Part=view and view.Part,TargetId=view and view.Id,Kind=view and view.Kind,Quality=result.Quality,Crit=result.Crit,Damage=result.Damage,
   HP=result.HP,MaxHP=result.MaxHP,Broke=result.Broke,Candy=result.Candy,Extra=extra,Position=pos})
  refreshPanel()
  if result.Broke then playBreak(pos or(view and view.Part.CFrame.Position),targetColor())end
 end

 -- CAMERA / LOOP --------------------------------------------------------------------------------
 local lastStep=os.clock()
 local function inRange()
  local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
  if not(view and view.Part and view.Part.Parent and root)then return false end
  local range=(view.Part:GetAttribute('Range')or 14)+6
  return(root.Position-view.Part.CFrame.Position).Magnitude<=range
 end
 local function step()
  local cam=workspace.CurrentCamera
  local dt=math.min(.1,os.clock()-lastStep);lastStep=os.clock()
  local now=os.clock()
  if cam and baseFOV and kicking then
   -- hit kick on the player's own camera; held during a perfect-hit pause
   if now>=holdUntil then fovKick=math.max(0,fovKick-dt*22)end
   cam.FieldOfView=baseFOV-fovKick
   if fovKick<=0 then kicking=false end
  end
  blurAmount=math.max(0,blurAmount-dt*60)
  blur.Size=blurAmount;blur.Enabled=blurAmount>.05
  for _,c in pairs(active)do
   if not c.Removed then
    local f=(now-c.LocalSpawn)/c.Window
    if f<0 then c.Frame.Visible=false
    else
     if f>1+.05 and not c.Judged then
      c.Judged=true;judged[c.Id]=true
      if Combo and c.Frame.Visible then Combo.Miss(circleCenter(c))end
      removeCircle(c,Color3.fromRGB(150,150,160),'miss')
      sendHit(c,1,true)
     else
      local att=c.Point
      if not att or not att.Parent then c.Point=pickPoint(c.Jitter);att=c.Point end
      if att and cam then
       local p,onScreen=cam:WorldToViewportPoint(wpos(att))
       local j=c.Jitter or Vector2.zero
       c.Frame.Position=UDim2.fromOffset(p.X+j.X*CIRCLE,p.Y+j.Y*CIRCLE)
       c.Frame.Visible=onScreen
       if onScreen and not c.Shown then
        c.Shown=true;c.PopDoneAt=now+.22
        TweenService:Create(c.Pop,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
       end
      end
      local k=math.min(f,1)
      local s=ringScale(k)
      c.Approach.Size=UDim2.fromScale(s,s)
      local inGold=f>=TM.PerfectFrom and f<=TM.PerfectTo
      local near=math.clamp(1-math.abs(f-MID)/.35,0,1)
      c.ApLine.Thickness=inGold and 6 or 3.5+near*1.5
      c.ApLine.Color=inGold and GOLD_HOT or Color3.new(1,1,1)
      c.ApGlow.Transparency=inGold and .35 or .72-near*.25
      c.ApGlow.Thickness=inGold and 14 or 10
      c.ApGrad.Rotation=(now*160+c.Id*37)%360
      c.Comet.Rotation=(now*(260+near*260)+c.Id*53)%360
      c.Gold.Transparency=inGold and 0 or .15+(1-near)*.25
      c.GoldSoft.Transparency=inGold and .3 or .72-near*.2
      c.GoldSoft.Thickness=inGold and 18+math.sin(now*40)*3 or 12
      for _,tk in ipairs(c.Ticks)do tk.BackgroundColor3=inGold and Color3.new(1,1,1)or GOLD_HOT end
      for i,g in ipairs(c.Glow)do g.Disc.BackgroundTransparency=math.clamp(g.Base-near*.05-(inGold and .04 or 0)+math.sin(now*6+i)*.01,0,1)end
      for i,o in ipairs(c.Sparks)do o.Rotation=(i*120+now*(70+near*160))%360 end
      local beat=math.sin(now*(6+near*16))*.5+.5
      c.CoreScale.Scale=1+beat*(.04+near*.1)+(inGold and .06 or 0)
      c.CoreEdge.Color=inGold and GOLD or c.Color
      if c.Shown and now>=c.PopDoneAt then c.Pop.Scale=inGold and 1.04+math.sin(now*30)*.035 or 1 end
     end
    end
   end
  end
  if now-lastActivity>IDLE_EXIT then self.Exit('idle')
  elseif not breakPlayed and not inRange()then Hud.Toast(message('HW:FAR'),U.Colors.gold);self.Exit('far')end
 end

 -- ENTER / EXIT -----------------------------------------------------------------------------
 local function needPickaxe()
  Hud.Toast(message('HW:NEED_PICKAXE'),U.Colors.gold)
  Audio.Play('Deny')
 end
 local function viewOf(part)
  local points={}
  for _,a in ipairs(part:GetChildren())do if a:IsA('Attachment')and a.Name=='HitPoint'then table.insert(points,a)end end
  local okM,mat=pcall(function()return Enum.Material[part:GetAttribute('Material')or'Slate']end)
  local col=part:GetAttribute('Color')
  return{Part=part,HitPoints=points,Kind=part:GetAttribute('Kind'),Id=part:GetAttribute('TargetId'),Variant=part:GetAttribute('Variant'),
   Color=typeof(col)=='Color3'and col or C3(180,160,140),Material=okM and mat or Enum.Material.Slate}
 end
 function self.Enter(part)
  if self.Active or not enabled()then return end
  if player:GetAttribute('HwDowned')==true then Hud.Toast(message('HW:DOWNED'),U.Colors.red);Audio.Play('Deny');return end -- [WP-B] downed: no strikes
  if not(part and part.Parent and part:GetAttribute('TargetId'))or part:GetAttribute('EndReason')then return end
  if ctx.Mine and ctx.Mine.Active then return end
  if ctx.MenuOpen()then Hud.Toast(L('Close the menu first','Сначала закрой меню'),U.Colors.gold);return end
  if (player:GetAttribute('MiningPickaxe')or 0)<1 then needPickaxe();return end
  local token={};self.Token=token
  self.Active=true;self.Target=part;view=viewOf(part);lastActivity=os.clock();breakPlayed=false
  self.RefreshPrompts()
  local ok,res=invoke('StrikeBegin',{Target=view.Id})
  local current=self.Token==token and self.Active
  if not ok or not current or ctx.MenuOpen()or not part.Parent then
   if current then
    self.Active=false;self.Target=nil;self.Token=nil;view=nil;self.RefreshPrompts()
    if not ok then
     if res=='HW:NEED_PICKAXE'then needPickaxe()elseif res~='HW:GONE'then Hud.Toast(message(res),U.Colors.red);Audio.Play('Deny')end
    end
   end
   if ok and not self.Active then task.spawn(invoke,'StrikeEnd',{})end
   return
  end
  hp,maxHP=tonumber(res.HP)or part:GetAttribute('HP')or 1,tonumber(res.MaxHP)or part:GetAttribute('MaxHP')or 1
  ctx.Main:SetAttribute('MiningActive',true)
  if ctx.Tool and ctx.Tool.Equip then pcall(ctx.Tool.Equip)end
  CAS:BindActionAtPriority(ACTION,function(_,inputState)
   if inputState==Enum.UserInputState.Begin then hitBest()end
   return Enum.ContextActionResult.Sink
  end,false,3000,Enum.KeyCode.Space,Enum.KeyCode.ButtonA,Enum.KeyCode.ButtonR2,Enum.KeyCode.F)
  panel.Visible=part:GetAttribute('Panel')~=false
  overlay.Visible=true;refreshPanel();layout()
  local last=UIS:GetLastInputType()
  local pad=UIS.GamepadEnabled and(last==Enum.UserInputType.Gamepad1 or not UIS.KeyboardEnabled and not UIS.TouchEnabled)
  local touch=UIS.TouchEnabled and(last==Enum.UserInputType.Touch or not UIS.KeyboardEnabled)
  local how=pad and'MINE_HINT_PAD'or touch and'MINE_HINT_TOUCH'or UIS.KeyboardEnabled and'MINE_HINT_KEYS'or'MINE_HINT'
  hint.Text=Text.Get(how)
  Anim.Draw();Anim.SetReady(true,nil,pick().Swing)
  Audio.Pickaxe('Draw',pick())
  if Combo then Combo.Reset()end
  baseFOV=nil;kicking=false
  holdUntil=0;fovKick=0
  RunService:BindToRenderStep('DOGROTS_HalloweenStrike',Enum.RenderPriority.Camera.Value+1,step)
  syncTargets(res.Targets)
  fire('StrikeBegin',{Part=part,TargetId=view.Id,Kind=view.Kind,Variant=view.Variant,Extra=res.Extra})
  table.insert(connections,ctx.Main:GetAttributeChangedSignal('OpenMenu'):Connect(function()
   if ctx.Main:GetAttribute('OpenMenu')~=nil then self.Exit('menu')end
  end))
  table.insert(connections,part:GetAttributeChangedSignal('EndReason'):Connect(function()
   local reason=part:GetAttribute('EndReason')
   if reason=='Broke'then task.delay(.3,function()if self.Active and self.Target==part then playBreak(part.CFrame.Position,targetColor())end end)
   elseif reason then self.Exit('gone')end
  end))
  table.insert(connections,part:GetAttributeChangedSignal('HP'):Connect(function()
   local v=part:GetAttribute('HP');if type(v)=='number'then hp=v;maxHP=part:GetAttribute('MaxHP')or maxHP;refreshPanel()end
  end))
  table.insert(connections,part.AncestryChanged:Connect(function()if not part:IsDescendantOf(workspace)then self.Exit('gone')end end))
  local character=player.Character
  local hum=character and character:FindFirstChildOfClass('Humanoid')
  if hum then table.insert(connections,hum.Died:Connect(function()self.Exit('died')end))end
  table.insert(connections,player.CharacterRemoving:Connect(function()self.Exit('respawn')end))
  table.insert(connections,player:GetAttributeChangedSignal('MiningPickaxe'):Connect(function()refreshPanel();resync(0)end))
  table.insert(connections,UIS.InputBegan:Connect(function(input)
   if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB then self.Exit('escape')end
  end))
 end

 function self.Exit(reason)
  self.Token=nil
  if not self.Active then return end
  local part=view and view.Part
  local info={Part=part,TargetId=view and view.Id,Kind=view and view.Kind,Reason=reason}
  self.Active=false
  RunService:UnbindFromRenderStep('DOGROTS_HalloweenStrike')
  CAS:UnbindAction(ACTION)
  for _,c in ipairs(connections)do c:Disconnect()end
  table.clear(connections)
  for _,c in pairs(active)do removeCircle(c,nil)end
  table.clear(active);table.clear(usedPoints);table.clear(sendQueue);table.clear(judged);resyncing=false
  overlay.Visible=false
  local cam=workspace.CurrentCamera
  if cam and baseFOV and kicking then cam.FieldOfView=baseFOV end
  baseFOV=nil;kicking=false
  blurAmount=0;blur.Size=0;blur.Enabled=false;fovKick=0
  Anim.SetReady(false)
  if Combo then Combo.Reset()end
  ctx.Main:SetAttribute('MiningActive',nil)
  self.Target=nil;view=nil
  self.RefreshPrompts()
  fire('StrikeEnd',info)
  task.spawn(invoke,'StrikeEnd',{})
 end

 -- PROMPTS ------------------------------------------------------------------------------------
 local prompts={} -- part -> ProximityPrompt
 local function promptAllowed(part)
  if self.Active or not enabled()or part:GetAttribute('EndReason')then return false end
  if player:GetAttribute('HwDowned')==true then return false end -- [WP-B] downed: target prompts hidden
  if ctx.Mine and ctx.Mine.Active then return false end
  local owner=part:GetAttribute('OwnerUserId')or 0
  if part:GetAttribute('Shared')==false and owner~=0 and owner~=player.UserId then return false end
  local members=part:GetAttribute('UyMembers') -- [WP-J] a trial's own targets (",uid,uid,"): only its members get the prompt
  if type(members)=='string'and members~=''and not string.find(members,','..player.UserId..',',1,true)then return false end
  return(part:GetAttribute('HP')or 1)>0
 end
 local function styleprompt(prompt,part)
  local verb=VERBS[part:GetAttribute('Verb')or'STRIKE']
  prompt.ActionText=verb and L(verb[1],verb[2])or tostring(part:GetAttribute('Verb')or'')
  prompt.ObjectText=labelOf(part)
  prompt.MaxActivationDistance=part:GetAttribute('Range')or 14
 end
 function self.RefreshPrompts()
  for part,prompt in pairs(prompts)do
   if part.Parent then prompt.Enabled=promptAllowed(part)end
  end
 end
 local function attach(part)
  if prompts[part]or not part:IsA('BasePart')then return end
  local prompt=Instance.new('ProximityPrompt')
  prompt.Name='HalloweenStrikePrompt';prompt.HoldDuration=0;prompt.RequiresLineOfSight=false;prompt.KeyboardKeyCode=Enum.KeyCode.E
  prompt.Style=Enum.ProximityPromptStyle.Default;prompt.Exclusivity=Enum.ProximityPromptExclusivity.OnePerButton
  prompt:SetAttribute('HalloweenTarget',true)
  styleprompt(prompt,part)
  prompt.Enabled=promptAllowed(part)
  prompt.Triggered:Connect(function()self.Enter(part)end)
  prompt.Parent=part
  prompts[part]=prompt
  part:GetAttributeChangedSignal('EndReason'):Connect(function()prompt.Enabled=promptAllowed(part)end)
  part:GetAttributeChangedSignal('HP'):Connect(function()local on=promptAllowed(part);if prompt.Enabled~=on then prompt.Enabled=on end end)
  part:GetAttributeChangedSignal('Verb'):Connect(function()styleprompt(prompt,part)end)
  part:GetAttributeChangedSignal('Label'):Connect(function()styleprompt(prompt,part)end)
 end
 local function detach(part)
  local prompt=prompts[part];prompts[part]=nil
  if prompt then prompt:Destroy()end
  if self.Active and self.Target==part then self.Exit('gone')end
 end
 -- nearest live target in prompt range (pickaxe click)
 local function nearestTarget()
  local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
  if not root then return nil end
  local best,bestD=nil,math.huge
  for part in pairs(prompts)do
   if part.Parent and promptAllowed(part)then
    local d=(part.CFrame.Position-root.Position).Magnitude
    if d<=(part:GetAttribute('Range')or 14)and d<bestD then best,bestD=part,d end
   end
  end
  return best
 end

 -- REMOTE PLAYERS ----------------------------------------------------------------------------
 local function pickaxeHandle(owner)
  local character=owner and owner.Character
  local held=character and character:FindFirstChild('MiningHeldPickaxe')
  local handle=held and held:IsA('Model')and(held.PrimaryPart or held:FindFirstChild('Handle'))
  return(handle and handle:IsA('BasePart'))and handle or nil
 end
 local function targetPart(id)
  for part in pairs(prompts)do if part.Parent and part:GetAttribute('TargetId')==id then return part end end
  return nil
 end
 local function remoteHit(data)
  if type(data)~='table'or data.UserId==player.UserId then return end
  local other=Players:GetPlayerByUserId(data.UserId or 0)
  local part=targetPart(data.TargetId)
  local cam=workspace.CurrentCamera
  if not(other and part and cam)or(cam.CFrame.Position-part.CFrame.Position).Magnitude>90 then return end
  local def=M.Pickaxes[other:GetAttribute('MiningPickaxe')or 1]or M.Pickaxes[1]
  if Skins and Skins.For then local ok,v=pcall(Skins.For,other,def);if ok and v then def=v end end
  Anim.Swing(1+((other:GetAttribute('MiningPickaxe')or 1)-1)*.01,other,def.Swing)
  if PickFX then PickFX.HitPulse(other.Character,1)end
  local att=nil
  for _,a in ipairs(part:GetChildren())do if a.Name=='HitPoint'and a:GetAttribute('Index')==data.Point then att=a end end
  att=att or World.HitPoint({HitPoints=viewOf(part).HitPoints},cam.CFrame.Position)
  local pos=att and wpos(att) or part.CFrame.Position
  local normal=att and att:GetAttribute('Normal')
  local v=viewOf(part)
  FX.Hit(pos,normal,v.Color,v.Material,def.FX or 1,data.Quality or 1,data.Crit==true,true,def.Theme)
  local cue=data.Crit and'Crit'or(data.Quality==2 and'Perfect'or'Hit')
  Audio.Pickaxe(cue,def,part,{Remote=true,Key=part})
  Audio.Pickaxe('Swing',def,pickaxeHandle(other)or part,{Remote=true,Key=part})
  fire('StrikeSwing',{Part=part,TargetId=data.TargetId,Kind=data.Kind,Position=pos,Normal=normal,Perfect=data.Quality==2,Crit=data.Crit,
   Remote=true,UserId=data.UserId,Miss=data.Miss,HitStop=0})
 end

 -- START (after the Halloween modules replicate) ------------------------------------------------
 task.spawn(function()
  local Halloween=RS:WaitForChild('Halloween',60)
  if not Halloween then return end
  local okS,S=pcall(function()return require(Halloween:WaitForChild('Shared'))end)
  if not okS or not S.Config.HalloweenEventEnabled then return end
  Shared=S
  Bus=require(Halloween:WaitForChild('Bus'))
  pcall(function()HFX=require(Halloween:WaitForChild('FX'))end)
  pcall(function()HAudio=require(Halloween:WaitForChild('Audio'))end)
  Remotes=Halloween:WaitForChild('Remotes')
  task.spawn(function()
   local mod=Halloween:WaitForChild('PickaxeSkins',30)
   if mod then local ok,res=pcall(require,mod);if ok then Skins=res end end
  end)
  local signal=Remotes:WaitForChild('Signal')
  signal.OnClientEvent:Connect(function(kind,data)
   if kind=='StrikeFx'then remoteHit(data)
   elseif kind=='TargetBroke'and type(data)=='table'and self.Active and view and data.TargetId==view.Id and data.UserId~=player.UserId then
    playBreak(view.Part.CFrame.Position,targetColor())
   end
  end)
  -- [WP-B] Event HP: becoming DOWNED ends the session at once and hides every target prompt until revived
  player:GetAttributeChangedSignal('HwDowned'):Connect(function()
   if player:GetAttribute('HwDowned')==true and self.Active then self.Exit('downed')end
   self.RefreshPrompts()
  end)
  for _,part in ipairs(CollectionService:GetTagged(TAG))do attach(part)end
  CollectionService:GetInstanceAddedSignal(TAG):Connect(attach)
  CollectionService:GetInstanceRemovedSignal(TAG):Connect(detach)
  -- the event switch / Mine sessions toggle every prompt
  task.spawn(function()
   local mineWas=nil
   while true do
    task.wait(.5)
    local mine=ctx.Mine and ctx.Mine.Active or false
    if mine~=mineWas then mineWas=mine;self.RefreshPrompts()end
    if self.Active and not enabled()then self.Exit('off')end
    for part in pairs(prompts)do if not part:IsDescendantOf(workspace)then detach(part)end end
   end
  end)
  -- clicking with the pickaxe next to a target starts a session (like next to your own ore)
  local wired=setmetatable({},{__mode='k'})
  local function wire(tool)
   if wired[tool]or not(tool:IsA('Tool')and tool:GetAttribute('MiningPickaxeTool')==true)then return end
   wired[tool]=true
   tool.Activated:Connect(function()
    if self.Active or(ctx.Mine and ctx.Mine.Active)or ctx.MenuOpen()then return end
    local part=nearestTarget()
    if part then task.delay(.25,function()if not self.Active then self.Enter(part)end end)end
   end)
  end
  local function watch(holder)
   if not holder then return end
   for _,c in ipairs(holder:GetChildren())do wire(c)end
   holder.ChildAdded:Connect(function(c)task.defer(wire,c)end)
  end
  local function onCharacter(character)
   watch(character)
   task.spawn(function()watch(player:WaitForChild('Backpack',10))end)
  end
  if player.Character then onCharacter(player.Character)end
  player.CharacterAdded:Connect(onCharacter)
 end)

 return self
end

return Strike
