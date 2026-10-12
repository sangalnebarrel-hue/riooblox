-- Kennel dig chains per dog (read by DogAnimationPlayer.ResolveName / .Chain on every peer).
--
-- A kennel dog that is producing digs continuously:
--   Idle -> Start -> Loop (looped for as long as it works) -> End -> Idle
-- and an optional accent lands exactly on every find (NextWorkAt):
--   Find    a reaction clip (or a list of clips played in order) that ENDS at NextWorkAt,
--           then the dog returns to its Loop. FindEvery = n plays it on every n-th find only.
--   Action  the work motion of a dog that has no loopable dig: it ends at NextWorkAt like a
--           Find; with Repeat = true it is played back to back for the whole cycle (one copy
--           always ends on the find) and Loop only fills the short gap that is left.
--
-- Precedence for every role: this table > the clip folder's <Role>Clip attribute (IdleClip,
-- WalkClip, WorkClip) > the candidate names in DogAnimationPlayer. A value of false means
-- "none" (for example a dog whose authored DigStart does not lead into its loop).
-- The build cannot change folder attributes, so every remapping lives here.
--
-- Rules (asserted by tests/animations.luau against the real clips):
--   * every named clip exists in ReplicatedStorage.DogAnimationClips.<DogId>;
--   * accents (Find/Action, the whole list) are played at x1.0 and last at most MinCycle seconds
--     (Config.Work.MinCooldown + Config.Work.Duration), so they always fit between two finds.
-- Chains were chosen from measured pose gaps (core bones, end of one clip -> start of the next).
local P = {}

P.Version = 1
P.MinCycle = 10

-- Crossfade seconds for each kind of change (a dog's own Fade table overrides single keys).
P.Fades = {
	Start = 0.25, -- rest pose -> DigStart
	Loop = 0.15, -- DigStart -> loop (phase matched)
	Direct = 0.35, -- rest pose -> loop when there is no DigStart (phase matched)
	Accent = 0.2, -- loop -> Find/Action
	Return = 0.2, -- Find/Action -> loop (phase matched)
	End = 0.2, -- loop -> DigEnd (taken at the loop boundary)
	Idle = 0.3, -- DigEnd -> rest pose (phase matched)
	Stop = 0.35, -- loop -> rest pose when there is no DigEnd (phase matched)
}

P.Dogs = {
	-- No dig clip is authored: the coffee chain (sip in, drink, sip out) is the dog's work and
	-- joins seamlessly (Idle->DrinkStart 3 deg, DrinkStart->Drinking 0, Drinking->DrinkEnd 0).
	CoffeeDog = { Start = "DrinkStart", Loop = "Drinking", End = "DrinkEnd", Find = false },
	-- No dig loop: Cook is its authored work loop and DigStart leads into it (5 deg). Its
	-- DigEnd starts from a dig pose that Cook never reaches, so it eases straight back to Idle.
	Ramendog = { Start = "DigStart", Loop = "Cook", End = false, Fade = { Stop = 0.5 } },
	-- No dig clip: it sniffs out the ground and rallies the team on every find (5 s, starts
	-- and ends on the Idle pose; the old WorkClip played it squeezed x1.4 and cut).
	CaptainCorgi = { Start = false, Loop = "Sniff", End = false, Action = "Rally" },
	-- No dig clip: the authored Charge1->Charge2->Charge3->Impact chain (5.2 s, every hop 0 deg,
	-- Idle <-> chain 0 deg) pounds the ground back to back, one Impact landing on each find.
	MechaBark = { Start = false, Loop = "Idle", End = false, Action = { "Charge1", "Charge2", "Charge3", "Impact" }, Repeat = true },
	-- DIG_DIVE is a closed 3.3 s dig loop (Idle <-> DIG_DIVE 2 deg). The 7 s BAT_DIG cinematic
	-- (the old WorkClip, squeezed x1.9) is now an accent on every third find at x1.0.
	Barkula = { Start = false, Loop = "DIG_DIVE", End = false, Find = "BAT_DIG", FindEvery = 3 },
	-- Fetch_Deep is its dig (closed on the body bones, Idle <-> 0 deg); Dig_Start ends in a pose
	-- nothing follows. Depth_Bypass (8 s, the old WorkClip at x2.15) lands every fourth find.
	["404Dog"] = { Start = false, Loop = "Fetch_Deep", End = false, Find = "Depth_Bypass", FindEvery = 4 },
	-- Dig_Sequence (draw, three strikes, sheathe) is closed: it loops at x1.0 instead of x1.71.
	Samuriba = { Start = false, Loop = "Dig_Sequence", End = false },
	-- Cube_Impact_Sequence starts and ends on the Idle pose and leads into Dig_End (all 0 deg).
	Cubedog = { Start = false, Loop = "Cube_Impact_Sequence", End = "Dig_End" },
	-- Ground_Opens stays THE DOG's arrival cinematic. At work it stands alert and digs out a
	-- find again and again (Stand_Idle -> Find 0 deg, Find -> Stand_Idle 2 deg).
	TheDog = { Start = false, Loop = "Stand_Idle", End = false, Find = false, Action = "Find", Repeat = true },
	-- There is no Idle clip: the candidates picked the synthetic Sleep (eyes shut). Idle_Night
	-- is the authored rest pose of its dig chain (Dig_End -> Idle_Night 1 deg).
	Vampug = { Idle = "Idle_Night" },
	-- DigDeep has a 52 deg seam and joins nothing; the authored chain is
	-- DigStart -> DepthBonus (loop) -> FoldBack -> Idle (9, 5, 0 deg) with Find on every find.
	LongDog = { Start = "DigStart", Loop = "DepthBonus", End = "FoldBack", Find = "Find" },
	-- Authored one-shot digs with their own lead-in/out (every hop 0 deg):
	RocketDachshund = { Start = "Dig_Start", Loop = "Rocket_Dig", End = "Return" },
	SharkdogPrime = { Start = { "Dig_Start", "Dig_Dive" }, Loop = "Dig_Circle", End = "Dig_End" },
	ThunderHusky = { Start = { "Dig_Start", "Dig_Strike" }, Loop = "Chain_Dig", End = "Dig_End" },
	-- Dig_Impact has a 62 deg seam: the whole authored dig (Dig_Start -> Dig_Impact -> Dig_End,
	-- 5 s, all 0 deg, starts and ends on Idle) repeats instead, one impact ending on each find.
	Dogzilla = { Start = false, Loop = "Idle", End = false, Action = { "Dig_Start", "Dig_Impact", "Dig_End" }, Repeat = true },
	-- Authored find reactions as the accent on every find. (BooHound TreasureFound, Knightweiler
	-- FindsLoot and PoliceShiba Success start and end on the Idle pose, 56-99 deg away from
	-- their dig loop, so they are not used.)
	Crabull = { Find = "Finds_Loot" },
	DragonShiba = { Find = "TreasureFound" },
	Barkbeard = { Find = "ChestFind" },
	CactusCorgi = { Find = "DryFind" },
	Necrohound = { Find = "BoneFound" },
	Sushiba = { Find = "FoodFound" },
	Sharkshund = { Find = "Finds_Aquatic_Loot" },
	Pharaohound = { Find = "ARTIFACT_FOUND" },
	Astrodoggo = { Find = "SpaceLoot" },
	CraneCorgi = { Find = "LiftSuccess" },
	CaptainBark = { Find = "MapFound" },
	TaxiDachshund = { Find = "DeliveryComplete" },
	Mushpup = { Find = "MutationResult" },
	ProfessorBark = { Find = "Identified", FindEvery = 2 },
}

return P
