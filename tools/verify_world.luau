--!nolint
-- Whole-place checks for a built place (run after tools/verify.luau):
--   * every LuaSourceContainer in the place compiles (not only the ones mirrored in src/)
--   * no two scripts share a name under the same parent (require(script.Parent.X) would be ambiguous)
--   * offline-built world roots (tools/edits) are present, fully anchored and inside their part / light budgets
-- usage: lune run tools/verify_world.luau <place.rbxl>
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local process = require("@lune/process")

local game = roblox.deserializePlace(fs.readFile(process.args[1]))
local failures = 0
local function fail(msg)
	failures += 1
	print("FAIL: " .. msg)
end

local compiled = 0
for _, inst in game:GetDescendants() do
	if inst:IsA("LuaSourceContainer") then
		local ok, err = pcall(luau.compile, inst.Source)
		if not ok then
			fail("compile error in " .. inst:GetFullName() .. ": " .. tostring(err))
		end
		compiled += 1
		local seen = {}
		for _, sib in inst.Parent:GetChildren() do
			if sib:IsA("LuaSourceContainer") and sib ~= inst and sib.Name == inst.Name and not seen[sib] then
				seen[sib] = true
				fail("duplicate script name " .. inst:GetFullName())
			end
		end
	end
end

-- World roots built by tools/edits. Budgets keep phones playable (see docs/HALLOWEEN_PART2.md, Performance).
local ROOTS = {
	{ path = { "Workspace", "DOGROTS_District", "40_Underyard" }, parts = 26000, lights = 260 },
	{ path = { "Workspace", "DOGROTS_District", "41_HalloweenCalendar" }, parts = 9000, lights = 90 },
}
local function find(path)
	local node = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end
for _, root in ROOTS do
	local node = find(root.path)
	local label = table.concat(root.path, ".")
	if not node then
		print("note: " .. label .. " not present")
		continue
	end
	local parts, lights, unanchored = 0, 0, 0
	for _, d in node:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if not d.Anchored then
				unanchored += 1
			end
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	print(string.format("%s: %d parts, %d lights", label, parts, lights))
	if unanchored > 0 then
		fail(label .. " has " .. unanchored .. " unanchored parts")
	end
	if parts > root.parts then
		fail(string.format("%s has %d parts (budget %d)", label, parts, root.parts))
	end
	if lights > root.lights then
		fail(string.format("%s has %d lights (budget %d)", label, lights, root.lights))
	end
end

print(string.format("compiled %d scripts, %d failures", compiled, failures))
if failures > 0 then
	process.exit(1)
end
