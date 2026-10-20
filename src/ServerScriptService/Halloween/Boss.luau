-- THE GRAVEKEEPER (ServerScriptService.Halloween.Boss) — the Dead Yard boss of NIGHT OF THE BURIED MOON.
-- Not a sword-clicking boss: every bit of damage comes from DOGROTS' own pickaxe timing hits (SSS.Halloween.Strike):
-- players break its stone ARMOR PLATES, dig the real GRAVE MOUND after it burrows, smash the SKELETON DOGS that shield it,
-- break CURSED ROCKS that fall from the sky (each hurls a shard back into the boss) and dig its WEAK POINTS while ENRAGED,
-- all while dodging telegraphed slams / sweeps / stomps.
--
-- CHAPTER II (WP-C, docs/halloween2/DESIGN.md §10.4-§10.5, §11, §23; docs/halloween2/BOSS.md):
-- * Fighters are the alive players INSIDE the pit (Layout.InPit): only they count for the armor scaling and only they can
--   hit plates / weak points / mounds / rocks (rim camping is gone). They are in the EventHP combat zone "Boss" (HP bar,
--   downed / revive; the bleed-out spawn is on the north rim) while they are down there; a downed player stays in the
--   zone until revived or bled out.
-- * Its attacks HURT (Event HP): every telegraphed attack is an EventHP hazard (Stomp / Slam / Sweep, the eruption of an
--   unfound mound, a fake mound's skeleton hands, falling rocks, rock explosions) and BossEvent Attack / Rocks / FakeMound
--   carry the HazardId(s) (CombatFX draws them, BossFX only animates); the knock-back + Curse land with the hit. Skeleton
--   bites are melee (knock() deals BossMath.AttackDamage). Targeting skips players EventHP.CanTarget refuses (downed).
-- * Damage scaling (BossMath, Chapter2Config.Boss): armor per hit = K x raw ^ .42 (x3 weak points, the yard-dog bonus,
--   SYNC STRIKE +50% for two players' Perfects within .5 s, WEAKENED -30%, H15 +25% on weak points), then a per-player
--   soft cap (full value up to MaxArmorBase(d) x .0045 / s over 3 s, 20% beyond; mechanic damage — weak points, the real
--   mound 8%, rocks 3% — bypasses 60% of it) and the timing factor on what lands (a Perfect body hit x PerfectExtra 2,
--   a Good one x GoodMult .75: a max-gear Good-hit spammer deals ~23% of a Perfect + mechanics player, target <= 35%).
--   Weak points take Perfect hits only on difficulty V. Difficulties below Chapter2Config.Boss.ScaleFrom (III) keep the
--   Chapter I curve without a cap.
-- * Endgame patterns on III / IV / V (Chapter2Config.Boss.Endgame, RS.Halloween.BossPatterns): GRAVE LINES, LANTERN
--   WALK, BONE RAIN (BossEvent Pattern {Name, StartAt, Duration, HazardIds}); cursed rock waves are capped per phase on
--   III / IV and unlimited on V; every pattern passes Hazards.Check + Hazards.CheckPattern (a safe spot always exists).
-- * Team wipe (EventHP.OnWipe "Boss"): BossEvent Wiped {} then finish "Escaped" / Reason "Wiped".
-- * Rewards: contributors who left before the end are parked in Boss.Pending and paid when they rejoin. Chapter II
--   players with a full reward also get modules.Chapter2.BossReward(player, d, {Finale}) (Bell Shards, first-clear keys,
--   finale rows; own receipt "hw-boss2:<fight>:<userId>") and every armor credit feeds C2.Progress(player, "BossDamage").
-- * Difficulty V with Shared.BossFinaleEnabled(): armor 0 is a FALSE VICTORY -> modules.BossFinale.Begin(F) runs the
--   three post-death phases on this same fight (Phase stays 5, Mode "Finale"); it calls finish(F, "Defeated") exactly
--   once at the end (victory: finale rewards; fail: the normal difficulty V reward).
--
-- Summon: the Grave Bell prompt (Layout.Bell) opens the Halloween window on the BOSS tab; the tab sends Request
-- `BossSummon {Difficulty}` (near the bell, difficulty unlocked: h.Boss.Unlocked >= d, cooldown over, one fight per server).
-- The Server Exorcism milestone 5000 summons it too (Exorcism.SetBossHook; Exorcism.Reset() when that fight is over).
-- API: Boss.Summon(difficulty, reason, player?) -> ok, err ; Boss.Abort(reason) ; Boss.Fight (live table, read only) ;
--      Boss.ArmorDamage(raw, weak, difficulty?) ; Boss.DogBonus(team) ; Boss.RockSpot(x, z) ; Boss.Status(player?) ;
--      Boss.Pending / Boss.ResumePending(player) (rewards paid on rejoin) ; Boss.Api (used by BossFinale) ;
--      Boss.Init(core, modules) + Boss.Step(dt) + Boss.Now / Rand / GetPlayers / Wait / Later (tests) ; Boss.Start.
--
-- Phases (armor fraction, Config.Boss.Phases): 1 AWAKENING (plates + attacks), 2 BURROW (6 mounds, one real: dig it ->
-- huge damage + eruption; fakes -> skeleton hands + curse; timeout -> eruption shockwave; then a surface window, repeat),
-- 3 SKELETON PACK (shield until most of the pack is smashed), 4 CURSED ROCKS (waves; break -> shard -> armor damage,
-- ignored -> explosion), 5 ENRAGED (faster attacks, weak points open briefly for x3 damage). Damage never skips a phase:
-- it stops at the next threshold and the boss transforms. Armor = BaseArmor x difficulty x (1 + PerFighterArmor x
-- (fighters - 1)); the fighter count is live (the armor FRACTION is kept when it changes).
--
-- Published on RS.Halloween.State.Boss (attributes): State ("Idle"|"Rising"|"Fight"|"Defeated"|"Escaped"), Difficulty,
--   Numeral, DifficultyName, Phase (0 idle, 1..5), PhaseName, Mode (animation state: Rise|Idle|Walk|Windup|Roar|Burrow|
--   Underground|Erupt|Stagger|Enrage|Death|Escape|Finale), ModeAt, ModeUntil, Attack, Armor, MaxArmor, StartedAt, EndsAt,
--   NextSummonAt, Fighters, Revision, Shield, ShieldLeft, ShieldNeed, WeakOpenUntil, WeakSlots ("Heart,Throat"), Plates
--   ("110111" in Models.Boss.Slots.PlateOrder, 0 = shattered / regrowing), PlateWear ("003900": cracks 0..9 per plate),
--   RockWave, RockWaves (cap, 0 = unlimited), BurrowUntil, Reason, FightId, Enraged, BossCF (CFrame, 4 Hz), Pattern
--   (endgame pattern running, "" none), PatternUntil, PerfectOnly (weak points take Perfect hits only).
-- The boss position: Workspace.HalloweenLive.Boss.BossRig.BossRoot (anchored, invisible, Persistent model; moved <= 10 Hz).
-- Signal "BossEvent" {Kind = Rise | Phase | Attack | Knock | Burrow | MoundHit | FakeMound | Erupt | Skeletons | Shield |
--   SkeletonDown | Bite | Rocks | RockLand | RockShard | RockExplode | Enrage | WeakPoint | PlateBreak | PlateRegrow | Hit |
--   Pattern | Wiped | Defeated | Escaped | Reward | RewardChapter2 | Finale (BossFinale), ...} (fields at each call below).
-- Strike kinds registered here (SSS.Halloween.Strike, WP7): BossPlate (BREAK; HP = plate integrity in ARMOR units, each hit
-- removes exactly the armor that landed), BossWeak (DIG; never breaks, x3 armor damage, + the digger's yard-dog bonus:
-- their best assigned dog digs with them, StrikeBegin Extra {Companion, Event, DogBonus, PerfectOnly}), BossMound /
-- BossSkeleton / CursedRock (DIG / STRIKE / BREAK; Damage = "Power": HP counts tier-normalized hits). Target parts carry
-- attributes Slot / Index / Key.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local BossMath = require(Halloween:WaitForChild("BossMath"))
local Hazards = require(Halloween:WaitForChild("Hazards"))
local Patterns = require(Halloween:WaitForChild("BossPatterns"))
local C2Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Config = Shared.Config
local Layout = Shared.Layout
local Models = Halloween:FindFirstChild("Models")
local BossModels = Models and Models:FindFirstChild("Boss") and require(Models.Boss) or nil

local B = Config.Boss -- Chapter I numbers (armor, phases, rewards)
local CB = C2Cfg.Boss -- Chapter II numbers (damage scaling, Event HP attacks, endgame patterns)
local Boss = { Fight = nil, NextSummonAt = 0, Started = false, StateRoot = nil :: Instance? }
Boss.ZONE = "Boss" -- EventHP combat zone id

-- tunables that are not in the shared Config (Config.Boss.X overrides any of them)
local T = {
	PlateShare = .05,        -- armor damage a stone plate absorbs before it shatters (share of MaxArmor)
	PlateBreakBonus = .025,  -- extra armor damage (share of MaxArmor) when a plate shatters
	PlateRegrow = 9,         -- seconds before a shattered plate grows back
	MoveRadius = 8,          -- the boss wanders this far from the pit centre
	WalkSpeed = 4.5,         -- studs per second (x difficulty speed)
	TurnSpeed = 1.6,         -- radians per second
	RiseSeconds = 6.5,
	SurfaceSeconds = 18,     -- burrow phase: time on the surface between two dives
	EruptRadius = 10, EruptKnock = 55, EruptCurse = 8,
	FakeRadius = 8, FakeKnock = 30,
	PackRepeat = 32,         -- seconds after a pack is beaten before the next one (still in phase 3)
	ShieldShare = .75,       -- share of the pack that must be smashed to drop the shield
	BiteRange = 3.4, BiteCurse = 5, BiteKnock = 18, BiteCooldown = 1.8,
	WaveGap = 13,            -- seconds between rock waves
	RockImpactRadius = 4.5, RockImpactCurse = 6, RockKnock = 40, RockExplodeRadius = 7, RockExplodeCurse = 10,
	TerraceRockRadius = 3,   -- rocks landing on the 6-wide terrace ring: telegraph + impact radius that fits the ring
	RockExplodeWarn = 1.2,   -- seconds of telegraph before an unbroken rock explodes (EventHP hazard)
	RewardRetry = { 2, 5, 12, 30, 60 }, -- seconds between reward attempts (a failed BossReward transaction is retried)
	WeakCycle = 12,          -- enraged: weak points open every N seconds
	Stomp = { Radius = 9.5, Telegraph = 1.2, Knock = 50, Curse = 6 },
	SweepRadius = 20, SweepAngle = 120,
	EmptyGrace = 40, ExorcismGrace = 75, -- (40: a solo fighter who dies can respawn and walk back from the spawn)
	EndHold = 12,            -- seconds the Defeated / Escaped state stays published (death animation, banners)
	ArmorK = 5, ArmorExp = .55, -- Chapter I curve (difficulties below Chapter2Config.Boss.ScaleFrom)
	ArenaRadius = 42,        -- (Chapter I fighter rule, only when Chapter2Config.Boss.InPitOnly == false)
	SkeletonScore = .012,    -- reward-share credit (share of MaxArmor) for smashing a skeleton dog / digging a fake mound
	MoundScore = .006,
}
for k, v in pairs(T) do
	if B[k] ~= nil then
		T[k] = B[k]
	end
end
Boss.Tunables = T

local core, modules = nil, nil
local stateFolder = nil
local rigRoot = nil
local rng = nil

---------------------------------------------------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------------------------------------------------
function Boss.Now(): number
	return workspace:GetServerTimeNow()
end

function Boss.Rand(a: number?, b: number?): number
	if not rng then
		local ok, r = pcall(function()
			return Random.new()
		end)
		rng = ok and r or false
	end
	local x
	if rng then
		x = rng:NextNumber()
	else
		x = math.random()
	end
	if a and b then
		return a + (b - a) * x
	end
	return x
end

function Boss.GetPlayers(): { Player }
	return Players:GetPlayers()
end

local function now(): number
	return Boss.Now()
end

local function rand01(): number
	return Boss.Rand()
end

local function diffDef(d: number)
	return B.Difficulties[math.clamp(math.floor(d or 1), 1, #B.Difficulties)]
end

local function phaseDef(p: number)
	return B.Phases[p]
end

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootPos(player: Player): Vector3?
	local r = core and core.Root(player)
	return r and r.Position or nil
end

local function floorY(): number
	return Layout.Pit.FloorY
end

-- real walkable height of the pit at (x, z) (arena floor -8, ramps, terrace ring -4, rim 0.2): Models.Boss.Surface
local function surfaceAt(x: number, z: number): (number, string)
	if BossModels and BossModels.Surface then
		return BossModels.Surface(Layout, x, z)
	end
	return floorY(), "Floor"
end
Boss.SurfaceAt = surfaceAt

local function signal(target: any, data: { [string]: any })
	if core then
		core.Signal(target, "BossEvent", data)
	end
end

local function idOf(target: any): any
	if type(target) ~= "table" then
		return target
	end
	return target.Id or target.TargetId
end

local function playerOf(uid: number): Player?
	for _, pl in ipairs(Boss.GetPlayers()) do
		if pl.UserId == uid and pl.Parent then
			return pl
		end
	end
	return nil
end

-- the Chapter II damage scaling (curve .42, soft cap, Perfect bonus) runs from this difficulty on
local function scaled(F): boolean
	return (F and F.Difficulty or 1) >= (tonumber(CB.ScaleFrom) or 1)
end

local function endgame(F): boolean
	local e = CB.Endgame
	return type(e) == "table" and type(e.Difficulties) == "table" and e.Difficulties[F.Difficulty] == true
end

local function perfectOnly(F): boolean
	local e = CB.Endgame
	return type(e) == "table" and type(e.WeakPointPerfectOnly) == "table" and e.WeakPointPerfectOnly[F.Difficulty] == true
end

-- the boss's own damage scale: raw pickaxe damage (1 .. ~1500) compressed so every tier matters but nobody one-shots
-- (difficulty: the Chapter II curve from CB.ScaleFrom on, else the Chapter I curve K x raw ^ .55)
function Boss.ArmorDamage(raw: number, weak: boolean?, difficulty: number?): number
	raw = math.max(0, tonumber(raw) or 0)
	if raw <= 0 then
		return 0
	end
	local opts: { [string]: any } = { Weak = weak == true, WeakMult = (B.WeakPoints and B.WeakPoints.Mult) or 3 }
	if (difficulty or 1) < (tonumber(CB.ScaleFrom) or 1) then
		opts.K, opts.Exp = T.ArmorK, T.ArmorExp
	end
	return (BossMath.ArmorDamage(raw, opts))
end

-- typical normal-hit damage of a player's REAL pickaxe (target HP is expressed in "average hits")
local miningM, miningR = nil, nil
local function damageOf(player: Player): number
	local Strike = modules and modules.Strike
	if Strike and type(Strike.HitDamage) == "function" then
		local ok, d = pcall(Strike.HitDamage, player)
		if ok and type(d) == "number" and d > 0 then
			return d
		end
	end
	local ok, d = pcall(function()
		if not miningM then
			miningM = require(RS:WaitForChild("DogEconomy"):WaitForChild("Config")).Mining
			miningR = require(RS:WaitForChild("Mining"):WaitForChild("MiningRules"))
		end
		local pick = miningM.Pickaxes[player:GetAttribute("MiningPickaxe") or 0]
		if not pick then
			return 1
		end
		return miningR.HitDamage(miningM, { Strength = player:GetAttribute("MiningStrength") or 0 }, pick, 1, 0, false)
	end)
	return (ok and type(d) == "number" and d > 0) and d or 1
end
Boss.DamageOf = damageOf

---------------------------------------------------------------------------------------------------------------------
-- published state
---------------------------------------------------------------------------------------------------------------------
local function setAttr(name: string, value: any)
	if stateFolder and stateFolder:GetAttribute(name) ~= value then
		stateFolder:SetAttribute(name, value)
	end
end

local function bump()
	if stateFolder then
		stateFolder:SetAttribute("Revision", (stateFolder:GetAttribute("Revision") or 0) + 1)
	end
end

local function plateMask(F): string
	local out = {}
	local order = BossModels and BossModels.Slots.PlateOrder or {}
	for _, slot in ipairs(order) do
		-- "0" = shattered (regrowing); plates withdrawn while it burrows / transforms still count as worn ("1")
		local pl = F.Plates[slot]
		local shattered = pl ~= nil and pl.Target == nil and pl.RegrowAt ~= nil
		table.insert(out, shattered and "0" or "1")
	end
	return table.concat(out)
end

local function plateWear(F): string
	local out = {}
	local order = BossModels and BossModels.Slots.PlateOrder or {}
	for _, slot in ipairs(order) do
		local pl = F.Plates[slot]
		local w = 0
		local tg = pl and pl.Target
		local hp, max = tg and tonumber(tg.HP), tg and tonumber(tg.MaxHP)
		if hp and max and max > 0 then
			w = math.clamp(math.floor((1 - hp / max) * 9 + .5), 0, 9)
		end
		table.insert(out, tostring(w))
	end
	return table.concat(out)
end

local function weakSlots(F): string
	local out = {}
	for slot in pairs(F.Weak) do
		table.insert(out, slot)
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function rockCap(F): number
	local rocks = type(CB.Endgame) == "table" and CB.Endgame.CursedRocks or nil
	if type(rocks) ~= "table" then
		return 0
	end
	if type(rocks.Unlimited) == "table" and rocks.Unlimited[F.Difficulty] then
		return 0
	end
	return math.max(0, math.floor(tonumber(type(rocks.WavesPerPhase) == "table" and rocks.WavesPerPhase[F.Difficulty]) or 0))
end

local function publish(F)
	if not stateFolder then
		return
	end
	if not F then
		setAttr("State", "Idle")
		setAttr("Phase", 0)
		setAttr("PhaseName", "")
		setAttr("Mode", "")
		setAttr("Armor", 0)
		setAttr("MaxArmor", 0)
		setAttr("Fighters", 0)
		setAttr("Shield", false)
		setAttr("ShieldLeft", 0)
		setAttr("ShieldNeed", 0)
		setAttr("WeakOpenUntil", 0)
		setAttr("WeakSlots", "")
		setAttr("Plates", "")
		setAttr("PlateWear", "")
		setAttr("RockWave", 0)
		setAttr("RockWaves", 0)
		setAttr("BurrowUntil", 0)
		setAttr("Enraged", false)
		setAttr("Attack", "")
		setAttr("Pattern", "")
		setAttr("PatternUntil", 0)
		setAttr("PerfectOnly", false)
		setAttr("NextSummonAt", Boss.NextSummonAt)
		return
	end
	local d = F.Def
	setAttr("State", F.State)
	setAttr("FightId", F.Id)
	setAttr("Difficulty", F.Difficulty)
	setAttr("Numeral", d.Numeral)
	setAttr("DifficultyName", d.Name)
	setAttr("Phase", F.Phase)
	setAttr("PhaseName", F.PhaseName or (phaseDef(F.Phase) or {}).Name or "")
	setAttr("Mode", F.Mode)
	setAttr("ModeAt", F.ModeAt)
	setAttr("ModeUntil", F.ModeUntil)
	setAttr("Attack", F.Attack and F.Attack.Kind or "")
	setAttr("Armor", math.max(0, math.ceil(F.Armor)))
	setAttr("MaxArmor", math.ceil(F.MaxArmor))
	setAttr("StartedAt", F.StartedAt)
	setAttr("EndsAt", F.EndsAt)
	setAttr("NextSummonAt", Boss.NextSummonAt)
	setAttr("Fighters", F.Fighters)
	setAttr("Shield", F.Shield)
	setAttr("ShieldLeft", F.Shield and math.max(0, F.ShieldNeed - F.ShieldKills) or 0)
	setAttr("ShieldNeed", F.Shield and F.ShieldNeed or 0)
	setAttr("WeakOpenUntil", F.WeakUntil)
	setAttr("WeakSlots", weakSlots(F))
	setAttr("Plates", plateMask(F))
	setAttr("PlateWear", plateWear(F))
	setAttr("RockWave", F.RockWave)
	setAttr("RockWaves", rockCap(F))
	setAttr("BurrowUntil", F.BurrowUntil)
	setAttr("Reason", F.Reason)
	setAttr("Enraged", F.Phase >= 5 and F.Finale == nil)
	setAttr("Pattern", F.Pattern and F.Pattern.Name or "")
	setAttr("PatternUntil", F.Pattern and F.Pattern.Until or 0)
	setAttr("PerfectOnly", perfectOnly(F))
end

local function setMode(F, mode: string, seconds: number?)
	F.Mode = mode
	F.ModeAt = now()
	F.ModeUntil = seconds and (F.ModeAt + seconds) or 0
	setAttr("Mode", mode)
	setAttr("ModeAt", F.ModeAt)
	setAttr("ModeUntil", F.ModeUntil)
	bump()
end

local function rootCF(F): CFrame
	return CFrame.new(F.Pos) * CFrame.Angles(0, F.Yaw, 0)
end

local function ensureRig()
	if rigRoot and rigRoot.Parent then
		return rigRoot
	end
	local live = workspace:FindFirstChild("HalloweenLive")
	if not live then
		return nil
	end
	local folder = live:FindFirstChild("Boss")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Boss"
		folder.Parent = live
	end
	local rig = folder:FindFirstChild("BossRig")
	if not rig then
		rig = Instance.new("Model")
		rig.Name = "BossRig"
		pcall(function()
			rig.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
		rig.Parent = folder
	end
	local root = rig:FindFirstChild("BossRoot")
	if not root then
		root = Instance.new("Part")
		root.Name = "BossRoot"
		root.Size = Vector3.new(2, 2, 2)
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.CastShadow = false
		root.CFrame = CFrame.new(Layout.Boss.Spawn + Vector3.new(0, -60, 0))
		root.Parent = rig
		rig.PrimaryPart = root
	end
	rigRoot = root
	return root
end

local function moveRoot(F, hidden: boolean?)
	local root = ensureRig()
	local cf = rootCF(F)
	if hidden then
		cf = cf * CFrame.new(0, -60, 0)
	end
	if root then
		root.CFrame = cf
		root:SetAttribute("Mode", F.Mode)
	end
	F.LastCFPublish = F.LastCFPublish or 0
	local t = now()
	if t - F.LastCFPublish >= .25 then
		F.LastCFPublish = t
		setAttr("BossCF", cf)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Event HP (modules.EventHP, started after this module: reached lazily, hooked once)
---------------------------------------------------------------------------------------------------------------------
local hookedHP: any = nil
local onWipe, onRevive -- (defined with the fight logic below)

-- the bleed-out spawn: the north rim, a few studs behind the top of the north ramp, facing the pit
local function rimSpawn(): CFrame
	local top = Layout.Pit.Ramps[1].Top
	local pos = Vector3.new(top.X, Layout.FloorY + 3.2, top.Z - 6)
	return CFrame.lookAt(pos, Vector3.new(Layout.Pit.Center.X, pos.Y, Layout.Pit.Center.Z))
end
Boss.RimSpawn = rimSpawn

local function combat(): any
	local hp = modules and modules.EventHP
	if type(hp) ~= "table" or type(hp.Enter) ~= "function" then
		return nil
	end
	if hookedHP ~= hp then
		hookedHP = hp
		pcall(hp.SetZone, Boss.ZONE, { Spawn = rimSpawn(), Name = { "THE PIT", "ЯМА" } })
		if type(hp.OnWipe) == "function" then
			hp.OnWipe(function(zoneId, players)
				if zoneId == Boss.ZONE then
					onWipe(players)
				end
			end)
		end
		if type(hp.OnRevive) == "function" then
			hp.OnRevive(function(player, zoneId, by)
				if zoneId == Boss.ZONE then
					onRevive(player, by)
				end
			end)
		end
	end
	return hp
end
Boss.Combat = combat

-- seconds of extra warning EventHP gives H10 Candle Corgi owners (the impact waits for it so everyone keeps the full
-- telegraph and the H10 owner sees it earlier)
local function lead(): number
	local hp = combat()
	local ok, v = pcall(function()
		return hp.Rules.Config().H10Lead
	end)
	return (ok and tonumber(v)) or .35
end
Boss.Lead = lead

local function hasDog(player: Player, key: string): boolean
	local hp = combat()
	if hp and type(hp.HasDog) == "function" then
		local ok, v = pcall(hp.HasDog, player, key)
		return ok and v == true
	end
	return false
end

-- can the boss aim at this player (in the pit's combat zone and not downed)
local function canTarget(player: Player): boolean
	local hp = combat()
	if hp and type(hp.CanTarget) == "function" then
		local ok, v = pcall(hp.CanTarget, player)
		return ok and v == true
	end
	return true
end
Boss.CanTarget = canTarget

local function cancelHazards(F, ids: { number }?)
	local hp = combat()
	if hp and type(hp.CancelHazards) == "function" then
		pcall(hp.CancelHazards, Boss.ZONE, ids)
	end
	if F and F.Hazards then
		if ids then
			for _, id in ipairs(ids) do
				F.Hazards[id] = nil
			end
		else
			table.clear(F.Hazards)
		end
	end
end
Boss.CancelHazards = cancelHazards

-- EventHP hazards (zone "Boss") with an OnHit that adds the Curse and tells the hit player (BossEvent Knock: the curse
-- popup; EventHP already applied the damage and the knock-back); record = a list that collects the hit userIds -> ids
local function hazardWave(F, defs: { any }, curse: number?, attack: string?, record: { number }?): { number }
	local hp = combat()
	if not hp or type(hp.HazardWave) ~= "function" or #defs == 0 then
		return {}
	end
	local hit = function(player: Player, dealt: number, velocity: Vector3?, _pos: Vector3?)
		if F.Ended or not player or not player.Parent then
			return
		end
		if record and not table.find(record, player.UserId) then
			table.insert(record, player.UserId)
		end
		if curse and curse > 0 and core and core.AddCurse then
			core.AddCurse(player, curse)
		end
		-- BossEvent Knock {Velocity, Curse, Attack, Damage} (to the hit player)
		signal(player, { Kind = "Knock", Velocity = velocity, Curse = curse or 0, Attack = attack, Damage = math.floor((tonumber(dealt) or 0) + .5) })
	end
	local list = {}
	for _, d in ipairs(defs) do
		local def = table.clone(d)
		def.OnHit = hit
		table.insert(list, def)
	end
	local ok, ids = pcall(hp.HazardWave, Boss.ZONE, list)
	if not ok or type(ids) ~= "table" then
		warn("Halloween Boss: hazard wave failed: " .. tostring(ids))
		return {}
	end
	F.Hazards = F.Hazards or {}
	for _, id in ipairs(ids) do
		F.Hazards[id] = true
	end
	return ids
end
Boss.HazardWave = hazardWave

---------------------------------------------------------------------------------------------------------------------
-- fighters, contribution
---------------------------------------------------------------------------------------------------------------------
local function isFighterPos(pos: Vector3): boolean
	local c = Layout.Pit.Center
	if CB.InPitOnly == false then
		local d = flatten(pos - c).Magnitude
		return (Layout.InPit(pos) or d <= T.ArenaRadius) and pos.Y > c.Y - 14 and pos.Y < c.Y + 22
	end
	-- only the pit counts (DESIGN §10.4: rim camping removed); y above the floor - 14 (a player falling through is not one)
	return Layout.InPit(pos) and pos.Y > c.Y - 14
end
Boss.IsFighterPos = isFighterPos

local function fighterList(): { Player }
	local out = {}
	for _, pl in ipairs(Boss.GetPlayers()) do
		local pos = rootPos(pl)
		if pos and isFighterPos(pos) then
			table.insert(out, pl)
		end
	end
	return out
end
Boss.FighterList = fighterList

local function maxArmorFor(F, n: number): number
	n = math.clamp(n, 1, B.MaxFighters or 20)
	return B.BaseArmor * F.Def.Armor * (1 + B.PerFighterArmor * (n - 1))
end

-- EventHP zone membership follows the pit: fighters are entered, players who climbed out are left (a downed player stays
-- until revived / bled out: crawling out of the pit must not cancel the downed state)
local function syncCombat(F, list: { Player })
	local hp = combat()
	if not hp or F.Ended then
		return
	end
	local inFight = {}
	for _, pl in ipairs(list) do
		inFight[pl] = true
		local okZ, zone = pcall(hp.Zone, pl)
		if okZ and zone ~= Boss.ZONE then
			local ok, err = pcall(hp.Enter, pl, Boss.ZONE)
			if not ok then
				warn("Halloween Boss: EventHP.Enter failed: " .. tostring(err))
			end
		end
	end
	local okP, members = pcall(hp.Players, Boss.ZONE)
	for _, pl in ipairs(okP and members or {}) do
		if not inFight[pl] and not hp.IsDowned(pl) then
			pcall(hp.Leave, pl, Boss.ZONE)
		end
	end
end

-- every member of the zone out (fight over); downed ones get up where they are
local function leaveCombat(keepDowned: boolean?)
	local hp = combat()
	if not hp then
		return
	end
	local okP, members = pcall(hp.Players, Boss.ZONE)
	for _, pl in ipairs(okP and members or {}) do
		if not (keepDowned and hp.IsDowned(pl)) then
			pcall(hp.Leave, pl, Boss.ZONE)
		end
	end
end

-- fighters every step (combat zone membership), the armor scaling once a second
local function updateFighters(F, rescale: boolean?)
	local list = fighterList()
	F.FighterList = list
	syncCombat(F, list)
	local n = #list
	if rescale and n ~= F.Fighters then
		F.Fighters = n
		local frac = F.MaxArmor > 0 and F.Armor / F.MaxArmor or 1
		F.MaxArmor = maxArmorFor(F, n)
		F.Armor = frac * F.MaxArmor
		setAttr("Fighters", n)
		setAttr("MaxArmor", math.ceil(F.MaxArmor))
		setAttr("Armor", math.max(0, math.ceil(F.Armor)))
	end
	return n
end

-- fighters the boss may aim at (not downed)
local function targetable(F): { Player }
	local out = {}
	for _, pl in ipairs(F.FighterList or {}) do
		if canTarget(pl) then
			table.insert(out, pl)
		end
	end
	return out
end
Boss.Targetable = targetable

local function targetPositions(F): { Vector3 }
	local out = {}
	for _, pl in ipairs(targetable(F)) do
		local p = rootPos(pl)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- reward-share credit without armor damage (skeletons, fake mounds, revives, finale mechanics)
local function score(F, player: Player?, amount: number)
	if not player or amount <= 0 then
		return
	end
	F.Score[player.UserId] = (F.Score[player.UserId] or 0) + amount
	F.Names[player.UserId] = player.Name
end

local function credit(F, player: Player?, amount: number)
	if not player or amount <= 0 then
		return
	end
	local uid = player.UserId
	F.Damage[uid] = (F.Damage[uid] or 0) + amount
	F.Score[uid] = (F.Score[uid] or 0) + amount
	F.Names[uid] = player.Name
	-- quest / stat / souls ride the per-second queue (one profile write per second)
	local per = (Config.Exorcism.Souls and Config.Exorcism.Souls.BossDamagePer) or 120
	local frac = (F.SoulFrac[uid] or 0) + amount / per
	local souls = math.floor(frac)
	F.SoulFrac[uid] = frac - souls
	F.WholeFrac = F.WholeFrac or {}
	local wf = (F.WholeFrac[uid] or 0) + amount
	local whole = math.floor(wf)
	F.WholeFrac[uid] = wf - whole
	if core and core.Queue and (whole > 0 or souls > 0) then
		-- (curse relief comes with every strike hit: kinds register Activity = "BossDamage")
		core.Queue(player, { Quest = { BossDamage = whole }, Stat = { BossDamage = whole }, Souls = souls })
	end
	-- Chapter II contracts ("Deal 2500 damage to THE GRAVEKEEPER"), stats and resonance (queued, 1 write per second)
	local C2 = modules and modules.Chapter2
	if whole > 0 and type(C2) == "table" and type(C2.Progress) == "function" then
		local ok, err = pcall(C2.Progress, player, "BossDamage", whole)
		if not ok then
			warn("Halloween Boss: Chapter2.Progress failed: " .. tostring(err))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Strike targets (adapter around SSS.Halloween.Strike, DESIGN §6)
---------------------------------------------------------------------------------------------------------------------
local function strike()
	return modules and modules.Strike
end

local function addTarget(F, spec: { [string]: any }, entry: { [string]: any })
	local Strike = strike()
	if not Strike then
		return nil
	end
	spec.Shared = true
	spec.MaxHP = spec.MaxHP or spec.HP
	spec.Data = spec.Data or {}
	spec.Data.Boss = true
	spec.Data.Fight = F.Id
	local ok, target = pcall(Strike.Add, spec)
	if not ok or target == nil then
		warn("Halloween Boss: Strike.Add failed: " .. tostring(target))
		return nil
	end
	entry.Target = target
	entry.Kind = spec.Kind
	F.Targets[target] = entry
	local id = idOf(target)
	if id ~= nil then
		F.TargetIds[id] = entry
	end
	return target
end

local function removeTarget(F, target: any, reason: string?)
	if target == nil then
		return
	end
	local entry = F.Targets[target]
	F.Targets[target] = nil
	local id = idOf(target)
	if id ~= nil then
		F.TargetIds[id] = nil
	end
	if entry then
		entry.Removed = true
	end
	local Strike = strike()
	if Strike then
		pcall(Strike.Remove, target, reason or "Boss")
	end
end

local function moveTarget(target: any, cf: CFrame)
	local Strike = strike()
	if Strike and target ~= nil then
		pcall(Strike.Move, target, cf)
	end
end

local function entryOf(F, target: any)
	if not F then
		return nil
	end
	return F.Targets[target] or F.TargetIds[idOf(target)]
end

local function hitQuality(hit: any): (number, boolean, number)
	local q = type(hit) == "table" and tonumber(hit.Quality) or 1
	local crit = type(hit) == "table" and hit.Crit == true
	local dmg = type(hit) == "table" and tonumber(hit.Damage) or nil
	return q or 1, crit, dmg or 0
end

---------------------------------------------------------------------------------------------------------------------
-- knockback / curse / Event HP (melee: skeleton bites; telegraphed attacks are hazards)
---------------------------------------------------------------------------------------------------------------------
local function knock(F, player: Player, from: Vector3, power: number, up: number?, curse: number?, attack: string?)
	local root = core and core.Root(player)
	if not root then
		return
	end
	local dir = flatten(root.Position - from)
	if dir.Magnitude < .1 then
		dir = Vector3.new(Boss.Rand(-1, 1), 0, Boss.Rand(-1, 1))
	end
	dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(1, 0, 0)
	local v = dir * power + Vector3.new(0, up or power * .55, 0)
	pcall(function()
		root.AssemblyLinearVelocity = v -- server copy; the owning client applies it too (Signal Knock)
	end)
	if curse and curse > 0 and core.AddCurse then
		core.AddCurse(player, curse)
	end
	local dealt = 0
	local hp = combat()
	if hp and attack then
		local ok, res = pcall(hp.Damage, player, BossMath.AttackDamage(attack, F.Difficulty), attack, { Kind = attack, Knock = v, From = from })
		dealt = (ok and tonumber(res)) or 0
	end
	-- BossEvent Knock {Velocity, Curse, Attack, Damage}
	signal(player, { Kind = "Knock", Velocity = v, Curse = curse or 0, Attack = attack, Damage = math.floor(dealt + .5) })
end

-- targetable players whose root is inside a horizontal radius at arena height (melee reach)
local function playersIn(center: Vector3, radius: number, F): { Player }
	local out = {}
	for _, pl in ipairs(targetable(F)) do
		local pos = rootPos(pl)
		if pos and pos.Y < floorY() + 10 and flatten(pos - center).Magnitude <= radius + 1 then
			table.insert(out, pl)
		end
	end
	return out
end

-- a telegraphed attack as an EventHP hazard (Circle / Cone on the pit floor, or on the real surface: Ground)
local function attackHazard(F, kind: string, shape: any, tele: number, impactAt: number, knockPower: number, up: number?, curse: number?,
	record: { number }?): number?
	local def = { Shape = shape, Telegraph = tele, ImpactAt = impactAt, Damage = BossMath.AttackDamage(kind, F.Difficulty),
		Knock = { Power = knockPower, Up = up or knockPower * .55 }, Kind = kind, Source = "Gravekeeper" }
	local ids = hazardWave(F, { def }, curse, kind, record)
	return ids[1]
end

local function teleFor(F, kind: string, base: number): number
	return Patterns.Telegraph(base, F.Difficulty, BossMath.AttackDamage(kind, F.Difficulty))
end

---------------------------------------------------------------------------------------------------------------------
-- armor plates + weak points (targets on the boss body)
---------------------------------------------------------------------------------------------------------------------
local function slotCF(F, slotPos: Vector3): CFrame
	return rootCF(F) * CFrame.new(slotPos)
end

local function spawnPlate(F, slot: string)
	local def = BossModels.Slots.Plates[slot]
	local cur = F.Plates[slot]
	if cur and cur.Target then
		return
	end
	-- integrity in ARMOR units (independent of pickaxe tiers): every hit removes exactly the armor damage it dealt
	local entry = { Slot = slot, Role = "Plate" }
	local cf = slotCF(F, def.Pos)
	local hp = math.max(1, math.floor(T.PlateShare * F.MaxArmor + .5))
	addTarget(F, { Kind = "BossPlate", CFrame = cf, Radius = def.Radius, HP = hp, MaxHP = hp, Color = Color3.fromRGB(84, 86, 100),
		Material = "Slate", Size = Vector3.one * def.Radius * 2, Name = "STONE ARMOR", NameRU = "КАМЕННАЯ БРОНЯ", Variant = slot,
		Attributes = { Slot = slot }, Data = { Slot = slot } }, entry)
	F.Plates[slot] = entry
end

local function spawnPlates(F)
	for _, slot in ipairs(BossModels.Slots.PlateOrder) do
		local pl = F.Plates[slot]
		if not (pl and (pl.Target or (pl.RegrowAt and pl.RegrowAt > now()))) then
			spawnPlate(F, slot)
		end
	end
	setAttr("Plates", plateMask(F))
end

local function clearPlates(F, keepTimers: boolean?)
	for slot, pl in pairs(F.Plates) do
		if pl.Target then
			removeTarget(F, pl.Target, "Burrow")
			pl.Target = nil
		end
		if not keepTimers then
			F.Plates[slot] = nil
		end
	end
	setAttr("Plates", plateMask(F))
end

local function openWeak(F)
	local open = (B.WeakPoints and B.WeakPoints.Open) or 6
	local count = (B.WeakPoints and B.WeakPoints.Count) or 3
	local order = BossModels.Slots.WeakOrder
	F.WeakUntil = now() + open
	local slots = {}
	for i = 1, math.min(count, #order) do
		local slot = order[i]
		local def = BossModels.Slots.Weak[slot]
		local entry = { Slot = slot, Role = "Weak" }
		addTarget(F, { Kind = "BossWeak", CFrame = slotCF(F, def.Pos), Radius = def.Radius, HP = 1e9, MaxHP = 1e9, Panel = false,
			Color = Color3.fromRGB(120, 255, 110), Material = "Neon", Size = Vector3.one * def.Radius * 2, Name = "WEAK POINT",
			NameRU = "СЛАБОЕ МЕСТО", Variant = slot, Attributes = { Slot = slot, PerfectOnly = perfectOnly(F) }, Data = { Slot = slot } }, entry)
		F.Weak[slot] = entry
		table.insert(slots, slot)
	end
	setAttr("WeakOpenUntil", F.WeakUntil)
	setAttr("WeakSlots", weakSlots(F))
	bump()
	-- BossEvent WeakPoint {Open, Slots = {slot...}, Until, PerfectOnly}
	signal("zone", { Kind = "WeakPoint", Open = true, Slots = slots, Until = F.WeakUntil, PerfectOnly = perfectOnly(F) or nil })
end

local function closeWeak(F)
	local had = false
	for slot, entry in pairs(F.Weak) do
		removeTarget(F, entry.Target, "Closed")
		F.Weak[slot] = nil
		had = true
	end
	F.WeakUntil = 0
	setAttr("WeakOpenUntil", 0)
	setAttr("WeakSlots", "")
	if had then
		signal("zone", { Kind = "WeakPoint", Open = false })
	end
end

local function syncBodyTargets(F)
	for slot, pl in pairs(F.Plates) do
		if pl.Target then
			moveTarget(pl.Target, slotCF(F, BossModels.Slots.Plates[slot].Pos))
		end
	end
	for slot, w in pairs(F.Weak) do
		if w.Target then
			moveTarget(w.Target, slotCF(F, BossModels.Slots.Weak[slot].Pos))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- phase machine
---------------------------------------------------------------------------------------------------------------------
local enterPhase, defeat, finish, startBurrow, applyDamage

local VULNERABLE = { Idle = true, Walk = true, Windup = true, Stagger = true }

local function invulnerable(F): (boolean, string?)
	if F.Ended then
		return true, "The Gravekeeper has fallen"
	end
	if F.Finale then
		return true, "The Gravekeeper has fallen"
	end
	if F.PendingPhase or F.PendingDefeat then
		return true, "The Gravekeeper is changing form!"
	end
	if F.Shield then
		return true, "THE GRAVEKEEPER IS SHIELDED - smash the skeleton dogs!"
	end
	if not VULNERABLE[F.Mode] then
		return true, "The Gravekeeper is changing form!"
	end
	return false
end
Boss.Invulnerable = function()
	return Boss.Fight and invulnerable(Boss.Fight)
end

-- all armor damage goes through here (clamped at the next phase threshold: no phase is ever skipped)
applyDamage = function(F, player: Player?, amount: number, source: string, force: boolean?): number
	if not F or F.Ended or F.Finale or amount <= 0 then
		return 0
	end
	if not force and invulnerable(F) then
		return 0
	end
	local nextDef = phaseDef(F.Phase + 1)
	local floorArmor = nextDef and nextDef.From * F.MaxArmor or 0
	local applied = math.min(amount, math.max(0, F.Armor - floorArmor))
	if applied <= 0 then
		return 0
	end
	F.Armor -= applied
	credit(F, player, applied)
	setAttr("Armor", math.max(0, math.ceil(F.Armor)))
	-- armor by source (Plate, Weak, Mound, Shard, PlateBreak, Sync, ...), in total and per player (balance reports)
	F.BySource = F.BySource or {}
	F.BySource[source] = (F.BySource[source] or 0) + applied
	if player then
		F.Sources = F.Sources or {}
		local mine = F.Sources[player.UserId] or {}
		F.Sources[player.UserId] = mine
		mine[source] = (mine[source] or 0) + applied
	end
	if F.Armor <= floorArmor + 1e-6 then
		-- the transformation happens on the next Step (never inside a Strike callback)
		F.Armor = floorArmor
		if nextDef then
			F.PendingPhase = F.Phase + 1
		else
			F.PendingDefeat = true
		end
	end
	return applied
end
Boss.ApplyDamage = function(player, amount, source, force)
	return applyDamage(Boss.Fight, player, amount, source or "Script", force)
end

local function capOf(F, player: Player): any
	F.Caps = F.Caps or {}
	local c = F.Caps[player.UserId]
	if not c then
		c = BossMath.NewCap()
		F.Caps[player.UserId] = c
	end
	return c
end

-- one player's armor damage through the soft cap (BossMath.CapApply over a rolling window; mechanic damage bypasses
-- 60% of it), then the timing factor on what lands (a Perfect body hit x PerfectExtra, a Good one x GoodMult), then
-- applyDamage. o = {Mechanic, Perfect, Good, Force}
local function deal(F, player: Player?, armor: number, source: string, o: { [string]: any }?): number
	local opts = o or {}
	if not F or F.Ended or armor <= 0 then
		return 0
	end
	if not opts.Force and invulnerable(F) then
		return 0 -- (an immune boss never eats a player's cap window)
	end
	local amount = armor
	if player and scaled(F) then
		amount = BossMath.CapApply(capOf(F, player), now(), armor, F.CapPerSecond or 0, opts.Mechanic == true)
		if opts.Perfect then
			amount *= tonumber(CB.PerfectExtra) or 1
		elseif opts.Good then
			amount *= tonumber(CB.GoodMult) or 1
		end
	end
	return applyDamage(F, player, amount, source, opts.Force)
end
Boss.Deal = function(player, armor, source, o)
	return deal(Boss.Fight, player, armor, source or "Script", o)
end

local function clearMounds(F)
	for _, m in pairs(F.Mounds) do
		if m.Target then
			removeTarget(F, m.Target, "Collapse")
		end
	end
	F.Mounds = {}
	F.BurrowUntil = 0
	if F.EruptHazard then
		cancelHazards(F, { F.EruptHazard })
		F.EruptHazard = nil
	end
	setAttr("BurrowUntil", 0)
end

local function clearSkeletons(F, reason: string?)
	local list = {}
	for key, s in pairs(F.Skeletons) do
		table.insert(list, { TargetId = idOf(s.Target), Position = s.Pos })
		if s.Target then
			removeTarget(F, s.Target, reason or "Collapse")
		end
		F.Skeletons[key] = nil
	end
	if #list > 0 then
		-- BossEvent SkeletonDown {Collapse = true, List = {{TargetId, Position}}}
		signal("zone", { Kind = "SkeletonDown", Collapse = true, List = list })
	end
end

local function clearRocks(F)
	for key, r in pairs(F.Rocks) do
		if r.Target then
			removeTarget(F, r.Target, "Collapse")
		end
		F.Rocks[key] = nil
	end
end

local function setShield(F, up: boolean)
	F.Shield = up
	setAttr("Shield", up)
	setAttr("ShieldNeed", up and F.ShieldNeed or 0)
	setAttr("ShieldLeft", up and math.max(0, F.ShieldNeed - F.ShieldKills) or 0)
	bump()
	-- BossEvent Shield {Up, Need, Left}
	signal("zone", { Kind = "Shield", Up = up, Need = F.ShieldNeed, Left = math.max(0, F.ShieldNeed - F.ShieldKills) })
end

-- PHASE 2: burrow + mounds
startBurrow = function(F)
	closeWeak(F)
	clearPlates(F, true)
	F.Attack = nil
	setMode(F, "Burrow", 2.4)
	F.SubPhase = "Diving"
	-- BossEvent Burrow {Stage = "Dive", Position}
	signal("zone", { Kind = "Burrow", Stage = "Dive", Position = F.Pos })
end

local function spawnMounds(F)
	local spots = Layout.Boss.Mounds
	local n = math.min((B.Burrow and B.Burrow.Mounds) or 6, #spots)
	local real = math.clamp(math.floor(Boss.Rand(1, n + .999)), 1, n)
	local list = {}
	F.Mounds = {}
	-- HP in tier-normalized hits (Strike Damage = "Power"), a little more with more diggers
	local hp = ((B.Burrow and B.Burrow.MoundHP) or 3) * (1 + .15 * math.max(0, F.Fighters - 1))
	for i = 1, n do
		local pos = spots[i] + Vector3.new(0, 1.2, 0)
		local entry = { Index = i, Real = i == real, Pos = spots[i], Role = "Mound" }
		addTarget(F, { Kind = "BossMound", Position = pos, Radius = 3.6, HP = hp, MaxHP = hp, Unit = 1, Color = Color3.fromRGB(70, 54, 44),
			Material = "Ground", Size = Vector3.new(7, 3, 7), Name = "GRAVE MOUND", NameRU = "МОГИЛЬНЫЙ ХОЛМ", Seed = i,
			Ground = spots[i], Attributes = { Index = i }, Data = { Index = i } }, entry)
		F.Mounds[i] = entry
		table.insert(list, { TargetId = idOf(entry.Target), Position = spots[i], Index = i })
	end
	F.RealMound = real
	local timeout = ((B.Burrow and B.Burrow.Timeout) or 22) / (F.Def.Speed ^ .3)
	F.BurrowUntil = now() + timeout
	F.EruptHazard = nil
	F.SubPhase = "Underground"
	setMode(F, "Underground")
	setAttr("BurrowUntil", F.BurrowUntil)
	-- BossEvent Burrow {Stage = "Mounds", Mounds = {{TargetId, Position, Index}}, Until}
	signal("zone", { Kind = "Burrow", Stage = "Mounds", Mounds = list, Until = F.BurrowUntil })
end

-- the unfound mound's eruption is telegraphed (EventHP hazard) so it lands exactly at the timeout
local function warnEruption(F)
	local m = F.Mounds[F.RealMound]
	if not m or F.EruptHazard then
		return
	end
	local tele = teleFor(F, "Erupt", 1.3)
	local impactAt = math.max(F.BurrowUntil, now() + tele)
	F.BurrowUntil = impactAt
	setAttr("BurrowUntil", impactAt)
	F.EruptHazard = attackHazard(F, "Erupt", Hazards.Circle(Vector3.new(m.Pos.X, floorY(), m.Pos.Z), T.EruptRadius), tele, impactAt,
		T.EruptKnock, nil, T.EruptCurse) or false
end

local function erupt(F, found: boolean, player: Player?)
	local m = F.Mounds[F.RealMound]
	local pos = m and m.Pos or Layout.Boss.Spawn
	local hazardId = F.EruptHazard
	if found and hazardId then
		cancelHazards(F, { hazardId })
	end
	F.EruptHazard = nil
	clearMounds(F)
	-- it bursts out of the mound a few studs toward the centre (its 40-stud body must fit inside the pit)
	local inward = Layout.Boss.Spawn + (pos - Layout.Boss.Spawn) * .75
	F.Pos = Vector3.new(inward.X, floorY(), inward.Z)
	-- burst out side-on (tangent to the mound circle): the ~40-stud body then stays inside the arena / terrace ring
	local c = Layout.Boss.Spawn
	local d = flatten(F.Pos - c)
	local tangent = d.Magnitude > .1 and Vector3.new(-d.Z, 0, d.X).Unit or Vector3.new(0, 0, -1)
	F.Yaw = math.atan2(-tangent.X, -tangent.Z)
	F.SubPhase = "Erupting"
	setMode(F, "Erupt", 2.2)
	moveRoot(F)
	local dealt = 0
	if found then
		local amount = ((B.Burrow and B.Burrow.RealDamage) or .08) * F.MaxArmor
		dealt = deal(F, player, amount, "Mound", { Mechanic = true, Force = true })
	end
	-- BossEvent Erupt {Position, Found, UserId, Damage, Hits, HazardId}: the unfound eruption hurts through its hazard
	signal("zone", { Kind = "Erupt", Position = pos, Found = found, UserId = player and player.UserId or 0, Damage = math.floor(dealt), Hits = {},
		HazardId = (not found and hazardId) or nil })
end

-- PHASE 3: skeleton pack
local function spawnPack(F)
	local cfg = B.Skeletons
	local count = math.min(cfg.Max or 14, (cfg.Count or 6) + (cfg.PerFighter or 1) * math.max(0, F.Fighters - 1))
	local spawns = Layout.Boss.SkeletonSpawns
	local hp = cfg.HP or 4 -- tier-normalized hits
	local list = {}
	F.PackSerial = (F.PackSerial or 0) + 1
	for i = 1, count do
		local base = spawns[((i - 1) % #spawns) + 1]
		local jitter = Vector3.new(Boss.Rand(-2.5, 2.5), 0, Boss.Rand(-2.5, 2.5))
		local pos = Vector3.new(base.X + jitter.X, floorY(), base.Z + jitter.Z)
		local key = F.PackSerial * 100 + i
		local entry = { Key = key, Pos = pos, Yaw = 0, NextBite = now() + 2, Role = "Skeleton", Born = now() }
		addTarget(F, { Kind = "BossSkeleton", Position = pos + Vector3.new(0, 1.9, 0), Radius = 2.4, HP = hp, MaxHP = hp, Unit = 1,
			Color = Color3.fromRGB(222, 210, 178), Material = "SmoothPlastic", Size = Vector3.new(3, 3.6, 5), Name = "SKELETON DOG",
			NameRU = "СОБАКА-СКЕЛЕТ", Seed = key, Ground = pos, Attributes = { Key = key }, Data = { Pack = F.PackSerial } }, entry)
		if entry.Target then
			F.Skeletons[key] = entry
			table.insert(list, { TargetId = idOf(entry.Target), Position = pos, Key = key })
		end
	end
	F.ShieldNeed = math.max(1, math.ceil(#list * ((cfg.Shield == false) and 0 or T.ShieldShare)))
	F.ShieldKills = 0
	-- BossEvent Skeletons {Count, Need, Spawns = {{TargetId, Position, Key}}}
	signal("zone", { Kind = "Skeletons", Count = #list, Need = F.ShieldNeed, Spawns = list })
	if cfg.Shield ~= false and #list > 0 then
		setShield(F, true)
	end
	F.NextPackAt = math.huge
end

-- PHASE 4: rock waves
-- a landing spot for a rock aimed at (x, z): the flat arena floor (a rock's half-size off the walls) or the middle of the
-- terrace ring, never a ramp / the stairs; Y = the real surface (Models.Boss.Surface), so the telegraph, the landing
-- hits, the rock model and its target all sit on the ground the players stand on. nil = no flat spot there.
local ROCK_HALF = 2.6
function Boss.RockSpot(x: number, z: number): (Vector3?, string?)
	local R, A = Layout.Pit.Rim, Layout.Pit.Arena
	-- per axis: inside the arena -> keep; in the outer band -> the nearer of the floor edge / the terrace centre line
	local function axis(v: number, r0: number, a0: number, a1: number, r1: number): (number, boolean)
		local lo, hi = a0 + ROCK_HALF, a1 - ROCK_HALF
		if v >= lo and v <= hi then
			return v, false
		end
		local edge, mid = lo, (r0 + a0) / 2
		if v > hi then
			edge, mid = hi, (r1 + a1) / 2
		end
		if math.abs(v - edge) <= math.abs(v - mid) then
			return edge, false
		end
		return mid, true
	end
	local nx, tx = axis(x, R.X0, A.X0, A.X1, R.X1)
	local nz, tz = axis(z, R.Z0, A.Z0, A.Z1, R.Z1)
	if tx or tz then
		-- on the ring: the other axis may run along it
		nx = tx and nx or math.clamp(x, R.X0 + ROCK_HALF + .4, R.X1 - ROCK_HALF - .4)
		nz = tz and nz or math.clamp(z, R.Z0 + ROCK_HALF + .4, R.Z1 - ROCK_HALF - .4)
	end
	local y, kind = surfaceAt(nx, nz)
	if kind ~= "Floor" and kind ~= "Terrace" then
		return nil
	end
	-- the whole rock (~5 wide) sits on that surface (no ramp under a corner)
	for _, o in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		local _, k2 = surfaceAt(nx + o[1] * (ROCK_HALF - .1), nz + o[2] * (ROCK_HALF - .1))
		if k2 ~= kind then
			return nil
		end
	end
	return Vector3.new(nx, y, nz), kind
end

local function rockWave(F)
	local cfg = B.Rocks
	F.RockWave += 1
	setAttr("RockWave", F.RockWave)
	local n = math.min(10, (cfg.PerWave or 5) + math.floor(math.max(0, F.Fighters - 1) / 2))
	local A = Layout.Pit.Arena
	local land = now() + math.max((cfg.LandDelay or 1.6) / (F.Def.Speed ^ .3), lead() + teleFor(F, "RockImpact", 0))
	local placed = {}
	local fighters = targetable(F)
	local candidates = {}
	for i = 1, n do
		local pos, kind
		for _ = 1, 12 do
			local cx, cz
			if i <= #fighters and Boss.Rand() < .6 then
				local p = rootPos(fighters[i])
				if p then
					cx, cz = p.X + Boss.Rand(-3, 3), p.Z + Boss.Rand(-3, 3)
				end
			end
			if not cx then
				-- the rest rain on the arena floor
				cx, cz = Boss.Rand(A.X0 + 3, A.X1 - 3), Boss.Rand(A.Z0 + 3, A.Z1 - 3)
			end
			local cand, k = Boss.RockSpot(cx, cz)
			local ok = cand ~= nil and flatten(cand - F.Pos).Magnitude > 9
			for _, q in ipairs(placed) do
				if ok and flatten(cand - q).Magnitude < 6 then
					ok = false
				end
			end
			if ok then
				pos, kind = cand, k
				break
			end
		end
		if pos then
			table.insert(placed, pos)
			local radius = kind == "Terrace" and math.min(T.RockImpactRadius, T.TerraceRockRadius) or T.RockImpactRadius
			local landAt = land + (i - 1) * .12
			local dmg = BossMath.AttackDamage("RockImpact", F.Difficulty)
			table.insert(candidates, { Pos = pos, Radius = radius, LandAt = landAt,
				Def = { Shape = Patterns.Ground(pos, radius), Telegraph = landAt - now() - lead(), ImpactAt = landAt, Damage = dmg,
					Knock = { Power = T.RockKnock, Up = T.RockKnock * .55 }, Kind = "RockImpact", Source = "Gravekeeper" } })
		end
	end
	-- the wave as a whole must leave a safe spot (thinned from the end otherwise)
	local defs = {}
	for _, c in ipairs(candidates) do
		table.insert(defs, c.Def)
	end
	local fair = Patterns.Thin(defs)
	local ids = hazardWave(F, fair, T.RockImpactCurse, "Rock")
	local rocks = {}
	for i = 1, #fair do
		local c = candidates[i]
		F.RockSerial = (F.RockSerial or 0) + 1
		local key = F.RockSerial
		F.Rocks[key] = { Key = key, Pos = c.Pos, LandAt = c.LandAt, Role = "Rock", Radius = c.Radius, HazardId = ids[i] }
		table.insert(rocks, { Key = key, Position = c.Pos, LandAt = c.LandAt, Radius = c.Radius, HazardId = ids[i] })
	end
	local cap = rockCap(F)
	-- BossEvent Rocks {Wave, Waves (0 = unlimited), Rocks = {{Key, Position (on the real surface), LandAt, Radius, HazardId}},
	-- HazardIds}
	signal("zone", { Kind = "Rocks", Wave = F.RockWave, Waves = cap > 0 and cap or (cfg.Waves or 3), Unlimited = cap == 0 or nil, Rocks = rocks,
		HazardIds = ids })
	F.NextWaveAt = now() + T.WaveGap / F.Def.Speed
end

-- PHASE entry
enterPhase = function(F, p: number)
	F.Phase = p
	F.Attack = nil
	local def = phaseDef(p)
	setAttr("Phase", p)
	setAttr("PhaseName", def and def.Name or "")
	bump()
	-- BossEvent Phase {Phase, Name}
	signal("zone", { Kind = "Phase", Phase = p, Name = def and def.Name or "" })
	if p == 2 then
		startBurrow(F)
	elseif p == 3 then
		clearMounds(F)
		if F.Mode ~= "Erupt" then
			setMode(F, "Roar", 2.6)
		else
			F.PendingRoar = true
		end
		F.SubPhase = "Summoning"
	elseif p == 4 then
		clearSkeletons(F, "Collapse")
		if F.Shield then
			setShield(F, false)
		end
		setMode(F, "Roar", 2.2)
		F.SubPhase = "Rocks"
		F.NextWaveAt = now() + 2.4
	elseif p == 5 then
		clearSkeletons(F, "Collapse")
		clearMounds(F)
		if F.Shield then
			setShield(F, false)
		end
		setMode(F, "Enrage", 3)
		F.SubPhase = "Enraged"
		F.NextWeakAt = now() + 4
		setAttr("Enraged", true)
		-- BossEvent Enrage {}
		signal("zone", { Kind = "Enrage", Position = F.Pos })
	end
	F.NextAttackAt = math.max(F.NextAttackAt or 0, now() + 4)
end

---------------------------------------------------------------------------------------------------------------------
-- attacks
---------------------------------------------------------------------------------------------------------------------
local function facing(F): Vector3
	return Vector3.new(-math.sin(F.Yaw), 0, -math.cos(F.Yaw))
end

local function yawTo(F, pos: Vector3): number
	local d = flatten(pos - F.Pos)
	if d.Magnitude < .1 then
		return F.Yaw
	end
	return math.atan2(-d.X, -d.Z)
end

local function nearestFighter(F, from: Vector3): (Player?, Vector3?, number)
	local best, bestPos, bestD = nil, nil, math.huge
	for _, pl in ipairs(targetable(F)) do
		local p = rootPos(pl)
		if p then
			local d = flatten(p - from).Magnitude
			if d < bestD then
				best, bestPos, bestD = pl, p, d
			end
		end
	end
	return best, bestPos, bestD
end

local function patternRunning(F): boolean
	return F.Pattern ~= nil and now() < F.Pattern.Until
end

local function startAttack(F)
	local pool = targetable(F)
	if #pool == 0 then
		return
	end
	local _, closePos, closeD = nearestFighter(F, F.Pos)
	local target = pool[math.clamp(math.floor(Boss.Rand(1, #pool + .999)), 1, #pool)]
	local tpos = rootPos(target) or closePos
	if not tpos then
		return
	end
	local kind
	local r = Boss.Rand()
	if closeD < 8.5 and r < .45 then
		kind = "Stomp"
	elseif r < .62 then
		kind = "Slam"
	else
		kind = "Sweep"
	end
	local a = { Kind = kind, Hits = {} }
	local shape, knockPower, up, curse
	if kind == "Stomp" then
		a.Pos = F.Pos
		a.Radius = T.Stomp.Radius
		a.Telegraph = teleFor(F, kind, T.Stomp.Telegraph)
		shape = Hazards.Circle(Vector3.new(a.Pos.X, floorY(), a.Pos.Z), a.Radius)
		knockPower, curse = T.Stomp.Knock, T.Stomp.Curse
	elseif kind == "Slam" then
		local d = flatten(tpos - F.Pos)
		local reach = math.min(d.Magnitude, 16)
		local dir = d.Magnitude > .1 and d.Unit or facing(F)
		a.Pos = Vector3.new(F.Pos.X, floorY(), F.Pos.Z) + dir * math.max(6, reach)
		a.Radius = B.Attacks.Slam.Radius
		a.Telegraph = teleFor(F, kind, B.Attacks.Slam.Telegraph)
		F.Yaw = yawTo(F, a.Pos)
		shape = Hazards.Circle(a.Pos, a.Radius)
		knockPower, curse = B.Attacks.Slam.Knock or 60, B.Attacks.Slam.Curse
	else
		F.Yaw = yawTo(F, tpos)
		a.Pos = F.Pos
		a.Radius = T.SweepRadius
		a.Angle = T.SweepAngle
		a.Dir = facing(F)
		a.Telegraph = teleFor(F, kind, B.Attacks.Sweep.Telegraph)
		shape = Hazards.Cone(Vector3.new(a.Pos.X, floorY(), a.Pos.Z), a.Dir, a.Angle, a.Radius)
		knockPower, up, curse = B.Attacks.Sweep.Knock or 48, 24, B.Attacks.Sweep.Curse
	end
	-- the impact waits for the H10 lead so everyone sees the whole telegraph (CANDLELIGHT owners see it earlier)
	local windup = lead() + a.Telegraph
	a.ImpactAt = now() + windup
	a.Dir = a.Dir or facing(F)
	a.HazardId = attackHazard(F, kind, shape, a.Telegraph, a.ImpactAt, knockPower, up, curse, a.Hits)
	F.Attack = a
	setMode(F, "Windup", windup)
	setAttr("Attack", kind)
	moveRoot(F)
	syncBodyTargets(F)
	-- BossEvent Attack {Attack, Stage = "Telegraph", Position, Radius, Angle?, Direction, Telegraph, ImpactAt, HazardId}
	-- (HazardId present: CombatFX draws the telegraph, BossFX only animates the wind-up / impact)
	signal("zone", { Kind = "Attack", Attack = kind, Stage = "Telegraph", Position = a.Pos, Radius = a.Radius, Angle = a.Angle,
		Direction = a.Dir, Telegraph = a.Telegraph, ImpactAt = a.ImpactAt, HazardId = a.HazardId })
end

local function resolveAttack(F)
	local a = F.Attack
	F.Attack = nil
	if not a then
		return
	end
	setMode(F, "Idle")
	setAttr("Attack", "")
	-- BossEvent Attack {Attack, Stage = "Impact", Position, Radius, Angle?, Direction, HazardId} (the hazard deals the damage)
	signal("zone", { Kind = "Attack", Attack = a.Kind, Stage = "Impact", Position = a.Pos, Radius = a.Radius, Angle = a.Angle,
		Direction = a.Dir, Hits = a.Hits, HazardId = a.HazardId })
	local iv = F.Phase >= 5 and B.Attacks.EnrageInterval or B.Attacks.Interval
	F.NextAttackAt = now() + Boss.Rand(iv[1], iv[2]) / F.Def.Speed
end

---------------------------------------------------------------------------------------------------------------------
-- endgame patterns (difficulties III-V): GRAVE LINES, LANTERN WALK, BONE RAIN
---------------------------------------------------------------------------------------------------------------------
local PATTERN_NAMES = { "GraveLines", "BoneRain", "LanternWalk" }

local function startPattern(F): boolean
	local e = CB.Endgame
	local positions = targetPositions(F)
	if #positions == 0 then
		return false
	end
	local pool = {}
	for _, name in ipairs(PATTERN_NAMES) do
		if name ~= F.LastPattern then
			table.insert(pool, name)
		end
	end
	local name = pool[math.clamp(math.floor(Boss.Rand(1, #pool + .999)), 1, #pool)]
	local centre = Vector3.zero
	for _, p in ipairs(positions) do
		centre += p
	end
	centre /= #positions
	local t = now()
	local gen = Patterns[name]
	local defs, info = gen(F.Difficulty, t, lead(), rand01, { Targets = positions, Toward = centre })
	if #defs == 0 then
		return false
	end
	local ids = hazardWave(F, defs, tonumber(e.Curse) or 4, name)
	F.LastPattern = name
	F.Pattern = { Name = name, StartAt = t, Until = info.Ends, Ids = ids }
	F.Patterns = (F.Patterns or 0) + 1
	-- no melee swing and no rock wave on top of a pattern
	F.NextAttackAt = math.max(F.NextAttackAt or 0, info.Ends + .8)
	if F.Phase == 4 and (F.NextWaveAt or 0) < info.Ends + .5 then
		F.NextWaveAt = info.Ends + .5
	end
	local every = e.Every or { 18, 26 }
	F.NextPatternAt = info.Ends + Boss.Rand(every[1], every[2]) / math.sqrt(F.Def.Speed)
	setAttr("Pattern", name)
	setAttr("PatternUntil", info.Ends)
	bump()
	-- BossEvent Pattern {Name = "GraveLines"|"LanternWalk"|"BoneRain", StartAt, Duration, HazardIds} (banner + boss pose;
	-- the hazards do the rest)
	signal("zone", { Kind = "Pattern", Name = name, StartAt = t, Duration = info.Duration, HazardIds = ids })
	return true
end
Boss.StartPattern = function(name: string?)
	local F = Boss.Fight
	if not F then
		return false
	end
	if name then
		F.LastPattern = nil
		local saved = PATTERN_NAMES
		PATTERN_NAMES = { name }
		local ok = startPattern(F)
		PATTERN_NAMES = saved
		return ok
	end
	return startPattern(F)
end

---------------------------------------------------------------------------------------------------------------------
-- skeleton AI, rocks
---------------------------------------------------------------------------------------------------------------------
local function stepSkeletons(F, dt: number)
	local arena = Layout.Pit.Arena
	local speed = (B.Skeletons.Speed or 11) * F.Def.Speed
	local t = now()
	for key, s in pairs(F.Skeletons) do
		if s.Removed then
			F.Skeletons[key] = nil
			continue
		end
		local _, ppos, d = nearestFighter(F, s.Pos)
		local goal = ppos and Vector3.new(ppos.X, floorY(), ppos.Z) or Layout.Boss.Spawn
		local delta = flatten(goal - s.Pos)
		-- separation from the rest of the pack
		local push = Vector3.zero
		for k2, o in pairs(F.Skeletons) do
			if k2 ~= key then
				local off = flatten(s.Pos - o.Pos)
				local m = off.Magnitude
				if m > .01 and m < 3.2 then
					push += off.Unit * (3.2 - m)
				end
			end
		end
		local step = Vector3.zero
		if delta.Magnitude > 2.4 then
			step = delta.Unit * math.min(delta.Magnitude - 2.2, speed * dt)
		end
		step += push * .5 * dt * 4
		local np = s.Pos + step
		np = Vector3.new(math.clamp(np.X, arena.X0 + 1.5, arena.X1 - 1.5), floorY(), math.clamp(np.Z, arena.Z0 + 1.5, arena.Z1 - 1.5))
		if delta.Magnitude > .2 then
			s.Yaw = math.atan2(-delta.X, -delta.Z)
		end
		s.Pos = np
		if s.Target then
			moveTarget(s.Target, CFrame.new(np + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, s.Yaw, 0))
		end
		-- bite (melee: knock() deals the Event HP damage)
		if ppos and d <= T.BiteRange and math.abs(ppos.Y - (floorY() + 3)) < 5 and t >= s.NextBite then
			s.NextBite = t + T.BiteCooldown / F.Def.Speed
			local pl = playersIn(s.Pos, T.BiteRange - .5, F)[1]
			if pl then
				knock(F, pl, s.Pos, T.BiteKnock, 10, T.BiteCurse, "Bite")
				-- BossEvent Bite {TargetId, UserId, Position}
				signal("zone", { Kind = "Bite", TargetId = idOf(s.Target), UserId = pl.UserId, Position = s.Pos })
			end
		end
	end
end

local function stepRocks(F)
	local t = now()
	local cfg = B.Rocks
	for key, r in pairs(F.Rocks) do
		if r.Removed then
			if r.ExplodeHazard then
				cancelHazards(F, { r.ExplodeHazard })
			end
			F.Rocks[key] = nil
		elseif not r.Landed and t >= r.LandAt then
			r.Landed = true
			r.ExplodeAt = t + (cfg.ExplodeAfter or 9)
			local hp = cfg.HP or 3 -- tier-normalized hits
			addTarget(F, { Kind = "CursedRock", Position = r.Pos + Vector3.new(0, 2.3, 0), Radius = 2.8, HP = hp, MaxHP = hp, Unit = 1,
				Color = Color3.fromRGB(70, 50, 90), Material = "Basalt", Size = Vector3.new(5, 4.6, 5), Name = "CURSED ROCK", NameRU = "ПРОКЛЯТЫЙ КАМЕНЬ",
				Seed = key, Ground = r.Pos, Attributes = { Key = key }, Data = { Key = key } }, r)
			-- BossEvent RockLand {Key, Position, TargetId, Hits, ExplodeAt, HazardId} (the landing hurts through its hazard)
			signal("zone", { Kind = "RockLand", Key = key, Position = r.Pos, TargetId = idOf(r.Target), Hits = {}, ExplodeAt = r.ExplodeAt,
				HazardId = r.HazardId })
		elseif r.Landed and r.ExplodeAt and not r.ExplodeHazard and t >= r.ExplodeAt - lead() - T.RockExplodeWarn then
			-- the explosion is telegraphed: an EventHP hazard that lands exactly at ExplodeAt (cancelled if it breaks first)
			local tele = teleFor(F, "RockExplode", T.RockExplodeWarn)
			local at = math.max(r.ExplodeAt, t + tele)
			r.ExplodeAt = at
			local ids = hazardWave(F, { { Shape = Patterns.Ground(r.Pos, T.RockExplodeRadius), Telegraph = tele, ImpactAt = at,
				Damage = BossMath.AttackDamage("RockExplode", F.Difficulty), Knock = { Power = T.RockKnock, Up = T.RockKnock * .55 }, Kind = "RockExplode",
				Source = "Gravekeeper" } }, T.RockExplodeCurse, "RockExplode")
			r.ExplodeHazard = ids[1] or false
		elseif r.Landed and r.ExplodeAt and t >= r.ExplodeAt then
			local tid = idOf(r.Target)
			if r.Target then
				removeTarget(F, r.Target, "Explode")
			end
			F.Rocks[key] = nil
			-- BossEvent RockExplode {Key, TargetId, Position, Hits, HazardId}
			signal("zone", { Kind = "RockExplode", Key = key, TargetId = tid, Position = r.Pos, Hits = {}, HazardId = r.ExplodeHazard or nil })
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- movement
---------------------------------------------------------------------------------------------------------------------
local function stepMove(F, dt: number)
	if F.Mode ~= "Idle" and F.Mode ~= "Walk" then
		return
	end
	local list = targetable(F)
	if #list == 0 then
		list = F.FighterList or {}
	end
	if #list == 0 then
		return
	end
	-- head for the middle of the fighters, inside the leash
	local sum = Vector3.zero
	local n = 0
	for _, pl in ipairs(list) do
		local p = rootPos(pl)
		if p then
			sum += flatten(p)
			n += 1
		end
	end
	if n == 0 then
		return
	end
	local centroid = sum / n
	local home = flatten(Layout.Boss.Spawn)
	local off = centroid - home
	if off.Magnitude > T.MoveRadius then
		off = off.Unit * T.MoveRadius
	end
	local goal = home + off
	local cur = flatten(F.Pos)
	local delta = goal - cur
	local moving = delta.Magnitude > 2
	if moving then
		local step = delta.Unit * math.min(delta.Magnitude, T.WalkSpeed * F.Def.Speed * dt)
		local np = cur + step
		F.Pos = Vector3.new(np.X, floorY(), np.Z)
	end
	-- turn toward the nearest fighter
	local _, ppos = nearestFighter(F, F.Pos)
	if ppos then
		local want = yawTo(F, ppos)
		local diff = (want - F.Yaw + math.pi) % (2 * math.pi) - math.pi
		local maxTurn = T.TurnSpeed * F.Def.Speed * dt
		F.Yaw += math.clamp(diff, -maxTurn, maxTurn)
	end
	local mode = moving and "Walk" or "Idle"
	if mode ~= F.Mode then
		setMode(F, mode)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- rewards
---------------------------------------------------------------------------------------------------------------------
local function pickDog(): any
	local rows = {}
	for _, id in ipairs(B.EventDogs or {}) do
		local def = Config.Dogs.Defs[id]
		local rank = def and def.Rank or 4
		table.insert(rows, { Kind = "Dog", Id = id, Rank = rank, Name = def and def.Name or id, Weight = rank >= 5 and ((B.DogWeights or {}).Rank5 or 1) or ((B.DogWeights or {}).Normal or 3),
			Rarity = Shared.Rarity(rank) })
	end
	if #rows == 0 then
		return nil
	end
	local row = Shared.Weighted(rows, function()
		return Boss.Rand()
	end)
	local out = table.clone(row)
	out.Weight = nil
	return out
end

-- one reward plan per contributor (pure: also used by the tests). Finale = this full-reward fighter won the difficulty V
-- finale (finale extras of Chapter II); a failed finale pays the normal difficulty V reward.
function Boss.RewardPlan(F, outcome: string)
	local total = 0
	local contributors = 0
	for _, dmg in pairs(F.Score) do
		total += dmg
		if dmg > 0 then
			contributors += 1
		end
	end
	local plans = {}
	if total <= 0 then
		return plans
	end
	local d = F.Def
	local ranked = {}
	for uid, sc in pairs(F.Score) do
		if sc > 0 then
			table.insert(ranked, { UserId = uid, Damage = F.Damage[uid] or 0, Score = sc })
		end
	end
	table.sort(ranked, function(a, b)
		return a.Score > b.Score
	end)
	for rank, row in ipairs(ranked) do
		local share = row.Score / total
		local rel = share * contributors
		local R = B.Reward or {}
		local perf = math.clamp((R.PerfBase or .35) + (R.PerfSlope or .65) * rel, 0, 1)
		local full = outcome == "Defeated" and share >= (B.MinContribution or .03)
		local plan = { UserId = row.UserId, Damage = row.Damage, Share = share, Rank = rank, Full = full, Outcome = outcome, Perf = perf,
			Difficulty = F.Difficulty, Finale = full and F.FinaleWon == true, FinaleRun = F.Finale ~= nil or nil }
		if full then
			plan.Candy = math.floor(d.Candy[1] + (d.Candy[2] - d.Candy[1]) * perf + .5)
			plan.Bones = math.floor((R.Bones or 40) * d.Reward * (.5 + .5 * perf) + .5)
			plan.XP = math.floor((R.XP or 25) * d.Reward + .5)
			local dogBase = R.DogPerfBase or .6
			if Boss.Rand() < (d.DogChance or 0) * (dogBase + (1 - dogBase) * perf) then
				plan.Dog = pickDog()
			end
			if d.CursedBlock and Boss.Rand() < d.CursedBlock then
				plan.Cursed = true
			end
			if d.EclipseChance and Boss.Rand() < d.EclipseChance then
				plan.Eclipse = true
			end
			plan.Unlock = math.min(#B.Difficulties, F.Difficulty + 1)
		else
			-- consolation: escaped boss, or a contribution below MinContribution
			local cons = R.Consolation or {}
			local scale = outcome == "Defeated" and (cons.Defeated or .5) or (cons.Escaped or .35)
			plan.Candy = math.max(cons.MinCandy or 3, math.floor(d.Candy[1] * scale * (.5 + .5 * perf) + .5))
			plan.Bones = math.floor((cons.Bones or 10) * d.Reward + .5)
			plan.XP = math.floor((cons.XP or 8) * d.Reward + .5)
		end
		table.insert(plans, plan)
	end
	return plans
end

-- Rewards are never lost silently and never paid twice: every contributor's BossReward transaction is retried with
-- backoff (T.RewardRetry) under one server receipt per fight + player ("hw-boss:<fight>:<userId>"):
--   * an OPEN outcome (an error saying "pending": a durable transaction may have committed its journal) freezes the plan
--     for good: the same receipt AND the same rows (so the same transaction path) on every later try, until it resolves
--     to that commit;
--   * only errors raised before anything is written (supply reservation, a busy lock / profile save), and only while no
--     try of this plan was ever "pending", move on to a fresh receipt suffix ("#n"); a failing event-dog supply (or a
--     third such failure) then pays the dog as its candy value; any other error keeps the receipt (a profile still
--     loading never reached the transaction).
-- The Chapter II part (Chapter2.BossReward) follows the Chapter I part under its own fixed receipt
-- ("hw-boss2:<fight>:<userId>"), so a retry never pays it twice either.
-- Unpaid rewards are parked in Boss.Pending[userId][fightId] (one slot per fight) and retried when the player (re)joins
-- (PlayerAdded), or, while they are in the server (also under a new Player object after a quick rejoin), after a delay.
-- Contributors who already left when the fight ends are parked straight away.
Boss.Pending = {} -- [userId] = {[fightId] = {Plan, Busy}}
Boss.Wait = function(seconds: number)
	task.wait(seconds)
end
Boss.Later = function(seconds: number, fn, ...)
	task.delay(seconds, fn, ...)
end
local PARK_DELAY, PARK_REJOIN_DELAY, PARK_ROUNDS = 90, 10, 6

-- errors that happen before any write (no journal, no profile change): a fresh receipt cannot pay twice
local function beforeWrite(err: string): boolean
	local e = string.lower(err)
	return string.find(e, "supply reservation", 1, true) ~= nil or string.find(e, "busy", 1, true) ~= nil
end

local function livePlayer(uid: number): Player?
	return playerOf(uid)
end

local function unpark(uid: number, fightId: string)
	local list = Boss.Pending[uid]
	if list then
		list[fightId] = nil
		if next(list) == nil then
			Boss.Pending[uid] = nil
		end
	end
end

local function park(uid: number, fightId: string, plan, from: Player?)
	local list = Boss.Pending[uid] or {}
	Boss.Pending[uid] = list
	list[fightId] = { Plan = plan }
	-- still / again in this server: retry on that live Player object instead of waiting for a future PlayerAdded
	local live = livePlayer(uid)
	plan.Rounds = (plan.Rounds or 0) + 1
	if live and plan.Rounds <= PARK_ROUNDS then
		Boss.Later(live == from and PARK_DELAY or PARK_REJOIN_DELAY, Boss.ResumePending, live)
	end
end
Boss.Park = park

local function tryGrant(player: Player, plan, receipt: string)
	local rows = {}
	if plan.Dog and not plan.DogAsCandy then
		table.insert(rows, plan.Dog)
	end
	return core.Transact(player, "BossReward", function(_p, h, ctx)
		local out = { Rewards = {} }
		out.Candy = ctx.Candy(plan.Candy or 0, "Boss", { NoCap = true })
		out.Bones = ctx.Bones(plan.Bones or 0)
		ctx.XP(plan.XP or 0)
		out.XP = plan.XP or 0
		if plan.Dog and plan.DogAsCandy then
			local d = plan.Dog
			table.insert(out.Rewards, { Kind = "Candy", Id = d.Id, Name = d.Name, Rank = d.Rank, Rarity = d.Rarity, Converted = true,
				Amount = ctx.Candy(Config.Rewards.Conversion.DogCandyPerRank * (d.Rank or 2), "Dog", { NoMult = true, NoCap = true }) })
		elseif plan.Dog then
			table.insert(out.Rewards, ctx.Reward(plan.Dog))
		end
		if plan.Cursed then
			table.insert(out.Rewards, ctx.Reward({ Kind = "Block", Id = "Cursed Pumpkin", Amount = 1, Name = "CURSED PUMPKIN", Rank = 5, Rarity = "Mythic" }))
		end
		if plan.Eclipse then
			table.insert(out.Rewards, ctx.Reward({ Kind = "Mutation", Id = "ECLIPSED", Name = "ECLIPSED FIND", Rank = 6, Rarity = "Secret" }))
		end
		if plan.Full then
			h.Boss.Kills += 1
			h.Boss.Best = math.max(h.Boss.Best, plan.Difficulty)
			if plan.Unlock and plan.Unlock > h.Boss.Unlocked then
				h.Boss.Unlocked = plan.Unlock
				out.Unlocked = plan.Unlock
			end
		end
		ctx.Relief("Objective")
		return out
	end, { Receipt = receipt, Rows = rows, Refresh = true })
end

-- does this plan carry a Chapter II part (Bell Shards / first-clear keys of III-V, the finale rows)?
local function needsChapter2(plan): boolean
	if not plan.Full then
		return false
	end
	local br = C2Cfg.BossRewards or {}
	local d = plan.Difficulty
	return plan.Finale == true or (br.Shards and br.Shards[d] ~= nil) or (br.FirstClearKeys and br.FirstClearKeys[d] ~= nil) or false
end

-- server-wide banners of a Chapter II boss reward (§24.4): the player's first finale clear, a Mythic / the Secret dog
local function announce(player: Player, res: any)
	if not core or type(res) ~= "table" then
		return
	end
	if res.FinaleFirst == true then
		core.Signal("all", "C2Announce", { Kind = "FinaleClear", Source = "Finale", Name = player.DisplayName, UserId = player.UserId })
	end
	for _, row in ipairs(type(res.Rewards) == "table" and res.Rewards or {}) do
		if type(row) == "table" and row.Kind == "Dog" and not row.Converted and type(row.Id) == "string" then
			local def = C2Cfg.Dogs and C2Cfg.Dogs.Defs and C2Cfg.Dogs.Defs[row.Id]
			local rank = def and def.Rank or 0
			if rank >= 6 then
				core.Signal("all", "C2Announce", { Kind = "HollowKing", Source = "Finale", Name = player.DisplayName, UserId = player.UserId, DogId = row.Id })
			elseif rank >= 5 then
				core.Signal("all", "C2Announce", { Kind = "Mythic", Source = "Finale", Name = player.DisplayName, UserId = player.UserId, DogId = row.Id })
			end
		end
	end
end

-- the Chapter II part -> true when done (paid, or this player is not a Chapter II player), false = park and retry later
local function grantChapter2(fightId: string, player: Player, plan): boolean
	local C2 = modules and modules.Chapter2
	if type(C2) ~= "table" or type(C2.BossReward) ~= "function" then
		return true
	end
	if type(C2.Enabled) == "function" and not C2.Enabled() then
		return true -- Chapter II switched off: nothing to pay (the player data waits)
	end
	local receipt = "hw-boss2:" .. tostring(fightId) .. ":" .. player.UserId
	local delays = T.RewardRetry or {}
	plan.C2Tries = 0
	while true do
		local latched = player:GetAttribute("HalloweenChapter1Complete")
		if latched == false then
			return true -- Chapter I not finished: no Chapter II reward (not an error)
		end
		local err = "Chapter I state still loading"
		if latched == true then
			local okCall, ok, res = pcall(C2.BossReward, player, plan.Difficulty, { Finale = plan.Finale == true, Receipt = receipt })
			if okCall and ok then
				res = type(res) == "table" and res or {}
				-- BossEvent RewardChapter2 {Difficulty, Finale, FinaleFirst, Rewards = {ctx.C2Reward outs}}
				signal(player, { Kind = "RewardChapter2", Difficulty = plan.Difficulty, Finale = plan.Finale == true, FinaleFirst = res.FinaleFirst == true,
					Rewards = res.Rewards })
				announce(player, res)
				return true
			end
			err = tostring(if okCall then res else ok)
			if err == "Finish Chapter I first" or err == "Chapter II is closed" then
				return true
			end
		end
		plan.C2Tries += 1
		warn(string.format("Halloween Boss: Chapter II reward for %s failed (try %d): %s", player.Name, plan.C2Tries, err))
		local delay = delays[plan.C2Tries]
		if not delay or not player.Parent then
			return false
		end
		Boss.Wait(delay)
	end
end

local function grant(fightId: string, player: Player, plan): boolean
	local uid = player.UserId
	local base = "hw-boss:" .. tostring(fightId) .. ":" .. uid
	local delays = T.RewardRetry or {}
	plan.Tries, plan.Fresh = 0, plan.Fresh or 0
	while not plan.Paid do
		plan.Tries += 1
		local receipt = plan.Fresh > 0 and (base .. "#" .. plan.Fresh) or base
		local okCall, ok, res = pcall(tryGrant, player, plan, receipt)
		if okCall and ok then
			plan.Paid = true
			res = type(res) == "table" and res or {}
			-- BossEvent Reward {Outcome, Difficulty, Candy, Bones, XP, Rewards = {rows}, Share, Rank, Damage, Full, Unlocked, Finale,
			-- Chapter2 (a Chapter II reward follows: RewardChapter2)}
			signal(player, { Kind = "Reward", Outcome = plan.Outcome, Difficulty = plan.Difficulty, Candy = res.Candy, Bones = res.Bones,
				XP = res.XP, Rewards = res.Rewards, Share = plan.Share, Rank = plan.Rank, Damage = math.floor(plan.Damage), Full = plan.Full,
				Unlocked = res.Unlocked, Finale = plan.Finale or nil, FinaleRun = plan.FinaleRun, Chapter2 = needsChapter2(plan) or nil })
			break
		end
		local err = tostring(if okCall then res else ok)
		warn(string.format("Halloween Boss: reward for %s failed (try %d): %s", player.Name, plan.Tries, err))
		if not Shared.Enabled() then
			unpark(uid, fightId)
			return false
		end
		if string.find(string.lower(err), "pending", 1, true) then
			plan.Unknown = true -- may have committed: this receipt + these rows from now on
		elseif not plan.Unknown and beforeWrite(err) then
			plan.Fresh += 1
			if plan.Dog and (string.find(string.lower(err), "supply", 1, true) or plan.Fresh >= 3) then
				plan.DogAsCandy = true
			end
		end
		local delay = delays[plan.Tries]
		if delay then
			Boss.Wait(delay)
		end
		if not delay or not player.Parent then
			if not delay then
				warn("Halloween Boss: reward for " .. player.Name .. " parked after " .. plan.Tries .. " tries")
			end
			park(uid, fightId, plan, player)
			return false
		end
	end
	if needsChapter2(plan) and not plan.C2Done then
		if not grantChapter2(fightId, player, plan) then
			if player.Parent then
				warn("Halloween Boss: Chapter II reward for " .. player.Name .. " parked")
			end
			park(uid, fightId, plan, player)
			return false
		end
		plan.C2Done = true
	end
	unpark(uid, fightId)
	return true
end
Boss.Grant = grant

-- pay every reward parked for this player (PlayerAdded / a scheduled retry; the profile may still be loading: grant
-- retries); true when nothing is left
function Boss.ResumePending(player: Player): boolean
	local list = Boss.Pending[player.UserId]
	if not list or not player.Parent then
		return list == nil
	end
	for fightId, entry in pairs(table.clone(list)) do
		if not entry.Busy then
			entry.Busy = true
			grant(fightId, player, entry.Plan)
		end
	end
	return Boss.Pending[player.UserId] == nil
end

local function grantAll(F, outcome: string)
	for _, plan in ipairs(Boss.RewardPlan(F, outcome)) do
		local player = playerOf(plan.UserId)
		if player then
			task.spawn(grant, F.Id, player, plan)
		else
			-- left before the end: kept for their rejoin (PlayerAdded -> ResumePending)
			park(plan.UserId, F.Id, plan, nil)
		end
	end
end

local function topList(F, n: number)
	local list = {}
	for uid, dmg in pairs(F.Damage) do
		table.insert(list, { UserId = uid, Name = F.Names[uid] or "?", Damage = math.floor(dmg) })
	end
	table.sort(list, function(a, b)
		return a.Damage > b.Damage
	end)
	while #list > n do
		table.remove(list)
	end
	return list
end
Boss.TopList = topList

local function cleanupTargets(F)
	closeWeak(F)
	clearPlates(F)
	clearMounds(F)
	clearSkeletons(F, "End")
	clearRocks(F)
	for target in pairs(F.Targets) do
		removeTarget(F, target, "End")
	end
	if F.Shield then
		F.Shield = false
	end
end

local function finaleModule(): any
	local m = modules and modules.BossFinale
	if type(m) == "table" and type(m.Begin) == "function" then
		return m
	end
	return nil
end

finish = function(F, outcome: string, reason: string?)
	if F.Ended then
		return
	end
	F.Ended = true
	F.Outcome = outcome
	F.EndReason = reason
	cleanupTargets(F)
	cancelHazards(F)
	-- out of the combat zone: a wipe's downed players are bled out to the rim by EventHP first (zone cleanup at the end of
	-- the hold); everyone else gets up now
	leaveCombat(reason == "Wiped")
	F.Pattern = nil
	F.Attack = nil
	Boss.NextSummonAt = now() + (B.SummonCooldown or 240)
	F.State = outcome
	F.EndHoldUntil = now() + T.EndHold
	local fin = F.Finale and finaleModule()
	if fin and type(fin.OnFinish) == "function" then
		local ok, err = pcall(fin.OnFinish, F, outcome, reason)
		if not ok then
			warn("Halloween Boss: BossFinale.OnFinish failed: " .. tostring(err))
		end
	end
	if outcome == "Defeated" then
		if F.Finale then
			setMode(F, "Finale", T.EndHold)
		else
			setMode(F, "Death", 6)
		end
		-- BossEvent Defeated {Difficulty, Numeral, Top = {{UserId, Name, Damage}}, Position, Duration, Finale ("Victory" |
		-- "Fail": the difficulty V finale already played the boss's death)}
		signal("all", { Kind = "Defeated", Difficulty = F.Difficulty, Numeral = F.Def.Numeral, Top = topList(F, 5), Position = F.Pos,
			Duration = 6, Finale = F.Finale and (F.FinaleWon and "Victory" or "Fail") or nil, FinaleReason = F.Finale and reason or nil })
	else
		setMode(F, "Escape", 4)
		-- BossEvent Escaped {Reason = "Time"|"Empty"|"Disabled"|"Wiped", Position}
		signal("all", { Kind = "Escaped", Reason = reason or "Time", Position = F.Pos, Difficulty = F.Difficulty })
	end
	publish(F)
	bump()
	if reason ~= "Disabled" then
		grantAll(F, outcome)
	end
	if F.Reason == "Exorcism" and Config.Exorcism.ResetAfterBoss ~= false and modules and modules.Exorcism and reason ~= "Disabled" then
		pcall(modules.Exorcism.Reset)
	end
end

defeat = function(F, _player: Player?)
	finish(F, "Defeated")
end

-- the fight is over and its hold ran out: forget it
local function release(F)
	if Boss.Fight == F then
		Boss.Fight = nil
	end
	leaveCombat(false)
	local fin = finaleModule()
	if fin and type(fin.Reset) == "function" then
		pcall(fin.Reset)
	end
	publish(nil)
	bump()
	if rigRoot and rigRoot.Parent then
		rigRoot.CFrame = CFrame.new(Layout.Boss.Spawn + Vector3.new(0, -60, 0))
	end
end

function Boss.Abort(reason: string?)
	local F = Boss.Fight
	if not F then
		return
	end
	finish(F, "Escaped", reason or "Disabled")
	release(F)
end

-- EventHP: every fighter in the pit is downed. Handled on the next Step (never inside a listener).
onWipe = function(_players)
	local F = Boss.Fight
	if F and not F.Ended and F.State == "Fight" then
		F.WipePending = true
	end
end

-- reviving an ally in the pit counts as contribution
onRevive = function(_player: Player, by: Player?)
	local F = Boss.Fight
	if F and not F.Ended and by and by ~= _player then
		score(F, by, (tonumber(CB.ReviveScore) or .01) * F.MaxArmor)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Strike kind handlers
---------------------------------------------------------------------------------------------------------------------
-- DOGS DIG THE WEAK POINTS: the digger's best assigned yard dog (DigSpots.Team of the Runtime view: AssignedSlot ~= "")
-- digs beside them (client BossFX companion, from the StrikeBegin Extra) and adds Config.Boss.WeakPoints.DogPerRank per
-- dog rank (+ EventDog with an event dog in the team, capped at DogMax) to their weak-point hits. No dogs: no bonus.
function Boss.DogBonus(team: any): number
	local wp = B.WeakPoints or {}
	local best = type(team) == "table" and team.Best or nil
	if type(best) ~= "table" then
		return 0
	end
	local rank = math.clamp(math.floor(tonumber(best.Rank) or 1), 1, 6)
	local bonus = (wp.DogPerRank or .04) * rank + (team.HasEvent and (wp.EventDog or .1) or 0)
	return math.clamp(bonus, 0, wp.DogMax or .3)
end

-- the player's dig team for this fight (refreshed whenever they start digging a weak point)
local function dogTeam(F, player: Player, fresh: boolean?)
	F.DogTeams = F.DogTeams or {}
	local uid = player.UserId
	local cached = F.DogTeams[uid]
	if cached and not fresh then
		return cached
	end
	local team = nil
	local DS = modules and modules.DigSpots
	local Runtime = core and core.Runtime
	local view = Runtime and Runtime.Views and Runtime.Views[uid]
	if DS and type(DS.Team) == "function" and view ~= nil then
		local ok, res = pcall(DS.Team, view)
		team = (ok and type(res) == "table") and res or nil
	end
	cached = { Best = team and team.Best or nil, HasEvent = team ~= nil and team.HasEvent == true, Bonus = Boss.DogBonus(team) }
	F.DogTeams[uid] = cached
	return cached
end

local function onWeakBegin(player: Player, target: any)
	local F = Boss.Fight
	if not F or not entryOf(F, target) then
		return nil
	end
	local team = dogTeam(F, player, true)
	-- StrikeBegin Extra (to the digger): Companion = {Id, Asset, Variant, Rank} | nil, Event, DogBonus (0 .. DogMax),
	-- PerfectOnly (difficulty V: only Perfect hits land)
	return { Companion = team.Best, Event = team.HasEvent, DogBonus = team.Bonus, PerfectOnly = perfectOnly(F) or nil }
end

-- armor of one body hit before the soft cap (BossMath: curve, x3 weak, dog bonus, sync, WEAKENED, H15 on weak points)
local function hitArmor(F, player: Player, entry: any, hit: any, sync: number?): (number, any)
	local q, crit, raw = hitQuality(hit)
	if raw <= 0 then
		raw = damageOf(player) * (q == 2 and 1.5 or 1) * (crit and 2 or 1)
	end
	local weak = entry.Role == "Weak"
	local opts: { [string]: any } = { Weak = weak, WeakMult = (B.WeakPoints and B.WeakPoints.Mult) or CB.WeakMult or 3, Mechanic = weak,
		Weakened = (tonumber(type(hit) == "table" and hit.EventMult) or 1) < 1 - 1e-6, Sync = sync }
	if weak then
		opts.DogBonus = dogTeam(F, player).Bonus
		opts.H15 = hasDog(player, "Wolf")
	end
	if not scaled(F) then
		opts.K, opts.Exp = T.ArmorK, T.ArmorExp
	end
	return BossMath.ArmorDamage(raw, opts)
end
Boss.HitArmor = function(player, entry, hit, sync)
	return hitArmor(Boss.Fight, player, entry, hit, sync)
end

-- expected armor damage of a hit (Strike "Damage" function: what the HP panel / hit number shows, before the cap)
local function bodyDamage(player: Player, target: any, hit: any): number
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not entry then
		return 0
	end
	return (hitArmor(F, player, entry, hit))
end

local function onPlateHit(player: Player, target: any, hit: any)
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not F or not entry or entry.Removed then
		if type(hit) == "table" then
			hit.Applied = 0
		end
		return nil
	end
	local q, crit = hitQuality(hit)
	local weak = entry.Role == "Weak"
	local dogBonus = weak and dogTeam(F, player).Bonus or 0
	-- difficulty V: the weak points only take Perfect hits
	if weak and perfectOnly(F) and q ~= 2 then
		if type(hit) == "table" then
			hit.Applied = 0
		end
		-- BossEvent Hit {Damage = 0, Weak, NeedPerfect} (to the hitter: "PERFECT ONLY")
		signal(player, { Kind = "Hit", Damage = 0, Weak = true, Slot = entry.Slot, Crit = crit, Quality = q, NeedPerfect = true,
			Armor = math.max(0, math.ceil(F.Armor)), TargetId = idOf(target) })
		return { BossDamage = 0, Weak = true, NeedPerfect = true, Armor = math.max(0, math.ceil(F.Armor)) }
	end
	local armor = hitArmor(F, player, entry, hit)
	local synced = false
	if q == 2 and not invulnerable(F) then
		-- SYNC STRIKE: two players' Perfects on the boss within .5 s -> +50% for both (the partner's earlier hit gets its
		-- bonus now)
		F.Sync = F.Sync or BossMath.NewSync()
		local mult, retro = BossMath.SyncHit(F.Sync, player.UserId, now(), armor)
		if mult > 1 then
			synced = true
			armor = hitArmor(F, player, entry, hit, mult)
		end
		for _, r in ipairs(retro) do
			local partner = playerOf(r.UserId)
			if partner and r.Bonus > 0 then
				local got = deal(F, partner, r.Bonus, "Sync", {})
				if got > 0 then
					-- BossEvent Hit {Damage, Sync = true, Retro = true} (to the partner)
					signal(partner, { Kind = "Hit", Damage = math.floor(got + .5), Sync = true, Retro = true, Armor = math.max(0, math.ceil(F.Armor)) })
				end
			end
		end
	end
	local applied = deal(F, player, armor, weak and "Weak" or "Plate", { Mechanic = weak, Perfect = q == 2, Good = q ~= 2 })
	entry.LastPerfect = q == 2 -- (the shatter bonus follows the quality of the breaking hit)
	-- the plate loses exactly the armor that landed (weak points have 1e9 HP)
	if type(hit) == "table" then
		hit.Applied = applied
	end
	-- BossEvent Hit {Damage, Weak, Slot, Crit, Quality, Armor, DogBonus, Sync} (to the hitter: big armor-damage number; DogBonus
	-- > 0 = their dog dug with them)
	signal(player, { Kind = "Hit", Damage = math.floor(applied + .5), Weak = weak, Slot = entry.Slot, Crit = crit, Quality = q,
		Armor = math.max(0, math.ceil(F.Armor)), TargetId = idOf(target), DogBonus = dogBonus > 0 and dogBonus or nil, Sync = synced or nil })
	return { BossDamage = math.floor(applied + .5), Weak = weak, Armor = math.max(0, math.ceil(F.Armor)),
		DogBonus = dogBonus > 0 and dogBonus or nil, Sync = synced or nil }
end

-- a plate whose integrity ran out shatters (called from Step, outside Strike callbacks)
local function breakPlate(F, slot: string, player: Player?)
	local entry = F.Plates[slot]
	if not entry or not entry.Target then
		return
	end
	if player == false then
		player = nil
	end
	local target = entry.Target
	local tid = idOf(target)
	removeTarget(F, target, "Broke")
	entry.Removed = nil
	entry.Target = nil
	entry.RegrowAt = now() + T.PlateRegrow
	-- the shatter bonus is plate damage (soft-capped like the hits); a Perfect breaking hit keeps its Perfect bonus
	local bonus = deal(F, player, T.PlateBreakBonus * F.MaxArmor, "PlateBreak", { Perfect = entry.LastPerfect == true,
		Good = entry.LastPerfect == false })
	setAttr("Plates", plateMask(F))
	setAttr("PlateWear", plateWear(F))
	bump()
	-- BossEvent PlateBreak {Slot, TargetId, UserId, Bonus}
	signal("zone", { Kind = "PlateBreak", Slot = slot, TargetId = tid, UserId = player and player.UserId or 0, Bonus = math.floor(bonus) })
end
Boss.BreakPlate = function(slot, player)
	return Boss.Fight and breakPlate(Boss.Fight, slot, player)
end

-- Strike broke a plate (its integrity ran out): shatter it on the next step (bonus damage, regrow timer, signal)
local function onPlateBreak(player: Player?, target: any, _info: any)
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not F or not entry or entry.Removed or entry.Role ~= "Plate" then
		return
	end
	F.BreakQueue = F.BreakQueue or {}
	F.BreakQueue[entry.Slot] = player or false
end

-- fighters only: a player outside the pit (the rim, the bell) cannot hit anything of the boss
local function inPit(player: Player): boolean
	if CB.InPitOnly == false then
		return true
	end
	local pos = rootPos(player)
	return pos ~= nil and isFighterPos(pos)
end
Boss.InPit = inPit

local OUTSIDE = "Climb down into the pit to fight the Gravekeeper"

local function canHitBody(player: Player, target: any)
	local F = Boss.Fight
	if not F or not entryOf(F, target) then
		return false, "Too late!"
	end
	if not inPit(player) then
		return false, OUTSIDE
	end
	local inv, why = invulnerable(F)
	if inv then
		return false, why
	end
	return true
end

local function onMoundHit(player: Player, target: any, _hit: any)
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not entry or entry.Removed then
		return nil
	end
	-- BossEvent MoundHit {TargetId, Position, Real, UserId}: the real one rumbles deep, fakes rattle with bones
	signal("zone", { Kind = "MoundHit", TargetId = idOf(target), Position = entry.Pos, Real = entry.Real, UserId = player and player.UserId or 0 })
	return { Real = entry.Real }
end

local function onMoundBreak(player: Player?, target: any, info: any)
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not F or not entry or entry.Removed or F.SubPhase ~= "Underground" then
		return
	end
	F.Targets[target] = nil
	entry.Target = nil
	entry.Removed = true
	-- every digger of this mound shares the search credit
	if type(info) == "table" and type(info.Contributors) == "table" then
		for _, c in pairs(info.Contributors) do
			if type(c) == "table" and c.Player and c.Player ~= player then
				score(F, c.Player, T.MoundScore * F.MaxArmor)
			end
		end
	end
	if entry.Real then
		erupt(F, true, player)
	else
		-- skeleton hands burst out of the fake mound: a short telegraphed hazard around it
		local tele = teleFor(F, "FakeMound", .9)
		local at = now() + lead() + tele
		local hazardId = attackHazard(F, "FakeMound", Hazards.Circle(Vector3.new(entry.Pos.X, floorY(), entry.Pos.Z), T.FakeRadius), tele, at,
			T.FakeKnock, 26, (B.Burrow and B.Burrow.FakeCurse) or 12)
		F.Mounds[entry.Index] = nil
		score(F, player, T.MoundScore * F.MaxArmor)
		-- BossEvent FakeMound {TargetId, Position, UserId, Hits, HazardId, ImpactAt}
		signal("zone", { Kind = "FakeMound", TargetId = idOf(target), Position = entry.Pos, UserId = player and player.UserId or 0, Hits = {},
			HazardId = hazardId, ImpactAt = at })
	end
end

local function onSkeletonBreak(player: Player?, target: any, _info: any)
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not F or not entry or entry.Removed then
		return
	end
	F.Targets[target] = nil
	entry.Removed = true
	F.Skeletons[entry.Key] = nil
	F.ShieldKills += 1
	score(F, player, T.SkeletonScore * F.MaxArmor)
	-- BossEvent SkeletonDown {TargetId, Position, UserId, Left}
	signal("zone", { Kind = "SkeletonDown", TargetId = idOf(target), Position = entry.Pos, UserId = player and player.UserId or 0,
		Left = math.max(0, F.ShieldNeed - F.ShieldKills) })
	if F.Shield then
		setAttr("ShieldLeft", math.max(0, F.ShieldNeed - F.ShieldKills))
		if F.ShieldKills >= F.ShieldNeed then
			setShield(F, false)
			clearSkeletons(F, "Collapse")
			setMode(F, "Stagger", 3)
			F.NextPackAt = now() + T.PackRepeat
			F.NextAttackAt = math.max(F.NextAttackAt or 0, now() + 4)
		end
	end
end

local function onRockBreak(player: Player?, target: any, _info: any)
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not F or not entry or entry.Removed then
		return
	end
	F.Targets[target] = nil
	entry.Removed = true
	F.Rocks[entry.Key] = nil
	if entry.ExplodeHazard then
		cancelHazards(F, { entry.ExplodeHazard })
	end
	local amount = ((B.Rocks and B.Rocks.Damage) or .03) * F.MaxArmor
	local applied = deal(F, player, amount, "Shard", { Mechanic = true, Force = true })
	-- BossEvent RockShard {TargetId, Key, From, UserId, Damage}
	signal("zone", { Kind = "RockShard", TargetId = idOf(target), Key = entry.Key, From = entry.Pos, UserId = player and player.UserId or 0,
		Damage = math.floor(applied) })
end

local function canHitAlways(player: Player, target: any)
	local F = Boss.Fight
	if not F or not entryOf(F, target) then
		return false, "Too late!"
	end
	if not inPit(player) then
		return false, OUTSIDE
	end
	return true
end

function Boss.RegisterStrike()
	local Strike = strike()
	if Boss.StrikeReady or not (Strike and type(Strike.Register) == "function") then
		return Boss.StrikeReady == true
	end
	local ok, err = pcall(function()
		Strike.Register("BossPlate", { Range = 24, Verb = "BREAK", Damage = bodyDamage, OnHit = onPlateHit, OnBreak = onPlateBreak,
			CanHit = canHitBody, Activity = "BossDamage", EventMult = true })
		Strike.Register("BossWeak", { Range = 22, Verb = "DIG", Damage = bodyDamage, OnBegin = onWeakBegin, OnHit = onPlateHit, CanHit = canHitBody,
			Activity = "BossDamage", EventMult = true })
		Strike.Register("BossMound", { Range = 14, Verb = "DIG", Damage = "Power", OnHit = onMoundHit, OnBreak = onMoundBreak, CanHit = canHitAlways,
			EventMult = "Apply" })
		Strike.Register("BossSkeleton", { Range = 13, Verb = "STRIKE", Damage = "Power", OnBreak = onSkeletonBreak, CanHit = canHitAlways,
			EventMult = "Apply" })
		Strike.Register("CursedRock", { Range = 14, Verb = "BREAK", Damage = "Power", OnBreak = onRockBreak, CanHit = canHitAlways,
			EventMult = "Apply" })
	end)
	if not ok then
		warn("Halloween Boss: Strike.Register failed: " .. tostring(err))
		return false
	end
	Boss.StrikeReady = true
	return true
end
Boss.Handlers = { PlateHit = onPlateHit, PlateBreak = onPlateBreak, MoundHit = onMoundHit, MoundBreak = onMoundBreak,
	SkeletonBreak = onSkeletonBreak, RockBreak = onRockBreak, CanHitBody = canHitBody, CanHitAlways = canHitAlways, WeakBegin = onWeakBegin,
	BodyDamage = bodyDamage }

---------------------------------------------------------------------------------------------------------------------
-- summon
---------------------------------------------------------------------------------------------------------------------
function Boss.Summon(difficulty: number, reason: string?, player: Player?): (boolean, string?)
	reason = reason or "Bell"
	if not Shared.Enabled() then
		return false, "The Night of the Buried Moon has ended"
	end
	if not BossModels then
		return false, "The Gravekeeper is not here this season"
	end
	if not Boss.StrikeReady and not Boss.RegisterStrike() then
		return false, "The Gravekeeper cannot be fought right now"
	end
	if Boss.Fight then
		return false, "The Gravekeeper is already awake"
	end
	local d = math.floor(tonumber(difficulty) or 0)
	if d < 1 or d > #B.Difficulties then
		return false, "Unknown difficulty"
	end
	local t = now()
	if reason == "Bell" then
		if not player then
			return false, "Ring the Grave Bell"
		end
		local unlocked = tonumber(player:GetAttribute("HwBossUnlocked")) or 1
		if d > unlocked then
			return false, "Defeat the previous difficulty first"
		end
		if t < Boss.NextSummonAt then
			return false, string.format("The Gravekeeper rests for %d more seconds", math.ceil(Boss.NextSummonAt - t))
		end
	end
	local def = diffDef(d)
	local F = {
		Id = (core and core.NewId and core.NewId()) or tostring(math.floor(t * 1000)), Difficulty = d, Def = def, Reason = reason,
		SummonerId = player and player.UserId or 0, StartedAt = t, EndsAt = t + (B.TimeLimit or 300) + T.RiseSeconds, State = "Rising",
		Phase = 1, Mode = "Rise", ModeAt = t, ModeUntil = t + T.RiseSeconds, Armor = 0, MaxArmor = 0, Fighters = 0,
		Pos = Vector3.new(Layout.Boss.Spawn.X, floorY(), Layout.Boss.Spawn.Z), Yaw = 0, Plates = {}, Weak = {}, WeakUntil = 0,
		Mounds = {}, Skeletons = {}, Rocks = {}, RockWave = 0, BurrowUntil = 0, Shield = false, ShieldNeed = 0, ShieldKills = 0,
		Targets = {}, TargetIds = {}, Damage = {}, Score = {}, Names = {}, SoulFrac = {}, NextAttackAt = t + T.RiseSeconds + 3,
		EmptyGrace = reason == "Exorcism" and T.ExorcismGrace or T.EmptyGrace, EmptySince = nil, SubPhase = "Rise",
		Caps = {}, Sync = BossMath.NewSync(), CapPerSecond = BossMath.CapPerSecond(BossMath.MaxArmorBase(d)), Hazards = {},
		NextPatternAt = t + T.RiseSeconds + ((type(CB.Endgame) == "table" and tonumber(CB.Endgame.First)) or 16),
	}
	local facingYaw = math.atan2(-Layout.Boss.Facing.X, -Layout.Boss.Facing.Z)
	F.Yaw = facingYaw
	F.MaxArmor = maxArmorFor(F, 1)
	F.Armor = F.MaxArmor
	Boss.Fight = F
	updateFighters(F, true)
	F.Armor = F.MaxArmor
	publish(F)
	moveRoot(F)
	bump()
	-- BossEvent Rise {Difficulty, Numeral, Name, Reason, SummonerId, SummonerName, Position, Duration, FightId, Endgame,
	-- PerfectOnly, Finale (difficulty V with the finale on)}
	signal("all", { Kind = "Rise", Difficulty = d, Numeral = def.Numeral, Name = def.Name, Reason = reason, SummonerId = F.SummonerId,
		SummonerName = player and player.Name or "", Position = F.Pos, Duration = T.RiseSeconds, FightId = F.Id, Endgame = endgame(F) or nil,
		PerfectOnly = perfectOnly(F) or nil,
		Finale = (d == 5 and reason ~= "Exorcism" and Shared.BossFinaleEnabled() and finaleModule() ~= nil) or nil })
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- the difficulty V finale handoff (DESIGN §11: keep F alive, never append Config.Boss.Phases)
---------------------------------------------------------------------------------------------------------------------
local function finaleOn(F): boolean
	return F.Difficulty == 5 and F.Reason ~= "Exorcism" and Shared.BossFinaleEnabled() and finaleModule() ~= nil
end

local function beginFinale(F): boolean
	local fin = finaleModule()
	if not fin then
		return false
	end
	-- the fight below the finale stops: every target, hazard, attack and pattern goes (the boss "dies")
	cleanupTargets(F)
	cancelHazards(F)
	F.Attack, F.Pattern = nil, nil
	F.Armor = 0
	setAttr("Armor", 0)
	setAttr("Attack", "")
	setAttr("Enraged", false)
	setMode(F, "Finale")
	local ok, err = pcall(fin.Begin, F)
	if not ok then
		warn("Halloween Boss: BossFinale.Begin failed: " .. tostring(err))
		F.Finale = nil
		return false
	end
	publish(F)
	return F.Finale ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- step (10 Hz from Heartbeat; the tests call it directly)
---------------------------------------------------------------------------------------------------------------------
function Boss.Step(dt: number)
	local F = Boss.Fight
	if not F then
		return
	end
	local t = now()
	if not Shared.Enabled() then
		Boss.Abort("Disabled")
		return
	end
	if F.Ended then
		if t >= (F.EndHoldUntil or 0) then
			release(F)
		end
		return
	end
	-- deferred transformations (set by damage inside Strike callbacks)
	if F.BreakQueue and not F.Finale then
		local q = F.BreakQueue
		F.BreakQueue = nil
		for slot, pl in pairs(q) do
			breakPlate(F, slot, pl)
		end
	end
	if F.PendingDefeat then
		F.PendingDefeat = nil
		if finaleOn(F) and beginFinale(F) then
			return
		end
		defeat(F, nil)
		return
	end
	if F.PendingPhase then
		local p = F.PendingPhase
		F.PendingPhase = nil
		enterPhase(F, p)
	end
	-- fighters: combat zone every step, the live armor scaling every second
	local rescale = t - (F.FightersAt or 0) >= 1
	if rescale then
		F.FightersAt = t
	end
	updateFighters(F, rescale and not F.Finale)
	if F.Finale then
		F.Fighters = #(F.FighterList or {})
		setAttr("Fighters", F.Fighters)
	end
	-- the whole team downed (EventHP OnWipe)
	if F.WipePending then
		F.WipePending = nil
		local fin = F.Finale and finaleModule()
		if fin then
			pcall(fin.Fail, F, "Wipe")
		else
			-- BossEvent Wiped {} (then the usual Escaped {Reason = "Wiped"})
			signal("all", { Kind = "Wiped", Difficulty = F.Difficulty, Position = F.Pos })
			finish(F, "Escaped", "Wiped")
		end
		if F.Ended then
			return
		end
	end
	-- nobody left in the arena -> it leaves
	if F.Fighters == 0 then
		F.EmptySince = F.EmptySince or t
		if t - F.EmptySince >= F.EmptyGrace then
			local fin = F.Finale and finaleModule()
			if fin then
				pcall(fin.Fail, F, "Empty")
			end
			if not F.Ended then
				finish(F, "Escaped", "Empty")
			end
			return
		end
	else
		if F.State == "Fight" then
			F.EmptyGrace = T.EmptyGrace -- the long exorcism grace only covers the walk to the pit
		end
		F.EmptySince = nil
	end
	-- the finale owns the fight from the false victory on (its own timers and time limit)
	if F.Finale then
		local fin = finaleModule()
		if fin then
			local ok, err = pcall(fin.Step, F, dt)
			if not ok then
				warn("Halloween Boss: BossFinale.Step failed: " .. tostring(err))
			end
		end
		if not F.Ended and (not fin or t >= F.EndsAt) then
			-- backstop (module gone / its clock stuck): the normal difficulty V reward
			if fin then
				pcall(fin.Fail, F, "Time")
			end
			if not F.Ended then
				finish(F, "Defeated", "FinaleFail")
			end
		end
		return
	end
	-- time limit -> escape
	if t >= F.EndsAt then
		finish(F, "Escaped", "Time")
		return
	end

	local timed = F.ModeUntil > 0 and t >= F.ModeUntil
	-- intro
	if F.Mode == "Rise" then
		if timed then
			F.State = "Fight"
			setAttr("State", "Fight")
			F.SubPhase = "Fight"
			setMode(F, "Idle")
			spawnPlates(F)
		end
		moveRoot(F)
		return
	end

	-- timed modes
	if timed then
		if F.Mode == "Windup" then
			resolveAttack(F)
		elseif F.Mode == "Burrow" then
			spawnMounds(F)
		elseif F.Mode == "Erupt" then
			spawnPlates(F)
			if F.PendingRoar or F.Phase ~= 2 then
				-- the eruption pushed it into the next phase: roar, then that phase begins
				F.PendingRoar = nil
				setMode(F, "Roar", 2.6)
			else
				F.SubPhase = "Surface"
				setMode(F, "Idle")
				F.SurfaceUntil = t + T.SurfaceSeconds
			end
		elseif F.Mode == "Roar" then
			setMode(F, "Idle")
			spawnPlates(F)
			if F.Phase == 3 and F.SubPhase == "Summoning" then
				F.SubPhase = "Pack"
				spawnPack(F)
			end
		elseif F.Mode == "Enrage" or F.Mode == "Stagger" then
			setMode(F, "Idle")
			spawnPlates(F)
		end
	end

	-- phase 2: underground timeout (telegraphed eruption) / surface window
	if F.Phase == 2 then
		if F.SubPhase == "Underground" and F.EruptHazard == nil and t >= F.BurrowUntil - lead() - teleFor(F, "Erupt", 1.3) then
			warnEruption(F)
		end
		if F.SubPhase == "Underground" and t >= F.BurrowUntil then
			erupt(F, false, nil)
		elseif F.SubPhase == "Surface" and F.SurfaceUntil and t >= F.SurfaceUntil and F.Mode ~= "Windup" then
			F.SurfaceUntil = nil
			startBurrow(F)
		end
	end
	-- phase 3: next pack
	if F.Phase == 3 and F.SubPhase == "Pack" and not F.Shield and t >= (F.NextPackAt or math.huge) and VULNERABLE[F.Mode] and F.Mode ~= "Windup" then
		F.SubPhase = "Summoning"
		setMode(F, "Roar", 2.2)
	end
	-- phase 4: rock waves (capped per phase on III / IV, unlimited on V; never on top of a pattern)
	if F.Phase == 4 and F.Mode ~= "Roar" and t >= (F.NextWaveAt or math.huge) and not patternRunning(F) then
		local cap = rockCap(F)
		if cap > 0 and F.RockWave >= cap then
			F.NextWaveAt = math.huge
		else
			rockWave(F)
		end
	end
	-- phase 5: weak points
	if F.Phase == 5 then
		if F.WeakUntil > 0 and t >= F.WeakUntil then
			closeWeak(F)
			F.NextWeakAt = t + T.WeakCycle / F.Def.Speed
		elseif F.WeakUntil == 0 and t >= (F.NextWeakAt or math.huge) and VULNERABLE[F.Mode] then
			openWeak(F)
		end
	end

	-- plate wear (cracks on the client) + regrowth
	setAttr("PlateWear", plateWear(F))
	for slot, pl in pairs(F.Plates) do
		if not pl.Target and pl.RegrowAt and t >= pl.RegrowAt and VULNERABLE[F.Mode] and F.SubPhase ~= "Underground" then
			pl.RegrowAt = nil
			F.Plates[slot] = nil
			spawnPlate(F, slot)
			setAttr("Plates", plateMask(F))
			-- BossEvent PlateRegrow {Slot}
			signal("zone", { Kind = "PlateRegrow", Slot = slot })
		end
	end

	-- the endgame pattern ended
	if F.Pattern and t >= F.Pattern.Until then
		F.Pattern = nil
		setAttr("Pattern", "")
		setAttr("PatternUntil", 0)
	end
	-- attacks + endgame patterns + movement while on the surface
	local surfaced = F.SubPhase ~= "Underground" and F.Mode ~= "Burrow"
	local ready = surfaced and (F.Mode == "Idle" or F.Mode == "Walk") and F.Fighters > 0 and not patternRunning(F)
	if ready and endgame(F) and t >= (F.NextPatternAt or math.huge) and not (F.Phase == 4 and (F.NextWaveAt or 0) - t < 2.5) then
		if not startPattern(F) then
			F.NextPatternAt = t + 3
		end
	elseif ready and t >= (F.NextAttackAt or 0) then
		startAttack(F)
	end
	if surfaced then
		stepMove(F, dt)
	end
	stepSkeletons(F, dt)
	stepRocks(F)
	if not F.Ended then
		moveRoot(F)
		syncBodyTargets(F)
	end
end

function Boss.Status(player: Player?)
	local F = Boss.Fight
	if not F then
		return { Active = false, NextSummonAt = Boss.NextSummonAt }
	end
	local mine = player and F.Damage[player.UserId] or 0
	local rank = 0
	if mine > 0 then
		rank = 1
		for _, dmg in pairs(F.Damage) do
			if dmg > mine then
				rank += 1
			end
		end
	end
	return { Active = not F.Ended, State = F.State, Phase = F.Phase, Difficulty = F.Difficulty, Armor = math.ceil(F.Armor),
		MaxArmor = math.ceil(F.MaxArmor), Damage = math.floor(mine), Rank = rank, Fighters = F.Fighters, EndsAt = F.EndsAt,
		Finale = F.Finale and F.Finale.State or nil, InPit = player ~= nil and inPit(player) or nil }
end

---------------------------------------------------------------------------------------------------------------------
-- the API BossFinale works through (it never touches the fight table's internals beyond F.Finale / F.FinaleWon / F.EndsAt)
---------------------------------------------------------------------------------------------------------------------
Boss.Api = {
	Signal = signal, Score = score, Finish = finish, AddTarget = addTarget, RemoveTarget = removeTarget, MoveTarget = moveTarget,
	EntryOf = entryOf, SetAttr = setAttr, Bump = bump, SetMode = setMode, Publish = publish, Combat = combat, Lead = lead,
	HazardWave = hazardWave, CancelHazards = cancelHazards, Targetable = targetable, TargetPositions = targetPositions, InPit = inPit,
	RootPos = rootPos, HasDog = hasDog, PlayerOf = playerOf, Outside = OUTSIDE,
}

---------------------------------------------------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------------------------------------------------
-- wiring without loops (tests): core / modules handles, state folder, strike kinds
function Boss.Init(c, m)
	core = c
	modules = m or {}
	hookedHP = nil
	local st = Boss.StateRoot or Halloween:FindFirstChild("State") -- (tests: Boss.StateRoot = a Folder)
	stateFolder = st and st:FindFirstChild("Boss")
	if st and not stateFolder then
		stateFolder = Instance.new("Folder")
		stateFolder.Name = "Boss"
		stateFolder.Parent = st
	end
	publish(nil)
	Boss.RegisterStrike()
end

function Boss.Start(c, m)
	if Boss.Started then
		return
	end
	Boss.Started = true
	Boss.Init(c, m)
	ensureRig()
	core.OnRequest("BossSummon", function(player, a)
		if not core.Near(player, Layout.Bell.Position, (B.SummonRange or 18) + 4) then
			return false, "Ring the Grave Bell at the pit to summon the Gravekeeper"
		end
		local ok, err = Boss.Summon(tonumber(a.Difficulty) or 1, "Bell", player)
		if not ok then
			return false, err
		end
		return true, { Message = "THE GRAVEKEEPER RISES" }
	end, { Cost = 2 })
	core.OnRequest("BossStatus", function(player)
		return true, Boss.Status(player)
	end, { Cost = .5 })
	if modules.World and modules.World.Prompt then
		modules.World.Prompt("Bell", { ActionText = "RING", ObjectText = "GRAVE BELL", MaxActivationDistance = 12, HoldDuration = .3 }, function(player)
			modules.World.OpenWindow(player, "Boss")
		end)
	end
	if modules.Exorcism and modules.Exorcism.SetBossHook then
		modules.Exorcism.SetBossHook(function(difficulty, reason)
			return Boss.Summon(difficulty, reason or "Exorcism", nil)
		end)
	end
	-- Strike may start after us (module order): retry the registration for a while
	task.spawn(function()
		for _ = 1, 30 do
			if Boss.RegisterStrike() then
				break
			end
			task.wait(1)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		if Boss.Pending[player.UserId] then
			task.spawn(Boss.ResumePending, player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local F = Boss.Fight
		if F and F.FighterList then
			local i = table.find(F.FighterList, player)
			if i then
				table.remove(F.FighterList, i)
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < .1 then
			return
		end
		local step = math.min(acc, .5)
		acc = 0
		local ok, err = pcall(Boss.Step, step)
		if not ok then
			warn("Halloween Boss step failed: " .. tostring(err))
		end
	end)
end

return Boss
