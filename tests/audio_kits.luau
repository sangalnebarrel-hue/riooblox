--!nolint
-- Pickaxe sound kits after the v5 impact redesign (docs/halloween2/DESIGN.md §16.3) and the Halloween cue library:
--   lune run tests/audio_kits.luau
-- Runs the real ReplicatedStorage.Mining.MiningAudio planner (Audio.Plan) over every stock kit and every Halloween skin
-- kit (PickaxeSkins registers them into MiningAudio.Kits), and checks the Chapter II cues of Halloween.Audio.
local L = require("./lib/economy_env")
local Audio = L.Require("ReplicatedStorage.Mining.MiningAudio")
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

-- the Halloween skin kits (PickaxeSkins.buildKits through its public registration path)
pcall(function()
	local Skins = L.Require("ReplicatedStorage.Halloween.PickaxeSkins")
	Skins.Register(nil)
end)

-- deterministic [0, 1) source (Park-Miller)
local function rng(seed)
	local s = seed
	return function()
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
end

local KNOCK, LAND = Audio.Sources[3], Audio.Sources[4]
local function isThud(row)
	return row[1] == KNOCK or row[1] == LAND
end
local function kitNames()
	local names = {}
	for name in pairs(Audio.Kits) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end
local function hasDistortedThump(fx)
	if type(fx) ~= "table" or fx.DistortionSoundEffect == nil then
		return false
	end
	local eq = fx.EqualizerSoundEffect
	return type(eq) == "table" and (eq.LowGain or 0) >= 6 and (eq.HighGain or 0) <= -14
end
local function sum(voices)
	local s = 0
	for _, v in ipairs(voices) do
		s += v.Row[2] * v.K
	end
	return s
end
-- every way a hit can be planned
local CASES = {
	{ Cue = "Hit" }, { Cue = "Perfect", Combo = 0 }, { Cue = "Perfect", Combo = 25 }, { Cue = "Hit", Dense = true },
	{ Cue = "Perfect", Dense = true, Combo = 8 }, { Cue = "Hit", Remote = true }, { Cue = "Perfect", Remote = true },
	{ Cue = "Hit", Pitch = 1.06 }, { Cue = "Hit", Volume = 1.5 },
}

test("the kit table holds every stock kit and the Halloween skin kits", function()
	local n = #kitNames()
	assert(n >= 16, "expected >= 16 kits, got " .. n)
	assert(Audio.Kits.Wood and Audio.Kits.Glitch, "stock kits missing")
	assert(Audio.Kits.HW_Grave and Audio.Kits.HW_Bone, "Halloween skin kits were not registered")
end)

test("every kit Hit / Perfect has exactly one impact row after softening", function()
	local r = rng(7)
	for _, name in ipairs(kitNames()) do
		local kit = Audio.Kits[name]
		for _, case in ipairs(CASES) do
			local voices = Audio.Plan(kit, case.Cue, case, {}, r)
			local impacts, thuds = 0, 0
			for _, v in ipairs(voices) do
				if v.Impact then
					impacts += 1
				end
				if isThud(v.Row) then
					thuds += 1
				end
			end
			assert(impacts == 1, string.format("%s %s: %d impact voices", name, case.Cue, impacts))
			assert(thuds == 1, string.format("%s %s: %d KNOCK/LAND voices (only the pooled impact may be one)", name, case.Cue, thuds))
		end
	end
end)

test("no THUMP distortion is left on any Hit / Perfect voice", function()
	local r = rng(11)
	for _, name in ipairs(kitNames()) do
		for _, cue in ipairs({ "Hit", "Perfect" }) do
			for _, v in ipairs((Audio.Plan(Audio.Kits[name], cue, {}, {}, r))) do
				assert(not hasDistortedThump(v.Row[4]), name .. " " .. cue .. " keeps a distorted thump row")
				if v.Impact then
					assert(v.Row[4] and v.Row[4].DistortionSoundEffect == nil, "the impact has distortion")
				end
			end
		end
	end
end)

test("simultaneous volume of a whole local hit stays <= 1.1 (Hit, Perfect, Crit, Break)", function()
	local r = rng(13)
	local worst, worstName = 0, ""
	for _, name in ipairs(kitNames()) do
		local kit = Audio.Kits[name]
		for _, case in ipairs(CASES) do
			if not case.Volume then
				local s = sum((Audio.Plan(kit, case.Cue, case, {}, r)))
				if s > worst then
					worst, worstName = s, name .. " " .. case.Cue
				end
				assert(s <= 1.1 + 1e-9, string.format("%s %s sums to %.3f", name, case.Cue, s))
			end
		end
		for _, cue in ipairs({ "Crit", "Break" }) do
			local s = sum((Audio.Plan(kit, cue, {}, {}, r)))
			assert(s <= 1.1 + 1e-9, string.format("%s %s sums to %.3f", name, cue, s))
		end
	end
	assert(worst > .3, "suspiciously quiet worst case " .. worst .. " (" .. worstName .. ")")
end)

test("impact pitch is uniform within .96-1.04 and its length / fade / EQ follow the spec", function()
	local r = rng(17)
	local lo, hi = math.huge, -math.huge
	local I = Audio.Impact
	for i = 1, 2000 do
		local voices = Audio.Plan(Audio.Kits.Wood, i % 2 == 0 and "Hit" or "Perfect", { Combo = i % 30, Pitch = 1.06 }, {}, r)
		for _, v in ipairs(voices) do
			if v.Impact then
				assert(v.P >= .96 - 1e-9 and v.P <= 1.04 + 1e-9, "impact pitch " .. v.P)
				lo, hi = math.min(lo, v.P), math.max(hi, v.P)
				assert(v.Row.dur == .14 and v.Row.fade == .05, "impact dur/fade")
				local eq = v.Row[4].EqualizerSoundEffect
				assert(eq.LowGain == 2 and eq.MidGain == 0 and eq.HighGain == -6, "impact EQ")
				assert(v.Row[2] * v.K <= I.Max + 1e-9 and v.Row[2] >= I.Min - 1e-9, "impact level " .. v.Row[2])
			end
		end
	end
	assert(lo < .965 and hi > 1.035, string.format("pitch range not covered: %.3f..%.3f", lo, hi))
	assert(I.Scale == .45, "volume scale")
	assert(#I.Pool == 4, "pool of 4")
	for _, row in ipairs(I.Pool) do
		assert(row[1] == KNOCK or row[1] == LAND, "pool sample is a KNOCK / LAND recording")
	end
end)

test("the impact pool never repeats twice in a row over 1000 draws (and uses every sample)", function()
	local r = rng(23)
	local state = {}
	local last, seen = nil, {}
	for i = 1, 1000 do
		local _, index = Audio.Plan(Audio.Kits.Saw, i % 3 == 0 and "Perfect" or "Hit", {}, state, r)
		assert(index ~= last, "pool repeated index " .. tostring(index) .. " at draw " .. i)
		seen[index] = (seen[index] or 0) + 1
		last = index
	end
	for i = 1, #Audio.Impact.Pool do
		assert((seen[i] or 0) > 150, "pool entry " .. i .. " drawn only " .. tostring(seen[i]))
	end
	-- the raw draw too, with a hostile source that always returns the same number
	local fixed = function()
		return 0
	end
	local prev = 1
	for _ = 1, 50 do
		local nextIndex = Audio.Impact.Draw(prev, fixed)
		assert(nextIndex ~= prev, "Draw repeated with a constant source")
		prev = nextIndex
	end
end)

test("Perfect = the kit character + accent + tick / sparkle / crack at the rising pitch", function()
	local r = rng(29)
	local stack = Audio.PerfectStack
	assert(#stack >= 5, "stack has tick, a 3-note sparkle and a crack")
	local voices = Audio.Plan(Audio.Kits.Magic, "Perfect", { Combo = 15 }, {}, r)
	local found = 0
	for _, v in ipairs(voices) do
		for _, row in ipairs(stack) do
			if v.Row == row then
				found += 1
				assert(math.abs(v.P - (1 + math.min(.06, 15 * .004))) < 1e-9, "stack plays at the rise pitch")
			end
		end
	end
	assert(found == #stack, "every stack row plays on a Perfect")
	-- remote Perfect: no accents, no stack
	local remote = Audio.Plan(Audio.Kits.Magic, "Perfect", { Remote = true }, {}, r)
	assert(#remote == 2, "remote hit = one character layer + the impact, got " .. #remote)
	-- dense local hitting keeps one character layer + the impact
	local dense = Audio.Plan(Audio.Kits.Digital, "Hit", { Dense = true }, {}, r)
	assert(#dense == 2 and dense[2].Impact, "dense hit = character + impact (impact second)")
end)

test("impact level follows the thud it replaces (45%, clamped)", function()
	local r = rng(31)
	local function impactOf(kitName)
		for _, v in ipairs((Audio.Plan(Audio.Kits[kitName], "Hit", {}, { Last = 4 }, function()
			return .1
		end))) do
			if v.Impact then
				return v.Row[2]
			end
		end
	end
	local wood = impactOf("Wood") -- KNOCK .5 replaced
	local fairy = impactOf("Fairy") -- KNOCK .12 replaced
	assert(wood and fairy and wood > fairy, "a heavy kit keeps a heavier impact than a light one")
	assert(math.abs(wood - math.clamp(.5 * .45 * Audio.Impact.Pool[1][2], Audio.Impact.Min, Audio.Impact.Max)) < 1e-9, "wood level " .. wood)
	local _ = r
end)

test("Crit / Break keep their character, lose thump distortion, Break thuds are softer", function()
	local r = rng(37)
	for _, name in ipairs(kitNames()) do
		local kit = Audio.Kits[name]
		for _, cue in ipairs({ "Crit", "Break" }) do
			if type(kit[cue]) == "table" then
				local voices = Audio.Plan(kit, cue, {}, {}, r)
				assert(#voices == #kit[cue], name .. " " .. cue .. " dropped rows")
				for i, v in ipairs(voices) do
					assert(not hasDistortedThump(v.Row[4]), name .. " " .. cue .. " distorted thump")
					if cue == "Break" and isThud(v.Row) then
						assert(v.Row[2] <= kit[cue][i][2] * Audio.Impact.BreakThud + 1e-9, name .. " Break thud not softened")
					end
				end
			end
		end
	end
end)

test("the generic Break / WeakPoint cues exist and the mix group is the Pickaxe bus child", function()
	-- the planner is pure; Play must not throw without a client (guarded)
	Audio.Play("Break")
	Audio.Play("WeakPoint")
	Audio.Pickaxe("Hit", "Wood")
	Audio.Pickaxe("Perfect", "Saw", nil, { Combo = 3 })
	local Mixer = L.Require("ReplicatedStorage.AudioMixer")
	assert(Mixer.Spec.Children.DOGROTS_MiningSFX.Parent == "Pickaxe", "mining group lives under the Pickaxe bus")
	assert(Mixer.Spec.Children.DOGROTS_MiningSFX.Compressor.GainMakeup == 0, "no makeup gain on the mining compressor")
	assert(Mixer.Spec.Groups.Pickaxe.Compressor.GainMakeup == 0, "no makeup gain on the Pickaxe bus")
end)

---------------------------------------------------------------------------------------------------------------------
-- Halloween.Audio cue library
---------------------------------------------------------------------------------------------------------------------
local HAudio = L.Require("ReplicatedStorage.Halloween.Audio")
local SOURCES = {}
for _, id in pairs(HAudio.Sources) do
	SOURCES[id] = true
end
local RANGES = {
	EqualizerSoundEffect = { LowGain = { -80, 10 }, MidGain = { -80, 10 }, HighGain = { -80, 10 } },
	ReverbSoundEffect = { DecayTime = { .1, 20 }, Density = { 0, 1 }, Diffusion = { 0, 1 }, DryLevel = { -80, 20 }, WetLevel = { -80, 20 } },
	TremoloSoundEffect = { Depth = { 0, 1 }, Duty = { 0, 1 }, Frequency = { .1, 20 } },
	ChorusSoundEffect = { Depth = { 0, 1 }, Mix = { 0, 1 }, Rate = { 0, 20 } },
	FlangeSoundEffect = { Depth = { 0, 1 }, Mix = { 0, 1 }, Rate = { 0, 20 } },
	DistortionSoundEffect = { Level = { 0, 1 } },
}
local CHAPTER2 = { "BellToll", "BellTollFar", "BellTollHuge", "SubSwell", "Heartbeat", "PortalHum", "PortalOpen", "PortalWhoosh",
	"PortalReverse", "ChurchCreak", "DustFall", "GroundCrack", "RevealHit", "RevealWord", "CoffinChain", "CoffinChainSnap",
	"CoffinRattle", "CoffinLid", "CoffinRevealCommon", "CoffinRevealRare", "CoffinRevealEpic", "CoffinRevealLegendary",
	"CoffinRevealMythic", "CoffinRevealSecret", "SealIgnite", "SealComplete", "TrialStart", "TrialWin", "TrialFail", "TrialTick",
	"HPHit", "HPLow", "Downed", "Revive", "ReviveTick", "HazardWarn", "HazardImpact", "ShockwaveRing", "ChainPulse", "ChainBreak",
	"CandleLight", "CandleSnuff", "GhostDogBark", "HoundBark", "HoundHowl", "ChoirNote", "DoorCreak", "DoorSlam", "Whisper2",
	"Moths", "MarshFrog", "CarnivalOrgan", "CaveDrip", "UnderyardBed", "Toll" }
local LOOPS = { PortalHum = true, HPLow = true, CarnivalOrgan = true, UnderyardBed = true }
local GROUPS = { SFX = true, Boss = true, Pickaxe = true, Cinema = true, Ambience = true, UI = true, Music = true }

test("the Chapter II cue library is complete (loops flagged as loops)", function()
	for _, name in ipairs(CHAPTER2) do
		local cue = HAudio.Cues[name]
		assert(cue and type(cue.Rows) == "table" and #cue.Rows > 0, "missing cue " .. name)
		assert((cue.Loop == true) == (LOOPS[name] == true), name .. " loop flag")
	end
	assert(HAudio.Cues.ChoirNote.Jitter == 0, "ChoirNote must stay in tune (pitch via opts)")
end)

test("every Halloween cue uses built-in samples, valid effect ranges, known groups and tasteful levels", function()
	local count = 0
	for name, cue in pairs(HAudio.Cues) do
		count += 1
		assert(cue.Group == nil or GROUPS[cue.Group], name .. " unknown group " .. tostring(cue.Group))
		local total = 0
		for i, row in ipairs(cue.Rows) do
			assert(SOURCES[row[1]], name .. " row " .. i .. " uses a non built-in sample")
			assert(type(row[2]) == "number" and row[2] > 0 and row[2] <= 1, name .. " row " .. i .. " volume")
			assert(type(row[3]) == "number" and row[3] >= .05 and row[3] <= 8, name .. " row " .. i .. " speed")
			total += row[2]
			for class, props in pairs(row[4] or {}) do
				local spec = RANGES[class]
				assert(spec, name .. " row " .. i .. " unknown effect " .. class)
				for prop, v in pairs(props) do
					local range = spec[prop]
					assert(range, name .. " " .. class .. "." .. prop .. " unknown")
					-- Chapter I presets predate this check; the Chapter II ones must be inside the documented ranges
					assert(v >= range[1] and v <= range[2], name .. " " .. class .. "." .. prop .. " = " .. v .. " out of range")
				end
			end
		end
		if table.find(CHAPTER2, name) then
			assert(total <= (cue.Loop and .4 or 2.6), string.format("%s rows sum to %.2f", name, total))
		end
	end
	assert(count >= 130, "expected >= 130 cues, got " .. count)
end)

test("boss cues play in the Boss bus, dig thuds in the Pickaxe bus with the impact duck", function()
	for _, name in ipairs({ "BossRoar", "BossSlam", "KillBlow", "MoonFlare", "WeakPointHit", "HoundBark", "ChainBreak", "HazardWarn" }) do
		assert(HAudio.Cues[name].Group == "Boss", name .. " not in the Boss bus")
	end
	for _, name in ipairs({ "DigSoil", "DigBone", "DigPumpkin", "DigGhost", "DigCursed", "OreBreak" }) do
		assert(HAudio.Cues[name].Group == "Pickaxe" and HAudio.Cues[name].Impact == true, name .. " routing")
	end
	assert(HAudio.ImpactDuck.Volume == .15, "dig thuds play at .15 under a kit impact")
end)

print(string.format("audio_kits: %d passed, %d failed", passed, failed))
