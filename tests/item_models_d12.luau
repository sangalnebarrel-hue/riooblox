--!nocheck
-- ITEM MODELS, Depth 1 (Backyard) and Depth 2 (Caverns): the individual Forge recipes in
-- ReplicatedStorage.DogEconomy.ItemModels.Depth1 / Depth2.
--   lune run tests/item_models_d12.luau
-- Every Depth 1/2 item of ItemDefinitions has a recipe that builds at lod 0 and lod 1 through
-- ItemModels.Build, stays inside its part budget, keeps the size of its old voxel model, rests on
-- the ground, marks accent parts, uses several shapes and colours, carries no lights, sounds or
-- scripts, and no two finds share the same geometry.
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

-- Lune builds CFrame.lookAt with a wrong rotation (Roblox is right). Forge's Rod/Beam/Ring use
-- lookAt, so the modules get the corrected library that tools/qa/scene.luau uses too.
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
L.CFrame = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return RawCFrame.new(...)
	end,
}, { __index = RawCFrame })

local Items = L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")
local ItemModels = L.Require("ReplicatedStorage.DogEconomy.ItemModels")
local Forge = L.Require("ReplicatedStorage.Forge")
local Depth1 = L.Require("ReplicatedStorage.DogEconomy.ItemModels.Depth1")
local Depth2 = L.Require("ReplicatedStorage.DogEconomy.ItemModels.Depth2")

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
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

-- Longest side (studs) of the old ReplicatedStorage.DiscoveryModels voxel model of each find.
local OLD_LONGEST = {
	rusty_spoon = 3.65, bottle_cap = 2.25, chewed_bone = 3.45, lost_key = 3.30, rubber_duck = 2.25,
	toy_car = 2.50, tennis_ball = 2.25, worm_jar = 2.64, dog_tag = 2.59, bent_fork = 3.55,
	shiny_marble = 3.75, garden_gnome = 2.86, funny_sock = 2.25, broken_clock = 2.47, old_wallet = 1.80,
	cracked_phone = 2.70, buried_lunchbox = 2.00, tiny_treasure_chest = 2.00, golden_bone = 3.45, mini_ufo_toy = 3.15,
	quartz_crystal = 3.38, large_coal = 2.41, amethyst = 3.38, silver_ore = 2.48, gold_nugget = 2.50,
	geode = 3.38, fossilized_fish = 2.80, ancient_shark_tooth = 2.15, bat_skeleton = 2.80, crystal_skull = 2.10,
	miner_s_lantern = 3.08, broken_pickaxe = 2.60, ancient_miner_helmet = 2.25, meteor_fragment = 2.45, red_crystal = 3.38,
	living_crystal = 3.38, fossilized_egg = 2.30, miner_s_badge = 2.25, head_sized_diamond = 3.38, underground_pearl = 2.25,
	heart_of_the_cavern = 3.38,
}

local ids = {}
for id, def in Items do
	if def.Depth == 1 or def.Depth == 2 then
		table.insert(ids, id)
	end
end
table.sort(ids)

local function shapeOf(part)
	if part:FindFirstChildOfClass("SpecialMesh") then
		return "Ellipsoid"
	elseif part.ClassName == "WedgePart" then
		return "Wedge"
	elseif part.ClassName == "Part" then
		local s = part.Shape.Name
		if s == "Ball" or s == "Cylinder" then
			return s
		end
	end
	return "Block"
end

local function visibleParts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= model.PrimaryPart then
			table.insert(out, d)
		end
	end
	return out
end

-- World-axis bounding box, exact for blocks, balls, sphere meshes and cylinders.
local function bounds(model)
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, part in visibleParts(model) do
		local shape = shapeOf(part)
		local cf, h = part.CFrame, part.Size / 2
		local c = { cf:GetComponents() }
		local pos = { c[1], c[2], c[3] }
		for i = 1, 3 do
			local r = { c[3 + (i - 1) * 3 + 1], c[3 + (i - 1) * 3 + 2], c[3 + (i - 1) * 3 + 3] }
			local e
			if shape == "Ball" then
				e = math.min(h.X, h.Y, h.Z)
			elseif shape == "Ellipsoid" then
				e = math.sqrt((r[1] * h.X) ^ 2 + (r[2] * h.Y) ^ 2 + (r[3] * h.Z) ^ 2)
			elseif shape == "Cylinder" then
				e = math.abs(r[1]) * h.X + math.min(h.Y, h.Z) * math.sqrt(r[2] ^ 2 + r[3] ^ 2)
			else
				e = math.abs(r[1]) * h.X + math.abs(r[2]) * h.Y + math.abs(r[3]) * h.Z
			end
			lo[i] = math.min(lo[i], pos[i] - e)
			hi[i] = math.max(hi[i], pos[i] + e)
		end
	end
	return lo, hi
end

local function colorKey(c)
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function signature(model)
	local rows = {}
	for _, part in visibleParts(model) do
		local s = part.Size
		local dims = { math.floor(s.X * 20 + 0.5), math.floor(s.Y * 20 + 0.5), math.floor(s.Z * 20 + 0.5) }
		table.sort(dims)
		table.insert(rows, string.format("%s:%d,%d,%d:%s", shapeOf(part), dims[1], dims[2], dims[3], colorKey(part.Color)))
	end
	table.sort(rows)
	return #rows .. "|" .. table.concat(rows, ";")
end

local built = {}
local function build(id, lod)
	local key = id .. "#" .. lod
	if built[key] == nil then
		built[key] = ItemModels.Build(id, lod) or false
	end
	return built[key] or nil
end

test("every Depth 1/2 find has a recipe in Depth1/Depth2", function()
	truthy(#ids == 41, "expected 41 Depth 1/2 items, found " .. #ids)
	for _, id in ids do
		local depth = Items[id].Depth
		local module = depth == 1 and Depth1 or Depth2
		truthy(type(module[id]) == "function", "no recipe for " .. id .. " in Depth" .. depth)
		truthy(ItemModels.Has(id), "ItemModels does not see " .. id)
		truthy(OLD_LONGEST[id], "no reference size for " .. id)
	end
	for id in Depth1 do
		truthy(Items[id] and Items[id].Depth == 1, "Depth1 has a recipe for a non Depth 1 item: " .. id)
	end
	for id in Depth2 do
		truthy(Items[id] and Items[id].Depth == 2, "Depth2 has a recipe for a non Depth 2 item: " .. id)
	end
end)

test("every recipe builds at lod 0 and lod 1", function()
	for _, id in ids do
		for _, lod in { 0, 1 } do
			-- run the recipe directly first so a failure shows its real error
			local b = Forge.Builder(id, { Lod = lod })
			local ok, err = pcall(ItemModels.Recipes[id], b, lod)
			truthy(ok, id .. " lod " .. lod .. ": " .. tostring(err))
			local model = build(id, lod)
			truthy(model, id .. " lod " .. lod .. " did not build through ItemModels.Build")
			truthy(model:GetAttribute("ItemModelLod") == lod, id .. ": ItemModelLod attribute")
			truthy(model.PrimaryPart and model.PrimaryPart.Name == "Root", id .. ": Root primary part")
		end
	end
end)

test("part budgets: lod 0 <= 40, lod 1 <= 14, lod 1 is lighter", function()
	for _, id in ids do
		local m0, m1 = build(id, 0), build(id, 1)
		local n0, n1 = Forge.CountParts(m0), Forge.CountParts(m1)
		truthy(n0 <= 40, string.format("%s lod 0 has %d parts (max 40)", id, n0))
		truthy(n1 <= 14, string.format("%s lod 1 has %d parts (max 14)", id, n1))
		truthy(n1 < n0, string.format("%s lod 1 (%d) should be lighter than lod 0 (%d)", id, n1, n0))
		truthy(n0 >= 8, string.format("%s lod 0 has only %d parts: not an individual model", id, n0))
	end
end)

test("size stays within 35% of the old model, resting on the ground, centred", function()
	for _, id in ids do
		for _, lod in { 0, 1 } do
			local lo, hi = bounds(build(id, lod))
			local longest = math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
			local ratio = longest / OLD_LONGEST[id]
			if lod == 0 then
				truthy(ratio >= 0.65 and ratio <= 1.35, string.format("%s longest side %.2f vs old %.2f (x%.2f)", id, longest, OLD_LONGEST[id], ratio))
			end
			truthy(lo[2] >= -0.05 and lo[2] <= 0.1, string.format("%s lod %d lowest point %.3f is not on the ground", id, lod, lo[2]))
			local cx, cz = (lo[1] + hi[1]) / 2, (lo[3] + hi[3]) / 2
			truthy(math.abs(cx) <= 0.6 and math.abs(cz) <= 0.6, string.format("%s lod %d is off centre (%.2f, %.2f)", id, lod, cx, cz))
		end
	end
end)

test("accents, shapes, colours and nothing but parts", function()
	for _, id in ids do
		for _, lod in { 0, 1 } do
			local model = build(id, lod)
			local accents, shapes, colours, shapeCount, colourCount = 0, {}, {}, 0, 0
			for _, part in visibleParts(model) do
				truthy(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery, id .. ": part is not inert: " .. part.Name)
				if part:GetAttribute("ItemAccent") then
					accents += 1
				end
				local shape = shapeOf(part)
				if not shapes[shape] then
					shapes[shape] = true
					shapeCount += 1
				end
				local key = colorKey(part.Color)
				if not colours[key] then
					colours[key] = true
					colourCount += 1
				end
			end
			truthy(accents >= 1 and accents <= 6, string.format("%s lod %d has %d accent parts (want 1..6)", id, lod, accents))
			if lod == 0 then
				truthy(shapeCount >= 2, id .. " uses a single kind of shape")
				truthy(colourCount >= 3, string.format("%s uses only %d colours", id, colourCount))
			end
			for _, d in model:GetDescendants() do
				local bad = d:IsA("Light") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("LuaSourceContainer") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
				truthy(not bad, id .. " contains a " .. d.ClassName)
			end
			truthy(model:GetAttribute("ForgeParts") == #visibleParts(model), id .. ": ForgeParts attribute")
		end
	end
end)

test("no two finds share the same geometry", function()
	local seen = {}
	for _, id in ids do
		local sig = signature(build(id, 0))
		truthy(not seen[sig], id .. " has the same geometry as " .. tostring(seen[sig]))
		seen[sig] = id
	end
end)

test("builds are deterministic (cached templates match fresh builds)", function()
	for _, id in ids do
		local a = signature(build(id, 0))
		local b = signature(ItemModels.Build(id, 0))
		truthy(a == b, id .. " builds differently each time")
	end
end)

print(string.format("item_models_d12: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("item_models_d12 tests failed")
end
