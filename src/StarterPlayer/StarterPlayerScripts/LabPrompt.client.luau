-- The genetics terminal prompt (created by Economy.LabService) shows only where the lab really works
-- (LabAccess: inside the lab, near the terminal, in line of sight), and speaks the player's language.
local player=game.Players.LocalPlayer;local Access=require(game.ReplicatedStorage.LabAccess)
local Localization=game:GetService('LocalizationService')
local function russian()
 local ok,locale=pcall(function()
  if game:GetService('RunService'):IsStudio()then return Localization.RobloxLocaleId end
  return player.LocaleId or Localization.RobloxLocaleId
 end)
 return ok and type(locale)=='string'and string.lower(string.sub(locale,1,2))=='ru'
end
local elapsed=0
game:GetService('RunService').Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<.15 then return end;elapsed=0
 local lab=Access.Model();local anchor=lab and lab:FindFirstChild('InteractionAnchor');local prompt=anchor and anchor:FindFirstChild('GeneticsPrompt')
 if prompt then
  prompt.Enabled=Access.CanUse(player)
  if russian()and prompt:GetAttribute('Localized')~=true then
   prompt.ActionText='ИСПОЛЬЗОВАТЬ ЛАБОРАТОРИЮ';prompt.ObjectText='ГЕНЕТИЧЕСКИЙ ТЕРМИНАЛ';prompt:SetAttribute('Localized',true)
  end
 end
end)
