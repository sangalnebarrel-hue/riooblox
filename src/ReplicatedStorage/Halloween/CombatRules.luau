-- The Event HP state machine of CHAPTER II combat (ReplicatedStorage.Halloween.CombatRules, docs/halloween2/DESIGN.md
-- §10.1). Pure: time is passed in, nothing touches a Player or the world, so tests/combat.luau runs every timing exactly.
-- ServerScriptService.Halloween.EventHP owns the live states (one per combat player) and applies the side effects
-- (attributes, walk speed, the revive prompt, teleports, signals); clients read the same numbers for the HUD.
--
-- RULES (defaults = the design; Chapter2Config.Combat + the H10 / H11 / H14 numbers of Chapter2Config.Dogs.Defs override
-- them, see fromChapter2)
--   HP: MaxHP 100 (+15 with H14 Bridehound in the yard team). A hit gives .6 s of i-frames (DPS ticks neither respect
--   nor grant them). Shields absorb first. WEAKENED (after a bleed-out, 25 s): +25% damage taken, -30% dealt (BossMath).
--   Regen +2 HP/s after 8 s without damage (never while downed). Event HP never kills: at 0 the player is DOWNED for 20 s
--   (walk speed 5, cannot strike, a REVIVE prompt: hold 2.2 s within 9 studs; H14 revivers x2 speed, H11 targets x1.4;
--   revived at 40 HP, +20 HP shield from an H14 reviver). H11 Mourning Shiba: one self-revive per fight once downed 8 s.
--   Bleed-out (the timer runs out): back to the zone's spawn at 60% HP and WEAKENED. Team wipe = every player of the
--   zone downed. Leaving and re-entering the same zone within 30 s keeps the state (HP never refills mid-fight).
-- API
--   CombatRules.Config() -> merged ; CombatRules.SetConfig(tbl | nil)
--   CombatRules.New(cfg, now, maxHP?) -> st
--   CombatRules.SetMax(st, maxHP)                       H14 joins / leaves the team mid-fight (HP moves with it)
--   CombatRules.Damage(st, amount, now, cfg, opts?) -> applied, result, absorbed
--       opts {Taken = mult, Tick = bool (DPS: no i-frames)}; result "Hit" | "Down" | "Shield" | "IFrame" | "Downed" | "None"
--   CombatRules.Heal(st, amount) -> healed ; CombatRules.AddShield(st, amount, now, seconds?) -> shield
--   CombatRules.Down(st, now, cfg) ; CombatRules.Revive(st, now, cfg, opts {HP, Shield}?)
--   CombatRules.CanSelfRevive(st, now, cfg) -> ok, reason ; CombatRules.SelfReviveAt(st, cfg) -> server time
--   CombatRules.BleedOut(st, now, cfg) ; CombatRules.Undown(st, now, cfg)   (leaving while downed: no penalty)
--   CombatRules.Tick(st, now, dt, cfg) -> events {Regen = n?, BleedOut = true?, ShieldEnded = true?}
--   CombatRules.Weakened(st, now) ; CombatRules.DealtMult(st, now) ; CombatRules.TakenMult(st, now)
--   CombatRules.ReviveHold(cfg, reviverSpeed?, targetSpeed?) -> seconds
--   CombatRules.Wiped(states) -> bool ; CombatRules.Resumable(left, zoneId, now, cfg) -> bool
--   CombatRules.Shown(st) -> {HP, Max, Shield} rounded for attributes
local root = script.Parent
local BossMath = require(root:WaitForChild("BossMath"))

local CombatRules = {}

CombatRules.Defaults = {
	MaxHP = 100,
	H14MaxHP = 15,            -- ETERNAL VOW: +15 max Event HP
	IFrames = .6,             -- seconds of invulnerability after a hit
	RegenDelay = 8,           -- seconds without damage before regen
	RegenPerSecond = 2,
	DownedSeconds = 20,       -- bleed-out timer
	DownedWalkSpeed = 5,
	ReviveHold = 2.2,         -- seconds of hold on the REVIVE prompt
	ReviveRange = 9,
	ReviveSlack = .25,        -- seconds of latency tolerance on the server's hold check (plus 20% of the hold)
	ReviveHP = 40,
	H14ReviveSpeed = 2,       -- an H14 reviver revives 2x faster
	H11ReviveSpeed = 1.4,     -- revives on an H11 owner are 40% faster
	H14ReviveShield = 20,     -- shield an H14 reviver gives the revived ally
	ReviveShieldSeconds = 0,  -- 0 = the shield lasts until used or the fight ends
	SelfReviveAfter = 8,      -- H11: seconds downed before the self-revive
	SelfReviveHP = 40,
	BleedOutHPFrac = .6,
	ReEnterGrace = 30,        -- re-entering the same zone within this keeps HP / downed history
	H10Lead = .35,            -- CANDLELIGHT: telegraphs reach the owner this much earlier
	H10GasMult = .7,          -- CANDLELIGHT: mine gas deals -30%
	HazardRange = 220,        -- players this close to a hazard get its telegraph
	HazardGrace = .12,        -- a player outside at ImpactAt OR ImpactAt - grace is spared
	NearbyRange = 90,         -- others this close see a player's floating damage numbers / downed signal
	DPSTick = .5,             -- lingering hazards apply their damage per second in steps of this
	WipeGrace = 1.5,          -- after a wipe the encounter owner has this long before EventHP bleeds everyone out
	TickRate = 10,            -- server combat ticks per second
	DogRefresh = 5,           -- seconds between team-dog ability lookups
	Dogs = { Candle = "HW_CandleCorgi", Mourning = "HW_MourningShiba", Bride = "HW_Bridehound", Wolf = "HW_BellkeeperWolf" },
}

local override: any = nil
local cached: any = nil

local function num(v: any): number?
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

-- flat keys (the names of CombatRules.Defaults) over the defaults; WEAKENED falls back to `weak` (BossMath numbers)
local function resolve(src: any, weak: any): any
	local c = table.clone(CombatRules.Defaults)
	c.Dogs = table.clone(CombatRules.Defaults.Dogs)
	c.WeakenedSeconds, c.WeakenedDealt, c.WeakenedTaken = weak.Seconds, weak.Dealt, weak.Taken
	if type(src) == "table" then
		for k, v in pairs(src) do
			if k == "Dogs" and type(v) == "table" then
				for dk, dv in pairs(v) do
					if type(dv) == "string" then
						c.Dogs[dk] = dv
					end
				end
			elseif num(v) and type(c[k]) == "number" then
				c[k] = num(v)
			end
		end
	end
	return c
end

-- Chapter2Config (whole module) -> flat keys: .Combat (alias .EventHP) {MaxHP, ReenterKeep, IFrames, Downed {Seconds,
-- WalkSpeed}, Revive {Hold, Range, HP}, BleedOut {HPFraction, WeakenedSeconds}, Weakened {DamageDealt, DamageTaken},
-- Regen {PerSecond, After}, Tick, Hazards {Grace, SignalRadius}} (+ any flat Defaults key), and the ability numbers of
-- .Dogs.Defs: HW_CandleCorgi {TelegraphLead, GasReduction}, HW_MourningShiba {SelfReviveAfter, ReviveOnYouFaster},
-- HW_Bridehound {MaxHPBonus, ReviveSpeedMult, ReviveShield}
local function fromChapter2(m: any): any
	local out: { [string]: any } = {}
	if type(m) ~= "table" then
		return out
	end
	local cb = m.Combat or m.EventHP
	if type(cb) == "table" then
		for k, v in pairs(cb) do
			if type(v) == "number" then
				out[k] = v
			end
		end
		out.ReEnterGrace = cb.ReenterKeep or cb.ReEnterGrace
		local function sub(name: string, map: { [string]: string })
			local t = cb[name]
			if type(t) == "table" then
				for from, to in pairs(map) do
					if num(t[from]) then
						out[to] = num(t[from])
					end
				end
			end
		end
		sub("Downed", { Seconds = "DownedSeconds", WalkSpeed = "DownedWalkSpeed" })
		sub("Revive", { Hold = "ReviveHold", Range = "ReviveRange", HP = "ReviveHP" })
		sub("BleedOut", { HPFraction = "BleedOutHPFrac", WeakenedSeconds = "WeakenedSeconds" })
		sub("Weakened", { DamageDealt = "WeakenedDealt", DamageTaken = "WeakenedTaken" })
		sub("Regen", { PerSecond = "RegenPerSecond", After = "RegenDelay" })
		sub("Hazards", { Grace = "HazardGrace", SignalRadius = "HazardRange" })
		if num(cb.Tick) and (num(cb.Tick) :: number) > 0 then
			out.TickRate = 1 / (num(cb.Tick) :: number)
		end
	end
	local defs = type(m.Dogs) == "table" and m.Dogs.Defs
	if type(defs) == "table" then
		local candle, mourning, bride = defs.HW_CandleCorgi, defs.HW_MourningShiba, defs.HW_Bridehound
		if type(candle) == "table" then
			out.H10Lead = num(candle.TelegraphLead) or out.H10Lead
			if num(candle.GasReduction) then
				out.H10GasMult = 1 - (num(candle.GasReduction) :: number)
			end
		end
		if type(mourning) == "table" then
			out.SelfReviveAfter = num(mourning.SelfReviveAfter) or out.SelfReviveAfter
			if num(mourning.ReviveOnYouFaster) then
				out.H11ReviveSpeed = 1 + (num(mourning.ReviveOnYouFaster) :: number)
			end
		end
		if type(bride) == "table" then
			out.H14MaxHP = num(bride.MaxHPBonus) or out.H14MaxHP
			out.H14ReviveSpeed = num(bride.ReviveSpeedMult) or out.H14ReviveSpeed
			out.H14ReviveShield = num(bride.ReviveShield) or out.H14ReviveShield
		end
	end
	return out
end

CombatRules.FromChapter2 = fromChapter2 -- tests: the Chapter2Config mapping

function CombatRules.Config(): any
	if override then
		return override
	end
	if not cached then
		local m = nil
		pcall(function()
			local inst = root:FindFirstChild("Chapter2Config")
			m = inst and require(inst :: any)
		end)
		cached = resolve(fromChapter2(m), BossMath.Config().Weakened)
	end
	return cached
end

-- tests / Studio: flat Defaults keys over the built-in defaults (the real Chapter2Config is ignored); nil = live config
function CombatRules.SetConfig(tbl: any?)
	override = tbl and resolve(tbl, BossMath.Defaults.Weakened) or nil
	cached = nil
end

---------------------------------------------------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------------------------------------------------
function CombatRules.New(cfg: any, now: number, maxHP: number?): any
	local max = math.max(1, num(maxHP) or cfg.MaxHP)
	return {
		HP = max, MaxHP = max, Shield = 0, ShieldUntil = 0, IFrameUntil = -math.huge, LastHitAt = -math.huge,
		Downed = false, DownedAt = 0, DownedUntil = 0, WeakenedUntil = 0, SelfReviveUsed = false, Downs = 0, Revives = 0,
		StartedAt = now,
	}
end

function CombatRules.SetMax(st: any, maxHP: number)
	local max = math.max(1, num(maxHP) or st.MaxHP)
	if max == st.MaxHP then
		return
	end
	local diff = max - st.MaxHP
	st.MaxHP = max
	if not st.Downed then
		st.HP = math.clamp(st.HP + math.max(0, diff), 1, max)
	end
end

local function shieldLive(st: any, now: number): boolean
	return st.Shield > 0 and (st.ShieldUntil <= 0 or now < st.ShieldUntil)
end

function CombatRules.Damage(st: any, amount: number, now: number, cfg: any, opts: any?): (number, string, number)
	local o = opts or {}
	if st.Downed then
		return 0, "Downed", 0
	end
	local raw = math.max(0, num(amount) or 0) * math.max(0, num(o.Taken) or 1)
	if raw <= 0 then
		return 0, "None", 0
	end
	if not o.Tick and now < st.IFrameUntil then
		return 0, "IFrame", 0
	end
	local absorbed = 0
	if shieldLive(st, now) then
		absorbed = math.min(st.Shield, raw)
		st.Shield -= absorbed
		raw -= absorbed
		if st.Shield <= 1e-6 then
			st.Shield, st.ShieldUntil = 0, 0
		end
	end
	local applied = math.min(st.HP, raw)
	st.HP -= applied
	st.LastHitAt = now
	if not o.Tick then
		st.IFrameUntil = now + cfg.IFrames
	end
	if st.HP <= 1e-6 then
		st.HP = 0
		CombatRules.Down(st, now, cfg)
		return applied, "Down", absorbed
	end
	if applied <= 0 then
		return 0, "Shield", absorbed
	end
	return applied, "Hit", absorbed
end

function CombatRules.Heal(st: any, amount: number): number
	if st.Downed then
		return 0
	end
	local before = st.HP
	st.HP = math.min(st.MaxHP, st.HP + math.max(0, num(amount) or 0))
	return st.HP - before
end

function CombatRules.AddShield(st: any, amount: number, now: number, seconds: number?): number
	local add = math.max(0, num(amount) or 0)
	if add <= 0 then
		return st.Shield
	end
	if not shieldLive(st, now) then
		st.Shield, st.ShieldUntil = 0, 0
	end
	st.Shield += add
	local s = num(seconds) or 0
	if s > 0 then
		st.ShieldUntil = math.max(st.ShieldUntil, now + s)
	elseif st.ShieldUntil > 0 then
		st.ShieldUntil = 0 -- a lasting shield makes the whole pool last
	end
	return st.Shield
end

function CombatRules.Down(st: any, now: number, cfg: any)
	st.Downed = true
	st.HP = 0
	st.Shield, st.ShieldUntil = 0, 0
	st.DownedAt = now
	st.DownedUntil = now + cfg.DownedSeconds
	st.Downs += 1
end

function CombatRules.Revive(st: any, now: number, cfg: any, opts: any?)
	local o = opts or {}
	st.Downed = false
	st.HP = math.clamp(num(o.HP) or cfg.ReviveHP, 1, st.MaxHP)
	st.Shield, st.ShieldUntil = 0, 0
	if (num(o.Shield) or 0) > 0 then
		CombatRules.AddShield(st, o.Shield, now, cfg.ReviveShieldSeconds)
	end
	st.IFrameUntil = now + cfg.IFrames
	st.LastHitAt = now -- regen waits its full delay again
	st.DownedUntil = 0
	st.Revives += 1
end

function CombatRules.SelfReviveAt(st: any, cfg: any): number
	return st.DownedAt + cfg.SelfReviveAfter
end

function CombatRules.CanSelfRevive(st: any, now: number, cfg: any): (boolean, string?)
	if not st.Downed then
		return false, "NotDowned"
	end
	if st.SelfReviveUsed then
		return false, "Used"
	end
	if now + 1e-6 < CombatRules.SelfReviveAt(st, cfg) then
		return false, "TooSoon"
	end
	return true, nil
end

-- the bleed-out: up at 60% and WEAKENED (the caller moves the player to the zone spawn)
function CombatRules.BleedOut(st: any, now: number, cfg: any)
	st.Downed = false
	st.HP = math.max(1, math.ceil(st.MaxHP * cfg.BleedOutHPFrac))
	st.Shield, st.ShieldUntil = 0, 0
	st.WeakenedUntil = now + cfg.WeakenedSeconds
	st.IFrameUntil = now + cfg.IFrames
	st.LastHitAt = now
	st.DownedUntil = 0
end

-- leaving the zone while downed (the encounter ended): up again without a penalty, at the bleed-out HP
function CombatRules.Undown(st: any, now: number, cfg: any)
	if not st.Downed then
		return
	end
	st.Downed = false
	st.HP = math.max(1, math.ceil(st.MaxHP * cfg.BleedOutHPFrac))
	st.DownedUntil = 0
	st.LastHitAt = now
end

function CombatRules.Tick(st: any, now: number, dt: number, cfg: any): any
	local events = {}
	if st.Downed then
		if now >= st.DownedUntil then
			events.BleedOut = true
		end
		return events
	end
	if st.ShieldUntil > 0 and now >= st.ShieldUntil and st.Shield > 0 then
		st.Shield, st.ShieldUntil = 0, 0
		events.ShieldEnded = true
	end
	if st.HP < st.MaxHP and now - st.LastHitAt >= cfg.RegenDelay then
		local add = math.min(st.MaxHP - st.HP, cfg.RegenPerSecond * math.max(0, dt))
		if add > 0 then
			st.HP += add
			events.Regen = add
		end
	end
	return events
end

function CombatRules.Weakened(st: any, now: number): boolean
	return (st.WeakenedUntil or 0) > now
end

function CombatRules.DealtMult(st: any?, now: number): number
	return (st and CombatRules.Weakened(st, now)) and CombatRules.Config().WeakenedDealt or 1
end

function CombatRules.TakenMult(st: any?, now: number): number
	return (st and CombatRules.Weakened(st, now)) and CombatRules.Config().WeakenedTaken or 1
end

function CombatRules.ReviveHold(cfg: any, reviverSpeed: number?, targetSpeed: number?): number
	return cfg.ReviveHold / math.max(.1, (num(reviverSpeed) or 1) * (num(targetSpeed) or 1))
end

-- the hold the server accepts (latency: 20% shorter and ReviveSlack seconds early)
function CombatRules.ReviveAccept(cfg: any, hold: number): number
	return math.max(0, hold * .8 - cfg.ReviveSlack)
end

function CombatRules.Wiped(states: { any }): boolean
	local n = 0
	for _, st in ipairs(states) do
		n += 1
		if not st.Downed then
			return false
		end
	end
	return n > 0
end

-- left = {Zone, St, LeftAt}: the state of a player who left `zoneId` comes back if they return in time
function CombatRules.Resumable(left: any?, zoneId: string, now: number, cfg: any): boolean
	return left ~= nil and left.Zone == zoneId and now - left.LeftAt <= cfg.ReEnterGrace
end

local function round1(x: number): number
	return math.floor(x * 10 + .5) / 10
end

function CombatRules.Shown(st: any): any
	return { HP = round1(st.HP), Max = round1(st.MaxHP), Shield = round1(st.Shield) }
end

return CombatRules
