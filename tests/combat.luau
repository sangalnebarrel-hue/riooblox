--!nolint
-- CHAPTER II combat (WP-B): hazard geometry + fairness, BossMath numbers, the Event HP state machine and the EventHP server
-- module driven with fake players / positions / clock. lune run tests/combat.luau
local L = require("./lib/economy_env")
local roblox = require("@lune/roblox")
local V3, CF = roblox.Vector3.new, roblox.CFrame
local Hazards = L.Require("ReplicatedStorage.Halloween.Hazards")
local BossMath = L.Require("ReplicatedStorage.Halloween.BossMath")
local Rules = L.Require("ReplicatedStorage.Halloween.CombatRules")
-- every number below is the design default, whatever Chapter2Config holds today
Hazards.SetConfig({})
BossMath.SetConfig({})
Rules.SetConfig({})

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
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then
		error((msg or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function yes(v, msg)
	if not v then
		error(msg or "expected true", 2)
	end
end
local function no(v, msg)
	if v then
		error(msg or "expected false", 2)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- 1. hazard geometry
---------------------------------------------------------------------------------------------------------------------
test("circle: radius, edge and the Y band", function()
	local c = Hazards.Circle(V3(10, 0, 10), 6)
	yes(Hazards.Contains(c, V3(10, 3, 10)), "centre")
	yes(Hazards.Contains(c, V3(15.9, 3, 10)), "inside the edge")
	no(Hazards.Contains(c, V3(16.1, 3, 10)), "outside the edge")
	yes(Hazards.Contains(c, V3(10, 10, 10)), "10 studs up is inside the band")
	no(Hazards.Contains(c, V3(10, 10.5, 10)), "above the band")
	no(Hazards.Contains(c, V3(10, -11, 10)), "below the band")
	local tall = Hazards.Circle(V3(10, 0, 10), 6, { Height = 30 })
	yes(Hazards.Contains(tall, V3(10, 25, 10)), "Height widens the band")
end)

test("ring: band, inner hole, gaps (also across 0/360)", function()
	local r = Hazards.Ring(V3(0, 0, 0), 8, 12, { { Angle = 90, Width = 40 }, { Angle = 0, Width = 30 } })
	yes(Hazards.Contains(r, V3(-10, 3, 0)), "in the band (180 deg)")
	no(Hazards.Contains(r, V3(0, 3, 0)), "inner hole is safe")
	no(Hazards.Contains(r, V3(-13, 3, 0)), "outside the outer edge")
	no(Hazards.Contains(r, V3(0, 3, 10)), "the gap at +Z (90 deg)")
	local a = math.rad(108) -- 18 deg off the gap centre, still inside its 20 deg half width
	no(Hazards.Contains(r, V3(math.cos(a) * 10, 3, math.sin(a) * 10)), "inside the gap width")
	local b = math.rad(112)
	yes(Hazards.Contains(r, V3(math.cos(b) * 10, 3, math.sin(b) * 10)), "just past the gap")
	local w = math.rad(-12) -- 348 deg: inside the gap around 0 deg
	no(Hazards.Contains(r, V3(math.cos(w) * 10, 3, math.sin(w) * 10)), "gap wraps around 0/360")
	no(Hazards.Contains(r, V3(-10, 14, 0)), "Y band")
end)

test("line: flat ends, half width, sloped ground band", function()
	local l = Hazards.Line(V3(0, 0, 0), V3(20, 0, 0), 4)
	yes(Hazards.Contains(l, V3(10, 3, 1.9)), "inside the half width")
	no(Hazards.Contains(l, V3(10, 3, 2.1)), "outside the half width")
	no(Hazards.Contains(l, V3(-.5, 3, 0)), "before From")
	no(Hazards.Contains(l, V3(20.5, 3, 0)), "after To")
	local slope = Hazards.Line(V3(0, 0, 0), V3(20, 10, 0), 4)
	yes(Hazards.Contains(slope, V3(18, 12, 0)), "band follows the slope")
	no(Hazards.Contains(slope, V3(2, 12, 0)), "too high at the low end")
end)

test("cone: opening angle and radius", function()
	local c = Hazards.Cone(V3(0, 0, 0), V3(0, 0, -1), 90, 10)
	yes(Hazards.Contains(c, V3(0, 3, -9)), "straight ahead")
	yes(Hazards.Contains(c, V3(5, 3, -6)), "inside 45 deg")
	no(Hazards.Contains(c, V3(7, 3, -3)), "outside the opening")
	no(Hazards.Contains(c, V3(0, 3, 5)), "behind")
	no(Hazards.Contains(c, V3(0, 3, -10.5)), "beyond the radius")
	yes(Hazards.Contains(c, V3(.2, 3, .2)), "at the apex")
end)

test("safe: inverse circle with an outer limit", function()
	local s = Hazards.Safe(V3(0, 0, 0), 9, 40)
	no(Hazards.Contains(s, V3(3, 3, 3)), "inside the safe circle")
	yes(Hazards.Contains(s, V3(20, 3, 0)), "outside = hit")
	no(Hazards.Contains(s, V3(41, 3, 0)), "beyond Outer")
	no(Hazards.Contains(s, V3(20, 20, 0)), "Y band")
	yes(Hazards.Contains(Hazards.Safe(V3(0, 0, 0), 9), V3(200, 3, 0)), "no Outer = everything outside")
end)

test("box: oriented extents", function()
	local cf = CF.new(V3(0, 0, 0)) * CF.Angles(0, math.rad(45), 0)
	local b = Hazards.Box(cf, V3(4, 1, 20))
	local along = cf.LookVector * 9
	yes(Hazards.Contains(b, V3(along.X, 3, along.Z)), "along the long axis (Y band covers the root height)")
	local side = cf.RightVector * 3
	no(Hazards.Contains(b, V3(side.X, 0, side.Z)), "beyond the short half width")
	yes(Hazards.Contains(b, V3(0, 9, 0)), "flat box: the band applies")
	no(Hazards.Contains(b, V3(0, 11, 0)), "above the band")
end)

test("paths: centre over time, moving containment, speed", function()
	local s = Hazards.Safe(V3(0, 0, 0), 5, 30, { Path = { { At = 0, Center = V3(0, 0, 0) }, { At = 4, Center = V3(20, 0, 0) } } })
	near(Hazards.PathCenter(s, 2).X, 10, 1e-6, "midway")
	near(Hazards.PathCenter(s, -1).X, 0, 1e-6, "before the path")
	near(Hazards.PathCenter(s, 9).X, 20, 1e-6, "after the path")
	no(Hazards.Contains(s, V3(10, 3, 0), 2), "following the safe circle")
	yes(Hazards.Contains(s, V3(0, 3, 0), 2), "left behind")
	near(Hazards.PathSpeed(s), 5, 1e-6, "5 studs/s")
	local line = Hazards.Line(V3(0, 0, 0), V3(10, 0, 0), 2, { Path = { { At = 0, Center = V3(5, 0, 0) }, { At = 1, Center = V3(5, 0, 6) } } })
	yes(Hazards.Contains(line, V3(5, 3, 6), 1), "a line sweeping sideways")
	no(Hazards.Contains(line, V3(5, 3, 0), 1), "no longer at its start")
end)

test("timing helpers", function()
	local d = { Shape = Hazards.Circle(V3(0, 0, 0), 4), Telegraph = 1.5, ImpactAt = 100, Linger = 3, Damage = 10 }
	near(Hazards.ShowAt(d), 98.5)
	near(Hazards.ShowAt(d, .35), 98.15)
	near(Hazards.EndAt(d), 103)
	near(Hazards.Progress(d, 99.25), .5)
	eq(Hazards.Phase(d, 98), "Waiting")
	eq(Hazards.Phase(d, 99), "Telegraph")
	eq(Hazards.Phase(d, 101), "Linger")
	eq(Hazards.Phase(d, 103.1), "Done")
	near(Hazards.Extent(Hazards.Ring(V3(0, 0, 0), 2, 9)), 9)
	near(Hazards.Extent(Hazards.Line(V3(0, 0, 0), V3(10, 0, 0), 4)), 7)
end)

test("encode / decode round trip for every shape", function()
	local shapes = {
		Hazards.Circle(V3(1, 2, 3), 4.5),
		Hazards.Ring(V3(1, 2, 3), 3, 7, { { Angle = 45, Width = 30 }, { Angle = 200, Width = 25 } }),
		Hazards.Line(V3(0, 0, 0), V3(10, 0, 5), 3),
		Hazards.Cone(V3(4, 0, 4), V3(1, 0, 0), 100, 12),
		Hazards.Safe(V3(0, 0, 0), 9, 40, { Path = { { At = 0, Center = V3(0, 0, 0) }, { At = 8, Center = V3(30, 0, 0) } } }),
		Hazards.Box(CF.new(V3(5, 0, 5)) * CF.Angles(0, 1, 0), V3(4, 2, 9), { Height = 6 }),
	}
	for i, s in ipairs(shapes) do
		local d = { Id = i, Shape = s, Telegraph = 1.25, ImpactAt = 1234.5, Damage = 18, Linger = 2, DPS = 4, Kind = "Slam", Source = "Boss",
			Knock = 40 }
		local back = Hazards.Decode(Hazards.Encode(d, 1233))
		eq(back.Id, i, "id")
		eq(Hazards.TypeOf(back.Shape), Hazards.TypeOf(s), "type")
		near(back.ShowAt, 1233)
		near(back.ImpactAt, 1234.5)
		near(back.Damage, 18)
		eq(back.Kind, "Slam")
		yes(back.Knock, "knock flag")
		-- the decoded shape hits exactly the same points
		for x = -20, 20, 2.5 do
			for z = -20, 20, 2.5 do
				local p = V3(x, 3, z)
				eq(Hazards.Contains(back.Shape, p, 1), Hazards.Contains(s, p, 1), "shape " .. i .. " at " .. tostring(p))
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- 2. fairness
---------------------------------------------------------------------------------------------------------------------
test("fairness: telegraphs, per-hit caps, moving speed, ring gaps", function()
	local circle = Hazards.Circle(V3(0, 0, 0), 5)
	yes(Hazards.Check({ Shape = circle, Telegraph = .9, Damage = 12 }), ".9 s for a light hit")
	no(Hazards.Check({ Shape = circle, Telegraph = .8, Damage = 12 }), "below .9 s")
	no(Hazards.Check({ Shape = circle, Telegraph = 1, Damage = 25 }), "a 25+ hit needs 1.2 s")
	yes(Hazards.Check({ Shape = circle, Telegraph = 1.2, Damage = 45 }), "45 = 45% of 100")
	no(Hazards.Check({ Shape = circle, Telegraph = 1.2, Damage = 46 }), "above 45%")
	no(Hazards.Check({ Shape = circle, Telegraph = 1.2, Damage = 41 }, { Trial = true }), "trials cap at 40%")
	yes(Hazards.Check({ Shape = circle, Telegraph = .2, Damage = 0 }), "a harmless marker needs no telegraph")
	no(Hazards.Check({ Shape = circle, Telegraph = .5, Damage = 0, DPS = 5, Linger = 3 }), "lingering damage is telegraphed too")
	local fast = Hazards.Safe(V3(0, 0, 0), 9, 40, { Path = { { At = 0, Center = V3(0, 0, 0) }, { At = 2, Center = V3(30, 0, 0) } } })
	no(Hazards.Check({ Shape = fast, Telegraph = 1.2, DPS = 7, Linger = 8 }), "15 studs/s safe zone")
	no(Hazards.Check({ Shape = Hazards.Ring(V3(0, 0, 0), 1, 20), Telegraph = 1.5, Damage = 14 }), "ring without a gap")
	no(Hazards.Check({ Shape = Hazards.Ring(V3(0, 0, 0), 1, 20, { { Angle = 0, Width = 5 } }), Telegraph = 1.5, Damage = 14 }), "gap too narrow")
	yes(Hazards.Check({ Shape = Hazards.Ring(V3(0, 0, 0), 1, 20, { { Angle = 0, Width = 40 } }), Telegraph = 1.5, Damage = 14 }), "a real gap")
	yes(Hazards.Check({ Shape = Hazards.Ring(V3(0, 0, 0), 10, 20), Telegraph = 1.5, Damage = 14 }), "a safe inner disc counts as the gap")
	local _, problems = Hazards.Check({ Shape = { Type = "Ring", Center = V3(0, 0, 0), Inner = 9, Outer = 4 }, Telegraph = 1, Damage = 5 })
	yes(#problems > 0, "bad ring geometry reported")
end)

test("sanitize makes every def fair", function()
	local defs = {
		{ Id = 1, Shape = Hazards.Circle(V3(0, 0, 0), 5), Telegraph = .3, Damage = 80 },
		{ Id = 2, Shape = Hazards.Ring(V3(0, 0, 0), 1, 20), Telegraph = 1.5, Damage = 14 },
		{ Id = 3, Shape = Hazards.Safe(V3(0, 0, 0), 9, 40, { Path = { { At = 0, Center = V3(0, 0, 0) }, { At = 2, Center = V3(30, 0, 0) } } }),
			Telegraph = 1.2, DPS = 7, Linger = 8 },
	}
	for _, d in ipairs(defs) do
		local fixed, problems = Hazards.Sanitize(d)
		yes(#problems > 0, "problems reported for " .. d.Id)
		yes(Hazards.Check(fixed), "fixed def " .. d.Id .. " is fair")
	end
	local f = Hazards.Sanitize(defs[1])
	near(f.Damage, 45)
	near(f.Telegraph, 1.2)
	near(Hazards.PathSpeed(Hazards.Sanitize(defs[3]).Shape), 11, 1e-6, "slowed to the limit")
	eq(defs[1].Damage, 80, "the original def is not modified")
end)

test("pattern check: grave lines leave a lane, a full carpet does not", function()
	local arena = { Center = V3(0, 0, 0), Radius = 20 }
	local lines = {}
	for i = -2, 2 do
		if i ~= 1 then
			table.insert(lines, { Shape = Hazards.Line(V3(-25, 0, i * 8), V3(25, 0, i * 8), 8), Damage = 18, Telegraph = 1.2 })
		end
	end
	local ok, frac = Hazards.CheckPattern(lines, arena)
	yes(ok, "one lane is open")
	yes(frac > 0 and frac < .5, "a narrow lane, fraction " .. frac)
	table.insert(lines, { Shape = Hazards.Line(V3(-25, 0, 8), V3(25, 0, 8), 8), Damage = 18, Telegraph = 1.2 })
	table.insert(lines, { Shape = Hazards.Circle(V3(0, 0, 0), 30), Damage = 0, Telegraph = 1 }) -- harmless markers never block
	local closed = Hazards.CheckPattern(lines, arena)
	no(closed, "every lane covered")
end)

---------------------------------------------------------------------------------------------------------------------
-- 3. BossMath
---------------------------------------------------------------------------------------------------------------------
test("armor curve: Chapter I parity by default, the design curve via config", function()
	for _, raw in ipairs({ 1, 7, 100, 192, 760, 2661 }) do
		local chapter1 = math.max(1, math.floor(5 * raw ^ .55 + .5)) -- Boss.ArmorDamage (Boss.luau, ArmorK 5 / ArmorExp .55)
		eq(BossMath.ArmorDamage(raw), chapter1, "raw " .. raw)
		eq(BossMath.ArmorDamage(raw, { Weak = true }), math.max(1, math.floor(5 * raw ^ .55 * 3 + .5)), "weak raw " .. raw)
	end
	eq(BossMath.ArmorDamage(0), 0, "no damage")
	BossMath.SetConfig({ ArmorExp = .42 })
	eq(BossMath.ArmorDamage(100), math.floor(5 * 100 ^ .42 + .5), "design exponent")
	BossMath.SetConfig({})
end)

test("armor multipliers: dog bonus, sync, weakened, H15, bonus cap", function()
	local base = 5 * 100 ^ .55
	eq(BossMath.ArmorDamage(100, { DogBonus = .2 }), math.floor(base * 1.2 + .5), "dog bonus")
	eq(BossMath.ArmorDamage(100, { DogBonus = .9 }), math.floor(base * 1.3 + .5), "dog bonus capped at .3")
	eq(BossMath.ArmorDamage(100, { Sync = true }), math.floor(base * 1.5 + .5), "sync")
	eq(BossMath.ArmorDamage(100, { Weakened = true }), math.floor(base * .7 + .5), "weakened")
	eq(BossMath.ArmorDamage(100, { H15 = true }), math.floor(base + .5), "H15 only on mechanics")
	eq(BossMath.ArmorDamage(100, { H15 = true, Mechanic = true }), math.floor(base * 1.25 + .5), "H15 on a chain")
	local _, parts = BossMath.ArmorDamage(100, { DogBonus = .3, Sync = true, H15 = true, Weak = true, Mult = 2 })
	near(parts.Bonus, 2.25, 1e-9, "bonus cap")
	near(BossMath.DealtMult({ Weakened = true }), .7)
	near(BossMath.TakenMult({ Weakened = true }), 1.25)
	eq(BossMath.ResonanceCount(true, true), 2)
	eq(BossMath.ResonanceCount(true, false), 1)
	eq(BossMath.ResonanceCount(false, true), 0)
	near(BossMath.H15Mult(true), 1.25)
end)

test("soft cap: 3 s window, 20% beyond, mechanic bypass", function()
	eq(BossMath.MaxArmorBase(5), 32500, "difficulty V base armor")
	local per = BossMath.CapPerSecond(BossMath.MaxArmorBase(5))
	near(per, 146.25, 1e-9)
	local cap = BossMath.NewCap()
	local total = 0
	for i = 0, 3 do
		total += BossMath.CapApply(cap, i * .5, 100, per)
	end
	near(total, 400, 1e-9, "the first 400 inside the 438.75 allowance")
	local fifth, info = BossMath.CapApply(cap, 2, 100, per)
	near(info.Full, 38.75, 1e-9)
	near(fifth, 38.75 + 61.25 * .2, 1e-9, "beyond the allowance at 20%")
	near(BossMath.CapApply(cap, 2.5, 100, per), 20, 1e-9, "fully over")
	-- the window rolls: hits older than 3 s no longer count
	near(BossMath.CapApply(cap, 6, 100, per), 100, 1e-9, "a fresh window")
	-- mechanic damage: 60% never capped
	local m = BossMath.NewCap()
	BossMath.CapApply(m, 0, 1000, per) -- saturate
	local mech, mi = BossMath.CapApply(m, .1, 100, per, true)
	near(mi.Free, 60, 1e-9)
	near(mech, 60 + 40 * .2, 1e-9, "60 bypass + 40 at 20%")
	-- sustained 300 armor/s: exactly the per-second allowance at full value, the excess at 20% (over-cap hits never eat
	-- the next second's allowance)
	local s = BossMath.NewCap()
	local sum = 0
	for i = 0, 299 do
		sum += BossMath.CapApply(s, i * .1, 30, per)
	end
	near(sum / 30, per + (300 - per) * .2, 2, "steady state per second")
end)

test("sync strike: two Perfects within .5 s, both rewarded once", function()
	local s = BossMath.NewSync()
	local m1, r1 = BossMath.SyncHit(s, 1, 10, 50)
	eq(m1, 1)
	eq(#r1, 0)
	local m2, r2 = BossMath.SyncHit(s, 2, 10.3, 80)
	near(m2, 1.5)
	eq(#r2, 1)
	eq(r2[1].UserId, 1)
	near(r2[1].Bonus, 25)
	local m3, r3 = BossMath.SyncHit(s, 3, 10.45, 60)
	near(m3, 1.5, 1e-9, "a third player joins the sync")
	eq(#r3, 0, "partners already synced get no second retro bonus")
	local m4 = BossMath.SyncHit(s, 1, 11.2, 50)
	eq(m4, 1, "too late after the others")
	local m5 = BossMath.SyncHit(s, 1, 11.4, 50)
	eq(m5, 1, "a player never syncs with themselves")
end)

test("event damage: difficulty scaling and the 45% / 40% clamp", function()
	eq(BossMath.AttackDamage("Slam", 5), 24, "Slam 16 x 1.5")
	eq(BossMath.AttackDamage("Slam", 1), 11, "Slam 16 x .7")
	eq(BossMath.AttackDamage("RockExplode", 5), 21)
	eq(BossMath.EventDamage(40, 5), 45, "60 clamped to 45")
	eq(BossMath.EventDamage(40, 5, { Trial = true }), 40, "trial clamp 40")
	eq(BossMath.EventDamage(40, 5, { NoScale = true }), 40)
	eq(BossMath.EventDamage(0, 5), 0)
	for d = 1, 5 do
		for attack in pairs(BossMath.Config().Damage) do
			yes(BossMath.AttackDamage(attack, d) <= 45, attack .. " at " .. d)
		end
	end
end)

test("design target: spam <= 35% of the mechanics DPS (TV-Head, difficulty V, design curve)", function()
	BossMath.SetConfig({ ArmorExp = .42 })
	local per = BossMath.CapPerSecond(BossMath.MaxArmorBase(5))
	-- TV-Head at max Strength: x1.2 strength, PerfectMult 2.2, full combo +80%, CritMult 3.5 on 3 hits in 10, 5 hits a second
	local plain, perfect = 160 * 1.2, 160 * 1.2 * 2.2 * 1.8
	local function run(mechanics: boolean): number
		local cap = BossMath.NewCap()
		local total = 0
		for i = 0, 149 do -- 30 s
			local t = i * .2
			local crit = i % 10 < 3
			local raw, opts
			if mechanics then
				raw = perfect * (crit and 3.5 or 1)
				-- half of the hits on mechanics (weak points / chains: x3, 60% cap bypass), half Perfects on plates; the crits
				-- fall on both alike
				opts = { Weak = (i + 5) % 10 < 5 }
			else
				raw = plain * (crit and 3.5 or 1)
				opts = {}
			end
			total += BossMath.CapApply(cap, t, BossMath.ArmorDamage(raw, opts), per, mechanics and opts.Weak)
		end
		return total / 30
	end
	local spam, skilled = run(false), run(true)
	local ratio = spam / skilled
	yes(ratio <= .35, string.format("spam %.0f/s vs mechanics %.0f/s = %.2f", spam, skilled, ratio))
	BossMath.SetConfig({})
end)

test("config mapping from the Chapter2Config shape (Boss / Combat / Dogs)", function()
	local c2 = {
		Boss = { ArmorK = 5, ArmorExp = .42, SoftCap = { Window = 3, PerSecond = .005, Beyond = .25, MechanicBypass = .5 },
			Sync = { Window = .4, Bonus = .6, MinPlayers = 2 }, WeakenedDealt = .72, Damage = { Slam = 18 }, DifficultyMult = { .7, .9, 1.1, 1.3, 1.6 } },
		Combat = { MaxHP = 120, ReenterKeep = 25, IFrames = .5, Downed = { Seconds = 18, WalkSpeed = 6 }, Revive = { Hold = 2, Range = 8, HP = 35 },
			BleedOut = { HPFraction = .5, WeakenedSeconds = 20 }, Weakened = { DamageDealt = .72, DamageTaken = 1.2 },
			Regen = { PerSecond = 3, After = 7 }, Tick = .2, Hazards = { Grace = .1, SignalRadius = 200, MaxHitFractionBoss = .4, MaxHitFractionTrial = .35 } },
		Dogs = { Defs = {
			HW_CandleCorgi = { TelegraphLead = .4, GasReduction = .25 },
			HW_MourningShiba = { SelfReviveAfter = 7, ReviveOnYouFaster = .5 },
			HW_Bridehound = { MaxHPBonus = 20, ReviveSpeedMult = 2.5, ReviveShield = 25 },
			HW_BellkeeperWolf = { ResonancePerfectMult = 3, MechanicDamageBonus = .3 },
		} },
	}
	BossMath.SetConfig(BossMath.FromChapter2(c2))
	local b = BossMath.Config()
	near(b.ArmorExp, .42)
	near(b.SoftCap.PerSecond, .005)
	near(b.Sync.Bonus, .6)
	near(b.Weakened.Dealt, .72)
	near(b.Weakened.Taken, 1.2)
	near(b.Weakened.Seconds, 20)
	near(b.MaxHitFrac, .4)
	near(b.TrialHitFrac, .35)
	near(b.Damage.Slam, 18)
	near(b.Damage.Stomp, 12, 1e-9, "unlisted attacks keep the defaults")
	near(b.DifficultyMult[5], 1.6)
	eq(b.H15.Resonance, 3)
	near(b.H15.Mechanic, 1.3)
	Rules.SetConfig(Rules.FromChapter2(c2))
	local r = Rules.Config()
	near(r.MaxHP, 120)
	near(r.ReEnterGrace, 25)
	near(r.IFrames, .5)
	near(r.DownedSeconds, 18)
	near(r.DownedWalkSpeed, 6)
	near(r.ReviveHold, 2)
	near(r.ReviveRange, 8)
	near(r.ReviveHP, 35)
	near(r.BleedOutHPFrac, .5)
	near(r.WeakenedSeconds, 20)
	near(r.WeakenedDealt, .72)
	near(r.WeakenedTaken, 1.2)
	near(r.RegenPerSecond, 3)
	near(r.RegenDelay, 7)
	near(r.TickRate, 5)
	near(r.HazardGrace, .1)
	near(r.HazardRange, 200)
	near(r.H10Lead, .4)
	near(r.H10GasMult, .75)
	near(r.SelfReviveAfter, 7)
	near(r.H11ReviveSpeed, 1.5)
	near(r.H14MaxHP, 20)
	near(r.H14ReviveSpeed, 2.5)
	near(r.H14ReviveShield, 25)
	BossMath.SetConfig({})
	Rules.SetConfig({})
end)

---------------------------------------------------------------------------------------------------------------------
-- 4. the Event HP state machine (pure timings)
---------------------------------------------------------------------------------------------------------------------
local C = Rules.Config()

test("damage and i-frames", function()
	local st = Rules.New(C, 0)
	eq(st.HP, 100)
	local a, res = Rules.Damage(st, 30, 0, C)
	near(a, 30)
	eq(res, "Hit")
	local b, res2 = Rules.Damage(st, 30, .3, C)
	eq(b, 0)
	eq(res2, "IFrame", "inside the .6 s i-frames")
	local c, res3 = Rules.Damage(st, 30, .6, C)
	near(c, 30, 1e-9, "i-frames end at .6 s")
	eq(res3, "Hit")
	local d = Rules.Damage(st, 5, .7, C, { Tick = true })
	near(d, 5, 1e-9, "DPS ticks ignore i-frames")
	near(st.IFrameUntil, 1.2, 1e-9, "... and do not extend them")
	near(st.HP, 35)
	local e = Rules.Damage(st, 8, 2, C, { Taken = 1.25 })
	near(e, 10, 1e-9, "taken multiplier")
end)

test("shields absorb first and can expire", function()
	local st = Rules.New(C, 0)
	Rules.AddShield(st, 20, 0)
	local a, res, absorbed = Rules.Damage(st, 15, 0, C)
	eq(a, 0)
	eq(res, "Shield")
	near(absorbed, 15)
	near(st.HP, 100)
	local b, res2, ab2 = Rules.Damage(st, 30, 1, C)
	near(ab2, 5)
	near(b, 25)
	eq(res2, "Hit")
	near(st.Shield, 0)
	local t = Rules.New(C, 0)
	Rules.AddShield(t, 10, 0, 5)
	local ev = Rules.Tick(t, 5.1, .1, C)
	yes(ev.ShieldEnded, "timed shield ends")
	near(t.Shield, 0)
end)

test("regen after 8 s without damage, never while downed", function()
	local st = Rules.New(C, 0)
	Rules.Damage(st, 50, 0, C)
	Rules.Tick(st, 7.9, 1, C)
	near(st.HP, 50, 1e-9, "no regen before 8 s")
	local ev = Rules.Tick(st, 8, 1, C)
	near(ev.Regen, 2)
	near(st.HP, 52)
	for i = 1, 40 do
		Rules.Tick(st, 8 + i, 1, C)
	end
	near(st.HP, 100, 1e-9, "capped at MaxHP")
	Rules.Damage(st, 100, 60, C)
	yes(st.Downed)
	Rules.Tick(st, 75, 5, C)
	eq(st.HP, 0, "no regen while downed")
end)

test("downed, bleed-out, weakened", function()
	local st = Rules.New(C, 10)
	local _, res = Rules.Damage(st, 150, 10, C)
	eq(res, "Down")
	yes(st.Downed)
	near(st.DownedUntil, 30)
	local x, r2 = Rules.Damage(st, 10, 11, C)
	eq(x, 0)
	eq(r2, "Downed")
	no(Rules.Tick(st, 29.9, .1, C).BleedOut, "still downed at 19.9 s")
	yes(Rules.Tick(st, 30, .1, C).BleedOut, "bleed-out at 20 s")
	Rules.BleedOut(st, 30, C)
	no(st.Downed)
	eq(st.HP, 60)
	near(st.WeakenedUntil, 55)
	yes(Rules.Weakened(st, 54.9))
	no(Rules.Weakened(st, 55.1))
	near(Rules.DealtMult(st, 40), .7)
	near(Rules.TakenMult(st, 40), 1.25)
	near(Rules.DealtMult(st, 60), 1)
end)

test("revive, H14 shield, self-revive window, hold times", function()
	local st = Rules.New(C, 0)
	Rules.Down(st, 0, C)
	Rules.Revive(st, 2, C, { Shield = 20 })
	no(st.Downed)
	eq(st.HP, 40)
	near(st.Shield, 20)
	eq(select(2, Rules.Damage(st, 10, 2.3, C)), "IFrame", "revive grants i-frames")
	local s2 = Rules.New(C, 0)
	Rules.Down(s2, 100, C)
	local ok, why = Rules.CanSelfRevive(s2, 107.9, C)
	no(ok)
	eq(why, "TooSoon")
	yes(Rules.CanSelfRevive(s2, 108, C), "after 8 s downed")
	s2.SelfReviveUsed = true
	eq(select(2, Rules.CanSelfRevive(s2, 109, C)), "Used")
	near(Rules.ReviveHold(C), 2.2)
	near(Rules.ReviveHold(C, 2), 1.1, 1e-9, "H14 halves")
	near(Rules.ReviveHold(C, 1, 1.4), 2.2 / 1.4, 1e-9, "H11 40% faster")
	near(Rules.ReviveAccept(C, 2.2), 2.2 * .8 - .25, 1e-9)
end)

test("wipe, resume window, H14 max HP", function()
	local a, b = Rules.New(C, 0), Rules.New(C, 0)
	no(Rules.Wiped({ a, b }))
	Rules.Down(a, 1, C)
	no(Rules.Wiped({ a, b }), "one still standing")
	Rules.Down(b, 2, C)
	yes(Rules.Wiped({ a, b }), "everyone down")
	no(Rules.Wiped({}), "an empty zone is not a wipe")
	local left = { Zone = "Arena", St = a, LeftAt = 10 }
	yes(Rules.Resumable(left, "Arena", 40, C))
	no(Rules.Resumable(left, "Arena", 40.5, C))
	no(Rules.Resumable(left, "Mine", 11, C))
	local h = Rules.New(C, 0)
	Rules.Damage(h, 30, 0, C)
	Rules.SetMax(h, 115)
	eq(h.MaxHP, 115)
	eq(h.HP, 85, "the bonus HP arrives filled")
	Rules.SetMax(h, 100)
	eq(h.HP, 85)
end)

---------------------------------------------------------------------------------------------------------------------
-- 5. EventHP (server module) with fake players, positions and a manual clock
---------------------------------------------------------------------------------------------------------------------
local EventHP = L.Require("ServerScriptService.Halloween.EventHP")
local T = 1000
local pos = {}
local sent = {}
local delayed = {}
local dogs = {}
local progress = {}
local gate = nil
local ended = {}
local handlers = {}
local listeners = { Down = {}, Revive = {}, BleedOut = {}, Wipe = {} }
EventHP.Now = function()
	return T
end
EventHP.RootOf = function(pl)
	local p = pos[pl]
	return p and { Position = p } or nil
end
local everyone = {}
EventHP.PlayerList = function()
	return everyone
end
EventHP.Send = function(to, kind, data)
	table.insert(sent, { To = to, Kind = kind, Data = data })
end
EventHP.Spawn = function(fn, ...)
	fn(...)
end
EventHP.Delay = function(_, fn, ...)
	table.insert(delayed, { Fn = fn, Args = table.pack(...) })
end
local fakeCore = {
	OnRequest = function(name, fn)
		handlers[name] = fn
	end,
	Signal = function() end,
}
local fakeModules = {
	Strike = {
		AddCanAct = function(_, fn)
			gate = fn
		end,
		End = function(pl)
			ended[pl] = true
		end,
	},
	Chapter2 = {
		HasTeamDog = function(pl, id)
			return dogs[pl.UserId] ~= nil and dogs[pl.UserId][id] == true
		end,
		Progress = function(pl, key, n)
			table.insert(progress, { Player = pl, Key = key, N = n })
		end,
	},
}
EventHP.Start(fakeCore, fakeModules)
EventHP.OnDown(function(pl, zone, source)
	table.insert(listeners.Down, { pl, zone, source })
end)
EventHP.OnRevive(function(pl, zone, by)
	table.insert(listeners.Revive, { pl, zone, by })
end)
EventHP.OnBleedOut(function(pl, zone, reason)
	table.insert(listeners.BleedOut, { pl, zone, reason })
end)
EventHP.OnWipe(function(zone, players)
	table.insert(listeners.Wipe, { zone, players })
end)

local nextId = 100
local function fakePlayer(at, dogList)
	nextId += 1
	local p = { UserId = nextId, Name = "P" .. nextId, DisplayName = "Dog" .. nextId, Parent = true, Character = nil, Attrs = {} }
	function p:GetAttribute(k)
		return self.Attrs[k]
	end
	function p:SetAttribute(k, v)
		self.Attrs[k] = v
	end
	pos[p] = at
	if dogList then
		dogs[p.UserId] = {}
		for _, id in ipairs(dogList) do
			dogs[p.UserId][id] = true
		end
	end
	table.insert(everyone, p)
	return p
end
local function advance(seconds)
	local steps = math.floor(seconds / .1 + .5)
	for _ = 1, steps do
		T += .1
		EventHP.Tick(.1)
	end
end
local function sentTo(pl, kind, sub)
	local out = {}
	for _, s in ipairs(sent) do
		if s.To == pl and s.Kind == kind and (sub == nil or (type(s.Data) == "table" and s.Data.Kind == sub)) then
			table.insert(out, s.Data)
		end
	end
	return out
end
local function cleanup(...)
	for _, pl in ipairs({ ... }) do
		EventHP.Forget(pl)
		local i = table.find(everyone, pl)
		if i then
			table.remove(everyone, i)
		end
	end
	table.clear(sent)
end

test("EventHP: enter, damage, attributes and who sees the numbers", function()
	local a = fakePlayer(V3(0, 3, 0))
	local near_ = fakePlayer(V3(30, 3, 0))
	local far = fakePlayer(V3(400, 3, 0))
	yes(EventHP.Enter(a, "T1", { Spawn = V3(0, 0, -50), Name = { "TEST", "ТЕСТ" } }))
	eq(a.Attrs.HwCombat, true)
	eq(a.Attrs.HwHP, 100)
	eq(a.Attrs.HwHPMax, 100)
	eq(a.Attrs.HwCombatZone, "T1")
	eq(#sentTo(a, "Combat", "Enter"), 1)
	local applied = EventHP.Damage(a, 12.4, "Slam", {})
	near(applied, 12.4)
	eq(a.Attrs.HwHP, 88, "half-step rounding up")
	eq(#sentTo(a, "Combat", "Hit"), 1, "the player")
	eq(#sentTo(near_, "Combat", "Hit"), 1, "a nearby player sees the number")
	eq(#sentTo(far, "Combat", "Hit"), 0, "a far player does not")
	eq(EventHP.Damage(a, 10, "Slam"), 0, "i-frames")
	eq(EventHP.Damage(near_, 10, "Slam"), 0, "not in combat: no Event HP")
	no(EventHP.InCombat(near_))
	eq(EventHP.Zone(a), "T1")
	cleanup(a, near_, far)
end)

test("EventHP: downed blocks strikes, slows nothing it cannot find, signals the zone", function()
	local a = fakePlayer(V3(0, 3, 0))
	local b = fakePlayer(V3(5, 3, 0))
	EventHP.Enter(a, "T2")
	EventHP.Enter(b, "T2")
	table.clear(listeners.Down)
	EventHP.Damage(a, 200, "Slam")
	yes(EventHP.IsDowned(a))
	eq(a.Attrs.HwDowned, true)
	near(a.Attrs.HwDownedUntil, T + 20)
	eq(a.Attrs.HwHP, 0)
	yes(ended[a], "the strike session ended")
	local ok, err = gate(a)
	no(ok)
	eq(err, "HW:DOWNED")
	yes(gate(b), "the standing ally may strike")
	eq(#listeners.Down, 1)
	eq(#sentTo(b, "Combat", "Down"), 1, "the zone hears the down")
	no(EventHP.CanTarget(a), "the boss skips downed players")
	yes(EventHP.CanTarget(b))
	eq(#listeners.Wipe, 0, "one ally standing: no wipe")
	cleanup(a, b)
end)

test("EventHP: revive hold is checked on the server (time, distance, H14)", function()
	local a = fakePlayer(V3(0, 3, 0))
	local b = fakePlayer(V3(4, 3, 0))
	local far = fakePlayer(V3(30, 3, 0))
	EventHP.Enter(a, "T3")
	EventHP.Enter(b, "T3")
	EventHP.Enter(far, "T3")
	EventHP.Down(a, "Test")
	no(EventHP.ReviveHold(a, a, "Began"), "no self revive by prompt")
	no(EventHP.ReviveHold(a, far, "Began"), "out of range")
	yes(EventHP.ReviveHold(a, b, "Began"))
	eq(a.Attrs.HwReviveBy, b.UserId)
	T += 1.0
	no(EventHP.ReviveHold(a, b, "Triggered"), "1.0 s is too short for a 2.2 s hold")
	yes(EventHP.IsDowned(a))
	eq(a.Attrs.HwReviveBy, 0)
	yes(EventHP.ReviveHold(a, b, "Began"))
	T += 1.6
	table.clear(listeners.Revive)
	table.clear(progress)
	yes(EventHP.ReviveHold(a, b, "Triggered"))
	no(EventHP.IsDowned(a))
	eq(a.Attrs.HwHP, 40)
	eq(a.Attrs.HwShield, 0)
	eq(#listeners.Revive, 1)
	eq(listeners.Revive[1][3], b)
	eq(#progress, 1)
	eq(progress[1].Key, "Revive")
	-- an H14 Bridehound reviver: half the hold and a 20 HP shield on the ally
	local c = fakePlayer(V3(0, 3, 6))
	local bride = fakePlayer(V3(2, 3, 6), { "HW_Bridehound" })
	EventHP.Enter(c, "T3")
	EventHP.Enter(bride, "T3")
	eq(bride.Attrs.HwHPMax, 115, "ETERNAL VOW +15 max HP")
	eq(bride.Attrs.HwReviveSpeed, 2)
	EventHP.Down(c, "Test")
	EventHP.ReviveHold(c, bride, "Began")
	T += .7
	yes(EventHP.ReviveHold(c, bride, "Triggered"), ".7 s is enough at 2x")
	eq(c.Attrs.HwShield, 20)
	cleanup(a, b, far, c, bride)
end)

test("EventHP: bleed-out after 20 s, WEAKENED, damage multipliers", function()
	local a = fakePlayer(V3(0, 3, 0))
	local b = fakePlayer(V3(3, 3, 0))
	EventHP.Enter(a, "T4", { Spawn = V3(0, 0, -40) })
	EventHP.Enter(b, "T4")
	table.clear(listeners.BleedOut)
	EventHP.Down(a, "Test")
	local downAt = T
	advance(19.8)
	yes(EventHP.IsDowned(a), "still downed")
	advance(.4)
	no(EventHP.IsDowned(a), "bled out")
	eq(a.Attrs.HwHP, 60)
	near(a.Attrs.HwWeakenedUntil, downAt + 20 + 25, .15)
	eq(#listeners.BleedOut, 1)
	eq(listeners.BleedOut[1][3], "Timer")
	near(EventHP.DamageMult(a), .7)
	near(EventHP.TakenMult(a), 1.25)
	T += 1
	local applied = EventHP.Damage(a, 10, "Slam")
	near(applied, 12.5, 1e-9, "+25% taken")
	near(EventHP.DamageMult(b), 1)
	cleanup(a, b)
end)

test("EventHP: team wipe fires once, then everyone left downed bleeds out", function()
	local a = fakePlayer(V3(0, 3, 0))
	local b = fakePlayer(V3(3, 3, 0))
	EventHP.Enter(a, "T5")
	EventHP.Enter(b, "T5")
	table.clear(listeners.Wipe)
	table.clear(listeners.BleedOut)
	table.clear(delayed)
	EventHP.Down(a, "Test")
	eq(#listeners.Wipe, 0)
	EventHP.Down(b, "Test")
	eq(#listeners.Wipe, 1, "wipe")
	eq(listeners.Wipe[1][1], "T5")
	eq(#listeners.Wipe[1][2], 2)
	eq(#sentTo(a, "Combat", "Wipe"), 1)
	eq(#delayed, 1, "the fallback waits WipeGrace")
	delayed[1].Fn(table.unpack(delayed[1].Args, 1, delayed[1].Args.n))
	no(EventHP.IsDowned(a))
	no(EventHP.IsDowned(b))
	eq(a.Attrs.HwHP, 60)
	eq(#listeners.BleedOut, 0, "a wipe is not reported as single bleed-outs")
	cleanup(a, b)
end)

test("EventHP: hazards hit the zone at ImpactAt with the .12 s grace; H10 sees them early", function()
	local a = fakePlayer(V3(0, 3, 0))
	local b = fakePlayer(V3(20, 3, 0))
	local late = fakePlayer(V3(9, 3, 0))
	local candle = fakePlayer(V3(0, 3, 20), { "HW_CandleCorgi" })
	local spectator = fakePlayer(V3(60, 3, 0)) -- not in combat: sees it, never takes damage
	for _, p in ipairs({ a, b, late, candle }) do
		EventHP.Enter(p, "T6")
	end
	table.clear(sent)
	local id = EventHP.Hazard("T6", { Shape = Hazards.Circle(V3(0, 0, 0), 6), Telegraph = 1, Damage = 14, Kind = "Slam", Source = "Test" })
	yes(id ~= nil)
	local mine = Hazards.Decode(sentTo(a, "Hazard")[1])
	near(mine.ImpactAt, T + .35 + 1, 1e-9, "ImpactAt = now + H10 lead + telegraph")
	near(mine.ShowAt, T + .35, 1e-9)
	near(Hazards.Decode(sentTo(candle, "Hazard")[1]).ShowAt, T, 1e-9, "CANDLELIGHT: .35 s earlier")
	eq(#sentTo(spectator, "Hazard"), 1, "a nearby spectator sees the telegraph")
	advance(1.3)
	pos[late] = V3(0, 3, 0) -- steps in at the last moment: was outside at ImpactAt - .12
	advance(.2)
	eq(a.Attrs.HwHP, 86, "standing in it")
	eq(b.Attrs.HwHP, 100, "outside")
	eq(late.Attrs.HwHP, 100, "the grace spares a late step-in")
	eq(spectator.Attrs.HwHP, nil)
	cleanup(a, b, late, candle, spectator)
end)

test("EventHP: lingering gas (H10 -30%) and a moving safe circle", function()
	local a = fakePlayer(V3(40, 3, 0))
	local candle = fakePlayer(V3(41, 3, 0), { "HW_CandleCorgi" })
	EventHP.Enter(a, "T7")
	EventHP.Enter(candle, "T7")
	EventHP.Hazard("T7", { Shape = Hazards.Circle(V3(40, 0, 0), 5), Telegraph = 1, Damage = 0, DPS = 6, Linger = 2, Kind = "Gas", Source = "Vent" })
	advance(1.4) -- telegraph + lead
	advance(2.2)
	local lost = 100 - a.Attrs.HwHP
	yes(lost >= 9 - 1e-6 and lost <= 12 + 1e-6, "3-4 ticks of 3 HP, lost " .. lost)
	local lostC = 100 - candle.Attrs.HwHP
	yes(lostC < lost, "CANDLELIGHT takes less gas damage")
	cleanup(a, candle)
	local follower = fakePlayer(V3(0, 3, -100))
	local idle = fakePlayer(V3(0, 3, -130))
	EventHP.Enter(follower, "T8")
	EventHP.Enter(idle, "T8")
	local path = { { At = 0, Center = V3(0, 0, -100) }, { At = 4, Center = V3(0, 0, -90) } }
	EventHP.Hazard("T8", { Shape = Hazards.Safe(V3(0, 0, -100), 9, 40, { Path = path }), Telegraph = 1.2, Damage = 0, DPS = 7, Linger = 4,
		Kind = "Lantern", Source = "Test" })
	local start = T + .35 + 1.2
	for _ = 1, 60 do
		T += .1
		local c = Hazards.PathCenter({ Path = path }, T - start) or V3(0, 0, -100)
		pos[follower] = V3(c.X, 3, c.Z)
		EventHP.Tick(.1)
	end
	eq(follower.Attrs.HwHP, 100, "inside the moving lantern: safe")
	yes(idle.Attrs.HwHP < 90, "left outside: 7 HP/s")
	cleanup(follower, idle)
end)

test("EventHP: unfair defs are made fair, waves and cancels", function()
	local a = fakePlayer(V3(0, 3, 0))
	EventHP.Enter(a, "T9")
	table.clear(sent)
	EventHP.Hazard("T9", { Shape = Hazards.Circle(V3(0, 0, 0), 4), Telegraph = .3, Damage = 80, Kind = "Slam", ImpactAt = T + .3 })
	local d = Hazards.Decode(sentTo(a, "Hazard")[1])
	near(d.Damage, 45, 1e-9, "capped at 45% of 100")
	near(d.Telegraph, 1.2, 1e-9, "heavy hit telegraph")
	yes(d.ImpactAt >= T + 1.2 - 1e-9, "the impact waits for the whole telegraph")
	EventHP.SetZone("T9", { Trial = true })
	table.clear(sent)
	EventHP.Hazard("T9", { Shape = Hazards.Circle(V3(0, 0, 0), 4), Telegraph = 2, Damage = 80, Kind = "Slam" })
	near(Hazards.Decode(sentTo(a, "Hazard")[1]).Damage, 40, 1e-9, "trial zones cap at 40%")
	EventHP.CancelHazards("T9")
	-- a Seals run enters with its trial id as the marker
	local runner = fakePlayer(V3(0, 3, 0))
	EventHP.Enter(runner, "Trial:HollowMine", { Trial = "HollowMine", Spawn = V3(0, 0, -30) })
	table.clear(sent)
	EventHP.Hazard("Trial:HollowMine", { Shape = Hazards.Circle(V3(0, 0, 0), 4), Telegraph = 2, Damage = 60, Kind = "Rock" })
	near(Hazards.Decode(sentTo(runner, "Hazard")[1]).Damage, 40, 1e-9, "a trial id marks a trial zone")
	EventHP.CancelHazards("Trial:HollowMine")
	cleanup(runner)
	table.clear(sent)
	local ids = EventHP.HazardWave("T9", {
		{ Shape = Hazards.Circle(V3(10, 0, 0), 3), Telegraph = 1, Damage = 8, Kind = "BoneRain" },
		{ Shape = Hazards.Circle(V3(-10, 0, 0), 3), Telegraph = 1, Damage = 8, Kind = "BoneRain", Delay = .2 },
		{ Shape = Hazards.Circle(V3(0, 0, 0), 3), Telegraph = 1, Damage = 8, Kind = "BoneRain", Delay = .4 },
	})
	eq(#ids, 3)
	local waves = sentTo(a, "Hazard")
	eq(#waves, 1, "one signal for the wave")
	eq(#waves[1].List, 3)
	eq(EventHP.CancelHazards("T9", { ids[3] }), 1)
	local cancel = sentTo(a, "Hazard")[2]
	eq(cancel.Cancel[1], ids[3])
	advance(2.5)
	eq(a.Attrs.HwHP, 100, "the cancelled circle never lands")
	cleanup(a)
end)

test("EventHP: leave clears attributes, re-enter within 30 s keeps HP", function()
	local a = fakePlayer(V3(0, 3, 0))
	EventHP.Enter(a, "T10")
	EventHP.Damage(a, 30, "Test")
	yes(EventHP.Leave(a, "T10"))
	eq(a.Attrs.HwCombat, nil)
	eq(a.Attrs.HwHP, nil)
	no(EventHP.Leave(a), "already out")
	T += 10
	EventHP.Enter(a, "T10")
	eq(a.Attrs.HwHP, 70, "resumed")
	EventHP.Leave(a)
	T += 31
	EventHP.Enter(a, "T10")
	eq(a.Attrs.HwHP, 100, "fresh after 30 s")
	EventHP.Down(a, "Test")
	EventHP.Leave(a)
	eq(a.Attrs.HwDowned, nil, "leaving while downed gets up")
	no(EventHP.IsDowned(a))
	no(EventHP.Leave(a, "Other"), "only that zone")
	cleanup(a)
end)

test("EventHP: C2SelfRevive (H11 MOURNING VEIL)", function()
	local plain = fakePlayer(V3(0, 3, 0))
	local shiba = fakePlayer(V3(2, 3, 0), { "HW_MourningShiba" })
	local friend = fakePlayer(V3(4, 3, 0))
	for _, p in ipairs({ plain, shiba, friend }) do
		EventHP.Enter(p, "T11")
	end
	local ok, err = handlers.C2SelfRevive(friend)
	no(ok)
	eq(err, "You are not downed")
	EventHP.Down(plain, "Test")
	ok, err = handlers.C2SelfRevive(plain)
	no(ok)
	eq(err, "MOURNING VEIL needs the Mourning Shiba in your yard team")
	EventHP.Down(shiba, "Test")
	near(shiba.Attrs.HwSelfReviveAt, T + 8, 1e-9)
	eq(plain.Attrs.HwSelfReviveAt, 0)
	T += 7
	ok, err = handlers.C2SelfRevive(shiba)
	no(ok)
	eq(err, "MOURNING VEIL is not ready yet")
	T += 1.1
	ok = handlers.C2SelfRevive(shiba)
	yes(ok)
	eq(shiba.Attrs.HwHP, 40)
	T += 1
	EventHP.Down(shiba, "Test")
	T += 9
	ok, err = handlers.C2SelfRevive(shiba)
	no(ok)
	eq(err, "MOURNING VEIL was already used in this fight")
	eq(shiba.Attrs.HwSelfReviveAt, 0, "the button is gone once used")
	-- the target speed of H11: an ally revives the shiba 40% faster
	EventHP.ReviveHold(shiba, friend, "Began")
	T += 1.1
	yes(EventHP.ReviveHold(shiba, friend, "Triggered"), "1.1 s >= .8 x 2.2 / 1.4 - .25")
	cleanup(plain, shiba, friend)
end)

---------------------------------------------------------------------------------------------------------------------
-- 6. Strike: the global CanAct gates and the EventMult opt-in
---------------------------------------------------------------------------------------------------------------------
test("Strike: CanAct gates and EventMult registration (Chapter I untouched)", function()
	local Strike = L.Require("ServerScriptService.Halloween.Strike")
	yes(Strike.CheckCanAct({}), "no gates: everyone may strike")
	Strike.AddCanAct("Test", function(pl)
		if pl.Downed then
			return false, "HW:DOWNED"
		end
		return true
	end)
	local ok, err = Strike.CheckCanAct({ Downed = true })
	no(ok)
	eq(err, "HW:DOWNED")
	yes(Strike.CheckCanAct({ Downed = false }))
	Strike.AddCanAct("Test", function()
		return false, "HW:OTHER"
	end)
	eq(#Strike.CanAct, 1, "re-adding a name replaces it")
	eq(select(2, Strike.CheckCanAct({})), "HW:OTHER")
	Strike.AddCanAct("Broken", function()
		error("boom")
	end)
	Strike.RemoveCanAct("Test")
	yes(Strike.CheckCanAct({}), "a failing gate never blocks play")
	Strike.RemoveCanAct("Broken")
	eq(#Strike.CanAct, 0)
	eq(Strike.Register("WPBPlain", {}).EventMult, nil, "Chapter I kinds do not opt in")
	eq(Strike.Register("WPBApply", { EventMult = "Apply" }).EventMult, "Apply")
	eq(Strike.Register("WPBExpose", { EventMult = true }).EventMult, true)
	eq(Strike.Register("WPBJunk", { EventMult = "yes" }).EventMult, nil)
end)

print(string.format("combat: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("combat tests failed")
end
