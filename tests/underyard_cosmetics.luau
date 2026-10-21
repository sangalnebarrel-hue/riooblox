--!nolint
-- THE UNDERYARD plot cosmetics and showcase finds (WP-K3): catalog rows, Forge recipes within budget and footprint,
-- idle animations (valid, never collidable, every pose inside the slot), the 15 finds (definitions, tiers, models,
-- showcase attributes, Russian). lune run tests/underyard_cosmetics.luau
local L = require("./lib/economy_env")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

-- Forge runs with Roblox's CFrame.lookAt (Lune's returns NaN for a vertical look, which every vertical rod has):
-- load it here with the shim of tools/sim.luau and hand it to the modules through L.Overrides.
do
	local function lookAt(at, target, up)
		local look = target - at
		if look.Magnitude < 1e-6 then
			return CFrame.new(at)
		end
		look = look.Unit
		local right = look:Cross(up or Vector3.new(0, 1, 0))
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.new(0, 0, -1))
		end
		right = right.Unit
		return CFrame.fromMatrix(at, right, right:Cross(look).Unit, -look)
	end
	local src = (process.env.DOGROTS_SRC or "src"):gsub("/$", "")
	local env = setmetatable({
		CFrame = setmetatable({ lookAt = lookAt }, { __index = CFrame }),
		Color3 = roblox.Color3, Vector3 = Vector3, Instance = roblox.Instance, Enum = roblox.Enum, typeof = typeof,
	}, { __index = _G })
	L.Overrides["ReplicatedStorage/Forge"] = luau.load(fs.readFile(src .. "/ReplicatedStorage/Forge.luau"), { debugName = "Forge", environment = env })()
end

local Catalog = L.Require("ReplicatedStorage.DogEconomy.DecorCatalog")
local DecorModels = L.Require("ReplicatedStorage.Decor.DecorModels")
local DecorIdle = L.Require("ReplicatedStorage.Decor.DecorIdle")
local Items = L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")
local Depths = L.Require("ReplicatedStorage.DogEconomy.DepthDefinitions")
local Profiles = L.Require("ReplicatedStorage.DogEconomy.WeightProfiles")
local ItemModels = L.Require("ReplicatedStorage.DogEconomy.ItemModels")
local Showcase = L.Require("ReplicatedStorage.DogEconomy.ShowcaseRules")
local Valuation = L.Require("ReplicatedStorage.ItemValuation")
local UnderyardItems = L.Require("ReplicatedStorage.Localization.UnderyardItems")
local PlotLoc = L.Require("ReplicatedStorage.Localization.Plot")

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
local function check(cond, msg)
	if not cond then
		error(msg, 2)
	end
end

-- The fixed ids of the design (docs/halloween2/DESIGN.md §9.8; WP-A's Chapter2Config references them).
local DECOR = {
	uy_crooked_bell_tower = "Large", uy_whispering_tree = "Large", uy_moon_statue = "Large", uy_ghost_fountain = "Large",
	uy_grave_gate = "Large", uy_haunted_kennel = "Small", uy_spirit_fence = "Small", uy_coffin_flowerbed = "Small",
	uy_floating_tombstones = "Small", uy_funeral_lanterns = "Small",
}
local FINDS = {
	uy_coffin_nail = "Common", uy_black_feather = "Common", uy_wax_hand = "Common", uy_crooked_house_key = "Common",
	uy_blue_funeral_rose = "Common", uy_bottled_whisper = "Rare", uy_broken_pocket_watch = "Rare", uy_lost_veil = "Rare",
	uy_cracked_bell_clapper = "Rare", uy_tiny_tombstone = "Rare", uy_dead_wedding_ring = "Epic", uy_ghost_photograph = "Epic",
	uy_mourning_locket = "Epic", uy_bellkeeper_mask = "Legendary", uy_hollow_heart = "Legendary",
}
local BUDGET = { Small = 40, Large = 120 }
local FIND_BUDGET = 80

local function cyrillic(text)
	return type(text) == "string" and string.find(text, "[\208\209]") ~= nil
end

-- Footprint of a decor slot (DecorCatalog header): Small <= 3.2 x 2.4 at the ground, 4 x 3.4 above 3 studs;
-- Large <= 9.6 x 11. Returns nil or a message for the first violating corner.
local function outside(size, p)
	if size == "Large" then
		if math.abs(p.X) > 4.8 + 1e-3 or math.abs(p.Z) > 5.5 + 1e-3 then
			return "Large footprint"
		end
	elseif p.Y < 3 then
		if math.abs(p.X) > 1.6 + 1e-3 or math.abs(p.Z) > 1.2 + 1e-3 then
			return "Small ground footprint"
		end
	elseif math.abs(p.X) > 2.0 + 1e-3 or math.abs(p.Z) > 1.7 + 1e-3 then
		return "Small upper footprint"
	end
	return nil
end
local function corners(cf, size)
	local out = {}
	local h = size / 2
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				table.insert(out, cf:PointToWorldSpace(Vector3.new(h.X * x, h.Y * y, h.Z * z)))
			end
		end
	end
	return out
end
local function visibleParts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and d.Transparency < 1 then
			table.insert(out, d)
		end
	end
	return out
end
local function bounds(model)
	local lo, hi
	for _, p in visibleParts(model) do
		for _, c in corners(p.CFrame, p.Size) do
			lo = lo and lo:Min(c) or c
			hi = hi and hi:Max(c) or c
		end
	end
	return lo, hi
end

local built = {}
local function decorModel(id)
	if built[id] == nil then
		built[id] = DecorModels.Build(id, 0) or false
	end
	return built[id] or nil
end

test("catalog: the 10 Underyard decorations with their fixed ids, sizes and event", function()
	local n = 0
	for id, size in DECOR do
		n += 1
		local item = Catalog.Get(id)
		check(item, "missing catalog row " .. id)
		check(item.Size == size, id .. " size " .. tostring(item.Size) .. " expected " .. size)
		check(item.Reward == "Underyard2026", id .. " reward " .. tostring(item.Reward))
		check(item.Cash == 0 and item.Stone == 0 and (item.Bones or 0) == 0, id .. " must not be for sale")
		check(item.Stage == 1, id .. " stage gate")
		check(Catalog.IsReward(id), id .. " is not a reward")
		check(Catalog.MaxOwned(id) == Catalog.SlotCount[size], id .. " max owned")
		check(type(item.Name) == "string" and item.Name == string.upper(item.Name) and #item.Name > 3, id .. " name")
		check(cyrillic(item.RU), id .. " Russian name")
		check(Catalog.CategoryById[item.Category].Size == size, id .. " category size")
		check(string.sub(item.Category, 1, 9) == "Underyard", id .. " category " .. item.Category)
		local en, ru = Catalog.RewardHint(item, false), Catalog.RewardHint(item, true)
		check(#en > 10 and cyrillic(ru), id .. " reward hint")
		check(PlotLoc.Exact[item.Name] == item.RU, id .. " name not localized by Localization.Plot")
	end
	check(n == 10, "expected 10 decorations")
	local ids = Catalog.RewardIds("Underyard2026")
	check(#ids == 10, "RewardIds lists " .. #ids)
	for _, id in ids do
		check(DECOR[id], "unexpected Underyard decoration " .. id)
	end
	-- the Chapter I rewards keep their own hint
	check(string.find(Catalog.RewardHint(Catalog.Get("hw_bone_arch"), false), "Pumpkin") ~= nil, "Chapter I hint")
	-- one rarity everywhere: the plot decor screen (catalog) and the Black Coffin / Underyard window (Chapter2Config)
	local C2Cfg = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
	for id in DECOR do
		local def = C2Cfg.Decor.Defs[id]
		check(def ~= nil, id .. " missing in Chapter2Config.Decor")
		check(Catalog.Get(id).Rarity == def.Rarity, id .. " rarity: catalog " .. tostring(Catalog.Get(id).Rarity) .. ", Chapter II " .. tostring(def.Rarity))
	end
end)

test("decor recipes exist, build at both levels of detail and stay within the part budget", function()
	for id, size in DECOR do
		check(DecorModels.Has(id), "no recipe " .. id)
		local model = decorModel(id)
		check(model, "recipe failed " .. id)
		local parts = model:GetAttribute("ForgeParts")
		check(type(parts) == "number" and parts > 10, id .. " part count")
		check(parts <= BUDGET[size], id .. " has " .. parts .. " parts (budget " .. BUDGET[size] .. ")")
		local lod1 = DecorModels.Build(id, 1)
		check(lod1 and lod1:GetAttribute("ForgeParts") <= parts, id .. " Lod 1")
		local lights = 0
		for _, d in model:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				check(d.Shadows == false, id .. " light casts shadows")
			end
		end
		check(lights <= 1, id .. " has " .. lights .. " lights")
		check(model:GetAttribute("DecorId") == id, id .. " DecorId")
	end
end)

test("decor stands on the ground inside its slot footprint", function()
	for id, size in DECOR do
		local model = decorModel(id)
		local lo, hi = bounds(model)
		check(lo.Y > -0.6 and lo.Y < 0.3, id .. " ground contact " .. lo.Y)
		check(hi.Y < (size == "Large" and 22 or 7), id .. " too tall " .. hi.Y)
		for _, p in visibleParts(model) do
			for _, c in corners(p.CFrame, p.Size) do
				local why = outside(size, c)
				check(not why, id .. " " .. p.Name .. " outside the " .. tostring(why) .. " at " .. tostring(c))
			end
		end
	end
end)

-- Every animated decoration (the Underyard pieces and the windmill): valid tracks, nothing collidable moves, movers
-- never nest, and every sampled pose keeps every moving part inside the footprint.
test("idle animations are valid, never move collidable parts and stay inside the footprint", function()
	local animated = { windmill = "Large" }
	for id, size in DECOR do
		animated[id] = size
	end
	for id, size in animated do
		local model = id == "windmill" and DecorModels.Build(id, 0) or decorModel(id)
		local tagged = model:GetAttribute("DecorIdle")
		check(type(tagged) == "number" and tagged > 0, id .. " not tagged DecorIdle")
		local count, movers = 0, 0
		for _, inst in model:GetDescendants() do
			local kind = inst:GetAttribute("IdleAnim")
			if kind ~= nil then
				count += 1
				check(inst:IsA("BasePart") or inst:IsA("Model"), id .. " IdleAnim on a " .. inst.ClassName)
				local spec = DecorIdle.Spec(inst, CFrame.new())
				check(spec, id .. " unknown IdleAnim " .. tostring(kind))
				check(spec.Period >= 0.5 and spec.Period <= 60, id .. " period " .. spec.Period)
				if spec.Moves then
					movers += 1
					local parent = inst.Parent
					while parent and parent ~= model do
						local k = parent:GetAttribute("IdleAnim")
						check(not (k and DecorIdle.Moves[k]), id .. " nested movers at " .. inst.Name)
						parent = parent.Parent
					end
					local parts = inst:IsA("BasePart") and { inst } or {}
					for _, d in inst:GetDescendants() do
						if d:IsA("BasePart") then
							table.insert(parts, d)
						end
					end
					check(#parts > 0, id .. " empty mover " .. inst.Name)
					for _, p in parts do
						check(not p.CanCollide, id .. " moves collidable part " .. p.Name)
					end
					for _, t in DecorIdle.Samples(spec, 36) do
						local delta = DecorIdle.Delta(spec, t)
						for _, p in parts do
							if p.Transparency < 1 then
								for _, c in corners(delta * p.CFrame, p.Size) do
									local why = outside(size, c)
									check(not why, id .. " " .. inst.Name .. " leaves the " .. tostring(why) .. " at t=" .. string.format("%.2f", t))
									check(c.Y > -0.3, id .. " " .. inst.Name .. " sinks into the ground")
								end
							end
						end
					end
				else
					check(spec.Amp >= 0 and spec.Amp <= 1, id .. " glow strength " .. spec.Amp)
				end
			end
		end
		check(count == tagged, id .. " DecorIdle " .. tagged .. " but " .. count .. " tracks")
		check(id == "uy_coffin_flowerbed" or movers > 0, id .. " has no moving part")
	end
end)

test("the design's idle motions are on the right pieces", function()
	local function kinds(id)
		local out = {}
		for _, inst in decorModel(id):GetDescendants() do
			local k = inst:GetAttribute("IdleAnim")
			if k then
				out[k] = (out[k] or 0) + 1
			end
		end
		return out
	end
	check(kinds("uy_crooked_bell_tower").Swing == 1, "bell tower: the bell swings")
	check(kinds("uy_whispering_tree").Sway >= 3 and kinds("uy_whispering_tree").Spin == 1, "tree: branches sway, whispers circle")
	check(kinds("uy_haunted_kennel").Swing == 1 and kinds("uy_haunted_kennel").Blink == 2, "kennel: door creaks, eyes blink")
	check(kinds("uy_spirit_fence").Bob == 3, "fence: three drifting wisps")
	check(kinds("uy_floating_tombstones").Bob == 3, "tombstones bob")
	check(kinds("uy_funeral_lanterns").Flicker >= 2, "lanterns flicker")
	check(kinds("uy_moon_statue").Pulse >= 2, "moon pulses")
	check(kinds("uy_ghost_fountain").Spin == 1, "fountain arcs turn")
	check(kinds("uy_grave_gate").Swing >= 2, "gates swing")
	check(kinds("uy_coffin_flowerbed").Pulse >= 1, "flowerbed glows")
end)

test("DecorIdle maths", function()
	local part = roblox.Instance.new("Part")
	part.CFrame = CFrame.new(0, 2, 0)
	part:SetAttribute("IdleAnim", "Swing")
	part:SetAttribute("IdleAmp", 20)
	part:SetAttribute("IdlePeriod", 2)
	part:SetAttribute("IdlePivot", CFrame.new(0, 3, 0))
	local spec = DecorIdle.Spec(part)
	check(spec.Moves and spec.Kind == "Swing" and spec.Amp == 20, "spec")
	local p = (DecorIdle.Delta(spec, 0.5) * part.CFrame).Position -- quarter period: full swing about X
	check(math.abs(p.Y - (3 - math.cos(math.rad(20)))) < 1e-4, "swing height " .. p.Y)
	check((DecorIdle.Delta(spec, 0) * part.CFrame).Position:FuzzyEq(Vector3.new(0, 2, 0), 1e-5), "rest at t=0")
	part:SetAttribute("IdleAnim", "Spin")
	part:SetAttribute("IdleAxis", "Y")
	part:SetAttribute("IdlePivot", CFrame.new(1, 0, 0))
	local spin = DecorIdle.Spec(part)
	check((DecorIdle.Delta(spin, 2) * part.CFrame).Position:FuzzyEq(Vector3.new(0, 2, 0), 1e-4), "a full turn")
	part:SetAttribute("IdleAnim", "Blink")
	part:SetAttribute("IdlePeriod", 4)
	local blink = DecorIdle.Spec(part)
	local shut = 0
	for i = 0, 3999 do
		local fade = DecorIdle.Glow(blink, i / 100)
		if fade == 1 then
			shut += 1
		end
	end
	check(shut > 0 and shut < 400, "blinks are short " .. shut)
	for _, kind in { "Flicker", "Pulse" } do
		part:SetAttribute("IdleAnim", kind)
		part:SetAttribute("IdleAmp", 1)
		local s = DecorIdle.Spec(part)
		for i = 0, 200 do
			local fade, light = DecorIdle.Glow(s, i / 37, 3)
			check(fade >= 0 and fade <= 1 and light >= 0 and light <= 1, kind .. " range")
		end
	end
	check(DecorIdle.Spec(roblox.Instance.new("Part")) == nil, "untagged")
end)

test("finds: 15 definitions, Class Underyard, names, never rolled by a depth", function()
	local n = 0
	local inDepth = {}
	for _, depth in Depths do
		for _, id in depth.Items or {} do
			inDepth[id] = true
		end
	end
	for id in FINDS do
		n += 1
		local def = Items[id]
		check(def, "missing item " .. id)
		check(def.Id == id and def.VisualAsset == id, id .. " ids")
		check(def.Class == "Underyard", id .. " class " .. tostring(def.Class))
		check(def.Event == "Underyard2026", id .. " event")
		check(type(def.Depth) == "number" and Depths[tostring(def.Depth)], id .. " depth")
		check(not inDepth[id], id .. " is in a DepthDefinitions list")
		check(type(def.BaseWeightKg) == "number" and def.BaseWeightKg > 0, id .. " weight")
		check(Profiles[def.WeightProfile], id .. " weight profile")
		check(type(def.BaseValue) == "number" and def.BaseValue > 0, id .. " value")
		check(type(def.DisplayName) == "string" and #def.DisplayName > 3, id .. " name")
		check(cyrillic(def.RU), id .. " Russian name")
		check(#def.Description > 10 and cyrillic(def.DescriptionRU), id .. " description")
		check(def.CanDropFromRoulette == false, id .. " roulette")
	end
	check(n == 15, "expected 15 finds")
	local events = 0
	for _, def in Items do
		if def.Event == "Underyard2026" then
			events += 1
			check(FINDS[def.Id], "unexpected Underyard find " .. def.Id)
		end
	end
	check(events == 15, "event finds " .. events)
end)

test("showcase tier of every find matches the design (5 Common, 5 Rare, 3 Epic, 2 Legendary)", function()
	local counts = {}
	for id, tier in FINDS do
		local rarity = Showcase.Rarity(id)
		check(rarity == tier, id .. " shows as " .. rarity .. ", design says " .. tier)
		check(Items[id].Showcase == tier, id .. " Showcase field")
		counts[tier] = (counts[tier] or 0) + 1
	end
	check(counts.Common == 5 and counts.Rare == 5 and counts.Epic == 3 and counts.Legendary == 2, "tier counts")
	-- sale prices rise with the tier (a standard-weight, unmutated find)
	local function price(id)
		local def = Items[id]
		return (Valuation.Price({ ItemId = id, WeightKg = def.BaseWeightKg, TierIndex = 3, Mutation = "NORMAL" }))
	end
	local low = { Common = math.huge, Rare = math.huge, Epic = math.huge, Legendary = math.huge }
	local high = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }
	for id, tier in FINDS do
		local p = price(id)
		check(p > 1000, id .. " price " .. p)
		low[tier] = math.min(low[tier], p)
		high[tier] = math.max(high[tier], p)
	end
	check(high.Common < low.Rare and high.Rare < low.Epic and high.Epic < low.Legendary, "prices rise with the tier")
	check(high.Legendary < 1.2e6, "legendary price stays below the depth soft cap " .. high.Legendary)
end)

test("find models: a Forge recipe per find within 80 parts, on the ground, readable size, showcase attributes", function()
	for id in FINDS do
		check(ItemModels.Has(id), "no model " .. id)
		local model = ItemModels.Build(id, 0)
		check(model, "model failed " .. id)
		local parts = model:GetAttribute("ForgeParts")
		check(parts > 12 and parts <= FIND_BUDGET, id .. " has " .. tostring(parts) .. " parts")
		local lod1 = ItemModels.Build(id, 1)
		check(lod1 and lod1:GetAttribute("ForgeParts") <= parts, id .. " Lod 1")
		local lo, hi = bounds(model)
		local size = hi - lo
		check(lo.Y > -0.2 and lo.Y < 0.15, id .. " rests on the ground (" .. lo.Y .. ")")
		check(size.Y >= 1.4 and size.Y <= 3.4, id .. " height " .. size.Y)
		check(size.X <= 3.2 and size.Z <= 3.2, id .. " footprint " .. tostring(size))
		local aura = model:GetAttribute("ShowcaseAura")
		check(typeof(aura) == "Color3", id .. " ShowcaseAura")
		local motif = model:GetAttribute("ShowcaseMotif")
		check(motif == nil or motif == "Wisp" or motif == "Ember", id .. " motif " .. tostring(motif))
		local glints, accents = 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				if d:GetAttribute("ShowcaseGlint") == true then
					glints += 1
				end
				if d:GetAttribute("ItemAccent") == true then
					accents += 1
				end
				check(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, id .. " part is interactive")
			elseif d:IsA("Light") then
				error(id .. " find models carry no lights")
			end
		end
		check(glints >= 1 and glints <= 3, id .. " glints " .. glints)
		check(accents >= 1, id .. " has no accent parts for mutations")
	end
end)

test("Russian for every find name (also in capitals) and description", function()
	for id in FINDS do
		local def = Items[id]
		check(UnderyardItems.Exact[def.DisplayName] == def.RU, id .. " name")
		local upper = UnderyardItems.Exact[string.upper(def.DisplayName)]
		check(cyrillic(upper) and upper == UnderyardItems.Upper(def.RU), id .. " capital name " .. tostring(upper))
		for _, code in utf8.codes(upper) do
			check(not (code >= 0x0430 and code <= 0x044F) and not (code >= 0x61 and code <= 0x7A), id .. " capital name has lower case")
		end
		check(UnderyardItems.Exact[def.Description] == def.DescriptionRU, id .. " description")
	end
end)

print(string.format("underyard_cosmetics: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("underyard_cosmetics tests failed")
end
