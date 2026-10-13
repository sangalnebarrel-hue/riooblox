
local Players = game:GetService("Players")
local LS = game:GetService("LocalizationService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

print("Player language:", player.LocaleId)
print("Emulator language:", LS.RobloxLocaleId)

local translator = LS:GetTranslatorForLocaleAsync("ru-ru")

task.wait(3)

for _, obj in ipairs(gui:GetDescendants()) do
	if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
		and obj.Text == "DOGS" then

		local translated = translator:Translate(obj, "DOGS")

		if translated == "DOGS" then
			translated = translator:Translate(game, "DOGS")
		end

		obj.Text = translated
		print("BUTTON CHANGED:", translated)
	end
end
