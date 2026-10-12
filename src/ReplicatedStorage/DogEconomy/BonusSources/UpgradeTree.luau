-- Bonus source of the UPGRADE TREE (DogEconomy.UpgradeTree): every bought level of a stat node adds
-- PerLevel to its Bonuses key for the whole team. The six original yard upgrades (Dig, Storage,
-- Kennel, Plot, DogStorage, Ability) are not listed here: their effects stay in Rules / ItemRules /
-- PlotCatalog, exactly as before the tree. Pure and nil-safe (p.Upgrades may be missing).
local Tree = require(script.Parent.Parent.UpgradeTree)

local Source = { Name = "UpgradeTree" }

function Source.Global(p, _now, add)
	if type(p) ~= "table" or type(p.Upgrades) ~= "table" then
		return
	end
	for _, id in ipairs(Tree.Order) do
		local node = Tree.Nodes[id]
		if node.Stat then
			local level = Tree.Level(p, id)
			if level > 0 then
				-- One add per node: MoneyMult nodes multiply with each other (Bonuses adder).
				add(node.Stat, Tree.Value(id, level))
			end
		end
	end
end

return Source
