-- MY BEST FINDS showcase: pure rules shared by the server feature (Economy.Features.Showcase), the
-- world stand (Economy.BestFinds) and the editor window (Modules.ShowcaseScreen).
-- Saved data (Features.Showcase): p.Showcase = {Version = 1, Slots = {["1"] = itemUid, ...}}.
-- A slot holds one owned find the player pinned; every slot without a pin is filled automatically
-- with the next best find (owned finds and the player's find records, rarest first). Docs:
-- docs/PLOT_COSMETICS.md.
--   ShowcaseRules.Capacity(p)            4 cases, 5 from yard stage 5 (PlotCatalog.Level)
--   ShowcaseRules.Pins(p)                {[slot] = uid} of owned, unique pins within capacity
--   ShowcaseRules.IsPinned(p, uid)       slot number or nil (sell / trade protection)
--   ShowcaseRules.Layout(p)              {Slots = {[i] = row}, Auto = {[i] = uid}, Capacity}
--   ShowcaseRules.Rarity(itemId)         "Common" .. "Secret" (ItemValuation rules)
--   ShowcaseRules.Effect(rarity, mut)    the case effect tier (Common .. Secret, "Mythic" for top mutations)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = ReplicatedStorage:WaitForChild("DogEconomy")
local ItemDefinitions = require(Economy:WaitForChild("ItemDefinitions"))
local ValueConfig = require(ReplicatedStorage:WaitForChild("ItemValueConfig"))
local PlotCatalog = require(ReplicatedStorage:WaitForChild("PlotCatalog"))

local S = {}
S.Version = 1
S.MaxSlots = 5
S.BaseSlots = 4
S.BonusStage = 5 -- yard stage that opens the fifth (crown) case
S.RarityRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }
-- Mutations that lift a Legendary find to the animated "Mythic" aura.
S.TopMutations = { RAINBOW = true, GLITCHED = true, VOID = true, CORRUPTED = true, CURSED = true, ["BLOOD MOON"] = true, ECLIPSED = true }
-- Effect / nameplate colours per tier (the UI kit rarity colours, Kit.Theme.Rarity).
S.Colors = {
	Common = Color3.fromRGB(170, 190, 205),
	Uncommon = Color3.fromRGB(125, 219, 48),
	Rare = Color3.fromRGB(38, 164, 243),
	Epic = Color3.fromRGB(161, 103, 242),
	Legendary = Color3.fromRGB(249, 180, 35),
	Mythic = Color3.fromRGB(247, 73, 112),
	Secret = Color3.fromRGB(230, 115, 245),
}

function S.Capacity(p: any): number
	local level = 1
	if type(p) == "table" then
		local ok, value = pcall(PlotCatalog.Level, p)
		level = ok and tonumber(value) or 1
	end
	return level >= S.BonusStage and S.MaxSlots or S.BaseSlots
end

local rarityCache: { [string]: string } = {}
function S.Rarity(itemId: any): string
	if type(itemId) ~= "string" then
		return "Common"
	end
	local cached = rarityCache[itemId]
	if cached then
		return cached
	end
	local def = ItemDefinitions[itemId]
	local rarity = "Common"
	if def then
		if def.Class == "Secret" then
			rarity = "Secret"
		else
			for _, row in ipairs(ValueConfig.Rarity) do
				if (tonumber(def.BaseDropChance) or 1) <= row.MaxChance then
					rarity = row.Name
					break
				end
			end
		end
	end
	rarityCache[itemId] = rarity
	return rarity
end

function S.Effect(rarity: string?, mutation: string?): string
	local r = rarity or "Common"
	if r == "Legendary" and S.TopMutations[string.upper(tostring(mutation or ""))] then
		return "Mythic"
	end
	return S.RarityRank[r] and r or "Common"
end

local function mutationFactor(x: any): number
	return tonumber(ValueConfig.Mutation[string.upper(tostring(x.Mutation or "NORMAL"))]) or 1
end

-- true when find a ranks above find b: rarity, then mutation, then value, then weight, then uid.
function S.Better(a: any, b: any): boolean
	local ra, rb = S.RarityRank[S.Rarity(a.ItemId)] or 0, S.RarityRank[S.Rarity(b.ItemId)] or 0
	if ra ~= rb then
		return ra > rb
	end
	local ma, mb = mutationFactor(a), mutationFactor(b)
	if ma ~= mb then
		return ma > mb
	end
	local va, vb = tonumber(a.SellValue) or 0, tonumber(b.SellValue) or 0
	if va ~= vb then
		return va > vb
	end
	local wa, wb = tonumber(a.WeightKg) or 0, tonumber(b.WeightKg) or 0
	if wa ~= wb then
		return wa > wb
	end
	return tostring(a.ItemUid) < tostring(b.ItemUid)
end

local function owned(p: any, uid: any): any
	local items = type(p) == "table" and p.Items
	local x = type(uid) == "string" and type(items) == "table" and items[uid] or nil
	if type(x) == "table" and x.ItemUid == uid and (x.OwnerUserId == nil or x.OwnerUserId == p.UserId) and ItemDefinitions[x.ItemId] then
		return x
	end
	return nil
end
S.Owned = owned

-- Pins that are still valid: owned, unique, inside capacity. Never writes to p.
function S.Pins(p: any): { [number]: string }
	local out: { [number]: string } = {}
	local data = type(p) == "table" and p.Showcase
	local slots = type(data) == "table" and data.Slots
	if type(slots) ~= "table" then
		return out
	end
	local capacity = S.Capacity(p)
	local seen: { [string]: boolean } = {}
	for i = 1, capacity do
		local uid = slots[tostring(i)]
		if type(uid) == "string" and not seen[uid] and owned(p, uid) then
			seen[uid] = true
			out[i] = uid
		end
	end
	return out
end

function S.IsPinned(p: any, uid: any): number?
	if type(uid) ~= "string" then
		return nil
	end
	local data = type(p) == "table" and p.Showcase
	local slots = type(data) == "table" and data.Slots
	if type(slots) ~= "table" then
		return nil
	end
	for i = 1, S.MaxSlots do
		if slots[tostring(i)] == uid then
			return i
		end
	end
	return nil
end

-- Candidates for automatic slots: owned finds and the find records of p.Stats (trophy copies
-- of finds that may since have been sold), best first, at most `limit`, skipping `exclude` uids.
local RECORDS = { "BestShowcaseFind", "BestShowcaseRelic", "MostValuable", "Heaviest", "Rarest" }
function S.Candidates(p: any, exclude: { [string]: boolean }?, limit: number?): { any }
	local top: { any } = {}
	local n = limit or S.MaxSlots
	local seen: { [string]: boolean } = {}
	local function offer(x: any)
		if type(x) ~= "table" or type(x.ItemUid) ~= "string" or not ItemDefinitions[x.ItemId] then
			return
		end
		if seen[x.ItemUid] or (exclude and exclude[x.ItemUid]) then
			return
		end
		seen[x.ItemUid] = true
		if #top >= n and not S.Better(x, top[#top]) then
			return
		end
		local at = #top + 1
		for i, y in ipairs(top) do
			if S.Better(x, y) then
				at = i
				break
			end
		end
		table.insert(top, at, x)
		if #top > n then
			table.remove(top)
		end
	end
	if type(p) == "table" and type(p.Items) == "table" then
		for uid, x in pairs(p.Items) do
			if owned(p, uid) then
				offer(x)
			end
		end
	end
	local stats = type(p) == "table" and p.Stats
	if type(stats) == "table" then
		for _, key in ipairs(RECORDS) do
			offer(stats[key])
		end
	end
	return top
end

-- What every case shows. Slots[i] = {Uid, ItemId, DisplayName, Mutation, WeightKg, SellValue,
-- Rarity, Effect, Pinned, Auto, Owned} or nil (nothing to show yet).
function S.Layout(p: any): any
	local capacity = S.Capacity(p)
	local pins = S.Pins(p)
	local used: { [string]: boolean } = {}
	for _, uid in pairs(pins) do
		used[uid] = true
	end
	local free = 0
	for i = 1, capacity do
		if not pins[i] then
			free += 1
		end
	end
	local auto = free > 0 and S.Candidates(p, used, free) or {}
	local slots, autoUids = {}, {}
	local nextAuto = 1
	for i = 1, capacity do
		local x, pinned = nil, false
		if pins[i] then
			x, pinned = owned(p, pins[i]), true
		else
			x = auto[nextAuto]
			nextAuto += 1
			if x then
				autoUids[i] = x.ItemUid
			end
		end
		if x then
			local rarity = S.Rarity(x.ItemId)
			slots[i] = {
				Slot = i,
				Uid = x.ItemUid,
				ItemId = x.ItemId,
				DisplayName = x.DisplayName or (ItemDefinitions[x.ItemId] and ItemDefinitions[x.ItemId].DisplayName) or x.ItemId,
				Mutation = string.upper(tostring(x.Mutation or "NORMAL")),
				WeightKg = tonumber(x.WeightKg) or 0,
				SellValue = tonumber(x.SellValue) or 0,
				Rarity = rarity,
				Effect = S.Effect(rarity, x.Mutation),
				Pinned = pinned,
				Auto = not pinned,
				Owned = owned(p, x.ItemUid) ~= nil,
			}
		end
	end
	return { Slots = slots, Auto = autoUids, Pins = pins, Capacity = capacity }
end

return S
