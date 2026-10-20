-- NIGHT OF THE BURIED MOON — client bootstrap (StarterPlayerScripts.HalloweenClient).
-- Starts the child modules with one shared ctx = {Player, Shared, Config, Layout, Bus, FX, Audio, State}.
-- Contract for every child module: `return {Start = function(ctx) ... end}`. A missing or failing module is reported
-- and skipped. Nothing runs when the event is switched off (Config.HalloweenEventEnabled / State.Enabled).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween", 60)
if not Halloween then
	return
end
local Shared = require(Halloween:WaitForChild("Shared"))
if not Shared.Config.HalloweenEventEnabled then
	return
end
local stateFolder = Halloween:WaitForChild("State", 30)
if stateFolder and stateFolder:GetAttribute("Enabled") == nil then
	stateFolder:GetAttributeChangedSignal("Enabled"):Wait()
end
if not Shared.Enabled() then
	return
end

local ctx = {
	Player = Players.LocalPlayer, Shared = Shared, Config = Shared.Config, Layout = Shared.Layout,
	Bus = require(Halloween:WaitForChild("Bus")), FX = require(Halloween:WaitForChild("FX")),
	Audio = require(Halloween:WaitForChild("Audio")),
}
ctx.State = require(script:WaitForChild("State"))
ctx.Modules = {}

local ORDER = { "State", "Lighting", "ZoneFX", "Soundscape", "BloodMoonFX", "CurseFX", "RushFX", "GateFX", "CauldronFX", "HouseFX",
	"AmbientFX", "SpotFX", "BossFX", "MainMapLayer", "ParticleGovernor", "HUD", "Onboarding" }

for _, name in ipairs(ORDER) do
	local mod = script:FindFirstChild(name)
	if not mod then
		warn("Halloween client: module " .. name .. " missing")
		continue
	end
	local ok, m = pcall(require, mod)
	if not ok then
		warn("Halloween client: " .. name .. " failed to load: " .. tostring(m))
		continue
	end
	ctx.Modules[name] = m
	if type(m) == "table" and type(m.Start) == "function" then
		task.spawn(function()
			local okStart, err = pcall(m.Start, ctx)
			if not okStart then
				warn("Halloween client: " .. name .. ".Start failed: " .. tostring(err))
			end
		end)
	end
end
