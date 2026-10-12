--!nocheck
-- Runs real ModuleScripts from src/ in Lune: a tiny Instance-like tree over the Rojo file layout
-- (X.luau = ModuleScript, X.server.luau = Script, X.client.luau = LocalScript, folders = Folder),
-- with stubs for the few Roblox services the economy modules touch. Not a test by itself
-- (tests/*.luau are the tests); require it from a test as "./lib/economy_env".
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local L = {}
local ROOT = (process.env.DOGROTS_SRC or "src"):gsub("/$", "")
L.Time = 1760000000

local sig = {
	Connect = function()
		return { Disconnect = function() end }
	end,
	Once = function()
		return { Disconnect = function() end }
	end,
	Wait = function() end,
}
local guid = 0
L.Stubs = {
	RunService = {
		IsServer = function() return true end,
		IsClient = function() return false end,
		IsStudio = function() return false end,
		Heartbeat = sig,
		Stepped = sig,
		RenderStepped = sig,
	},
	Players = {
		GetPlayers = function() return {} end,
		PlayerAdded = sig,
		PlayerRemoving = sig,
		GetPlayerByUserId = function() return nil end,
	},
	HttpService = {
		GenerateGUID = function()
			guid += 1
			return string.format("%032x", guid)
		end,
		JSONEncode = function(_, v) return require("@lune/serde").encode("json", v) end,
		JSONDecode = function(_, v) return require("@lune/serde").decode("json", v) end,
	},
	LocalizationService = { RobloxLocaleId = "en-us" },
}

-- Deterministic stand-in for Roblox's Random.
local function newRandom(seed)
	local state = math.floor(tonumber(seed) or 1) % 2147483647
	if state <= 0 then state += 2147483646 end
	local r = {}
	function r:NextNumber(a, b)
		state = (state * 48271) % 2147483647
		local x = state / 2147483647
		if a then return a + (b - a) * x end
		return x
	end
	function r:NextInteger(a, b)
		return a + math.floor(self:NextNumber() * (b - a + 1))
	end
	return r
end
L.Random = { new = newRandom }

-- The whole src tree is indexed once up front: fs calls yield, and metamethods cannot.
local FILES, DIRS = {}, { [""] = true }
local function scan(rel)
	local dir = ROOT .. (rel == "" and "" or "/" .. rel)
	for _, entry in ipairs(fs.readDir(dir)) do
		local p = rel == "" and entry or rel .. "/" .. entry
		if fs.isDir(ROOT .. "/" .. p) then
			DIRS[p] = true
			scan(p)
		else
			FILES[p] = fs.readFile(ROOT .. "/" .. p)
		end
	end
end
scan("")
local function exists(path)
	return FILES[path:sub(#ROOT + 2)] ~= nil
end
local function isDir(path)
	local rel = path == ROOT and "" or path:sub(#ROOT + 2)
	return DIRS[rel] == true
end
-- path is relative to src ("" = game).
local function fileOf(path)
	for _, ext in ipairs({ ".luau", ".server.luau", ".client.luau", ".lua" }) do
		if exists(ROOT .. "/" .. path .. ext) then return ROOT .. "/" .. path .. ext, ext end
	end
	return nil
end
local classOf = { [".luau"] = "ModuleScript", [".lua"] = "ModuleScript", [".server.luau"] = "Script", [".client.luau"] = "LocalScript" }

local proxies = {}
local requireNode
local makeNode
local function childNames(path)
	local names, seen = {}, {}
	local prefix = path == "" and "" or path .. "/"
	local entries = {}
	for f in pairs(FILES) do
		if f:sub(1, #prefix) == prefix and not f:sub(#prefix + 1):find("/") then table.insert(entries, f:sub(#prefix + 1)) end
	end
	for d in pairs(DIRS) do
		if d ~= "" and d:sub(1, #prefix) == prefix and not d:sub(#prefix + 1):find("/") then table.insert(entries, d:sub(#prefix + 1)) end
	end
	for _, entry in ipairs(entries) do
		local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", ""):gsub("%.lua$", "")
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end
local function childPath(path, name)
	local p = path == "" and name or path .. "/" .. name
	if fileOf(p) or isDir(ROOT .. "/" .. p) then return p end
	return nil
end
makeNode = function(path)
	if proxies[path] then return proxies[path] end
	local name = path:match("([^/]+)$") or "game"
	local file, ext = fileOf(path)
	local className = file and classOf[ext] or "Folder"
	local node = {}
	local methods = {}
	function methods.FindFirstChild(_, child)
		local p = childPath(path, child)
		return p and makeNode(p) or nil
	end
	methods.WaitForChild = methods.FindFirstChild
	function methods.GetChildren()
		local out = {}
		for _, n in ipairs(childNames(path)) do table.insert(out, makeNode(childPath(path, n))) end
		return out
	end
	function methods.GetDescendants()
		local out = {}
		local function walk(p)
			for _, n in ipairs(childNames(p)) do
				local c = childPath(p, n)
				table.insert(out, makeNode(c))
				walk(c)
			end
		end
		walk(path)
		return out
	end
	function methods.IsA(_, class)
		return class == className or (class == "LuaSourceContainer" and className ~= "Folder") or class == "Instance"
	end
	function methods.GetAttribute() return nil end
	function methods.SetAttribute() end
	function methods.GetFullName() return path end
	function methods.GetService(_, service)
		if L.Stubs[service] then return L.Stubs[service] end
		return makeNode(service)
	end
	function methods.GetAttributeChangedSignal() return sig end
	function methods.GetPropertyChangedSignal() return sig end
	setmetatable(node, {
		__index = function(_, k)
			if methods[k] then return methods[k] end
			if k == "Name" then return name end
			if k == "ClassName" then return className end
			if k == "Parent" then
				if path == "" then return nil end
				return makeNode(path:match("^(.*)/[^/]+$") or "")
			end
			if path == "" and L.Stubs[k] then return L.Stubs[k] end
			local p = childPath(path, k)
			return p and makeNode(p) or nil
		end,
		__tostring = function() return name end,
	})
	proxies[path] = node
	L.Paths = L.Paths or {}
	L.Paths[node] = path
	return node
end

local cache = {}
local game = makeNode("")
local workspaceStub = setmetatable({
	GetServerTimeNow = function() return L.Time end,
	FindFirstChild = function() return nil end,
}, { __index = function() return nil end })
L.Game = game
L.Overrides = {}
requireNode = function(target)
	local path = L.Paths[target]
	assert(path, "require: not a src module")
	if L.Overrides[path] ~= nil then return L.Overrides[path] end
	if cache[path] ~= nil then return cache[path] end
	local file = fileOf(path)
	assert(file, "require: no source for " .. path)
	local source = FILES[file:sub(#ROOT + 2)]
	local env = setmetatable({
		script = target,
		game = game,
		-- A test may set L.Workspace (before the first require) for modules that walk the world.
		workspace = L.Workspace or workspaceStub,
		require = requireNode,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Enum = roblox.Enum,
		Font = roblox.Font,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Instance = roblox.Instance,
		typeof = typeof,
		warn = function(...) if L.Verbose then print("warn:", ...) end end,
		print = function(...) if L.Verbose then print(...) end end,
		task = { wait = function() end, spawn = function() end, defer = function() end, delay = function() end },
		Random = L.Random,
		tick = os.clock,
		os = setmetatable({ time = function() return L.Time end }, { __index = os }),
	}, { __index = _G })
	local fn = luau.load(source, { debugName = file, environment = env })
	local result = fn()
	cache[path] = result
	return result
end
L.Require = function(path)
	return requireNode(makeNode((path:gsub("%.", "/"))))
end
L.Reset = function()
	cache = {}
end
return L
