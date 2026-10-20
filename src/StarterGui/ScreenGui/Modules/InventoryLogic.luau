-- Pure logic of MY BAG (Modules.InventoryScreen): rows of the finds with their rarity and value,
-- search / rarity / depth / mutation / favourite filters, the five sorts, Lucky Block grouping by
-- tier, capacity, sell safety and market price parsing. No services and no instances:
-- tests/inventory.luau runs it in Lune. (The old static page keeps InventoryPage.InventoryView.)
local L = {}

L.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }
L.RarityRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }
L.Sorts = { "rarest", "newest", "value", "heaviest", "name" }
-- Natural direction of each sort (SortSelect's arrow flips it).
L.SortDescending = { rarest = true, newest = true, value = true, heaviest = true, name = false }
-- Selling one of these asks for a 1 s hold (and favourites always do).
L.HoldFrom = 4 -- Epic

-- Item rarity from its definition: the rule of ItemValuation (Secret class first, then the first
-- ItemValueConfig.Rarity row whose MaxChance covers the base drop chance).
function L.Rarity(def: any, valueConfig: any): string
	if type(def) ~= "table" then
		return "Common"
	end
	if def.Class == "Secret" then
		return "Secret"
	end
	local chance = tonumber(def.BaseDropChance) or 1
	for _, row in ipairs(valueConfig and valueConfig.Rarity or {}) do
		if chance <= row.MaxChance then
			return row.Name
		end
	end
	return "Common"
end

-- Uids the player PINNED to the showcase (protected from selling, trading and listing):
-- snapshot.Features.Showcase.Pinned = {[uid] = slot} (Features.Showcase), or its Slots
-- {["1"] = uid}. Finds the stand shows only as automatic picks (Auto / Exhibits) stay free.
function L.ShowcaseSet(snapshot: any, items: any): { [string]: boolean }
	local set = {}
	if type(snapshot) ~= "table" or type(items) ~= "table" then
		return set
	end
	local features = type(snapshot.Features) == "table" and snapshot.Features or {}
	local data = type(features.Showcase) == "table" and features.Showcase or (type(snapshot.Showcase) == "table" and snapshot.Showcase or nil)
	if not data then
		return set
	end
	if type(data.Pinned) == "table" then
		for uid in pairs(data.Pinned) do
			if type(uid) == "string" and items[uid] ~= nil then
				set[uid] = true
			end
		end
	elseif type(data.Slots) == "table" then
		for _, uid in pairs(data.Slots) do
			if type(uid) == "string" and items[uid] ~= nil then
				set[uid] = true
			end
		end
	end
	return set
end

-- One row per owned find. ctx: Definitions, ValueConfig, Price(item) -> number (the server's
-- formula, ItemValuation.Price), Showcase (set of uids), Names (optional ItemId -> shown name).
function L.Rows(profile: any, ctx: any): { any }
	local rows = {}
	local items = type(profile) == "table" and type(profile.Items) == "table" and profile.Items or {}
	local defs = ctx.Definitions or {}
	local showcase = ctx.Showcase or {}
	for uid, item in pairs(items) do
		if type(uid) == "string" and type(item) == "table" then
			local def = defs[item.ItemId]
			local rarity = L.Rarity(def, ctx.ValueConfig)
			local value = 0
			if ctx.Price then
				local ok, price = pcall(ctx.Price, item)
				value = (ok and tonumber(price)) or tonumber(item.SellValue) or 0
			else
				value = tonumber(item.SellValue) or 0
			end
			local name = tostring(item.DisplayName or (def and def.DisplayName) or item.ItemId or "?")
			local shown = ctx.Names and ctx.Names[item.ItemId] or nil
			local mutation = string.upper(tostring(item.Mutation or "NORMAL"))
			table.insert(rows, {
				Key = uid,
				Item = item,
				ItemId = item.ItemId,
				Name = name,
				Rarity = rarity,
				Rank = L.RarityRank[rarity] or 1,
				Mutation = mutation,
				Depth = tonumber(item.Depth or (def and def.Depth)) or 1,
				Weight = tonumber(item.WeightKg) or 0,
				Value = math.max(0, math.floor(value)),
				Odds = tonumber(item.CombinedOdds) or 0,
				FoundAt = tonumber(item.FoundAt) or 0,
				Favorite = item.Favorite == true,
				Showcase = showcase[uid] == true,
				Tradeable = item.Tradeable ~= false,
				Search = string.lower(name .. " " .. (shown or "") .. " " .. mutation .. " " .. rarity),
			})
		end
	end
	return rows
end

-- Filters: Query (text), Rarities (set or list), Depth (number or nil), Mutations (set or list),
-- Favorites (only favourites). Empty sets mean "any".
local function asSet(value: any): { [any]: boolean }?
	if type(value) ~= "table" then
		return nil
	end
	local set, any = {}, false
	for key, inner in pairs(value) do
		if type(key) == "number" then
			set[inner] = true
		elseif inner then
			set[key] = true
		end
		any = true
	end
	return any and set or nil
end

function L.Match(row: any, f: any): boolean
	local query = string.lower(tostring(f.Query or ""))
	query = string.gsub(query, "^%s+", "")
	query = string.gsub(query, "%s+$", "")
	if query ~= "" and not string.find(row.Search, query, 1, true) then
		return false
	end
	if f.Favorites and not row.Favorite then
		return false
	end
	if f.Depth and row.Depth ~= f.Depth then
		return false
	end
	local rarities = asSet(f.Rarities)
	if rarities and not rarities[row.Rarity] then
		return false
	end
	local mutations = asSet(f.Mutations)
	if mutations and not mutations[row.Mutation] then
		return false
	end
	return true
end

function L.Filter(rows: { any }, f: any): { any }
	local out = {}
	for _, row in ipairs(rows) do
		if L.Match(row, f or {}) then
			table.insert(out, row)
		end
	end
	return out
end

-- Sorts in place and returns rows. descending nil = the sort's natural direction. Ties fall
-- back to rarity, value and the uid, so the order is stable between refreshes.
function L.Sort(rows: { any }, id: string?, descending: boolean?): { any }
	local sort = id or "rarest"
	local desc = descending
	if desc == nil then
		desc = L.SortDescending[sort] ~= false
	end
	-- Keys compared in order; rarest = rarity tier, then the odds of that exact find.
	local function keys(row: any): (any, any)
		if sort == "newest" then
			return row.FoundAt, 0
		elseif sort == "value" then
			return row.Value, 0
		elseif sort == "heaviest" then
			return row.Weight, 0
		elseif sort == "name" then
			return string.lower(row.Name), ""
		end
		return row.Rank, row.Odds
	end
	table.sort(rows, function(a, b)
		local a1, a2 = keys(a)
		local b1, b2 = keys(b)
		if a1 ~= b1 then
			if desc then
				return a1 > b1
			end
			return a1 < b1
		end
		if a2 ~= b2 then
			if desc then
				return a2 > b2
			end
			return a2 < b2
		end
		if a.Rank ~= b.Rank then
			return a.Rank > b.Rank
		end
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.Key < b.Key
	end)
	return rows
end

-- Rows of the current view: filtered and sorted. state: the filter fields + Sort, Desc.
function L.View(rows: { any }, state: any): { any }
	return L.Sort(L.Filter(rows, state), state.Sort, state.Desc)
end

-- Mutations present in the bag (filter options), most valuable first; NORMAL is left out.
function L.Mutations(rows: { any }, valueConfig: any): { string }
	local seen, list = {}, {}
	for _, row in ipairs(rows) do
		if row.Mutation ~= "NORMAL" and not seen[row.Mutation] then
			seen[row.Mutation] = true
			table.insert(list, row.Mutation)
		end
	end
	local mult = valueConfig and valueConfig.Mutation or {}
	table.sort(list, function(a, b)
		local ma, mb = tonumber(mult[a]) or 1, tonumber(mult[b]) or 1
		if ma ~= mb then
			return ma > mb
		end
		return a < b
	end)
	return list
end

-- Number of active filters besides search and rarity chips (the FILTERS button count).
function L.ExtraFilters(state: any): number
	local n = 0
	if state.Depth then
		n += 1
	end
	local mutations = asSet(state.Mutations)
	if mutations then
		for _ in pairs(mutations) do
			n += 1
		end
	end
	if state.Favorites then
		n += 1
	end
	return n
end

-- True when any filter (search, rarity, depth, mutation, favourites) narrows the list.
function L.Filtering(state: any): boolean
	local query = tostring(state.Query or "")
	return string.find(query, "%S") ~= nil or asSet(state.Rarities) ~= nil or L.ExtraFilters(state) > 0
end

-- Capacity of the bag: fraction, Full (sell before digging more) and Warn (80 %+).
function L.Capacity(count: any, capacity: any): any
	local n, cap = math.max(0, tonumber(count) or 0), math.max(0, tonumber(capacity) or 0)
	local fraction = cap > 0 and math.clamp(n / cap, 0, 1) or 0
	return { Count = n, Capacity = cap, Fraction = fraction, Full = cap > 0 and n >= cap, Warn = cap > 0 and n >= cap * 0.8 }
end

-- Seconds the SELL confirmation must be held: Epic and rarer, or a favourite.
function L.SellHold(rarity: string?, favorite: boolean?): number
	if favorite then
		return 1
	end
	return ((L.RarityRank[rarity or "Common"] or 1) >= L.HoldFrom) and 1 or 0
end

-- Total sale value of rows.
function L.TotalValue(rows: { any }): number
	local total = 0
	for _, row in ipairs(rows) do
		total += row.Value
	end
	return total
end

-- Market price typed by the player: digits with optional spaces / commas, or a K / M suffix
-- ("12k" = 12000). Returns the whole price or nil and a reason ("empty", "invalid", "low", "high").
function L.ParsePrice(text: any, minimum: number?, maximum: number?): (number?, string?)
	local raw = string.lower(tostring(text or ""))
	raw = string.gsub(raw, "[%s,_']", "")
	if raw == "" then
		return nil, "empty"
	end
	local digits, suffix = string.match(raw, "^(%d+%.?%d*)([km]?)$")
	if not digits then
		return nil, "invalid"
	end
	local value = tonumber(digits)
	if not value then
		return nil, "invalid"
	end
	if suffix == "k" then
		value *= 1e3
	elseif suffix == "m" then
		value *= 1e6
	end
	value = math.floor(value + 0.5)
	if value < (minimum or 10) then
		return nil, "low"
	end
	if maximum and value > maximum then
		return nil, "high"
	end
	return value, nil
end

-- The 1 % listing fee the server charges (Market:Create) and what the seller keeps.
function L.Fee(price: number): number
	return math.max(1, math.ceil(price * 0.01))
end

-- Suggested prices from the collector value: x1, x1.5, x2, x3 (never under the minimum).
function L.PriceHints(value: number, minimum: number?): { number }
	local floor = minimum or 10
	local base = math.max(floor, math.floor(tonumber(value) or 0))
	local list = {}
	for _, mult in ipairs({ 1, 1.5, 2, 3 }) do
		table.insert(list, math.max(floor, math.floor(base * mult + 0.5)))
	end
	return list
end

-- Lucky Blocks grouped by tier, rarest first. ctx: Canonical(tier) and Rank(tier) of
-- LuckyBlockConfig. Each group: Tier, Rank, Count, Stored (in the bag, stacks included),
-- Placed (on pads), Ready (placed and done), NextReadyAt (the next placed one to finish),
-- Uid (a block to show the odds of: a stored one first).
function L.Blocks(profile: any, now: number, ctx: any): { any }
	local canonical = ctx and ctx.Canonical or function(tier)
		return tier
	end
	local rank = ctx and ctx.Rank or function()
		return 1
	end
	local groups, order = {}, {}
	local function group(tier: any): any
		local key = tostring(canonical(tier) or tier)
		local g = groups[key]
		if not g then
			g = { Tier = key, Rank = tonumber(rank(key)) or 0, Count = 0, Stored = 0, Placed = 0, Ready = 0, NextReadyAt = nil, Uid = nil }
			groups[key] = g
			table.insert(order, g)
		end
		return g
	end
	if type(profile) ~= "table" then
		return order
	end
	for tier, quantity in pairs(type(profile.LuckyCredits) == "table" and profile.LuckyCredits or {}) do
		local n = math.max(0, math.floor(tonumber(quantity) or 0))
		if n > 0 then
			local g = group(tier)
			g.Count += n
			g.Stored += n
		end
	end
	for uid, block in pairs(type(profile.OwnedBlocks) == "table" and profile.OwnedBlocks or {}) do
		if type(block) == "table" and block.Tier then
			local g = group(block.Tier)
			g.Count += 1
			local readyAt = tonumber(block.ReadyAt)
			if block.State == "Placed" or block.State == "Ready" then
				g.Placed += 1
				if block.State == "Ready" or (readyAt and readyAt <= now) then
					g.Ready += 1
				elseif readyAt and (g.NextReadyAt == nil or readyAt < g.NextReadyAt) then
					g.NextReadyAt = readyAt
				end
				g.PlacedUid = g.PlacedUid or uid
			else
				g.Stored += 1
				g.Uid = g.Uid or uid
			end
		end
	end
	for _, g in ipairs(order) do
		g.Uid = g.Uid or g.PlacedUid
	end
	table.sort(order, function(a, b)
		if a.Rank ~= b.Rank then
			return a.Rank > b.Rank
		end
		return a.Tier < b.Tier
	end)
	return order
end

-- Blocks owned in total (the LUCKY BLOCKS capacity line).
function L.BlockCount(groups: { any }): number
	local n = 0
	for _, g in ipairs(groups) do
		n += g.Count
	end
	return n
end

-- Weight for chips: "850 g", "4.2 kg", "37 kg", "1.2K kg".
function L.WeightText(kg: number, short: ((number) -> string)?): string
	kg = tonumber(kg) or 0
	if kg < 1 then
		return string.format("%d g", math.floor(kg * 1000 + 0.5))
	elseif kg < 10 then
		return string.format("%.1f kg", kg)
	elseif kg < 1000 then
		return string.format("%d kg", math.floor(kg + 0.5))
	end
	return (short and short(kg) or tostring(math.floor(kg))) .. " kg"
end

return L
