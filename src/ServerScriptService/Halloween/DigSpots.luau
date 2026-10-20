-- HAUNTED DIG SPOTS (ServerScriptService.Halloween.DigSpots): while the Blood Moon is ACTIVE, haunted spots rise at
-- Layout.DigPoints and are dug with the pickaxe timing circles (Strike kind "DigSpot", verb DIG). Five types
-- (Config.DigSpots.Types): CURSED SOIL, GHOST SOIL, PUMPKIN PATCH, BONE GRAVE, CURSED TREASURE (rare, max one at a time,
-- server-wide announcement). Count: Config.DigSpots.Active + PerPlayer per extra player in the zone (cap MaxActive);
-- a dug spot is replaced after Respawn seconds, an undug one sinks after Lifetime seconds, every spot sinks when the
-- moon ends. Spot HP = BaseHP * type.HP * (1 + .12 * diggers) in tier-normalized "Power" units (Strike).
-- Every digger (dealt damage, within 24 studs) gets the type's rewards in one Core.Transact: candy, bones, a rare find
-- (event-mutated item + loot beam) with type.RareChance, quest DigSpots, stat Spots (+ Treasures), souls DigSpot,
-- curse relief DigSpot. Event dog abilities (the player's yard team: dogs with AssignedSlot ~= ""):
--   H01 Pumpkin Pup     +20% candy from PUMPKIN PATCH
--   H02 Sheet Shiba     GHOST LOOT: at GHOST SOIL a GhostLootChance HAUNTED find when the normal rare roll missed
--   H03 Bone Corgi      +35% bones from every spot
--   H05 Bat Dachshund   spots start damaged: the first time the player starts digging a spot it loses SpotHead (25%)
--   H07 Headless Hound  CURSED TREASURE spawns with CursedTreasureMult (x2) weight while such a player is in the zone
--   any event dog       GHOST SOIL never phases (normal teams: MissChance per hit deals no damage, "MISS" on the
--                       companion dog) and pays +EventDogBonus (+50%) candy
-- The companion: the player's best assigned dog (highest rank) is sent to the client on Begin; SpotFX shows a spectral
-- copy digging beside the spot.
-- Signals: SpotReward {TargetId, Kind="DigSpot", Variant, Candy, Bones, Item?, Rare, GhostLoot, Treasure, Full, Position},
--          CandyFx, Find (Strike.Reveal), SpotAnnounce {Kind="TreasureSpawn"|"TreasureDug", Position, UserId, Name} (all).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config
local Layout = Shared.Layout
local Spots = require(Halloween:WaitForChild("Models"):WaitForChild("Spots"))
local StrikeLib = require(script.Parent:WaitForChild("Strike"))

local DS = { Spots = {}, Cooldowns = {}, Active = false, Started = false, PlayerReady = {} }
DS.RewardRange = 24
DS.HitPower = Config.DigSpots.HitPower or 3.6 -- spot HP per unit of hit power (a plain Wooden hit = 1 power)
DS.DiggerScale = .12
DS.LingerAfterHit = 8 -- an undug spot that is being dug does not sink for this long after the last hit

local core, Strike = nil, nil
local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

local dogDefs = nil
local function defs()
	if dogDefs == nil then
		local ok, res = pcall(function()
			return require(RS:WaitForChild("DogEconomy"):WaitForChild("DogDefinitions"))
		end)
		dogDefs = ok and res or {}
	end
	return dogDefs
end

local function typeRow(id: string)
	for _, t in ipairs(Config.DigSpots.Types) do
		if t.Id == id then
			return t
		end
	end
	return nil
end
DS.Type = typeRow

---------------------------------------------------------------------------------------------------------------------
-- pure helpers (tests)
---------------------------------------------------------------------------------------------------------------------
function DS.TargetCount(zonePlayers: number): number
	local c = Config.DigSpots
	return math.min(c.MaxActive, c.Active + c.PerPlayer * math.max(0, (zonePlayers or 0) - 1))
end

function DS.SpotHP(row: any, diggers: number): number
	return Config.DigSpots.BaseHP * (row.HP or 1) * (1 + DS.DiggerScale * math.max(1, diggers or 1))
end

-- team = {Event = {[dogId]=true}, HasEvent, Best = {Id, Asset, Variant, Rank}} from a profile-like table {Dogs = {...}}
function DS.Team(view: any): { [string]: any }
	local out = { Event = {}, HasEvent = false, Best = nil }
	local all = defs()
	local bestScore = -1
	for _, d in pairs(type(view) == "table" and type(view.Dogs) == "table" and view.Dogs or {}) do
		if type(d) == "table" and type(d.DogId) == "string" and type(d.AssignedSlot) == "string" and d.AssignedSlot ~= "" then
			if Shared.IsEventDog(d.DogId) then
				out.Event[d.DogId] = true
				out.HasEvent = true
			end
			local def = all[d.DogId]
			local rank = def and def.Rank or (Shared.EventDog(d.DogId) and Shared.EventDog(d.DogId).Rank) or 1
			local score = rank * 1000 + math.min(999, tonumber(d.Mastery) or 0)
			if score > bestScore then
				bestScore = score
				out.Best = { Id = d.DogId, Asset = def and def.VisualAsset or d.DogId, Variant = d.Variant, Rank = rank }
			end
		end
	end
	return out
end

-- spawn weights for the current zone (H07 doubles the treasure, Max caps alive types)
function DS.Weights(alive: { [string]: number }, headless: boolean): { any }
	local rows = {}
	local mult = (Shared.EventDog("HW_HeadlessHound") or {}).CursedTreasureMult or 2
	for _, t in ipairs(Config.DigSpots.Types) do
		if not (t.Max and (alive[t.Id] or 0) >= t.Max) then
			local w = t.Weight or 0
			if t.Id == "CursedTreasure" and headless then
				w *= mult
			end
			table.insert(rows, { Id = t.Id, Weight = w, Row = t })
		end
	end
	return rows
end

-- what one digger gets for a dug spot. rolls = 6 numbers in [0,1); team from DS.Team; boost = exorcism mutation boost
function DS.RewardPlan(row: any, team: any, rolls: { number }, boost: number?): { [string]: any }
	local ev = team and team.Event or {}
	local dogsCfg = Config.Dogs.Defs
	local plan = { Candy = StrikeLib.RandRange(row.Candy, rolls[1]), Bones = StrikeLib.RandRange(row.Bones, rolls[2]) }
	if row.Id == "PumpkinPatch" and ev.HW_PumpkinPup then
		plan.Candy *= 1 + (dogsCfg.HW_PumpkinPup.PumpkinCandy or 0)
	end
	if row.Id == "GhostSoil" and team and team.HasEvent then
		plan.Candy *= 1 + (row.EventDogBonus or 0)
	end
	if ev.HW_BoneCorgi then
		plan.Bones = math.floor(plan.Bones * (1 + (dogsCfg.HW_BoneCorgi.Bones or 0)) + .5)
	end
	local chance = math.min(1, (row.RareChance or 0) * (boost or 1))
	plan.RareChance = chance
	if rolls[3] < chance then
		local mut, share = StrikeLib.RareMutation(rolls[4], true)
		plan.Rare = true
		plan.Mutation = mut.Id
		plan.MutationChance = chance * share
		plan.RareCandy = StrikeLib.RandRange(Config.Candy.RareFind, rolls[5])
	elseif row.Id == "GhostSoil" and ev.HW_SheetShiba and rolls[6] < (dogsCfg.HW_SheetShiba.GhostLootChance or 0) then
		plan.Rare = true
		plan.GhostLoot = true
		plan.Mutation = "HAUNTED"
		plan.MutationChance = (1 - chance) * (dogsCfg.HW_SheetShiba.GhostLootChance or 0)
		plan.RareCandy = StrikeLib.RandRange(Config.Candy.RareFind, rolls[5])
	end
	plan.Treasure = row.Rare == true
	return plan
end

-- ghost soil phasing for one hit
function DS.Phases(row: any, team: any, r: number): boolean
	return row ~= nil and (row.MissChance or 0) > 0 and not (team and team.HasEvent) and r < row.MissChance
end

---------------------------------------------------------------------------------------------------------------------
-- runtime
---------------------------------------------------------------------------------------------------------------------
local function viewTeam(player: Player)
	local Runtime = core and core.Runtime
	local view = Runtime and Runtime.Views and Runtime.Views[player.UserId]
	return DS.Team(view)
end

local function zoneHeadless(): boolean
	for _, pl in ipairs(core.ZonePlayers()) do
		if viewTeam(pl).Event.HW_HeadlessHound then
			return true
		end
	end
	return false
end

local function aliveCounts(): ({ [string]: number }, number)
	local counts, n = {}, 0
	for _, t in pairs(DS.Spots) do
		if t.Alive then
			counts[t.Variant] = (counts[t.Variant] or 0) + 1
			n += 1
		end
	end
	return counts, n
end

local function freePoint(): number?
	local free = {}
	for i = 1, #Layout.DigPoints do
		if DS.Spots[i] == nil then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[rng:NextInteger(1, #free)]
end

function DS.Spawn(typeId: string?, index: number?)
	if not Strike then
		return nil
	end
	index = index or freePoint()
	if not index or DS.Spots[index] then
		return nil
	end
	local row
	if typeId then
		row = typeRow(typeId)
	else
		local counts = aliveCounts()
		local pick = Shared.Weighted(DS.Weights(counts, zoneHeadless()), roll)
		row = pick and pick.Row
	end
	if not row then
		return nil
	end
	local info = Spots.Info[row.Id] or Spots.Info.CursedSoil
	local ground = Layout.DigPoints[index]
	local h = info.Height + 1
	local facing = rng:NextNumber(-.6, .6)
	local center = CFrame.new(ground + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, facing, 0)
	local points = {}
	for _, p in ipairs(Spots.HitPoints(row.Id)) do
		table.insert(points, { Pos = p.Pos - Vector3.new(0, h / 2, 0), Normal = p.Normal })
	end
	local hp = DS.SpotHP(row, 1)
	local target = Strike.Add({
		Kind = "DigSpot", CFrame = center, Radius = info.Radius, Size = Vector3.new(info.Radius * 2, h, info.Radius * 2), HP = hp, MaxHP = hp,
		Unit = DS.HitPower, Color = Shared.Color(row.Color), Material = "Ground", Variant = row.Id, Seed = rng:NextInteger(1, 1e6),
		Name = row.Name, NameRU = info.RU, Ground = ground, Facing = facing, HitPoints = points,
		Attributes = { Rare = row.Rare == true, Lifetime = Config.DigSpots.Lifetime },
		Data = { Index = index, Ground = ground, Row = row, Diggers = {}, Teams = {}, Headed = false },
	})
	DS.Spots[index] = target
	if row.Rare then
		core.Signal("all", "SpotAnnounce", { Kind = "TreasureSpawn", Position = ground, Name = row.Name })
	end
	return target
end

local function sink(target, reason: string?)
	local index = target.Data.Index
	if DS.Spots[index] == target then
		DS.Spots[index] = nil
	end
	Strike.Remove(target, reason or "Sink")
end

function DS.SinkAll(reason: string?)
	local i = 0
	for _, t in pairs(DS.Spots) do
		i += 1
		task.delay(i * .12, function()
			if t.Alive then
				sink(t, reason or "Sink")
			end
		end)
	end
end

local function reward(player: Player, target)
	local row = target.Data.Row
	local pos = target.Data.Ground or target.Position
	local rolls = { roll(), roll(), roll(), roll(), roll(), roll() }
	local boost = core.MutationBoost()
	local ok, res = core.Transact(player, "DigSpot", function(p, _h, ctx)
		local plan = DS.RewardPlan(row, DS.Team(p), rolls, boost)
		local candy = ctx.Candy(plan.Candy, "DigSpot")
		local bones = plan.Bones > 0 and ctx.Bones(plan.Bones) or 0
		local item = nil
		if plan.Rare then
			item = ctx.Item({ Mutation = plan.Mutation, MutationChance = plan.MutationChance, Origin = "Halloween" })
			candy += ctx.Candy(plan.RareCandy or 0, "RareFind")
			ctx.Relief("RareFind")
		end
		ctx.Relief("DigSpot")
		ctx.Quest("DigSpots", 1)
		ctx.Stat("Spots", 1)
		if plan.Treasure then
			ctx.Stat("Treasures", 1)
		end
		ctx.Souls(Config.Exorcism.Souls.DigSpot or 0)
		return { Candy = candy, Bones = bones, Item = item, Rare = plan.Rare == true, GhostLoot = plan.GhostLoot == true,
			Treasure = plan.Treasure, Full = plan.Rare == true and item == nil }
	end)
	if not ok then
		if type(res) == "string" and not string.find(res, "ended") then
			core.Toast(player, res, "error")
		end
		return
	end
	DS.PlayerReady[player] = os.clock() + (Config.DigSpots.PlayerCooldown or 0)
	core.Signal(player, "SpotReward", { TargetId = target.Id, Kind = "DigSpot", Variant = row.Id, Candy = res.Candy, Bones = res.Bones,
		Item = StrikeLib.ItemSummary(res.Item), Rare = res.Rare, GhostLoot = res.GhostLoot, Treasure = res.Treasure, Full = res.Full, Position = pos })
	if res.Candy and res.Candy > 0 then
		core.Signal(player, "CandyFx", { Amount = res.Candy, From = pos + Vector3.new(0, 2.5, 0), Source = "DigSpot", Big = res.Rare or res.Treasure, Played = true })
	end
	if res.Item then
		Strike.Reveal(player, res.Item, pos)
	end
end

local function onBegin(player: Player, target)
	local d = target.Data
	local team = viewTeam(player)
	d.Teams[player.UserId] = team
	local extra = { Companion = team.Best, Event = team.HasEvent }
	if not d.Diggers[player.UserId] then
		d.Diggers[player.UserId] = true
		local n = 0
		for _ in pairs(d.Diggers) do
			n += 1
		end
		-- more diggers -> more HP (the missing HP grows with the max)
		local newMax = DS.SpotHP(d.Row, n)
		Strike.SetHP(target, target.HP + (newMax - target.MaxHP), newMax)
		-- H05 Bat Dachshund: the spot starts damaged (once per spot)
		local bat = Shared.EventDog("HW_BatDachshund")
		if team.Event.HW_BatDachshund and not d.Headed and bat then
			d.Headed = true
			Strike.SetHP(target, math.max(1, target.HP - target.MaxHP * (bat.SpotHead or 0)))
			target.Part:SetAttribute("Damaged", true)
			extra.HeadStart = true
		end
	end
	return extra
end

local function onHit(player: Player, target, hit)
	local row = target.Data.Row
	local team = target.Data.Teams[player.UserId]
	if DS.Phases(row, team, roll()) then
		hit.Applied = 0
		return { Miss = true }
	end
	return nil
end

local function onBreak(_killer: Player?, target, info)
	local index = target.Data.Index
	if DS.Spots[index] == target then
		DS.Spots[index] = nil
	end
	local respawn = Config.DigSpots.Respawn
	table.insert(DS.Cooldowns, os.clock() + respawn[1] + rng:NextNumber() * (respawn[2] - respawn[1]))
	local pos = target.Data.Ground or target.Position
	local first = nil
	for _, c in pairs(info.Contributors) do
		local pl = c.Player
		if pl and pl.Parent and c.Damage > 0 and core.Near(pl, pos, DS.RewardRange) then
			first = first or pl
			task.spawn(reward, pl, target)
		end
	end
	if target.Data.Row.Rare and first then
		core.Signal("all", "SpotAnnounce", { Kind = "TreasureDug", Position = pos, UserId = first.UserId, Name = first.DisplayName })
	end
end

local function canHit(player: Player, target)
	if not Shared.Enabled() then
		return false, "HW:OFF"
	end
	local s = Strike.Sessions[player]
	if not (s and s.Target == target) and (DS.PlayerReady[player] or 0) > os.clock() then
		return false, "HW:WAIT"
	end
	return true
end

local function tick()
	local now = os.clock()
	for i = #DS.Cooldowns, 1, -1 do
		if DS.Cooldowns[i] <= now then
			table.remove(DS.Cooldowns, i)
		end
	end
	-- slots of targets removed elsewhere (event switched off, debug) are free again
	for i, t in pairs(DS.Spots) do
		if t.Removed then
			DS.Spots[i] = nil
		end
	end
	-- undug spots sink after their lifetime (not while someone is digging)
	for _, t in pairs(DS.Spots) do
		if t.Alive and now - t.BornAt > Config.DigSpots.Lifetime and now - (t.LastHitAt or 0) > DS.LingerAfterHit then
			sink(t, "Sink")
		end
	end
	if not DS.Active or not Shared.Enabled() then
		return
	end
	local _, alive = aliveCounts()
	local want = DS.TargetCount(#core.ZonePlayers()) - #DS.Cooldowns
	local spawned = 0
	while alive < want and spawned < 2 do
		if not DS.Spawn() then
			break
		end
		alive += 1
		spawned += 1
	end
end
DS.Tick = tick

local function onMoon(state: string)
	local active = state == "ACTIVE" and Shared.Enabled()
	if active == DS.Active then
		return
	end
	DS.Active = active
	if not active then
		table.clear(DS.Cooldowns)
		DS.SinkAll("Sink")
	end
end
DS.OnMoon = onMoon

function DS.Start(c, modules)
	if DS.Started then
		return
	end
	core = c
	Strike = modules and modules.Strike
	if not Strike then
		warn("Halloween DigSpots: Strike module missing; dig spots disabled")
		return
	end
	DS.Started = true
	Strike.Register("DigSpot", {
		Range = Config.DigSpots.Range, Verb = "DIG", Damage = "Power", Activity = "Hit",
		CanHit = canHit, OnBegin = onBegin, OnHit = onHit, OnBreak = onBreak,
	})
	local BloodMoon = modules.BloodMoon
	if BloodMoon and BloodMoon.OnChange then
		BloodMoon.OnChange(function(state)
			onMoon(state)
		end)
	else
		local folder = Halloween:WaitForChild("State"):WaitForChild("BloodMoon")
		folder:GetAttributeChangedSignal("State"):Connect(function()
			onMoon(folder:GetAttribute("State"))
		end)
		onMoon(folder:GetAttribute("State"))
	end
	Players.PlayerRemoving:Connect(function(player)
		DS.PlayerReady[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(.5)
			local ok, err = pcall(tick)
			if not ok then
				warn("Halloween DigSpots tick failed: " .. tostring(err))
			end
		end
	end)
	-- debug (Studio panel): Spot {Id} spawns a spot at the free dig point nearest to the player, even without a moon
	pcall(function()
		local dbg = require(script.Parent:WaitForChild("Debug"))
		dbg.Commands.Spot = function(player, a)
			local root = core.Root(player)
			local best, bestD = nil, math.huge
			for i, p in ipairs(Layout.DigPoints) do
				local d = root and (root.Position - p).Magnitude or i
				if DS.Spots[i] == nil and d < bestD then
					best, bestD = i, d
				end
			end
			local id = type(a.Id) == "string" and typeRow(a.Id) and a.Id or nil
			local t = best and DS.Spawn(id, best)
			return t ~= nil, t and { Message = "Spawned " .. t.Variant } or "No free dig point"
		end
	end)
end

return DS
