--!nocheck
-- ITEM MODELS, Depth 3 (Ancient Ruins) and Depth 4 (Cursed Depths): lune run tests/item_models_d34.luau
-- Builds every Depth 3/4 find through the real ReplicatedStorage.DogEconomy.ItemModels (recipes in
-- ItemModels/Depth3.luau and Depth4.luau, Forge builder) at Lod 0 and Lod 1 and checks: a recipe
-- per ItemDefinitions id, part budgets, size against the old voxel model, resting on the ground,
-- accents, colours, no lights/sounds/scripts/effects, and that no two finds share a geometry.
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

-- Lune 0.10.5 builds CFrame.lookAt with a wrong rotation (Roblox is right) and Forge's Rod / Beam /
-- Ring use it: modules get the same corrected CFrame library as tools/qa/scene.luau.
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
local Depth3 = L.Require("ReplicatedStorage.DogEconomy.ItemModels.Depth3")
local Depth4 = L.Require("ReplicatedStorage.DogEconomy.ItemModels.Depth4")
local V3 = roblox.Vector3.new
local Enum = roblox.Enum

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
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end

-- Bounding box (X, Y, Z studs) of the old voxel model in ReplicatedStorage.DiscoveryModels.
local OLD = {
	ancient_coin = { 2.25, 2.25, 0.48 },
	golden_cup = { 2.25, 2.42, 1.35 },
	pharaoh_mask = { 2.55, 2.35, 1.55 },
	stone_tablet = { 2.10, 2.80, 0.60 },
	eye_of_statue = { 2.45, 1.75, 1.25 },
	ritual_dagger = { 1.50, 3.85, 0.42 },
	lost_crown = { 2.62, 1.55, 2.63 },
	ancient_book = { 1.86, 2.40, 1.12 },
	golden_scarab = { 2.70, 1.35, 2.25 },
	broken_sword = { 1.50, 3.85, 0.42 },
	knight_helmet = { 2.25, 2.25, 1.77 },
	royal_ring = { 1.95, 2.17, 0.60 },
	dog_statuette = { 1.74, 2.67, 2.62 },
	crystal_of_time = { 2.80, 3.38, 2.25 },
	cursed_idol = { 1.74, 2.67, 2.62 },
	sealed_sarcophagus = { 1.50, 1.97, 3.80 },
	eye_of_ancient_god = { 2.45, 1.75, 1.25 },
	crown_of_forgotten_king = { 2.62, 1.55, 2.63 },
	dragon_egg = { 2.25, 2.30, 2.25 },
	golden_dog_idol = { 1.74, 2.67, 2.62 },
	huge_statue = { 17.50, 23.62, 20.06 },
	cursed_bone = { 3.45, 0.77, 1.25 },
	bloody_coin = { 2.25, 2.25, 0.48 },
	broken_horn = { 1.88, 2.59, 0.80 },
	demon_tooth = { 1.88, 2.59, 0.80 },
	possessed_doll = { 1.74, 2.67, 2.62 },
	black_candle = { 0.80, 2.45, 0.80 },
	cursed_ring = { 1.95, 2.17, 0.60 },
	demon_skull = { 2.35, 2.80, 1.55 },
	frozen_heart = { 2.25, 2.03, 1.35 },
	soul_fragment = { 2.80, 3.38, 2.25 },
	eye_in_a_jar = { 1.70, 2.64, 1.40 },
	burning_chain = { 2.97, 2.05, 0.17 },
	cursed_sword = { 1.50, 3.85, 0.42 },
	book_of_souls = { 1.86, 2.40, 1.12 },
	demon_crown = { 2.62, 1.55, 2.63 },
	shadow_crystal = { 2.80, 3.38, 2.25 },
	heart_of_the_beast = { 2.25, 2.03, 1.35 },
	black_halo = { 3.20, 0.41, 3.20 },
	unknown_skull = { 1.90, 2.10, 1.55 },
	the_forbidden_bone = { 3.45, 0.77, 1.25 },
	normal_bone = { 3.45, 0.65, 1.25 },
}

local FORBIDDEN = { "Light", "Sound", "LuaSourceContainer", "ParticleEmitter", "Fire", "Smoke", "Sparkles", "Beam", "Trail", "Explosion", "ProximityPrompt", "ClickDetector" }

local ids = {}
for id, d in Items do
	if type(d) == "table" and (d.Depth == 3 or d.Depth == 4) then
		table.insert(ids, id)
	end
end
table.sort(ids)

local function parts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= model.PrimaryPart then
			table.insert(out, d)
		end
	end
	return out
end
local function bbox(list)
	local lo, hi
	for _, p in list do
		local cf, s = p.CFrame, p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = cf:PointToWorldSpace(V3(s.X * sx, s.Y * sy, s.Z * sz))
					lo = lo and V3(math.min(lo.X, w.X), math.min(lo.Y, w.Y), math.min(lo.Z, w.Z)) or w
					hi = hi and V3(math.max(hi.X, w.X), math.max(hi.Y, w.Y), math.max(hi.Z, w.Z)) or w
				end
			end
		end
	end
	return lo, hi
end
local function colorKey(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
-- Geometry signature: part count + sorted rounded sizes + sorted colours.
local function signature(model)
	local sizes, colors = {}, {}
	for _, p in parts(model) do
		local s = p.Size
		local dims = { math.floor(s.X * 20 + 0.5), math.floor(s.Y * 20 + 0.5), math.floor(s.Z * 20 + 0.5) }
		table.sort(dims)
		table.insert(sizes, table.concat(dims, "x"))
		table.insert(colors, colorKey(p.Color))
	end
	table.sort(sizes)
	table.sort(colors)
	return #sizes .. "|" .. table.concat(sizes, ";") .. "|" .. table.concat(colors, ";")
end

local built = {}
local function build(id, lod)
	local key = id .. "#" .. lod
	if built[key] == nil then
		built[key] = ItemModels.Build(id, lod) or false
	end
	return built[key] or nil
end

test("42 Depth 3/4 finds, every one has a recipe in its depth module", function()
	eq(#ids, 42, "Depth 3/4 item count")
	for _, id in ids do
		truthy(ItemModels.Has(id), "no recipe for " .. id)
		truthy(OLD[id], "no reference size for " .. id)
		local depth = Items[id].Depth
		truthy((depth == 3 and Depth3[id]) or (depth == 4 and Depth4[id]), id .. " must live in Depth" .. depth .. ".luau")
	end
	for id in Depth3 do
		eq(Items[id] and Items[id].Depth, 3, "Depth3.luau recipe " .. id)
	end
	for id in Depth4 do
		eq(Items[id] and Items[id].Depth, 4, "Depth4.luau recipe " .. id)
	end
end)

for _, id in ids do
	test(id .. " builds at Lod 0 and Lod 1", function()
		for _, lod in { 0, 1 } do
			local m = build(id, lod)
			truthy(m, id .. " lod " .. lod .. " failed to build")
			eq(m.Name, id, "model name")
			eq(m:GetAttribute("ItemModelLod"), lod, "ItemModelLod")
			truthy(m.PrimaryPart and m.PrimaryPart.Name == "Root", "Root primary part")
		end
	end)

	test(id .. " part budget", function()
		local n0, n1 = #parts(build(id, 0)), #parts(build(id, 1))
		eq(build(id, 0):GetAttribute("ForgeParts"), n0, "ForgeParts attribute")
		truthy(n0 <= 40, string.format("lod 0 has %d parts (max 40)", n0))
		truthy(n0 >= 6, string.format("lod 0 has only %d parts", n0))
		truthy(n1 <= 14, string.format("lod 1 has %d parts (max 14)", n1))
		truthy(n1 <= n0, "lod 1 must not have more parts than lod 0")
		local rarity = Items[id].Class == "Secret" and "Secret" or nil
		if Items[id].BaseDropChance >= 0.06 and not rarity then
			truthy(n0 <= 32, string.format("a Common find stays simple: %d parts", n0))
		end
	end)

	test(id .. " size close to the old model and resting on the ground", function()
		local old = OLD[id]
		local oldLongest = math.max(old[1], old[2], old[3])
		for _, lod in { 0, 1 } do
			local lo, hi = bbox(parts(build(id, lod)))
			local size = hi - lo
			local longest = math.max(size.X, size.Y, size.Z)
			local ratio = longest / oldLongest
			truthy(ratio >= 0.65 and ratio <= 1.35, string.format("lod %d longest side %.2f vs old %.2f (x%.2f)", lod, longest, oldLongest, ratio))
			truthy(math.abs(lo.Y) <= 0.08 + 0.002 * longest, string.format("lod %d rests on Y = 0 (min Y %.3f)", lod, lo.Y))
			local cx, cz = (lo.X + hi.X) / 2, (lo.Z + hi.Z) / 2
			truthy(math.abs(cx) <= 0.2 * longest and math.abs(cz) <= 0.2 * longest, string.format("lod %d centred on the origin (%.2f, %.2f)", lod, cx, cz))
		end
	end)

	test(id .. " accents, colours, shapes and clean instances", function()
		for _, lod in { 0, 1 } do
			local m = build(id, lod)
			local list = parts(m)
			local accents, colors, shaped = 0, {}, false
			for _, p in list do
				if p:GetAttribute("ItemAccent") then
					accents += 1
				end
				colors[colorKey(p.Color)] = true
				truthy(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery, p.Name .. " must be anchored and non-interactive")
				local rotated = p.CFrame.RightVector:Dot(V3(1, 0, 0)) < 0.999 or p.CFrame.UpVector:Dot(V3(0, 1, 0)) < 0.999
				if p.ClassName ~= "Part" or p.Shape ~= Enum.PartType.Block or p:FindFirstChildOfClass("SpecialMesh") or rotated then
					shaped = true
				end
			end
			truthy(accents >= 1, string.format("lod %d has no accent part", lod))
			truthy(accents <= math.max(4, #list / 2), string.format("lod %d: %d of %d parts are accents", lod, accents, #list))
			local nColors = 0
			for _ in colors do
				nColors += 1
			end
			truthy(nColors >= 2, string.format("lod %d is one flat colour", lod))
			truthy(shaped, "lod " .. lod .. " is made only of axis-aligned blocks")
			for _, d in m:GetDescendants() do
				for _, class in FORBIDDEN do
					truthy(not d:IsA(class), id .. " contains a " .. d.ClassName)
				end
			end
		end
	end)
end

test("no two Depth 3/4 finds share a geometry", function()
	local seen = {}
	for _, id in ids do
		local sig = signature(build(id, 0))
		truthy(not seen[sig], id .. " has the same geometry as " .. tostring(seen[sig]))
		seen[sig] = id
	end
end)

test("Normal Bone is not a recoloured Chewed Bone or Cursed Bone", function()
	local normal = signature(build("normal_bone", 0))
	eq(normal == signature(build("cursed_bone", 0)), false, "normal vs cursed bone")
	if ItemModels.Has("chewed_bone") then
		local chewed = ItemModels.Build("chewed_bone", 0)
		truthy(chewed, "chewed_bone builds")
		eq(normal == signature(chewed), false, "normal vs chewed bone")
	end
	local hasGlitch = false
	for _, p in parts(build("normal_bone", 0)) do
		if p.Material == Enum.Material.Neon then
			hasGlitch = true
		end
	end
	truthy(hasGlitch, "the Secret bone keeps its glitch fringe")
end)

test("ItemModels.Get hands out clones of a cached template", function()
	local a, b = ItemModels.Get("pharaoh_mask", 0), ItemModels.Get("pharaoh_mask", 0)
	truthy(a and b and a ~= b, "two distinct clones")
	eq(#parts(a), #parts(b), "same parts")
	eq(#parts(a), #parts(build("pharaoh_mask", 0)), "same as a fresh build")
end)

print(string.format("item_models_d34: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("item_models_d34 tests failed")
end
