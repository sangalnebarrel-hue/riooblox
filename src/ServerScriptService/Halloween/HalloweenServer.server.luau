-- NIGHT OF THE BURIED MOON — server bootstrap (ServerScriptService.Halloween.HalloweenServer).
-- Config: ReplicatedStorage.Halloween.Config (HalloweenEventEnabled = the off switch).
-- Order: World switch -> Core (data, requests, activity, curse, rush) -> Blood Moon -> Exorcism -> Actions ->
-- gameplay modules (Strike, Ores, DigSpots, Boss, Houses) -> Studio debug. A missing or failing gameplay module is
-- reported and skipped; the rest of the event keeps running.
local RS = game:GetService("ReplicatedStorage")
local Halloween = RS:WaitForChild("Halloween")
local Config = require(Halloween:WaitForChild("Config"))
local here = script.Parent

local World = require(here:WaitForChild("World"))
if not Config.HalloweenEventEnabled then
	World.Disable()
	-- an invoke must never hang on a client (event dex tab, skins menu): answer every request politely
	local remotes = Halloween:FindFirstChild("Remotes")
	local request = remotes and remotes:FindFirstChild("Request")
	if request and request:IsA("RemoteFunction") then
		request.OnServerInvoke = function()
			return false, "The Night of the Buried Moon has ended"
		end
	end
	print("DOGROTS_HALLOWEEN_DISABLED (player data kept)")
	return
end

local Core = require(here:WaitForChild("Core"))
local modules = { World = World, Core = Core }

local function start(name: string, ...)
	local mod = here:FindFirstChild(name)
	if not mod then
		warn("Halloween: module " .. name .. " missing")
		return nil
	end
	local ok, m = pcall(require, mod)
	if not ok then
		warn("Halloween: module " .. name .. " failed to load: " .. tostring(m))
		return nil
	end
	modules[name] = m
	if type(m) == "table" and type(m.Start) == "function" then
		local okStart, err = pcall(m.Start, ...)
		if not okStart then
			warn("Halloween: " .. name .. ".Start failed: " .. tostring(err))
		end
	end
	return m
end

World.Start(Core)
Core.Start()
start("BloodMoon", Core)
start("Exorcism", Core)
start("Actions", Core)
for _, name in ipairs({ "Strike", "Ores", "DigSpots", "Boss", "Houses" }) do
	start(name, Core, modules)
end
start("Debug", Core, modules)
print("DOGROTS_HALLOWEEN_READY", Config.EventName)
