--!strict
-- FIFO queue for the one shared throwing platform. Pure (no Roblox services) so it can be tested in Lune.
-- Entries are opaque keys (Players on the server). Position 1 = the current turn; 2+ = waiting.
-- ThrowService owns presence sampling, attributes and teleports; this module only keeps the order.
local ThrowQueue = {}
ThrowQueue.__index = ThrowQueue

export type Queue = typeof(setmetatable({} :: { List: { any } }, ThrowQueue))

function ThrowQueue.new(): Queue
	return setmetatable({ List = {} }, ThrowQueue)
end

function ThrowQueue.Position(self: Queue, key: any): number
	return table.find(self.List, key) or 0
end

function ThrowQueue.Head(self: Queue): any
	return self.List[1]
end

function ThrowQueue.Count(self: Queue): number
	return #self.List
end

-- Join the back. Returns the new position (unchanged if already queued).
function ThrowQueue.Join(self: Queue, key: any): number
	local i = table.find(self.List, key)
	if i then
		return i
	end
	table.insert(self.List, key)
	return #self.List
end

-- Remove from anywhere. Returns true if it was queued.
function ThrowQueue.Remove(self: Queue, key: any): boolean
	local i = table.find(self.List, key)
	if not i then
		return false
	end
	table.remove(self.List, i)
	return true
end

-- Send a player to the back of the line (end of their turn / idle turn). No-op when they are alone.
function ThrowQueue.ToBack(self: Queue, key: any): boolean
	local i = table.find(self.List, key)
	if not i or #self.List <= 1 then
		return false
	end
	table.remove(self.List, i)
	table.insert(self.List, key)
	return true
end

function ThrowQueue.Snapshot(self: Queue): { any }
	return table.clone(self.List)
end

return ThrowQueue
