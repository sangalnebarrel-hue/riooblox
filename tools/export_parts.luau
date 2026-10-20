--!nolint
-- Export the BaseParts under one or more instance paths of a place to JSON for tools/render_preview.py.
-- usage: lune run tools/export_parts.luau <place.rbxl> <out.json> <Path.To.Root> [<Path.To.Root2> ...]
--   paths are dot-separated from the DataModel, e.g. Workspace.DOGROTS_District.40_Underyard
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")

local placePath, outPath = process.args[1], process.args[2]
assert(placePath and outPath and process.args[3], "usage: lune run tools/export_parts.luau <place> <out.json> <root> [...]")
local game = roblox.deserializePlace(fs.readFile(placePath))

local function find(path)
	local node = game
	for name in string.gmatch(path, "[^%.]+") do
		local nxt = node:FindFirstChild(name)
		if not nxt and node == game then
			local ok, svc = pcall(function()
				return game:GetService(name)
			end)
			nxt = ok and svc or nil
		end
		node = nxt
		if not node then
			return nil
		end
	end
	return node
end

local function r3(n)
	return math.floor(n * 1000 + 0.5) / 1000
end

local parts = {}
for i = 3, #process.args do
	local root = find(process.args[i])
	assert(root, "not found: " .. process.args[i])
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			local shape = "Block"
			if d.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif d.ClassName == "CornerWedgePart" then
				shape = "Corner"
			elseif d.ClassName == "Part" then
				local ok, s = pcall(function()
					return d.Shape.Name
				end)
				if ok and s then
					shape = s
				end
			end
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				local ok, mt = pcall(function()
					return mesh.MeshType.Name
				end)
				if ok and mt == "Sphere" then
					shape = "Ball"
				end
			end
			local c = d.Color
			table.insert(parts, {
				n = d.Name,
				s = shape,
				p = { r3(x), r3(y), r3(z) },
				r = { r3(r00), r3(r01), r3(r02), r3(r10), r3(r11), r3(r12), r3(r20), r3(r21), r3(r22) },
				z = { r3(d.Size.X), r3(d.Size.Y), r3(d.Size.Z) },
				c = { math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5) },
				t = r3(d.Transparency),
				m = d.Material.Name,
				a = d.Anchored,
				k = d.CanCollide,
			})
		end
	end
end
fs.writeFile(outPath, serde.encode("json", parts))
print("exported", #parts, "parts to", outPath)
