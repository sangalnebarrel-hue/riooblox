-- CHAPTER II onboarding on the server (ServerScriptService.Halloween.Chapter2Tutorial, WP-H2; docs/halloween2/DESIGN.md
-- §9 "Chapter II onboarding", §22.2, §22.4). Started by HalloweenServer after Seals (start(name, Core, modules)); reaches
-- Chapter2, Seals, EventHP, Strike and Underyard lazily through `modules` (DESIGN §22.1). The steps themselves live in
-- Chapter2 (C2Tutorial, Chapter2Config.Tutorial); this module makes steps 1, 2 and 5 playable:
--   * TUTORIAL ECHOES (step 1 "Bell Shards"): three echo targets per player at TutorialEcho_1..3 while that player is on
--     step 1 inside the Underyard (Strike kind UyTutorialEcho, owner-only, gone when the step is). Every judged hit feeds
--     the Perfect streak (C2.StreakHit: 5 Perfects in a row pay streak shards); digging an echo out pays
--     UnderyardRuntime.Config.TutorialEcho.Shards Echo shards (daily returns apply) and respawns it a moment later. Ten
--     earned shards complete the step (Chapter2 Auto "ShardsEarned").
--   * THE TRIAL OF THE TOLL ("Toll", step 2): BEGIN TRIAL at TutorialBell -> an owner-only hand-bell target (UyTollBell):
--     only a Perfect hit rings it on the beat; 5 tolls win (Seals WinAtGoal) -> TutorialEvent "Toll".
--   * THE MOURNER ("Mourner", step 5): BEGIN TRIAL at the Mourner -> the player's own Event HP zone ("Practice:<RunId>",
--     the HP bar appears); the dummy telegraphs Circle (on the player) -> Line (through the player) -> Ring (round it, one
--     gap) through EventHP.Hazard with low damage; a cycle with 2 dodges opens the weak spot (UyMournerWeak, owner-only)
--     for WeakWindow s — only a Perfect hit on it wins -> TutorialEvent "Mourner"; fewer dodges -> the cycle repeats.
--     Downed: the ghost guide revives the player after ReviveAfter s (EventHP.Revive; the solo "wipe" is cancelled for
--     these zones, so no bleed-out). Numbers: UnderyardRuntime.Config.Mourner; rules: UnderyardRuntime.Mourner*.
-- The two trials grant nothing themselves and can only be started on their own guide step (a won trial advances the
-- step), so they cannot be farmed for trial contracts or resonance. A failed or abandoned run can be retried at once.
-- Their BEGIN TRIAL prompts are this module's own (attribute UyTutorialTrial = "Toll" | "Mourner", not the Seals
-- framework's UyTrialId): HalloweenClient.Chapter2Guide shows each one only to a player on its step who is not in a run.
-- C2Trial signals besides Seals' own (to the run's player): Toll {Count, Goal, Counted}; MournerAttack {Attack, Index,
--   Cycle, ImpactAt, Telegraph, Target, Gap?}; MournerResult {Outcome = "Dodged"|"Hit", Dodges, Need, Next =
--   "Next"|"Again"|"Weak"}; WeakOpen {Until, TargetId}; WeakHit {}; WeakMiss {}; WeakClose {}; Downed {ReviveAt};
--   Revived {}; Far {} (the player left the ring: no attacks until they are back).
-- Overridable for tests: CT.Now() (server time), CT.Defer(fn) (runs after the wipe bookkeeping), CT.Root(player).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Runtime = require(Halloween:WaitForChild("UnderyardRuntime"))
local Hazards = require(Halloween:WaitForChild("Hazards"))

local CT = {}
CT.Runtime = Runtime
local Cfg = Runtime.Config
local V3 = Vector3.new
local C3 = Color3.fromRGB

local core: any = nil
local modules: any = nil

CT.Now = function(): number
	return workspace:GetServerTimeNow()
end
CT.Defer = function(fn: () -> ())
	task.defer(fn)
end
CT.Root = function(player: Player): BasePart?
	if core then
		return core.Root(player)
	end
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

local function mod(name: string): any
	return modules and modules[name]
end

local STEP = { Toll = 2, Mourner = 5 } -- the guide step each practice trial belongs to (Chapter2Config.Tutorial.Steps)
CT.Step = STEP
local ECHO_SLOTS = 3

-- a gameplay point (the live anchor part when there is one, else UnderyardLayout)
local function anchor(name: string): Vector3?
	local c2 = mod("Chapter2")
	if c2 and type(c2.AnchorPos) == "function" then
		local ok, pos = pcall(c2.AnchorPos, name)
		if ok and typeof(pos) == "Vector3" then
			return pos
		end
	end
	return Layout.Anchor(name)
end
CT.Anchor = anchor

-- the Mourner stands on its pedestal at the practice ring's centre (ground level)
local function mournerGround(): Vector3
	local a = anchor("Mourner") or (Layout.Square.Mourner + V3(0, 3, 0))
	return V3(a.X, Layout.Floor, a.Z)
end
CT.MournerGround = mournerGround

---------------------------------------------------------------------------------------------------------------------
-- step 1: the tutorial echoes
---------------------------------------------------------------------------------------------------------------------
local echoes: { [Player]: any } = {}
CT.Echoes = echoes

local function wantsEchoes(player: Player): boolean
	local c2, uy = mod("Chapter2"), mod("Underyard")
	if not (c2 and uy) or not Shared.Chapter2Enabled() or not player.Parent then
		return false
	end
	return c2.TutorialStep(player) == 1 and uy.InZone(player) == true and c2.Eligible(player) == true
end
CT.WantsEchoes = wantsEchoes

local function clearEchoes(player: Player)
	local st = echoes[player]
	echoes[player] = nil
	local Strike = mod("Strike")
	if st and Strike then
		for _, t in pairs(st.Targets) do
			if not t.Removed then
				Strike.Remove(t, "Tutorial")
			end
		end
	end
end
CT.ClearEchoes = clearEchoes

local function spawnEcho(player: Player, st: any, slot: number)
	local Strike = mod("Strike")
	local base = anchor("TutorialEcho_" .. slot)
	if not (Strike and base) then
		return
	end
	local ec = Cfg.TutorialEcho
	local pos = (base :: Vector3) + V3(0, ec.Lift, 0)
	st.Targets[slot] = Strike.Add({
		Kind = ec.Kind, Position = pos, Radius = ec.Radius, HP = ec.HP, MaxHP = ec.HP, Owner = player, Shared = false,
		Name = "ECHO", NameRU = "ЭХО", Color = C3(150, 200, 255), Material = "Neon", Panel = true, Seed = slot,
		Ground = V3(pos.X, Layout.Floor, pos.Z), Data = { UserId = player.UserId, Slot = slot },
		Attributes = { UyTutorialEcho = slot },
	})
	st.Spawned += 1
end

-- 1 s per player (Chapter2.OnTick): echoes exist exactly while the player is on step 1 in the Underyard
function CT.EchoTick(player: Player)
	if not wantsEchoes(player) then
		if echoes[player] then
			clearEchoes(player)
		end
		return
	end
	local st = echoes[player]
	if not st then
		st = { Targets = {}, RespawnAt = {}, Spawned = 0, Dug = 0 }
		echoes[player] = st
	end
	local now = CT.Now()
	for slot = 1, ECHO_SLOTS do
		local t = st.Targets[slot]
		if (t == nil or t.Removed) and now >= (st.RespawnAt[slot] or 0) then
			st.Targets[slot] = nil
			spawnEcho(player, st, slot)
		end
	end
end

local function echoDug(player: Player?, target: any)
	local data = target.Data or {}
	local owner = Players:GetPlayerByUserId(tonumber(data.UserId) or 0) or player
	local st = owner and echoes[owner]
	if st then
		st.Targets[data.Slot or 0] = nil
		st.RespawnAt[data.Slot or 0] = CT.Now() + Cfg.TutorialEcho.Respawn
		st.Dug += 1
	end
	local c2 = mod("Chapter2")
	if c2 and owner then
		c2.QueueShards(owner, Cfg.TutorialEcho.Shards, "Echo")
		c2.Progress(owner, "Echo", 1)
	end
end
CT.EchoDug = echoDug

---------------------------------------------------------------------------------------------------------------------
-- step 2: the Trial of the Toll
---------------------------------------------------------------------------------------------------------------------
local function runOf(player: Player, trialId: string): any
	local Seals = mod("Seals")
	local run = Seals and Seals.RunOf(player)
	if run and run.TrialId == trialId and run.State == "Running" then
		return run
	end
	return nil
end

local function removeTarget(t: any, reason: string)
	local Strike = mod("Strike")
	if t and Strike and not t.Removed then
		Strike.Remove(t, reason)
	end
end

local function canStart(trialId: string): (Player) -> (boolean, string?)
	return function(player: Player): (boolean, string?)
		local c2 = mod("Chapter2")
		if not c2 or c2.TutorialStep(player) ~= STEP[trialId] then
			return false, "This practice is part of the Underyard guide"
		end
		if player:GetAttribute("HwDowned") == true then
			return false, "You are downed: wait for a revive"
		end
		return true, nil
	end
end

function CT.TollDef(): { [string]: any }
	return {
		Name = { "TRIAL OF THE TOLL", "ИСПЫТАНИЕ ЗВОНА" }, StartAnchor = "TutorialBell", District = "BellSquare", Combat = false,
		Exclusive = false, WinAtGoal = true, TutorialEvent = "Toll", Goal = Cfg.Toll.Goal,
		Prompt = false, -- CT.Prompts: shown by the guide to players on this step only
		CanStart = canStart("Toll"),
		OnStart = function(run)
			local Strike = mod("Strike")
			local bell = anchor("TutorialBell")
			if not (Strike and bell) then
				error("no hand-bell")
			end
			run.Data.Toll = Runtime.TollNew(Cfg.Toll.Goal)
			run.Public.Count = 0
			run.Public.Goal = Cfg.Toll.Goal
			local pos = (bell :: Vector3) + V3(0, 1, 0)
			run.Data.Target = Strike.Add({
				Kind = Cfg.Toll.Kind, Position = pos, Radius = 1.6, HP = 1, MaxHP = 1, Owner = run.Leader, Shared = false,
				Name = "HAND BELL", NameRU = "КОЛОКОЛЬЧИК", Color = C3(214, 170, 92), Material = "Metal", Panel = false,
				Ground = V3(pos.X, Layout.Floor, pos.Z), Data = { RunId = run.Id, TrialId = "Toll" }, Attributes = { UyTrialTarget = "Toll" },
			})
			run.Public.Target = run.Data.Target.Id
		end,
		OnLeave = function(run)
			if #run.Players == 0 then
				removeTarget(run.Data.Target, "Left")
			end
		end,
		OnEnd = function(run, result)
			removeTarget(run.Data.Target, result == "Won" and "Won" or "Ended")
		end,
	}
end

-- one judged hit on the hand-bell -> extra for the hitter
function CT.TollHit(player: Player, target: any, hit: any): any
	hit.Applied = 0
	local run = runOf(player, "Toll")
	if not run or run.Data.Target ~= target then
		return { Toll = 0, Counted = false }
	end
	local Seals = mod("Seals")
	local perfect = hit.Quality == 2
	Seals.Hit(run, player, perfect)
	local st = run.Data.Toll
	local counted = Runtime.TollHit(st, perfect)
	run.Public.Count = st.Count
	Seals.Signal(run, "Toll", { Count = st.Count, Goal = st.Goal, Counted = counted, UserId = player.UserId })
	if counted then
		Seals.AddScore(run, player, 1) -- the fifth toll wins (WinAtGoal)
	end
	return { Toll = st.Count, Goal = st.Goal, Counted = counted }
end

---------------------------------------------------------------------------------------------------------------------
-- step 5: the Mourner
---------------------------------------------------------------------------------------------------------------------
local zones: { [string]: any } = {} -- tutorial Event HP zone -> run
CT.Zones = zones
local KIND_OF = { Circle = "Slam", Line = "Line", Ring = "Shockwave" } -- CombatFX telegraph colours

local function hazardOf(shape: any): any
	if shape.Type == "Circle" then
		return Hazards.Circle(shape.Center, shape.Radius)
	elseif shape.Type == "Line" then
		return Hazards.Line(shape.From, shape.To, shape.Width)
	end
	return Hazards.Ring(shape.Center, shape.Inner, shape.Outer, shape.Gaps)
end

local function hpState(player: Player): (number?, number?)
	local EventHP = mod("EventHP")
	if not EventHP then
		return nil, nil
	end
	local P = type(EventHP.States) == "table" and EventHP.States[player] or nil
	local last = P and P.St and tonumber(P.St.LastHitAt) or nil
	local hp, _, shield = EventHP.HP(player)
	return last, (tonumber(hp) or 0) + (tonumber(shield) or 0)
end

-- did the attack in the air land on the player? (Event HP lost after it was cast, or downed)
local function wasHit(run: any, player: Player, impactAt: number): boolean
	local EventHP = mod("EventHP")
	if not EventHP then
		return false
	end
	if EventHP.IsDowned(player) then
		return true
	end
	local last, hp = hpState(player)
	if last ~= nil and run.Data.LastHit0 ~= nil then
		return last > run.Data.LastHit0 + 1e-6 and last >= impactAt - .3
	end
	return hp ~= nil and run.Data.HP0 ~= nil and hp < run.Data.HP0 - .5
end
CT.WasHit = wasHit

local function signal(run: any, kind: string, extra: any)
	local Seals = mod("Seals")
	if Seals then
		Seals.Signal(run, kind, extra)
	end
end

local function openWeak(run: any, st: any)
	local Strike = mod("Strike")
	if not Strike then
		return
	end
	removeTarget(run.Data.Weak, "Reopen")
	local mc = Cfg.Mourner
	local pos = mournerGround() + V3(0, mc.WeakLift, 0)
	run.Data.Weak = Strike.Add({
		Kind = mc.Kind, Position = pos, Radius = mc.WeakRadius, HP = 1, MaxHP = 1, Owner = run.Leader, Shared = false,
		Name = "WEAK SPOT", NameRU = "СЛАБОЕ МЕСТО", Color = C3(mc.Color[1], mc.Color[2], mc.Color[3]), Material = "Neon", Panel = false,
		Ground = mournerGround(), Data = { RunId = run.Id, TrialId = "Mourner" }, Attributes = { UyTrialTarget = "Mourner" },
	})
	run.Public.Phase = "Weak"
	run.Public.WeakUntil = st.WeakUntil
	signal(run, "WeakOpen", { Until = st.WeakUntil, TargetId = run.Data.Weak.Id })
end

local function attack(run: any, st: any, now: number)
	local player = run.Leader
	local root = CT.Root(player)
	local EventHP = mod("EventHP")
	if not root or not EventHP then
		return -- (no character for a moment: try on the next tick)
	end
	local mc = Cfg.Mourner
	local centre = mournerGround()
	local target = (root :: BasePart).Position
	if V3(target.X - centre.X, 0, target.Z - centre.Z).Magnitude > mc.FarRadius then
		-- the player walked off: the Mourner waits for them at its ring
		if not run.Data.FarSaid then
			run.Data.FarSaid = true
			signal(run, "Far", {})
		end
		st.NextAt = now + .5
		return
	end
	run.Data.FarSaid = nil
	local kind = Runtime.MournerNextKind(st)
	local gap = kind == "Ring" and Runtime.MournerGapAngle(centre, target, run.Id * 7 + st.Cycle * 3 + st.Index) or nil
	local shape = Runtime.MournerShape(kind, centre, target, gap)
	local impactAt = now + .35 + mc.Telegraph
	run.Data.LastHit0, run.Data.HP0 = hpState(player)
	EventHP.Hazard(run.Data.Zone, { Shape = hazardOf(shape), Telegraph = mc.Telegraph, ImpactAt = impactAt, Damage = mc.Damage,
		Knock = { Power = 20, Up = 12 }, Kind = KIND_OF[kind], Source = "Mourner", Color = C3(mc.Color[1], mc.Color[2], mc.Color[3]),
		Trial = "Mourner" })
	Runtime.MournerAttacked(st, kind, impactAt)
	run.Public.Phase = "Telegraph"
	signal(run, "MournerAttack", { Attack = kind, Index = st.Index, Cycle = st.Cycle, ImpactAt = impactAt, Telegraph = mc.Telegraph,
		Target = target, Gap = gap, Retry = st.Retry or nil })
end

local function evaluate(run: any, st: any, now: number)
	local player = run.Leader
	local impactAt = st.Attack and st.Attack.ImpactAt or now
	local hit = wasHit(run, player, impactAt)
	local outcome, follow = Runtime.MournerResolve(st, hit, now)
	run.Public.Dodges = st.Dodges
	run.Public.Phase = st.Phase
	signal(run, "MournerResult", { Outcome = outcome, Dodges = st.Dodges, Need = Cfg.Mourner.NeedDodges, Next = follow, Cycle = st.Cycle })
	if follow == "Weak" then
		openWeak(run, st)
	end
end

local function closeWeak(run: any, st: any, now: number)
	removeTarget(run.Data.Weak, "Closed")
	run.Data.Weak = nil
	Runtime.MournerWeakClosed(st, now)
	run.Public.Phase = st.Phase
	signal(run, "WeakClose", {})
end

local function revive(run: any, st: any, now: number)
	local EventHP = mod("EventHP")
	local player = run.Leader
	if EventHP and EventHP.IsDowned(player) then
		EventHP.Revive(player, nil, { HP = Cfg.Mourner.ReviveHP })
	end
	local follow = Runtime.MournerRevived(st, now)
	run.Public.Phase = st.Phase
	signal(run, "Revived", { Next = follow })
	if follow == "Weak" then
		openWeak(run, st)
	end
end

local function cleanupMourner(run: any)
	local EventHP = mod("EventHP")
	local zone = run.Data.Zone
	removeTarget(run.Data.Weak, "Ended")
	run.Data.Weak = nil
	if zone then
		zones[zone] = nil
		if EventHP then
			pcall(EventHP.CancelHazards, zone)
			pcall(EventHP.Leave, run.Leader, zone)
			-- the run's own zone is done: forget it once nobody is in it (one small table per run otherwise)
			local z = type(EventHP.Zones) == "table" and EventHP.Zones[zone] or nil
			if z and next(z.Members or {}) == nil then
				EventHP.Zones[zone] = nil
			end
		end
	end
end

function CT.MournerDef(): { [string]: any }
	return {
		Name = { "THE MOURNER", "ПЛАКАЛЬЩИК" }, StartAnchor = "Mourner", District = "BellSquare", Combat = false, Exclusive = false,
		WinAtGoal = true, TutorialEvent = "Mourner", Goal = 1,
		Prompt = false, -- CT.Prompts
		CanStart = canStart("Mourner"),
		OnStart = function(run)
			local EventHP = mod("EventHP")
			if not EventHP then
				error("no EventHP")
			end
			local zone = "Practice:" .. tostring(run.Id)
			local ring = Layout.Square.PracticeRing
			local spawn = ring.Centre + V3(0, 3, -(ring.Radius - 2.5))
			EventHP.SetZone(zone, { Spawn = CFrame.lookAt(spawn, ring.Centre + V3(0, 3, 0)), Name = { "PRACTICE · THE MOURNER", "ТРЕНИРОВКА · ПЛАКАЛЬЩИК" },
				Trial = "Mourner" })
			zones[zone] = run
			run.Data.Zone = zone
			EventHP.Enter(run.Leader, zone, { Trial = "Mourner" })
			run.Data.M = Runtime.MournerNew(CT.Now())
			run.Public.Phase = "Intro"
			run.Public.Dodges = 0
			run.Public.Need = Cfg.Mourner.NeedDodges
			run.Public.Centre = mournerGround()
		end,
		OnTick = function(run)
			local st = run.Data.M
			if not st or run.State ~= "Running" then
				return
			end
			local now = CT.Now()
			local due = Runtime.MournerDue(st, now)
			if due == "Attack" then
				attack(run, st, now)
			elseif due == "Evaluate" then
				evaluate(run, st, now)
			elseif due == "CloseWeak" then
				closeWeak(run, st, now)
			elseif due == "Revive" then
				revive(run, st, now)
			end
		end,
		OnLeave = function(run)
			if #run.Players == 0 then
				cleanupMourner(run)
			end
		end,
		OnEnd = function(run)
			cleanupMourner(run)
		end,
	}
end

-- one judged hit on the weak spot: only a Perfect while it is open wins
function CT.WeakHit(player: Player, target: any, hit: any): any
	hit.Applied = 0
	local run = runOf(player, "Mourner")
	if not run or run.Data.Weak ~= target then
		return { Weak = false }
	end
	local Seals = mod("Seals")
	local perfect = hit.Quality == 2
	Seals.Hit(run, player, perfect)
	if Runtime.MournerWeakHit(run.Data.M, perfect) then
		run.Public.Phase = "Won"
		-- the heart leaves with reason "Won" (UnderyardFX collapses the dummy on it)
		removeTarget(run.Data.Weak, "Won")
		run.Data.Weak = nil
		signal(run, "WeakHit", { UserId = player.UserId })
		Seals.AddScore(run, player, 1) -- wins (WinAtGoal)
		return { Weak = true, Perfect = true }
	end
	signal(run, "WeakMiss", { UserId = player.UserId })
	return { Weak = true, Perfect = false }
end

-- EventHP: a tutorial player went down -> hazards cancelled, revive scheduled; their solo "wipe" is called off
function CT.OnDown(player: Player, zoneId: string)
	local run = zones[zoneId]
	if not run or run.State ~= "Running" then
		return
	end
	local EventHP = mod("EventHP")
	if EventHP then
		pcall(EventHP.CancelHazards, zoneId)
	end
	local st = run.Data.M
	Runtime.MournerDowned(st, CT.Now())
	run.Public.Phase = st.Phase
	signal(run, "Downed", { ReviveAt = st.ReviveAt, UserId = player.UserId })
end

function CT.OnWipe(zoneId: string)
	if not zones[zoneId] then
		return
	end
	-- EventHP arms the bleed-out after the listeners ran: cancel it once it is set (the guide revives instead)
	CT.Defer(function()
		local EventHP = mod("EventHP")
		local z = EventHP and type(EventHP.Zones) == "table" and EventHP.Zones[zoneId]
		if z then
			z.WipeToken = nil
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Strike kinds + start
---------------------------------------------------------------------------------------------------------------------
local function ownerOnly(player: Player, target: any): (boolean, string?)
	if target.Owner ~= player then
		return false, "HW:NOT_YOURS"
	end
	return true, nil
end

function CT.RegisterKinds()
	local Strike = mod("Strike")
	if not Strike then
		return false
	end
	local ec = Cfg.TutorialEcho
	Strike.Register(ec.Kind, {
		Range = ec.Range, Verb = "DIG", Perfect = false, Activity = "Hit",
		Damage = function(_player, _target, hit)
			return hit.Quality == 2 and 2 or 1
		end,
		CanHit = function(player, target)
			local ok, err = ownerOnly(player, target)
			if not ok then
				return ok, err
			end
			if not wantsEchoes(player) then
				return false, "HW:GONE"
			end
			return true
		end,
		OnHit = function(player, _target, hit)
			local c2 = mod("Chapter2")
			if c2 then
				c2.StreakHit(player, hit.Quality == 2)
			end
			return { Echo = true, Perfect = hit.Quality == 2 }
		end,
		OnBreak = function(killer, target)
			echoDug(killer, target)
		end,
	})
	Strike.Register(Cfg.Toll.Kind, {
		Range = Cfg.Toll.Range, Verb = "STRIKE", Perfect = false, Activity = "Hit", Remove = false,
		Damage = function()
			return 0
		end,
		CanHit = function(player, target)
			local ok, err = ownerOnly(player, target)
			if not ok then
				return ok, err
			end
			local run = runOf(player, "Toll")
			if not run or run.Data.Target ~= target then
				return false, "HW:GONE"
			end
			return true
		end,
		OnHit = function(player, target, hit)
			return CT.TollHit(player, target, hit)
		end,
	})
	Strike.Register(Cfg.Mourner.Kind, {
		Range = Cfg.Mourner.WeakRange, Verb = "STRIKE", Perfect = false, Activity = "Hit", Remove = false,
		Damage = function()
			return 0
		end,
		CanHit = function(player, target)
			local ok, err = ownerOnly(player, target)
			if not ok then
				return ok, err
			end
			local run = runOf(player, "Mourner")
			if not run or run.Data.Weak ~= target or not run.Data.M or run.Data.M.Phase ~= "Weak" then
				return false, "HW:GONE"
			end
			return true
		end,
		OnHit = function(player, target, hit)
			return CT.WeakHit(player, target, hit)
		end,
	})
	return true
end

-- the BEGIN TRIAL prompts of the two practice trials (on the TutorialBell / Mourner anchors; the client shows each only
-- on its guide step)
CT.PromptDefs = {
	{ Trial = "Toll", Anchor = "TutorialBell", Object = { "TRIAL OF THE TOLL", "ИСПЫТАНИЕ ЗВОНА" } },
	{ Trial = "Mourner", Anchor = "Mourner", Object = { "THE MOURNER", "ПЛАКАЛЬЩИК" } },
}
function CT.Prompts(): { [string]: ProximityPrompt }
	local out = {}
	local uy = mod("Underyard")
	if not uy then
		return out
	end
	for _, d in ipairs(CT.PromptDefs) do
		out[d.Trial] = uy.Prompt(d.Anchor, {
			Name = "UyTutorialPrompt", ActionText = "BEGIN TRIAL", ActionTextRU = "НАЧАТЬ ИСПЫТАНИЕ", ObjectText = d.Object[1],
			ObjectTextRU = d.Object[2], HoldDuration = .3, MaxActivationDistance = 12, Attributes = { UyTutorialTrial = d.Trial },
		}, function(player)
			local Seals = mod("Seals")
			if not Seals then
				return
			end
			local ok, err = Seals.Start(player, d.Trial)
			local c2 = mod("Chapter2")
			if not ok and type(err) == "string" and c2 then
				c2.Toast(player, err)
			end
		end)
	end
	return out
end

function CT.Start(c: any, m: any)
	core, modules = c, m
	if not Shared.Chapter2Enabled() then
		return
	end
	local Seals, C2, EventHP = mod("Seals"), mod("Chapter2"), mod("EventHP")
	if not (Seals and C2) then
		warn("Chapter2Tutorial: Seals / Chapter2 missing, the onboarding trials are off")
		return
	end
	CT.RegisterKinds()
	Seals.RegisterTrial("Toll", CT.TollDef())
	Seals.RegisterTrial("Mourner", CT.MournerDef())
	CT.Prompts()
	if EventHP then
		if type(EventHP.OnDown) == "function" then
			EventHP.OnDown(function(player, zoneId)
				CT.OnDown(player, zoneId)
			end)
		end
		if type(EventHP.OnWipe) == "function" then
			EventHP.OnWipe(function(zoneId)
				CT.OnWipe(zoneId)
			end)
		end
	end
	if type(C2.OnTick) == "function" then
		C2.OnTick(function(player)
			CT.EchoTick(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		clearEchoes(player)
	end)
end

return CT
