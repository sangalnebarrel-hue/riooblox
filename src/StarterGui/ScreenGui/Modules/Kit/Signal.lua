-- Minimal signal for kit components: no BindableEvent, no instance per signal.
-- Handlers run in their own thread (task.spawn), so one failing handler does not stop the others.
local Signal = {}
Signal.__index = Signal

function Signal.new(): any
	local self: any = setmetatable({}, Signal)
	self._handlers = {}
	return self
end

function Signal.Connect(self: any, fn: (...any) -> ()): any
	local handlers = self._handlers
	local handler = { Fn = fn, Connected = true }
	table.insert(handlers, handler)
	local connection: any = { Connected = true }
	function connection.Disconnect(conn: any)
		if not handler.Connected then
			return
		end
		handler.Connected = false
		conn.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal.Once(self: any, fn: (...any) -> ()): any
	local connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: any, ...: any)
	for _, handler in ipairs(table.clone(self._handlers)) do
		if handler.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
end

function Signal.DisconnectAll(self: any)
	for _, handler in ipairs(self._handlers) do
		handler.Connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
