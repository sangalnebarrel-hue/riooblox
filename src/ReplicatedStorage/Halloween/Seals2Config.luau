-- BELL SEALS V-VII, BELL RESONANCE and the BLACK BELL ASSAULT — activity numbers (ReplicatedStorage.Halloween.Seals2Config,
-- WP-J; docs/halloween2/DESIGN.md §8.4 items 5-7, §8.6, §9.1). Shared by the server activities (SealDoors, SealChoir,
-- SealBell, Resonance), the pure rules (Seals2Rules) and the client presenters (HalloweenClient.Trials.Doors / Choir /
-- Bell / Assault / Resonance).
-- The economy numbers of these activities (door weights and chests, choir size, resonance goal / points / milestones,
-- assault rewards, seal rewards) live in Chapter2Config (WP-A: C.Doors, C.Choir, C.Resonance, C.Seals[5..7]) and are
-- read from there (C.Base); this module holds everything else: patterns, timings, positions, hit points, UI pacing.
-- Every hazard number obeys DESIGN §10.2 (telegraph >= .9 s, >= 1.2 s at 25+ damage, <= 40% of Event HP per hit in a
-- trial, moving safe zones <= 11 studs/s, a safe gap in every ring / line wave); tests/seals_5_7.luau checks it.
local Halloween = script.Parent
local Base = require(Halloween:WaitForChild("Chapter2Config"))

local C = {}
C.Version = 1
C.Base = Base

---------------------------------------------------------------------------------------------------------------------
-- SEAL V · CROOKED DOORS (Crooked Row; Chapter2Config.Doors = weights, chests, allowance)
---------------------------------------------------------------------------------------------------------------------
C.Doors = {
	Count = 4, -- Door_1..4 (UnderyardLayout.Crooked.Doors)
	PromptRange = 10, -- ProximityPrompt MaxActivationDistance on Door_i
	PromptHold = .6,
	OpenRadius = 12, -- server: the opener stands this close to the door (+ Chapter2Config.Proximity.Slack)
	Cooldown = 3, -- seconds between two door actions of one player
	ApproachRadius = 72, -- studs from the door wall centre: the deal is rolled (+ the H13 moth hint) and the state pushed
	ApproachRate = 1, -- seconds between two approach scans
	DealLife = 1800, -- a rolled deal (incl. its moth roll) stays with a player this long in this server
	SwingRadius = 140, -- players this close see another player's door swing open
	CountsFor = 5, -- the seal the outcomes count for
	OpenAngle = 95, -- client fallback when a leaf model has no OpenAngle attribute
	-- 25 s survival hazard dance (Seals.RegisterTrial "DoorChallenge"; TimeLimit = Chapter2Config.Trials.Defs)
	Challenge = {
		Court = "DoorCourt", -- anchor at the court centre (UnderyardLayout.Crooked.Court)
		Radius = 26, -- the court
		LeaveRadius = 34, -- standing farther than this from the court centre ...
		LeaveGrace = 2.5, -- ... for this long fails the challenge ("You fled the Door Court")
		Every = { 2.2, 1.5 }, -- seconds between two waves at the start / at the end (linear ramp)
		Telegraph = { 1.35, 1.05 }, -- telegraph at the start / at the end
		Damage = 16,
		FirstWave = 1.6, -- seconds after the start before the first telegraph
		Stomp = { Radius = 6, Extra = 2, Spread = 9 }, -- a paw on the player + Extra paws around
		Cross = { Width = 5, Length = 56 }, -- two lines crossing on the player
		Lanes = { Count = 3, Spacing = 12, Width = 6, Length = 60 }, -- parallel lanes (the gaps between are safe)
		Ripple = { Inner = 8, Outer = 30, Gaps = 2, GapWidth = 52 }, -- a ring on the court with doorways
		Finale = { At = 18, Radius = 8, Speed = 5, DPS = 9, Linger = 5.5, Telegraph = 1.2 }, -- the last seconds: a moving safe circle
		Spawn = "DoorCourt", -- bleed-out edge (the court centre)
	},
	-- THE DOORKEEPER mini boss (Seals.RegisterTrial "Doorkeeper"; party up to Chapter2Config.Trials.Defs.Doorkeeper.MaxParty)
	Doorkeeper = {
		HP = 60, -- tier-normalised Power (Strike Damage = "Power"): ~45 plain hits of a fresh pickaxe solo
		HPPerFighter = 25,
		Intro = 1.8, -- seconds the Doorkeeper takes to step out before it can be hit or attacks
		Height = 7, -- hit box centre above the ground
		Size = { 7, 13, 4 },
		Range = 17, -- strike prompt range
		Every = { 3.4, 2.4 }, -- seconds between attacks at full HP / near death
		Stagger = 1.6, -- after a SLAM it is stuck in the ground: hits count x StaggerMult
		StaggerMult = 2,
		Slots = { { 0, 0 }, { -13, 4 }, { 13, 4 }, { 0, 13 } }, -- offsets from the court centre (several fights at once)
		Attacks = {
			Slam = { Radius = 7, Telegraph = 1.3, Damage = 18, Weight = 3, Second = 3 }, -- + a second slam at 3+ fighters
			Sweep = { Radius = 18, Angle = 100, Telegraph = 1.2, Damage = 14, Weight = 2 },
			Ring = { Inner = 5, Outer = 16, GapWidth = 70, Telegraph = 1.4, Damage = 16, Weight = 2 },
			Charge = { Length = 28, Width = 7, Telegraph = 1.3, Damage = 20, Weight = 2 },
		},
		Spawn = "DoorCourt",
	},
	-- the hidden room (teleport only): three chests, then back out in front of the door
	Rare = {
		Spawn = "RareRoom", -- arrival anchor (UnderyardLayout.Crooked.RareRoom.Spawn)
		Chests = { { -9, 3, -6 }, { 0, 3, -6 }, { 9, 3, -6 } }, -- RareChest_i anchors: offsets from RareRoom.Centre
		ChestRange = 8,
		Visit = 90, -- seconds before the room sends the player back on its own
		ExitDelay = 3, -- seconds after the last chest
		ReturnAhead = 10, -- studs in front of the door (court side) the player comes back to
	},
}

---------------------------------------------------------------------------------------------------------------------
-- SEAL VI · CHOIR HUNT (all unlocked districts; Chapter2Config.Choir / Seals[6].Activity)
---------------------------------------------------------------------------------------------------------------------
C.Choir = {
	-- one wander loop per spirit (indexes into UnderyardLayout.ChoirPaths) and the district it belongs to
	Routes = {
		{ Points = { 1, 2, 3 }, District = "BellSquare" },
		{ Points = { 4, 5, 6 }, District = "FuneralCarnival" },
		{ Points = { 7, 8, 9 }, District = "MourningMarsh" },
		{ Points = { 10, 11, 12 }, District = "Undercrypt" },
		{ Points = { 13, 14, 15 }, District = "CrookedRow" },
		{ Points = { 18, 16, 19 }, District = "BellSquare" }, -- ring road, east half
		{ Points = { 21, 17, 20 }, District = "BellSquare" }, -- ring road, west half
	},
	-- the Last Bell's song (D minor): spirit i sings Melody[i] (Halloween Audio "ChoirNote", Pitch 1 = A)
	Melody = { 1.0, .7937, .6674, .7492, .7937, .8909, 1.0595 },
	NoteNames = { "A", "F", "D", "E", "F", "G", "B♭" },
	SingEvery = 3.6, -- seconds between two notes of one spirit (spirit i sings at phase i / Spirits)
	Hover = 3, -- studs above its path point
	Linger = { 1.2, 2.6 }, -- pause at every path point
	FleeSpeed = 22, -- studs/s while fleeing (Chapter2Config.Choir.FleeDistance studs)
	Radius = 2.5, -- strike hit box
	Range = 15, -- strike prompt range (a moving target)
	MothEvery = 2, -- seconds between two H13 nearest-spirit updates
	MothRefresh = 6, -- an unchanged hint is re-sent this often
}

---------------------------------------------------------------------------------------------------------------------
-- SEAL VII · LAST BELL TRIAL vs THE BELLKEEPER (Black Bell Arena; Chapter2Config.Seals[7].Activity)
---------------------------------------------------------------------------------------------------------------------
C.Bell = {
	Intro = 3.5, -- seconds of the opening toll before wave 1
	-- wave 1: shockwave rings (expanding bands with doorways), Activity.ShockwaveEvery / ShockwaveDamage
	Rings = {
		Tolls = 4, -- tolls to survive
		Bands = { { 4, 14 }, { 18, 28 }, { 32, 44 } }, -- {inner, outer} studs from the arena centre
		Stagger = .6, -- seconds between two bands of one toll (the wave expands)
		Telegraph = 1.3,
		Gaps = 2, -- doorways per band
		GapWidth = 46, -- degrees
		GapTurn = 40, -- each band's doorways turn this much from the previous band's
	},
	-- wave 2: four chains, one ringing at a time; only Perfect hits in the bright part of a pulse count
	Chains = {
		Order = { "N", "E", "S", "W" },
		Bright = .55, -- fraction of each pulse that counts (Activity.PulsePeriod)
		Grace = .15, -- seconds of latency forgiveness after the bright part
		Shockwave = { Every = { 10, 12 }, Bands = { { 6, 16 }, { 22, 32 } } }, -- the bell keeps tolling, slower
		Radius = 2.6, Range = 16,
	},
	-- wave 3: the Bellkeeper's weak point burns (Activity.WeakHP + WeakHPPerFighter, Power) while Lines + Circles fall
	Burn = {
		Height = 7.5, -- weak point above the Bellkeeper's feet
		Radius = 3, Range = 19,
		Every = { 3.2, 2.2 }, -- seconds between two volleys at full / near zero weak HP
		Line = { Count = 2, Width = 6, Length = 70, Telegraph = 1.25, Damage = 16 },
		Circle = { Radius = 6, Telegraph = 1.2, Damage = 14, Max = 4 },
	},
	Spawn = "ArenaSpawn",
}

---------------------------------------------------------------------------------------------------------------------
-- BELL RESONANCE (§8.6; Chapter2Config.Resonance = goal, points, milestones, assault rewards)
---------------------------------------------------------------------------------------------------------------------
C.Resonance = {
	PublishEvery = .5, -- State.Resonance.Value is written at most this often
	Tick = 1,
	-- 75%: Resonant Echo spots (Strike kind "UyResEcho" at ResonantEcho_n)
	Echo = { HP = 6, Radius = 2.6, Range = 14, Respawn = 6, Height = 2.5 },
	-- 50%: a key for every Chapter II player active in the Underyard in the last ActivityWindow seconds
	-- 100%: THE BLACK BELL ASSAULT
	Assault = {
		Countdown = 30, -- seconds between 100% and the raid (the arena opens for every Chapter II player)
		WaitStep = 5, -- a running LAST BELL TRIAL holds the start this many seconds at a time
		ResultHold = 8, -- seconds the result stays published before the counter resets
		Height = 9, -- the Bellkeeper's lantern heart above its feet (the shared target)
		Radius = 4, Range = 21,
		MinHits = 5, -- hits on the Bellkeeper a player needs for the rewards (+ active within the activity window)
		FailShards = { 15, 30 }, -- the bell held: contributors still get a few shards
		JoinRate = .5, -- seconds between two arena scans (players walking in join the raid)
		Phases = {
			{ Above = .66, Rings = 8 }, -- seconds between tolls
			{ Above = .33, Rings = 9, Lines = 5 },
			{ Above = 0, Rings = 10, Lines = 4.5, Circles = 4 },
		},
		Ring = { Bands = { { 5, 15 }, { 20, 30 }, { 35, 46 } }, Stagger = .55, Telegraph = 1.3, Damage = 14, Gaps = 2, GapWidth = 46, GapTurn = 40 },
		Line = { Count = 3, Width = 6, Length = 80, Telegraph = 1.25, Damage = 16 },
		Circle = { Radius = 6, Telegraph = 1.2, Damage = 14, Max = 6 },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- CLIENT (presenters / widget)
---------------------------------------------------------------------------------------------------------------------
C.Client = {
	DoorSignRadius = 90, -- the floating "CHOOSE YOUR DOOR" sign above the wall shows within this distance
	DoorOpenTime = .9, -- leaf swing
	DoorHold = 2.4, -- seconds a door stays open before it creaks shut
	SpiritLerp = 8, -- visual follow speed of a spirit towards its target part (1/s)
	ArenaRange = 260, -- the Bellkeeper / chains render within this distance of the arena centre
	Meter = { Width = 300, PhoneWidth = 236, Height = 52, PhoneHeight = 46 }, -- the BELL RESONANCE card (px)
	-- colours of the activities (Chapter2Config.Palette)
	Colors = {
		Reward = { 255, 206, 96 }, Challenge = { 255, 84, 84 }, MiniBoss = { 168, 92, 255 }, Rare = { 255, 244, 196 },
		Moth = { 220, 230, 255 }, Spirit = { 150, 200, 255 }, Chain = { 186, 120, 255 }, Resonance = { 150, 80, 230 },
	},
}

return C
