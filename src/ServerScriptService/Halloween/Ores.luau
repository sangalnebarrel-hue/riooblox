-- HALLOWEEN ORE (ServerScriptService.Halloween.Ores): always-on mining nodes on THE DEAD YARD ore field
-- (Layout.OrePoints, Config.Ore). Strike kind "Ore" (verb MINE): the same pickaxe timing circles as the Mining Corner,
-- shared targets (every player hits the same node). Node HP is tier-normalized ("Power" damage): a node needs
-- Config.Ore.HitsTarget plain Wooden-Pickaxe hits, better pickaxes / Perfects / combos / crits / Strength go faster.
-- On break every contributor within 20 studs gets (one Core.Transact each): Loot candy (Config.Ore.Candy), quest MineOre,
-- stat Ore, souls OreBreak, curse relief Break; with Config.Ore.RareChance (x exorcism mutation boost) a RARE FIND: an item
-- rolled on the player's deepest layer with a forced event mutation (Config.Rewards.RareFindMutations; BLOOD MOON only
-- during an active Blood Moon) + Config.Candy.RareFind candy + the DiscoveryReveal loot beam. Nodes respawn after
-- Config.Ore.Respawn seconds with a new kind (Config.Ore.Kinds by weight).
-- Signals: SpotReward {TargetId, Kind="Ore", Variant, Candy, Item?, Rare, Position} (to the rewarded player),
--          CandyFx {Amount, From, Source="Ore", Big} (HUD candy fly), Find (zone, Strike.Reveal).
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config
local Layout = Shared.Layout
local Spots = require(Halloween:WaitForChild("Models"):WaitForChild("Spots"))
local StrikeLib = require(script.Parent:WaitForChild("Strike"))

local Ores = { Nodes = {}, Started = false }
Ores.RewardRange = 20
Ores.HitBox = Vector3.new(8.4, 6, 8.4)

local core, Strike = nil, nil
local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end
Ores.Roll = roll

-- pure: node HP / unit for one roll set (tests)
function Ores.NodeStats(rHP: number, rHits: number): (number, number, number)
	local cfg = Config.Ore
	local hp = cfg.HP[1] + math.floor(rHP * (cfg.HP[2] - cfg.HP[1] + 1 - 1e-9))
	local hits = cfg.HitsTarget[1] + math.floor(rHits * (cfg.HitsTarget[2] - cfg.HitsTarget[1] + 1 - 1e-9))
	return hp, hits, hp / hits
end

-- pure: what one contributor gets for a broken node (rolls in [0,1))
function Ores.RewardPlan(rolls: { number }, bloodMoon: boolean, boost: number?): { [string]: any }
	local cfg = Config.Ore
	local plan = { Candy = StrikeLib.RandRange(cfg.Candy or Config.Candy.Loot, rolls[1]) }
	local chance = math.min(1, (cfg.RareChance or 0) * (boost or 1))
	plan.RareChance = chance
	if rolls[2] < chance then
		local row, share = StrikeLib.RareMutation(rolls[3], bloodMoon)
		plan.Rare = true
		plan.Mutation = row.Id
		plan.MutationChance = chance * share
		plan.RareCandy = StrikeLib.RandRange(Config.Candy.RareFind, rolls[4])
	end
	return plan
end

local function pointCF(index: number): (Vector3, number)
	local ground = Layout.OrePoints[index]
	-- face the lane (front = -Z) with some variety
	local facing = math.rad(((index * 37) % 70) - 35)
	return ground, facing
end

local spawnNode

local function reward(player: Player, target)
	local pos = target.Data.Ground or target.Position
	local bm = core.BloodMoonActive()
	local plan = Ores.RewardPlan({ roll(), roll(), roll(), roll() }, bm, core.MutationBoost())
	local ok, res = core.Transact(player, "OreBreak", function(_p, _h, ctx)
		local candy = ctx.Candy(plan.Candy, "Ore")
		local item = nil
		if plan.Rare then
			item = ctx.Item({ Mutation = plan.Mutation, MutationChance = plan.MutationChance, Origin = "Halloween" })
			candy += ctx.Candy(plan.RareCandy, "RareFind")
			ctx.Relief("RareFind")
		else
			ctx.Relief("Break")
		end
		ctx.Quest("MineOre", 1)
		ctx.Stat("Ore", 1)
		ctx.Souls(Config.Exorcism.Souls.OreBreak or 0)
		return { Candy = candy, Item = item, Rare = plan.Rare == true, Full = plan.Rare == true and item == nil }
	end)
	if not ok then
		if type(res) == "string" and not string.find(res, "ended") then
			core.Toast(player, res, "error")
		end
		return
	end
	core.Signal(player, "SpotReward", { TargetId = target.Id, Kind = "Ore", Variant = target.Variant, Candy = res.Candy,
		Item = Strike.ItemSummary(res.Item), Rare = res.Rare, Full = res.Full, Position = pos })
	if res.Candy and res.Candy > 0 then
		core.Signal(player, "CandyFx", { Amount = res.Candy, From = pos + Vector3.new(0, 3, 0), Source = "Ore", Big = res.Rare, Played = true })
	end
	if res.Item then
		Strike.Reveal(player, res.Item, pos)
	end
end

local function onBreak(killer: Player?, target, info)
	local index = target.Data.Index
	local pos = target.Data.Ground or target.Position
	for _, c in pairs(info.Contributors) do
		local pl = c.Player
		if pl and pl.Parent and c.Damage > 0 and core.Near(pl, pos, Ores.RewardRange + target.Radius) then
			task.spawn(reward, pl, target)
		end
	end
	Ores.Nodes[index] = nil
	local cfg = Config.Ore
	local wait = cfg.Respawn[1] + rng:NextNumber() * (cfg.Respawn[2] - cfg.Respawn[1])
	task.delay(wait, function()
		if Ores.Nodes[index] == nil and Shared.Enabled() then
			spawnNode(index)
		end
	end)
end

spawnNode = function(index: number)
	if not Strike or not Layout.OrePoints[index] then
		return nil
	end
	local kind = Shared.Weighted(Config.Ore.Kinds, roll)
	local info = Spots.Info[kind.Id] or Spots.Info.PumpkinOre
	local hp, hits, unit = Ores.NodeStats(roll(), roll())
	local ground, facing = pointCF(index)
	local box = Ores.HitBox
	local center = CFrame.new(ground + Vector3.new(0, box.Y / 2, 0)) * CFrame.Angles(0, facing, 0)
	local points = {}
	for _, p in ipairs(Spots.HitPoints(kind.Id)) do
		table.insert(points, { Pos = p.Pos - Vector3.new(0, box.Y / 2, 0), Normal = p.Normal })
	end
	local target = Strike.Add({
		Kind = "Ore", CFrame = center, Radius = 4.2, Size = box, HP = hp, MaxHP = hp, Unit = unit,
		Color = Shared.Color(kind.Accent), Material = "Slate", Variant = kind.Id, Seed = rng:NextInteger(1, 1e6),
		Name = kind.Name or info.Name, NameRU = info.RU, Ground = ground, Facing = facing, HitPoints = points,
		Data = { Index = index, Ground = ground, Hits = hits },
	})
	Ores.Nodes[index] = target
	return target
end
Ores.Spawn = spawnNode

function Ores.Start(c, modules)
	if Ores.Started then
		return
	end
	core = c
	Strike = modules and modules.Strike
	if not Strike then
		warn("Halloween Ores: Strike module missing; ore disabled")
		return
	end
	Ores.Started = true
	Strike.Register("Ore", {
		Range = Config.Ore.Range, Verb = "MINE", Damage = "Power", Activity = "Hit",
		CanHit = function()
			return Shared.Enabled(), "HW:OFF"
		end,
		OnBreak = onBreak,
	})
	for i = 1, math.min(Config.Ore.Nodes or #Layout.OrePoints, #Layout.OrePoints) do
		spawnNode(i)
	end
	-- debug (Studio panel): respawn every node now
	pcall(function()
		local dbg = require(script.Parent:WaitForChild("Debug"))
		dbg.Commands.Ore = function()
			for i = 1, #Layout.OrePoints do
				local t = Ores.Nodes[i]
				if t then
					Strike.Remove(t, "Debug")
					Ores.Nodes[i] = nil
				end
				spawnNode(i)
			end
			return true, { Message = "Halloween ore respawned" }
		end
	end)
end

return Ores
