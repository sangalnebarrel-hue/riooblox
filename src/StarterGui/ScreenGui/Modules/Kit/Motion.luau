-- Tween helpers. Every kit animation goes through Motion.Tween so reduced motion makes it instant.
-- Reduced motion is on when any of these says so: Motion.Override (tests, tools), Perf.Quality
-- (Roblox's accessibility setting, the saved Setting_ReducedMotion, PAWPAD's Motion toggle), or,
-- if Perf.Quality cannot be loaded, the ReducedMotion / Setting_ReducedMotion player attributes and
-- GuiService.ReducedMotionEnabled read directly.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Motion = {}

-- true / false forces reduced motion on / off (tests, an in-game setting); nil follows the game.
Motion.Override = nil :: boolean?

local quality: any = nil
local function qualityModule(): any
	if quality == nil then
		quality = false
		local perf = ReplicatedStorage:FindFirstChild("Perf")
		local module = perf and perf:FindFirstChild("Quality")
		if module and module:IsA("ModuleScript") then
			local ok, value = pcall(require, module)
			if ok and type(value) == "table" then
				quality = value
			end
		end
	end
	return quality
end

local function fallback(): boolean
	local player = Players.LocalPlayer
	if player and (player:GetAttribute("ReducedMotion") == true or player:GetAttribute("Setting_ReducedMotion") == true) then
		return true
	end
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

function Motion.Reduced(): boolean
	if Motion.Override ~= nil then
		return Motion.Override == true
	end
	local q = qualityModule()
	if q then
		local ok, value = pcall(q.Reduced)
		if ok then
			return value == true
		end
	end
	return fallback()
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
