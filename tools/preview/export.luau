--!nocheck
-- Exports World.Spec layouts or regions of a place file to a JSON scene for tools/preview/render.mjs.
-- Run from the repository root (modules load from src/ through tests/lib/economy_env.luau):
--
--   lune run tools/preview/export.luau out/scene.json --module ReplicatedStorage.Lab.FlaskLayout --call Build --args '[1]'
--   lune run tools/preview/export.luau out/scene.json --file tools/preview/samples/stand.luau
--   lune run tools/preview/export.luau out/scene.json --specs my_specs.json
--   lune run tools/preview/export.luau out/scene.json --place build/DOGROTS_MINING.rbxl \
--       --path Workspace/DOGROTS_District/05_MutationLab [--path ...] [--max 20000] [--invisible]
--   Any source may be repeated; --anchor x,y,z[,yawDegrees] moves the spec sources.
--
-- --module: a ModuleScript under src/ (dotted path). With --call the named function is called
--   (arguments from --args, a JSON array); without it the module itself must be a spec list or a
--   function. The result is a spec list or {Specs = list, Anchor = CFrame}.
-- --file: a Luau file evaluated with Spec, Vector3, CFrame, Color3, Enum, UDim2 and the sequence
--   types in scope; it returns a spec list or a function returning one.
-- --specs: JSON, a list of parts: {"Class","Shape","Name","Size":[x,y,z],"CFrame":[x,y,z] or 12
--   numbers or {"Position":[x,y,z],"Rotation":[rx,ry,rz] degrees},"Color":[r,g,b] 0-255 or "#RRGGBB",
--   "Material","Transparency","Reflectance","Children":[{"Class":"PointLight","Range":..,"Color":..}]}.
-- --place: every visible BasePart under each --path (slash separated, from the DataModel). Mesh
--   parts and unions are drawn as their bounding box (marked "Approx"); SpecialMesh bricks,
--   spheres, cylinders and wedges keep their shape. --max keeps the largest parts only.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local L = require("../../tests/lib/economy_env")

local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
local Spec = L.Require("ReplicatedStorage.World.Spec")

local args = process.args
local out = args[1]
if not out or out:sub(1, 2) == "--" then
	print("usage: lune run tools/preview/export.luau <out.json> (--module path [--call fn] [--args json] | --file f.luau | --specs f.json | --place f.rbxl --path A/B [--max n]) [--anchor x,y,z,yaw]")
	process.exit(1)
end

local parts, lights, notes = {}, {}, {}
local skipped = 0

local function vec(v)
	return { v.X, v.Y, v.Z }
end
local function cframe(cf)
	return { cf:GetComponents() }
end
local function color(c)
	return { c.R, c.G, c.B }
end

local function materialName(m)
	if type(m) == "string" then
		return m
	end
	return m and m.Name or "SmoothPlastic"
end

local function addLight(spec, at)
	if spec.Enabled == false then
		return
	end
	table.insert(lights, {
		Class = spec.Class or "PointLight",
		Position = vec(at),
		Color = color(spec.Color or Color3.new(1, 1, 1)),
		Range = spec.Range or 12,
		Brightness = spec.Brightness or 1,
	})
end

local LIGHTS = { PointLight = true, SpotLight = true, SurfaceLight = true }

-- World-space spec parts -> scene parts (lights from Children; attachments move their lights).
local function addSpecs(specs, anchor)
	for _, spec in ipairs(Spec.Flatten(specs, anchor)) do
		if Spec.IsPart(spec) then
			table.insert(parts, {
				Name = spec.Name,
				Class = spec.Class or "Part",
				Shape = spec.Shape or "Block",
				Size = vec(spec.Size),
				CFrame = cframe(spec.CFrame),
				Color = color(spec.Color or Spec.DefaultColor),
				Material = materialName(spec.Material),
				Transparency = spec.Transparency or 0,
				Reflectance = spec.Reflectance or 0,
			})
			local function children(list, frame)
				for _, child in ipairs(list or {}) do
					local at = frame
					if child.Class == "Attachment" and child.CFrame then
						at = frame * child.CFrame
					end
					if LIGHTS[child.Class] then
						addLight(child, at.Position)
					end
					children(child.Children, at)
				end
			end
			children(spec.Children, spec.CFrame)
		end
	end
end

local function parseAnchor(text)
	local n = {}
	for v in string.gmatch(text, "[^,]+") do
		table.insert(n, tonumber(v) or 0)
	end
	return CFrame.new(n[1] or 0, n[2] or 0, n[3] or 0) * CFrame.Angles(0, math.rad(n[4] or 0), 0)
end

local function fromSpecResult(result, anchor, label)
	if type(result) == "function" then
		result = result()
	end
	if type(result) == "table" and result.Specs then
		anchor = (result.Anchor or CFrame.identity) * anchor
		result = result.Specs
	end
	assert(type(result) == "table", label .. " did not return a spec list")
	local ok, problems = Spec.Validate(result)
	if not ok then
		table.insert(notes, label .. ": " .. #problems .. " spec problem(s): " .. table.concat(problems, "; ", 1, math.min(5, #problems)))
	end
	addSpecs(result, anchor)
end

local function fileEnv()
	return setmetatable({
		Spec = Spec,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Require = L.Require,
	}, { __index = _G })
end

-- JSON spec values -> Roblox values.
local function jsonColor(v)
	if type(v) == "string" then
		return Color3.fromHex(v)
	elseif type(v) == "table" then
		return Color3.fromRGB(v[1] or 0, v[2] or 0, v[3] or 0)
	end
	return nil
end
local function jsonCFrame(v)
	if type(v) ~= "table" then
		return CFrame.identity
	end
	if v.Position then
		local p, r = v.Position, v.Rotation or { 0, 0, 0 }
		return CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	elseif #v == 12 then
		return CFrame.new(table.unpack(v))
	end
	return CFrame.new(v[1] or 0, v[2] or 0, v[3] or 0)
end
local function jsonChild(c)
	local child = {}
	for k, v in pairs(c) do
		child[k] = v
	end
	if c.Color then
		child.Color = jsonColor(c.Color)
	end
	if c.CFrame then
		child.CFrame = jsonCFrame(c.CFrame)
	end
	if c.Children then
		child.Children = {}
		for _, g in ipairs(c.Children) do
			table.insert(child.Children, jsonChild(g))
		end
	end
	return child
end
local function jsonSpecs(list)
	local specs = {}
	for _, p in ipairs(list) do
		local props = jsonChild(p)
		props.Size = Vector3.new(table.unpack(p.Size or { 1, 1, 1 }))
		props.CFrame = jsonCFrame(p.CFrame)
		table.insert(specs, Spec.Part(props))
	end
	return specs
end

-- Place regions -----------------------------------------------------------------------------------
local placeCache = {}
local function loadPlace(path)
	if not placeCache[path] then
		placeCache[path] = roblox.deserializePlace(fs.readFile(path))
	end
	return placeCache[path]
end

local function resolve(game, path)
	local node = game
	local sep = path:find("/", 1, true) and "/" or "."
	for name in string.gmatch(path, "[^" .. sep .. "]+") do
		local child = node:FindFirstChild(name)
		if not child and node == game then
			local ok, service = pcall(function()
				return game:GetService(name)
			end)
			child = ok and service or nil
		end
		assert(child, "no " .. name .. " under " .. node:GetFullName())
		node = child
	end
	return node
end

local MESH_SHAPES = { Sphere = { "Part", "Ball" }, Cylinder = { "Part", "Cylinder" }, Brick = { "Part", "Block" }, Wedge = { "WedgePart", "Block" } }

local function placePart(part, invisible)
	local transparency = part.Transparency
	if transparency >= 0.98 and not invisible then
		skipped += 1
		return nil
	end
	local class, shape, approx = part.ClassName, "Block", nil
	local size = part.Size
	if class == "Part" then
		shape = part.Shape.Name
	elseif not (class == "WedgePart" or class == "CornerWedgePart" or class == "TrussPart") then
		approx, class = class, "Part"
	end
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		local kind = MESH_SHAPES[mesh.MeshType.Name]
		if kind then
			class, shape, approx = kind[1], kind[2], nil
			size = size * mesh.Scale
		else
			approx = "Mesh"
		end
	end
	return {
		Name = part.Name,
		Class = class,
		Shape = shape,
		Size = vec(size),
		CFrame = cframe(part.CFrame),
		Color = color(part.Color),
		Material = part.Material.Name,
		Transparency = transparency,
		Reflectance = part.Reflectance,
		Approx = approx,
		Volume = size.X * size.Y * size.Z,
	}
end

local function addPlace(file, paths, max, invisible)
	local game = loadPlace(file)
	local found = {}
	for _, path in ipairs(paths) do
		local root = resolve(game, path)
		local list = root:GetDescendants()
		table.insert(list, 1, root)
		for _, inst in ipairs(list) do
			if inst:IsA("BasePart") then
				local p = placePart(inst, invisible)
				if p then
					table.insert(found, p)
				end
			elseif LIGHTS[inst.ClassName] and inst.Enabled then
				local holder = inst.Parent
				local at
				if holder and holder:IsA("Attachment") and holder.Parent and holder.Parent:IsA("BasePart") then
					at = (holder.Parent.CFrame * holder.CFrame).Position
				elseif holder and holder:IsA("BasePart") then
					at = holder.CFrame.Position
				end
				if at then
					addLight({ Class = inst.ClassName, Color = inst.Color, Range = inst.Range, Brightness = inst.Brightness }, at)
				end
			end
		end
	end
	if max and #found > max then
		table.sort(found, function(a, b)
			return a.Volume > b.Volume
		end)
		table.insert(notes, string.format("%s: kept the %d largest of %d parts", file, max, #found))
		for i = #found, max + 1, -1 do
			found[i] = nil
		end
	end
	for _, p in ipairs(found) do
		p.Volume = nil
		table.insert(parts, p)
	end
end

-- Arguments ------------------------------------------------------------------------------------------
local anchor = CFrame.identity
local i = 2
local pending = {}
while i <= #args do
	local flag, value = args[i], args[i + 1]
	if flag == "--anchor" then
		anchor = parseAnchor(value)
		i += 2
	elseif flag == "--module" then
		local entry = { Kind = "module", Path = value }
		while args[i + 2] == "--call" or args[i + 2] == "--args" do
			entry[args[i + 2] == "--call" and "Call" or "Args"] = args[i + 3]
			i += 2
		end
		table.insert(pending, entry)
		i += 2
	elseif flag == "--file" or flag == "--specs" then
		table.insert(pending, { Kind = flag:sub(3), Path = value })
		i += 2
	elseif flag == "--place" then
		local entry = { Kind = "place", Path = value, Paths = {} }
		i += 2
		while args[i] == "--path" or args[i] == "--max" or args[i] == "--invisible" do
			if args[i] == "--path" then
				table.insert(entry.Paths, args[i + 1])
				i += 2
			elseif args[i] == "--max" then
				entry.Max = tonumber(args[i + 1])
				i += 2
			else
				entry.Invisible = true
				i += 1
			end
		end
		table.insert(pending, entry)
	else
		error("unknown argument " .. tostring(flag))
	end
end
assert(#pending > 0, "nothing to export: give --module, --file, --specs or --place")

for _, entry in ipairs(pending) do
	if entry.Kind == "module" then
		local module = L.Require(entry.Path)
		local result = module
		if entry.Call then
			local fn = module[entry.Call]
			assert(type(fn) == "function", entry.Path .. "." .. entry.Call .. " is not a function")
			result = fn(table.unpack(entry.Args and serde.decode("json", entry.Args) or {}))
		end
		fromSpecResult(result, anchor, entry.Path)
	elseif entry.Kind == "file" then
		local chunk = luau.load(fs.readFile(entry.Path), { debugName = entry.Path, environment = fileEnv() })
		fromSpecResult(chunk(), anchor, entry.Path)
	elseif entry.Kind == "specs" then
		fromSpecResult(jsonSpecs(serde.decode("json", fs.readFile(entry.Path))), anchor, entry.Path)
	else
		assert(#entry.Paths > 0, "--place needs at least one --path")
		addPlace(entry.Path, entry.Paths, entry.Max, entry.Invisible)
	end
end

-- Bounds of every part box, for the renderer's cameras.
local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
for _, p in ipairs(parts) do
	local cf = CFrame.new(table.unpack(p.CFrame))
	local h = Vector3.new(p.Size[1], p.Size[2], p.Size[3]) / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local q = cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
				x0, y0, z0 = math.min(x0, q.X), math.min(y0, q.Y), math.min(z0, q.Z)
				x1, y1, z1 = math.max(x1, q.X), math.max(y1, q.Y), math.max(z1, q.Z)
			end
		end
	end
end

local scene = {
	Version = 1,
	Parts = parts,
	Lights = lights,
	Bounds = #parts > 0 and { Min = { x0, y0, z0 }, Max = { x1, y1, z1 } } or nil,
	Stats = { Parts = #parts, Lights = #lights, SkippedInvisible = skipped },
	Notes = notes,
}
local dir = out:match("^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, serde.encode("json", scene))
print(string.format("preview export: %d parts, %d lights -> %s", #parts, #lights, out))
for _, note in ipairs(notes) do
	print("  note: " .. note)
end
