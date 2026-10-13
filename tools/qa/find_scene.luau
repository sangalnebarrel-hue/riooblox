--!nocheck
-- QA scene: one find model built from code (DogEconomy.ItemModels recipe), optionally styled for a
-- mutation through DiscoveryVisuals.Style. Prints part / accent counts and the size.
--   lune run tools/qa/scene.luau tools/qa/find_scene.luau out.json <itemId> [lod] [mutation]
--   python3 -I tools/qa/render.py out.json out.png --views iso,front,side,top --size 320
-- Recipe errors are raised here (ItemModels.Build only warns), so a broken recipe shows its line.
return function(L, roblox, args)
	local Forge = L.Require("ReplicatedStorage.Forge")
	local ItemModels = L.Require("ReplicatedStorage.DogEconomy.ItemModels")
	local id = args[1]
	local lod = tonumber(args[2]) or 0
	local mutation = args[3] or "NORMAL"
	local recipe = ItemModels.Recipes[id]
	assert(recipe, "no recipe for " .. tostring(id))
	local b = Forge.Builder(id, { Lod = lod })
	recipe(b, lod)
	local model = b:Finish()
	model:SetAttribute("ItemModelLod", lod)
	local accents = 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("ItemAccent") then
			accents += 1
		end
	end
	local V = L.Require("ReplicatedStorage.DogEconomy.DiscoveryVisuals")
	local _, size = V.Bounds(model)
	if mutation ~= "NORMAL" then
		V.Style(model, mutation)
	end
	print(string.format("%s lod %d: %d parts (budget %d), %d accent parts, size %.2f x %.2f x %.2f", id, lod, b.Parts, lod <= 0 and 40 or 14, accents, size.X, size.Y, size.Z))
	return model, string.format("%s L%d %s", id, lod, mutation)
end
