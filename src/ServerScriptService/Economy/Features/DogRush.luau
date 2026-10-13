-- DOG RUSH progress (docs/DOG_RUSH.md). Feature module (Economy.FeatureRegistry); the event rules are
-- ReplicatedStorage.WorldEvents.DogRush, the pups are spawned and validated by WorldEventService.
-- Saved data (created by the first catch; absent on every other profile):
--   p.DogRush = {Version = 1, Generation = <event generation>, Caught = <pups this event>,
--                Claimed = {["3"] = true, ...} (chests of this event), Lifetime = <pups ever>,
--                Best = <most pups in one event>, Chests = <chests ever>}
-- Lifetime feeds the DOG WRANGLER / PUP HERDER / STAMPEDE KING titles (TitleDefinitions stat Pups).
-- F.Catch runs inside WorldEventService's catch transaction: per-event cap, coins (BoostPricing minutes
-- of the player's income) + bones, and every chest the catch reaches, at most once per event.
-- Snapshot: snapshot.Features.DogRush = {Lifetime, Best, Generation, Caught, Goal}.
local RS = game:GetService("ReplicatedStorage")
local Rush = require(RS:WaitForChild("WorldEvents"):WaitForChild("DogRush"))
local Config = require(RS.DogEconomy.Config)

local F = { Name = "DogRush", Order = 55 }

local function count(v: any): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v < 0 then
		return 0
	end
	return math.floor(v)
end

function F.Shape(p: any): any
	local d = p.DogRush
	if type(d) ~= "table" then
		d = {}
		p.DogRush = d
	end
	d.Version = 1
	d.Generation = type(d.Generation) == "string" and #d.Generation <= 80 and d.Generation or ""
	d.Caught = count(d.Caught)
	d.Lifetime = math.max(count(d.Lifetime), d.Caught)
	d.Best = math.max(count(d.Best), d.Caught)
	d.Chests = count(d.Chests)
	if type(d.Claimed) ~= "table" then
		d.Claimed = {}
	end
	local bad = nil
	for key, value in pairs(d.Claimed) do
		if type(key) ~= "string" or value ~= true then
			bad = bad or {}
			table.insert(bad, key)
		end
	end
	for _, key in ipairs(bad or {}) do
		d.Claimed[key] = nil
	end
	return d
end

function F.Normalize(_R: any, p: any, _now: number)
	if p.DogRush ~= nil then
		F.Shape(p)
	end
end

function F.Validate(R: any, p: any)
	local d = p.DogRush
	if d == nil then
		return
	end
	R.Check(type(d) == "table" and type(d.Claimed) == "table", "Invalid DOG RUSH progress")
	R.Check(R.Int(d.Caught or 0, 0, 1000000) and R.Int(d.Lifetime or 0, 0, 1e12), "Invalid DOG RUSH progress")
end

-- One caught pup in event `generation`. addBlock(p, tier, count) -> boolean grants a free Lucky Block
-- (server: LuckyLifecycle.AddStored when the storage has room) or nil. Returns the reward table.
function F.Catch(R: any, p: any, generation: string, now: number, addBlock: any): any
	R.Check(type(generation) == "string" and #generation > 0 and #generation <= 80, "This event opportunity has ended")
	local d = F.Shape(p)
	if d.Generation ~= generation then
		d.Generation = generation
		d.Caught = 0
		d.Claimed = {}
	end
	R.Check(d.Caught < Rush.Pups.PerEvent, "You caught every pup you can this rush!")
	d.Caught += 1
	d.Lifetime += 1
	d.Best = math.max(d.Best, d.Caught)
	local coins = math.clamp(math.floor(Rush.PupCoins(p, now)), 0, math.max(0, Config.MaxCash - p.Cash))
	if coins > 0 then
		R.Credit(p, coins)
	end
	local bones = math.clamp(Rush.Pups.Bones, 0, math.max(0, Config.MaxCash - p.Bones))
	p.Bones += bones
	local chests = {}
	for _, m in ipairs(Rush.Milestones) do
		local key = tostring(m.Count)
		if d.Caught >= m.Count and d.Claimed[key] ~= true then
			d.Claimed[key] = true
			d.Chests += 1
			local chestCoins = math.clamp(math.floor(Rush.ChestCoins(m, p, now)), 0, math.max(0, Config.MaxCash - p.Cash))
			if chestCoins > 0 then
				R.Credit(p, chestCoins)
			end
			local chestBones = m.Bones or 0
			local block = nil
			if m.Block then
				local granted = false
				if type(addBlock) == "function" then
					local ok, result = pcall(addBlock, p, m.Block.Tier, m.Block.Count)
					granted = ok and result == true
				end
				if granted then
					block = { Tier = m.Block.Tier, Count = m.Block.Count }
				else
					chestBones += m.FallbackBones or 0
				end
			end
			chestBones = math.clamp(chestBones, 0, math.max(0, Config.MaxCash - p.Bones))
			p.Bones += chestBones
			table.insert(chests, { Count = m.Count, Coins = chestCoins, Bones = chestBones, Block = block })
		end
	end
	return {
		Coins = coins,
		Bones = bones,
		Caught = d.Caught,
		Goal = Rush.Goal,
		PerEvent = Rush.Pups.PerEvent,
		Lifetime = d.Lifetime,
		Chests = chests,
	}
end

function F.Snapshot(_R: any, p: any, view: any, _now: number)
	local d = type(p.DogRush) == "table" and p.DogRush or {}
	view.DogRush = {
		Lifetime = count(d.Lifetime),
		Best = count(d.Best),
		Generation = type(d.Generation) == "string" and d.Generation or "",
		Caught = count(d.Caught),
		Goal = Rush.Goal,
	}
end

return F
