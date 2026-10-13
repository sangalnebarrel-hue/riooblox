--!nocheck
-- Exports the parts of a scene to JSON for tools/qa/render.py (QA previews without Studio).
--   lune run tools/qa/scene.luau <scene.luau> <out.json> [args...]
-- A scene script returns function(L, roblox, args) -> Instance | {Instance} [, title]
-- where L is tests/lib/economy_env (L.Require("ReplicatedStorage.X") runs real src modules that
-- build real Lune instances). The place can be read with roblox.deserializePlace when a scene
-- needs existing geometry (pass it in args).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local scenePath, outPath = process.args[1], process.args[2]
assert(scenePath and outPath, "usage: lune run tools/qa/scene.luau <scene.luau> <out.json> [args...]")
local extra = {}
for i = 3, #process.args do
	table.insert(extra, process.args[i])
end

local L = require("../../tests/lib/economy_env")

-- Lune 0.10.5 builds CFrame.lookAt / CFrame.new(pos, target) with a wrong rotation (Roblox is
-- right); scenes and the modules they require get a corrected CFrame library.
local RawCFrame = roblox.CFrame
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return RawCFrame.new(at)
	end
	look = look.Unit
	up = up or roblox.Vector3.new(0, 1, 0)
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.new(0, 0, -1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(roblox.Vector3.new(1, 0, 0))
		end
	end
	right = right.Unit
	return RawCFrame.fromMatrix(at, right, right:Cross(look))
end
local CFrameFixed = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return RawCFrame.new(...)
	end,
}, { __index = RawCFrame })
L.CFrame = CFrameFixed
local robloxFixed = setmetatable({ CFrame = CFrameFixed }, { __index = roblox })
local chunk = luau.load(fs.readFile(scenePath), {
	debugName = scenePath,
	environment = setmetatable({ require = require }, { __index = _G }),
})
local build = chunk()
local result, title = build(L, robloxFixed, extra)
local roots = typeof(result) == "Instance" and { result } or result

local out = {}
local function shapeOf(p)
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		local ok, kind = pcall(function()
			return mesh.MeshType.Name
		end)
		if ok and kind == "Sphere" then
			return "Ellipsoid"
		end
	end
	if p.ClassName == "WedgePart" then
		return "Wedge"
	elseif p.ClassName == "CornerWedgePart" then
		return "CornerWedge"
	elseif p.ClassName == "Part" then
		local ok, s = pcall(function()
			return p.Shape.Name
		end)
		if ok and (s == "Ball" or s == "Cylinder" or s == "Wedge" or s == "CornerWedge") then
			return s
		end
	end
	return "Block"
end
local function add(p)
	local ok, cf = pcall(function()
		return p.CFrame
	end)
	if not ok then
		return
	end
	local c = { cf:GetComponents() }
	local tr = 0
	pcall(function()
		tr = p.Transparency
	end)
	local col = p.Color
	local mat = "Plastic"
	pcall(function()
		mat = p.Material.Name
	end)
	table.insert(out, {
		shape = shapeOf(p),
		p = { c[1], c[2], c[3] },
		r = { c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12] },
		s = { p.Size.X, p.Size.Y, p.Size.Z },
		c = { col.R, col.G, col.B },
		m = mat,
		t = tr,
		n = p.Name,
	})
end
for _, root in roots do
	if root:IsA("BasePart") then
		add(root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			add(d)
		end
	end
end
fs.writeFile(outPath, serde.encode("json", { title = title, parts = out }))
print(string.format("exported %d parts to %s", #out, outPath))
