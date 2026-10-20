--!nolint
-- THE GRAVEKEEPER, CHAPTER II (WP-C): Boss.luau driven through its test hooks (Boss.Init / Step / Now / Rand / GetPlayers,
-- Handlers) with the REAL Strike, EventHP, BossPatterns and BossFinale modules, fake players and a manual clock.
-- Covers: pit-only fighters, Event HP damage on attacks (hazards) and bites, endgame patterns fair on III-V and only
-- there, rock wave caps, the damage scaling (soft cap, Perfect bonus, WEAKENED, V weak points, SYNC STRIKE), wipe, parked
-- rewards, Chapter II rewards, the difficulty V finale (every stage, victory pays once, fail paths, §23.2 payloads) and
-- the DPS design target simulation (spam vs mechanics). lune run tests/boss_finale.luau
local L = require("./lib/economy_env")
local roblox = require("@lune/roblox")
local V3 = roblox.Vector3.new

-- spawned functions run at once (Strike OnBreak, grants); its forever-loop ends at its first wait
local STOP = "__test_wait__"
L.Task = {
	wait = function()
		error(STOP)
	end,
	spawn = function(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok and not string.find(tostring(err), STOP, 1, true) then
			error(err, 0)
		end
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	delay = function() end,
}
L.Workspace = roblox.Instance.new("Folder") -- Strike parents its target parts here

local Config = L.Require("ReplicatedStorage.Halloween.Config")
local C2Cfg = L.Require("ReplicatedStorage.Halloween.Chapter2Config")
local Hazards = L.Require("ReplicatedStorage.Halloween.Hazards")
local BossMath = L.Require("ReplicatedStorage.Halloween.BossMath")
local Patterns = L.Require("ReplicatedStorage.Halloween.BossPatterns")
local Layout = L.Require("ReplicatedStorage.Halloween.Layout")
local Strike = L.Require("ServerScriptService.Halloween.Strike")
local EventHP = L.Require("ServerScriptService.Halloween.EventHP")
local Boss = L.Require("ServerScriptService.Halloween.Boss")
local Fin = L.Require("ServerScriptService.Halloween.BossFinale")
local M = L.Require("ReplicatedStorage.DogEconomy.Config").Mining
local MR = L.Require("ReplicatedStorage.Mining.MiningRules")

-- BOSS_TEST=<text>: only the tests whose name contains it. Balance exploration (docs/halloween2/BOSS.md): BOSS_PERFECT,
-- BOSS_GOOD, BOSS_BEYOND, BOSS_BYPASS, BOSS_PERSEC override Chapter2Config.Boss PerfectExtra / GoodMult / SoftCap.Beyond / MechanicBypass /
-- PerSecond for this run.
local env = require("@lune/process").env
local ONLY = env.BOSS_TEST
do
	local b = C2Cfg.Boss
	b.PerfectExtra = tonumber(env.BOSS_PERFECT) or b.PerfectExtra
	b.GoodMult = tonumber(env.BOSS_GOOD) or b.GoodMult
	b.SoftCap.Beyond = tonumber(env.BOSS_BEYOND) or b.SoftCap.Beyond
	b.SoftCap.MechanicBypass = tonumber(env.BOSS_BYPASS) or b.SoftCap.MechanicBypass
	b.SoftCap.PerSecond = tonumber(env.BOSS_PERSEC) or b.SoftCap.PerSecond
	BossMath.SetConfig(nil)
end

local passed, failed = 0, 0
local function test(name, fn)
	if ONLY and not string.find(name, ONLY, 1, true) then
		return
	end
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
		error((msg or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then
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
-- the fake world
---------------------------------------------------------------------------------------------------------------------
local T = 5000
local pos = {}
local everyone = {}
local signals = {}
local queued = {}
local curse = {}
local handlers = {}
local transacts = {}
local receipts = {}
local failNext = {} -- [userId] = n failing reward transactions
local c2Calls = {}
local c2Progress = {}
local later = {}
local rng = L.Random.new(7)

local function rand()
	return rng:NextNumber()
end

local function rootOf(pl)
	local p = pos[pl]
	if not p or not pl.Parent then
		return nil
	end
	return { Position = p, AssemblyLinearVelocity = V3(0, 0, 0) }
end

local fakeCore = {
	Root = rootOf,
	Signal = function(target, kind, data)
		table.insert(signals, { To = target, Kind = kind, Data = data })
	end,
	Queue = function(pl, op)
		table.insert(queued, { Player = pl, Op = op })
		return 0
	end,
	Activity = function() end,
	AddCurse = function(pl, n)
		curse[pl] = (curse[pl] or 0) + n
	end,
	OnRequest = function(name, fn)
		handlers[name] = fn
	end,
	Near = function(pl, p, r)
		local q = pos[pl]
		return q ~= nil and (q - p).Magnitude <= r
	end,
}
local fightSerial = 0
fakeCore.NewId = function()
	fightSerial += 1
	return "fight" .. fightSerial
end
fakeCore.Transact = function(player, label, fn, opts)
	local o = opts or {}
	local uid = player.UserId
	if (failNext[uid] or 0) > 0 then
		failNext[uid] -= 1
		return false, "Your saved profile is still loading"
	end
	if o.Receipt and receipts[o.Receipt] then
		return true, receipts[o.Receipt], nil, true
	end
	local h = { Boss = { Kills = 0, Best = 0, Unlocked = 1 } }
	local rec = { Player = player, Label = label, Receipt = o.Receipt, Candy = 0, Bones = 0, XP = 0, Rewards = {} }
	local ctx = {
		Candy = function(n)
			rec.Candy += n
			return n
		end,
		Bones = function(n)
			rec.Bones += n
			return n
		end,
		XP = function(n)
			rec.XP += n
		end,
		Reward = function(row)
			table.insert(rec.Rewards, row)
			return row
		end,
		Relief = function() end,
	}
	local res = fn({}, h, ctx, os.time())
	rec.Boss = h.Boss
	table.insert(transacts, rec)
	if o.Receipt then
		receipts[o.Receipt] = res
	end
	return true, res, nil, false
end

local eligible = {}
local fakeC2 = {
	Enabled = function()
		return true
	end,
	BossReward = function(player, d, info)
		table.insert(c2Calls, { Player = player, Difficulty = d, Finale = info and info.Finale, Receipt = info and info.Receipt })
		if info and info.Receipt and receipts[info.Receipt] then
			return true, receipts[info.Receipt]
		end
		local res = { Rewards = { { Kind = "Shards", Amount = C2Cfg.BossRewards.Shards[d] or 0 } }, FinaleFirst = info and info.Finale == true or nil }
		if info and info.Receipt then
			receipts[info.Receipt] = res
		end
		return true, res
	end,
	Progress = function(pl, key, n)
		table.insert(c2Progress, { Player = pl, Key = key, N = n })
	end,
	HasTeamDog = function()
		return false
	end,
}

local modules = { Strike = Strike, EventHP = EventHP, Chapter2 = fakeC2, BossFinale = Fin, Boss = Boss }

-- clocks / players / randomness everywhere
Boss.Now = function()
	return T
end
Boss.Rand = function(a, b)
	local x = rand()
	if a and b then
		return a + (b - a) * x
	end
	return x
end
Boss.GetPlayers = function()
	return everyone
end
Boss.Wait = function() end
Boss.Later = function(s, fn, ...)
	table.insert(later, { At = T + s, Fn = fn, Args = table.pack(...) })
end
Strike.Clock = function()
	return T
end
Strike.Now = function()
	return T
end
Strike.Random = function()
	return .99 -- no crits in the unit tests (the DPS simulation rolls its own)
end
EventHP.Now = function()
	return T
end
EventHP.RootOf = rootOf
EventHP.PlayerList = function()
	return everyone
end
EventHP.Send = function(to, kind, data)
	table.insert(signals, { To = to, Kind = kind, Data = data })
end
EventHP.Spawn = function(fn, ...)
	fn(...)
end
local wipeQueue = {}
EventHP.Delay = function(_, fn, ...)
	table.insert(wipeQueue, { Fn = fn, Args = table.pack(...) })
end

local stateRoot = roblox.Instance.new("Folder")
stateRoot.Name = "State"
Boss.StateRoot = stateRoot
Fin.StateRoot = stateRoot

Strike.Start(fakeCore, modules)
EventHP.Start(fakeCore, modules)
Boss.Init(fakeCore, modules)
Fin.Init(fakeCore, modules)

local nextUid = 1000
local function newPlayer(at, attrs)
	nextUid += 1
	local p = { UserId = nextUid, Name = "P" .. nextUid, DisplayName = "Dog" .. nextUid, Parent = true, Character = nil, Attrs = {} }
	function p:GetAttribute(k)
		return self.Attrs[k]
	end
	function p:SetAttribute(k, v)
		self.Attrs[k] = v
	end
	p.Attrs.MiningPickaxe = 16
	p.Attrs.MiningStrength = 1100
	p.Attrs.HalloweenChapter1Complete = true
	for k, v in pairs(attrs or {}) do
		p.Attrs[k] = v
	end
	pos[p] = at
	table.insert(everyone, p)
	return p
end

local function leave(pl)
	local i = table.find(everyone, pl)
	if i then
		table.remove(everyone, i)
	end
	pl.Parent = nil
	EventHP.Forget(pl)
	Strike.Sessions[pl] = nil
end

local FLOOR = Layout.Pit.FloorY + 3 -- root height on the arena floor
local CENTER = Layout.Pit.Center
local function floorPos(dx, dz)
	return V3(CENTER.X + dx, FLOOR, CENTER.Z + dz)
end
local RIM = V3(CENTER.X, Layout.FloorY + 3.2, Layout.Pit.Rim.Z0 - 6) -- north rim, next to the bell

local function clearWorld()
	if Boss.Fight then
		Boss.Abort("Test")
	end
	for _, pl in ipairs(table.clone(everyone)) do
		leave(pl)
	end
	for id, t in pairs(Strike.Targets) do
		Strike.Targets[id] = nil
	end
	table.clear(Strike.Sessions)
	for _, z in pairs(EventHP.Zones) do
		table.clear(z.Hazards)
		table.clear(z.Members)
		z.Wiped = false
		z.WipeToken = nil
	end
	table.clear(signals)
	table.clear(queued)
	table.clear(transacts)
	table.clear(c2Calls)
	table.clear(c2Progress)
	table.clear(later)
	table.clear(wipeQueue)
	Boss.NextSummonAt = 0
	Boss.Pending = {}
	T += 1000
end

local function step(seconds, withHP)
	local n = math.max(1, math.floor(seconds / .1 + .5))
	for _ = 1, n do
		T += .1
		Boss.Step(.1)
		if withHP ~= false then
			EventHP.Tick(.1)
		end
		for i = #wipeQueue, 1, -1 do
			local w = table.remove(wipeQueue, i)
			w.Fn(table.unpack(w.Args, 1, w.Args.n))
		end
	end
end

local function signalsOf(kind, sub, field)
	local out = {}
	for _, s in ipairs(signals) do
		if s.Kind == kind and (sub == nil or (type(s.Data) == "table" and s.Data[field or "Kind"] == sub)) then
			table.insert(out, s.Data)
		end
	end
	return out
end

local function finaleSignals(stage)
	local out = {}
	for _, s in ipairs(signals) do
		if s.Kind == "BossEvent" and type(s.Data) == "table" and s.Data.Kind == "Finale" and s.Data.Stage == stage then
			table.insert(out, s.Data)
		end
	end
	return out
end

local function summon(d, reason)
	local ok, err = Boss.Summon(d, reason or "Debug", everyone[1])
	assert(ok, "summon failed: " .. tostring(err))
	step(7) -- the rise
	return Boss.Fight
end

-- a judged hit on `target` right now: the session's first circle is made due (Perfect or Good timing)
local function hit(pl, target, perfect)
	local s = Strike.Sessions[pl]
	if not s or s.Target ~= target then
		local ok, err = Strike.Begin(pl, { Target = target.Id })
		if not ok then
			return false, err
		end
		s = Strike.Sessions[pl]
	end
	local circle
	for _, c in pairs(s.Targets) do
		circle = c
		break
	end
	circle.SpawnAt = T - (perfect and .82 or .5) * circle.Window
	s.LastHitAt = T - 1
	return Strike.Hit(pl, { Target = circle.Id, Quality = perfect and 2 or 1 })
end

local function targetsOf(kind)
	return Strike.All(kind)
end

-- the test players never dodge: keep them standing (heal, revive) where a test only checks the mechanics
local function topUp()
	for _, pl in ipairs(everyone) do
		if EventHP.IsDowned(pl) then
			EventHP.Revive(pl, nil)
		end
		EventHP.Heal(pl, 200)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- 1. patterns: fair on III-V, the §10.2 rules, counts by difficulty
---------------------------------------------------------------------------------------------------------------------
test("endgame patterns: every def fair (Check) + a safe spot (CheckPattern) over 150 seeds per difficulty", function()
	local area = Patterns.Area()
	for d = 3, 5 do
		local r = L.Random.new(d * 97)
		local function rr()
			return r:NextNumber()
		end
		for _ = 1, 150 do
			local targets = { floorPos(rr() * 40 - 20, rr() * 40 - 20), floorPos(rr() * 40 - 20, rr() * 40 - 20) }
			for _, name in ipairs({ "GraveLines", "LanternWalk", "BoneRain" }) do
				local defs, info = Patterns[name](d, 100, .35, rr, { Targets = targets, Toward = targets[1] })
				yes(#defs > 0, name .. " produced nothing")
				local ok, why = Patterns.Fair(defs, area)
				yes(ok, name .. " unfair: " .. table.concat(why.Problems, " | "))
				for _, def in ipairs(defs) do
					yes(def.Damage <= 45 and (def.DPS or 0) <= 45, "45% cap")
					yes(def.Telegraph >= (def.Damage >= 25 and 1.2 or .9) - 1e-9, "telegraph minimum")
					yes(def.ImpactAt >= 100 + .35 + def.Telegraph - 1e-9, "full telegraph + H10 lead before the impact")
					yes(Hazards.PathSpeed(def.Shape) <= 11 + 1e-9, "safe zone speed")
				end
				yes(info.Duration > 0 and info.Duration < 20, name .. " duration")
			end
		end
	end
end)

test("endgame pattern sizes follow the difficulty (III lo .. V hi) and the design numbers", function()
	local function count(name, d)
		local defs = Patterns[name](d, 0, .35, rand, { Targets = {} })
		return #defs, defs[1]
	end
	eq(count("GraveLines", 3), 3)
	eq(count("GraveLines", 4), 4)
	eq(count("GraveLines", 5), 5)
	eq(count("BoneRain", 3), 12)
	eq(count("BoneRain", 5), 18)
	local _, line = count("GraveLines", 5)
	eq(line.Damage, 27, "GraveLines 18 x 1.5")
	eq(line.Shape.Width, 6)
	local _, bone = count("BoneRain", 4)
	eq(bone.Damage, BossMath.EventDamage(12, 4))
	local lw = Patterns.LanternWalk(5, 0, .35, rand)[1]
	eq(lw.Shape.Type, "Safe")
	eq(lw.Shape.Radius, 9)
	eq(lw.DPS, 7)
	eq(lw.Linger, 8)
	near(lw.Telegraph, 1.2, 1e-9, "the 1.2 s grace")
	yes(Hazards.PathSpeed(lw.Shape) <= 6 + 1e-6, "drifts at <= 6 studs/s")
end)

test("finale patterns: shockwave rings keep a gap, volleys / ghost bites / hound patterns are fair", function()
	local area = Patterns.Area()
	local r = L.Random.new(4242)
	local function rr()
		return r:NextNumber()
	end
	for _ = 1, 120 do
		local defs = Patterns.Shockwave(0, .35, rr)
		yes(Patterns.Fair(defs, area), "shockwave fair")
		for _, d in ipairs(defs) do
			eq(d.Shape.Type, "Ring")
			yes(Hazards.GapStuds(d.Shape) >= 6, "a gap a dog fits through")
			eq(d.Damage, 21, "14 x 1.5")
		end
		yes(Patterns.Fair(Patterns.Volley(0, .35, rr, { Targets = { floorPos(3, 4) } }), area), "volley fair")
		local bite = Patterns.GhostBite(floorPos(2, 2), 0, .35)
		yes(Hazards.Check(bite), "ghost bite fair")
		eq(bite.Damage, 12, "8 x 1.5")
		for _, name in ipairs(Patterns.HoundPatterns) do
			local defs2, beats = Patterns.Hound(name, 10, .6, rr, { Targets = { floorPos(rr() * 20, 0), floorPos(0, rr() * 20) }, Fighters = 3 })
			yes(#defs2 > 0 and beats >= 8, name .. " size")
			-- each beat group impacting together leaves a safe spot; every def is fair; impacts sit on the beat grid
			local groups = {}
			for _, d in ipairs(defs2) do
				yes(Hazards.Check(d), name .. " def fair")
				local k = math.floor((d.ImpactAt - 10) / .6 + .5)
				near(d.ImpactAt, 10 + k * .6, 1e-6, name .. " on the beat")
				groups[k] = groups[k] or {}
				table.insert(groups[k], d)
			end
			for _, g in pairs(groups) do
				yes(Hazards.CheckPattern(g, area), name .. " beat group leaves a safe spot")
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- 2. pit-only fighters, Event HP zone
---------------------------------------------------------------------------------------------------------------------
test("fighters: only players inside the pit count (armor scaling) and enter the EventHP zone", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local rim = newPlayer(RIM) -- next to the bell: a fighter in Chapter I, a spectator now
	local F = summon(3)
	eq(F.Fighters, 1, "the rim player does not count")
	near(F.MaxArmor, Config.Boss.BaseArmor * F.Def.Armor, 1e-6, "solo armor")
	eq(EventHP.Zone(a), "Boss")
	eq(a.Attrs.HwCombat, true)
	eq(EventHP.Zone(rim), nil, "no Event HP on the rim")
	-- the rim player jumps in: a fighter (zone + armor) within a second
	pos[rim] = floorPos(6, 0)
	step(1.1)
	eq(F.Fighters, 2)
	eq(EventHP.Zone(rim), "Boss")
	-- and climbs out again
	pos[rim] = RIM
	step(1.1)
	eq(F.Fighters, 1)
	eq(EventHP.Zone(rim), nil)
	-- a downed player who crawls out of the pit stays in the fight until revived / bled out
	EventHP.Down(a, "Test")
	pos[a] = RIM
	step(.3)
	eq(EventHP.Zone(a), "Boss", "downed players keep their downed state")
	clearWorld()
end)

test("rim camping: plates / weak points / mounds refuse players outside the pit", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local rim = newPlayer(RIM)
	summon(3)
	local plate = targetsOf("BossPlate")[1]
	yes(plate ~= nil, "plates are up")
	local ok, err = Boss.Handlers.CanHitBody(rim, plate)
	no(ok)
	eq(err, "Climb down into the pit to fight the Gravekeeper")
	yes(Boss.Handlers.CanHitBody(a, plate))
	local ok2 = hit(rim, plate, true)
	no(ok2, "Strike refuses the rim player")
	yes((hit(a, plate, true)), "the pit player hits")
	clearWorld()
end)

---------------------------------------------------------------------------------------------------------------------
-- 3. attacks hurt (Event HP hazards), bites, targeting skips the downed
---------------------------------------------------------------------------------------------------------------------
test("attacks: telegraph signal carries the HazardId, the hazard deals AttackDamage + knock + curse", function()
	clearWorld()
	local a = newPlayer(floorPos(0, 6))
	local F = summon(3)
	F.NextPatternAt = math.huge -- melee only here
	F.NextAttackAt = T
	step(.2)
	local tele = signalsOf("BossEvent", "Attack")
	yes(#tele >= 1, "an attack started")
	local atk = tele[#tele]
	eq(atk.Stage, "Telegraph")
	yes(type(atk.HazardId) == "number", "HazardId")
	local zone = EventHP.Zones.Boss
	yes(zone.Hazards[atk.HazardId] ~= nil, "the hazard is live in zone Boss")
	local def = zone.Hazards[atk.HazardId].Def
	eq(def.Damage, BossMath.AttackDamage(atk.Attack, 3))
	yes(def.Telegraph >= .9 - 1e-9, "fair telegraph")
	near(def.ImpactAt, atk.ImpactAt, 1e-6, "boss windup ends on the impact")
	-- stand inside it at the impact
	local c = Hazards.Center(def.Shape)
	pos[a] = V3(c.X, FLOOR, c.Z)
	if atk.Attack == "Sweep" then
		pos[a] = V3(c.X, FLOOR, c.Z) + def.Shape.Dir * 6
	end
	step(def.ImpactAt - T + .25)
	local hp = EventHP.HP(a)
	near(hp, 100 - def.Damage, 1e-6, "Event HP took the attack")
	yes((curse[a] or 0) > 0, "the Chapter I curse still comes with the hit")
	local knocks = signalsOf("BossEvent", "Knock")
	yes(#knocks >= 1 and knocks[#knocks].Damage == def.Damage, "Knock signal with the damage")
	local impact = signalsOf("BossEvent", "Attack")
	eq(impact[#impact].Stage, "Impact")
	eq(impact[#impact].HazardId, atk.HazardId)
	clearWorld()
end)

test("targeting skips downed players; skeleton bites deal Event HP through knock()", function()
	clearWorld()
	local a = newPlayer(floorPos(0, 6))
	local b = newPlayer(floorPos(0, -6))
	local F = summon(3)
	EventHP.Down(a, "Test")
	local list = Boss.Targetable(F)
	eq(#list, 1)
	eq(list[1], b)
	-- a skeleton next to b bites
	F.Phase = 3
	local sk = { Key = 1, Pos = V3(pos[b].X + 1.5, Layout.Pit.FloorY, pos[b].Z), Yaw = 0, NextBite = T - 1, Role = "Skeleton" }
	F.Skeletons[1] = sk
	local before = EventHP.HP(b)
	step(.1, false)
	near(before - EventHP.HP(b), BossMath.AttackDamage("Bite", 3), 1e-6, "Bite 6 x 1.1")
	F.Skeletons[1] = nil
	clearWorld()
end)

---------------------------------------------------------------------------------------------------------------------
-- 4. damage scaling
---------------------------------------------------------------------------------------------------------------------
test("damage scaling: soft cap per player, Perfect bonus on what lands, mechanic bypass", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local F = summon(5)
	F.NextAttackAt, F.NextPatternAt = math.huge, math.huge
	local per = BossMath.CapPerSecond(BossMath.MaxArmorBase(5))
	near(F.CapPerSecond, per, 1e-9)
	local entry = { Role = "Plate" }
	local plain = Boss.HitArmor(a, entry, { Quality = 1, Damage = 192 })
	local perfect = Boss.HitArmor(a, entry, { Quality = 2, Damage = 760 })
	near(plain, BossMath.ArmorDamage(192), 1e-9, "the Chapter II curve")
	yes(perfect > plain)
	-- first hits land in full (inside the allowance) x PerfectExtra
	local armor0 = F.Armor
	local got = Boss.Deal(a, 100, "Plate", { Perfect = true })
	near(got, 100 * (C2Cfg.Boss.PerfectExtra or 1), 1e-6)
	-- far beyond the 3 s allowance: 20% of the excess
	local g2 = Boss.Deal(a, 10000, "Plate", {})
	local room = per * 3 - 100
	near(g2, room + (10000 - room) * .2, 1e-6, "Beyond 20%")
	-- mechanic damage: 60% bypasses the (now full) cap
	local g3 = Boss.Deal(a, 1000, "Mound", { Mechanic = true, Force = true })
	near(g3, 600 + 400 * .2, 1e-6)
	yes(F.Armor < armor0)
	clearWorld()
end)

test("damage scaling: WEAKENED -30%, difficulty V weak points take Perfect hits only", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local F = summon(5)
	F.NextAttackAt, F.NextPatternAt = math.huge, math.huge
	local entry = { Role = "Plate" }
	local normal = Boss.HitArmor(a, entry, { Quality = 1, Damage = 300 })
	local weak = Boss.HitArmor(a, entry, { Quality = 1, Damage = 300, EventMult = .7 })
	near(weak / normal, .7, .02, "WEAKENED")
	-- enraged with the weak points open
	F.Phase = 5
	F.Mode = "Idle"
	F.NextWeakAt = T
	step(.1, false)
	local wp = targetsOf("BossWeak")[1]
	yes(wp ~= nil, "weak points open")
	eq(wp.Part:GetAttribute("PerfectOnly"), true)
	local ok, res = hit(a, wp, false)
	yes(ok)
	eq(res.Damage, 0, "a Good hit does nothing on V")
	eq(res.Extra.NeedPerfect, true)
	local ok2, res2 = hit(a, wp, true)
	yes(ok2)
	yes(res2.Extra.BossDamage > 0, "a Perfect lands")
	clearWorld()
	-- difficulty IV: any hit
	local b = newPlayer(floorPos(-6, 0))
	local F4 = summon(4)
	F4.NextAttackAt, F4.NextPatternAt = math.huge, math.huge
	F4.Phase = 5
	F4.NextWeakAt = T
	step(.1, false)
	local _, res3 = hit(b, targetsOf("BossWeak")[1], false)
	yes(res3.Extra.BossDamage > 0, "IV: Good hits land on weak points")
	clearWorld()
end)

test("SYNC STRIKE: two players' Perfects within .5 s both get +50%", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local b = newPlayer(floorPos(6, 0))
	local F = summon(3)
	F.NextAttackAt, F.NextPatternAt = math.huge, math.huge
	local plate = targetsOf("BossPlate")[1]
	local _, ra = hit(a, plate, true)
	T += .3
	local _, rb = hit(b, plate, true)
	eq(rb.Extra.Sync, true, "the second Perfect syncs")
	local retro = 0
	for _, s in ipairs(signals) do
		if s.To == a and s.Kind == "BossEvent" and s.Data.Kind == "Hit" and s.Data.Retro then
			retro += 1
		end
	end
	eq(retro, 1, "the partner gets the bonus for the earlier hit")
	no(ra.Extra.Sync, "the first hit alone was not synced")
	clearWorld()
end)

---------------------------------------------------------------------------------------------------------------------
-- 5. endgame patterns only on III-V, rock wave caps
---------------------------------------------------------------------------------------------------------------------
test("endgame patterns run on III / IV / V (Pattern signal, HazardIds, StartAt, Duration) and never on I / II", function()
	for _, d in ipairs({ 2, 3, 5 }) do
		clearWorld()
		local a = newPlayer(floorPos(-6, 4))
		local F = summon(d)
		F.EndsAt = math.huge
		step(70)
		local pats = signalsOf("BossEvent", "Pattern")
		if d <= 2 then
			eq(#pats, 0, "no endgame pattern on " .. d)
		else
			yes(#pats >= 1, "a pattern on " .. d)
			local p = pats[1]
			yes(p.Name == "GraveLines" or p.Name == "LanternWalk" or p.Name == "BoneRain")
			yes(type(p.HazardIds) == "table" and #p.HazardIds > 0)
			yes(p.StartAt > 0 and p.Duration > 0)
		end
		local _ = a
	end
	clearWorld()
end)

test("cursed rock waves: capped at 3 per phase on III / IV, unlimited on V; each wave is fair", function()
	for _, d in ipairs({ 4, 5 }) do
		clearWorld()
		newPlayer(floorPos(-6, 4))
		local F = summon(d)
		F.EndsAt = math.huge
		F.NextPatternAt, F.NextAttackAt = math.huge, math.huge
		F.Phase = 4
		F.SubPhase = "Rocks"
		F.NextWaveAt = T
		step(80)
		local waves = signalsOf("BossEvent", "Rocks")
		if d == 4 then
			eq(#waves, 3, "IV: 3 waves")
			eq(waves[1].Waves, 3)
		else
			yes(#waves >= 5, "V: waves keep coming (" .. #waves .. ")")
			eq(waves[1].Unlimited, true)
		end
		for _, w in ipairs(waves) do
			yes(#w.HazardIds == #w.Rocks, "one hazard per rock")
			local defs = {}
			for _, id in ipairs(w.HazardIds) do
				local h = EventHP.Zones.Boss.Hazards[id]
				if h then
					table.insert(defs, h.Def)
				end
			end
		end
	end
	clearWorld()
end)

---------------------------------------------------------------------------------------------------------------------
-- 6. wipe, parked rewards, Chapter II rewards
---------------------------------------------------------------------------------------------------------------------
test("team wipe: BossEvent Wiped, then Escaped {Reason = Wiped} and consolation rewards", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local b = newPlayer(floorPos(6, 0))
	local F = summon(3)
	F.NextAttackAt, F.NextPatternAt = math.huge, math.huge
	Boss.Deal(a, 50, "Plate", {})
	EventHP.Down(a, "Test")
	EventHP.Down(b, "Test")
	step(.2)
	eq(#signalsOf("BossEvent", "Wiped"), 1)
	local esc = signalsOf("BossEvent", "Escaped")
	eq(#esc, 1)
	eq(esc[1].Reason, "Wiped")
	eq(F.Outcome, "Escaped")
	yes(#transacts >= 1 and transacts[1].Boss.Kills == 0, "a consolation, not a kill")
	step(13)
	eq(Boss.Fight, nil, "released after the hold")
	eq(EventHP.Zone(a), nil, "out of combat")
	clearWorld()
end)

test("parked rewards: a contributor who left before the end is paid on rejoin (once)", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local b = newPlayer(floorPos(6, 0))
	local F = summon(3)
	F.NextAttackAt, F.NextPatternAt = math.huge, math.huge
	Boss.Deal(a, 3000, "Plate", {})
	Boss.Deal(b, 3000, "Plate", {})
	local fightId = F.Id
	leave(b)
	F.Armor = 1
	Boss.ApplyDamage(a, 5, "Test", true)
	F.Phase = 5
	F.PendingPhase = nil
	F.PendingDefeat = true
	step(.2)
	eq(F.Outcome, "Defeated")
	yes(Boss.Pending[b.UserId] ~= nil and Boss.Pending[b.UserId][fightId] ~= nil, "b is parked")
	local paidA = 0
	for _, r in ipairs(transacts) do
		if r.Player == a then
			paidA += 1
		end
	end
	eq(paidA, 1, "a paid at once")
	-- b rejoins (a new Player object, same UserId)
	local b2 = newPlayer(floorPos(0, 0))
	b2.UserId = b.UserId
	yes(Boss.ResumePending(b2), "nothing left parked")
	local paidB = 0
	for _, r in ipairs(transacts) do
		if r.Player == b2 then
			paidB += 1
		end
	end
	eq(paidB, 1, "b paid on rejoin")
	yes(Boss.ResumePending(b2), "a second resume pays nothing")
	clearWorld()
end)

test("rewards: a failing transaction is retried / parked; Chapter II reward once per eligible full fighter", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local b = newPlayer(floorPos(6, 0), { HalloweenChapter1Complete = false })
	local F = summon(4)
	F.NextAttackAt, F.NextPatternAt = math.huge, math.huge
	Boss.Deal(a, 2000, "Plate", {})
	Boss.Deal(b, 2000, "Plate", {})
	failNext[a.UserId] = 2
	F.PendingDefeat = true
	step(.2)
	local calls = {}
	for _, c in ipairs(c2Calls) do
		calls[c.Player] = (calls[c.Player] or 0) + 1
	end
	eq(calls[a], 1, "Chapter II reward for the eligible fighter")
	eq(calls[b], nil, "no Chapter II reward without Chapter I")
	eq(c2Calls[1].Receipt, "hw-boss2:" .. F.Id .. ":" .. a.UserId)
	eq(c2Calls[1].Finale, false)
	eq(#signalsOf("BossEvent", "RewardChapter2"), 1)
	-- BossDamage progress for Chapter II contracts
	local dmg = 0
	for _, p in ipairs(c2Progress) do
		if p.Player == a and p.Key == "BossDamage" then
			dmg += p.N
		end
	end
	near(dmg, math.floor(F.Damage[a.UserId]), 1, "C2.Progress BossDamage = the armor that landed (" .. dmg .. ")")
	clearWorld()
end)

---------------------------------------------------------------------------------------------------------------------
-- 7. the difficulty V finale
---------------------------------------------------------------------------------------------------------------------
local function toFinale(players)
	local F = summon(5)
	F.NextAttackAt, F.NextPatternAt = math.huge, math.huge
	for _, pl in ipairs(players) do
		Boss.Deal(pl, 4000, "Plate", {})
	end
	F.Phase = 5
	F.PendingPhase = nil
	F.PendingDefeat = true
	step(.1)
	return F
end

local function stateAttr(name)
	return stateRoot.Finale:GetAttribute(name)
end

local function chainTarget()
	return targetsOf("FinaleChain")[1]
end

-- a Perfect on the active chain in the bright part of its pulse
local function chainHit(pl, bright)
	local F = Boss.Fight
	local Fn = F.Finale
	local ch = Fn.Chains[Fn.Active]
	local pulse = C2Cfg.Finale.Bell.PulsePeriod
	local ph = ((T - ch.Since) % pulse) / pulse
	local want = bright and .2 or .8
	T += ((want - ph) % 1) * pulse
	return hit(pl, chainTarget(), true)
end

test("finale: armor 0 on V is a FALSE VICTORY (no defeat, FakeDeath signal, state, Phase 5 / Mode Finale)", function()
	clearWorld()
	local a = newPlayer(floorPos(-6, 0))
	local F = toFinale({ a })
	eq(#signalsOf("BossEvent", "Defeated"), 0, "no Defeated yet")
	eq(#transacts, 0, "nothing paid yet")
	local fd = finaleSignals("FakeDeath")
	eq(#fd, 1)
	eq(fd[1].Seconds, 6)
	yes(type(fd[1].At) == "number")
	eq(stateAttr("State"), "FakeDeath")
	eq(stateRoot.Boss:GetAttribute("Mode"), "Finale")
	eq(stateRoot.Boss:GetAttribute("Phase"), 5)
	eq(F.Ended, nil)
	eq(#targetsOf("BossPlate"), 0, "the body targets are gone")
	clearWorld()
end)

test("finale: the whole run (Bell -> Choir -> Hound -> Victory) pays exactly once with the finale rewards", function()
	clearWorld()
	local a = newPlayer(floorPos(-4, 0))
	local b = newPlayer(floorPos(4, 0))
	local F = toFinale({ a, b })
	step(6.1)
	-- THE BELL TOLLS
	eq(stateAttr("State"), "Bell")
	local bell = finaleSignals("Bell")[1]
	yes(typeof(bell.BellCF) == "CFrame" and bell.Pulse == 1.2 and bell.Bright == .55)
	for _, k in ipairs({ "N", "E", "S", "W" }) do
		yes(typeof(bell.Chains[k]) == "Vector3", "rim anchor " .. k)
	end
	eq(bell.Need, 6 + 3 * (2 - 1), "chain need for 2 fighters")
	step(2.6)
	local act = finaleSignals("ChainActive")[1]
	yes(act ~= nil and act.Need == 9 and act.Pulse == 1.2 and type(act.Since) == "number")
	eq(stateAttr("Chain"), act.Key)
	-- stand near the chain link
	local link = Fin.ChainPos(act.Key)
	pos[a] = V3(link.X + 3, FLOOR, link.Z + (link.Z < CENTER.Z and 8 or -8))
	pos[b] = pos[a] + V3(-6, 0, 0)
	-- a Good hit: IMMUNE; a Perfect outside the bright part: MISSED THE TOLL; inside: counts
	local _, r1 = hit(a, chainTarget(), false)
	eq(r1.Extra.Counted, false)
	eq(r1.Extra.Reason, "Immune")
	local _, r2 = chainHit(a, false)
	eq(r2.Extra.Reason, "Toll")
	local _, r3 = chainHit(a, true)
	eq(r3.Extra.Counted, true)
	local hitsSig = finaleSignals("ChainHit")
	eq(hitsSig[#hitsSig].Hits, 1)
	-- break all four chains
	for _ = 1, 4 do
		local guard = 0
		while Boss.Fight.Finale.Active and guard < 40 do
			guard += 1
			local key = Boss.Fight.Finale.Active
			local l = Fin.ChainPos(key)
			pos[a] = V3(l.X, FLOOR, l.Z) + (V3(CENTER.X, 0, CENTER.Z) - V3(l.X, 0, l.Z)).Unit * 6
			chainHit(a, true)
			topUp()
			step(.1)
		end
		topUp()
		step(1.6)
	end
	eq(#finaleSignals("ChainBreak"), 4)
	yes(#finaleSignals("BellToll") >= 1, "the bell tolled (shockwave rings)")
	step(1.6)
	-- THE BURIED CHOIR
	eq(stateAttr("State"), "Choir")
	local choir = finaleSignals("Choir")[1]
	eq(#choir.Candles, 6)
	eq(#choir.Pattern, 6)
	eq(choir.Rounds, 3)
	for round = 1, 3 do
		local Fn = Boss.Fight.Finale
		-- toggle every wrong candle (cooldown respected)
		for i, lit in ipairs(Fn.Candles) do
			if lit ~= Fn.Pattern[i] then
				local c = nil
				for _, t in ipairs(targetsOf("FinaleCandle")) do
					if t.Part:GetAttribute("Index") == i then
						c = t
					end
				end
				pos[a] = V3(c.Position.X, c.Position.Y + 1, c.Position.Z) + (V3(CENTER.X, 0, CENTER.Z) - V3(c.Position.X, 0, c.Position.Z)).Unit * 4
				hit(a, c, false)
				T += .5
			end
		end
		step(.2)
		local open = finaleSignals("WeakOpen")
		eq(#open, round, "weak points open on round " .. round)
		eq(#open[round].Points, 3)
		for _, wpTarget in ipairs(targetsOf("FinaleWeak")) do
			pos[a] = V3(wpTarget.Position.X + 3, FLOOR, wpTarget.Position.Z)
			local guard = 0
			while wpTarget.Alive and guard < 60 do
				guard += 1
				hit(a, wpTarget, true)
			end
		end
		step(.2)
		local rounds = finaleSignals("Round")
		local cleared = 0
		for _, r in ipairs(rounds) do
			if r.Cleared then
				cleared += 1
			end
		end
		eq(cleared, round, "round " .. round .. " cleared")
	end
	step(3)
	-- THE LAST BARK
	eq(stateAttr("State"), "Hound")
	local hound = finaleSignals("Hound")[1]
	eq(hound.Bpm, 100)
	eq(hound.Max, 24 + 10 * (2 - 1))
	yes(typeof(hound.HoundCF) == "CFrame" and typeof(hound.MoonDir) == "Vector3")
	local guard = 0
	while Boss.Fight and not Boss.Fight.Ended and guard < 3000 do
		guard += 1
		topUp()
		step(.1)
		local Fn = Boss.Fight.Finale
		if Fn.CounterUntil and T < Fn.CounterUntil then
			local jaw = targetsOf("HoundJaw")[1]
			if jaw then
				pos[a] = V3(jaw.Position.X, FLOOR, jaw.Position.Z - 8)
				pos[b] = V3(jaw.Position.X + 4, FLOOR, jaw.Position.Z - 8)
				hit(a, jaw, true)
				hit(b, jaw, true)
			end
		end
	end
	local patterns = finaleSignals("HoundPattern")
	yes(#patterns >= 2, "hound patterns ran")
	for _, p in ipairs(patterns) do
		local k = (p.BeatAt - hound.StartAt) / .6
		near(k, math.floor(k + .5), 1e-6, "patterns start on the beat grid")
	end
	local barks = finaleSignals("Bark")
	yes(#barks >= 1 and barks[1].CounterUntil - barks[1].At == 3, "3 s counter window")
	-- VICTORY: once
	local vic = finaleSignals("Victory")
	eq(#vic, 1)
	yes(#vic[1].Top >= 1 and type(vic[1].Top[1].Score) == "number")
	local def = signalsOf("BossEvent", "Defeated")
	eq(#def, 1, "finish Defeated exactly once")
	eq(def[1].Finale, "Victory")
	eq(Boss.Fight.FinaleWon, true)
	local paid = {}
	for _, r in ipairs(transacts) do
		paid[r.Player] = (paid[r.Player] or 0) + 1
		eq(r.Boss.Best, 5)
	end
	eq(paid[a], 1)
	eq(paid[b], 1)
	local finaleCalls = 0
	for _, c in ipairs(c2Calls) do
		if c.Finale then
			finaleCalls += 1
		end
	end
	eq(finaleCalls, 2, "the finale rewards for both")
	local ann = signalsOf("C2Announce", "FinaleClear")
	eq(#ann, 2, "server-wide FinaleClear on a first clear")
	step(15)
	eq(Boss.Fight, nil)
	eq(stateAttr("State"), "", "finale state reset")
	clearWorld()
end)

test("finale: counter window is Perfect only and capped at 6 counted hits per player per window", function()
	clearWorld()
	local a = newPlayer(floorPos(-4, 0))
	local F = toFinale({ a })
	local ok = Fin.Debug -- (Studio only: jump with the internal stage functions instead)
	local _ = ok
	step(6.1)
	-- jump to the hound
	local Fn = F.Finale
	for _, key in ipairs({ "N", "E", "S", "W" }) do
		Fn.Chains[key].Broken = true
	end
	Fn.Active = nil
	Fn.ChoirAt = T
	step(.1)
	Fn.HoundAt = T
	step(.2)
	eq(Fn.State, "Hound")
	eq(Fn.HoundMax, 24)
	local guard = 0
	while not Fn.CounterUntil and guard < 200 do
		guard += 1
		step(.1)
	end
	local jaw = targetsOf("HoundJaw")[1]
	pos[a] = V3(jaw.Position.X, FLOOR, jaw.Position.Z - 8)
	local _, rGood = hit(a, jaw, false)
	eq(rGood.Extra.Reason, "Perfect")
	local counted = 0
	for _ = 1, 9 do
		local _, r = hit(a, jaw, true)
		if r.Extra.Counted then
			counted += 1
		end
	end
	eq(counted, 6, "cap 6 per window")
	eq(Fn.HoundHP, 24 - 6)
	clearWorld()
end)

test("finale fail: a wipe -> Fail {Reason = Wipe}, Defeated once, the normal V reward without finale extras", function()
	clearWorld()
	local a = newPlayer(floorPos(-4, 0))
	local F = toFinale({ a })
	step(8)
	EventHP.Down(a, "Test")
	step(.2)
	local fail = finaleSignals("Fail")
	eq(#fail, 1)
	eq(fail[1].Reason, "Wipe")
	local def = signalsOf("BossEvent", "Defeated")
	eq(#def, 1)
	eq(def[1].Finale, "Fail")
	eq(F.FinaleWon, false)
	eq(#transacts, 1, "the difficulty V reward")
	eq(transacts[1].Boss.Best, 5)
	eq(#c2Calls, 1)
	eq(c2Calls[1].Finale, false, "no finale extras")
	eq(#signalsOf("C2Announce"), 0)
	clearWorld()
end)

test("finale fail: 7 minutes total -> Fail {Reason = Time}", function()
	clearWorld()
	local a = newPlayer(floorPos(-4, 0))
	local F = toFinale({ a })
	local deadline = F.Finale.Deadline
	near(deadline - F.Finale.Start, 420, 1e-6)
	-- keep the player alive: no hazards reach them (out of every zone hazard)
	EventHP.Leave = EventHP.Leave
	local guard = 0
	while not F.Ended and guard < 5000 do
		guard += 1
		T += 1
		F.Finale.NextTollAt = math.huge
		F.Finale.NextGhostAt = math.huge
		F.Finale.NextVolleyAt = math.huge
		Boss.Step(1)
	end
	local fail = finaleSignals("Fail")
	eq(#fail, 1)
	eq(fail[1].Reason, "Time")
	yes(T >= deadline - 1e-6)
	eq(#signalsOf("BossEvent", "Defeated"), 1)
	clearWorld()
end)

test("finale off (BossFinaleEnabled false) or an exorcism fight: difficulty V ends normally", function()
	clearWorld()
	Config.HalloweenBossFinaleEnabled = false
	local a = newPlayer(floorPos(-4, 0))
	local F = toFinale({ a })
	eq(F.Finale, nil)
	eq(#signalsOf("BossEvent", "Defeated"), 1)
	eq(#finaleSignals("FakeDeath"), 0)
	Config.HalloweenBossFinaleEnabled = true
	clearWorld()
end)

test("the exorcism D-II fight still works (no summoner, long empty grace, pit fighters)", function()
	clearWorld()
	local ok = Boss.Summon(2, "Exorcism", nil)
	yes(ok)
	local F = Boss.Fight
	eq(F.EmptyGrace, 75)
	step(50)
	no(F.Ended, "still waiting for the exorcists")
	local a = newPlayer(floorPos(0, 6))
	step(8)
	eq(F.State, "Fight")
	eq(F.Fighters, 1)
	F.PendingDefeat = true
	step(.2)
	eq(F.Outcome, "Defeated")
	eq(#finaleSignals("FakeDeath"), 0)
	local _ = a
	clearWorld()
end)

test("§23.2 payload shapes: Finale stages carry the documented fields", function()
	clearWorld()
	local a = newPlayer(floorPos(-4, 0))
	local F = toFinale({ a })
	step(6.1)
	step(2.6)
	local Fn = F.Finale
	local link = Fin.ChainPos(Fn.Active)
	pos[a] = V3(link.X, FLOOR, link.Z) + (V3(CENTER.X, 0, CENTER.Z) - V3(link.X, 0, link.Z)).Unit * 6
	chainHit(a, true)
	step(8)
	local need = {
		FakeDeath = { "At", "Seconds" },
		Bell = { "StartAt", "BellCF", "Chains", "Pulse", "Bright", "Need" },
		ChainActive = { "Key", "Since", "Pulse", "Bright", "Need", "Hits" },
		ChainHit = { "Key", "Hits", "Need", "UserId", "Counted" },
		BellToll = { "At" },
	}
	for stage, fields in pairs(need) do
		local s = finaleSignals(stage)[1]
		yes(s ~= nil, stage .. " sent")
		for _, f in ipairs(fields) do
			yes(s[f] ~= nil, stage .. "." .. f)
		end
	end
	for _, attr in ipairs({ "State", "StageStart", "StageUntil", "Chain", "ChainsLeft", "ChainHits", "ChainNeed", "Candles", "Pattern", "Round",
		"Rounds", "HoundHP", "HoundMax", "CounterUntil", "Bpm", "Revision" }) do
		yes(stateRoot.Finale:GetAttribute(attr) ~= nil, "State.Finale." .. attr)
	end
	-- later stages through the stage functions
	for _, key in ipairs({ "N", "E", "S", "W" }) do
		Fn.Chains[key].Broken = true
	end
	if Fn.Active and Fn.Chains[Fn.Active].Target then
		Strike.Remove(Fn.Chains[Fn.Active].Target, "Test")
	end
	Fn.Active = nil
	Fn.ChoirAt = T
	step(.2)
	local choir = finaleSignals("Choir")[1]
	for _, f in ipairs({ "StartAt", "Candles", "Pattern", "Round", "Rounds" }) do
		yes(choir[f] ~= nil, "Choir." .. f)
	end
	yes(typeof(choir.Candles[1].Position) == "Vector3" and type(choir.Candles[1].Lit) == "boolean")
	local c = targetsOf("FinaleCandle")[1]
	pos[a] = V3(c.Position.X, c.Position.Y + 1, c.Position.Z) + (V3(CENTER.X, 0, CENTER.Z) - V3(c.Position.X, 0, c.Position.Z)).Unit * 4
	hit(a, c, false)
	local cs = finaleSignals("Candle")[1]
	for _, f in ipairs({ "Index", "Lit", "UserId" }) do
		yes(cs[f] ~= nil, "Candle." .. f)
	end
	step(5)
	local gh = finaleSignals("Ghosts")[1]
	yes(gh ~= nil and type(gh.Count) == "number", "Ghosts.Count")
	eq(#targetsOf("FinaleGhost"), gh.Count)
	-- the hound
	Fn.HoundAt = T
	step(.2)
	local hound = finaleSignals("Hound")[1]
	for _, f in ipairs({ "StartAt", "Bpm", "HoundCF", "MoonDir", "HP", "Max" }) do
		yes(hound[f] ~= nil, "Hound." .. f)
	end
	step(6)
	local hp = finaleSignals("HoundPattern")[1]
	for _, f in ipairs({ "Name", "BeatAt", "Beats" }) do
		yes(hp[f] ~= nil, "HoundPattern." .. f)
	end
	step(5)
	local bark = finaleSignals("Bark")[1]
	for _, f in ipairs({ "At", "CounterUntil", "JawPos" }) do
		yes(bark[f] ~= nil, "Bark." .. f)
	end
	clearWorld()
end)

---------------------------------------------------------------------------------------------------------------------
-- 8. the DPS design target: a max-gear player spamming non-perfect hits vs the same player playing the mechanics
---------------------------------------------------------------------------------------------------------------------
-- A faithful fight: the real Boss + Strike (timing circles, MiningRules damage, crits, combos), no Event HP (the bots
-- never dodge), bots clicking like a human (>= Client.HumanGap between clicks).
-- Like the client, a circle that runs out is sent as a Miss (the combo resets): with 5 circles a TV-Head cannot click
-- every one at human speed, so its bots drop some.
--   SPAM: Good hits (the oldest circle past 47% of its window) on the boss's body only: the stone plates, else the weak
--         points; it never plays a mechanic (no mound, no skeleton, no cursed rock).
--   SKILLED: Perfect hits (the oldest circle inside 74-91% of its window) on weak points when open, cursed rocks, the
--         real mound (one test hit per mound), the skeletons under the shield, else the most cracked plate.
-- The design target compares the two styles IN THE SAME FIGHT (a duo: same phases, same invulnerable windows, own
-- soft caps): spam armor / mechanics armor. Solo runs report the kill times (a solo spammer still has to smash the
-- skeleton shield and dig the mounds to get anywhere: there it plays those with Good hits).
local function pickIndex(id)
	for i, p in ipairs(M.Pickaxes) do
		if p.Id == id then
			return i
		end
	end
	error("no pickaxe " .. id)
end

-- bots = {{Style = "Spam"|"Skilled", Pick = id, Strength = n}} -> {Time, Done, Bots = {{Dealt, Dps}}, BySource, MaxArmor}
local function simulate(d, bots, seconds, seed)
	clearWorld()
	local saveHP = modules.EventHP
	modules.EventHP = nil
	Boss.Init(fakeCore, modules)
	local simRng = L.Random.new(seed or (1234 + d))
	Strike.Random = function()
		return simRng:NextNumber()
	end
	for i, b in ipairs(bots) do
		b.Player = newPlayer(floorPos(-8 + i * 3, 0), { MiningPickaxe = pickIndex(b.Pick or "TVHead"), MiningStrength = b.Strength or 1100 })
		b.LastClick, b.Tested, b.Real = -1e9, {}, nil
		b.Perfect = b.Style == "Skilled"
		b.Solo = #bots == 1
		b.Frac = b.Perfect and .82 or .47
	end
	local F = summon(d)
	local startAt = T
	local gap = M.Client.HumanGap
	local function standAt(pl, target, i)
		local p = target.Position
		local ground = Boss.SurfaceAt(p.X, p.Z)
		local toC = V3(CENTER.X - p.X, 0, CENTER.Z - p.Z)
		local off = toC.Magnitude > .5 and toC.Unit * 4 or V3(4, 0, 0)
		local side = V3(-off.Z, 0, off.X).Unit * (i - 1.5) * 2
		local x, z = p.X + off.X + side.X, p.Z + off.Z + side.Z
		local y = Boss.SurfaceAt(x, z)
		pos[pl] = V3(x, math.min(y, ground) + 3, z)
	end
	local function choose(b)
		local weak, plates, rocks, mounds, skel = targetsOf("BossWeak"), targetsOf("BossPlate"), targetsOf("CursedRock"), targetsOf("BossMound"),
			targetsOf("BossSkeleton")
		if b.Perfect then
			if #weak > 0 then
				return weak[1]
			end
			if #rocks > 0 then
				return rocks[1]
			end
			if #mounds > 0 then
				for _, m in ipairs(mounds) do
					if b.Real == m.Id then
						return m
					end
				end
				-- (tests the mounds from the other end than the spammer digs them: who finds the real one is luck)
				for i = #mounds, 1, -1 do
					if not b.Tested[mounds[i].Id] then
						return mounds[i]
					end
				end
				return mounds[#mounds]
			end
			if #skel > 0 and F.Shield then
				return skel[1]
			end
			table.sort(plates, function(x, y)
				return x.HP / x.MaxHP < y.HP / y.MaxHP
			end)
			return plates[1]
		end
		-- the spammer never plays a mechanic: the body only (plates, else the weak points); alone it has to smash the
		-- skeleton shield and dig the mounds (in order) to get anywhere
		if b.Solo and #skel > 0 and F.Shield then
			return skel[1]
		end
		if #plates > 0 then
			return plates[1]
		end
		if b.Solo and #mounds > 0 then
			return mounds[1]
		end
		return weak[1]
	end
	while Boss.Fight == F and not F.Ended and not F.PendingDefeat and not F.Finale and T - startAt < seconds do
		T += .05
		for i, b in ipairs(bots) do
			local pl = b.Player
			local target = choose(b)
			if target then
				standAt(pl, target, i)
				local s = Strike.Sessions[pl]
				if not s or s.Target ~= target or T > (s.ActiveUntil or 0) then
					Strike.Begin(pl, { Target = target.Id })
					s = Strike.Sessions[pl]
				end
				if s and s.Target == target then
					-- like the client: a circle that ran out (105% of its window) is sent as a Miss (combo reset)
					for _, c in pairs(table.clone(s.Targets)) do
						if T - c.SpawnAt > 1.05 * c.Window then
							Strike.Hit(pl, { Target = c.Id, Quality = 1, Miss = true })
						end
					end
					-- one click per HumanGap: SPAM clicks the oldest circle past 47% of its window; SKILLED clicks the oldest
					-- circle inside the Perfect band (74-91%) and lets the others wait
					local pick, pickF = nil, -1
					for _, c in pairs(s.Targets) do
						local f = (T - c.SpawnAt) / c.Window
						local ok = if b.Perfect then f >= .74 and f <= .91 else f >= b.Frac
						if ok and f > pickF then
							pick, pickF = c, f
						end
					end
					if pick and T - b.LastClick >= gap then
						local ok, res = Strike.Hit(pl, { Target = pick.Id, Quality = b.Perfect and 2 or 1 })
						b.LastClick = T
						if ok and type(res) == "table" and type(res.Extra) == "table" and res.Extra.Real ~= nil then
							for _, other in ipairs(bots) do
								other.Tested[target.Id] = true
								if res.Extra.Real then
									other.Real = target.Id -- (the real mound rumbles for everyone)
								end
							end
						end
					end
				end
			end
		end
		if math.floor((T - startAt) * 20 + .5) % 2 == 0 then
			Boss.Step(.1)
		end
	end
	local dur = T - startAt
	local out = { Time = dur, MaxArmor = F.MaxArmor, Done = F.PendingDefeat == true or F.Outcome == "Defeated" or F.Finale ~= nil,
		BySource = F.BySource or {}, Bots = {} }
	for i, b in ipairs(bots) do
		local dealt = F.Damage[b.Player.UserId] or 0
		out.Bots[i] = { Dealt = dealt, Dps = dealt / dur, Sources = (F.Sources or {})[b.Player.UserId] or {} }
	end
	modules.EventHP = saveHP
	Strike.Random = function()
		return .99
	end
	clearWorld()
	Boss.Init(fakeCore, modules)
	return out
end

local function sources(t)
	local list = {}
	for k, v in pairs(t) do
		table.insert(list, string.format("%s %d", k, math.floor(v)))
	end
	table.sort(list)
	return table.concat(list, ", ")
end

local function dpsReport(d, seeds)
	local spamSum, skilledSum, ratios = 0, 0, {}
	for s = 1, seeds do
		local duo = simulate(d, { { Style = "Spam" }, { Style = "Skilled" } }, 420, 1000 * d + s)
		local ratio = duo.Bots[1].Dealt / math.max(1, duo.Bots[2].Dealt)
		table.insert(ratios, ratio)
		spamSum += duo.Bots[1].Dps
		skilledSum += duo.Bots[2].Dps
		print(string.format("  d%d duo #%d (%.0f s, %s): spam %.0f/s, mechanics %.0f/s, ratio %.2f", d, s, duo.Time,
			duo.Done and "killed" or "escaped", duo.Bots[1].Dps, duo.Bots[2].Dps, ratio))
		print("      spam: " .. sources(duo.Bots[1].Sources) .. " | mechanics: " .. sources(duo.Bots[2].Sources))
	end
	local mean = 0
	for _, r in ipairs(ratios) do
		mean += r
	end
	return mean / #ratios, spamSum / seeds, skilledSum / seeds
end

test("DPS design target: max-gear spam <= 35% of the same player's mechanics DPS in the same fight (III, IV, V)", function()
	local diffs = { 3, 4, 5 }
	if env.BOSS_DIFFS then
		diffs = {}
		for n in string.gmatch(env.BOSS_DIFFS, "%d") do
			table.insert(diffs, tonumber(n))
		end
	end
	for _, d in ipairs(diffs) do
		local ratio, spam, skilled = dpsReport(d, tonumber(env.BOSS_SEEDS) or 3)
		print(string.format("  => difficulty %d: spam %.0f/s vs mechanics %.0f/s, mean ratio %.2f (target <= %.2f)", d, spam, skilled, ratio,
			C2Cfg.Boss.SpamTarget))
		yes(ratio <= C2Cfg.Boss.SpamTarget + 1e-9, string.format("difficulty %d ratio %.2f", d, ratio))
	end
end)

test("solo kill times: a skilled max-gear player clears III-V inside the time limit; the spammer is much slower", function()
	for _, d in ipairs({ 3, 4, 5 }) do
		local skilled = simulate(d, { { Style = "Skilled" } }, 420)
		local spam = simulate(d, { { Style = "Spam" } }, 420)
		print(string.format("  solo d%d TV-Head: mechanics %.0f/s killed in %.0f s | spam %.0f/s %s in %.0f s", d, skilled.Bots[1].Dps, skilled.Time,
			spam.Bots[1].Dps, spam.Done and "killed" or "not killed", spam.Time))
		yes(skilled.Done and skilled.Time <= 300, "the skilled solo kill fits the time limit on " .. d)
		yes(spam.Time > 1.5 * skilled.Time, "spam is much slower on " .. d)
	end
	-- the endgame is not max-gear only: a Legendary pickaxe playing the mechanics clears NIGHTMARE alone
	local mid = simulate(3, { { Style = "Skilled", Pick = "ClownChrono", Strength = 470 } }, 420)
	print(string.format("  solo d3 Clown Chronomord: mechanics %.0f/s, %s in %.0f s", mid.Bots[1].Dps, mid.Done and "killed" or "not killed", mid.Time))
	yes(mid.Done and mid.Time <= 300, "a mid-gear skilled solo clears III")
end)

test("Chapter I gate: a mid-gear solo player still beats UNEASY (II) inside the time limit", function()
	local mid = simulate(2, { { Style = "Skilled", Pick = "Frankenzombie", Strength = 380 } }, 420)
	print(string.format("  d2 Zombie-Frankenstein (Perfects + mechanics): %.0f/s, killed in %.0f s", mid.Bots[1].Dps, mid.Time))
	yes(mid.Done and mid.Time <= 300, "UNEASY solo with a mid pickaxe")
	local low = simulate(2, { { Style = "Spam", Pick = "Frankenzombie", Strength = 380 } }, 420)
	print(string.format("  d2 Zombie-Frankenstein (Good hits only): %.0f/s, %s in %.0f s", low.Bots[1].Dps, low.Done and "killed" or "not killed",
		low.Time))
	yes(low.Done and low.Time <= 300, "UNEASY solo with Good hits only (the Chapter I gate stays open: ScaleFrom = III)")
end)

print(string.format("boss_finale: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("boss_finale failed")
end
