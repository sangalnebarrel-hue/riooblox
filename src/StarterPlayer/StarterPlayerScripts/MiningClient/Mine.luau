-- Active Mining session for the local owner: walk to the ore, frame the camera, show the
-- server-issued timing circles ON the ore pile, judge clicks/taps, swing the pickaxe and play
-- predicted effects instantly, then apply the server's verdict (coins, crits, breaks).
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local TweenService=game:GetService('TweenService')
local Mine={}

local CIRCLE_MAX=118 -- px, outer ring at the moment a circle opens (shrinks on small screens)
local IDLE_EXIT=22 -- seconds without a hit before the session closes itself

function Mine.new(ctx)
 local self:any={Active=false,Corner=nil}
 local player=ctx.Player
 local M,Text,Audio,U=ctx.M,ctx.Text,ctx.Audio,ctx.U
 local Net,World,FX,Hud,Anim=ctx.Net,ctx.World,ctx.FX,ctx.Hud,ctx.Anim
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
 local comboLabel=text(panel,'Combo',270,60,154,26,18,U.Colors.gold,Enum.TextXAlignment.Right)

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
 local function pick()return M.Pickaxes[(state and state.PickaxeLevel)or Net.Attr('MiningPickaxe',1)]or M.Pickaxes[1]end
 local function tier()return pick().FX or 1 end

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
  local combo=(os.clock()-lastPaidHit<M.ComboTimeout)and(s.Combo or 0)or 0
  comboLabel.Text=combo>=2 and Text.Get('COMBO',combo)or''
 end

 -- CIRCLES ------------------------------------------------------------------------------------
 local function ring(parent,name,size,color,thickness,z)
  local f=Instance.new('Frame');f.Name=name;f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromScale(size,size)
  f.BackgroundTransparency=1;f.ZIndex=z;f.Parent=parent
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=f
  local s=Instance.new('UIStroke');s.Color=color;s.Thickness=thickness;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=f
  return f,s
 end
 local function ringScale(f)return 1-.75*f end
 local usedPoints={}
 -- A new circle must not cover a live one on screen (a tap would land on the wrong circle), so
 -- hit points whose projection is within ~0.9 circle of a live circle are avoided.
 local function screenPos(cam,att)
  local p,on=cam:WorldToViewportPoint(att.WorldPosition)
  return Vector2.new(p.X,p.Y),on
 end
 local function pickPoint()
  local cam=workspace.CurrentCamera
  if not view then return nil end
  if not cam then return World.HitPoint(view,nil,usedPoints)end
  local live={}
  for _,c in pairs(active)do
   if not c.Removed and c.Point and c.Point.Parent then table.insert(live,(screenPos(cam,c.Point)))end
  end
  local avoid={};local free=0;local fallback,fallbackGap=nil,-1
  for _,att in ipairs(view.HitPoints or{})do
   if att.Parent then
    local p=screenPos(cam,att)
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
 local function removeCircle(c,resultColor)
  if c.Removed then return end
  c.Removed=true
  active[c.Id]=nil
  if c.Point then usedPoints[c.Point]=nil end
  local frame=c.Frame
  if resultColor then
   c.Ring.Color=resultColor;c.Gold.Color=resultColor
   TweenService:Create(frame,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(CIRCLE*1.35,CIRCLE*1.35)}):Play()
   TweenService:Create(c.Back,TweenInfo.new(.18),{BackgroundTransparency=1}):Play()
   TweenService:Create(c.Ring,TweenInfo.new(.18),{Transparency=1}):Play()
   TweenService:Create(c.Gold,TweenInfo.new(.18),{Transparency=1}):Play()
   task.delay(.2,function()frame:Destroy()end)
  else frame:Destroy()end
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
 local function judge(c)
  if c.Removed or c.Judged then return end
  local f=(os.clock()-c.LocalSpawn)/c.Window
  if f<0 then return end
  c.Judged=true;judged[c.Id]=true
  lastActivity=os.clock()
  local pos=c.Point and c.Point.WorldPosition
  if f<TM.GoodFrom then
   removeCircle(c,U.Colors.red)
   if pos then FX.Popup(pos,Text.Get('TOO_EARLY'),U.Colors.red)end
   Audio.Play('Miss')
   sendHit(c,1,true)
   return
  end
  local perfect=f>=TM.PerfectFrom and f<=TM.PerfectTo
  removeCircle(c,perfect and U.Colors.gold or Color3.fromRGB(110,220,255))
  Anim.Swing(1+tier()*.02)
  if pos and view and view.Def then
   local normal=c.Point:GetAttribute('Normal')
   task.delay(.11,function()
    if not self.Active then return end
    FX.Hit(pos,normal,World.OreColor(view.Def),Enum.Material.Slate,tier(),perfect and 2 or 1,false)
    World.Wobble(view,perfect and 1.2 or .8)
   end)
  end
  Audio.Play(perfect and'Perfect'or'Hit',nil,tier())
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
  local c={Id=t.Id,Window=t.Window,LocalSpawn=t.LocalSpawn,Slot=t.Slot}
  c.Point=pickPoint()
  local color=Color3.fromRGB(table.unpack(pick().Color or{110,220,255}))
  local frame=Instance.new('Frame');frame.Name='Circle'..t.Id;frame.AnchorPoint=Vector2.new(.5,.5);frame.Size=UDim2.fromOffset(CIRCLE,CIRCLE)
  frame.BackgroundTransparency=1;frame.Visible=false;frame.ZIndex=math.max(21,1000000-t.Id);frame.Parent=circles
  local back=Instance.new('Frame');back.Name='Back';back.AnchorPoint=Vector2.new(.5,.5);back.Position=UDim2.fromScale(.5,.5);back.Size=UDim2.fromScale(.62,.62)
  back.BackgroundColor3=Color3.fromRGB(23,43,76);back.BackgroundTransparency=.45;back.ZIndex=21;back.Parent=frame
  do local cc=Instance.new('UICorner');cc.CornerRadius=UDim.new(1,0);cc.Parent=back end
  local _,gold=ring(frame,'Gold',ringScale((TM.PerfectFrom+TM.PerfectTo)/2),Color3.fromRGB(255,206,64),7,22)
  local shrink,white=ring(frame,'Ring',1,Color3.new(1,1,1),4,23)
  local dot,dotStroke=ring(frame,'Core',.16,color,3,24)
  dot.BackgroundTransparency=0;dot.BackgroundColor3=color;dotStroke.Color=Color3.new(1,1,1)
  local button=Instance.new('TextButton');button.Name='Hit';button.Text='';button.BackgroundTransparency=1;button.AutoButtonColor=false
  button.AnchorPoint=Vector2.new(.5,.5);button.Position=UDim2.fromScale(.5,.5);button.Size=UDim2.fromScale(1,1);button.ZIndex=25;button.Parent=frame
  button.InputBegan:Connect(function(input)
   if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then judgeAt(input,c)end
  end)
  c.Frame,c.Ring,c.Gold,c.Back,c.Shrink=frame,white,gold,back,shrink
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
  if key=='TOO_LATE'then if pos then FX.Popup(pos,message,U.Colors.red)end;refreshPanel();return end
  if type(s)~='table'then return end
  lastPaidHit=os.clock()
  local payout=s.LastPayout or 0
  if pos then
   if s.LastCrit then
    FX.Popup(pos,Text.Get('CRIT',Text.Short(payout)),Color3.fromRGB(255,110,70),true)
    FX.Hit(pos,c.Point and c.Point:GetAttribute('Normal'),view and view.Def and World.OreColor(view.Def)or Color3.new(1,1,1),Enum.Material.Slate,tier(),2,true)
    Audio.Play('Crit',nil,tier())
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
   local center=(view.Core and view.Core.Position or pos)+Vector3.new(0,4,0)
   local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if root then FX.Coins(center,18,root)end
   FX.Popup(center,'+'..Text.Short(s.LastBrokenValue or payout),U.Colors.gold,true)
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
 local function frameCamera()
  camera=workspace.CurrentCamera;if not camera or not view then return end
  if camera:GetAttribute('SecretZoom')or camera:GetAttribute('DiscoveryZoom')then savedCamera=nil;return end
  savedCamera={Type=camera.CameraType,Subject=camera.CameraSubject,FOV=camera.FieldOfView}
  local core=view.Core
  local orePos=(core:FindFirstChild('OreRoot')and core.OreRoot.WorldPosition or core.Position)+Vector3.new(0,3,0)
  local stand=core:FindFirstChild('MinerStand')
  local away=stand and(stand.WorldPosition-orePos)or(-core.CFrame.LookVector)
  away=Vector3.new(away.X,0,away.Z);away=away.Magnitude>.1 and away.Unit or Vector3.new(0,0,1)
  local side=away:Cross(Vector3.new(0,1,0))
  local goal=CFrame.lookAt(orePos+away*17+side*4+Vector3.new(0,8.5,0),orePos+Vector3.new(0,.5,0))
  camera.CameraType=Enum.CameraType.Scriptable
  self.CameraBase=goal
  local start=camera.CFrame
  local t0=os.clock()
  self.CameraBlend=function()
   local a=math.clamp((os.clock()-t0)/.55,0,1);a=a*a*(3-2*a)
   return start:Lerp(goal,a)
  end
 end
 local function restoreCamera()
  camera=workspace.CurrentCamera
  if camera and savedCamera then
   camera.CameraType=Enum.CameraType.Custom
   local character=player.Character;local hum=character and character:FindFirstChildOfClass('Humanoid')
   camera.CameraSubject=hum or savedCamera.Subject
   camera.FieldOfView=savedCamera.FOV
  end
  savedCamera=nil;self.CameraBlend=nil
 end

 -- MOVEMENT -----------------------------------------------------------------------------------
 local setControls=ctx.SetControls
 local function walkToStand()
  local character=player.Character;local hum=character and character:FindFirstChildOfClass('Humanoid')
  local root=character and character:FindFirstChild('HumanoidRootPart')
  local stand=view and view.Core:FindFirstChild('MinerStand')
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
 local function step()
  local cam=workspace.CurrentCamera
  if self.CameraBlend and cam then
   local base=self.CameraBlend()
   local shake=FX.ShakeAmount
   if shake>.001 then
    base=base*CFrame.new((math.random()-.5)*shake*.6,(math.random()-.5)*shake*.6,0)
    FX.ShakeAmount=math.max(0,shake-.06)
   end
   cam.CFrame=base
  end
  local now=os.clock()
  for _,c in pairs(active)do
   if not c.Removed then
    local f=(now-c.LocalSpawn)/c.Window
    if f<0 then c.Frame.Visible=false
    else
     if f>1+.05 and not c.Judged then
      c.Judged=true;judged[c.Id]=true
      removeCircle(c,Color3.fromRGB(150,150,160))
      sendHit(c,1,true)
     else
      local att=c.Point
      if not att or not att.Parent then c.Point=pickPoint();att=c.Point end
      if att and cam then
       local p,onScreen=cam:WorldToViewportPoint(att.WorldPosition)
       c.Frame.Position=UDim2.fromOffset(p.X,p.Y)
       c.Frame.Visible=onScreen
      end
      local s=ringScale(math.min(f,1))
      c.Shrink.Size=UDim2.fromScale(s,s)
      local inGold=f>=TM.PerfectFrom and f<=TM.PerfectTo
      c.Ring.Color=inGold and Color3.fromRGB(255,240,160)or Color3.new(1,1,1)
      c.Ring.Thickness=inGold and 6 or 4
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
  if self.Active or(ctx.Gym and ctx.Gym.Active)then return end
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
    if not ok then Hud.Toast(msg,U.Colors.red);Audio.Play('Deny')end
   end
   -- Close the server session we just opened unless a newer entry already owns it.
   if ok and not self.Active then task.spawn(Net.Invoke,'MiningEnd',{})end
   return
  end
  ctx.Main:SetAttribute('MiningActive',true)
  setControls(false)
  CAS:BindActionAtPriority('DOGROTS_MiningHit',function(_,inputState)
   if inputState==Enum.UserInputState.Begin then hitBest()end
   return Enum.ContextActionResult.Sink
  end,false,3000,Enum.KeyCode.Space,Enum.KeyCode.ButtonA,Enum.KeyCode.ButtonR2,Enum.KeyCode.F)
  overlay.Visible=true;refreshPanel();layout()
  local last=UIS:GetLastInputType()
  local pad=UIS.GamepadEnabled and(last==Enum.UserInputType.Gamepad1 or not UIS.KeyboardEnabled and not UIS.TouchEnabled)
  local touch=UIS.TouchEnabled and(last==Enum.UserInputType.Touch or not UIS.KeyboardEnabled)
  local how=pad and'MINE_HINT_PAD'or touch and'MINE_HINT_TOUCH'or UIS.KeyboardEnabled and'MINE_HINT_KEYS'or'MINE_HINT'
  hint.Text=Text.Get(how)
  Audio.Play('Whoosh')
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
  restoreCamera()
  setControls(true)
  ctx.Main:SetAttribute('MiningActive',nil)
  self.Corner=nil;view=nil
  World.RefreshPrompts()
  task.spawn(function()Net.Invoke('MiningEnd',{})end)
 end

 return self
end

return Mine
