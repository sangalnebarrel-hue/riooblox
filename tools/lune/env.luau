-- Lune harness: load the place and run ModuleScripts with a Roblox-like environment.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local task = require("@lune/task")

local H = {}
H.roblox = roblox

-- Method / property shims for things the builders use that Lune does not implement.
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local function parts(root)
	local out = {}
	if root:IsA("BasePart") then table.insert(out, root) end
	for _, d in root:GetDescendants() do if d:IsA("BasePart") then table.insert(out, d) end end
	return out
end
local function bbox(root)
	local minv, maxv = nil, nil
	for _, p in parts(root) do
		local cf, s = p.CFrame, p.Size
		for _, dx in { -0.5, 0.5 } do for _, dy in { -0.5, 0.5 } do for _, dz in { -0.5, 0.5 } do
			local w = cf:PointToWorldSpace(Vector3.new(s.X * dx, s.Y * dy, s.Z * dz))
			if not minv then minv, maxv = w, w else
				minv = Vector3.new(math.min(minv.X, w.X), math.min(minv.Y, w.Y), math.min(minv.Z, w.Z))
				maxv = Vector3.new(math.max(maxv.X, w.X), math.max(maxv.Y, w.Y), math.max(maxv.Z, w.Z))
			end
		end end end
	end
	if not minv then return CFrame.new(), Vector3.new() end
	return CFrame.new((minv + maxv) / 2), maxv - minv
end
local pivots = setmetatable({}, { __mode = "k" })
local function getPivot(self)
	if self:IsA("BasePart") then return self.CFrame end
	if self.PrimaryPart then return self.PrimaryPart.CFrame end
	if pivots[self] then return pivots[self] end
	local cf = bbox(self)
	return cf
end
roblox.implementMethod("Instance", "WaitForChild", function(self, name) return self:FindFirstChild(name) end)
roblox.implementMethod("Model", "GetPivot", getPivot)
local PART_CLASSES = { "BasePart", "Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", "UnionOperation", "SpawnLocation", "Seat", "VehicleSeat", "PartOperation" }
for _, class in PART_CLASSES do pcall(roblox.implementMethod, class, "GetPivot", getPivot) end
roblox.implementMethod("Model", "GetBoundingBox", function(self) return bbox(self) end)
roblox.implementMethod("Model", "GetExtentsSize", function(self) local _, s = bbox(self); return s end)
local function pivotTo(self, cf)
	local delta = cf * getPivot(self):Inverse()
	for _, p in parts(self) do p.CFrame = delta * p.CFrame end
	if not self:IsA("BasePart") then pivots[self] = cf end
end
roblox.implementMethod("Model", "PivotTo", pivotTo)
for _, class in PART_CLASSES do pcall(roblox.implementMethod, class, "PivotTo", pivotTo) end
roblox.implementMethod("Model", "SetPrimaryPartCFrame", pivotTo)
roblox.implementMethod("Model", "ScaleTo", function(self, s)
		local pivot = getPivot(self)
	local k = s / (self:GetAttribute("__scale") or 1)
	for _, p in parts(self) do
		local rel = pivot:ToObjectSpace(p.CFrame)
		p.Size = p.Size * k
		p.CFrame = pivot * (CFrame.new(rel.Position * k) * rel.Rotation)
	end
	self:SetAttribute("__scale", s)
end)
roblox.implementMethod("Model", "GetScale", function(self) return self:GetAttribute("__scale") or 1 end)
for _, class in PART_CLASSES do pcall(roblox.implementProperty, class, "Position", function(self) return self.CFrame.Position end, function(self, v) self.CFrame = CFrame.new(v) * self.CFrame.Rotation end) end
roblox.implementProperty("BasePart", "Orientation", function(self) local x, y, z = self.CFrame:ToOrientation(); return Vector3.new(math.deg(x), math.deg(y), math.deg(z)) end, function(self, v) self.CFrame = CFrame.new(self.CFrame.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)) end)
roblox.implementProperty("Attachment", "WorldPosition", function(self) local p = self.Parent; return (p and p:IsA("BasePart") and p.CFrame or CFrame.new()):PointToWorldSpace(self.CFrame.Position) end, function(self, v) local p = self.Parent; local base = (p and p:IsA("BasePart") and p.CFrame or CFrame.new()); self.CFrame = CFrame.new(base:PointToObjectSpace(v)) * self.CFrame.Rotation end)
roblox.implementProperty("Attachment", "WorldCFrame", function(self) local p = self.Parent; return (p and p:IsA("BasePart") and p.CFrame or CFrame.new()) * self.CFrame end, function(self, v) local p = self.Parent; local base = (p and p:IsA("BasePart") and p.CFrame or CFrame.new()); self.CFrame = base:ToObjectSpace(v) end)
roblox.implementProperty("Attachment", "Position", function(self) return self.CFrame.Position end, function(self, v) self.CFrame = CFrame.new(v) * self.CFrame.Rotation end)

function H.loadPlace(path)
	local game = roblox.deserializePlace(fs.readFile(path))
	H.game = game
	return game
end

local cache = {}
local env
local function makeEnv()
	local e = {}
	e.game = H.game
	e.workspace = H.game:GetService("Workspace")
	e.Instance = roblox.Instance
	for _, name in { "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "ColorSequence", "ColorSequenceKeypoint", "NumberSequence", "NumberSequenceKeypoint", "NumberRange", "Rect", "Font", "BrickColor", "Ray", "Region3", "Faces", "Axes", "PhysicalProperties", "Enum", "Content" } do
		e[name] = (roblox :: any)[name]
	end
	e.typeof = roblox.typeof or typeof
	e.task = { spawn = function(f, ...) return f(...) end, defer = function(f, ...) end, delay = function() end, wait = function() return 0 end }
	-- Deterministic stand-in for Roblox's Random (Park-Miller).
	e.Random = {
		new = function(seed)
			local st = math.floor(tonumber(seed) or os.clock() * 1000) % 2147483646 + 1
			local r = {}
			local function nxt()
				st = (st * 48271) % 2147483647
				return st / 2147483647
			end
			function r:NextNumber(a, b)
				a, b = a or 0, b or 1
				return a + (b - a) * nxt()
			end
			function r:NextInteger(a, b)
				return math.floor(a + (b - a + 1) * nxt())
			end
			return r
		end,
	}
	e.tick = os.clock
	e.time = os.clock
	e.warn = function(...) print("[warn]", ...) end
	e.print = print
	e.require = function(target)
		return H.require(target)
	end
	setmetatable(e, { __index = _G })
	return e
end

function H.require(inst)
	if cache[inst] ~= nil then
		return cache[inst]
	end
	assert(inst and inst.ClassName == "ModuleScript", "require: not a ModuleScript: " .. tostring(inst))
	local src = inst.Source
	local e = makeEnv()
	e.script = inst
	local fn = luau.load(src, { debugName = inst:GetFullName(), environment = e })
	local result = fn()
	cache[inst] = result
	return result
end

function H.compile(src, name)
	local ok, err = pcall(luau.compile, src)
	if not ok then
		return false, tostring(err)
	end
	return true
end

return H
