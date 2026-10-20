--!nolint
-- Offline edit: HALLOWEEN CALENDAR stage decorations (ServerStorage.HalloweenCalendar.Stage01..Stage08),
-- docs/halloween2/DESIGN.md §13. Idempotent:
-- 1. removes the previous ServerStorage.HalloweenCalendar and any Workspace.DOGROTS_District.41_HalloweenCalendar,
-- 2. measures the real island once (CalendarKit.Site: grass, ground-level geometry, keep-outs, prompts),
-- 3. runs every ModuleScript ServerStorage.HalloweenCalendarBuild.StageNN ({Stage = n, Build = function(ctx)}) in stage
--    order into its own Folder StageNN (attribute CalendarStage = n); later stages see what earlier ones reserved,
-- 4. final pass per folder (decor never collides / casts, lights Shadows=false + HwBaseBrightness), budget report,
-- 5. leaves an empty Workspace.DOGROTS_District.41_HalloweenCalendar Model for the server (Calendar.luau) to fill.
-- Builder ctx = {Stage, Folder, Site, CK, Kit, YardKit, Cfg, Rules, Params, Rng, District, Note(text), Model(name)}.
-- Builders only use Instance.new + datatypes (tools/sim.luau) and the deterministic YardKit Rng.
return function(ctx)
	local game, sim, report, roblox = ctx.game, ctx.sim, ctx.report, ctx.roblox
	local Instance = roblox.Instance
	local ws = game:GetService("Workspace")
	local RS = game:GetService("ReplicatedStorage")
	local SS = game:GetService("ServerStorage")
	local district = ws:FindFirstChild("DOGROTS_District")
	assert(district, "Workspace.DOGROTS_District missing")
	local buildFolder = SS:FindFirstChild("HalloweenCalendarBuild")
	if not buildFolder then
		report.Skipped = "ServerStorage.HalloweenCalendarBuild missing"
		return
	end
	local Cfg = sim:require(RS.Halloween.HalloweenCalendarConfig)
	local Rules = sim:require(RS.Halloween.CalendarRules)
	for _, old in ipairs({ SS:FindFirstChild(Cfg.Storage), district:FindFirstChild(Cfg.Root) }) do
		if old then
			old:Destroy()
		end
	end

	local CK = sim:require(buildFolder.CalendarKit)
	local Y = CK.Y
	local t0 = os.clock()
	local site = CK.Site(district, Cfg, ws)
	local pool = site:Pool()
	report.Site = { Grass = site.Counts.Grass, Blocked = site.Counts.Blocked, Prompts = site.Counts.Prompts,
		Doors = site.Counts.Doors, FreeCells = #pool, Seconds = math.floor((os.clock() - t0) * 10) / 10 }

	local store = Instance.new("Folder")
	store.Name = Cfg.Storage
	store:SetAttribute("HalloweenCalendar", true)
	store:SetAttribute("Version", Cfg.Version)
	store.Parent = SS

	local stages = {}
	for _, m in ipairs(buildFolder:GetChildren()) do
		if m:IsA("ModuleScript") and string.match(m.Name, "^Stage%d+$") then
			local mod = sim:require(m)
			if type(mod) == "table" and type(mod.Build) == "function" then
				table.insert(stages, { Name = m.Name, Stage = tonumber(mod.Stage) or tonumber(string.match(m.Name, "%d+")), Mod = mod })
			end
		end
	end
	table.sort(stages, function(a, b)
		return a.Stage < b.Stage
	end)

	report.Stages = {}
	local totalParts, totalLights = 0, 0
	local function makeCtx(entry, folder, notes)
		local n = entry.Stage
		return {
			Stage = n, Folder = folder, Site = site, CK = CK, Kit = CK.K, YardKit = Y, Cfg = Cfg, Rules = Rules,
			Params = Rules.StageParams(n, Cfg), Rng = Y.Rng(Cfg.Build.Seed + n * 7919), District = district,
			Note = function(text)
				table.insert(notes, tostring(text))
			end,
			Model = function(name)
				local m = Instance.new("Model")
				m.Name = name
				m.Parent = folder
				return m
			end,
		}
	end
	-- 1) claims: set pieces of later stages reserve their ground before the earlier stages scatter anything
	local folders = {}
	for _, entry in ipairs(stages) do
		local row = Cfg.Stages[entry.Stage]
		local folder = Instance.new("Folder")
		folder.Name = row and row.Folder or entry.Name
		folder:SetAttribute("CalendarStage", entry.Stage)
		folder.Parent = store
		folders[entry] = { Folder = folder, Notes = {} }
		if type(entry.Mod.Claim) == "function" then
			local f = folders[entry]
			entry.Mod.Claim(makeCtx(entry, f.Folder, f.Notes))
		end
	end
	-- 2) builds in stage order
	for _, entry in ipairs(stages) do
		local folder, notes = folders[entry].Folder, folders[entry].Notes
		entry.Mod.Build(makeCtx(entry, folder, notes))
		local parts, lights = CK.Finish(folder)
		folder:SetAttribute("Parts", parts)
		folder:SetAttribute("Lights", lights)
		totalParts += parts
		totalLights += lights
		table.insert(report.Stages, { Name = folder.Name, Parts = parts, Lights = lights, Notes = notes })
	end
	store:SetAttribute("Parts", totalParts)
	store:SetAttribute("Lights", totalLights)
	report.Parts, report.Lights = totalParts, totalLights
	if totalParts > Cfg.Build.MaxParts or totalLights > Cfg.Build.MaxLights then
		report.OverBudget = string.format("%d parts / %d lights (budget %d / %d)", totalParts, totalLights, Cfg.Build.MaxParts, Cfg.Build.MaxLights)
	end

	-- the live root the server fills (decor only: never collides; lights are left to WorldDetailQuality)
	local root = Instance.new("Model")
	root.Name = Cfg.Root
	root:SetAttribute("HalloweenCalendar", true)
	root:SetAttribute("HalloweenEvent", true)
	root.Parent = district
end
