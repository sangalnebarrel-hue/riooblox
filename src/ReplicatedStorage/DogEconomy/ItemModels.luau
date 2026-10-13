-- Find models built from code (ReplicatedStorage.Forge): one individual, detailed model per
-- ItemDefinitions id, in two levels of detail.
--   ItemModels.Has(itemId) -> boolean
--   ItemModels.Build(itemId, lod) -> Model?      a fresh build (tests, QA renders)
--   ItemModels.Get(itemId, lod) -> Model?        a clone of the cached template (game code)
-- Recipes live in the child modules Depth1..Depth5: each returns {[itemId] = function(b, lod)}
-- where b is a Forge builder (b.Lod = lod). A recipe builds around the origin, resting on Y = 0,
-- front towards -Z, at the size of the find's old voxel model (DiscoveryVisuals scales it by
-- weight). Lod 0: full detail (viewports, reveals, showcases); Lod 1: silhouette for many
-- distant copies (b:Detail work is skipped).
-- Items without a recipe return nil, and DiscoveryVisuals falls back to the old
-- ReplicatedStorage.DiscoveryModels model.
local Forge = require(script.Parent.Parent:WaitForChild("Forge"))

local ItemModels = {}
local recipes: { [string]: (any, number) -> () } = {}
for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, list = pcall(require, child)
		if ok and type(list) == "table" then
			for id, fn in list do
				if type(fn) == "function" then
					recipes[id] = fn
				end
			end
		else
			warn("DOGROTS item models " .. child.Name .. ": " .. tostring(list))
		end
	end
end
ItemModels.Recipes = recipes

function ItemModels.Has(itemId: string): boolean
	return recipes[itemId] ~= nil
end

function ItemModels.Build(itemId: string, lod: number?): Model?
	local fn = recipes[itemId]
	if not fn then
		return nil
	end
	local level = lod or 0
	local b = Forge.Builder(itemId, { Lod = level })
	local ok, err = pcall(fn, b, level)
	if not ok then
		warn("DOGROTS item model " .. itemId .. ": " .. tostring(err))
		b.Model:Destroy()
		return nil
	end
	local model = b:Finish()
	model:SetAttribute("ItemModelLod", level)
	return model
end

-- Templates are built once per item and level, then cloned.
local templates: { [string]: Model | false } = {}
function ItemModels.Get(itemId: string, lod: number?): Model?
	local key = itemId .. "#" .. tostring(lod or 0)
	local template = templates[key]
	if template == nil then
		template = ItemModels.Build(itemId, lod) or false
		templates[key] = template
	end
	return template and template:Clone() or nil
end

return ItemModels
