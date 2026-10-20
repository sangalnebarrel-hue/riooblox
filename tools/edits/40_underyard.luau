--!nolint
-- Offline edit: THE UNDERYARD (Workspace.DOGROTS_District.40_Underyard), docs/halloween2/DESIGN.md §7.
-- 1. removes the previous build (idempotent),
-- 2. creates the root Model and the Anchors model (1x1 invisible parts named after UnderyardLayout.Anchors),
-- 3. runs every ModuleScript in ServerStorage.UnderyardBuild that returns {Order = n, Build = function(ctx)} in Order
--    (ties by name). Builder ctx = {Root, Anchors, Layout, District, Kit, YardKit, Note(text), Model(name)}.
-- Builders must only use Instance.new + datatypes (tools/sim.luau) and place geometry around the layout points.
return function(ctx)
	local game, sim, report, roblox = ctx.game, ctx.sim, ctx.report, ctx.roblox
	local Instance, Vector3, Color3, CFrame = roblox.Instance, roblox.Vector3, roblox.Color3, roblox.CFrame
	local ws = game:GetService("Workspace")
	local RS = game:GetService("ReplicatedStorage")
	local SS = game:GetService("ServerStorage")
	local district = ws:FindFirstChild("DOGROTS_District")
	assert(district, "Workspace.DOGROTS_District missing")
	local buildFolder = SS:FindFirstChild("UnderyardBuild")
	if not buildFolder then
		report.Skipped = "ServerStorage.UnderyardBuild missing"
		return
	end
	local old = district:FindFirstChild("40_Underyard")
	if old then
		old:Destroy()
	end
	local Layout = sim:require(RS.Halloween.UnderyardLayout)

	local root = Instance.new("Model")
	root.Name = "40_Underyard"
	root:SetAttribute("HalloweenEvent", true)
	root:SetAttribute("Chapter", 2)
	root:SetAttribute("SelfManagedFX", false)
	root.Parent = district

	local anchors = Instance.new("Model")
	anchors.Name = "Anchors"
	anchors.Parent = root
	local names = {}
	for name in pairs(Layout.Anchors) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = CFrame.new(Layout.Anchors[name])
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Color = Color3.fromRGB(150, 80, 230)
		p.Parent = anchors
	end
	report.Anchors = #names

	local HB = SS:FindFirstChild("HalloweenBuild")
	local Kit = HB and HB:FindFirstChild("Kit") and sim:require(HB.Kit) or nil
	local YardKit = HB and HB:FindFirstChild("YardKit") and sim:require(HB.YardKit) or nil

	local mods = {}
	for _, m in ipairs(buildFolder:GetChildren()) do
		if m:IsA("ModuleScript") then
			local mod = sim:require(m)
			if type(mod) == "table" and type(mod.Build) == "function" then
				table.insert(mods, { Name = m.Name, Order = tonumber(mod.Order) or 100, Mod = mod })
			end
		end
	end
	table.sort(mods, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Name < b.Name
	end)

	local function count(model)
		local parts, lights = 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			elseif d:IsA("Light") then
				lights += 1
			end
		end
		return parts, lights
	end

	report.Builders = {}
	for _, entry in ipairs(mods) do
		local notes = {}
		local bctx = {
			Root = root,
			Anchors = anchors,
			Layout = Layout,
			District = district,
			Kit = Kit,
			YardKit = YardKit,
			Note = function(text)
				table.insert(notes, tostring(text))
			end,
			Model = function(name)
				local m = Instance.new("Model")
				m.Name = name
				m.Parent = root
				return m
			end,
		}
		local before = #root:GetChildren()
		entry.Mod.Build(bctx)
		local made = {}
		for i, child in ipairs(root:GetChildren()) do
			if i > before then
				local parts, lights = count(child)
				table.insert(made, string.format("%s %dp %dl", child.Name, parts, lights))
			end
		end
		table.insert(report.Builders, { Name = entry.Name, Made = made, Notes = notes })
	end
	local parts, lights = count(root)
	report.Parts, report.Lights = parts, lights
end
