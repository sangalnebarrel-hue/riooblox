-- Bonus source: DOG ARTIFACTS (p.Equipment.Artifacts, Features.Equipment). An artifact only helps
-- the dog it is equipped on (DogUid) and only in a slot that dog has (EquipmentDefinitions.DogSlots
-- by rank). Several artifacts with the same stat on one dog add up to E.ArtifactCaps[stat].
-- Pure and nil-safe: a missing or half-written p.Equipment adds nothing.
local Equipment = require(script.Parent.Parent.EquipmentDefinitions)
local DogDefinitions = require(script.Parent.Parent.DogDefinitions)

local S = { Name = "Artifacts" }

-- {[DogUid] = {artifact, ...}} for one Artifacts table, rebuilt when the table or its revision
-- (p.Equipment.Rev, bumped by every equipment change) differs. Bonuses.For runs once per dog.
local cache = setmetatable({}, { __mode = "k" })
local function byDog(eq: any): any
	local artifacts = eq.Artifacts
	if type(artifacts) ~= "table" then
		return nil
	end
	local rev = tonumber(eq.Rev) or 0
	local hit = cache[artifacts]
	if hit and hit.Rev == rev then
		return hit.Index
	end
	local index = {}
	for uid, a in pairs(artifacts) do
		if type(a) == "table" and type(a.DogUid) == "string" then
			local list = index[a.DogUid]
			if not list then
				list = {}
				index[a.DogUid] = list
			end
			table.insert(list, { Uid = tostring(a.Uid or uid), Entry = a })
		end
	end
	-- One deterministic winner per slot, even before Normalize resolves a doubled slot.
	for _, list in pairs(index) do
		table.sort(list, function(x, y)
			return x.Uid < y.Uid
		end)
	end
	cache[artifacts] = { Rev = rev, Index = index }
	return index
end

-- Totals of one dog: {[stat] = value} after the per-dog caps (also used by the UI).
function S.Totals(p: any, d: any): { [string]: number }
	local totals = {}
	if type(p) ~= "table" or type(d) ~= "table" or type(p.Equipment) ~= "table" or type(d.DogUid) ~= "string" then
		return totals
	end
	local index = byDog(p.Equipment)
	local list = index and index[d.DogUid]
	if not list then
		return totals
	end
	local slots = Equipment.DogSlots(DogDefinitions[d.DogId] or d)
	local used = {}
	for _, row in ipairs(list) do
		local a = row.Entry
		local slot = tonumber(a.Slot)
		local def = Equipment.ArtifactById[a.Id]
		if def and slot and slot % 1 == 0 and slot >= 1 and slot <= slots and not used[slot] then
			used[slot] = true
			totals[def.Stat] = (totals[def.Stat] or 0) + Equipment.Value(a)
		end
	end
	for stat, value in pairs(totals) do
		totals[stat] = math.min(value, Equipment.ArtifactCaps[stat] or value)
	end
	return totals
end

function S.Dog(p, d, _now, add)
	for stat, value in pairs(S.Totals(p, d)) do
		add(stat, value)
	end
end

return S
