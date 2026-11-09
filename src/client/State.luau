-- Client-side copy of the player's state, pushed by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local State = {}

State.data = nil :: any
State.changed = Signal.new() -- (data)
State.toast = Signal.new() -- (text, color?)
State.effect = Signal.new() -- (kind, payload)

-- Server time offset so playtime timers match the server.
function State.serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Call a server action and toast its message.
function State.action(name: string, ...): (boolean, string?)
	local ok, result, msg = pcall(function(...)
		return Remotes.get("Action"):InvokeServer(name, ...)
	end, ...)
	if not ok then
		return false
	end
	if msg then
		State.toast:Fire(msg, result and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 110, 110))
	end
	return result, msg
end

function State.init()
	Remotes.get("State").OnClientEvent:Connect(function(data)
		State.data = data
		State.changed:Fire(data)
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(text, color)
		State.toast:Fire(text, color)
	end)
	Remotes.get("Effect").OnClientEvent:Connect(function(kind, payload)
		State.effect:Fire(kind, payload)
	end)
end

return State
