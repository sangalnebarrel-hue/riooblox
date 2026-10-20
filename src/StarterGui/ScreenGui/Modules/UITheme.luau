-- Read design tokens and decorations from the actual SOURCE instances.
local Tween=game:GetService('TweenService')
local GuiService=game:GetService('GuiService')
local UserInput=game:GetService('UserInputService')
local GameIcons=require(game:GetService('ReplicatedStorage'):WaitForChild('GameIcons'))
-- Kit motion (one reduced-motion switch) and UI sounds for the legacy buttons and the HUD.
local Motion=require(script.Parent:WaitForChild('Kit'):WaitForChild('Motion'))
local Sound=require(script.Parent.Kit:WaitForChild('Sound'))
-- Kit design tokens (pure data): the legacy primitives below draw with the same shapes, strokes,
-- radii and motion as the Kit windows (DOGS / LAB / BAG), so every menu reads as one game.
local KitTheme=require(script.Parent.Kit:WaitForChild('Theme'))
local gui=script.Parent.Parent;local main=gui:WaitForChild('MainWindow')
local yard=main.Content.PageContainer.YardPage
local cardTemplate=yard.LatestFoundCard.Main
local buttonTemplate=main.Sidebar.DogsButton
local activeTemplate=main.Sidebar.YardButton
local headerTemplate=yard.YardHeader
local U={FontFace=Font.fromEnum(Enum.Font.FredokaOne)};local C=Color3.fromRGB
-- Presentation labels only. Keep canonical ability/slot IDs in all requests.
function U.AbilityLabel(id)return(tostring(id or '—'):gsub('(%l)(%u)','%1 %2'))end
function U.DigSlotLabel(id)local value=tostring(id or '');local number=value:match('^DigSlot_(%d+)$');return number and 'DIG SPOT '..number or(value~=''and value or 'Storage')end
local function ink(instance,fallback)local stroke=instance:FindFirstChildWhichIsA('UIStroke');return stroke and stroke.Color or fallback end
U.Colors={metal=C(232,244,255),secondary=C(220,237,253),navy=C(218,237,253),panel=C(255,255,255),edge=C(23,43,76),orange=C(34,184,242),nav=C(55,168,241),gold=C(249,180,35),blue=C(38,164,243),green=C(125,219,48),red=C(247,73,112),purple=C(161,103,242),text=C(23,43,76),muted=C(83,112,150),light=C(247,251,255)}
-- Kit surfaces and readable accent inks (gold / green text on white or Surface cards).
U.Surface=KitTheme.Surface;U.SurfaceAlt=KitTheme.SurfaceAlt;U.Backdrop=KitTheme.Backdrop;U.Field=KitTheme.Field
U.TextGold=KitTheme.Darken(U.Colors.gold,.25);U.TextGreen=KitTheme.Darken(U.Colors.green,.35)
U.Rarity={Common=C(170,190,205),Rare=U.Colors.blue,Epic=U.Colors.purple,Legendary=U.Colors.gold,Mythic=U.Colors.red,Secret=C(230,115,245),Uncommon=U.Colors.green,['Brainrot God']=U.Colors.red}
U.Tiers={C(102,166,225),C(130,219,76),C(162,181,202),C(249,180,57),C(255,146,32),C(228,75,153),C(255,48,116),C(203,58,245),C(179,114,255),C(255,55,144)}
function U.New(class,props,parent)local o=Instance.new(class);for k,v in pairs(props)do o[k]=v end;o.Parent=parent;return o end
function U.SafeArea(screen)
 local size=screen.AbsoluteSize
 local ok,safe,own=pcall(function()return GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets),GuiService:GetInsetArea(screen.ScreenInsets)end)
 if ok then
  -- Inset rectangles share the Core UI origin; subtract this ScreenGui's origin.
  local left=math.clamp(safe.Min.X-own.Min.X,0,size.X)
  local top=math.clamp(safe.Min.Y-own.Min.Y,0,size.Y)
  local right=math.clamp(safe.Max.X-own.Min.X,left,size.X)
  local bottom=math.clamp(safe.Max.Y-own.Min.Y,top,size.Y)
  return left,top,right-left,bottom-top
 end
 local top=screen.IgnoreGuiInset and 64 or 0
 return 0,top,size.X,math.max(1,size.Y-top)
end
function U.SafePosition(screen,w,h,factor,margin)
 local left,top,width,height=U.SafeArea(screen);local size=screen.AbsoluteSize
 local halfW,halfH=w*factor/2,h*factor/2
 local function fit(value,minimum,maximum)return maximum<minimum and(minimum+maximum)/2 or math.clamp(value,minimum,maximum)end
 return UDim2.fromOffset(fit(size.X/2,left+margin+halfW,left+width-margin-halfW),fit(size.Y/2,top+margin+halfH,top+height-margin-halfH))
end
-- Roblox touch controls live in PlayerGui.TouchGui (PlayerModule TouchJump): the jump button is
-- 70px (short side <= 500) or 120px, bottom-right of the Core UI safe area; the thumbstick rests
-- bottom-left. Returns jump left/top in this ScreenGui's pixels and the thumbstick height to keep free.
function U.TouchReserve(screen,left,top,width,height)
 local small=math.min(width,height)<=500;local size=small and 70 or 120
 local jx,jy=left+width-(size*1.5-10),top+height-(small and size+20 or size*1.75)
 local touchGui=screen.Parent and screen.Parent:FindFirstChild('TouchGui')
 local jump=touchGui and touchGui:FindFirstChild('JumpButton',true)
 if jump and jump:IsA('GuiObject')and jump.Visible and jump.AbsoluteSize.X>0 then
  local x,y=jump.AbsolutePosition.X-screen.AbsolutePosition.X,jump.AbsolutePosition.Y-screen.AbsolutePosition.Y
  if x>left+width*.5 and y>top+height*.4 then jx,jy=math.min(jx,x),math.min(jy,y)end
 end
 return jx,jy,small and 100 or 170
end
-- Re-run a layout (coalesced) whenever the usable screen can change: window or camera viewport
-- size, top bar inset, touch mode, or Roblox's touch controls appearing / moving.
function U.WatchHUD(screen,layout)
 local queued,cs,camera=false,{},nil
 local function relayout()if queued then return end;queued=true;task.defer(function()queued=false;if screen.Parent then layout()end end)end
 local function on(signal)table.insert(cs,signal:Connect(relayout))end
 on(screen:GetPropertyChangedSignal('AbsoluteSize'));on(GuiService:GetPropertyChangedSignal('TopbarInset'));on(UserInput:GetPropertyChangedSignal('TouchEnabled'))
 local function bindCamera()
  if camera then camera:Disconnect()end
  local cam=workspace.CurrentCamera;camera=cam and cam:GetPropertyChangedSignal('ViewportSize'):Connect(relayout);relayout()
 end
 table.insert(cs,workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(bindCamera));bindCamera()
 local function touchGui(g)
  if g.Name~='TouchGui'then return end
  local function jump(o)if o.Name=='JumpButton'and o:IsA('GuiObject')then on(o:GetPropertyChangedSignal('AbsolutePosition'));on(o:GetPropertyChangedSignal('Visible'));relayout()end end
  for _,o in ipairs(g:GetDescendants())do jump(o)end;table.insert(cs,g.DescendantAdded:Connect(jump))
 end
 local playerGui=screen.Parent
 if playerGui then for _,g in ipairs(playerGui:GetChildren())do touchGui(g)end;table.insert(cs,playerGui.ChildAdded:Connect(touchGui))end
 screen.Destroying:Connect(function()if camera then camera:Disconnect()end;for _,c in ipairs(cs)do c:Disconnect()end end)
end
local function decorate(o,template)
 for _,v in ipairs(template:GetChildren())do
  if v:IsA('UICorner')or v:IsA('UIStroke')or v:IsA('UIGradient')then v:Clone().Parent=o end
 end
end
function U.Round(o,n)
 local old=o:FindFirstChildWhichIsA('UICorner');if old then old:Destroy()end
 return U.New('UICorner',{CornerRadius=UDim.new(0,n or 10)},o)
end
function U.Stroke(o,c,t,a)
 local old=o:FindFirstChildWhichIsA('UIStroke');if old then old:Destroy()end
 return U.New('UIStroke',{Color=c or U.Colors.edge,Thickness=t or 3,Transparency=a or 0,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},o)
end
function U.Gradient(o,a,b,rotation)
 local old=o:FindFirstChildWhichIsA('UIGradient');if old then old:Destroy()end
 o.BackgroundColor3=Color3.new(1,1,1);return U.New('UIGradient',{Color=ColorSequence.new(a,b),Rotation=rotation or 90},o)
end
function U.Frame(p,n,x,y,w,h,c)return U.New('Frame',{Name=n,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=c or U.Colors.panel,BorderSizePixel=0},p)end
function U.Shadow(o)
 -- A sibling shadow must not become an extra cell in an automatic layout.
 if o.Parent:FindFirstChildWhichIsA('UIGridLayout')or o.Parent:FindFirstChildWhichIsA('UIListLayout')or o.Parent:FindFirstChildWhichIsA('UIPageLayout')then return end
 -- Soft depth under a raised card (no hard offset block): a faint navy drop, same corners.
 local offset=UDim2.fromOffset(0,4)
 local shadow=U.New('Frame',{Name='DropShadow',Position=o.Position+offset,Size=o.Size,AnchorPoint=o.AnchorPoint,BackgroundColor3=U.Colors.edge,BackgroundTransparency=.82,BorderSizePixel=0,Visible=o.Visible,ZIndex=math.max(1,o.ZIndex-1)},o.Parent)
 local corner=o:FindFirstChildWhichIsA('UICorner');U.Round(shadow,corner and corner.CornerRadius.Offset>0 and corner.CornerRadius.Offset or KitTheme.Radius.Card)
 local cs={}
 for _,key in ipairs({'Position','Size','AnchorPoint','Visible'})do table.insert(cs,o:GetPropertyChangedSignal(key):Connect(function()shadow[key]=key=='Position'and(o.Position+offset)or o[key]end))end
 o.Destroying:Connect(function()for _,c in ipairs(cs)do c:Disconnect()end;shadow:Destroy()end)
 return shadow
end
-- Kit card (Kit.Cards): white, radius 14, a 2 px navy outline; raised cards add a soft shadow.
function U.Panel(p,n,x,y,w,h,raised)
 local o=U.Frame(p,n,x,y,w,h);o.ZIndex=2
 U.Round(o,KitTheme.Radius.Card);U.Stroke(o,U.Colors.edge,KitTheme.StrokeWidth.Card)
 if raised then U.Shadow(o)end
 return o
end
U.Card=U.Panel;U.PreviewCard=U.Panel
-- Section heading band (Kit SurfaceAlt rows): callers put an Ink title inside it.
function U.Header(p,n,x,y,w,h)
 local o=U.Frame(p,n,x,y,w,h,U.SurfaceAlt);o.ZIndex=3
 U.Round(o,KitTheme.Radius.Field);U.Stroke(o,U.Colors.edge,2,.55)
 return o
end
-- A titled section band (U.Header + an Ink heading, Kit Heading size); returns the band.
function U.Section(p,title,x,y,w,h)
 local band=U.Header(p,'Section',x,y,w,h or 38)
 local t=U.Text(band,title,14,0,w-28,h or 38,KitTheme.TextSize.Heading,U.Colors.text,true);t.Name='Title';t.TextWrapped=false;t.TextScaled=true
 U.New('UITextSizeConstraint',{MinTextSize=12,MaxTextSize=KitTheme.TextSize.Heading},t)
 return band
end
function U.Text(p,s,x,y,w,h,size,color,bold)
 return U.New('TextLabel',{Name='Label',Text=tostring(s),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,TextColor3=color or U.Colors.text,FontFace=U.FontFace,TextSize=size or 20,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextStrokeColor3=buttonTemplate.TextStrokeColor3,TextStrokeTransparency=1,ZIndex=4},p)
end
function U.Center(p,s,x,y,w,h,size,c,b)local t=U.Text(p,s,x,y,w,h,size,c,b);t.TextXAlignment=Enum.TextXAlignment.Center;return t end
function U.Title(p,s,x,y,w,h)return U.Text(p,s,x,y,w,h,30,U.Colors.text,true)end
-- Selection highlight (Kit card Selected: a 4 px accent outline). Gold, the old highlight colour,
-- maps to the kit accent; other colours (red: featured offers) stay.
function U.Glow(o,c)U.Stroke(o,(c==nil or c==U.Colors.gold)and KitTheme.Accent or c,4)end
local enhanced=setmetatable({},{__mode='k'})
local captions=setmetatable({},{__mode='k'}) -- U.Button captions: their ink follows the button style
local WHITE0=Color3.new(1,1,1)
-- White / panel colours make the Kit secondary button: a white face with Ink text.
local function light(color)local _,s,v=color:ToHSV();return s<.12 and v>.94 end
local function saturated(color)
 local h,s,v=color:ToHSV()
 if s<.22 then return v>.9 and WHITE0 or U.Colors.blue:Lerp(WHITE0,.28)end
 return Color3.fromHSV(h,math.max(s,.72),math.max(v,.84))
end
-- The soft white halo of a hovered button (Kit.Base hoverGlow): 2 px outside the face, made on the
-- first mouse hover only. Faces that lay out or pad their children get none (it would become a cell,
-- sit off-centre or grow an auto-sized button).
local function hoverGlow(face)
 if face:FindFirstChildWhichIsA('UIGridLayout')or face:FindFirstChildWhichIsA('UIListLayout')or face:FindFirstChildWhichIsA('UIPadding')or face.AutomaticSize~=Enum.AutomaticSize.None then return nil end
 local old=face:FindFirstChild('KitHoverGlow');if old then return old:FindFirstChild('Glow')end
 local corner=face:FindFirstChildWhichIsA('UICorner');local radius=corner and corner.CornerRadius or UDim.new(0,KitTheme.Radius.Button)
 local glow=U.New('Frame',{Name='KitHoverGlow',BackgroundTransparency=1,BorderSizePixel=0,Active=false,Position=UDim2.fromOffset(-2,-2),Size=UDim2.new(1,4,1,4),ZIndex=face.ZIndex},face)
 U.New('UICorner',{CornerRadius=UDim.new(radius.Scale,radius.Offset>0 and radius.Offset+2 or 0)},glow)
 local stroke=U.New('UIStroke',{Name='Glow',ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=WHITE0,Thickness=3,Transparency=1,LineJoinMode=Enum.LineJoinMode.Round},glow)
 stroke:SetAttribute('KitGlow',true)
 return stroke
end
function U.SetButtonEnabled(button,on)
 button.Active=on==true;button.Selectable=on==true;button:SetAttribute('UIEnabled',on==true)
end
-- Kit button look on any legacy button: gradient face (radius 12, 2 px navy outline), hover lift with
-- a soft white halo, press squash, the release spring and Kit.Sound cues. Disabled: greyed face,
-- faded caption, no motion.
function U.EnhanceButton(button,color)
 if not button:IsA('GuiButton')then return end
 if enhanced[button]then return end
 -- Transparent hit targets select a visible card; painting them would cover its artwork.
 local face=button
 if button.BackgroundTransparency>=.95 then
  local surface=button.Parent and button.Parent:FindFirstChild('Surface')
  if not surface or not surface:IsA('Frame')then return end
  face=surface
 end
 enhanced[button]=true;button.AutoButtonColor=false;button:SetAttribute('PawpadAnimated',true)
 Sound.Attach(button) -- hover + click sounds (every legacy menu button sounds like the kit)
 local base=saturated(color or button:GetAttribute('ButtonBaseColor')or face.BackgroundColor3)
 button:SetAttribute('ButtonBaseColor',base)
 U.Round(face,KitTheme.Radius.Button)
 local existingStroke=face:FindFirstChildWhichIsA('UIStroke')
 if existingStroke then existingStroke.Enabled=true;existingStroke.Color=U.Colors.edge;existingStroke.Thickness=KitTheme.StrokeWidth.Button;existingStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border else U.Stroke(face,U.Colors.edge,KitTheme.StrokeWidth.Button)end
 local gradient=face:FindFirstChildWhichIsA('UIGradient')or U.New('UIGradient',{},face)
 local motionTarget=face==button and button or button.Parent
 local scale=motionTarget:FindFirstChildWhichIsA('UIScale')or U.New('UIScale',{Name='ButtonMotion'},motionTarget)
 local hover,pressed=false,false;local glow=nil;local saved=nil
 local caption=captions[button]
 -- Caption ink: white with a navy outline on colour, Ink on a white (secondary) face. A plain
 -- TextButton keeps its own text colours unless it turns secondary (restored when it stops).
 local function ink(isLight,enabled)
  if caption then
   caption.TextColor3=isLight and U.Colors.text or WHITE0;caption.TextStrokeColor3=U.Colors.edge;caption.TextStrokeTransparency=isLight and 1 or .15
   caption.TextTransparency=enabled and 0 or .35
  elseif button:IsA('TextButton')and button.Text~=''then
   if isLight and not saved then saved={button.TextColor3,button.TextStrokeTransparency};button.TextColor3=U.Colors.text;button.TextStrokeTransparency=1
   elseif not isLight and saved then button.TextColor3=saved[1];button.TextStrokeTransparency=saved[2];saved=nil end
  end
 end
 local function draw()
  if not button.Parent then return end
  local enabled=button.Active and button:GetAttribute('UIEnabled')~=false
  local current=button:GetAttribute('ButtonBaseColor')or base
  local tone=enabled and current or current:Lerp(KitTheme.Disabled,.7)
  face.BackgroundColor3=WHITE0;gradient.Color=ColorSequence.new(tone:Lerp(WHITE0,.12),tone);gradient.Rotation=90;gradient.Enabled=true
  local stroke=face:FindFirstChildWhichIsA('UIStroke');if stroke then stroke.Color=enabled and U.Colors.edge or Color3.fromRGB(99,116,144)end
  ink(light(current),enabled)
  local goal=not enabled and 1 or pressed and .94 or hover and 1.03 or 1
  if pressed and enabled then Motion.Tween(scale,KitTheme.Motion.Press*.8,{Scale=goal})
  else Motion.Tween(scale,KitTheme.Motion.Press*1.6,{Scale=goal},Enum.EasingStyle.Back)end
  if glow then Motion.Tween(glow,KitTheme.Motion.Fast,{Transparency=(hover and enabled)and .35 or 1})end
 end
 local function hovered(mouse)
  hover=true
  if mouse and not glow and button.Active and button:GetAttribute('UIEnabled')~=false then local ok,stroke=pcall(hoverGlow,face);glow=ok and stroke or nil end
  draw()
 end
 button.MouseEnter:Connect(function()hovered(Sound.MouseInput())end);button.MouseLeave:Connect(function()hover=false;pressed=false;draw()end)
 button.MouseButton1Down:Connect(function()pressed=true;draw()end);button.MouseButton1Up:Connect(function()pressed=false;draw()end)
 button.SelectionGained:Connect(function()hovered(false)end);button.SelectionLost:Connect(function()hover=false;pressed=false;draw()end)
 button:GetPropertyChangedSignal('Active'):Connect(draw);button:GetAttributeChangedSignal('UIEnabled'):Connect(draw);button:GetAttributeChangedSignal('ButtonBaseColor'):Connect(draw)
 -- A script recolouring the face (layouts, tab states) sets the base colour; repaint at once even
 -- when the attribute keeps its value (the face would otherwise stay flat).
 face:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
  local value=face.BackgroundColor3
  if value~=WHITE0 then button:SetAttribute('ButtonBaseColor',saturated(value));draw()end
 end)
 draw()
end
function U.Button(p,n,s,x,y,w,h,fn,c)
 local b=U.New('TextButton',{Name=n,Text='',Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=c or U.Colors.blue,BorderSizePixel=0,AutoButtonColor=false,Selectable=fn~=nil,Active=fn~=nil,ZIndex=3},p)
 -- Kit caption: ~19-21 px on a 44-50 px button, shrinking to fit.
 local size=math.max(8,math.min(21,math.floor(h*.44)))
 local caption=U.Center(b,s,6,2,w-12,h-4,size,WHITE0,true);caption.TextStrokeTransparency=.15;caption.TextStrokeColor3=U.Colors.edge;caption.Name='Caption';caption.Size=UDim2.new(1,-12,1,-4);caption.TextWrapped=false;caption.TextScaled=true;U.New('UITextSizeConstraint',{MinTextSize=math.min(12,size),MaxTextSize=size},caption)
 captions[b]=caption
 U.EnhanceButton(b,c or U.Colors.blue)
 if fn then b.Activated:Connect(function(...)if b.Active and b:GetAttribute('UIEnabled')~=false then fn(...)end end)end
 return b
end
function U.SecondaryButton(p,n,s,x,y,w,h,fn,c)return U.Button(p,n,s,x,y,w,h,fn,c or U.Colors.panel)end
function U.DangerButton(p,n,s,x,y,w,h,fn)return U.Button(p,n,s,x,y,w,h,fn,U.Colors.red)end
-- Kit tab (Kit.Tabs): a pill. Idle: white, Ink text, faint outline. Selected: filled with the accent
-- (Kit accent by default) and underlined.
function U.Tab(p,n,s,x,y,w,h,fn,on,accent)
 local color=accent or KitTheme.Accent
 local b=U.Button(p,n,s,x,y,w,h,fn,on and color or U.Colors.panel);U.Round(b,math.floor(h/2))
 local stroke=b:FindFirstChildWhichIsA('UIStroke');if stroke then stroke.Transparency=on and 0 or .55 end
 b:SetAttribute('KitSound','Tab')
 if on then
  local line=U.Frame(b,'Underline',0,0,0,0,KitTheme.Darken(color,.28));line.AnchorPoint=Vector2.new(.5,1);line.Position=UDim2.new(.5,0,1,-3);line.Size=UDim2.new(.6,0,0,4);line.ZIndex=b.ZIndex+1
  U.New('UICorner',{CornerRadius=UDim.new(.5,0)},line)
 end
 return b
end
-- Kit pill (Kit.Pill): fully rounded, filled, readable text (Ink on light colours, white with a navy
-- outline on strong ones).
function U.Badge(p,s,x,y,w,c)
 local color=c or U.Colors.nav;local b=U.Frame(p,'Badge',x,y,w,28,color);U.New('UICorner',{CornerRadius=UDim.new(.5,0)},b)
 local ink=KitTheme.OnColor(color);local t=U.Center(b,s,8,0,w-16,28,15,ink,true)
 t.TextWrapped=false;t.TextScaled=true;U.New('UITextSizeConstraint',{MinTextSize=8,MaxTextSize=15},t)
 if ink==KitTheme.White then t.TextStrokeColor3=U.Colors.edge;t.TextStrokeTransparency=.35 end
 return b
end
-- Kit progress bar (Kit.ProgressBar): pale pill track, gradient pill fill, white text with a navy outline.
function U.Bar(p,x,y,w,h,value,c,caption)
 local b=U.Frame(p,'Progress',x,y,w,h,U.Colors.secondary);b.ZIndex=2;U.New('UICorner',{CornerRadius=UDim.new(.5,0)},b);U.Stroke(b,U.Colors.edge,2,.35)
 local v=math.clamp(tonumber(value)or 0,0,1);local tone=c or U.Colors.green
 local f=U.New('Frame',{Name='Fill',Size=UDim2.fromScale(v,1),BackgroundColor3=WHITE0,BorderSizePixel=0,Visible=v>0,ZIndex=3},b);U.New('UICorner',{CornerRadius=UDim.new(.5,0)},f)
 U.New('UIGradient',{Color=ColorSequence.new(tone:Lerp(WHITE0,.25),tone),Rotation=90},f)
 if caption then local t=U.Center(b,caption,0,0,w,h,math.min(15,math.floor(h*.62)),WHITE0,true);t.TextStrokeColor3=U.Colors.edge;t.TextStrokeTransparency=.1;t.ZIndex=4 end
 return b
end
U.ProgressBar=U.Bar
function U.Scroll(p,n,x,y,w,h)return U.New('ScrollingFrame',{Name=n,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=5,ScrollBarImageColor3=U.Colors.nav,ScrollingDirection=Enum.ScrollingDirection.Y},p)end
function U.Grid(p,n,x,y,w,h,columns,cellH)local sc=U.Scroll(p,n,x,y,w,h);local cw=math.floor((w-12-(columns-1)*12)/columns);U.New('UIGridLayout',{CellSize=UDim2.fromOffset(cw,cellH),CellPadding=UDim2.fromOffset(12,12),SortOrder=Enum.SortOrder.LayoutOrder},sc);return sc,cw end
-- Kit field (Kit.SearchBox): pale field, radius 10, faint outline that turns accent while typing.
function U.Search(p,n,placeholder,value,x,y,w,fn)
 local b=U.New('TextBox',{Name=n,Text=value or'',PlaceholderText=placeholder,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,42),BackgroundColor3=U.Field,TextColor3=U.Colors.text,PlaceholderColor3=U.Colors.muted,FontFace=U.FontFace,TextSize=17,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},p)
 U.Round(b,KitTheme.Radius.Field);local stroke=U.Stroke(b,U.Colors.edge,2,.5);U.New('UIPadding',{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,8)},b)
 b.Focused:Connect(function()stroke.Color=KitTheme.Accent;stroke.Transparency=0 end)
 b.FocusLost:Connect(function()stroke.Color=U.Colors.edge;stroke.Transparency=.5;fn(b.Text)end);return b
end
U.Input=U.Search
-- A value picker (Kit SortSelect look): a white secondary button with a ▾.
function U.Cycle(p,n,label,values,current,x,y,w,fn)return U.Button(p,n,label..'  ▾',x,y,w,40,#values>0 and function()local i=table.find(values,current)or 1;fn(values[i%#values+1])end or nil,U.Colors.panel)end
-- Kit dialog card (Kit.Modal): Surface card, radius 18, 3 px outline, a short accent bar over an Ink
-- title (the first child named 'Label': callers rename / retitle it), content below y = 64. It springs
-- in like the kit (0.9 -> 1, Back) unless `still` (redrawn dialogs) or the caller animates its UIScale.
function U.Modal(parent,name,title,w,h,still)
 local box=U.Frame(parent,name,0,0,w,h,U.Surface);box.AnchorPoint=Vector2.new(.5,.5);box.Position=UDim2.fromScale(.5,.5);box.ZIndex=2
 U.Round(box,KitTheme.Radius.Window);U.Stroke(box,U.Colors.edge,KitTheme.StrokeWidth.Window)
 U.Text(box,title,24,18,w-48,40,24,U.Colors.text,true)
 local bar=U.Frame(box,'AccentBar',24,12,46,5,KitTheme.Accent);bar.ZIndex=4;U.New('UICorner',{CornerRadius=UDim.new(.5,0)},bar)
 local scale=U.New('UIScale',{Scale=1},box)
 local fit=1
 local function resize()
  local _,_,width,height=U.SafeArea(gui);fit=math.min(1,(width-24)/w,(height-24)/h);scale.Scale=fit
  box.Position=U.SafePosition(gui,w,h,fit,12)
 end
 local c=gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(resize);local inset=GuiService:GetPropertyChangedSignal('TopbarInset'):Connect(resize)
 box.Destroying:Connect(function()c:Disconnect();inset:Disconnect()end);resize()
 if not still then
  task.defer(function()
   -- A caller that tweens the UIScale itself (LuckyReel's bounce) keeps its own motion.
   if not box.Parent or Motion.Reduced()or math.abs(scale.Scale-fit)>.001 then return end
   scale.Scale=fit*.9;Motion.Tween(scale,KitTheme.Motion.Open,{Scale=fit},Enum.EasingStyle.Back)
  end)
 end
 return box
end
function U.Overlay(parent,name)return U.New('Frame',{Name=name,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Active=true,ZIndex=80},parent)end

function U.Icon(p,key,x,y,size,color)
 local assetKey=({Collection='DogDex',Storage='Inventory',Discoveries='Inventory',Marketplace='Shop'})[key]or key
 if U.Assets and U.Assets[assetKey]then return U.AssetIcon(p,assetKey,x,y,size)end
 key=GameIcons.FallbackKey(assetKey)
 local fallbackAsset=({Storage='Inventory',Discoveries='Inventory'})[key]or key
 if U.Assets and U.Assets[fallbackAsset]then return U.AssetIcon(p,fallbackAsset,x,y,size)end
 local f=U.Frame(p,'Icon'..key,x,y,size,size);f.BackgroundTransparency=1;local ink=color or U.Colors.muted
 local function box(a,b,w,h,r)local o=U.Frame(f,'Glyph',a*size,b*size,w*size,h*size,ink);if r then U.Round(o,r*size)end;return o end
 if key=='Dogs' or key=='Paw'then box(.27,.46,.5,.4,.2);for _,v in ipairs({{.1,.25},{.31,.08},{.57,.08},{.79,.25}})do box(v[1],v[2],.18,.27,.1)end
 elseif key=='Yard'then local roof=box(.2,.12,.55,.55,.04);roof.Rotation=45;box(.2,.4,.6,.48,.02);box(.43,.57,.17,.31,.01).BackgroundColor3=U.Colors.navy
 elseif key=='Coins'then
  local coin=box(.08,.08,.84,.84,.5);U.Gradient(coin,C(255,237,93),C(229,143,12));U.Stroke(coin,C(104,62,10),size*.025)
  local ring=box(.18,.18,.64,.64,.5);U.Gradient(ring,C(255,199,49),C(255,219,90));U.Stroke(ring,C(190,117,12),size*.025);U.Icon(ring,'Paw',size*.11,size*.1,size*.42,C(217,132,10))
 elseif key=='Ticket'then
  local body=box(.04,.24,.92,.52,.08);U.Gradient(body,C(255,229,75),C(255,159,25));U.Stroke(body,U.Colors.edge,size*.03)
  for _,xx in ipairs({.24,.74})do for yy=0,3 do box(xx,.3+yy*.1,.025,.05).BackgroundColor3=U.Colors.edge end end
  U.Icon(body,'Paw',size*.34,size*.1,size*.25,U.Colors.edge)
 elseif key=='Bones'then
  local bone=box(.14,.39,.72,.24,.11);bone.Rotation=-25;for _,v in ipairs({{.08,.39},{.12,.57},{.65,.11},{.75,.29}})do local b=box(v[1],v[2],.22,.22,.11);U.Gradient(b,C(255,247,215),C(203,177,138))end
 elseif key=='Dig'then
  local handle=box(.45,.2,.12,.72,.03);handle.Rotation=40;handle.BackgroundColor3=U.Colors.secondary;local metal=box(.2,.16,.62,.17,.02);metal.Rotation=35;U.Gradient(metal,C(191,217,237),C(68,109,150))
 elseif key=='Luck'then
  for _,v in ipairs({{.14,.16},{.49,.16},{.14,.5},{.49,.5}})do local leaf=box(v[1],v[2],.36,.36,.18);U.Gradient(leaf,C(145,248,90),C(35,170,28))end
 elseif key=='DogDex' or key=='Collection'then box(.1,.2,.34,.6,.04);box(.49,.2,.34,.6,.04);box(.45,.22,.025,.61)
 elseif key=='Trade'then box(.16,.28,.6,.11);local a=box(.68,.19,.22,.22);a.Rotation=45;box(.24,.62,.6,.11);local b=box(.12,.56,.22,.22);b.Rotation=45
 elseif key=='Lab'then box(.4,.08,.2,.45);box(.3,.04,.4,.12,.03);box(.18,.56,.64,.32,.06);box(.29,.42,.42,.27,.04);box(.35,.62,.12,.1,.03).BackgroundColor3=Color3.new(1,1,1)
 elseif key=='Shop' or key=='Marketplace'then box(.13,.28,.74,.46,.04);box(.05,.14,.14,.14);for _,xx in ipairs({.23,.65})do box(xx,.79,.15,.15,.08)end
 elseif key=='Events'then box(.1,.2,.8,.68,.04);for _,xx in ipairs({.27,.63})do box(xx,.07,.1,.25,.03)end;for a=0,2 do for b=0,1 do box(.22+a*.22,.43+b*.2,.12,.11).BackgroundColor3=U.Colors.navy end end
 elseif key=='Records'then for i=0,2 do box(.13+i*.26,.6-i*.2,.18,.28+i*.2,.02)end
 elseif key=='Discoveries' or key=='Storage'then box(.12,.2,.76,.67,.04);box(.46,.2,.06,.67).BackgroundColor3=U.Colors.navy;box(.12,.34,.76,.06).BackgroundColor3=U.Colors.navy
 else U.Center(f,key=='Coins' and '●'or key=='Bones'and '◆'or key=='Dig'and '⚒'or key=='Luck'and '✦'or key=='Halloween'and '🍬'or '★',0,0,size,size,size*.85,ink,true)end
 return f
end
U.Fmt=require(game.ReplicatedStorage.PriceFormat).Number
function U.Count(t)local n=0;for _ in pairs(t or {})do n+=1 end;return n end
function U.Weight(n)return type(n)=='number'and string.format('%.10g kg',n)or '—'end
function U.Odds(n)return n and n>0 and ('1 in '..string.format('%.6g',1/n))or '—'end
-- DOGROTS candy interface. Applies presentation before gameplay controllers bind.
U.Assets={Dogs='rbxassetid://117639585361256',Inventory='rbxassetid://77546579160081',Yard='rbxassetid://115488468002446',Shop='rbxassetid://99434251630478',DogDex='rbxassetid://124671430150778',Lab='rbxassetid://105402832269661',Events='rbxassetid://86724140753338',Trade='rbxassetid://137537596011172'}
GameIcons.Apply(U.Assets)
local WHITE=C(255,255,255)
local NAVY=C(23,43,76)
local PALE=C(232,244,255)
local specs={
 {key='Dogs',label='DOGS',color=C(255,169,38)},
 {key='Inventory',label='BAG',color=C(26,192,239)},
 {key='Yard',label='MY YARD',color=C(123,219,51)},
 {key='Shop',label='SHOP',color=C(248,79,170)},
 {key='DogDex',label='INDEX',color=C(92,142,250)},
 {key='Lab',label='LAB',color=C(162,105,246)},
 {key='Trade',label='TRADE',color=C(41,204,168)},
 {key='Events',label='EVENTS',color=C(255,192,32)},
}
local byKey={};for _,s in ipairs(specs)do byKey[s.key]=s end
local function rect(o,x,y,w,h)
 o.AnchorPoint=Vector2.zero;o.Position=UDim2.fromOffset(x,y);o.Size=UDim2.fromOffset(w,h)
end
local function surface(o,color,radius,thickness)
 o.BackgroundColor3=color;o.BorderSizePixel=0
 local g=o:FindFirstChildWhichIsA('UIGradient');if g then g.Color=ColorSequence.new(WHITE,WHITE);g.Transparency=NumberSequence.new(0);g.Enabled=true end
 local s=o:FindFirstChildWhichIsA('UIStroke')
 if s then s.Enabled=true;s.Color=NAVY;s.Thickness=thickness or 2;s.Transparency=0;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border else U.Stroke(o,NAVY,thickness or 2)end
 U.Round(o,radius or 12)
end
local function typeface(o,size,white)
 o.Font=Enum.Font.FredokaOne;o.TextColor3=white and WHITE or NAVY
 o.TextStrokeColor3=NAVY;o.TextStrokeTransparency=white and 0 or 1
 o.TextScaled=false;o.TextSize=size or 19;o.TextWrapped=true
 if o:IsA('TextLabel')then for _,c in ipairs(o:GetChildren())do if c:IsA('UIStroke')then c.Enabled=false end end end
 for _,c in ipairs(o:GetChildren())do if c:IsA('UITextSizeConstraint')then c.MinTextSize=8;c.MaxTextSize=size or 24 end end
end
function U.AssetIcon(parent,key,x,y,size,slot)
 -- Several icons can share a parent. Rebuilding the same icon slot reuses it;
 -- callers replacing an icon with another key can pass a stable explicit slot.
 local identity=slot or(tostring(key)..'@'..tostring(x)..':'..tostring(y))
 local icon
 for _,child in ipairs(parent:GetChildren())do
  if child:IsA('ImageLabel')and child.Name=='CandyIcon'and child:GetAttribute('CandyIconSlot')==identity then icon=child;break end
 end
 if not icon then icon=U.New('ImageLabel',{Name='CandyIcon',BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit},parent)end
 icon:SetAttribute('CandyIconSlot',identity);icon:SetAttribute('CandyIconKey',key)
 icon.Image=U.Assets[key]or GameIcons.Resolve(key)or''
 icon.Position=UDim2.fromOffset(x,y);icon.Size=UDim2.fromOffset(size,size);icon.ZIndex=parent.ZIndex+2
 return icon
end
function U.SetNavState(button,on)
 local key=button:GetAttribute('CandyPage') or button.Name:gsub('Button$','')
 local spec=byKey[key];if not spec then return end
 surface(button,spec.color,12,on and 4 or 2)
 local marker=button:FindFirstChild('SelectedMark');if marker then marker.Visible=on end
end
function U.LayoutYard(y)
 -- Yard: a large world preview and compact information cards.
 rect(y.YardHeader,14,14,903,50);rect(y.YardHeader.YardHeaderTitle,20,0,580,50)
 rect(y.YardPreviewPanel,14,80,538,300);surface(y.YardPreviewPanel,C(210,239,255),15,2)
 y.YardPreviewPanel.YardName.Text='YOUR YARD / HOME BASE';typeface(y.YardPreviewPanel.YardName,16,false)
 rect(y.StatsGrid,572,80,345,300)
 local grid=y.StatsGrid:FindFirstChildWhichIsA('UIGridLayout');if grid then grid.CellSize=UDim2.fromOffset(166,142);grid.CellPadding=UDim2.fromOffset(13,16)end
 local tints={IncomeCard=C(226,250,196),LevelCard=C(216,237,255),StorageCard=C(252,229,248),KennelsCard=C(255,244,198)}
 for name,tint in pairs(tints)do if y.StatsGrid:FindFirstChild(name)then
  local card=y.StatsGrid[name];surface(card,tint,13,2);card.Accent.Visible=false
  rect(card.Label,14,12,138,43);typeface(card.Label,17,false)
  rect(card.Value,14,66,138,57);typeface(card.Value,33,false)
 end end
 y.YardPreviewPanel.YardViewport.BackgroundColor3=C(168,217,243)
 rect(y.YardPreviewPanel.YardViewport,12,12,514,236)
 rect(y.YardPreviewPanel.YardName,16,258,506,30)
 rect(y.LatestFoundCard,14,396,903,104)
 local latest=y.LatestFoundCard.Main;rect(latest,0,0,903,104);latest.Accent.Visible=false
 rect(latest.PreviewArea,12,12,80,80)
 rect(latest.Title,110,8,430,22);typeface(latest.Title,15,false)
 rect(latest.ItemName,110,32,610,30);typeface(latest.ItemName,23,false)
 rect(latest.ItemInfo,110,67,780,25);typeface(latest.ItemInfo,17,false)
 rect(latest.ClassLabel,654,8,230,24);typeface(latest.ClassLabel,14,false)
 rect(y.ActionButtons,14,520,903,60)
 for i,name in ipairs({'Upgrades','DiggingLayers','GlobalDig'})do
  local holder=y.ActionButtons[name];rect(holder,(i-1)*306,0,291,60)
  surface(holder.Main,({C(134,220,57),C(39,190,241),C(255,185,38)})[i],12,2)
  holder.Main.Position=UDim2.new();holder.Main.Size=UDim2.fromScale(1,1)
  typeface(holder.Main,22,true)
  if not holder.Main:FindFirstChildWhichIsA('UIGradient')then U.New('UIGradient',{Color=ColorSequence.new(WHITE,WHITE)},holder.Main)end
 end
end
------------------------------------------------------------------------------------------------
-- HUD (docs/UI.md). Icon-first: a rail of round-square menu buttons with a tiny label under the
-- icon (left), the currency pills (top centre), small round buttons NAVIGATE / TITLES / HIDE UI /
-- SETTINGS (top-right). The maths live in Modules.HUDLayout; U.LayoutHUD applies them whenever
-- the screen, the top bar inset, touch mode or the touch controls change. The tiles reuse the
-- instances other scripts bind to (HUD.PawpadWidget.PawpadButton, HUD.InventoryWidget.
-- InventoryButton(.Capacity), HUD.Quick<Key>.Open, HUD.MoneyWidget, HUD.XPWidget,
-- HUD.SimpleSettings.Open); each managed root carries HUDEdge (the edge Hide UI slides it to).
------------------------------------------------------------------------------------------------
local StarterGui=game:GetService('StarterGui')
local Players=game:GetService('Players')
local HUDLayout=require(script.Parent.HUDLayout)
local UIText=require(game:GetService('ReplicatedStorage'):WaitForChild('Localization'):WaitForChild('UI'))
-- Typed as any: the HUD touches many GuiObject properties of found / created instances.
local function make(class:string,props:any,parent:any):any return U.New(class,props,parent)end
local function find(o:any,name:string):any return o:FindFirstChild(name)end
local function findClass(o:any,class:string):any return o:FindFirstChildWhichIsA(class)end
U.QuickTiles={}::any -- the rail tiles (BuildHUD)
U.HUD=false::any -- the last layout (LayoutHUD): free zone, boosts, touch reserve
local KitModule=nil
local function kit()
 if KitModule==nil then local ok,value=pcall(require,script.Parent.Kit);KitModule=ok and value or false end
 return KitModule or nil
end
-- Self-localized HUD text (labels carry NoTranslate): Localization.UI has the Russian.
-- CHAPTER II words (UNDERYARD tile, Bell Shards / Lucky Dust pills): ReplicatedStorage.Halloween.UnderyardView (WP-L)
local underyardView=nil
local function uyText(en)
 if underyardView==nil then
  -- never yields (labels are localized from tooltips and layout code): a module that is not there yet is tried again later
  local folder=game:GetService('ReplicatedStorage'):FindFirstChild('Halloween')
  local mod=folder and folder:FindFirstChild('UnderyardView')
  if not mod then return en end
  local ok,m=pcall(require,mod)
  underyardView=ok and type(m)=='table'and m or false
 end
 return underyardView and underyardView.T(en,'ru')or en
end
function U.L(en)
 local k=kit()
 if k and k.Lang()=='ru'then return UIText.Words[en]or UIText.Exact[en]or uyText(en)end
 return en
end
U.RailSpecs={
 {key='Dogs',label='DOGS',color=C(255,169,38),tip='Your pack: give every dog a job'},
 {key='Inventory',label='BAG',color=C(26,192,239),tip='Your finds and Lucky Blocks',hotkey='B'},
 {key='Yard',label='YARD',color=C(123,219,51),tip='Your yard, upgrades and income',hotkey='P'},
 {key='Shop',label='SHOP',color=C(248,79,170),tip='Boosts, spins and offers'},
 {key='DogDex',label='DEX',color=C(92,142,250),tip='Every dog you have discovered'},
 {key='Lab',label='LAB',color=C(162,105,246),tip='Mutate and improve your dogs'},
 {key='Trade',label='TRADE',color=C(41,204,168),tip='Swap dogs, items and artifacts with players'},
 {key='Events',label='EVENTS',color=C(255,192,32),tip='World events and daily rewards'},
}
-- NIGHT OF THE BURIED MOON (Halloween event, WP9): the HALLOWEEN tile and the Moon Candy / Curse pills while the event is on.
U.HalloweenEnabled=(function()local ok,HC=pcall(function()return require(game:GetService('ReplicatedStorage'):WaitForChild('Halloween',2):WaitForChild('Config',2))end);return ok and type(HC)=='table'and HC.HalloweenEventEnabled==true end)()
if U.HalloweenEnabled then table.insert(U.RailSpecs,{key='Halloween',label='HALLOWEEN',color=C(255,128,24),glyph='🎃',tip='Night of the Buried Moon: candy, quests, the cauldron and the Dead Yard'})end
-- CHAPTER II · THE UNDERYARD (WP-L): the UNDERYARD tile once Chapter I is complete (when = player attribute that must be
-- true: U.LayoutHUD hides the tile until then) and the Bell Shards pill; the Lucky Dust pill whenever you have some.
U.Chapter2Enabled=U.HalloweenEnabled and(function()local ok,HC=pcall(function()return require(game:GetService('ReplicatedStorage'):WaitForChild('Halloween',2):WaitForChild('Config',2))end);return ok and type(HC)=='table'and HC.HalloweenChapter2Enabled==true end)()
if U.Chapter2Enabled then table.insert(U.RailSpecs,{key='Underyard',label='UNDERYARD',color=C(150,80,230),glyph='🔔',tip='Below the church: Bell Seals, daily contracts, the Black Coffin and the Dex II',when='HalloweenChapter1Complete'})end
U.ClusterSpecs={
 {key='Navigate',name='QuickNavigate',title='NAVIGATE',glyph='🧭',tip='Where to go? Show me the way'},
 {key='Titles',name='QuickTitles',title='TITLES',glyph='👑',tip='Pick the title shown over your head',module='TitlesScreen'},
 {key='HideUI',name='QuickHideUI',title='HIDE UI',eye=true,tip='Hide the interface for screenshots and videos',hotkey='H'},
 {key='Settings',name='SimpleSettings',title='SETTINGS',icon='Settings',glyph='⚙',tip='Sounds, motion and more'},
}
-- Currency pills, widths in bar heights. Always: coins and level; bones / stone once you have some.
U.PillSpecs={
 {key='Coins',name='MoneyWidget',units=4.6,always=true,title='COINS',tip='Earned by your dogs. Spend them on dogs, upgrades and boosts.'},
 {key='Bones',name='QuickBones',units=3,title='BONES',tip='A rare currency for special offers.'},
 {key='Stone',name='QuickStone',units=3,title='STONE',tip='Mined at your Mining Corner. Builds yard decor.'},
 {key='Level',name='XPWidget',units=3.6,always=true,title='LEVEL',tip=nil},
}
-- Halloween pills (built by StarterPlayerScripts.HalloweenClient.HUD); before LEVEL: the tooltips above index 1..3.
if U.HalloweenEnabled then table.insert(U.PillSpecs,4,{key='MoonCandy',name='MoonCandyPill',units=3,always=true,title='MOON CANDY'});table.insert(U.PillSpecs,5,{key='MoonCurse',name='MoonCursePill',units=3.6,title='CURSE'})end
-- Chapter II pills before LEVEL (WP-L): Bell Shards (in the Underyard or when > 0), Lucky Dust (when > 0)
if U.Chapter2Enabled then table.insert(U.PillSpecs,#U.PillSpecs,{key='BellShards',name='QuickShards',units=3,title='BELL SHARDS',tip='Earned in THE UNDERYARD. Offer them at the Bell Seal altars and open the Black Coffin.'})end
table.insert(U.PillSpecs,#U.PillSpecs,{key='LuckyDust',name='QuickDust',units=3,title='LUCKY DUST',tip='Dismantle Lucky Blocks for it in your bag and forge new Lucky Blocks with it.'})
local queuedLayout=setmetatable({},{__mode='k'})
-- Coalesced U.LayoutHUD (several changes in one frame lay out once).
function U.RequestHUDLayout(screen:any)
 if queuedLayout[screen]then return end
 queuedLayout[screen]=true
 task.defer(function()queuedLayout[screen]=nil;if screen.Parent then U.LayoutHUD(screen)end end)
end
-- A small "pop" (badges, counters): grows in with an overshoot. Instant with reduced motion.
function U.Pop(o:any)
 local pop=find(o,'Pop')
 if not(pop and pop:IsA('UIScale'))then pop=make('UIScale',{Name='Pop'},o)end
 if Motion.Reduced()then pop.Scale=1;return end
 pop.Scale=.45;Motion.Tween(pop,.34,{Scale=1},Enum.EasingStyle.Back)
end
local function stroked(label:any,thickness:number?):any
 label.TextStrokeTransparency=1
 local s=find(label,'CandyTextStroke')or make('UIStroke',{Name='CandyTextStroke'},label)
 s.Color=NAVY;s.Thickness=thickness or 2;s.Transparency=0;s.Enabled=true
 s.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;s.LineJoinMode=Enum.LineJoinMode.Round
 return s
end
local function textLimit(label:any,maxSize:number,minSize:number?):any
 local limit=findClass(label,'UITextSizeConstraint')or make('UITextSizeConstraint',{},label)
 limit.MinTextSize=1;limit.MaxTextSize=math.max(1,math.floor(maxSize));limit.MinTextSize=math.min(limit.MaxTextSize,minSize or 8)
 return limit
end
local function label(parent:any,name:string,text:string,z:number,props:any?):any
 local t=make('TextLabel',{Name=name,Text=text,BackgroundTransparency=1,FontFace=U.FontFace,TextColor3=WHITE,TextScaled=true,TextWrapped=false,
  TextXAlignment=Enum.TextXAlignment.Center,ZIndex=z},parent)
 for k,v in pairs(props or{})do(t::any)[k]=v end
 return t
end
-- The eye of HIDE UI (slashed) and of the show-UI button (open), drawn with frames.
function U.EyeGlyph(parent:any,z:number,slashed:boolean?,color:Color3?):any
 local ink=color or NAVY
 local old=find(parent,'EyeGlyph');if old then old:Destroy()end
 local holder=make('Frame',{Name='EyeGlyph',BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.66,.66),ZIndex=z},parent)
 local white=make('Frame',{Name='White',BackgroundColor3=WHITE,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(1,.6),ZIndex=z},holder)
 make('UICorner',{CornerRadius=UDim.new(.5,0)},white);U.Stroke(white,ink,2.5)
 local pupil=make('Frame',{Name='Pupil',BackgroundColor3=ink,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.36,.36),ZIndex=z+1},holder)
 make('UICorner',{CornerRadius=UDim.new(.5,0)},pupil)
 if slashed then
  local slash=make('Frame',{Name='Slash',BackgroundColor3=ink,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(1.1,0,0,4),Rotation=-38,ZIndex=z+2},holder)
  make('UICorner',{CornerRadius=UDim.new(.5,0)},slash);U.Stroke(slash,WHITE,1.5)
 end
 return holder
end
-- Hover lift (scale up, icon rises, soft glow), press squash and the release spring of a HUD
-- button, plus its hover / click sounds. `glow` is a UIStroke shown on hover (mouse / gamepad).
local function hudMotion(b:any,icon:any,glow:any,hoverScale:number?)
 local scale=find(b,'TileMotion')
 if not(scale and scale:IsA('UIScale'))then scale=make('UIScale',{Name='TileMotion'},b)end
 local hover,pressed=false,false
 local home=icon and icon.Position
 local function draw()
  local goal=pressed and .92 or hover and(hoverScale or 1.07)or 1
  if pressed then Motion.Tween(scale,.07,{Scale=goal})else Motion.Tween(scale,.18,{Scale=goal},Enum.EasingStyle.Back)end
  if icon and home then Motion.Tween(icon,.18,{Position=home+UDim2.fromOffset(0,(hover and not pressed)and -3 or 0)},Enum.EasingStyle.Back)end
  if glow then Motion.Tween(glow,.12,{Transparency=hover and .2 or 1})end
 end
 b.MouseEnter:Connect(function()if Sound.MouseInput()then hover=true;draw()end end)
 b.MouseLeave:Connect(function()hover,pressed=false,false;draw()end)
 b.MouseButton1Down:Connect(function()pressed=true;draw()end)
 b.MouseButton1Up:Connect(function()pressed=false;draw()end)
 b.SelectionGained:Connect(function()hover=true;draw()end)
 b.SelectionLost:Connect(function()hover,pressed=false,false;draw()end)
 Sound.Attach(b)
end
local function tooltip(target:any,spec:any)
 local k=kit();if not k then return end
 pcall(function()
  k.Tooltip(target,function()
   local title=U.L(spec.title or spec.label or'')
   if spec.hotkey and not UserInput.TouchEnabled then title=title..'  ['..spec.hotkey..']'end
   return spec.tip and U.L(spec.tip)or'',title
  end)
 end)
end
-- A rail tile on an existing root / button (or new HUD.Quick<Key>.Open).
local function buildTile(hud:any,spec:any,root:any,b:any):any
 root=root or make('Frame',{Name='Quick'..spec.key},hud)
 b=b or make('TextButton',{Name='Open',Text='',AutoButtonColor=false},root)
 root.BackgroundTransparency=1;root.AnchorPoint=Vector2.zero;root.Size=UDim2.fromOffset(68,68);root.ZIndex=10;root.ClipsDescendants=false
 for _,o in ipairs(root:GetChildren())do if o:IsA('UIAspectRatioConstraint')or o:IsA('UISizeConstraint')then o:Destroy()end end
 for _,o in ipairs(b:GetChildren())do
  if o:IsA('GuiObject')then o.Visible=false
  elseif o:IsA('UIPadding')then o:Destroy()
  elseif o:IsA('UIStroke')or o:IsA('UIGradient')then o.Enabled=false end
 end
 -- A transparent hit target with its own face: UITheme.EnhanceButton leaves it alone.
 b.Text='';b.AutoButtonColor=false;b.BackgroundTransparency=1;b.BorderSizePixel=0;b.Position=UDim2.new();b.Size=UDim2.fromScale(1,1);b.ZIndex=11;b.ClipsDescendants=false
 b:SetAttribute('CandyPage',spec.key)
 local z=12
 local face=make('Frame',{Name='CandyFace',BackgroundColor3=WHITE,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=z},b)
 make('UICorner',{CornerRadius=UDim.new(.3,0)},face);U.Stroke(face,NAVY,2.5)
 make('UIGradient',{Color=ColorSequence.new(spec.color:Lerp(WHITE,.28),spec.color:Lerp(NAVY,.12)),Rotation=90},face)
 local shine=make('Frame',{Name='CandyShine',BackgroundColor3=WHITE,BackgroundTransparency=.72,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(.5,.07),Size=UDim2.fromScale(.78,.34),ZIndex=z+1},face)
 make('UICorner',{CornerRadius=UDim.new(.5,0)},shine)
 local glowFrame=make('Frame',{Name='CandyGlow',BackgroundTransparency=1,Position=UDim2.fromOffset(-3,-3),Size=UDim2.new(1,6,1,6),ZIndex=z},b)
 make('UICorner',{CornerRadius=UDim.new(.32,0)},glowFrame)
 local glow=make('UIStroke',{Name='Glow',Color=WHITE,Thickness=3,Transparency=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},glowFrame)
 local icon=make('ImageLabel',{Name='CandyIcon',BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit,Image=U.Assets[spec.key]or GameIcons.Resolve(spec.key)or'',
  AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.42),Size=UDim2.fromScale(.8,.8),ZIndex=z+3},b)
 if icon.Image==''and spec.glyph then local g=label(b,'HwGlyph',spec.glyph,z+3,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.42),Size=UDim2.fromScale(.72,.72)});g:SetAttribute('NoTranslate',true)end
 local caption=label(b,'CandyCaption',U.L(spec.label),z+5,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,1,-3),Size=UDim2.new(1,12,0,16)})
 caption:SetAttribute('NoTranslate',true);stroked(caption,2);textLimit(caption,16,8)
 local badge=label(b,'CandyBadge','',z+7,{AutomaticSize=Enum.AutomaticSize.X,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,6,0,-6),Size=UDim2.fromOffset(20,20),
  BackgroundTransparency=0,BackgroundColor3=U.Colors.red,BorderSizePixel=0,Visible=false,TextScaled=false,TextSize=13})
 badge:SetAttribute('NoTranslate',true);make('UICorner',{CornerRadius=UDim.new(.5,0)},badge);U.Stroke(badge,WHITE,2)
 make('UIPadding',{PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5)},badge)
 hudMotion(b,icon,glow)
 tooltip(b,spec)
 local sc=findClass(root,'UIScale')or make('UIScale',{Name='CandyHUDScale'},root)
 return {root=root,button=b,scale=sc,key=spec.key,face=face,icon=icon,caption=caption,badge=badge,spec=spec}
end
-- Text / colour of a rail tile's corner badge ("" hides it). Pops when the text changes.
function U.SetTileBadge(key:string,text:any,color:Color3?)
 for _,t in ipairs(U.QuickTiles or{})do
  if t.key==key and t.badge then
   local value=text~=nil and tostring(text)or''
   local changed=t.badge.Text~=value
   t.badge.Text=value;t.badge.Visible=value~=''
   if color then t.badge.BackgroundColor3=color end
   if changed and value~=''then U.Pop(t.badge)end
  end
 end
end
-- A currency pill frame (navy glass, white rim); MoneyWidget and XPWidget get one too.
local function pillFace(root:any,z:number):any
 local old=find(root,'CandyPill');if old then old:Destroy()end
 local face=make('Frame',{Name='CandyPill',BackgroundColor3=NAVY,BackgroundTransparency=.25,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=z},root)
 make('UICorner',{CornerRadius=UDim.new(.5,0)},face);U.Stroke(face,WHITE,2,.7)
 make('UIGradient',{Color=ColorSequence.new(C(255,255,255),C(165,175,195)),Rotation=90},face)
 return face
end
local function pillIcon(root:any,key:string,glyph:string?,z:number):any
 local old=find(root,'CandyPillIcon');if old then old:Destroy()end
 local image=U.Assets[key]or GameIcons.Resolve(key)
 local icon
 if image then icon=make('ImageLabel',{Name='CandyPillIcon',BackgroundTransparency=1,Image=image,ScaleType=Enum.ScaleType.Fit,ZIndex=z},root)
 else icon=label(root,'CandyPillIcon',glyph or'●',z,{TextScaled=true});icon:SetAttribute('NoTranslate',true)end
 icon.Position=UDim2.fromOffset(3,3);icon.Size=UDim2.fromOffset(40,40)
 return icon
end
-- Animated number on a label: counts up (Quad out, 0.5 s), snaps down; instant with reduced motion.
local function counter(holder:any,valueLabel:any,format:(number)->string)
 local value=find(holder,'CandyCount')
 if not(value and value:IsA('NumberValue'))then value=make('NumberValue',{Name='CandyCount'},holder)end
 local tween=nil
 value.Changed:Connect(function(v)valueLabel.Text=format(v)end)
 return function(target)
  target=tonumber(target)or 0
  if tween then tween:Cancel();tween=nil end
  if target<=value.Value or Motion.Reduced()then value.Value=target;valueLabel.Text=format(target);return end
  tween=Tween:Create(value,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Value=target});tween:Play()
 end
end
local short=nil
local function shortNumber(n)
 if not short then local ok,f=pcall(require,script.Parent.Kit.Format);short=ok and f or false end
 if short then return short.Short(math.floor(n+.5))end
 return tostring(math.floor(n+.5))
end
local function buildPills(screen:any,hud:any)
 local player=Players.LocalPlayer
 -- Coins: MoneyWidget (MoneyController animates and fits the amount).
 local money=hud.MoneyWidget
 money.AnchorPoint=Vector2.zero;money.BackgroundTransparency=1;money.ZIndex=10
 for _,o in ipairs(money:GetDescendants())do if o:IsA('UIStroke')and o.Name~='CandyTextStroke'then o.Enabled=false end;if o:IsA('UIPadding')then o:Destroy()end end
 for _,o in ipairs(money:GetChildren())do if o.Name=='Shadow'then o.Visible=false end end
 pillFace(money,10);pillIcon(money,'Coins','$',13)
 local mm=money.Main;mm.BackgroundTransparency=1;mm.ZIndex=11;mm.Position=UDim2.fromOffset(46,0);mm.Size=UDim2.new(1,-52,1,0)
 mm.CurrencyBox.Visible=false;mm.Label.Visible=false
 local amount=mm.Amount;typeface(amount,30,true);amount.TextColor3=C(150,255,90);stroked(amount,2);amount.TextXAlignment=Enum.TextXAlignment.Left;amount.TextWrapped=false
 if amount.Text:sub(1,1)~='$'then amount.Text='$'..amount.Text end
 money:SetAttribute('HUDGrowLeft',false)
 -- Level: LV + a slim progress bar (the exact XP shows in the tooltip).
 local xp=hud.XPWidget
 xp.AnchorPoint=Vector2.zero;xp.BackgroundTransparency=1;xp.ZIndex=10
 for _,o in ipairs(xp:GetChildren())do if o.Name=='Shadow'then o.Visible=false end end
 local xm=xp.Main;xm.BackgroundTransparency=1;xm.Position=UDim2.new();xm.Size=UDim2.fromScale(1,1);xm.ZIndex=11
 for _,o in ipairs(xm:GetChildren())do if o:IsA('UIStroke')then o.Enabled=false end end
 pillFace(xp,10)
 local level=xm.LevelLabel;typeface(level,24,true);level.TextColor3=C(110,226,255);stroked(level,2);level.TextScaled=true;textLimit(level,26,10)
 level.TextXAlignment=Enum.TextXAlignment.Center;level.AnchorPoint=Vector2.zero;level.Position=UDim2.fromOffset(8,0);level.Size=UDim2.fromOffset(76,46)
 xm.XPText.Visible=false
 local barBg=xm.XPBarBackground;barBg.Visible=true;barBg.ZIndex=12;barBg.AnchorPoint=Vector2.new(0,.5);barBg.BackgroundColor3=C(12,26,50);barBg.BackgroundTransparency=.15
 local g=findClass(barBg,'UIGradient');if g then g.Enabled=false end
 local bs=findClass(barBg,'UIStroke');if bs then bs.Enabled=true;bs.Color=WHITE;bs.Transparency=.6;bs.Thickness=1.5 end
 U.Round(barBg,6)
 local fill=barBg.Fill;fill.BackgroundColor3=C(78,220,255);fill.ZIndex=13;U.Round(fill,6)
 for _,o in ipairs(fill:GetChildren())do if o:IsA('UIStroke')then o.Enabled=false end end
 -- Bones and stone: shown once you own some.
 local function simplePill(name,key,glyph,color)
  local old=find(hud,name);if old then old:Destroy()end
  local root=make('Frame',{Name=name,BackgroundTransparency=1,Size=UDim2.fromOffset(138,46),Visible=false,ZIndex=10},hud)
  make('UIScale',{Name='CandyHUDScale'},root)
  pillFace(root,10);pillIcon(root,key,glyph,13)
  local value=label(root,'Value','0',13,{TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(48,0),Size=UDim2.new(1,-58,1,0),TextColor3=color})
  value:SetAttribute('NoTranslate',true);stroked(value,2);textLimit(value,28,10)
  return root,value
 end
 local bonesRoot,bonesValue=simplePill('QuickBones','Bones','🦴',C(255,244,214))
 local stoneRoot,stoneValue=simplePill('QuickStone','Stone','🪨',C(226,222,214))
 local setBones=counter(bonesRoot,bonesValue,shortNumber)
 local setStone=counter(stoneRoot,stoneValue,shortNumber)
 local function showPill(root,amount)
  local had=(root:GetAttribute('HUDValue')or 0)>0
  root:SetAttribute('HUDValue',amount)
  if had~=(amount>0)then U.RequestHUDLayout(screen)end
 end
 local function bones()local n=math.max(0,tonumber(player:GetAttribute('Bones'))or 0);setBones(n);showPill(bonesRoot,n)end
 player:GetAttributeChangedSignal('Bones'):Connect(bones);bones()
 -- Chapter II (WP-L): Lucky Dust (when > 0) and Bell Shards (in the Underyard or when > 0), with the built Underyard icons.
 local function uyArt(root,kind)
  local holder=find(root,'CandyPillIcon');if not holder then return end
  local folder=game:GetService('ReplicatedStorage'):FindFirstChild('Halloween')
  local mod=folder and folder:FindFirstChild('UnderyardIcons')
  if not mod then return end
  pcall(function()
   local UI=require(mod)
   UI.New(holder,kind,{Size=40,ZIndex=14,FrameSize=UDim2.fromScale(1.05,1.05),Position=UDim2.fromScale(.5,.5),AnchorPoint=Vector2.new(.5,.5)})
   if holder:IsA('TextLabel')then holder.TextTransparency=1 end
  end)
 end
 local dustRoot,dustValue=simplePill('QuickDust','LuckyDust','✨',C(255,228,150))
 uyArt(dustRoot,'Dust')
 local setDust=counter(dustRoot,dustValue,shortNumber)
 local function dust()local n=math.max(0,tonumber(player:GetAttribute('LuckyDust'))or 0);setDust(n);showPill(dustRoot,n)end
 player:GetAttributeChangedSignal('LuckyDust'):Connect(dust);dust()
 local shardRoot=nil
 if U.Chapter2Enabled then
  local shardValue
  shardRoot,shardValue=simplePill('QuickShards','BellShards','🔔',C(222,196,255))
  uyArt(shardRoot,'Shard')
  local setShards=counter(shardRoot,shardValue,shortNumber)
  local function shards()
   local n=math.max(0,tonumber(player:GetAttribute('BellShards'))or 0);setShards(n)
   -- in the Underyard the pill stays up even at 0 (offerings, the coffin and the Toll Box are priced in shards)
   showPill(shardRoot,(n>0 or player:GetAttribute('UyInZone')==true)and math.max(n,1)or 0)
  end
  player:GetAttributeChangedSignal('BellShards'):Connect(shards);player:GetAttributeChangedSignal('UyInZone'):Connect(shards);shards()
 end
 U.ChapterPills={Dust=dustRoot,Shards=shardRoot}
 -- Stone: p.Resources.Stone from a player attribute when the server publishes one, otherwise
 -- from any economy snapshot (Modules.Net), refreshed after ores break at the Mining Corner.
 local lastStone=nil
 local function stone(n)
  n=math.max(0,math.floor(tonumber(n)or 0));if n==lastStone then return end
  lastStone=n;setStone(n);showPill(stoneRoot,n)
 end
 if type(player:GetAttribute('Stone'))=='number'then stone(player:GetAttribute('Stone'))end
 player:GetAttributeChangedSignal('Stone'):Connect(function()stone(player:GetAttribute('Stone'))end)
 task.spawn(function()
  local ok,Net=pcall(require,script.Parent.Net);if not ok or type(Net)~='table'then return end
  local function fromSnapshot(snapshot)
   if type(player:GetAttribute('Stone'))=='number'then return end
   local p=type(snapshot)=='table'and snapshot.Profile;local r=type(p)=='table'and p.Resources
   if type(r)=='table'then stone(r.Stone)elseif type(p)=='table'then stone(0)end
  end
  Net.Changed:Connect(fromSnapshot)
  local pending=false
  player:GetAttributeChangedSignal('MiningOresBroken'):Connect(function()
   if pending or type(player:GetAttribute('Stone'))=='number'then return end
   pending=true
   task.delay(8,function()pending=false;Net.Snapshot(6)end)
  end)
  if Net.Cached()then fromSnapshot(Net.Cached())end
 end)
 -- Tooltips explain each pill (hover / long press).
 local k=kit()
 if k then
  pcall(function()
   k.Tooltip(money,function()return U.L(U.PillSpecs[1].tip),U.L('COINS')end)
   k.Tooltip(bonesRoot,function()return U.L(U.PillSpecs[2].tip),U.L('BONES')end)
   k.Tooltip(stoneRoot,function()return U.L(U.PillSpecs[3].tip),U.L('STONE')end)
   k.Tooltip(xp,function()return xm.XPText.Text,U.L('LEVEL')..' '..tostring(player:GetAttribute('Level')or 1)end)
   for _,spec in ipairs(U.PillSpecs)do
    local root=(spec.key=='LuckyDust'and dustRoot)or(spec.key=='BellShards'and shardRoot)or nil
    if root then k.Tooltip(root,function()return U.L(spec.tip),U.L(spec.title)end)end
   end
  end)
 end
end
-- BAG: "23/50" (orange from 80 %, red and pulsing when full; pops on every new find). The old
-- Capacity label stays hidden (InventoryController still writes it). EVENTS: "!" while a world
-- event runs (orange during its warning).
local function bindBadges(hud:any)
 local player=Players.LocalPlayer
 local bag;for _,t in ipairs(U.QuickTiles or{})do if t.key=='Inventory'then bag=t end end
 if bag then
  local cap=find(bag.button,'Capacity');if cap and cap:IsA('GuiObject')then cap.Visible=false end
  local pulse=nil
  local function refresh()
   local count,capacity=player:GetAttribute('ItemCount'),player:GetAttribute('ItemCapacity')
   if type(count)~='number'or type(capacity)~='number'then return end
   local full=capacity>0 and count>=capacity
   U.SetTileBadge('Inventory',string.format('%d/%d',count,capacity),full and U.Colors.red or(capacity>0 and count>=capacity*.8)and C(214,128,18)or NAVY)
   if full and not pulse then pulse=Motion.Loop(bag.badge,.6,{BackgroundTransparency=.35})
   elseif not full and pulse then pulse:Cancel();pulse=nil;bag.badge.BackgroundTransparency=0 end
  end
  for _,n in ipairs({'ItemCount','ItemCapacity'})do player:GetAttributeChangedSignal(n):Connect(refresh)end
  refresh()
 end
 task.spawn(function()
  local events=game:GetService('ReplicatedStorage'):WaitForChild('WorldEvents',30)
  local state=events and events:WaitForChild('State',30)
  if not state then return end
  local function eventBadge()
   local phase=state:GetAttribute('State')
   if phase=='ACTIVE'then U.SetTileBadge('Events','!',U.Colors.red)
   elseif phase=='WARNING'then U.SetTileBadge('Events','!',C(214,128,18))
   else U.SetTileBadge('Events','')end
  end
  state:GetAttributeChangedSignal('State'):Connect(eventBadge);eventBadge()
 end)
end
-- The rail (left), currency pills (top) and badges. The cluster is built by U.BuildCluster.
function U.BuildHUD(screen:any)
 local hud=screen.HUD
 local tiles={}
 for _,spec in ipairs(U.RailSpecs)do
  local root,b
  if spec.key=='Yard'then root=hud.PawpadWidget;b=root.PawpadButton
  elseif spec.key=='Inventory'then root=hud.InventoryWidget;b=root.InventoryButton end
  for _,o in ipairs(root and root:GetChildren()or{})do if o.Name=='Shadow'then o.Visible=false end end
  table.insert(tiles,buildTile(hud,spec,root,b))
 end
 U.QuickTiles=tiles
 -- tiles shown only while a player attribute is true (spec.when, e.g. the UNDERYARD tile after Chapter I)
 local player0=Players.LocalPlayer
 for _,spec in ipairs(U.RailSpecs)do
  if spec.when then player0:GetAttributeChangedSignal(spec.when):Connect(function()U.RequestHUDLayout(screen)end)end
 end
 local dig=find(hud,'GlobalDigWidget');if dig then dig.Visible=false end
 -- A tooltip shown over a tile must not stay on screen once a menu (or Hide UI) hides the HUD.
 hud:GetPropertyChangedSignal('Visible'):Connect(function()
  if not hud.Visible then pcall(function()require(script.Parent.Kit.Feedback).HideTooltip()end)end
 end)
 buildPills(screen,hud)
 bindBadges(hud)
 -- The captions localize themselves: follow a language change.
 local player=Players.LocalPlayer
 player:GetPropertyChangedSignal('LocaleId'):Connect(function()
  task.defer(function()for _,t in ipairs(U.QuickTiles or{})do t.caption.Text=U.L(t.spec.label)end end)
 end)
end
-- NAVIGATE, TITLES, HIDE UI and SETTINGS: round buttons at the top-right (HUD.<name>.Open).
function U.BuildCluster(screen:any)
 local hud=screen.HUD
 for _,spec in ipairs(U.ClusterSpecs)do
  local old=find(hud,spec.name);if old then old:Destroy()end
  local root=make('Frame',{Name=spec.name,BackgroundTransparency=1,AnchorPoint=Vector2.zero,Size=UDim2.fromOffset(44,44),ZIndex=12},hud)
  local b=make('TextButton',{Name='Open',Text='',AutoButtonColor=false,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=12},root)
  local face=make('Frame',{Name='CandyFace',BackgroundColor3=WHITE,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=12},b)
  make('UICorner',{CornerRadius=UDim.new(.5,0)},face);U.Stroke(face,NAVY,2.5)
  make('UIGradient',{Color=ColorSequence.new(WHITE,C(206,228,250)),Rotation=90},face)
  local glowFrame=make('Frame',{Name='CandyGlow',BackgroundTransparency=1,Position=UDim2.fromOffset(-3,-3),Size=UDim2.new(1,6,1,6),ZIndex=12},b)
  make('UICorner',{CornerRadius=UDim.new(.5,0)},glowFrame)
  local glow=make('UIStroke',{Name='Glow',Color=WHITE,Thickness=3,Transparency=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},glowFrame)
  local icon
  if spec.eye then icon=U.EyeGlyph(b,14,true)
  else
   local image=spec.icon and(U.Assets[spec.icon]or GameIcons.Resolve(spec.icon))
   if image then icon=make('ImageLabel',{Name='CandyIcon',BackgroundTransparency=1,Image=image,ScaleType=Enum.ScaleType.Fit,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.7,.7),ZIndex=14},b)
   else icon=label(b,'CandyGlyph',spec.glyph or'★',14,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.66,.66),TextColor3=NAVY});icon:SetAttribute('NoTranslate',true)end
  end
  hudMotion(b,icon,glow,1.1)
  tooltip(b,spec)
  if spec.module then
   local modules=script.Parent
   local function wanted()root:SetAttribute('HUDWanted',find(modules,spec.module)~=nil);U.RequestHUDLayout(screen)end
   modules.ChildAdded:Connect(wanted);wanted()
  end
 end
end
function U.LayoutHUD(screen:any)
 local hud=find(screen,'HUD');if not hud then return end
 local left,top,width,height=U.SafeArea(screen);local touch=UserInput.TouchEnabled
 local jx,jy,thumb=U.TouchReserve(screen,left,top,width,height)
 local tiles={}
 local lp=Players.LocalPlayer
 for _,t in ipairs(U.QuickTiles or{})do
  local on=not(t.spec and t.spec.when)or(lp~=nil and lp:GetAttribute(t.spec.when)==true)
  t.root.Visible=on
  if on then table.insert(tiles,t)end
 end
 local cluster={}
 for _,spec in ipairs(U.ClusterSpecs)do
  local root=find(hud,spec.name)
  if root and root:IsA('GuiObject')then
   local on=root:GetAttribute('HUDWanted')~=false;root.Visible=on
   if on then table.insert(cluster,root)end
  end
 end
 local pillUnits,pillRoots={},{}
 for _,spec in ipairs(U.PillSpecs)do
  local root=find(hud,spec.name)
  if root and root:IsA('GuiObject')then
   local on=spec.always or(root:GetAttribute('HUDValue')or 0)>0;root.Visible=on
   if on then table.insert(pillUnits,spec.units);table.insert(pillRoots,root)end
  end
 end
 -- The Roblox leaderboard covers the top-right (it is hidden while Hide UI is on: keep the last answer).
 local playerList=U.HUD and U.HUD.PlayerList or false
 if not screen:GetAttribute('UIHidden')then pcall(function()playerList=StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)end)end
 local o=HUDLayout.Compute({Left=left,Top=top,Width=width,Height=height,Touch=touch,JumpX=jx,JumpY=jy,Thumb=thumb,
  Tiles=#tiles,Cluster=#cluster,PlayerList=playerList,Pills=pillUnits})
 -- Rail.
 local B=o.Rail.Size;local labelH=o.Rail.LabelH
 for i,t in ipairs(tiles)do
  local cell=o.Rail.Cells[i]
  t.scale.Scale=1;t.root.AnchorPoint=Vector2.zero;t.root.Size=UDim2.fromOffset(B,B);t.root.Position=UDim2.fromOffset(cell.X,cell.Y)
  t.root:SetAttribute('HUDEdge','Left')
  t.caption.Size=UDim2.new(1,math.floor(B*.2),0,labelH);t.caption.Position=UDim2.new(.5,0,1,-math.floor(labelH*.15))
  textLimit(t.caption,labelH,7)
  local badgeH=math.clamp(math.floor(B*.3),16,22)
  t.badge.Size=UDim2.fromOffset(badgeH,badgeH);t.badge.TextSize=math.max(11,badgeH-7)
 end
 -- Cluster.
 for i,root in ipairs(cluster)do
  local cell=o.Cluster.Cells[i]
  root.AnchorPoint=Vector2.zero;root.Size=UDim2.fromOffset(o.Cluster.Size,o.Cluster.Size);root.Position=UDim2.fromOffset(cell.X,cell.Y)
  root:SetAttribute('HUDEdge',o.Cluster.Vertical and'Right'or'Top')
 end
 -- Currency pills: 46 px-tall widgets scaled to the bar height.
 local unit=o.Bar.Unit
 for i,root in ipairs(pillRoots)do
  local cell=o.Bar.Cells[i];local w46=math.max(60,cell.W/unit)
  local sc=findClass(root,'UIScale')or make('UIScale',{Name='CandyHUDScale'},root)
  sc.Scale=unit;root.AnchorPoint=Vector2.zero;root.Size=UDim2.fromOffset(w46,46);root.Position=UDim2.fromOffset(cell.X,cell.Y)
  root:SetAttribute('HUDEdge','Top')
  if root.Name=='MoneyWidget'then root:SetAttribute('HUDMaxRight',cell.X+cell.W-math.floor(6*unit))
  elseif root.Name=='XPWidget'then
   local barBg=find(root.Main,'XPBarBackground')
   if barBg then barBg.Position=UDim2.new(0,88,.5,0);barBg.Size=UDim2.fromOffset(math.max(20,w46-102),12)end
  end
 end
 -- Free zone: offline notice, income chip (HUDStatsController), map marker button, bag toast.
 local notice=find(hud,'OfflineEarningsNotice')
 if notice then
  notice.AnchorPoint=Vector2.new(.5,0);notice.Position=UDim2.fromOffset(o.Notice.X,o.Notice.Y);notice.Size=UDim2.fromOffset(o.Notice.W,o.Notice.H)
  notice:SetAttribute('HUDEdge','Top')
  local caption=find(notice,'Caption');if caption then caption.TextSize=touch and 15 or 17;caption.Size=UDim2.new(1,-12,1,-4)end
 end
 screen:SetAttribute('HUDIncomeSlot',Vector2.new(o.Chip.X,o.Chip.Y))
 local guide=find(screen,'DistrictGuide');local clear=guide and find(guide,'ClearMarker')
 if clear and clear:IsA('GuiObject')then clear.AnchorPoint=Vector2.zero;clear.Position=UDim2.fromOffset(o.Clear.X,o.Clear.Y)end
 local toast=find(screen,'InventoryToast')
 if toast then toast.AnchorPoint=Vector2.new(.5,0);toast.Position=UDim2.fromOffset(o.Toast.X,o.Toast.Y);toast.Size=UDim2.fromOffset(o.Toast.W,o.Toast.H)end
 U.HUD={Touch=touch,Scale=o.Scale,Left=left,Top=top,Width=width,Height=height,InnerLeft=o.Free.Left,InnerRight=o.Free.Right,JumpX=jx,JumpY=jy,
  StatsBottom=o.Bar.Bottom,BuffRight=o.Buff.Right,BuffTop=o.Buff.Top,BuffBottom=o.Buff.Bottom,PlayerList=playerList,Layout=o}
 screen:SetAttribute('HUDInnerLeft',o.Free.Left);screen:SetAttribute('HUDInnerRight',o.Free.Right);screen:SetAttribute('HUDFreeTop',o.Free.Top)
end
U.LayoutTouchHUD=U.LayoutHUD
function U.ApplyShell(screen)
 -- Rebuild generated decoration when loading a place saved with an editor preview.
 for _,o in ipairs(screen:GetDescendants())do
  if o.Name=='CandyIcon'or o.Name=='CandyCaption'or o.Name=='SelectedMark'or o.Name=='CandyEmpty'or o.Name=='CandyStart'then o:Destroy()end
 end
 for _,o in ipairs(screen.HUD:GetChildren())do if o.Name:match('^Quick')then o:Destroy()end end
 for _,o in ipairs(screen.MainWindow.Sidebar:GetChildren())do if o.Name=='Label'or o.Name=='InventoryButton'then o:Destroy()end end
 screen:SetAttribute('CandyShellV1',true)
 local window=screen.MainWindow;local side=window.Sidebar;local header=window.Header
 local content=window.Content;local pages=content.PageContainer;local hud=screen.HUD
 for _,o in ipairs(window:GetDescendants())do
  if o:IsA('GuiObject')then
   if o:IsA('TextLabel')or o:IsA('TextBox')or o:IsA('TextButton')then
    typeface(o,o:IsA('TextButton')and 20 or math.clamp(o.TextSize,18,24),o:IsA('TextButton'))
    if o:IsA('TextBox')then o.PlaceholderColor3=C(92,116,150)end
   end
   if (o:IsA('Frame')or o:IsA('ScrollingFrame')or o:IsA('TextBox'))and o.BackgroundTransparency<.95 then
    surface(o,o.Name:find('Preview')and C(214,238,255)or WHITE,12,2)
   elseif o:IsA('TextButton')then surface(o,C(37,180,238),10,2);if o.Text~=''then o.BackgroundTransparency=0 end end
   if o.Name:find('Shadow')then o.Visible=false end
   if o:IsA('ScrollingFrame')then o.ScrollBarImageColor3=C(62,171,240);o.ScrollBarThickness=6 end
  end
 end
 for _,o in ipairs(window:GetChildren())do if o:IsA('UIAspectRatioConstraint')or o:IsA('UISizeConstraint')then o:Destroy()end end
 surface(window,PALE,22,4);window.ClipsDescendants=false
 window.AnchorPoint=Vector2.new(.5,.5);window.Position=UDim2.new(.5,0,.5,24);window.Size=UDim2.fromOffset(1160,740)
 local scale=window:FindFirstChildWhichIsA('UIScale')or U.New('UIScale',{Name='ResponsiveScale'},window)
 surface(header,C(35,187,244),17,3);rect(header,12,12,1136,84)
 rect(header.Title,94,8,295,40);header.Title.Text='DOGROTS';typeface(header.Title,34,true)
 rect(header.Subtitle,97,48,295,23);header.Subtitle.Text='YOUR PACK. YOUR ADVENTURE.';typeface(header.Subtitle,13,true)
 U.AssetIcon(header,'Dogs',9,-8,96)
 surface(header.StatsPanel,C(17,120,194),12,2);rect(header.StatsPanel,600,15,360,54)
 rect(header.StatsPanel.StatsContent,10,6,340,42)
 local stats=header.StatsPanel.StatsContent
 local lay=stats:FindFirstChildWhichIsA('UIListLayout');if lay then lay.FillDirection=Enum.FillDirection.Horizontal;lay.Padding=UDim.new(0,8);lay.VerticalAlignment=Enum.VerticalAlignment.Center end
 for _,o in ipairs(stats:GetChildren())do if o:IsA('TextLabel')then o.Size=UDim2.fromOffset(108,40);typeface(o,16,true);o.TextScaled=true;local limit=o:FindFirstChildWhichIsA('UITextSizeConstraint')or U.New('UITextSizeConstraint',{},o);limit.MaxTextSize=17;limit.MinTextSize=10 end end
 surface(header.CloseButton,C(250,76,123),13,3);rect(header.CloseButton,1062,15,58,54);typeface(header.CloseButton,31,true)
 header.CloseButton.Text='X'
 side.BackgroundTransparency=1;rect(side,18,111,176,607)
 for _,o in ipairs(side:GetChildren())do if o:IsA('UIListLayout')or o:IsA('UIPadding')then o:Destroy()end end
 local inventory=side:FindFirstChild('InventoryButton')or U.New('TextButton',{Name='InventoryButton',Text='',AutoButtonColor=false},side)
 local sideOrder={'Yard','Dogs','Inventory','DogDex','Trade','Lab','Shop','Events'}
 for i,key in ipairs(sideOrder)do
  local b=side:FindFirstChild(key..'Button');local spec=byKey[key]
  if b then
   b:SetAttribute('CandyPage',key);b.Text='';b.BackgroundTransparency=0;rect(b,12,12+(i-1)*66,152,56);b.ClipsDescendants=false
   for _,o in ipairs(b:GetChildren())do if o:IsA('UIPadding')or o:IsA('UIAspectRatioConstraint')then o:Destroy()end end
   U.SetNavState(b,key=='Yard');U.AssetIcon(b,key,0,-3,55)
   local text=U.New('TextLabel',{Name='CandyCaption',BackgroundTransparency=1,Text=spec.label,Position=UDim2.fromOffset(55,3),Size=UDim2.fromOffset(94,50),ZIndex=b.ZIndex+3},b)
   typeface(text,18,true);text.TextXAlignment=Enum.TextXAlignment.Left
   local marker=U.Frame(b,'SelectedMark',-5,16,4,24,WHITE);U.Round(marker,3);marker.Visible=key=='Yard'
  end
 end
 U.Text(side,'P  OPEN / CLOSE',12,565,152,20,12,C(81,112,151))
 content.BackgroundTransparency=1;rect(content,211,111,931,610)
 pages.BackgroundTransparency=1;pages.Position=UDim2.new();pages.Size=UDim2.fromScale(1,1)
 for _,p in ipairs(pages:GetChildren())do
  if p:IsA('GuiObject')and p.Name:match('Page$')then
   p.Position=UDim2.new();p.Size=UDim2.fromScale(1,1);p.BackgroundTransparency=1
   local h=p:FindFirstChild('PageHeader')or p:FindFirstChild('InventoryHeader')or p:FindFirstChild('YardHeader')
   local spec=byKey[p.Name:gsub('Page$','')]
   if h then surface(h,spec and spec.color or C(38,177,240),12,2)
    for _,t in ipairs(h:GetDescendants())do if t:IsA('TextLabel')then typeface(t,t.Name=='Capacity'and 20 or 28,true)end end
   end
  end
 end
 U.LayoutYard(pages.YardPage)
 -- HUD: menu rail, currency pills and badges (the cluster follows in ApplyStandalone).
 U.BuildHUD(screen)
 screen.Backdrop.BackgroundColor3=C(14,29,58);screen.Backdrop.BackgroundTransparency=.25
 local function resize()
  local v=screen.AbsoluteSize
  if not screen:GetAttribute('StandaloneWindows')then scale.Scale=math.max(.25,math.min(1.05,(v.X-30)/1160,(v.Y-94)/740))end
  U.LayoutHUD(screen)
 end
 resize();U.WatchHUD(screen,resize)
 -- Helpful empty states sit outside automatic item grids.
 local dog=pages.DogsPage
 local empty=U.Frame(dog,'CandyEmpty',0,0,0,0);empty.BackgroundTransparency=1;empty.Position=UDim2.fromScale(.02,.26);empty.Size=UDim2.fromScale(.61,.67);empty.ZIndex=12
 U.AssetIcon(empty,'Dogs',160,12,155)
 local title=U.Center(empty,'YOUR PACK STARTS HERE',10,168,525,35,26,NAVY,true)
 U.Center(empty,'Adopt your first dog and put it to work!',30,206,485,45,18,C(81,107,143))
 local go=U.Button(empty,'Go','FIND YOUR FIRST DOG',130,270,290,52,nil,C(129,224,48));go.Active=true;go.Selectable=true
 local function dogEmpty()empty.Visible=dog.DogGrid.Empty.Visible;dog.DogGrid.Empty.TextTransparency=1 end
 dog.DogGrid.Empty:GetPropertyChangedSignal('Visible'):Connect(dogEmpty);dogEmpty()
 local inv=pages.InventoryPage;local e=inv.Browser.GridPanel.Main.Empty
 for _,filter in ipairs(inv.Browser.Filters:GetChildren())do local button=filter:FindFirstChild('Button');if button then typeface(button,14,true);button.TextScaled=true end end
 e.Position=UDim2.fromScale(.07,.31);e.Size=UDim2.fromScale(.86,.32);typeface(e,19,false)
 local cta=U.Button(inv.Browser.GridPanel.Main,'CandyStart','GO TO MY YARD',0,0,246,48,nil,C(129,224,48));cta.Active=true;cta.Selectable=true;cta.AnchorPoint=Vector2.new(.5,0);cta.Position=UDim2.fromScale(.5,.7);cta.ZIndex=15
 local function invEmpty()cta.Visible=e.Visible end;e:GetPropertyChangedSignal('Visible'):Connect(invEmpty);invEmpty()
 -- Illustrated shop banner; catalog availability and purchases stay server-owned.
 local shop=pages.ShopPage;surface(shop.FeaturedPanel,C(224,243,255),12,2)
 U.AssetIcon(shop.FeaturedPanel,'Shop',10,-3,80)
 shop.FeaturedPanel.Title.Position=UDim2.fromScale(.16,.12);shop.FeaturedPanel.Title.Size=UDim2.fromScale(.8,.35);typeface(shop.FeaturedPanel.Title,23,false)
 shop.FeaturedPanel.Description.Position=UDim2.fromScale(.16,.53);shop.FeaturedPanel.Description.Size=UDim2.fromScale(.8,.32);typeface(shop.FeaturedPanel.Description,17,false)
 for _,card in ipairs(shop.ProductGrid:GetChildren())do if card:IsA('Frame')and card:FindFirstChild('Preview')then
  local art=U.AssetIcon(card.Preview,'Shop',0,0,56);art.AnchorPoint=Vector2.new(.5,.5);art.Position=UDim2.fromScale(.5,.5)
  card.Preview.Caption.Visible=false;surface(card.Preview,C(252,225,244),10,1)
  typeface(card.ProductName,18,false);typeface(card.Description,15,false);typeface(card.Price,15,false);typeface(card.Details,17,true)
 end end
 local preview=shop.SelectedProductPanel.Preview;preview.Caption.Visible=false
 local art=U.AssetIcon(preview,'Shop',0,0,110);art.AnchorPoint=Vector2.new(.5,.5);art.Position=UDim2.fromScale(.5,.5)
 surface(preview,C(252,225,244),12,2)
end
function U.AttachNavigation(screen,N)
 for _,t in ipairs(U.QuickTiles or{})do
  if t.key~='Yard'and t.key~='Inventory'then t.button.Activated:Connect(function()N.OpenPage(t.key)end)end
 end
 -- Cluster: NAVIGATE (the route finder, or the district map until Modules.NavigatorScreen
 -- exists), TITLES, HIDE UI (Modules handles UIHidden: StarterPlayerScripts.HideUI).
 local function on(name,fn)
  local root=screen.HUD:FindFirstChild(name);local b=root and root:FindFirstChild('Open')
  if b and b:IsA('GuiButton')then b.Activated:Connect(fn)end
 end
 on('QuickNavigate',function()
  if script.Parent:FindFirstChild('NavigatorScreen')then N.OpenPage('Navigate');return end
  N.Close();local toggle=screen:FindFirstChild('ToggleDistrictMap');if toggle and toggle:IsA('BindableEvent')then toggle:Fire()end
 end)
 on('QuickTitles',function()N.OpenPage('Titles')end)
 on('QuickHideUI',function()if N.Owner=='HUD'then screen:SetAttribute('UIHidden',true)end end)
 local pages=screen.MainWindow.Content.PageContainer
 screen.MainWindow.Sidebar.InventoryButton.Activated:Connect(function()N.OpenPage('Inventory')end)
 pages.DogsPage.CandyEmpty.Go.Activated:Connect(function()N.Navigate('Factory')end)
 pages.InventoryPage.Browser.GridPanel.Main.CandyStart.Activated:Connect(function()N.Navigate('Your yard')end)
 local function selection()
  local key=screen:GetAttribute('OpenMenu')or'Yard'
  for _,b in ipairs(screen.MainWindow.Sidebar:GetChildren())do if b:IsA('TextButton')then U.SetNavState(b,b:GetAttribute('CandyPage')==key)end end
 end
 screen:GetAttributeChangedSignal('OpenMenu'):Connect(selection);selection()
end


-- Independent windows share a visual language, never a visible navigation shell.
U.WindowSpecs={
 Yard={Title='MY YARD',Subtitle='Your pack, your progress',Color=C(125,219,48),Icon='Yard'},
 Dogs={Title='MY DOGS',Subtitle='Choose a dog. Give it a job.',Color=C(255,169,38),Icon='Dogs'},
 DogDetail={Title='DOG DETAILS',Subtitle='Your dog, its ability and its next job',Color=C(255,169,38),Icon='Dogs'},
 Inventory={Title='MY BAG',Subtitle='Lucky blocks and discoveries',Color=C(26,192,239),Icon='Inventory'},
 DogDex={Title='DOG INDEX',Subtitle='100 discoveries + exclusive prizes',Color=C(92,142,250),Icon='DogDex'},
 Trade={Title='TRADE',Subtitle='Swap with players in this server',Color=C(41,204,168),Icon='Trade'},
 Shop={Title='PAW MARKET',Subtitle='Everything for a happier pack',Color=C(248,79,170),Icon='Shop'},
 Supplies={Title='SUPPLIES',Subtitle='Boosts priced for your pack',Color=C(123,219,51),Icon='Supplies'},
 Luck={Title='LUCK',Subtitle='Rarer dogs for the whole server',Color=C(46,204,113),Icon='Luck'},
 RewardMachine={Title='DOG-O-MATIC',Subtitle='One free DOG TOKEN. One random reward.',Color=C(171,105,247),Icon='RewardMachine'},
 Events={Title='WORLD EVENTS',Subtitle='What is coming, what it gives you',Color=C(255,192,32),Icon='Events'},
 Lab={Title='GENETICS LAB',Subtitle='Discover new possibilities',Color=C(162,105,246),Icon='Lab'},
 Cosmetics={Title='YARD STYLES',Subtitle='Make your home your own',Color=C(248,79,170),Icon='Yard'},
 Discoveries={Title='DISCOVERIES',Subtitle='Every find tells a story',Color=C(26,192,239),Icon='Inventory'},
 LuckyOdds={Title='LUCKY BLOCK',Subtitle='All chances shown before you buy',Color=C(255,169,38),Icon='Inventory'},
 LuckyPad={Title='LUCKY PAD',Subtitle='Place a block, wait, then open it',Color=C(255,169,38),Icon='Inventory'},
 OfflineEarnings={Title='WELCOME BACK',Subtitle='Your pack kept working',Color=C(125,219,48),Icon='Dogs'},
 Shelter={Title='DOG SHELTER',Subtitle='Find your extra dogs a new home',Color=C(255,169,38),Icon='Dogs'},
 TicketShop={Title='DOG TOKENS',Subtitle='A free token every 5 hours · Lucky Spin packs',Color=C(171,105,247),Icon='Ticket'},
 Settings={Title='SETTINGS',Subtitle='Play your way',Color=C(92,142,250),Icon='Settings'},
}
-- Window shell metrics (Kit.Window): desktop 12 px padding and a 74 px header over the legacy
-- 931 x 610 body at (16, 100); phones are a full-screen sheet with an 8 px (portrait) / 6 px
-- (landscape) padding and a 58 / 50 px header.
function U.ShellMetrics(compact,landscape)
 if not compact then return {Pad=12,Header=74,ContentX=16,ContentY=100,Bottom=16}end
 local pad=landscape and 6 or 8;local header=landscape and 50 or 58
 return {Pad=pad,Header=header,ContentX=pad,ContentY=pad+header+pad,Bottom=pad}
end
-- The Kit window header of a legacy page (a child of the page, drawn over the card's top band):
-- accent gradient, radius 14, 2 px outline, icon, white title + subtitle, the red X (WindowClose).
function U.WindowChrome(page,key,width,close)
 local old=page:FindFirstChild('WindowChrome');if old then old:Destroy()end
 local spec=U.WindowSpecs[key]or{Title=key:gsub('(%l)(%u)','%1 %2'):upper(),Subtitle='',Color=U.Colors.blue,Icon='Dogs'}
 local chrome=U.Frame(page,'WindowChrome',-4,-88,width+8,74,WHITE);chrome.ZIndex=10;chrome.Size=UDim2.new(1,8,0,74)
 U.Round(chrome,KitTheme.Radius.Card);U.Stroke(chrome,U.Colors.edge,2)
 U.New('UIGradient',{Color=ColorSequence.new(spec.Color:Lerp(WHITE,.18),spec.Color),Rotation=90},chrome)
 local icon=U.Icon(chrome,spec.Icon,8,6,62)
 local title=U.Text(chrome,spec.Title,84,0,width-160,38,KitTheme.TextSize.Title,WHITE,true);title.Name='Title';title.TextStrokeColor3=NAVY;title.TextStrokeTransparency=0;title.ZIndex=14;title.TextWrapped=false;title.TextScaled=true
 local limit=U.New('UITextSizeConstraint',{MinTextSize=14,MaxTextSize=KitTheme.TextSize.Title},title)
 local subtitle=U.Text(chrome,spec.Subtitle,85,0,width-160,22,KitTheme.TextSize.Subtitle,WHITE);subtitle.Name='Subtitle';subtitle.TextStrokeColor3=NAVY;subtitle.TextStrokeTransparency=.45;subtitle.ZIndex=14;subtitle.TextWrapped=false;subtitle.TextTruncate=Enum.TextTruncate.AtEnd
 local x=U.Button(chrome,'WindowClose','X',0,0,48,48,close,U.Colors.red);x.ZIndex=15;x.AnchorPoint=Vector2.new(1,.5);x:SetAttribute('KitSound','')
 local caption=x:FindFirstChild('Caption');if caption then caption:SetAttribute('NoTranslate',true)end
 local function layoutChrome()
  local compact=gui:GetAttribute('CompactMenus')==true;local landscape=compact and gui:GetAttribute('LandscapeMenus')==true
  local m=U.ShellMetrics(compact,landscape);local headerH=m.Header
  chrome.Position=UDim2.fromOffset(m.Pad-m.ContentX,m.Pad-m.ContentY);chrome.Size=UDim2.new(1,2*(m.ContentX-m.Pad),0,headerH)
  local iconSize=headerH-(compact and 10 or 12)
  icon.Position=UDim2.fromOffset(8,math.floor((headerH-iconSize)/2));icon.Size=UDim2.fromOffset(iconSize,iconSize)
  local closeSize=compact and math.min(44,headerH-8)or 48 -- >= 42 px touch target
  x.Size=UDim2.fromOffset(closeSize,closeSize);x.Position=UDim2.new(1,-math.floor((headerH-closeSize)/2),.5,0)
  local textX=iconSize+16;local textW=-(textX+closeSize+18)
  local showSubtitle=not landscape and subtitle.Text~=''
  local titleH=compact and 30 or 38;local subtitleH=compact and 18 or 22
  local top=math.floor((headerH-(titleH+(showSubtitle and subtitleH or 0)))/2)
  title.Position=UDim2.fromOffset(textX,top);title.Size=UDim2.new(1,textW,0,titleH);limit.MaxTextSize=KitTheme.Size('Title',compact)
  subtitle.Visible=showSubtitle;subtitle.Position=UDim2.fromOffset(textX+1,top+titleH-2);subtitle.Size=UDim2.new(1,textW,0,subtitleH);subtitle.TextSize=KitTheme.Size('Subtitle',compact)
 end
 local changed=page:GetPropertyChangedSignal('AbsoluteSize'):Connect(layoutChrome);local compactChanged=gui:GetAttributeChangedSignal('CompactMenus'):Connect(layoutChrome);local landscapeChanged=gui:GetAttributeChangedSignal('LandscapeMenus'):Connect(layoutChrome);chrome.Destroying:Connect(function()changed:Disconnect();compactChanged:Disconnect();landscapeChanged:Disconnect()end);layoutChrome()
 page:SetAttribute('StandaloneWindow',true)
 return chrome
end
-- Kit window motion for a legacy window root: the card springs from 0.9 (Back easing) while a
-- Surface cover fades off it (Kit.Window open, ~0.18 s; instant with reduced motion).
-- setScale(k) applies the open multiplier (the caller keeps its own responsive scale).
function U.OpenMotion(root,setScale,radius)
 local cover=U.New('Frame',{Name='KitFadeCover',BackgroundColor3=U.Surface,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),Visible=false,Active=false,ZIndex=60},root)
 local corner=U.Round(cover,radius or KitTheme.Radius.Window)
 local value=U.New('NumberValue',{Name='KitOpenMotion',Value=1},root)
 value.Changed:Connect(function(v)setScale(v)end)
 local token=0
 local function play()
  if not root.Visible then return end
  token+=1;local mine=token
  if Motion.Reduced()then value.Value=1;cover.Visible=false;return end
  value.Value=.9;cover.BackgroundTransparency=0;cover.Visible=true
  Motion.Tween(value,KitTheme.Motion.Open+.06,{Value=1},Enum.EasingStyle.Back)
  Motion.Tween(cover,KitTheme.Motion.Open,{BackgroundTransparency=1})
  task.delay(KitTheme.Motion.Open,function()if token==mine then cover.Visible=false end end)
 end
 root:GetPropertyChangedSignal('Visible'):Connect(play)
 return value,corner
end
-- The bag notification (InventoryController writes InventoryToast.Main.Message): the Kit toast look
-- (white card, radius 14, faint navy outline, info dot, Ink text) and its slide-in from above.
local function styleToast(screen)
 local toast=find(screen,'InventoryToast');local face=toast and find(toast,'Main')
 if not(face and face:IsA('GuiObject'))then return end
 for _,o in ipairs(toast:GetChildren())do if o.Name=='Shadow'and o:IsA('GuiObject')then o.Visible=false end end
 face.BackgroundColor3=WHITE;face.BackgroundTransparency=0;U.Round(face,14)
 local stroke=findClass(face,'UIStroke');if stroke then stroke.Enabled=true;stroke.Color=NAVY;stroke.Thickness=2;stroke.Transparency=.2 else U.Stroke(face,NAVY,2,.2)end
 local message=find(face,'Message')
 if message and message:IsA('TextLabel')then message.TextColor3=NAVY;message.TextStrokeTransparency=1;message.TextXAlignment=Enum.TextXAlignment.Left;message.Position=UDim2.new(0,46,.1,0);message.Size=UDim2.new(1,-58,.8,0)end
 local dot=find(face,'KitKind')
 if not dot then
  dot=make('Frame',{Name='KitKind',BackgroundColor3=KitTheme.Info,BorderSizePixel=0,AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,10,.5,0),Size=UDim2.fromScale(.62,.62),SizeConstraint=Enum.SizeConstraint.RelativeYY,ZIndex=face.ZIndex+1},face)
  make('UICorner',{CornerRadius=UDim.new(.5,0)},dot);make('UISizeConstraint',{MaxSize=Vector2.new(28,28)},dot)
  local glyph=label(dot,'Glyph','i',face.ZIndex+2,{Size=UDim2.fromScale(1,1)});glyph:SetAttribute('NoTranslate',true);textLimit(glyph,17,8)
 end
 toast:GetPropertyChangedSignal('Visible'):Connect(function()
  if not toast.Visible or Motion.Reduced()then face.Position=UDim2.new();face.BackgroundTransparency=0;return end
  face.Position=UDim2.fromOffset(0,-18);face.BackgroundTransparency=.3
  Motion.Tween(face,KitTheme.Motion.Slide+.06,{Position=UDim2.new(),BackgroundTransparency=0},Enum.EasingStyle.Back)
 end)
end
function U.ApplyStandalone(screen)
 screen:SetAttribute('StandaloneWindows',true)
 local main=screen.MainWindow;local pages=main.Content.PageContainer
 -- MainWindow is the Kit window card (Surface, radius 18, 3 px outline); each page brings its Kit
 -- header (U.WindowChrome) and draws straight on the card, like a Kit window body.
 main.BackgroundTransparency=0;main.BackgroundColor3=U.Surface;main.ClipsDescendants=false
 local mainGradient=findClass(main,'UIGradient');if mainGradient then mainGradient.Enabled=false end
 local cardCorner=U.Round(main,KitTheme.Radius.Window);local cardStroke=U.Stroke(main,U.Colors.edge,KitTheme.StrokeWidth.Window)
 main.Header.Visible=false;main.Sidebar.Visible=false
 main.Size=UDim2.fromOffset(963,726);main.Position=UDim2.new(.5,0,.5,16)
 main.Content.Position=UDim2.fromOffset(16,100);main.Content.Size=UDim2.fromOffset(931,610);main.Content.ClipsDescendants=false
 local contentStroke=findClass(main.Content,'UIStroke');if contentStroke then contentStroke.Enabled=false end
 pages.ClipsDescendants=false
 for _,page in ipairs(pages:GetChildren())do
  if page:IsA('Frame')and page.Name:match('Page$')then
   page.BackgroundTransparency=1;page.BorderSizePixel=0;page.ClipsDescendants=false
   local pageStroke=findClass(page,'UIStroke');if pageStroke then pageStroke.Enabled=false end
   U.WindowChrome(page,page.Name:gsub('Page$',''),931)
   -- Original in-page headings remain useful section labels and preserve controller paths.
   local heading=page:FindFirstChild('PageHeader')or page:FindFirstChild('InventoryHeader')or page:FindFirstChild('YardHeader')
   if heading then
    heading.BackgroundColor3=U.SurfaceAlt
    local headingStroke=findClass(heading,'UIStroke');if headingStroke then headingStroke.Transparency=.55 end
    for _,o in ipairs(heading:GetDescendants())do if o:IsA('TextLabel')then o.TextColor3=U.Colors.text;o.TextStrokeTransparency=1 end end
   end
  end
 end
 -- Kit backdrop: the same dim as kit windows, faded in when a legacy window opens.
 local backdrop=screen.Backdrop
 backdrop.BackgroundColor3=U.Backdrop;backdrop.BackgroundTransparency=KitTheme.BackdropTransparency
 backdrop:GetPropertyChangedSignal('Visible'):Connect(function()
  if not backdrop.Visible or Motion.Reduced()then backdrop.BackgroundTransparency=KitTheme.BackdropTransparency;return end
  backdrop.BackgroundTransparency=1;Motion.Tween(backdrop,KitTheme.Motion.Open,{BackgroundTransparency=KitTheme.BackdropTransparency})
 end)
 local baseScale=1
 local openMotion,coverCorner=U.OpenMotion(main,function(k)local s=findClass(main,'UIScale');if s then s.Scale=baseScale*k end end)
 styleToast(screen)
 local dig=screen.HUD:FindFirstChild('GlobalDigWidget');if dig then dig.Visible=false end
 -- NAVIGATE, TITLES, HIDE UI and SETTINGS (HUD.SimpleSettings.Open keeps its name).
 U.BuildCluster(screen)
 U.LayoutHUD(screen)
 local function font(o)
  if o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox')then o.FontFace=U.FontFace end
  if o:IsA('GuiButton')then task.defer(function()if o.Parent then U.EnhanceButton(o)end end)end
 end
 for _,o in ipairs(screen:GetDescendants())do font(o)end
 screen.DescendantAdded:Connect(font)
 local inventoryLayout={}
 for _,name in ipairs({'InventoryHeader','Tabs','Browser','Details'})do local o=pages.InventoryPage:FindFirstChild(name);if o then inventoryLayout[o]={Position=o.Position,Size=o.Size}end end
 local bagDetails=false;local inv=pages.InventoryPage
 local inventoryHeaderLayout={}
 for _,name in ipairs({'Title','Capacity'})do local o=inv.InventoryHeader:FindFirstChild(name);if o then inventoryHeaderLayout[o]={Position=o.Position,Size=o.Size,AnchorPoint=o.AnchorPoint,Visible=o.Visible}end end
 local bagBack=U.Button(inv,'MobileBagBack','BACK TO BAG',12,63,165,42,function()bagDetails=false;inv.Browser.Visible=true;inv.Details.Visible=false;inv.Tabs.Visible=true;inv.MobileBagBack.Visible=false end,U.Colors.blue)
 bagBack.Visible=false;bagBack.ZIndex=20
 local function showBagDetails()
  if not screen:GetAttribute('CompactMenus')then return end
  bagDetails=true;inv.Browser.Visible=false;inv.Details.Visible=true;inv.Tabs.Visible=false;bagBack.Visible=true
 end
 local bagGrid=inv.Browser.GridPanel.Main.ItemGrid
 local function bindBagCard(card)
  if card:IsA('Frame')and card.Name:match('^Entry_')then local b=card:FindFirstChild('Main');if b and b:IsA('GuiButton')then b.Activated:Connect(showBagDetails)end end
 end
 bagGrid.ChildAdded:Connect(bindBagCard);for _,card in ipairs(bagGrid:GetChildren())do bindBagCard(card)end
 inv:GetPropertyChangedSignal('Visible'):Connect(function()if inv.Visible and screen:GetAttribute('CompactMenus')then bagDetails=false;inv.Browser.Visible=true;inv.Details.Visible=false;inv.Tabs.Visible=true;bagBack.Visible=false end end)
 local function resize()
  local scale=findClass(main,'UIScale')
  local _,_,width,height=U.SafeArea(screen)
  local compact=width<700 or height<560
  local landscape=compact and width>height*1.25
  local m=U.ShellMetrics(compact,landscape)
  -- Desktop: the 963 x 726 card, scaled to fit. Phones: a full-screen sheet in the safe area that
  -- reflows in real pixels (Kit.Window); a fixed tall canvas made landscape text ~8 px.
  local designW=compact and math.max(280,math.floor(width))or 963
  local designH=compact and math.max(180,math.floor(height))or 726
  local factor=compact and 1 or math.max(.2,math.min(1,(width-28)/designW,(height-36)/designH))
  screen:SetAttribute('CompactMenus',compact);screen:SetAttribute('LandscapeMenus',landscape)
  baseScale=factor;scale.Scale=factor*openMotion.Value;main.Size=UDim2.fromOffset(designW,designH);main.Position=U.SafePosition(screen,designW,designH,factor,compact and 0 or 14)
  cardCorner.CornerRadius=UDim.new(0,compact and 0 or KitTheme.Radius.Window);coverCorner.CornerRadius=cardCorner.CornerRadius;cardStroke.Enabled=not compact
  main.Content.Position=UDim2.fromOffset(m.ContentX,m.ContentY)
  main.Content.Size=UDim2.fromOffset(designW-2*m.ContentX,designH-m.ContentY-m.Bottom)
  local inv=pages.InventoryPage
  for o,layout in pairs(inventoryHeaderLayout)do o.Position=layout.Position;o.Size=layout.Size;o.AnchorPoint=layout.AnchorPoint;o.Visible=layout.Visible end
  if compact then
   inv.InventoryHeader.Position=UDim2.fromOffset(12,10);inv.InventoryHeader.Size=landscape and UDim2.fromOffset(150,42)or UDim2.new(1,-24,0,44)
   if landscape then
    inv.InventoryHeader.Title.Visible=false;local cap=inv.InventoryHeader.Capacity;cap.AnchorPoint=Vector2.zero;cap.Position=UDim2.new();cap.Size=UDim2.fromScale(1,1)
   end
   inv.Tabs.Position=UDim2.fromOffset(landscape and 174 or 12,landscape and 10 or 62);inv.Tabs.Size=UDim2.new(1,landscape and -186 or -24,0,landscape and 42 or 46)
   local bodyY=landscape and 60 or 116;local bottom=landscape and 72 or 132
   inv.Browser.Position=UDim2.fromOffset(12,bodyY);inv.Browser.Size=UDim2.new(1,-24,1,-bottom);inv.Browser.Visible=not bagDetails
   local details=inv:FindFirstChild('Details')or inv:FindFirstChild('DetailPanel')or inv:FindFirstChild('SelectedItemPanel')
   if details then details.Position=UDim2.fromOffset(12,bodyY);details.Size=UDim2.new(1,-24,1,-bottom);details.Visible=bagDetails end
   bagBack.Position=UDim2.fromOffset(landscape and 174 or 12,landscape and 10 or 63)
   inv.Tabs.Visible=not bagDetails;bagBack.Visible=bagDetails
  else for o,layout in pairs(inventoryLayout)do o.Position=layout.Position;o.Size=layout.Size;o.Visible=true end;bagBack.Visible=false end
 end
 screen:GetPropertyChangedSignal('AbsoluteSize'):Connect(resize)
 local inset=GuiService:GetPropertyChangedSignal('TopbarInset'):Connect(resize);screen.Destroying:Connect(function()inset:Disconnect()end);resize()
end
function U.BindStandalone(screen,N)
 GameIcons.Preload(U.Assets)
 local pages=screen.MainWindow.Content.PageContainer
 local yard=pages.YardPage
 yard.YardHeader.YardHeaderTitle.Size=UDim2.fromOffset(580,50)
 local offline=U.Button(yard.YardHeader,'OfflineEarnings','OFFLINE EARNINGS',631,7,255,36,function()N.OpenScreen('OfflineEarnings')end,U.Colors.gold)
 for _,page in ipairs(pages:GetChildren())do
  local chrome=page:FindFirstChild('WindowChrome');local close=chrome and chrome:FindFirstChild('WindowClose')
  if close then close.Active=true;close.Selectable=true;close.Activated:Connect(N.Close)end
 end
 screen.HUD.SimpleSettings.Open.Activated:Connect(function()N.OpenScreen('Settings')end)
end

return U
