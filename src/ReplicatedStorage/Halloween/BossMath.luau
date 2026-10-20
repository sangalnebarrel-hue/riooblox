-- Damage scaling of CHAPTER II combat (ReplicatedStorage.Halloween.BossMath, docs/halloween2/DESIGN.md §10.4-10.5, §9.8).
-- Pure: requires only config modules, so Lune tests run it as-is (tests/combat.luau).
--   * Player -> boss: the per-hit armor curve K x raw ^ Exp (raw = MiningRules.HitDamage incl. Strength / Perfect / combo /
--     crit), weak points x3, the yard-dog bonus, SYNC STRIKE (two players' Perfects within .5 s: +50% for both), WEAKENED
--     (-30% dealt), H15 RESONANT HOWL (+25% on chains / bells / weak points); the extra multipliers together are capped
--     (BonusCap) so stacking never runs away.
--   * Per-player soft cap over a rolling 3 s window: full value up to MaxArmorBase(d) x .0045 armor per second, 20% beyond;
--     mechanic damage (weak points, chains, real mounds, rocks, counter windows) bypasses 60% of the cap.
--   * Boss -> player Event HP: attack damage x the difficulty multiplier (I .7 .. V 1.5), never above 45% of MaxHP in a
--     single hit (40% in trials).
-- Numbers: ReplicatedStorage.Halloween.Chapter2Config.Boss when present (WP-A), else the built-in defaults below (the
-- Chapter I curve 5 / .55; every other default equals the design). WEAKENED and the per-hit caps also come from
-- Chapter2Config.Combat (Weakened {DamageDealt, DamageTaken}, BleedOut.WeakenedSeconds, MaxHP, Hazards.MaxHitFraction*),
-- H15 from Chapter2Config.Dogs.Defs.HW_BellkeeperWolf. Chapter2Config.Boss keys read (nested or flat):
--   ArmorK, ArmorExp, WeakMult, DogBonusMax, BonusCap,
--   SoftCap = {Window, PerSecond, Beyond, MechanicBypass}  | SoftCapWindow, SoftCapPerSecond, SoftCapBeyond, MechanicBypass
--   Sync = {Window, Bonus}                                 | SyncWindow, SyncBonus
--   Weakened = {Dealt, Taken, Seconds}                     | WeakenedDealt, WeakenedTaken, WeakenedSeconds
--   DifficultyMult = {I, II, III, IV, V} (alias DamageMult), Damage = {Stomp, Slam, ...}, MaxHitFrac, TrialHitFrac,
--   H15 = {Resonance, Mechanic}
-- API
--   BossMath.Config() -> merged table ; BossMath.SetConfig(tbl | nil)   (tests / Studio overrides)
--   BossMath.ArmorDamage(raw, opts?) -> armor, parts
--       opts {Weak, WeakMult, DogBonus, Sync (bool | mult), Weakened, H15, Mechanic, Mult, K, Exp}
--   BossMath.MaxArmorBase(difficulty) ; BossMath.CapPerSecond(maxArmorBase)
--   BossMath.NewCap() -> state ; BossMath.CapApply(state, now, amount, perSecond, mechanic?) -> applied, info
--   BossMath.NewSync() -> state ; BossMath.SyncHit(state, userId, now, amount) -> mult, retro {{UserId, Bonus}}
--   BossMath.DealtMult(opts {Weakened, H15, Mechanic}) ; BossMath.TakenMult(opts {Weakened})
--   BossMath.EventDamage(base, difficulty, opts {Trial, MaxHP, NoScale}?) -> dmg ; BossMath.HitCap(opts?) -> number
--   BossMath.AttackDamage(attack, difficulty, opts?) -> dmg   (Damage table x difficulty, capped)
--   BossMath.ResonanceCount(perfect, h15) ; BossMath.H15Mult(mechanicTarget)
local root = script.Parent

local BossMath = {}

BossMath.Defaults = {
	ArmorK = 5, ArmorExp = .55,          -- Chapter I curve; Chapter2Config.Boss.ArmorExp = .42 flattens it for Chapter II
	WeakMult = 3,                        -- weak points (Config.Boss.WeakPoints.Mult)
	DogBonusMax = .3,                    -- the yard-dog digger bonus cap (Config.Boss.WeakPoints.DogMax)
	BonusCap = 2.25,                     -- dog x sync x H15 x extra multipliers together never exceed this
	SoftCap = { Window = 3, PerSecond = .0045, Beyond = .2, MechanicBypass = .6 },
	Sync = { Window = .5, Bonus = .5 },
	Weakened = { Dealt = .7, Taken = 1.25, Seconds = 25 },
	DifficultyMult = { .7, .9, 1.1, 1.3, 1.5 },
	MaxHP = 100, MaxHitFrac = .45, TrialHitFrac = .40,
	Damage = { Stomp = 12, Slam = 16, Sweep = 10, Erupt = 14, FakeMound = 8, Bite = 6, RockImpact = 10, RockExplode = 14 },
	H15 = { Resonance = 2, Mechanic = 1.25 },
	BaseArmor = 5000,                    -- fallback when Config.Boss is missing
	DifficultyArmor = { 1, 1.6, 2.5, 4, 6.5 },
}

local override: any = nil
local cached: any = nil

local function requireSibling(name: string): any
	local ok, m = pcall(function()
		local inst = root:FindFirstChild(name)
		return inst and require(inst :: any)
	end)
	if ok and type(m) == "table" then
		return m
	end
	return nil
end

local function copy(t: any): any
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == "table" and copy(v) or v
	end
	return out
end

local function num(v: any): number?
	local n = tonumber(v)
	if n == nil or n ~= n then
		return nil
	end
	return n
end

-- merge a Chapter2Config.Boss-like table over the defaults (nested tables or the flat aliases)
local function resolve(src: any): any
	local c = copy(BossMath.Defaults)
	local halloween = requireSibling("Config")
	local hb = halloween and halloween.Boss
	if type(hb) == "table" then
		c.BaseArmor = num(hb.BaseArmor) or c.BaseArmor
		if type(hb.Difficulties) == "table" then
			local list = {}
			for i, d in ipairs(hb.Difficulties) do
				list[i] = num(d.Armor) or c.DifficultyArmor[i] or 1
			end
			c.DifficultyArmor = list
		end
		if type(hb.WeakPoints) == "table" then
			c.WeakMult = num(hb.WeakPoints.Mult) or c.WeakMult
			c.DogBonusMax = num(hb.WeakPoints.DogMax) or c.DogBonusMax
		end
	end
	if type(src) ~= "table" then
		return c
	end
	for _, k in ipairs({ "ArmorK", "ArmorExp", "WeakMult", "DogBonusMax", "BonusCap", "MaxHP", "MaxHitFrac", "TrialHitFrac" }) do
		c[k] = num(src[k]) or c[k]
	end
	local function sub(name: string, flat: { [string]: string })
		if type(src[name]) == "table" then
			for k, v in pairs(src[name]) do
				if num(v) then
					c[name][k] = num(v)
				end
			end
		end
		for key, field in pairs(flat) do
			c[name][field] = num(src[key]) or c[name][field]
		end
	end
	sub("SoftCap", { SoftCapWindow = "Window", SoftCapPerSecond = "PerSecond", SoftCapFrac = "PerSecond", SoftCapBeyond = "Beyond",
		MechanicBypass = "MechanicBypass" })
	sub("Sync", { SyncWindow = "Window", SyncBonus = "Bonus" })
	sub("Weakened", { WeakenedDealt = "Dealt", WeakenedTaken = "Taken", WeakenedSeconds = "Seconds" })
	sub("H15", {})
	local mults = src.DifficultyMult or src.DamageMult
	if type(mults) == "table" and #mults > 0 then
		local list = {}
		for i, v in ipairs(mults) do
			list[i] = num(v) or c.DifficultyMult[i] or 1
		end
		c.DifficultyMult = list
	end
	if type(src.Damage) == "table" then
		for k, v in pairs(src.Damage) do
			if num(v) then
				c.Damage[k] = num(v)
			end
		end
	end
	return c
end

-- Chapter2Config (whole module) -> a Boss-like source: .Boss, plus the WEAKENED numbers and hit caps of .Combat and the
-- H15 ability numbers of .Dogs.Defs.HW_BellkeeperWolf {ResonancePerfectMult, MechanicDamageBonus}
local function fromChapter2(m: any): any
	if type(m) ~= "table" then
		return nil
	end
	local src = type(m.Boss) == "table" and table.clone(m.Boss) or {}
	local combat = m.Combat or m.EventHP
	if type(combat) == "table" then
		local w = combat.Weakened
		if type(w) == "table" then
			src.WeakenedDealt = src.WeakenedDealt or w.DamageDealt or w.Dealt
			src.WeakenedTaken = src.WeakenedTaken or w.DamageTaken or w.Taken
		end
		if type(combat.BleedOut) == "table" then
			src.WeakenedSeconds = src.WeakenedSeconds or combat.BleedOut.WeakenedSeconds
		end
		src.MaxHP = src.MaxHP or combat.MaxHP
		local hz = combat.Hazards
		if type(hz) == "table" then
			src.MaxHitFrac = src.MaxHitFrac or hz.MaxHitFractionBoss
			src.TrialHitFrac = src.TrialHitFrac or hz.MaxHitFractionTrial
		end
	end
	local defs = type(m.Dogs) == "table" and m.Dogs.Defs
	local wolf = type(defs) == "table" and defs.HW_BellkeeperWolf
	if type(wolf) == "table" then
		local h15 = type(src.H15) == "table" and table.clone(src.H15) or {}
		h15.Resonance = h15.Resonance or num(wolf.ResonancePerfectMult)
		if h15.Mechanic == nil and num(wolf.MechanicDamageBonus) then
			h15.Mechanic = 1 + (num(wolf.MechanicDamageBonus) :: number)
		end
		src.H15 = h15
	end
	return src
end

BossMath.FromChapter2 = fromChapter2 -- tests: the Chapter2Config mapping

function BossMath.Config(): any
	if override then
		return override
	end
	if not cached then
		cached = resolve(fromChapter2(requireSibling("Chapter2Config")))
	end
	return cached
end

-- tests / Studio: a Chapter2Config.Boss-like table merged over the defaults (nil = back to the real config)
function BossMath.SetConfig(tbl: any?)
	override = tbl and resolve(tbl) or nil
	cached = nil
end

---------------------------------------------------------------------------------------------------------------------
-- player -> boss
---------------------------------------------------------------------------------------------------------------------
-- armor dealt by one hit. parts = {Base, Weak, Bonus (capped product), Weakened, Raw}
function BossMath.ArmorDamage(raw: number, opts: any?): (number, any)
	local c = BossMath.Config()
	local o = opts or {}
	raw = math.max(0, num(raw) or 0)
	if raw <= 0 then
		return 0, { Base = 0, Weak = 1, Bonus = 1, Weakened = 1, Raw = 0 }
	end
	local k = num(o.K) or c.ArmorK
	local e = num(o.Exp) or c.ArmorExp
	local base = k * raw ^ e
	local weak = 1
	if o.Weak then
		weak = num(o.WeakMult) or c.WeakMult
	end
	local bonus = 1 + math.clamp(num(o.DogBonus) or 0, 0, c.DogBonusMax)
	if o.Sync == true then
		bonus *= 1 + c.Sync.Bonus
	elseif num(o.Sync) then
		bonus *= num(o.Sync) :: number
	end
	if o.H15 and (o.Mechanic or o.Weak) then
		bonus *= c.H15.Mechanic
	end
	bonus *= math.max(0, num(o.Mult) or 1)
	bonus = math.min(bonus, c.BonusCap)
	local weakened = o.Weakened and c.Weakened.Dealt or 1
	local d = base * weak * bonus * weakened
	return math.max(1, math.floor(d + .5)), { Base = base, Weak = weak, Bonus = bonus, Weakened = weakened, Raw = raw }
end

-- MaxArmor of a difficulty for ONE fighter (the soft-cap reference: more fighters never raise a player's own cap)
function BossMath.MaxArmorBase(difficulty: number): number
	local c = BossMath.Config()
	local list = c.DifficultyArmor
	local d = math.clamp(math.floor(num(difficulty) or 1), 1, math.max(1, #list))
	return c.BaseArmor * (list[d] or 1)
end

function BossMath.CapPerSecond(maxArmorBase: number): number
	return math.max(0, num(maxArmorBase) or 0) * BossMath.Config().SoftCap.PerSecond
end

function BossMath.NewCap(): any
	return { Hist = {} }
end

-- the soft cap over a rolling window. state = BossMath.NewCap() per player and fight. Returns the armor that lands and
-- {Free (bypassed), Full (inside the allowance), Over (beyond, before the 20%), Room (allowance left before this hit)}
function BossMath.CapApply(state: any, now: number, amount: number, perSecond: number, mechanic: boolean?): (number, any)
	local c = BossMath.Config().SoftCap
	amount = math.max(0, num(amount) or 0)
	local hist = state.Hist
	local sum = 0
	for i = #hist, 1, -1 do
		if hist[i].At <= now - c.Window then
			table.remove(hist, i)
		else
			sum += hist[i].Amount
		end
	end
	local free = mechanic and amount * c.MechanicBypass or 0
	local counted = amount - free
	local allowance = math.max(0, num(perSecond) or 0) * c.Window
	local room = math.max(0, allowance - sum)
	local full = math.min(counted, room)
	local over = counted - full
	-- the window keeps the FULL-value armor only: over-cap hits never eat the next second's allowance, so a player
	-- always lands perSecond at full value and only the excess drops to Beyond
	if full > 0 then
		table.insert(hist, { At = now, Amount = full })
	end
	local applied = free + full + over * c.Beyond
	return applied, { Free = free, Full = full, Over = over, Room = room }
end

function BossMath.NewSync(): any
	return { Recent = {} }
end

-- a server-confirmed Perfect on the boss. mult: 1 + Sync.Bonus when another player landed a Perfect within the window;
-- retro: earlier partner hits that had not been synced yet, each with the bonus armor they should now receive.
function BossMath.SyncHit(state: any, userId: number, now: number, amount: number): (number, { any })
	local c = BossMath.Config().Sync
	local recent = state.Recent
	local retro = {}
	local synced = false
	for uid, r in pairs(recent) do
		if now - r.At > c.Window then
			recent[uid] = nil
		elseif uid ~= userId then
			synced = true
			if not r.Synced then
				r.Synced = true
				table.insert(retro, { UserId = uid, Bonus = r.Amount * c.Bonus })
			end
		end
	end
	table.sort(retro, function(a, b)
		return a.UserId < b.UserId
	end)
	recent[userId] = { At = now, Amount = math.max(0, num(amount) or 0), Synced = synced }
	return synced and (1 + c.Bonus) or 1, retro
end

function BossMath.DealtMult(opts: any?): number
	local c = BossMath.Config()
	local o = opts or {}
	local m = 1
	if o.Weakened then
		m *= c.Weakened.Dealt
	end
	if o.H15 and o.Mechanic then
		m *= c.H15.Mechanic
	end
	return m
end

function BossMath.TakenMult(opts: any?): number
	local o = opts or {}
	return o.Weakened and BossMath.Config().Weakened.Taken or 1
end

function BossMath.ResonanceCount(perfect: boolean, h15: boolean?): number
	if not perfect then
		return 0
	end
	return h15 and BossMath.Config().H15.Resonance or 1
end

function BossMath.H15Mult(mechanicTarget: boolean?): number
	return mechanicTarget and BossMath.Config().H15.Mechanic or 1
end

---------------------------------------------------------------------------------------------------------------------
-- boss -> player (Event HP)
---------------------------------------------------------------------------------------------------------------------
function BossMath.HitCap(opts: any?): number
	local c = BossMath.Config()
	local o = opts or {}
	local maxHP = num(o.MaxHP) or c.MaxHP
	return maxHP * (o.Trial and c.TrialHitFrac or c.MaxHitFrac)
end

function BossMath.DifficultyMult(difficulty: number): number
	local list = BossMath.Config().DifficultyMult
	local d = math.clamp(math.floor(num(difficulty) or 1), 1, math.max(1, #list))
	return list[d] or 1
end

function BossMath.EventDamage(base: number, difficulty: number?, opts: any?): number
	local o = opts or {}
	base = math.max(0, num(base) or 0)
	if base <= 0 then
		return 0
	end
	local scaled = o.NoScale and base or base * BossMath.DifficultyMult(difficulty or 1)
	local cap = math.floor(BossMath.HitCap(o))
	return math.clamp(math.floor(scaled + .5), 1, math.max(1, cap))
end

function BossMath.AttackDamage(attack: string, difficulty: number?, opts: any?): number
	local base = num(opts and opts.Base) or BossMath.Config().Damage[attack] or 0
	return BossMath.EventDamage(base, difficulty, opts)
end

return BossMath
