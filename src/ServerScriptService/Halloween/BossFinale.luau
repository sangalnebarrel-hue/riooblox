-- THE GRAVEKEEPER · difficulty V finale (ServerScriptService.Halloween.BossFinale, WP-C; docs/halloween2/DESIGN.md §11,
-- §23.2; docs/halloween2/BOSS.md). The FALSE VICTORY and the three post-death phases, run on the live Gravekeeper fight
-- (Boss.luau hands it over instead of defeat() when difficulty V reaches armor 0 with Shared.BossFinaleEnabled()):
--   FakeDeath (6 s) -> Bell (THE BELL TOLLS: break 4 chains with Perfect hits in the bright part of each 1.2 s pulse,
--   6 + 3 x (fighters - 1) counted hits each; shockwave rings with a gap every 6-8 s) -> Choir (THE BURIED CHOIR: hit
--   the 6 candles until they match the bell's pattern, the buried weak points open, break them; 3 rounds; ghost dogs and
--   spirit line volleys) -> Hound (THE LAST BARK: patterns on a 100 BPM beat grid; after each one the hound barks and
--   its jaw takes Perfect hits for 3 s, <= 6 counted per player per window, until the bark points run out) -> Victory
--   (finish "Defeated" once, the finale rewards) | Fail (wipe, nobody in the pit, or 7 min: the normal difficulty V
--   reward without the finale extras).
-- Everything that hurts is an EventHP hazard in zone "Boss" (RS.Halloween.BossPatterns builds and checks them); the
-- fight table F stays Boss's (Phase 5, Mode "Finale"); this module keeps F.Finale = its state and sets F.FinaleWon.
--
-- API (modules.BossFinale; Boss reaches it lazily)
--   BossFinale.Begin(F) ; BossFinale.Step(F, dt) ; BossFinale.Fail(F, reason "Wipe"|"Time"|"Empty") ;
--   BossFinale.OnFinish(F, outcome, reason) (Boss.finish) ; BossFinale.Reset() (the fight was released) ;
--   BossFinale.Debug(player, args {Stage?}) (C2Debug "Finale", Studio) ; BossFinale.Init(core, modules) (tests) ;
--   BossFinale.Start(core, modules) ; BossFinale.Now / Rand (default: Boss.Now / Boss.Rand)
-- RS.Halloween.State.Finale attributes: State ("" | "FakeDeath" | "Bell" | "Choir" | "Hound" | "Victory" | "Fail"), Stage
--   (0..6), StageStart, StageUntil, Chain ("N"|"E"|"S"|"W"|""), ChainsLeft, ChainHits, ChainNeed, ChainSince, Pulse, Bright,
--   Candles ("101100"), Pattern, Round, Rounds, WeakUntil, HoundHP, HoundMax, CounterUntil, Bpm, StartAt (hound beat 0),
--   BellCF, HoundCF, JawPos, Deadline, Reason (Fail), FightId, Revision.
-- Signal BossEvent {Kind = "Finale", Stage = FakeDeath | Bell | ChainActive | ChainHit | ChainBreak | BellToll | Choir |
--   Candle | Round | WeakOpen | Ghosts | Volley | Hound | HoundPattern | Bark | Counter | Victory | Fail, ...} (payloads at
--   each call; §23.2 + additive fields).
-- Strike kinds: FinaleChain (attr Key), FinaleCandle (attr Index, Lit), FinaleWeak, FinaleGhost, HoundJaw. Only fighters in
-- the pit may hit them; a downed player cannot strike (EventHP gate).
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local BossMath = require(Halloween:WaitForChild("BossMath"))
local Patterns = require(Halloween:WaitForChild("BossPatterns"))
local C2Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Layout = Shared.Layout

local FC = C2Cfg.Finale
local BossFinale = { Started = false, StrikeReady = false, StateRoot = nil :: Instance? }
BossFinale.CHAINS = { "N", "E", "S", "W" }
BossFinale.STAGES = { FakeDeath = 1, Bell = 2, Choir = 3, Hound = 4, Victory = 5, Fail = 6 }
BossFinale.TITLES = { FakeDeath = "FALSE VICTORY", Bell = "THE BELL TOLLS", Choir = "THE BURIED CHOIR", Hound = "THE LAST BARK",
	Victory = "THE LAST BARK", Fail = "THE BELL SILENCES YOU" }

local core, modules = nil, nil
local stateFolder: Folder? = nil

local V3 = Vector3.new
local PIT = Layout.Pit.Center

---------------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------------
local function boss(): any
	local b = modules and modules.Boss
	return type(b) == "table" and b or nil
end

local function api(): any
	local b = boss()
	return b and b.Api or nil
end

function BossFinale.Now(): number
	local b = boss()
	if b and type(b.Now) == "function" then
		return b.Now()
	end
	return workspace:GetServerTimeNow()
end

function BossFinale.Rand(a: number?, b: number?): number
	local m = boss()
	local x = (m and type(m.Rand) == "function") and m.Rand() or math.random()
	if a and b then
		return a + (b - a) * x
	end
	return x
end

local function now(): number
	return BossFinale.Now()
end

local function rand01(): number
	return BossFinale.Rand()
end

local function vec(t: any, default: Vector3): Vector3
	if type(t) == "table" then
		return V3(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0)
	end
	return default
end

local function signal(target: any, data: { [string]: any })
	local a = api()
	data.Kind = "Finale"
	if a then
		a.Signal(target, data)
	elseif core then
		core.Signal(target, "BossEvent", data)
	end
end

local function idOf(target: any): any
	return type(target) == "table" and (target.Id or target.TargetId) or target
end

local function fighters(F): number
	return math.max(1, #(F.FighterList or {}))
end

-- reward-share credit (Boss score) + the finale's own tally (the Victory top list)
local function credit(F, Fin, player: Player?, share: number, points: number)
	if not player then
		return
	end
	local a = api()
	if a then
		a.Score(F, player, share * math.max(1, F.MaxArmor or 1))
	end
	local uid = player.UserId
	Fin.Score[uid] = (Fin.Score[uid] or 0) + points
	Fin.Names[uid] = player.Name
end

local function hazards(F, defs: { any }, attack: string): { number }
	local a = api()
	if not a or #defs == 0 then
		return {}
	end
	return a.HazardWave(F, defs, 0, attack)
end

local function addTarget(F, Fin, spec: { [string]: any }, entry: { [string]: any }): any
	local a = api()
	if not a then
		return nil
	end
	entry.Finale = true
	local target = a.AddTarget(F, spec, entry)
	if target then
		Fin.Targets[target] = entry
	end
	return target
end

local function removeTarget(F, Fin, target: any, reason: string?)
	if target == nil then
		return
	end
	Fin.Targets[target] = nil
	local a = api()
	if a then
		a.RemoveTarget(F, target, reason or "Finale")
	end
end

local function setPartAttr(target: any, name: string, value: any)
	local part = type(target) == "table" and target.Part or nil
	if part and part.Parent then
		pcall(function()
			part:SetAttribute(name, value)
		end)
	end
end

local function bits(list: { boolean }): string
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v and "1" or "0"
	end
	return table.concat(out)
end

local function pingOf(player: Player): number
	local ok, v = pcall(function()
		return player:GetNetworkPing()
	end)
	return math.clamp((ok and tonumber(v)) or 0, 0, 1)
end

---------------------------------------------------------------------------------------------------------------------
-- published state (RS.Halloween.State.Finale)
---------------------------------------------------------------------------------------------------------------------
local function ensureState()
	if stateFolder and stateFolder.Parent then
		return stateFolder
	end
	local st = BossFinale.StateRoot or Halloween:FindFirstChild("State") -- (tests: BossFinale.StateRoot = a Folder)
	if not st then
		return nil
	end
	local f = st:FindFirstChild("Finale")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Finale"
		f.Parent = st
	end
	stateFolder = f
	return f
end

local function setAttr(name: string, value: any)
	local f = ensureState()
	if f and f:GetAttribute(name) ~= value then
		f:SetAttribute(name, value)
	end
end

local IDLE = {
	State = "", Stage = 0, StageStart = 0, StageUntil = 0, Chain = "", ChainsLeft = 0, ChainHits = 0, ChainNeed = 0, ChainSince = 0,
	Pulse = 0, Bright = 0, Candles = "", Pattern = "", Round = 0, Rounds = 0, WeakUntil = 0, HoundHP = 0, HoundMax = 0, CounterUntil = 0,
	Bpm = 0, StartAt = 0, Deadline = 0, Reason = "", FightId = "",
}

local function publish(Fin: any?)
	if not ensureState() then
		return
	end
	if not Fin then
		for k, v in pairs(IDLE) do
			setAttr(k, v)
		end
		setAttr("BellCF", nil)
		setAttr("HoundCF", nil)
		setAttr("JawPos", nil)
	else
		local ch = Fin.Active and Fin.Chains and Fin.Chains[Fin.Active]
		setAttr("State", Fin.State)
		setAttr("Stage", BossFinale.STAGES[Fin.State] or 0)
		setAttr("StageStart", Fin.StageStart or 0)
		setAttr("StageUntil", Fin.StageUntil or 0)
		setAttr("Chain", Fin.Active or "")
		setAttr("ChainsLeft", Fin.ChainsLeft or 0)
		setAttr("ChainHits", ch and math.floor(ch.Hits + 1e-6) or 0)
		setAttr("ChainNeed", ch and ch.Need or 0)
		setAttr("ChainSince", ch and ch.Since or 0)
		setAttr("Pulse", FC.Bell.PulsePeriod)
		setAttr("Bright", FC.Bell.Bright or .55)
		setAttr("Candles", Fin.Candles and bits(Fin.Candles) or "")
		setAttr("Pattern", Fin.Pattern and bits(Fin.Pattern) or "")
		setAttr("Round", Fin.Round or 0)
		setAttr("Rounds", Fin.Rounds or 0)
		setAttr("WeakUntil", Fin.WeakOpen and Fin.WeakUntil or 0)
		setAttr("HoundHP", Fin.HoundHP and math.max(0, math.ceil(Fin.HoundHP - 1e-6)) or 0)
		setAttr("HoundMax", Fin.HoundMax or 0)
		setAttr("CounterUntil", Fin.CounterUntil or 0)
		setAttr("Bpm", Fin.HoundMax and FC.Hound.BPM or 0)
		setAttr("StartAt", Fin.StartAt or 0)
		setAttr("Deadline", Fin.Deadline or 0)
		setAttr("Reason", Fin.Reason or "")
		setAttr("FightId", Fin.Fight or "")
		setAttr("BellCF", Fin.BellCF)
		setAttr("HoundCF", Fin.HoundCF)
		setAttr("JawPos", Fin.JawPos)
	end
	local f = ensureState()
	if f then
		f:SetAttribute("Revision", (f:GetAttribute("Revision") or 0) + 1)
	end
end
BossFinale.Publish = publish

local function enter(F, Fin, state: string, untilAt: number?)
	local t = now()
	Fin.State = state
	Fin.StageStart = t
	Fin.StageUntil = untilAt or Fin.Deadline
	F.PhaseName = BossFinale.TITLES[state] or state
	local a = api()
	if a then
		a.SetAttr("PhaseName", F.PhaseName)
		a.Bump()
	end
	publish(Fin)
end

---------------------------------------------------------------------------------------------------------------------
-- geometry (from Layout.Pit and the config offsets)
---------------------------------------------------------------------------------------------------------------------
function BossFinale.BellCF(): CFrame
	return CFrame.new(PIT + V3(0, FC.Bell.Height or 28, 0))
end

-- the four rim anchors (the tops of the N / E / S / W ramps)
function BossFinale.Anchors(): { [string]: Vector3 }
	local out = {}
	for _, r in ipairs(Layout.Pit.Ramps) do
		out[r.Id] = V3(r.Top.X, r.Top.Y + 1, r.Top.Z)
	end
	return out
end

-- where a chain's hittable link hangs: ChainAlong of the way from its rim anchor to the bell
function BossFinale.ChainPos(key: string): Vector3
	local anchor = BossFinale.Anchors()[key] or PIT
	return anchor:Lerp(BossFinale.BellCF().Position, FC.Bell.ChainAlong or .25)
end

-- six candles on the terrace ring: two on the east and west sides, one each on the north and south sides, off the ramps
local CANDLE_OFFSETS = { { 27, -11 }, { 27, 11 }, { 11, 27 }, { -27, 11 }, { -27, -11 }, { -11, -27 } }
function BossFinale.CandlePositions(): { Vector3 }
	local out = {}
	for i, o in ipairs(CANDLE_OFFSETS) do
		local x, z = PIT.X + o[1], PIT.Z + o[2]
		local y = Patterns.Surface(x, z)
		out[i] = V3(x, y, z)
	end
	return out
end

function BossFinale.HoundCF(): CFrame
	local pos = PIT + vec(FC.Hound.HoundOffset, V3(0, 0, 50))
	return CFrame.lookAt(pos, V3(PIT.X, pos.Y, PIT.Z))
end

function BossFinale.JawPos(): Vector3
	return PIT + vec(FC.Hound.JawOffset, V3(0, 10, 18))
end

function BossFinale.ChainNeed(n: number): number
	return (FC.Bell.ChainHits or 6) + (FC.Bell.ChainHitsPerFighter or 3) * math.max(0, math.floor(n) - 1)
end

function BossFinale.HoundPoints(n: number): number
	return (FC.Hound.BarkPoints or 24) + (FC.Hound.BarkPointsPerFighter or 10) * math.max(0, math.floor(n) - 1)
end

-- is server time t inside the bright part of a chain pulse that started at `since` (edge grace on both ends)
function BossFinale.Bright(t: number, since: number): boolean
	local pulse = FC.Bell.PulsePeriod or 1.2
	local bright = FC.Bell.Bright or .55
	local grace = FC.Bell.EdgeGrace or .04
	local ph = ((t - since) % pulse) / pulse
	return ph < bright + grace / pulse or ph > 1 - grace / pulse
end

---------------------------------------------------------------------------------------------------------------------
-- stage: FALSE VICTORY
---------------------------------------------------------------------------------------------------------------------
function BossFinale.Begin(F)
	ensureState()
	BossFinale.RegisterStrike()
	local t = now()
	local Fin = { State = "", Start = t, Deadline = t + (FC.TimeLimit or 420), Score = {}, Names = {}, Fight = F.Id, Targets = {},
		Ghosts = {}, BellCF = BossFinale.BellCF() }
	F.Finale = Fin
	F.FinaleWon = false
	-- the boss's own clock: past the finale deadline (the finale fails first; Boss keeps a backstop)
	F.EndsAt = Fin.Deadline + 30
	local a = api()
	if a then
		a.SetAttr("EndsAt", F.EndsAt)
	end
	local seconds = FC.FakeDeath.Seconds or 6
	enter(F, Fin, "FakeDeath", t + seconds)
	-- Finale FakeDeath {At, Seconds}: music hard stop, the collapse, the fake reward flash, silence, the toll, "...not yet"
	signal("zone", { Stage = "FakeDeath", At = t, Seconds = seconds, Silence = FC.FakeDeath.Silence, Deadline = Fin.Deadline })
end

---------------------------------------------------------------------------------------------------------------------
-- stage: THE BELL TOLLS
---------------------------------------------------------------------------------------------------------------------
local function startBell(F, Fin)
	local t = now()
	enter(F, Fin, "Bell")
	local anchors = BossFinale.Anchors()
	local start = math.clamp(math.floor(BossFinale.Rand(1, 4.999)), 1, 4)
	Fin.Order = {}
	Fin.Chains = {}
	for i = 0, 3 do
		local key = BossFinale.CHAINS[((start - 1 + i) % 4) + 1]
		table.insert(Fin.Order, key)
		Fin.Chains[key] = { Key = key, Anchor = anchors[key], Hits = 0, Need = 0, Broken = false }
	end
	Fin.ChainsLeft = 4
	Fin.Active = nil
	local descend = FC.Bell.Descend or 2.5
	Fin.NextChainAt = t + descend
	Fin.NextTollAt = t + descend + (FC.Bell.FirstToll or 3)
	local need = BossFinale.ChainNeed(fighters(F))
	publish(Fin)
	-- Finale Bell {StartAt, BellCF, Chains {N, E, S, W = rim anchors}, Pulse, Bright, Need, Order, Descend}
	signal("zone", { Stage = "Bell", StartAt = t, BellCF = Fin.BellCF, Chains = anchors, Pulse = FC.Bell.PulsePeriod, Bright = FC.Bell.Bright,
		Need = need, Order = table.clone(Fin.Order), Descend = descend })
end

local function activateChain(F, Fin)
	local key = nil
	for _, k in ipairs(Fin.Order) do
		if not Fin.Chains[k].Broken then
			key = k
			break
		end
	end
	if not key then
		return
	end
	local t = now()
	local ch = Fin.Chains[key]
	ch.Need = BossFinale.ChainNeed(fighters(F))
	ch.Since = t
	ch.Hits = 0
	Fin.Active = key
	Fin.NextChainAt = nil
	local pos = BossFinale.ChainPos(key)
	addTarget(F, Fin, { Kind = "FinaleChain", Position = pos, Radius = 2.6, HP = 1e9, MaxHP = 1e9, Panel = false, Color = Color3.fromRGB(150, 80, 230),
		Material = "Metal", Size = V3(4, 4, 4), Name = "CURSED CHAIN", NameRU = "ПРОКЛЯТАЯ ЦЕПЬ", Variant = key,
		Attributes = { Key = key, Since = t, Pulse = FC.Bell.PulsePeriod, Bright = FC.Bell.Bright, Need = ch.Need } },
		ch)
	publish(Fin)
	-- Finale ChainActive {Key, Since (pulse phase 0), Pulse, Bright, Need, Hits, TargetId}
	signal("zone", { Stage = "ChainActive", Key = key, Since = t, Pulse = FC.Bell.PulsePeriod, Bright = FC.Bell.Bright, Need = ch.Need, Hits = 0,
		TargetId = idOf(ch.Target), Position = pos })
end

local function breakChain(F, Fin, key: string)
	local ch = Fin.Chains and Fin.Chains[key]
	if not ch or ch.Broken then
		return
	end
	ch.Broken = true
	if ch.Target then
		removeTarget(F, Fin, ch.Target, "Broke")
		ch.Target = nil
	end
	Fin.Active = nil
	local left = 0
	for _, c in pairs(Fin.Chains) do
		if not c.Broken then
			left += 1
		end
	end
	Fin.ChainsLeft = left
	local t = now()
	if left == 0 then
		Fin.ChoirAt = t + (FC.Choir.StartDelay or 1.5)
	else
		Fin.NextChainAt = t + (FC.Bell.BreakPause or 1.5)
	end
	publish(Fin)
	-- Finale ChainBreak {Key, Left}
	signal("zone", { Stage = "ChainBreak", Key = key, Left = left })
end

local function toll(F, Fin)
	local t = now()
	local a = api()
	local defs, info = Patterns.Shockwave(t, a and a.Lead() or .35, rand01)
	local ids = hazards(F, defs, "Shockwave")
	local first = math.huge
	for _, d in ipairs(defs) do
		first = math.min(first, d.ImpactAt)
	end
	local every = FC.Bell.ShockwaveEvery or { 6, 8 }
	Fin.NextTollAt = t + BossFinale.Rand(every[1], every[2])
	-- Finale BellToll {At (impact of the first ring), HazardIds, Rings}
	signal("zone", { Stage = "BellToll", At = first < math.huge and first or info.Ends, HazardIds = ids, Rings = #defs })
end

local function stepBell(F, Fin, t: number)
	if Fin.PendingBreak then
		local key = Fin.PendingBreak
		Fin.PendingBreak = nil
		breakChain(F, Fin, key)
	end
	if Fin.ChoirAt then
		return
	end
	if not Fin.Active and Fin.NextChainAt and t >= Fin.NextChainAt then
		activateChain(F, Fin)
	end
	if t >= (Fin.NextTollAt or math.huge) then
		toll(F, Fin)
	end
end

-- a hit on the ACTIVE chain counts when it is a Perfect landed in the bright part of the pulse (the bell is immune to
-- everything else); H15 Bellkeeper Wolf counts x1.25
local function onChainHit(player: Player, target: any, hit: any)
	if type(hit) == "table" then
		hit.Applied = 0
	end
	local F = boss() and boss().Fight
	local Fin = F and F.Finale
	local entry = Fin and Fin.Targets[target]
	if not Fin or Fin.State ~= "Bell" or not entry or entry.Key ~= Fin.Active or entry.Broken then
		return { Counted = false, Reason = "Immune" }
	end
	local ch = entry
	local t = now()
	local counted, reason = false, nil
	if tonumber(type(hit) == "table" and hit.Quality) ~= 2 then
		reason = "Immune"
	else
		local back = math.min(pingOf(player), FC.Bell.PingGrace or .25)
		if BossFinale.Bright(t, ch.Since) or BossFinale.Bright(t - back, ch.Since) then
			counted = true
		else
			reason = "Toll"
		end
	end
	if counted then
		local a = api()
		local add = (a and a.HasDog(player, "Wolf")) and BossMath.H15Mult(true) or 1
		ch.Hits += add
		credit(F, Fin, player, (FC.Bell.ChainScore or .004) * add, add)
		if ch.Hits >= ch.Need - 1e-6 and not Fin.PendingBreak then
			Fin.PendingBreak = ch.Key
		end
		setPartAttr(ch.Target, "Hits", math.floor(ch.Hits + 1e-6))
		publish(Fin)
	end
	-- Finale ChainHit {Key, Hits, Need, UserId, Counted, Reason ("Immune": not a Perfect | "Toll": outside the bright part)}
	signal("zone", { Stage = "ChainHit", Key = ch.Key, Hits = math.floor(ch.Hits + 1e-6), Need = ch.Need, UserId = player.UserId, Counted = counted,
		Reason = reason })
	return { Counted = counted, Reason = reason, Hits = math.floor(ch.Hits + 1e-6), Need = ch.Need }
end

---------------------------------------------------------------------------------------------------------------------
-- stage: THE BURIED CHOIR
---------------------------------------------------------------------------------------------------------------------
local function newPattern(current: { boolean }): { boolean }
	local n = #current
	for _ = 1, 40 do
		local p = {}
		local lit, diff = 0, 0
		for i = 1, n do
			p[i] = rand01() < .5
			if p[i] then
				lit += 1
			end
			if p[i] ~= current[i] then
				diff += 1
			end
		end
		if lit > 0 and lit < n and diff >= 2 then
			return p
		end
	end
	-- deterministic fallback: flip two candles
	local p = table.clone(current)
	p[1], p[n] = not p[1], not p[n]
	return p
end

local function matches(Fin): boolean
	for i, v in ipairs(Fin.Candles) do
		if v ~= Fin.Pattern[i] then
			return false
		end
	end
	return true
end

local function startChoir(F, Fin)
	local t = now()
	Fin.ChoirAt = nil
	enter(F, Fin, "Choir")
	local count = FC.Choir.Candles or 6
	local positions = BossFinale.CandlePositions()
	Fin.Candles = {}
	for i = 1, count do
		Fin.Candles[i] = rand01() < .5
	end
	Fin.Pattern = newPattern(Fin.Candles)
	Fin.Round, Fin.Rounds = 1, FC.Choir.Rounds or 3
	Fin.CandleTargets = {}
	Fin.CandleAt = {}
	local list = {}
	for i = 1, count do
		local pos = positions[((i - 1) % #positions) + 1]
		local entry = { Index = i, Role = "Candle", Pos = pos }
		addTarget(F, Fin, { Kind = "FinaleCandle", Position = pos + V3(0, 2.5, 0), Radius = 1.6, HP = 1e9, MaxHP = 1e9, Panel = false,
			Color = Color3.fromRGB(255, 170, 80), Material = "Neon", Size = V3(2.4, 5, 2.4), Name = "CURSED CANDLE", NameRU = "ПРОКЛЯТАЯ СВЕЧА",
			Variant = "Candle", Ground = pos, Attributes = { Index = i, Lit = Fin.Candles[i] } }, entry)
		Fin.CandleTargets[i] = entry
		Fin.CandleAt[i] = 0
		table.insert(list, { Position = pos, Lit = Fin.Candles[i], TargetId = idOf(entry.Target) })
	end
	Fin.NextGhostAt = t + (FC.Choir.FirstGhosts or 4)
	Fin.NextVolleyAt = t + (FC.Choir.FirstVolley or 6)
	publish(Fin)
	-- Finale Choir {StartAt, Candles {[i] = {Position, Lit, TargetId}}, Pattern, Round, Rounds}
	signal("zone", { Stage = "Choir", StartAt = t, Candles = list, Pattern = bits(Fin.Pattern), Round = 1, Rounds = Fin.Rounds })
end

local function openWeak(F, Fin)
	local t = now()
	local spots = table.clone(Layout.Boss.Mounds)
	for i = #spots, 2, -1 do
		local j = math.clamp(1 + math.floor(rand01() * i), 1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	local n = math.min(FC.Choir.WeakPoints or 3, #spots)
	local hp = (FC.Choir.WeakHP or 10) + (FC.Choir.WeakHPPerFighter or 5) * (fighters(F) - 1)
	Fin.WeakOpen = true
	Fin.WeakUntil = t + (FC.Choir.WeakSeconds or 20)
	Fin.WeakLeft = n
	Fin.WeakTargets = {}
	local points = {}
	for i = 1, n do
		local pos = spots[i]
		local entry = { Role = "Weak", Pos = pos, Index = i }
		local target = addTarget(F, Fin, { Kind = "FinaleWeak", Position = pos + V3(0, 1.2, 0), Radius = 3.4, HP = hp, MaxHP = hp, Unit = 1,
			Color = Color3.fromRGB(120, 255, 140), Material = "Neon", Size = V3(6.5, 2.6, 6.5), Name = "BURIED WEAK POINT",
			NameRU = "ПОГРЕБЁННОЕ СЛАБОЕ МЕСТО", Seed = i, Ground = pos, Attributes = { Index = i } }, entry)
		if target then
			table.insert(Fin.WeakTargets, entry)
			table.insert(points, { Id = idOf(target), Position = pos })
		end
	end
	Fin.WeakLeft = #Fin.WeakTargets
	publish(Fin)
	-- Finale WeakOpen {Points {{Id, Position}}, Until, Round}
	signal("zone", { Stage = "WeakOpen", Points = points, Until = Fin.WeakUntil, Round = Fin.Round })
end

local function closeWeak(F, Fin)
	for _, e in ipairs(Fin.WeakTargets or {}) do
		if e.Target and not e.Broken then
			removeTarget(F, Fin, e.Target, "Closed")
		end
	end
	Fin.WeakTargets = {}
	Fin.WeakOpen = false
	Fin.WeakUntil = 0
end

local function nextRound(F, Fin, cleared: boolean)
	local t = now()
	closeWeak(F, Fin)
	if cleared then
		-- Finale Round {Round, Pattern, Cleared = true}
		signal("zone", { Stage = "Round", Round = Fin.Round, Pattern = bits(Fin.Pattern), Cleared = true })
		Fin.Round += 1
		if Fin.Round > Fin.Rounds then
			Fin.Round = Fin.Rounds
			Fin.HoundAt = t + (FC.Choir.HoundDelay or 2.5)
			publish(Fin)
			return
		end
	end
	Fin.Pattern = newPattern(Fin.Candles)
	publish(Fin)
	-- Finale Round {Round, Pattern, Cleared = false, Reset (the weak points closed unbroken: same round again)}
	signal("zone", { Stage = "Round", Round = Fin.Round, Pattern = bits(Fin.Pattern), Cleared = false, Reset = (not cleared) or nil })
end

local function spawnGhosts(F, Fin)
	local c = FC.Choir
	local alive = 0
	for _ in pairs(Fin.Ghosts) do
		alive += 1
	end
	local want = math.min((c.GhostCount or 2) + (c.GhostPerFighter or 1) * (fighters(F) - 1), math.max(0, (c.GhostMax or 8) - alive))
	if want <= 0 then
		return
	end
	local t = now()
	local spawns = Layout.Boss.SkeletonSpawns
	local list = {}
	Fin.GhostSerial = Fin.GhostSerial or 0
	for i = 1, want do
		Fin.GhostSerial += 1
		local key = Fin.GhostSerial
		local base = spawns[((key - 1) % #spawns) + 1]
		local pos = V3(base.X + BossFinale.Rand(-2, 2), Layout.Pit.FloorY, base.Z + BossFinale.Rand(-2, 2))
		local entry = { Key = key, Pos = pos, Yaw = 0, NextBite = t + 2 + i * .2, Role = "Ghost" }
		local target = addTarget(F, Fin, { Kind = "FinaleGhost", Position = pos + V3(0, 1.9, 0), Radius = 2.4, HP = c.GhostHP or 3,
			MaxHP = c.GhostHP or 3, Unit = 1, Color = Color3.fromRGB(150, 200, 255), Material = "ForceField", Size = V3(3, 3.6, 5),
			Name = "GHOST DOG", NameRU = "ПРИЗРАЧНЫЙ ПЁС", Seed = key, Ground = pos, Attributes = { Key = key } }, entry)
		if target then
			Fin.Ghosts[key] = entry
			table.insert(list, { TargetId = idOf(target), Position = pos, Key = key })
		end
	end
	-- Finale Ghosts {Count, Spawns {{TargetId, Position, Key}}}
	signal("zone", { Stage = "Ghosts", Count = #list, Spawns = list })
end

local function stepGhosts(F, Fin, dt: number, t: number)
	local c = FC.Choir
	local a = api()
	if not a then
		return
	end
	local arena = Layout.Pit.Arena
	local targets = a.Targetable(F)
	for key, g in pairs(Fin.Ghosts) do
		if g.Removed then
			Fin.Ghosts[key] = nil
			continue
		end
		local best, bestPos, bestD = nil, nil, math.huge
		for _, pl in ipairs(targets) do
			local p = a.RootPos(pl)
			if p then
				local d = V3(p.X - g.Pos.X, 0, p.Z - g.Pos.Z).Magnitude
				if d < bestD then
					best, bestPos, bestD = pl, p, d
				end
			end
		end
		if bestPos then
			local delta = V3(bestPos.X - g.Pos.X, 0, bestPos.Z - g.Pos.Z)
			if delta.Magnitude > 3 then
				local step = delta.Unit * math.min(delta.Magnitude - 2.5, (c.GhostSpeed or 9) * dt)
				local np = g.Pos + step
				g.Pos = V3(math.clamp(np.X, arena.X0 + 1.5, arena.X1 - 1.5), Layout.Pit.FloorY, math.clamp(np.Z, arena.Z0 + 1.5, arena.Z1 - 1.5))
			end
			if delta.Magnitude > .2 then
				g.Yaw = math.atan2(-delta.X, -delta.Z)
			end
			if g.Target then
				a.MoveTarget(g.Target, CFrame.new(g.Pos + V3(0, 1.9, 0)) * CFrame.Angles(0, g.Yaw, 0))
			end
			-- the lunge: a telegraphed bite circle where the player stands now
			if best and bestD <= (c.GhostLunge or 6) and t >= g.NextBite then
				g.NextBite = t + (c.GhostBiteCooldown or 2.6)
				local def = Patterns.GhostBite(V3(bestPos.X, Layout.Pit.FloorY, bestPos.Z), t, a.Lead())
				local ids = hazards(F, { def }, "Bite")
				-- Finale GhostBite {Key, TargetId, UserId, Position, HazardId, ImpactAt} (the ghost lunges)
				signal("zone", { Stage = "GhostBite", Key = key, TargetId = idOf(g.Target), UserId = best.UserId, Position = def.Shape.Center,
					HazardId = ids[1], ImpactAt = def.ImpactAt })
			end
		end
	end
end

local function volley(F, Fin, t: number)
	local a = api()
	local defs = Patterns.Volley(t, a and a.Lead() or .35, rand01, { Targets = a and a.TargetPositions(F) or {} })
	local ids = hazards(F, defs, "Volley")
	local every = FC.Choir.VolleyEvery or { 5, 8 }
	Fin.NextVolleyAt = t + BossFinale.Rand(every[1], every[2])
	local from = #defs > 0 and defs[1].Shape.From or PIT
	-- Finale Volley {At, From, HazardIds} (the Gravekeeper's spirit throws from the rim)
	signal("zone", { Stage = "Volley", At = t, From = from, HazardIds = ids })
end

local function clearChoir(F, Fin)
	closeWeak(F, Fin)
	for _, e in ipairs(Fin.CandleTargets or {}) do
		if e.Target then
			removeTarget(F, Fin, e.Target, "Choir")
		end
	end
	Fin.CandleTargets = {}
	for key, g in pairs(Fin.Ghosts) do
		if g.Target then
			removeTarget(F, Fin, g.Target, "Choir")
		end
		Fin.Ghosts[key] = nil
	end
end

local startHound

local function stepChoir(F, Fin, dt: number, t: number)
	if Fin.HoundAt then
		if t >= Fin.HoundAt then
			Fin.HoundAt = nil
			clearChoir(F, Fin)
			startHound(F, Fin)
		end
		return
	end
	if Fin.WeakOpen then
		if (Fin.WeakLeft or 0) <= 0 then
			nextRound(F, Fin, true)
		elseif t >= Fin.WeakUntil then
			nextRound(F, Fin, false)
		end
	elseif Fin.PendingMatch or matches(Fin) then
		Fin.PendingMatch = nil
		if matches(Fin) then
			openWeak(F, Fin)
		end
	end
	if Fin.HoundAt then
		return
	end
	if t >= (Fin.NextGhostAt or math.huge) then
		Fin.NextGhostAt = t + (FC.Choir.GhostWaveEvery or 14)
		spawnGhosts(F, Fin)
	end
	if t >= (Fin.NextVolleyAt or math.huge) then
		volley(F, Fin, t)
	end
	stepGhosts(F, Fin, dt, t)
end

-- a hit toggles the candle (a short cooldown keeps two simultaneous hits from cancelling out); locked while the weak
-- points are open
local function onCandleHit(player: Player, target: any, hit: any)
	if type(hit) == "table" then
		hit.Applied = 0
	end
	local F = boss() and boss().Fight
	local Fin = F and F.Finale
	local entry = Fin and Fin.Targets[target]
	if not Fin or Fin.State ~= "Choir" or not entry or entry.Role ~= "Candle" then
		return { Locked = true }
	end
	if Fin.WeakOpen or Fin.HoundAt then
		return { Locked = true }
	end
	local t = now()
	local i = entry.Index
	if t - (Fin.CandleAt[i] or 0) < (FC.Choir.CandleCooldown or .45) then
		return { Locked = true, Cooldown = true }
	end
	Fin.CandleAt[i] = t
	local lit = not Fin.Candles[i]
	Fin.Candles[i] = lit
	setPartAttr(entry.Target, "Lit", lit)
	-- a flip that puts the candle right is credited (wrong flips are not)
	if lit == Fin.Pattern[i] then
		credit(F, Fin, player, FC.Choir.CandleScore or .002, 1)
	end
	if matches(Fin) then
		Fin.PendingMatch = true
	end
	publish(Fin)
	-- Finale Candle {Index, Lit, UserId, Candles, Match}
	signal("zone", { Stage = "Candle", Index = i, Lit = lit, UserId = player.UserId, Candles = bits(Fin.Candles), Match = Fin.PendingMatch or nil })
	return { Index = i, Lit = lit }
end

-- FinaleWeak damage: tier-normalised power (any hit), H15 x1.25
local function weakDamage(player: Player, _target: any, hit: any): number
	local power = tonumber(type(hit) == "table" and hit.Power) or 1
	local a = api()
	if a and a.HasDog(player, "Wolf") then
		power *= BossMath.H15Mult(true)
	end
	return power
end

local function onWeakBreak(player: Player?, target: any, info: any)
	local F = boss() and boss().Fight
	local Fin = F and F.Finale
	local entry = Fin and Fin.Targets[target]
	if not Fin or not entry or entry.Role ~= "Weak" or entry.Broken then
		return
	end
	entry.Broken = true
	Fin.Targets[target] = nil
	Fin.WeakLeft = math.max(0, (Fin.WeakLeft or 1) - 1)
	-- every digger shares the credit by their damage
	local total, shares = 0, {}
	if type(info) == "table" and type(info.Contributors) == "table" then
		for _, c in pairs(info.Contributors) do
			if type(c) == "table" and c.Player and (tonumber(c.Damage) or 0) > 0 then
				total += c.Damage
				table.insert(shares, c)
			end
		end
	end
	for _, c in ipairs(shares) do
		credit(F, Fin, c.Player, (FC.Choir.WeakScore or .02) * c.Damage / total, 2 * c.Damage / total)
	end
	if #shares == 0 then
		credit(F, Fin, player, FC.Choir.WeakScore or .02, 2)
	end
	publish(Fin)
end

local function onGhostBreak(player: Player?, target: any, _info: any)
	local F = boss() and boss().Fight
	local Fin = F and F.Finale
	local entry = Fin and Fin.Targets[target]
	if not Fin or not entry or entry.Role ~= "Ghost" then
		return
	end
	Fin.Targets[target] = nil
	entry.Removed = true
	Fin.Ghosts[entry.Key] = nil
	credit(F, Fin, player, FC.Choir.GhostScore or .006, 1)
	-- Finale GhostDown {Key, TargetId, UserId, Position}
	signal("zone", { Stage = "GhostDown", Key = entry.Key, TargetId = idOf(target), UserId = player and player.UserId or 0, Position = entry.Pos })
end

---------------------------------------------------------------------------------------------------------------------
-- stage: THE LAST BARK
---------------------------------------------------------------------------------------------------------------------
local function beatLen(): number
	return 60 / (FC.Hound.BPM or 100)
end

-- the first grid beat at or after time t
local function nextBeat(Fin, t: number): number
	local b = beatLen()
	local k = math.ceil((t - Fin.StartAt) / b - 1e-6)
	return Fin.StartAt + math.max(0, k) * b
end

startHound = function(F, Fin)
	local t = now()
	enter(F, Fin, "Hound")
	local n = fighters(F)
	Fin.HoundMax = BossFinale.HoundPoints(n)
	Fin.HoundHP = Fin.HoundMax
	Fin.StartAt = t + (FC.Hound.Rise or 3)
	Fin.NextPatternAt = Fin.StartAt + (FC.Hound.LeadBeats or 2) * beatLen()
	Fin.Current = nil
	Fin.CounterUntil = nil
	Fin.HoundCF = BossFinale.HoundCF()
	Fin.JawPos = BossFinale.JawPos()
	Fin.Order = {}
	Fin.OrderIndex = 0
	local moon = vec(FC.Hound.MoonDir, V3(0, .35, 1))
	publish(Fin)
	-- Finale Hound {StartAt (beat 0; FINALE_HOUND anchored here), Bpm, HoundCF, MoonDir, HP, Max, JawPos}
	signal("zone", { Stage = "Hound", StartAt = Fin.StartAt, Bpm = FC.Hound.BPM, HoundCF = Fin.HoundCF, MoonDir = moon.Unit, HP = Fin.HoundHP,
		Max = Fin.HoundMax, JawPos = Fin.JawPos })
end

local function nextPatternName(Fin): string
	Fin.OrderIndex += 1
	if Fin.OrderIndex > #Fin.Order then
		local last = Fin.Order[#Fin.Order]
		local list = table.clone(Patterns.HoundPatterns)
		for i = #list, 2, -1 do
			local j = math.clamp(1 + math.floor(rand01() * i), 1, i)
			list[i], list[j] = list[j], list[i]
		end
		if list[1] == last and #list > 1 then
			list[1], list[2] = list[2], list[1]
		end
		Fin.Order = list
		Fin.OrderIndex = 1
	end
	return Fin.Order[Fin.OrderIndex]
end

local function startHoundPattern(F, Fin)
	local a = api()
	local beatAt = Fin.NextPatternAt
	local name = nextPatternName(Fin)
	local positions = a and a.TargetPositions(F) or {}
	local intensity = (Fin.HoundHP or 0) <= (Fin.HoundMax or 1) / 2 and 1 or 0
	local defs, beats = Patterns.Hound(name, beatAt, beatLen(), rand01, { Targets = positions, Fighters = fighters(F), Intensity = intensity })
	local ids = hazards(F, defs, name)
	Fin.Current = { Name = name, BeatAt = beatAt, Beats = beats, Ids = ids }
	Fin.BarkAt = beatAt + beats * beatLen()
	Fin.NextPatternAt = nil
	publish(Fin)
	-- Finale HoundPattern {Name, BeatAt, Beats, HazardIds, BarkAt}
	signal("zone", { Stage = "HoundPattern", Name = name, BeatAt = beatAt, Beats = beats, HazardIds = ids, BarkAt = Fin.BarkAt })
end

local function bark(F, Fin)
	local at = Fin.BarkAt
	Fin.BarkAt = nil
	Fin.CounterUntil = at + (FC.Hound.CounterWindow or 3)
	Fin.Counts = {}
	local entry = { Role = "Jaw" }
	addTarget(F, Fin, { Kind = "HoundJaw", Position = Fin.JawPos, Radius = 3.2, HP = 1e9, MaxHP = 1e9, Panel = false,
		Color = Color3.fromRGB(200, 150, 255), Material = "Neon", Size = V3(6.4, 5, 6.4), Name = "THE HOUND'S JAW", NameRU = "ПАСТЬ ГОНЧЕЙ",
		Variant = "Jaw", Attributes = { Until = Fin.CounterUntil } }, entry)
	Fin.Jaw = entry
	publish(Fin)
	-- Finale Bark {At, CounterUntil, JawPos, TargetId}
	signal("zone", { Stage = "Bark", At = at, CounterUntil = Fin.CounterUntil, JawPos = Fin.JawPos, TargetId = idOf(entry.Target) })
end

local function closeCounter(F, Fin, t: number)
	if Fin.Jaw and Fin.Jaw.Target then
		removeTarget(F, Fin, Fin.Jaw.Target, "Closed")
	end
	Fin.Jaw = nil
	Fin.CounterUntil = nil
	Fin.Current = nil
	Fin.NextPatternAt = nextBeat(Fin, t + (FC.Hound.GapBeats or 1) * beatLen())
	publish(Fin)
end

local victory

local function stepHound(F, Fin, t: number)
	if Fin.PendingVictory then
		Fin.PendingVictory = nil
		victory(F, Fin)
		return
	end
	local a = api()
	local lead = a and a.Lead() or .35
	if not Fin.Current and Fin.NextPatternAt and t >= Fin.NextPatternAt - lead - .05 then
		startHoundPattern(F, Fin)
	end
	if Fin.BarkAt and t >= Fin.BarkAt then
		bark(F, Fin)
	end
	if Fin.CounterUntil and t >= Fin.CounterUntil then
		closeCounter(F, Fin, t)
	end
end

-- the jaw takes Perfect hits only while the counter window is open; each counts 1 (H15: 1.25), at most
-- CounterCapPerPlayer per player per window
local function onJawHit(player: Player, target: any, hit: any)
	if type(hit) == "table" then
		hit.Applied = 0
	end
	local F = boss() and boss().Fight
	local Fin = F and F.Finale
	local entry = Fin and Fin.Targets[target]
	local function refuse(reason: string)
		-- Finale Counter {HP, Max, UserId, Hits, Counted = false, Reason ("Closed" | "Perfect" | "Cap")} (to the hitter)
		if Fin and Fin.HoundMax then
			signal(player, { Stage = "Counter", HP = math.max(0, math.ceil((Fin.HoundHP or 0) - 1e-6)), Max = Fin.HoundMax, UserId = player.UserId,
				Hits = Fin.Counts and Fin.Counts[player.UserId] or 0, Counted = false, Reason = reason })
		end
		return { Counted = false, Reason = reason }
	end
	if not Fin or Fin.State ~= "Hound" or not entry or entry.Role ~= "Jaw" then
		return refuse("Closed")
	end
	local t = now()
	if not Fin.CounterUntil or t > Fin.CounterUntil + .15 then
		return refuse("Closed")
	end
	if tonumber(type(hit) == "table" and hit.Quality) ~= 2 then
		return refuse("Perfect")
	end
	local uid = player.UserId
	local hits = Fin.Counts[uid] or 0
	if hits >= (FC.Hound.CounterCapPerPlayer or 6) then
		return refuse("Cap")
	end
	Fin.Counts[uid] = hits + 1
	local a = api()
	local add = (a and a.HasDog(player, "Wolf")) and BossMath.H15Mult(true) or 1
	Fin.HoundHP = math.max(0, Fin.HoundHP - add)
	credit(F, Fin, player, (FC.Hound.CounterScore or .006) * add, add)
	if Fin.HoundHP <= 1e-6 then
		Fin.PendingVictory = true
	end
	publish(Fin)
	local hp = math.max(0, math.ceil(Fin.HoundHP - 1e-6))
	-- Finale Counter {HP, Max, UserId, Hits, Counted = true}
	signal("zone", { Stage = "Counter", HP = hp, Max = Fin.HoundMax, UserId = uid, Hits = hits + 1, Counted = true })
	return { Counted = true, HP = hp, Max = Fin.HoundMax, Hits = hits + 1 }
end

---------------------------------------------------------------------------------------------------------------------
-- the end: VICTORY / FAIL
---------------------------------------------------------------------------------------------------------------------
local function topList(Fin, n: number)
	local list = {}
	for uid, sc in pairs(Fin.Score) do
		table.insert(list, { UserId = uid, Name = Fin.Names[uid] or "?", Score = math.floor(sc + .5) })
	end
	table.sort(list, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.UserId < b.UserId
	end)
	while #list > n do
		table.remove(list)
	end
	return list
end
BossFinale.TopList = topList

local function stopEverything(F, Fin)
	local a = api()
	if a then
		a.CancelHazards(F)
	end
	for target in pairs(table.clone(Fin.Targets)) do
		removeTarget(F, Fin, target, "End")
	end
	Fin.Ghosts = {}
	Fin.Active = nil
end

victory = function(F, Fin)
	if Fin.State == "Victory" or Fin.State == "Fail" or F.Ended then
		return
	end
	local t = now()
	stopEverything(F, Fin)
	F.FinaleWon = true
	Fin.Reason = nil
	enter(F, Fin, "Victory", t + (FC.VictoryHold or 8))
	-- Finale Victory {At, Top {{UserId, Name, Score}}}
	signal("all", { Stage = "Victory", At = t, Top = topList(Fin, 5) })
	local a = api()
	if a then
		a.Finish(F, "Defeated", "FinaleVictory")
	end
end
BossFinale.Victory = function(F)
	if F and F.Finale then
		victory(F, F.Finale)
	end
end

function BossFinale.Fail(F, reason: string?)
	local Fin = F and F.Finale
	if not Fin or Fin.State == "Victory" or Fin.State == "Fail" or F.Ended then
		return
	end
	local t = now()
	stopEverything(F, Fin)
	F.FinaleWon = false
	Fin.Reason = reason or "Time"
	enter(F, Fin, "Fail", t + (FC.VictoryHold or 8))
	-- Finale Fail {Reason ("Wipe" | "Time" | "Empty")}: "THE BELL SILENCES YOU" (the normal difficulty V reward follows)
	signal("all", { Stage = "Fail", Reason = Fin.Reason, At = t })
	local a = api()
	if a then
		a.Finish(F, "Defeated", "FinaleFail")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the step (Boss.Step calls it 10x a second while F.Finale is set)
---------------------------------------------------------------------------------------------------------------------
function BossFinale.Step(F, dt: number)
	local Fin = F and F.Finale
	if not Fin or F.Ended then
		return
	end
	local t = now()
	if Fin.State == "Victory" or Fin.State == "Fail" then
		return
	end
	if t >= Fin.Deadline then
		BossFinale.Fail(F, "Time")
		return
	end
	if Fin.State == "FakeDeath" then
		if t >= Fin.StageUntil then
			startBell(F, Fin)
		end
	elseif Fin.State == "Bell" then
		stepBell(F, Fin, t)
		if Fin.ChoirAt and t >= Fin.ChoirAt then
			startChoir(F, Fin)
		end
	elseif Fin.State == "Choir" then
		stepChoir(F, Fin, dt, t)
	elseif Fin.State == "Hound" then
		stepHound(F, Fin, t)
	end
end

-- Boss.finish ran (victory, fail, or an abort from outside): the state shows the result until the fight is released
function BossFinale.OnFinish(F, _outcome: string, reason: string?)
	local Fin = F and F.Finale
	if not Fin then
		return
	end
	if Fin.State ~= "Victory" and Fin.State ~= "Fail" then
		stopEverything(F, Fin)
		Fin.State = "Fail"
		Fin.Reason = reason == "Disabled" and "Disabled" or (reason or "Time")
		Fin.StageStart = now()
		Fin.StageUntil = Fin.StageStart + (FC.VictoryHold or 8)
		publish(Fin)
	end
end

function BossFinale.Reset()
	publish(nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Strike kinds
---------------------------------------------------------------------------------------------------------------------
local OUTSIDE = "Climb down into the pit to fight the Gravekeeper"

local function canHitFinale(player: Player, target: any)
	local F = boss() and boss().Fight
	local Fin = F and F.Finale
	if not Fin or F.Ended or not Fin.Targets[target] then
		return false, "Too late!"
	end
	local a = api()
	if a and not a.InPit(player) then
		return false, a.Outside or OUTSIDE
	end
	return true
end

local function zero(): number
	return 0
end

function BossFinale.RegisterStrike(): boolean
	if BossFinale.StrikeReady then
		return true
	end
	local Strike = modules and modules.Strike
	if not (type(Strike) == "table" and type(Strike.Register) == "function") then
		return false
	end
	local ok, err = pcall(function()
		Strike.Register("FinaleChain", { Range = FC.Bell.ChainRange or 20, Verb = "BREAK", Damage = zero, OnHit = onChainHit, CanHit = canHitFinale,
			Activity = "BossDamage" })
		Strike.Register("FinaleCandle", { Range = FC.Choir.CandleRange or 14, Verb = "STRIKE", Damage = zero, OnHit = onCandleHit,
			CanHit = canHitFinale, Activity = "BossDamage" })
		Strike.Register("FinaleWeak", { Range = 14, Verb = "DIG", Damage = weakDamage, OnBreak = onWeakBreak, CanHit = canHitFinale,
			Activity = "BossDamage", EventMult = "Apply" })
		Strike.Register("FinaleGhost", { Range = 13, Verb = "STRIKE", Damage = "Power", OnBreak = onGhostBreak, CanHit = canHitFinale,
			Activity = "BossDamage", EventMult = "Apply" })
		Strike.Register("HoundJaw", { Range = FC.Hound.JawRange or 22, Verb = "STRIKE", Damage = zero, OnHit = onJawHit, CanHit = canHitFinale,
			Activity = "BossDamage" })
	end)
	if not ok then
		warn("Halloween BossFinale: Strike.Register failed: " .. tostring(err))
		return false
	end
	BossFinale.StrikeReady = true
	return true
end
BossFinale.Handlers = { ChainHit = onChainHit, CandleHit = onCandleHit, WeakBreak = onWeakBreak, GhostBreak = onGhostBreak, JawHit = onJawHit,
	CanHit = canHitFinale, WeakDamage = weakDamage }

---------------------------------------------------------------------------------------------------------------------
-- Studio QA (C2Debug {Cmd = "Finale", Stage?}): no fight -> a difficulty V fight that goes straight to the false
-- victory; Stage = "Bell" | "Choir" | "Hound" | "Win" | "Fail" jumps the running finale
---------------------------------------------------------------------------------------------------------------------
function BossFinale.Debug(player: Player, args: any): (boolean, any)
	if not (RunService:IsStudio() and game.GameId == 0) then
		return false, "Unknown debug command"
	end
	local b = boss()
	if not b then
		return false, "Boss module missing"
	end
	local stage = type(args) == "table" and tostring(args.Stage or args.N or "") or ""
	local F = b.Fight
	if not F then
		local ok, err = b.Summon(5, "Debug", player)
		if not ok then
			return false, err
		end
		F = b.Fight
		F.State = "Fight"
		F.Phase = 5
		F.PendingDefeat = true
		return true, { Message = "Finale started" }
	end
	local Fin = F.Finale
	if not Fin then
		if F.Difficulty ~= 5 then
			return false, "The finale needs difficulty V"
		end
		F.State = "Fight"
		F.Phase = 5
		F.PendingDefeat = true
		return true, { Message = "Finale started" }
	end
	if stage == "Bell" and Fin.State == "FakeDeath" then
		Fin.StageUntil = now()
	elseif stage == "Choir" and (Fin.State == "FakeDeath" or Fin.State == "Bell") then
		if Fin.State == "FakeDeath" then
			startBell(F, Fin)
		end
		for _, key in ipairs(BossFinale.CHAINS) do
			breakChain(F, Fin, key)
		end
		Fin.ChoirAt = now()
	elseif stage == "Hound" and Fin.State ~= "Hound" and Fin.State ~= "Victory" and Fin.State ~= "Fail" then
		if Fin.State == "Choir" then
			clearChoir(F, Fin)
		end
		stopEverything(F, Fin)
		startHound(F, Fin)
	elseif stage == "Win" then
		victory(F, Fin)
	elseif stage == "Fail" then
		BossFinale.Fail(F, "Time")
	else
		return false, "Unknown finale stage"
	end
	return true, { Message = "Finale stage: " .. stage }
end

---------------------------------------------------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------------------------------------------------
function BossFinale.Init(c, m)
	core = c
	modules = m or {}
	stateFolder = nil
	ensureState()
	publish(nil)
	BossFinale.RegisterStrike()
end

function BossFinale.Start(c, m)
	if BossFinale.Started then
		return
	end
	BossFinale.Started = true
	BossFinale.Init(c, m)
end

return BossFinale
