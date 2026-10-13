-- Plot decorations (feature module, see Economy.FeatureRegistry). Catalog, slots and prices:
-- ReplicatedStorage.DogEconomy.DecorCatalog; world: Economy.PlotDecorWorld. Docs: docs/PLOT_COSMETICS.md.
--   DecorBuy {Id, Quote?, Slot?}  buys one copy for coins + Stone (+ Bones on Mythic pieces), anywhere.
--                                 Quote = the coin price the window showed. Slot (optional): BUY & PLACE,
--                                 which needs the player in their own yard like DecorPlace.
--   DecorPlace {Slot, Id}         puts an owned copy on a slot of its size (a copy already there goes back)
--   DecorRemove {Slot}            takes the decoration off the slot (it stays owned)
-- Saved data: p.Decor = {Version = 1, Owned = {[id] = count}, Placed = {[slotId] = id}};
-- placed copies of an id never exceed the owned count.
-- Snapshot.Features.Decor = {Version, Owned, Placed, Free = {[id] = n}, Stone, Stage, InYard}.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = ReplicatedStorage:WaitForChild("DogEconomy")
local Catalog = require(Economy:WaitForChild("DecorCatalog"))
local Resources = require(Economy:WaitForChild("Resources"))
local Access = require(ReplicatedStorage:WaitForChild("PlotInteractionAccess"))

local F = { Name = "Decor", Order = 61 }
F.Catalog = Catalog

local MAX_KEY = 40
local MAX_COUNT = 1000

-- True when the owner of p stands inside their own yard. Tests replace this.
function F.Present(p: any): boolean
	local player = type(p) == "table" and type(p.UserId) == "number" and Players:GetPlayerByUserId(p.UserId) or nil
	local yard = player and Access.OwnYard(player)
	return yard ~= nil and Access.InYard(player, yard, 4)
end

local function whole(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= 0 and v <= MAX_COUNT
end

-- Placed copies of every id.
local function placedCounts(placed: any): { [string]: number }
	local counts = {}
	for _, id in pairs(placed) do
		counts[id] = (counts[id] or 0) + 1
	end
	return counts
end
F.PlacedCounts = placedCounts

function F.Normalize(_R, p, _now)
	local data = p.Decor
	if type(data) ~= "table" then
		p.Decor = { Version = Catalog.Version, Owned = {}, Placed = {} }
		return
	end
	if data.Version ~= Catalog.Version then
		data.Version = Catalog.Version
	end
	if type(data.Owned) ~= "table" then
		data.Owned = {}
	end
	if type(data.Placed) ~= "table" then
		data.Placed = {}
	end
	-- Owned: well-formed counts only (unknown ids from a newer build are kept as they are).
	local fix: { any }? = nil
	for id, n in pairs(data.Owned) do
		if type(id) ~= "string" or #id > MAX_KEY then
			fix = fix or {}
			table.insert(fix :: { any }, { id, nil })
		elseif not whole(n) then
			local healed = type(n) == "number" and n == n and math.clamp(math.floor(n), 0, MAX_COUNT) or 0
			fix = fix or {}
			table.insert(fix :: { any }, { id, healed > 0 and healed or nil })
		elseif n == 0 then
			fix = fix or {}
			table.insert(fix :: { any }, { id, nil })
		end
	end
	if fix then
		for _, row in ipairs(fix) do
			data.Owned[row[1]] = row[2]
		end
	end
	-- Placed: a known slot holding a well-formed id that fits it; never more copies than owned.
	local drop: { any }? = nil
	local used: { [string]: number } = {}
	for _, slot in ipairs(Catalog.Slots) do
		local id = data.Placed[slot.Id]
		if id ~= nil then
			local item = type(id) == "string" and Catalog.Get(id) or nil
			local ok = type(id) == "string" and #id <= MAX_KEY and (item == nil or item.Size == slot.Size)
			if ok then
				used[id] = (used[id] or 0) + 1
				ok = used[id] <= (data.Owned[id] or 0)
			end
			if not ok then
				drop = drop or {}
				table.insert(drop :: { any }, slot.Id)
			end
		end
	end
	for key in pairs(data.Placed) do
		if type(key) ~= "string" or not Catalog.SlotById[key] then
			drop = drop or {}
			table.insert(drop :: { any }, key)
		end
	end
	if drop then
		for _, key in ipairs(drop) do
			data.Placed[key] = nil
		end
	end
end

-- Structure only (saving needs string keys and whole counts); nil (a profile that skipped
-- Normalize) passes. Slot / count rules that Normalize heals (a slot of a newer build, more copies
-- placed than owned) are kept by the actions and healed by Normalize, never rejected here.
function F.Validate(R, p)
	local data = p.Decor
	if data == nil then
		return
	end
	R.Check(type(data) == "table" and type(data.Owned) == "table" and type(data.Placed) == "table", "Invalid decor")
	for id, n in pairs(data.Owned) do
		R.Check(type(id) == "string" and #id <= MAX_KEY and whole(n), "Invalid decor count")
	end
	for slot, id in pairs(data.Placed) do
		R.Check(type(slot) == "string" and #slot <= MAX_KEY and type(id) == "string" and #id <= MAX_KEY, "Invalid decor slot")
	end
end

local function slotArg(R, value): any
	local slot = Catalog.Slot(value)
	R.Check(slot ~= nil, "Choose a decor spot")
	return slot
end
local function itemArg(R, value): any
	local item = Catalog.Get(value)
	R.Check(item ~= nil, "Unknown decoration")
	return item
end

local function place(R, p, slot, item)
	local data = p.Decor
	R.Check(item.Size == slot.Size, item.Size == "Large" and "This decoration needs a BIG spot" or "This decoration needs a SMALL spot")
	local current = data.Placed[slot.Id]
	if current == item.Id then
		return
	end
	local counts = placedCounts(data.Placed)
	R.Check((data.Owned[item.Id] or 0) > (counts[item.Id] or 0), "Buy another " .. item.Name .. " first")
	data.Placed[slot.Id] = item.Id
	return current
end

local function buy(R, p, a)
	local item = itemArg(R, a.Id)
	local data = p.Decor
	local ok, stage = Catalog.Unlocked(p, item.Id)
	R.Check(ok, "Unlocks at yard stage " .. stage)
	local owned = data.Owned[item.Id] or 0
	R.Check(owned < Catalog.MaxOwned(item.Id), "You already own one for every " .. (item.Size == "Large" and "big" or "small") .. " spot")
	local cash, stone, bones = Catalog.Price(item.Id)
	if a.Quote ~= nil then
		R.Check(a.Quote == cash, "The price changed: " .. cash .. " Coins now. Check and buy again")
	end
	local slot = a.Slot ~= nil and slotArg(R, a.Slot) or nil
	if slot then
		R.Check(item.Size == slot.Size, item.Size == "Large" and "This decoration needs a BIG spot" or "This decoration needs a SMALL spot")
		R.Check(F.Present(p), "Walk into your yard to place decorations")
	end
	R.Check(Resources.CanSpend(p, { Stone = stone }), "Not enough Stone: " .. stone .. " needed (mine Limestone at your Mining Corner)")
	R.Check((p.Bones or 0) >= bones, "Not enough Bones: " .. bones .. " needed")
	R.Check((p.Cash or 0) >= cash, "Not enough Coins")
	R.Pay(p, cash, bones)
	Resources.Spend(p, { Stone = stone })
	data.Owned[item.Id] = owned + 1
	local replaced = nil
	if slot then
		replaced = place(R, p, slot, item)
		return item.Name .. " placed", { Id = item.Id, Slot = slot.Id, Replaced = replaced, Paid = { Cash = cash, Stone = stone, Bones = bones } }
	end
	return item.Name .. " bought", { Id = item.Id, Paid = { Cash = cash, Stone = stone, Bones = bones } }
end

function F.Action(R, p, action, a, now, _random)
	if action ~= "DecorBuy" and action ~= "DecorPlace" and action ~= "DecorRemove" then
		return nil
	end
	a = type(a) == "table" and a or {}
	F.Normalize(R, p, now)
	if action == "DecorBuy" then
		return buy(R, p, a)
	end
	local slot = slotArg(R, a.Slot)
	R.Check(F.Present(p), "Walk into your yard to place decorations")
	local data = p.Decor
	if action == "DecorRemove" then
		local id = data.Placed[slot.Id]
		R.Check(id ~= nil, "This spot is already empty")
		data.Placed[slot.Id] = nil
		local item = Catalog.Get(id)
		return (item and item.Name or "Decoration") .. " removed", { Slot = slot.Id, Id = id }
	end
	local item = itemArg(R, a.Id)
	local replaced = place(R, p, slot, item)
	return item.Name .. " placed", { Slot = slot.Id, Id = item.Id, Replaced = replaced }
end

function F.Snapshot(_R, p, view, _now)
	local data = type(p.Decor) == "table" and p.Decor or { Owned = {}, Placed = {} }
	local owned, placed, free = {}, {}, {}
	for id, n in pairs(type(data.Owned) == "table" and data.Owned or {}) do
		if Catalog.Get(id) and whole(n) and n > 0 then
			owned[id] = n
		end
	end
	for slot, id in pairs(type(data.Placed) == "table" and data.Placed or {}) do
		if Catalog.SlotById[slot] and Catalog.Get(id) then
			placed[slot] = id
		end
	end
	local counts = placedCounts(placed)
	for id, n in pairs(owned) do
		free[id] = math.max(0, n - (counts[id] or 0))
	end
	local inYard = false
	pcall(function()
		inYard = F.Present(p)
	end)
	view.Decor = {
		Version = Catalog.Version,
		Owned = owned,
		Placed = placed,
		Free = free,
		Stone = Resources.Get(p, "Stone"),
		Stage = Catalog.Stage(p),
		InYard = inYard,
	}
end

return F
