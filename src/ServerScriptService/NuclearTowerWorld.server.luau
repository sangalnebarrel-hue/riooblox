-- The NUCLEAR MUTATION TOWER (the mutation lab is a nuclear cooling tower now).
-- The compound is saved in the place (Workspace.DOGROTS_District.05_MutationLab.NuclearCompound,
-- built by ServerScriptService.NuclearTowerBuild from ReplicatedStorage.NuclearLayout). This script
-- rebuilds it when it is missing or older than the layout, and keeps the lab's anchors where the
-- console and the pad are: InteractionAnchor (LabService's START MUTATION prompt, LabAccess reach) on
-- the console, InteriorZone over the plaza. Everything that moves (door, arm, screens, beams) is
-- animated by each client (Modules.LabPresentation); the server only announces results (LabService).
local RS = game:GetService("ReplicatedStorage")
local L = require(RS:WaitForChild("NuclearLayout"))

local map = workspace:WaitForChild("DOGROTS_District", 60)
local lab = map and map:WaitForChild("05_MutationLab", 60)
if not lab then
	warn("Nuclear tower: Workspace.DOGROTS_District.05_MutationLab not found")
	return
end

local ok, err = pcall(function()
	local compound = lab:FindFirstChild(L.Name)
	if not compound or (compound:GetAttribute("Version") or 0) < L.Version then
		local Build = require(script.Parent:WaitForChild("NuclearTowerBuild"))
		compound = Build.Build(lab)
		local parts = compound:GetAttribute("Parts") or 0
		if parts > Build.MaxParts then
			warn(string.format("Nuclear tower: %d parts (budget %d)", parts, Build.MaxParts))
		end
	end
	local anchor = lab:FindFirstChild("InteractionAnchor")
	if anchor and anchor:IsA("BasePart") and (anchor.Position - L.Anchor).Magnitude > 0.05 then
		anchor.CFrame = CFrame.new(L.Anchor)
	end
	local zone = lab:FindFirstChild("InteriorZone")
	if zone and zone:IsA("BasePart") then
		local Z = L.Zone
		local size = Vector3.new(Z.X1 - Z.X0, Z.Y1 - Z.Y0, Z.Z1 - Z.Z0)
		if (zone.Size - size).Magnitude > 0.05 then
			zone.Size = size
			zone.CFrame = CFrame.new((Z.X0 + Z.X1) / 2, (Z.Y0 + Z.Y1) / 2, (Z.Z0 + Z.Z1) / 2)
		end
	end
	lab:SetAttribute("NuclearTower", true)
	lab:SetAttribute("MutationMachine", true)
end)
if not ok then
	warn("Nuclear tower: " .. tostring(err))
end
