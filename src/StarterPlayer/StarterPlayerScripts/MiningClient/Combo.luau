-- The 2D "juice" of Active Mining: every successful click bursts into a colourful shockwave at the
-- circle (rainbow / lava / diamond / cosmic / magic / robot / alien styles cycle with the combo),
-- an "xN" pops up there, and the endless combo counter grows on the right with a heat bar.
-- Milestones (10, 25, 50, 100, then every 100) get a full-screen celebration; crits a big stamp.
-- Also used by the strength training ("REPS xN"). Everything respects Low FX / Reduced Motion.
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local Combo={}

local C=Color3.fromRGB
local PIXEL=Font.fromEnum(Enum.Font.FredokaOne)
local STYLES={
 {Name='RAINBOW',RU='РАДУГА',Colors=nil,Glyphs={'✦','★','✧'}},
 {Name='LAVA',RU='ЛАВА',Colors={C(255,60,20),C(255,140,30),C(255,220,80)},Glyphs={'✹','✸','●'}},
 {Name='DIAMOND',RU='АЛМАЗ',Colors={C(210,245,255),C(120,220,255),C(255,255,255)},Glyphs={'◆','◇','✦'}},
 {Name='COSMIC',RU='КОСМОС',Colors={C(150,80,255),C(80,130,255),C(255,120,230)},Glyphs={'★','✧','✦'}},
 {Name='MAGIC',RU='МАГИЯ',Colors={C(255,120,220),C(255,220,120),C(190,120,255)},Glyphs={'✧','♥','✦'}},
 {Name='ROBOT',RU='РОБОТ',Colors={C(80,255,220),C(60,200,255),C(200,255,120)},Glyphs={'▣','■','◼'}},
 {Name='ALIEN',RU='ПРИШЕЛЕЦ',Colors={C(140,255,60),C(60,255,160),C(200,90,255)},Glyphs={'◉','◎','👽'}},
}
Combo.Styles=STYLES
local MILESTONES={[10]=true,[25]=true,[50]=true,[75]=true}
-- The hit counter over a struck circle: a juicy pink "x23" (candy gradient, deep pink outline).
local PINK={Colors={C(255,170,225),C(255,92,182),C(226,40,150)},Stroke=C(118,16,78)}
local GOLDEN={Colors={C(255,250,190),C(255,214,80),C(255,150,40)},Stroke=C(120,60,10)}

local function rainbowSeq(offset)
 local k={}
 for i=0,6 do k[#k+1]=ColorSequenceKeypoint.new(i/6,Color3.fromHSV((i/6+(offset or 0))%1,.75,1))end
 return ColorSequence.new(k)
end
local function seq(colors)
 if not colors then return rainbowSeq(math.random())end
 return ColorSequence.new({ColorSequenceKeypoint.new(0,colors[1]),ColorSequenceKeypoint.new(.5,colors[2]),ColorSequenceKeypoint.new(1,colors[3]or colors[1])})
end
local function color(style)
 if not style.Colors then return Color3.fromHSV(math.random(),.7,1)end
 return style.Colors[math.random(1,#style.Colors)]
end

function Combo.new(ctx)
 local self:any={Count=0,Best=0,LastAt=0,Timeout=3.2}
 local FX,Text,Audio=ctx.FX,ctx.Text,ctx.Audio
 local gui=ctx.Gui::ScreenGui
 local function low()return FX.Low()end
 local function reduced()return FX.ReducedMotion and FX.ReducedMotion()end

 local layer=Instance.new('Frame');layer.Name='ComboFX';layer.Size=UDim2.fromScale(1,1);layer.BackgroundTransparency=1;layer.ZIndex=60
 layer.Active=false;layer.Parent=gui

 -- COUNTER ---------------------------------------------------------------------------------------
 local counter=Instance.new('Frame');counter.Name='ComboCounter';counter.AnchorPoint=Vector2.new(1,.5);counter.Position=UDim2.new(1,-28,.42,0)
 counter.Size=UDim2.fromOffset(230,150);counter.BackgroundTransparency=1;counter.Visible=false;counter.ZIndex=70;counter.Parent=layer
 local counterScale=Instance.new('UIScale');counterScale.Parent=counter
 -- Narrow landscape screens (phones): the centred 460 px ore panel (top ~46-58, ~130 px tall with its Stone pill) reaches
 -- x = W/2+230 and would sit under the 230 px counter. Shrink the counter into the gap at the right edge;
 -- where even half size does not fit, also drop it below the panel. UIScale scales around AnchorPoint (1,.5).
 local rest=1
 local function layoutCounter()
  local size=gui.AbsoluteSize
  if size.X>=1000 or size.Y*.42-75>=190 then rest=1;counter.Position=UDim2.new(1,-28,.42,0)
  else
   local room=(size.X/2-246)/230
   rest=math.clamp(room,.5,.8)
   counter.Position=UDim2.new(1,-10,0,math.floor(room<rest and math.max(size.Y*.42,190+75*rest)or size.Y*.42))
  end
  counterScale.Scale=rest
 end
 gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(layoutCounter);layoutCounter()
 local caption=Instance.new('TextLabel');caption.Name='Caption';caption.BackgroundTransparency=1;caption.Size=UDim2.new(1,0,0,28)
 caption.FontFace=PIXEL;caption.TextScaled=true;caption.TextColor3=Color3.new(1,1,1);caption.TextStrokeTransparency=0;caption.TextStrokeColor3=C(20,24,48)
 caption.TextXAlignment=Enum.TextXAlignment.Right;caption.ZIndex=71;caption.Parent=counter
 local big=Instance.new('TextLabel');big.Name='Value';big.BackgroundTransparency=1;big.Position=UDim2.fromOffset(0,26);big.Size=UDim2.new(1,0,0,90)
 big.FontFace=PIXEL;big.TextScaled=true;big.TextColor3=Color3.new(1,1,1);big.TextXAlignment=Enum.TextXAlignment.Right;big.ZIndex=72;big.Parent=counter
 local bigGrad=Instance.new('UIGradient');bigGrad.Color=rainbowSeq(0);bigGrad.Rotation=20;bigGrad.Parent=big
 local bigStroke=Instance.new('UIStroke');bigStroke.Color=C(20,24,48);bigStroke.Thickness=4;bigStroke.Parent=big
 local heatBack=Instance.new('Frame');heatBack.Name='Heat';heatBack.AnchorPoint=Vector2.new(1,0);heatBack.Position=UDim2.new(1,0,0,122)
 heatBack.Size=UDim2.new(.8,0,0,12);heatBack.BackgroundColor3=C(20,24,48);heatBack.BackgroundTransparency=.2;heatBack.ZIndex=71;heatBack.Parent=counter
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=heatBack end
 local heat=Instance.new('Frame');heat.Name='Fill';heat.AnchorPoint=Vector2.new(1,0);heat.Position=UDim2.fromScale(1,0);heat.Size=UDim2.fromScale(1,1)
 heat.BackgroundColor3=Color3.new(1,1,1);heat.ZIndex=72;heat.Parent=heatBack
 do local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=heat
  local g=Instance.new('UIGradient');g.Color=rainbowSeq(.3);g.Parent=heat end
 -- Edge glow on hot streaks.
 local edge=Instance.new('Frame');edge.Name='EdgeGlow';edge.Size=UDim2.fromScale(1,1);edge.BackgroundTransparency=1;edge.ZIndex=61;edge.Parent=layer
 local edgeStroke=Instance.new('UIStroke');edgeStroke.Thickness=16;edgeStroke.Transparency=1;edgeStroke.Color=Color3.new(1,1,1);edgeStroke.Parent=edge
 local edgeGrad=Instance.new('UIGradient');edgeGrad.Color=rainbowSeq(0);edgeGrad.Parent=edgeStroke

 local label='COMBO'
 local function ru()return Text.IsRussian()end
 local function show(n)
  counter.Visible=n>=2
  big.Text='x'..n
  caption.Text=(label=='COMBO'and(ru()and'КОМБО'or'COMBO')or(ru()and'ПОВТОРЫ'or'REPS'))..(n>=10 and' 🔥'or'')
  if reduced()then return end
  counterScale.Scale=rest*(1.35+math.min(.4,n*.01))
  TweenService:Create(counterScale,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=rest}):Play()
  big.Rotation=math.random(-9,9)
  TweenService:Create(big,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Rotation=0}):Play()
 end

 -- BURSTS ----------------------------------------------------------------------------------------
 local function frame(props)
  local f=Instance.new('Frame');f.BorderSizePixel=0;f.AnchorPoint=Vector2.new(.5,.5);f.ZIndex=props.ZIndex or 65
  for k,v in pairs(props)do if k~='ZIndex'then(f::any)[k]=v end end
  f.Parent=layer;return f
 end
 local function ring(pos,size,thick,colors,life,startSize)
  local f=frame({Position=UDim2.fromOffset(pos.X,pos.Y),Size=UDim2.fromOffset(startSize or 16,startSize or 16),BackgroundTransparency=1})
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=f
  local s=Instance.new('UIStroke');s.Thickness=thick;s.Color=Color3.new(1,1,1);s.Parent=f
  local g=Instance.new('UIGradient');g.Color=seq(colors);g.Rotation=math.random(0,360);g.Parent=s
  TweenService:Create(f,TweenInfo.new(life,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(size,size)}):Play()
  TweenService:Create(s,TweenInfo.new(life,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Transparency=1,Thickness=1}):Play()
  TweenService:Create(g,TweenInfo.new(life),{Rotation=g.Rotation+160}):Play()
  Debris:AddItem(f,life+.05)
 end
 local function flashDisc(pos,size,colorValue,life)
  local f=frame({Position=UDim2.fromOffset(pos.X,pos.Y),Size=UDim2.fromOffset(size*.3,size*.3),BackgroundColor3=colorValue,BackgroundTransparency=.15})
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=f
  TweenService:Create(f,TweenInfo.new(life,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(size,size),BackgroundTransparency=1}):Play()
  Debris:AddItem(f,life+.05)
 end
 local function rays(pos,count,len,style,life)
  local base=math.random()*360
  for i=1,count do
   local a=base+i*360/count+math.random(-8,8)
   local r=math.rad(a)
   local f=frame({Position=UDim2.fromOffset(pos.X+math.cos(r)*14,pos.Y+math.sin(r)*14),Size=UDim2.fromOffset(len*.5,5),Rotation=a,BackgroundColor3=color(style)})
   local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=f
   local d=len*(.8+math.random()*.6)
   TweenService:Create(f,TweenInfo.new(life,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
    {Position=UDim2.fromOffset(pos.X+math.cos(r)*d,pos.Y+math.sin(r)*d),Size=UDim2.fromOffset(len*.12,2),BackgroundTransparency=1}):Play()
   Debris:AddItem(f,life+.05)
  end
 end
 local function sparks(pos,count,style,spread,life,size)
  for i=1,count do
   local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(.5,.5);l.ZIndex=66
   l.Position=UDim2.fromOffset(pos.X,pos.Y);l.Size=UDim2.fromOffset(size or 26,size or 26);l.TextScaled=true
   l.Text=style.Glyphs[math.random(1,#style.Glyphs)];l.TextColor3=color(style);l.FontFace=PIXEL
   l.TextStrokeTransparency=.2;l.TextStrokeColor3=C(20,24,48);l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true)
   l.Rotation=math.random(-40,40);l.Parent=layer
   local a=math.random()*math.pi*2;local d=spread*(.5+math.random()*.7)
   local goal=UDim2.fromOffset(pos.X+math.cos(a)*d,pos.Y+math.sin(a)*d+spread*.25)
   TweenService:Create(l,TweenInfo.new(life,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=goal,Rotation=l.Rotation+math.random(-180,180)}):Play()
   TweenService:Create(l,TweenInfo.new(life*.5,Enum.EasingStyle.Linear,Enum.EasingDirection.In,0,false,life*.5),{TextTransparency=1,TextStrokeTransparency=1}):Play()
   Debris:AddItem(l,life+.05)
  end
 end
 local function stamp(pos,textValue,size,style,life,rise)
  local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(.5,.5);l.ZIndex=75
  l.Position=UDim2.fromOffset(pos.X,pos.Y);l.Size=UDim2.fromOffset(size*math.max(2,utf8.len(textValue)or 2)*.62,size);l.TextScaled=true
  l.FontFace=PIXEL;l.Text=textValue;l.TextColor3=Color3.new(1,1,1);l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true)
  local g=Instance.new('UIGradient');g.Color=seq(style.Colors);g.Rotation=90;g.Parent=l
  local s=Instance.new('UIStroke');s.Color=style.Stroke or C(20,24,48);s.Thickness=math.max(2.5,size/11);s.Parent=l
  local sc=Instance.new('UIScale');sc.Scale=reduced()and 1 or 2.2;sc.Parent=l
  l.Rotation=math.random(-10,10);l.Parent=layer
  if not reduced()then TweenService:Create(sc,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()end
  TweenService:Create(l,TweenInfo.new(life,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromOffset(pos.X,pos.Y-(rise or 40))}):Play()
  TweenService:Create(l,TweenInfo.new(life*.35,Enum.EasingStyle.Linear,Enum.EasingDirection.In,0,false,life*.65),{TextTransparency=1}):Play()
  TweenService:Create(s,TweenInfo.new(life*.35,Enum.EasingStyle.Linear,Enum.EasingDirection.In,0,false,life*.65),{Transparency=1}):Play()
  Debris:AddItem(l,life+.05)
  return l
 end
 self.Stamp=stamp
 local function screenFlash(colorValue,strength)
  if reduced()then return end
  local f=Instance.new('Frame');f.Size=UDim2.fromScale(1,1);f.BackgroundColor3=colorValue;f.BackgroundTransparency=1-(strength or .3);f.ZIndex=62;f.Parent=layer
  TweenService:Create(f,TweenInfo.new(.35),{BackgroundTransparency=1}):Play()
  Debris:AddItem(f,.4)
 end
 -- TV theme: a short glitch of colour bars over the screen.
 function self.Glitch()
  if reduced()or low()then return end
  for i=1,5 do
   local f=Instance.new('Frame');f.BorderSizePixel=0;f.ZIndex=63;f.Position=UDim2.new(0,0,math.random(),0);f.Size=UDim2.new(1,0,0,math.random(4,22))
   f.BackgroundColor3=({C(110,255,130),C(255,80,220),C(90,220,255)})[math.random(1,3)];f.BackgroundTransparency=.55;f.Parent=layer
   TweenService:Create(f,TweenInfo.new(.16,Enum.EasingStyle.Linear),{BackgroundTransparency=1,Position=UDim2.new((math.random()-.5)*.1,0,f.Position.Y.Scale,0)}):Play()
   Debris:AddItem(f,.2)
  end
 end

 function self.Style(n)return STYLES[((n or self.Count)%#STYLES)+1]end

 -- A successful click at screen position pos (Vector2). quality 2 = gold ring.
 function self.Hit(pos,quality,themeColor)
  local now=os.clock()
  if now-self.LastAt>self.Timeout then self.Count=0 end
  self.Count+=1;self.LastAt=now
  self.Best=math.max(self.Best,self.Count)
  local n=self.Count
  local style=self.Style(n)
  local power=(quality==2 and 1.3 or 1)*(1+math.min(1.2,n*.02))
  local lite=low()
  ring(pos,170*power,8,nil,.5)
  if not lite then
   ring(pos,110*power,5,style.Colors,.38)
   flashDisc(pos,90*power,themeColor or color(style),.3)
   rays(pos,quality==2 and 12 or 8,70*power,style,.4)
  end
  sparks(pos,lite and 3 or(quality==2 and 9 or 6),style,90*power,.6)
  local tag=stamp(pos-Vector2.new(0,52),'x'..n,quality==2 and 50 or 40,PINK,.75,56)
  if quality==2 and tag then
   stamp(pos+Vector2.new(0,44),Text.IsRussian()and'ИДЕАЛЬНО!'or'PERFECT!',26,GOLDEN,.6,24)
  end
  label='COMBO';show(n)
  if n>=25 and not reduced()then
   edgeStroke.Transparency=.35;TweenService:Create(edgeStroke,TweenInfo.new(.5),{Transparency=1}):Play()
   edgeGrad.Color=style.Colors and seq(style.Colors)or rainbowSeq(math.random())
  end
  if MILESTONES[n]or(n>=100 and n%100==0)then self.Milestone(n,style)end
  return n,style
 end
 function self.Milestone(n,style)
  local size=gui.AbsoluteSize
  local center=Vector2.new(size.X/2,size.Y*.38)
  stamp(center,(Text.IsRussian()and'КОМБО x'or'COMBO x')..n..'!!',n>=100 and 84 or 66,style,1.4,30)
  stamp(center+Vector2.new(0,70),Text.IsRussian()and style.RU or style.Name,34,style,1.2,10)
  ring(center,size.X*.7,14,nil,.8,40)
  sparks(center,low()and 10 or 26,style,size.Y*.45,1.1,34)
  screenFlash(color(style),.28)
  FX.Shake(1.6)
  if Audio then Audio.Play('Milestone')end
 end
 function self.Crit(pos,themeColor,textValue)
  local style=self.Style(self.Count+3)
  ring(pos,260,12,nil,.6,30)
  stamp(pos-Vector2.new(0,90),textValue or(Text.IsRussian()and'КРИТ!'or'CRIT!'),56,{Colors={C(255,90,60),C(255,220,80),C(255,255,255)}},.9,60)
  sparks(pos,low()and 4 or 12,style,150,.8,30)
  screenFlash(themeColor or C(255,220,150),.22)
 end
 function self.Break(pos,colorValue)
  local style=self.Style(self.Count+1)
  ring(pos,420,16,nil,.75,40)
  ring(pos,300,10,style.Colors,.6,30)
  sparks(pos,low()and 8 or 20,style,240,1,32)
  screenFlash(colorValue or Color3.new(1,1,1),.2)
 end
 -- Combo lost (a miss / a closed circle).
 function self.Miss(pos)
  if self.Count>=5 and pos then
   stamp(pos-Vector2.new(0,40),(Text.IsRussian()and'КОМБО СГОРЕЛО'or'COMBO LOST')..' x'..self.Count,26,{Colors={C(170,180,200),C(120,130,150),C(200,200,210)}},.9,20)
  end
  self.Count=0;self.LastAt=0
  counter.Visible=false
 end
 function self.Reset()self.Count=0;self.LastAt=0;counter.Visible=false end
 -- Strength training reuses the counter: REPS xN.
 function self.Rep(pos)
  local now=os.clock()
  if now-self.LastAt>6 then self.Count=0 end
  self.Count+=1;self.LastAt=now
  local style=self.Style(self.Count)
  if pos then ring(pos,160,8,nil,.5);sparks(pos,low()and 3 or 8,style,110,.7);stamp(pos-Vector2.new(0,50),'x'..self.Count,34,style,.8,50)end
  label='REPS';show(self.Count)
  if self.Count%10==0 then self.Milestone(self.Count,style)end
 end

 -- Heat bar + hide when the streak cools down.
 game:GetService('RunService').RenderStepped:Connect(function()
  if not counter.Visible then return end
  local left=1-(os.clock()-self.LastAt)/(label=='REPS'and 6 or self.Timeout)
  if left<=0 then counter.Visible=false;if label=='COMBO'then self.Count=0 end;return end
  heat.Size=UDim2.fromScale(left,1)
  bigGrad.Offset=Vector2.new(math.sin(os.clock()*2)*.3,0)
  bigGrad.Rotation=(os.clock()*40)%360
 end)

 return self
end

return Combo
