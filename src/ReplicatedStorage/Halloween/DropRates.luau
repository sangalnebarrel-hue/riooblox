-- Rare prize philosophy for weighted drop tables (ReplicatedStorage.Halloween.DropRates; pure: requires nothing, safe on
-- server, client and in Lune tests). docs/halloween2/DESIGN.md §12.3, docs/halloween2/CHAPTER1_BALANCE.md.
-- A table keeps every row; only the rows' PROBABILITIES change: each row's chance is multiplied by the factor of its
-- class (Classify: resources x .5, Common/Rare/Epic prizes x .10, Legendary x .05, Mythic x .025, Secret x .01 — the
-- factors live in Config.Rebalance.RarityScale) and the probability this frees goes to the filler row(s) (Lucky Dust
-- for the Pumpkin blocks), so a "miss" still feeds the Dust Forge. Rescaled weights are integers on a fixed scale
-- (Scale = 1e6): every rescaled row's chance equals old chance x factor within 1e-6 (a row that would round to 0 keeps
-- weight 1, so no prize ever becomes impossible) and the weights of a rescaled table sum to exactly Scale.
--   DropRates.Scale                                      1 000 000
--   DropRates.Classify(row) -> class                     "Resource" (Kind Cash/Bones/Candy/Dust/...) or the row's rarity
--                                                        ("Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret";
--                                                        from Rarity, else from Rank 1..6)
--   DropRates.Factor(row, factors) -> factor, class      errors when the factors table has no entry for the class
--   DropRates.Rescale(rows, factors, filler) -> rows, report
--                                                        new rows (deep copies, original order, filler rows appended);
--                                                        `rows` is never edited. filler = one row or a list of rows (the
--                                                        freed probability is split by their own Weight, default equal)
--   DropRates.Report(rows) -> report                     plain odds of any weighted table (UI odds lists, docs)
--   DropRates.ScaleChance(chance, rows, factors) -> chance, weights
--                                                        one roll that then picks a row by weight (the boss dog drop:
--                                                        DogChance x DogWeights): the factors apply to each row's absolute
--                                                        chance; returns the new overall chance + new relative weights
--   DropRates.Expected(chance) -> tries                  expected tries for one hit (1 / chance, math.huge for 0)
-- report = {Scale, Total, TotalWas, FillerChance, Rows = {{Index, Id, Kind, Name, Rarity, Class, Factor, WeightWas,
--           ChanceWas, Weight, Chance, Expected, Filler}}}   (Report() rows: Index, Id, Kind, Name, Rarity, Class,
--           Weight, Chance, Expected)
local DropRates = {}

DropRates.Scale = 1000000

local RESOURCE = { Cash = true, Coins = true, Bones = true, Candy = true, Dust = true, Shards = true, Stone = true }
local RARITIES = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local RARITY_OF = {}
for i, name in ipairs(RARITIES) do
	RARITY_OF[name] = i
end

local function weight(row: any): number
	local w = type(row) == "table" and tonumber(row.Weight) or nil
	if w == nil or w ~= w or w == math.huge or w <= 0 then
		return 0
	end
	return w
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepCopy(x)
	end
	return out
end

function DropRates.Classify(row: any): string
	if type(row) ~= "table" then
		return "Common"
	end
	if RESOURCE[row.Kind] then
		return "Resource"
	end
	if type(row.Rarity) == "string" and RARITY_OF[row.Rarity] then
		return row.Rarity
	end
	local rank = math.clamp(math.floor(tonumber(row.Rank) or 1), 1, #RARITIES)
	return RARITIES[rank]
end

function DropRates.Factor(row: any, factors: { [string]: number }): (number, string)
	local class = DropRates.Classify(row)
	local f = type(factors) == "table" and tonumber(factors[class]) or nil
	if f == nil or f ~= f or f < 0 then
		error("DropRates: no factor for class " .. class, 2)
	end
	return f, class
end

function DropRates.Expected(chance: number): number
	chance = tonumber(chance) or 0
	if chance <= 0 then
		return math.huge
	end
	return 1 / chance
end

local function fillerList(filler: any): { any }
	if type(filler) ~= "table" then
		return {}
	end
	if filler.Kind ~= nil then
		return { filler }
	end
	local out = {}
	for _, row in ipairs(filler) do
		if type(row) == "table" then
			table.insert(out, row)
		end
	end
	return out
end

function DropRates.Rescale(rows: { any }, factors: { [string]: number }, filler: any): ({ any }, any)
	assert(type(rows) == "table", "DropRates.Rescale: rows must be a table")
	local SCALE = DropRates.Scale
	local total = 0
	for _, row in ipairs(rows) do
		total += weight(row)
	end
	assert(total > 0, "DropRates.Rescale: the table has no positive weight")
	local fillers = fillerList(filler)
	assert(#fillers > 0, "DropRates.Rescale: a filler row is required")
	local out = {}
	local report = { Scale = SCALE, Total = SCALE, TotalWas = total, FillerChance = 0, Rows = {} }
	local used = 0
	for i, row in ipairs(rows) do
		local w = weight(row)
		if w > 0 then
			local factor, class = DropRates.Factor(row, factors)
			assert(factor <= 1, "DropRates.Rescale: factor above 1 for class " .. class)
			local chanceWas = w / total
			local exact = chanceWas * factor * SCALE
			local nw = math.floor(exact + .5)
			if nw < 1 and exact > 0 then
				nw = 1 -- a prize never becomes impossible (still within 1e-6 of old x factor)
			end
			local copy = deepCopy(row)
			copy.Weight = nw
			table.insert(out, copy)
			used += nw
			table.insert(report.Rows, { Index = i, Id = row.Id, Kind = row.Kind, Name = row.Name, Rarity = row.Rarity, Class = class,
				Factor = factor, WeightWas = w, ChanceWas = chanceWas, Weight = nw, Chance = nw / SCALE,
				Expected = DropRates.Expected(nw / SCALE), Filler = false })
		end
	end
	local free = SCALE - used
	assert(free >= 0, "DropRates.Rescale: the rescaled rows exceed the scale")
	-- the freed probability: split between the filler rows by their own Weight (equal when none), remainder to the last
	local shares, shareTotal = {}, 0
	for i, row in ipairs(fillers) do
		local s = weight(row)
		shares[i] = s > 0 and s or 1
		shareTotal += shares[i]
	end
	local given = 0
	for i, row in ipairs(fillers) do
		local nw = i == #fillers and (free - given) or math.floor(free * shares[i] / shareTotal)
		given += nw
		if nw > 0 then
			local copy = deepCopy(row)
			copy.Weight = nw
			table.insert(out, copy)
			table.insert(report.Rows, { Index = #rows + i, Id = row.Id, Kind = row.Kind, Name = row.Name, Rarity = row.Rarity,
				Class = DropRates.Classify(row), Factor = 1, WeightWas = 0, ChanceWas = 0, Weight = nw, Chance = nw / SCALE,
				Expected = DropRates.Expected(nw / SCALE), Filler = true })
			report.FillerChance += nw / SCALE
		end
	end
	return out, report
end

function DropRates.Report(rows: { any }): any
	local total = 0
	for _, row in ipairs(rows or {}) do
		total += weight(row)
	end
	local report = { Total = total, Rows = {} }
	for i, row in ipairs(rows or {}) do
		local w = weight(row)
		local chance = total > 0 and w / total or 0
		table.insert(report.Rows, { Index = i, Id = row.Id, Kind = row.Kind, Name = row.Name, Rarity = row.Rarity,
			Class = DropRates.Classify(row), Weight = w, Chance = chance, Expected = DropRates.Expected(chance) })
	end
	return report
end

function DropRates.ScaleChance(chance: number, rows: { any }, factors: { [string]: number }): (number, { number })
	chance = math.clamp(tonumber(chance) or 0, 0, 1)
	local total = 0
	for _, row in ipairs(rows) do
		total += weight(row)
	end
	local abs, sum = {}, 0
	for i, row in ipairs(rows) do
		local share = total > 0 and weight(row) / total or 0
		abs[i] = chance * share * (DropRates.Factor(row, factors))
		sum += abs[i]
	end
	local weights = {}
	for i = 1, #rows do
		weights[i] = sum > 0 and abs[i] / sum or 0
	end
	return sum, weights
end

return DropRates
