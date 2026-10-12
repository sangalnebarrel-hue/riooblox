-- Dogdex collection rewards (spec §8), shared by the server (ServerScriptService.Economy.Features.Dogdex
-- grants them through the 'DexClaim' action) and the Dogdex window (shows them).
-- A tier unlocks when the museum count (Rules.MuseumCount: discovered dogs #1-#100, bonus dogs such as
-- Aurion excluded) reaches Count. Claims are saved in p.DexClaims keyed by the threshold as a string
-- ("10", "20", ...), never by position in this table, so reordering or retuning tiers can never reopen
-- a claim. Thresholds of the old table (10, 25, 50, 75, 100) that a player already claimed stay
-- claimed; old-only thresholds (25, 75) are no longer claimable and stay harmless in the ledger.
-- Rewards:
--   Bones   flat amount
--   Coins   {MinCash, IncomeMinutes}: BoostPricing.Coins, i.e. that many minutes of the player's team
--           income, never less than MinCash x the layer scale of the deepest unlocked layer
--   Block   {Tier, Count}: free Lucky Blocks (stored in the inventory, not paid random items)
--   Title   a collection title (p.Cosmetics key, equipped from COSMETICS); TitleName is shown in the UI
local M = {}
M.Version = 2
M.Total = 100 -- dogs #1-#100 of the museum: the full collection

M.Tiers = {
	{ Count = 10, Bones = 25, Coins = { MinCash = 20000, IncomeMinutes = 10 }, Block = { Tier = "Rare", Count = 1 }, Title = "Dex10", TitleName = "DOG SPOTTER" },
	{ Count = 20, Bones = 40, Coins = { MinCash = 40000, IncomeMinutes = 15 } },
	{ Count = 30, Bones = 60, Coins = { MinCash = 80000, IncomeMinutes = 20 }, Block = { Tier = "Epic", Count = 1 }, Title = "Dex30", TitleName = "DOG COLLECTOR" },
	{ Count = 40, Bones = 80, Coins = { MinCash = 150000, IncomeMinutes = 25 } },
	{ Count = 50, Bones = 110, Coins = { MinCash = 300000, IncomeMinutes = 30 }, Block = { Tier = "Legendary", Count = 1 }, Title = "Dex50", TitleName = "DOGDEX EXPERT" },
	{ Count = 60, Bones = 140, Coins = { MinCash = 500000, IncomeMinutes = 40 }, Block = { Tier = "Epic", Count = 2 } },
	{ Count = 70, Bones = 180, Coins = { MinCash = 900000, IncomeMinutes = 50 }, Block = { Tier = "Legendary", Count = 1 }, Title = "Dex70", TitleName = "DOG SCHOLAR" },
	{ Count = 80, Bones = 230, Coins = { MinCash = 1500000, IncomeMinutes = 60 }, Block = { Tier = "Legendary", Count = 2 } },
	{ Count = 90, Bones = 300, Coins = { MinCash = 3000000, IncomeMinutes = 75 }, Block = { Tier = "Mythic", Count = 1 }, Title = "Dex90", TitleName = "DOG LEGEND" },
	{ Count = 100, Bones = 500, Coins = { MinCash = 6000000, IncomeMinutes = 120 }, Block = { Tier = "Mythic", Count = 2 }, Title = "Dex100", TitleName = "DOGDEX MASTER", Full = true },
}

M.ByCount = {}
for index, tier in ipairs(M.Tiers) do
	tier.Index = index
	M.ByCount[tier.Count] = tier
end

-- The tier unlocked at exactly `count` dogs (nil when no tier has that threshold).
function M.Get(count: any): any
	return type(count) == "number" and M.ByCount[count] or nil
end

-- Coins the tier pays this player now (server and client agree: same BoostPricing maths).
function M.Coins(tier: any, p: any, now: number?): number
	if type(tier) ~= "table" or type(tier.Coins) ~= "table" then
		return 0
	end
	local Pricing = require(script.Parent.BoostPricing)
	return Pricing.Coins(tier.Coins, p or {}, now or os.time())
end

-- The first tier not claimed yet (nil when every tier is claimed).
function M.Next(claims: any): any
	claims = type(claims) == "table" and claims or {}
	for _, tier in ipairs(M.Tiers) do
		if claims[tostring(tier.Count)] ~= true then
			return tier
		end
	end
	return nil
end

return M
