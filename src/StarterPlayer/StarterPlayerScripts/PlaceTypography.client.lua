-- DOGROTS typography: a fun pixel face (Press Start 2P, Enum.Font.Arcade) for every title, button,
-- label, popup and world sign it fits in, and the round FredokaOne for long text (descriptions,
-- hints, paragraphs) so everything stays readable. Applies to district signs, dog labels and
-- player menus, including new clones; re-checks when a label's text or size changes.
--   KeepFont attribute: the label keeps its own font (numbers, Secret arrival whispers...).
--   PixelFont = true / false attribute on a label or any ancestor: force pixel / round.
local Players=game:GetService('Players')
local TextService=game:GetService('TextService')
local PIXEL=Font.fromEnum(Enum.Font.Arcade)
local ROUND=Font.fromEnum(Enum.Font.FredokaOne)
local LONG=26 -- characters: longer texts stay round
local FLOOR=8 -- px: smallest readable pixel face for a scaled label with no UITextSizeConstraint
local player=Players.LocalPlayer

local function forced(o)
 local node=o
 while node and node~=game do
  local v=node:GetAttribute('PixelFont')
  if v~=nil then return v end
  node=node.Parent
 end
 return nil
end
local function plain(text)
 -- RichText tags do not count towards the length.
 return (string.gsub(text or'','<[^>]+>',''))
end
local function unscaled(o)
 -- AbsoluteSize includes every UIScale up to the LayerCollector (window scale, press squash, open motion);
 -- text sizes do not, so fit is judged in unscaled px and a UIScale tween alone never changes the result.
 local factor=1
 local node=o
 while node and node~=game and not node:IsA('LayerCollector')do
  local s=node:FindFirstChildWhichIsA('UIScale')
  if s then factor*=s.Scale end
  node=node.Parent
 end
 return o.AbsoluteSize/(factor>.01 and factor or 1)
end
local function pixelFits(o)
 if not o.TextScaled then return o.TextFits end
 -- A scaled label never shrinks below its UITextSizeConstraint minimum; Arcade is ~1 em per glyph.
 local limit=o:FindFirstChildWhichIsA('UITextSizeConstraint')
 local minSize=limit and limit.MinTextSize or FLOOR
 local box=unscaled(o)
 local need=TextService:GetTextSize(plain(o.Text),minSize,Enum.Font.Arcade,Vector2.new(o.TextWrapped and box.X or 1e5,1e5))
 return need.X<=box.X+1 and need.Y<=box.Y+1
end
local attached=setmetatable({},{__mode='k'}) -- labels already wired (reparenting fires DescendantAdded again)
local function attach(o)
 if attached[o]then return end
 if not(o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox'))then return end
 if o:GetAttribute('KeepFont')then return end
 attached[o]=true
 local writing=false
 local failedAt=nil -- unscaled AbsoluteSize at which the pixel face did not fit (retry only when it grows)
 local checking=false
 local function set(face)if o.FontFace~=face then writing=true;o.FontFace=face;writing=false end end
 local function check()
  -- A label whose text does not fit in the pixel face (scaled ones at their minimum size) goes back to the round one.
  if checking then return end
  checking=true
  task.defer(function()
   checking=false
   if o:GetAttribute('KeepFont')or forced(o)~=nil then return end -- choose() owns forced faces
   if o.Parent and o.FontFace==PIXEL and o.AbsoluteSize.X>=1 and not pixelFits(o)then
    failedAt=unscaled(o);set(ROUND)
   end
  end)
 end
 local function choose()
  if writing or o:GetAttribute('KeepFont')then return end
  local force=forced(o)
  if force~=nil then set(force and PIXEL or ROUND);return end
  if o:IsA('TextBox')then set(ROUND);return end
  local text=plain(o.Text)
  local long=utf8.len(text)or #text
  if long>LONG or string.find(text,'\n')or failedAt then set(ROUND);return end
  set(PIXEL);check()
 end
 choose()
 o:GetPropertyChangedSignal('FontFace'):Connect(choose)
 o:GetPropertyChangedSignal('Text'):Connect(function()failedAt=nil;choose()end)
 o:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
  if failedAt then
   local size=unscaled(o)
   if size.X>failedAt.X+12 or size.Y>failedAt.Y+6 then failedAt=nil;choose()end
  elseif o.FontFace==PIXEL then check()end -- laid out smaller (resize, phone layout): fit again
 end)
end
for _,root in ipairs({workspace,player:WaitForChild('PlayerGui')})do
 for _,o in ipairs(root:GetDescendants())do attach(o)end
 root.DescendantAdded:Connect(attach)
end
