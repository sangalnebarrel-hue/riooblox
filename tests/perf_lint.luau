--!nocheck
--!nolint
-- Perf lint: client code (src/StarterPlayer, src/StarterGui, src/ReplicatedStorage) must not add
-- its own per-frame connections (RenderStepped / Heartbeat / Stepped / PreSimulation / ...:Connect,
-- BindToRenderStep) or workspace-wide DescendantAdded listeners. Today's offenders are listed in
-- BASELINE (file -> count) so existing code passes; anything new fails with a pointer to
-- ReplicatedStorage.Perf.Scheduler / CollectionService tags. Perf.Scheduler itself is allowed.
-- lune run tests/perf_lint.luau            (--report prints the current counts)
local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOTS = { "src/StarterPlayer", "src/StarterGui", "src/ReplicatedStorage" }
local ALLOWED = { ["src/ReplicatedStorage/Perf/Scheduler.luau"] = true }
local FRAME_EVENTS = { "RenderStepped", "Heartbeat", "Stepped", "PreSimulation", "PostSimulation", "PreRender", "PreAnimation" }

-- Existing per-frame connections (Frame) and workspace-wide DescendantAdded listeners (Workspace).
-- Lower a number when you move a script onto Perf.Scheduler or tags; never raise it.
local BASELINE = {
	["src/ReplicatedStorage/RewardMachineText.luau"] = { Frame = 1 },
	["src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau"] = { Frame = 2 },
	["src/ReplicatedStorage/WorldEvents/WorldEventFX.luau"] = { Frame = 3 },
	["src/ReplicatedStorage/WorldEvents/WorldEventSpectacle.luau"] = { Frame = 2 },
	["src/StarterGui/ScreenGui/HUD/HUDStatsController.client.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/HUD/MoneyWidget/MoneyController.client.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/Modules/BuffHUD.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/Modules/Equipment/CaseOpening.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/Modules/Kit/Preview.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/Modules/LabPresentation.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/Modules/LuckyReel.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/Modules/RewardScreens.luau"] = { Frame = 1 },
	["src/StarterGui/ScreenGui/PawpadRuntime.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau"] = { Workspace = 1 },
	["src/StarterPlayer/StarterPlayerScripts/DistrictGuide.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/DistrictWorldMotion.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/DogAnimations.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/DogLinePortalFX.client.luau"] = { Frame = 2 },
	["src/StarterPlayer/StarterPlayerScripts/ExpressMotion.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/GlobalDigPresentation.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/LabPrompt.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/LuckyArrivalFX.client.luau"] = { Frame = 3 },
	["src/StarterPlayer/StarterPlayerScripts/LuckyBlockFX.client.luau"] = { Frame = 2, Workspace = 1 },
	["src/StarterPlayer/StarterPlayerScripts/LuckyLifecycleFX.client.luau"] = { Frame = 3 },
	["src/StarterPlayer/StarterPlayerScripts/MiningClient/Anim.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/MiningClient/FX.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/MiningClient/Gym.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/MiningClient/Mine.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/MiningClient/Shop.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/MuseumPresentation.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/PlaceTypography.client.luau"] = { Workspace = 1 },
	["src/StarterPlayer/StarterPlayerScripts/PlotPrompts.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/RewardMachineAttractionFX.client.luau"] = { Frame = 2 },
	["src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Kit.luau"] = { Frame = 4 },
	["src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Mega.luau"] = { Frame = 2 },
	["src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Stare.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/SecretAura.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/ShopInteriorPrompts.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/SpiderdogAnimation.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/VoidAtmosphere.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/WelcomeArrival.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/WorldEventController.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/WorldEventGameplayFX.client.luau"] = { Frame = 5 },
	["src/StarterPlayer/StarterPlayerScripts/WorldEventTestPanel.client.luau"] = { Frame = 1 },
	["src/StarterPlayer/StarterPlayerScripts/WorldSignController.client.luau"] = { Frame = 1 },
}

-- Code without comments (block comments first, then line comments). Strings are left alone; a
-- "--" inside a string only shortens what is scanned on that line.
local function stripComments(source)
	source = source:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	return (source:gsub("%-%-[^\n]*", ""))
end

local function escape(name)
	return (name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

-- counts(source) -> frame, workspaceWide
local function counts(source)
	local code = "\n" .. stripComments(source) -- a leading separator for the "[^%w_.]name" patterns
	local frame = 0
	for _, event in ipairs(FRAME_EVENTS) do
		for _ in code:gmatch("%." .. event .. "%s*:%s*Connect%s*%(") do
			frame += 1
		end
		for _ in code:gmatch("%." .. event .. "%s*:%s*ConnectParallel%s*%(") do
			frame += 1
		end
	end
	for _ in code:gmatch("BindToRenderStep%s*%(") do
		frame += 1
	end
	-- Names that refer to the Workspace (or the whole game) in this file.
	local roots = { workspace = true, Workspace = true, game = true }
	for name in code:gmatch("local%s+([%w_]+)%s*=%s*workspace[^%w_.:]") do
		roots[name] = true
	end
	for name in code:gmatch("local%s+([%w_]+)%s*=%s*game:GetService%(%s*[\"']Workspace[\"']%s*%)") do
		roots[name] = true
	end
	for name in code:gmatch("local%s+([%w_]+)%s*=%s*game%.Workspace[^%w_]") do
		roots[name] = true
	end
	-- Loops over a list holding the Workspace: `for _, root in ipairs({workspace, gui}) do
	-- root.DescendantAdded...` or `local roots = {gui, workspace}` ... `for _, root in roots do`.
	local function holdsRoot(literal)
		for root in pairs(roots) do
			if root ~= "game" and literal:find("[{,]%s*" .. escape(root) .. "%s*[,}]") then
				return true
			end
		end
		return false
	end
	local lists = {}
	for name, literal in code:gmatch("local%s+([%w_]+)%s*=%s*(%b{})") do
		if holdsRoot(literal) then
			lists[name] = true
		end
	end
	local function loopVar(var, iterated)
		if lists[iterated] or (iterated:sub(1, 1) == "{" and holdsRoot(iterated)) then
			roots[var] = true
		end
	end
	for var, iterated in code:gmatch("for%s+[%w_]+%s*,%s*([%w_]+)%s+in%s+ipairs%(%s*(%b{})%s*%)") do
		loopVar(var, iterated)
	end
	for var, iterated in code:gmatch("for%s+[%w_]+%s*,%s*([%w_]+)%s+in%s+ipairs%(%s*([%w_]+)%s*%)") do
		loopVar(var, iterated)
	end
	for var, iterated in code:gmatch("for%s+[%w_]+%s*,%s*([%w_]+)%s+in%s+([%w_]+)%s+do") do
		loopVar(var, iterated)
	end
	for var, iterated in code:gmatch("for%s+[%w_]+%s*,%s*([%w_]+)%s+in%s+(%b{})%s*do") do
		loopVar(var, iterated)
	end
	local wide = 0
	for root in pairs(roots) do
		for _ in code:gmatch("[^%w_.]" .. escape(root) .. "%.DescendantAdded") do
			wide += 1
		end
		if root ~= "game" then
			for _ in code:gmatch("game%." .. escape(root) .. "%.DescendantAdded") do
				wide += 1
			end
		end
	end
	for _ in code:gmatch("game:GetService%(%s*[\"']Workspace[\"']%s*%)%.DescendantAdded") do
		wide += 1
	end
	return frame, wide
end

local passed, failed = 0, 0
local function check(name, ok, message)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. message)
	end
end

-- The scanner itself.
do
	local cases = {
		{ "RunService.Heartbeat:Connect(function() end)", 1, 0 },
		{ "Run.RenderStepped:Connect(f) game:GetService('RunService').PreSimulation:Connect(g)", 2, 0 },
		{ "-- RunService.Heartbeat:Connect(f)\n--[[ Run.Stepped:Connect(f) ]]", 0, 0 },
		{ "RunService:BindToRenderStep('x', 1, f)", 1, 0 },
		{ "RunService.Heartbeat:Wait() Run.Heartbeat:Once(f)", 0, 0 },
		{ "workspace.DescendantAdded:Connect(f)", 0, 1 },
		{ "local ws=workspace;ws.DescendantAdded:Connect(f)", 0, 1 },
		{ "local W = game:GetService(\"Workspace\")\nW.DescendantAdded:Connect(f)", 0, 1 },
		{ "game.Workspace.DescendantAdded:Connect(f) game.DescendantAdded:Connect(f)", 0, 2 },
		{ "map.DescendantAdded:Connect(f) yards.DescendantAdded:Connect(f)", 0, 0 },
		{ "local map=workspace:WaitForChild('X');map.DescendantAdded:Connect(f)", 0, 0 },
		{ "for _,root in ipairs({workspace,gui})do root.DescendantAdded:Connect(f) end", 0, 1 },
		{ "local roots = {gui, workspace}\nfor _, root in ipairs(roots) do root.DescendantAdded:Connect(f) end", 0, 1 },
		{ "for _, part in ipairs(list) do part.DescendantAdded:Connect(f) end", 0, 0 },
	}
	for i, case in ipairs(cases) do
		local frame, wide = counts(case[1])
		check("scanner case " .. i, frame == case[2] and wide == case[3], string.format("%q -> %d frame, %d workspace (expected %d, %d)", case[1], frame, wide, case[2], case[3]))
	end
end

-- Every client file against the baseline.
local report = process.args[1] == "--report"
local files = {}
local function scan(dir)
	if not fs.isDir(dir) then
		return
	end
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			scan(path)
		elseif entry:match("%.luau$") then
			table.insert(files, path)
		end
	end
end
for _, root in ipairs(ROOTS) do
	scan(root)
end
table.sort(files)
check("client files found", #files > 100, "only " .. #files .. " files (run from the repository root)")

local seen = {}
for _, path in ipairs(files) do
	local frame, wide = counts(fs.readFile(path))
	seen[path] = true
	if report and (frame > 0 or wide > 0) then
		print(string.format('\t["%s"] = { Frame = %d, Workspace = %d },', path, frame, wide))
	end
	if not ALLOWED[path] then
		local base = BASELINE[path] or {}
		check(path .. " per-frame", frame <= (base.Frame or 0), string.format(
			"%d RenderStepped/Heartbeat/Stepped/PreSimulation connection(s), baseline %d. Run periodic work through ReplicatedStorage.Perf.Scheduler.Every(hz, name, fn) instead.",
			frame, base.Frame or 0))
		check(path .. " workspace-wide", wide <= (base.Workspace or 0), string.format(
			"%d workspace-wide DescendantAdded listener(s), baseline %d. Tag the objects and use CollectionService:GetInstanceAddedSignal(tag) instead.",
			wide, base.Workspace or 0))
		if frame < (base.Frame or 0) or wide < (base.Workspace or 0) then
			print(string.format("note: %s is below its baseline (%d/%d) - lower BASELINE in tests/perf_lint.luau", path, frame, wide))
		end
	end
end
for path in pairs(BASELINE) do
	check("baseline file exists: " .. path, seen[path] == true, "remove it from BASELINE")
end

print(string.format("perf_lint: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("perf_lint failed")
end
