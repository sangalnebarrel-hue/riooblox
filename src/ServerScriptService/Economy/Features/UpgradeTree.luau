-- UPGRADE TREE purchases (feature module, see Economy.FeatureRegistry). Definitions, prices, gates
-- and prerequisites: ReplicatedStorage.DogEconomy.UpgradeTree; stat effects: BonusSources.UpgradeTree.
--   TreeUpgrade {Node=id, Level=n?}  buys the next level of a node. Level (optional) is the level the
--                                    client showed: a stale window cannot buy a level it did not show.
--   Upgrade {Kind=id}                the old action of DOG TRAINING / ESTATE UPGRADES, same rules.
-- Purchases work anywhere (no workshop or shop visit). Saved data:
--   p.Upgrades[nodeId] = level   (the original six keys keep their meaning: no migration)
--   p.UpgradeTreeVersion          version of the tree data (DogEconomy.UpgradeTree.Version)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tree = require(ReplicatedStorage:WaitForChild("DogEconomy"):WaitForChild("UpgradeTree"))
local PlotCatalog = require(ReplicatedStorage:WaitForChild("PlotCatalog"))

local F = { Name = "UpgradeTree", Order = 20 }

-- Keys of nodes this build does not define (a node added by a later build, then a rollback) are kept
-- as they are when they look like a level.
local UNKNOWN_MAX = 1000
local MAX_KEY = 40

local function finite(v)
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end

-- Keeps p.Upgrades well-formed. Valid levels are never changed; only malformed entries are healed.
function F.Normalize(_R, p, _now)
	if type(p.Upgrades) ~= "table" then
		p.Upgrades = {}
	end
	local upgrades = p.Upgrades
	local changes = nil
	for key, value in pairs(upgrades) do
		local node = type(key) == "string" and Tree.Nodes[key] or nil
		local healed = nil -- nil: drop the entry
		if type(key) == "string" and #key <= MAX_KEY then
			if finite(value) then
				healed = math.clamp(math.floor(value), 0, node and node.Max or UNKNOWN_MAX)
			elseif node then
				healed = 0
			end
		end
		if healed ~= value then
			changes = changes or {}
			table.insert(changes, { Key = key, Value = healed })
		end
	end
	if changes then
		for _, change in ipairs(changes) do
			upgrades[change.Key] = change.Value
		end
	end
	if not finite(p.UpgradeTreeVersion) or p.UpgradeTreeVersion < Tree.Version then
		p.UpgradeTreeVersion = Tree.Version
	end
end

-- Structure only. A profile that has not been normalized yet (nil Upgrades / version) passes.
function F.Validate(R, p)
	if p.Upgrades == nil then
		return
	end
	R.Check(type(p.Upgrades) == "table", "Invalid upgrades")
	for key, value in pairs(p.Upgrades) do
		R.Check(type(key) == "string" and #key <= MAX_KEY, "Invalid upgrade key")
		local node = Tree.Nodes[key]
		R.Check(R.Int(value, 0, node and node.Max or UNKNOWN_MAX), "Invalid upgrade level")
	end
	R.Check(p.UpgradeTreeVersion == nil or finite(p.UpgradeTreeVersion), "Invalid upgrade tree version")
end

function F.Action(R, p, action, a, _now, _random)
	if action ~= "TreeUpgrade" and action ~= "Upgrade" then
		return nil
	end
	a = type(a) == "table" and a or {}
	local id = action == "Upgrade" and a.Kind or a.Node
	R.Check(type(id) == "string" and #id <= MAX_KEY and Tree.Nodes[id] ~= nil, "Unknown upgrade")
	if type(p.Upgrades) ~= "table" then
		p.Upgrades = {}
	end
	local level = Tree.Level(p, id)
	if a.Level ~= nil then
		R.Check(a.Level == level, "This upgrade changed. Check the new price and try again")
	end
	local ok, reason = Tree.Check(p, id)
	R.Check(ok, reason)
	-- The server price, never a client value.
	local cash, bones = Tree.Cost(id, level)
	R.Pay(p, cash, bones)
	p.Upgrades[id] = level + 1
	local xp = R.AddXP(p, Tree.XP(id, level + 1))
	local message
	if id == "Plot" then
		message = "Yard expanded: " .. PlotCatalog.Stages[level + 2].Name
	elseif action == "Upgrade" then
		message = "Upgrade purchased"
	else
		message = Tree.Nodes[id].Name .. " upgraded to level " .. (level + 1)
	end
	return message, { Node = id, Level = level + 1, XPGranted = xp, Paid = { Cash = cash, Bones = bones } }
end

-- snapshot.Features.UpgradeTree: tree progress (the window reads levels from Profile.Upgrades).
function F.Snapshot(_R, p, view, _now)
	local owned, total = Tree.Progress(p)
	view.UpgradeTree = { Version = Tree.Version, Levels = owned, MaxLevels = total }
end

return F
