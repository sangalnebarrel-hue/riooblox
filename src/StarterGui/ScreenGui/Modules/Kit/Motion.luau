-- Tween helpers. Every kit animation goes through Motion.Tween so ReducedMotion (the Roblox
-- accessibility setting, or Motion.Override) makes it instant.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Motion = {}

-- true / false forces reduced motion on / off (tests, an in-game setting); nil follows Roblox.
Motion.Override = nil :: boolean?

function Motion.Reduced(): boolean
	if Motion.Override ~= nil then
		return Motion.Override == true
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
