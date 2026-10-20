-- THE GRAVEKEEPER (ServerScriptService.Halloween.Boss) — the Dead Yard boss of NIGHT OF THE BURIED MOON.
-- Not a sword-clicking boss: every bit of damage comes from DOGROTS' own pickaxe timing hits (SSS.Halloween.Strike):
-- players break its stone ARMOR PLATES, dig the real GRAVE MOUND after it burrows, smash the SKELETON DOGS that shield it,
-- break CURSED ROCKS that fall from the sky (each hurls a shard back into the boss) and dig its WEAK POINTS while ENRAGED,
-- all while dodging telegraphed slams / sweeps / stomps (knockback + Curse).
--
-- Summon: the Grave Bell prompt (Layout.Bell) opens the Halloween window on the BOSS tab; the tab sends Request
-- `BossSummon {Difficulty}` (near the bell, difficulty unlocked: h.Boss.Unlocked >= d, cooldown over, one fight per server).
-- The Server Exorcism milestone 5000 summons it too (Exorcism.SetBossHook; Exorcism.Reset() when that fight is over).
-- API: Boss.Summon(difficulty, reason, player?) -> ok, err ; Boss.Abort(reason) ; Boss.Fight (live table, read only) ;
--      Boss.ArmorDamage(raw, weak) ; Boss.DogBonus(team) ; Boss.RockSpot(x, z) ; Boss.Status(player?) ;
--      Boss.Pending / Boss.ResumePending(player) (rewards retried on rejoin) ; Boss.Init(core, modules) + Boss.Step(dt)
--      (tests) ; Boss.Start.
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
--   Underground|Erupt|Stagger|Enrage|Death|Escape), ModeAt, ModeUntil, Attack, Armor, MaxArmor, StartedAt, EndsAt,
--   NextSummonAt, Fighters, Revision, Shield, ShieldLeft, ShieldNeed, WeakOpenUntil, WeakSlots ("Heart,Throat"), Plates
--   ("110111" in Models.Boss.Slots.PlateOrder, 0 = shattered / regrowing), PlateWear ("003900": cracks 0..9 per plate),
--   RockWave, BurrowUntil, Reason, FightId, Enraged, BossCF (CFrame, 4 Hz).
-- The boss position: Workspace.HalloweenLive.Boss.BossRig.BossRoot (anchored, invisible, Persistent model; moved <= 10 Hz).
-- Signal "BossEvent" {Kind = Rise | Phase | Attack | Knock | Burrow | MoundHit | FakeMound | Erupt | Skeletons | Shield |
--   SkeletonDown | Bite | Rocks | RockLand | RockShard | RockExplode | Enrage | WeakPoint | PlateBreak | PlateRegrow | Hit |
--   Defeated | Escaped | Reward, ...} (fields documented at each Signal call below).
-- Strike kinds registered here (SSS.Halloween.Strike, WP7): BossPlate (BREAK; HP = plate integrity in ARMOR units, each hit
-- removes exactly the armor it dealt), BossWeak (DIG; never breaks, x3 armor damage, + the digger's yard-dog bonus: their
-- best assigned dog digs with them, StrikeBegin Extra {Companion, Event, DogBonus}), BossMound / BossSkeleton / CursedRock
-- (DIG / STRIKE / BREAK; Damage = "Power": HP counts tier-normalized hits). Target parts carry attributes Slot / Index / Key.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config
local Layout = Shared.Layout
local Models = Halloween:FindFirstChild("Models")
local BossModels = Models and Models:FindFirstChild("Boss") and require(Models.Boss) or nil

local B = Config.Boss
local Boss = { Fight = nil, NextSummonAt = 0, Started = false }

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
	RewardRetry = { 2, 5, 12, 30, 60 }, -- seconds between reward attempts (a failed BossReward transaction is retried)
	WeakCycle = 12,          -- enraged: weak points open every N seconds
	Stomp = { Radius = 9.5, Telegraph = 1.2, Knock = 50, Curse = 6 },
	SweepRadius = 20, SweepAngle = 120,
	EmptyGrace = 40, ExorcismGrace = 75, -- (40: a solo fighter who dies can respawn and walk back from the spawn)
	EndHold = 12,            -- seconds the Defeated / Escaped state stays published (death animation, banners)
	ArmorK = 5, ArmorExp = .55, -- armor damage = K * rawPickaxeDamage ^ Exp (compresses the 1..1500 pickaxe range)
	ArenaRadius = 42,        -- fighters: alive players this close (horizontally) to the pit centre (incl. the bell)
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

-- the boss's own damage scale: raw pickaxe damage (1 .. ~1500) compressed so every tier matters but nobody one-shots
function Boss.ArmorDamage(raw: number, weak: boolean?): number
	raw = math.max(0, tonumber(raw) or 0)
	if raw <= 0 then
		return 0
	end
	local d = T.ArmorK * raw ^ T.ArmorExp
	if weak then
		d *= (B.WeakPoints and B.WeakPoints.Mult) or 3
	end
	return math.max(1, math.floor(d + .5))
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
		setAttr("BurrowUntil", 0)
		setAttr("Enraged", false)
		setAttr("Attack", "")
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
	setAttr("PhaseName", (phaseDef(F.Phase) or {}).Name or "")
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
	setAttr("BurrowUntil", F.BurrowUntil)
	setAttr("Reason", F.Reason)
	setAttr("Enraged", F.Phase >= 5)
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
-- fighters, contribution
---------------------------------------------------------------------------------------------------------------------
local function isFighterPos(pos: Vector3): boolean
	local c = Layout.Pit.Center
	local d = flatten(pos - c).Magnitude
	return (Layout.InPit(pos) or d <= T.ArenaRadius) and pos.Y > c.Y - 14 and pos.Y < c.Y + 22
end

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

local function updateFighters(F)
	local list = fighterList()
	F.FighterList = list
	local n = #list
	if n ~= F.Fighters then
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

local function avgDamage(F): number
	local sum, n = 0, 0
	local list = F.FighterList or {}
	if #list == 0 then
		list = Boss.GetPlayers()
	end
	for _, pl in ipairs(list) do
		sum += damageOf(pl)
		n += 1
	end
	return n > 0 and math.max(1, sum / n) or 1
end

local _ = avgDamage

-- reward-share credit without armor damage (skeletons, fake mounds)
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
	local whole = math.floor(amount + .5)
	if core and core.Queue and whole > 0 then
		-- (curse relief comes with every strike hit: kinds register Activity = "BossDamage")
		core.Queue(player, { Quest = { BossDamage = whole }, Stat = { BossDamage = whole }, Souls = souls })
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
-- knockback / curse
---------------------------------------------------------------------------------------------------------------------
local function knock(player: Player, from: Vector3, power: number, up: number?, curse: number?, attack: string?)
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
	signal(player, { Kind = "Knock", Velocity = v, Curse = curse or 0, Attack = attack })
end

-- players whose root is inside a horizontal radius (and roughly at arena height; with groundY: standing on that surface,
-- root .5 .. 6.5 above it, so a rock on the terrace ring never hits the floor below it and vice versa)
local function playersIn(center: Vector3, radius: number, F, groundY: number?): { Player }
	local out = {}
	for _, pl in ipairs((F and F.FighterList) or fighterList()) do
		local pos = rootPos(pl)
		local level = pos ~= nil and (if groundY then pos.Y > groundY + .5 and pos.Y < groundY + 6.5 else pos.Y < floorY() + 10)
		if pos and level and flatten(pos - center).Magnitude <= radius + 1 then
			table.insert(out, pl)
		end
	end
	return out
end

-- fighters down in the pit (not the rim spectators): the ones attacks and rocks are aimed at
local function pitFighters(F): { Player }
	local out = {}
	for _, pl in ipairs(F.FighterList or {}) do
		local pos = rootPos(pl)
		if pos and Layout.InPit(pos) and pos.Y < floorY() + 10 then
			table.insert(out, pl)
		end
	end
	return out
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
			NameRU = "СЛАБОЕ МЕСТО", Variant = slot, Attributes = { Slot = slot }, Data = { Slot = slot } }, entry)
		F.Weak[slot] = entry
		table.insert(slots, slot)
	end
	setAttr("WeakOpenUntil", F.WeakUntil)
	setAttr("WeakSlots", weakSlots(F))
	bump()
	-- BossEvent WeakPoint {Open, Slots = {slot...}, Until}
	signal("zone", { Kind = "WeakPoint", Open = true, Slots = slots, Until = F.WeakUntil })
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
	if not F or F.Ended or amount <= 0 then
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
	if F.Armor <= floorArmor + 1e-6 then
		-- the transformation happens on the next Step (never inside a Strike callback)
		F.Armor = floorArmor
		if nextDef then
			F.PendingPhase = F.Phase + 1
		else
			F.PendingDefeat = true
		end
	end
	local _ = source
	return applied
end
Boss.ApplyDamage = function(player, amount, source, force)
	return applyDamage(Boss.Fight, player, amount, source or "Script", force)
end

local function clearMounds(F)
	for _, m in pairs(F.Mounds) do
		if m.Target then
			removeTarget(F, m.Target, "Collapse")
		end
	end
	F.Mounds = {}
	F.BurrowUntil = 0
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
	F.SubPhase = "Underground"
	setMode(F, "Underground")
	setAttr("BurrowUntil", F.BurrowUntil)
	-- BossEvent Burrow {Stage = "Mounds", Mounds = {{TargetId, Position, Index}}, Until}
	signal("zone", { Kind = "Burrow", Stage = "Mounds", Mounds = list, Until = F.BurrowUntil })
end

local function erupt(F, found: boolean, player: Player?)
	local m = F.Mounds[F.RealMound]
	local pos = m and m.Pos or Layout.Boss.Spawn
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
	local hits = {}
	if not found then
		for _, pl in ipairs(playersIn(pos, T.EruptRadius, F)) do
			knock(pl, pos, T.EruptKnock, nil, T.EruptCurse, "Erupt")
			table.insert(hits, pl.UserId)
		end
	end
	local dealt = 0
	if found then
		local amount = ((B.Burrow and B.Burrow.RealDamage) or .08) * F.MaxArmor
		dealt = applyDamage(F, player, amount, "Mound", true)
	end
	-- BossEvent Erupt {Position, Found, UserId, Damage, Hits}
	signal("zone", { Kind = "Erupt", Position = pos, Found = found, UserId = player and player.UserId or 0, Damage = math.floor(dealt), Hits = hits })
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
	local rocks = {}
	local land = now() + (cfg.LandDelay or 1.6) / (F.Def.Speed ^ .3)
	local placed = {}
	-- aimed rocks go to the players down in the pit (rim spectators are never targets)
	local fighters = pitFighters(F)
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
			F.RockSerial = (F.RockSerial or 0) + 1
			local key = F.RockSerial
			local radius = kind == "Terrace" and math.min(T.RockImpactRadius, T.TerraceRockRadius) or T.RockImpactRadius
			F.Rocks[key] = { Key = key, Pos = pos, LandAt = land + (i - 1) * .12, Role = "Rock", Radius = radius }
			table.insert(rocks, { Key = key, Position = pos, LandAt = land + (i - 1) * .12, Radius = radius })
		end
	end
	-- BossEvent Rocks {Wave, Waves, Rocks = {{Key, Position (on the real surface), LandAt, Radius}}}
	signal("zone", { Kind = "Rocks", Wave = F.RockWave, Waves = cfg.Waves or 3, Rocks = rocks })
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
	for _, pl in ipairs(F.FighterList or {}) do
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

local function startAttack(F)
	local list = F.FighterList or {}
	if #list == 0 then
		return
	end
	local speed = F.Def.Speed
	local _, closePos, closeD = nearestFighter(F, F.Pos)
	-- aim at someone down in the pit (rim spectators cannot be hit: an attack on them would be wasted)
	local pool = pitFighters(F)
	if #pool == 0 then
		pool = list
	end
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
	local a = { Kind = kind }
	if kind == "Stomp" then
		a.Pos = F.Pos
		a.Radius = T.Stomp.Radius
		a.Telegraph = T.Stomp.Telegraph / speed ^ .5
	elseif kind == "Slam" then
		local d = flatten(tpos - F.Pos)
		local reach = math.min(d.Magnitude, 16)
		local dir = d.Magnitude > .1 and d.Unit or facing(F)
		a.Pos = Vector3.new(F.Pos.X, floorY(), F.Pos.Z) + dir * math.max(6, reach)
		a.Radius = B.Attacks.Slam.Radius
		a.Telegraph = B.Attacks.Slam.Telegraph / speed ^ .5
		F.Yaw = yawTo(F, a.Pos)
	else
		F.Yaw = yawTo(F, tpos)
		a.Pos = F.Pos
		a.Radius = T.SweepRadius
		a.Angle = T.SweepAngle
		a.Dir = facing(F)
		a.Telegraph = B.Attacks.Sweep.Telegraph / speed ^ .5
	end
	a.ImpactAt = now() + a.Telegraph
	a.Dir = a.Dir or facing(F)
	F.Attack = a
	setMode(F, "Windup", a.Telegraph)
	setAttr("Attack", kind)
	moveRoot(F)
	syncBodyTargets(F)
	-- BossEvent Attack {Attack, Stage = "Telegraph", Position, Radius, Angle?, Direction, Telegraph, ImpactAt}
	signal("zone", { Kind = "Attack", Attack = kind, Stage = "Telegraph", Position = a.Pos, Radius = a.Radius, Angle = a.Angle,
		Direction = a.Dir, Telegraph = a.Telegraph, ImpactAt = a.ImpactAt })
end

local function resolveAttack(F)
	local a = F.Attack
	F.Attack = nil
	if not a then
		return
	end
	local hits = {}
	local cfg
	if a.Kind == "Slam" then
		cfg = B.Attacks.Slam
		for _, pl in ipairs(playersIn(a.Pos, a.Radius, F)) do
			knock(pl, a.Pos, cfg.Knock or 60, nil, cfg.Curse, "Slam")
			table.insert(hits, pl.UserId)
		end
	elseif a.Kind == "Stomp" then
		cfg = T.Stomp
		for _, pl in ipairs(playersIn(a.Pos, a.Radius, F)) do
			knock(pl, a.Pos, cfg.Knock, nil, cfg.Curse, "Stomp")
			table.insert(hits, pl.UserId)
		end
	else
		cfg = B.Attacks.Sweep
		local half = math.rad((a.Angle or 120) / 2)
		for _, pl in ipairs(playersIn(a.Pos, a.Radius, F)) do
			local p = rootPos(pl)
			local d = p and flatten(p - a.Pos)
			if d and (d.Magnitude < 4 or math.acos(math.clamp(d.Unit:Dot(a.Dir), -1, 1)) <= half) then
				-- swept sideways (away from the swing side) and back
				local side = a.Dir:Cross(Vector3.new(0, 1, 0))
				local s = (d:Dot(side) >= 0) and 1 or -1
				knock(pl, p - side * s * 4 - a.Dir * 2, cfg.Knock or 48, 24, cfg.Curse, "Sweep")
				table.insert(hits, pl.UserId)
			end
		end
	end
	setMode(F, "Idle")
	setAttr("Attack", "")
	-- BossEvent Attack {Attack, Stage = "Impact", Position, Radius, Angle?, Direction, Hits = {userId...}}
	signal("zone", { Kind = "Attack", Attack = a.Kind, Stage = "Impact", Position = a.Pos, Radius = a.Radius, Angle = a.Angle,
		Direction = a.Dir, Hits = hits })
	local iv = F.Phase >= 5 and B.Attacks.EnrageInterval or B.Attacks.Interval
	F.NextAttackAt = now() + Boss.Rand(iv[1], iv[2]) / F.Def.Speed
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
		-- bite
		if ppos and d <= T.BiteRange and math.abs(ppos.Y - (floorY() + 3)) < 5 and t >= s.NextBite then
			s.NextBite = t + T.BiteCooldown / F.Def.Speed
			local pl = nil
			for _, cand in ipairs(F.FighterList or {}) do
				local cp = rootPos(cand)
				if cp and flatten(cp - s.Pos).Magnitude <= T.BiteRange + .5 then
					pl = cand
					break
				end
			end
			if pl then
				knock(pl, s.Pos, T.BiteKnock, 10, T.BiteCurse, "Bite")
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
			F.Rocks[key] = nil
		elseif not r.Landed and t >= r.LandAt then
			r.Landed = true
			r.ExplodeAt = t + (cfg.ExplodeAfter or 9)
			local hits = {}
			for _, pl in ipairs(playersIn(r.Pos, r.Radius or T.RockImpactRadius, F, r.Pos.Y)) do
				knock(pl, r.Pos, T.RockKnock, nil, T.RockImpactCurse, "Rock")
				table.insert(hits, pl.UserId)
			end
			local hp = cfg.HP or 3 -- tier-normalized hits
			addTarget(F, { Kind = "CursedRock", Position = r.Pos + Vector3.new(0, 2.3, 0), Radius = 2.8, HP = hp, MaxHP = hp, Unit = 1,
				Color = Color3.fromRGB(70, 50, 90), Material = "Basalt", Size = Vector3.new(5, 4.6, 5), Name = "CURSED ROCK", NameRU = "ПРОКЛЯТЫЙ КАМЕНЬ",
				Seed = key, Ground = r.Pos, Attributes = { Key = key }, Data = { Key = key } }, r)
			-- BossEvent RockLand {Key, Position, TargetId, Hits, ExplodeAt}
			signal("zone", { Kind = "RockLand", Key = key, Position = r.Pos, TargetId = idOf(r.Target), Hits = hits, ExplodeAt = r.ExplodeAt })
		elseif r.Landed and r.ExplodeAt and t >= r.ExplodeAt then
			local tid = idOf(r.Target)
			if r.Target then
				removeTarget(F, r.Target, "Explode")
			end
			F.Rocks[key] = nil
			local hits = {}
			for _, pl in ipairs(playersIn(r.Pos, T.RockExplodeRadius, F, r.Pos.Y)) do
				knock(pl, r.Pos, T.RockKnock, nil, T.RockExplodeCurse, "RockExplode")
				table.insert(hits, pl.UserId)
			end
			-- BossEvent RockExplode {Key, TargetId, Position, Hits}
			signal("zone", { Kind = "RockExplode", Key = key, TargetId = tid, Position = r.Pos, Hits = hits })
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
	local list = F.FighterList or {}
	if #list == 0 then
		return
	end
	-- head for the middle of the fighters, inside the leash
	local sum = Vector3.zero
	for _, pl in ipairs(list) do
		local p = rootPos(pl)
		if p then
			sum += flatten(p)
		end
	end
	local centroid = sum / #list
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

-- one reward plan per contributor (pure: also used by the tests)
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
			Difficulty = F.Difficulty }
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
-- Unpaid rewards are parked in Boss.Pending[userId][fightId] (one slot per fight) and retried when the player (re)joins
-- (PlayerAdded), or, while they are in the server (also under a new Player object after a quick rejoin), after a delay.
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
	for _, pl in ipairs(Boss.GetPlayers()) do
		if pl.UserId == uid and pl.Parent then
			return pl
		end
	end
	return nil
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

local function park(uid: number, fightId: string, plan, from: Player)
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

local function grant(fightId: string, player: Player, plan): boolean
	local uid = player.UserId
	local base = "hw-boss:" .. tostring(fightId) .. ":" .. uid
	local delays = T.RewardRetry or {}
	plan.Tries, plan.Fresh = 0, plan.Fresh or 0
	while true do
		plan.Tries += 1
		local receipt = plan.Fresh > 0 and (base .. "#" .. plan.Fresh) or base
		local okCall, ok, res = pcall(tryGrant, player, plan, receipt)
		if okCall and ok then
			unpark(uid, fightId)
			res = type(res) == "table" and res or {}
			-- BossEvent Reward {Outcome, Difficulty, Candy, Bones, XP, Rewards = {rows}, Share, Rank, Damage, Full, Unlocked}
			signal(player, { Kind = "Reward", Outcome = plan.Outcome, Difficulty = plan.Difficulty, Candy = res.Candy, Bones = res.Bones,
				XP = res.XP, Rewards = res.Rewards, Share = plan.Share, Rank = plan.Rank, Damage = math.floor(plan.Damage), Full = plan.Full,
				Unlocked = res.Unlocked })
			return true
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
		local player = nil
		for _, pl in ipairs(Boss.GetPlayers()) do
			if pl.UserId == plan.UserId then
				player = pl
			end
		end
		if player and player.Parent then
			task.spawn(grant, F.Id, player, plan)
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

finish = function(F, outcome: string, reason: string?)
	if F.Ended then
		return
	end
	F.Ended = true
	F.Outcome = outcome
	cleanupTargets(F)
	Boss.NextSummonAt = now() + (B.SummonCooldown or 240)
	F.State = outcome
	F.EndHoldUntil = now() + T.EndHold
	if outcome == "Defeated" then
		setMode(F, "Death", 6)
		-- BossEvent Defeated {Difficulty, Numeral, Top = {{UserId, Name, Damage}}, Position, Duration}
		signal("all", { Kind = "Defeated", Difficulty = F.Difficulty, Numeral = F.Def.Numeral, Top = topList(F, 5), Position = F.Pos,
			Duration = 6 })
	else
		setMode(F, "Escape", 4)
		-- BossEvent Escaped {Reason = "Time"|"Empty"|"Disabled", Position}
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

function Boss.Abort(reason: string?)
	local F = Boss.Fight
	if not F then
		return
	end
	finish(F, "Escaped", reason or "Disabled")
	Boss.Fight = nil
	publish(nil)
	bump()
	if rigRoot and rigRoot.Parent then
		rigRoot.CFrame = CFrame.new(Layout.Boss.Spawn + Vector3.new(0, -60, 0))
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
	-- StrikeBegin Extra (to the digger): Companion = {Id, Asset, Variant, Rank} | nil, Event, DogBonus (0 .. DogMax)
	return { Companion = team.Best, Event = team.HasEvent, DogBonus = team.Bonus }
end

-- expected armor damage of a hit (Strike "Damage" function: what the HP panel / hit number shows)
local function bodyDamage(player: Player, target: any, hit: any): number
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not entry then
		return 0
	end
	local q, crit, raw = hitQuality(hit)
	local weak = entry.Role == "Weak"
	local dmg = Boss.ArmorDamage(raw > 0 and raw or damageOf(player) * (q == 2 and 1.5 or 1) * (crit and 2 or 1), weak)
	if weak and dmg > 0 then
		local bonus = dogTeam(F, player).Bonus
		if bonus > 0 then
			dmg = math.floor(dmg * (1 + bonus) + .5)
		end
	end
	return dmg
end

local function onPlateHit(player: Player, target: any, hit: any)
	local F = Boss.Fight
	local entry = entryOf(F, target)
	if not entry or entry.Removed then
		if type(hit) == "table" then
			hit.Applied = 0
		end
		return nil
	end
	local q, crit = hitQuality(hit)
	local weak = entry.Role == "Weak"
	local amount = bodyDamage(player, target, hit)
	local applied = applyDamage(F, player, amount, weak and "Weak" or "Plate")
	-- the plate loses exactly the armor it absorbed (weak points have 1e9 HP: the number still shows the x3 damage)
	if type(hit) == "table" then
		hit.Applied = applied
	end
	local dogBonus = (weak and F) and dogTeam(F, player).Bonus or 0
	-- BossEvent Hit {Damage, Weak, Slot, Crit, Quality, Armor, DogBonus} (to the hitter: big armor-damage number; DogBonus
	-- > 0 = their dog dug with them)
	signal(player, { Kind = "Hit", Damage = math.floor(applied + .5), Weak = weak, Slot = entry.Slot, Crit = crit, Quality = q,
		Armor = math.max(0, math.ceil(F and F.Armor or 0)), TargetId = idOf(target), DogBonus = dogBonus > 0 and dogBonus or nil })
	return { BossDamage = math.floor(applied + .5), Weak = weak, Armor = F and math.max(0, math.ceil(F.Armor)) or 0,
		DogBonus = dogBonus > 0 and dogBonus or nil }
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
	local bonus = applyDamage(F, player, T.PlateBreakBonus * F.MaxArmor, "PlateBreak")
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

local function canHitBody(_player: Player, target: any)
	local F = Boss.Fight
	if not F or not entryOf(F, target) then
		return false, "Too late!"
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
		local hits = {}
		for _, pl in ipairs(playersIn(entry.Pos, T.FakeRadius, F)) do
			knock(pl, entry.Pos, T.FakeKnock, 26, (B.Burrow and B.Burrow.FakeCurse) or 12, "FakeMound")
			table.insert(hits, pl.UserId)
		end
		F.Mounds[entry.Index] = nil
		score(F, player, T.MoundScore * F.MaxArmor)
		-- BossEvent FakeMound {TargetId, Position, UserId, Hits}
		signal("zone", { Kind = "FakeMound", TargetId = idOf(target), Position = entry.Pos, UserId = player and player.UserId or 0, Hits = hits })
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
	local amount = ((B.Rocks and B.Rocks.Damage) or .03) * F.MaxArmor
	local applied = applyDamage(F, player, amount, "Shard", true)
	-- BossEvent RockShard {TargetId, Key, From, UserId, Damage}
	signal("zone", { Kind = "RockShard", TargetId = idOf(target), Key = entry.Key, From = entry.Pos, UserId = player and player.UserId or 0,
		Damage = math.floor(applied) })
end

local function canHitAlways(_player: Player, target: any)
	local F = Boss.Fight
	if not F or not entryOf(F, target) then
		return false, "Too late!"
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
			CanHit = canHitBody, Activity = "BossDamage" })
		Strike.Register("BossWeak", { Range = 22, Verb = "DIG", Damage = bodyDamage, OnBegin = onWeakBegin, OnHit = onPlateHit, CanHit = canHitBody,
			Activity = "BossDamage" })
		Strike.Register("BossMound", { Range = 14, Verb = "DIG", Damage = "Power", OnHit = onMoundHit, OnBreak = onMoundBreak, CanHit = canHitAlways })
		Strike.Register("BossSkeleton", { Range = 13, Verb = "STRIKE", Damage = "Power", OnBreak = onSkeletonBreak, CanHit = canHitAlways })
		Strike.Register("CursedRock", { Range = 14, Verb = "BREAK", Damage = "Power", OnBreak = onRockBreak, CanHit = canHitAlways })
	end)
	if not ok then
		warn("Halloween Boss: Strike.Register failed: " .. tostring(err))
		return false
	end
	Boss.StrikeReady = true
	return true
end
Boss.Handlers = { PlateHit = onPlateHit, PlateBreak = onPlateBreak, MoundHit = onMoundHit, MoundBreak = onMoundBreak,
	SkeletonBreak = onSkeletonBreak, RockBreak = onRockBreak, CanHitBody = canHitBody, WeakBegin = onWeakBegin }

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
	}
	local facingYaw = math.atan2(-Layout.Boss.Facing.X, -Layout.Boss.Facing.Z)
	F.Yaw = facingYaw
	F.MaxArmor = maxArmorFor(F, 1)
	F.Armor = F.MaxArmor
	Boss.Fight = F
	updateFighters(F)
	F.Armor = F.MaxArmor
	publish(F)
	moveRoot(F)
	bump()
	-- BossEvent Rise {Difficulty, Numeral, Name, Reason, SummonerId, SummonerName, Position, Duration, FightId}
	signal("all", { Kind = "Rise", Difficulty = d, Numeral = def.Numeral, Name = def.Name, Reason = reason, SummonerId = F.SummonerId,
		SummonerName = player and player.Name or "", Position = F.Pos, Duration = T.RiseSeconds, FightId = F.Id })
	return true
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
			Boss.Fight = nil
			publish(nil)
			bump()
			if rigRoot and rigRoot.Parent then
				rigRoot.CFrame = CFrame.new(Layout.Boss.Spawn + Vector3.new(0, -60, 0))
			end
		end
		return
	end
	-- deferred transformations (set by damage inside Strike callbacks)
	if F.BreakQueue then
		local q = F.BreakQueue
		F.BreakQueue = nil
		for slot, pl in pairs(q) do
			breakPlate(F, slot, pl)
		end
	end
	if F.PendingDefeat then
		F.PendingDefeat = nil
		defeat(F, nil)
		return
	end
	if F.PendingPhase then
		local p = F.PendingPhase
		F.PendingPhase = nil
		enterPhase(F, p)
	end
	-- fighters (live armor scaling) every second
	if t - (F.FightersAt or 0) >= 1 then
		F.FightersAt = t
		updateFighters(F)
	end
	-- nobody left in the arena -> it leaves
	if F.Fighters == 0 then
		F.EmptySince = F.EmptySince or t
		if t - F.EmptySince >= F.EmptyGrace then
			finish(F, "Escaped", "Empty")
			return
		end
	else
		if F.State == "Fight" then
			F.EmptyGrace = T.EmptyGrace -- the long exorcism grace only covers the walk to the pit
		end
		F.EmptySince = nil
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

	-- phase 2: underground timeout / surface window
	if F.Phase == 2 then
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
	-- phase 4: rock waves
	if F.Phase == 4 and F.Mode ~= "Roar" and t >= (F.NextWaveAt or math.huge) then
		rockWave(F)
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

	-- attacks + movement while on the surface
	local surfaced = F.SubPhase ~= "Underground" and F.Mode ~= "Burrow"
	if surfaced and (F.Mode == "Idle" or F.Mode == "Walk") and t >= (F.NextAttackAt or 0) and F.Fighters > 0 then
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
		MaxArmor = math.ceil(F.MaxArmor), Damage = math.floor(mine), Rank = rank, Fighters = F.Fighters, EndsAt = F.EndsAt }
end

---------------------------------------------------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------------------------------------------------
-- wiring without loops (tests): core / modules handles, state folder, strike kinds
function Boss.Init(c, m)
	core = c
	modules = m or {}
	local st = Halloween:FindFirstChild("State")
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
