-- Dogdex (spec §8): collection rewards and the per-species stats the Dogdex window shows.
-- Feature module (Economy.FeatureRegistry). Saved data it touches:
--   p.DexClaims  {["10"]=true, ...}  reward ledger keyed by threshold (DogEconomy.DexRewards). Old claims
--                (10/25/50/75/100) stay as they are: a claimed threshold is never paid again and an old-only
--                threshold (25, 75) is not claimable any more.
--   p.VariantDex {[DogId]={[Variant]=true}} variants ever owned. Normalize also records the variant of every
--                dog the player owns now (lab rerolls change a dog's variant without Rules.Discover).
-- Action 'DexClaim' {Count} runs before the legacy Rules branch: the threshold must be a tier of
-- DexRewards, the museum count (Rules.MuseumCount) must reach it and the ledger must not have it. Bones,
-- coins (minutes of the player's income, BoostPricing), free Lucky Blocks (inventory, never paid random)
-- and a collection title are granted in the same transaction as the ledger entry.
-- Snapshot: snapshot.Features.Dogdex = {Count, Total, Bonus, BonusTotal, Layer, Rewards={{Count, Claimed,
-- Coins}}, DexStats={[DogId]={C=coins/min, D=digs/min, L=luck %, E=efficiency, F=finds/min}},
-- VariantDex={[DogId]=mask (bit i-1 = Config.Variants[i])}}.
-- Stats are the base stats of a Normal, mastery-0 dog of each DISCOVERED species working alone at the
-- player's current depth with all of the player's own bonuses, from the one income model
-- (Rules.IncomeModel). They are cached per player (a few seconds of work for a full collection only
-- when the depth, the upgrades, the bonuses or the boosts change, or once a minute at most).
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local C = require(script.Parent.Parent.Config)
local D = require(script.Parent.Parent.DogDefinitions)
local LuckRules = require(script.Parent.Parent.LuckRules)
local Rewards = require(RS.DogEconomy.DexRewards)
local Bonuses = require(RS.DogEconomy.Bonuses)
local BlockConfig = require(RS.LuckyBlockConfig)
local Lifecycle = require(RS.LuckyLifecycleConfig)

local F = { Name = "Dogdex", Order = 40 }
F.CacheSeconds = 60

-- Variant name -> bit (Config.Variants order: Normal = 1, Shiny = 2, Golden = 4, ...).
local VARIANT_BIT = {}
for i, v in ipairs(C.Variants) do
	VARIANT_BIT[v.Name] = 2 ^ (i - 1)
end
F.VariantBit = VARIANT_BIT

local BONUS_TOTAL = 0
for _, def in pairs(D) do
	-- event dogs (EventDex) have their own dex tab and reward ledger (NIGHT OF THE BURIED MOON): not BONUS dogs
	if type(def) == "table" and def.MuseumExcluded and not def.Reserved and not def.EventDex then
		BONUS_TOTAL += 1
	end
end

local function truthy(t, key)
	return type(t) == "table" and t[key] == true
end

function F.Normalize(_R, p, _now)
	-- The claim ledger: a table with string keys (DataStore-safe); numeric keys are converted.
	if type(p.DexClaims) ~= "table" then
		p.DexClaims = {}
	end
	local numeric = nil
	for key, value in pairs(p.DexClaims) do
		if type(key) == "number" then
			numeric = numeric or {}
			numeric[key] = value
		end
	end
	if numeric then
		for key, value in pairs(numeric) do
			p.DexClaims[key] = nil
			if value then
				p.DexClaims[tostring(math.floor(key))] = true
			end
		end
	end
	-- Variants ever owned: also the current variant of every owned dog.
	if type(p.VariantDex) ~= "table" then
		p.VariantDex = {}
	end
	for _, d in pairs(type(p.Dogs) == "table" and p.Dogs or {}) do
		if type(d) == "table" and type(d.DogId) == "string" and VARIANT_BIT[d.Variant] and D[d.DogId] then
			local seen = p.VariantDex[d.DogId]
			if type(seen) ~= "table" then
				seen = {}
				p.VariantDex[d.DogId] = seen
			end
			if seen[d.Variant] ~= true then
				seen[d.Variant] = true
			end
		end
	end
end

-- Free Lucky Blocks straight into the inventory (the LuckyLifecycle.AddStored shape: not paid random).
local function addBlocks(R, p, tier, count, now)
	p.OwnedBlocks = type(p.OwnedBlocks) == "table" and p.OwnedBlocks or {}
	for _ = 1, count do
		local uid
		repeat
			uid = string.upper((Http:GenerateGUID(false):gsub("-", "")))
		until p.OwnedBlocks[uid] == nil
		p.OwnedBlocks[uid] = {
			Uid = uid,
			OwnerUserId = p.UserId,
			Tier = tier,
			State = "Stored",
			PurchasedAt = now,
			PaidRandom = false,
			Origin = "Dogdex",
		}
	end
	return R.Count(p.OwnedBlocks)
end

function F.Claim(R, p, a, now)
	local count = type(a) == "table" and a.Count or nil
	R.Check(R.Int(count, 1, 1000), "Invalid milestone")
	local tier = Rewards.Get(count)
	R.Check(tier ~= nil, "Invalid milestone")
	p.DexClaims = type(p.DexClaims) == "table" and p.DexClaims or {}
	local key = tostring(tier.Count)
	R.Check(p.DexClaims[key] ~= true, "Reward already claimed")
	R.Check(R.MuseumCount(p) >= tier.Count, "Discover " .. tier.Count .. " dogs to unlock this reward")
	local block = tier.Block
	if block then
		R.Check(BlockConfig.Rank(block.Tier) ~= nil and R.Int(block.Count, 1, 10), "Invalid milestone")
		local stored = R.Count(type(p.OwnedBlocks) == "table" and p.OwnedBlocks or {})
		R.Check(stored + block.Count <= Lifecycle.InventoryCapacity, "Your Lucky Block storage is full. Open a block, then claim this reward")
	end
	p.DexClaims[key] = true
	local bones = math.clamp(math.floor(tier.Bones or 0), 0, math.max(0, C.MaxCash - p.Bones))
	p.Bones += bones
	local coins = math.clamp(math.floor(Rewards.Coins(tier, p, now)), 0, math.max(0, C.MaxCash - p.Cash))
	if coins > 0 then
		R.Credit(p, coins)
	end
	if block then
		addBlocks(R, p, block.Tier, block.Count, now)
	end
	if tier.Title then
		p.Cosmetics = type(p.Cosmetics) == "table" and p.Cosmetics or {}
		p.Cosmetics[tier.Title] = true
	end
	return "Dogdex reward claimed",
		{
			DexReward = {
				Count = tier.Count,
				Bones = bones,
				Coins = coins,
				Block = block and { Tier = block.Tier, Count = block.Count } or nil,
				Title = tier.Title,
			},
		}
end

function F.Action(R, p, action, a, now, _random)
	if action ~= "DexClaim" then
		return nil
	end
	return F.Claim(R, p, a, now)
end

-- Base stats of every discovered species --------------------------------------------------------
local cache = {}
local cacheSize = 0

local function round(x, decimals)
	x = tonumber(x) or 0
	if x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	local m = 10 ^ decimals
	return math.floor(x * m + 0.5) / m
end
-- Coins per minute with three significant digits (enough for the cards, small on the wire).
local function coins(x)
	x = tonumber(x) or 0
	if x ~= x or x <= 0 or x == math.huge then
		return 0
	end
	if x >= 1000 then
		local unit = 10 ^ (math.floor(math.log10(x)) - 2)
		return math.floor(x / unit + 0.5) * unit
	end
	return round(x, x >= 10 and 1 or 2)
end

local function deepest(p)
	local n = 1
	for i = 1, #C.Layers do
		if truthy(p.UnlockedLayers, tostring(i)) then
			n = i
		else
			break
		end
	end
	return n
end

-- Everything (apart from the clock) that changes the base stats.
local function signature(R, p, now, discovered)
	local parts = { tostring(p.CurrentLayer), tostring(deepest(p)), tostring(discovered) }
	local keys = {}
	for k in pairs(type(p.Upgrades) == "table" and p.Upgrades or {}) do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		table.insert(parts, k .. "=" .. tostring(p.Upgrades[k]))
	end
	local global = Bonuses.Global(p, now)
	for _, k in ipairs(Bonuses.Keys) do
		table.insert(parts, string.format("%.4f", tonumber(global[k]) or 0))
	end
	local supplies = type(p.Supplies) == "table" and p.Supplies or {}
	for _, k in ipairs({ "GoldenBiscuit", "EnergySnack", "LuckyTreat" }) do
		table.insert(parts, (tonumber(supplies[k]) or 0) > now and "1" or "0")
	end
	table.insert(parts, tostring(LuckRules.Bonus(p, now)))
	-- A full bag stops item income (Rules.IncomeModel), so it changes the numbers too.
	local okStorage, storage = pcall(R.Storage, p, now)
	table.insert(parts, okStorage and type(storage) == "table" and storage.ItemFull and "full" or "room")
	return table.concat(parts, "|")
end

function F.Stats(R, p, now)
	local dogs, discovered = {}, 0
	for id, known in pairs(type(p.DogDex) == "table" and p.DogDex or {}) do
		local def = D[id]
		if known == true and type(def) == "table" and not def.Reserved then
			discovered += 1
			local uid = "dex:" .. id
			dogs[uid] = {
				DogUid = uid,
				DogId = id,
				Variant = "Normal",
				Mastery = 0,
				MasteryXP = 0,
				AscensionLevel = 0,
				AssignedSlot = "",
				State = "Inventory",
				OwnerUserId = p.UserId,
			}
		end
	end
	if discovered == 0 then
		return {}
	end
	local key = signature(R, p, now, discovered)
	local hit = cache[p.UserId]
	if hit and hit.Key == key and now - hit.At < F.CacheSeconds then
		return hit.Stats
	end
	-- A read-only view: only these sample dogs, nobody at work beside them (no team auras), every
	-- other field (upgrades, bonuses, boosts, depth, storage) read from the real profile.
	local view = setmetatable({ Dogs = dogs }, { __index = p })
	local model = R.IncomeModel(view, now)
	local stats = {}
	for uid, m in pairs(model.Dogs or {}) do
		local id = string.sub(uid, 5)
		stats[id] = {
			C = coins(m.CoinsPerMin),
			D = round(m.DigsPerMin, 2),
			L = round(m.LuckPct, 1),
			E = round(m.Efficiency, 2),
			F = round(m.ItemFindsPerMin, 3),
		}
	end
	if not hit then
		cacheSize += 1
		if cacheSize > 300 then
			table.clear(cache)
			cacheSize = 1
		end
	end
	cache[p.UserId] = { Key = key, At = now, Stats = stats }
	return stats
end
function F.ResetCache()
	table.clear(cache)
	cacheSize = 0
end

function F.Snapshot(R, p, view, now)
	local claims = type(p.DexClaims) == "table" and p.DexClaims or {}
	local rewards = {}
	for i, tier in ipairs(Rewards.Tiers) do
		rewards[i] = { Count = tier.Count, Claimed = claims[tostring(tier.Count)] == true, Coins = Rewards.Coins(tier, p, now) }
	end
	local bonus = 0
	for id, known in pairs(type(p.DogDex) == "table" and p.DogDex or {}) do
		local def = D[id]
		if known == true and type(def) == "table" and def.MuseumExcluded and not def.Reserved and not def.EventDex then
			bonus += 1
		end
	end
	local variants = {}
	for id, seen in pairs(type(p.VariantDex) == "table" and p.VariantDex or {}) do
		if type(seen) == "table" and D[id] then
			local mask = 0
			for name, bit in pairs(VARIANT_BIT) do
				if seen[name] == true then
					mask += bit
				end
			end
			if mask > 0 then
				variants[id] = mask
			end
		end
	end
	local ok, stats = pcall(F.Stats, R, p, now)
	if not ok then
		warn("DOGROTS dogdex stats: " .. tostring(stats))
		stats = {}
	end
	view.Dogdex = {
		Version = Rewards.Version,
		Count = R.MuseumCount(p),
		Total = Rewards.Total,
		Bonus = bonus,
		BonusTotal = BONUS_TOTAL,
		Layer = p.CurrentLayer,
		Rewards = rewards,
		DexStats = stats,
		VariantDex = variants,
	}
end

return F
