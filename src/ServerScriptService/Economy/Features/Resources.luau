-- Stored crafting resources (ReplicatedStorage.DogEconomy.Resources): p.Resources = {Stone = n}.
-- Feature module (Economy.FeatureRegistry): fills the table for old profiles and validates it.
-- Stone is granted by the Mining Corner (MiningRules) and spent by plot decor (Features.Decor).
local RS = game:GetService("ReplicatedStorage")
local Resources = require(RS.DogEconomy.Resources)

local F = { Name = "Resources", Order = 10 }

function F.Normalize(_R, p, _now)
	Resources.Normalize(p)
end

function F.Validate(_R, p)
	Resources.Validate(p)
end

return F
