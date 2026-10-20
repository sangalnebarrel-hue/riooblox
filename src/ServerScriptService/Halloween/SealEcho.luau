-- BELL SEAL I · ECHO DIG (ServerScriptService.Halloween.SealEcho, WP-I; docs/halloween2/DESIGN.md §8.4.1, §22.4).
-- A Bell Square trial run by the Seals framework: Activity.TimeLimit (90 s) from GO, haunted echo points (Strike kind
-- "UyEcho") rise at the 16 EchoPoint_n anchors; ONE judged timing hit digs an echo. An echo lives Activity.Life s on its
-- point (+ EchoLifeBonus while a party member has H09 Bell Pup in a yard dig slot) and then JUMPS to another free point
-- after a telegraphed trail of Activity.Trail s (part attributes JumpTo / JumpAt). Clear: 12 echoes; Gold: 18 with
-- >= 60% Perfect (Chapter2Config.Seals[1].Gold through Seals.DefaultGold, counted over the whole party).
-- Every dig: Seals.Hit (Perfect share) + Seals.AddScore, Chapter2.StreakHit (Perfect streak shards), Chapter2.Progress
-- "Echo" (contracts / stats / resonance) and Chapter2.QueueShards(Activity.ObjectiveShards, "Echo") (daily DR).
-- Numbers: SealRules.Activity(1) (Chapter2Config.Seals[1].Activity over SealConfig[1]).
-- Echo target part attributes (read by HalloweenClient.Trials.Echo): UyRun, UyTrial, UyMembers, Index, LifeFrom, Life, ExpireAt,
-- JumpTo? (Vector3, the landing point while the jump is telegraphed), JumpAt?, NextPos? (H09: the next landing point,
-- known from the rise), Pup (bool). Public run data (C2Trial .Data): {GoAt, Goal, Gold = {Total, PerfectShare}, Dug, Hits,
-- Perfects, Pup, Life}.
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Rules = require(Halloween:WaitForChild("SealRules"))

local SEAL = 1
local Echo = {}
Echo.Seal = SEAL
Echo.Act = Rules.Activity(SEAL)
Echo.Kind = Echo.Act.Kind or "UyEcho"
Echo.Runs = {} -- run.Id -> run (running)
-- overridable (tests drive the module with a manual clock and fixed rolls)
Echo.Now = function(): number
	return workspace:GetServerTimeNow()
end
local rng = Random.new()
Echo.Roll = function(): number
	return rng:NextNumber()
end

local modules: any = nil
local occupied: { [number]: any } = {} -- echo point index -> target standing on it (every run)
local reserved: { [number]: any } = {} -- echo point index -> target that will land there

local function C2(): any
	return modules and modules.Chapter2
end
local function SealsMod(): any
	return modules and modules.Seals
end
local function StrikeMod(): any
	return modules and modules.Strike
end

-- the echo points: saved anchor parts when present, else the layout
function Echo.Points(): { Vector3 }
	local out = {}
	local c2 = C2()
	for i = 1, math.floor(tonumber(Echo.Act.Points) or #Layout.EchoPoints) do
		local name = "EchoPoint_" .. i
		local p = (c2 and c2.AnchorPos and c2.AnchorPos(name)) or Layout.Anchor(name)
		if not p then
			break
		end
		out[i] = p
	end
	return out
end

local function setAttr(target: any, name: string, value: any)
	local part = target.Part
	if part and part.Parent then
		part:SetAttribute(name, value)
	end
end

local function hitCF(ground: Vector3, facing: number): CFrame
	return CFrame.new(ground + Vector3.new(0, Echo.Act.Lift, 0)) * CFrame.Angles(0, facing, 0)
end

-- the longest H09 Bell Pup bonus of the party (0 without one)
local function pupBonus(run: any): number
	local c2 = C2()
	if not c2 or type(c2.Ability) ~= "function" then
		return 0
	end
	local best = 0
	for _, pl in ipairs(run.Players) do
		local ok, def = pcall(c2.Ability, pl, "HW_BellPup")
		if ok and type(def) == "table" then
			best = math.max(best, tonumber(def.EchoLifeBonus) or 0)
		end
	end
	return best
end

local function takenSet(): { [number]: boolean }
	local out = {}
	for i, t in pairs(occupied) do
		if t.Alive then
			out[i] = true
		end
	end
	for i, t in pairs(reserved) do
		if t.Alive then
			out[i] = true
		end
	end
	return out
end

local function release(target: any)
	local i = target.Data.Index
	if i and occupied[i] == target then
		occupied[i] = nil
	end
	local j = target.Data.NextIndex
	if j and reserved[j] == target then
		reserved[j] = nil
	end
end

-- where this echo jumps next (reserved at once so no other echo lands there)
local function planNext(run: any, target: any): number?
	if target.Data.NextIndex then
		return target.Data.NextIndex
	end
	local st = run.Data.Echo
	local from = st.Points[target.Data.Index]
	local j = Rules.PickPoint(st.Points, takenSet(), from, Echo.Act.MinJumpDistance, Echo.Roll)
	if j then
		target.Data.NextIndex = j
		reserved[j] = target
		if st.Bonus > 0 then
			setAttr(target, "NextPos", st.Points[j]) -- ECHO EAR: the next jump target pulses for the party
		end
	end
	return j
end

local function spawnEcho(run: any, now: number): any?
	local st = run.Data.Echo
	local S = StrikeMod()
	if not S then
		return nil
	end
	local i = Rules.PickPoint(st.Points, takenSet(), nil, 0, Echo.Roll)
	if not i then
		return nil
	end
	local a = Echo.Act
	st.Bonus = pupBonus(run)
	local life = Rules.EchoLife(a, st.Bonus)
	local facing = Echo.Roll() * math.pi * 2
	local size = a.HitSize or { 6, 4.5, 6 }
	local solo = #run.Players <= 1
	local target = S.Add({
		Kind = Echo.Kind, CFrame = hitCF(st.Points[i], facing), Radius = 3.2, Size = Vector3.new(size[1], size[2], size[3]), HP = 1, MaxHP = 1,
		Unit = 1, Color = Color3.fromRGB(150, 230, 200), Material = "Ground", Variant = "Echo", Seed = math.floor(Echo.Roll() * 1e6),
		Name = a.LabelEn, NameRU = a.LabelRu, Ground = st.Points[i], Facing = facing, Panel = false, Shared = not solo, Owner = run.Leader,
		Data = { Run = run, Index = i },
		Attributes = { UyRun = run.Id, UyTrial = run.TrialId, UyMembers = Rules.Members(run.Players), Index = i, LifeFrom = now, Life = life,
			ExpireAt = now + life, Pup = st.Bonus > 0 },
	})
	occupied[i] = target
	st.Targets[target.Id] = target
	target.Data.ExpireAt = now + life
	target.Data.Life = life
	if st.Bonus > 0 then
		planNext(run, target)
	end
	return target
end

-- the telegraphed trail starts (JumpTo / JumpAt), then the echo lands on its next point with a fresh life
local function stepEcho(run: any, target: any, now: number)
	local st = run.Data.Echo
	local a = Echo.Act
	local expire = target.Data.ExpireAt
	if not target.Data.Jumping and now >= expire - a.Trail then
		local j = planNext(run, target)
		if j then
			target.Data.Jumping = true
			setAttr(target, "JumpTo", st.Points[j])
			setAttr(target, "JumpAt", expire)
		else
			target.Data.ExpireAt = expire + 1 -- nowhere free to go: it lingers a moment longer
			setAttr(target, "ExpireAt", target.Data.ExpireAt)
		end
		return
	end
	if target.Data.Jumping and now >= expire then
		local j = target.Data.NextIndex
		release(target)
		target.Data.Jumping, target.Data.NextIndex = false, nil
		if not j or not st.Points[j] then
			return
		end
		occupied[j] = target
		target.Data.Index = j
		st.Bonus = pupBonus(run)
		local life = Rules.EchoLife(a, st.Bonus)
		local facing = Echo.Roll() * math.pi * 2
		local S = StrikeMod()
		if S then
			S.Move(target, hitCF(st.Points[j], facing))
		end
		target.Data.ExpireAt, target.Data.Life = now + life, life
		target.Data.Jumps = (target.Data.Jumps or 0) + 1
		setAttr(target, "Ground", st.Points[j])
		setAttr(target, "Facing", facing)
		setAttr(target, "Index", j)
		setAttr(target, "LifeFrom", now)
		setAttr(target, "Life", life)
		setAttr(target, "ExpireAt", now + life)
		setAttr(target, "Pup", st.Bonus > 0)
		setAttr(target, "JumpTo", nil)
		setAttr(target, "JumpAt", nil)
		setAttr(target, "NextPos", nil)
		st.Jumps += 1
		if st.Bonus > 0 then
			planNext(run, target)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Strike kind
---------------------------------------------------------------------------------------------------------------------
local function member(run: any, player: Player): boolean
	return table.find(run.Players, player) ~= nil
end

function Echo.CanHit(player: Player, target: any): (boolean, string?)
	local run = target.Data.Run
	if not run or run.State ~= "Running" then
		return false, "HW:GONE"
	end
	if not member(run, player) then
		return false, "HW:NOT_YOURS"
	end
	if Echo.Now() < run.Data.Echo.GoAt then
		return false, "HW:WAIT"
	end
	return true, nil
end

-- one judged hit digs the echo (Damage = its whole HP): every score / reward happens here, synchronously
function Echo.OnHit(player: Player, target: any, hit: any): any
	local run = target.Data.Run
	if not run or run.State ~= "Running" or target.Data.Dug then
		hit.Applied = 0
		return nil
	end
	local perfect = hit.Quality == 2
	local now = Echo.Now()
	local st = run.Data.Echo
	target.Data.Dug = { UserId = player.UserId, Perfect = perfect }
	release(target)
	st.Targets[target.Id] = nil
	table.insert(st.Due, now + Echo.Act.RespawnDelay)
	local S = SealsMod()
	S.Hit(run, player, perfect)
	local c2 = C2()
	if c2 then
		c2.StreakHit(player, perfect)
		c2.Progress(player, "Echo", 1)
		c2.QueueShards(player, Echo.Act.ObjectiveShards, "Echo")
	end
	local pub = run.Public
	pub.Dug = run.Total + 1
	pub.Hits = run.Data.Hits or 0
	pub.Perfects = run.Data.Perfects or 0
	S.AddScore(run, player, 1)
	return { Echo = true, Perfect = perfect }
end

-- any removal (dug, run end): the point is free again
function Echo.OnRemove(target: any, _reason: string?)
	release(target)
	local run = target.Data.Run
	local st = run and run.Data and run.Data.Echo
	if st then
		st.Targets[target.Id] = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The trial (Seals def)
---------------------------------------------------------------------------------------------------------------------
function Echo.OnStart(run: any)
	local a = Echo.Act
	local goAt = run.StartedAt + a.Countdown
	if run.EndsAt > 0 then
		run.EndsAt += a.Countdown
	end
	local st = { GoAt = goAt, Points = Echo.Points(), Targets = {}, Due = {}, Bonus = pupBonus(run), Jumps = 0 }
	run.Data.Echo = st
	local want = Rules.EchoAlive(a, #run.Players)
	for k = 0, want - 1 do
		table.insert(st.Due, goAt + k * a.SpawnStagger)
	end
	local gold = Cfg.Seals[SEAL].Gold
	run.Public = { GoAt = goAt, Goal = run.Goal, Gold = { Total = gold.Total, PerfectShare = gold.PerfectShare }, Dug = 0, Hits = 0, Perfects = 0,
		Pup = st.Bonus > 0, Life = Rules.EchoLife(a, st.Bonus) }
	Echo.Runs[run.Id] = run
end

function Echo.OnTick(run: any, _dt: number)
	local st = run.Data.Echo
	if not st or run.State ~= "Running" then
		return
	end
	local now = Echo.Now()
	if now < st.GoAt then
		return
	end
	for _, t in pairs(table.clone(st.Targets)) do
		if t.Alive then
			stepEcho(run, t, now)
		else
			st.Targets[t.Id] = nil
		end
	end
	-- rises due now (one per due time; a missing point retries half a second later)
	local want = Rules.EchoAlive(Echo.Act, #run.Players)
	local alive = 0
	for _ in pairs(st.Targets) do
		alive += 1
	end
	table.sort(st.Due)
	while #st.Due > 0 and st.Due[1] <= now do
		table.remove(st.Due, 1)
		if alive < want then
			if spawnEcho(run, now) then
				alive += 1
			else
				table.insert(st.Due, now + .5)
				break
			end
		end
	end
	if alive + #st.Due < want then
		table.insert(st.Due, now + Echo.Act.RespawnDelay)
	end
	run.Public.Alive = alive
end

-- a member left: their prompts go (UyMembers), the alive count follows the party (OnTick)
function Echo.OnLeave(run: any, _player: Player, _reason: string)
	local st = run.Data.Echo
	if not st then
		return
	end
	local members = Rules.Members(run.Players)
	for _, t in pairs(st.Targets) do
		setAttr(t, "UyMembers", members)
	end
end

function Echo.OnEnd(run: any, result: string)
	Echo.Runs[run.Id] = nil
	local st = run.Data.Echo
	if not st then
		return
	end
	local S = StrikeMod()
	for _, t in pairs(st.Targets) do
		release(t)
		if S and t.Alive then
			S.Remove(t, result == "Won" and "Won" or "End")
		end
	end
	table.clear(st.Targets)
	table.clear(st.Due)
end

function Echo.Start(_core: any, m: any)
	modules = m
	Echo.Act = Rules.Activity(SEAL)
	if not Shared.Chapter2Enabled() then
		return
	end
	local Seals, Strike = m and m.Seals, m and m.Strike
	if not Seals or not Strike then
		warn("SealEcho: Seals or Strike missing; ECHO DIG disabled")
		return
	end
	Strike.Register(Echo.Kind, {
		Range = Echo.Act.Range, Verb = "DIG", Perfect = false, Activity = "Hit", Remove = true,
		Damage = function(_player, target)
			return target.HP
		end,
		CanHit = Echo.CanHit, OnHit = Echo.OnHit, OnRemove = Echo.OnRemove,
	})
	Seals.Register(SEAL, { OnStart = Echo.OnStart, OnTick = Echo.OnTick, OnLeave = Echo.OnLeave, OnEnd = Echo.OnEnd })
end

return Echo
