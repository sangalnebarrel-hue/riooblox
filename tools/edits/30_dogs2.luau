--!nolint
-- Offline edit: THE UNDERYARD event dogs H09-H16 (WP-K1, docs/halloween2/DESIGN.md §9.8).
-- Bakes ReplicatedStorage.Halloween.Models.EventDogs2 (run through tools/sim.luau) into the three libraries every dog
-- system reads, exactly like the Chapter I dogs H01-H08:
--   ServerStorage.DogTemplates.<Id>           Engine.AssetReady (needs the template with a RootPart), kennels, displays,
--                                             SecretReveal, lab recipes
--   ReplicatedStorage.MenuModels.<Id>         every UI preview (Kit.Preview / PreviewRenderer), the Secret arrival SkyDog
--   ReplicatedStorage.DogAnimationClips.<Id>  one ModuleScript per clip of EventDogs2.ClipNamesFor(id) (the signature is
--                                             saved twice: "Signature" and its own name) + the folder's role attributes
--                                             (IdleClip / WalkClip / WorkClip / SignatureClip) DogAnimationPlayer resolves
-- Idempotent: every previous instance named after one of the ids in those three folders is replaced.
return function(ctx)
	local game, sim, report, roblox = ctx.game, ctx.sim, ctx.report, ctx.roblox
	local Instance = roblox.Instance
	local RS = game:GetService("ReplicatedStorage")
	local SS = game:GetService("ServerStorage")
	local halloween = RS:FindFirstChild("Halloween")
	local models = halloween and halloween:FindFirstChild("Models")
	local module = models and models:FindFirstChild("EventDogs2")
	if not module then
		report.Skipped = "ReplicatedStorage.Halloween.Models.EventDogs2 missing"
		return
	end
	local D = sim:require(module)

	local function folder(parent, name)
		local f = parent:FindFirstChild(name)
		if not f then
			f = Instance.new("Folder")
			f.Name = name
			f.Parent = parent
		end
		return f
	end
	local templates = folder(SS, "DogTemplates")
	local menus = folder(RS, "MenuModels")
	local library = folder(RS, "DogAnimationClips")

	report.Dogs = {}
	local totalParts, totalClips = 0, 0
	for _, id in ipairs(D.Order) do
		local model = D.Build(id)
		assert(model, "EventDogs2.Build returned nothing for " .. id)
		for _, parent in ipairs({ templates, menus, library }) do
			for _, child in ipairs(parent:GetChildren()) do
				if child.Name == id then
					child:Destroy()
				end
			end
		end
		local menu = model:Clone()
		model.Parent = templates
		menu.Parent = menus

		local clips = Instance.new("Folder")
		clips.Name = id
		for key, value in pairs(D.FolderAttributes(id)) do
			clips:SetAttribute(key, value)
		end
		local names = D.ClipNamesFor(id)
		for _, name in ipairs(names) do
			local clip = D.Clip(id, name)
			assert(clip, "EventDogs2.Clip returned nothing for " .. id .. "." .. name)
			local source = Instance.new("ModuleScript")
			source.Name = name
			source.Source = D.Serialize(clip, D.ClipHeader(id, name))
			source.Parent = clips
		end
		clips.Parent = library

		local parts = model:GetAttribute("Parts") or 0
		totalParts += parts
		totalClips += #names
		table.insert(report.Dogs, string.format("%s %s: %d parts, %d FX hooks, %d clips (signature %s)", model:GetAttribute("EventCode"), id, parts,
			model:GetAttribute("FXHooks") or 0, #names, tostring(model:GetAttribute("SignatureClip"))))
	end
	report.Parts, report.Clips = totalParts, totalClips
end
