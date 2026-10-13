-- Trade System 2.0 (docs/TRADE.md): limits, timings and the value estimate, shared by the server
-- (ServerScriptService.Economy.Engine, the authority) and the trade window (Modules.TradeScreen,
-- display only). Pure: no services besides the shared catalogues.
-- The value estimate only feeds the "is this fair?" bar and the extra confirmation: it never
-- blocks a trade.
local RS = game:GetService("ReplicatedStorage")
local Economy = RS:WaitForChild("DogEconomy")
local Dogs = require(Economy:WaitForChild("DogDefinitions"))
local Items = require(Economy:WaitForChild("ItemDefinitions"))
local Valuation = require(RS:WaitForChild("ItemValuation"))
local ValueConfig = require(RS:WaitForChild("ItemValueConfig"))

local T = {}

-- Offer size (one offer = up to MaxDogs dogs + MaxItems finds + Cash; Runtime.clean allows 30).
T.MaxDogs = 9
T.MaxItems = 9
-- Invitations: a request that locks nobody. It expires after InviteSeconds; after a decline,
-- an expiry or a withdrawal the same sender waits InviteCooldown seconds before inviting the
-- same player again; a sender has at most MaxInvites pending invitations.
T.InviteSeconds = 45
T.InviteCooldown = 20
T.MaxInvites = 3
-- Sessions: cancelled after SessionIdle seconds without any action. READY is accepted
-- ReviewSeconds after the latest offer change; after both READY, CONFIRM unlocks after
-- ConfirmDelay seconds.
T.SessionIdle = 300
T.ReviewSeconds = 2
T.ConfirmDelay = 5
-- The window warns (and asks again with a summary) when you give WarnRatio x more than you get.
T.WarnRatio = 3
-- Giving a dog or find of this rarity rank or rarer (Legendary) also asks for the summary.
T.BigRank = 5
T.RarityRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }
-- Value multipliers of dog variants (rarer variants are worth more than their income bonus).
T.VariantValue = { Normal = 1, Shiny = 1.5, Golden = 2.5, Corrupted = 4, Glitched = 7, Void = 12 }

local function num(v: any, default: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

-- Estimated coin value of a dog: its catalogue price (tongue price for walking Secrets) x variant
-- x mastery / ascension / first edition.
function T.DogValue(d: any): number
	if type(d) ~= "table" then
		return 0
	end
	local def = Dogs[d.DogId]
	if not def then
		return 0
	end
	local base = num(def.LinePrice or def.BasePrice, 0)
	local variant = T.VariantValue[d.Variant or "Normal"] or 1
	local mastery = 1 + math.clamp(num(d.Mastery, 0), 0, 100) * 0.003
	local ascension = 1 + 0.25 * math.clamp(num(d.AscensionLevel, 0), 0, 3)
	local edition = d.Edition == "First Edition" and 1.1 or 1
	return math.max(0, math.floor(base * variant * mastery * ascension * edition))
end

-- Estimated coin value of a find: its sale value (ItemValuation, fixed when it was found).
function T.ItemValue(x: any): number
	if type(x) ~= "table" then
		return 0
	end
	local value = num(x.SellValue, 0)
	if value >= 1 then
		return math.floor(value)
	end
	if Items[x.ItemId] then
		local ok, price = pcall(Valuation.Price, x)
		if ok and type(price) == "number" then
			return math.floor(price)
		end
	end
	return 0
end

-- Rarity names: dogs from their catalogue entry, finds from ItemValueConfig (the sale price rule).
function T.DogRarity(d: any): string
	local def = type(d) == "table" and Dogs[d.DogId]
	return (def and def.Rarity) or (type(d) == "table" and d.Rarity) or "Common"
end

function T.ItemRarity(x: any): string
	local def = type(x) == "table" and Items[x.ItemId]
	if not def then
		return "Common"
	end
	if def.Class == "Secret" then
		return "Secret"
	end
	for _, row in ipairs(ValueConfig.Rarity) do
		if (def.BaseDropChance or 1) <= row.MaxChance then
			return row.Name
		end
	end
	return "Common"
end

function T.IsBig(rarity: string?): boolean
	return (T.RarityRank[rarity or ""] or 0) >= T.BigRank
end

-- Finds with the same ItemId and mutation are "identical" for the quantity stepper.
function T.GroupKey(x: any): string
	return tostring(x.ItemId) .. "|" .. string.upper(tostring(x.Mutation or "NORMAL"))
end

-- Fairness from the viewer's side: give = what the viewer gives, get = what the viewer gets.
--   Share: give / (give + get) (0.5 when both are equal or empty)
--   Ratio: give / get (capped at 999)
--   Warn:  the viewer gives at least WarnRatio x more than they get
--   Level: "Empty" | "Fair" | "Over" (you give far more) | "Under" (you get far more)
function T.Fairness(give: any, get: any): any
	local g, r = math.max(0, num(give, 0)), math.max(0, num(get, 0))
	local total = g + r
	local f: any = { Give = g, Get = r, Share = total > 0 and g / total or 0.5 }
	if r > 0 then
		f.Ratio = math.min(999, g / r)
	else
		f.Ratio = g > 0 and 999 or 1
	end
	f.Warn = g > 0 and g >= T.WarnRatio * r
	if total == 0 then
		f.Level = "Empty"
	elseif f.Warn then
		f.Level = "Over"
	elseif r > 0 and r >= T.WarnRatio * g then
		f.Level = "Under"
	else
		f.Level = "Fair"
	end
	return f
end

return T
