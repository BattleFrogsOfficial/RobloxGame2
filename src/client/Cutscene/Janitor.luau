--!strict
-- Cleanup bag for one cutscene: every instance, connection, tween, sound, thread and callback it creates goes
-- in here, and Clean() releases all of them (on finish, skip, error, death or character removal). Clean() is
-- idempotent and never throws.
local Janitor = {}
Janitor.__index = Janitor

export type Janitor = typeof(setmetatable({} :: { _items: { any }, _cleaned: boolean }, Janitor))

function Janitor.new(): Janitor
	return setmetatable({ _items = {}, _cleaned = false }, Janitor)
end

-- Adds an item and returns it. A late Add after Clean releases the item immediately.
function Janitor.Add<T>(self: Janitor, item: T): T
	if self._cleaned then
		Janitor._release(item)
	else
		table.insert(self._items, item)
	end
	return item
end

function Janitor._release(item: any)
	pcall(function()
		local kind = typeof(item)
		if kind == "Instance" then
			if item:IsA("Tween") then
				item:Cancel()
			elseif item:IsA("Sound") then
				item:Stop()
			end
			item:Destroy()
		elseif kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "function" then
			item()
		elseif kind == "thread" then
			if coroutine.status(item) ~= "dead" and coroutine.running() ~= item then
				task.cancel(item)
			end
		elseif kind == "table" then
			if type(item.Disconnect) == "function" then
				item:Disconnect()
			elseif type(item.Destroy) == "function" then
				item:Destroy()
			elseif type(item.Cancel) == "function" then
				item:Cancel()
			end
		end
	end)
end

function Janitor.Clean(self: Janitor)
	if self._cleaned then
		return
	end
	self._cleaned = true
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		Janitor._release(items[i])
	end
end

return Janitor
