-- Pickaxe market (UI kit window, the same look as DOGS / LAB / BAG): the collection of the 16
-- DOGROTS pickaxes on the left (rarity, owned / in hand / next / locked), the showcase on the
-- right: the living 3D model (MiningClient.PickFX animates it), rarity banner, lore, what makes
-- it special, animated stat bars, the price and Strength it needs, one big action button and
-- TRY A HIT (plays its hit sound and makes the model react). Opened from the pickaxe sign.
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local Shop={}

local RARITY_ORDER={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6}

function Shop.new(ctx)
 local self:any={IsOpen=false}
 local player=ctx.Player
 local M,Text,Audio,Models,Rules=ctx.M,ctx.Text,ctx.Audio,ctx.Models,ctx.Rules
 local Net,Hud=ctx.Net,ctx.Hud
 local modules=ctx.Main:WaitForChild('Modules')
 local Kit=require(modules:WaitForChild('Kit'))
 local Base=require(modules.Kit:WaitForChild('Base'))
 local Theme=Kit.Theme
 local P=Theme.Colors
 local PIXEL=Font.fromEnum(Enum.Font.Arcade)
 local function L(en,ru)return Text.L(en,ru)end
 local function rarityColor(r)return Theme.Rarity[r or'Common']or Theme.Rarity.Common end
 local function rarityName(r)return Text.IsRussian()and((M.RarityRU or{})[r]or r)or string.upper(r or'')end

 local selected=1
 local busy=false
 local tiles={}
 local ui:any={}
 local preview=nil -- {Model, Camera, Spin}
 local spinConn=nil

 local win=Kit.Window.new({
  Key='MiningShop',
  Title='⛏ '..Text.Get('PICKAXE_SHOP'),
  Subtitle='',
  Accent=Color3.fromRGB(242,146,38),
  MaxSize=Vector2.new(1080,740),
  NoTranslate=true,
  OnClose=function()
   self.IsOpen=false;if spinConn then spinConn:Disconnect();spinConn=nil end
   -- Stop PickFX animating the hidden preview every frame; Open -> Select -> setPreview builds and tracks a new one.
   if preview then if ctx.PickFX then ctx.PickFX.Untrack(preview.Model)end;preview.Model:Destroy();preview=nil end
  end,
 })
 local body=win.Body

 -- LEFT: the collection ----------------------------------------------------------------------
 local left=Kit.New('Frame',{Name='Collection',BackgroundColor3=Theme.SurfaceAlt,BorderSizePixel=0,ZIndex=3},body)
 Kit.Corner(left,Theme.Radius.Card);Kit.Stroke(left,P.edge,2)
 local listTitle=Kit.Text(left,{Name='Title',Text='',TextSize=18,Scaled=true,MinTextSize=11,Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-24,0,28),ZIndex=4,NoTranslate=true})
 local list=Kit.New('ScrollingFrame',{Name='List',BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=6,ScrollBarImageColor3=P.edge,
  Position=UDim2.fromOffset(6,38),Size=UDim2.new(1,-12,1,-44),CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=4},left)
 Kit.New('UIListLayout',{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},list)
 Kit.Padding(list,4,4,8,4)

 -- RIGHT: the showcase -------------------------------------------------------------------------
 local right=Kit.New('Frame',{Name='Showcase',BackgroundColor3=Theme.White,BorderSizePixel=0,ZIndex=3},body)
 Kit.Corner(right,Theme.Radius.Card);Kit.Stroke(right,P.edge,2)
 local showScale=Kit.New('UIScale',{},right)
 local stage=Kit.New('ViewportFrame',{Name='Stage',BackgroundColor3=Color3.fromRGB(30,40,62),BorderSizePixel=0,Ambient=Color3.fromRGB(170,170,190),
  LightColor=Color3.new(1,1,1),LightDirection=Vector3.new(-1,-1.3,-1),ZIndex=4},right)
 Kit.Corner(stage,Theme.Radius.Card)
 local stageGrad=Kit.New('UIGradient',{Rotation=90},stage)
 local banner=Kit.New('Frame',{Name='Rarity',BackgroundColor3=Theme.White,BorderSizePixel=0,Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(150,30),ZIndex=6},stage)
 Kit.Corner(banner,'pill');Kit.Stroke(banner,P.edge,2)
 local bannerGrad=Kit.New('UIGradient',{},banner)
 local bannerText=Kit.Text(banner,{Text='',TextSize=16,Scaled=true,MinTextSize=9,AlignX='Center',Color=Theme.White,Stroke=0,Position=UDim2.fromOffset(6,2),Size=UDim2.new(1,-12,1,-4),ZIndex=7,NoTranslate=true,Font=PIXEL})
 local number=Kit.Text(stage,{Text='',TextSize=16,AlignX='Right',Color=Theme.White,Stroke=0.2,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,12),Size=UDim2.fromOffset(90,26),ZIndex=6,NoTranslate=true,Font=PIXEL})
 local stateTag=Kit.Text(stage,{Text='',TextSize=16,Scaled=true,MinTextSize=9,AlignX='Center',Color=Theme.White,Stroke=0.3,AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-10),Size=UDim2.fromOffset(220,26),ZIndex=6,NoTranslate=true,Font=PIXEL})
 local nameLabel=Kit.Text(right,{Text='',TextSize=28,Scaled=true,MinTextSize=14,ZIndex=4,NoTranslate=true})
 local lore=Kit.Text(right,{Text='',TextSize=15,Wrap=true,Scaled=true,MinTextSize=10,AlignY='Top',Color=P.muted,ZIndex=4,NoTranslate=true})
 local trait=Kit.Text(right,{Text='',TextSize=16,Scaled=true,MinTextSize=10,Color=P.purple,ZIndex=4,NoTranslate=true,Rich=true})
 local statsFrame=Kit.New('Frame',{Name='Stats',BackgroundTransparency=1,ZIndex=4},right)
 Kit.New('UIGridLayout',{CellSize=UDim2.new(.5,-6,0,40),CellPadding=UDim2.fromOffset(12,6),SortOrder=Enum.SortOrder.LayoutOrder},statsFrame)
 local STATS={
  {Key='Damage',Label={'Power','Мощь'},Value=function(d)return d.Damage end,Max=function()return M.Pickaxes[#M.Pickaxes].Damage end,Log=true,Format=function(d)return tostring(d.Damage)end,Color=P.red},
  {Key='Speed',Label={'Speed','Скорость'},Value=function(d)return 1.15-d.Window end,Max=function()return .4 end,Format=function(d)return string.format('%.2fs',d.Window)end,Color=P.blue},
  {Key='Circles',Label={'Circles','Круги'},Value=function(d)return d.Circles end,Max=function()return 5 end,Format=function(d)return tostring(d.Circles)end,Color=P.gold},
  {Key='Crit',Label={'Crit','Крит'},Value=function(d)return d.CritChance or 0 end,Max=function()return .3 end,Format=function(d)return math.floor((d.CritChance or 0)*1000+.5)/10 ..'% x'..(d.CritMult or 2)end,Color=Color3.fromRGB(255,110,70)},
  {Key='Luck',Label={'Ore luck','Удача'},Value=function(d)return d.Luck or 0 end,Max=function()return 1 end,Format=function(d)return '+'..math.floor((d.Luck or 0)*100+.5)..'%'end,Color=P.green},
  {Key='Coins',Label={'Coins','Монеты'},Value=function(d)return d.CoinBonus or 0 end,Max=function()return 1.5 end,Format=function(d)return '+'..math.floor((d.CoinBonus or 0)*100+.5)..'%'end,Color=Color3.fromRGB(255,196,40)},
 }
 for i,st in ipairs(STATS)do
  local cell=Kit.New('Frame',{Name=st.Key,BackgroundTransparency=1,LayoutOrder=i,ZIndex=4},statsFrame)
  st.Label2=Kit.Text(cell,{Text='',TextSize=14,Scaled=true,MinTextSize=9,Size=UDim2.new(.6,0,0,18),ZIndex=5,NoTranslate=true,Color=P.muted})
  st.ValueLabel=Kit.Text(cell,{Text='',TextSize=14,Scaled=true,MinTextSize=9,AlignX='Right',Position=UDim2.fromScale(.6,0),Size=UDim2.new(.4,0,0,18),ZIndex=5,NoTranslate=true,Font='numeric'})
  st.Bar=Kit.ProgressBar(cell,{Height=14,Position=UDim2.fromOffset(0,22),Size=UDim2.new(1,0,0,14),Color=st.Color,ZIndex=5,NoTranslate=true})
 end
 local priceChip=Kit.Pill(right,{Text='',Color=P.gold,ZIndex=5,NoTranslate=true,Height=34,TextSize=18,PadX=12})
 local strengthChip=Kit.Pill(right,{Text='',Color=P.green,ZIndex=5,NoTranslate=true,Height=34,TextSize=18,PadX=12})
 local action=Kit.Button(right,{Text='',Style='success',ZIndex=5,NoTranslate=true,OnClick=function()self.Action()end})
 local tryButton=Kit.Button(right,{Text=Text.Get('TRY_HIT'),Style='secondary',ZIndex=5,NoTranslate=true,OnClick=function()self.TryHit()end})

 -- Sparkles flying out of a button (purchase / try).
 local function sparkle(from,count,colors)
  local gui=from:FindFirstAncestorWhichIsA('ScreenGui');if not gui then return end
  local center=from.AbsolutePosition+from.AbsoluteSize/2-gui.AbsolutePosition
  for _=1,count do
   local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(.5,.5);l.Size=UDim2.fromOffset(26,26)
   l.Position=UDim2.fromOffset(center.X,center.Y);l.Text=({'✦','★','✧','♦'})[math.random(1,4)];l.TextScaled=true;l.FontFace=PIXEL
   l.TextColor3=colors[math.random(1,#colors)];l.ZIndex=80;l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true);l.Parent=gui
   local a=math.random()*math.pi*2;local d=60+math.random()*90
   TweenService:Create(l,TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromOffset(center.X+math.cos(a)*d,center.Y+math.sin(a)*d),TextTransparency=1,Rotation=math.random(-180,180)}):Play()
   Debris:AddItem(l,.65)
  end
 end

 -- LAYOUT ----------------------------------------------------------------------------------------
 local fit=1 -- base scale of the showcase (Select's pop animates around it)
 local popTween=nil
 local function layout()
  local info=win:GetLayout()
  -- Body clips its children: never lay out past it (the floors only cover the no-size-yet fallback).
  local W,H=math.max(300,info.Width),math.max(120,info.Height)
  local stacked=info.Phone and not info.Landscape -- portrait only; landscape phones keep the list beside the showcase
  local rw,rh,lw,lh
  if stacked then
   rw,rh=W,math.floor(H*.64);lw,lh=W,H-rh-8
   right.Position=UDim2.fromOffset(0,0);left.Position=UDim2.fromOffset(0,rh+8)
  else
   lw=math.floor(math.clamp(W*.36,250,380));rw=W-lw-12;rh=H;lh=H
   left.Position=UDim2.fromOffset(0,0);right.Position=UDim2.fromOffset(lw+12,0)
  end
  left.Size=UDim2.fromOffset(lw,lh)
  -- A showcase smaller than its design size is laid out at that size and scaled down to fit
  -- (side by side, the stage and the info column each need ~260 px).
  local short=not stacked and rh<480
  if popTween then popTween:Cancel();popTween=nil end
  fit=math.min(1,rh/(stacked and 490 or 340),short and rw/550 or 1);showScale.Scale=fit
  rw,rh=math.floor(rw/fit),math.floor(rh/fit)
  right.Size=UDim2.fromOffset(rw,rh)
  local pad=12
  local grid=statsFrame:FindFirstChildOfClass('UIGridLayout')
  local function placeStats(x,y,w,h)
   statsFrame.Position=UDim2.fromOffset(x,y);statsFrame.Size=UDim2.fromOffset(w,h)
   local cellH=math.clamp(math.floor((h-12)/3),30,44)
   grid.CellSize=UDim2.new(.5,-6,0,cellH)
   for _,st in ipairs(STATS)do st.Bar.Instance.Position=UDim2.fromOffset(0,math.max(18,cellH-16))end
  end
  local by=rh-pad-46
  local function split(room)local bw=math.min(250,math.floor(room*.6));return bw,math.min(170,room-bw-12)end
  local bw,tw=split(rw-330) -- desktop: BUY and TRY A HIT beside the chips
  local chipsAbove=stacked or tw<110 -- no room for both buttons there: the chips get their own row above them
  if chipsAbove then bw,tw=split(rw-pad*2)end
  if short then
   -- Landscape phone / low window: the model on the left, name, price, lore, trait and stats beside it.
   local sw=math.floor((rw-pad*3)*.5);local x=pad*2+sw;local cw=rw-x-pad
   stage.Position=UDim2.fromOffset(pad,pad);stage.Size=UDim2.fromOffset(sw,by-pad-8)
   number.Visible=sw>=272 -- on a narrower stage '#16/16' runs into the rarity banner
   nameLabel.Position=UDim2.fromOffset(x,pad);nameLabel.Size=UDim2.fromOffset(cw,28)
   priceChip.Instance.Position=UDim2.fromOffset(x,pad+32);strengthChip.Instance.Position=UDim2.fromOffset(x+150,pad+32)
   lore.Position=UDim2.fromOffset(x,pad+72);lore.Size=UDim2.fromOffset(cw,30)
   trait.Position=UDim2.fromOffset(x,pad+104);trait.Size=UDim2.fromOffset(cw,22)
   placeStats(x,pad+130,cw,by-8-(pad+130))
  else
   local bottomH=chipsAbove and 92 or 54
   local stageH=math.floor(rh*(stacked and .36 or .4))
   if not stacked then stageH=math.max(70,math.min(stageH,rh-pad-8-98-bottomH-pad-(3*34+12)))end -- the 3 stat rows always fit
   stage.Position=UDim2.fromOffset(pad,pad);stage.Size=UDim2.fromOffset(rw-pad*2,stageH);number.Visible=true
   local y=pad+stageH+8
   nameLabel.Position=UDim2.fromOffset(pad+4,y);nameLabel.Size=UDim2.fromOffset(rw-pad*2-8,stacked and 26 or 32);y+=stacked and 26 or 32
   lore.Position=UDim2.fromOffset(pad+4,y);lore.Size=UDim2.fromOffset(rw-pad*2-8,stacked and 30 or 38);y+=stacked and 30 or 40
   trait.Position=UDim2.fromOffset(pad+4,y);trait.Size=UDim2.fromOffset(rw-pad*2-8,22);y+=26
   placeStats(pad+4,y,rw-pad*2-8,math.max(60,rh-y-bottomH-pad))
   local chipY=chipsAbove and by-40 or by+8
   priceChip.Instance.Position=UDim2.fromOffset(pad,chipY);strengthChip.Instance.Position=UDim2.fromOffset(pad+150,chipY)
  end
  if stacked or short then
   action.Instance.Position=UDim2.fromOffset(pad,by);action.Instance.Size=UDim2.fromOffset(math.floor((rw-pad*3)*.62),46)
   tryButton.Instance.Position=UDim2.fromOffset(pad*2+math.floor((rw-pad*3)*.62),by);tryButton.Instance.Size=UDim2.fromOffset(math.floor((rw-pad*3)*.38),46)
  else
   action.Instance.Position=UDim2.fromOffset(rw-pad-bw,by);action.Instance.Size=UDim2.fromOffset(bw,46)
   tryButton.Instance.Position=UDim2.fromOffset(rw-pad-bw-12-tw,by);tryButton.Instance.Size=UDim2.fromOffset(tw,46)
  end
 end
 win.Resized:Connect(function()if self.IsOpen then layout()end end)

 -- STATE -----------------------------------------------------------------------------------------
 local function stateNow()local s=Net.State();s.Cash=Net.Cash();return s end
 local function status(i,s)
  if i==s.PickaxeLevel then return'hand'end
  if i<=s.PickaxeOwned then return'owned'end
  if i==s.PickaxeOwned+1 then return'next'end
  return'locked'
 end

 local function setPreview(def,level)
  if preview then preview.Model:Destroy();if ctx.PickFX then ctx.PickFX.Untrack(preview.Model)end;preview=nil end
  local model=Models.Pickaxe(def,level)
  model.Parent=stage
  local cam=stage:FindFirstChildOfClass('Camera')or Kit.New('Camera',{FieldOfView=30},stage)
  stage.CurrentCamera=cam
  local len=(def.Visual and def.Visual.Length)or 4.2
  local dist=len>5 and 12.5 or 10.5
  cam.CFrame=CFrame.lookAt(Vector3.new(0,.9,dist),Vector3.new(0,.9,0))
  preview={Model=model,Spin=0,Kick=0,Base=CFrame.Angles(0,0,math.rad(-28))}
  if ctx.PickFX then ctx.PickFX.Track(model,true)end
 end

 local function renderTiles(s)
  for i,t in ipairs(tiles)do
   local st=status(i,s)
   local def=M.Pickaxes[i]
   local col=rarityColor(def.Rarity)
   t.Badge.Text=(st=='hand'and'✋')or(st=='owned'and'✔')or(st=='next'and'➜')or'🔒'
   t.Badge.TextColor3=(st=='hand'and P.blue)or(st=='owned'and P.green)or(st=='next'and P.gold)or P.muted
   t.Stroke.Color=i==selected and col or P.edge
   t.Stroke.Thickness=i==selected and 3 or 2
   t.Face.BackgroundColor3=i==selected and col:Lerp(Theme.White,.82)or Theme.White
   t.Name.TextColor3=st=='locked'and P.muted or P.text
   t.Icon.TextTransparency=st=='locked'and .45 or 0
  end
  local owned=s.PickaxeOwned
  listTitle.Text=L('COLLECTION ','КОЛЛЕКЦИЯ ')..owned..' / '..#M.Pickaxes
 end
 local function buildTiles()
  for i,def in ipairs(M.Pickaxes)do
   local col=rarityColor(def.Rarity)
   local b=Kit.New('TextButton',{Name='Pick'..i,Text='',AutoButtonColor=false,BackgroundTransparency=1,Size=UDim2.new(1,0,0,62),LayoutOrder=i,ZIndex=5},list)
   local face=Base.Face(b,Theme.White,Theme.Radius.Button,5)
   local stroke=Kit.Stroke(face,P.edge,2)
   local stripe=Kit.New('Frame',{Name='Stripe',BackgroundColor3=col,BorderSizePixel=0,Position=UDim2.fromOffset(6,6),Size=UDim2.new(0,6,1,-12),ZIndex=6},b)
   Kit.Corner(stripe,3)
   local disc=Kit.New('Frame',{Name='IconDisc',BackgroundColor3=col:Lerp(Theme.White,.55),BorderSizePixel=0,Position=UDim2.fromOffset(18,7),Size=UDim2.fromOffset(48,48),ZIndex=6},b)
   Kit.Corner(disc,'pill');Kit.Stroke(disc,col,2)
   local icon=Kit.Text(disc,{Text=def.Icon or'⛏',TextSize=30,Scaled=true,AlignX='Center',ZIndex=7,NoTranslate=true})
   local name=Kit.Text(b,{Text=Text.Name(def),TextSize=17,Scaled=true,MinTextSize=10,Position=UDim2.fromOffset(74,8),Size=UDim2.new(1,-120,0,24),ZIndex=6,NoTranslate=true})
   local rar=Kit.Text(b,{Text=rarityName(def.Rarity),TextSize=12,Scaled=true,MinTextSize=8,Color=col:Lerp(P.text,.25),Position=UDim2.fromOffset(74,33),Size=UDim2.new(1,-120,0,18),ZIndex=6,NoTranslate=true,Font=PIXEL})
   local badge=Kit.Text(b,{Text='',TextSize=24,Scaled=true,AlignX='Center',AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(32,32),ZIndex=6,NoTranslate=true})
   Base.Press(b,b,nil,1.025)
   b.Activated:Connect(function()self.Select(i)end)
   tiles[i]={Button=b,Face=face,Stroke=stroke,Badge=badge,Name=name,Icon=icon,Rarity=rar}
  end
 end
 buildTiles()

 function self.Select(i,instant)
  selected=math.clamp(i,1,#M.Pickaxes)
  local def=M.Pickaxes[selected]
  local s=stateNow()
  local col=rarityColor(def.Rarity)
  local grad=Theme.RarityGradient[def.Rarity]
  bannerGrad.Color=grad and ColorSequence.new(grad[1],grad[2])or ColorSequence.new(col:Lerp(Theme.White,.2),col)
  bannerText.Text=rarityName(def.Rarity)
  stageGrad.Color=ColorSequence.new(col:Lerp(Color3.fromRGB(20,26,44),.35),Color3.fromRGB(18,22,38))
  number.Text='#'..selected..'/'..#M.Pickaxes
  nameLabel.Text=(def.Icon or'⛏')..' '..Text.Name(def)
  nameLabel.TextColor3=col:Lerp(P.text,.45)
  lore.Text=Text.IsRussian()and(def.LoreRU or def.Lore or'')or(def.Lore or'')
  trait.Text='<b>'..Text.Get('PICK_TRAIT')..':</b> '..(Text.IsRussian()and(def.TraitRU or def.Trait)or def.Trait or'')
  for _,st in ipairs(STATS)do
   st.Label2.Text=Text.IsRussian()and st.Label[2]or string.upper(st.Label[1])
   st.ValueLabel.Text=st.Format(def)
   local v=st.Value(def)/math.max(1e-6,st.Max())
   if st.Log then v=math.log(1+st.Value(def))/math.log(1+st.Max())end
   st.Bar:SetValue(math.clamp(v,.03,1),instant)
  end
  setPreview(def,selected)
  self.RenderAction(s)
  renderTiles(s)
  if not instant and not Kit.Motion.Reduced()then
   showScale.Scale=fit*.97 -- pop around the fit scale, not 1, so it does not undo the fit
   popTween=TweenService:Create(showScale,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=fit});popTween:Play()
  end
 end
 function self.RenderAction(s)
  s=s or stateNow()
  local def=M.Pickaxes[selected]
  local st=status(selected,s)
  local needC=s.Cash<def.Price;local needS=s.Strength<def.Strength
  priceChip:Set('💰 '..(def.Price>0 and Text.Short(def.Price)or Text.Get('FREE')),(st=='owned'or st=='hand'or not needC)and P.gold or P.red)
  strengthChip:Set('💪 '..def.Strength,(st=='owned'or st=='hand'or not needS)and P.green or P.red)
  local label,style
  if st=='hand'then label,style=Text.Get('IN_HAND'),'primary'
  elseif st=='owned'then label,style=Text.Get('EQUIP'),'success'
  elseif st=='locked'then label,style=Text.Get('PREVIOUS_FIRST'),'secondary'
  elseif needS then label,style=Text.Get('NEED_MORE_STRENGTH'),'secondary'
  elseif needC then label,style=Text.Get('NEED_MORE_COINS'),'secondary'
  else label,style=Text.Get('BUY'),'gold'end
  action:SetText(label);action:SetStyle(style)
  stateTag.Text=(st=='hand'and Text.Get('IN_HAND'))or(st=='owned'and Text.Get('OWNED'))or(st=='next'and Text.Get('NEXT_UP'))or Text.Get('LOCKED_SHORT')
  stateTag.TextColor3=(st=='hand'and Color3.fromRGB(120,200,255))or(st=='owned'and Color3.fromRGB(150,255,130))or(st=='next'and Color3.fromRGB(255,214,90))or Color3.fromRGB(200,200,210)
  win:SetTitle(nil,Text.Get('YOUR_COINS',Text.Short(s.Cash))..'   ·   '..Text.Get('YOUR_STRENGTH',s.Strength)..'   ·   '..Text.Get('YOUR_STONE',Text.Short(tonumber(Net.Attr('Stone',0))or 0)))
 end
 local function buy(level)
  if busy then return end
  busy=true;action:SetBusy(true)
  local ok,msg=Net.Invoke('MiningPickaxe',{Level=level})
  busy=false;action:SetBusy(false)
  if ok then
   Audio.Play('Buy');Hud.Toast(msg,P.green)
   sparkle(action.Instance,18,{P.gold,P.green,Theme.White,rarityColor(M.Pickaxes[level].Rarity)})
   if preview and ctx.PickFX then ctx.PickFX.PreviewPulse(preview.Model);preview.Kick=1 end
  else Audio.Play('Deny');Hud.Toast(msg,P.red)end
  if self.IsOpen then self.RenderAction();renderTiles(stateNow())end
 end
 function self.Action()
  local s=stateNow();local def=M.Pickaxes[selected];local st=status(selected,s)
  if st=='hand'then return end
  if st=='owned'then buy(selected);return end
  if st=='locked'then Audio.Play('Deny');Hud.Toast(Text.Get('IN_ORDER'),P.gold);self.Select(s.PickaxeOwned+1);return end
  if s.Strength<def.Strength then Audio.Play('Deny');Hud.Toast(Text.Get('NEED_STRENGTH',def.Strength),P.gold);return end
  if s.Cash<def.Price then
   Audio.Play('Deny')
   Hud.Toast(Text.Get('NEED_COINS',Text.Short(def.Price))..(selected==1 and(' · '..Text.Get('SELL_HINT'))or''),P.gold,selected==1 and 4 or nil)
   return
  end
  buy(selected)
 end
 function self.TryHit()
  local def=M.Pickaxes[selected]
  Audio.Play(math.random()<.25 and'Crit'or'Hit',nil,def.FX,def.Sound)
  if preview then preview.Kick=1;if ctx.PickFX then ctx.PickFX.PreviewPulse(preview.Model)end end
  local pal=ctx.PickFX and ctx.PickFX.Palette(def.Theme)or{P.gold}
  sparkle(stage,12,pal)
 end

 -- OPEN / CLOSE ------------------------------------------------------------------------------------
 function self.Open(corner)
  if (ctx.Mine and ctx.Mine.Active)or(ctx.Gym and ctx.Gym.Active)then return end
  self.Corner=corner
  local s=stateNow()
  local start=(s.PickaxeOwned<#M.Pickaxes and s.PickaxeOwned+1)or math.max(1,s.PickaxeLevel)
  win:Open()
  self.IsOpen=win.IsOpen
  if not self.IsOpen then return end
  layout()
  self.Select(start,true)
  -- Tutorial step 7: the first pickaxe glows gold.
  if s.PickaxeOwned==0 and player:GetAttribute('TutorialActive')==true and player:GetAttribute('TutorialStep')==7 then
   local t=tiles[1];if t then t.Stroke.Color=P.gold;t.Stroke.Thickness=4 end
  end
  if spinConn then spinConn:Disconnect()end
  spinConn=RunService.RenderStepped:Connect(function(dt)
   if not preview or not preview.Model.Parent then return end
   preview.Spin+=dt*(.9+preview.Kick*12)
   preview.Kick=math.max(0,preview.Kick-dt*2.5)
   local bob=math.sin(os.clock()*1.6)*.12
   local swing=preview.Kick>0 and math.sin(preview.Kick*math.pi)*.6 or 0
   preview.Model:PivotTo(CFrame.new(0,bob,0)*CFrame.Angles(0,preview.Spin,0)*preview.Base*CFrame.Angles(swing,0,0))
   bannerGrad.Offset=Vector2.new(math.sin(os.clock()*1.4)*.35,0)
  end)
 end
 function self.Close()
  if not self.IsOpen then return end
  win:Close('close')
  self.IsOpen=false
 end

 for _,name in ipairs({'MiningStrength','MiningPickaxe','MiningPickaxeOwned'})do
  player:GetAttributeChangedSignal(name):Connect(function()if self.IsOpen and not busy then self.RenderAction();renderTiles(stateNow())end end)
 end
 player:GetAttributeChangedSignal('Stone'):Connect(function()if self.IsOpen then self.RenderAction()end end)
 task.spawn(function()
  local stats=player:WaitForChild('leaderstats',30);local coins=stats and stats:WaitForChild('Coins',30)
  if coins then coins.Changed:Connect(function()if self.IsOpen and not busy then self.RenderAction()end end)end
 end)
 player.CharacterRemoving:Connect(function()self.Close()end)

 return self
end

return Shop
