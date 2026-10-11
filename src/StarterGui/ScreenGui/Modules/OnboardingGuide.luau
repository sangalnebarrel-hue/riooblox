-- Global Fix 1: a non-modal, progression-aware tutorial for the full DOGROTS loop.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Http=game:GetService('HttpService')
local UIS=game:GetService('UserInputService')
local GuiService=game:GetService('GuiService')
local Guide={}
local controller

local MiningClient={Started=false}
function MiningClient.Start(gui)
 if MiningClient.Started and MiningClient.Root and MiningClient.Root.Parent then return end;MiningClient.Started=true
 local player=Players.LocalPlayer
 local remote=RS:WaitForChild('DogEconomyRequest')
 local MC=require(RS:WaitForChild('DogEconomy'):WaitForChild('Config')).Mining
 local PPS=game:GetService('ProximityPromptService')
 local Tween=game:GetService('TweenService')
 local Debris=game:GetService('Debris')
 local SoundService=game:GetService('SoundService')
 local U=require(script.Parent.UITheme)
 local state=nil;local busy=false;local targetEpoch=0
 local function fmt(n)
  n=math.floor(tonumber(n)or 0)
  if n>=1000000000 then return string.format('%.1fB',n/1e9)end
  if n>=1000000 then return string.format('%.1fM',n/1e6)end
  if n>=1000 then return string.format('%.1fK',n/1e3)end
  return tostring(n)
 end
 local function make(class,props,parent)
  local o=Instance.new(class);for k,v in pairs(props or{})do o[k]=v end;o.Parent=parent;return o
 end
 local function round(o,r)local c=make('UICorner',{CornerRadius=UDim.new(0,r or 10)},o);return c end
 local function stroke(o,color,w)local s=make('UIStroke',{Color=color or U.Colors.edge,Thickness=w or 2},o);return s end
 local function label(parent,text,size,pos,font,color,z)
  return make('TextLabel',{Text=text,Size=size,Position=pos or UDim2.new(),BackgroundTransparency=1,BorderSizePixel=0,
   TextColor3=color or U.Colors.text,Font=font or Enum.Font.GothamBold,TextScaled=false,TextSize=16,TextWrapped=true,
   TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,ZIndex=z or 92},parent)
 end
 local function button(parent,text,size,pos,color,z)
  local b=make('TextButton',{Text=text,Size=size,Position=pos,BackgroundColor3=color or U.Colors.green,BorderSizePixel=0,
   TextColor3=U.Colors.text,Font=Enum.Font.GothamBold,TextSize=14,AutoButtonColor=true,ZIndex=z or 93},parent);round(b,9);stroke(b,U.Colors.edge,2);return b
 end
 local root=make('Frame',{Name='MiningExperience',Visible=true,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Active=false,ZIndex=90},gui);MiningClient.Root=root
 local shade=make('Frame',{Name='MiningShade',Visible=false,Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(5,8,13),BackgroundTransparency=.25,BorderSizePixel=0,Active=true,ZIndex=89},root)
 local toast=label(root,'',UDim2.fromOffset(460,48),UDim2.new(.5,-230,0,84),Enum.Font.GothamBold,Color3.new(1,1,1),120);toast.BackgroundColor3=Color3.fromRGB(20,26,36);toast.BackgroundTransparency=.08;toast.Visible=false;toast.TextXAlignment=Enum.TextXAlignment.Center;round(toast,12);stroke(toast,U.Colors.edge,2)
 local toastId=0
 local function notify(text,color)
  toastId+=1;local id=toastId;toast.Text=tostring(text or'');toast.TextColor3=color or Color3.new(1,1,1);toast.Visible=true
  task.delay(2.4,function()if toastId==id then toast.Visible=false end end)
 end
 local function play(id,volume,speed)
  local s=Instance.new('Sound');s.SoundId=id;s.Volume=volume or .5;s.PlaybackSpeed=speed or 1;s.Parent=SoundService;s:Play();Debris:AddItem(s,3)
 end
 local function updateState(result)
  if type(result)~='table'then return end
  local patch=result.StatePatch or result
  if type(patch.Mining)=='table'then state=patch.Mining
  elseif type(result.MiningState)=='table'then state=result.MiningState end
 end
 local function snapshot()
  local transport,ok,result=pcall(function()return remote:InvokeServer('Snapshot',{})end)
  if transport and ok and type(result)=='table'and type(result.Profile)=='table'then state=result.Profile.Mining;return true,result end
  notify('Не удалось загрузить данные мини-шахты',Color3.fromRGB(255,120,120));return false
 end
 local function invoke(action,args)
  if busy and action~='MiningHit'then return false,'Подожди' end
  if action~='MiningHit'then busy=true end
  local id=Http:GenerateGUID(false):gsub('-','')
  local transport,ok,result=pcall(function()return remote:InvokeServer(action,args or{},id)end)
  if action~='MiningHit'then busy=false end
  if not transport then notify('Связь с сервером прервалась',Color3.fromRGB(255,120,120));return false,result end
  if not ok then notify(tostring(result),Color3.fromRGB(255,150,120));return false,result end
  updateState(result)
  return true,result
 end
 local shop=make('Frame',{Name='PickaxeShop',Visible=false,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(720,520),BackgroundColor3=Color3.fromRGB(245,240,226),BorderSizePixel=0,ZIndex=91},root);round(shop,16);stroke(shop,U.Colors.edge,3)
 local shopTitle=label(shop,'⛏ МАГАЗИН КИРОК',UDim2.new(1,-90,0,48),UDim2.fromOffset(24,12),Enum.Font.GothamBlack,U.Colors.text,92);shopTitle.TextSize=25
 local shopStats=label(shop,'',UDim2.new(1,-48,0,28),UDim2.fromOffset(24,55),Enum.Font.GothamBold,U.Colors.muted,92);shopStats.TextSize=13
 local shopClose=button(shop,'✕',UDim2.fromOffset(44,40),UDim2.new(1,-58,0,12),Color3.fromRGB(235,83,107),94)
 local shopList=make('ScrollingFrame',{Name='List',Position=UDim2.fromOffset(18,92),Size=UDim2.new(1,-36,1,-110),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=6,CanvasSize=UDim2.new(),ZIndex=92},shop)
 local strength=make('Frame',{Name='StrengthTraining',Visible=false,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(780,520),BackgroundColor3=Color3.fromRGB(245,240,226),BorderSizePixel=0,ZIndex=91},root);round(strength,16);stroke(strength,U.Colors.edge,3)
 local strTitle=label(strength,'💪 ТРЕНИРОВКА СИЛЫ',UDim2.new(1,-90,0,48),UDim2.fromOffset(24,12),Enum.Font.GothamBlack,U.Colors.text,92);strTitle.TextSize=25
 local strStats=label(strength,'',UDim2.fromOffset(420,28),UDim2.fromOffset(24,55),Enum.Font.GothamBold,U.Colors.muted,92);strStats.TextSize=13
 local strClose=button(strength,'✕',UDim2.fromOffset(44,40),UDim2.new(1,-58,0,12),Color3.fromRGB(235,83,107),94)
 local weightList=make('ScrollingFrame',{Name='Weights',Position=UDim2.fromOffset(18,92),Size=UDim2.fromOffset(445,408),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=5,CanvasSize=UDim2.new(),ZIndex=92},strength)
 local track=make('Frame',{Name='LiftTrack',Position=UDim2.new(1,-292,0,98),Size=UDim2.fromOffset(260,320),BackgroundColor3=Color3.fromRGB(25,32,42),BorderSizePixel=0,ZIndex=92},strength);round(track,14);stroke(track,U.Colors.edge,2)
 local topLine=make('Frame',{Position=UDim2.new(.1,0,.17,0),Size=UDim2.new(.8,0,0,4),BackgroundColor3=U.Colors.green,BorderSizePixel=0,ZIndex=94},track)
 local trackHint=label(track,'ПЕРЕТАЩИ ГИРЮ\nВВЕРХ ДО ЗЕЛЁНОЙ ЛИНИИ',UDim2.new(1,-20,0,54),UDim2.fromOffset(10,8),Enum.Font.GothamBold,Color3.fromRGB(220,230,240),94);trackHint.TextXAlignment=Enum.TextXAlignment.Center;trackHint.TextSize=12
 local weightKnob=button(track,'●',UDim2.fromOffset(82,68),UDim2.new(.5,-41,1,-84),Color3.fromRGB(110,125,142),96);weightKnob.TextSize=30
 local liftButton=button(strength,'ПОДНЯТЬ ГИРЮ',UDim2.fromOffset(260,48),UDim2.new(1,-292,1,-68),U.Colors.green,94)
 local mine=make('Frame',{Name='MiningGame',Visible=false,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(760,500),BackgroundColor3=Color3.fromRGB(16,22,30),BorderSizePixel=0,ZIndex=91},root);round(mine,16);stroke(mine,U.Colors.edge,3)
 local mineTitle=label(mine,'МИНИ-ШАХТА',UDim2.new(1,-100,0,42),UDim2.fromOffset(22,12),Enum.Font.GothamBlack,Color3.fromRGB(245,245,245),92);mineTitle.TextSize=24
 local mineStats=label(mine,'',UDim2.new(1,-100,0,32),UDim2.fromOffset(22,50),Enum.Font.GothamBold,Color3.fromRGB(187,203,220),92);mineStats.TextSize=14
 local mineClose=button(mine,'✕',UDim2.fromOffset(44,40),UDim2.new(1,-58,0,12),Color3.fromRGB(235,83,107),95)
 local hpBack=make('Frame',{Position=UDim2.fromOffset(22,84),Size=UDim2.new(1,-44,0,18),BackgroundColor3=Color3.fromRGB(45,52,63),BorderSizePixel=0,ZIndex=92},mine);round(hpBack,9)
 local hpFill=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(100,220,125),BorderSizePixel=0,ZIndex=93},hpBack);round(hpFill,9)
 local arena=make('Frame',{Name='TimingArena',Position=UDim2.fromOffset(18,118),Size=UDim2.new(1,-36,1,-136),BackgroundColor3=Color3.fromRGB(22,30,40),BorderSizePixel=0,ClipsDescendants=true,ZIndex=92},mine);round(arena,14);stroke(arena,Color3.fromRGB(65,79,95),2)
 local arenaHelp=label(arena,'ЖДИ, ПОКА КРУГ СЖИМАЕТСЯ · ЗОЛОТАЯ ЗОНА = PERFECT',UDim2.new(1,-20,0,30),UDim2.fromOffset(10,8),Enum.Font.GothamBold,Color3.fromRGB(150,166,183),93);arenaHelp.TextXAlignment=Enum.TextXAlignment.Center;arenaHelp.TextSize=11
 local function hideAll()
  shop.Visible=false;strength.Visible=false;mine.Visible=false;shade.Visible=false;targetEpoch+=1
 end
 shopClose.Activated:Connect(hideAll);strClose.Activated:Connect(hideAll);mineClose.Activated:Connect(hideAll)
 local function layout()
  local cam=workspace.CurrentCamera;local v=cam and cam.ViewportSize or Vector2.new(1280,720)
  shop.Size=UDim2.fromOffset(math.min(720,v.X-24),math.min(520,v.Y-80))
  strength.Size=UDim2.fromOffset(math.min(780,v.X-24),math.min(520,v.Y-80))
  mine.Size=UDim2.fromOffset(math.min(760,v.X-24),math.min(500,v.Y-80))
 end
 layout()
 if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(layout)end
 local function setModal(frame)
  hideAll();shade.Visible=true;frame.Visible=true
 end
 local function mineDef()
  if not state then return nil,nil end
  return MC.Ores[state.OreIndex or 1],MC.Pickaxes[state.PickaxeLevel or 0]
 end
 local function renderMine()
  local ore,pick=mineDef();if not ore then return end
  local hp=math.max(0,state.OreHP or 0);local max=math.max(1,state.OreMaxHP or ore.HP)
  mineTitle.Text=(ore.Icon or '⛏')..' '..(ore.RU or ore.Name)
  mineStats.Text='💪 '..(state.Strength or 0)..'   ·   HP '..hp..' / '..max..'   ·   '..(pick and((pick.Icon or '⛏')..' '..(pick.RU or pick.Name))or'БЕЗ КИРКИ')
  hpFill.Size=UDim2.new(math.clamp(hp/max,0,1),0,1,0)
  hpFill.BackgroundColor3=hp/max<.3 and Color3.fromRGB(245,93,81)or hp/max<.6 and Color3.fromRGB(245,184,74)or Color3.fromRGB(100,220,125)
 end
 local function renderShop()
  if not state then return end
  shopStats.Text='СИЛА: '..(state.Strength or 0)..'   ·   КУПЛЕНО КИРОК: '..(state.PickaxeOwned or 0)..' / 7'
  shopList:ClearAllChildren();local y=0
  for i,def in ipairs(MC.Pickaxes)do
   local row=make('Frame',{Size=UDim2.new(1,-10,0,58),Position=UDim2.fromOffset(0,y),BackgroundColor3=i%2==0 and Color3.fromRGB(235,230,217)or Color3.fromRGB(250,246,236),BorderSizePixel=0,ZIndex=92},shopList);round(row,9)
   local c=Color3.fromRGB(def.Color[1],def.Color[2],def.Color[3]);local icon=def.Icon or '⛏';make('Frame',{Size=UDim2.fromOffset(7,58),BackgroundColor3=c,BorderSizePixel=0,ZIndex=93},row)
   local title=label(row,icon..' '..i..'. '..(def.RU or def.Name),UDim2.new(.42,0,0,25),UDim2.fromOffset(18,5),Enum.Font.GothamBold,U.Colors.text,93);title.TextSize=14
   local sub=label(row,'УРОН '..def.Damage..' · СИЛА '..def.Strength..' · '..fmt(def.Price)..' монет',UDim2.new(.58,-165,0,23),UDim2.fromOffset(18,30),Enum.Font.Gotham,U.Colors.muted,93);sub.TextSize=11
   local owned=(state.PickaxeOwned or 0)>=i;local equipped=(state.PickaxeLevel or 0)==i
   local canBuy=i==(state.PickaxeOwned or 0)+1 and(state.Strength or 0)>=def.Strength
   local txt=equipped and'В РУКАХ'or owned and'ВЗЯТЬ'or canBuy and'КУПИТЬ'or i==(state.PickaxeOwned or 0)+1 and'НУЖНА СИЛА'or'ПО ПОРЯДКУ'
   local bcolor=equipped and U.Colors.blue or((canBuy or owned)and U.Colors.green or Color3.fromRGB(130,137,148))
   local b=button(row,txt,UDim2.fromOffset(142,40),UDim2.new(1,-152,0,9),bcolor,94)
   b.Active=not equipped and(owned or canBuy)
   if b.Active then b.Activated:Connect(function()
    local ok,res=invoke('MiningPickaxe',{Level=i})
    if ok then notify(res.Message or'Готово',c);renderShop()end
   end)end
   y+=64
  end
  shopList.CanvasSize=UDim2.fromOffset(0,y)
 end
 local function renderStrength()
  if not state then return end
  strStats.Text='СИЛА: '..(state.Strength or 0)..'   ·   ГИРЯ: '..(state.WeightLevel or 0)..' / 7'
  weightList:ClearAllChildren();local y=0
  for i,def in ipairs(MC.Weights)do
   local row=make('Frame',{Size=UDim2.new(1,-10,0,54),Position=UDim2.fromOffset(0,y),BackgroundColor3=i%2==0 and Color3.fromRGB(235,230,217)or Color3.fromRGB(250,246,236),BorderSizePixel=0,ZIndex=92},weightList);round(row,8)
   local c=Color3.fromRGB(def.Color[1],def.Color[2],def.Color[3]);local icon=def.Icon or '🏋️';make('Frame',{Size=UDim2.fromOffset(6,54),BackgroundColor3=c,BorderSizePixel=0,ZIndex=93},row)
   local nm=label(row,icon..' '..i..'. '..(def.RU or def.Name),UDim2.new(.54,0,0,23),UDim2.fromOffset(15,4),Enum.Font.GothamBold,U.Colors.text,93);nm.TextSize=13
   local sub=label(row,'+'..def.Gain..' силы · до '..def.Cap..' · '..(def.Price==0 and'БЕСПЛАТНО'or fmt(def.Price)..' монет'),UDim2.new(.66,-105,0,20),UDim2.fromOffset(15,28),Enum.Font.Gotham,U.Colors.muted,93);sub.TextSize=10
   local owned=(state.WeightOwned or 0)>=i;local equipped=(state.WeightLevel or 0)==i
   local canBuy=i==(state.WeightOwned or 0)+1 and(state.Strength or 0)>=def.Strength
   local txt=equipped and'ВЫБРАНО'or owned and'ВЗЯТЬ'or canBuy and(def.Price==0 and'ПОЛУЧИТЬ'or'КУПИТЬ')or i==(state.WeightOwned or 0)+1 and'НУЖНА СИЛА'or'ПО ПОРЯДКУ'
   local bcolor=equipped and U.Colors.blue or((canBuy or owned)and U.Colors.green or Color3.fromRGB(130,137,148))
   local b=button(row,txt,UDim2.fromOffset(100,36),UDim2.new(1,-108,0,9),bcolor,94);b.TextSize=10
   b.Active=not equipped and(owned or canBuy)
   if b.Active then b.Activated:Connect(function()
    local ok,res=invoke('MiningWeight',{Level=i});if ok then notify(res.Message or'Готово',c);renderStrength()end
   end)end
   y+=59
  end
  weightList.CanvasSize=UDim2.fromOffset(0,y)
  local def=MC.Weights[state.WeightLevel or 0]
  if def then
   local c=Color3.fromRGB(def.Color[1],def.Color[2],def.Color[3]);weightKnob.BackgroundColor3=c
   liftButton.Text=(state.Strength or 0)>=def.Cap and'МАКСИМУМ ДЛЯ ЭТОЙ ГИРИ'or'ПОДНЯТЬ · +'..def.Gain..' СИЛЫ'
  else liftButton.Text='СНАЧАЛА ПОЛУЧИ ПЕРВУЮ ГИРЮ' end
 end
 local lifting=false
 local function train()
  if lifting or not state then return end
  local def=MC.Weights[state.WeightLevel or 0];if not def then notify('Сначала получи и выбери гирю №1');return end
  if (state.Strength or 0)>=def.Cap then notify('Эта гиря больше не увеличивает силу');return end
  lifting=true
  local up=Tween:Create(weightKnob,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,-41,.17,-34)});up:Play();up.Completed:Wait()
  play('rbxasset://sounds/swordslash.wav',.25,1.25)
  local ok,res=invoke('MiningTrain',{})
  if ok then notify(res.Message or'Сила выросла!',U.Colors.green);renderStrength()end
  local down=Tween:Create(weightKnob,TweenInfo.new(.28,Enum.EasingStyle.Bounce,Enum.EasingDirection.Out),{Position=UDim2.new(.5,-41,1,-84)});down:Play();down.Completed:Wait();lifting=false
 end
 liftButton.Activated:Connect(function()task.spawn(train)end)
 local dragging=false
 weightKnob.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true end end)
 UIS.InputChanged:Connect(function(input)
  if not dragging or not strength.Visible then return end
  if input.UserInputType~=Enum.UserInputType.MouseMovement and input.UserInputType~=Enum.UserInputType.Touch then return end
  local y=math.clamp(input.Position.Y-track.AbsolutePosition.Y-34,52,track.AbsoluteSize.Y-78)
  weightKnob.Position=UDim2.new(.5,-41,0,y)
 end)
 UIS.InputEnded:Connect(function(input)
  if not dragging then return end
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
   dragging=false
   if weightKnob.AbsolutePosition.Y<=topLine.AbsolutePosition.Y+24 then task.spawn(train)
   else Tween:Create(weightKnob,TweenInfo.new(.2),{Position=UDim2.new(.5,-41,1,-84)}):Play()end
  end
 end)
 local function coinPopup(text,pos,color)
  local l=label(arena,text,UDim2.fromOffset(180,36),UDim2.fromOffset(pos.X-90,pos.Y-18),Enum.Font.GothamBlack,color or U.Colors.gold,110);l.TextXAlignment=Enum.TextXAlignment.Center;l.TextSize=20
  Tween:Create(l,TweenInfo.new(.55),{Position=UDim2.fromOffset(pos.X-90,pos.Y-70),TextTransparency=1}):Play();Debris:AddItem(l,.7)
 end
 local function shake()
  local base=mine.Position
  task.spawn(function()
   for _=1,3 do mine.Position=base+UDim2.fromOffset(math.random(-5,5),math.random(-3,3));task.wait(.025)end
   mine.Position=base
  end)
 end
 local scheduleTarget
 scheduleTarget=function(delayTime)
  local epoch=targetEpoch
  task.delay(delayTime or .1,function()
   if epoch~=targetEpoch or not mine.Visible or not state then return end
   renderMine()
   local ore,pick=mineDef();if not pick then return end
   local size=arena.AbsoluteSize;if size.X<180 or size.Y<150 then task.wait(.1);scheduleTarget(.05);return end
   local serial=epoch*100000+math.random(1,99999)
   local x=math.random(70,math.max(71,math.floor(size.X-70)));local y=math.random(75,math.max(76,math.floor(size.Y-65)))
   local target=make('TextButton',{Name='TimingTarget',Text='',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(108,108),BackgroundColor3=Color3.fromRGB(84,196,255),BackgroundTransparency=.25,BorderSizePixel=0,AutoButtonColor=false,ZIndex=103},arena);round(target,54)
   local ring=stroke(target,Color3.fromRGB(236,246,255),5)
   local core=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(38,38),BackgroundColor3=Color3.fromRGB(255,199,72),BorderSizePixel=0,ZIndex=104},target);round(core,19);stroke(core,Color3.fromRGB(255,239,183),3)
   local window=math.max(.56,.92-(state.PickaxeLevel or 1)*.045)
   local tween=Tween:Create(target,TweenInfo.new(window,Enum.EasingStyle.Linear),{Size=UDim2.fromOffset(38,38)});tween:Play()
   local used=false
   local function finish(hit)
    if used then return end;used=true;tween:Cancel()
    if target.Parent then target:Destroy()end
    if epoch~=targetEpoch or not mine.Visible then return end
    if not hit then notify('ПРОМАХ · дождись следующего круга',Color3.fromRGB(255,145,120));scheduleTarget(.16);return end
    scheduleTarget(math.max(.06,(pick.Cooldown or .6)*.20))
   end
   target.Activated:Connect(function()
    if used then return end
    local px=target.AbsoluteSize.X
    if px>78 then coinPopup('РАНО!',Vector2.new(x,y),Color3.fromRGB(255,140,120));finish(false);return end
    local quality=px<=54 and 2 or 1
    local beforeBreak=state.OresBroken or 0
    local ok,res=invoke('MiningHit',{Quality=quality})
    if not ok then finish(false);return end
    renderMine();shake()
    local payout=state.LastPayout or 0
    local text=(quality==2 and'PERFECT  'or'HIT  ')..'+'..fmt(payout)
    coinPopup(text,Vector2.new(x,y),quality==2 and Color3.fromRGB(255,215,73)or Color3.fromRGB(111,224,255))
    play(quality==2 and'rbxasset://sounds/electronicpingshort.wav'or'rbxasset://sounds/swordslash.wav',quality==2 and .5 or .32,quality==2 and 1.35 or 1.05)
    if (state.OresBroken or 0)>beforeBreak then
     play('rbxasset://sounds/collide.wav',.65,.75);notify('РУДА РАЗБИТА! НОВАЯ: '..((MC.Ores[state.OreIndex]or{}).RU or'РУДА'),Color3.fromRGB(255,215,73))
    end
    finish(true)
   end)
   task.delay(window+.08,function()if target.Parent and not used then finish(false)end end)
  end)
 end
 local function yardForPrompt(prompt)
  local node=prompt
  while node and node~=workspace do
   if node:GetAttribute('YardId')~=nil then return node end
   node=node.Parent
  end
 end
 local function ownYard(prompt)
  local yard=yardForPrompt(prompt)
  if not yard or yard:GetAttribute('OwnerUserId')~=player.UserId then notify('Это не твой участок',Color3.fromRGB(255,140,120));return nil end
  return yard
 end
 local function openShop()
  if not snapshot()then return end;setModal(shop);renderShop()
 end
 local function openStrength()
  if not snapshot()then return end;setModal(strength);renderStrength()
 end
 local function openMine()
  if not snapshot()then return end
  if not state or(state.PickaxeLevel or 0)<1 then notify('Сначала купи Деревянную кирку за 600 монет');openShop();return end
  local ok,res=invoke('MiningBegin',{});if not ok then return end
  setModal(mine);renderMine();targetEpoch+=1;scheduleTarget(.2)
 end
 PPS.PromptTriggered:Connect(function(prompt)
  if prompt.Name=='MiningOrePrompt'then if ownYard(prompt)then openMine()end
  elseif prompt.Name=='MiningPickaxeShopPrompt'then if ownYard(prompt)then openShop()end
  elseif prompt.Name=='MiningStrengthPrompt'then if ownYard(prompt)then openStrength()end end
 end)
 gui:GetAttributeChangedSignal('OpenMenu'):Connect(function()if gui:GetAttribute('OpenMenu')~=nil then hideAll()end end)
 player.CharacterAdded:Connect(function()hideAll()end)
end

local LAST=17
local cards={
 [0]={Title='WELCOME TO DOGROTS',Icon='Dogs',Body='You start with Cash and an empty yard. This guide teaches the real DOGROTS loop step by step, including the active Mining Corner beside your kennels.',Button='START THE GUIDE'},
 [1]={Title='1 · BUY YOUR FIRST DOG',Icon='Dogs',Body='Go to THE DOG tongue and buy your first affordable dog. New dogs become workers you can assign to your yard. Rarer dogs cost much more and become long-term goals.',Button='SHOW THE DOG',Destination='THE DOG'},
 [2]={Title='2 · PUT THE DOG TO WORK',Icon='Yard',Body='Return to your yard and use an empty kennel. Assign the dog to a Dig Slot. Only assigned dogs dig.',Button='SHOW MY YARD',Destination='Your yard'},
 [3]={Title='3 · WAIT FOR A REAL DIG',Icon='Discoveries',Body='A dog works in cycles. Ordinary finds fill your yard storage; rare discoveries go to BAG. Your dog can NEVER reach a depth you have not unlocked.',Button='VIEW MY DOGS',Page='Dogs'},
 [4]={Title='4 · SELL, DON\'T JUST AFK',Icon='Coins',Body='Take ordinary finds to your Collector and sell them. Cash is intentionally earned through the loop: dig → collect → sell → reinvest.',Button='SHOW COLLECTOR',Destination='Your yard'},
 [5]={Title='5 · LEVELS OPEN THE GAME',Icon='Events',Body='XP comes from digging, selling, active mining, unlocking depths and buying upgrades. Reach Level 2. Higher levels unlock deeper layers and stronger upgrades.',Button='VIEW MY DOGS',Page='Dogs'},
 [6]={Title='6 · BUY YOUR FIRST UPGRADE',Icon='Yard',Body='Use your yard upgrade terminal. Every upgrade has both a Cash price and a player-level requirement. Choose Dig, Storage, Kennel, Plot or another useful path.',Button='SHOW UPGRADES',Destination='Your yard'},
 [7]={Title='7 · ACTIVE MINING',Icon='Dig',Body='Beside your kennels is a Mining Corner. Buy the Wooden Pickaxe for 600 Coins, activate the ore pile and click the shrinking circles in good timing. Every successful hit pays Coins; a broken ore instantly rolls a new random ore.',Button='SHOW MINING CORNER',Destination='Your yard'},
 [8]={Title='8 · TRAIN YOUR STRENGTH',Icon='Yard',Body='The strength rack is beside the ore. The first weight is free. Equip it, drag the weight upward to complete a rep and gain Strength. Better pickaxes require both Coins and enough Strength.',Button='SHOW STRENGTH RACK',Destination='Your yard'},
 [9]={Title='9 · PICKAXES, WEIGHTS & ORES',Icon='Dig',Body='There are 7 pickaxes and 7 training weights. Stronger pickaxes deal much more damage; the final Voidbreaker can crush any ore in only a couple of clean hits. Ores reroll randomly from Limestone to extremely rare Void Crystal.',Button='CONTINUE',Info=true},
 [10]={Title='10 · DOG LINE + DEPTHS',Icon='Dig',Body='THE DOG tongue is where you expand your team with new dogs; prices rise sharply with rarity. Layers are hard progression gates: Caverns opens at Level 5, then Ancient Ruins, Cursed Depths and THE VOID. Dogs can never pull loot from a layer you have not unlocked.',Button='OPEN LAYERS & CONTINUE',Page='Layers',Info=true},
 [11]={Title='11 · LUCKY BLOCKS',Icon='Inventory',Body='Lucky Blocks can be bought from the tongue and placed on Lucky Pads in your yard. Higher tiers cost much more and contain stronger reward pools.',Button='SHOW THE TONGUE & CONTINUE',Destination='THE DOG',Info=true},
 [12]={Title='12 · DOG-O-MATIC',Icon='Ticket',Body='DOG-O-MATIC spends DOG TOKENS for a random prize. A free token refills five hours after use; paid token bundles are optional. Keep one free inventory slot before spinning.',Button='OPEN DOG-O-MATIC & CONTINUE',Page='RewardMachine',Info=true},
 [13]={Title='13 · LAB & DOG GROWTH',Icon='Lab',Body='The Lab is for long-term dog progression: review genetics actions before committing them. Mastery grows through work; abilities, variants and mutations change how dogs perform.',Button='OPEN LAB & CONTINUE',Page='Lab',Info=true},
 [14]={Title='14 · DOGDEX & MUSEUM',Icon='Index',Body='DogDex tracks what you have discovered. Museum progress, sets, records and collection milestones give you reasons to hunt beyond raw Cash.',Button='OPEN DOGDEX & CONTINUE',Page='DogDex',Info=true},
 [15]={Title='15 · SAFE PLAYER TRADING',Icon='Trade',Body='Trading unlocks at Level 5 for both players. Build an offer, UPDATE it, LOCK it, review both estimated values, then wait through the safety timer before FINAL CONFIRM.',Button='OPEN TRADE & CONTINUE',Page='Trade',Info=true},
 [16]={Title='16 · EVENTS & RETURN REWARDS',Icon='Events',Body='Events are bonuses, not free-money farms: stay active and dig to qualify. EVENTS also holds Daily Rewards and playtime milestones. Offline income is only a small welcome-back bonus.',Button='OPEN EVENTS & CONTINUE',Page='Events',Info=true},
 [17]={Title='YOU KNOW THE WHOLE LOOP',Icon='Dogs',Body='Buy dogs → assign → dig → sell → level → upgrade → unlock depth. Between dog cycles, actively mine ore, train Strength and upgrade your pickaxe. Then chase Lucky Blocks, DOG-O-MATIC, Lab, DogDex, Museum, events and safe trades.',Button='FINISH GUIDE'},
}

function Guide.Replay()if controller then controller.Replay()end end
function Guide.Start(gui,navigation)
 MiningClient.Start(gui)
 if controller then return controller end
 local U=require(script.Parent.UITheme)
 local player=Players.LocalPlayer
 local remote=RS:WaitForChild('DogEconomyRequest')
 local root=U.New('Frame',{Name='OnboardingGuide',Visible=false,Active=false,BackgroundColor3=U.Colors.panel,BorderSizePixel=0,ZIndex=75},gui)
 U.Round(root,16);U.Stroke(root,U.Colors.edge,3)
 local accent=U.New('Frame',{Name='Accent',BackgroundColor3=U.Colors.blue,BorderSizePixel=0,Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(4,40),ZIndex=76},root);U.Round(accent,2)
 local heading=U.Text(root,'',25,8,300,21,13,U.Colors.blue,true);heading.Name='ProgressCaption';heading.ZIndex=77
 local title=U.Text(root,'',25,30,330,30,20,U.Colors.text,true);title.Name='TaskTitle';title.ZIndex=77
 local body=U.Text(root,'',18,68,400,84,15,U.Colors.text,false);body.Name='TaskBody';body.ZIndex=77;body.TextYAlignment=Enum.TextYAlignment.Top
 local iconHolder=U.New('Frame',{Name='TaskIcon',BackgroundTransparency=1,Size=UDim2.fromOffset(42,42),ZIndex=76},root)
 local pending=false;local collapsed=false;local replayStep=nil;local alive=true;local errorText=nil;local lastIcon=nil;local showAfter=os.clock()+2
 local render
 local function stage()return replayStep or math.clamp(tonumber(player:GetAttribute('TutorialStep'))or 0,0,LAST)end
 local function request(action)
  if pending then return end
  pending=true;errorText=nil;render()
  task.spawn(function()
   local id=Http:GenerateGUID(false):gsub('-','')
   local transport,ok=pcall(function()return remote:InvokeServer('Tutorial',{Action=action},id)end)
   if not alive then return end
   pending=false
   if not transport or not ok then errorText='Could not save the guide. Tap again to retry.'end
   render()
  end)
 end
 local function go(card)
  if card.Page then navigation.OpenPage(card.Page)
  elseif card.Destination then navigation.Navigate(card.Destination)end
 end
 local primary=U.Button(root,'Action','',18,166,280,42,function()
  local step=stage();local card=cards[step]
  if replayStep~=nil then
   if replayStep<LAST then replayStep+=1 else replayStep=nil end
   errorText=nil;render();return
  end
  if step==0 then request('Start')
  elseif step==LAST then request('Finish')
  elseif card.Info then request('Next');task.defer(function()go(card)end)
  else go(card)end
 end,U.Colors.green)
 local skip=U.Button(root,'Skip','SKIP',306,166,100,42,function()
  if replayStep~=nil then replayStep=nil;render()else request(stage()==LAST and'Finish'or'Skip')end
 end,U.Colors.blue)
 local collapse=U.Button(root,'Collapse','-',0,0,44,44,function()collapsed=not collapsed;render()end,U.Colors.blue)
 for _,button in ipairs({primary,skip,collapse})do button.ZIndex=77;button.Caption.ZIndex=78 end
 local progress={}
 for i=1,LAST-1 do progress[i]=U.New('Frame',{Name='Step'..i,Size=UDim2.fromOffset(20,4),BackgroundColor3=U.Colors.secondary,BorderSizePixel=0,ZIndex=76},root);U.Round(progress[i],2)end
 local marker=U.New('BillboardGui',{Name='TutorialWorldMarker',Enabled=false,ResetOnSpawn=false,AlwaysOnTop=false,MaxDistance=140,Size=UDim2.fromOffset(220,48),StudsOffsetWorldSpace=Vector3.new(0,5,0),LightInfluence=0},player:WaitForChild('PlayerGui'))
 local markerText=U.Center(marker,'',4,2,212,42,18,U.Colors.gold,true);markerText.TextStrokeTransparency=0;markerText.TextStrokeColor3=U.Colors.edge
 local function part(object)
  if not object then return end
  if object:IsA('BasePart')then return object end
  return object:FindFirstChildWhichIsA('BasePart',true)
 end
 local function myYard()
  local map=workspace:FindFirstChild('DOGROTS_District');local yards=map and map:FindFirstChild('04_PlayerYards')
  if not yards then return end
  for _,yard in ipairs(yards:GetChildren())do
   if yard:GetAttribute('OwnerUserId')==player.UserId and yard:GetAttribute('YardId')==player:GetAttribute('YardId')then return yard end
  end
 end
 local function target(step)
  local map=workspace:FindFirstChild('DOGROTS_District')
  if step==1 then local line=map and map:FindFirstChild('03_DogLine');return part(line),'BUY YOUR FIRST DOG'end                            
  local yard=myYard();if not yard then return end
  if step==2 or step==3 then return part(yard:FindFirstChild('DigSlot_1',true)or yard),'YOUR DIG KENNEL'end
  if step==4 then return part(yard:FindFirstChild('SellAnchor',true)),'YOUR COLLECTOR'end
  if step==6 then return part(yard:FindFirstChild('UpgradeAnchor',true)),'YARD UPGRADES'end
  if step==7 then return part(yard:FindFirstChild('MiningPickaxeShop',true)or yard:FindFirstChild('MiningOreCore',true)),'КУПИ КИРКУ И РАЗБЕЙ РУДУ'end
  if step==8 then return part(yard:FindFirstChild('MiningStrengthRack',true)),'ПРОКАЧАЙ СИЛУ'end
 end
 render=function()
  if not alive then return end
  local active=replayStep~=nil or player:GetAttribute('TutorialActive')==true
  local modal=gui:GetAttribute('OpenMenu')~=nil or(gui:GetAttribute('ModalOwnerCount')or 0)>0
  root.Visible=active and not modal and player:GetAttribute('EconomyReady')==true and os.clock()>=showAfter
  marker.Enabled=false
  if not root.Visible then return end
  local step=stage();local card=cards[step]
  local left,top,width,height=U.SafeArea(gui);local narrow=width<600;local touch=UIS.TouchEnabled
  local cardW=math.min(narrow and 342 or touch and 380 or 462,width-24);local compact=cardW<410
  local cardH=collapsed and 48 or(compact and 246 or 232);local bottom=touch and height>width and 235 or 16
  root.Size=UDim2.fromOffset(cardW,cardH);root.Position=UDim2.fromOffset(left+math.floor((width-cardW)/2),top+math.max(8,height-bottom-cardH))
  heading.Text=replayStep~=nil and('HOW TO PLAY  '..(step+1)..' / '..(LAST+1))or step==0 and'INTERACTIVE GUIDE' or step==LAST and'GUIDE COMPLETE'or('GUIDE  '..step..' / '..(LAST-1))
  title.Text=card.Title;title.TextSize=compact and 16 or 19;title.Position=UDim2.fromOffset(25,collapsed and 13 or 30);title.Size=UDim2.fromOffset(cardW-(collapsed and 78 or 120),collapsed and 26 or 30)
  heading.Visible=not collapsed;body.Visible=not collapsed;iconHolder.Visible=not collapsed;primary.Visible=not collapsed;skip.Visible=not collapsed
  accent.Position=UDim2.fromOffset(12,collapsed and 10 or 12);accent.Size=UDim2.fromOffset(4,collapsed and 28 or 40)
  collapse.Position=UDim2.fromOffset(cardW-47,2);collapse.Caption.Text=collapsed and'+'or'-';collapse.Caption.TextSize=24
  iconHolder.Position=UDim2.fromOffset(cardW-86,15)
  if card.Icon~=lastIcon then
   iconHolder:ClearAllChildren();local icon=U.Icon(iconHolder,card.Icon,0,0,42)
   for _,child in ipairs(icon:GetDescendants())do if child:IsA('GuiObject')then child.ZIndex=78 end end
   icon.ZIndex=78;lastIcon=card.Icon
  end
  body.Text=errorText or card.Body;body.TextSize=compact and 13 or 15;body.Position=UDim2.fromOffset(18,68);body.Size=UDim2.fromOffset(cardW-36,cardH-132)
  local buttonY=cardH-58;local primaryW=cardW-138
  primary.Position=UDim2.fromOffset(18,buttonY);primary.Size=UDim2.fromOffset(primaryW,42);primary.Caption.Size=UDim2.new(1,-12,1,-4);primary.Caption.TextSize=compact and 12 or 14
  primary.Caption.Text=pending and'SAVING...'or replayStep~=nil and(step==LAST and'DONE'or'NEXT')or card.Button
  skip.Position=UDim2.fromOffset(cardW-112,buttonY);skip.Size=UDim2.fromOffset(94,42);skip.Caption.Size=UDim2.new(1,-12,1,-4);skip.Caption.TextSize=14
  skip.Caption.Text=replayStep~=nil and'CLOSE'or step==LAST and'CLOSE'or'SKIP'
  U.SetButtonEnabled(primary,not pending);U.SetButtonEnabled(skip,not pending)
  local count=LAST-1;local segment=(cardW-36-(count-1)*3)/count
  for i,bar in ipairs(progress)do
   bar.Visible=not collapsed;bar.Position=UDim2.fromOffset(18+(i-1)*(segment+3),cardH-8);bar.Size=UDim2.fromOffset(segment,4)
   bar.BackgroundColor3=step>i and U.Colors.green or step==i and U.Colors.gold or U.Colors.secondary
  end
  if replayStep==nil and not collapsed then local object,label=target(step);if object then marker.Adornee=object;markerText.Text=label;marker.Enabled=true end end
 end
 local connections={}
 local function connect(signal,callback)table.insert(connections,signal:Connect(callback))end
 for _,name in ipairs({'TutorialStep','TutorialActive','EconomyReady','YardId'})do connect(player:GetAttributeChangedSignal(name),render)end
 for _,name in ipairs({'OpenMenu','ModalOwnerCount'})do connect(gui:GetAttributeChangedSignal(name),render)end
 connect(gui:GetPropertyChangedSignal('AbsoluteSize'),render);connect(GuiService:GetPropertyChangedSignal('TopbarInset'),render);connect(UIS:GetPropertyChangedSignal('TouchEnabled'),render)
 controller={Replay=function()navigation.Close();replayStep=0;collapsed=false;errorText=nil;showAfter=0;render()end}
 connect(gui.Destroying,function()alive=false;marker:Destroy();for _,connection in ipairs(connections)do connection:Disconnect()end;controller=nil end)
 task.spawn(function()while alive and gui.Parent do render();task.wait(.5)end end)
 render();return controller
end
return Guide
