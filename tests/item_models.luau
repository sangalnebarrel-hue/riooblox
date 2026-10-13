--!nocheck
-- ITEM MODELS (find models built from code): lune run tests/item_models.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): Forge, DogEconomy.ItemModels with
-- its Depth recipes, DogEconomy.DiscoveryVisuals (Clone / Style / Preview) and
-- EconomyRewardVisuals. ReplicatedStorage.DiscoveryModels (the old voxel models, only in the
-- place) is stubbed with a few hand-made models.
--   * coverage over every ItemDefinitions id: depth 5 ids must all have a recipe; the other depths
--     are reported, and become strict once every Depth module is present (>= 100 recipes);
--   * every recipe builds at lod 0 and lod 1 within the part budgets (40 / 14), without lights,
--     sounds, scripts or emitters; depth 5 models rest on Y = 0 and mark 1..4 accents;
--   * Clone: recipe model, else the old model, else nil; weight scaling;
--   * Style: every mutation recolours accents, NORMAL restores, ghosts are cleaned, models
--     without accents never error;
--   * template cache: Get returns distinct clones.
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

-- Lune's CFrame.lookAt has a wrong rotation (see tools/qa/scene.luau): the modules get a fixed one,
-- so the preview camera maths is checked for real.
local RawCFrame = roblox.CFrame
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return RawCFrame.new(at)
	end
	look = look.Unit
	up = up or roblox.Vector3.new(0, 1, 0)
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.new(0, 0, -1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(roblox.Vector3.new(1, 0, 0))
		end
	end
	right = right.Unit
	return RawCFrame.fromMatrix(at, right, right:Cross(look))
end
local CFrameFixed = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return RawCFrame.new(...)
	end,
}, { __index = RawCFrame })
L.CFrame = CFrameFixed
local Vector3, Color3, Instance, Enum = roblox.Vector3, roblox.Color3, roblox.Instance, roblox.Enum

-- Stub ReplicatedStorage.DiscoveryModels: hand-made "old" models (plain parts, no accents).
local realReplicated = L.Game.ReplicatedStorage
local oldModels = Instance.new("Folder")
oldModels.Name = "DiscoveryModels"
local function oldModel(name, colors)
	local m = Instance.new("Model")
	m.Name = name
	for i, c in colors do
		local p = Instance.new("Part")
		p.Name = "Voxel" .. i
		p.Size = Vector3.new(0.5, 0.5, 0.5)
		p.CFrame = RawCFrame.new((i - 1) * 0.5, 0.25, 0)
		p.Color = c
		p.Anchored = false
		p.CanCollide = true
		p.Parent = m
	end
	m.Parent = oldModels
	return m
end
oldModel("qa_old_item", { Color3.fromRGB(150, 150, 150), Color3.fromRGB(140, 140, 150), Color3.fromRGB(255, 40, 200) })
L.Stubs.ReplicatedStorage = setmetatable({
	FindFirstChild = function(_, name)
		if name == "DiscoveryModels" then
			return oldModels
		end
		return realReplicated:FindFirstChild(name)
	end,
	WaitForChild = function(_, name)
		if name == "DiscoveryModels" then
			return oldModels
		end
		return realReplicated:FindFirstChild(name)
	end,
}, {
	__index = function(_, k)
		if k == "DiscoveryModels" then
			return oldModels
		end
		return realReplicated[k]
	end,
})

local Forge = L.Require("ReplicatedStorage.Forge")
local Items = L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")
local ItemModels = L.Require("ReplicatedStorage.DogEconomy.ItemModels")
local V = L.Require("ReplicatedStorage.DogEconomy.DiscoveryVisuals")
local RewardVisuals = L.Require("ReplicatedStorage.EconomyRewardVisuals")
local Mutations = L.Require("ReplicatedStorage.DogEconomy.MutationDefinitions")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function near(a, b, tolerance, msg)
	if math.abs(a - b) > tolerance then
		error((msg or "") .. string.format(" expected %.6g ±%.3g got %.6g", b, tolerance, a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

local ids, byDepth = {}, {}
for id, d in Items do
	if type(d) == "table" and d.Id == id then
		table.insert(ids, id)
		byDepth[d.Depth] = byDepth[d.Depth] or {}
		table.insert(byDepth[d.Depth], id)
	end
end
table.sort(ids)
local recipeCount = 0
for _ in ItemModels.Recipes do
	recipeCount += 1
end
local STRICT = recipeCount >= 100

local function parts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
local function accents(model)
	local out = {}
	for _, p in parts(model) do
		if p:GetAttribute("ItemAccent") then
			table.insert(out, p)
		end
	end
	return out
end
local function ghosts(model)
	local n = 0
	for _, p in parts(model) do
		if p:GetAttribute("ItemGhost") then
			n += 1
		end
	end
	return n
end

test("coverage of every find id", function()
	local missing, lines = {}, {}
	for depth = 1, 5 do
		local list = byDepth[depth] or {}
		local have = 0
		for _, id in list do
			if ItemModels.Has(id) then
				have += 1
			elseif depth == 5 or STRICT then
				table.insert(missing, id)
			end
		end
		table.insert(lines, string.format("depth %d: %d/%d", depth, have, #list))
	end
	print(string.format("item models: %d recipes for %d find ids (%s)%s", recipeCount, #ids, table.concat(lines, ", "), STRICT and "" or " - other depths not strict yet"))
	eq(#ids, 108, "find ids")
	eq(#(byDepth[5] or {}), 25, "depth 5 ids")
	truthy(#missing == 0, "find ids without a recipe: " .. table.concat(missing, ", "))
	for id in ItemModels.Recipes do
		truthy(Items[id] ~= nil, "recipe for an unknown id " .. id)
	end
end)

local FORBIDDEN = { "Light", "Sound", "LuaSourceContainer", "ParticleEmitter", "Beam", "Trail", "Fire", "Smoke", "Sparkles" }
test("every recipe builds within budgets at lod 0 and 1", function()
	local checked = 0
	for id in ItemModels.Recipes do
		local counts = {}
		for lod = 0, 1 do
			local model = ItemModels.Build(id, lod)
			truthy(model, id .. " lod " .. lod .. " failed to build")
			local n = model:GetAttribute("ForgeParts")
			counts[lod] = n
			truthy(n >= 1, id .. " has no parts")
			truthy(n <= (lod == 0 and 40 or 14), string.format("%s lod %d: %d parts", id, lod, n))
			eq(model:GetAttribute("ItemModelLod"), lod, id .. " lod attribute")
			for _, d in model:GetDescendants() do
				for _, class in FORBIDDEN do
					truthy(not d:IsA(class), id .. " contains a " .. d.ClassName)
				end
				if d:IsA("BasePart") then
					truthy(d.Anchored and not d.CanCollide and not d.CanTouch and not d.CanQuery, id .. " part " .. d.Name .. " is interactive")
				end
			end
		end
		truthy(counts[1] <= counts[0], id .. " lod 1 has more parts than lod 0")
		checked += 1
	end
	truthy(checked >= 25, "recipes checked")
end)

test("depth 5 models rest on the ground, centred, with 1..4 accents", function()
	for _, id in byDepth[5] do
		for lod = 0, 1 do
			local model = ItemModels.Build(id, lod)
			truthy(model, id)
			local box, size = V.Bounds(model)
			local bottom = box.Position.Y - size.Y / 2
			-- V.Bounds is a box per part (a turned ball counts its corners), so a little slack
			truthy(bottom > -0.08 and bottom < 0.08, string.format("%s lod %d rests at %.3f", id, lod, bottom))
			truthy(math.abs(box.Position.X) < 0.25 and math.abs(box.Position.Z) < 0.25, id .. " is not centred")
			truthy(size.Y > 0.5 and math.max(size.X, size.Y, size.Z) < 5, id .. " has an odd size")
			local a = #accents(model)
			if lod == 0 then
				-- a Gem / ring accent counts all of its parts
				truthy(a >= 1 and a <= 6, string.format("%s has %d accent parts", id, a))
			else
				truthy(a >= 1, id .. " lod 1 lost its accents")
			end
			eq(model.PrimaryPart and model.PrimaryPart.Name, "Root", id .. " root")
		end
	end
end)

test("Clone uses the recipe model, else the old model, else nil", function()
	local model = V.Clone({ ItemId = "the_cube", Mutation = "NORMAL" })
	truthy(model, "the_cube clone")
	eq(model:GetAttribute("ItemModelLegacy"), nil, "recipe model is not legacy")
	eq(model:GetAttribute("ItemId"), "the_cube")
	truthy(model:GetAttribute("ForgeParts"), "recipe template")
	local lod1 = V.Clone({ ItemId = "lost_planet" }, { Lod = 1 })
	eq(lod1:GetAttribute("ItemModelLod"), 1, "lod option")

	local old = V.Clone({ ItemId = "qa_old_item", Mutation = "NORMAL" })
	truthy(old, "fallback to DiscoveryModels")
	eq(old:GetAttribute("ItemModelLegacy"), true)
	truthy(old ~= oldModels.qa_old_item, "a clone, not the source")
	eq(#parts(old), 3, "old model parts")
	for _, p in parts(old) do
		truthy(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery, "old part made static")
	end
	eq(oldModels.qa_old_item.Voxel1.Anchored, false, "source untouched")

	-- a real find without a recipe (only while some Depth modules are missing) also falls back
	for _, id in ids do
		if not ItemModels.Has(id) then
			oldModel(id, { Color3.fromRGB(90, 90, 90) })
			local m = V.Clone({ ItemId = id, Mutation = "GOLDEN", WeightKg = Items[id].BaseWeightKg })
			truthy(m and m:GetAttribute("ItemModelLegacy"), id .. " fallback")
			break
		end
	end
	eq(V.Clone({ ItemId = "no_such_find" }), nil, "unknown id")
	eq(V.Clone(nil), nil, "nil")
	eq(V.Clone({}), nil, "no id")
end)

test("weight scaling (cube root, clamped)", function()
	local d = Items.anti_matter_cube
	local _, base = V.Bounds(V.Clone({ ItemId = "anti_matter_cube" }))
	local _, big = V.Bounds(V.Clone({ ItemId = "anti_matter_cube", WeightKg = d.BaseWeightKg * 8 }))
	near(big.Y / base.Y, 2, 0.02, "8x weight = 2x size")
	near(V.WeightScale({ ItemId = "anti_matter_cube", WeightKg = d.BaseWeightKg / 1000 }), 0.25, 1e-9, "lower clamp")
	near(V.WeightScale({ ItemId = "anti_matter_cube", WeightKg = d.BaseWeightKg * 1e9 }), d.ScaleCap, 1e-9, "ScaleCap")
	near(V.WeightScale({ ItemId = "anti_matter_cube" }), 1, 1e-9, "no weight")
	near(V.WeightScale({ ItemId = "anti_matter_cube", WeightKg = 0 / 0 }), 1, 1e-9, "NaN weight")
	local _, flat = V.Bounds(V.Clone({ ItemId = "anti_matter_cube", WeightKg = d.BaseWeightKg * 8 }, { NoScale = true }))
	near(flat.Y, base.Y, 1e-3, "NoScale")
end)

local MUTATIONS = {}
for _, m in Mutations do
	table.insert(MUTATIONS, m.Name)
end

local function snapshot(model)
	local out = {}
	for _, p in parts(model) do
		out[p] = { p.Color, p.Material }
	end
	return out
end

test("Style recolours accents for every mutation and restores NORMAL", function()
	eq(#MUTATIONS, 5, "item mutations")
	for _, id in byDepth[5] do
		local model = ItemModels.Get(id, 0)
		local before = snapshot(model)
		local list = accents(model)
		for _, mutation in MUTATIONS do
			V.Style(model, mutation)
			eq(model:GetAttribute("ItemMutation"), mutation, id)
			if mutation == "NORMAL" then
				for p, look in before do
					truthy(p.Color == look[1] and p.Material == look[2], id .. " NORMAL restores " .. p.Name)
				end
				eq(ghosts(model), 0, id .. " NORMAL keeps no ghosts")
			else
				local changed = false
				for _, p in list do
					eq(p.Material, Enum.Material.Neon, id .. " " .. mutation .. " accent material")
					if p.Color ~= before[p][1] then
						changed = true
					end
				end
				truthy(changed, id .. " " .. mutation .. " left the accents as they were")
				local g = ghosts(model)
				if mutation == "GLITCHED" then
					truthy(g >= 1 and g <= 2, id .. " GLITCHED ghosts: " .. g)
				else
					eq(g, 0, id .. " " .. mutation .. " ghosts")
				end
			end
		end
		-- restyling again does not stack ghosts, and NORMAL cleans up
		V.Style(model, "GLITCHED")
		V.Style(model, "GLITCHED")
		local g = ghosts(model)
		truthy(g >= 1 and g <= 2, id .. " ghosts stack: " .. g)
		V.Style(model, "NORMAL")
		eq(ghosts(model), 0, id .. " ghosts left")
		for p, look in before do
			truthy(p.Color == look[1] and p.Material == look[2], id .. " restyle restores " .. p.Name)
		end
	end
end)

test("GOLDEN / CURSED / GLITCHED body colours move the right way", function()
	local model = ItemModels.Get("dog_from_another_timeline", 0)
	local body
	for _, p in parts(model) do
		if p.Transparency < 1 and not p:GetAttribute("ItemAccent") and p.Material == Enum.Material.SmoothPlastic then
			body = p
			break
		end
	end
	truthy(body, "a body part")
	local original = body.Color
	V.Style(model, "GOLDEN")
	truthy(body.Color.R > original.R and body.Color.G > original.G, "GOLDEN lerps to gold")
	truthy(body.Material == Enum.Material.Metal or body.Material == Enum.Material.Foil, "GOLDEN metallic")
	V.Style(model, "CURSED")
	truthy(body.Color.G < original.G and body.Color.B < original.B, "CURSED darkens")
	eq(body.Material, Enum.Material.SmoothPlastic, "CURSED keeps the material")
	V.Style(model, "RAINBOW")
	local hues = {}
	for _, p in accents(model) do
		hues[string.format("%.2f", (p.Color:ToHSV()))] = true
	end
	local n = 0
	for _ in hues do
		n += 1
	end
	truthy(n >= 2, "RAINBOW accents get different hues")
end)

test("Style never errors on models without accents", function()
	local plain = Instance.new("Model")
	for i = 1, 4 do
		local p = Instance.new("Part")
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = RawCFrame.new(i, 0.5, 0)
		p.Color = Color3.fromRGB(100 + i * 20, 100, 100)
		p.Parent = plain
	end
	local empty = Instance.new("Model")
	local invisible = Instance.new("Model")
	local hidden = Instance.new("Part")
	hidden.Transparency = 1
	hidden.Parent = invisible
	for _, mutation in { "NORMAL", "GOLDEN", "RAINBOW", "CURSED", "GLITCHED", "SHINY", "", nil } do
		V.Style(plain, mutation)
		V.Style(empty, mutation)
		V.Style(invisible, mutation)
		V.Style(nil, mutation)
	end
	V.Style(plain, "GLITCHED")
	truthy(ghosts(plain) >= 1, "a model without accents still glitches")
	V.Style(plain, "NORMAL")
	eq(ghosts(plain), 0)
	eq(hidden.Transparency, 1, "invisible parts stay invisible")
	-- the old fallback model styles too
	local old = V.Clone({ ItemId = "qa_old_item", Mutation = "CURSED" })
	eq(old:GetAttribute("ItemMutation"), "CURSED")
	local neon = 0
	for _, p in parts(old) do
		if p.Material == Enum.Material.Neon then
			neon += 1
		end
	end
	eq(neon, 1, "only the vivid voxel of the old model glows")
end)

test("template cache returns distinct clones", function()
	local a = ItemModels.Get("broken_portal", 0)
	local b = ItemModels.Get("broken_portal", 0)
	truthy(a and b and a ~= b, "two instances")
	eq(#parts(a), #parts(b), "same parts")
	local pa, pb = parts(a), parts(b)
	local before = pb[2].Color
	pa[2].Color = Color3.new(1, 0, 0)
	eq(pb[2].Color, before, "clones do not share parts")
	local c = ItemModels.Get("broken_portal", 1)
	truthy(#parts(c) < #parts(a), "lod 1 is its own template")
	eq(ItemModels.Get("no_such_find", 0), nil, "no recipe")
	local x = V.Clone({ ItemId = "broken_portal", Mutation = "GOLDEN" })
	local y = V.Clone({ ItemId = "broken_portal", Mutation = "NORMAL" })
	truthy(x ~= y and y:GetAttribute("ItemMutation") == "NORMAL", "styling a clone leaves the template alone")
	local fresh = ItemModels.Get("broken_portal", 0)
	eq(fresh:GetAttribute("ItemMutation"), nil, "template unstyled")
end)

test("rarity", function()
	eq(V.Rarity("void_fragment"), "Common")
	eq(V.Rarity("glitched_coin"), "Uncommon")
	eq(V.Rarity("alien_skull"), "Rare")
	eq(V.Rarity("eye_of_the_void"), "Epic")
	eq(V.Rarity("lost_planet"), "Legendary")
	eq(V.Rarity("the_cube"), "Secret")
	eq(V.Rarity("no_such_find"), "Common")
	truthy(V.RarityColor("Secret") ~= V.RarityColor("Common"), "rarity colours")
	eq(V.RarityRank.Epic, 4)
end)

test("preview: one model per frame, framed by the camera", function()
	local frame = V.Preview(nil, { ItemId = "dimension_key", Mutation = "NORMAL" }, 0, 0, 160, 100)
	eq(frame.ClassName, "ViewportFrame")
	local model = frame:FindFirstChild("Find")
	truthy(model, "find model in the frame")
	local camera = frame:FindFirstChildOfClass("Camera")
	truthy(camera, "camera")
	-- every corner of the find's box is inside the view
	local box, size = V.Bounds(model)
	local tanV = math.tan(math.rad(camera.FieldOfView / 2))
	local tanH = tanV * 160 / 100
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local q = camera.CFrame:PointToObjectSpace(box.Position + size * Vector3.new(sx, sy, sz) / 2)
				local depth = -q.Z
				truthy(depth > 0, "corner behind the camera")
				truthy(math.abs(q.X) / depth <= tanH + 1e-6 and math.abs(q.Y) / depth <= tanV + 1e-6, "corner outside the view")
			end
		end
	end
	V.Show(frame, { ItemId = "dimension_key", Mutation = "NORMAL" }, 160, 100)
	eq(frame:FindFirstChild("Find"), model, "the same find is not rebuilt")
	V.Show(frame, { ItemId = "cosmic_egg", Mutation = "GOLDEN" }, 160, 100)
	local count = 0
	for _, c in frame:GetChildren() do
		if c:IsA("Model") then
			count += 1
		end
	end
	eq(count, 1, "one model per frame")
	truthy(frame:FindFirstChild("Find") ~= model, "replaced")
	eq(#frame:GetChildren(), 2, "model + camera")
	local unknown = V.Preview(nil, { ItemId = "no_such_find" }, 0, 0, 50, 50)
	eq(unknown:FindFirstChild("Find"), nil, "unknown find leaves the frame empty")
end)

test("EconomyRewardVisuals builds item rewards through DiscoveryVisuals", function()
	local model = RewardVisuals.Build({ Kind = "Item", Id = "piece_of_the_sun" })
	truthy(model and model:GetAttribute("ForgeParts"), "recipe model")
	local old = RewardVisuals.Build({ Kind = "Item", Id = "qa_old_item" })
	truthy(old and old:GetAttribute("ItemModelLegacy"), "old model")
	eq(RewardVisuals.Build({ Kind = "Item" }), nil, "no id")
end)

print(string.format("item_models: %d passed, %d failed", passed, failed))
if failed > 0 then
	error(failed .. " item_models test(s) failed")
end
