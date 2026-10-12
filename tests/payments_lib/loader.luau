--!nocheck
--!nolint
-- Minimal Roblox-like loader for server modules in src/ (Rojo layout), used by tests/payments.luau.
-- Every module gets a fake `script` whose Parent chain resolves sibling modules by name, a fake
-- `game` with stub services, Instance.new for plain containers, and a controllable os.time.
-- Overrides[path] replaces any module (path = "ServerScriptService/Economy/Rules").
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local SRC = "src"
local L = { Overrides = {}, Cache = {}, Services = {}, Warnings = {}, Prints = {}, Fired = {}, Verbose = false, Now = nil }

-- The src tree is indexed once up front: Lune's fs calls yield, and lookups happen inside
-- metamethods (script.Parent.X), which must not yield.
local FILES, DIRS, LISTING = {}, {}, {}
local function scan(rel)
	local names = {}
	LISTING[rel] = names
	for _, entry in fs.readDir(SRC .. (rel == "" and "" or "/" .. rel)) do
		local full = rel == "" and entry or rel .. "/" .. entry
		if fs.isDir(SRC .. "/" .. full) then
			DIRS[full] = true
			names[entry] = true
			scan(full)
		else
			local name = entry
			for _, suffix in { "%.server%.luau$", "%.client%.luau$", "%.luau$" } do
				if name:match(suffix) then
					name = (name:gsub(suffix, ""))
					local key = rel == "" and name or rel .. "/" .. name
					FILES[key] = SRC .. "/" .. full
					names[name] = true
					break
				end
			end
		end
	end
end
scan("")
local function fileFor(path)
	return FILES[path]
end
local function isFolder(path)
	return DIRS[path] == true
end

-- ===== Instances (src-backed nodes and runtime-created objects share one metatable) =====
local Meta, Methods, nodes = {}, {}, {}
local function new(fields)
	fields.__attrs = fields.__attrs or {}
	fields.__children = fields.__children or {}
	fields.__props = fields.__props or {}
	return setmetatable(fields, Meta)
end
local function node(path)
	if nodes[path] == nil then
		nodes[path] = new({ __path = path, __name = path:match("([^/]+)$") })
	end
	return nodes[path]
end
L.Node = node
local function srcChild(obj, name)
	local path = rawget(obj, "__path")
	if not path or type(name) ~= "string" then
		return nil
	end
	local childPath = path .. "/" .. name
	if L.Overrides[childPath] ~= nil or fileFor(childPath) or isFolder(childPath) then
		return node(childPath)
	end
	return nil
end
function Methods:FindFirstChild(name)
	return rawget(self, "__children")[name] or srcChild(self, name)
end
function Methods:WaitForChild(name)
	return self:FindFirstChild(name) or error("WaitForChild: missing " .. tostring(name))
end
function Methods:GetChildren()
	local out, seen = {}, {}
	for name, child in rawget(self, "__children") do
		seen[name] = true
		table.insert(out, child)
	end
	local path = rawget(self, "__path")
	if path and LISTING[path] then
		for name in LISTING[path] do
			if not seen[name] then
				seen[name] = true
				table.insert(out, node(path .. "/" .. name))
			end
		end
	end
	return out
end
function Methods:IsA(class)
	local own = rawget(self, "__class")
	if own then
		return own == class or class == "Instance"
	end
	local path = rawget(self, "__path")
	local file = path and fileFor(path)
	if class == "ModuleScript" then
		return file ~= nil and not file:match("%.server%.luau$") and not file:match("%.client%.luau$")
	elseif class == "Folder" then
		return file == nil and path ~= nil and isFolder(path)
	end
	return class == "Instance"
end
function Methods:SetAttribute(k, v)
	rawget(self, "__attrs")[k] = v
end
function Methods:GetAttribute(k)
	return rawget(self, "__attrs")[k]
end
function Methods:Destroy()
	self.Parent = nil
end
function Methods:FireClient(player, payload)
	table.insert(L.Fired, { Remote = self.Name, Player = player, Payload = payload })
end
function Methods:FireAllClients(payload)
	table.insert(L.Fired, { Remote = self.Name, All = true, Payload = payload })
end
function Methods:Invoke(...)
	local fn = rawget(self, "__props").OnInvoke
	return fn(...)
end
Meta.__index = function(self, k)
	if Methods[k] then
		return Methods[k]
	end
	if k == "Name" then
		return rawget(self, "__name")
	end
	if k == "ClassName" then
		return rawget(self, "__class") or "ModuleScript"
	end
	if k == "Parent" then
		local parent = rawget(self, "__parent")
		if parent ~= nil then
			return parent
		end
		local path = rawget(self, "__path")
		if path then
			local up = path:match("^(.*)/[^/]+$")
			if up then
				return node(up)
			end
			return rawget(self, "__detached") and nil or L.Game
		end
		return nil
	end
	local props = rawget(self, "__props")
	if props[k] ~= nil then
		return props[k]
	end
	local child = rawget(self, "__children")[k]
	if child ~= nil then
		return child
	end
	return srcChild(self, k)
end
Meta.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "__parent")
		if old ~= nil then
			rawget(old, "__children")[rawget(self, "__name")] = nil
		end
		rawset(self, "__parent", v)
		rawset(self, "__detached", v == nil)
		if v ~= nil then
			rawget(v, "__children")[rawget(self, "__name")] = self
		end
		return
	end
	if k == "Name" then
		rawset(self, "__name", v)
		return
	end
	rawget(self, "__props")[k] = v
end
function L.Instance(className, props)
	local obj = new({ __class = className, __name = className })
	for k, v in props or {} do
		obj[k] = v
	end
	return obj
end
function L.IsInstance(v)
	return type(v) == "table" and getmetatable(v) == Meta
end

-- ===== Signals, Enum, game =====
function L.Signal()
	local s = { Handlers = {} }
	function s:Connect(fn)
		table.insert(self.Handlers, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, h in self.Handlers do
			task.spawn(h, ...)
		end
	end
	return s
end
L.Enum = setmetatable({}, {
	__index = function(_, e)
		return setmetatable({}, {
			__index = function(_, item)
				return "Enum." .. e .. "." .. item
			end,
		})
	end,
})
L.Game = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return function(_, name)
				return L.Services[name] or node(name)
			end
		end
		return L.Services[k] or node(k)
	end,
})

local Random = {}
function Random.new(seed)
	local state = ((seed or 1) % 2147483646) + 1
	local r = {}
	function r:NextNumber(a, b)
		state = (state * 48271) % 2147483647
		local x = state / 2147483647
		if a and b then
			return a + (b - a) * x
		end
		return x
	end
	function r:NextInteger(a, b)
		return a + math.floor(self:NextNumber() * (b - a + 1))
	end
	return r
end

local function stub()
	return setmetatable({}, {
		__index = function()
			return function(...)
				return stub()
			end
		end,
		__call = function()
			return stub()
		end,
	})
end

local function collect(list, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	table.insert(list, table.concat(parts, " "))
	return table.concat(parts, " ")
end
local fakeOs = setmetatable({
	time = function(t)
		if t then
			return os.time(t)
		end
		return L.Now or os.time()
	end,
}, { __index = os })

local function env(path)
	return setmetatable({
		script = node(path),
		game = L.Game,
		workspace = node("Workspace"),
		Enum = L.Enum,
		task = task,
		require = L.Require,
		Instance = { new = function(className) return L.Instance(className) end },
		Random = Random,
		warn = function(...)
			local line = collect(L.Warnings, ...)
			if L.Verbose then
				print("[warn] " .. line)
			end
		end,
		print = function(...)
			local line = collect(L.Prints, ...)
			if L.Verbose then
				print(line)
			end
		end,
		typeof = function(v)
			if L.IsInstance(v) then
				return "Instance"
			end
			return typeof(v)
		end,
		Color3 = stub(), Vector3 = stub(), CFrame = stub(), UDim2 = stub(), UDim = stub(), NumberRange = stub(),
		ColorSequence = stub(), NumberSequence = stub(), BrickColor = stub(), TweenInfo = stub(), Vector2 = stub(),
		os = fakeOs, math = math, string = string, table = table, bit32 = bit32, utf8 = utf8, buffer = buffer,
		coroutine = coroutine, type = type, pairs = pairs, ipairs = ipairs, next = next, select = select,
		tostring = tostring, tonumber = tonumber, pcall = pcall, xpcall = xpcall, error = error, assert = assert,
		setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
		rawequal = rawequal, rawlen = rawlen, unpack = table.unpack, debug = debug, shared = {},
	}, {
		__index = function()
			return nil
		end,
	})
end

function L.Require(target)
	local path = type(target) == "string" and target or rawget(target, "__path")
	assert(path, "require: not a module")
	if L.Overrides[path] ~= nil then
		return L.Overrides[path]
	end
	if L.Cache[path] ~= nil then
		return L.Cache[path]
	end
	local file = fileFor(path)
	assert(file, "module not found: " .. tostring(path))
	local chunk = luau.load(fs.readFile(file), { debugName = path, environment = env(path) })
	local result = chunk()
	L.Cache[path] = result
	return result
end

-- Fresh module state (keeps services and overrides).
function L.Reset()
	L.Cache = {}
	nodes = {}
	L.Warnings, L.Prints, L.Fired = {}, {}, {}
end

return L
