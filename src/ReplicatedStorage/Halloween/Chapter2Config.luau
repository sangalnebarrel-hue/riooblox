-- DOGROTS HALLOWEEN PART II · THE UNDERYARD — every balance number of CHAPTER II lives here.
-- ReplicatedStorage.Halloween.Chapter2Config (shared by server and client; docs/halloween2/DESIGN.md §1-§11, §17).
-- The server is the only side that grants anything; clients read this table for UI / FX / timers only.
-- Pure math on these numbers (DR, rested, dates, offering discount, contracts, coffin roll, duplicates, dex II) lives in
-- ReplicatedStorage.Halloween.Chapter2Rules. Saved ids (seal numbers, dog ids, decor / skin / find ids, contract ids,
-- journal keys, title keys) are permanent: never rename one that shipped.
-- Dates are UTC {Year, Month, Day, Hour?}. The Chapter I switches live in Halloween.Config (HalloweenChapter2Enabled).
local C = {}

C.Version = 1
C.EventId = "Underyard2026" -- EventDex of the dogs H09-H16 and Reward tag of the plot cosmetics
C.Name = { "THE UNDERYARD", "ПОДДВОРЬЕ" }
C.Subtitle = { "BENEATH THE LAST BELL", "ПОД ПОСЛЕДНИМ КОЛОКОЛОМ" }
C.Start = { Year = 2026, Month = 10, Day = 20, Hour = 0 } -- Chapter II opens; the rested allowance counts from here
C.ClaimDeadline = { Year = 2026, Month = 11, Day = 1, Hour = 0 } -- informational (the window shows "the bell falls silent")

---------------------------------------------------------------------------------------------------------------------
-- CHAPTER I COMPLETION (HalloweenChapter1Complete, §3.3) — existing persistent fields only, latched once true
---------------------------------------------------------------------------------------------------------------------
C.Chapter1 = {
	Req = {
		BossBest = 2, -- p.Halloween.Boss.Best: beat THE GRAVEKEEPER on UNEASY (II) or higher with a full reward
		Cauldron = 300, -- p.Halloween.Cauldron.Invested: cauldron level 3 BOILING (the 7-day brew claim is NOT required)
		Knocks = 7, -- p.Halloween.Stats.Knocks: doors knocked (lifetime)
		BloodMoons = 1, -- p.Halloween.Stats.BloodMoons: Blood Moon participations
		Spots = 10, -- p.Halloween.Stats.Spots: haunted dig spots dug
	},
	-- checklist rows in the order the locked CHAPTER II card shows them (Key = Req key)
	Checklist = {
		{ Key = "BossBest", Text = { "Defeat THE GRAVEKEEPER on UNEASY or higher", "Победи СМОТРИТЕЛЯ КЛАДБИЩА на сложности ТРЕВОЖНО или выше" } },
		{ Key = "Cauldron", Text = { "Feed the cauldron to level 3 (BOILING)", "Накорми котёл до 3 уровня (КИПИТ)" } },
		{ Key = "Knocks", Text = { "Knock on 7 cursed doors", "Постучи в 7 проклятых дверей" } },
		{ Key = "BloodMoons", Text = { "Take part in a Blood Moon", "Поучаствуй в Кровавой Луне" } },
		{ Key = "Spots", Text = { "Dig 10 haunted spots", "Раскопай 10 проклятых могил" } },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- THE REVEAL, THE CHURCH AND THE PORTAL (§6)
---------------------------------------------------------------------------------------------------------------------
C.Reveal = {
	ChurchRadius = 60, -- C2RevealSeen: the player must be this close to the crypt door (server, + Slack)
	TriggerRadius = 46, -- the client plays the church cinematic inside this radius (UnderyardLayout.Church)
	TeaserEvery = { 45, 90 }, -- not yet eligible: bell toll + "Something is waiting below." near the church
}
C.Portal = {
	HoldDuration = .5,
	Range = 10, -- ProximityPrompt MaxActivationDistance (church DESCEND and arrival arch ASCEND)
	Cooldown = 3, -- seconds between two portal uses of one player
	TransitionDelay = .8, -- seconds the server waits (client screen goes black) before moving the character
	StreamTimeout = 6, -- RequestStreamAroundAsync budget before the move happens anyway
	Grace = .6, -- seconds after a teleport the zone polls ignore the character (no void / gate push-back)
}

---------------------------------------------------------------------------------------------------------------------
-- ZONE RUNTIME (Underyard.luau)
---------------------------------------------------------------------------------------------------------------------
C.Zone = {
	PresenceRate = .25, -- seconds between presence samples (UyInZone / UyDistrict, 4 Hz)
	GateRate = .5, -- seconds between district gating checks (push-back to the gate)
	GatePush = 9, -- studs in front of a gate (towards Bell Square) a sealed player is put back to
	RespawnWindow = 15, -- a player who died in the Underyard less than this many seconds ago respawns there
	VoidY = -34, -- below this (inside the zone footprint) the character is recovered to the arrival arch
	FootprintMargin = 30, -- studs around UnderyardLayout.Zone that still count as "fell from the Underyard"
	PracticeSlack = 2, -- studs around the practice ring that still count as inside it
}

-- server proximity checks (a lagged client: + Slack studs)
C.Proximity = {
	Radius = 16, -- Toll Box, seal altars, coffin shrine
	Slack = 6,
}

---------------------------------------------------------------------------------------------------------------------
-- BELL SEALS (§8.1 / §8.4) — date gate (UTC) + previous seal cleared + offering paid at its altar in Bell Square
---------------------------------------------------------------------------------------------------------------------
-- Rewards.First (DR-exempt "First") + Keys on the first clear, Rewards.Repeat (DR "Repeat") on later clears,
-- Rewards.Rows = extra rows of the first clear (dogs / plot cosmetics). Gold (stricter target) first time: GoldRewards.
-- Trial = framework numbers (Seals.luau), Gold = criteria the default evaluator reads (Seals.DefaultGold),
-- Activity = numbers of the activity module itself (WP-I / WP-J).
C.Seals = {
	{
		Index = 1, Id = "Echo", Numeral = "I", Name = { "ECHO", "ЭХО" }, Trial = { Id = "EchoDig", TimeLimit = 90, Goal = 12 },
		Title = { "ECHO DIG", "ЭХО-РАСКОПКИ" }, District = "BellSquare", Opens = { Year = 2026, Month = 10, Day = 20 }, Offering = 100,
		Text = { "Haunted echoes jump between the graves of Bell Square. Dig each one before it leaps away.",
			"Призрачные эхо прыгают между могилами Колокольной площади. Раскопай каждое, пока оно не ускользнуло." },
		Gold = { Total = 18, PerfectShare = .6 },
		Rewards = { First = 150, Repeat = 20, Keys = 1, Rows = { { Kind = "Dog", Id = "HW_BellPup", Rank = 2 } } },
		GoldRewards = { Keys = 1 },
		Activity = { Points = 16, Life = 4.5, Trail = 1.2, MaxAlive = 3, ObjectiveShards = 2, Kind = "UyEcho" },
	},
	{
		Index = 2, Id = "Procession", Numeral = "II", Name = { "PROCESSION", "ПРОЦЕССИЯ" }, Trial = { Id = "FuneralRun", TimeLimit = 75, Goal = 10 },
		Title = { "FUNERAL RUN", "ПОХОРОННЫЙ ЗАБЕГ" }, District = "FuneralCarnival", Opens = { Year = 2026, Month = 10, Day = 20 }, Offering = 200,
		Text = { "Run the dead carnival: ten rings in order, past the swinging coffins and over the carousel.",
			"Пробеги мёртвый карнавал: десять колец по порядку, мимо качающихся гробов и через карусель." },
		Gold = { Time = 55 },
		Rewards = { First = 175, Repeat = 25, Keys = 1, Rows = {} },
		GoldRewards = { Keys = 1 },
		Activity = { Checkpoints = 10, PendulumPeriod = 3.2, PendulumDamage = 12, PendulumKnock = 70, CarouselBetween = { 5, 6 },
			MaxSpeed = 72, SpeedSlack = 1.15, SampleRate = .25, ObjectiveShards = 1, StartAnchor = "RunStart" },
	},
	{
		Index = 3, Id = "Reflection", Numeral = "III", Name = { "REFLECTION", "ОТРАЖЕНИЕ" }, Trial = { Id = "MirrorGraves", TimeLimit = 240, Goal = 3 },
		Title = { "MIRROR GRAVES", "ЗЕРКАЛЬНЫЕ МОГИЛЫ" }, District = "MourningMarsh", Opens = { Year = 2026, Month = 10, Day = 21 }, Offering = 300,
		Text = { "The pond remembers the graves mirrored left to right. Turn the runes until the water agrees.",
			"Пруд помнит могилы, отражённые слева направо. Поворачивай руны, пока вода не согласится." },
		Gold = { NoMistakes = true },
		Rewards = { First = 200, Repeat = 30, Keys = 1, Rows = {} },
		GoldRewards = { Keys = 1 },
		Activity = { Graves = 6, Directions = 4, Rounds = { 4, 5, 6 }, WrongPenalty = 15, ObjectiveShards = 4 },
	},
	{
		Index = 4, Id = "Hollow", Numeral = "IV", Name = { "HOLLOW", "ПУСТОТА" }, Trial = { Id = "HollowMine", TimeLimit = 240, Goal = 14, Combat = true },
		Title = { "HOLLOW MINE", "ПОЛАЯ ШАХТА" }, District = "Undercrypt", Opens = { Year = 2026, Month = 10, Day = 22 }, Offering = 400,
		Text = { "Break the hollow ore cores on the sunken mine floor while the Undercrypt collapses around you.",
			"Разбей полые рудные ядра на дне затопленной шахты, пока Подклепье рушится вокруг." },
		Gold = { Total = 20, NoDowns = true },
		Rewards = { First = 250, Repeat = 35, Keys = 1, Rows = { { Kind = "Dog", Id = "HW_CandleCorgi", Rank = 3 } } },
		GoldRewards = { Keys = 1 },
		Activity = { Nodes = 12, Respawn = { 6, 10 }, NodeHits = 7, ObjectiveShards = 3, Kind = "UyHollowOre", StartAnchor = "MineEntrance",
			Rocks = { Radius = 6, Telegraph = 1.4, Damage = 18, Every = { 4, 7 } },
			Gas = { Radius = 5, Telegraph = 1.2, DPS = 6, Linger = 6, Every = { 9, 14 } },
			Tunnel = { Width = 8, Length = 40, Telegraph = 1.6, Damage = 22, Every = { 20, 30 } } },
	},
	{
		Index = 5, Id = "Choice", Numeral = "V", Name = { "CHOICE", "ВЫБОР" }, Trial = { Id = "CrookedDoors", TimeLimit = 0, Goal = 3 },
		Title = { "CROOKED DOORS", "КРИВЫЕ ДВЕРИ" }, District = "CrookedRow", Opens = { Year = 2026, Month = 10, Day = 23 }, Offering = 500,
		Text = { "Four crooked doors, a few openings a day. Behind them: treasure, a test, the Doorkeeper or a hidden room.",
			"Четыре кривые двери и всего несколько попыток в день. За ними сокровище, испытание, Привратник или тайная комната." },
		Gold = { NoDowns = true }, -- Seal V Gold: the three outcomes without being downed in a challenge / mini boss
		Rewards = { First = 275, Repeat = 40, Keys = 1, Rows = {} },
		GoldRewards = { Keys = 1 },
		Activity = { Outcomes = 3 }, -- door numbers: C.Doors
	},
	{
		Index = 6, Id = "Choir", Numeral = "VI", Name = { "CHOIR", "ХОР" }, Trial = { Id = "ChoirHunt", TimeLimit = 480, Goal = 7 },
		Title = { "CHOIR HUNT", "ОХОТА НА ХОР" }, District = "*", Opens = { Year = 2026, Month = 10, Day = 24 }, Offering = 650,
		Text = { "Seven spirits sing one note each of the Last Bell's song. Follow the melody, catch them with a Perfect.",
			"Семь духов поют по одной ноте песни Последнего колокола. Иди на мелодию и лови их идеальным ударом." },
		Gold = { Time = 300 },
		Rewards = { First = 325, Repeat = 50, Keys = 1, Rows = {} },
		GoldRewards = { Keys = 1 },
		Activity = { Spirits = 7, FleeDistance = 25, Speed = 7, ObjectiveShards = 4, Kind = "UyChoir" }, -- numbers: C.Choir too
	},
	{
		Index = 7, Id = "LastBell", Numeral = "VII", Name = { "LAST BELL", "ПОСЛЕДНИЙ КОЛОКОЛ" }, Trial = { Id = "LastBell", TimeLimit = 360, Goal = 3, Combat = true },
		Title = { "LAST BELL TRIAL", "ИСПЫТАНИЕ ПОСЛЕДНЕГО КОЛОКОЛА" }, District = "BlackBellArena", Opens = { Year = 2026, Month = 10, Day = 26 }, Offering = 800,
		Text = { "THE BELLKEEPER holds the Black Bell's rope. Survive the tolls, break the chains, burn his weak point.",
			"ЗВОНАРЬ держит верёвку Чёрного колокола. Переживи удары, разбей цепи, прожги его слабое место." },
		Gold = { NoBleedOut = true },
		Rewards = { First = 400, Repeat = 60, Keys = 1,
			Rows = { { Kind = "Dog", Id = "HW_MourningShiba", Rank = 3 }, { Kind = "Decor", Id = "uy_crooked_bell_tower" } } },
		GoldRewards = { Keys = 1 },
		Activity = { Waves = 3, ShockwaveDamage = 14, ShockwaveEvery = { 6, 8 }, Chains = 4, ChainHits = 6, ChainHitsPerFighter = 3,
			PulsePeriod = 1.2, WeakHP = 30, WeakHPPerFighter = 10, ObjectiveShards = 4, StartAnchor = "ArenaCentre", Spawn = "ArenaSpawn" },
	},
}
C.SealCount = #C.Seals

-- "The Bell remembers": a seal whose date opened at least this many days ago costs 40% less to offer (§8.3)
C.Offering = { DiscountAfterDays = 2, Discount = .4 }

---------------------------------------------------------------------------------------------------------------------
-- TRIALS FRAMEWORK (Seals.luau, §22.4)
---------------------------------------------------------------------------------------------------------------------
C.Trials = {
	MaxParty = 6,
	PartyRadius = 30, -- eligible players this close to the leader at start join the run
	StartRadius = 16, -- the leader must be this close to the start anchor (+ C.Proximity.Slack)
	TickRate = .1, -- server run tick (10 Hz max)
	SampleRate = .25, -- position samples of movement trials (4 Hz)
	LeaveGrace = 3, -- seconds outside the trial's districts before the player is out
	SignalEvery = 1, -- "Tick" signal period
	EndHold = 4, -- seconds a finished run stays published before it is cleaned up
	Cooldown = 3, -- seconds between two starts of one player
	-- non-seal trials (Seals.RegisterTrial): tutorial, door challenges, the Assault
	Defs = {
		Toll = { TimeLimit = 40, Goal = 5, MaxParty = 1, District = "BellSquare", StartAnchor = "TutorialBell" },
		Mourner = { TimeLimit = 90, Goal = 1, MaxParty = 1, District = "BellSquare", StartAnchor = "Mourner", Combat = true },
		DoorChallenge = { TimeLimit = 25, Goal = 1, MaxParty = 1, District = "CrookedRow", StartAnchor = "DoorCourt", Combat = true },
		Doorkeeper = { TimeLimit = 120, Goal = 1, MaxParty = 6, District = "CrookedRow", StartAnchor = "DoorCourt", Combat = true },
		Assault = { TimeLimit = 480, Goal = 1, MaxParty = 40, PartyRadius = 1000, District = "BlackBellArena", StartAnchor = "ArenaCentre",
			Combat = true },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- BELL SHARDS · daily diminishing returns (§8.2) and catch-up (§8.3)
---------------------------------------------------------------------------------------------------------------------
-- DR by raw shards earned today (UTC): first 500 at 100%, next 500 at 35%, beyond 10%. Exact float integration:
-- the profile keeps the cumulative effective amount and every grant pays floor(after) - floor(before).
C.DailyReturns = {
	Tiers = { { Upto = 500, Rate = 1 }, { Upto = 1000, Rate = .35 }, { Rate = .10 } }, -- the last tier has no Upto
	-- sources that skip DR (fixed / capped rewards)
	Exempt = {
		First = true, -- seal first clear
		Contract = true, -- daily contract claim
		FinaleFirst = true, -- Gravekeeper finale first clear
		Exchange = true, -- Toll Box (own daily cap)
		Tutorial = true, -- Chapter II onboarding grant / refund
		Dex = true, -- Dex II milestone
		Refund = true, -- Black Coffin shards row (a refund of the opening price)
		Duplicate = true, -- duplicate conversion
		Overflow = true, -- Coffin Key overflow conversion
		Debug = true,
	},
}
C.Rested = {
	PerDay = 500, -- a full UTC day with less than this raw shards ...
	Fraction = .5, -- ... adds (PerDay - earned) x Fraction to the pool
	Cap = 750,
}
-- shard sources (C2.Progress / ctx.Shards labels): Streak Echo Ore Spirit Objective Repeat Boss Door Resonance Assault
-- (DR) and the exempt ones above. "Earn Bell Shards" contracts and Stats.ShardsEarned ignore these:
C.ShardsIgnore = { Contract = true, Exchange = true, Debug = true, Tutorial = true }

-- Perfect Hit streaks on Underyard targets (C2.StreakHit)
C.Streak = {
	Every = 5, -- consecutive Perfects
	Shards = 2,
	MinuteCap = 10, -- streak shards per player per rolling minute (before the resonance buff)
	Timeout = 6, -- seconds without a judged hit break the streak
}

-- Candy -> Bell Shards at the Toll Box (Bell Square)
C.Exchange = {
	CandyPerShard = 25,
	MaxPerDay = 40, -- shards per UTC day
	MaxPerRequest = 40,
}

---------------------------------------------------------------------------------------------------------------------
-- DAILY CONTRACTS (§8.5): 3 per UTC day per player, deterministic per userId + day; unclaimed ones expire
---------------------------------------------------------------------------------------------------------------------
-- Id = the C2.Progress statKey that advances it. MinCleared: seals the player must have cleared when the day's list
-- is drawn (so nobody gets a contract for a district that is still sealed for them). Weight: draw weight.
C.Contracts = {
	PerDay = 3,
	Reward = { Shards = 60 }, -- each claim, DR-exempt
	Bonus = { Keys = 1 }, -- all three claimed (C2ContractBonus)
	Pool = {
		{ Id = "Perfect", Goal = 40, Weight = 10, MinCleared = 0, Text = { "Land %d Perfect Hits in the Underyard", "Сделай %d идеальных ударов в Поддворье" } },
		{ Id = "Trial", Goal = 1, Weight = 10, MinCleared = 0, Text = { "Clear any Bell Trial", "Пройди любое испытание колокола" } },
		{ Id = "Echo", Goal = 15, Weight = 9, MinCleared = 0, Text = { "Dig %d echo points", "Раскопай %d точек эха" } },
		{ Id = "Shards", Goal = 250, Weight = 9, MinCleared = 0, Text = { "Earn %d Bell Shards", "Заработай %d осколков колокола" } },
		{ Id = "BossDamage", Goal = 2500, Weight = 7, MinCleared = 0, Text = { "Deal %d damage to THE GRAVEKEEPER", "Нанеси СМОТРИТЕЛЮ КЛАДБИЩА %d урона" } },
		{ Id = "Coffin", Goal = 1, Weight = 6, MinCleared = 0, Text = { "Open a Black Coffin", "Открой Чёрный гроб" } },
		{ Id = "Resonance", Goal = 150, Weight = 8, MinCleared = 0, Text = { "Contribute %d Bell Resonance", "Внеси %d резонанса колокола" } },
		{ Id = "Ore", Goal = 12, Weight = 9, MinCleared = 3, Text = { "Break %d hollow ore cores", "Разбей %d полых рудных ядер" } },
		{ Id = "Revive", Goal = 1, Weight = 4, MinCleared = 3, Text = { "Revive an ally", "Подними союзника" } },
		{ Id = "Door", Goal = 1, Weight = 8, MinCleared = 4, Text = { "Open a Crooked Door", "Открой кривую дверь" } },
		{ Id = "Spirit", Goal = 3, Weight = 8, MinCleared = 5, Text = { "Catch %d choir spirits", "Поймай %d духов хора" } },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- COFFIN KEYS + THE BLACK COFFIN (§9.1-§9.4)
---------------------------------------------------------------------------------------------------------------------
C.Coffin = {
	Price = { Shards = 150, Keys = 1 }, -- at the coffin shrine in Bell Square
	MaxKeys = 12, -- stored keys; never sold
	OverflowKeyShards = 60, -- a reward key above MaxKeys converts to this many shards (DR-exempt "Overflow")
	Last = 10, -- results kept in Coffins.Last
	TotalWeight = 100000,
	-- the table is built below (rows with weights, ids from §9.8); C.Coffin.Table
}

-- Showcase finds (ItemDefinitions ids, Class "Underyard"; never in a DepthDefinitions list)
C.Finds = {
	Order = { "uy_coffin_nail", "uy_black_feather", "uy_wax_hand", "uy_crooked_house_key", "uy_blue_funeral_rose",
		"uy_bottled_whisper", "uy_broken_pocket_watch", "uy_lost_veil", "uy_cracked_bell_clapper", "uy_tiny_tombstone",
		"uy_dead_wedding_ring", "uy_ghost_photograph", "uy_mourning_locket", "uy_bellkeeper_mask", "uy_hollow_heart" },
	Defs = {
		uy_coffin_nail = { Tier = "Common", Name = { "Coffin Nail", "Гробовой гвоздь" } },
		uy_black_feather = { Tier = "Common", Name = { "Black Feather", "Чёрное перо" } },
		uy_wax_hand = { Tier = "Common", Name = { "Wax Hand", "Восковая рука" } },
		uy_crooked_house_key = { Tier = "Common", Name = { "Crooked House Key", "Ключ от кривого дома" } },
		uy_blue_funeral_rose = { Tier = "Common", Name = { "Blue Funeral Rose", "Синяя траурная роза" } },
		uy_bottled_whisper = { Tier = "Rare", Name = { "Bottled Whisper", "Шёпот в бутылке" } },
		uy_broken_pocket_watch = { Tier = "Rare", Name = { "Broken Pocket Watch", "Сломанные карманные часы" } },
		uy_lost_veil = { Tier = "Rare", Name = { "Lost Veil", "Потерянная вуаль" } },
		uy_cracked_bell_clapper = { Tier = "Rare", Name = { "Cracked Bell Clapper", "Треснувший язык колокола" } },
		uy_tiny_tombstone = { Tier = "Rare", Name = { "Tiny Tombstone", "Крошечное надгробие" } },
		uy_dead_wedding_ring = { Tier = "Epic", Name = { "Dead Wedding Ring", "Мёртвое обручальное кольцо" } },
		uy_ghost_photograph = { Tier = "Epic", Name = { "Ghost Photograph", "Призрачная фотография" } },
		uy_mourning_locket = { Tier = "Epic", Name = { "Mourning Locket", "Траурный медальон" } },
		uy_bellkeeper_mask = { Tier = "Legendary", Name = { "Bellkeeper Mask", "Маска Звонаря" } },
		uy_hollow_heart = { Tier = "Legendary", Name = { "Hollow Heart", "Полое сердце" } },
	},
	TierWeight = { Common = 3000, Rare = 1800, Epic = 1500, Legendary = 700 }, -- coffin weight per find of that tier
	TierRank = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 },
}

-- Plot cosmetics (DecorCatalog rows, Reward = "Underyard2026")
C.Decor = {
	Order = { "uy_crooked_bell_tower", "uy_whispering_tree", "uy_haunted_kennel", "uy_spirit_fence", "uy_coffin_flowerbed",
		"uy_floating_tombstones", "uy_funeral_lanterns", "uy_moon_statue", "uy_ghost_fountain", "uy_grave_gate" },
	Defs = {
		uy_crooked_bell_tower = { Size = "Large", Rarity = "Legendary", Name = { "Crooked Bell Tower", "Кривая колокольня" } },
		uy_whispering_tree = { Size = "Large", Rarity = "Epic", Name = { "Whispering Tree", "Шепчущее дерево" } },
		uy_haunted_kennel = { Size = "Small", Rarity = "Rare", Name = { "Haunted Kennel", "Будка с привидениями" } },
		uy_spirit_fence = { Size = "Small", Rarity = "Rare", Name = { "Spirit Fence", "Призрачный забор" } },
		uy_coffin_flowerbed = { Size = "Small", Rarity = "Rare", Name = { "Coffin Flowerbed", "Клумба-гроб" } },
		uy_floating_tombstones = { Size = "Small", Rarity = "Epic", Name = { "Floating Tombstones", "Парящие надгробия" } },
		uy_funeral_lanterns = { Size = "Small", Rarity = "Epic", Name = { "Funeral Lantern Set", "Траурные фонари" } },
		uy_moon_statue = { Size = "Large", Rarity = "Mythic", Name = { "Moon Statue", "Лунная статуя" } },
		uy_ghost_fountain = { Size = "Large", Rarity = "Legendary", Name = { "Ghost Fountain", "Призрачный фонтан" } },
		uy_grave_gate = { Size = "Large", Rarity = "Legendary", Name = { "Animated Grave Gate", "Живые кладбищенские ворота" } },
	},
	CoffinWeight = 150, -- each
}

-- Pickaxe skins (Halloween Config.Skins entries with Chapter = 2, added by WP-K2; cosmetic only)
C.Skins = {
	Order = { "UY_ToothyAlarm", "UY_FateHand", "UY_Laughsaw", "UY_TVHead", "UY_NastyOctopus", "UY_GummyHorror", "UY_BellReaper" },
	Defs = {
		UY_ToothyAlarm = { Rarity = "Epic", Name = { "Toothy Alarm", "Зубастый Будильник" } },
		UY_FateHand = { Rarity = "Legendary", Name = { "Hand of Fate · Buried", "Рука Судьбы · Погребённая" } },
		UY_Laughsaw = { Rarity = "Legendary", Name = { "Laughsaw · Funeral", "Смехопила · Похоронная" } },
		UY_TVHead = { Rarity = "Mythic", Name = { "TV-Head · Static", "ТВ-Башка · Помехи" } },
		UY_NastyOctopus = { Rarity = "Mythic", Name = { "Nasty Octopus · Swamp", "Мерзкий Спрут · Болотный" } },
		UY_GummyHorror = { Rarity = "Mythic", Name = { "Gummy Horror", "Мармеладный Ужас" } },
		UY_BellReaper = { Rarity = "Secret", Name = { "Bell Reaper", "Жнец Колокола" }, DexOnly = true },
	},
	CoffinWeight = 95, -- each (the Dex-only Secret skin is never in the coffin nor the tailor)
}

---------------------------------------------------------------------------------------------------------------------
-- EVENT DOGS H09-H16 (DogDefinitions Index 209-216, EventDex "Underyard2026") + ability numbers (§9.8)
-- Abilities count while the dog is assigned to a yard dig slot (same rule as H01-H08).
---------------------------------------------------------------------------------------------------------------------
C.Dogs = {
	Order = { "HW_BellPup", "HW_CandleCorgi", "HW_MourningShiba", "HW_CoffinPug", "HW_MothHound", "HW_Bridehound",
		"HW_BellkeeperWolf", "HW_HollowKing" },
	Defs = {
		HW_BellPup = { Code = "H09", Index = 209, EventIndex = 9, Rank = 2, Name = { "Bell Pup", "Колокольчик" }, Ability = "EchoEar",
			EchoLifeBonus = 4, PulseNextJump = true },
		HW_CandleCorgi = { Code = "H10", Index = 210, EventIndex = 10, Rank = 3, Name = { "Candle Corgi", "Свечной корги" },
			Ability = "Candlelight", TelegraphLead = .35, GasReduction = .30 },
		HW_MourningShiba = { Code = "H11", Index = 211, EventIndex = 11, Rank = 3, Name = { "Mourning Shiba", "Скорбная шиба" },
			Ability = "MourningVeil", SelfReviveAfter = 8, SelfRevivesPerFight = 1, ReviveOnYouFaster = .40 },
		HW_CoffinPug = { Code = "H12", Index = 212, EventIndex = 12, Rank = 4, Name = { "Coffin Pug", "Гробовой мопс" }, Ability = "CoffinSense",
			BonusFindChance = .08, DuplicateBonus = .25 },
		HW_MothHound = { Code = "H13", Index = 213, EventIndex = 13, Rank = 4, Name = { "Moth Hound", "Мотыльковая гончая" }, Ability = "MothSwarm",
			RewardDoorChance = .35, ShowNearestSpirit = true },
		HW_Bridehound = { Code = "H14", Index = 214, EventIndex = 14, Rank = 5, Name = { "Bridehound", "Невеста-гончая" }, Ability = "EternalVow",
			MaxHPBonus = 15, ReviveSpeedMult = 2, ReviveShield = 20 },
		HW_BellkeeperWolf = { Code = "H15", Index = 215, EventIndex = 15, Rank = 5, Name = { "Bellkeeper Wolf", "Волк-звонарь" },
			Ability = "ResonantHowl", ResonancePerfectMult = 2, MechanicDamageBonus = .25 },
		HW_HollowKing = { Code = "H16", Index = 216, EventIndex = 16, Rank = 6, Name = { "Hollow King", "Полый король" }, Ability = "CrownOfTheUnderyard",
			Secret = true, ActiveMinutesPerRoll = 20, ExtraFindRolls = 1 },
	},
	CoffinWeight = { HW_BellPup = 220, HW_CandleCorgi = 160, HW_MourningShiba = 160, HW_CoffinPug = 120, HW_MothHound = 120,
		HW_Bridehound = 32, HW_BellkeeperWolf = 32, HW_HollowKing = 4 },
	TeamOnly = true,
}

-- DEX II milestones (§9.8). Rows use the ctx.C2Reward kinds.
C.Dex2Rewards = {
	{ Count = 3, Rows = { { Kind = "Shards", Amount = 300, Source = "Dex" }, { Kind = "Key", Amount = 1, Source = "Dex" } } },
	{ Count = 5, Rows = { { Kind = "Decor", Id = "uy_spirit_fence" }, { Kind = "Dust", Amount = 1500 } } },
	{ Count = 7, Rows = { { Kind = "Skin", Id = "UY_ToothyAlarm" } } },
	{ Count = 8, Rows = { { Kind = "Skin", Id = "UY_BellReaper" }, { Kind = "Title", Id = "HollowCrown2026" } } },
}

-- Duplicates / fallback (§9.4). Dogs are never converted (a duplicate dog is still a dog); a dog that cannot be
-- delivered (full dog storage, model not in this place) becomes DogShardsPerRank x rank shards.
C.Duplicates = {
	Decor = { Fragments = 12, Dust = 400 },
	Skin = { Fragments = 25, Dust = 800 },
	Find = { Shards = 80, Dust = 150, LegendaryFragments = 3 },
	DogShardsPerRank = 150,
	CoffinPugBonus = .25, -- H12 in the yard team: +25% on every duplicate conversion
}

-- THE TAILOR OF THE DEAD (§9.5): fragments -> a chosen cosmetic (bad-luck path)
C.Craft = {
	Decor = 45,
	Skin = 90,
	MaxFragments = 99999,
}

---------------------------------------------------------------------------------------------------------------------
-- CROOKED DOORS (Seal V; §8.4.5)
---------------------------------------------------------------------------------------------------------------------
C.Doors = {
	PerDay = 3,
	ContractBonus = 1, -- +1 door when all of today's contracts are claimed
	MothChance = .35, -- H13: a moth marks the reward door before choosing
	Outcomes = {
		{ Id = "Reward", Weight = 40 },
		{ Id = "Challenge", Weight = 30 },
		{ Id = "MiniBoss", Weight = 20 },
		{ Id = "Rare", Weight = 10 },
	},
	Reward = { Shards = { 30, 80 }, Dust = { 80, 160 }, KeyChance = .15, FindChance = .04 },
	Challenge = { Seconds = 25, Shards = { 30, 60 }, Dust = { 60, 120 } },
	MiniBoss = { Name = { "THE DOORKEEPER", "ПРИВРАТНИК" }, Shards = { 40, 80 }, Dust = { 100, 200 }, KeyChance = .1 },
	Rare = { Chests = 3, Keys = 1, Finds = 1, HollowKingChance = .005, Dust = { 150, 300 } },
	Resonance = 10,
}

---------------------------------------------------------------------------------------------------------------------
-- CHOIR HUNT (Seal VI; §8.4.6)
---------------------------------------------------------------------------------------------------------------------
C.Choir = { Spirits = 7, FleeDistance = 25, TimeLimit = 480, GoldTime = 300, MothShowsNearest = true }

---------------------------------------------------------------------------------------------------------------------
-- BELL RESONANCE (§8.6, server mechanic in Resonance.luau) — points per action (C2.Progress statKeys)
---------------------------------------------------------------------------------------------------------------------
C.Resonance = {
	Base = 4000,
	PlayerDivisor = 6, -- Goal = Base x clamp(activeUnderyardPlayers / PlayerDivisor, Clamp[1], Clamp[2])
	Clamp = { .6, 2 },
	RecomputeEvery = 60,
	ActivityWindow = 180, -- AFK players get nothing
	Points = { Perfect = 1, Streak = 3, Echo = 4, Ore = 4, Spirit = 4, Trial = 60, Door = 10, Revive = 15 },
	BossDamagePer = 150, -- 1 point per this much armor damage
	Milestones = {
		{ At = .25, Kind = "Toll", Name = { "RESONANT TOLL", "РЕЗОНИРУЮЩИЙ ЗВОН" }, StreakBonus = .25, Seconds = 300 },
		{ At = .5, Kind = "Keys", Name = { "KEYS FOR THE FAITHFUL", "КЛЮЧИ ДЛЯ ВЕРНЫХ" }, Keys = 1, PerDay = 2 },
		{ At = .75, Kind = "Echoes", Name = { "RESONANT ECHOES", "РЕЗОНИРУЮЩЕЕ ЭХО" }, Count = 6, Seconds = 180, Shards = 4, Points = 6 },
		{ At = 1, Kind = "Assault", Name = { "BLACK BELL ASSAULT", "ШТУРМ ЧЁРНОГО КОЛОКОЛА" }, Seconds = 480 },
	},
	Assault = { Shards = { 60, 120 }, Keys = 1, DropChance = .02, HPPerAttacker = 1, BaseHP = 400 },
	KeysPerDay = 2, -- resonance keys a player can get per UTC day (Daily.Keys)
}

---------------------------------------------------------------------------------------------------------------------
-- THE GRAVEKEEPER for Chapter II players (§8.2 / §9.1) and the difficulty V finale rewards (§11.1)
---------------------------------------------------------------------------------------------------------------------
C.BossRewards = {
	Shards = { [3] = 25, [4] = 40, [5] = 70 }, -- full reward, DR source "Boss"
	FirstClearKeys = { [3] = 1, [4] = 1, [5] = 1 }, -- first full clear of III / IV / V (Boss.FirstClears)
}
C.Finale = {
	Rewards = {
		First = { Shards = 250, ShardSource = "FinaleFirst", Keys = 3, Title = "LastBark2026", Decor = "uy_moon_statue",
			Dogs = { { Id = "HW_BellkeeperWolf", Chance = .12, Rank = 5 }, { Id = "HW_HollowKing", Chance = .004, Rank = 6 } } },
		Repeat = { Shards = 120, ShardSource = "Boss", Keys = 1, SkinChance = .06,
			Dogs = { { Id = "HW_BellkeeperWolf", Chance = .015, Rank = 5 }, { Id = "HW_HollowKing", Chance = .0005, Rank = 6 } } },
	},
	-- phase numbers (§11; BossFinale WP-C / FinaleFX WP-N). Discrete damages are x the difficulty V multiplier (1.5,
	-- BossMath.EventDamage, capped at 45% Event HP); DPS numbers are as written.
	FakeDeath = { Seconds = 6, Silence = 2.5 },
	Bell = { Height = 28, ShockwaveEvery = { 6, 8 }, ShockwaveDamage = 14, Chains = 4, PulsePeriod = 1.2, ChainHits = 6,
		ChainHitsPerFighter = 3, ShockwaveGap = 50,
		-- [WP-C] Bright = share of each pulse whose Perfect hits count; Descend = the bell's descent before the first chain;
		-- FirstToll = seconds after that to the first shockwave; ChainAlong = where on the chain (anchor -> bell) its
		-- hittable link hangs; ChainRange = Strike range; PingGrace = latency the bright-window check forgives (s);
		-- BreakPause = seconds between a broken chain and the next one; ChainScore = reward credit per counted hit
		-- (share of MaxArmor)
		Bright = .55, Descend = 2.5, FirstToll = 3, ShockwaveTelegraph = 1.5, DoubleChance = .45, ChainAlong = .25, ChainRange = 20,
		PingGrace = .25, EdgeGrace = .04, BreakPause = 1.5, ChainScore = .004 },
	Choir = { Candles = 6, Rounds = 3, WeakPoints = 3, WeakHP = 10, WeakHPPerFighter = 5, GhostBite = 8, GhostWaveEvery = 14,
		VolleyDamage = 14, VolleyEvery = { 5, 8 },
		-- [WP-C] WeakSeconds = how long the buried weak points stay open after a matched pattern; CandleCooldown = a candle
		-- ignores hits this long after it flipped; ghost dogs: GhostCount + GhostPerFighter x (fighters - 1) per wave (at
		-- most GhostMax alive), HP in tier-normalised hits, studs/s, bite (a telegraphed EventHP circle) within GhostLunge
		-- studs every GhostBiteCooldown s; StartDelay = seconds after the last chain breaks; scores = reward credit
		StartDelay = 1.5, WeakSeconds = 20, CandleCooldown = .45, CandleRange = 14, GhostCount = 2, GhostPerFighter = 1, GhostMax = 8, GhostHP = 3,
		GhostSpeed = 9, GhostLunge = 6, GhostBiteCooldown = 2.6, GhostBiteRadius = 3.5, FirstGhosts = 4, FirstVolley = 6, VolleyTelegraph = 1.4,
		VolleyWidth = 5, CandleScore = .002, WeakScore = .02, GhostScore = .006, HoundDelay = 2.5 },
	Hound = { BPM = 100, CounterWindow = 3, CounterCapPerPlayer = 6, BarkPoints = 24, BarkPointsPerFighter = 10,
		BurstDamage = 12, LineDamage = 16, RingDamage = 14, SafeDPS = 7,
		-- [WP-C] Rise = seconds from the hound's appearance to beat 0 (StartAt); LeadBeats = beats before the first pattern;
		-- GapBeats = beats between a counter window and the next pattern; offsets from the pit floor centre (studs):
		-- HoundOffset = the hound behind the south rim, JawOffset = where its jaw comes down when it barks; MoonDir = from
		-- the pit towards the Black Moon; CounterScore = reward credit per counted jaw hit
		Rise = 3, LeadBeats = 2, GapBeats = 1, SafeRadius = 8, SafeSpeed = 9, JawRange = 22, HoundOffset = { 0, 0, 50 }, JawOffset = { 0, 10, 18 },
		MoonDir = { 0, .35, 1 }, CounterScore = .006 },
	TimeLimit = 420, -- 7 min total after the false victory: "THE BELL SILENCES YOU"
	VictoryHold = 8, -- [WP-C] seconds the Victory / Fail state stays published (cinematic) before the fight is released
}

---------------------------------------------------------------------------------------------------------------------
-- COMBAT: Event HP, downed / revive, hazards (§10.1-§10.2; EventHP.luau, Hazards.luau, CombatHUD)
---------------------------------------------------------------------------------------------------------------------
C.Combat = {
	MaxHP = 100,
	ReenterKeep = 30, -- re-entering a combat zone within this many seconds keeps the HP
	IFrames = .6, -- seconds of invulnerability after a hit
	Downed = { Seconds = 20, WalkSpeed = 5 },
	Revive = { Hold = 2.2, Range = 9, HP = 40 },
	BleedOut = { HPFraction = .6, WeakenedSeconds = 25 },
	Weakened = { DamageDealt = .7, DamageTaken = 1.25 }, -- -30% dealt, +25% taken
	Regen = { PerSecond = 2, After = 8 },
	Tick = .1, -- 10 Hz combat ticks
	Hazards = {
		MinTelegraph = .9, -- every damaging attack is telegraphed at least this long
		HeavyTelegraph = 1.2, -- ... and this long when Damage >= HeavyDamage
		HeavyDamage = 25,
		Grace = .12, -- rewind tolerance: outside at ImpactAt or ImpactAt - Grace = spared
		SignalRadius = 220,
		YBand = 10, -- default vertical band of a shape (± studs) unless Height
		MaxHitFractionBoss = .45, -- no single hit above 45% MaxHP at difficulty V
		MaxHitFractionTrial = .40,
		MaxSafeZoneSpeed = 11, -- studs/s
		MinGap = 1, -- every Ring / Line pattern keeps at least one safe gap
	},
	PracticeZone = "Practice",
}

---------------------------------------------------------------------------------------------------------------------
-- THE GRAVEKEEPER damage scaling and attacks (§10.4-§10.5; BossMath WP-B / Boss WP-C)
---------------------------------------------------------------------------------------------------------------------
C.Boss = {
	ArmorK = 5,
	ArmorExp = .42, -- was .55 (compresses the pickaxe range harder: mechanics and Perfects dominate)
	SoftCap = { Window = 3, PerSecond = .0045, Beyond = .2, MechanicBypass = .6 }, -- x MaxArmorBase(d) per second
	-- [WP-C] tuned (was 1.0): the timing factor on the armor a body hit LANDS after the soft cap (the cap flattens
	-- the gear, the timing survives it): a Perfect x PerfectExtra, a Good hit x GoodMult. This puts a max-gear player
	-- spamming Good hits at ~23% of the same player playing Perfects + mechanics in the same fight (target <= 35%;
	-- tests/boss_finale.luau simulation, docs/halloween2/BOSS.md §2.1)
	PerfectExtra = 2, -- Perfect x2 on top of the pickaxe PerfectMult (already in raw)
	GoodMult = .75, -- [WP-C]
	ScaleFrom = 3, -- [WP-C] this curve, the soft cap and the timing factor apply from difficulty III (the endgame);
	-- I / II keep the Chapter I curve (Config.Boss ArmorK 5 / ArmorExp .55, no cap): the Chapter I gate (UNEASY) does not
	-- get harder for players who do not hit Perfects
	WeakMult = 3,
	Sync = { Window = .5, Bonus = .5, MinPlayers = 2 }, -- SYNC STRIKE
	WeakenedDealt = .7,
	SpamTarget = .35, -- design target: non-perfect spam <= 35% of the DPS of the same player playing the mechanics
	Damage = { Stomp = 12, Slam = 16, Sweep = 10, Erupt = 14, FakeMound = 8, Bite = 6, RockImpact = 10, RockExplode = 14 },
	DifficultyMult = { .7, .9, 1.1, 1.3, 1.5 }, -- I .. V
	TelegraphScale = { 1, 1, .95, .9, .85 }, -- never below C.Combat.Hazards minimums
	Endgame = {
		Difficulties = { [3] = true, [4] = true, [5] = true },
		GraveLines = { Count = { 3, 5 }, Damage = 18, Width = 6, Stagger = .45,
			Telegraph = 1.5, Knock = 30 }, -- [WP-C] base telegraph (x TelegraphScale), knock-back
		LanternWalk = { Radius = 9, Seconds = 8, DPS = 7, Grace = 1.2, Speed = 6 },
		BoneRain = { Count = { 12, 18 }, Radius = 4, Damage = 12, Stagger = .18,
			Telegraph = 1.4, Aimed = .4, Knock = 20 }, -- [WP-C] base telegraph, share of bones aimed at fighters, knock-back
		CursedRocks = { WavesPerPhase = { [3] = 3, [4] = 3 }, Unlimited = { [5] = true } },
		WeakPointPerfectOnly = { [5] = true },
		-- [WP-C] pattern rhythm: the first one this many seconds after the rise, then Every (s, / sqrt(difficulty speed))
		-- after the previous one ended; Curse = Chapter I curse added by a pattern hit
		First = 16, Every = { 18, 26 }, Curse = 4,
	},
	InPitOnly = true, -- plates / weak points only from inside the pit; only pit players count as fighters
	-- [WP-C] Gravekeeper server (Boss.luau, docs/halloween2/BOSS.md)
	PatternBand = 3.4, -- vertical half band of rock / bone circles centred at root height (terrace vs floor never mix)
	ReviveScore = .01, -- reward credit (share of MaxArmor) for reviving an ally in the pit
}

---------------------------------------------------------------------------------------------------------------------
-- CHAPTER II ONBOARDING (§9 cont.) — server step conditions in Chapter2.luau, client Chapter2Guide
---------------------------------------------------------------------------------------------------------------------
-- Step ids are saved (p.Underyard.Tutorial.Step): 1..#Steps, Done after the last. Event = the C2.TutorialEvent key that
-- completes the step; Auto = a profile condition checked in every Chapter II transaction.
C.Tutorial = {
	Steps = {
		{ Id = 1, Key = "Shards", Event = "Shards", Auto = "ShardsEarned", Goal = 10, Anchor = "TutorialEcho_1",
			Title = { "BELL SHARDS", "ОСКОЛКИ КОЛОКОЛА" }, Text = { "Hit the echoes", "Бей по эхо" } },
		{ Id = 2, Key = "Toll", Event = "Toll", Anchor = "TutorialBell",
			Title = { "FIRST TRIAL", "ПЕРВОЕ ИСПЫТАНИЕ" }, Text = { "Ring the hand-bell 5 times in rhythm", "Позвони в колокольчик 5 раз в ритм" } },
		{ Id = 3, Key = "Coffin", Event = "Coffin", Auto = "CoffinOpened", Anchor = "CoffinShrine", Grant = { Keys = 1, Shards = 150 },
			Title = { "THE BLACK COFFIN", "ЧЁРНЫЙ ГРОБ" }, Text = { "Open your first Black Coffin", "Открой свой первый Чёрный гроб" } },
		{ Id = 4, Key = "Practice", Event = "Practice", Anchor = "PracticeRing",
			Title = { "EVENT HP", "ЗДОРОВЬЕ СОБЫТИЯ" }, Text = { "Step into the practice ring", "Встань в тренировочный круг" } },
		{ Id = 5, Key = "Mourner", Event = "Mourner", Anchor = "Mourner",
			Title = { "COMBAT", "БОЙ" }, Text = { "Dodge the Mourner and strike its weak spot", "Уклонись от Плакальщика и ударь в слабое место" } },
		{ Id = 6, Key = "SealOffer", Event = "SealOffer", Auto = "SealOffered", Anchor = "SealAltar_1", RefundSeal = 1,
			Title = { "FIRST SEAL", "ПЕРВАЯ ПЕЧАТЬ" }, Text = { "Offer Bell Shards at Altar I", "Принеси осколки к алтарю I" } },
	},
	ForceCoffinFind = true, -- the tutorial's first coffin (step 3) rolls the showcase-find group
}

---------------------------------------------------------------------------------------------------------------------
-- EVENT JOURNAL (§9.6) — keys are saved; texts EN + RU
---------------------------------------------------------------------------------------------------------------------
C.Journal = {
	Max = 40,
	Order = { "chapter1", "reveal", "descend", "seal1", "seal2", "seal3", "seal4", "seal5", "seal6", "seal7", "finale", "assault" },
	Entries = {
		chapter1 = { Title = { "THE DEAD YARD", "МЁРТВЫЙ ДВОР" }, Text = {
			"The Gravekeeper fell, the cauldron boiled and the doors were knocked. The yard went quiet. Too quiet.",
			"Смотритель пал, котёл закипел, в двери постучали. Двор затих. Слишком затих." } },
		reveal = { Title = { "IS THAT ALL?", "И ЭТО ВСЁ?" }, Text = {
			"Three tolls under the church. The ground cracked, the doors opened by themselves, and something below breathed in.",
			"Три удара под церковью. Земля треснула, двери открылись сами, и что-то внизу вдохнуло." } },
		descend = { Title = { "BENEATH THE LAST BELL", "ПОД ПОСЛЕДНИМ КОЛОКОЛОМ" }, Text = {
			"Under the church lies the Underyard: a crooked town of the buried, sealed by seven bells that no longer ring.",
			"Под церковью лежит Поддворье: кривой город погребённых, запечатанный семью колоколами, что больше не звонят." } },
		seal1 = { Title = { "SEAL I · ECHO", "ПЕЧАТЬ I · ЭХО" }, Text = {
			"The echoes were the bell's first words. Caught, they ring again, and a little pup with a bell follows you home.",
			"Эхо были первыми словами колокола. Пойманные, они звенят снова, и щенок с колокольчиком идёт за тобой." } },
		seal2 = { Title = { "SEAL II · PROCESSION", "ПЕЧАТЬ II · ПРОЦЕССИЯ" }, Text = {
			"The funeral carnival never stopped turning. You ran its procession faster than the coffins could swing.",
			"Похоронный карнавал так и не остановился. Ты пробежал его процессию быстрее, чем качались гробы." } },
		seal3 = { Title = { "SEAL III · REFLECTION", "ПЕЧАТЬ III · ОТРАЖЕНИЕ" }, Text = {
			"The marsh keeps everything backwards. You turned the graves until the pond finally looked away.",
			"Топь хранит всё наоборот. Ты поворачивал могилы, пока пруд наконец не отвёл взгляд." } },
		seal4 = { Title = { "SEAL IV · HOLLOW", "ПЕЧАТЬ IV · ПУСТОТА" }, Text = {
			"The Undercrypt was mined hollow long ago. A corgi with a candle on its head showed you the way out.",
			"Подклепье давно выработано до пустоты. Корги со свечой на голове показал тебе выход." } },
		seal5 = { Title = { "SEAL V · CHOICE", "ПЕЧАТЬ V · ВЫБОР" }, Text = {
			"Every crooked door is a choice somebody regretted. You opened three and walked out of each one.",
			"Каждая кривая дверь — чей-то выбор, о котором пожалели. Ты открыл три и вышел из каждой." } },
		seal6 = { Title = { "SEAL VI · CHOIR", "ПЕЧАТЬ VI · ХОР" }, Text = {
			"Seven voices, seven notes. Together they sang the song the Last Bell forgot.",
			"Семь голосов, семь нот. Вместе они спели песню, которую забыл Последний колокол." } },
		seal7 = { Title = { "SEAL VII · LAST BELL", "ПЕЧАТЬ VII · ПОСЛЕДНИЙ КОЛОКОЛ" }, Text = {
			"The Bellkeeper let go of the rope. The Black Bell is silent, and a mourning shiba waits by its gallows.",
			"Звонарь отпустил верёвку. Чёрный колокол молчит, а у виселицы ждёт скорбная шиба." } },
		finale = { Title = { "THE LAST BARK", "ПОСЛЕДНИЙ ЛАЙ" }, Text = {
			"The Gravekeeper died twice. The hound behind the moon barked once more, then shattered into moths at dawn.",
			"Смотритель умер дважды. Гончая за луной залаяла ещё раз и на рассвете рассыпалась мотыльками." } },
		assault = { Title = { "BLACK BELL ASSAULT", "ШТУРМ ЧЁРНОГО КОЛОКОЛА" }, Text = {
			"The whole Underyard rang at once, and everyone answered. The Black Bell was dragged down by many hands.",
			"Всё Поддворье зазвенело разом, и все откликнулись. Чёрный колокол стащили вниз множеством рук." } },
	},
}

---------------------------------------------------------------------------------------------------------------------
-- TITLES (p.Cosmetics keys; TitleDefinitions legacy rows)
---------------------------------------------------------------------------------------------------------------------
C.Titles = {
	HollowCrown2026 = { "HOLLOW CROWN", "ПОЛАЯ КОРОНА" }, -- Dex II 8/8
	LastBark2026 = { "THE LAST BARK", "ПОСЛЕДНИЙ ЛАЙ" }, -- finale first clear
}

---------------------------------------------------------------------------------------------------------------------
-- PROFILE LIMITS (p.Underyard, §3.2: <= 6 KB JSON)
---------------------------------------------------------------------------------------------------------------------
C.Limits = { OwnedDecor = 40, OwnedFinds = 40, Journal = 40, Dex2Claims = 8, CoffinLast = 10, Contracts = 6, Stat = 1e12 }

---------------------------------------------------------------------------------------------------------------------
-- PRESENTATION / QUALITY (§17): Shared.Budget falls back to these keys
---------------------------------------------------------------------------------------------------------------------
C.Quality = {
	High = { UnderMotes = 60, Telegraph = 1, FinaleFX = 1, CalendarFX = 1, CoffinFX = 1, GhostLights = 12 },
	Medium = { UnderMotes = 30, Telegraph = 1, FinaleFX = .7, CalendarFX = .6, CoffinFX = .75, GhostLights = 8 },
	Low = { UnderMotes = 10, Telegraph = .6, FinaleFX = .4, CalendarFX = .3, CoffinFX = .5, GhostLights = 5 },
}
C.Palette = { -- Underyard accents (Color3.fromRGB components)
	Sickly = { 120, 255, 140 }, Violet = { 150, 80, 230 }, Candle = { 255, 170, 80 }, Moon = { 150, 200, 255 },
	Bone = { 230, 222, 200 }, Ink = { 16, 12, 26 },
}

---------------------------------------------------------------------------------------------------------------------
-- BLACK COFFIN TABLE (weights sum to C.Coffin.TotalWeight; the UI shows the exact %)
-- Row = {Key (unique, saved in Coffins.Last), Group, Kind (ctx.C2Reward kind), Id?, Amount | Min/Max | Coins, Weight,
--        Rank? (rarity 1..6 for the reveal), Tier? (finds)}
---------------------------------------------------------------------------------------------------------------------
do
	local rows = {
		{ Key = "Dust", Group = "Dust", Kind = "Dust", Min = 60, Max = 120, Weight = 24000, Rank = 1 },
		{ Key = "Shards", Group = "Shards", Kind = "Shards", Min = 40, Max = 90, Source = "Refund", Weight = 15000, Rank = 1 },
		{ Key = "Bones", Group = "Bones", Kind = "Bones", Min = 300, Max = 600, Weight = 8000, Rank = 1 },
		{ Key = "Coins", Group = "Coins", Kind = "Cash", Coins = { IncomeMinutes = 30, MinCash = 50000 }, Weight = 9000, Rank = 2 },
		{ Key = "Fragments", Group = "Fragments", Kind = "Fragments", Min = 1, Max = 3, Weight = 6000, Rank = 2 },
		{ Key = "Key", Group = "Key", Kind = "Key", Amount = 1, Source = "Coffin", Weight = 1500, Rank = 3 },
	}
	for _, id in ipairs(C.Finds.Order) do
		local def = C.Finds.Defs[id]
		table.insert(rows, { Key = id, Group = "Find", Kind = "Find", Id = id, Tier = def.Tier, Weight = C.Finds.TierWeight[def.Tier],
			Rank = C.Finds.TierRank[def.Tier] + 1 })
	end
	local decorRank = { Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
	for _, id in ipairs(C.Decor.Order) do
		table.insert(rows, { Key = id, Group = "Decor", Kind = "Decor", Id = id, Weight = C.Decor.CoffinWeight,
			Rank = decorRank[C.Decor.Defs[id].Rarity] or 3 })
	end
	local skinRank = { Epic = 3, Legendary = 4, Mythic = 5, Secret = 6 }
	for _, id in ipairs(C.Skins.Order) do
		local def = C.Skins.Defs[id]
		if not def.DexOnly then
			table.insert(rows, { Key = id, Group = "Skin", Kind = "Skin", Id = id, Weight = C.Skins.CoffinWeight, Rank = skinRank[def.Rarity] or 4 })
		end
	end
	for _, id in ipairs(C.Dogs.Order) do
		local def = C.Dogs.Defs[id]
		local group = def.Rank >= 6 and "Secret" or def.Rank >= 5 and "Mythic" or "Dog"
		table.insert(rows, { Key = id, Group = group, Kind = "Dog", Id = id, Rank = def.Rank, Weight = C.Dogs.CoffinWeight[id] })
	end
	-- filler up to TotalWeight goes to the Lucky Dust row (a miss still feeds the Dust Forge)
	local sum = 0
	for _, row in ipairs(rows) do
		sum += row.Weight
	end
	rows[1].Weight += C.Coffin.TotalWeight - sum
	C.Coffin.Filler = C.Coffin.TotalWeight - sum
	C.Coffin.Table = rows
	-- display groups of the drop-rate panel, in order
	C.Coffin.Groups = {
		{ Id = "Dust", Name = { "Lucky Dust", "Счастливая пыль" } },
		{ Id = "Shards", Name = { "Bell Shards (refund)", "Осколки колокола (возврат)" } },
		{ Id = "Bones", Name = { "Bones", "Кости" } },
		{ Id = "Coins", Name = { "Coins (30 min of income)", "Монеты (30 минут дохода)" } },
		{ Id = "Fragments", Name = { "Cosmetic Fragments", "Фрагменты косметики" } },
		{ Id = "Key", Name = { "Coffin Key (refund)", "Ключ от гроба (возврат)" } },
		{ Id = "Find", Name = { "Showcase finds", "Находки для витрины" } },
		{ Id = "Decor", Name = { "Plot cosmetics", "Украшения участка" } },
		{ Id = "Skin", Name = { "Pickaxe skins", "Скины кирки" } },
		{ Id = "Dog", Name = { "Event dogs", "Собаки события" } },
		{ Id = "Mythic", Name = { "Mythic dogs", "Мифические собаки" } },
		{ Id = "Secret", Name = { "SECRET · THE HOLLOW KING", "СЕКРЕТ · ПОЛЫЙ КОРОЛЬ" } },
	}
end

return C
