--!nolint
-- Offline Roblox environment for build-time builder modules (run by tools/place_build.luau).
-- Builder ModuleScripts that live in the place (ServerStorage.HalloweenBuild, ServerStorage.UnderyardBuild, ...) are
-- executed here with the place's own DataModel, so their output is SAVED in the place and can be edited in Studio.
--
-- What the environment provides on top of Lune's roblox library:
--   * require(ModuleScript) that runs the module's Source from the place (cached per instance, like Roblox)
--   * game / workspace / script globals, game:GetService
--   * Random (Park-Miller, deterministic per seed; Lune has no Random)
--   * CFrame.lookAt that matches Roblox (Lune's is mirrored)
--   * Model:GetPivot / Model:PivotTo (PrimaryPart pivot, else bounding-box centre)
--   * task / tick / os / DateTime stubs (builders must not yield)
-- Builders must only use Instance.new + datatypes; services such as TweenService do not exist here.
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")

local Sim = {}

local V3 = roblox.Vector3
local RCF = roblox.CFrame

local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-6 then
		return RCF.new(at)
	end
	look = look.Unit
	local upHint = up or V3.new(0, 1, 0)
	local right = look:Cross(upHint)
	if right.Magnitude < 1e-6 then
		right = look:Cross(V3.new(0, 0, -1))
	end
	right = right.Unit
	return RCF.fromMatrix(at, right, right:Cross(look).Unit, -look)
end

local CFrameShim = setmetatable({ lookAt = lookAt }, { __index = RCF })

local RandomShim = {}
function RandomShim.new(seed)
	local state = math.floor(math.abs(seed or 1)) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local r = {}
	function r:NextNumber(a, b)
		state = (state * 48271) % 2147483647
		local u = (state - 1) / 2147483646
		if a == nil then
			return u
		end
		return a + (b - a) * u
	end
	function r:NextInteger(a, b)
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	function r:NextUnitVector()
		local z = self:NextNumber(-1, 1)
		local t = self:NextNumber(0, math.pi * 2)
		local s = math.sqrt(1 - z * z)
		return V3.new(s * math.cos(t), s * math.sin(t), z)
	end
	function r:Clone()
		return RandomShim.new(state)
	end
	return r
end

local function boundsCentre(model)
	local minV, maxV
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.Position
			local h = d.Size / 2
			local lo, hi = p - h, p + h
			if not minV then
				minV, maxV = lo, hi
			else
				minV = V3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z))
				maxV = V3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z))
			end
		end
	end
	if not minV then
		return RCF.new()
	end
	return RCF.new((minV + maxV) / 2)
end

local installed = false
local function installMethods()
	if installed then
		return
	end
	installed = true
	roblox.implementMethod("Model", "GetPivot", function(self)
		local pp = self.PrimaryPart
		if pp then
			return pp.CFrame
		end
		return boundsCentre(self)
	end)
	roblox.implementMethod("Model", "PivotTo", function(self, cf)
		local pp = self.PrimaryPart
		local pivot = pp and pp.CFrame or boundsCentre(self)
		local delta = cf * pivot:Inverse()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = delta * d.CFrame
			end
		end
	end)
end

-- Sim.new(game) -> sim with sim:require(moduleScript) and sim.env (shared globals)
function Sim.new(game)
	installMethods()
	local sim = { cache = {}, loading = {} }
	local globals = {
		game = game,
		workspace = game:GetService("Workspace"),
		Random = RandomShim,
		CFrame = CFrameShim,
		task = {
			wait = function()
				return 0
			end,
			spawn = function(f, ...)
				return f(...)
			end,
			defer = function(f, ...)
				return f(...)
			end,
			delay = function() end,
		},
		tick = function()
			return 0
		end,
		time = function()
			return 0
		end,
		warn = function(...)
			print("[warn]", ...)
		end,
		print = print,
		typeof = typeof,
	}
	local std = {
		math = math, string = string, table = table, utf8 = utf8, bit32 = bit32, buffer = buffer, coroutine = coroutine,
		os = os, debug = debug, pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring,
		tonumber = tonumber, pcall = pcall, xpcall = xpcall, error = error, assert = assert, select = select,
		setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal,
		rawlen = rawlen, unpack = table.unpack, newproxy = newproxy,
	}
	for k, v in std do
		globals[k] = v
	end
	for _, k in { "Axes", "BrickColor", "Color3", "ColorSequence", "ColorSequenceKeypoint", "Content", "Enum", "Faces", "Font", "Instance", "NumberRange", "NumberSequence", "NumberSequenceKeypoint", "PhysicalProperties", "Ray", "Rect", "Region3", "Region3int16", "UDim", "UDim2", "Vector2", "Vector2int16", "Vector3", "Vector3int16" } do
		globals[k] = roblox[k]
	end
	sim.globals = globals

	function sim:require(module)
		assert(typeof(module) == "Instance" and module:IsA("ModuleScript"), "sim:require expects a ModuleScript, got " .. tostring(module))
		local cached = self.cache[module]
		if cached ~= nil then
			return cached
		end
		assert(not self.loading[module], "cyclic require of " .. module:GetFullName())
		self.loading[module] = true
		local env = setmetatable({ script = module }, {
			__index = function(_, key)
				return globals[key]
			end,
		})
		env.require = function(target)
			return self:require(target)
		end
		local fn = luau.load(module.Source, { debugName = module:GetFullName(), environment = env })
		local result = fn()
		self.loading[module] = nil
		self.cache[module] = result
		return result
	end

	return sim
end

Sim.lookAt = lookAt
Sim.Random = RandomShim

return Sim
