--!nolint
-- Compare the output place with the source place it was built from (final delivery check):
--   * both files deserialize (the output is a valid binary .rbxl) and the output survives a serialize round trip
--   * every script of the source place still exists in the output (same full name), every other source instance too
--     unless it lies under a root an offline edit rebuilds on purpose (listed below)
--   * per-service instance counts, added / changed scripts, the world roots Part II adds
-- usage: lune run tools/compare_places.luau <source.rbxl> <output.rbxl>
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local srcPath, outPath = process.args[1], process.args[2]
assert(srcPath and outPath, "usage: lune run tools/compare_places.luau <source.rbxl> <output.rbxl>")

local header = string.sub(fs.readFile(outPath), 1, 8)
assert(header == "<roblox!", "the output is not a binary Roblox place (header " .. string.format("%q", header) .. ")")
local src = roblox.deserializePlace(fs.readFile(srcPath))
local out = roblox.deserializePlace(fs.readFile(outPath))
-- round trip: what Studio reads is what Lune wrote
local again = roblox.deserializePlace(roblox.serializePlace(out))

-- roots that tools/edits rebuild or reshape on purpose (their old children may be replaced or hidden)
local REBUILT = {
	"Workspace.DOGROTS_District.40_Underyard",
	"Workspace.DOGROTS_District.38_DeadYard.Church",
	"Workspace.DOGROTS_District.38_DeadYard.Crypts",
	"ServerStorage.HalloweenCalendar",
	"ServerStorage.HalloweenCalendarBuild",
	"ServerStorage.UnderyardBuild",
	"ReplicatedStorage.MenuModels",
	"ReplicatedStorage.Halloween.Models",
	"SoundService",
}
local function rebuilt(full: string): boolean
	for _, r in ipairs(REBUILT) do
		if full == r or string.sub(full, 1, #r + 1) == r .. "." then
			return true
		end
	end
	return false
end

local function index(game)
	local byName, counts, scripts = {}, {}, {}
	for _, svc in ipairs(game:GetChildren()) do
		local n = 0
		for _, d in ipairs(svc:GetDescendants()) do
			n += 1
			local full = d:GetFullName()
			byName[full] = (byName[full] or 0) + 1
			if d:IsA("LuaSourceContainer") then
				scripts[full] = d.Source
			end
		end
		counts[svc.Name] = n
	end
	return byName, counts, scripts
end

local sNames, sCounts, sScripts = index(src)
local oNames, oCounts, oScripts = index(out)
local _, aCounts = index(again)

local failures = 0
local function fail(msg)
	failures += 1
	print("FAIL: " .. msg)
end

-- scripts: none of the source place's scripts may disappear
local missingScripts, changedScripts, addedScripts = 0, 0, 0
for full, source in pairs(sScripts) do
	if oScripts[full] == nil then
		missingScripts += 1
		fail("script missing in the output: " .. full)
	elseif oScripts[full] ~= source then
		changedScripts += 1
	end
end
for full in pairs(oScripts) do
	if sScripts[full] == nil then
		addedScripts += 1
	end
end

-- other instances: kept unless under a rebuilt root
local lost, lostSamples = 0, {}
for full, n in pairs(sNames) do
	if not rebuilt(full) and (oNames[full] or 0) < n then
		lost += 1
		if #lostSamples < 15 then
			table.insert(lostSamples, full)
		end
	end
end
if lost > 0 then
	fail(string.format("%d source instances missing outside the rebuilt roots, e.g.:\n  %s", lost, table.concat(lostSamples, "\n  ")))
end

-- round trip stability
for name, n in pairs(oCounts) do
	if aCounts[name] ~= n then
		fail(string.format("round trip changed %s: %d -> %s", name, n, tostring(aCounts[name])))
	end
end

print(string.format("source: %s (%d bytes)   output: %s (%d bytes)", srcPath, #fs.readFile(srcPath), outPath, #fs.readFile(outPath)))
local names = {}
for name in pairs(oCounts) do
	table.insert(names, name)
end
table.sort(names)
for _, name in ipairs(names) do
	if (sCounts[name] or 0) ~= oCounts[name] then
		print(string.format("  %-26s %7d -> %7d", name, sCounts[name] or 0, oCounts[name]))
	end
end
print(string.format("scripts: %d in the source, %d kept unchanged, %d changed, %d added, %d missing", (function()
	local n = 0
	for _ in pairs(sScripts) do
		n += 1
	end
	return n
end)(), (function()
	local n = 0
	for full, source in pairs(sScripts) do
		if oScripts[full] == source then
			n += 1
		end
	end
	return n
end)(), changedScripts, addedScripts, missingScripts))
print(string.format("round trip: %s; %d failures", failures == 0 and "stable" or "see above", failures))
if failures > 0 then
	process.exit(1)
end
