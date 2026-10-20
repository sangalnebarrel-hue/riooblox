--!nolint
-- Verifies a built place with Lune (independent rbx-dom reader):
--   * every src/ file exists in the place with the right class and identical Source
--   * every script touched by the build compiles with the Luau compiler
--   * new scripts carry no stray tags / attributes and are enabled
--   * optionally exports a Rojo-style sourcemap + script files for luau-lsp analyze
-- usage: lune run tools/verify.luau <place.rbxl> <srcDir> [exportDir]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local process = require("@lune/process")

local placePath, srcDir, exportDir = process.args[1], process.args[2], process.args[3]
local game = roblox.deserializePlace(fs.readFile(placePath))

local serde = require("@lune/serde")
local created = {}
local reportPath = string.gsub(placePath, "[^/]+$", "build_report.json")
if fs.isFile(reportPath) then
	local report = serde.decode("json", fs.readFile(reportPath))
	for _, entry in report.created or {} do
		created[(string.gsub(entry, " %(%a+%)$", ""))] = true
	end
end

local failures = 0
local function fail(msg)
	failures += 1
	print("FAIL: " .. msg)
end

local function classify(fileName: string)
	for _, pair in { { ".server.luau", "Script" }, { ".client.luau", "LocalScript" }, { ".luau", "ModuleScript" } } do
		local suffix, cls = pair[1], pair[2]
		if string.sub(fileName, -#suffix) == suffix then
			return string.sub(fileName, 1, -#suffix - 1), cls
		end
	end
	return nil, nil
end

local function findPath(parts: { string })
	local node = game:FindFirstChild(parts[1])
	for i = 2, #parts do
		if not node then
			return nil
		end
		local matches = {}
		for _, child in node:GetChildren() do
			if child.Name == parts[i] then
				table.insert(matches, child)
			end
		end
		if #matches ~= 1 then
			return nil
		end
		node = matches[1]
	end
	return node
end

local checked = 0
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
				local pathText = table.concat(parts, "/")
				local inst = findPath(parts)
				local source = fs.readFile(full)
				if not inst then
					fail("missing instance " .. pathText)
				elseif inst.ClassName ~= cls then
					fail("class mismatch " .. pathText .. " " .. inst.ClassName .. " ~= " .. cls)
				elseif inst.Source ~= source then
					fail("source mismatch " .. pathText)
				else
					local ok, err = pcall(luau.compile, source)
					if not ok then
						fail("compile error in " .. pathText .. ": " .. tostring(err))
					end
					local isNew = created[pathText] == true
					if isNew and #inst:GetTags() > 0 then
						fail("unexpected tags on " .. pathText)
					end
					local attrCount = 0
					for _ in inst:GetAttributes() do
						attrCount += 1
					end
					if isNew and attrCount > 0 then
						fail("unexpected attributes on " .. pathText)
					end
					if isNew and (cls == "Script" or cls == "LocalScript") and inst.Disabled then
						fail("script disabled: " .. pathText)
					end
					checked += 1
				end
			end
		end
	end
end
walk(srcDir, {})
print(string.format("verified %d src scripts, %d failures", checked, failures))

if exportDir then
	-- Rojo-style sourcemap so luau-lsp can resolve require(script.Parent.X) paths.
	if fs.isDir(exportDir) then
		fs.removeDir(exportDir)
	end
	fs.writeDir(exportDir)
	local count = 0
	local function safe(s: string)
		return (string.gsub(s, "[^%w%._%-]", "_"))
	end
	local function node(inst, pathText: string)
		local entry = { name = inst.Name, className = inst.ClassName, children = {} }
		if inst:IsA("LuaSourceContainer") and not string.find(pathText, "DogAnimationClips", 1, true) then
			count += 1
			local fileName = string.format("%05d_%s.luau", count, safe(pathText))
			fs.writeFile(exportDir .. "/" .. fileName, inst.Source)
			entry.filePaths = { fileName }
		end
		for _, child in inst:GetChildren() do
			table.insert(entry.children, node(child, pathText .. "/" .. child.Name))
		end
		return entry
	end
	local rootNode = { name = "Game", className = "DataModel", children = {} }
	for _, svc in game:GetChildren() do
		table.insert(rootNode.children, node(svc, svc.Name))
	end
	fs.writeFile(exportDir .. "/sourcemap.json", serde.encode("json", rootNode))
	print("exported", count, "scripts to", exportDir)
end

if failures > 0 then
	process.exit(1)
end
