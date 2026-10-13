--!nocheck
-- DOG RUSH rework (docs/DOG_RUSH.md): lune run tests/dog_rush.luau
-- Runs the real modules from src/ (tests/lib/economy_env.luau): the shared rules
-- (WorldEvents.DogRush: routes, clock-driven packs, budgets, pup spawn points, rewards), the saved
-- progress (Economy.Features.DogRush: per-event cap, chests 3 / 6 / 10 exactly once, lifetime counter,
-- old and new profiles), the DOG_RUSH definition, the pup model and the DOG WRANGLER title tiers.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Vector3, Color3 = roblox.Vector3, roblox.Color3
local L = require("./lib/economy_env")
local Rush = L.Require("ReplicatedStorage.WorldEvents.DogRush")
local Defs = L.Require("ReplicatedStorage.WorldEvents.WorldEventDefinitions")
local Config = L.Require("ReplicatedStorage.WorldEvents.WorldEventConfig")
local Objects = L.Require("ReplicatedStorage.WorldEvents.WorldEventObjects")
local Pricing = L.Require("ReplicatedStorage.DogEconomy.BoostPricing")
local EconomyConfig = L.Require("ReplicatedStorage.DogEconomy.Config")
local Titles = L.Require("ReplicatedStorage.DogEconomy.TitleDefinitions")
local R = L.Require("ServerScriptService.Economy.Rules")
local Feature = L.Require("ServerScriptService.Economy.Features.DogRush")
local TitleFeature = L.Require("ServerScriptService.Economy.Features.Titles")

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
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end
local function near(a, b, tolerance, msg)
	if math.abs(a - b) > tolerance then error((msg or "") .. string.format(" expected %.6g ±%.3g got %.6g", b, tolerance, a), 2) end
end
local function truthy(v, msg)
	if not v then error(msg or "expected truthy", 2) end
end
local function refused(fn, needle)
	local ok, err = pcall(fn)
	if ok then error("expected a refusal" .. (needle and (" (" .. needle .. ")") or ""), 2) end
	if needle and not string.find(tostring(err), needle, 1, true) then error("wrong refusal: " .. tostring(err), 2) end
	return tostring(err)
end
local function seeded(seed)
	local state = seed or 7
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

local NOW = 1760000000
L.Time = NOW
local nextUid = 5000
local function profile()
	nextUid += 1
	local p = R.Profile(nextUid, NOW)
	return R.Normalize(p, nextUid, NOW)
end
local GEN = "4242:DOG_RUSH"

-- Routes -----------------------------------------------------------------------------------------
test("routes: closed loops on the real streets (boulevard, DOG EXPRESS lanes, south loop)", function()
	eq(#Rush.RouteList, 2)
	for _, route in ipairs(Rush.RouteList) do
		truthy(route.Count >= 100 and route.Length > 300, "route size " .. route.Id)
		near(route.StepLength, Rush.Step, 0.2, "even samples")
		for i = 1, route.Count do
			local x, z = route.X[i], route.Z[i]
			-- Inside the street corridor: X -29..29 (boulevard -18..18, lanes ±23..29), Z 160..740.
			truthy(math.abs(x) <= 29 and z >= 160 and z <= 740, string.format("on the street %s #%d (%.1f, %.1f)", route.Id, i, x, z))
			eq(route.Y[i], Rush.StreetY, "precomputed street height")
			near(math.sqrt(route.TX[i] ^ 2 + route.TZ[i] ^ 2), 1, 1e-6, "unit heading")
			local j = i % route.Count + 1
			local d = math.sqrt((route.X[j] - x) ^ 2 + (route.Z[j] - z) ^ 2)
			truthy(d <= Rush.Step * 1.6, "continuous " .. route.Id .. " #" .. i .. " " .. d)
		end
	end
	-- The outer loop runs on both DOG EXPRESS lanes, the inner one on the open south half of the boulevard.
	local outer, inner = Rush.Route.Outer, Rush.Route.Inner
	local west, east = 0, 0
	for i = 1, outer.Count do
		if math.abs(outer.X[i] + 26) < 0.5 then west += 1 end
		if math.abs(outer.X[i] - 26) < 0.5 then east += 1 end
	end
	truthy(west > 200 and east > 200, "both lanes used")
	for i = 1, inner.Count do
		truthy(math.abs(inner.X[i]) <= 18 and inner.Z[i] >= 410, "inner loop on the boulevard, south of the arch")
	end
end)

test("routes: the pack position is a pure function of the server clock (every client agrees)", function()
	local start = NOW
	for index = 1, #Rush.Packs do
		for _, t in ipairs({ 0, 1.5, 30, 61, 77.7, 200, 239 }) do
			local routeA, da = Rush.PackDistance(index, start + t, start)
			local routeB, db = Rush.PackDistance(index, start + t, start)
			eq(routeA, routeB)
			eq(da, db, "same clock, same distance")
			local x1, y1, z1, tx1, tz1 = Rush.Sample(routeA, da)
			local x2, y2, z2, tx2, tz2 = Rush.Sample(routeB, db)
			eq(x1, x2); eq(y1, y2); eq(z1, z2); eq(tx1, tx2); eq(tz1, tz2)
		end
	end
	-- Wrap-around: a full lap later the leader is at the same place.
	local route = Rush.Route.Outer
	local x1, _, z1 = Rush.Sample(route, 123.4)
	local x2, _, z2 = Rush.Sample(route, 123.4 + route.Length * 3)
	near(x1, x2, 1e-6); near(z1, z2, 1e-6)
	local xn, _, zn = Rush.Sample(route, -10)
	local xp, _, zp = Rush.Sample(route, route.Length - 10)
	near(xn, xp, 1e-6, "negative distances wrap"); near(zn, zp, 1e-6)
	-- Moving forward along the heading.
	local ax, _, az, tx, tz = Rush.Sample(route, 50)
	local bx, _, bz = Rush.Sample(route, 51)
	truthy((bx - ax) * tx + (bz - az) * tz > 0.5, "heading points forward")
end)

test("routes: speed, the ALPHA STAMPEDE surge, formation and pack budgets", function()
	eq(Rush.Distance(0), 0)
	near(Rush.Distance(10), Rush.Speed * 10, 1e-9)
	local before = Rush.Distance(Rush.SurgeAt)
	local after = Rush.Distance(Rush.SurgeAt + Rush.SurgeLength)
	near(after - before, Rush.Speed * Rush.SurgeBoost * Rush.SurgeLength, 1e-6, "sprint during the surge")
	truthy(Rush.Surging(Rush.SurgeAt + 1) and not Rush.Surging(Rush.SurgeAt - 1), "surge window")
	eq(Rush.SurgeAt, Defs.ById.DOG_RUSH.SignatureSeconds, "surge = the event's signature moment")
	local last = -1
	for t = 0, 240, 0.5 do
		local d = Rush.Distance(t)
		truthy(d > last, "monotonic")
		last = d
	end
	-- Formation stays inside a lane (±2 studs) and behind the leader.
	for slot = 1, 5 do
		for t = 0, 10, 0.37 do
			local lateral, back = Rush.Slot(slot, t)
			truthy(math.abs(lateral) <= 2.1 and back <= 0.01 and back >= -11, "slot " .. slot)
		end
	end
	-- Budgets (WorldEventConfig.FX Dogs): High 14, Medium 8, Low 3; the first pack is the same for all.
	for level, budget in ipairs({ Config.FX.Low.Dogs, Config.FX.Medium.Dogs, Config.FX.High.Dogs }) do
		local packs = Rush.PacksFor(level, budget)
		local dogs = 0
		for _, row in ipairs(packs) do dogs += row.Size end
		truthy(dogs <= budget and dogs <= 14 and dogs >= math.min(3, budget), "dogs within budget " .. level .. ": " .. dogs)
		eq(packs[1].Index, 1, "pack 1 shown on every quality")
	end
	eq(#Rush.PacksFor(3, 14), 3)
	eq(#Rush.PacksFor(1, 3), 1)
end)

-- Pup spawn points ---------------------------------------------------------------------------------
test("pups: spawn points are street points, spaced, near players, deterministic", function()
	local function onRoute(at)
		for _, route in ipairs(Rush.RouteList) do
			for i = 1, route.Count do
				local dx, dz = route.X[i] - at.X, route.Z[i] - at.Z
				if dx * dx + dz * dz <= (route.Lateral + Rush.Step) ^ 2 then return true end
			end
		end
		return false
	end
	local hub = Vector3.new(0, 3, 377)
	local a, b = {}, {}
	local randA, randB = seeded(11), seeded(11)
	for _ = 1, 20 do
		local pa = Rush.PickSpawn(randA, { hub }, a)
		local pb = Rush.PickSpawn(randB, { hub }, b)
		eq(pa == nil, pb == nil, "same seed, same result")
		if pa then
			eq(pa, pb, "deterministic")
			truthy(onRoute(pa), "on a street route")
			eq(pa.Y, Rush.StreetY, "street height")
			for _, other in ipairs(a) do
				truthy((Vector3.new(other.X, 0, other.Z) - Vector3.new(pa.X, 0, pa.Z)).Magnitude >= Rush.Pups.Spacing - 1e-6, "spacing")
			end
			table.insert(a, pa)
			table.insert(b, pb)
		end
	end
	truthy(#a >= 12, "enough room for pups: " .. #a)
	-- Most pups are near the player.
	local close = 0
	for _, at in ipairs(a) do
		local d = (Vector3.new(at.X, 0, at.Z) - Vector3.new(hub.X, 0, hub.Z)).Magnitude
		if d <= Rush.Pups.NearMax + 10 then close += 1 end
	end
	truthy(close >= #a * 0.5, "near the player: " .. close .. " / " .. #a)
	-- Without players: anywhere on the routes.
	local alone = Rush.PickSpawn(seeded(3), {}, {})
	truthy(alone and onRoute(alone), "uniform fallback")
	-- How many pups are out: grows with players, clamped.
	eq(Rush.TargetPups(0), Rush.Pups.MinActive)
	truthy(Rush.TargetPups(4) > Rush.TargetPups(1), "more players, more pups")
	eq(Rush.TargetPups(100), Rush.Pups.MaxActive)
	truthy(Rush.Pups.MaxActive <= Config.Interactions.MaxActive, "within the event object cap")
end)

-- Rewards ----------------------------------------------------------------------------------------
test("rewards: per-pup coins follow the income (BoostPricing minutes) and bones; per-event cap", function()
	local p = profile()
	p.OfflineEarnings = p.OfflineEarnings or {}
	p.OfflineEarnings.BaseRate = 50 -- coins per second
	local cash, bones = p.Cash, p.Bones
	local reward = Feature.Catch(R, p, GEN, NOW, nil)
	local expected = Pricing.Coins(Rush.Pups.Coins, p, NOW)
	eq(reward.Coins, expected, "income-scaled coins")
	near(expected, 50 * 60 * Rush.Pups.Coins.IncomeMinutes, 50 * 60 * Rush.Pups.Coins.IncomeMinutes * 0.06, "~12 s of income")
	eq(p.Cash - cash, reward.Coins)
	eq(p.Bones - bones, Rush.Pups.Bones)
	eq(reward.Caught, 1)
	eq(reward.Goal, 10)
	-- A brand new player still gets the floor.
	local q = profile()
	local first = Feature.Catch(R, q, GEN, NOW, nil)
	eq(first.Coins, Pricing.Coins(Rush.Pups.Coins, q, NOW))
	truthy(first.Coins >= Rush.Pups.Coins.MinCash, "floor")
	-- The per-event cap.
	for _ = 2, Rush.Pups.PerEvent do Feature.Catch(R, p, GEN, NOW, nil) end
	eq(p.DogRush.Caught, Rush.Pups.PerEvent)
	local before = p.Cash
	refused(function() Feature.Catch(R, p, GEN, NOW, nil) end, "You caught every pup you can this rush!")
	eq(p.Cash, before, "nothing paid past the cap")
	-- Coins never pass the wallet limit.
	p.Cash = EconomyConfig.MaxCash - 5
	local capped = Feature.Catch(R, p, "next:DOG_RUSH", NOW, nil)
	truthy(capped.Coins <= 5 and p.Cash <= EconomyConfig.MaxCash, "wallet limit")
	-- Generation must be a real one.
	refused(function() Feature.Catch(R, p, "", NOW, nil) end, "ended")
	refused(function() Feature.Catch(R, p, string.rep("x", 81), NOW, nil) end, "ended")
end)

test("rewards: chests at 3 / 6 / 10 exactly once per event (idempotent), lucky block or bones", function()
	local p = profile()
	local granted = {}
	local function addBlock(profile, tier, count)
		table.insert(granted, tier .. "x" .. count)
		return true
	end
	local chests = {}
	for i = 1, Rush.Pups.PerEvent do
		local reward = Feature.Catch(R, p, GEN, NOW + i, addBlock)
		for _, c in ipairs(reward.Chests) do
			table.insert(chests, c.Count)
			truthy(c.Coins >= 0 and c.Bones > 0, "chest pays")
			eq(i, c.Count, "a chest opens on the catch that reaches it")
		end
	end
	eq(table.concat(chests, ","), "3,6,10", "three chests, once each")
	eq(table.concat(granted, ","), "Rarex1", "the golden chest gives a free Rare Lucky Block")
	eq(p.DogRush.Chests, 3)
	for _, m in ipairs(Rush.Milestones) do eq(p.DogRush.Claimed[tostring(m.Count)], true) end
	-- A new event starts the chests over; the lifetime counter keeps growing.
	local reward = Feature.Catch(R, p, "4243:DOG_RUSH", NOW + 999, addBlock)
	eq(reward.Caught, 1)
	eq(#reward.Chests, 0)
	eq(p.DogRush.Lifetime, Rush.Pups.PerEvent + 1)
	eq(p.DogRush.Best, Rush.Pups.PerEvent)
	-- No safe block helper (or a full storage): more bones instead.
	local q = profile()
	local bonesBefore = q.Bones
	local total = 0
	for i = 1, 10 do
		local r = Feature.Catch(R, q, GEN, NOW + i, function() return false end)
		total += r.Bones
		for _, c in ipairs(r.Chests) do
			total += c.Bones
			eq(c.Block, nil, "no block")
		end
	end
	eq(q.Bones - bonesBefore, total, "reported bones = paid bones")
	local golden = Rush.Milestone(10)
	local expected = 10 * Rush.Pups.Bones
	for _, m in ipairs(Rush.Milestones) do expected += m.Bones end
	eq(total, expected + golden.FallbackBones, "fallback bones for the golden chest")
	-- An erroring helper is treated like a refusal (the catch still commits).
	local e = profile()
	for i = 1, 10 do Feature.Catch(R, e, GEN, NOW + i, function() error("storage busy") end) end
	eq(e.DogRush.Caught, 10)
end)

test("rewards: chest coins scale with income and the milestones are ordered", function()
	local last = 0
	for i, m in ipairs(Rush.Milestones) do
		truthy(m.Count > last, "ascending")
		last = m.Count
		truthy(m.Coins.MinCash > 0 and m.Coins.IncomeMinutes > 0 and m.Bones > 0, "chest " .. i)
		truthy(m.Name ~= "" and m.RU ~= "" and m.Icon ~= "", "names " .. i)
	end
	eq(Rush.Goal, 10)
	truthy(Rush.Pups.PerEvent >= Rush.Goal, "the last chest is reachable")
	local p = profile()
	p.OfflineEarnings = p.OfflineEarnings or {}
	p.OfflineEarnings.BaseRate = 1000
	eq(Rush.ChestCoins(Rush.Milestone(10), p, NOW), Pricing.Coins(Rush.Milestone(10).Coins, p, NOW))
	truthy(Rush.ChestCoins(Rush.Milestone(10), p, NOW) > Rush.ChestCoins(Rush.Milestone(3), p, NOW), "bigger chest, more coins")
	-- Whole event (12 pups + 3 chests) for a player earning 1000 coins/s: under 7 minutes of income.
	local total = 12 * Rush.PupCoins(p, NOW)
	for _, m in ipairs(Rush.Milestones) do total += Rush.ChestCoins(m, p, NOW) end
	truthy(total <= 1000 * 60 * 7, "bounded: " .. total)
	eq(Rush.NextMilestone(0).Count, 3)
	eq(Rush.NextMilestone(3).Count, 6)
	eq(Rush.NextMilestone(10), nil)
end)

-- Saved progress ---------------------------------------------------------------------------------
test("progress: old profiles stay untouched, counters persist, broken data is healed", function()
	local p = profile()
	eq(p.DogRush, nil, "no DOG RUSH data until the first catch")
	Feature.Validate(R, p)
	R.Validate(p)
	for i = 1, 4 do Feature.Catch(R, p, GEN, NOW + i, nil) end
	R.Validate(p)
	-- Save / load (JSON) and normalize: nothing is lost.
	local loaded = serde.decode("json", serde.encode("json", p))
	R.Normalize(loaded, loaded.UserId, NOW + 10)
	eq(loaded.DogRush.Lifetime, 4)
	eq(loaded.DogRush.Caught, 4)
	eq(loaded.DogRush.Generation, GEN)
	eq(loaded.DogRush.Claimed["3"], true)
	R.Validate(loaded)
	-- The same event continues after a rejoin; the chest is not paid twice.
	local reward = Feature.Catch(R, loaded, GEN, NOW + 20, nil)
	eq(reward.Caught, 5)
	eq(#reward.Chests, 0)
	-- Broken values are repaired, never rejected.
	loaded.DogRush = { Caught = -3, Lifetime = 0 / 0, Claimed = { [3] = true, ["6"] = "yes", ["10"] = true }, Generation = 7 }
	R.Normalize(loaded, loaded.UserId, NOW + 30)
	eq(loaded.DogRush.Caught, 0)
	eq(loaded.DogRush.Lifetime, 0)
	eq(loaded.DogRush.Generation, "")
	eq(loaded.DogRush.Claimed["10"], true)
	eq(loaded.DogRush.Claimed["6"], nil)
	R.Validate(loaded)
	-- Snapshot.
	local view = {}
	Feature.Snapshot(R, loaded, view, NOW)
	eq(view.DogRush.Goal, 10)
	local fresh = {}
	Feature.Snapshot(R, profile(), fresh, NOW)
	eq(fresh.DogRush.Lifetime, 0)
end)

test("titles: DOG WRANGLER / PUP HERDER / STAMPEDE KING unlock from the lifetime counter", function()
	local p = profile()
	local function catches(n, gen)
		for i = 1, n do Feature.Catch(R, p, gen, NOW + i, nil) end
	end
	for e = 1, 5 do catches(10, "gen" .. e) end -- 50 pups over 5 events
	TitleFeature.Evaluate(R, p, NOW + 100)
	truthy(p.Titles.Unlocked.DogWrangler and p.Titles.Unlocked.PupHerder, "10 and 50")
	truthy(not p.Titles.Unlocked.StampedeKing, "not 200 yet")
	eq(Titles.Stats.Pups(p), 50)
end)

-- Definition, model and client wiring --------------------------------------------------------------
test("definition: DOG_RUSH keeps its perks and end reward, adds pups and the stampede", function()
	local def = Defs.ById.DOG_RUSH
	eq(def.WorldProps, "Stampede", "no more DogCrowd around the player")
	eq(def.Weight, 14)
	eq(def.Perks.Walk, 1.35)
	eq(def.Perks.LineSpeed, 1.5)
	eq(def.Perks.LineLuck, 1.2)
	truthy(def.Perks.Effects.Zoomies and def.Perks.Effects.Trail and def.Perks.Effects.Pups, "effects")
	eq(def.Perks.Reward.MinCash, 600)
	eq(def.Perks.Reward.IncomeMinutes, 1)
	eq(def.Perks.Reward.Bones, 2)
	eq(def.GameplayModifiers.DigSpeed, 0.15)
	eq(def.GameplayModifiers.Recovery, 0.05)
	eq(def.SpecialObjects, nil, "pups have their own spawner")
	local lines = table.concat(Defs.PerkLines(def), "\n")
	truthy(string.find(lines, "CATCH RUNAWAY PUPS", 1, true), "perk line")
end)

test("pup model: a small golden puppy, anchored, non-colliding, touch zone and visual sub-model", function()
	local model = Objects.Build("RunawayPup", Color3.fromRGB(255, 206, 84))
	local parts, touch = 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			truthy(d.Anchored and not d.CanCollide, "anchored, no collision: " .. d.Name)
			if d.CanTouch then touch += 1; eq(d.Name, "CatchZone") end
		end
	end
	truthy(parts <= 40, "part budget " .. parts)
	eq(touch, 1, "only the catch zone is touchable")
	eq(model.PrimaryPart.Name, "InteractionCore")
	local visual = model:FindFirstChild("Visual")
	truthy(visual and visual.PrimaryPart and visual.PrimaryPart.Name == "PupBody", "visual sub-model with a primary part")
	eq(model:GetAttribute("PupKind"), "Golden")
end)

test("client: no player-attached stampede left; world-space stampede and fixed sky stage", function()
	local fx = fs.readFile("src/ReplicatedStorage/WorldEvents/WorldEventFX.luau")
	truthy(not string.find(fx, "DogCrowd", 1, true), "DogCrowd removed")
	truthy(string.find(fx, "Stampede.Begin", 1, true), "stampede wired")
	local cataclysm = fs.readFile("src/ReplicatedStorage/WorldEvents/WorldEventCataclysm.luau")
	truthy(not string.find(cataclysm, "StampedeWake", 1, true), "StampedeWake removed")
	truthy(string.find(cataclysm, "Stampede.LeaderPosition", 1, true), "surge at the pack")
	local stampede = fs.readFile("src/ReplicatedStorage/WorldEvents/WorldEventStampede.luau")
	truthy(not string.find(stampede, "HumanoidRootPart", 1, true), "never reads the player's position")
	truthy(string.find(stampede, "GetServerTimeNow", 1, true), "server clock")
	truthy(not string.find(string.match(stampede, "local function update%(%).-\nend\n") or "", "Raycast", 1, true), "no raycasts per frame")
	local spectacle = fs.readFile("src/ReplicatedStorage/WorldEvents/WorldEventSpectacle.luau")
	truthy(string.find(spectacle, "Rush.SkyStage", 1, true), "fixed sky stage")
	near((Rush.SkyStage.Look).Magnitude, 1, 1e-6)
	local gameplay = fs.readFile("src/StarterPlayer/StarterPlayerScripts/WorldEventGameplayFX.client.luau")
	truthy(string.find(gameplay, "DOG RUSH!", 1, true) and string.find(gameplay, "СОБАЧИЙ ЗАБЕГ!", 1, true), "localized banner")
	truthy(string.find(gameplay, "rbxasset://sounds/volume_slider.ogg", 1, true), "bark cue")
end)

print(string.format("dog_rush: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("dog_rush tests failed")
end
