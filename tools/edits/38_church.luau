--!nolint
-- Offline edit: THE CHURCH (the Grand Crypt + Moon Tower of THE DEAD YARD), docs/halloween2/DESIGN.md §6.4.
-- Runs ServerStorage.HalloweenBuild.Church onto Workspace.DOGROTS_District.38_DeadYard:
--   * hides the Grand Crypt's solid core and its old ajar door (K.Hide: Halloween_Original* recorded once),
--   * builds 38_DeadYard.Church = ChurchChamber, ChurchDoorL/R (closed hinge models), ChurchSlit, ChurchPortal (every part
--     Transparency 1, RevealT attributes), ChurchCracks (hidden), ChurchFX (dust / fog attachments),
--   * makes sure the server anchor 38_DeadYard.Anchors.Portal (128, 3, 729) exists (Underyard.luau puts the DESCEND
--     prompt on it at runtime).
-- Idempotent: the previous Church model is destroyed first, hidden originals keep their first recorded values, the anchor
-- is reused. Builders only use Instance.new + datatypes (tools/sim.luau).
return function(ctx)
	local game, sim, report = ctx.game, ctx.sim, ctx.report
	local ws = game:GetService("Workspace")
	local SS = game:GetService("ServerStorage")
	local district = ws:FindFirstChild("DOGROTS_District")
	local yard = district and district:FindFirstChild("38_DeadYard")
	if not yard then
		report.Skipped = "Workspace.DOGROTS_District.38_DeadYard missing"
		return
	end
	local HB = SS:FindFirstChild("HalloweenBuild")
	local module = HB and HB:FindFirstChild("Church")
	if not (module and module:IsA("ModuleScript")) then
		report.Skipped = "ServerStorage.HalloweenBuild.Church missing"
		return
	end
	local Church = sim:require(module)
	local notes = {}
	local root, result = Church.Build({
		Root = yard,
		Note = function(text)
			table.insert(notes, tostring(text))
		end,
	})
	for k, v in pairs(result) do
		report[k] = v
	end
	report.Notes = notes
	if not root then
		return
	end
	-- the contract the client relies on (fail the build loudly when a builder change breaks it)
	for _, name in ipairs({ "ChurchDoorL", "ChurchDoorR", "ChurchSlit", "ChurchPortal", "ChurchCracks", "ChurchChamber", "ChurchFX" }) do
		assert(root:FindFirstChild(name), "38_church: " .. name .. " missing")
	end
	for _, name in ipairs({ "ChurchDoorL", "ChurchDoorR" }) do
		local door = root[name]
		assert(door.PrimaryPart and door.PrimaryPart.Name == "Hinge", "38_church: " .. name .. " has no Hinge PrimaryPart")
		assert(typeof(door:GetAttribute("ClosedPivot")) == "CFrame", "38_church: " .. name .. " has no ClosedPivot")
	end
	for _, d in ipairs(root.ChurchPortal:GetDescendants()) do
		if d:IsA("BasePart") then
			assert(d.Transparency == 1 and type(d:GetAttribute("RevealT")) == "number", "38_church: portal part " .. d.Name .. " is not hidden")
		end
	end
	assert(yard.Anchors:FindFirstChild("Portal"), "38_church: Anchors.Portal missing")
end
