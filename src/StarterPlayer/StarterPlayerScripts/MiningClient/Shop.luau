-- Pickaxe market: a game-styled window opened from the pickaxe sign. Seven pickaxes with a 3D
-- preview, what makes each one different, and the Coins + Strength each needs.
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local TweenService=game:GetService('TweenService')
local Shop={}

function Shop.new(ctx)
 local self:any={IsOpen=false}
 local player=ctx.Player
 local M,Text,Audio,U,N,Models,Rules=ctx.M,ctx.Text,ctx.Audio,ctx.U,ctx.N,ctx.Models,ctx.Rules
 local Net,Hud=ctx.Net,ctx.Hud
 local font=U.FontFace or Font.fromEnum(Enum.Font.FredokaOne)
 local OWNER='MiningShop'

 local gui=Instance.new('ScreenGui');gui.Name='MiningShop';gui.ResetOnSpawn=false;gui.DisplayOrder=70;gui.Enabled=false
 gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui:SetAttribute('NoTranslate',true);gui.Parent=ctx.PlayerGui
 local root=Instance.new('Frame');root.Name='Window';root.AnchorPoint=Vector2.new(.5,.5);root.Position=UDim2.fromScale(.5,.5)
 root.BackgroundColor3=Color3.fromRGB(255,251,242);root.BorderSizePixel=0;root.Parent=gui
 U.Round(root,16);U.Stroke(root,U.Colors.edge,3)
 local scale=Instance.new('UIScale');scale.Parent=root
 local title=U.Text(root,'',24,14,600,40,28,U.Colors.text,true)
 local subtitle=U.Text(root,'',24,56,700,26,17,U.Colors.muted)
 local list=Instance.new('ScrollingFrame');list.Name='List';list.BackgroundTransparency=1;list.BorderSizePixel=0
 list.ScrollBarThickness=8;list.ScrollBarImageColor3=U.Colors.edge;list.CanvasSize=UDim2.new();list.Parent=root
 local footer=U.Text(root,'',24,0,700,24,15,U.Colors.muted)
 local closeButton=U.Button(root,'Close','×',0,14,44,40,function()self.Close()end,U.Colors.red)

 local W,H,columns=900,640,2
 local function layout()
  local _,_,width,height=U.SafeArea(gui)
  local compact=width<720 or height<520
  columns=compact and 1 or 2
  W=compact and math.min(560,width-16)or 900
  H=compact and math.min(860,height-16)or 640
  local factor=math.max(.3,math.min(1,(width-24)/W,(height-24)/H))
  scale.Scale=factor
  root.Size=UDim2.fromOffset(W,H)
  root.Position=U.SafePosition(gui,W,H,factor,12)
  title.Size=UDim2.fromOffset(W-110,40);subtitle.Size=UDim2.fromOffset(W-48,26)
  closeButton.Position=UDim2.fromOffset(W-62,14)
  list.Position=UDim2.fromOffset(16,92);list.Size=UDim2.fromOffset(W-32,H-92-46)
  footer.Position=UDim2.fromOffset(24,H-40);footer.Size=UDim2.fromOffset(W-48,26)
 end

 local previews={}
 local spin=nil
 local function preview(parent,def,level,x,y,size)
  local vp=Instance.new('ViewportFrame');vp.Name='Preview';vp.Position=UDim2.fromOffset(x,y);vp.Size=UDim2.fromOffset(size,size)
  vp.BackgroundColor3=Color3.fromRGB(32,44,66);vp.BorderSizePixel=0;vp.Ambient=Color3.fromRGB(170,170,180);vp.LightColor=Color3.new(1,1,1)
  vp.LightDirection=Vector3.new(-1,-1.4,-1);vp.Parent=parent
  U.Round(vp,12)
  local model=Models.Pickaxe(def,level)
  model.Parent=vp
  local cam=Instance.new('Camera');cam.FieldOfView=32;cam.CFrame=CFrame.lookAt(Vector3.new(0,.6,9.2),Vector3.new(0,.6,0));cam.Parent=vp
  vp.CurrentCamera=cam
  table.insert(previews,{Model=model,Phase=level*.7})
  return vp
 end

 local function stateNow()
  local s=Net.State();s.Cash=Net.Cash();return s
 end
 local function pct(x)return math.floor((x or 0)*100+.5)..'%'end
 local function statLines(def)
  local a=Text.Get('DAMAGE')..' '..def.Damage..'  ·  '..Text.Get('CIRCLES')..' '..def.Circles..'  ·  '..Text.Get('CRIT_CHANCE')..' '..pct(def.CritChance)
  local b=Text.Get('LUCK')..' +'..pct(def.Luck)..'  ·  '..Text.Get('COIN_BONUS')..' +'..pct(def.CoinBonus)..'  ·  '..Text.Get('WINDOW')..' '..string.format('%.2f',def.Window)..'s'
  return a,b
 end
 local busy=false
 local function buy(level)
  if busy then return end
  busy=true
  local ok,msg=Net.Invoke('MiningPickaxe',{Level=level})
  busy=false
  if ok then Audio.Play('Buy');Hud.Toast(msg,U.Colors.green)else Audio.Play('Deny');Hud.Toast(msg,U.Colors.red)end
  if self.IsOpen then self.Render()end
 end

 function self.Render()
  for _,c in ipairs(list:GetChildren())do c:Destroy()end
  table.clear(previews)
  local s=stateNow()
  title.Text='⛏ '..Text.Get('PICKAXE_SHOP')
  subtitle.Text=Text.Get('YOUR_COINS',Text.Short(s.Cash))..'   ·   '..Text.Get('YOUR_STRENGTH',s.Strength)
  footer.Text=Text.L('Train Strength at the weight rack · better pickaxes need Coins AND Strength',
   'Качай силу у стойки с гирями · для лучших кирок нужны монеты И сила')
  local gap=12
  local cardW=math.floor((W-32-gap*(columns+1)-8)/columns)
  local cardH=212
  local easy,hard=M.Ores[1],M.Ores[#M.Ores]
  for i,def in ipairs(M.Pickaxes)do
   local col=(i-1)%columns;local row=math.floor((i-1)/columns)
   local card=Instance.new('Frame');card.Name='Pickaxe'..i;card.Position=UDim2.fromOffset(gap+col*(cardW+gap),gap+row*(cardH+gap))
   card.Size=UDim2.fromOffset(cardW,cardH);card.BackgroundColor3=Color3.new(1,1,1);card.BorderSizePixel=0;card.Parent=list
   U.Round(card,14)
   local owned=i<=s.PickaxeOwned;local equipped=i==s.PickaxeLevel;local nextOne=i==s.PickaxeOwned+1
   local color=Color3.fromRGB(table.unpack(def.Color))
   U.Stroke(card,equipped and U.Colors.blue or(owned and U.Colors.green or U.Colors.edge),equipped and 4 or 2)
   local stripe=Instance.new('Frame');stripe.Size=UDim2.new(0,8,1,-16);stripe.Position=UDim2.fromOffset(8,8);stripe.BackgroundColor3=color;stripe.BorderSizePixel=0;stripe.Parent=card
   U.Round(stripe,4)
   preview(card,def,i,24,14,112)
   local x=148;local w=cardW-x-12
   local name=U.Text(card,(def.Icon or'⛏')..' '..Text.Name(def),x,10,w,28,20,U.Colors.text,true)
   name.TextColor3=color:Lerp(U.Colors.text,.55)
   local trait=U.Text(card,Text.IsRussian()and(def.TraitRU or def.Trait)or def.Trait,x,38,w,40,14,U.Colors.purple)
   trait.TextWrapped=true;trait.TextYAlignment=Enum.TextYAlignment.Top
   local a,b=statLines(def)
   U.Text(card,a,x,80,w,20,13,U.Colors.muted)
   U.Text(card,b,x,100,w,20,13,U.Colors.muted)
   local m=Rules.New(M);m.Strength=math.max(s.Strength,def.Strength)
   local hits=Text.Name(easy)..' ~'..Rules.HitsToBreak(M,m,def,easy)..'  ·  '..Text.Name(hard)..' ~'..Rules.HitsToBreak(M,m,def,hard)
   U.Text(card,'⚒ '..hits,x,120,w,20,13,U.Colors.text)
   local needCoins=s.Cash<def.Price;local needStrength=s.Strength<def.Strength
   local req=U.Text(card,'',16,cardH-66,cardW-180,24,15,U.Colors.text,true)
   req.Text='💰 '..(def.Price>0 and Text.Short(def.Price)or Text.Get('FREE'))..'    💪 '..def.Strength
   req.TextColor3=(owned and U.Colors.green)or((needCoins or needStrength)and U.Colors.red)or U.Colors.text
   local label,color2,fn
   if equipped then label,color2=Text.Get('IN_HAND'),U.Colors.blue
   elseif owned then label,color2,fn=Text.Get('TAKE'),U.Colors.green,function()buy(i)end
   elseif not nextOne then label,color2=Text.Get('PREVIOUS_FIRST'),U.Colors.muted
   elseif needStrength then label,color2,fn=Text.Get('NEED_MORE_STRENGTH'),U.Colors.muted,function()
     Audio.Play('Deny');Hud.Toast(Text.Get('NEED_STRENGTH',def.Strength),U.Colors.gold)end
   elseif needCoins then label,color2,fn=Text.Get('NEED_MORE_COINS'),U.Colors.muted,function()
     Audio.Play('Deny');Hud.Toast(Text.Get('NEED_COINS',Text.Short(def.Price)),U.Colors.gold)end
   else label,color2,fn=Text.Get('BUY'),U.Colors.green,function()buy(i)end end
   local button=U.Button(card,'Action',label,cardW-176,cardH-56,164,44,fn,color2)
   button.ZIndex=5
   if (owned or nextOne)and not needStrength and def.Strength>0 then
    U.Text(card,'✔ '..Text.Get('STRENGTH_VALUE',def.Strength),16,cardH-40,cardW-200,22,13,U.Colors.green)
   elseif needStrength and nextOne then
    U.Text(card,Text.L('Lift weights to reach it','Подними гири, чтобы дорасти'),16,cardH-40,cardW-200,22,13,U.Colors.red)
   end
  end
  local rows=math.ceil(#M.Pickaxes/columns)
  list.CanvasSize=UDim2.fromOffset(0,gap+rows*(cardH+gap))
 end

 function self.Open(corner)
  if self.IsOpen then return end
  if (ctx.Mine and ctx.Mine.Active)or(ctx.Gym and ctx.Gym.Active)then return end
  self.IsOpen=true;self.Corner=corner
  N.Acquire(OWNER,OWNER)
  layout();self.Render();gui.Enabled=true
  Audio.Play('Click')
  root.Position=root.Position+UDim2.fromOffset(0,24)
  TweenService:Create(root,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=U.SafePosition(gui,W,H,scale.Scale,12)}):Play()
  spin=RunService.RenderStepped:Connect(function()
   local t=os.clock()
   for _,p in ipairs(previews)do
    if p.Model.Parent then p.Model:PivotTo(CFrame.Angles(0,t*.9+p.Phase,0)*CFrame.Angles(0,0,math.rad(-35)))end
   end
  end)
 end
 function self.Close()
  if not self.IsOpen then return end
  self.IsOpen=false;gui.Enabled=false
  if spin then spin:Disconnect();spin=nil end
  if N.Owner==OWNER then N.Close()end
 end

 for _,name in ipairs({'MiningStrength','MiningPickaxe','MiningPickaxeOwned'})do
  player:GetAttributeChangedSignal(name):Connect(function()if self.IsOpen and not busy then self.Render()end end)
 end
 task.spawn(function()
  local stats=player:WaitForChild('leaderstats',30);local coins=stats and stats:WaitForChild('Coins',30)
  -- Coins change often (dogs dig); rebuild the cards only when a price becomes (un)affordable.
  local function affordKey()
   local cash=Net.Cash();local key={}
   for i,p in ipairs(M.Pickaxes)do key[i]=cash>=p.Price and'1'or'0'end
   return table.concat(key)
  end
  local lastKey=''
  if coins then coins.Changed:Connect(function()if self.IsOpen and not busy then
   local s=stateNow();subtitle.Text=Text.Get('YOUR_COINS',Text.Short(s.Cash))..'   ·   '..Text.Get('YOUR_STRENGTH',s.Strength)
   local key=affordKey();if key~=lastKey then lastKey=key;self.Render()end
  end end)end
 end)
 UIS.InputBegan:Connect(function(input)if self.IsOpen and(input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB)then self.Close()end end)
 ctx.Main:GetAttributeChangedSignal('OpenMenu'):Connect(function()
  if self.IsOpen and N.Owner~=OWNER then self.IsOpen=false;gui.Enabled=false;if spin then spin:Disconnect();spin=nil end end
 end)
 gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if self.IsOpen then layout();self.Render()end end)
 player.CharacterRemoving:Connect(function()self.Close()end)

 return self
end

return Shop
