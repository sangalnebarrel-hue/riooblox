-- DOGROTS: NIGHT OF THE BURIED MOON — every balance number of the Halloween event lives here.
-- ReplicatedStorage.Halloween.Config (shared by server and client). The server is the only side that grants anything;
-- clients read this table for UI / FX / timers only.
--
-- EVENT OFF SWITCH
--   HalloweenEventEnabled = false  -> the Dead Yard gate is sealed (COMING SOON plaque returns), every Halloween UI hides,
--   Blood Moon / boss / exorcism / candy rush timers stop, the main-map layer is removed, event actions are refused.
--   Saved data (profile.Halloween, event dogs, event mutations, skins, pumpkin blocks) is NEVER deleted, and event dogs /
--   mutated finds keep working everywhere in the normal game.
local C = {}

C.HalloweenEventEnabled = true
-- Chapter switches (docs/halloween2/DESIGN.md §2). Every one of them only stops systems; saved data is never deleted.
C.HalloweenChapter1Enabled = true -- THE DEAD YARD activities: candy, ores, dig spots, houses, cauldron, quests, Blood Moon, boss
C.HalloweenChapter2Enabled = true -- THE UNDERYARD: reveal, church portal, seals, Black Coffin, contracts, resonance, dex II
C.HalloweenCalendarEnabled = true -- main-map Halloween calendar (D-7 .. October 31, HalloweenCalendarConfig)
C.HalloweenBossFinaleEnabled = true -- Gravekeeper difficulty V: false victory + post-death phases
C.MainMapDecorations = true -- temporary Halloween layer on the main DOGROTS map (players can also hide it in SETTINGS)
C.EventId = "BuriedMoon2026"
C.Season = "NOTBM_2026"
C.EventName = "NIGHT OF THE BURIED MOON"
C.ZoneName = "THE DEAD YARD"
C.DexName = "BURIED MOON 2026"
C.CurrencyName = "CANDY"
C.DataVersion = 1

-- Studio helpers (never active in a live server): Blood Moon every 90 s, short cauldron timer, F7 debug panel.
C.Studio = { FastTimers = false, DebugPanel = true }

---------------------------------------------------------------------------------------------------------------------
-- CANDY (event currency, saved in profile.Halloween.Candy; server only)
---------------------------------------------------------------------------------------------------------------------
C.Candy = {
	Max = 1e9,
	Loot = { 1, 3 },          -- an ordinary Halloween find (ore node break, plain dig spot)
	PerfectHit = 1,           -- each server-confirmed Perfect Hit on Halloween ore / dig spots / boss
	PerfectHitCap = 40,       -- max Perfect Hit candy per player per minute (anti-macro)
	RareFind = { 3, 8 },      -- rare Halloween find (rare item roll, Cursed Treasure, event mutation)
	Quest = { 25, 50 },       -- each daily quest
	Boss = { 20, 100 },       -- boss reward (scaled by difficulty and contribution)
	TreatHouse = { 6, 14 },   -- Trick-or-Treat house: TREAT
	TrickHouse = { 2, 5 },    -- Trick-or-Treat house: TRICK consolation
	MinuteCap = 220,          -- hard cap of candy granted per player per rolling minute (everything except quests/boss/houses)
}

---------------------------------------------------------------------------------------------------------------------
-- ANTI-AFK: "activity" = server-validated actions. Candy only flows from active play; Curse rises when idle.
---------------------------------------------------------------------------------------------------------------------
C.Activity = {
	Window = 10,          -- seconds an action keeps the player "active" (Candy Rush timer runs, Curse doesn't rise)
	MoveWindow = 6,       -- walking is not idle: the curse holds while moving (HRP displacement sampled every second,
	MoveStuds = 14,       -- decayed, > MoveStuds / 2), but it is no activity (no Candy Rush time, no Blood Moon credit)
}

---------------------------------------------------------------------------------------------------------------------
-- CURSE (0..100, only inside the Dead Yard; RAM + saved copy so rejoining doesn't clear it)
---------------------------------------------------------------------------------------------------------------------
C.Curse = {
	IdleGrace = 8,         -- seconds without an action, a step or a guide card before the curse starts creeping
	RisePerSecond = 1.6,   -- while idle in the zone: standing still, no actions (~60 s from 0 to 100); walking holds it
	DecayOutside = 2.5,    -- per second while outside the Dead Yard
	OnboardingFreeze = 20, -- first-visit guide: each card holds the curse this long (Request "OnboardingStep", only while
	OnboardingFreezeMax = 180, -- the profile is not onboarded yet), at most OnboardingFreezeMax seconds per session
	SaveStep = 5, SaveEvery = 5, -- the saved copy follows RAM once it is SaveStep points off (at most every SaveEvery s)
	Relief = {             -- curse removed per action
		Hit = 1.2, Perfect = 3, Break = 6, Find = 8, RareFind = 18, DigSpot = 10, BossDamage = 2.5, Objective = 25,
		Strength = 20, Knock = 6, Cauldron = 12,
	},
	CandyMultiplier = {    -- candy income multiplier by curse level (piecewise, server-side)
		{ At = 0, Mult = 1 }, { At = 60, Mult = 1 }, { At = 80, Mult = .7 }, { At = 99.9, Mult = .5 }, { At = 100, Mult = .25 },
	},
	Thresholds = { Whisper = 55, Vignette = 70, Distort = 85, Max = 100 }, -- client presentation steps
}

---------------------------------------------------------------------------------------------------------------------
-- BLOOD MOON: phase-locked inside the NORMAL gap of the world-event clock (period 915 s ≈ every 15 minutes),
-- so it never overlaps a world event. Offsets are seconds from the start of each world-event cycle.
---------------------------------------------------------------------------------------------------------------------
C.BloodMoon = {
	Period = 0,             -- seconds between Blood Moons; 0 = one per world-event cycle (WorldEventSchedule.Period(), 915 s).
	                        -- Another value runs its own clock from the world-event epoch and CAN overlap world events.
	Offset = 210, Warning = 30, Active = 150, Fade = 12, -- Offset+Warning+Active+Fade must fit the NORMAL gap (600 s)
	StudioPeriod = 90, StudioOffset = 20, -- Studio FastTimers: cycle length / warning offset
	ParticipationSeconds = 25, -- seconds of activity in the zone during ACTIVE to count as "participated" (quest)
	CandyBonus = .5,        -- +50% candy from every source during ACTIVE
	MutationBonus = 2,      -- x this on every natural event mutation row of a yard dig during ACTIVE (the BLOOD MOON row
	                        -- only rolls during ACTIVE at all)
}

---------------------------------------------------------------------------------------------------------------------
-- HAUNTED DIG SPOTS (spawn while the Blood Moon is ACTIVE; dug with the pickaxe timing circles)
---------------------------------------------------------------------------------------------------------------------
C.DigSpots = {
	Active = 7,             -- spots alive at the same time
	PerPlayer = 2,          -- + this many per extra player in the zone (cap MaxActive)
	MaxActive = 14,
	Respawn = { 5, 9 },     -- seconds before a dug spot is replaced
	Lifetime = 70,          -- an undug spot sinks after this many seconds
	Range = 13,             -- server interaction distance
	PlayerCooldown = 2,     -- per player per spot after it is dug (shared spots: every digger gets a reward)
	Types = {
		{ Id = "CursedSoil", Name = "CURSED SOIL", Weight = 30, HP = 1.6, Candy = { 2, 4 }, RareChance = .22, Bones = { 0, 1 },
			Color = { 120, 18, 28 }, Accent = { 255, 60, 60 } },
		{ Id = "GhostSoil", Name = "GHOST SOIL", Weight = 26, HP = 1.0, Candy = { 2, 4 }, RareChance = .10, Bones = { 0, 1 },
			MissChance = .30, EventDogBonus = .5, Color = { 170, 220, 255 }, Accent = { 210, 245, 255 } },
		{ Id = "PumpkinPatch", Name = "PUMPKIN PATCH", Weight = 24, HP = 1.0, Candy = { 6, 10 }, RareChance = .06, Bones = { 0, 0 },
			Color = { 255, 130, 30 }, Accent = { 120, 220, 60 } },
		{ Id = "BoneGrave", Name = "BONE GRAVE", Weight = 17, HP = 1.2, Candy = { 1, 3 }, RareChance = .08, Bones = { 12, 30 },
			Color = { 225, 215, 190 }, Accent = { 140, 255, 150 } },
		{ Id = "CursedTreasure", Name = "CURSED TREASURE", Weight = 3, HP = 2.6, Candy = { 14, 24 }, RareChance = 1, Bones = { 20, 40 },
			Color = { 255, 200, 70 }, Accent = { 190, 90, 255 }, Rare = true, Max = 1 },
	},
	BaseHP = 26,            -- spot HP = BaseHP * type.HP * (1 + .12 * diggers) ; damage = player's real pickaxe damage
	ItemDepth = "Max",      -- rare finds roll on the player's deepest unlocked layer
}

---------------------------------------------------------------------------------------------------------------------
-- HALLOWEEN ORE (always-on mining nodes in the Dead Yard; same pickaxe timing circles as the Mining Corner)
---------------------------------------------------------------------------------------------------------------------
C.Ore = {
	Nodes = 10,
	HP = { 40, 70 },          -- scaled by the miner's pickaxe damage tier so every tier needs ~6-12 hits
	HitsTarget = { 6, 11 },
	Respawn = { 8, 14 },
	Range = 14,
	Candy = { 1, 3 },         -- per break (C.Candy.Loot)
	RareChance = .06,         -- chance a break is a rare find (item + C.Candy.RareFind)
	Kinds = {
		{ Id = "PumpkinOre", Name = "PUMPKIN ORE", Weight = 40, Rock = { 54, 36, 28 }, Accent = { 255, 128, 24 }, FX = "Ember" },
		{ Id = "GraveStone", Name = "GRAVE STONE", Weight = 34, Rock = { 92, 96, 108 }, Accent = { 140, 255, 150 }, FX = "Sparkle" },
		{ Id = "MoonShard", Name = "MOON SHARD", Weight = 26, Rock = { 40, 26, 58 }, Accent = { 190, 110, 255 }, FX = "Void" },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- HAUNTED CAULDRON
---------------------------------------------------------------------------------------------------------------------
C.Cauldron = {
	TrickCost = 80,              -- TRICK: 80 Candy -> Pumpkin Lucky Block (Cursed Pumpkin with CursedChance)
	CursedChance = .06,
	Levels = {                   -- TREAT: invest candy, level up; Cost = candy to reach this level
		{ Level = 1, Cost = 0, Table = "Treat1", Name = "SIMMERING" },
		{ Level = 2, Cost = 100, Table = "Treat2", Name = "BUBBLING" },
		{ Level = 3, Cost = 200, Table = "Treat3", Name = "BOILING" },
		{ Level = 4, Cost = 350, Table = "Treat4", Name = "OVERFLOWING" },
		{ Level = 5, Cost = 600, Table = "Treat5", Name = "BURIED MOON BREW" },
	},
	BrewSeconds = 7 * 86400,     -- the brew is ready this long after the first TREAT (one reward per season)
	StudioBrewSeconds = 120,
	InvestStep = { 10, 50 },     -- UI quick-invest buttons
	Range = 22,
}

---------------------------------------------------------------------------------------------------------------------
-- REWARD TABLES (Kind = Cash | Bones | Candy | Decor | Skin | Dog | Mutation | Block | Luck)
-- Cash rows use income-scaled coins: {MinCash, IncomeMinutes} (DogEconomy.BoostPricing.Coins)
---------------------------------------------------------------------------------------------------------------------
C.Rewards = {
	Pumpkin = { -- PUMPKIN LUCKY BLOCK
		{ Kind = "Cash", Coins = { MinCash = 15000, IncomeMinutes = 18 }, Weight = 2600, Rank = 1, Rarity = "Common", Name = "Coin Pile" },
		{ Kind = "Bones", Amount = 60, Weight = 2200, Rank = 1, Rarity = "Common", Name = "60 Bones" },
		{ Kind = "Decor", Id = "hw_jack_o_lantern", Weight = 1100, Rank = 2, Rarity = "Rare", Name = "JACK-O'-LANTERN" },
		{ Kind = "Decor", Id = "hw_grave_stone", Weight = 1000, Rank = 2, Rarity = "Rare", Name = "GRAVE STONE" },
		{ Kind = "Decor", Id = "hw_candle_cluster", Weight = 800, Rank = 3, Rarity = "Epic", Name = "CANDLE CLUSTER" },
		{ Kind = "Mutation", Id = "HAUNTED", Weight = 900, Rank = 3, Rarity = "Epic", Name = "HAUNTED FIND" },
		{ Kind = "Mutation", Id = "PUMPKINIZED", Weight = 450, Rank = 4, Rarity = "Legendary", Name = "PUMPKINIZED FIND" },
		{ Kind = "Skin", Id = "PumpkinSmasher", Weight = 160, Rank = 4, Rarity = "Legendary", Name = "PUMPKIN SMASHER SKIN" },
		{ Kind = "Skin", Id = "BonePickaxe", Weight = 160, Rank = 4, Rarity = "Legendary", Name = "BONE PICKAXE SKIN" },
		{ Kind = "Dog", Id = "HW_PumpkinPup", Weight = 380, Rank = 2, Rarity = "Rare", Name = "Pumpkin Pup" },
		{ Kind = "Dog", Id = "HW_SheetShiba", Weight = 140, Rank = 3, Rarity = "Epic", Name = "Sheet Shiba" },
		{ Kind = "Dog", Id = "HW_BoneCorgi", Weight = 140, Rank = 3, Rarity = "Epic", Name = "Bone Corgi" },
		{ Kind = "Dog", Id = "HW_Frankenpug", Weight = 34, Rank = 4, Rarity = "Legendary", Name = "Frankenpug" },
		{ Kind = "Dog", Id = "HW_BatDachshund", Weight = 34, Rank = 4, Rarity = "Legendary", Name = "Bat Dachshund" },
		{ Kind = "Dog", Id = "HW_PlaguePug", Weight = 8, Rank = 5, Rarity = "Mythic", Name = "Plague Pug" },
		{ Kind = "Dog", Id = "HW_HeadlessHound", Weight = 8, Rank = 5, Rarity = "Mythic", Name = "Headless Hound" },
		{ Kind = "Dog", Id = "HW_EclipseDog", Weight = 1, Rank = 6, Rarity = "Secret", Name = "Eclipse Dog" },
	},
	CursedPumpkin = { -- CURSED PUMPKIN (very rare variant: from TRICK at CursedChance, exorcism, Hell+ boss, cauldron L5)
		{ Kind = "Cash", Coins = { MinCash = 60000, IncomeMinutes = 45 }, Weight = 1800, Rank = 2, Rarity = "Rare", Name = "Cursed Hoard" },
		{ Kind = "Bones", Amount = 220, Weight = 1500, Rank = 2, Rarity = "Rare", Name = "220 Bones" },
		{ Kind = "Decor", Id = "hw_bone_arch", Weight = 900, Rank = 3, Rarity = "Epic", Name = "BONE ARCH" },
		{ Kind = "Mutation", Id = "BLOOD MOON", Weight = 900, Rank = 4, Rarity = "Legendary", Name = "BLOOD MOON FIND" },
		{ Kind = "Mutation", Id = "ECLIPSED", Weight = 120, Rank = 6, Rarity = "Secret", Name = "ECLIPSED FIND" },
		{ Kind = "Skin", Id = "GhostScythe", Weight = 420, Rank = 5, Rarity = "Mythic", Name = "GHOST SCYTHE SKIN" },
		{ Kind = "Skin", Id = "LivingCoffin", Weight = 420, Rank = 5, Rarity = "Mythic", Name = "LIVING COFFIN SKIN" },
		{ Kind = "Dog", Id = "HW_SheetShiba", Weight = 900, Rank = 3, Rarity = "Epic", Name = "Sheet Shiba" },
		{ Kind = "Dog", Id = "HW_BoneCorgi", Weight = 900, Rank = 3, Rarity = "Epic", Name = "Bone Corgi" },
		{ Kind = "Dog", Id = "HW_Frankenpug", Weight = 520, Rank = 4, Rarity = "Legendary", Name = "Frankenpug" },
		{ Kind = "Dog", Id = "HW_BatDachshund", Weight = 520, Rank = 4, Rarity = "Legendary", Name = "Bat Dachshund" },
		{ Kind = "Dog", Id = "HW_PlaguePug", Weight = 180, Rank = 5, Rarity = "Mythic", Name = "Plague Pug" },
		{ Kind = "Dog", Id = "HW_HeadlessHound", Weight = 180, Rank = 5, Rarity = "Mythic", Name = "Headless Hound" },
		{ Kind = "Dog", Id = "HW_EclipseDog", Weight = 12, Rank = 6, Rarity = "Secret", Name = "Eclipse Dog" },
	},
	-- TREAT brew rewards: every row is granted (not rolled); higher cauldron level = better table
	Treat1 = { { Kind = "Candy", Amount = 120 }, { Kind = "Bones", Amount = 80 }, { Kind = "Block", Id = "Pumpkin", Amount = 1 } },
	Treat2 = { { Kind = "Candy", Amount = 250 }, { Kind = "Bones", Amount = 160 }, { Kind = "Block", Id = "Pumpkin", Amount = 2 },
		{ Kind = "Decor", Id = "hw_candle_cluster" } },
	Treat3 = { { Kind = "Candy", Amount = 450 }, { Kind = "Bones", Amount = 300 }, { Kind = "Block", Id = "Pumpkin", Amount = 3 },
		{ Kind = "Skin", Id = "GraveShovel" }, { Kind = "Dog", Id = "HW_SheetShiba" } },
	Treat4 = { { Kind = "Candy", Amount = 700 }, { Kind = "Bones", Amount = 500 }, { Kind = "Block", Id = "Cursed Pumpkin", Amount = 1 },
		{ Kind = "Block", Id = "Pumpkin", Amount = 3 }, { Kind = "Skin", Id = "GraveShovel" }, { Kind = "Dog", Id = "HW_Frankenpug" } },
	Treat5 = { { Kind = "Candy", Amount = 1100 }, { Kind = "Bones", Amount = 800 }, { Kind = "Block", Id = "Cursed Pumpkin", Amount = 2 },
		{ Kind = "Skin", Id = "SoulReaper" }, { Kind = "Dog", Id = "HW_HeadlessHound" }, { Kind = "Decor", Id = "hw_bone_arch" } },
	-- Halloween ore / dig spot rare finds: item rolled on the player's deepest layer with a forced event mutation
	RareFindMutations = { { Id = "HAUNTED", Weight = 70 }, { Id = "PUMPKINIZED", Weight = 22 }, { Id = "BLOOD MOON", Weight = 8, BloodMoonOnly = true } },
	-- what a reward row pays instead when it can't be granted (Core ctx.Reward, boss dog-as-candy): never fails
	Conversion = { DecorBones = 60, SkinCandy = 60, DogCandyPerRank = 120, MutationCandy = 80, BlockCandy = 80 },
}

---------------------------------------------------------------------------------------------------------------------
-- PUMPKIN LUCKY BLOCKS (placed on the normal Lucky Pads)
---------------------------------------------------------------------------------------------------------------------
C.PumpkinBlocks = {
	Tiers = {
		Pumpkin = { Rank = 4, Style = "Pumpkin", Rewards = "Pumpkin", OpenSeconds = 45, TradeValue = 600000, GhostChance = .3 },
		["Cursed Pumpkin"] = { Rank = 5, Style = "CursedPumpkin", Rewards = "CursedPumpkin", OpenSeconds = 75, TradeValue = 4000000, GhostChance = 1 },
	},
	Tradeable = false,
}

---------------------------------------------------------------------------------------------------------------------
-- ITEM MUTATIONS (finds). Multipliers apply AFTER the depth soft cap so x20 really is x20 (bounded by Max).
---------------------------------------------------------------------------------------------------------------------
C.Mutations = {
	Order = { "HAUNTED", "PUMPKINIZED", "BLOOD MOON", "ECLIPSED" },
	Defs = {
		HAUNTED = { Mult = 2.5, Color = { 150, 235, 210 }, Accent = { 210, 255, 240 }, Name = "HAUNTED" },
		PUMPKINIZED = { Mult = 4, Color = { 255, 128, 24 }, Accent = { 130, 220, 60 }, Name = "PUMPKINIZED" },
		["BLOOD MOON"] = { Mult = 8, Color = { 210, 26, 44 }, Accent = { 255, 90, 90 }, Name = "BLOOD MOON" },
		ECLIPSED = { Mult = 20, Color = { 26, 14, 40 }, Accent = { 176, 70, 255 }, Name = "ECLIPSED" },
	},
	PostCapLimit = 60e6,  -- an event-mutated find is never worth more than this (keeps the economy bounded)
	-- natural rolls on yard digs while the event is on (absolute chances taken from NORMAL)
	YardChance = { HAUNTED = .004, PUMPKINIZED = .0015, ["BLOOD MOON"] = .0012 }, -- BLOOD MOON row only during Blood Moon
	ExorcismBoost = 2,    -- exorcism milestone multiplier (10 min)
}

---------------------------------------------------------------------------------------------------------------------
-- EVENT DOGS (DogDefinitions rows are added by the patch; abilities read these numbers)
---------------------------------------------------------------------------------------------------------------------
C.Dogs = {
	Order = { "HW_PumpkinPup", "HW_SheetShiba", "HW_BoneCorgi", "HW_Frankenpug", "HW_BatDachshund", "HW_PlaguePug", "HW_HeadlessHound", "HW_EclipseDog" },
	Defs = {
		HW_PumpkinPup = { Code = "H01", Index = 201, Rank = 2, Name = "Pumpkin Pup", Ability = "PumpkinPatch",
			Signature = "+20% Candy from Pumpkin Patch dig spots.", PumpkinCandy = .20 },
		HW_SheetShiba = { Code = "H02", Index = 202, Rank = 3, Name = "Sheet Shiba", Ability = "GhostLoot",
			Signature = "Can find Ghost Loot: haunted finds at Ghost Soil and in the yard.", GhostLootChance = .25, YardHaunted = .05 },
		HW_BoneCorgi = { Code = "H03", Index = 203, Rank = 3, Name = "Bone Corgi", Ability = "BoneHoard",
			Signature = "+35% Bones from digs and Bone Graves. Falls apart and rebuilds itself.", Bones = .35 },
		HW_Frankenpug = { Code = "H04", Index = 204, Rank = 4, Name = "Frankenpug", Ability = "Overcharge",
			Signature = "OVERCHARGE: every 5 digs it supercharges and digs 60% faster for 40 s.", ChargeDigs = 5, Speed = .6, Seconds = 40 },
		HW_BatDachshund = { Code = "H05", Index = 205, Rank = 4, Name = "Bat Dachshund", Ability = "NightFlight",
			Signature = "After a find it flies straight to the next dig: +40% speed on the next dig and dig spots start damaged.",
			NextDigSpeed = .4, SpotHead = .25 },
		HW_PlaguePug = { Code = "H06", Index = 206, Rank = 5, Name = "Plague Pug", Ability = "Plague",
			Signature = "Strongly raises the mutation chance of its finds and slightly for the whole team.", ItemMutation = .6, TeamMutation = .12 },
		HW_HeadlessHound = { Code = "H07", Index = 207, Rank = 5, Name = "Headless Hound", Ability = "HeadlessTreasure",
			Signature = "Finds Headless Treasure: bonus coin caches on digs, double Cursed Treasure chance.", TreasureChance = .04,
			TreasureMinutes = 6, CursedTreasureMult = 2,
			TreasureFloor = 2500 }, -- the smallest Headless Treasure, x BoostPricing layer scale (1, 3, 8, 20, 50)
		HW_EclipseDog = { Code = "H08", Index = 208, Rank = 6, Name = "Eclipse Dog", Ability = "Eclipse",
			Signature = "Rarely turns a find into ECLIPSED (x20 value).", EclipseChance = .006 },
	},
	TeamOnly = true, -- abilities count only while the dog is assigned to a dig slot (yard team)
}

---------------------------------------------------------------------------------------------------------------------
-- BOSS: THE GRAVEKEEPER
---------------------------------------------------------------------------------------------------------------------
C.Boss = {
	BaseArmor = 5000,             -- difficulty I armor; scaled by Difficulty.Armor and by fighters
	PerFighterArmor = .35,        -- +35% armor per extra fighter beyond the first
	MaxFighters = 20,
	TimeLimit = 300,              -- seconds; boss escapes after this (consolation reward)
	SummonCooldown = 240,         -- after a fight ends
	SummonRange = 18,
	Phases = {                    -- armor fraction at which each phase starts
		{ Id = 1, Name = "AWAKENING", From = 1.00 },
		{ Id = 2, Name = "BURROW", From = .72 },
		{ Id = 3, Name = "SKELETON PACK", From = .52 },
		{ Id = 4, Name = "CURSED ROCKS", From = .32 },
		{ Id = 5, Name = "ENRAGED", From = .15 },
	},
	Burrow = { Mounds = 6, MoundHP = 3, RealDamage = .08, FakeCurse = 12, Timeout = 22 },
	Skeletons = { Count = 6, PerFighter = 1, Max = 14, HP = 4, Speed = 11, Shield = true },
	Rocks = { Waves = 3, PerWave = 5, HP = 3, LandDelay = 1.6, ExplodeAfter = 9, Damage = .03 },
	Attacks = { Slam = { Radius = 13, Telegraph = 1.4, Knock = 60, Curse = 8 }, Sweep = { Telegraph = 1.1, Curse = 6 },
		Interval = { 6, 9 }, EnrageInterval = { 3.5, 5 } },
	-- dogs dig the weak points: the digger's best assigned yard dog digs beside them for +DogPerRank x its rank
	-- (+EventDog with an event dog in the yard team) extra weak-point damage, at most +DogMax; no dogs = no bonus
	WeakPoints = { Count = 3, Mult = 3, Open = 6, DogPerRank = .04, EventDog = .1, DogMax = .3 },
	Difficulties = {
		{ Id = 1, Numeral = "I", Name = "EASY", Armor = 1.0, Speed = 1.0, Reward = 1.0, DogChance = .02, Candy = { 20, 35 }, Unlock = 0 },
		{ Id = 2, Numeral = "II", Name = "UNEASY", Armor = 1.6, Speed = 1.15, Reward = 1.5, DogChance = .04, Candy = { 30, 50 }, Unlock = 1 },
		{ Id = 3, Numeral = "III", Name = "NIGHTMARE", Armor = 2.5, Speed = 1.3, Reward = 2.2, DogChance = .07, Candy = { 45, 70 }, Unlock = 2 },
		{ Id = 4, Numeral = "IV", Name = "HELL", Armor = 4.0, Speed = 1.5, Reward = 3.2, DogChance = .12, Candy = { 60, 85 }, Unlock = 3, CursedBlock = .35 },
		{ Id = 5, Numeral = "V", Name = "???", Armor = 6.5, Speed = 1.75, Reward = 4.5, DogChance = .2, Candy = { 80, 100 }, Unlock = 4, CursedBlock = 1, EclipseChance = .03 },
	},
	MinContribution = .03,        -- share of total damage needed for a full reward (below: consolation)
	EventDogs = { "HW_Frankenpug", "HW_BatDachshund", "HW_PlaguePug", "HW_HeadlessHound" },
	DogWeights = { Normal = 3, Rank5 = 1 }, -- boss event-dog drop weights (rank 5+ dogs are rarer)
	Reward = {                    -- per contributor; perf = PerfBase + PerfSlope * (share x contributors), clamped 0..1
		PerfBase = .35, PerfSlope = .65,
		Bones = 40, XP = 25,          -- full reward: Bones x Difficulty.Reward x (.5 + .5 perf), XP x Difficulty.Reward
		DogPerfBase = .6,             -- dog chance x (DogPerfBase + (1 - DogPerfBase) x perf)
		Consolation = { Defeated = .5, Escaped = .35, MinCandy = 3, Bones = 10, XP = 8 },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- CANDY RUSH (personal daily x2 for 10 minutes of ACTIVE play). Personal and server (exorcism) rush do not stack:
-- the personal timer waits while a server rush at least as strong runs, so no daily second is wasted.
---------------------------------------------------------------------------------------------------------------------
C.CandyRush = { Seconds = 600, Mult = 2, ServerMult = 2,
	SaveEvery = 5, -- seconds of rush used between saved copies (the timer itself lives in server RAM)
}

---------------------------------------------------------------------------------------------------------------------
-- TRICK OR TREAT STREET (7 houses, one knock per house per UTC day)
---------------------------------------------------------------------------------------------------------------------
C.TrickOrTreat = {
	Houses = 7,
	TreatChance = .62,
	Range = 12,
	Tricks = { -- client effects; every trick also pays C.Candy.TrickHouse
		{ Id = "Jumpscare", Weight = 18 }, { Id = "CurseBoost", Weight = 16, Curse = 18 }, { Id = "MiniBoss", Weight = 12 },
		{ Id = "Ghosts", Weight = 20 }, { Id = "Fog", Weight = 16 }, { Id = "FakeChest", Weight = 18 },
	},
	MiniBossHP = 6,
	MiniBossCandy = { 6, 12 }, -- bounty for breaking the porch skeleton
	MiniBossSeconds = 45, -- it slips back into the house after this
}

---------------------------------------------------------------------------------------------------------------------
-- SERVER EXORCISM (shared per server)
---------------------------------------------------------------------------------------------------------------------
C.Exorcism = {
	Goal = 5000,
	Souls = { Candy = 1, OreBreak = 3, DigSpot = 6, BossDamagePer = 120, Quest = 20, Knock = 2, Trick = 10 },
	Milestones = {
		{ At = 1000, Kind = "CandyRush", Seconds = 300, Name = "CANDY RUSH x2 · 5 MIN" },
		{ At = 2500, Kind = "Block", Tier = "Pumpkin", MinRank = 3, Name = "RARE PUMPKIN BLOCK FOR EVERYONE" }, -- MinRank: Epic+ only
		{ At = 4000, Kind = "Mutation", Seconds = 600, Mult = 2, Name = "MUTATION CHANCE x2 · 10 MIN" },
		{ At = 5000, Kind = "Boss", Difficulty = 2, Name = "THE GRAVEKEEPER RISES" },
	},
	ResetAfterBoss = true,
}

---------------------------------------------------------------------------------------------------------------------
-- DAILY QUESTS (UTC day; 5 drawn per player per day from the pool, deterministic per user+day)
---------------------------------------------------------------------------------------------------------------------
C.Quests = {
	PerDay = 5,
	Pool = {
		{ Id = "DigSpots", Text = "Dig %d Haunted Spots", Goal = 10, Candy = 45, Bones = 40 },
		{ Id = "Perfect", Text = "Get %d Perfect Hits", Goal = 10, Candy = 30 },
		{ Id = "EarnCandy", Text = "Earn %d Candy", Goal = 50, Candy = 25, Bones = 25 },
		{ Id = "BloodMoon", Text = "Participate in a Blood Moon", Goal = 1, Candy = 40 },
		{ Id = "BossDamage", Text = "Damage the Gravekeeper", Goal = 400, Candy = 50, Bones = 60 },
		{ Id = "OpenPumpkin", Text = "Open a Pumpkin Block", Goal = 1, Candy = 35 },
		{ Id = "FindMutation", Text = "Find a Halloween mutation", Goal = 1, Candy = 50 },
		{ Id = "MineOre", Text = "Break %d Halloween ores", Goal = 12, Candy = 30 },
		{ Id = "Knock", Text = "Knock on %d doors", Goal = 3, Candy = 25 },
	},
	Always = { "Perfect", "EarnCandy" }, -- always part of the daily set
	AllBonus = { Kind = "Block", Id = "Pumpkin", Amount = 1, Candy = 30 }, -- finishing every daily quest
}

---------------------------------------------------------------------------------------------------------------------
-- EVENT DOGDEX rewards (BURIED MOON 2026 tab; separate ledger from the main dex)
---------------------------------------------------------------------------------------------------------------------
C.DexRewards = {
	{ Count = 2, Candy = 60, Bones = 80 },
	{ Count = 4, Candy = 120, Block = "Pumpkin" },
	{ Count = 6, Candy = 200, Skin = "GraveShovel" },
	{ Count = 8, Candy = 400, Block = "Cursed Pumpkin", Skin = "SoulReaper", Title = "BuriedMoon2026" },
}

---------------------------------------------------------------------------------------------------------------------
-- PICKAXE SKINS (cosmetic only; stats always come from the player's real pickaxe tier)
---------------------------------------------------------------------------------------------------------------------
C.Skins = {
	Order = { "GraveShovel", "BonePickaxe", "PumpkinSmasher", "GhostScythe", "LivingCoffin", "SoulReaper" },
	Names = { GraveShovel = "Grave Shovel", BonePickaxe = "Bone Pickaxe", PumpkinSmasher = "Pumpkin Smasher",
		GhostScythe = "Ghost Scythe", LivingCoffin = "Living Coffin", SoulReaper = "Soul Reaper" },
	Rarity = { GraveShovel = "Epic", BonePickaxe = "Legendary", PumpkinSmasher = "Legendary", GhostScythe = "Mythic",
		LivingCoffin = "Mythic", SoulReaper = "Secret" },
}

---------------------------------------------------------------------------------------------------------------------
-- PRESENTATION / QUALITY
---------------------------------------------------------------------------------------------------------------------
C.Quality = {
	High = { Particles = 60, Lights = 22, Ambient = 1, Crows = 9, Ghosts = 5, Bats = 14 },
	Medium = { Particles = 32, Lights = 14, Ambient = .7, Crows = 6, Ghosts = 3, Bats = 8 },
	Low = { Particles = 10, Lights = 6, Ambient = .35, Crows = 3, Ghosts = 1, Bats = 3 },
}
C.Palette = { -- UI + world accents (Color3.fromRGB components)
	Pumpkin = { 255, 128, 24 }, Purple = { 122, 62, 200 }, DeepPurple = { 40, 16, 60 }, Neon = { 120, 255, 110 },
	Blood = { 200, 30, 50 }, Ghost = { 140, 215, 255 }, Bone = { 236, 226, 200 }, Gold = { 255, 200, 70 }, Ink = { 18, 10, 28 },
}
C.Music = { OstAssetId = 0, BloodMoonAssetId = 0, Volume = .5, Crossfade = 3 } -- uploaded ids optional; 0 = procedural OST

return C
