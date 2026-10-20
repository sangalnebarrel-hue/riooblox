-- Client-side signal hub of the Halloween event (ReplicatedStorage.Halloween.Bus). One table per client (require cache).
-- Bus.On(name, fn) -> {Disconnect}; Bus.Fire(name, data); Bus.Last(name) -> last data fired (late subscribers).
-- Listeners run in protected threads so one failing module never breaks another.
local Bus = {}
local listeners = {}
local last = {}

function Bus.On(name: string, fn: (any) -> ())
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	local entry = { Fn = fn, Alive = true }
	table.insert(list, entry)
	return {
		Disconnect = function()
			entry.Alive = false
			local l = listeners[name]
			local i = l and table.find(l, entry)
			if i then
				table.remove(l, i)
			end
		end,
	}
end

function Bus.Fire(name: string, data: any)
	last[name] = data
	local list = listeners[name]
	if not list then
		return
	end
	for _, entry in ipairs(table.clone(list)) do
		if entry.Alive then
			task.spawn(function()
				local ok, err = pcall(entry.Fn, data)
				if not ok then
					warn("Halloween Bus listener failed (" .. name .. "): " .. tostring(err))
				end
			end)
		end
	end
end

function Bus.Last(name: string): any
	return last[name]
end

return Bus
