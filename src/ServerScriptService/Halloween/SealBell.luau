-- BELL SEAL VII · LAST BELL TRIAL vs THE BELLKEEPER (ServerScriptService.Halloween.SealBell, WP-J; docs/halloween2/DESIGN.md
-- §8.4 item 7). A mechanic gauntlet in the Black Bell Arena (Seals combat trial: Event HP zone "Trial:LastBell", party up to
-- 6, 6 min, one run on the server at a time; never while the Black Bell Assault rings):
--   intro   the Bellkeeper pulls the rope: one toll without damage
--   wave 1  SHOCKWAVE RINGS: every Chapter2Config ShockwaveEvery seconds the Black Bell tolls; three ring bands expand from
--           the arena centre, each with doorways turned from the last (Seals2Rules.Toll; the channels between bands and the
--           doorways are safe). Survive Seals2Config.Bell.Rings.Tolls tolls.
--   wave 2  FOUR CHAINS (ArenaChain_N/E/S/W): one chain rings at a time (Strike kind "UyBellChain"; the others refuse hits),
--           pulsing every PulsePeriod; only a PERFECT hit inside the bright part of a pulse counts (+25% with H15).
--           Counted hits needed = ChainHits + ChainHitsPerFighter x (fighters - 1). The bell keeps tolling, slower.
--   wave 3  WEAK-POINT BURN: the Bellkeeper's lantern heart opens (Strike kind "UyBellWeak", Power HP = WeakHP +
--           WeakHPPerFighter x (fighters - 1), WEAKENED applies, +25% with H15) while Line + Circle volleys fall on the
--           fighters (Seals2Rules.Burn).
-- Clear: the heart breaks (WinAtGoal, 3 waves); Gold: nobody bled out (Chapter2Config.Seals[7].Gold.NoBleedOut).
-- The arena's live state for every client (members AND spectators) is the folder RS.Halloween.State.BellArena
-- {Mode "" | "Trial" | "Assault", RunId, Wave, Waves, TollAt, TollSerial, Chain, ChainSince, ChainHits, ChainNeed, Pulse,
-- Bright, Broken ("NE"), WeakId, KeeperId, Attack, AttackAt, AttackSerial, Revision} (the Assault, Resonance.luau, writes it
-- too through SealBell.Stage). C2Trial kinds to members: "BellWave" {Wave}, "BellToll" {At}, "ChainActive" {Key, Since,
-- Need}, "ChainHit" {Key, Hits, Need, UserId, Counted}, "ChainBreak" {Key, Left}, "WeakOpen" {TargetId, HP, Max},
-- "BellVolley" {At}.
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Base = require(Halloween:WaitForChild("Chapter2Config"))
local Cfg = require(Halloween:WaitForChild("Seals2Config"))
local SR = require(Halloween:WaitForChild("Seals2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local Bell = {}
Bell.Config = Cfg

local SEAL = 7
local BC = Cfg.Bell
local ACT = Base.Seals[SEAL].Activity

local core: any = nil
local modules: any = nil
local runsById: { [number]: any } = {}
local folder: Folder? = nil
local rng = Random.new()

Bell.Now = function(): number
	return workspace:GetServerTimeNow()
end
Bell.Clock = function(): number
	return os.clock()
end
Bell.Roll = function(): number
	return rng:NextNumber()
end

local function C2(): any
	return modules and modules.Chapter2
end
local function SealsM(): any
	return modules and modules.Seals
end
local function StrikeM(): any
	return modules and modules.Strike
end
local function HP(): any
	return modules and modules.EventHP
end

local function rootPos(player: Player): Vector3?
	local root = core and core.Root(player)
	return root and root.Position or nil
end

local function anchorPos(name: string): Vector3?
	local c2 = C2()
	if c2 and c2.AnchorPos then
		return c2.AnchorPos(name)
	end
	return Layout.Anchor(name)
end

local function centre(): Vector3
	return Layout.Arena.Centre
end

local function keeperPos(): Vector3
	local p = anchorPos("Bellkeeper") or Layout.Arena.Bellkeeper
	return Vector3.new(p.X, Layout.Arena.Centre.Y, p.Z)
end
Bell.KeeperPos = keeperPos

---------------------------------------------------------------------------------------------------------------------
-- RS.Halloween.State.BellArena (shared with the Assault)
---------------------------------------------------------------------------------------------------------------------
local DEFAULTS = { Mode = "", RunId = 0, Wave = 0, Waves = 0, TollAt = 0, TollSerial = 0, Chain = "", ChainSince = 0, ChainHits = 0,
	ChainNeed = 0, Pulse = ACT.PulsePeriod or 1.2, Bright = BC.Chains.Bright, Broken = "", WeakId = 0, KeeperId = 0, Attack = "",
	AttackAt = 0, AttackSerial = 0 }

local function stageFolder(): Folder?
	if folder and folder.Parent then
		return folder
	end
	local st = Halloween:FindFirstChild("State")
	if not st then
		return nil
	end
	local f = st:FindFirstChild("BellArena")
	if not f then
		f = Instance.new("Folder")
		f.Name = "BellArena"
		for k, v in pairs(DEFAULTS) do
			f:SetAttribute(k, v)
		end
		f:SetAttribute("Revision", 0)
		f.Parent = st
	end
	folder = f :: Folder
	return folder
end

-- write arena attributes; reset = true starts from the defaults (a new mode)
function Bell.Stage(attrs: { [string]: any }, reset: boolean?)
	local f = stageFolder()
	if not f then
		return
	end
	if reset then
		for k, v in pairs(DEFAULTS) do
			if attrs[k] == nil and f:GetAttribute(k) ~= v then
				f:SetAttribute(k, v)
			end
		end
	end
	for k, v in pairs(attrs) do
		if f:GetAttribute(k) ~= v then
			f:SetAttribute(k, v)
		end
	end
	f:SetAttribute("Revision", (tonumber(f:GetAttribute("Revision")) or 0) + 1)
end

function Bell.StageMode(): string
	local f = stageFolder()
	local m = f and f:GetAttribute("Mode")
	return type(m) == "string" and m or ""
end

-- the Black Bell Assault holds the arena from its countdown to its end (Resonance's live state, else the replicated one)
local function assaultBusy(): boolean
	local res = modules and modules.Resonance
	local live = res and type(res.State) == "table" and res.State.Assault
	if type(live) == "table" then
		return live.State == "Countdown" or live.State == "Active"
	end
	local st = Halloween:FindFirstChild("State")
	local a = st and st:FindFirstChild("Assault")
	local s = a and a:GetAttribute("State")
	return s == "Countdown" or s == "Active"
end

---------------------------------------------------------------------------------------------------------------------
-- Waves
---------------------------------------------------------------------------------------------------------------------
local function signal(run: any, kind: string, extra: any?)
	local seals = SealsM()
	if seals then
		seals.Signal(run, kind, extra)
	end
end

local function hazards(run: any, defs: { any })
	local hp = HP()
	if hp and hp.HazardWave and #defs > 0 then
		local ok, err = pcall(hp.HazardWave, run.Zone, defs)
		if not ok then
			warn("SealBell: hazards failed: " .. tostring(err))
		end
	end
end

-- one toll of the Black Bell (shockwave ring bands); bands = nil: the intro toll (no damage)
local function toll(run: any, bands: { any }?)
	local now = Bell.Now()
	local serial = (run.Data.TollSerial or 0) + 1
	run.Data.TollSerial = serial
	Bell.Stage({ TollAt = now, TollSerial = serial })
	signal(run, "BellToll", { At = now, Serial = serial })
	if not bands then
		return
	end
	local rc = BC.Rings
	local defs = SR.Toll(centre(), { Bands = bands, Gaps = rc.Gaps, GapWidth = rc.GapWidth, GapTurn = rc.GapTurn, Stagger = rc.Stagger,
		Telegraph = rc.Telegraph, Damage = ACT.ShockwaveDamage or 14, Start = Bell.Roll() * 360, Kind = "Shockwave", Source = "Bell" })
	hazards(run, defs)
end

local function fighterList(run: any): { Player }
	local hp = HP()
	local out = {}
	for _, pl in ipairs(run.Players) do
		if not hp or not hp.CanTarget or hp.CanTarget(pl) then
			table.insert(out, pl)
		end
	end
	return out
end

local function members(run: any): string
	local ids = {}
	for _, pl in ipairs(run.Players) do
		table.insert(ids, tostring(pl.UserId))
	end
	return "," .. table.concat(ids, ",") .. ","
end

-- Activity.ObjectiveShards to every member for a survived ring wave and each broken chain (Chapter2.QueueShards, daily DR),
-- like the rounds of the other seals
local function objective(run: any)
	local c2 = C2()
	local n = tonumber(ACT.ObjectiveShards) or 0
	if not c2 or not c2.QueueShards or n <= 0 then
		return
	end
	for _, pl in ipairs(run.Players) do
		if pl.Parent then
			pcall(c2.QueueShards, pl, n, "Objective")
		end
	end
end

local function startWave(run: any, wave: number)
	local d = run.Data
	d.Wave = wave
	run.Public.Wave = wave
	Bell.Stage({ Wave = wave })
	signal(run, "BellWave", { Wave = wave })
	local clock = Bell.Clock()
	local strike = StrikeM()
	local n = math.max(1, #run.Players)
	if wave == 1 then
		d.NextToll = clock + .6
		d.Tolls = 0
	elseif wave == 2 then
		-- the rings were survived: wave 1 scores
		local seals = SealsM()
		if seals then
			seals.AddScore(run, nil, 1)
		end
		objective(run)
		d.ChainIndex = 0
		d.Chains = {}
		d.NextToll = clock + 4
		d.Need = SR.ChainNeed(n, ACT)
		run.Public.ChainNeed = d.Need
		run.Public.ChainsLeft = #BC.Chains.Order
		if strike then
			for _, key in ipairs(BC.Chains.Order) do
				local pos = anchorPos("Chain_" .. key) or (Layout.Arena.Chains[key] + Vector3.new(0, 2, 0))
				local t = strike.Add({
					Kind = "UyBellChain", Position = pos + Vector3.new(0, 1.5, 0), Radius = BC.Chains.Radius, HP = d.Need, MaxHP = d.Need, Unit = 1,
					Color = Color3.fromRGB(186, 120, 255), Material = "CorrodedMetal", Data = { RunId = run.Id, Chain = key, Mode = "Trial" },
					Name = "CURSED CHAIN", NameRU = "ПРОКЛЯТАЯ ЦЕПЬ", Panel = true,
					Attributes = { UyRunId = run.Id, UyChain = key, UyMembers = members(run) },
				})
				d.Chains[key] = t
			end
		end
		d.ActivateAt = clock + 1.5
	elseif wave == 3 then
		local max = SR.WeakHP(n, ACT)
		d.NextVolley = clock + 2
		if strike then
			local kp = keeperPos()
			local t = strike.Add({
				Kind = "UyBellWeak", Position = kp + Vector3.new(0, BC.Burn.Height, 0), Radius = BC.Burn.Radius, HP = max, MaxHP = max, Unit = 1,
				Color = Color3.fromRGB(255, 170, 80), Material = "Neon", Data = { RunId = run.Id, Mode = "Trial" },
				Name = "THE BELLKEEPER'S HEART", NameRU = "СЕРДЦЕ ЗВОНАРЯ", Panel = true,
				Attributes = { UyRunId = run.Id, UyWeak = true, UyMembers = members(run) },
			})
			d.Weak = t
			run.Public.WeakId, run.Public.WeakHP, run.Public.WeakMax = t.Id, max, max
			Bell.Stage({ WeakId = t.Id, Chain = "" })
			signal(run, "WeakOpen", { TargetId = t.Id, HP = max, Max = max })
		end
	end
end

local function activateChain(run: any)
	local d = run.Data
	d.ChainIndex += 1
	local key = BC.Chains.Order[d.ChainIndex]
	if not key then
		return
	end
	local now = Bell.Now()
	d.Chain, d.Since = key, now
	run.Public.Chain, run.Public.ChainSince, run.Public.ChainHits = key, now, 0
	Bell.Stage({ Chain = key, ChainSince = now, ChainHits = 0, ChainNeed = d.Need, Pulse = ACT.PulsePeriod or 1.2, Bright = BC.Chains.Bright })
	signal(run, "ChainActive", { Key = key, Since = now, Need = d.Need, Pulse = ACT.PulsePeriod or 1.2, Bright = BC.Chains.Bright })
end

local function breakChain(run: any, key: string)
	local d = run.Data
	d.Broken = (d.Broken or "") .. key
	run.Public.ChainsLeft = math.max(0, #BC.Chains.Order - #d.Broken)
	Bell.Stage({ Broken = d.Broken, Chain = "" })
	signal(run, "ChainBreak", { Key = key, Left = run.Public.ChainsLeft })
	objective(run)
	d.Chain = nil
	if run.Public.ChainsLeft <= 0 then
		local seals = SealsM()
		if seals then
			seals.AddScore(run, nil, 1)
		end
		if run.State == "Running" then
			d.WaveAt = Bell.Clock() + 2.5 -- a breath before the heart opens
			d.Pending = 3
		end
	else
		d.ActivateAt = Bell.Clock() + 1.2
	end
end
Bell.BreakChain = breakChain

local function onStart(run: any)
	runsById[run.Id] = run
	run.Data.Wave = 0
	run.Data.Broken = ""
	run.Public = { Wave = 0, Waves = 3, Tolls = 0, TollsNeed = BC.Rings.Tolls, Chain = "", ChainHits = 0, ChainNeed = 0,
		ChainsLeft = #BC.Chains.Order, WeakId = 0, WeakHP = 0, WeakMax = 0, Keeper = keeperPos(), Center = centre() }
	Bell.Stage({ Mode = "Trial", RunId = run.Id, Wave = 0, Waves = 3 }, true)
	toll(run, nil) -- the opening toll
	run.Data.WaveAt = Bell.Clock() + BC.Intro
	run.Data.Pending = 1
end

local function onTick(run: any, _dt: number)
	local d = run.Data
	local clock = Bell.Clock()
	if d.Pending and clock >= (d.WaveAt or 0) then
		local wave = d.Pending
		d.Pending = nil
		startWave(run, wave)
		return
	end
	if d.Wave == 1 then
		if d.Tolls < BC.Rings.Tolls and clock >= d.NextToll then
			d.Tolls += 1
			run.Public.Tolls = d.Tolls
			toll(run, BC.Rings.Bands)
			local every = ACT.ShockwaveEvery or { 6, 8 }
			d.NextToll = clock + every[1] + Bell.Roll() * (every[2] - every[1])
			if d.Tolls >= BC.Rings.Tolls then
				-- the last bands land (3 bands x Stagger + telegraph), then the chains wake up
				d.WaveAt = clock + BC.Rings.Telegraph + .35 + BC.Rings.Stagger * #BC.Rings.Bands + 1.5
				d.Pending = 2
			end
		end
	elseif d.Wave == 2 then
		if not d.Chain and d.ActivateAt and clock >= d.ActivateAt and run.Public.ChainsLeft > 0 then
			d.ActivateAt = nil
			activateChain(run)
		end
		if clock >= d.NextToll then
			local every = BC.Chains.Shockwave.Every
			d.NextToll = clock + every[1] + Bell.Roll() * (every[2] - every[1])
			toll(run, BC.Chains.Shockwave.Bands)
		end
	elseif d.Wave == 3 then
		local t = d.Weak
		if t and t.Alive and clock >= d.NextVolley then
			local positions = {}
			for _, pl in ipairs(fighterList(run)) do
				local p = rootPos(pl)
				if p then
					table.insert(positions, p)
				end
			end
			if #positions > 0 then
				hazards(run, SR.Burn(keeperPos(), positions, BC.Burn, Bell.Roll))
				local serial = (d.AttackSerial or 0) + 1
				d.AttackSerial = serial
				Bell.Stage({ Attack = "Burn", AttackAt = Bell.Now(), AttackSerial = serial })
				signal(run, "BellVolley", { At = Bell.Now() })
			end
			local frac = t.HP / math.max(1, t.MaxHP)
			d.NextVolley = clock + SR.Every(BC.Burn.Every, 1 - frac)
		end
	end
end

local function onEnd(run: any, _result: string)
	runsById[run.Id] = nil
	local strike = StrikeM()
	local d = run.Data
	if strike then
		for _, t in pairs(d.Chains or {}) do
			if t.Alive then
				strike.Remove(t, "Fled")
			end
		end
		if d.Weak and d.Weak.Alive then
			strike.Remove(d.Weak, "Fled")
		end
	end
	local hp = HP()
	if hp and hp.CancelHazards then
		pcall(hp.CancelHazards, run.Zone)
	end
	if Bell.StageMode() == "Trial" then
		Bell.Stage({ Mode = "", RunId = 0 }, true)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Strike kinds (also used by the Assault through target.Data.Mode = "Assault": Resonance.luau handles those)
---------------------------------------------------------------------------------------------------------------------
local function runOf(target: any): any
	local id = target and target.Data and target.Data.RunId
	return id and runsById[id] or nil
end

local function wolf(player: Player): number
	local c2 = C2()
	if c2 and c2.HasTeamDog and c2.HasTeamDog(player, "HW_BellkeeperWolf") then
		local def = Base.Dogs.Defs.HW_BellkeeperWolf
		return 1 + (def and def.MechanicDamageBonus or .25)
	end
	return 1
end
Bell.Wolf = wolf

-- the judged hit on the ringing chain: counted when Perfect and inside the bright part of the pulse
function Bell.ChainJudge(quality: number?, now: number, since: number): boolean
	return quality == 2 and SR.PulseBright(now, since, ACT.PulsePeriod or 1.2, BC.Chains.Bright, BC.Chains.Grace)
end

local function memberCheck(player: Player, target: any): (boolean, string?)
	local run = runOf(target)
	local seals = SealsM()
	if not run or run.State ~= "Running" or not seals or seals.RunOf(player) ~= run then
		return false, "HW:NOT_YOURS"
	end
	return true, nil
end

local function registerKinds()
	local strike = StrikeM()
	if not strike or not strike.Register then
		return
	end
	strike.Register("UyBellChain", {
		Range = BC.Chains.Range, Verb = "STRIKE", Perfect = false, Activity = "Hit",
		Damage = function()
			return 0
		end,
		CanHit = function(player: Player, target: any)
			local ok, err = memberCheck(player, target)
			if not ok then
				return false, err
			end
			local run = runOf(target)
			if run.Data.Chain ~= target.Data.Chain then
				return false, "This chain is not ringing yet"
			end
			return true
		end,
		OnHit = function(player: Player, target: any, hit: any)
			local run = runOf(target)
			local c2, seals = C2(), SealsM()
			local perfect = hit.Quality == 2
			if c2 then
				c2.StreakHit(player, perfect)
			end
			if run and seals then
				seals.Hit(run, player, perfect)
			end
			local counted = run ~= nil and run.Data.Chain == target.Data.Chain and Bell.ChainJudge(hit.Quality, Bell.Now(), run.Data.Since or 0)
			if not counted then
				hit.Applied = 0
				if run then
					signal(run, "ChainHit", { Key = target.Data.Chain, Hits = run.Public.ChainHits, Need = run.Data.Need, UserId = player.UserId,
						Counted = false })
				end
				return { Miss = true, MissedToll = true }
			end
			hit.Applied = wolf(player)
			local hits = math.min(run.Data.Need, (target.MaxHP - target.HP) + hit.Applied)
			run.Public.ChainHits = math.floor(hits + 1e-6)
			Bell.Stage({ ChainHits = run.Public.ChainHits })
			signal(run, "ChainHit", { Key = target.Data.Chain, Hits = run.Public.ChainHits, Need = run.Data.Need, UserId = player.UserId,
				Counted = true })
			return { Weak = true, Counted = true }
		end,
		OnBreak = function(_killer: Player?, target: any)
			local run = runOf(target)
			if run and run.State == "Running" then
				breakChain(run, target.Data.Chain)
			end
		end,
	})
	strike.Register("UyBellWeak", {
		Range = BC.Burn.Range, Verb = "STRIKE", Damage = "Power", Perfect = false, EventMult = "Apply", Activity = "Hit",
		CanHit = memberCheck,
		OnHit = function(player: Player, target: any, hit: any)
			local run = runOf(target)
			local c2, seals = C2(), SealsM()
			local perfect = hit.Quality == 2
			if c2 then
				c2.StreakHit(player, perfect)
			end
			if run and seals then
				seals.Hit(run, player, perfect)
			end
			hit.Applied = (tonumber(hit.Applied) or 0) * wolf(player)
			if run then
				run.Public.WeakHP = math.max(0, math.floor((target.HP - hit.Applied) * 10 + .5) / 10)
			end
			return { Weak = true }
		end,
		OnBreak = function(_killer: Player?, target: any)
			local run = runOf(target)
			local seals = SealsM()
			if run and run.State == "Running" and seals then
				run.Public.WeakHP = 0
				seals.AddScore(run, nil, 1) -- the third wave: WinAtGoal wins the trial
			end
		end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
function Bell.Start(c: any, m: any)
	core, modules = c, m
	stageFolder()
	if not Shared.Chapter2Enabled() then
		return
	end
	registerKinds()
	local seals = SealsM()
	if not seals then
		warn("SealBell: Seals framework missing")
		return
	end
	seals.Register(SEAL, {
		WinAtGoal = true, OnStart = onStart, OnTick = onTick, OnEnd = onEnd,
		CanStart = function()
			if assaultBusy() or Bell.StageMode() == "Assault" then
				return false, "The Black Bell Assault is ringing: join it in the arena"
			end
			return true, nil
		end,
	})
end

return Bell
