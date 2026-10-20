-- BELL SEAL II · FUNERAL RUN (ServerScriptService.Halloween.SealRun, WP-I; docs/halloween2/DESIGN.md §8.4.2, §24.2).
-- A Funeral Carnival movement trial run by the Seals framework: from GO every runner passes the ten checkpoint rings
-- RunCheckpoint_1..10 in order within the time limit (75 s), past the three swinging coffin pendulums, over the turning
-- carousel and the coffin conveyor. Clear = finish; Gold = finish in <= Chapter2Config.Seals[2].Gold.Time (55 s).
-- Server validation of every runner from the framework's 4 Hz position samples (SealRules.RunStep):
--   * rings only in order; a ring counts when the sampled path segment passes through it (lagged positions included);
--   * minimum leg time = leg distance / (Activity.MaxSpeed x Activity.SpeedSlack) (72 x 1.15), per leg and for all
--     legs since GO / the last rewind together (a sustained speed hack fails the sum), minus LegTimeSlack;
--   * no teleport jumps (a sample farther than possible since the last move, knock-back allowed after a pendulum hit).
--   A violation puts the runner back on their last ring (Underyard.Teleport); MaxViolations of them end their run.
-- Pendulums (§24.2): RunPendulum_i hinge models (UySwingAmp / UySwingPeriod / UySwingPhase, PrimaryPart at the pivot)
-- swing as angle = Amp * sin(2 pi * (serverTime mod Period) / Period + Phase); every pass of a coffin through the lane is
-- an Event HP hazard (EventHP zone "Trial:FuneralRun"): a Box strip across the lane telegraphed for Activity
-- PendulumTelegraph s, Activity.PendulumDamage (12) Event HP; a runner it really hits (the hazard's OnHit) is thrown
-- along the swing (SealRules.SwingKnock) and gets the knock allowance of the leg-time check. Runs are not exclusive: one
-- pendulum schedule serves every running group.
-- Rewards per ring: Chapter2.QueueShards(Activity.ObjectiveShards, "Objective"). A party wins when every runner still in
-- the run has finished (or the clock runs out with at least one finisher: the others are out with reason "Time").
-- Public run data: {GoAt, Gold = {Time}, Checkpoints, Progress = {[userId] = rings}, Finish = {[userId] = seconds},
-- Carousel = leg index (ring i -> i + 1 crosses the carousel deck)}. Extra C2Trial kinds: Checkpoint {UserId, Index,
-- Split}, Finish {UserId, Time}, Rewind {UserId, Index, Reason = "Jump"|"TooFast", Violations}.
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Rules = require(Halloween:WaitForChild("SealRules"))

local SEAL = 2
local Run = {}
Run.Seal = SEAL
Run.Act = Rules.Activity(SEAL)
Run.TrialId = Cfg.Seals[SEAL].Trial.Id
Run.Zone = "Trial:" .. Run.TrialId
Run.Active = {} -- run.Id -> run
Run.Scheduled = {} -- "pendulum:pass" -> {Def, Id, ImpactAt, Checked}
Run.Modules = nil :: any -- the boot modules (Start)
-- overridable (tests: manual clock, world lookups, teleports)
Run.Now = function(): number
	return workspace:GetServerTimeNow()
end
-- the MODEL of that name (the Anchors folder holds parts with the same names: RunPendulum_i is both a layout anchor
-- and the hinge model), looked up in the Funeral Carnival first
Run.FindModel = function(name: string): Instance?
	local d = workspace:FindFirstChild("DOGROTS_District")
	local root = d and d:FindFirstChild("40_Underyard")
	if not root then
		return nil
	end
	local carnival = root:FindFirstChild("FuneralCarnival")
	local hit = carnival and carnival:FindFirstChild(name, true)
	if hit and hit:IsA("Model") then
		return hit
	end
	for _, inst in ipairs(root:GetDescendants()) do
		if inst.Name == name and inst:IsA("Model") then
			return inst
		end
	end
	return nil
end
Run.Teleport = function(player: Player, cf: CFrame)
	local UY = Run.Modules and Run.Modules.Underyard
	if UY and type(UY.Teleport) == "function" then
		task.spawn(UY.Teleport, player, cf, { NoStream = true })
	end
end

local core: any = nil
local modules: any = nil
local specs: { any }? = nil
local specsAt = -1e9

local function C2(): any
	return modules and modules.Chapter2
end
local function SealsMod(): any
	return modules and modules.Seals
end

local function anchor(name: string): Vector3?
	local c2 = C2()
	return (c2 and c2.AnchorPos and c2.AnchorPos(name)) or Layout.Anchor(name)
end

function Run.Checkpoints(): { Vector3 }
	local out = {}
	for i = 1, math.floor(tonumber(Run.Act.Checkpoints) or #Layout.Carnival.Checkpoints) do
		local p = anchor("RunCheckpoint_" .. i)
		if not p then
			break
		end
		out[i] = p
	end
	return out
end

function Run.StartPos(): Vector3
	return anchor("RunStart") or (Layout.Carnival.RunStart + Vector3.new(0, 3, 0))
end

-- the three pendulums: the hinge models of the place (rest pose, attributes) or the layout fallback
function Run.Pendulums(): { any }
	if specs and os.clock() - specsAt < 30 then
		return specs
	end
	local path = { Layout.Carnival.RunStart }
	for _, p in ipairs(Layout.Carnival.Checkpoints) do
		table.insert(path, p)
	end
	local out = {}
	for i, p in ipairs(Layout.Carnival.Pendulums) do
		local hinge: CFrame? = nil
		local attrs = nil
		local m = Run.FindModel("RunPendulum_" .. i)
		if m and m:IsA("Model") then
			local pp = m.PrimaryPart
			hinge = pp and pp.CFrame or m:GetPivot()
			attrs = m:GetAttributes()
		end
		out[i] = Rules.PendulumSpec(i, hinge or Rules.FallbackHinge(p, path, Run.Act), attrs, Run.Act)
	end
	specs, specsAt = out, os.clock()
	return out
end

-- tests / Studio: forget the cached pendulum specs
function Run.ResetPendulums()
	specs, specsAt = nil, -1e9
end

---------------------------------------------------------------------------------------------------------------------
-- Pendulum hazards (one schedule for every running group)
---------------------------------------------------------------------------------------------------------------------
local function rootPos(player: Player): Vector3?
	local root = core and core.Root(player)
	return root and root.Position or nil
end

-- the runner of `player` in any running group (nil when they are not running)
local function runnerOf(player: Player): any
	for _, run in pairs(Run.Active) do
		local st = run.Data.Run
		local r = st and run.State == "Running" and st.Runners[player.UserId]
		if r and table.find(run.Players, player) then
			return r
		end
	end
	return nil
end

-- a pass really hit a runner (EventHP calls the hazard's OnHit only for damage that landed): the coffin throws them
-- ALONG its swing, and their leg timing allows the flight (faster samples + a time credit, SealRules.Knocked)
function Run.OnPendulumHit(player: Player, def: any)
	local r = runnerOf(player)
	if r then
		Rules.Knocked(r, (tonumber(def.ImpactAt) or Run.Now()) + Run.Act.KnockGrace, Run.Act)
	end
	local v = def.KnockVelocity
	local root = typeof(v) == "Vector3" and core and core.Root(player) or nil
	if root then
		pcall(function()
			root.AssemblyLinearVelocity = v
		end)
	end
end

-- schedules the passes whose telegraph has to appear soon; marks the passes that already struck (Checked) and forgets old ones
function Run.Drive(now: number)
	local EventHP = modules and modules.EventHP
	local a = Run.Act
	if next(Run.Active) ~= nil and EventHP and type(EventHP.Hazard) == "function" then
		local t0 = now + a.PendulumTelegraph + .05
		local t1 = t0 + a.PendulumLead
		for _, spec in ipairs(Run.Pendulums()) do
			for _, cross in ipairs(Rules.Crossings(spec, t0, t1)) do
				local key = spec.Index .. ":" .. cross.K
				if not Run.Scheduled[key] then
					local def = Rules.PendulumHazard(spec, cross, a)
					def.OnHit = function(player: Player)
						Run.OnPendulumHit(player, def)
					end
					local ok, id = pcall(EventHP.Hazard, Run.Zone, def)
					Run.Scheduled[key] = { Def = def, Id = ok and id or nil, ImpactAt = cross.T, Checked = false }
				end
			end
		end
	end
	for key, s in pairs(Run.Scheduled) do
		if not s.Checked and now >= s.ImpactAt then
			s.Checked = true
		end
		if now > s.ImpactAt + 3 then
			Run.Scheduled[key] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Runners
---------------------------------------------------------------------------------------------------------------------
local function round2(x: number): number
	return math.floor(x * 100 + .5) / 100
end

local function finishInfo(run: any): { [number]: any }
	local info = {}
	for uid, r in pairs(run.Data.Run.Runners) do
		info[uid] = { Score = r.Next - 1 }
	end
	return info
end

-- every runner still in the run has finished -> the party wins
local function maybeWin(run: any)
	if run.State ~= "Running" or #run.Players == 0 then
		return
	end
	local st = run.Data.Run
	for _, pl in ipairs(run.Players) do
		local r = st.Runners[pl.UserId]
		if not r or not r.Done then
			return
		end
	end
	SealsMod().Win(run, finishInfo(run))
end

local function facingTo(from: Vector3, to: Vector3?): CFrame
	local cf = CFrame.new(from)
	if to then
		local d = Rules.Flat(to - from)
		if d.Magnitude > .1 then
			cf *= CFrame.Angles(0, math.atan2(-d.X, -d.Z), 0)
		end
	end
	return cf
end

-- a violation: back on the last ring (or the start), the leg timer restarts there; too many = out of the run
local function rewind(run: any, player: Player, r: any, e: any, now: number)
	local S = SealsMod()
	if r.Violations > Run.Act.MaxViolations then
		S.Leave(player, "Invalid")
		return
	end
	local st = run.Data.Run
	local at: Vector3 = (r.Next > 1 and st.Checkpoints[r.Next - 1]) or st.Start
	Run.Teleport(player, facingTo(at, st.Checkpoints[r.Next]))
	Rules.Rewound(r, now, at)
	S.Signal(run, "Rewind", { UserId = player.UserId, Index = r.Next, Reason = e.Kind, Violations = r.Violations }, player)
end

function Run.OnSample(run: any, player: Player, pos: Vector3, t: number)
	local st = run.Data.Run
	if not st or run.State ~= "Running" or t < st.GoAt then
		return
	end
	local r = st.Runners[player.UserId]
	if not r or r.Done then
		return
	end
	local S = SealsMod()
	local c2 = C2()
	for _, e in ipairs(Rules.RunStep(r, pos, t, st.Checkpoints, Run.Act)) do
		if run.State ~= "Running" then
			return
		end
		if e.Kind == "Checkpoint" then
			run.Public.Progress[tostring(player.UserId)] = e.Index
			if c2 then
				c2.QueueShards(player, Run.Act.ObjectiveShards, "Objective")
			end
			S.Signal(run, "Checkpoint", { UserId = player.UserId, Index = e.Index, Split = round2(e.Time - st.GoAt) })
			S.AddScore(run, player, 1)
		elseif e.Kind == "Finish" then
			run.Public.Finish[tostring(player.UserId)] = round2(e.Time - st.GoAt)
			S.Signal(run, "Finish", { UserId = player.UserId, Time = round2(e.Time - st.GoAt) })
			maybeWin(run)
		elseif e.Kind == "Jump" or e.Kind == "TooFast" then
			rewind(run, player, r, e, t)
			return
		end
	end
end

function Run.IsGold(run: any, player: Player): boolean
	local st = run.Data.Run
	local r = st and st.Runners[player.UserId]
	local gold = Cfg.Seals[SEAL].Gold
	return r ~= nil and r.Done and r.FinishAt ~= nil and r.FinishAt - st.GoAt <= (gold.Time or 0) + 1e-6
end

-- the clock ran out: runners who have not finished are out ("Time"); the finishers win
function Run.OnTimeUp(run: any)
	local st = run.Data.Run
	local S = SealsMod()
	for _, pl in ipairs(table.clone(run.Players)) do
		local r = st.Runners[pl.UserId]
		if not (r and r.Done) and run.State == "Running" then
			S.Leave(pl, "Time")
		end
	end
	if run.State == "Running" and #run.Players > 0 then
		S.Win(run, finishInfo(run))
	end
end

-- somebody dropped out: the others may all be home already
function Run.OnLeave(run: any, _player: Player, _reason: string)
	maybeWin(run)
end

function Run.OnStart(run: any)
	local a = Run.Act
	local goAt = run.StartedAt + a.Countdown
	if run.EndsAt > 0 then
		run.EndsAt += a.Countdown
	end
	local cps = Run.Checkpoints()
	local start = Run.StartPos()
	local st = { GoAt = goAt, Checkpoints = cps, Start = start, Runners = {} }
	run.Data.Run = st
	for _, pl in ipairs(run.Players) do
		-- leg 1 runs from where the runner stood when the run began (the start line is held by the client countdown)
		st.Runners[pl.UserId] = Rules.NewRunner(rootPos(pl) or start, goAt)
	end
	local car = Layout.Carnival.Carousel
	local gold = Cfg.Seals[SEAL].Gold
	run.Public = { GoAt = goAt, Gold = { Time = gold.Time }, Checkpoints = #cps, Progress = {}, Finish = {},
		Carousel = Rules.CarouselLeg(cps, car.Centre, car.Radius) or (a.CarouselBetween and a.CarouselBetween[1]) or 0 }
	Run.Active[run.Id] = run
	Run.Drive(Run.Now())
end

function Run.OnTick(run: any, _dt: number)
	if run.State == "Running" then
		Run.Drive(Run.Now())
	end
end

function Run.OnEnd(run: any, _result: string)
	Run.Active[run.Id] = nil
	if next(Run.Active) == nil then
		-- nobody runs any more: the telegraphs of passes still to come go away
		local EventHP = modules and modules.EventHP
		local ids = {}
		for key, s in pairs(Run.Scheduled) do
			if s.Id and not s.Checked then
				table.insert(ids, s.Id)
			end
			Run.Scheduled[key] = nil
		end
		if EventHP and type(EventHP.CancelHazards) == "function" and #ids > 0 then
			pcall(EventHP.CancelHazards, Run.Zone, ids)
		end
	end
end

function Run.Start(c: any, m: any)
	core, modules = c, m
	Run.Modules = m
	Run.Act = Rules.Activity(SEAL)
	if not Shared.Chapter2Enabled() then
		return
	end
	local Seals = m and m.Seals
	if not Seals then
		warn("SealRun: Seals missing; FUNERAL RUN disabled")
		return
	end
	local EventHP = m.EventHP
	if EventHP and type(EventHP.SetZone) == "function" then
		pcall(EventHP.SetZone, Run.Zone, { Spawn = Run.StartPos(), Name = Cfg.Seals[SEAL].Title, Trial = Run.TrialId })
	end
	Seals.Register(SEAL, {
		Combat = true, -- pendulums hit Event HP (§10.1: "Funeral Run (pendulums only)")
		Exclusive = false,
		Spawn = Run.StartPos(),
		Goal = math.max(1, #Run.Checkpoints()),
		OnStart = Run.OnStart, OnTick = Run.OnTick, OnSample = Run.OnSample, OnTimeUp = Run.OnTimeUp, OnLeave = Run.OnLeave,
		OnEnd = Run.OnEnd, IsGold = Run.IsGold,
	})
end

return Run
