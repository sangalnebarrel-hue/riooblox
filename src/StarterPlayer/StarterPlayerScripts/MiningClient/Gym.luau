-- Strength training at the weight rack: pick one of 7 weights (the first is free), then tap
-- fast to push it UP against its weight; every completed lift is one rep of Strength.
-- Strength unlocks better pickaxes and adds damage above a pickaxe's requirement.
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local TweenService=game:GetService('TweenService')
local Gym={}

local IDLE_EXIT=30

function Gym.new(ctx)
 local self:any={Active=false,Corner=nil}
 local player=ctx.Player
 local M,Text,Audio,U,Models=ctx.M,ctx.Text,ctx.Audio,ctx.U,ctx.Models
 local Net,FX,Hud,Anim,World=ctx.Net,ctx.FX,ctx.Hud,ctx.Anim,ctx.World
 local font=U.FontFace or Font.fromEnum(Enum.Font.FredokaOne)
 local gui=ctx.Gui::ScreenGui

 -- PANEL --------------------------------------------------------------------------------------
 local overlay=Instance.new('Frame');overlay.Name='Training';overlay.Size=UDim2.fromScale(1,1);overlay.BackgroundTransparency=1
 overlay.Visible=false;overlay.ZIndex=10;overlay.Parent=gui
 local modal=Instance.new('TextButton');modal.Name='CursorRelease';modal.Size=UDim2.fromOffset(1,1);modal.BackgroundTransparency=1;modal.Text='';modal.Modal=true;modal.Parent=overlay
 local panel=Instance.new('Frame');panel.Name='Panel';panel.BackgroundColor3=Color3.fromRGB(255,251,242);panel.BorderSizePixel=0;panel.ZIndex=30;panel.Parent=overlay
 U.Round(panel,16);U.Stroke(panel,U.Colors.edge,3)
 local title=U.Text(panel,'',18,10,300,34,24,U.Colors.text,true)
 local strengthLabel=U.Text(panel,'',18,44,300,30,22,U.Colors.green,true)
 local goalLabel=U.Text(panel,'',18,74,320,20,14,U.Colors.muted)
 local goalBar=Instance.new('Frame');goalBar.Name='Goal';goalBar.Position=UDim2.fromOffset(18,96);goalBar.Size=UDim2.fromOffset(300,10)
 goalBar.BackgroundColor3=Color3.fromRGB(220,226,236);goalBar.BorderSizePixel=0;goalBar.ZIndex=31;goalBar.Parent=panel;U.Round(goalBar,5)
 local goalFill=Instance.new('Frame');goalFill.Size=UDim2.fromScale(0,1);goalFill.BackgroundColor3=U.Colors.green;goalFill.BorderSizePixel=0;goalFill.ZIndex=32;goalFill.Parent=goalBar;U.Round(goalFill,5)
 local rows=Instance.new('ScrollingFrame');rows.Name='Weights';rows.BackgroundTransparency=1;rows.BorderSizePixel=0;rows.ScrollBarThickness=6
 rows.ScrollBarImageColor3=U.Colors.edge;rows.ZIndex=31;rows.Parent=panel
 local exitButton=U.Button(panel,'Exit',Text.Get('EXIT'),0,0,120,40,function()self.Exit('button')end,U.Colors.red)
 local shopButton=U.Button(panel,'Shop','⛏ '..Text.Get('PICKAXES'),0,0,150,40,function()
  local corner=self.Corner;self.Exit('shop');if ctx.Shop and corner then ctx.Shop.Open(corner)end
 end,U.Colors.blue)

 -- Lift meter (centre-bottom): tap the big button to push the weight up.
 local meter=Instance.new('Frame');meter.Name='LiftMeter';meter.AnchorPoint=Vector2.new(.5,1);meter.BackgroundColor3=Color3.fromRGB(23,43,76)
 meter.BackgroundTransparency=.15;meter.BorderSizePixel=0;meter.ZIndex=30;meter.Parent=overlay;U.Round(meter,16);U.Stroke(meter,Color3.new(1,1,1),3)
 local track=Instance.new('Frame');track.Name='Track';track.AnchorPoint=Vector2.new(.5,0);track.Position=UDim2.new(.5,0,0,40);track.Size=UDim2.new(0,46,1,-130)
 track.BackgroundColor3=Color3.fromRGB(45,60,88);track.BorderSizePixel=0;track.ZIndex=31;track.Parent=meter;U.Round(track,12)
 local topLine=Instance.new('Frame');topLine.Name='Top';topLine.AnchorPoint=Vector2.new(.5,.5);topLine.Position=UDim2.fromScale(.5,0);topLine.Size=UDim2.new(1,24,0,6)
 topLine.BackgroundColor3=U.Colors.green;topLine.BorderSizePixel=0;topLine.ZIndex=33;topLine.Parent=track;U.Round(topLine,3)
 local fill=Instance.new('Frame');fill.Name='Fill';fill.AnchorPoint=Vector2.new(0,1);fill.Position=UDim2.fromScale(0,1);fill.Size=UDim2.fromScale(1,0)
 fill.BackgroundColor3=U.Colors.gold;fill.BorderSizePixel=0;fill.ZIndex=32;fill.Parent=track;U.Round(fill,12)
 local weightIcon=Instance.new('TextLabel');weightIcon.Name='Weight';weightIcon.AnchorPoint=Vector2.new(.5,.5);weightIcon.BackgroundTransparency=1
 weightIcon.Size=UDim2.fromOffset(64,64);weightIcon.TextScaled=true;weightIcon.Text='🏋️';weightIcon.ZIndex=34;weightIcon.Parent=track
 local meterTitle=U.Text(meter,'',0,8,0,26,18,Color3.new(1,1,1),true);meterTitle.Size=UDim2.new(1,0,0,26);meterTitle.TextXAlignment=Enum.TextXAlignment.Center
 local liftButton=Instance.new('TextButton');liftButton.Name='Lift';liftButton.AnchorPoint=Vector2.new(.5,1);liftButton.Position=UDim2.new(.5,0,1,-14)
 liftButton.Size=UDim2.new(1,-24,0,64);liftButton.BackgroundColor3=U.Colors.green;liftButton.AutoButtonColor=false;liftButton.Text=Text.Get('LIFT')
 liftButton.FontFace=font;liftButton.TextScaled=true;liftButton.TextColor3=Color3.new(1,1,1);liftButton.ZIndex=35;liftButton.Parent=meter
 U.Round(liftButton,14);U.Stroke(liftButton,U.Colors.edge,3)
 local liftScale=Instance.new('UIScale');liftScale.Parent=liftButton
 local hintLabel=U.Text(overlay,'',0,0,0,26,17,Color3.new(1,1,1),true);hintLabel.TextXAlignment=Enum.TextXAlignment.Center
 hintLabel.TextStrokeTransparency=0;hintLabel.TextStrokeColor3=U.Colors.edge;hintLabel.ZIndex=30

 local compact=false
 local function layout()
  local size=gui.AbsoluteSize
  compact=size.X<760
  local pw=compact and math.min(size.X-16,420)or 360
  local ph=compact and math.min(300,size.Y*.42)or math.min(560,size.Y-140)
  panel.Size=UDim2.fromOffset(pw,ph)
  if compact then panel.AnchorPoint=Vector2.new(.5,0);panel.Position=UDim2.new(.5,0,0,44)
  else panel.AnchorPoint=Vector2.new(1,.5);panel.Position=UDim2.new(1,-16,.5,0)end
  title.Size=UDim2.fromOffset(pw-36,34);strengthLabel.Size=UDim2.fromOffset(pw-36,30);goalLabel.Size=UDim2.fromOffset(pw-36,20)
  goalBar.Size=UDim2.fromOffset(pw-36,10)
  rows.Position=UDim2.fromOffset(10,114);rows.Size=UDim2.fromOffset(pw-20,ph-114-58)
  exitButton.Position=UDim2.fromOffset(pw-134,ph-50);shopButton.Position=UDim2.fromOffset(14,ph-50)
  local mw,mh=compact and 150 or 170,compact and math.min(300,size.Y*.42)or 380
  meter.Size=UDim2.fromOffset(mw,mh)
  if compact then meter.AnchorPoint=Vector2.new(.5,1);meter.Position=UDim2.new(.5,0,1,-16)
  else meter.AnchorPoint=Vector2.new(.5,1);meter.Position=UDim2.new(.5,-80,1,-24)end
  hintLabel.Size=UDim2.fromOffset(math.min(size.X-20,560),26)
  hintLabel.AnchorPoint=Vector2.new(.5,1)
  hintLabel.Position=compact and UDim2.new(.5,0,1,-mh-24)or UDim2.new(.5,-80,1,-mh-34)
 end
 gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if self.Active then layout();self.Render()end end)

 -- STATE --------------------------------------------------------------------------------------
 local height,lastTap,cooldownUntil,lastActivity=0,0,0,0
 local busy,sending=false,false
 local connections={}
 local savedCamera=nil
 local function weightDef()return M.Weights[Net.Attr('MiningWeight',0)]end
 local function nextPickaxe(strength)
  for i,p in ipairs(M.Pickaxes)do if p.Strength>strength then return p,i end end
  return nil
 end

 local function request(action,args,okColor)
  if busy then return false end
  busy=true
  local ok,msg=Net.Invoke(action,args)
  busy=false
  if ok then if okColor then Audio.Play('Buy');Hud.Toast(msg,okColor)end
  else Audio.Play('Deny');Hud.Toast(msg,U.Colors.red)end
  if self.Active then self.Render()end
  return ok
 end

 function self.Render()
  if not self.Active then return end
  local s=Net.State();local cash=Net.Cash()
  title.Text='💪 '..Text.Get('TRAINING')
  strengthLabel.Text=Text.Get('STRENGTH_VALUE',s.Strength)
  local pickDef=M.Pickaxes[s.PickaxeLevel]
  local nextP=nextPickaxe(s.Strength)
  if nextP then
   goalLabel.Text=Text.L('Next: ','Дальше: ')..Text.Name(nextP)..' — '..s.Strength..' / '..nextP.Strength
   goalFill.Size=UDim2.fromScale(math.clamp(s.Strength/math.max(1,nextP.Strength),0,1),1)
  else
   local bonus=pickDef and math.floor((ctx.Rules.StrengthBonus(M,{Strength=s.Strength},pickDef)-1)*100+.5)or 0
   goalLabel.Text=Text.Get('STRENGTH_BONUS',bonus)
   goalFill.Size=UDim2.fromScale(1,1)
  end
  for _,c in ipairs(rows:GetChildren())do c:Destroy()end
  local w=rows.AbsoluteSize.X>0 and rows.AbsoluteSize.X-10 or 330
  local y=0
  for i,def in ipairs(M.Weights)do
   local owned=i<=s.WeightOwned;local selected=i==s.WeightLevel;local nextOne=i==s.WeightOwned+1
   local row=Instance.new('Frame');row.Name='Weight'..i;row.Position=UDim2.fromOffset(0,y);row.Size=UDim2.fromOffset(w,58)
   row.BackgroundColor3=selected and Color3.fromRGB(226,246,214)or Color3.new(1,1,1);row.BorderSizePixel=0;row.ZIndex=32;row.Parent=rows
   U.Round(row,10);U.Stroke(row,selected and U.Colors.green or Color3.fromRGB(205,214,228),2)
   local color=Color3.fromRGB(table.unpack(def.Color))
   local dot=Instance.new('Frame');dot.Size=UDim2.fromOffset(10,40);dot.Position=UDim2.fromOffset(8,9);dot.BackgroundColor3=color;dot.BorderSizePixel=0;dot.ZIndex=33;dot.Parent=row;U.Round(dot,5)
   local nm=U.Text(row,(def.Icon or'')..' '..Text.Name(def),26,4,w-150,26,16,U.Colors.text,true);nm.ZIndex=33
   local sub=U.Text(row,Text.Get('GAIN_PER_REP',def.Gain,def.Cap)..'  ·  💪'..def.Strength,26,30,w-150,22,13,U.Colors.muted);sub.ZIndex=33
   local label,col,fn
   local needS=s.Strength<def.Strength;local needC=cash<def.Price
   if selected then label,col=Text.Get('SELECTED'),U.Colors.blue
   elseif owned then label,col,fn=Text.Get('TAKE'),U.Colors.green,function()request('MiningWeight',{Level=i})end
   elseif not nextOne then label,col=Text.Get('LOCKED'),U.Colors.muted
   elseif needS then label,col,fn=Text.Get('NEED_MORE_STRENGTH'),U.Colors.muted,function()Audio.Play('Deny');Hud.Toast(Text.Get('NEED_STRENGTH',def.Strength),U.Colors.gold)end
   elseif needC then label,col,fn=Text.Short(def.Price),U.Colors.muted,function()Audio.Play('Deny');Hud.Toast(Text.Get('NEED_COINS',Text.Short(def.Price)),U.Colors.gold)end
   else label,col,fn=def.Price==0 and Text.Get('CLAIM')or('💰 '..Text.Short(def.Price)),U.Colors.green,function()request('MiningWeight',{Level=i},U.Colors.green)end end
   local b=U.Button(row,'Action',label,w-118,9,110,40,fn,col);b.ZIndex=34
   for _,d in ipairs(b:GetDescendants())do if d:IsA('GuiObject')then d.ZIndex=35 end end
   y+=64
  end
  rows.CanvasSize=UDim2.fromOffset(0,y)
  local def=weightDef()
  meterTitle.Text=def and((def.Icon or'')..' '..Text.Name(def))or Text.Get('CHOOSE_WEIGHT')
  weightIcon.Text=def and(def.Icon or'🏋️')or'🏋️'
  local capped=def and s.Strength>=def.Cap
  if not def then hintLabel.Text=Text.Get('TUTORIAL_WEIGHT')
  elseif capped then hintLabel.Text=Text.Get('CAP_REACHED',def.Cap)..' · '..Text.Get('NEXT_WEIGHT_HINT')
  else hintLabel.Text=Text.Get('LIFT_HINT')..(UIS.KeyboardEnabled and(' · '..Text.Get('LIFT_HINT_KEY'))or'')end
  liftButton.BackgroundColor3=(def and not capped)and U.Colors.green or U.Colors.muted
 end

 -- LIFTING ------------------------------------------------------------------------------------
 local function tapPower(def,level)return .17-.008*(level-1)end
 local function fallRate(level)return .42+.025*(level-1)end
 local function completeRep()
  local def=weightDef();if not def or sending then return end
  sending=true
  local before=Net.Attr('MiningStrength',0)
  local nextBefore=nextPickaxe(before)
  task.spawn(function()
   local ok,msg=Net.Invoke('MiningTrain',{})
   sending=false
   if not self.Active then return end
   local character=player.Character;local head=character and character:FindFirstChild('Head')
   local pos=head and head.Position+Vector3.new(0,2.2,0)
   if ok then
    local after=(Net.LastState and Net.LastState.Strength)or Net.Attr('MiningStrength',0)
    if pos then FX.Popup(pos,'+'..math.max(0,after-before)..' 💪',U.Colors.green,true)
     FX.Burst(pos-Vector3.new(0,1.5,0),{Color=Color3.fromRGB(150,255,140),Color2=Color3.fromRGB(255,230,120),Count=18,Speed=NumberRange.new(6,12),Spread=Vector2.new(180,180),Acceleration=Vector3.new(0,-10,0)})
     FX.Ring(pos-Vector3.new(0,6,0),U.Colors.green,10,.5)
    end
    Audio.Play('LiftTop');Audio.Play('Strength')
    if nextBefore and after>=nextBefore.Strength then
     Hud.Toast(Text.L('Strong enough for: ','Теперь хватает силы: ')..Text.Name(nextBefore)..' ⛏',U.Colors.gold,4)
     FX.Flash(U.Colors.gold,.2)
    end
    local def2=weightDef()
    if def2 and after>=def2.Cap then Hud.Toast(Text.Get('CAP_REACHED',def2.Cap),U.Colors.gold,3)end
   else
    Audio.Play('Deny');Hud.Toast(msg,U.Colors.red)
   end
   cooldownUntil=os.clock()+def.Cooldown*.85
   self.Render()
  end)
 end
 local function tap()
  if not self.Active then return end
  lastActivity=os.clock()
  local def=weightDef()
  if not def then Audio.Play('Deny');Hud.Toast(Text.Get('NEED_WEIGHT'),U.Colors.gold);return end
  if Net.Attr('MiningStrength',0)>=def.Cap then Audio.Play('Deny');Hud.Toast(Text.Get('WEIGHT_CAPPED'),U.Colors.gold);return end
  if os.clock()<cooldownUntil or sending then return end
  height=math.min(1,height+tapPower(def,Net.Attr('MiningWeight',1)))
  lastTap=os.clock()
  liftScale.Scale=.92;TweenService:Create(liftScale,TweenInfo.new(.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
  Audio.Play('Lift',nil,height)
  if height>=1 then completeRep()end
 end
 liftButton.InputBegan:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then tap()end
 end)

 local function step(dt)
  local level=Net.Attr('MiningWeight',1)
  if os.clock()<cooldownUntil or sending then
   height=math.max(0,height-dt*2.6) -- set down after a completed rep
  elseif os.clock()-lastTap>.12 then
   height=math.max(0,height-dt*fallRate(level))
  end
  fill.Size=UDim2.fromScale(1,height)
  weightIcon.Position=UDim2.fromScale(.5,1-height)
  weightIcon.TextColor3=height>.85 and U.Colors.gold or Color3.new(1,1,1)
  Anim.SetLift(true,height)
  if os.clock()-lastActivity>IDLE_EXIT then self.Exit('idle')end
 end

 -- CAMERA / MOVEMENT -------------------------------------------------------------------------
 local setControls=ctx.SetControls
 local function positionCharacter(corner)
  local character=player.Character;local hum=character and character:FindFirstChildOfClass('Humanoid')
  local root=character and character:FindFirstChild('HumanoidRootPart')
  local mat=corner:FindFirstChild('GymMat');local rack=corner:FindFirstChild('MiningStrengthRack')
  if not(hum and root and mat)then return end
  local target=Vector3.new(mat.Position.X,root.Position.Y,mat.Position.Z)
  if(root.Position-target).Magnitude>2 then
   hum:MoveTo(target)
   local done=false;local conn=hum.MoveToFinished:Once(function()done=true end);local t=os.clock()
   while not done and os.clock()-t<1.6 and self.Active do task.wait()end
   conn:Disconnect()
  end
  if not self.Active then return end
  -- Face away from the rack (towards the walkway) so the camera can film the lift.
  local away=rack and(root.Position-rack.Position)or corner:GetPivot().LookVector
  away=Vector3.new(away.X,0,away.Z);if away.Magnitude<.1 then away=Vector3.new(0,0,-1)end
  root.CFrame=CFrame.lookAt(root.Position,root.Position+away.Unit)
 end
 local function frameCamera()
  local camera=workspace.CurrentCamera;local character=player.Character
  local root=character and character:FindFirstChild('HumanoidRootPart')
  if not camera or not root or camera:GetAttribute('SecretZoom')or camera:GetAttribute('DiscoveryZoom')then return end
  savedCamera={FOV=camera.FieldOfView}
  camera.CameraType=Enum.CameraType.Scriptable
  local look=root.CFrame.LookVector
  local goal=CFrame.lookAt(root.Position+look*11+root.CFrame.RightVector*(compact and 0 or 3.5)+Vector3.new(0,3.4,0),root.Position+Vector3.new(0,1.8,0))
  TweenService:Create(camera,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{CFrame=goal}):Play()
 end
 local function restoreCamera()
  local camera=workspace.CurrentCamera
  if camera and savedCamera then
   camera.CameraType=Enum.CameraType.Custom
   local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
   if hum then camera.CameraSubject=hum end
   camera.FieldOfView=savedCamera.FOV
  end
  savedCamera=nil
 end

 -- ENTER / EXIT -----------------------------------------------------------------------------
 function self.Enter(corner)
  if self.Active or(ctx.Mine and ctx.Mine.Active)then return end
  if ctx.Main:GetAttribute('OpenMenu')~=nil then return end
  self.Active=true;self.Corner=corner;lastActivity=os.clock();height=0
  World.RefreshPrompts()
  local ok,msg=Net.Invoke('MiningTrainBegin',{})
  if not ok then
   self.Active=false;self.Corner=nil;World.RefreshPrompts()
   Hud.Toast(msg,U.Colors.red);Audio.Play('Deny');return
  end
  ctx.Main:SetAttribute('MiningActive',true)
  setControls(false)
  CAS:BindActionAtPriority('DOGROTS_MiningLift',function(_,inputState)
   if inputState==Enum.UserInputState.Begin then tap()end
   return Enum.ContextActionResult.Sink
  end,false,3000,Enum.KeyCode.Space,Enum.KeyCode.ButtonA,Enum.KeyCode.ButtonR2,Enum.KeyCode.F)
  layout();overlay.Visible=true;self.Render()
  Audio.Play('Whoosh')
  task.spawn(function()positionCharacter(corner);if self.Active then frameCamera()end end)
  RunService:BindToRenderStep('DOGROTS_MiningTraining',Enum.RenderPriority.Input.Value+1,step)
  for _,name in ipairs({'MiningStrength','MiningWeight','MiningWeightOwned'})do
   table.insert(connections,player:GetAttributeChangedSignal(name):Connect(function()if not busy then self.Render()end end))
  end
  table.insert(connections,ctx.Main:GetAttributeChangedSignal('OpenMenu'):Connect(function()
   if ctx.Main:GetAttribute('OpenMenu')~=nil then self.Exit('menu')end
  end))
  table.insert(connections,corner:GetAttributeChangedSignal('OwnerUserId'):Connect(function()
   if corner:GetAttribute('OwnerUserId')~=player.UserId then self.Exit('owner')end
  end))
  local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
  if hum then table.insert(connections,hum.Died:Connect(function()self.Exit('died')end))end
  table.insert(connections,player.CharacterRemoving:Connect(function()self.Exit('respawn')end))
  table.insert(connections,UIS.InputBegan:Connect(function(input)
   if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB then self.Exit('escape')end
  end))
 end

 function self.Exit(_reason)
  if not self.Active then return end
  self.Active=false
  RunService:UnbindFromRenderStep('DOGROTS_MiningTraining')
  CAS:UnbindAction('DOGROTS_MiningLift')
  for _,c in ipairs(connections)do c:Disconnect()end
  table.clear(connections)
  overlay.Visible=false
  Anim.SetLift(false,0)
  restoreCamera();setControls(true)
  ctx.Main:SetAttribute('MiningActive',nil)
  self.Corner=nil
  World.RefreshPrompts()
  task.spawn(function()Net.Invoke('MiningTrainEnd',{})end)
 end

 return self
end

return Gym
