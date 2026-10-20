-- "Everything glows under the mouse": every button in the player's menus gets a soft lift and a
-- turning rainbow outline while hovered, and every clickable world object (ClickDetector) gets a
-- rainbow Highlight. Kit buttons keep their own lift (KitPress) and only get the outline.
-- Opt out with the NoHover attribute on a button or any ancestor.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local UserInputService=game:GetService('UserInputService')
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')

local function rainbow(offset)
 local k={}
 for i=0,6 do k[#k+1]=ColorSequenceKeypoint.new(i/6,Color3.fromHSV((i/6+offset)%1,.7,1))end
 return ColorSequence.new(k)
end
local function reduced()return player:GetAttribute('ReducedMotion')==true end
-- Touch taps also fire MouseEnter (and MouseLeave only on the next tap elsewhere): button hover is
-- mouse-only, the same test as Kit Sound.MouseInput.
local function mouseInput()
 local t=UserInputService:GetLastInputType()
 return t==Enum.UserInputType.MouseMovement or t==Enum.UserInputType.MouseButton1 or t==Enum.UserInputType.MouseButton2 or t==Enum.UserInputType.MouseWheel
end
local function optedOut(o)
 local node=o
 while node and node~=playerGui do
  if node:GetAttribute('NoHover')then return true end
  node=node.Parent
 end
 return false
end

-- GUI BUTTONS ------------------------------------------------------------------------------------
local live={} -- gradients turning while hovered
local hovering={} -- hovered button -> its leave function (also run when it is hidden mid-hover)
local attached=setmetatable({},{__mode='k'}) -- once per button; unlike an attribute, Clone() does not copy it
-- The object's own outline: any UIStroke but our ring.
local function outlineOf(o)
 for _,c in ipairs(o:GetChildren())do if c:IsA('UIStroke')and c.Name~='HoverGlowStroke'then return c end end
 return nil
end
local function strokeOf(button)
 local face=button:FindFirstChild('Face')
 return(face and outlineOf(face))or outlineOf(button),face
end
-- The rainbow ring is a UIStroke of our own: the button's outline belongs to its screen (selected,
-- tab and disabled looks are drawn on it) and is never written here. The ring sits on a transparent
-- frame the size of the outlined object, so it covers that outline while hovered. An object that lays
-- out, auto-sizes or clips its children (the frame would become a cell, grow the button or be cut off)
-- gets the ring straight on it when it has no outline of its own, else none.
-- A UIPadding shrinks the box the frame is placed in: the frame is pushed back out over it on each hover.
local function fit(f,host)
 local pad=host:FindFirstChildWhichIsA('UIPadding')
 if not pad then f.Position=UDim2.new();f.Size=UDim2.fromScale(1,1);return end
 local w,h=host.AbsoluteSize.X,host.AbsoluteSize.Y
 local l,r=pad.PaddingLeft.Scale*w+pad.PaddingLeft.Offset,pad.PaddingRight.Scale*w+pad.PaddingRight.Offset
 local t,b=pad.PaddingTop.Scale*h+pad.PaddingTop.Offset,pad.PaddingBottom.Scale*h+pad.PaddingBottom.Offset
 f.Position=UDim2.fromOffset(-l,-t);f.Size=UDim2.new(1,l+r,1,t+b)
end
local function ringOf(host)
 local f=host:FindFirstChild('HoverGlowFrame')
 local s=(f or host):FindFirstChild('HoverGlowStroke')
 if not s then
  if not f then
   if host:FindFirstChildWhichIsA('UIGridStyleLayout')or host.AutomaticSize~=Enum.AutomaticSize.None or host.ClipsDescendants then
    if outlineOf(host)then return nil end
    f=host
   else
    f=Instance.new('Frame');f.Name='HoverGlowFrame';f.Active=false;f.BackgroundTransparency=1;f.BorderSizePixel=0
    f.ZIndex=host.ZIndex
    local c=host:FindFirstChildOfClass('UICorner')
    if c then local u=Instance.new('UICorner');u.CornerRadius=c.CornerRadius;u.Parent=f end
    f.Parent=host
   end
  end
  s=Instance.new('UIStroke');s.Name='HoverGlowStroke';s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
  s.Color=Color3.new(1,1,1);s.Thickness=3;s.Transparency=1;s.LineJoinMode=Enum.LineJoinMode.Round;s.Parent=f
 end
 if s.Parent~=host then fit(s.Parent,host)end
 return s
end
-- On screen: under PlayerGui with every GuiObject up to its ScreenGui visible and that ScreenGui enabled.
local function shown(o)
 while o and o~=playerGui do
  if(o:IsA('GuiObject')and not o.Visible)or(o:IsA('LayerCollector')and not o.Enabled)then return false end
  o=o.Parent
 end
 return o==playerGui
end
local function attachButton(b)
 if not b:IsA('GuiButton')or optedOut(b)then return end
 if attached[b]then return end
 attached[b]=true
 local ring,grad,scale=nil,nil,nil
 local function leave()
  hovering[b]=nil
  if grad then live[grad]=nil;grad=nil end -- stays on the ring (rainbow while it fades), reused next time
  if ring and ring.Parent then TweenService:Create(ring,TweenInfo.new(.15),{Transparency=1}):Play()end
  ring=nil
  if scale then
   local s=scale;scale=nil
   local t=TweenService:Create(s,TweenInfo.new(.12),{Scale=1});t:Play()
   t.Completed:Once(function()if s.Parent and s~=scale then s:Destroy()end end)
  end
 end
 b.MouseEnter:Connect(function()
  if not mouseInput()then return end
  if b.AbsoluteSize.X<14 or b.AbsoluteSize.Y<14 then return end
  local stroke,face=strokeOf(b)
  -- A text stroke on the button itself outlines its caption, not the button.
  if stroke and stroke.Parent==b and b:IsA('TextButton')and stroke.ApplyStrokeMode==Enum.ApplyStrokeMode.Contextual then stroke=nil end
  local transparent=b.BackgroundTransparency>.95 and not face and not b:IsA('ImageButton')
  if stroke or not transparent then ring=ringOf(stroke and stroke.Parent or face or b)end
  if ring then
   grad=ring:FindFirstChild('HoverRainbow')or Instance.new('UIGradient')
   grad.Name='HoverRainbow';grad.Color=rainbow(math.random());grad.Parent=ring
   ring.Thickness=math.max(stroke and stroke.Thickness or 0,3)+1
   TweenService:Create(ring,TweenInfo.new(.15),{Transparency=0}):Play()
   live[grad]=true
  end
  hovering[b]=leave
  -- A small lift for buttons without their own press animation.
  if not reduced()and not b:FindFirstChildOfClass('UIScale')and not(face and face:FindFirstChildOfClass('UIScale'))then
   scale=Instance.new('UIScale');scale.Name='HoverScale';scale.Parent=b
  end
  if scale then TweenService:Create(scale,TweenInfo.new(.14,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.05}):Play()end
 end)
 b.MouseLeave:Connect(leave)
end
for _,d in ipairs(playerGui:GetDescendants())do attachButton(d)end
playerGui.DescendantAdded:Connect(function(d)if d:IsA('GuiButton')then task.defer(attachButton,d)end end)

-- WORLD OBJECTS (ClickDetector) -------------------------------------------------------------------
local highlight=Instance.new('Highlight')
highlight.Name='DOGROTS_HoverHighlight';highlight.FillTransparency=.82;highlight.OutlineTransparency=0
highlight.DepthMode=Enum.HighlightDepthMode.Occluded;highlight.Enabled=false
-- Under the camera: local to this client, always inside the rendered world.
highlight.Parent=workspace.CurrentCamera or workspace
workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()if workspace.CurrentCamera then highlight.Parent=workspace.CurrentCamera end end)
local hovered=nil
local function target(detector)
 local p=detector.Parent
 -- The clicked part itself (a sign board, a rack bar), not the model around it (the whole dig site);
 -- an invisible hitbox (the ore core) gets none. Only a detector on a small Model lights it whole.
 if p and p:IsA('BasePart')then return p.Transparency<.99 and p or nil end
 if p and p:IsA('Model')and #p:GetDescendants()<160 then return p end
 return nil
end
local watched=setmetatable({},{__mode='k'}) -- once per detector (DescendantAdded fires again on a move)
local function watchDetector(d)
 if not d:IsA('ClickDetector')or watched[d]then return end
 watched[d]=true
 d.MouseHoverEnter:Connect(function(who)
  -- Touch screens have no hover: a tap would leave the highlight on until the next tap elsewhere.
  if who~=player or UserInputService:GetLastInputType()==Enum.UserInputType.Touch then return end
  local t=target(d)
  hovered=d;highlight.Adornee=t;highlight.Enabled=t~=nil
 end)
 d.MouseHoverLeave:Connect(function(who)
  if who~=player or hovered~=d then return end
  hovered=nil;highlight.Enabled=false;highlight.Adornee=nil
 end)
end
for _,d in ipairs(workspace:GetDescendants())do watchDetector(d)end
workspace.DescendantAdded:Connect(watchDetector)

RunService.RenderStepped:Connect(function()
 local t=os.clock()
 for g in pairs(live)do
  if g.Parent then g.Rotation=(t*160)%360 else live[g]=nil end
 end
 -- MouseLeave never comes for a button hidden under the cursor (its window closed, its page switched).
 for b,leave in pairs(hovering)do if not shown(b)then leave()end end
 if highlight.Enabled then
  highlight.OutlineColor=Color3.fromHSV((t*.35)%1,.65,1)
  highlight.FillColor=Color3.fromHSV((t*.35+.5)%1,.4,1)
 end
end)
