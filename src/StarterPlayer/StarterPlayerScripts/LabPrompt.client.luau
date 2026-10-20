-- The lab prompt (created by Economy.LabService: START MUTATION at the nuclear tower's console, or the old
-- genetics terminal when LabConfig.SimpleMode is off) shows only where the lab really works (LabAccess:
-- inside the lab, near the console, in line of sight), and speaks the player's language.
-- It also starts the machine's client side (Modules.LabPresentation.StartWorld: idle motion near the
-- machine and the short public effect when another player mutates a dog).
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
   if prompt:GetAttribute('Simple')then prompt.ActionText='ЗАПУСК МУТАЦИИ';prompt.ObjectText='ЯДЕРНЫЙ ПУЛЬТ'
   else prompt.ActionText='ИСПОЛЬЗОВАТЬ ЛАБОРАТОРИЮ';prompt.ObjectText='ГЕНЕТИЧЕСКИЙ ТЕРМИНАЛ'end
   prompt:SetAttribute('Localized',true)
  end
 end
end)
task.spawn(function()
 local gui=player:WaitForChild('PlayerGui'):WaitForChild('ScreenGui',60)
 local modules=gui and gui:WaitForChild('Modules',60)
 local module=modules and modules:WaitForChild('LabPresentation',60)
 if not module then return end
 local ok,presentation=pcall(require,module)
 if ok and type(presentation)=='table'and presentation.StartWorld then
  local started,err=pcall(presentation.StartWorld)
  if not started then warn('Mutation machine FX: '..tostring(err))end
 end
end)
