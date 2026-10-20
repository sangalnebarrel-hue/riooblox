-- BELL SEAL IV · HOLLOW MINE (ServerScriptService.Halloween.SealMine, WP-I; docs/halloween2/DESIGN.md §8.4.4, §10.2).
-- An Undercrypt combat trial run by the Seals framework (start: MineEntrance; EventHP zone "Trial:HollowMine", one run
-- on the server at a time). Activity.TimeLimit (4 min) from GO on the sunken mine floor: hollow ore nodes (Strike kind
-- "UyHollowOre", tier-normalised "Power" HP = NodeHits plain Wooden hits, + PartyHP per extra member, WEAKENED hits
-- deal less) stand at MineNode_1..12 and grow back Activity.Respawn s after they break. Hazards hit Event HP:
--   falling rocks   Circle r Rocks.Radius aimed near players on the floor, telegraph 1.4 s, 18 (one per RockPerPlayers)
--   gas vents       Circle r Gas.Radius near a player, lingering Gas.Linger s at Gas.DPS (Kind "Gas": H10 -30%)
--   collapses       a Line of Tunnel.Length x Tunnel.Width across the floor through a player, telegraph 1.6 s, 22
-- Downed miners can be revived (EventHP); a bleed-out puts that miner out of the run (Seals), a wipe fails it.
-- Clear: Goal (14) cores; Gold: 20 cores without being downed (Seals.DefaultGold: Total + NoDowns). Reaching the Gold
-- total ends the run at once (Activity.GoldEndsRun).
-- Every core: Seals.AddScore for the miner who broke it; every member who dealt damage to it gets Chapter2.Progress
-- "Ore" (contracts / stats / resonance) and Chapter2.QueueShards(Activity.ObjectiveShards, "Ore"). Every judged hit:
-- Seals.Hit + Chapter2.StreakHit.
-- Ore target part attributes: UyRun, UyTrial, UyMembers, Index (+ Strike's HP / MaxHP). Public run data: {GoAt, Goal, Gold =
-- {Total, NoDowns}, Cores, Nodes}. Extra C2Trial kind: Core {Index, UserId, Position}.
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Rules = require(Halloween:WaitForChild("SealRules"))

local SEAL = 4
local Mine = {}
Mine.Seal = SEAL
Mine.Act = Rules.Activity(SEAL)
Mine.Kind = Mine.Act.Kind or "UyHollowOre"
Mine.TrialId = Cfg.Seals[SEAL].Trial.Id
Mine.Zone = "Trial:" .. Mine.TrialId
-- overridable (tests: manual clock and rolls)
Mine.Now = function(): number
	return workspace:GetServerTimeNow()
end
local rng = Random.new()
Mine.Roll = function(): number
	return rng:NextNumber()
end

local core: any = nil
local modules: any = nil

local function C2(): any
	return modules and modules.Chapter2
end
local function SealsMod(): any
	return modules and modules.Seals
end
local function StrikeMod(): any
	return modules and modules.Strike
end

local function anchor(name: string): Vector3?
	local c2 = C2()
	return (c2 and c2.AnchorPos and c2.AnchorPos(name)) or Layout.Anchor(name)
end

function Mine.Nodes(): { Vector3 }
	local out = {}
	for i = 1, math.floor(tonumber(Mine.Act.Nodes) or #Layout.MineNodes) do
		local p = anchor("MineNode_" .. i)
		if not p then
			break
		end
		out[i] = p
	end
	return out
end

local function rootPos(player: Player): Vector3?
	local root = core and core.Root(player)
	return root and root.Position or nil
end

local function downed(player: Player): boolean
	return player:GetAttribute("HwDowned") == true
end

---------------------------------------------------------------------------------------------------------------------
-- Ore nodes
---------------------------------------------------------------------------------------------------------------------
local function spawnNode(run: any, i: number, _now: number): any?
	local st = run.Data.Mine
	local S = StrikeMod()
	local ground = st.Points[i]
	if not S or not ground then
		return nil
	end
	local a = Mine.Act
	local hp, unit = Rules.NodeHP(a, st.Party)
	local facing = Mine.Roll() * math.pi * 2
	local size = a.HitSize or { 6.4, 5, 6.4 }
	local t = S.Add({
		Kind = Mine.Kind, CFrame = CFrame.new(ground + Vector3.new(0, a.Lift, 0)) * CFrame.Angles(0, facing, 0), Radius = 3.2,
		Size = Vector3.new(size[1], size[2], size[3]), HP = hp, MaxHP = hp, Unit = unit, Color = Color3.fromRGB(176, 110, 255),
		Material = "Slate", Variant = "HollowOre", Seed = math.floor(Mine.Roll() * 1e6), Name = a.LabelEn, NameRU = a.LabelRu, Ground = ground,
		Facing = facing, Panel = false, Shared = st.Party > 1, Owner = run.Leader, Data = { Run = run, Index = i },
		Attributes = { UyRun = run.Id, UyTrial = run.TrialId, UyMembers = Rules.Members(run.Players), Index = i },
	})
	st.Nodes[i] = t
	st.Due[i] = nil
	return t
end

local function member(run: any, player: Player): boolean
	return table.find(run.Players, player) ~= nil
end

function Mine.CanHit(player: Player, target: any): (boolean, string?)
	local run = target.Data.Run
	if not run or run.State ~= "Running" then
		return false, "HW:GONE"
	end
	if not member(run, player) then
		return false, "HW:NOT_YOURS"
	end
	if Mine.Now() < run.Data.Mine.GoAt then
		return false, "HW:WAIT"
	end
	return true, nil
end

function Mine.OnHit(player: Player, target: any, hit: any): any
	local run = target.Data.Run
	if not run or run.State ~= "Running" then
		hit.Applied = 0
		return nil
	end
	local perfect = hit.Quality == 2
	SealsMod().Hit(run, player, perfect)
	local c2 = C2()
	if c2 then
		c2.StreakHit(player, perfect)
	end
	return { Ore = true, Perfect = perfect }
end

-- a core broke: the miner scores, every member who worked on it gets the ore progress and the shards
function Mine.OnBreak(killer: Player?, target: any, info: any)
	local run = target.Data.Run
	if not run or run.State ~= "Running" then
		return
	end
	local st = run.Data.Mine
	local i = target.Data.Index
	if st.Nodes[i] == target then
		st.Nodes[i] = nil
	end
	local now = Mine.Now()
	st.Due[i] = now + Rules.Every(Mine.Act.Respawn, Mine.Roll())
	-- the credit goes to the killer when they are a member, else to the member who dealt the most
	local credit: Player? = (killer and member(run, killer)) and killer or nil
	local best = -1
	local c2 = C2()
	for _, c in pairs(info and info.Contributors or {}) do
		local pl = c.Player
		if pl and c.Damage > 0 and member(run, pl) then
			if c2 then
				c2.Progress(pl, "Ore", 1)
				c2.QueueShards(pl, Mine.Act.ObjectiveShards, "Ore")
			end
			if not credit and c.Damage > best then
				best = c.Damage
				credit = pl
			end
		end
	end
	local S = SealsMod()
	run.Public.Cores = run.Total + 1
	S.Signal(run, "Core", { Index = i, UserId = credit and credit.UserId or 0, Position = st.Points[i] })
	S.AddScore(run, credit, 1)
	local gold = Cfg.Seals[SEAL].Gold
	if Mine.Act.GoldEndsRun and run.State == "Running" and gold.Total and run.Total >= gold.Total then
		S.Win(run)
	end
end

function Mine.OnRemove(target: any, reason: string?)
	if reason == "Broke" then
		return -- OnBreak schedules the regrowth
	end
	local run = target.Data.Run
	local st = run and run.Data and run.Data.Mine
	if st and st.Nodes[target.Data.Index] == target then
		st.Nodes[target.Data.Index] = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Hazards
---------------------------------------------------------------------------------------------------------------------
-- members standing (not downed) on the mine floor, with their positions
local function floorPlayers(run: any): { any }
	local out = {}
	for _, pl in ipairs(run.Players) do
		local pos = rootPos(pl)
		if pos and not downed(pl) and Rules.OnFloor(pos, Layout, Mine.Act) then
			table.insert(out, { Player = pl, Pos = pos })
		end
	end
	return out
end

local function shuffled(list: { any }): { any }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = math.floor(Mine.Roll() * i) + 1
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function around(pos: Vector3, minR: number, maxR: number): Vector3
	local ang = Mine.Roll() * math.pi * 2
	local r = minR + (maxR - minR) * Mine.Roll()
	return Rules.ClampFloor(pos + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r), Layout, Mine.Act.FloorMargin)
end

-- the hazard defs of this tick (empty when nothing is due); advances the timers
function Mine.Hazards(run: any, now: number): { any }
	local st = run.Data.Mine
	local a = Mine.Act
	local defs = {}
	if now < st.GoAt + a.HazardDelay then
		return defs
	end
	local who = floorPlayers(run)
	if #who == 0 then
		-- nobody down there: the mine holds its breath (timers wait for the miners)
		st.NextRock = math.max(st.NextRock, now + 1)
		st.NextGas = math.max(st.NextGas, now + 1)
		st.NextTunnel = math.max(st.NextTunnel, now + 1)
		return defs
	end
	if now >= st.NextRock then
		st.NextRock = now + Rules.Every(a.Rocks.Every, Mine.Roll())
		local n = math.max(1, math.ceil(#who / math.max(1, a.RockPerPlayers)))
		for k, w in ipairs(shuffled(who)) do
			if k > n then
				break
			end
			table.insert(defs, Rules.RockDef(around(w.Pos, 0, a.RockSpread), a))
		end
	end
	if now >= st.NextGas then
		st.NextGas = now + Rules.Every(a.Gas.Every, Mine.Roll())
		local w = who[math.floor(Mine.Roll() * #who) + 1]
		local pos = around(w.Pos, 3, a.GasNear)
		for _ = 1, 6 do
			local clear = true
			for _, node in pairs(st.Nodes) do
				if node.Alive and Rules.Flat(node.Position - pos).Magnitude < a.GasClear then
					clear = false
					break
				end
			end
			if clear then
				break
			end
			pos = around(w.Pos, 3, a.GasNear)
		end
		table.insert(defs, Rules.GasDef(pos, a))
	end
	if now >= st.NextTunnel then
		st.NextTunnel = now + Rules.Every(a.Tunnel.Every, Mine.Roll())
		local w = who[math.floor(Mine.Roll() * #who) + 1]
		table.insert(defs, Rules.TunnelDef(around(w.Pos, 0, 4), Mine.Roll() * math.pi, a, Layout))
	end
	return defs
end

---------------------------------------------------------------------------------------------------------------------
-- The trial (Seals def)
---------------------------------------------------------------------------------------------------------------------
function Mine.OnStart(run: any)
	local a = Mine.Act
	local goAt = run.StartedAt + a.Countdown
	if run.EndsAt > 0 then
		run.EndsAt += a.Countdown
	end
	local st = { GoAt = goAt, Points = Mine.Nodes(), Nodes = {}, Due = {}, Party = math.max(1, #run.Players),
		NextRock = goAt + a.HazardDelay, NextGas = goAt + a.HazardDelay + Rules.Every(a.Gas.Every, .5) / 2,
		NextTunnel = goAt + Rules.Every(a.Tunnel.Every, Mine.Roll()) }
	run.Data.Mine = st
	for i = 1, #st.Points do
		st.Due[i] = goAt + (i - 1) * .08
	end
	local gold = Cfg.Seals[SEAL].Gold
	run.Public = { GoAt = goAt, Goal = run.Goal, Gold = { Total = gold.Total, NoDowns = gold.NoDowns == true }, Cores = 0, Nodes = #st.Points }
end

function Mine.OnTick(run: any, _dt: number)
	local st = run.Data.Mine
	if not st or run.State ~= "Running" then
		return
	end
	local now = Mine.Now()
	if now < st.GoAt then
		return
	end
	for i, due in pairs(st.Due) do
		if now >= due and not st.Nodes[i] then
			spawnNode(run, i, now)
		end
	end
	local defs = Mine.Hazards(run, now)
	local EventHP = modules and modules.EventHP
	if #defs > 0 and EventHP and type(EventHP.HazardWave) == "function" then
		local ok, err = pcall(EventHP.HazardWave, Mine.Zone, defs)
		if not ok then
			warn("SealMine: hazards failed: " .. tostring(err))
		end
	end
end

-- a member left (bled out, walked off): their prompts go
function Mine.OnLeave(run: any, _player: Player, _reason: string)
	local st = run.Data.Mine
	if not st then
		return
	end
	local members = Rules.Members(run.Players)
	for _, t in pairs(st.Nodes) do
		if t.Part and t.Part.Parent then
			t.Part:SetAttribute("UyMembers", members)
		end
	end
end

function Mine.OnEnd(run: any, result: string)
	local st = run.Data.Mine
	if not st then
		return
	end
	local S = StrikeMod()
	for i, t in pairs(st.Nodes) do
		st.Nodes[i] = nil
		if S and t.Alive then
			S.Remove(t, result == "Won" and "Won" or "End")
		end
	end
	table.clear(st.Due)
	local EventHP = modules and modules.EventHP
	if EventHP and type(EventHP.CancelHazards) == "function" then
		pcall(EventHP.CancelHazards, Mine.Zone)
	end
end

function Mine.Start(c: any, m: any)
	core, modules = c, m
	Mine.Act = Rules.Activity(SEAL)
	if not Shared.Chapter2Enabled() then
		return
	end
	local Seals, Strike = m and m.Seals, m and m.Strike
	if not Seals or not Strike then
		warn("SealMine: Seals or Strike missing; HOLLOW MINE disabled")
		return
	end
	local spawn = anchor(Mine.Act.Spawn or "MineSpawn") or Layout.Undercrypt.Spawn
	local EventHP = m.EventHP
	if EventHP and type(EventHP.SetZone) == "function" then
		pcall(EventHP.SetZone, Mine.Zone, { Spawn = spawn, Name = Cfg.Seals[SEAL].Title, Trial = Mine.TrialId })
	end
	Strike.Register(Mine.Kind, {
		Range = Mine.Act.Range, Verb = "MINE", Damage = "Power", EventMult = "Apply", Perfect = false, Activity = "Hit", Remove = true,
		CanHit = Mine.CanHit, OnHit = Mine.OnHit, OnBreak = Mine.OnBreak, OnRemove = Mine.OnRemove,
	})
	Seals.Register(SEAL, { Spawn = spawn, OnStart = Mine.OnStart, OnTick = Mine.OnTick, OnLeave = Mine.OnLeave, OnEnd = Mine.OnEnd })
end

return Mine
