-- Pure list logic of the DOG SHELTER window (Modules.ShelterScreen): filters, sorts, counts, the protection icons,
-- the price breakdown lines, which server replies are worth one automatic retry and the quote deadline.
-- No services and no `script`: tests/shelter_e2e.luau requires it directly.
--   rows: the List reply rows of Economy.ShelterService ({Uid, Name, Rarity, Rank, Price, Eligible, Protection,
--         Breakdown, Event, NeedsHold, ...}).
local M = {}

M.Filters = { "all", "sellable", "protected" }
M.Sorts = { "sellable", "rarity", "price" }

-- Protection code (ShelterRules.Eligible) -> icon glyph and the short card label (English key of Localization.Shelter.UI).
M.Protections = {
	Missing = { Icon = "❔", Label = "UNAVAILABLE" },
	Trade = { Icon = "🤝", Label = "IN TRADE" },
	Locked = { Icon = "🔒", Label = "LOCKED" },
	Favorite = { Icon = "❤️", Label = "FAVORITE" },
	Working = { Icon = "⛏️", Label = "WORKING" },
	Kennel = { Icon = "🏠", Label = "IN KENNEL" },
	Display = { Icon = "🏆", Label = "ON DISPLAY" },
	Listing = { Icon = "🏷️", Label = "LISTED" },
	Reserved = { Icon = "⏳", Label = "RESERVED" },
	Error = { Icon = "⚠️", Label = "UNAVAILABLE" },
}

function M.Protection(code: any): any
	return M.Protections[code] or M.Protections.Error
end

local RARITY = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Secret = 6 }
local function rankOf(row: any): number
	local rank = tonumber(row.Rank)
	if rank and rank > 0 then
		return rank
	end
	return RARITY[row.Rarity] or 0
end
M.RankOf = rankOf

function M.Counts(rows: { any }): any
	local counts = { all = 0, sellable = 0, protected = 0, Total = 0 }
	for _, row in ipairs(rows) do
		counts.all += 1
		if row.Eligible then
			counts.sellable += 1
			counts.Total += tonumber(row.Price) or 0
		else
			counts.protected += 1
		end
	end
	return counts
end

-- The rows to show: filter "all" | "sellable" | "protected"; sort "sellable" (sellable first, then price), "rarity"
-- (rarest first), "price" (most valuable first); desc flips the main key. Ties fall back to price, name and uid, so
-- the order never jumps between two refreshes of the same data.
function M.Items(rows: { any }, filter: string?, sort: string?, desc: boolean?): { any }
	local kept = {}
	for _, row in ipairs(rows) do
		if filter == "sellable" then
			if row.Eligible then
				table.insert(kept, row)
			end
		elseif filter == "protected" then
			if not row.Eligible then
				table.insert(kept, row)
			end
		else
			table.insert(kept, row)
		end
	end
	local function tie(a: any, b: any): boolean
		local pa, pb = tonumber(a.Price) or 0, tonumber(b.Price) or 0
		if pa ~= pb then
			return pa < pb
		end
		local na, nb = tostring(a.Name or ""), tostring(b.Name or "")
		if na ~= nb then
			return na < nb
		end
		return tostring(a.Uid) < tostring(b.Uid)
	end
	local flip = desc == true
	table.sort(kept, function(a: any, b: any): boolean
		if sort == "rarity" then
			local ra, rb = rankOf(a), rankOf(b)
			if ra ~= rb then
				if flip then
					return ra < rb
				end
				return ra > rb
			end
			return tie(a, b)
		elseif sort == "price" then
			local pa, pb = tonumber(a.Price) or 0, tonumber(b.Price) or 0
			if pa ~= pb then
				if flip then
					return pa < pb
				end
				return pa > pb
			end
			return tie(a, b)
		end
		-- "sellable": the server order (sellable first, cheapest first); desc = most valuable first.
		if (a.Eligible == true) ~= (b.Eligible == true) then
			return a.Eligible == true
		end
		local pa, pb = tonumber(a.Price) or 0, tonumber(b.Price) or 0
		if pa ~= pb then
			if flip then
				return pa > pb
			end
			return pa < pb
		end
		return tie(a, b)
	end)
	return kept
end

function M.Find(rows: { any }, uid: any): any
	if uid == nil then
		return nil
	end
	for _, row in ipairs(rows) do
		if row.Uid == uid then
			return row
		end
	end
	return nil
end

-- After a sale: the dog that took the sold dog's place in the shown list (the next one, else the previous one).
function M.NextUid(items: { any }, soldUid: any): any
	for i, row in ipairs(items) do
		if row.Uid == soldUid then
			local nextRow = items[i + 1] or items[i - 1]
			return nextRow and nextRow.Uid or nil
		end
	end
	return nil
end

-- Replies that can heal by themselves within a second: the server judged a lagged position, the profile is still
-- loading or the request bucket is empty. The window retries those once (ShelterConfig.RetryDelay).
M.RetryMessages = {
	["Visit the reception inside Dog Shelter"] = true,
	["Please wait for your profile"] = true,
	["Too many requests; wait a moment"] = true,
	["Account is busy; retry shortly"] = true,
}
function M.Retryable(message: any): boolean
	return type(message) == "string" and M.RetryMessages[message] == true
end

-- Sell replies after which the reviewed price is gone: back to REVIEW SALE (and a fresh list).
M.StaleMessages = {
	["Confirmation expired; choose the dog again"] = true,
	["Dog changed; review this dog again before selling"] = true,
	["Dog changed; request a new price"] = true,
	["Invalid confirmation"] = true,
}
function M.Stale(message: any): boolean
	return type(message) == "string" and M.StaleMessages[message] == true
end

-- Client deadline of a quote on the local monotonic clock: the server's TTL minus one second of travel. Never the
-- device's wall clock (A07 D3: a phone clock running fast used to expire every quote at once).
function M.Deadline(quote: any, clockNow: number): number
	local ttl = tonumber(quote and quote.TTL) or 0
	return clockNow + math.max(0, ttl - 1)
end

local function percent(x: number): string
	local value = math.floor(x * 1000 + 0.5) / 10
	if value == math.floor(value) then
		return string.format("%d%%", value)
	end
	return string.format("%.1f%%", value)
end
M.Percent = percent

-- "x1.42" style multiplier (two decimals, trailing zeros dropped).
function M.Mult(x: any): string
	local value = math.floor((tonumber(x) or 1) * 100 + 0.5) / 100
	local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
	return "×" .. text
end

-- The bonus parts of a breakdown as {Key, Value} (Key = template of Localization.Shelter.Templates, Value = "30%").
function M.BonusParts(breakdown: any): { any }
	local parts = {}
	if type(breakdown) ~= "table" then
		return parts
	end
	for _, spec in ipairs({ { "Variant", "Variant +%s" }, { "Mastery", "Mastery +%s" }, { "Ascension", "Ascension +%s" } }) do
		local v = tonumber(breakdown[spec[1]]) or 0
		if v > 0.0005 then
			table.insert(parts, { Key = spec[2], Value = percent(v) })
		end
	end
	return parts
end

return M
