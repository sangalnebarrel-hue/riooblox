-- BELL RESONANCE + the BLACK BELL ASSAULT (ServerScriptService.Halloween.Resonance, WP-J; docs/halloween2/DESIGN.md §8.6,
-- §24.4). One server-wide value fed by Underyard actions: Chapter2.Progress calls Resonance.Add(points, player, statKey)
-- with Chapter2Config.Resonance.Points already applied (Perfect 1 (x2 with H15), streak 3, echo / ore / spirit 4, trial
-- 60, door 10, revive 15, boss damage 1 per 150 armor).
--   Goal      Base x clamp(active Underyard players / 6, .6, 2) (Seals2Rules.Goal), recomputed every RecomputeEvery s;
--             "active" = Chapter II players in the Underyard with an action within ActivityWindow (180 s).
--   25%       RESONANT TOLL: State.Resonance.BuffUntil = now + 5 min (Chapter2.StreakHit pays +25% streak shards in the
--             Underyard while it runs).
--   50%       a Coffin Key for every Chapter II player who contributed in the Underyard within the activity window and is
--             still active (C2.Grant {Kind = "Key", Source = "Resonance"}: at most 2 such keys per UTC day). AFK = nothing.
--   75%       six RESONANT ECHOES in Bell Square for 3 min (Strike kind "UyResEcho" at ResonantEcho_n, respawning): every
--             contributor of a broken echo gets bonus shards (DR "Resonance"), an echo dug and bonus resonance.
--   100%      THE BLACK BELL ASSAULT: a 30 s countdown (the arena opens for every Chapter II player, whatever their seals:
--             Underyard.AllowDistrict), then a server raid against the Bellkeeper "Assault" variant (Strike kind
--             "UyAssault", Power HP = BaseHP x attackers, growing as people join) for 8 min: shockwave tolls, then lines,
--             then bone circles (phases by HP). Every Chapter II player walking into the arena joins
--             (Seals.RegisterTrial "Assault", one solo run each so anyone can come and go; the Event HP zone "Assault" is
--             shared, so allies revive each other). Victory: every contributor (>= MinHits hits, active) gets Bell Shards,
--             a Coffin Key, the journal entry and a 2% coffin-grade drop roll (Chapter2Rules.CoffinRoll); the bell holding
--             (time) pays a few shards. Then the counter resets (Cycle + 1).
--   The value is frozen from 100% until the reset. Late joiners read the replicated state.
-- Replicated: RS.Halloween.State.Resonance {Value, Goal, Milestone (0..4), Cycle, BuffUntil (unix), EchoUntil, AssaultAt,
--   AssaultUntil, Revision} and State.Assault {State ("" | "Countdown" | "Active" | "Won" | "Failed"), StartsAt, EndsAt, HP,
--   MaxHP, Attackers, Waiting, Revision}; the arena stage through SealBell.Stage (Mode "Assault"); player attribute
--   UyAssaultHits (the raider's own hits this assault, cleared with the cycle).
-- Signals: C2Resonance {Kind = "Milestone" | "Key" | "Reward", ...} to Underyard players / the player concerned,
--   C2Announce {Kind = "Assault", Stage = "Countdown" | "Start" | "Won" | "Failed", Name, UserId} to everyone,
--   C2Assault {Kind = "Toll" | "Attack" | "Phase", ...} to Underyard players (the arena animation).
-- Studio only (GameId 0): request C2ResonanceDebug {Cmd = "Add" | "Fill" | "Assault" | "Win" | "Reset", N}.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Base = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Cfg = require(Halloween:WaitForChild("Seals2Config"))
local SR = require(Halloween:WaitForChild("Seals2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local Res = {}
Res.Config = Cfg

local RC = Base.Resonance
local CC = Cfg.Resonance
local AC = CC.Assault
local ZONE = "Assault"
local ASSAULT_NAME = { "BLACK BELL ASSAULT", "ШТУРМ ЧЁРНОГО КОЛОКОЛА" }

local core: any = nil
local modules: any = nil
local rng = Random.new()

-- overridable (tests: manual clocks, captured spawns)
Res.Now = function(): number
	return workspace:GetServerTimeNow()
end
Res.Unix = function(): number
	return os.time()
end
Res.Clock = function(): number
	return os.clock()
end
Res.Roll = function(): number
	return rng:NextNumber()
end
Res.Spawn = function(fn: (...any) -> (), ...: any)
	task.spawn(fn, ...)
end
Res.Delay = function(seconds: number, fn: (...any) -> (), ...: any)
	task.delay(seconds, fn, ...)
end

-- the live state (also read by tests)
local S = {
	Value = 0, Goal = RC.Base, Milestone = 0, Cycle = 1, BuffUntil = 0, EchoUntil = 0, Dirty = true, LastAt = {},
	Contrib = {}, Echoes = {},
	Assault = { State = "", StartsAt = 0, EndsAt = 0, HP = 0, MaxHP = 0, Attackers = {}, Count = 0, Hits = {}, Damage = {},
		Target = nil, Phase = 1, NextRing = 0, NextLine = 0, NextCircle = 0, Waiting = false, By = nil, Serial = 0 },
}
Res.State = S

local function C2(): any
	return modules and modules.Chapter2
end
local function UY(): any
	return modules and modules.Underyard
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
local function BellM(): any
	return modules and modules.SealBell
end

local function signalPlayer(player: Player, kind: string, data: any)
	if core then
		core.Signal(player, kind, data)
	end
end

local function signalUnderyard(kind: string, data: any)
	local c2 = C2()
	if c2 then
		c2.Signal("underyard", kind, data)
	end
end

local function announce(stage: string, extra: any?)
	if not core then
		return
	end
	local data = { Kind = "Assault", Stage = stage }
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	core.Signal("all", "C2Announce", data)
end

local function anchorPos(name: string): Vector3?
	local c2 = C2()
	if c2 and c2.AnchorPos then
		return c2.AnchorPos(name)
	end
	return Layout.Anchor(name)
end

---------------------------------------------------------------------------------------------------------------------
-- Replicated folders
---------------------------------------------------------------------------------------------------------------------
local function stateChild(name: string): Folder?
	local st = Halloween:FindFirstChild("State")
	if not st then
		return nil
	end
	local f = st:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = st
	end
	return f :: Folder
end

local function setAttrs(f: Instance?, attrs: { [string]: any })
	if not f then
		return
	end
	local changed = false
	for k, v in pairs(attrs) do
		if f:GetAttribute(k) ~= v then
			f:SetAttribute(k, v)
			changed = true
		end
	end
	if changed then
		f:SetAttribute("Revision", (tonumber(f:GetAttribute("Revision")) or 0) + 1)
	end
end

local function publish()
	S.Dirty = false
	local a = S.Assault
	setAttrs(stateChild("Resonance"), {
		Value = math.floor(S.Value), Goal = S.Goal, Milestone = S.Milestone, Cycle = S.Cycle, BuffUntil = S.BuffUntil,
		EchoUntil = S.EchoUntil, AssaultAt = a.State == "Countdown" and a.StartsAt or 0,
		AssaultUntil = a.State == "Active" and a.EndsAt or 0,
	})
end
Res.Publish = publish

local function publishAssault()
	local a = S.Assault
	setAttrs(stateChild("Assault"), {
		State = a.State, StartsAt = a.StartsAt, EndsAt = a.EndsAt, HP = math.max(0, math.ceil(a.HP)), MaxHP = math.ceil(a.MaxHP),
		Attackers = a.Count, Waiting = a.Waiting,
	})
end
Res.PublishAssault = publishAssault

---------------------------------------------------------------------------------------------------------------------
-- Goal and activity
---------------------------------------------------------------------------------------------------------------------
-- a Chapter II player who acted in the Underyard within the activity window (and is still active)
function Res.Active(player: Player): boolean
	local c2 = C2()
	local at = S.LastAt[player]
	return player.Parent ~= nil and at ~= nil and Res.Clock() - at <= RC.ActivityWindow and c2 ~= nil and c2.Eligible(player)
		and (c2.ActiveWithin == nil or c2.ActiveWithin(player, RC.ActivityWindow))
end

function Res.ActiveCount(): number
	local c2 = C2()
	local n = 0
	local list = c2 and c2.UnderyardPlayers and c2.UnderyardPlayers() or {}
	for _, pl in ipairs(list) do
		if c2.Eligible(pl) and c2.ActiveWithin and c2.ActiveWithin(pl, RC.ActivityWindow) then
			n += 1
		end
	end
	return n
end

local fireMilestone -- forward

local function checkMilestones(by: Player?)
	if S.Assault.State ~= "" then
		return
	end
	for _, i in ipairs(SR.NewMilestones(S.Milestone, S.Value, S.Goal, Base)) do
		S.Milestone = i
		fireMilestone(i, by)
		if S.Assault.State ~= "" then
			break
		end
	end
	S.Dirty = true
end

function Res.RecomputeGoal()
	if S.Assault.State ~= "" then
		return
	end
	local goal = SR.Goal(Res.ActiveCount(), Base)
	if goal ~= S.Goal then
		S.Goal = goal
		S.Dirty = true
		checkMilestones(nil)
	end
end

-- Chapter2.Progress -> Add(points, player, statKey) (H15 already applied by the caller)
function Res.Add(points: number, player: Player?, statKey: string?)
	if not Shared.Chapter2Enabled() then
		return
	end
	points = math.floor(tonumber(points) or 0)
	if points <= 0 or points ~= points then
		return
	end
	local c2 = C2()
	if player and c2 and c2.InUnderyard and c2.InUnderyard(player) then
		S.LastAt[player] = Res.Clock()
	end
	if S.Assault.State ~= "" then
		return -- frozen from 100% until the reset
	end
	S.Value += points
	if player then
		S.Contrib[player.UserId] = (S.Contrib[player.UserId] or 0) + points
	end
	S.Dirty = true
	checkMilestones(player)
end

---------------------------------------------------------------------------------------------------------------------
-- Milestones
---------------------------------------------------------------------------------------------------------------------
local spawnEcho -- forward
local startCountdown -- forward

local function keyMilestone()
	local c2 = C2()
	if not c2 then
		return
	end
	local m = RC.Milestones[2]
	for _, pl in ipairs(Players:GetPlayers()) do
		if Res.Active(pl) then
			Res.Spawn(function()
				local ok, rows = c2.Grant(pl, "C2Resonance", { { Kind = "Key", Amount = m.Keys or 1, Source = "Resonance" } },
					{ Message = "The bell rang for you: a Coffin Key" })
				local got = ok and type(rows) == "table" and rows[1] and rows[1].Amount or 0
				signalPlayer(pl, "C2Resonance", { Kind = "Key", Granted = got, Capped = ok and got <= 0 })
			end)
		end
	end
end
Res.KeyMilestone = keyMilestone

fireMilestone = function(i: number, by: Player?)
	local m = RC.Milestones[i]
	if not m then
		return
	end
	local data = { Kind = "Milestone", Index = i, Milestone = m.Kind, Value = math.floor(S.Value), Goal = S.Goal,
		UserId = by and by.UserId or 0, Name = by and by.DisplayName or nil }
	if m.Kind == "Toll" then
		S.BuffUntil = Res.Unix() + (m.Seconds or 300)
		data.Until = S.BuffUntil
	elseif m.Kind == "Keys" then
		keyMilestone()
	elseif m.Kind == "Echoes" then
		S.EchoUntil = Res.Unix() + (m.Seconds or 180)
		data.Until = S.EchoUntil
		for k = 1, (m.Count or 6) do
			spawnEcho(k)
		end
	elseif m.Kind == "Assault" then
		startCountdown(by)
		data.StartsAt = S.Assault.StartsAt
	end
	S.Dirty = true
	signalUnderyard("C2Resonance", data)
end

-- RESONANT ECHO spot k (respawns until EchoUntil)
spawnEcho = function(k: number)
	local strike = StrikeM()
	if not strike or Res.Unix() >= S.EchoUntil then
		return
	end
	local old = S.Echoes[k]
	if old and old.Alive then
		return
	end
	local pos = anchorPos("ResonantEcho_" .. k) or Layout.ResonantEchoes[k]
	if not pos then
		return
	end
	S.Echoes[k] = strike.Add({
		Kind = "UyResEcho", Position = pos + Vector3.new(0, CC.Echo.Height, 0), Radius = CC.Echo.Radius, HP = CC.Echo.HP, MaxHP = CC.Echo.HP,
		Unit = 1, Color = Color3.fromRGB(150, 80, 230), Material = "Neon", Data = { Echo = k }, Name = "RESONANT ECHO",
		NameRU = "РЕЗОНИРУЮЩЕЕ ЭХО", Panel = true, Attributes = { UyResonantEcho = k },
	})
end
Res.SpawnEcho = spawnEcho

local function echoBroken(target: any, info: any)
	local c2 = C2()
	local m = RC.Milestones[3]
	for _, row in pairs(info and info.Contributors or {}) do
		local pl = row.Player
		if pl and pl.Parent and (row.Hits or 0) > 0 and c2 then
			c2.QueueShards(pl, m.Shards or 4, "Resonance")
			c2.Progress(pl, "Echo", 1)
			Res.Add(m.Points or 6, pl, "ResonantEcho")
		end
	end
	local k = target.Data and target.Data.Echo
	if k then
		Res.Delay(CC.Echo.Respawn, spawnEcho, k)
	end
end
Res.EchoBroken = echoBroken

local function clearEchoes()
	local strike = StrikeM()
	for k, t in pairs(S.Echoes) do
		if t.Alive and strike then
			strike.Remove(t, "Faded")
		end
		S.Echoes[k] = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- THE BLACK BELL ASSAULT
---------------------------------------------------------------------------------------------------------------------
local function arenaStage(attrs: { [string]: any }, reset: boolean?)
	local bell = BellM()
	if bell and bell.Stage then
		pcall(bell.Stage, attrs, reset)
	end
end

local function keeperPos(): Vector3
	local bell = BellM()
	if bell and bell.KeeperPos then
		return bell.KeeperPos()
	end
	return Layout.Arena.Bellkeeper
end

startCountdown = function(by: Player?)
	local a = S.Assault
	a.State = "Countdown"
	a.StartsAt = Res.Now() + AC.Countdown
	a.EndsAt, a.HP, a.MaxHP, a.Count, a.Waiting = 0, 0, 0, 0, false
	a.Attackers, a.Hits, a.Damage = {}, {}, {}
	a.By = by and { Name = by.DisplayName, UserId = by.UserId } or nil
	publishAssault()
	publish()
	announce("Countdown", { StartsAt = a.StartsAt, Name = a.By and a.By.Name or nil, UserId = a.By and a.By.UserId or 0 })
end
Res.StartCountdown = startCountdown

local function lastBellRunning(): boolean
	local seals = SealsM()
	for _, run in ipairs(seals and seals.Runs and seals.Runs() or {}) do
		if run.TrialId == "LastBell" and run.State == "Running" then
			return true
		end
	end
	return false
end

local function assaultRuns(): { any }
	local out = {}
	local seals = SealsM()
	for _, run in ipairs(seals and seals.Runs and seals.Runs() or {}) do
		if run.TrialId == "Assault" and run.State == "Running" then
			table.insert(out, run)
		end
	end
	return out
end

local function beginAssault()
	local a = S.Assault
	local strike = StrikeM()
	a.State = "Active"
	a.Waiting = false
	a.EndsAt = Res.Now() + (RC.Milestones[4].Seconds or 480)
	a.MaxHP = SR.AssaultMaxHP(1, Base)
	a.HP = a.MaxHP
	a.Phase = 1
	local clock = Res.Clock()
	a.NextRing, a.NextLine, a.NextCircle = clock + 3, clock + 8, clock + 10
	local hp = HP()
	if hp and hp.SetZone then
		pcall(hp.SetZone, ZONE, { Spawn = anchorPos("ArenaSpawn") or Layout.Arena.Spawn, Name = ASSAULT_NAME, Trial = "Assault" })
	end
	if strike then
		a.Target = strike.Add({
			Kind = "UyAssault", Position = keeperPos() + Vector3.new(0, AC.Height, 0), Radius = AC.Radius, HP = a.MaxHP, MaxHP = a.MaxHP,
			Unit = 1, Color = Color3.fromRGB(186, 120, 255), Material = "Neon", Data = { Mode = "Assault" }, Name = "THE BELLKEEPER",
			NameRU = "ЗВОНАРЬ", Panel = true, Attributes = { UyAssault = true },
		})
	end
	arenaStage({ Mode = "Assault", Wave = 1, Waves = #AC.Phases, KeeperId = a.Target and a.Target.Id or 0 }, true)
	publishAssault()
	publish()
	announce("Start", { EndsAt = a.EndsAt })
end
Res.BeginAssault = beginAssault

local function rewardRows(won: boolean): ({ any }, { string })
	local rows, dogs = {}, {}
	local ra = RC.Assault
	if won then
		table.insert(rows, { Kind = "Shards", Amount = SR.Between(Res.Roll, ra.Shards[1], ra.Shards[2]), Source = "Assault" })
		table.insert(rows, { Kind = "Key", Amount = ra.Keys or 1, Source = "Assault" })
		if Res.Roll() < (ra.DropChance or .02) then
			local row = Rules.CoffinRoll(Res.Roll, Base)
			if type(row) == "table" then
				table.insert(rows, row)
				if row.Kind == "Dog" and type(row.Id) == "string" then
					table.insert(dogs, row.Id)
				end
			end
		end
	else
		table.insert(rows, { Kind = "Shards", Amount = SR.Between(Res.Roll, AC.FailShards[1], AC.FailShards[2]), Source = "Assault" })
	end
	return rows, dogs
end
Res.RewardRows = rewardRows

-- contributors who earned the rewards: enough hits on the Bellkeeper and still active
function Res.Winners(): { Player }
	local out = {}
	local c2 = C2()
	for uid, hits in pairs(S.Assault.Hits) do
		local pl = Players:GetPlayerByUserId(uid)
		if pl and hits >= AC.MinHits and c2 and c2.Eligible(pl)
			and (c2.ActiveWithin == nil or c2.ActiveWithin(pl, RC.ActivityWindow)) then
			table.insert(out, pl)
		end
	end
	table.sort(out, function(x, y)
		return x.UserId < y.UserId
	end)
	return out
end

local function clearHits()
	for _, pl in ipairs(Players:GetPlayers()) do
		pcall(function()
			if pl:GetAttribute("UyAssaultHits") ~= nil then
				pl:SetAttribute("UyAssaultHits", nil)
			end
		end)
	end
end

local function resetCycle()
	clearHits()
	local a = S.Assault
	a.State, a.StartsAt, a.EndsAt, a.HP, a.MaxHP, a.Count, a.Waiting = "", 0, 0, 0, 0, 0, false
	a.Attackers, a.Hits, a.Damage, a.Target, a.By = {}, {}, {}, nil, nil
	S.Value, S.Milestone = 0, 0
	S.Cycle += 1
	S.Contrib = {}
	arenaStage({ Mode = "" }, true)
	publishAssault()
	publish()
	Res.RecomputeGoal()
end
Res.ResetCycle = resetCycle

local function endAssault(won: boolean)
	local a = S.Assault
	if a.State ~= "Active" then
		return
	end
	a.State = won and "Won" or "Failed"
	local strike = StrikeM()
	if a.Target and a.Target.Alive and strike then
		strike.Remove(a.Target, won and "Broke" or "Fled")
	end
	local hp = HP()
	if hp and hp.CancelHazards then
		pcall(hp.CancelHazards, ZONE)
	end
	local seals = SealsM()
	for _, run in ipairs(assaultRuns()) do
		if seals then
			if won then
				seals.Win(run)
			else
				seals.Fail(run, "Time")
			end
		end
	end
	local c2 = C2()
	for _, pl in ipairs(Res.Winners()) do
		local rows, dogs = rewardRows(won)
		Res.Spawn(function()
			if not c2 then
				return
			end
			local ok, granted = c2.Grant(pl, won and "C2Assault" or "C2AssaultHeld", rows, { Dogs = dogs, Journal = won and "assault" or nil,
				Message = won and "THE BLACK BELL FALLS" or "The bell held" })
			local out = {}
			for _, r in ipairs(ok and type(granted) == "table" and granted or {}) do
				table.insert(out, { Kind = r.Kind, Id = r.Id, Amount = r.Amount, Rank = r.Rank, Converted = r.Converted })
			end
			signalPlayer(pl, "C2Resonance", { Kind = "Reward", Won = won, Rewards = out, Hits = a.Hits[pl.UserId] or 0 })
		end)
	end
	a.EndsAt = Res.Now() + AC.ResultHold
	publishAssault()
	announce(won and "Won" or "Failed", { Name = a.By and a.By.Name or nil, UserId = a.By and a.By.UserId or 0 })
	Res.Delay(AC.ResultHold, function()
		if S.Assault.State == "Won" or S.Assault.State == "Failed" then
			resetCycle()
		end
	end)
end
Res.EndAssault = endAssault

-- a player joined the raid: the Bellkeeper grows (HP keeps its fraction of damage dealt)
local function addAttacker(player: Player)
	local a = S.Assault
	if a.Attackers[player.UserId] then
		return
	end
	a.Attackers[player.UserId] = true
	a.Count += 1
	local newMax = SR.AssaultMaxHP(a.Count, Base)
	local delta = newMax - a.MaxHP
	if delta > 0 then
		a.MaxHP = newMax
		a.HP += delta
		local strike = StrikeM()
		if a.Target and a.Target.Alive and strike and strike.SetHP then
			strike.SetHP(a.Target, a.HP, a.MaxHP)
		end
	end
	publishAssault()
end
Res.AddAttacker = addAttacker

local function fighterPositions(): { Vector3 }
	local hp = HP()
	local out = {}
	for _, pl in ipairs(hp and hp.Players and hp.Players(ZONE) or {}) do
		if not hp.CanTarget or hp.CanTarget(pl) then
			local root = core and core.Root(pl)
			if root then
				table.insert(out, root.Position)
			end
		end
	end
	return out
end

local function assaultHazards(defs: { any })
	local hp = HP()
	if hp and hp.HazardWave and #defs > 0 then
		pcall(hp.HazardWave, ZONE, defs)
	end
end

local function attackSignal(kind: string)
	local a = S.Assault
	a.Serial += 1
	local now = Res.Now()
	if kind == "Toll" then
		arenaStage({ TollAt = now, TollSerial = a.Serial })
	else
		arenaStage({ Attack = kind, AttackAt = now, AttackSerial = a.Serial })
	end
	signalUnderyard("C2Assault", { Kind = kind == "Toll" and "Toll" or "Attack", Attack = kind, At = now, Serial = a.Serial })
end

-- the 10 Hz raid step
function Res.AssaultStep()
	local a = S.Assault
	if a.State == "Countdown" then
		if Res.Now() >= a.StartsAt then
			if lastBellRunning() then
				a.Waiting = true
				a.StartsAt = Res.Now() + AC.WaitStep
				publishAssault()
			else
				beginAssault()
			end
		end
		return
	end
	if a.State ~= "Active" then
		return
	end
	if Res.Now() >= a.EndsAt then
		endAssault(false)
		return
	end
	local t = a.Target
	if t then
		a.HP = t.HP
	end
	local frac = a.HP / math.max(1, a.MaxHP)
	local phase = SR.AssaultPhase(frac, AC)
	if phase ~= a.Phase then
		a.Phase = phase
		arenaStage({ Wave = phase })
		signalUnderyard("C2Assault", { Kind = "Phase", Phase = phase })
	end
	local ph = AC.Phases[phase]
	local clock = Res.Clock()
	if clock >= a.NextRing and ph.Rings then
		a.NextRing = clock + ph.Rings
		local r = AC.Ring
		assaultHazards(SR.Toll(Layout.Arena.Centre, { Bands = r.Bands, Gaps = r.Gaps, GapWidth = r.GapWidth, GapTurn = r.GapTurn,
			Stagger = r.Stagger, Telegraph = r.Telegraph, Damage = r.Damage, Start = Res.Roll() * 360, Kind = "Shockwave", Source = "Assault" }))
		attackSignal("Toll")
	end
	if ph.Lines and clock >= a.NextLine then
		a.NextLine = clock + ph.Lines
		local pos = fighterPositions()
		if #pos > 0 then
			assaultHazards(SR.Burn(keeperPos(), pos, { Line = AC.Line, Circle = { Max = 0, Radius = 1, Telegraph = 1, Damage = 0 } }, Res.Roll))
			attackSignal("Lines")
		end
	end
	if ph.Circles and clock >= a.NextCircle then
		a.NextCircle = clock + ph.Circles
		local pos = fighterPositions()
		if #pos > 0 then
			assaultHazards(SR.Burn(keeperPos(), pos, { Line = { Count = 0, Width = 1, Length = 1, Telegraph = 1, Damage = 0 }, Circle = AC.Circle },
				Res.Roll))
			attackSignal("Circles")
		end
	end
end

-- players walking into the arena join (one solo Seals run each)
local joining: { [Player]: boolean } = {}
function Res.JoinScan()
	if S.Assault.State ~= "Active" then
		return
	end
	local uy, seals, c2 = UY(), SealsM(), C2()
	if not uy or not seals or not c2 then
		return
	end
	for _, pl in ipairs(uy.Players()) do
		if uy.District(pl) == "BlackBellArena" and c2.Eligible(pl) and not seals.RunOf(pl) then
			joining[pl] = true
			pcall(seals.Start, pl, "Assault")
			joining[pl] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Strike kinds + the Assault trial def
---------------------------------------------------------------------------------------------------------------------
local function inAssault(player: Player): boolean
	local seals = SealsM()
	local run = seals and seals.RunOf and seals.RunOf(player)
	return run ~= nil and run.TrialId == "Assault" and run.State == "Running"
end

local function wolf(player: Player): number
	local c2 = C2()
	if c2 and c2.HasTeamDog and c2.HasTeamDog(player, "HW_BellkeeperWolf") then
		local def = Base.Dogs.Defs.HW_BellkeeperWolf
		return 1 + (def and def.MechanicDamageBonus or .25)
	end
	return 1
end

local function registerKinds()
	local strike = StrikeM()
	if not strike or not strike.Register then
		return
	end
	strike.Register("UyAssault", {
		Range = AC.Range, Verb = "STRIKE", Damage = "Power", Perfect = false, EventMult = "Apply", Activity = "Hit",
		CanHit = function(player: Player)
			if S.Assault.State ~= "Active" then
				return false, "HW:GONE"
			end
			if not inAssault(player) then
				return false, "Step into the arena to join the Assault"
			end
			return true
		end,
		OnHit = function(player: Player, target: any, hit: any)
			local c2 = C2()
			local a = S.Assault
			local perfect = hit.Quality == 2
			if c2 then
				c2.StreakHit(player, perfect)
			end
			hit.Applied = (tonumber(hit.Applied) or 0) * wolf(player)
			a.Hits[player.UserId] = (a.Hits[player.UserId] or 0) + 1
			pcall(player.SetAttribute, player, "UyAssaultHits", a.Hits[player.UserId]) -- the raid HUD's "your hits"
			a.Damage[player.UserId] = (a.Damage[player.UserId] or 0) + math.min(target.HP, hit.Applied)
			a.HP = math.max(0, target.HP - hit.Applied)
			S.Dirty = true
			return { Weak = true }
		end,
		OnBreak = function()
			S.Assault.HP = 0
			endAssault(true)
		end,
	})
	strike.Register("UyResEcho", {
		Range = CC.Echo.Range, Verb = "STRIKE", Damage = "Power", Perfect = false, Activity = "Hit",
		CanHit = function(player: Player)
			local c2 = C2()
			if not c2 or not c2.Eligible(player) then
				return false, "HW:CANT"
			end
			return true
		end,
		OnHit = function(player: Player, _target: any, hit: any)
			local c2 = C2()
			if c2 then
				c2.StreakHit(player, hit.Quality == 2)
			end
			return nil
		end,
		OnBreak = function(_killer: Player?, target: any, info: any)
			echoBroken(target, info)
		end,
	})
end

local function registerTrial()
	local seals = SealsM()
	if not seals then
		return
	end
	local spawn = anchorPos("ArenaSpawn") or Layout.Arena.Spawn
	seals.RegisterTrial("Assault", {
		Name = ASSAULT_NAME, District = "BlackBellArena", StartAnchor = "", Combat = false, Exclusive = false, MaxParty = 1,
		Prompt = false, Spawn = spawn,
		CanStart = function(player: Player)
			if S.Assault.State ~= "Active" then
				return false, "The Black Bell is silent"
			end
			local uy = UY()
			if not joining[player] and not (uy and uy.District(player) == "BlackBellArena") then
				return false, "Step into the arena to join the Assault"
			end
			return true, nil
		end,
		OnStart = function(run: any)
			local a = S.Assault
			run.EndsAt = a.EndsAt
			run.Zone = ZONE
			local hp = HP()
			for _, pl in ipairs(run.Players) do
				if hp and hp.Enter then
					pcall(hp.Enter, pl, ZONE, { Spawn = spawn, Name = ASSAULT_NAME, Trial = "Assault" })
				end
				addAttacker(pl)
			end
			run.Public = { Kind = "Assault", Keeper = keeperPos(), Center = Layout.Arena.Centre, TargetId = a.Target and a.Target.Id or 0 }
		end,
		OnLeave = function(_run: any, player: Player)
			local hp = HP()
			if hp and hp.Leave then
				pcall(hp.Leave, player, ZONE)
			end
		end,
		OnEnd = function(run: any)
			local hp = HP()
			for _, pl in ipairs(run.Players) do
				if hp and hp.Leave then
					pcall(hp.Leave, pl, ZONE)
				end
			end
		end,
		OnTimeUp = function()
			if S.Assault.State == "Active" and Res.Now() >= S.Assault.EndsAt - .05 then
				endAssault(false)
			end
		end,
		IsGold = function()
			return false
		end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- Studio debug
---------------------------------------------------------------------------------------------------------------------
function Res.Debug(cmd: string, n: number?, player: Player?): (boolean, string)
	if cmd == "Add" then
		Res.Add(math.max(1, math.floor(n or 100)), player, "Debug")
		return true, "Resonance added"
	elseif cmd == "Fill" then
		Res.Add(math.max(1, S.Goal - math.floor(S.Value)), player, "Debug")
		return true, "Resonance added"
	elseif cmd == "Assault" then
		if S.Assault.State == "" then
			S.Value = S.Goal
			S.Milestone = #RC.Milestones
			startCountdown(player)
		end
		S.Assault.StartsAt = math.min(S.Assault.StartsAt, Res.Now() + 3)
		return true, "Assault started"
	elseif cmd == "Win" then
		endAssault(true)
		return true, "Assault ended"
	elseif cmd == "Reset" then
		resetCycle()
		return true, "Resonance reset"
	end
	return false, "Unknown resonance debug command"
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
function Res.Start(c: any, m: any)
	core, modules = c, m
	if RunService:IsStudio() and game.GameId == 0 then
		core.OnRequest("C2ResonanceDebug", function(player, a)
			return Res.Debug(tostring(a.Cmd), tonumber(a.N), player)
		end, { Cost = .5 })
	end
	if not Shared.Chapter2Enabled() then
		return
	end
	S.Goal = SR.Goal(0, Base)
	publish()
	publishAssault()
	registerKinds()
	registerTrial()
	local uy = UY()
	if uy and uy.AllowDistrict then
		-- the arena opens for every Chapter II player from the countdown to the end of the raid
		uy.AllowDistrict(function(player: Player, district: string)
			local st = S.Assault.State
			if district ~= "BlackBellArena" or (st ~= "Countdown" and st ~= "Active") then
				return false
			end
			local c2 = C2()
			return c2 ~= nil and c2.Eligible(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		S.LastAt[player] = nil
		joining[player] = nil
	end)
	-- 10 Hz: the raid; publish throttled; 1 s: goal / join scans
	task.spawn(function()
		local publishAt, goalAt, joinAt = 0, Res.Clock(), 0
		while true do
			task.wait(.1)
			local clock = Res.Clock()
			local ok, err = pcall(Res.AssaultStep)
			if not ok then
				warn("Resonance assault step failed: " .. tostring(err))
			end
			if clock - joinAt >= AC.JoinRate then
				joinAt = clock
				local okJ, errJ = pcall(Res.JoinScan)
				if not okJ then
					warn("Resonance join scan failed: " .. tostring(errJ))
				end
			end
			if clock - goalAt >= RC.RecomputeEvery then
				goalAt = clock
				pcall(Res.RecomputeGoal)
			end
			if clock - publishAt >= CC.PublishEvery and (S.Dirty or S.Assault.State == "Active") then
				publishAt = clock
				pcall(publish)
				if S.Assault.State == "Active" then
					pcall(publishAssault)
				end
			end
			if S.EchoUntil > 0 and Res.Unix() >= S.EchoUntil and next(S.Echoes) ~= nil then
				clearEchoes()
			end
		end
	end)
end

return Res
