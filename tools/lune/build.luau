-- Build: base place + src/ scripts -> output place.
--   lune run tools/lune/build.luau place/DOGROTS_MINING_6.rbxl src build/DOGROTS_MINING_7.rbxl
-- Every src/<Service>/<path>.{server,client,}.lua replaces (or creates) the script at that path:
-- .server.lua = Script, .client.lua = LocalScript, .lua = ModuleScript. Missing parent folders
-- are created as Folders. Nothing else in the place is touched (world edits happen at runtime
-- in the scripts themselves, so they stay reversible).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local luau = require("@lune/luau")

local basePath, srcDir, outPath = process.args[1], process.args[2], process.args[3]
assert(basePath and srcDir and outPath, "usage: build.luau <base.rbxl> <srcDir> <out.rbxl>")
local game = roblox.deserializePlace(fs.readFile(basePath))

local changed, created, same, failed = 0, 0, 0, 0
local function classOf(file: string): (string, string)
	if file:sub(-11) == ".server.lua" then
		return "Script", file:sub(1, -12)
	elseif file:sub(-11) == ".client.lua" then
		return "LocalScript", file:sub(1, -12)
	end
	return "ModuleScript", file:sub(1, -5)
end

local function walk(dir: string, parts: { string })
	for _, name in fs.readDir(dir) do
		local full = dir .. "/" .. name
		if fs.isDir(full) then
			local nextParts = table.clone(parts)
			table.insert(nextParts, name)
			walk(full, nextParts)
		elseif name:sub(-4) == ".lua" then
			local class, instName = classOf(name)
			local source = fs.readFile(full)
			local ok, err = pcall(luau.compile, source)
			if not ok then
				failed += 1
				print("COMPILE ERROR " .. full .. ": " .. tostring(err))
				continue
			end
			-- Resolve the parent chain.
			local node: any = game
			for i, part in parts do
				local child = node:FindFirstChild(part)
				if not child then
					if i == 1 then
						error("unknown service " .. part)
					end
					child = roblox.Instance.new("Folder")
					child.Name = part
					child.Parent = node
					print("created folder " .. child:GetFullName())
				end
				node = child
			end
			local inst = node:FindFirstChild(instName)
			if inst and inst.ClassName ~= class then
				print("CLASS MISMATCH " .. full .. " is " .. inst.ClassName)
				failed += 1
				continue
			end
			if not inst then
				inst = roblox.Instance.new(class)
				inst.Name = instName
				inst.Parent = node
				inst.Source = source
				created += 1
				print("created " .. class .. " " .. inst:GetFullName())
			elseif inst.Source ~= source then
				inst.Source = source
				changed += 1
				print("updated " .. inst:GetFullName())
			else
				same += 1
			end
		end
	end
end
walk(srcDir, {})
print(string.format("scripts: %d updated, %d created, %d unchanged, %d failed", changed, created, same, failed))
if failed > 0 then
	process.exit(1)
end
local dir = outPath:match("^(.*)/[^/]*$")
if dir then
	fs.writeDir(dir)
end
fs.writeFile(outPath, roblox.serializePlace(game))
print("wrote " .. outPath)
