-- Small shared HUD pieces for Active Mining: a toast line and "+coins" popups next to the
-- money counter (HUD.MoneyWidget), styled like the HUD counter. The toast has its own ScreenGui
-- above the pickaxe market (DisplayOrder 70) so purchase results stay visible.
local TweenService=game:GetService('TweenService')
local Hud={}

function Hud.new(ctx)
 local self:any={}
 local U=ctx.U
 local font=U.FontFace or Font.fromEnum(Enum.Font.FredokaOne)

 local toast=Instance.new('TextLabel');toast.Name='MiningToast';toast.AnchorPoint=Vector2.new(.5,0)
 toast.Position=UDim2.new(.5,0,.16,0);toast.Size=UDim2.fromOffset(560,46);toast.BackgroundColor3=Color3.fromRGB(255,251,242)
 toast.BorderSizePixel=0;toast.FontFace=font;toast.TextScaled=true;toast.TextColor3=U.Colors.text;toast.Visible=false;toast.ZIndex=150
 local layer=Instance.new('ScreenGui');layer.Name='MiningToast';layer.DisplayOrder=80;layer.ResetOnSpawn=false;layer.IgnoreGuiInset=true
 layer.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;layer:SetAttribute('NoTranslate',true);layer:SetAttribute('KeepFont',true)
 layer.Parent=ctx.PlayerGui
 toast.Parent=layer
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,12);corner.Parent=toast
 local stroke=Instance.new('UIStroke');stroke.Color=U.Colors.edge;stroke.Thickness=3;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=toast
 local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,14);pad.PaddingRight=UDim.new(0,14);pad.PaddingTop=UDim.new(0,6);pad.PaddingBottom=UDim.new(0,6);pad.Parent=toast
 local limit=Instance.new('UITextSizeConstraint');limit.MaxTextSize=24;limit.Parent=toast
 local token=0
 function self.Toast(text,color,seconds)
  token+=1;local id=token
  local width=math.clamp(layer.AbsoluteSize.X-32,240,620)
  toast.Size=UDim2.fromOffset(width,46)
  -- While mining, the ore and its circles fill the screen centre (on short phone screens from
  -- about y=130 down). Toasts then go above the ore panel (it starts at y=46 on touch) on short
  -- screens, and right under it on tall ones.
  local mining=ctx.Mine and ctx.Mine.Active
  toast.AnchorPoint=Vector2.new(.5,0)
  if mining and layer.AbsoluteSize.Y<560 then
   width=math.min(width,math.max(220,math.floor(layer.AbsoluteSize.X*.5)))
   toast.Size=UDim2.fromOffset(width,36);toast.Position=UDim2.new(.5,0,0,6)
  elseif mining then
   toast.Position=UDim2.new(.5,0,0,162)
  else
   toast.Position=UDim2.new(.5,0,.16,0)
  end
  toast.Text=text;toast.TextColor3=color or U.Colors.text;toast.Visible=true
  stroke.Color=color or U.Colors.edge
  task.delay(seconds or 2.6,function()if token==id then toast.Visible=false end end)
 end

 -- "+X" next to the money counter; gains within 0.25 s merge.
 local pending,flushAt=0,0
 local function moneyWidget()
  local hud=ctx.Main:FindFirstChild('HUD');return hud and hud:FindFirstChild('MoneyWidget')
 end
 local function flush()
  local amount=pending;pending=0
  if amount<=0 then return end
  local widget=moneyWidget()
  if not widget or not widget:IsA('GuiObject')or not widget.Visible then return end
  local l=Instance.new('TextLabel');l.Name='MiningGain';l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(0,.5)
  l.Position=UDim2.new(1,8,.5,0);l.Size=UDim2.fromOffset(170,30);l.FontFace=font;l.TextScaled=true
  l.TextXAlignment=Enum.TextXAlignment.Left;l.Text='+'..ctx.Text.Short(amount);l.TextColor3=Color3.fromRGB(132,255,57)
  l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true)
  local s=Instance.new('UIStroke');s.Color=U.Colors.edge;s.Thickness=2;s.Parent=l
  l.ZIndex=(widget.ZIndex or 1)+5;l.Parent=widget
  TweenService:Create(l,TweenInfo.new(.7,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(1,8,.5,-30),TextTransparency=1}):Play()
  TweenService:Create(s,TweenInfo.new(.7),{Transparency=1}):Play()
  task.delay(.75,function()l:Destroy()end)
 end
 function self.Coins(amount)
  amount=math.floor(tonumber(amount)or 0);if amount<=0 then return end
  pending+=amount
  if os.clock()>=flushAt then flushAt=os.clock()+.25;task.delay(.25,flush)end
 end

 return self
end

return Hud
