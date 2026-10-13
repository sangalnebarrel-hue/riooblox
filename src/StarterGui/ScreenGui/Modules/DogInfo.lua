-- Pure logic behind the MY DOGS and DOGDEX windows (Modules.DogsScreen / Modules.DogdexScreen):
-- filtering, sorting and comparing dogs, the bonuses of one dog, where a species comes from and the
-- states of the Dogdex rewards. No instances and no network: tests/dogdex.luau runs it in Lune.
-- Numbers come from the server (Snapshot.DogStats for owned dogs, Snapshot.Features.Dogdex.Stats for
-- species); the formulas here only mirror what the rules already apply (Rules.Bonus, Engine:LineOdds).
local RS = game:GetService("ReplicatedStorage")
local Economy = RS:WaitForChild("DogEconomy")
local C = require(Economy:WaitForChild("Config"))
local Defs = require(Economy:WaitForChild("DogDefinitions"))
local Rewards = require(Economy:WaitForChild("DexRewards"))
local Blocks = require(RS:WaitForChild("LuckyBlockConfig"))

local Info = {}

Info.Rarities = table.clone(C.Rarities)
Info.Variants = {}
Info.VariantBonus = {}
Info.VariantBit = {}
for i, v in ipairs(C.Variants) do
	table.insert(Info.Variants, v.Name)
	Info.VariantBonus[v.Name] = v.Bonus or 0
	Info.VariantBit[v.Name] = 2 ^ (i - 1)
end

local RARITY_RANK = {}
for i, name in ipairs(C.Rarities) do
	RARITY_RANK[name] = i
end
function Info.RarityRank(name: any): number
	return RARITY_RANK[name] or 0
end

-- Every species of the catalogue in Dogdex order (#1 ... #100, then the bonus dogs).
Info.Species = {}
Info.MuseumTotal = 0
for _, def in pairs(Defs) do
	if type(def) == "table" and def.Id and def.Rank and not def.Reserved then
		table.insert(Info.Species, def)
		if not def.MuseumExcluded and (def.Index or 0) >= 1 and (def.Index or 0) <= 100 then
			Info.MuseumTotal += 1
		end
	end
end
table.sort(Info.Species, function(a, b)
	local x, y = a.MuseumExcluded and 1 or 0, b.MuseumExcluded and 1 or 0
	if x ~= y then
		return x < y
	end
	return (a.Index or 0) < (b.Index or 0)
end)

-- Lower case for search, Cyrillic included (string.lower only folds ASCII).
function Info.Fold(s: any): string
	local out = {}
	for _, code in utf8.codes(tostring(s or "")) do
		if code >= 0x410 and code <= 0x42F then
			code += 0x20
		elseif code == 0x401 then
			code = 0x451
		elseif code >= 65 and code <= 90 then
			code += 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

-- Upper case, Cyrillic included.
function Info.Upper(s: any): string
	local out = {}
	for _, code in utf8.codes(tostring(s or "")) do
		if code >= 0x430 and code <= 0x44F then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401
		elseif code >= 97 and code <= 122 then
			code -= 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

------------------------------------------------------------------------------------------------
-- One owned dog
------------------------------------------------------------------------------------------------
function Info.Slot(d: any): number?
	return tonumber(tostring(d and d.AssignedSlot or ""):match("^DigSlot_(%d+)$"))
end

-- "Digging" (in a kennel), "Arriving" (walking from the DOG LINE) or "Idle".
function Info.State(d: any): string
	if type(d) ~= "table" then
		return "Idle"
	end
	if d.State == "Walking" then
		return "Arriving"
	end
	if (d.AssignedSlot or "") ~= "" then
		return "Digging"
	end
	return "Idle"
end

-- Income bonuses of the dog itself, as Rules.Bonus applies them (fractions: .3 = +30%).
function Info.Bonus(d: any): any
	local variant = Info.VariantBonus[d and d.Variant or "Normal"] or 0
	local mastery = math.clamp(tonumber(d and d.Mastery) or 0, 0, 100) * 0.0015
	local level = math.clamp(math.floor(tonumber(d and d.AscensionLevel) or 0), 0, #C.Ascension - 1)
	local ascension = C.Ascension[level + 1] or 0
	return { Variant = variant, Mastery = mastery, Ascension = ascension, Total = variant + mastery + ascension }
end

-- Rarity power: multiplies the value of every loot roll (Config.Power by rank).
function Info.Power(def: any): number
	return def and (def.PowerBudget or C.Power[def.Rank or 1]) or 1
end

-- A list entry for MY DOGS. name: the display name as the player reads it (auto-translated).
function Info.Entry(d: any, stats: any, name: string?): any
	local def = Defs[d.DogId] or {}
	local display = name or d.DisplayName or def.DisplayName or d.DogId
	return {
		Uid = d.DogUid,
		Dog = d,
		Def = def,
		Stats = stats or {},
		Name = display,
		Rank = def.Rank or Info.RarityRank(d.Rarity),
		Search = Info.Fold(display .. " " .. tostring(d.DisplayName or "") .. " " .. tostring(d.DogId or "")),
	}
end

-- filter: {Query (folded), States = {Digging, Idle: either; Locked, Favorite: only those},
--          Rarities = {[name]=true} (any of them), Variant = "Any" | "Mutated" | variant name}
function Info.Match(entry: any, filter: any): boolean
	local f = filter or {}
	local d = entry.Dog
	if f.Query and f.Query ~= "" and not string.find(entry.Search, f.Query, 1, true) then
		return false
	end
	local states = f.States or {}
	if states.Digging or states.Idle then
		local state = Info.State(d)
		local digging = state == "Digging"
		if not ((states.Digging and digging) or (states.Idle and not digging)) then
			return false
		end
	end
	if states.Locked and d.Locked ~= true then
		return false
	end
	if states.Favorite and d.Favorite ~= true then
		return false
	end
	if f.Rarities and next(f.Rarities) and not f.Rarities[entry.Def.Rarity or d.Rarity] then
		return false
	end
	local variant = f.Variant or "Any"
	if variant == "Mutated" then
		if (d.Variant or "Normal") == "Normal" then
			return false
		end
	elseif variant ~= "Any" and (d.Variant or "Normal") ~= variant then
		return false
	end
	return true
end

local function num(v: any): number
	v = tonumber(v)
	if not v or v ~= v then
		return 0
	end
	return v
end

-- Sort keys: rarity, efficiency, income, speed, newest, mastery, name. desc = best / newest first.
Info.SortKeys = { "rarity", "efficiency", "income", "speed", "newest", "mastery", "name" }
function Info.SortEntries(list: { any }, key: string?, desc: boolean?): { any }
	key = key or "rarity"
	local function value(e): any
		local s = e.Stats
		if key == "rarity" then
			return e.Rank * 1000 + math.min(999, num(s.Efficiency) * 10)
		elseif key == "efficiency" then
			return num(s.Efficiency)
		elseif key == "income" then
			return num(s.CoinsPerMin)
		elseif key == "speed" then
			return num(s.DigsPerMin)
		elseif key == "newest" then
			return num(e.Dog.CreatedAt)
		elseif key == "mastery" then
			return num(e.Dog.Mastery)
		end
		return nil
	end
	local keyed = {}
	for i, e in ipairs(list) do
		keyed[i] = { E = e, V = value(e), N = Info.Fold(e.Name) }
	end
	table.sort(keyed, function(a, b)
		if key == "name" then
			if a.N ~= b.N then
				if desc then
					return a.N > b.N
				end
				return a.N < b.N
			end
		elseif a.V ~= b.V then
			if desc then
				return a.V > b.V
			end
			return a.V < b.V
		end
		if a.N ~= b.N then
			return a.N < b.N
		end
		return tostring(a.E.Uid) < tostring(b.E.Uid)
	end)
	local out = table.create(#keyed)
	for i, k in ipairs(keyed) do
		out[i] = k.E
	end
	return out
end

-- Side by side: rows {Id, A, B, Better = "a" | "b" | nil, Lower (lower is better)} and the overall
-- winner (more coins per minute, then efficiency). a, b: entries (Info.Entry).
Info.CompareRows = {
	{ Id = "income", Get = function(e) return num(e.Stats.CoinsPerMin) end },
	{ Id = "efficiency", Get = function(e) return num(e.Stats.Efficiency) end },
	{ Id = "speed", Get = function(e) return num(e.Stats.DigsPerMin) end },
	{ Id = "luck", Get = function(e) return num(e.Stats.LuckPct) end },
	{ Id = "finds", Get = function(e) return num(e.Stats.ItemFindsPerMin) end },
	{ Id = "power", Get = function(e) return Info.Power(e.Def) end },
	{ Id = "variant", Get = function(e) return Info.Bonus(e.Dog).Variant end },
	{ Id = "mastery", Get = function(e) return num(e.Dog.Mastery) end },
	{ Id = "ascension", Get = function(e) return num(e.Dog.AscensionLevel) end },
}
function Info.Compare(a: any, b: any): any
	local rows = {}
	for _, spec in ipairs(Info.CompareRows) do
		local x, y = spec.Get(a), spec.Get(b)
		local better = nil
		local tolerance = math.max(math.abs(x), math.abs(y)) * 1e-3 + 1e-9
		if math.abs(x - y) > tolerance then
			if spec.Lower then
				better = x < y and "a" or "b"
			else
				better = x > y and "a" or "b"
			end
		end
		table.insert(rows, { Id = spec.Id, A = x, B = y, Better = better })
	end
	local ia, ib = num(a.Stats.CoinsPerMin), num(b.Stats.CoinsPerMin)
	local winner = nil
	if math.abs(ia - ib) > math.max(ia, ib) * 1e-3 + 1e-9 then
		winner = ia > ib and "a" or "b"
	else
		local ea, eb = num(a.Stats.Efficiency), num(b.Stats.Efficiency)
		if math.abs(ea - eb) > 1e-3 then
			winner = ea > eb and "a" or "b"
		end
	end
	local high, low = math.max(ia, ib), math.min(ia, ib)
	return { Rows = rows, Winner = winner, IncomeGain = low > 0 and high / low - 1 or nil }
end

------------------------------------------------------------------------------------------------
-- Species (Dogdex)
------------------------------------------------------------------------------------------------
-- Chance that one dog walking the DOG LINE is this species (Engine:LineOdds without server luck).
function Info.LineChance(def: any): number?
	if type(def) ~= "table" or def.CanSpawnOnLine ~= true then
		return nil
	end
	local total = 0
	for _, w in ipairs(C.Weights) do
		total += w
	end
	local shares, mine = 0, def.LineWeight or 1
	for _, other in pairs(Defs) do
		if type(other) == "table" and other.Rank == def.Rank and other.CanSpawnOnLine == true and not other.Reserved then
			shares += other.LineWeight or 1
		end
	end
	if total <= 0 or shares <= 0 then
		return nil
	end
	return (C.Weights[def.Rank] or 0) / total * mine / shares
end

-- Where a species comes from: {Key = "Line" | "Lucky" | "Machine" | "Jackpot" | "Trade", Chance?, Tiers?}.
function Info.Sources(def: any): { any }
	local out = {}
	if type(def) ~= "table" then
		return out
	end
	local line = Info.LineChance(def)
	if line then
		table.insert(out, { Key = "Line", Chance = line })
	end
	if def.CanDropFromLuckyBlock == true then
		local tiers = {}
		for _, tier in ipairs(Blocks.Rarities) do
			local row = Blocks.RewardPools[tier]
			if row and (row[def.Rank] or 0) > 0 then
				table.insert(tiers, tier)
			end
		end
		if #tiers > 0 then
			table.insert(out, { Key = "Lucky", Tiers = tiers })
		end
	end
	if def.Jackpot or (def.Acquisition == "RouletteOnly") then
		table.insert(out, { Key = "Jackpot" })
	elseif def.CanDropFromRoulette == true then
		table.insert(out, { Key = "Machine" })
	end
	table.insert(out, { Key = "Trade" })
	return out
end

-- Dogdex grid entries. dex: snapshot.Features.Dogdex (may be nil); names: DogId -> display name.
function Info.SpeciesEntries(profile: any, dex: any, names: any): { any }
	local owned, best = {}, {}
	for _, d in pairs(profile and profile.Dogs or {}) do
		if type(d) == "table" and d.DogId then
			owned[d.DogId] = (owned[d.DogId] or 0) + 1
			best[d.DogId] = math.max(best[d.DogId] or 0, num(d.Mastery))
		end
	end
	local known = profile and profile.DogDex or {}
	local favorites = profile and profile.DexFavorites or {}
	local stats = dex and dex.DexStats or {}
	local out = {}
	for _, def in ipairs(Info.Species) do
		local name = (names and names[def.Id]) or def.DisplayName
		local found = known[def.Id] == true
		table.insert(out, {
			Id = def.Id,
			Def = def,
			Found = found,
			Owned = owned[def.Id] or 0,
			BestMastery = best[def.Id] or 0,
			Favorite = favorites[def.Id] == true,
			Stats = found and stats[def.Id] or nil,
			Name = name,
			Search = found and Info.Fold(name .. " " .. def.DisplayName .. " " .. def.Id) or "",
		})
	end
	return out
end

-- filter: {Query, Found / Missing (either), Favorite, Owned (only those), Rarities}. Undiscovered dogs
-- never match a name search (their names are secret).
function Info.MatchSpecies(entry: any, filter: any): boolean
	local f = filter or {}
	if f.Query and f.Query ~= "" then
		local hit = entry.Found and string.find(entry.Search, f.Query, 1, true) ~= nil
		local number = tonumber(f.Query)
		if not hit and not (number and entry.Def.Index == number) then
			return false
		end
	end
	if f.Found or f.Missing then
		if not ((f.Found and entry.Found) or (f.Missing and not entry.Found)) then
			return false
		end
	end
	if f.Favorite and not entry.Favorite then
		return false
	end
	if f.Owned and entry.Owned <= 0 then
		return false
	end
	if f.Rarities and next(f.Rarities) and not f.Rarities[entry.Def.Rarity] then
		return false
	end
	return true
end

-- Sort keys: number, rarity, name, income, efficiency. Undiscovered dogs have no stats: last.
Info.SpeciesSortKeys = { "number", "rarity", "name", "income", "efficiency" }
function Info.SortSpecies(list: { any }, key: string?, desc: boolean?): { any }
	key = key or "number"
	local function order(e): number
		return (e.Def.MuseumExcluded and 1000 or 0) + (e.Def.Index or 0)
	end
	local function value(e): any
		if key == "rarity" then
			return e.Def.Rank or 0
		elseif key == "income" then
			return e.Stats and num(e.Stats.C) or nil
		elseif key == "efficiency" then
			return e.Stats and num(e.Stats.E) or nil
		elseif key == "name" then
			return e.Found and Info.Fold(e.Name) or nil
		end
		return order(e)
	end
	local keyed = {}
	for i, e in ipairs(list) do
		keyed[i] = { E = e, V = value(e), O = order(e) }
	end
	table.sort(keyed, function(a, b)
		if a.V == nil or b.V == nil then
			if (a.V == nil) ~= (b.V == nil) then
				return a.V ~= nil
			end
		elseif a.V ~= b.V then
			if desc then
				return a.V > b.V
			end
			return a.V < b.V
		end
		return a.O < b.O
	end)
	local out = table.create(#keyed)
	for i, k in ipairs(keyed) do
		out[i] = k.E
	end
	return out
end

-- Variants in a VariantDex mask (or a {[name]=true} table): {[name]=true} and how many.
function Info.VariantsOf(value: any): (any, number)
	local set, n = {}, 0
	if type(value) == "number" then
		for name, bit in pairs(Info.VariantBit) do
			if math.floor(value / bit) % 2 == 1 then
				set[name] = true
				n += 1
			end
		end
	elseif type(value) == "table" then
		for _, name in ipairs(Info.Variants) do
			if value[name] == true then
				set[name] = true
				n += 1
			end
		end
	end
	return set, n
end

-- Museum count: discovered dogs #1-#100 (Rules.MuseumCount).
function Info.MuseumCount(profile: any): number
	local n = 0
	for id, known in pairs(profile and profile.DogDex or {}) do
		local def = Defs[id]
		if known == true and def and not def.MuseumExcluded and (def.Index or 0) >= 1 and (def.Index or 0) <= 100 then
			n += 1
		end
	end
	return n
end

-- Reward track rows: {Tier, Count, State = "claimed" | "ready" | "locked", Coins, Missing}.
-- dex: snapshot.Features.Dogdex (server states and coin amounts); profile is the fallback.
function Info.RewardRows(dex: any, profile: any): ({ any }, number)
	local count = dex and tonumber(dex.Count) or Info.MuseumCount(profile)
	local server = {}
	for _, row in ipairs(dex and dex.Rewards or {}) do
		server[row.Count] = row
	end
	local claims = profile and profile.DexClaims or {}
	local rows = {}
	for _, tier in ipairs(Rewards.Tiers) do
		local s = server[tier.Count]
		local claimed
		if s then
			claimed = s.Claimed == true
		else
			claimed = claims[tostring(tier.Count)] == true
		end
		local state = claimed and "claimed" or (count >= tier.Count and "ready" or "locked")
		table.insert(rows, {
			Tier = tier,
			Count = tier.Count,
			State = state,
			Coins = s and tonumber(s.Coins) or nil,
			Missing = math.max(0, tier.Count - count),
		})
	end
	return rows, count
end

-- Claimable tiers and the next locked one.
function Info.RewardSummary(rows: { any }): (number, any)
	local ready, nextLocked = 0, nil
	for _, row in ipairs(rows) do
		if row.State == "ready" then
			ready += 1
		elseif row.State == "locked" and not nextLocked then
			nextLocked = row
		end
	end
	return ready, nextLocked
end

return Info
