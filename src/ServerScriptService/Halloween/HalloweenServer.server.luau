-- NIGHT OF THE BURIED MOON — server bootstrap (ServerScriptService.Halloween.HalloweenServer).
-- Config: ReplicatedStorage.Halloween.Config (HalloweenEventEnabled = the off switch).
-- Order: World switch -> Core (data, requests, activity, curse, rush) -> Blood Moon -> Exorcism -> Actions ->
-- gameplay modules (Strike, Ores, DigSpots, Boss, Houses) -> Chapter II (EventHP, Chapter2, Underyard, seals, coffin,
-- resonance, finale) -> Calendar -> Studio debug. A missing or failing gameplay module is
-- reported and skipped; the rest of the event keeps running.
local RS = game:GetService("ReplicatedStorage")
local Halloween = RS:WaitForChild("Halloween")
local Config = require(Halloween:WaitForChild("Config"))
local here = script.Parent

local World = require(here:WaitForChild("World"))
if not Config.HalloweenEventEnabled then
	World.Disable()
	-- an invoke must never hang on a client (event dex tab, skins menu): every request is answered politely, and owned
	-- pickaxe skins stay usable (AfterEvent: PickaxeSkin from the saved profile + SkinEquip)
	local remotes = Halloween:FindFirstChild("Remotes")
	local request = remotes and remotes:FindFirstChild("Request")
	local closed = "The Night of the Buried Moon has ended"
	local okAfter, AfterEvent = pcall(require, here:WaitForChild("AfterEvent"))
	if okAfter then
		AfterEvent.Start(request, closed)
	elseif request and request:IsA("RemoteFunction") then
		request.OnServerInvoke = function()
			return false, closed
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

-- chapter switches replicate as State attributes (Shared.Chapter1Enabled & co. read them on both sides)
local stateFolder = Halloween:FindFirstChild("State")
if stateFolder then
	for _, key in ipairs({ "HalloweenChapter1Enabled", "HalloweenChapter2Enabled", "HalloweenCalendarEnabled", "HalloweenBossFinaleEnabled" }) do
		stateFolder:SetAttribute(key, Config[key] == true)
	end
end

World.Start(Core)
Core.Start()
-- THE DEAD YARD activities (Config.HalloweenChapter1Enabled, DESIGN §2): off = the Blood Moon, exorcism, ores, dig spots,
-- houses and the Gravekeeper do not start and their requests refuse (Core.Chapter1Actions); the zone stays visible and
-- Strike keeps serving Chapter II. Claims of what players already earned stay open (Actions).
local chapter1 = Config.HalloweenChapter1Enabled ~= false
if chapter1 then
	start("BloodMoon", Core)
	start("Exorcism", Core)
end
start("Actions", Core)
for _, name in ipairs({ "Strike", "Ores", "DigSpots", "Boss", "Houses" }) do
	if chapter1 or name == "Strike" then
		start(name, Core, modules)
	end
end
if not chapter1 then
	print("DOGROTS_HALLOWEEN_CHAPTER1_OFF (Dead Yard activities closed, player data kept)")
end
-- CHAPTER II · THE UNDERYARD (docs/halloween2/DESIGN.md §4.1) + the calendar. Modules that are not in the place yet
-- are reported and skipped like any other.
for _, name in ipairs({ "EventHP", "Chapter2", "Underyard", "Seals", "Chapter2Tutorial", -- [WP-H2] onboarding trials
	"SealEcho", "SealRun", "SealMirror", "SealMine",
	"SealDoors", "SealChoir", "SealBell", "Coffin", "Resonance", "BossFinale", "Calendar" }) do
	start(name, Core, modules)
end
start("Debug", Core, modules)
print("DOGROTS_HALLOWEEN_READY", Config.EventName)
