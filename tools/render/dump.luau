-- Serializes the BaseParts of a model built in Lune to JSON for tools/render/render.py.
local serde = require("@lune/serde")
local D = {}
function D.parts(root)
	local out = {}
	local list = root:IsA("BasePart") and { root } or {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	for _, p in list do
		local shape = "Block"
		if p.ClassName == "WedgePart" then
			shape = "Wedge"
		elseif p.ClassName == "Part" then
			local ok, s = pcall(function()
				return p.Shape
			end)
			if ok and s then
				shape = s.Name
			end
		end
		local mesh = p:FindFirstChildWhichIsA("SpecialMesh")
		if mesh and mesh.MeshType.Name == "Sphere" then
			shape = "Sphere"
		end
		local c = { p.CFrame:GetComponents() }
		table.insert(out, {
			name = p.Name,
			shape = shape,
			cf = c,
			size = { p.Size.X, p.Size.Y, p.Size.Z },
			color = { p.Color.R, p.Color.G, p.Color.B },
			t = p.Transparency,
			mat = p.Material.Name,
		})
	end
	return out
end
function D.write(path, scenes)
	require("@lune/fs").writeFile(path, serde.encode("json", scenes))
end
return D
