--!nocheck
--!nolint
-- ReplicatedStorage.Net.Remotes on fake instances (server find-or-create, client wait with a
-- timeout, Unreliable fallback, name rules): lune run tests/remotes.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end
local function read(path)
	for _, prefix in { "", "../" } do
		local ok, text = pcall(fs.readFile, prefix .. path)
		if ok then
			return text
		end
	end
	error("cannot read " .. path)
end
local SOURCE = read("src/ReplicatedStorage/Net/Remotes.luau")

-- ===== A tiny instance tree =====
local Instance = {}
Instance.__index = function(self, k)
	if Instance[k] then
		return Instance[k]
	end
	if k == "Parent" then
		return rawget(self, "_parent")
	end
	return rawget(self, "_children")[k]
end
Instance.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			rawget(old, "_children")[self.Name] = nil
		end
		rawset(self, "_parent", v)
		if v then
			rawget(v, "_children")[self.Name] = self
		end
	else
		rawset(self, k, v)
	end
end
local function make(className, name)
	return setmetatable({ ClassName = className, Name = name or className, _children = {} }, Instance)
end
function Instance.FindFirstChild(self, name)
	return rawget(self, "_children")[name]
end

-- A world: ReplicatedStorage, server or client, optional missing classes and "appears later" hooks.
local function world(opts)
	opts = opts or {}
	local W = { Created = {}, Warnings = {}, Waits = {}, Later = {} }
	local rs = make("ReplicatedStorage")
	W.RS = rs
	function rs.WaitForChild(self, name, timeout)
		return Instance.WaitForChild(self, name, timeout)
	end
	function Instance.WaitForChild(self, name, timeout)
		table.insert(W.Waits, { Name = name, Timeout = timeout })
		local child = rawget(self, "_children")[name]
		if child then
			return child
		end
		local later = W.Later[name]
		if later then
			W.Later[name] = nil
			local made = later()
			made.Parent = self
			return made
		end
		return nil
	end
	local env = setmetatable({
		game = {
			GetService = function(_, service)
				if service == "RunService" then
					return { IsServer = function() return opts.Server ~= false end }
				end
				return rs
			end,
		},
		Instance = {
			new = function(className)
				if opts.Missing and opts.Missing[className] then
					error("Unable to create an Instance of type \"" .. className .. "\"")
				end
				local obj = make(className)
				table.insert(W.Created, className)
				return obj
			end,
		},
		warn = function(...)
			table.insert(W.Warnings, table.concat({ ... }, " "))
		end,
		os = { clock = function() return 100 end },
	}, { __index = _G })
	W.Remotes = luau.load(SOURCE, { debugName = "Remotes", environment = env })()
	function W.Count(className)
		local n = 0
		for _, c in W.Created do
			if c == className then
				n += 1
			end
		end
		return n
	end
	return W
end

-- ===== Server =====
test("the server creates the folder once and finds or creates each remote", function()
	local W = world()
	local event = W.Remotes.Event("TradeInvite")
	eq(event.ClassName, "RemoteEvent")
	eq(event.Name, "TradeInvite")
	local folder = W.RS:FindFirstChild("DOGROTS_Net")
	truthy(folder and folder.ClassName == "Folder", "folder")
	eq(event.Parent, folder)
	eq(W.Remotes.Event("TradeInvite"), event, "same remote again")
	local fn = W.Remotes.Function("ShowcaseQuery")
	eq(fn.ClassName, "RemoteFunction")
	eq(fn.Parent, folder)
	eq(W.Count("Folder"), 1, "one folder")
	eq(W.Count("RemoteEvent"), 1)
	eq(W.Count("RemoteFunction"), 1)
end)

test("the server reuses remotes already in the folder", function()
	local W = world()
	local folder = make("Folder", "DOGROTS_Net")
	folder.Parent = W.RS
	local existing = make("RemoteEvent", "RushCatch")
	existing.Parent = folder
	eq(W.Remotes.Event("RushCatch"), existing)
	eq(#W.Created, 0, "nothing new")
end)

test("Unreliable makes an UnreliableRemoteEvent, or a RemoteEvent where the class is missing", function()
	local W = world()
	eq(W.Remotes.Unreliable("RushFX").ClassName, "UnreliableRemoteEvent")
	local old = world({ Missing = { UnreliableRemoteEvent = true } })
	local fallback = old.Remotes.Unreliable("RushFX")
	eq(fallback.ClassName, "RemoteEvent")
	eq(old.Remotes.Unreliable("TitleFX").ClassName, "RemoteEvent", "the missing class is not retried")
	eq(old.Remotes.Unreliable("RushFX"), fallback)
end)

test("a name used by another kind of remote is an error", function()
	local W = world()
	W.Remotes.Event("Clash")
	local ok, err = pcall(W.Remotes.Function, "Clash")
	eq(ok, false)
	truthy(tostring(err):find("is a RemoteEvent, not a RemoteFunction", 1, true), tostring(err))
	local fresh = world()
	local folder = make("Folder", "DOGROTS_Net")
	folder.Parent = fresh.RS
	make("RemoteFunction", "Other").Parent = folder
	ok = pcall(fresh.Remotes.Event, "Other")
	eq(ok, false, "an existing remote of another kind")
end)

test("names must be a letter then letters, digits or '_' (at most 50)", function()
	local W = world()
	for _, bad in { "", "1abc", "a b", "a.b", "a-b", string.rep("a", 51), 5, nil } do
		local ok, err = pcall(W.Remotes.Event, bad)
		eq(ok, false, "accepted " .. tostring(bad))
		truthy(tostring(err):find("Invalid remote name", 1, true), tostring(err))
	end
	truthy(W.Remotes.Event("Trade_Invite2"), "a good name")
	truthy(W.Remotes.ValidName(string.rep("a", 50)))
	eq(#W.Warnings, 0)
end)

-- ===== Client =====
test("a client waits for the server's remote (30 s by default)", function()
	local W = world({ Server = false })
	local folder = make("Folder", "DOGROTS_Net")
	folder.Parent = W.RS
	local remote = make("RemoteEvent", "TradeInvite")
	remote.Parent = folder
	eq(W.Remotes.Event("TradeInvite"), remote)
	eq(#W.Created, 0, "clients never create remotes")
	for _, call in W.Waits do
		eq(call.Timeout, 30, "timeout of " .. call.Name)
	end
	W.Later.ShowcaseQuery = function()
		return make("RemoteFunction", "ShowcaseQuery")
	end
	eq(W.Remotes.Function("ShowcaseQuery").ClassName, "RemoteFunction", "arrives while waiting")
end)

test("a client gets nil and a clear warning when the remote never comes", function()
	local W = world({ Server = false })
	eq(W.Remotes.Event("TradeInvite", 5), nil)
	truthy(W.Warnings[1] and W.Warnings[1]:find("DOGROTS_Net never appeared", 1, true), tostring(W.Warnings[1]))
	eq(W.Waits[1].Timeout, 5, "custom timeout")
	local folder = make("Folder", "DOGROTS_Net")
	folder.Parent = W.RS
	eq(W.Remotes.Function("Missing"), nil)
	truthy(W.Warnings[2] and W.Warnings[2]:find("never created RemoteFunction Missing", 1, true), tostring(W.Warnings[2]))
	make("RemoteFunction", "Wrong").Parent = folder
	eq(W.Remotes.Event("Wrong"), nil, "wrong kind")
	truthy(W.Warnings[3] and W.Warnings[3]:find("Remote Wrong is a RemoteFunction, not a RemoteEvent", 1, true), tostring(W.Warnings[3]))
end)

test("a client's Unreliable accepts the RemoteEvent fallback", function()
	local W = world({ Server = false })
	local folder = make("Folder", "DOGROTS_Net")
	folder.Parent = W.RS
	local fallback = make("RemoteEvent", "RushFX")
	fallback.Parent = folder
	eq(W.Remotes.Unreliable("RushFX"), fallback)
	local real = make("UnreliableRemoteEvent", "TitleFX")
	real.Parent = folder
	eq(W.Remotes.Unreliable("TitleFX"), real)
	eq(W.Remotes.Event("TitleFX"), nil, "an UnreliableRemoteEvent is not an Event")
end)

print(("remotes: %d passed, %d failed"):format(passed, failed))
process.exit(failed > 0 and 1 or 0)
