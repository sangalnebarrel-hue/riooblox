-- DOGROTS typography: a fun pixel face (Press Start 2P, Enum.Font.Arcade) for every title, button,
-- label, popup and world sign it fits in, and the round FredokaOne for long text (descriptions,
-- hints, paragraphs) so everything stays readable. Applies to district signs, dog labels and
-- player menus, including new clones; re-checks when a label's text or size changes.
--   KeepFont attribute: the label keeps its own font (numbers, Secret arrival whispers...).
--   PixelFont = true / false attribute on a label or any ancestor: force pixel / round.
local Players=game:GetService('Players')
local PIXEL=Font.fromEnum(Enum.Font.Arcade)
local ROUND=Font.fromEnum(Enum.Font.FredokaOne)
local LONG=26 -- characters: longer texts stay round
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
local function attach(o)
 if not(o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox'))then return end
 if o:GetAttribute('KeepFont')then return end
 local writing=false
 local failedAt=nil -- AbsoluteSize at which the pixel face did not fit (retry only when it grows)
 local function set(face)if o.FontFace~=face then writing=true;o.FontFace=face;writing=false end end
 local function choose()
  if writing or o:GetAttribute('KeepFont')then return end
  local force=forced(o)
  if force~=nil then set(force and PIXEL or ROUND);return end
  if o:IsA('TextBox')then set(ROUND);return end
  local text=plain(o.Text)
  local long=utf8.len(text)or #text
  if long>LONG or string.find(text,'\n')or failedAt then set(ROUND);return end
  set(PIXEL)
  -- A fixed-size label whose text does not fit in the pixel face goes back to the round one.
  if not o.TextScaled then
   task.defer(function()
    if o.Parent and o.FontFace==PIXEL and not o.TextScaled and not o.TextFits then
     failedAt=o.AbsoluteSize;set(ROUND)
    end
   end)
  end
 end
 choose()
 o:GetPropertyChangedSignal('FontFace'):Connect(choose)
 o:GetPropertyChangedSignal('Text'):Connect(function()failedAt=nil;choose()end)
 o:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
  if failedAt and(o.AbsoluteSize.X>failedAt.X+12 or o.AbsoluteSize.Y>failedAt.Y+6)then failedAt=nil;choose()end
 end)
end
for _,root in ipairs({workspace,player:WaitForChild('PlayerGui')})do
 for _,o in ipairs(root:GetDescendants())do attach(o)end
 root.DescendantAdded:Connect(attach)
end
