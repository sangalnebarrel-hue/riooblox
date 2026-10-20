-- NIGHT OF THE BURIED MOON · event dog templates (ServerStorage.HalloweenBuild.Dogs, WP4).
-- Builds the 8 event dogs (RS.Halloween.Models.EventDogs) into the two model libraries every dog consumer reads:
--   ServerStorage.DogTemplates.<VisualAsset>   kennels, displays, reveals, lab recipes, Engine AssetReady
--   ReplicatedStorage.MenuModels.<VisualAsset> every UI preview (Kit.Preview / PreviewRenderer), lab cinematic, stampede
-- VisualAsset = DogId (HW_*). Run offline by hw/edits/dogs.luau through tools/sim.luau (the models are SAVED in the
-- place); Dogs.Ensure() can also be called at runtime (server) to recreate a missing template, e.g. in a test place.
-- Clip ModuleScripts (ReplicatedStorage.DogAnimationClips.<Id>) need Source and are written by the Lune edit only.
-- Each model carries its ability FX hooks (Attachments "HwFX_*", see EventDogs.StartFX / BurstFX); nothing emits until a
-- client asks, so the saved templates stay particle-free.
local D = {}

local function eventDogs()
	local RS = game:GetService("ReplicatedStorage")
	local halloween = RS:FindFirstChild("Halloween")
	local models = halloween and halloween:FindFirstChild("Models")
	local module = models and models:FindFirstChild("EventDogs")
	assert(module, "ReplicatedStorage.Halloween.Models.EventDogs is missing")
	return require(module)
end

local function folder(parent: Instance, name: string): Instance
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

-- Builds (or rebuilds) every event dog. ctx (optional): {Note = function(text), Only = {[id] = true}, Missing = bool}
function D.Build(ctx: any?)
	ctx = ctx or {}
	local note = ctx.Note or function() end
	local EventDogs = eventDogs()
	local SS = game:GetService("ServerStorage")
	local RS = game:GetService("ReplicatedStorage")
	local templates = folder(SS, "DogTemplates")
	local menus = folder(RS, "MenuModels")
	local built = {}
	for _, id in ipairs(EventDogs.Order) do
		if ctx.Only and not ctx.Only[id] then
			continue
		end
		if ctx.Missing and templates:FindFirstChild(id) and menus:FindFirstChild(id) then
			continue
		end
		local model = EventDogs.Build(id)
		if model then
			local old = templates:FindFirstChild(id)
			if old then
				old:Destroy()
			end
			local oldMenu = menus:FindFirstChild(id)
			if oldMenu then
				oldMenu:Destroy()
			end
			local menu = model:Clone()
			model.Parent = templates
			menu.Parent = menus
			built[id] = model:GetAttribute("Parts") or 0
			note(string.format("dogs: %s built (%d parts, %d FX hooks)", id, built[id], model:GetAttribute("FXHooks") or 0))
		else
			note("dogs: no builder for " .. id)
		end
	end
	return built
end

-- Runtime safety net (server): recreate templates / menu models that are missing. Never touches existing ones.
function D.Ensure(): number
	local n = 0
	local ok, err = pcall(function()
		for _ in pairs(D.Build({ Missing = true })) do
			n += 1
		end
	end)
	if not ok then
		warn("DOGROTS event dogs: " .. tostring(err))
	end
	return n
end

return D
