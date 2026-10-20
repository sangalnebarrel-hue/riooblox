-- DOG SHELTER rules. Pure (no services, no instances): Economy.ShelterService, CommunityQATests and
-- tests/shelter_e2e.luau use them. Prices come from the catalog, never from the client or resale history:
--   price = max(1, floor(BasePrice x rate x Rules.Bonus(dog)))   rate = def.ShelterRate or Config.Rate
--   Rules.Bonus = 1 + variant bonus + mastery bonus + ascension bonus (Breakdown shows the parts)
-- Eligible(p, uid, trading) -> ok, reason, code: one place decides which dogs are protected, so List, Quote and Sell
--   agree. Protected: not owned, any active trade session, Locked, Favorite, working / walking, a kennel slot, the yard
--   display, a marketplace listing or reservation of the dog. Codes (Protection) let the window draw an icon.
-- NeedsHold(def): Mythic / Secret dogs (rank >= HoldRank) and every event dog (EventDex) are sold with a
--   hold-to-confirm; the server refuses their Sell without Confirm = true.
-- InReach(x, y, z, client): the visit rule of ReplicatedStorage.DogEconomy.ShelterConfig (all shelter numbers live
--   there, shared with the window).
local S = {}

S.Config = require(game:GetService("ReplicatedStorage"):WaitForChild("DogEconomy"):WaitForChild("ShelterConfig"))
S.Rate = S.Config.Rate -- legacy name (CommunityQATests, the old window)

-- Protection codes (Eligible's third value) and their messages.
S.Messages = {
	Missing = "Dog not owned",
	Trade = "Finish your trade first",
	Locked = "Unlock this dog first",
	Favorite = "Remove this dog from favorites first",
	Working = "Wait for delivery or remove this dog from work",
	Kennel = "Remove this dog from its kennel first",
	Display = "Remove this dog from its display first",
	Listing = "Cancel the marketplace listing first",
	Reserved = "Dog is reserved",
	Error = "This dog cannot be rehomed right now",
}

function S.Eligible(p: any, uid: any, trading: any): (boolean, string?, string?)
	local m = S.Messages
	local dogs = type(p) == "table" and type(p.Dogs) == "table" and p.Dogs or {}
	local d = type(uid) == "string" and dogs[uid] or nil
	if type(d) ~= "table" or d.OwnerUserId ~= p.UserId or d.DogUid ~= uid then
		return false, m.Missing, "Missing"
	end
	if trading then
		return false, m.Trade, "Trade"
	end
	if d.Locked then
		return false, m.Locked, "Locked"
	end
	if d.Favorite then
		return false, m.Favorite, "Favorite"
	end
	-- A kennel dog is "Digging": name the kennel, the more useful reason.
	if (d.AssignedSlot or "") ~= "" then
		return false, m.Kennel, "Kennel"
	end
	if d.State ~= "Inventory" then
		return false, m.Working, "Working"
	end
	for _, shown in pairs(type(p.DisplayDogs) == "table" and p.DisplayDogs or {}) do
		if shown == uid then
			return false, m.Display, "Display"
		end
	end
	-- Listed dogs leave p.Dogs (Market), so these only guard records that still name the dog.
	for key, entry in pairs(type(p.Listings) == "table" and p.Listings or {}) do
		if key == uid or entry == uid or (type(entry) == "table" and entry.DogUid == uid) then
			return false, m.Listing, "Listing"
		end
	end
	local reservations = type(p.Reservations) == "table" and p.Reservations or {}
	if reservations[uid] then
		return false, m.Reserved, "Reserved"
	end
	return true, nil, nil
end

-- The shelter rate of one definition (event chapters may set def.ShelterRate).
function S.RateOf(def: any, cfg: any?): number
	local rate = type(def) == "table" and tonumber(def.ShelterRate) or nil
	if rate and rate > 0 and rate <= 1 then
		return rate
	end
	return (cfg or S.Config).Rate
end

function S.Price(d: any, definitions: any, bonus: (any) -> number): number
	local def = definitions[d.DogId]
	assert(def and type(def.BasePrice) == "number", "Unknown dog")
	return math.max(1, math.floor(def.BasePrice * S.RateOf(def) * bonus(d)))
end

-- The parts of the price for the detail panel: Base x Rate x Bonus = Price, Bonus = 1 + Variant + Mastery + Ascension.
-- economy: Economy.Config (Variants, Ascension); the mastery part is what Rules.Bonus adds beyond the other two.
function S.Breakdown(d: any, definitions: any, bonus: (any) -> number, economy: any?): any
	local def = definitions[d.DogId]
	assert(def and type(def.BasePrice) == "number", "Unknown dog")
	local total = bonus(d)
	local variant = 0
	for _, v in ipairs(type(economy) == "table" and economy.Variants or {}) do
		if v.Name == d.Variant then
			variant = tonumber(v.Bonus) or 0
		end
	end
	local ascension = 0
	local ascensions = type(economy) == "table" and economy.Ascension or nil
	if type(ascensions) == "table" then
		ascension = tonumber(ascensions[1 + (tonumber(d.AscensionLevel) or 0)]) or 0
	end
	local mastery = math.max(0, total - 1 - variant - ascension)
	return {
		Base = def.BasePrice,
		Rate = S.RateOf(def),
		Bonus = total,
		Variant = variant,
		Mastery = mastery,
		Ascension = ascension,
		Price = S.Price(d, definitions, bonus),
	}
end

function S.NeedsHold(def: any, cfg: any?): boolean
	if type(def) ~= "table" then
		return false
	end
	return (tonumber(def.Rank) or 0) >= (cfg or S.Config).HoldRank or def.EventDex ~= nil
end

function S.InReach(x: number, y: number, z: number, client: boolean?): boolean
	return S.Config.InReach(x, y, z, client)
end

-- List order: sellable first, then cheapest, then by uid (stable for the window).
function S.Order(a: any, b: any): boolean
	if a.Eligible ~= b.Eligible then
		return a.Eligible == true
	end
	if a.Price ~= b.Price then
		return (a.Price or 0) < (b.Price or 0)
	end
	return tostring(a.Uid) < tostring(b.Uid)
end

return S
