-- DOGROTS typography: ONE typeface for the whole place - Fredoka One. Every TextLabel, TextButton
-- and TextBox in the world (district signs, dog labels, billboards) and in the player's GUI uses it,
-- including labels created later and labels whose scripts set another font: the face is put back
-- the moment anything changes it. (The old pixel face, Enum.Font.FredokaOne, is no longer used.)
local Players=game:GetService('Players')
local ROUND=Font.fromEnum(Enum.Font.FredokaOne)
local player=Players.LocalPlayer

local attached=setmetatable({},{__mode='k'}) -- labels already wired (reparenting fires DescendantAdded again)
local function attach(o)
 if attached[o]then return end
 if not(o:IsA('TextLabel')or o:IsA('TextButton')or o:IsA('TextBox'))then return end
 attached[o]=true
 local writing=false
 local function enforce()
  if writing then return end
  local face=o.FontFace
  if face.Family~=ROUND.Family then
   writing=true
   -- Keep the requested weight / style where Fredoka One can show it (it only has Regular).
   o.FontFace=ROUND
   writing=false
  end
 end
 enforce()
 o:GetPropertyChangedSignal('FontFace'):Connect(enforce)
end
for _,root in ipairs({workspace,player:WaitForChild('PlayerGui')})do
 for _,o in ipairs(root:GetDescendants())do attach(o)end
 root.DescendantAdded:Connect(attach)
end
