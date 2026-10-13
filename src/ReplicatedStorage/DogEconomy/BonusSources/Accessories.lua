-- Bonus source: PLAYER ACCESSORIES (p.Equipment.Accessories, Features.Equipment). An equipped
-- accessory (Slot = its definition's slot) adds its stat to the player-wide totals: every dog
-- and the player's earnings. One accessory per slot (Hat, Face, Back, Aura).
-- Pure and nil-safe: a missing or half-written p.Equipment adds nothing.
local Equipment = require(script.Parent.Parent.EquipmentDefinitions)

local S = { Name = "Accessories" }

-- The equipped accessory per slot: {[slot] = entry}. Deterministic (lowest Uid) even before
-- Normalize resolves two accessories claiming one slot.
function S.Equipped(p: any): { [string]: any }
	local result = {}
	local eq = type(p) == "table" and p.Equipment
	local list = type(eq) == "table" and eq.Accessories
	if type(list) ~= "table" then
		return result
	end
	local uids = {}
	for uid, a in pairs(list) do
		if type(a) == "table" and type(a.Slot) == "string" then
			local def = Equipment.AccessoryById[a.Id]
			if def and def.Slot == a.Slot then
				local key = tostring(a.Uid or uid)
				local current = result[a.Slot]
				if not current or key < uids[a.Slot] then
					result[a.Slot] = a
					uids[a.Slot] = key
				end
			end
		end
	end
	return result
end

-- Player-wide totals: {[stat] = value} (also used by the UI).
function S.Totals(p: any): { [string]: number }
	local totals = {}
	for _, a in pairs(S.Equipped(p)) do
		local def = Equipment.AccessoryById[a.Id]
		if def then
			totals[def.Stat] = (totals[def.Stat] or 0) + Equipment.Value(a)
		end
	end
	return totals
end

function S.Global(p, _now, add)
	for stat, value in pairs(S.Totals(p)) do
		add(stat, value)
	end
end

return S
