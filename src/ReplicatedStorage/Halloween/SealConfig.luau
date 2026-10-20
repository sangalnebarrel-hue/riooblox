-- BELL SEALS I-IV · activity tuning (ReplicatedStorage.Halloween.SealConfig, WP-I; docs/halloween2/DESIGN.md §8.4.1-4).
-- Extends Chapter2Config.Seals[i].Activity (WP-A) with every further number the activity servers (SealEcho, SealRun,
-- SealMirror, SealMine), their presenters (HalloweenClient.Trials.Echo / Run / Mirror / Mine) and tests/seals_1_4.luau
-- read. SealRules.Activity(i) merges both: a key that Chapter2Config.Seals[i].Activity defines always wins, so the
-- balance table of the chapter stays the single place for the headline numbers (lives, periods, damages, shards).
-- Shared by server and client; the server is the only side that decides anything.
local C = {}

C.Version = 1
C.Countdown = 3 -- seconds of 3-2-1 between a run's start and GO; the time limit starts at GO (Seals' EndsAt + this)

---------------------------------------------------------------------------------------------------------------------
-- I · ECHO DIG (Bell Square): haunted echoes at the 16 EchoPoint_n anchors, dug with one judged timing hit
---------------------------------------------------------------------------------------------------------------------
C[1] = {
	Range = 13, -- strike prompt distance (studs from the hit box centre; the server allows + Strike.RangeSlack)
	HitSize = { 6, 4.5, 6 }, -- strike hit box (X, Y, Z)
	Lift = 2.2, -- hit box centre above the anchor's ground point
	RespawnDelay = .9, -- seconds after a dig before a new echo rises somewhere else
	SpawnStagger = .45, -- the first echoes of a run rise one after another
	PartyAlive = .5, -- extra echoes alive per extra party member (floored)
	MaxAliveCap = 6,
	MinJumpDistance = 16, -- a jump lands at least this far away (studs, flat)
	LabelEn = "HAUNTED ECHO",
	LabelRu = "ПРИЗРАЧНОЕ ЭХО",
	GoldEndsRun = false, -- the 90 s always run out: more digs, more shards, a better Perfect share
}

---------------------------------------------------------------------------------------------------------------------
-- II · FUNERAL RUN (Funeral Carnival): ten checkpoint rings in order, pendulums, the carousel, the coffin conveyor
---------------------------------------------------------------------------------------------------------------------
C[2] = {
	CheckpointRadius = 7, -- UnderyardLayout.Carnival.CheckpointRadius (the arch's inner clear width is 12.6)
	CheckpointSlack = 2.5, -- extra studs a lagged server position may miss the ring by
	CheckpointBand = 12, -- vertical band around the checkpoint anchor (the carousel deck, the conveyor belt)
	JumpSlack = 8, -- studs on top of MaxSpeed x SpeedSlack x dt before a sample counts as a teleport jump
	LegTimeSlack = .25, -- seconds a leg (and the legs since GO / a rewind in total) may beat distance / (MaxSpeed x
	--                     SpeedSlack): the error of crossing times interpolated between two 4 Hz samples
	KnockSpeed = 75, -- extra studs / s allowed while a pendulum knock-back is still carrying the runner
	KnockGrace = 1.2, -- seconds after a pendulum impact the knock allowance holds (and the time it may have saved)
	MaxViolations = 4, -- leg-time / jump violations before the runner is out of the run ("Invalid")
	-- pendulums (§24.2: angle = Amp * sin(2 pi * (serverTime mod Period) / Period + Phase), the hinge model's attributes
	-- UySwingAmp / UySwingPeriod / UySwingPhase win; these are the fallbacks when RunPendulum_i is not in the place)
	PendulumAmp = 1.0, -- radians
	PendulumPivotY = 17, -- pivot height above the lane
	PendulumArm = 12.2, -- pivot -> coffin centre
	PendulumPhaseStep = 2.0943951023931953, -- 2 pi / 3: the three never swing in step
	PendulumStrip = { 14, 8, 4.6 }, -- the hazard box at each pass: across the lane x height x along the lane
	PendulumTelegraph = 1.0, -- seconds of warning before each pass (>= Combat.Hazards.MinTelegraph)
	PendulumKnockUp = 30, -- upward part of the knock-back (Activity.PendulumKnock is the horizontal power)
	PendulumLead = .45, -- a pass is scheduled this long before its telegraph has to appear (network margin)
	LaneWidth = 12,
	FinishHold = 2.5, -- a finished runner's FINISHED banner time
}

---------------------------------------------------------------------------------------------------------------------
-- III · MIRROR GRAVES (Mourning Marsh): six turning headstones, the pond shows the target mirrored (grave i <-> 7 - i)
---------------------------------------------------------------------------------------------------------------------
C[3] = {
	StartAnchor = "PondConsult", -- the run begins (and the pond is consulted) at the scrying basin on the north shore
	TurnRange = 11, -- server check: studs from the MirrorGrave_i anchor (+ Proximity.Slack)
	ConsultRange = 12, -- server check: studs from PondConsult (+ Proximity.Slack)
	-- the prompts themselves (grave 1's headstone and the scrying basin stand ~2-3.5 studs apart on the north terrace):
	-- TURN sits on the grave's outer side (where its boardwalk spur arrives), CONSULT on the basin's pond side, with
	-- tight activation distances and different keys, so the two never compete (checked against the built marsh)
	TurnOffset = 2.6, -- studs from the stone centre, away from the pond
	TurnPromptRange = 6,
	ConsultOffset = { 0, .2, 3.6 }, -- from the PondConsult anchor (the basin stands 1.5 south of it; the pond is +Z)
	ConsultPromptRange = 6,
	TurnKeys = { "E", "ButtonX" }, -- keyboard, gamepad
	ConsultKeys = { "F", "ButtonY" },
	TurnCooldown = .35, -- one quarter turn per grave per this many seconds (the stone's turn animation)
	ConsultCooldown = 1.5,
	MinWrongShare = .75, -- at least this share of a round's active graves start turned away from their target
	RoundPause = 1.4, -- seconds the stones shuffle into the next round (turns are refused meanwhile)
	PondRadius = 8.6, -- where the reflected runes float on the mirror pond (studs from its centre)
}

---------------------------------------------------------------------------------------------------------------------
-- IV · HOLLOW MINE (Undercrypt): hollow ore nodes on the sunken mine floor under falling rocks, gas and collapses
---------------------------------------------------------------------------------------------------------------------
C[4] = {
	Unit = 10, -- HP per tier-normalised power ("Power" damage: a plain Wooden hit = 1 power = 10 HP)
	PartyHP = .5, -- node HP x (1 + PartyHP x (party - 1))
	HitSize = { 6.4, 5, 6.4 },
	Lift = 2.5,
	Range = 13,
	Spawn = "MineSpawn", -- edge respawn after a bleed-out (anchor)
	HazardDelay = 5, -- seconds after GO before the first hazard
	FloorBand = 7, -- a player is "on the mine floor" up to this many studs above Undercrypt.FloorY
	FloorMargin = 4, -- hazards stay this far inside the floor box
	RockSpread = 3.5, -- a rock lands within this many studs of the player it aims at (standing still gets hit)
	RockPerPlayers = 2, -- one rock per this many players on the floor each wave
	GasNear = 9, -- a gas vent cracks open within this many studs of a player
	GasClear = 4.5, -- ... and at least this far from a living ore node's centre
	LabelEn = "HOLLOW ORE",
	LabelRu = "ПОЛАЯ РУДА",
	GoldEndsRun = true, -- the Gold total collapses the mine early: a win, no need to wait for the clock
}

return C
