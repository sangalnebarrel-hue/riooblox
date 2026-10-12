-- Cleanup bag (maid / janitor pattern) for any client or server system. The UI kit's
-- StarterGui.ScreenGui.Modules.Kit.Maid forwards here, so both share one implementation.
--   local maid = Maid.new()
--   maid:Give(connection | instance | function | thread | tween | object with Destroy/Disconnect/Cancel)
--   maid:Connect(signal, fn)        -- connects and gives the connection
--   maid:Set("highlight", item)     -- keyed slot: cleans the previous item in that slot (nil clears)
--   maid:Clean()                    -- releases everything in reverse order (Destroy is an alias)
-- One failing cleanup never stops the others; it is reported with warn.
local Maid = {}
Maid.__index = Maid

function Maid.new(): any
	local self: any = setmetatable({}, Maid)
	self._tasks = {}
	self._keys = {}
	return self
end

local function release(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		task.cancel(item)
	elseif type(item) == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Cancel) == "function" then
			item:Cancel()
		end
	end
end

local function safeRelease(item: any)
	local ok, err = pcall(release, item)
	if not ok then
		warn("Perf.Maid cleanup failed: " .. tostring(err))
	end
end

function Maid.Give(self: any, item: any): any
	if item ~= nil then
		table.insert(self._tasks, item)
	end
	return item
end

function Maid.Connect(self: any, signal: any, fn: (...any) -> ()): any
	return self:Give(signal:Connect(fn))
end

-- Keyed slot: the previous item under `key` is released first; nil just clears the slot.
function Maid.Set(self: any, key: any, item: any): any
	local previous = self._keys[key]
	self._keys[key] = item
	if previous ~= nil and previous ~= item then
		safeRelease(previous)
	end
	return item
end

function Maid.Get(self: any, key: any): any
	return self._keys[key]
end

function Maid.Clean(self: any)
	local tasks = self._tasks
	local keys = self._keys
	self._tasks = {}
	self._keys = {}
	for _, item in pairs(keys) do
		safeRelease(item)
	end
	for i = #tasks, 1, -1 do
		safeRelease(tasks[i])
	end
end

Maid.Destroy = Maid.Clean

return Maid
