-- Installs the NUCLEAR MUTATION MACHINE in the Mutation Lab when the server starts (docs/LAB.md):
-- the old central chamber is hidden (reversibly, originals in MutationMachine_* attributes), the roof
-- skylight is cut where the tube passes, the machine and its console are built
-- (ServerScriptService.MutationMachineBuild) and LabService's InteractionAnchor (the ACTIVATE prompt and
-- the LabAccess reach) moves to the console. LabConfig.MachineWorld = false leaves the old lab untouched.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("LabConfig"))
if Config.MachineWorld == false then
	return
end
local map = workspace:WaitForChild("DOGROTS_District", 60)
local lab = map and map:WaitForChild("05_MutationLab", 60)
if not lab then
	warn("Mutation machine: Workspace.DOGROTS_District.05_MutationLab not found")
	return
end
local ok, err = pcall(function()
	local Build = require(script.Parent:WaitForChild("MutationMachineBuild"))
	local machine = Build.Install(lab)
	local parts = machine:GetAttribute("Parts") or 0
	if parts > Build.MaxParts then
		warn(string.format("Mutation machine: %d parts (budget %d)", parts, Build.MaxParts))
	end
	lab:SetAttribute("MutationMachine", true)
end)
if not ok then
	warn("Mutation machine: " .. tostring(err))
end
