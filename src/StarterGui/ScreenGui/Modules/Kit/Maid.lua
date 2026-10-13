-- Cleanup bag (maid / janitor pattern). Give it connections, instances, functions, threads,
-- tweens or objects with Destroy / Disconnect; Clean() releases everything in reverse order.
local Maid = {}
Maid.__index = Maid

function Maid.new(): any
	local self: any = setmetatable({}, Maid)
	self._tasks = {}
	return self
end

function Maid.Give(self: any, item: any): any
	if item ~= nil then
		table.insert(self._tasks, item)
	end
	return item
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

function Maid.Clean(self: any)
	local tasks = self._tasks
	self._tasks = {}
	for i = #tasks, 1, -1 do
		local ok, err = pcall(release, tasks[i])
		if not ok then
			warn("Kit.Maid cleanup failed: " .. tostring(err))
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
