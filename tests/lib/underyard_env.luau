--!nocheck
-- Builds THE UNDERYARD offline in a fresh DataModel (no base place needed): the real src/ builder modules
-- (ServerStorage.HalloweenBuild.Kit / YardKit, every ServerStorage.UnderyardBuild module, ReplicatedStorage.Halloween.
-- UnderyardLayout) are loaded as ModuleScripts and the real edit tools/edits/40_underyard.luau runs them through
-- tools/sim.luau, exactly like tools/place_build.luau does. Not a test by itself; tests/underyard_world.luau uses it.
--   local E = require("./lib/underyard_env")
--   local game, report = E.Build()        -- report = the edit's report table
--   E.Root(game) -> 40_Underyard model ; E.Export(instance, path) -> JSON for tools/render_preview.py
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("../../tools/sim")

local E = {}
local SRC = (process.env.DOGROTS_SRC or "src"):gsub("/$", "")
local EDITS = (process.env.DOGROTS_EDITS or "tools/edits"):gsub("/$", "")

local function module(parent, name: string, path: string)
	local ms = roblox.Instance.new("ModuleScript")
	ms.Name = name
	ms.Source = fs.readFile(path)
	ms.Parent = parent
	return ms
end

local function folder(parent, name: string)
	local f = parent:FindFirstChild(name)
	if not f then
		f = roblox.Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

function E.Build()
	local game = roblox.Instance.new("DataModel")
	local ws = game:GetService("Workspace")
	local district = roblox.Instance.new("Model")
	district.Name = "DOGROTS_District"
	district.Parent = ws
	local SS = game:GetService("ServerStorage")
	local RS = game:GetService("ReplicatedStorage")
	local hb = folder(SS, "HalloweenBuild")
	module(hb, "Kit", SRC .. "/ServerStorage/HalloweenBuild/Kit.luau")
	module(hb, "YardKit", SRC .. "/ServerStorage/HalloweenBuild/YardKit.luau")
	local ub = folder(SS, "UnderyardBuild")
	local dir = SRC .. "/ServerStorage/UnderyardBuild"
	if fs.isDir(dir) then
		for _, entry in fs.readDir(dir) do
			if string.sub(entry, -5) == ".luau" and not string.find(entry, "%.server%.luau$") and not string.find(entry, "%.client%.luau$") then
				module(ub, string.sub(entry, 1, -6), dir .. "/" .. entry)
			end
		end
	end
	module(folder(RS, "Halloween"), "UnderyardLayout", SRC .. "/ReplicatedStorage/Halloween/UnderyardLayout.luau")
	-- [WP-K4] the BlackCoffin builder (Order 31) reads its sizes / attribute contract from CoffinConfig
	module(folder(RS, "Halloween"), "CoffinConfig", SRC .. "/ReplicatedStorage/Halloween/CoffinConfig.luau")
	local report = {}
	local edit = luau.load(fs.readFile(EDITS .. "/40_underyard.luau"), { debugName = "40_underyard.luau" })()
	edit({ game = game, sim = Sim.new(game), report = report, roblox = roblox, fs = fs, serde = serde })
	return game, report
end

function E.Root(game)
	return game:GetService("Workspace").DOGROTS_District:FindFirstChild("40_Underyard")
end

local function r3(n)
	return math.floor(n * 1000 + 0.5) / 1000
end

-- same JSON as tools/export_parts.luau
function E.Export(root, outPath: string): number
	local parts = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
			local shape = "Block"
			if d.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif d.ClassName == "CornerWedgePart" then
				shape = "Corner"
			elseif d.ClassName == "Part" then
				shape = d.Shape.Name
			end
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType.Name == "Sphere" then
				shape = "Ball"
			end
			local c = d.Color
			table.insert(parts, {
				n = d.Name, s = shape, p = { r3(x), r3(y), r3(z) },
				r = { r3(r00), r3(r01), r3(r02), r3(r10), r3(r11), r3(r12), r3(r20), r3(r21), r3(r22) },
				z = { r3(d.Size.X), r3(d.Size.Y), r3(d.Size.Z) },
				c = { math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5) },
				t = r3(d.Transparency), m = d.Material.Name, a = d.Anchored, k = d.CanCollide,
			})
		end
	end
	fs.writeFile(outPath, serde.encode("json", parts))
	return #parts
end

return E
