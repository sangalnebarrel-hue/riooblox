--!nolint
-- Build the DOGROTS place with Lune (rbx-dom): base place + every script under src/ + offline world edits.
--
--   lune run tools/place_build.luau <base.rbxl> <srcDir> <out.rbxl> [editsDir]
--
-- 1. src/ scripts (Rojo names: .server.luau = Script, .client.luau = LocalScript, .luau = ModuleScript) are written
--    onto the place: an existing instance keeps every property except Source, a missing one is created (missing
--    directories become Folders, a directory next to a script file is that script's children).
-- 2. Every editsDir/*.luau (sorted by name) is a chunk returning function(ctx) with ctx = { game, sim, report, roblox,
--    fs, serde } (edits cannot use require; everything they need is in ctx). Edits run the
--    build-time builder ModuleScripts that live in the place through tools/sim.luau, so the geometry they make is
--    saved in the place. Edits must be idempotent (remove their previous output first).
-- 3. The place is serialized to <out.rbxl>; build_report.json is written next to it.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local Sim = require("./sim")

local basePath, srcDir, outPath, editsDir = process.args[1], process.args[2], process.args[3], process.args[4]
assert(basePath and srcDir and outPath, "usage: lune run tools/place_build.luau <base.rbxl> <srcDir> <out.rbxl> [editsDir]")

local game = roblox.deserializePlace(fs.readFile(basePath))
local report = { modified = {}, created = {}, edits = {} }

local function classify(fileName: string)
	for _, pair in { { ".server.luau", "Script" }, { ".client.luau", "LocalScript" }, { ".luau", "ModuleScript" } } do
		local suffix, cls = pair[1], pair[2]
		if string.sub(fileName, -#suffix) == suffix then
			return string.sub(fileName, 1, -#suffix - 1), cls
		end
	end
	return nil, nil
end

local function childNamed(parent, name: string)
	local found = nil
	for _, c in parent:GetChildren() do
		if c.Name == name then
			assert(found == nil, "ambiguous path: " .. parent:GetFullName() .. "." .. name)
			found = c
		end
	end
	return found
end

-- collect files, parents first
local items = {}
local function walk(dir: string, rel: { string })
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			local nextRel = table.clone(rel)
			table.insert(nextRel, entry)
			walk(full, nextRel)
		else
			local name, cls = classify(entry)
			if name then
				local parts = table.clone(rel)
				table.insert(parts, name)
				table.insert(items, { parts = parts, cls = cls, path = full })
			end
		end
	end
end
walk(srcDir, {})
table.sort(items, function(a, b)
	if #a.parts ~= #b.parts then
		return #a.parts < #b.parts
	end
	return table.concat(a.parts, "/") < table.concat(b.parts, "/")
end)

for _, item in items do
	local parts, cls = item.parts, item.cls
	local source = fs.readFile(item.path)
	local svc = game:GetService(parts[1])
	assert(svc, "missing service " .. parts[1])
	local parent = svc
	for i = 2, #parts - 1 do
		local nxt = childNamed(parent, parts[i])
		if not nxt then
			nxt = roblox.Instance.new("Folder")
			nxt.Name = parts[i]
			nxt.Parent = parent
			table.insert(report.created, table.concat(parts, "/", 1, i) .. " (Folder)")
		end
		parent = nxt
	end
	local pathText = table.concat(parts, "/")
	local inst = childNamed(parent, parts[#parts])
	if inst then
		assert(inst.ClassName == cls, "class mismatch " .. pathText .. ": " .. inst.ClassName .. " ~= " .. cls)
		if inst.Source ~= source then
			inst.Source = source
			table.insert(report.modified, pathText)
		end
	else
		inst = roblox.Instance.new(cls)
		inst.Name = parts[#parts]
		inst.Source = source
		inst.Parent = parent
		table.insert(report.created, pathText .. " (" .. cls .. ")")
	end
end

if editsDir and fs.isDir(editsDir) then
	local names = {}
	for _, entry in fs.readDir(editsDir) do
		if string.sub(entry, -5) == ".luau" then
			table.insert(names, entry)
		end
	end
	table.sort(names)
	for _, entry in names do
		local edit = luau.load(fs.readFile(editsDir .. "/" .. entry), { debugName = entry })()
		local sim = Sim.new(game)
		local editReport = {}
		edit({ game = game, sim = sim, report = editReport, roblox = roblox, fs = fs, serde = serde })
		report.edits[entry] = editReport
		print("edit", entry, serde.encode("json", editReport))
	end
end

fs.writeFile(outPath, roblox.serializePlace(game))
local reportPath = string.gsub(outPath, "[^/]+$", "build_report.json")
fs.writeFile(reportPath, serde.encode("json", report, true))
print(string.format("modified %d, created %d, edits %d", #report.modified, #report.created, #(function()
	local t = {}
	for k in report.edits do
		table.insert(t, k)
	end
	return t
end)()))
print("wrote", outPath)
