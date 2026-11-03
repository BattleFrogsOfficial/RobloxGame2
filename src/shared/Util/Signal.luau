--!strict
-- Tiny signal. Handlers run in their own thread (task.spawn) so one error never breaks the others.
local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }
export type Signal = typeof(setmetatable({} :: { _handlers: { [any]: (...any) -> () } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local key = {}
	self._handlers[key] = fn
	local conn = { Connected = true } :: any
	function conn.Disconnect(c: any)
		c.Connected = false
		self._handlers[key] = nil
	end
	return conn
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local conn: Connection
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Fire(self: Signal, ...: any)
	for _, fn in self._handlers do
		task.spawn(fn, ...)
	end
end

-- Yields until the next Fire; returns its arguments.
function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	table.clear(self._handlers)
end

return Signal
