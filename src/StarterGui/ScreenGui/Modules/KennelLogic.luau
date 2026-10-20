-- The pure rules behind the KENNEL window (Modules.KennelScreen), the dog picker of one dig kennel:
-- entries, where a dog is, filters, order, the suggested dog and what the main button does.
-- No instances, no network: tools/test_kennel.luau requires it.
local RS = game:GetService("ReplicatedStorage")
local Economy = RS:WaitForChild("DogEconomy")
local C = require(Economy:WaitForChild("Config"))
local Defs = require(Economy:WaitForChild("DogDefinitions"))

local L = {}

L.Rarities = table.clone(C.Rarities) -- Common .. Secret (rank 1..6)
L.RarityRank = {}
for i, name in ipairs(C.Rarities) do
	L.RarityRank[name] = i
end
L.Variants, L.VariantRank, L.VariantBonus = {}, {}, {}
for i, v in ipairs(C.Variants) do
	table.insert(L.Variants, v.Name)
	L.VariantRank[v.Name] = i
	L.VariantBonus[v.Name] = v.Bonus or 0
end

local function num(v)
	v = tonumber(v)
	if not v or v ~= v then
		return 0
	end
	return v
end

-- Lower case for search, Cyrillic included (string.lower only folds ASCII; same as DogInfo.Fold).
function L.Fold(s)
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

function L.SlotNumber(slotName)
	return tonumber(tostring(slotName or ""):match("^DigSlot_(%d+)$"))
end

-- "+30%" for a variant's income bonus, "" for Normal.
function L.BonusText(variant)
	local b = L.VariantBonus[variant or "Normal"] or 0
	if b <= 0 then
		return ""
	end
	return "+" .. tostring(math.floor(b * 100 + 0.5)) .. "%"
end

-- Where a dog is, seen from kennel `slotName`:
--   "Here"     digging in this kennel          "Other"  digging in kennel OtherSlot
--   "Arriving" walking from the DOG LINE       "Free"   in storage (can be put to work)
function L.Status(d, slotName)
	if d.State == "Walking" then
		return "Arriving", nil
	end
	local assigned = d.AssignedSlot or ""
	if assigned == "" then
		return "Free", nil
	end
	if assigned == slotName then
		return "Here", nil
	end
	return "Other", L.SlotNumber(assigned)
end

-- One card. stats: Snapshot.DogStats[uid] (the dog's potential income even when idle).
function L.Entry(d, stats, slotName, shownName)
	local def = Defs[d.DogId] or {}
	local rarity = def.Rarity or d.Rarity or "Common"
	local variant = d.Variant or "Normal"
	if L.VariantRank[variant] == nil then
		variant = "Normal"
	end
	local status, other = L.Status(d, slotName)
	local s = stats or {}
	local name = shownName or d.DisplayName or def.DisplayName or d.DogId
	return {
		Uid = d.DogUid,
		Dog = d,
		DogId = d.DogId,
		Name = name,
		Rarity = rarity,
		RarityRank = L.RarityRank[rarity] or def.Rank or 0,
		Variant = variant,
		VariantRank = L.VariantRank[variant] or 1,
		Mutated = variant ~= "Normal",
		Bonus = L.VariantBonus[variant] or 0,
		Status = status,
		OtherSlot = other,
		Coins = num(s.CoinsPerMin),
		Efficiency = num(s.Efficiency),
		DigsPerMin = num(s.DigsPerMin),
		Mastery = num(d.Mastery),
		Locked = d.Locked == true,
		Favorite = d.Favorite == true,
		Search = L.Fold(tostring(name) .. " " .. tostring(d.DisplayName or "") .. " " .. tostring(d.DogId or "")),
	}
end

-- Every dog of the profile that belongs to userId, as entries.
function L.Entries(profile, dogStats, slotName, userId, nameOf)
	local list = {}
	for uid, d in pairs(profile and profile.Dogs or {}) do
		if type(d) == "table" and d.DogUid == uid and (userId == nil or d.OwnerUserId == userId) then
			table.insert(list, L.Entry(d, (dogStats or {})[uid], slotName, nameOf and nameOf(d.DogId) or nil))
		end
	end
	return list
end

function L.Occupant(profile, slotName)
	for _, d in pairs(profile and profile.Dogs or {}) do
		if type(d) == "table" and d.AssignedSlot == slotName then
			return d
		end
	end
	return nil
end

-- filter: {Query (L.Fold), Free, Working (either; none = all), Mutated, Rarities = {[name]=true}}
function L.Match(e, f)
	f = f or {}
	if f.Query and f.Query ~= "" and not string.find(e.Search, f.Query, 1, true) then
		return false
	end
	if f.Free or f.Working then
		local free = e.Status == "Free"
		local working = e.Status == "Here" or e.Status == "Other"
		if not ((f.Free and free) or (f.Working and working)) then
			return false
		end
	end
	if f.Mutated and not e.Mutated then
		return false
	end
	if f.Rarities and next(f.Rarities) and not f.Rarities[e.Rarity] then
		return false
	end
	return true
end

-- key: "best" (rarity, then mutation, then income), "income", "mutation" (mutation, then rarity), "name".
-- desc=false reverses the key order (name: A..Z is the default). The dog already in this kennel always
-- comes first and dogs on their way come last, whatever the order.
L.SortKeys = { "best", "income", "mutation", "name" }
function L.Sort(list, key, desc)
	key = key or "best"
	if desc == nil then
		desc = key ~= "name"
	end
	local function group(e)
		if e.Status == "Here" then
			return 0
		elseif e.Status == "Arriving" then
			return 2
		end
		return 1
	end
	-- primary(a, b): -1 a first, 1 b first, 0 tie (best-first order for every key except name)
	local function primary(a, b)
		local function cmp(x, y)
			if x == y then
				return 0
			end
			return x > y and -1 or 1
		end
		if key == "name" then
			local x, y = L.Fold(a.Name), L.Fold(b.Name)
			if x == y then
				return 0
			end
			return x < y and -1 or 1
		elseif key == "income" then
			return cmp(a.Coins, b.Coins)
		elseif key == "mutation" then
			local c = cmp(a.VariantRank, b.VariantRank)
			if c ~= 0 then
				return c
			end
			return cmp(a.RarityRank, b.RarityRank)
		end
		local c = cmp(a.RarityRank, b.RarityRank)
		if c ~= 0 then
			return c
		end
		c = cmp(a.VariantRank, b.VariantRank)
		if c ~= 0 then
			return c
		end
		return cmp(a.Coins, b.Coins)
	end
	local flip = (key == "name") == (desc == true)
	table.sort(list, function(a, b)
		local ga, gb = group(a), group(b)
		if ga ~= gb then
			return ga < gb
		end
		local c = primary(a, b)
		if c ~= 0 then
			if flip then
				return c > 0
			end
			return c < 0
		end
		if a.Coins ~= b.Coins then
			return a.Coins > b.Coins
		end
		if a.Name ~= b.Name then
			return a.Name < b.Name
		end
		return tostring(a.Uid) < tostring(b.Uid)
	end)
	return list
end

-- The dog to preselect when the window opens: the idle dog that earns the most, and with a dog inside
-- only one that earns more than it (nil when none does). Dogs working in another kennel are never
-- suggested: moving one empties its kennel, so the team would earn less, not more.
function L.Suggest(list, occupant)
	local best, coins = nil, occupant and occupant.Coins or -1
	for _, e in ipairs(list) do
		if e.Status == "Free" and e.Coins > coins then
			best, coins = e, e.Coins
		end
	end
	return best
end

-- How the team's income per minute changes when entry e starts work in this kennel (occupant: the entry
-- inside now, or nil). A dog from storage (or one still arriving) adds its income, and the dog inside goes
-- to storage. A dog moved from another kennel earns the same here, but its kennel is left empty, so the
-- team only loses the dog inside. Returns the change and, for a move, the number of the kennel left
-- empty. Returns nil for no entry or for the dog inside itself.
function L.Gain(e, occupant)
	if not e or e.Status == "Here" then
		return nil, nil
	end
	local lost = 0
	if occupant and occupant.Uid ~= e.Uid then
		lost = num(occupant.Coins)
	end
	if e.Status == "Other" then
		return 0 - lost, e.OtherSlot or 0 -- not -lost, which is -0 for an empty kennel
	end
	return num(e.Coins) - lost, nil
end

-- What the main button does for entry e in kennel slotName (occupant: the entry or profile dog there now, or nil).
-- e.Coins says nothing about a move: compare by L.Gain, which counts the kennel a moved dog leaves.
--   Kind: "Assign" | "Swap" | "Move" | "Remove" | "Blocked"
--   Steps: requests in order {Action, Args}; Freed: kennel number another dog leaves (Move)
function L.Plan(e, occupant, slotName)
	if not e then
		return { Kind = "Blocked", Steps = {}, Reason = "Select a dog" }
	end
	if e.Status == "Arriving" then
		return { Kind = "Blocked", Steps = {}, Reason = "Wait until your dog arrives in your yard" }
	end
	if e.Status == "Here" then
		return { Kind = "Remove", Steps = { { "Remove", { Uid = e.Uid } } } }
	end
	local steps = {}
	local occupantUid = occupant and (occupant.Uid or occupant.DogUid) or nil
	if occupantUid and occupantUid ~= e.Uid then
		table.insert(steps, { "Remove", { Uid = occupantUid } })
	else
		occupant = nil
	end
	table.insert(steps, { "Assign", { Uid = e.Uid, Slot = slotName } })
	if e.Status == "Other" then
		return { Kind = "Move", Steps = steps, Freed = e.OtherSlot, Replaced = occupant }
	end
	return { Kind = occupant and "Swap" or "Assign", Steps = steps, Replaced = occupant }
end

return L
