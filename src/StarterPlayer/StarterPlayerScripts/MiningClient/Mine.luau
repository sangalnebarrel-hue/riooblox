-- Active Mining session for the local owner: walk to the ore, frame the camera, show the
-- server-issued timing circles ON the ore piles (the main pile and its satellites, so they are
-- scattered over the dig site), judge clicks/taps, swing the pickaxe and play predicted effects
-- instantly (MiningClient.Combo: shockwave + endless "xN" combo, PickFX: the pickaxe's own hit),
-- then apply the server's verdict (coins, crits, breaks). The camera orbits the dig site:
-- right mouse drag / one-finger swipe / right stick / Z-C, mouse wheel or pinch to zoom, R resets.
-- Circles (v2): a soft glowing target with a GOLD zone and a glowing approach ring that closes onto
-- it (a comet runs along the ring, the core beats faster as the gold window nears). A hit bursts
-- into a flash, speed lines and a ring blast, the world blurs for a blink and the camera kicks;
-- the miner turns to the struck outcrop and swings the pickaxe in the hand (the Tool is drawn
-- when the session starts), and far outcrops are reached by a ground shockwave in the pickaxe's
-- colours. While mining, the background is softly out of focus.
local Players=game:GetService('Players')
local Lighting=game:GetService('Lighting')
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local TweenService=game:GetService('TweenService')
local Mine={}
local Skins=(function()local ok,m=pcall(function()return require(game:GetService('ReplicatedStorage'):WaitForChild('Halloween',10):WaitForChild('PickaxeSkins',10))end);if ok and type(m)=='table'then return m end;return{For=function(_,d)return d end,CritText=function()return nil end}end)() -- Halloween pickaxe skins (cosmetic visual def)

local CIRCLE_MAX=118 -- px, outer ring at the moment a circle opens (shrinks on small screens)
local JITTER=.42 -- circles land up to this many circle sizes away from their hit point (random)
local IDLE_EXIT=22 -- seconds without a hit before the session closes itself
local HIT_SOUND_DELAY=.11 -- the strike sound lands with FX.Hit (the swing whoosh plays on the click)

function Mine.new(ctx)
 local self:any={Active=false,Corner=nil}
 local player=ctx.Player
 local M,Text,Audio,U=ctx.M,ctx.Text,ctx.Audio,ctx.U
 local Net,World,FX,Hud,Anim=ctx.Net,ctx.World,ctx.FX,ctx.Hud,ctx.Anim
 local Combo,PickFX=ctx.Combo,ctx.PickFX
 local TM=M.Timing
 local CIRCLE=CIRCLE_MAX
 local gui=ctx.Gui::ScreenGui
 gui.IgnoreGuiInset=true
 pcall(function()gui.ScreenInsets=Enum.ScreenInsets.None end)
 local font=U.FontFace or Font.fromEnum(Enum.Font.FredokaOne)

 -- OVERLAY ------------------------------------------------------------------------------------
 local overlay=Instance.new('Frame');overlay.Name='MiningSession';overlay.Size=UDim2.fromScale(1,1);overlay.BackgroundTransparency=1
 overlay.Visible=false;overlay.ZIndex=10;overlay.Parent=gui
 -- Frees the cursor from shift-lock while mining.
 local modal=Instance.new('TextButton');modal.Name='CursorRelease';modal.Size=UDim2.fromOffset(1,1);modal.BackgroundTransparency=1;modal.Text=''
 modal.Modal=true;modal.Parent=overlay
 local circles=Instance.new('Frame');circles.Name='Circles';circles.Size=UDim2.fromScale(1,1);circles.BackgroundTransparency=1;circles.ZIndex=20;circles.Parent=overlay

 local panel=Instance.new('Frame');panel.Name='OrePanel';panel.AnchorPoint=Vector2.new(.5,0);panel.Position=UDim2.new(.5,0,0,58)
 panel.Size=UDim2.fromOffset(440,92);panel.BackgroundColor3=Color3.fromRGB(255,251,242);panel.BorderSizePixel=0;panel.ZIndex=30;panel.Parent=overlay
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,14);c.Parent=panel
  local s=Instance.new('UIStroke');s.Color=U.Colors.edge;s.Thickness=3;s.Parent=panel end
 local function text(parent,name,x,y,w,h,size,color,align)
  local l=Instance.new('TextLabel');l.Name=name;l.BackgroundTransparency=1;l.Position=UDim2.fromOffset(x,y);l.Size=UDim2.fromOffset(w,h)
  l.FontFace=font;l.TextSize=size;l.TextColor3=color or U.Colors.text;l.TextXAlignment=align or Enum.TextXAlignment.Left
  l.TextTruncate=Enum.TextTruncate.AtEnd;l.ZIndex=31;l.Text='';l.Parent=parent;return l
 end
 local oreTitle=text(panel,'OreTitle',16,8,300,28,24)
 oreTitle.TextScaled=true;oreTitle.TextTruncate=Enum.TextTruncate.None
 do local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=24;limit.MinTextSize=13;limit.Parent=oreTitle end
 local rarity=text(panel,'Rarity',300,10,124,24,16,U.Colors.muted,Enum.TextXAlignment.Right)
 local hpBack=Instance.new('Frame');hpBack.Name='HP';hpBack.Position=UDim2.fromOffset(16,40);hpBack.Size=UDim2.new(1,-32,0,16)
 hpBack.BackgroundColor3=Color3.fromRGB(23,43,76);hpBack.BorderSizePixel=0;hpBack.ZIndex=31;hpBack.Parent=panel
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=hpBack end
 local hpFill=Instance.new('Frame');hpFill.Name='Fill';hpFill.Size=UDim2.fromScale(1,1);hpFill.BorderSizePixel=0;hpFill.BackgroundColor3=U.Colors.green;hpFill.ZIndex=32;hpFill.Parent=hpBack
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=hpFill end
 local hpText=text(hpBack,'HPText',0,0,0,0,13,Color3.new(1,1,1),Enum.TextXAlignment.Center);hpText.Size=UDim2.fromScale(1,1);hpText.ZIndex=33
 local infoLeft=text(panel,'Info',16,60,260,26,15,U.Colors.muted)
 -- Pickaxe · worth · stone of this ore: long RU names shrink instead of being cut.
 infoLeft.TextScaled=true;infoLeft.TextTruncate=Enum.TextTruncate.None
 do local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=15;limit.MinTextSize=10;limit.Parent=infoLeft end
 local comboLabel=text(panel,'Combo',270,60,154,26,18,U.Colors.gold,Enum.TextXAlignment.Right)
 -- Stored Stone (player attribute "Stone", projected by Economy.Runtime) under the panel's right edge.
 local STONE_COLOR=Color3.fromRGB(176,170,160)
 local stonePill=Instance.new('TextLabel');stonePill.Name='Stone';stonePill.AnchorPoint=Vector2.new(1,0)
 stonePill.Position=UDim2.new(1,-12,1,4);stonePill.Size=UDim2.fromOffset(112,26);stonePill.BackgroundColor3=Color3.fromRGB(255,251,242)
 stonePill.BorderSizePixel=0;stonePill.FontFace=font;stonePill.TextScaled=true;stonePill.TextColor3=U.Colors.text;stonePill.Text=''
 stonePill.ZIndex=31;stonePill.Parent=panel
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=stonePill
  local s=Instance.new('UIStroke');s.Color=STONE_COLOR:Lerp(U.Colors.edge,.5);s.Thickness=2;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=stonePill
  local p=Instance.new('UIPadding');p.PaddingLeft=UDim.new(0,8);p.PaddingRight=UDim.new(0,8);p.PaddingTop=UDim.new(0,3);p.PaddingBottom=UDim.new(0,3);p.Parent=stonePill
  local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=17;limit.Parent=stonePill end
 local function reducedMotion()
  if FX.ReducedMotion and FX.ReducedMotion()then return true end
  local ok,v=pcall(function()return(game:GetService('GuiService')::any).ReducedMotionEnabled end)
  return ok and v==true
 end
 local stoneShown=nil
 local function showStone(total)
  total=math.max(0,math.floor(tonumber(total)or tonumber(Net.Attr('Stone',0))or 0))
  stonePill.Text='🪨 '..Text.Short(total)
  if stoneShown and total>stoneShown and self.Active and not reducedMotion()then
   stonePill.Size=UDim2.fromOffset(124,30)
   TweenService:Create(stonePill,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(112,26)}):Play()
  end
  stoneShown=total
 end

 local hint=text(overlay,'Hint',0,0,0,0,20,Color3.new(1,1,1),Enum.TextXAlignment.Center)
 hint.AnchorPoint=Vector2.new(.5,1);hint.Position=UDim2.new(.5,0,1,-86);hint.Size=UDim2.fromOffset(620,30);hint.TextStrokeTransparency=0
 hint.TextScaled=true;hint.TextTruncate=Enum.TextTruncate.None
 do local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=20;limit.MinTextSize=11;limit.Parent=hint end
 hint.TextStrokeColor3=U.Colors.edge;hint.ZIndex=30
 local exitButton=U.Button(overlay,'Exit',Text.Get('EXIT'),0,0,150,48,function()self.Exit('button')end,U.Colors.red)
 exitButton.AnchorPoint=Vector2.new(.5,1);exitButton.Position=UDim2.new(.5,0,1,-24);exitButton.ZIndex=40
 for _,d in ipairs(exitButton:GetDescendants())do if d:IsA('GuiObject')then d.ZIndex=41 end end

 local function layout()
  local size=gui.AbsoluteSize
  panel.Size=UDim2.fromOffset(math.clamp(size.X-24,300,460),92)
  rarity.Position=UDim2.fromOffset(panel.Size.X.Offset-140,10)
  comboLabel.Position=UDim2.fromOffset(panel.Size.X.Offset-170,60)
  local top=UIS.TouchEnabled and 46 or 58
  panel.Position=UDim2.new(.5,0,0,top)
  CIRCLE=math.clamp(math.floor(math.min(size.X,size.Y)*.22),72,CIRCLE_MAX)
  hint.Size=UDim2.fromOffset(math.min(size.X-24,640),30)
 end
 gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(layout);layout()

 -- STATE ------------------------------------------------------------------------------------
 local view,camera,savedCamera=nil,nil,nil
 local active={} -- target id -> circle
 local lastActivity=0
 local sendQueue,sending,lastSent={},false,0
 local state=nil
 local connections={}
 local resyncing=false
 -- Ids the player already judged. A response built before the server processed that hit still
 -- lists the target; it must not come back as a fresh circle. Server ids only increase.
 local judged={}

 local lastPaidHit=0
 local function pick()return Skins.For(player,M.Pickaxes[(state and state.PickaxeLevel)or Net.Attr('MiningPickaxe',1)]or M.Pickaxes[1])end
 local function tier()return pick().FX or 1 end
 local function theme()return pick().Theme or'Wood'end
 local function pickColor()return Color3.fromRGB(table.unpack(pick().Color or{110,220,255}))end

 -- Short news in the panel title (break, new ore) instead of a toast over the ore and circles.
 local bannerUntil=0
 local function banner(text,color,seconds)
  bannerUntil=os.clock()+(seconds or 1.5)
  oreTitle.Text=text;oreTitle.TextColor3=color
 end
 local function refreshPanel()
  local s=state or Net.State()
  local def=World.OreDef(s.OreId)
  local hp=s.OreHP or def.HP;local max=math.max(1,s.OreMaxHP or def.HP)
  if os.clock()>=bannerUntil then
   oreTitle.Text=(def.Icon or'')..' '..Text.Name(def)
   oreTitle.TextColor3=World.OreColor(def):Lerp(U.Colors.text,.35)
  end
  rarity.Text=Text.IsRussian()and(def.RarityRU or def.Rarity or'')or(def.Rarity or'')
  hpFill.Size=UDim2.fromScale(math.clamp(hp/max,0,1),1)
  hpFill.BackgroundColor3=hp/max<.3 and U.Colors.red or hp/max<.6 and U.Colors.gold or U.Colors.green
  hpText.Text=Text.Get('HP',hp,max)
  local p=pick()
  local worth=math.floor((s.OreValue or 0)*(1+(p.CoinBonus or 0))+.5) -- what the server pays (MiningRules.Hit)
  infoLeft.Text=(p.Icon or'⛏')..' '..Text.Name(p)..'  ·  '..Text.Get('ORE_VALUE',Text.Short(worth))
  -- Stone this ore stores when broken (MiningRules.StoneForBreak, deepest unlocked layer).
  local stone=ctx.Rules.StoneForBreak(M,def,Net.Attr('MiningLayer',1))
  if stone>0 then infoLeft.Text..='  ·  '..Text.Get('ORE_STONE',stone)end
  -- The panel shows the damage streak the server counts (perfect hits, capped); the endless
  -- click combo lives on the right (MiningClient.Combo).
  local combo=(os.clock()-lastPaidHit<M.ComboTimeout)and(s.Combo or 0)or 0
  comboLabel.Text=combo>=2 and('⚡ '..Text.Get('COMBO',combo))or''
 end

 -- CIRCLES ------------------------------------------------------------------------------------
 local C3=Color3.fromRGB
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
 -- Blur blink + FOV kick on hits (the world only; the GUI stays sharp).
 local blur=Lighting:FindFirstChild('DOGROTS_MiningBlur')
 if not blur then blur=Instance.new('BlurEffect');blur.Name='DOGROTS_MiningBlur';blur.Size=0;blur.Enabled=false;blur.Parent=Lighting end
 local focus=Lighting:FindFirstChild('DOGROTS_MiningFocus')
 if not focus then
  focus=Instance.new('DepthOfFieldEffect');focus.Name='DOGROTS_MiningFocus';focus.Enabled=false
  focus.FarIntensity=.32;focus.NearIntensity=0;focus.InFocusRadius=16;focus.FocusDistance=24;focus.Parent=Lighting
 end
 local blurAmount,fovKick=0,0
 function self.Kick(strength)
  if reducedMotion()then return end
  blurAmount=math.max(blurAmount,8*strength)
  fovKick=math.max(fovKick,3.2*strength)
 end
 local usedPoints={}
 -- A new circle must not cover a live one on screen (a tap would land on the wrong circle), so
 -- hit points whose projection is within ~0.9 circle of a live circle are avoided.
 local function screenPos(cam,att)
  local p,on=cam:WorldToViewportPoint(att.WorldPosition)
  return Vector2.new(p.X,p.Y),on
 end
 -- Circles are drawn jittered off their points, so drawn centres (point + jitter) are compared.
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
 -- Speed lines and a flash where a circle was hit (2D, over the circle).
 local function burst2D(center,color,perfect)
  if reducedMotion()then return end
  local size=CIRCLE*(perfect and 2.6 or 1.9)
  local flash=disc(circles,'HitFlash',1,Color3.new(1,1,1),.05,90)
  flash.Size=UDim2.fromOffset(CIRCLE*.4,CIRCLE*.4);flash.Position=UDim2.fromOffset(center.X,center.Y)
  TweenService:Create(flash,TweenInfo.new(.28,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(size*.62,size*.62),BackgroundTransparency=1}):Play()
  game:GetService('Debris'):AddItem(flash,.32)
  local blast,stroke=ring(circles,'HitBlast',1,perfect and GOLD_HOT or color,perfect and 10 or 7,91)
  blast.Size=UDim2.fromOffset(CIRCLE*.6,CIRCLE*.6);blast.Position=UDim2.fromOffset(center.X,center.Y)
  TweenService:Create(blast,TweenInfo.new(.36,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(size,size)}):Play()
  TweenService:Create(stroke,TweenInfo.new(.36,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Transparency=1,Thickness=1}):Play()
  game:GetService('Debris'):AddItem(blast,.4)
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
   game:GetService('Debris'):AddItem(line,.3)
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
   -- a crack and a shake, then it drops away
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
  else -- missed / closed: sinks and greys out
   TweenService:Create(c.Pop,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.72}):Play()
  end
  task.delay(.26,function()frame:Destroy()end)
 end
 local function sendHit(c,quality,miss)
  table.insert(sendQueue,{Circle=c,Quality=quality,Miss=miss})
  if sending then return end
  sending=true
  task.spawn(function()
   while #sendQueue>0 and self.Active do
    local item=table.remove(sendQueue,1)
    local wait=(M.MinHitGap+.02)-(os.clock()-lastSent)
    if wait>0 then task.wait(wait)end
    lastSent=os.clock()
    task.spawn(function()self.OnResult(item,Net.Invoke('MiningHit',{Target=item.Circle.Id,Quality=item.Quality,Miss=item.Miss}))end)
   end
   sending=false
  end)
 end
 -- Player clicked circle c at the current time.
 local function circleCenter(c)
  return c.Frame.AbsolutePosition+c.Frame.AbsoluteSize/2
 end
-- The miner turns to the struck point (yaw only) so every swing lands where the circle was.
 local function faceTowards(pos)
  local character=player.Character;local root=character and character:FindFirstChild('HumanoidRootPart')
  if not(root and root:IsA('BasePart')and pos)then return nil end
  local flat=Vector3.new(pos.X,root.Position.Y,pos.Z)
  if(flat-root.Position).Magnitude<.5 then return root end
  root.CFrame=CFrame.lookAt(root.Position,flat)
  return root
 end
 -- A ground shockwave in the pickaxe's colours from the miner's feet to an outcrop out of reach.
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
  game:GetService('Debris'):AddItem(head,t+.4)
 end
 local function judge(c)
  if c.Removed or c.Judged then return end
  local f=(os.clock()-c.LocalSpawn)/c.Window
  if f<0 then return end
  c.Judged=true;judged[c.Id]=true
  lastActivity=os.clock()
  local pos=c.Point and c.Point.WorldPosition
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
  -- Turn to the outcrop, swing the pickaxe in the hand, then the strike lands (.11 s: the swing's
  -- downstroke) with the pickaxe's own effect; far outcrops get a ground shockwave.
  local root=pos and faceTowards(pos)
  Anim.Swing(1+tier()*.02,nil,def.Swing)
  Audio.Pickaxe('Swing',def)
  local n=1
  if Combo then n=Combo.Hit(screen,perfect and 2 or 1,color)end
  FX.Shake((perfect and .55 or .35)+math.min(.9,n*.025))
  if PickFX then PickFX.HitPulse(player.Character,perfect and 1 or .7)end
  if def.Theme=='TV'and Combo then Combo.Glitch()end
  if pos and view and view.Def then
   local normal=c.Point:GetAttribute('Normal')
   local point=c.Point
   local palette=PickFX and PickFX.Palette(theme())or{color}
   task.delay(.05,function()if self.Active then strikeWave(root,pos,palette,perfect)end end)
   task.delay(.11,function()
    if not self.Active then return end
    FX.Hit(pos,normal,World.OreColor(view.Def),Enum.Material.Slate,tier(),perfect and 2 or 1,false,false,theme())
    World.Wobble(view,perfect and 1.2 or .8,point)
   end)
  end
  -- The pickaxe's own strike (its sound kit, MiningAudio) with the strike effect above.
  task.delay(HIT_SOUND_DELAY,function()if self.Active then Audio.Pickaxe(perfect and'Perfect'or'Hit',def,nil,{Combo=n})end end)
  sendHit(c,perfect and 2 or 1,false)
 end
 -- Overlapping circles: one tap may reach several buttons. Resolve it once, preferring a circle
 -- that is past "too early" and closest to its gold ring, then the circle nearest the tap.
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
  -- A random screen offset from the hit point: circles never sit on a fixed grid. Chosen before
  -- the point so pickPoint keeps the drawn circle clear of the live ones.
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
  -- 1 soft glow: stacked translucent discs fake a radial bloom in the pickaxe's colour
  c.Glow={}
  for i,g in ipairs({{1.34,.93},{1.18,.88},{1.04,.84}})do
   local d=keep(disc(frame,'Glow'..i,g[1],color,g[2],z));table.insert(c.Glow,{Disc=d,Base=g[2],Size=g[1]})
  end
  -- 2 the plate: a dark glass disc with a lighter top and an inner tinted well
  local plate=keep(disc(frame,'Plate',.84,INK,.32,z+1))
  local pg=Instance.new('UIGradient');pg.Color=ColorSequence.new(color:Lerp(Color3.new(1,1,1),.25),INK);pg.Rotation=90;pg.Parent=plate
  local well=keep(disc(frame,'Well',.6,color:Lerp(INK,.45),.35,z+2))
  local wg=Instance.new('UIGradient');wg.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,.6)});wg.Rotation=90;wg.Parent=well
  keepRing(ring(frame,'PlateEdge',.84,color:Lerp(Color3.new(1,1,1),.5),2,z+2,.35))
  -- 3 the GOLD zone at the perfect radius: soft band + crisp line + four ticks
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
  -- 4 the approach ring: glow + bright line in the pickaxe's palette, a comet running along it
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
  -- 5 orbiting sparkles
  c.Sparks={}
  for i=1,3 do
   local orbit=Instance.new('Frame');orbit.Name='Orbit';orbit.AnchorPoint=Vector2.new(.5,.5);orbit.Position=UDim2.fromScale(.5,.5)
   orbit.Size=UDim2.fromScale(.72,.72);orbit.BackgroundTransparency=1;orbit.ZIndex=z+3;orbit.Rotation=i*120;orbit.Parent=frame
   local dot=disc(orbit,'Spark',.07,palette[(i-1)%#palette+1]:Lerp(Color3.new(1,1,1),.3),.1,z+3);dot.Position=UDim2.fromScale(.5,0);keep(dot)
   table.insert(c.Sparks,orbit)
  end
  -- 6 the core: a bright pill that beats faster as the gold window nears, with the pickaxe icon
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
 local function syncTargets(list)
  if not self.Active then return end
  local live={}
  for _,t in ipairs(list)do live[t.Id]=true;makeCircle(t)end
  for id,c in pairs(active)do if not live[id]and not c.Judged then removeCircle(c,nil)end end
  for id in pairs(judged)do if not live[id]then judged[id]=nil end end
 end
 Net.OnTargets=function(list)syncTargets(list)end

 -- Keyboard / gamepad: hit the circle closest to its gold ring.
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
 -- Ask the server for its live circles. Only a real dead end (too far away, no pickaxe) ends
 -- the session; transient failures (rate limit, busy profile, connection) retry a second later.
 local function resync(delay)
  if resyncing or not self.Active then return end
  resyncing=true
  task.delay(delay or 0,function()
   if not self.Active then resyncing=false;return end
   local ok,msg,raw=Net.Invoke('MiningBegin',{})
   resyncing=false
   if ok or not self.Active then return end
   if raw=='Stand at your Mining Corner'or Text.Key(raw)=='NEED_PICKAXE'then
    Hud.Toast(msg,U.Colors.red);self.Exit('resync');return
   end
   resync(1)
  end)
 end
 function self.OnResult(item,ok,message,result)
  if not self.Active then return end
  local c=item.Circle
  local pos=c.Point and c.Point.WorldPosition or(view and view.Core and view.Core.Position)
  if not ok then
   if result=='Stand at your Mining Corner'then Hud.Toast(message,U.Colors.red);self.Exit('distance');return end
   local key=type(result)=='string'and Text.Key(result)
   if pos and(key=='TOO_EARLY'or key=='NOT_READY')then FX.Popup(pos,message,U.Colors.red)
   elseif key~='SESSION_OVER'and key~='TARGET_GONE'then Hud.Toast(message,U.Colors.red)end
   -- The server may still hold this circle (or a newer one): ask for the live list. A circle
   -- whose hit failed may come back; non-"M:" failures (rate limit) wait for the bucket first.
   judged[c.Id]=nil
   resync(key and 0 or 1)
   return
  end
  local key=Text.Key(type(result)=='table'and result.Message or nil)
  -- Responses can overtake each other; the server's hit counter orders them.
  local patch=type(result)=='table'and result.StatePatch
  local s=type(patch)=='table'and patch.Mining or(type(result)=='table'and result.MiningState)
  local fresh=type(s)=='table'and(not state or(s.Hits or 0)>=(state.Hits or 0))
  if fresh then state=s end
  if item.Miss or key=='MISS'or key=='STALE'then refreshPanel();return end
  if key=='TOO_LATE'then
   if pos then FX.Popup(pos,message,U.Colors.red)end
   if Combo then Combo.Miss()end
   refreshPanel();return
  end
  if type(s)~='table'then return end
  lastPaidHit=os.clock()
  local payout=s.LastPayout or 0
  if pos then
   if s.LastCrit then
    FX.Popup(pos,Text.Get('CRIT',Text.Short(payout)),Color3.fromRGB(255,110,70),true)
    FX.Hit(pos,c.Point and c.Point:GetAttribute('Normal'),view and view.Def and World.OreColor(view.Def)or Color3.new(1,1,1),Enum.Material.Slate,tier(),2,true,false,theme())
    Audio.Pickaxe('Crit',pick())
    if Combo then
     local cam=workspace.CurrentCamera
     local p2=cam and cam:WorldToViewportPoint(pos)
     Combo.Crit(p2 and Vector2.new(p2.X,p2.Y)or gui.AbsoluteSize/2,pickColor(),theme()=='Digits'and'67!!'or(theme()=='Alarm'and'DRRRING!')or(theme()=='Zombie'and'ZZT!!')or(theme()=='Clown'and'HA-HA-HA!')or(theme()=='Ink'and'SPLOOSH!')or Skins.CritText(theme())or nil)
    end
    FX.Shake(1.1)
   else
    FX.Popup(pos,'+'..Text.Short(payout),s.LastQuality==2 and U.Colors.gold or Color3.fromRGB(150,235,255),s.LastQuality==2)
   end
  end
  if payout>0 then
   Hud.Coins(payout);Audio.Play('Coin',nil,s.Combo)
   local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if pos and root then FX.Coins(pos,math.clamp(math.ceil(math.log10(payout+1)*1.6),1,8),root)end
  end
  if s.LastBreak and view then
   local brokenDef=World.OreDef(s.LastBrokenId)
   World.PlayBreak(view,true,s)
   FX.Shake(1.7)
   if Combo then
    local cam=workspace.CurrentCamera
    local corePos=view.Core and view.Core.Position or pos
    local p2=cam and corePos and cam:WorldToViewportPoint(corePos)
    Combo.Break(p2 and Vector2.new(p2.X,p2.Y)or gui.AbsoluteSize/2,World.OreColor(brokenDef))
   end
   local center=(view.Core and view.Core.Position or pos)+Vector3.new(0,4,0)
   local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if root then FX.Coins(center,18,root)end
   FX.Popup(center,'+'..Text.Short(s.LastBrokenValue or payout),U.Colors.gold,true)
   local stone=math.max(0,math.floor(tonumber(s.LastStone)or 0))
   if stone>0 then
    -- A second, smaller popup under the coins so both stay readable.
    task.delay(.18,function()if self.Active then FX.Popup(center-Vector3.new(0,1.6,0),Text.Get('STONE_GAIN',stone),STONE_COLOR)end end)
    local stored=type(result)=='table'and type(result.Resources)=='table'and tonumber(result.Resources.Stone)
    showStone(stored or(stoneShown or 0)+stone)
    -- First Stone ever: say once what it is for.
    if not self.StoneHintShown and(tonumber(s.StoneMined)or 0)<=stone then
     self.StoneHintShown=true;Hud.Toast(Text.Get('STONE_HINT'),STONE_COLOR:Lerp(U.Colors.text,.5),4.5)
    end
   end
   banner(message,World.OreColor(brokenDef):Lerp(U.Colors.text,.25),M.Client.BreakPause*.6)
   task.delay(M.Client.BreakPause*.6,function()
    if not self.Active then return end
    local newDef,newIndex=World.OreDef(s.OreId)
    if newIndex>=7 then banner(Text.Get('RARE_ORE',Text.Name(newDef)),World.OreColor(newDef),2.5)
    else banner(Text.Get('NEW_ORE',Text.Name(newDef)),U.Colors.text,1.2)end
   end)
  elseif view and fresh then
   World.ApplyState(view,s)
  end
  refreshPanel()
 end

 -- CAMERA -------------------------------------------------------------------------------------
 -- An orbit around the dig site (the main pile and its satellites). The player turns it with the
 -- right mouse button / a swipe on empty screen / the right stick / Z-C, zooms with the wheel or
 -- a pinch, and R puts it back. The orbit never goes under the ground or into the pile.
 -- Z/C rather than Q/E: E is the ProximityPrompt key, and keys are tracked from InputBegan so
 -- typing in chat (processed input) never turns the camera.
 local orbit={Yaw=0,Pitch=0,Zoom=0,TYaw=0,TPitch=0,TZoom=0,Keys={}}
 local ORBIT_LEFT,ORBIT_RIGHT=Enum.KeyCode.Z,Enum.KeyCode.C
 local frameInfo,fovTween=nil,nil
 local function focusPoint()
  local core=view and view.Core;if not core then return nil end
  local sum=(core:FindFirstChild('OreRoot')and core.OreRoot.WorldPosition or core.Position)*2;local n=2
  for _,a in ipairs(core:GetChildren())do
   if a:IsA('Attachment')and string.match(a.Name,'^OreSat%d+$')then sum+=a.WorldPosition;n+=1 end
  end
  return sum/n+Vector3.new(0,2.6,0)
 end
 local function orbitGoal()
  local f=frameInfo;if not f then return nil end
  local yaw=f.Yaw+orbit.Yaw
  local pitch=math.clamp(f.Pitch+orbit.Pitch,math.rad(8),math.rad(72))
  local dist=math.clamp(f.Dist+orbit.Zoom,12,40)
  local flat=Vector3.new(math.sin(yaw),0,math.cos(yaw))
  local eye=f.Focus+flat*math.cos(pitch)*dist+Vector3.new(0,math.sin(pitch)*dist,0)
  return CFrame.lookAt(eye,f.Focus)
 end
 local function frameCamera()
  camera=workspace.CurrentCamera;if not camera or not view then return end
  if camera:GetAttribute('SecretZoom')or camera:GetAttribute('DiscoveryZoom')then savedCamera=nil;return end
  savedCamera={Type=camera.CameraType,Subject=camera.CameraSubject,FOV=camera.FieldOfView}
  local core=view.Core
  local orePos=(core:FindFirstChild('OreRoot')and core.OreRoot.WorldPosition or core.Position)+Vector3.new(0,3,0)
  local stand=core:FindFirstChild('MinerStand')
  local away=stand and(stand.WorldPosition-orePos)or(-core.CFrame.LookVector)
  away=Vector3.new(away.X,0,away.Z);away=away.Magnitude>.1 and away.Unit or Vector3.new(0,0,1)
  -- Behind the miner, a little to the side so the swing is visible, high enough to see every pile.
  local side=away:Cross(Vector3.new(0,1,0))
  local dir=(away+side*.22).Unit
  frameInfo={Focus=focusPoint()or orePos,Yaw=math.atan2(dir.X,dir.Z),Pitch=math.rad(30),Dist=22}
  orbit.Yaw,orbit.Pitch,orbit.Zoom,orbit.TYaw,orbit.TPitch,orbit.TZoom=0,0,0,0,0,0
  camera.CameraType=Enum.CameraType.Scriptable
  local start=camera.CFrame
  local t0=os.clock()
  self.CameraBlend=function()
   local goal=orbitGoal()or start
   local a=math.clamp((os.clock()-t0)/.6,0,1);a=a*a*(3-2*a)
   return start:Lerp(goal,a)
  end
  if fovTween then fovTween:Cancel()end
  fovTween=TweenService:Create(camera,TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{FieldOfView=68})
  local thisTween=fovTween
  thisTween.Completed:Once(function()if fovTween==thisTween then fovTween=nil end end)
  fovTween:Play()
 end
 local function restoreCamera()
  -- A still-running FOV tween would overwrite the restored FOV, so stop it first.
  if fovTween then fovTween:Cancel();fovTween=nil end
  camera=workspace.CurrentCamera
  if camera and savedCamera then
   camera.CameraType=Enum.CameraType.Custom
   local character=player.Character;local hum=character and character:FindFirstChildOfClass('Humanoid')
   camera.CameraSubject=hum or savedCamera.Subject
   camera.FieldOfView=savedCamera.FOV
  end
  savedCamera=nil;self.CameraBlend=nil;frameInfo=nil
 end
 -- Orbit input (bound while a session runs).
 local dragging=false
 local touches={}
 local function orbitBy(dx,dy)
  orbit.TYaw-=dx*.006
  orbit.TPitch=math.clamp(orbit.TPitch+dy*.005,math.rad(-25),math.rad(45))
 end
 local function zoomBy(z)orbit.TZoom=math.clamp(orbit.TZoom+z,-10,18)end
 local function bindOrbit()
  table.insert(connections,UIS.InputBegan:Connect(function(input,processed)
   if input.UserInputType==Enum.UserInputType.MouseButton2 then dragging=true
   elseif input.UserInputType==Enum.UserInputType.Touch and not processed then touches[input]=input.Position
   elseif input.KeyCode==Enum.KeyCode.R and not processed then orbit.TYaw,orbit.TPitch,orbit.TZoom=0,0,0
   elseif (input.KeyCode==ORBIT_LEFT or input.KeyCode==ORBIT_RIGHT)and not processed then orbit.Keys[input.KeyCode]=true end
  end))
  table.insert(connections,UIS.InputEnded:Connect(function(input)
   if input.UserInputType==Enum.UserInputType.MouseButton2 then dragging=false
   elseif input.UserInputType==Enum.UserInputType.Touch then touches[input]=nil
   elseif input.KeyCode==ORBIT_LEFT or input.KeyCode==ORBIT_RIGHT then orbit.Keys[input.KeyCode]=nil end
  end))
  table.insert(connections,UIS.InputChanged:Connect(function(input,processed)
   if input.UserInputType==Enum.UserInputType.MouseMovement and dragging then orbitBy(input.Delta.X,input.Delta.Y)
   elseif input.UserInputType==Enum.UserInputType.MouseWheel and not processed then zoomBy(-input.Position.Z*2.2)
   elseif input.UserInputType==Enum.UserInputType.Touch and touches[input]then
    local count=0;for _ in pairs(touches)do count+=1 end
    local last=touches[input];touches[input]=input.Position
    local d=input.Position-last
    if count==1 then orbitBy(d.X*1.2,d.Y*1.2)
    elseif count==2 then
     -- Pinch: the distance between the two fingers changes.
     local other
     for k,pos in pairs(touches)do if k~=input then other=pos end end
     if other then
      local before=(last-other).Magnitude;local after=(input.Position-other).Magnitude
      zoomBy((before-after)*.06)
     end
    end
   elseif input.KeyCode==Enum.KeyCode.Thumbstick2 then
    local v=input.Position
    if v.Magnitude>.2 then orbit.Stick=Vector2.new(v.X,v.Y)else orbit.Stick=nil end
   end
  end))
 end
 local function updateOrbit(dt)
  if orbit.Keys[ORBIT_LEFT]and UIS:IsKeyDown(ORBIT_LEFT)then orbit.TYaw+=dt*1.6 end
  if orbit.Keys[ORBIT_RIGHT]and UIS:IsKeyDown(ORBIT_RIGHT)then orbit.TYaw-=dt*1.6 end
  if orbit.Stick then orbitBy(orbit.Stick.X*dt*420,-orbit.Stick.Y*dt*300)end
  local k=math.min(1,dt*10)
  orbit.Yaw+=(orbit.TYaw-orbit.Yaw)*k;orbit.Pitch+=(orbit.TPitch-orbit.Pitch)*k;orbit.Zoom+=(orbit.TZoom-orbit.Zoom)*k
 end

 -- MOVEMENT -----------------------------------------------------------------------------------
 local setControls=ctx.SetControls
 local function walkToStand()
  local character=player.Character;local hum=character and character:FindFirstChildOfClass('Humanoid')
  local root=character and character:FindFirstChild('HumanoidRootPart')
  local stand=view and view.Core and view.Core:FindFirstChild('MinerStand')
  if not(hum and root and stand)then return end
  local target=stand.WorldPosition
  local flat=Vector3.new(target.X,root.Position.Y,target.Z)
  if(root.Position-flat).Magnitude>2.5 then
   hum:MoveTo(flat)
   local done=false
   local conn=hum.MoveToFinished:Once(function()done=true end)
   local t=os.clock()
   while not done and os.clock()-t<1.6 and self.Active do task.wait()end
   conn:Disconnect()
  end
  if not self.Active then return end
  local look=view.Core.Position
  root.CFrame=CFrame.lookAt(root.Position,Vector3.new(look.X,root.Position.Y,look.Z))
 end

 -- LOOP ----------------------------------------------------------------------------------------
 local lastStep=os.clock()
 local function step()
  local cam=workspace.CurrentCamera
  local dt=math.min(.1,os.clock()-lastStep);lastStep=os.clock()
  if self.CameraBlend and cam then
   updateOrbit(dt)
   cam.CFrame=self.CameraBlend()*FX.ShakeOffset(dt)
   -- hit kick: a blink of blur and a short FOV punch, both decay fast
   fovKick=math.max(0,fovKick-dt*22)
   if frameInfo and not fovTween then cam.FieldOfView=68-fovKick end
   if view and view.Core then focus.FocusDistance=(cam.CFrame.Position-view.Core.Position).Magnitude end
  end
  blurAmount=math.max(0,blurAmount-dt*60)
  blur.Size=blurAmount;blur.Enabled=blurAmount>.05
  local now=os.clock()
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
       local p,onScreen=cam:WorldToViewportPoint(att.WorldPosition)
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
      local near=math.clamp(1-math.abs(f-MID)/.35,0,1) -- 0 far from the gold window .. 1 inside it
      -- the approach ring heats up as it closes: thicker, warmer, brighter glow
      c.ApLine.Thickness=inGold and 6 or 3.5+near*1.5
      c.ApLine.Color=inGold and GOLD_HOT or Color3.new(1,1,1)
      c.ApGlow.Transparency=inGold and .35 or .72-near*.25
      c.ApGlow.Thickness=inGold and 14 or 10
      c.ApGrad.Rotation=(now*160+c.Id*37)%360
      c.Comet.Rotation=(now*(260+near*260)+c.Id*53)%360
      -- the gold zone breathes and flares when the ring is on it
      c.Gold.Transparency=inGold and 0 or .15+(1-near)*.25
      c.GoldSoft.Transparency=inGold and .3 or .72-near*.2
      c.GoldSoft.Thickness=inGold and 18+math.sin(now*40)*3 or 12
      for _,tk in ipairs(c.Ticks)do tk.BackgroundColor3=inGold and Color3.new(1,1,1)or GOLD_HOT end
      -- glow and sparks
      for i,g in ipairs(c.Glow)do g.Disc.BackgroundTransparency=math.clamp(g.Base-near*.05-(inGold and .04 or 0)+math.sin(now*6+i)*.01,0,1)end
      for i,o in ipairs(c.Sparks)do o.Rotation=(i*120+now*(70+near*160))%360 end
      -- the core's heartbeat speeds up towards the window
      local beat=math.sin(now*(6+near*16))*.5+.5
      c.CoreScale.Scale=1+beat*(.04+near*.1)+(inGold and .06 or 0)
      c.CoreEdge.Color=inGold and GOLD or c.Color
      -- Pulse in the gold window once the pop-in has finished, back to 1 outside it.
      if c.Shown and now>=c.PopDoneAt then c.Pop.Scale=inGold and 1.04+math.sin(now*30)*.035 or 1 end
     end
    end
   end
  end
  if comboLabel.Text~=''and now-lastPaidHit>=M.ComboTimeout then comboLabel.Text=''end
  if bannerUntil>0 and now>=bannerUntil then bannerUntil=0;refreshPanel()end
  if now-lastActivity>IDLE_EXIT then self.Exit('idle')end
 end

 -- ENTER / EXIT -----------------------------------------------------------------------------
 function self.Enter(corner)
  if self.Active then return end
  if ctx.MenuOpen()then Hud.Toast(Text.L('Close the menu first','Сначала закрой меню'),U.Colors.gold);return end
  local s=Net.State()
  if (s.PickaxeLevel or 0)<1 then
   Hud.Toast(Text.Get('NEED_PICKAXE'),U.Colors.gold)
   Audio.Play('Deny')
   if ctx.Shop then ctx.Shop.Open(corner)end
   return
  end
  view=World.View(corner)
  if not view or not view.Core then Hud.Toast(Text.L('Loading the ore…','Руда загружается…'),U.Colors.gold);view=nil;return end
  local token={};self.Token=token
  self.Active=true;self.Corner=corner;state=s;lastActivity=os.clock()
  World.RefreshPrompts()
  local ok,msg=Net.Invoke('MiningBegin',{})
  -- Anything may have happened during the round-trip (a menu opened, the yard changed hands,
  -- Exit ran): only a still-current, still-valid entry may continue.
  local current=self.Token==token and self.Active
  if not ok or not current or ctx.MenuOpen()or not corner:IsDescendantOf(workspace)
   or corner:GetAttribute('OwnerUserId')~=player.UserId then
   if current then
    self.Active=false;self.Corner=nil;self.Token=nil;view=nil;World.RefreshPrompts()
    setControls(true) -- after Active=false: an unlock that saw this entry as busy must still happen
    if not ok then Hud.Toast(msg,U.Colors.red);Audio.Play('Deny')end
   end
   -- Close the server session we just opened unless a newer entry already owns it.
   if ok and not self.Active then task.spawn(Net.Invoke,'MiningEnd',{})end
   return
  end
  ctx.Main:SetAttribute('MiningActive',true)
  -- The pickaxe comes out of the inventory into the hand.
  if ctx.Tool and ctx.Tool.Equip then pcall(ctx.Tool.Equip)end
  if not reducedMotion()then focus.Enabled=true end
  setControls(false)
  CAS:BindActionAtPriority('DOGROTS_MiningHit',function(_,inputState)
   if inputState==Enum.UserInputState.Begin then hitBest()end
   return Enum.ContextActionResult.Sink
  end,false,3000,Enum.KeyCode.Space,Enum.KeyCode.ButtonA,Enum.KeyCode.ButtonR2,Enum.KeyCode.F)
  overlay.Visible=true;refreshPanel();layout()
  stoneShown=nil;showStone()
  table.insert(connections,player:GetAttributeChangedSignal('Stone'):Connect(function()showStone()end))
  local last=UIS:GetLastInputType()
  local pad=UIS.GamepadEnabled and(last==Enum.UserInputType.Gamepad1 or not UIS.KeyboardEnabled and not UIS.TouchEnabled)
  local touch=UIS.TouchEnabled and(last==Enum.UserInputType.Touch or not UIS.KeyboardEnabled)
  local how=pad and'MINE_HINT_PAD'or touch and'MINE_HINT_TOUCH'or UIS.KeyboardEnabled and'MINE_HINT_KEYS'or'MINE_HINT'
  hint.Text=Text.Get(how)..'  ·  '..Text.Get(pad and'CAMERA_HINT_PAD'or touch and'CAMERA_HINT_TOUCH'or'CAMERA_HINT')
  Anim.Draw();Anim.SetReady(true,nil,pick().Swing)
  -- The draw sound goes with the draw animation, always: the pickaxe may already have been in the
  -- hand (click near your ore, the Ore prompt while holding it), so Tool.Equip fired no Equipped.
  -- When it did fire, its Draw and this one are the same kit in the same frame: the kit's Draw
  -- throttle (.6 s per owner) plays exactly one.
  Audio.Pickaxe('Draw',pick())
  if Combo then Combo.Reset()end
  bindOrbit()
  task.spawn(function()
   walkToStand()
   if self.Active then frameCamera()end
  end)
  RunService:BindToRenderStep('DOGROTS_MiningSession',Enum.RenderPriority.Camera.Value+1,step)
  syncTargets(Net.Targets)
  table.insert(connections,ctx.Main:GetAttributeChangedSignal('OpenMenu'):Connect(function()
   if ctx.Main:GetAttribute('OpenMenu')~=nil then self.Exit('menu')end
  end))
  table.insert(connections,corner:GetAttributeChangedSignal('OwnerUserId'):Connect(function()
   if corner:GetAttribute('OwnerUserId')~=player.UserId then self.Exit('owner')end
  end))
  local character=player.Character
  local hum=character and character:FindFirstChildOfClass('Humanoid')
  if hum then table.insert(connections,hum.Died:Connect(function()self.Exit('died')end))end
  table.insert(connections,player.CharacterRemoving:Connect(function()self.Exit('respawn')end))
  table.insert(connections,UIS.InputBegan:Connect(function(input,processed)
   if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB then self.Exit('escape')end
  end))
 end

 function self.Exit(_reason)
  self.Token=nil
  if not self.Active then return end
  self.Active=false
  RunService:UnbindFromRenderStep('DOGROTS_MiningSession')
  CAS:UnbindAction('DOGROTS_MiningHit')
  for _,c in ipairs(connections)do c:Disconnect()end
  table.clear(connections)
  for _,c in pairs(active)do removeCircle(c,nil)end
  table.clear(active);table.clear(usedPoints);table.clear(sendQueue);table.clear(judged)
  overlay.Visible=false
  dragging=false;table.clear(touches);table.clear(orbit.Keys);orbit.Stick=nil
  restoreCamera()
  focus.Enabled=false;blurAmount=0;blur.Size=0;blur.Enabled=false;fovKick=0
  Anim.SetReady(false)
  if Combo then Combo.Reset()end
  setControls(true)
  ctx.Main:SetAttribute('MiningActive',nil)
  self.Corner=nil;view=nil
  World.RefreshPrompts()
  task.spawn(function()Net.Invoke('MiningEnd',{})end)
 end

 return self
end

return Mine
