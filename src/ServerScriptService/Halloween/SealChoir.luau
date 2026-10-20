-- BELL SEAL VI · CHOIR HUNT (ServerScriptService.Halloween.SealChoir, WP-J; docs/halloween2/DESIGN.md §8.4 item 6).
-- 8 min across every unlocked district: seven choir spirits (Strike kind "UyChoir", ONE timing circle, 1 HP) wander their
-- loops of UnderyardLayout.ChoirPaths (Seals2Config.Choir.Routes; a route in a district a party member has not unlocked
-- falls back to a ring-road loop), lingering at each point. Each spirit sings one note of the Last Bell's song on a
-- deterministic server-time schedule (run.Public: SingEvery + spirit index -> Seals2Rules.SingAt; the clients play it
-- as 3D "ChoirNote" at the spirit), the only hint where they are. Only a server-confirmed PERFECT catches a spirit; a
-- Good hit startles it: it flees Chapter2Config.Choir.FleeDistance studs along its loop, away from the hitter.
-- H13 Moth Hound in a member's yard team: every few seconds that member's client is told the nearest spirit
-- (C2Trial "ChoirMoth", to that player only). Clear: all 7 (Seals WinAtGoal); Gold: <= 5 min (Chapter2Config.Seals[6].Gold).
-- Every catch: C2.Progress "Spirit" (contract, stats, resonance), objective shards (DR "Spirit"), Seals.AddScore; every
-- judged hit: C2.StreakHit + Seals.Hit. C2Trial kinds: "ChoirCaught" {TargetId, Note, UserId, Caught}, "ChoirFlee"
-- {TargetId, From, To, UserId}, "ChoirMoth" {TargetId, Note}.
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Base = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Cfg = require(Halloween:WaitForChild("Seals2Config"))
local SR = require(Halloween:WaitForChild("Seals2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local Choir = {}
Choir.Config = Cfg

local SEAL = 6
local CC = Cfg.Choir
local ACT = Base.Seals[SEAL].Activity

local core: any = nil
local modules: any = nil
local runsById: { [number]: any } = {}
local rng = Random.new()

Choir.Now = function(): number
	return workspace:GetServerTimeNow()
end
Choir.Clock = function(): number
	return os.clock()
end
Choir.Roll = function(): number
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

local function rootPos(player: Player): Vector3?
	local root = core and core.Root(player)
	return root and root.Position or nil
end

local function members(run: any): string
	local ids = {}
	for _, pl in ipairs(run.Players) do
		table.insert(ids, tostring(pl.UserId))
	end
	return "," .. table.concat(ids, ",") .. ","
end

-- may every member of the run enter `district`? (by seals cleared: a running "*" trial opens every district in
-- Underyard.Unlocked, so the seal count is read directly)
local function allowedFor(run: any): (string) -> boolean
	local c2 = C2()
	return function(district: string): boolean
		for _, pl in ipairs(run.Players) do
			local cleared = c2 and c2.ClearedCount(pl) or 0
			if not Rules.DistrictUnlocked(cleared, district, Layout.Unlock) then
				return false
			end
		end
		return true
	end
end
Choir.AllowedFor = allowedFor

local function routePoints(route: any): { Vector3 }
	local pts = {}
	for _, i in ipairs(route.Points) do
		local p = Layout.ChoirPaths[i]
		if p then
			table.insert(pts, p + Vector3.new(0, CC.Hover, 0))
		end
	end
	return pts
end

local function spiritCFrame(pos: Vector3, ahead: Vector3?): CFrame
	if ahead and (ahead - pos).Magnitude > .1 then
		local look = Vector3.new(ahead.X, pos.Y, ahead.Z)
		if (look - pos).Magnitude > .1 then
			return CFrame.lookAt(pos, look)
		end
	end
	return CFrame.new(pos)
end

local function spiritOf(target: any): (any, any)
	local d = target and target.Data
	local run = d and runsById[d.RunId]
	if not run then
		return nil, nil
	end
	return run, run.Data.Spirits[d.Spirit]
end
Choir.SpiritOf = spiritOf

---------------------------------------------------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------------------------------------------------
local function onStart(run: any)
	runsById[run.Id] = run
	local strike = StrikeM()
	local routes = SR.Routes(allowedFor(run), CC)
	local n = math.min(Base.Choir.Spirits or ACT.Spirits or 7, #routes)
	local spirits, public = {}, {}
	local who = members(run)
	for i = 1, n do
		local pts = routePoints(routes[i])
		local total = SR.LoopLength(pts)
		local s = Choir.Roll() * total
		local pos = SR.LoopAt(pts, s)
		local sp = { Index = i, Points = pts, Total = total, S = s, Dir = 1, LingerUntil = 0, Caught = false, Flee = 0, Speed = ACT.Speed or 7 }
		-- the next vertex the spirit lingers at
		local _, seg = SR.LoopAt(pts, s)
		sp.NextVertex = seg % #pts + 1
		if strike then
			sp.Target = strike.Add({
				Kind = "UyChoir", CFrame = spiritCFrame(pos), Radius = CC.Radius, HP = 1, MaxHP = 1, Unit = 1,
				Color = Color3.fromRGB(150, 200, 255), Material = "Glass", Data = { RunId = run.Id, Spirit = i },
				Name = "CHOIR SPIRIT", NameRU = "ДУХ ХОРА", Panel = false,
				Attributes = { UyRunId = run.Id, UyChoirNote = i, UyMembers = who },
			})
		end
		spirits[i] = sp
		public[i] = { Id = sp.Target and sp.Target.Id or 0, Note = i, Caught = false }
	end
	run.Data.Spirits = spirits
	run.Data.Moth = {}
	run.Data.MothAt = 0
	run.Public = { Spirits = public, SingEvery = CC.SingEvery, Caught = 0, Count = n }
end

local function advance(sp: any, dt: number, clock: number)
	if sp.Caught or #sp.Points < 2 or sp.Total <= 0 then
		return
	end
	if sp.Flee > 0 then
		local step = math.min(sp.Flee, CC.FleeSpeed * dt)
		sp.Flee -= step
		sp.S = (sp.S + sp.FleeDir * step) % sp.Total
		if sp.Flee <= 0 then
			sp.Flee = 0
			sp.LingerUntil = clock + .6
			local _, seg = SR.LoopAt(sp.Points, sp.S)
			sp.NextVertex = seg % #sp.Points + 1
		end
		return
	end
	if clock < sp.LingerUntil then
		return
	end
	local target = SR.VertexS(sp.Points, sp.NextVertex)
	if sp.NextVertex == 1 then
		target = sp.Total
	end
	local before = sp.S
	local moved = before + sp.Speed * dt
	if moved >= target then
		sp.S = target % sp.Total
		sp.NextVertex = sp.NextVertex % #sp.Points + 1
		sp.LingerUntil = clock + CC.Linger[1] + Choir.Roll() * (CC.Linger[2] - CC.Linger[1])
	else
		sp.S = moved
	end
end
Choir.Advance = advance

local function onTick(run: any, dt: number)
	local clock = Choir.Clock()
	local strike = StrikeM()
	for _, sp in ipairs(run.Data.Spirits) do
		if not sp.Caught then
			advance(sp, dt, clock)
			local pos = SR.LoopAt(sp.Points, sp.S)
			local ahead = SR.LoopAt(sp.Points, (sp.S + (sp.Flee > 0 and sp.FleeDir or 1) * 2) % math.max(1, sp.Total))
			if strike and sp.Target and sp.Target.Alive then
				strike.Move(sp.Target, spiritCFrame(pos, ahead))
			end
		end
	end
	-- H13 MOTH SWARM: the nearest spirit, to that member only
	if clock - run.Data.MothAt >= CC.MothEvery then
		run.Data.MothAt = clock
		local c2, seals = C2(), SealsM()
		if c2 and seals and Base.Choir.MothShowsNearest ~= false then
			local list = {}
			for _, sp in ipairs(run.Data.Spirits) do
				if not sp.Caught and sp.Target then
					table.insert(list, { Id = sp.Target.Id, Note = sp.Index, Position = sp.Target.Position })
				end
			end
			for _, pl in ipairs(run.Players) do
				if c2.HasTeamDog(pl, "HW_MothHound") then
					local pos = rootPos(pl)
					local best = pos and SR.Nearest(pos, list)
					local last = run.Data.Moth[pl.UserId]
					if best and (not last or last.Id ~= best.Id or clock - last.At >= CC.MothRefresh) then
						run.Data.Moth[pl.UserId] = { Id = best.Id, At = clock }
						seals.Signal(run, "ChoirMoth", { TargetId = best.Id, Note = best.Note }, pl)
					end
				end
			end
		end
	end
end

local function onEnd(run: any, result: string)
	runsById[run.Id] = nil
	local strike = StrikeM()
	for _, sp in ipairs(run.Data.Spirits or {}) do
		if sp.Target and sp.Target.Alive and strike then
			strike.Remove(sp.Target, result == "Won" and "Sang" or "Fled")
		end
	end
end

-- a Good hit: the spirit flees FleeDistance along its loop, the way that ends farther from the hitter
local function flee(run: any, sp: any, player: Player)
	local p = rootPos(player) or (sp.Target and sp.Target.Position) or Vector3.zero
	local dist = Base.Choir.FleeDistance or ACT.FleeDistance or 25
	local from = SR.LoopAt(sp.Points, sp.S)
	local newS, to = SR.Flee(sp.Points, sp.S, p, dist)
	local fwd = (sp.S + dist) % math.max(1, sp.Total)
	sp.FleeDir = math.abs(newS - fwd) < 1e-6 and 1 or -1
	sp.Flee = dist
	local seals = SealsM()
	if seals then
		seals.Signal(run, "ChoirFlee", { TargetId = sp.Target and sp.Target.Id or 0, From = from, To = to, UserId = player.UserId, Note = sp.Index })
	end
end
Choir.Flee = flee

---------------------------------------------------------------------------------------------------------------------
-- Strike kind
---------------------------------------------------------------------------------------------------------------------
local function registerKind()
	local strike = StrikeM()
	if not strike or not strike.Register then
		return
	end
	strike.Register("UyChoir", {
		Range = CC.Range, Verb = "STRIKE", Perfect = false, Activity = "Hit",
		Damage = function()
			return 0
		end,
		CanHit = function(player: Player, target: any)
			local run, sp = spiritOf(target)
			local seals = SealsM()
			if not run or run.State ~= "Running" or not seals or seals.RunOf(player) ~= run then
				return false, "HW:NOT_YOURS"
			end
			if not sp or sp.Caught then
				return false, "HW:GONE"
			end
			return true
		end,
		-- one timing circle, whatever the pickaxe (the session is trimmed to its first slot)
		OnBegin = function(player: Player)
			local s = strike.Sessions and strike.Sessions[player]
			if s and type(s.Targets) == "table" then
				for slot in pairs(s.Targets) do
					if slot ~= 1 then
						s.Targets[slot] = nil
					end
				end
			end
			return { Circles = 1, PerfectOnly = true }
		end,
		OnHit = function(player: Player, target: any, hit: any)
			local run, sp = spiritOf(target)
			local c2, seals = C2(), SealsM()
			local perfect = hit.Quality == 2
			if c2 then
				c2.StreakHit(player, perfect)
			end
			if run and seals then
				seals.Hit(run, player, perfect)
			end
			if SR.Judge(hit.Quality) == "Catch" then
				hit.Applied = target.HP
				return { Caught = true, Note = sp and sp.Index or 0 }
			end
			hit.Applied = 0
			if run and sp and sp.Flee <= 0 then
				flee(run, sp, player)
			end
			return { Miss = true, Flee = true, Note = sp and sp.Index or 0 }
		end,
		OnBreak = function(killer: Player?, target: any)
			local run, sp = spiritOf(target)
			local seals, c2 = SealsM(), C2()
			if not run or not sp or sp.Caught or run.State ~= "Running" then
				return
			end
			sp.Caught = true
			run.Public.Spirits[sp.Index].Caught = true
			run.Public.Caught = (run.Public.Caught or 0) + 1
			if killer and c2 then
				c2.Progress(killer, "Spirit", 1)
				c2.QueueShards(killer, ACT.ObjectiveShards or 4, "Spirit")
			end
			if seals then
				seals.Signal(run, "ChoirCaught", { TargetId = target.Id, Note = sp.Index, UserId = killer and killer.UserId or 0,
					Caught = run.Public.Caught })
				seals.AddScore(run, killer, 1)
			end
		end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
function Choir.Start(c: any, m: any)
	core, modules = c, m
	if not Shared.Chapter2Enabled() then
		return
	end
	registerKind()
	local seals = SealsM()
	if not seals then
		warn("SealChoir: Seals framework missing")
		return
	end
	-- (a member who leaves is handled by the Seals framework: Leave -> OnEnd when the last member goes)
	seals.Register(SEAL, {
		WinAtGoal = true, OnStart = onStart, OnTick = onTick, OnEnd = onEnd,
	})
end

return Choir
