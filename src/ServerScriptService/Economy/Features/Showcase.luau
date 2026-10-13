-- MY BEST FINDS showcase (feature module, see Economy.FeatureRegistry). Rules shared with the
-- stand and the editor: ReplicatedStorage.DogEconomy.ShowcaseRules. Docs: docs/PLOT_COSMETICS.md.
--   ShowcaseSet {Slot = 1..5, Uid = itemUid}  pins an owned find in a case (moving a find clears its old case)
--   ShowcaseClear {Slot = 1..5}               the case goes back to the automatic pick
-- Both need the player at their own showcase (PlotInteractionAccess zone ShowcaseInteractionZone).
-- Saved data: p.Showcase = {Version = 1, Slots = {["1"] = itemUid, ...}}. Normalize drops pins of
-- finds that left the inventory (sold, traded, used): that case shows the automatic pick again.
-- Snapshot.Features.Showcase = {Version, Slots = {[slot] = uid}, Auto = {[slot] = uid}, Capacity,
--   MaxSlots, BonusStage, Exhibits = {[slot] = row}, Pinned = {[uid] = slot}, Near}.
-- Other systems: F.IsPinned(p, uid) -> slot? (sale / trade protection).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("DogEconomy"):WaitForChild("ShowcaseRules"))
local Access = require(ReplicatedStorage:WaitForChild("PlotInteractionAccess"))

local F = { Name = "Showcase", Order = 60 }
F.Rules = Rules
F.IsPinned = Rules.IsPinned

local MAX_UID = 100

-- Where the owner of p stands: true when they are at their own showcase. Tests replace this.
function F.Present(p: any): boolean
	local player = type(p) == "table" and type(p.UserId) == "number" and Players:GetPlayerByUserId(p.UserId) or nil
	if not player then
		return false
	end
	local yard = Access.OwnYard(player)
	local anchor = yard and yard:FindFirstChild("ShowcaseAnchor")
	return anchor ~= nil and Access.CanUse(player, yard, anchor)
end

function F.Normalize(_R, p, _now)
	local data = p.Showcase
	if type(data) ~= "table" then
		p.Showcase = { Version = Rules.Version, Slots = {} }
		return
	end
	if type(data.Slots) ~= "table" then
		data.Slots = {}
	end
	if data.Version ~= Rules.Version then
		data.Version = Rules.Version
	end
	local slots = data.Slots
	local drop: { any }? = nil
	local seen: { [string]: boolean } = {}
	for key, uid in pairs(slots) do
		local index = type(key) == "string" and tonumber(key) or nil
		local ok = index ~= nil and index % 1 == 0 and index >= 1 and index <= Rules.MaxSlots and tostring(index) == key
			and type(uid) == "string" and #uid <= MAX_UID and not seen[uid] and Rules.Owned(p, uid) ~= nil
		if ok then
			seen[uid] = true
		else
			drop = drop or {}
			table.insert(drop :: { any }, key)
		end
	end
	if drop then
		for _, key in ipairs(drop) do
			slots[key] = nil
		end
	end
end

-- Structure only: string keys and uids. A pin of a find that just left the inventory, a
-- duplicate or a case of a newer build are healed by Normalize, never rejected here.
function F.Validate(R, p)
	local data = p.Showcase
	if data == nil then
		return
	end
	R.Check(type(data) == "table" and type(data.Slots) == "table", "Invalid showcase")
	for key, uid in pairs(data.Slots) do
		R.Check(type(key) == "string" and #key <= 4, "Invalid showcase slot")
		R.Check(type(uid) == "string" and #uid <= MAX_UID, "Invalid showcase find")
	end
end

local function slotArg(R, p, value): number
	local index = tonumber(value)
	local capacity = Rules.Capacity(p)
	R.Check(index ~= nil and R.Int(index, 1, Rules.MaxSlots), "Choose a showcase case")
	R.Check((index :: number) <= capacity, "The fifth case opens at yard stage " .. Rules.BonusStage)
	return index :: number
end

function F.Action(R, p, action, a, now, _random)
	if action ~= "ShowcaseSet" and action ~= "ShowcaseClear" then
		return nil
	end
	a = type(a) == "table" and a or {}
	F.Normalize(R, p, now)
	local slot = slotArg(R, p, a.Slot)
	R.Check(F.Present(p), "Walk up to your showcase to change it")
	local slots = p.Showcase.Slots
	local key = tostring(slot)
	if action == "ShowcaseClear" then
		R.Check(slots[key] ~= nil, "This case already shows your best find automatically")
		slots[key] = nil
		return "Case " .. slot .. " shows your best find automatically", { Slot = slot }
	end
	local uid = a.Uid
	R.Check(type(uid) == "string" and #uid >= 1 and #uid <= MAX_UID, "Choose a find")
	local x = Rules.Owned(p, uid)
	R.Check(x ~= nil, "Choose a find you own")
	local moved = nil
	for k, other in pairs(slots) do
		if other == uid and k ~= key then
			slots[k] = nil
			moved = tonumber(k)
		end
	end
	slots[key] = uid
	local name = x.DisplayName or x.ItemId
	return name .. " is on display in case " .. slot, { Slot = slot, Uid = uid, MovedFrom = moved }
end

function F.Snapshot(_R, p, view, _now)
	local layout = Rules.Layout(p)
	local slots, pinned, exhibits = {}, {}, {}
	for i, uid in pairs(layout.Pins) do
		slots[tostring(i)] = uid
		pinned[uid] = i
	end
	local auto = {}
	for i, uid in pairs(layout.Auto) do
		auto[tostring(i)] = uid
	end
	for i, row in pairs(layout.Slots) do
		exhibits[tostring(i)] = row
	end
	local near = false
	pcall(function()
		near = F.Present(p)
	end)
	view.Showcase = {
		Version = Rules.Version,
		Slots = slots,
		Auto = auto,
		Capacity = layout.Capacity,
		MaxSlots = Rules.MaxSlots,
		BonusStage = Rules.BonusStage,
		Exhibits = exhibits,
		Pinned = pinned,
		Near = near,
	}
end

return F
