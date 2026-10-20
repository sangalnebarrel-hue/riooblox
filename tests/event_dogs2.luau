--!nocheck
-- THE UNDERYARD event dogs H09-H16 (WP-K1, DESIGN §9.8): lune run tests/event_dogs2.luau
-- Runs the real modules from src/:
--   * DogDefinitions: the eight rows (Index 209-216, EventDex "Underyard2026", EventIndex 9..16, EventCode H09..H16,
--     ranks, ability ids), the generalised event post-loop (flags, prices, no First Edition) for both event dexes;
--   * Localization.HalloweenDogs2: Russian for every name / signature / arrival line, no key repeated elsewhere;
--   * SecretArrivalConfig + SecretArrivals Dogs/Mega HW_HollowKing;
--   * Models.EventDogs2 built in Lune through tools/sim.luau: the rig contract of Models.EventDogs (bones, part
--     binding, paws lowest, sizes, lights, FX hooks), every clip (shape, seams, joins, serialisation, posed sanity);
--   * the baked assets of a built place (DOGROTS_PLACE, else build/DOGROTS_HALLOWEEN_PART2_THE_UNDERYARD.rbxl when
--     check.sh just built it, else the base place baked here by tools/edits/30_dogs2.luau, twice: idempotent), and the
--     real ReplicatedStorage.DogAnimationPlayer resolving and decoding their dig chains from that place, and playing
--     every clip on a table mirror of each baked template (parts must land where the generated clips put them).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("../tools/sim")
local L = require("./lib/economy_env")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local Config = L.Require("ReplicatedStorage.DogEconomy.Config")
local Defs = L.Require("ReplicatedStorage.DogEconomy.DogDefinitions")
local Arrivals = L.Require("ReplicatedStorage.SecretArrivalConfig")

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
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

local IDS = { "HW_BellPup", "HW_CandleCorgi", "HW_MourningShiba", "HW_CoffinPug", "HW_MothHound", "HW_Bridehound", "HW_BellkeeperWolf", "HW_HollowKing" }
local RANKS = { 2, 3, 3, 4, 4, 5, 5, 6 }
local ABILITIES = { "EchoEar", "Candlelight", "MourningVeil", "CoffinSense", "MothSwarm", "EternalVow", "ResonantHowl", "HollowCrown" }
local NAMES = { "Bell Pup", "Candle Corgi", "Mourning Shiba", "Coffin Pug", "Moth Hound", "Bridehound", "Bellkeeper Wolf", "Hollow King" }
local CHAPTER1 = { "HW_PumpkinPup", "HW_SheetShiba", "HW_BoneCorgi", "HW_Frankenpug", "HW_BatDachshund", "HW_PlaguePug", "HW_HeadlessHound", "HW_EclipseDog" }

---------------------------------------------------------------------------------------------------------------------
-- definitions
---------------------------------------------------------------------------------------------------------------------
test("eight Underyard rows: Index 209-216, EventDex Underyard2026, EventIndex 9..16, codes, ranks, abilities", function()
	for i, id in ipairs(IDS) do
		local d = Defs[id]
		truthy(d, id .. " missing")
		eq(d.Index, 208 + i, id .. " Index")
		eq(d.EventDex, "Underyard2026", id .. " EventDex")
		eq(d.EventIndex, 8 + i, id .. " EventIndex")
		eq(d.EventCode, string.format("H%02d", 8 + i), id .. " EventCode")
		eq(d.Rank, RANKS[i], id .. " Rank")
		eq(d.Ability, ABILITIES[i], id .. " Ability")
		eq(d.DisplayName, NAMES[i], id .. " DisplayName")
		eq(d.VisualAsset, id, id .. " VisualAsset")
		eq(d.Acquisition, "Event", id .. " Acquisition")
		eq(d.MuseumExcluded, true, id .. " MuseumExcluded")
		eq(d.Tags[1], "Halloween", id .. " first tag (Set)")
		truthy(type(d.Signature) == "string" and #d.Signature > 20, id .. " Signature")
	end
end)

test("indices and ids are unique across the whole roster", function()
	local byIndex = {}
	for id, d in pairs(Defs) do
		truthy(byIndex[d.Index] == nil, "Index " .. d.Index .. " used by " .. tostring(byIndex[d.Index]) .. " and " .. id)
		byIndex[d.Index] = id
		eq(d.Id, id, "key / Id")
	end
end)

test("EventDex grouping: two dexes of eight, contiguous EventIndex per dex, codes follow the index", function()
	local groups = {}
	for id, d in pairs(Defs) do
		if d.EventDex then
			groups[d.EventDex] = groups[d.EventDex] or {}
			table.insert(groups[d.EventDex], d)
		end
	end
	eq(#(groups.BuriedMoon2026 or {}), 8, "BuriedMoon2026 dogs")
	eq(#(groups.Underyard2026 or {}), 8, "Underyard2026 dogs")
	for dex, list in pairs(groups) do
		table.sort(list, function(a, b)
			return a.EventIndex < b.EventIndex
		end)
		local first = dex == "Underyard2026" and 9 or 1
		for i, d in ipairs(list) do
			eq(d.EventIndex, first + i - 1, dex .. " EventIndex of " .. d.Id)
			eq(d.EventCode, string.format("H%02d", d.EventIndex), d.Id .. " code")
		end
	end
	for i, id in ipairs(CHAPTER1) do
		eq(Defs[id].EventDex, "BuriedMoon2026", id .. " keeps its dex")
		eq(Defs[id].EventIndex, i, id .. " keeps its index")
	end
end)

test("event post-loop applies to every EventDex: event-only flags, rank prices, no First Edition, names", function()
	for id, d in pairs(Defs) do
		if d.EventDex then
			eq(d.CanSpawnOnLine, false, id .. " line")
			eq(d.CanDropFromLuckyBlock, false, id .. " lucky block")
			eq(d.CanDropFromRoulette, false, id .. " roulette")
			eq(d.LineWeight, nil, id .. " line weight")
			eq(d.LinePrice, nil, id .. " line price")
			eq(d.FirstEditionLimit, 0, id .. " first edition")
			eq(d.MinLayer, 1, id .. " min layer")
			eq(d.BasePrice, Config.Prices[d.Rank], id .. " base price")
			eq(d.Price, d.BasePrice, id .. " price")
			eq(d.Rarity, Config.Rarities[d.Rank], id .. " rarity")
			eq(d.Available, true, id .. " available")
			eq(d.SupplyType, "Permanent", id .. " supply")
		end
	end
	for _, id in ipairs(IDS) do
		eq(Defs[id].EventName, "THE UNDERYARD", id .. " EventName")
		eq(Defs[id].AcquisitionDescription, "Event dog · THE UNDERYARD 2026", id .. " description")
	end
	for _, id in ipairs(CHAPTER1) do
		eq(Defs[id].EventName, "NIGHT OF THE BURIED MOON", id .. " EventName")
		eq(Defs[id].AcquisitionDescription, "Event dog · NIGHT OF THE BURIED MOON 2026", id .. " description")
	end
	-- an ordinary rank-4 dog still gets its First Edition run (the post-loop only touches event dogs)
	local standard = 0
	for _, d in pairs(Defs) do
		if not d.EventDex and d.Acquisition == "Standard" and d.Rank >= 4 then
			eq(d.FirstEditionLimit, 5000, d.Id .. " standard first edition")
			standard += 1
		end
	end
	truthy(standard > 10, "standard rank 4+ dogs found: " .. standard)
end)

test("the animations test can parse every row (one row per line, Id and VisualAsset on it)", function()
	local found = {}
	for row in fs.readFile("src/ReplicatedStorage/DogEconomy/DogDefinitions.luau"):gmatch("{Index=%d+,[^\n]*") do
		local id, visual = row:match('Id="([^"]+)"'), row:match('VisualAsset="([^"]+)"')
		if id then
			found[id] = visual
		end
	end
	for _, id in ipairs(IDS) do
		eq(found[id], id, id .. " parsed")
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- localization
---------------------------------------------------------------------------------------------------------------------
local Loc = L.Require("ReplicatedStorage.Localization.HalloweenDogs2")
local function russian(s)
	return type(s) == "string" and s:find("[\208\209]") ~= nil
end

test("HalloweenDogs2 has Russian for every name, signature and Hollow King arrival line", function()
	for _, id in ipairs(IDS) do
		truthy(russian(Loc.Exact[Defs[id].DisplayName]), id .. " name")
		truthy(russian(Loc.Exact[Defs[id].Signature]), id .. " signature: " .. Defs[id].Signature)
	end
	truthy(russian(Loc.Exact[Defs.HW_BellPup.AcquisitionDescription]), "acquisition description")
	local a = Arrivals.Dogs.HW_HollowKing
	truthy(russian(Loc.Exact[a.Title]), "arrival title")
	for _, w in ipairs(a.Whispers) do
		truthy(russian(Loc.Exact[w[2]]), "whisper " .. w[2])
	end
	truthy(russian(Loc.Exact["✦  THE HOLLOW KING RISES  ✦"]), "kicker")
	for _, venue in ipairs({ "FROM THE BLACK COFFIN", "BEHIND A CROOKED DOOR", "AFTER THE LAST BARK", "IN THE UNDERYARD" }) do
		truthy(russian(Loc.Exact[venue]), venue)
	end
	-- the player-named kicker goes through the pattern
	local rule = Loc.Patterns[1]
	local out = string.gsub("✦  BARKLEY RAISED THE HOLLOW KING  ✦", rule[1], rule[2])
	eq(out, "✦  BARKLEY ПРОБУДИЛ ПОЛОГО КОРОЛЯ  ✦", "kicker pattern")
	for key, value in pairs(Loc.UI) do
		truthy(russian(value), "UI " .. key)
	end
	for key, value in pairs(Loc.Templates) do
		eq(select(2, string.gsub(key, "%%", "")), select(2, string.gsub(value, "%%", "")), "template placeholders " .. key)
	end
end)

test("no Exact key of HalloweenDogs2 repeats another Localization module or the AutoTranslate base dictionary", function()
	local base = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	local problems = {}
	for _, file in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		local name = file:gsub("%.luau$", "")
		if name ~= "HalloweenDogs2" then
			local ok, other = pcall(L.Require, "ReplicatedStorage.Localization." .. name)
			if ok and type(other) == "table" and type(other.Exact) == "table" then
				for key in pairs(Loc.Exact) do
					if other.Exact[key] ~= nil then
						table.insert(problems, key .. " also in " .. name)
					end
				end
			end
		end
	end
	for key in pairs(Loc.Exact) do
		if base:find('["' .. key .. '"]', 1, true) then
			table.insert(problems, key .. " also in the AutoTranslate base")
		end
	end
	eq(#problems, 0, table.concat(problems, "; "))
end)

---------------------------------------------------------------------------------------------------------------------
-- models and clips (Models.EventDogs2 through tools/sim.luau)
---------------------------------------------------------------------------------------------------------------------
local game = roblox.Instance.new("DataModel")
local RS = game:GetService("ReplicatedStorage")
local hwFolder = roblox.Instance.new("Folder")
hwFolder.Name = "Halloween"
hwFolder.Parent = RS
local modelsFolder = roblox.Instance.new("Folder")
modelsFolder.Name = "Models"
modelsFolder.Parent = hwFolder
for _, name in ipairs({ "EventDogs", "EventDogs2" }) do
	local m = roblox.Instance.new("ModuleScript")
	m.Name = name
	m.Source = fs.readFile("src/ReplicatedStorage/Halloween/Models/" .. name .. ".luau")
	m.Parent = modelsFolder
end
local sim = Sim.new(game)
local E2 = sim:require(modelsFolder.EventDogs2)
local E = E2.Base -- the EventDogs module EventDogs2 registered its specs in

test("EventDogs2 registers its specs in EventDogs without touching the Chapter I order", function()
	eq(#E2.Order, 8, "order")
	for i, id in ipairs(IDS) do
		eq(E2.Order[i], id, "order " .. i)
		truthy(E2.Spec(id) and E.Spec(id) == E2.Spec(id), id .. " registered")
		eq(E2.Spec(id).Code, string.format("H%02d", 8 + i), id .. " code")
	end
	eq(#E.Order, 8, "Chapter I order")
	for i, id in ipairs(CHAPTER1) do
		eq(E.Order[i], id, "Chapter I order " .. i)
	end
	eq(E2.Build("HW_PumpkinPup"), nil, "EventDogs2 builds only its own dogs")
	eq(E2.Clip("HW_PumpkinPup", "Idle"), nil, "EventDogs2 clips only its own dogs")
end)

local built = {}
for _, id in ipairs(IDS) do
	built[id] = E2.Build(id)
end

-- bone name -> Bone, bone name -> bind-pose world CFrame (Lune hands out a new userdata per access: key by name)
local function restOf(model)
	local bones, rest = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	local function world(b)
		if rest[b.Name] then
			return rest[b.Name]
		end
		local parent = b.Parent
		rest[b.Name] = (parent:IsA("Bone") and world(parent) or parent.CFrame) * b.CFrame
		return rest[b.Name]
	end
	for _, b in pairs(bones) do
		world(b)
	end
	return bones, rest
end

test("rig contract: attributes, RootPart, unique bones with pure-translation bind poses, paws lowest", function()
	for i, id in ipairs(IDS) do
		local model = built[id]
		truthy(model and model:IsA("Model"), id .. " model")
		eq(model.Name, id, id .. " name")
		eq(model.PrimaryPart and model.PrimaryPart.Name, "RootPart", id .. " PrimaryPart")
		eq(model:GetAttribute("DogId"), id, id .. " DogId")
		eq(model:GetAttribute("EventDex"), "Underyard2026", id .. " EventDex attr")
		eq(model:GetAttribute("EventCode"), string.format("H%02d", 8 + i), id .. " EventCode attr")
		eq(model:GetAttribute("DogPartRig"), true, id .. " DogPartRig")
		eq(model:GetAttribute("AnimationSource"), "DogAnimationClips", id .. " AnimationSource")
		eq(model:GetAttribute("AnimationBaseScale"), 1, id .. " AnimationBaseScale")
		eq(model:GetAttribute("SignatureClip"), E2.Spec(id).SignatureName, id .. " SignatureClip")
		truthy(model:FindFirstChild("AnimationController") and model.AnimationController:FindFirstChildOfClass("Animator"), id .. " animator")
		local names, low = {}, {}
		local root = model.RootPart:FindFirstChild("Root")
		truthy(root and root:IsA("Bone"), id .. " Root bone under RootPart")
		local bones, rest = restOf(model)
		for _, d in model:GetDescendants() do
			if d:IsA("Bone") then
				truthy(not names[d.Name], id .. " duplicate bone " .. d.Name)
				names[d.Name] = true
				local r = d.CFrame - d.CFrame.Position
				truthy((r.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-6 and (r.UpVector - Vector3.new(0, 1, 0)).Magnitude < 1e-6,
					id .. " bone " .. d.Name .. " is not a pure translation")
				if d.Parent:IsA("Bone") then
					table.insert(low, { Name = d.Name, Y = rest[d.Name].Position.Y })
				end
			end
		end
		for _, need in ipairs({ "Root", "Body", "Neck", "Head", "Jaw", "Ear_L", "Ear_R", "Tail", "Tail2", "TailTip", "Leg_FL", "Leg_FR", "Leg_BL",
			"Leg_BR", "Paw_FL", "Paw_FR", "Paw_BL", "Paw_BR" }) do
			truthy(bones[need], id .. " missing bone " .. need)
		end
		table.sort(low, function(a, b)
			return a.Y < b.Y
		end)
		for k = 1, 4 do
			truthy(low[k].Name:match("^Paw_"), id .. ": bone " .. low[k].Name .. " sits as low as the paws")
		end
		truthy(low[5].Y > low[4].Y + 0.05, id .. ": a bone sits level with the paws (" .. low[5].Name .. ")")
	end
end)

test("every part is bound to a bone (DogBone / DogBoneOffset reproduce its bind pose); unique names; counts", function()
	for _, id in ipairs(IDS) do
		local model = built[id]
		local bones, rest = restOf(model)
		local names, count = {}, 0
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "RootPart" then
				count += 1
				truthy(not names[p.Name], id .. " duplicate part name " .. p.Name)
				names[p.Name] = true
				local bone = bones[p:GetAttribute("DogBone")]
				truthy(bone, id .. " " .. p.Name .. " has no bone")
				local offset = p:GetAttribute("DogBoneOffset")
				truthy(typeof(offset) == "CFrame", id .. " " .. p.Name .. " offset")
				local cf = rest[bone.Name] * offset
				truthy((cf.Position - p.CFrame.Position).Magnitude < 1e-3, id .. " " .. p.Name .. " offset position")
				truthy(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery, id .. " " .. p.Name .. " physics flags")
			end
		end
		eq(model:GetAttribute("Parts"), count, id .. " Parts attribute")
		truthy(count >= 150 and count <= 420, id .. " part count " .. count)
	end
end)

test("sizes match the Chapter I dogs: feet on the ground, 4-6.6 studs tall, compact footprint", function()
	for _, id in ipairs(IDS) do
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, p in built[id]:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "RootPart" and p.Transparency < 1 then
				for x = -1, 1, 2 do
					for y = -1, 1, 2 do
						for z = -1, 1, 2 do
							local q = p.CFrame:PointToWorldSpace(p.Size * Vector3.new(x, y, z) / 2)
							lo, hi = lo:Min(q), hi:Max(q)
						end
					end
				end
			end
		end
		local size = hi - lo
		truthy(lo.Y > -0.05 and lo.Y < 0.12, id .. string.format(" feet at %.3f", lo.Y))
		truthy(size.Y >= 4.0 and size.Y <= 6.6, id .. string.format(" height %.2f", size.Y))
		truthy(size.X <= 4.4 and size.Z <= 7.8, id .. string.format(" footprint %.2f x %.2f", size.X, size.Z))
		truthy(math.abs(lo.X + hi.X) < 0.6, id .. " roughly symmetric")
	end
end)

test("lights are baked off (DogLight + SelfManagedFX), at most two; FX hooks use EventDogs recipes", function()
	for _, id in ipairs(IDS) do
		local lights, hooks = 0, 0
		for _, d in built[id]:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				eq(d.Enabled, false, id .. " light enabled")
				eq(d.Shadows, false, id .. " light shadows")
				eq(d:GetAttribute("DogLight"), true, id .. " DogLight")
				eq(d.Parent:GetAttribute("SelfManagedFX"), true, id .. " light part SelfManagedFX")
			elseif d:IsA("Attachment") and d:GetAttribute("HwFX") then
				hooks += 1
				truthy(d.Name:match("^HwFX_"), id .. " hook name " .. d.Name)
				truthy(E.FXRecipes[d:GetAttribute("HwFX")], id .. " unknown recipe " .. tostring(d:GetAttribute("HwFX")))
				eq(typeof(d:GetAttribute("HwFXColor")), "Color3", id .. " hook colour")
				eq(d:GetAttribute("SelfManagedFX"), true, id .. " hook SelfManagedFX")
			elseif d:IsA("ParticleEmitter") then
				error(id .. " template carries a ParticleEmitter")
			end
		end
		truthy(lights >= 1 and lights <= 2, id .. " lights " .. lights)
		truthy(hooks >= 1, id .. " hooks")
		eq(built[id]:GetAttribute("FXHooks"), hooks, id .. " FXHooks attribute")
	end
end)

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < 1e6
end
local function rowCF(row)
	return CFrame.new(row[1], row[2], row[3], row[4], row[5], row[6], row[7])
end

test("every clip: the shared clip set, durations, finite unit-quaternion frames, closed loops, signature copy", function()
	for _, id in ipairs(IDS) do
		local names = E2.ClipNamesFor(id)
		eq(#names, #E.ClipNames + 1, id .. " clip count")
		local bones = {}
		for _, b in ipairs(E2.BoneNames(id)) do
			bones[b] = true
		end
		for _, name in ipairs(names) do
			local clip = E2.Clip(id, name)
			truthy(clip, id .. "." .. name)
			eq(clip.fps, E.FPS, id .. "." .. name .. " fps")
			eq(clip.duration, E2.Duration(id, name), id .. "." .. name .. " duration")
			eq(clip.loop, E.IsLooped(name == E2.Spec(id).SignatureName and "Signature" or name), id .. "." .. name .. " loop")
			local frames = math.max(2, math.floor(clip.duration * clip.fps + 0.5) + 1)
			local moving = 0
			for bone, rows in pairs(clip.tracks) do
				truthy(bones[bone], id .. "." .. name .. " track for unknown bone " .. bone)
				eq(#rows, frames, id .. "." .. name .. "." .. bone .. " frames")
				for _, row in ipairs(rows) do
					eq(#row, 7, "row width")
					for _, v in ipairs(row) do
						truthy(finite(v), id .. "." .. name .. "." .. bone .. " non-finite value")
					end
					local q = math.sqrt(row[4] ^ 2 + row[5] ^ 2 + row[6] ^ 2 + row[7] ^ 2)
					truthy(math.abs(q - 1) < 1e-4, id .. "." .. name .. "." .. bone .. " quaternion length " .. q)
				end
				if clip.loop then
					local a, b = rows[1], rows[#rows]
					for k = 1, 7 do
						truthy(math.abs(a[k] - b[k]) < 1e-6, id .. "." .. name .. "." .. bone .. " loop seam is open")
					end
				end
				moving += 1
			end
			truthy(moving >= 4, id .. "." .. name .. " barely moves")
		end
		local sig, own = E2.Clip(id, "Signature"), E2.Clip(id, E2.Spec(id).SignatureName)
		eq(E2.Serialize(sig), E2.Serialize(own), id .. " signature copy")
		truthy(sig.duration >= 3 and sig.duration <= 4.2, id .. " signature length " .. sig.duration)
	end
end)

test("DigStart ends on the DigLoop's first pose and DigEnd starts there (seamless kennel chain)", function()
	for _, id in ipairs(IDS) do
		local start, loop, stop = E2.Clip(id, "DigStart"), E2.Clip(id, "DigLoop"), E2.Clip(id, "DigEnd")
		for bone, rows in pairs(loop.tracks) do
			local first = rows[1]
			local a = start.tracks[bone] and start.tracks[bone][#start.tracks[bone]] or { 0, 0, 0, 0, 0, 0, 1 }
			local b = stop.tracks[bone] and stop.tracks[bone][1] or { 0, 0, 0, 0, 0, 0, 1 }
			for k = 1, 7 do
				truthy(math.abs(a[k] - first[k]) < 2e-3, id .. " DigStart>DigLoop " .. bone)
				truthy(math.abs(b[k] - first[k]) < 2e-3, id .. " DigLoop>DigEnd " .. bone)
			end
		end
	end
end)

test("serialised clips load back to the same numbers", function()
	for _, id in ipairs(IDS) do
		for _, name in ipairs({ "Idle", "DigLoop", E2.Spec(id).SignatureName }) do
			local clip = E2.Clip(id, name)
			local back = luau.load(E2.Serialize(clip, E2.ClipHeader(id, name)), { debugName = id .. "." .. name })()
			eq(back.duration, clip.duration, "duration")
			eq(back.loop, clip.loop, "loop")
			eq(back.fps, clip.fps, "fps")
			for bone, rows in pairs(clip.tracks) do
				for f, row in ipairs(rows) do
					for k = 1, 7 do
						truthy(math.abs(back.tracks[bone][f][k] - row[k]) < 1e-4, id .. "." .. name .. " round trip")
					end
				end
			end
		end
	end
end)

-- pose a model with a clip frame (DogAnimationPlayer:ApplyParts math) and return its lowest point and spread
local function posed(model, clip, frame)
	local bones = restOf(model)
	local world = {}
	local function w(b)
		if world[b.Name] then
			return world[b.Name]
		end
		local parent = b.Parent
		local base = parent:IsA("Bone") and w(parent) or parent.CFrame
		local tr = CFrame.identity
		local rows = clip.tracks[b.Name]
		if rows then
			tr = rowCF(rows[math.min(frame, #rows)])
		end
		world[b.Name] = base * b.CFrame * tr
		return world[b.Name]
	end
	local lowest, far = math.huge, 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "RootPart" then
			local cf = w(bones[p:GetAttribute("DogBone")]) * p:GetAttribute("DogBoneOffset")
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						lowest = math.min(lowest, cf:PointToWorldSpace(p.Size * Vector3.new(x, y, z) / 2).Y)
					end
				end
			end
			far = math.max(far, (cf.Position - Vector3.new(0, 2.6, 0)).Magnitude)
		end
	end
	return lowest, far
end

test("posed sanity: nothing sinks through the floor or flies apart in any clip", function()
	for _, id in ipairs(IDS) do
		for _, name in ipairs(E2.ClipNamesFor(id)) do
			local clip = E2.Clip(id, name)
			local frames = 0
			for _, rows in pairs(clip.tracks) do
				frames = math.max(frames, #rows)
			end
			for f = 1, frames, 3 do
				local lowest, far = posed(built[id], clip, f)
				-- the dig clips may dip a paw (DogAnimationPlayer lifts the rig); everything else stays above ground
				local floor = (name == "DigLoop" or name == "DigStart" or name == "DigEnd") and -0.6 or -0.45
				truthy(lowest > floor, string.format("%s.%s frame %d sinks to %.2f", id, name, f, lowest))
				truthy(far < 8.5, string.format("%s.%s frame %d flies apart (%.2f)", id, name, f, far))
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- Secret arrival
---------------------------------------------------------------------------------------------------------------------
test("SecretArrivalConfig.HW_HollowKing plays its own clips inside the hold; arrival modules compile", function()
	local a = Arrivals.Dogs.HW_HollowKing
	truthy(a, "config entry")
	eq(a.Title, "HOLLOW KING", "title")
	eq(typeof(a.Color), "Color3", "colour")
	truthy(a.Hold >= 6 and a.Hold <= 10, "hold")
	truthy(a.MegaSeconds >= a.Hold + 10, "mega seconds")
	local names = {}
	for _, n in ipairs(E2.ClipNamesFor("HW_HollowKing")) do
		names[n] = true
	end
	local signature = false
	for _, step in ipairs(a.Clips) do
		truthy(names[step[2]], "unknown clip " .. tostring(step[2]))
		truthy(step[1] >= 0 and step[1] < a.Hold, "clip time " .. step[1])
		if step[2] == "Coronation" then
			signature = true
			truthy(step[1] + E2.Duration("HW_HollowKing", "Coronation") <= a.Hold + 0.05, "Coronation ends inside the hold")
		end
	end
	truthy(signature, "the arrival plays the signature")
	for _, w in ipairs(a.Whispers) do
		truthy(w[1] < a.Hold, "whisper time")
	end
	for _, file in ipairs({ "src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Dogs/HW_HollowKing.luau",
		"src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Mega/HW_HollowKing.luau" }) do
		local ok, err = pcall(luau.compile, fs.readFile(file))
		truthy(ok, file .. ": " .. tostring(err))
	end
	truthy(fs.readFile("src/StarterPlayer/StarterPlayerScripts/SecretArrivals/Mega.luau"):find("Coffin='FROM THE BLACK COFFIN'", 1, true), "Mega venue")
end)

---------------------------------------------------------------------------------------------------------------------
-- baked assets in a built place
---------------------------------------------------------------------------------------------------------------------
local placePath = process.env.DOGROTS_PLACE
	or (fs.isFile("build/DOGROTS_HALLOWEEN_PART2_THE_UNDERYARD.rbxl") and "build/DOGROTS_HALLOWEEN_PART2_THE_UNDERYARD.rbxl" or nil)
local place, bakeReports
if placePath then
	place = roblox.deserializePlace(fs.readFile(placePath))
else
	-- the base place + this branch's model modules, baked twice by the real edit (the second run must replace, not add)
	place = roblox.deserializePlace(fs.readFile("place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl"))
	local models = place:GetService("ReplicatedStorage").Halloween.Models
	for _, name in ipairs({ "EventDogs", "EventDogs2" }) do
		local m = models:FindFirstChild(name)
		if not m then
			m = roblox.Instance.new("ModuleScript")
			m.Name = name
			m.Parent = models
		end
		m.Source = fs.readFile("src/ReplicatedStorage/Halloween/Models/" .. name .. ".luau")
	end
	local edit = luau.load(fs.readFile("tools/edits/30_dogs2.luau"), { debugName = "30_dogs2.luau" })()
	bakeReports = {}
	for run = 1, 2 do
		local report = {}
		edit({ game = place, sim = Sim.new(place), report = report, roblox = roblox, fs = fs, serde = serde })
		bakeReports[run] = report
	end
	placePath = "base place baked in memory"
end
local placeRS = place:GetService("ReplicatedStorage")
local placeSS = place:GetService("ServerStorage")
local library = placeRS:FindFirstChild("DogAnimationClips")

test("baked: templates (AssetReady), menu models and clip folders exist once each [" .. placePath .. "]", function()
	if bakeReports then
		eq(#bakeReports[1].Dogs, 8, "report")
		eq(bakeReports[1].Parts, bakeReports[2].Parts, "same output on the second run")
	end
	for _, id in ipairs(IDS) do
		for _, parent in ipairs({ placeSS.DogTemplates, placeRS.MenuModels, library }) do
			local n = 0
			for _, c in ipairs(parent:GetChildren()) do
				if c.Name == id then
					n += 1
				end
			end
			eq(n, 1, id .. " copies in " .. parent.Name)
		end
		-- Runtime.Engine.AssetReady: DogTemplates[def.VisualAsset] is a Model with a RootPart
		local template = placeSS.DogTemplates:FindFirstChild(Defs[id].VisualAsset)
		truthy(template and template:IsA("Model") and template:FindFirstChild("RootPart", true), id .. " AssetReady")
		eq(template.PrimaryPart and template.PrimaryPart.Name, "RootPart", id .. " template PrimaryPart")
		eq(template:GetAttribute("Parts"), built[id]:GetAttribute("Parts"), id .. " template matches the builder")
		local menu = placeRS.MenuModels[id]
		eq(menu:GetAttribute("Parts"), template:GetAttribute("Parts"), id .. " menu model")
		eq(menu:GetAttribute("EventDex"), "Underyard2026", id .. " menu EventDex")
	end
	for _, id in ipairs(CHAPTER1) do
		truthy(placeSS.DogTemplates:FindFirstChild(id) and placeRS.MenuModels:FindFirstChild(id) and library:FindFirstChild(id), id .. " still baked")
	end
end)

test("baked clip ModuleScripts: one per clip, role attributes, header, decode to the generated clips", function()
	for _, id in ipairs(IDS) do
		local folder = library[id]
		eq(folder.ClassName, "Folder", id .. " clip folder")
		eq(folder:GetAttribute("IdleClip"), "Idle", id .. " IdleClip")
		eq(folder:GetAttribute("WalkClip"), "Walk", id .. " WalkClip")
		eq(folder:GetAttribute("WorkClip"), "DigLoop", id .. " WorkClip")
		eq(folder:GetAttribute("SignatureClip"), E2.Spec(id).SignatureName, id .. " SignatureClip")
		local names = E2.ClipNamesFor(id)
		eq(#folder:GetChildren(), #names, id .. " clip modules")
		for _, name in ipairs(names) do
			local m = folder:FindFirstChild(name)
			truthy(m and m:IsA("ModuleScript"), id .. "." .. name .. " module")
			truthy(m.Source:sub(1, #E2.ClipHeader(id, name)) == E2.ClipHeader(id, name), id .. "." .. name .. " header")
			local data = luau.load(m.Source, { debugName = id .. "." .. name })()
			local clip = E2.Clip(id, name)
			eq(data.duration, clip.duration, id .. "." .. name .. " duration")
			eq(data.loop, clip.loop, id .. "." .. name .. " loop")
		end
	end
end)

-- the real DogAnimationPlayer over the place's clip library (services stubbed like tests/animations.luau)
local clipCache = {}
local function runClip(m)
	if clipCache[m] == nil then
		clipCache[m] = luau.load(m.Source, { debugName = m.Name })()
	end
	return clipCache[m]
end
local Profiles = luau.load(fs.readFile("src/ReplicatedStorage/DogDigProfiles.luau"), { debugName = "DogDigProfiles" })()
local marker = { Gait = {}, Profiles = {}, Economy = {}, Definitions = {} }
marker.Economy.WaitForChild = function()
	return marker.Definitions
end
local replicated = {
	WaitForChild = function(_, name)
		if name == "DogAnimationClips" then
			return library
		elseif name == "DogWalkGait" then
			return marker.Gait
		elseif name == "DogDigProfiles" then
			return marker.Profiles
		elseif name == "DogEconomy" then
			return marker.Economy
		end
		error("unexpected WaitForChild " .. tostring(name))
	end,
	FindFirstChild = function()
		return nil
	end,
}
local warnings = {}
local clock = { Now = 1000 } -- the player's server clock (Play reads it; Step gets explicit times)
local Player = luau.load(fs.readFile("src/ReplicatedStorage/DogAnimationPlayer.luau"), { debugName = "DogAnimationPlayer", environment = setmetatable({
	game = { GetService = function()
		return replicated
	end },
	workspace = { GetServerTimeNow = function()
		return clock.Now
	end },
	require = function(x)
		if x == marker.Gait then
			return { new = function()
				return nil
			end }
		elseif x == marker.Profiles then
			return Profiles
		elseif x == marker.Definitions then
			return Defs
		end
		return runClip(x)
	end,
	warn = function(...)
		table.insert(warnings, table.concat({ ... }, " "))
	end,
	Vector3 = Vector3,
	CFrame = CFrame,
}, { __index = _G }) })()

test("DogAnimationPlayer resolves and decodes each dig chain; loops close, accents fit, no squeezing", function()
	for _, id in ipairs(IDS) do
		local chain = Player.Chain(id)
		truthy(chain, id .. " chain")
		eq(chain.Idle, "Idle", id .. " idle")
		eq(chain.Loop, "DigLoop", id .. " loop")
		eq(chain.Start and chain.Start[1], "DigStart", id .. " start")
		eq(chain.End and chain.End[1], "DigEnd", id .. " end")
		eq(chain.Accent and chain.Accent[1], "DigFind", id .. " accent")
		eq(Player.ResolveName(id, "Walk"), "Walk", id .. " walk")
		eq(Player.DogIdFor(Defs[id].VisualAsset), id, id .. " VisualAsset -> Id")
		for _, name in ipairs(E2.ClipNamesFor(id)) do
			local clip = Player.LoadClip(id, name)
			truthy(clip, id .. "." .. name .. " does not decode")
			if clip.Looped then
				truthy(clip.SeamClosed, id .. "." .. name .. " seam")
			end
		end
		local accent = Player.SequenceDuration(id, chain.Accent)
		truthy(accent and accent <= Profiles.MinCycle, id .. " accent " .. tostring(accent))
		eq(Player.GetWorkSpeed(id, chain.Loop, Profiles.MinCycle), 1, id .. " loop speed")
	end
	eq(#warnings, 0, "player warnings: " .. table.concat(warnings, "; "))
end)

test("the accent returns to the loop and the loop ends into DigEnd without a pop (core bones)", function()
	local function gap(names, a, b)
		local worst = 0
		for _, name in ipairs(names) do
			local x, y = a[name] or CFrame.identity, b[name] or CFrame.identity
			local _, angle = (x:Inverse() * y):ToAxisAngle()
			angle = math.abs(angle) % (2 * math.pi)
			worst = math.max(worst, if angle > math.pi then 2 * math.pi - angle else angle)
		end
		return math.deg(worst)
	end
	local function pose(clip, frame)
		local p = {}
		for name, frames in pairs(clip.Tracks) do
			p[name] = frames[math.clamp(frame, 1, #frames)]
		end
		return p
	end
	for _, id in ipairs(IDS) do
		local find, loop, stop = Player.LoadClip(id, "DigFind"), Player.LoadClip(id, "DigLoop"), Player.LoadClip(id, "DigEnd")
		local phase = Player.MatchPhase(setmetatable({}, Player), loop, {}, find)
		local frame = math.floor(phase * loop.FPS + 0.5) + 1
		local g = gap(Player.CoreNames(loop), pose(find, find.Frames), pose(loop, frame))
		truthy(g <= 45, string.format("%s accent>loop %.0f deg", id, g))
		local g2 = gap(Player.CoreNames(stop), pose(loop, loop.Frames), pose(stop, 1))
		truthy(g2 <= 12, string.format("%s loop>end %.0f deg", id, g2))
	end
end)

-- A table mirror of a baked template that the real player can drive in Lune (Lune instances have no Transform
-- solving or signals): bones keep CFrame + Transform, parts CFrame + Anchored, the model answers the few methods
-- DogAnimationPlayer calls on a rig outside the world (GetDescendants, GetAttribute, GetScale, GetPivot, ...).
local FakeMethods = {}
function FakeMethods:IsA(class)
	if class == "BasePart" then
		return self.IsPart
	elseif class == "Light" then
		return self.IsLight
	end
	return self.ClassName == class
end
function FakeMethods:GetAttribute(name)
	return self.Attributes[name]
end
function FakeMethods:GetDescendants()
	return self.Descendants
end
function FakeMethods:GetScale()
	return 1
end
function FakeMethods:GetPivot()
	return self.PrimaryPart.CFrame
end
function FakeMethods:IsDescendantOf()
	return false
end
local fakeSignal = { Connect = function()
	return { Disconnect = function() end }
end }
local FakeMeta = { __index = function(self, key)
	if key == "TransformedWorldCFrame" or key == "WorldCFrame" then
		local parent = rawget(self, "Parent")
		local base = if parent.ClassName == "Bone" then parent.TransformedWorldCFrame else parent.CFrame
		return base * rawget(self, "CFrame") * (if key == "WorldCFrame" then CFrame.identity else rawget(self, "Transform"))
	elseif key == "DescendantAdded" or key == "DescendantRemoving" then
		return fakeSignal
	end
	return FakeMethods[key]
end }

local function fakeRig(template)
	local model = setmetatable({ Name = template.Name, ClassName = "Model", Attributes = template:GetAttributes(), Descendants = {},
		Parts = {}, Bones = {}, Rest = {} }, FakeMeta)
	local function mirror(source, parent)
		for _, child in ipairs(source:GetChildren()) do
			local node = setmetatable({ Name = child.Name, ClassName = child.ClassName, Attributes = child:GetAttributes(), Parent = parent,
				IsPart = child:IsA("BasePart"), IsLight = child:IsA("Light") }, FakeMeta)
			if node.IsPart then
				node.CFrame, node.Anchored = child.CFrame, child.Anchored
				model.Rest[node] = child.CFrame
				if child.Name == "RootPart" then
					model.PrimaryPart = node
				else
					table.insert(model.Parts, node)
				end
			elseif child:IsA("Bone") then
				node.CFrame, node.Transform = child.CFrame, CFrame.identity
				model.Bones[child.Name] = node
			end
			table.insert(model.Descendants, node)
			mirror(child, node)
		end
	end
	mirror(template, model)
	return model
end

-- every part where the generated clip puts it at `frame` (+ a vertical rig lift)
local function expectedFrames(model, clip, frame, lift)
	local world = {}
	local function w(bone)
		if world[bone.Name] then
			return world[bone.Name]
		end
		local parent = bone.Parent
		local base = if parent.ClassName == "Bone" then w(parent) else parent.CFrame + Vector3.new(0, lift, 0)
		local rows = clip.tracks[bone.Name]
		world[bone.Name] = base * bone.CFrame * (if rows then rowCF(rows[math.min(frame, #rows)]) else CFrame.identity)
		return world[bone.Name]
	end
	local out = {}
	for _, part in ipairs(model.Parts) do
		out[part] = w(model.Bones[part.Attributes.DogBone]) * part.Attributes.DogBoneOffset
	end
	return out
end

local function worstGap(model, want)
	local pos, rot = 0, 0
	for _, part in ipairs(model.Parts) do
		local a, b = part.CFrame, want[part]
		pos = math.max(pos, (a.Position - b.Position).Magnitude)
		rot = math.max(rot, (a.LookVector - b.LookVector).Magnitude, (a.UpVector - b.UpVector).Magnitude)
	end
	return pos, rot
end

test("DogAnimationPlayer plays every clip on a baked rig: parts land where the generated clips put them", function()
	for _, id in ipairs(IDS) do
		local template = placeSS.DogTemplates[Defs[id].VisualAsset]
		local model = fakeRig(template)
		local player = Player.new(model)
		eq(player.DogId, id, id .. " player id")
		eq(#player.RigParts, #model.Parts, id .. " every part follows a bone")
		eq(#player.RigParts, template:GetAttribute("Parts"), id .. " Parts attribute")
		local lights = 0
		for _, d in ipairs(model.Descendants) do
			if d.IsLight then
				lights += 1
			end
		end
		eq(#player.RigLights, lights, id .. " baked lights collected")
		local size = template:GetAttribute("VisualSize")
		local height = if typeof(size) == "Vector3" then size.Y else 5
		for _, name in ipairs(E2.ClipNamesFor(id)) do
			local clip = E2.Clip(id, name)
			local frames = 0
			for _, rows in pairs(clip.tracks) do
				frames = math.max(frames, #rows)
			end
			clock.Now += 10
			local start = clock.Now
			truthy(player:Play(name, { FadeTime = 0 }), id .. " plays " .. name)
			eq(player.Name, name, id .. " playing " .. name)
			eq(player.Looped, clip.loop, id .. "." .. name .. " looped")
			if player.Lift then
				-- only the dig chain may lift the rig, and never by more than a quarter of its height
				truthy(name:match("^Dig"), id .. "." .. name .. " is lifted")
				for _, v in ipairs(player.Lift) do
					truthy(v >= 0 and v <= height * 0.25 + 1e-6, id .. "." .. name .. " lift " .. v)
				end
			end
			local function check(k, at)
				player:Step(at)
				local lift = player.Lift and player.Lift[math.min(k, #player.Lift)] or 0
				local pos, rot = worstGap(model, expectedFrames(model, clip, k, lift))
				truthy(pos < 5e-3 and rot < 5e-3, string.format("%s.%s frame %d: parts off by %.4f studs / %.4f", id, name, k, pos, rot))
			end
			for k = 1, frames, 5 do
				check(k, start + (k - 1) / clip.fps)
			end
			check(frames, start + (frames - 1) / clip.fps)
			if clip.loop then
				-- a loop wraps onto its own frames (no recovery blend: the seam is closed)
				eq(player.Recovery, 0, id .. "." .. name .. " recovery")
				check(4, start + clip.duration + 3 / clip.fps)
				truthy(not player:IsDone(start + clip.duration * 3), id .. "." .. name .. " loop never ends")
			else
				truthy(not player:IsDone(start + clip.duration - 0.02), id .. "." .. name .. " ends early")
				truthy(player:IsDone(start + clip.duration + 0.02), id .. "." .. name .. " never ends")
				-- a finished one-shot holds its authored last frame
				check(frames, start + clip.duration + 1)
			end
		end
		-- the kennel chain queues through DigStart into the DigLoop at the authored join
		clock.Now += 10
		local start = clock.Now
		truthy(player:Play("DigStart", { FadeTime = 0, Next = { "DigLoop", { FadeTime = 0 } } }), id .. " DigStart")
		local d = E2.Duration(id, "DigStart")
		player:Step(start + d * 0.5)
		eq(player.Name, "DigStart", id .. " still starting")
		player:Step(start + d + 0.001)
		eq(player.Name, "DigLoop", id .. " queued DigLoop")
		-- Stop puts every part back on its bind pose (the baked template)
		player:Stop()
		local worst = 0
		for _, part in ipairs(model.Parts) do
			worst = math.max(worst, (part.CFrame.Position - model.Rest[part].Position).Magnitude)
		end
		truthy(worst < 1e-3, string.format("%s rest pose off by %.4f", id, worst))
		player:Destroy()
	end
	eq(#warnings, 0, "player warnings: " .. table.concat(warnings, "; "))
end)

print(string.format("event_dogs2: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("event_dogs2 tests failed")
end
