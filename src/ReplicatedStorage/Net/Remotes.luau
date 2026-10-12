-- Remotes: the shared RemoteEvents / RemoteFunctions of the new systems. The place build cannot
-- create remotes, so they live in ReplicatedStorage.DOGROTS_Net and are made at run time:
--   Remotes.Event(name, timeout?)      -> RemoteEvent?
--   Remotes.Function(name, timeout?)   -> RemoteFunction?
--   Remotes.Unreliable(name, timeout?) -> UnreliableRemoteEvent (a RemoteEvent where that class does
--                                         not exist), for VFX and other droppable broadcasts
-- On the server the call finds or creates the remote (the folder is created once) and never
-- returns nil; a name already used by a remote of another kind is an error. On a client it waits
-- for the server's remote (WaitForChild, `timeout` seconds, default Remotes.Timeout = 30) and
-- returns nil with a warning when it never comes, so callers must handle nil.
-- Names: a letter, then letters, digits or '_', at most 50 characters (anything else errors).
-- Every OnServerEvent / OnServerInvoke handler checks its argument types and calls Runtime.Allow.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}
Remotes.FolderName = "DOGROTS_Net"
Remotes.Timeout = 30

local cache: { [string]: Instance } = {}
local folder: Instance? = nil

function Remotes.ValidName(name: any): boolean
	return type(name) == "string" and #name <= 50 and string.match(name, "^%a[%w_]*$") ~= nil
end

local function serverFolder(): Instance
	local existing = folder or ReplicatedStorage:FindFirstChild(Remotes.FolderName)
	if not existing then
		local created = Instance.new("Folder")
		created.Name = Remotes.FolderName
		created.Parent = ReplicatedStorage
		existing = created
	end
	folder = existing
	return existing :: Instance
end

-- The class an Unreliable remote gets on this engine.
local unreliableClass: string? = nil
local function newUnreliable(): Instance
	if unreliableClass == nil then
		local ok, remote = pcall(Instance.new, "UnreliableRemoteEvent")
		unreliableClass = ok and "UnreliableRemoteEvent" or "RemoteEvent"
		if ok then
			return remote
		end
	end
	return Instance.new(unreliableClass :: string)
end

local function accepts(kind: string, remote: Instance): boolean
	if kind == "Unreliable" then
		return remote.ClassName == "UnreliableRemoteEvent" or remote.ClassName == "RemoteEvent"
	end
	return remote.ClassName == kind
end

local function waitFor(parent: Instance, name: string, deadline: number): Instance?
	local left = deadline - os.clock()
	if left <= 0 then
		return parent:FindFirstChild(name)
	end
	return parent:WaitForChild(name, left)
end

-- A remote of another kind under `name`: a server bug (error), a client gets nil and a warning.
local function wrongKind(kind: string, remote: Instance): nil
	local message = "Remote " .. remote.Name .. " is a " .. remote.ClassName .. ", not a " .. kind
	if RunService:IsServer() then
		error(message, 3)
	end
	warn("DOGROTS remotes: " .. message)
	return nil
end

local function get(kind: string, name: string, timeout: number?): Instance?
	assert(Remotes.ValidName(name), "Invalid remote name: " .. tostring(name))
	local known = cache[name]
	if known and known.Parent then
		if not accepts(kind, known) then
			return wrongKind(kind, known)
		end
		return known
	end
	if RunService:IsServer() then
		local parent = serverFolder()
		local remote = parent:FindFirstChild(name)
		if remote then
			if not accepts(kind, remote) then
				return wrongKind(kind, remote)
			end
		else
			remote = kind == "Unreliable" and newUnreliable() or Instance.new(kind)
			remote.Name = name
			remote.Parent = parent
		end
		cache[name] = remote
		return remote
	end
	local deadline = os.clock() + (timeout or Remotes.Timeout)
	local parent = folder or waitFor(ReplicatedStorage, Remotes.FolderName, deadline)
	if not parent then
		warn("DOGROTS remotes: ReplicatedStorage." .. Remotes.FolderName .. " never appeared; " .. name .. " is unavailable")
		return nil
	end
	folder = parent
	local remote = waitFor(parent, name, deadline)
	if not remote then
		warn("DOGROTS remotes: the server never created " .. kind .. " " .. name)
		return nil
	end
	if not accepts(kind, remote) then
		return wrongKind(kind, remote)
	end
	cache[name] = remote
	return remote
end

function Remotes.Event(name: string, timeout: number?): RemoteEvent?
	return get("RemoteEvent", name, timeout) :: any
end

function Remotes.Function(name: string, timeout: number?): RemoteFunction?
	return get("RemoteFunction", name, timeout) :: any
end

function Remotes.Unreliable(name: string, timeout: number?): any
	return get("Unreliable", name, timeout)
end

return Remotes
