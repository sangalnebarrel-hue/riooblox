-- LUCKY DUST rules (ReplicatedStorage.Halloween.DustRules, docs/halloween2/DESIGN.md §14). Pure: what a Lucky Block
-- is worth, how much Lucky Dust dismantling it returns, what forging a block costs, which dismantles need a confirmed
-- hold and the Halloween candy a pumpkin tier adds. Shared by the server feature
-- (ServerScriptService.Economy.Features.LuckyDust), the bag (Modules.InventoryScreen: DISMANTLE, DUST FORGE) and
-- tests/lucky_dust.luau. Requires only config: LuckyBlockConfig (tiers, conveyor prices, reward pools, event tiers),
-- DogEconomy.Config (dog BasePrice by rank) and DogEconomy.LuckyDustConfig (every Lucky Dust number).
--
--   Value      BlockValue(tier) = min(ConveyorPrice, EV of the contents) for the six conveyor tiers, with
--              EV = Σ RewardPools[tier][rank] / 100 × Config.Prices[rank] (the dog BasePrice a block holds on average);
--              the event tiers (Pumpkin, Cursed Pumpkin) are worth their TradeValue.
--   Dismantle  Yield(tier) = floor(BlockValue × Salvage / CoinsPerDust) dust (Salvage .25, clamped to .20-.30);
--              EventBonus(tier) = Halloween candy for the pumpkin tiers (15 / 50).
--   Forge      ForgeCost(tier) = ceil(BlockValue × ForgeRate / CoinsPerDust) dust, Common..Legendary only (100 %).
--   Confirm    ConfirmNeeded(tier) = rank >= ConfirmRank (4: Legendary and up, both pumpkin tiers).
-- No profitable loop: dismantling returns Salvage of a block's value and forging charges the full value, so a
-- dismantle -> forge cycle gives back at most Salvage × max(EV / value) ≈ .25 × 1.73 ≈ .43 of what went in, even when
-- the forged block is judged by its higher EV (tests/lucky_dust.luau checks every tier pair).
local RS = game:GetService("ReplicatedStorage")
local Blocks = require(RS:WaitForChild("LuckyBlockConfig"))
local Economy = RS:WaitForChild("DogEconomy")
local DogConfig = require(Economy:WaitForChild("Config"))
local Config = require(Economy:WaitForChild("LuckyDustConfig"))

local D = {}
D.Config = Config

-- Display / iteration order: the conveyor tiers, then the event tiers.
D.Order = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Pumpkin", "Cursed Pumpkin" }

-- The computed numbers, frozen for the docs and the balance review (tests/lucky_dust.luau fails when the live values
-- drift from this table, so a price or pool change is noticed and this table updated on purpose).
-- Price = conveyor price, EV = average dog BasePrice inside, Value = BlockValue, Yield = dust per dismantle at
-- Salvage .25, Forge = dust per forged block, Candy = Halloween candy per dismantle.
D.Reference = {
	Common = { Price = 5000, EV = 8635, Value = 5000, Yield = 12, Forge = 50 },
	Rare = { Price = 22000, EV = 36220, Value = 22000, Yield = 55, Forge = 220 },
	Epic = { Price = 120000, EV = 183440, Value = 120000, Yield = 300, Forge = 1200 },
	Legendary = { Price = 750000, EV = 1064100, Value = 750000, Yield = 1875, Forge = 7500 },
	Mythic = { Price = 5000000, EV = 3494500, Value = 3494500, Yield = 8736 },
	Secret = { Price = 45000000, EV = 10380000, Value = 10380000, Yield = 25950 },
	Pumpkin = { TradeValue = 600000, Value = 600000, Yield = 1500, Candy = 15 },
	["Cursed Pumpkin"] = { TradeValue = 4000000, Value = 4000000, Yield = 10000, Candy = 50 },
}

local EPS = 1e-7

local function num(v: any): number
	return (type(v) == "number" and v == v) and v or 0
end

-- Canonical tier name (legacy aliases: Uncommon -> Rare, Brainrot God -> Mythic).
function D.Canonical(tier: any): string?
	if type(tier) ~= "string" then
		return nil
	end
	return Blocks.Canonical(tier)
end

function D.Rank(tier: any): number?
	if type(tier) ~= "string" then
		return nil
	end
	return Blocks.Rank(tier)
end

function D.IsEvent(tier: any): boolean
	local canonical = D.Canonical(tier)
	return canonical ~= nil and Blocks.IsEvent(canonical)
end

-- Average dog BasePrice inside a conveyor tier (whole coins), nil for event / unknown tiers.
function D.Contents(tier: any): number?
	local canonical = D.Canonical(tier)
	local pool = canonical and Blocks.RewardPools[canonical]
	if type(pool) ~= "table" then
		return nil
	end
	local ev = 0
	for rank, percent in ipairs(pool) do
		ev += num(percent) * num(DogConfig.Prices[rank]) / 100
	end
	return math.floor(ev + 0.5)
end

-- Coins a block of this tier is worth for dismantling and forging; nil when the tier cannot be valued.
function D.BlockValue(tier: any): number?
	local canonical = D.Canonical(tier)
	if not canonical then
		return nil
	end
	local event = Blocks.EventTiers[canonical]
	if event then
		local value = num(event.TradeValue)
		return value > 0 and math.floor(value) or nil
	end
	local price = num(Blocks.ConveyorPrices[canonical])
	local ev = D.Contents(canonical)
	if price <= 0 or not ev then
		return nil
	end
	return math.min(price, ev)
end

-- The salvage share in force (config clamped to the allowed range).
function D.Salvage(): number
	return math.clamp(num(Config.Salvage), Config.SalvageMin, Config.SalvageMax)
end

-- Dust one dismantled block returns (0 = this tier cannot be dismantled).
function D.Yield(tier: any): number
	local value = D.BlockValue(tier)
	if not value then
		return 0
	end
	return math.max(0, math.floor(value * D.Salvage() / Config.CoinsPerDust + EPS))
end

-- Halloween candy one dismantled block adds (pumpkin tiers only).
function D.EventBonus(tier: any): number
	local canonical = D.Canonical(tier)
	return canonical and math.max(0, math.floor(num(Config.EventCandy[canonical]))) or 0
end

function D.ConfirmNeeded(tier: any): boolean
	local rank = D.Rank(tier)
	return rank ~= nil and rank >= Config.ConfirmRank
end

function D.CanForge(tier: any): boolean
	return type(tier) == "string" and table.find(Config.Forgeable, tier) ~= nil and D.BlockValue(tier) ~= nil
end

-- Dust one forged block costs; nil when the tier is not sold at the forge.
function D.ForgeCost(tier: any): number?
	if not D.CanForge(tier) then
		return nil
	end
	local value = D.BlockValue(tier) :: number
	return math.max(1, math.ceil(value * num(Config.ForgeRate) / Config.CoinsPerDust - EPS))
end

-- The pure half of dismantle eligibility (the server adds: not opening, no trade session, the quote fingerprint).
-- Returns ok, reason (reason = a server message, localized by Localization.LuckyDust).
function D.Eligible(block: any, userId: number?, uid: string?): (boolean, string?)
	if type(block) ~= "table" or (userId ~= nil and block.OwnerUserId ~= userId) or (uid ~= nil and block.Uid ~= uid) then
		return false, "That block is not in your bag"
	end
	if block.State ~= "Stored" then
		return false, "Take that block off its Lucky pad first"
	end
	if D.Yield(block.Tier) <= 0 then
		return false, "This block cannot be dismantled"
	end
	return true, nil
end

-- What identifies a stored block for a quote: a block that changed between quote and dismantle is refused.
function D.Fingerprint(block: any): string
	return table.concat({
		tostring(block.Tier),
		tostring(block.State),
		tostring(block.PurchasedAt or 0),
		block.PaidRandom == true and "1" or "0",
		tostring(block.Origin or ""),
		tostring(block.Seed or 0),
	}, "|")
end

-- Totals of a list of {Tier, Count?} entries: {Count, Total (dust), Candy, NeedsConfirm, ByTier = {[tier] = n}}.
function D.Summarize(entries: { any }): any
	local out = { Count = 0, Total = 0, Candy = 0, NeedsConfirm = false, ByTier = {} }
	for _, entry in ipairs(entries) do
		local tier = D.Canonical(entry.Tier)
		local n = math.max(0, math.floor(num(entry.Count or 1)))
		if tier and n > 0 then
			out.Count += n
			out.Total += D.Yield(tier) * n
			out.Candy += D.EventBonus(tier) * n
			out.NeedsConfirm = out.NeedsConfirm or D.ConfirmNeeded(tier)
			out.ByTier[tier] = (out.ByTier[tier] or 0) + n
		end
	end
	return out
end

-- Picks what a dismantle request should hold from a profile (the server profile or snapshot.Profile): stored blocks of
-- the given tiers (in the order of `tiers`, oldest first) and then legacy credit stacks, at most `max` in total.
-- Returns {Uids = {uid}, Credits = {[savedTier] = n}, Count, Available (all eligible), ByTier = {[tier] = n}}.
function D.Select(profile: any, tiers: { string }, max: number?, userId: number?): any
	local limit = math.max(0, math.floor(max or Config.MaxBatch))
	local out = { Uids = {}, Credits = {}, Count = 0, Available = 0, ByTier = {} }
	if type(profile) ~= "table" then
		return out
	end
	local owner = userId or profile.UserId
	local blocks = type(profile.OwnedBlocks) == "table" and profile.OwnedBlocks or {}
	local credits = type(profile.LuckyCredits) == "table" and profile.LuckyCredits or {}
	for _, wanted in ipairs(tiers) do
		local tier = D.Canonical(wanted)
		if tier and D.Yield(tier) > 0 then
			local list = {}
			for uid, block in pairs(blocks) do
				if type(uid) == "string" and type(block) == "table" and D.Canonical(block.Tier) == tier and D.Eligible(block, owner, uid) then
					table.insert(list, { Uid = uid, At = num(block.PurchasedAt) })
				end
			end
			table.sort(list, function(a, b)
				if a.At ~= b.At then
					return a.At < b.At
				end
				return a.Uid < b.Uid
			end)
			out.Available += #list
			for _, row in ipairs(list) do
				if out.Count < limit then
					table.insert(out.Uids, row.Uid)
					out.Count += 1
					out.ByTier[tier] = (out.ByTier[tier] or 0) + 1
				end
			end
			local keys = {}
			for saved, n in pairs(credits) do
				if type(saved) == "string" and D.Canonical(saved) == tier and num(n) >= 1 then
					table.insert(keys, saved)
				end
			end
			table.sort(keys)
			for _, saved in ipairs(keys) do
				local have = math.floor(num(credits[saved]))
				out.Available += have
				local take = math.min(have, limit - out.Count)
				if take > 0 then
					out.Credits[saved] = take
					out.Count += take
					out.ByTier[tier] = (out.ByTier[tier] or 0) + take
				end
			end
		end
	end
	return out
end

-- How much of a block's value comes back when it is dismantled and the dust is spent on `toTier` (fraction of
-- BlockValue(fromTier); `count` blocks are dismantled together so partial forges are not lost). The forged blocks are
-- judged by max(conveyor price, EV of the contents), the most generous view.
function D.CycleReturn(fromTier: string, toTier: string, count: number?): number
	local value = D.BlockValue(fromTier)
	local cost = D.ForgeCost(toTier)
	if not value or not cost then
		return 0
	end
	local n = math.max(1, math.floor(count or 1))
	local forged = math.floor(D.Yield(fromTier) * n / cost)
	local worth = math.max(num(Blocks.ConveyorPrices[D.Canonical(toTier) :: string]), D.Contents(toTier) or 0)
	return forged * worth / (value * n)
end

return D
