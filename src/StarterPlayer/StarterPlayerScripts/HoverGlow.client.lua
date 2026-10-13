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
local function strokeOf(button)
 local face=button:FindFirstChild('Face')
 return(face and face:FindFirstChildOfClass('UIStroke'))or button:FindFirstChildOfClass('UIStroke'),face
end
local function attachButton(b)
 if not b:IsA('GuiButton')or optedOut(b)then return end
 if b:GetAttribute('HoverGlowAttached')then return end
 b:SetAttribute('HoverGlowAttached',true)
 local glow,grad,scale=nil,nil,nil
 local saved=nil
 b.MouseEnter:Connect(function()
  if b.AbsoluteSize.X<14 or b.AbsoluteSize.Y<14 then return end
  local stroke,face=strokeOf(b)
  local transparent=b.BackgroundTransparency>.95 and not face and not b:IsA('ImageButton')
  if stroke then
   glow=stroke
   saved={Color=stroke.Color,Thickness=stroke.Thickness,Transparency=stroke.Transparency}
  elseif not transparent then
   glow=b:FindFirstChild('HoverGlowStroke')
   if not glow then
    glow=Instance.new('UIStroke');glow.Name='HoverGlowStroke';glow.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    glow.Thickness=3;glow.Transparency=1;glow.Parent=b
   end
   saved={Color=glow.Color,Thickness=glow.Thickness,Transparency=1}
  end
  if glow then
   grad=glow:FindFirstChild('HoverRainbow')or Instance.new('UIGradient')
   grad.Name='HoverRainbow';grad.Color=rainbow(math.random());grad.Parent=glow
   glow.Color=Color3.new(1,1,1)
   TweenService:Create(glow,TweenInfo.new(.15),{Thickness=math.max(saved.Thickness,3)+1,Transparency=0}):Play()
   live[grad]=true
  end
  -- A small lift for buttons without their own press animation.
  if not reduced()and not b:FindFirstChildOfClass('UIScale')and not(face and face:FindFirstChildOfClass('UIScale'))then
   scale=Instance.new('UIScale');scale.Name='HoverScale';scale.Parent=b
  end
  if scale then TweenService:Create(scale,TweenInfo.new(.14,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.05}):Play()end
 end)
 b.MouseLeave:Connect(function()
  if grad then live[grad]=nil;grad:Destroy();grad=nil end
  if glow and saved and glow.Parent then
   glow.Color=saved.Color
   TweenService:Create(glow,TweenInfo.new(.15),{Thickness=saved.Thickness,Transparency=saved.Transparency}):Play()
  end
  glow,saved=nil,nil
  if scale then
   local s=scale;scale=nil
   local t=TweenService:Create(s,TweenInfo.new(.12),{Scale=1});t:Play()
   t.Completed:Once(function()if s.Parent and s~=scale then s:Destroy()end end)
  end
 end)
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
 local model=p and p:FindFirstAncestorOfClass('Model')
 -- Small models light up whole; big ones (a yard) only the part.
 if model and model~=workspace and #model:GetDescendants()<160 then return model end
 return p
end
local function watchDetector(d)
 if not d:IsA('ClickDetector')then return end
 d.MouseHoverEnter:Connect(function(who)
  if who~=player then return end
  hovered=d;highlight.Adornee=target(d);highlight.Enabled=true
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
 if highlight.Enabled then
  highlight.OutlineColor=Color3.fromHSV((t*.35)%1,.65,1)
  highlight.FillColor=Color3.fromHSV((t*.35+.5)%1,.4,1)
 end
end)
-- Touch screens have no hover: nothing to do there, but keep the highlight off.
if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then highlight.Enabled=false end
