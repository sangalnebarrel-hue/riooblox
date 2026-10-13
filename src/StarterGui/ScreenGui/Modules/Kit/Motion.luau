-- Tween helpers. Every kit animation goes through Motion.Tween so reduced motion makes it
-- instant. Reduced motion is one switch for the whole game: Motion.Override (tests), else the
-- in-game Settings "Motion" toggle (player attribute ReducedMotion, which the world effects read
-- too; PawpadRuntime seeds it from the Roblox setting), else Roblox's ReducedMotionEnabled.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Motion = {}

-- true / false forces reduced motion on / off (tests, tools); nil follows the settings.
Motion.Override = nil :: boolean?

function Motion.Reduced(): boolean
	if Motion.Override ~= nil then
		return Motion.Override == true
	end
	local player = Players.LocalPlayer
	local chosen = player and player:GetAttribute("ReducedMotion")
	if type(chosen) == "boolean" then
		return chosen
	end
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

-- Tweens `goals` over `time` seconds (Quad Out by default). With reduced motion (or time <= 0)
-- the goals are applied at once and nil is returned.
function Motion.Tween(instance: Instance, time: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween?
	if time <= 0 or Motion.Reduced() then
		local target: any = instance
		for key, value in pairs(goals) do
			target[key] = value
		end
		return nil
	end
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- An endless back-and-forth tween (busy dots). Returns nil with reduced motion; Cancel() the
-- result to stop it.
function Motion.Loop(instance: Instance, time: number, goals: { [string]: any }, delayTime: number?): Tween?
	if Motion.Reduced() then
		return nil
	end
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delayTime or 0),
		goals
	)
	tween:Play()
	return tween
end

return Motion
