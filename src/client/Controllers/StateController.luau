--!strict
-- Client cache of the server PlayerState: RequestState once (with retry), then every StateUpdate snapshot.
-- Live per-second numbers (Cash, Bones, IncomePerSec, ThrowPower) also come from player attributes.
--   StateController.Get() -> state?        StateController.Changed:Connect(fn(state))
--   StateController.Live(name) -> number   StateController.LiveChanged:Connect(fn(name, value))
--   StateController.ServerNow() -> os.time() on the server's clock (for boost timers)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local StateController = {}

StateController.Changed = Signal.new()
StateController.LiveChanged = Signal.new()

local state: any = nil
local serverOffset = 0
local LIVE_KEYS = { "Cash", "Bones", "IncomePerSec", "ThrowPower" }

local function apply(snap: any)
	if type(snap) ~= "table" then
		return
	end
	state = snap
	if type(snap.Computed) == "table" and type(snap.Computed.ServerTime) == "number" then
		serverOffset = snap.Computed.ServerTime - os.time()
	end
	StateController.Changed:Fire(state)
end

function StateController.Get(): any
	return state
end

function StateController.IsReady(): boolean
	return state ~= nil
end

-- Yields until the first snapshot arrives.
function StateController.Wait(): any
	while not state do
		StateController.Changed:Wait()
	end
	return state
end

function StateController.Computed(): any
	return if state and type(state.Computed) == "table" then state.Computed else {}
end

function StateController.ServerNow(): number
	return os.time() + serverOffset
end

-- Live attribute when present (updates every income tick), else the last snapshot value.
function StateController.Live(name: string): number
	local v = Players.LocalPlayer:GetAttribute(name)
	if type(v) == "number" then
		return v
	end
	if state then
		if name == "IncomePerSec" then
			return tonumber(StateController.Computed().IncomePerSec) or 0
		end
		return tonumber(state[name]) or 0
	end
	return 0
end

function StateController.Start()
	local player = Players.LocalPlayer
	local update = Remotes.Get("StateUpdate") :: RemoteEvent
	update.OnClientEvent:Connect(apply)
	for _, key in LIVE_KEYS do
		player:GetAttributeChangedSignal(key):Connect(function()
			StateController.LiveChanged:Fire(key, player:GetAttribute(key))
		end)
	end
	task.spawn(function()
		local request = Remotes.Get("RequestState") :: RemoteFunction
		local waitTime = 2
		while not state do
			local ok, snap = pcall(function()
				return request:InvokeServer()
			end)
			if ok and type(snap) == "table" then
				if not state then
					apply(snap)
				end
				break
			end
			task.wait(waitTime) -- server rate-limits RequestState; StateUpdate usually arrives first anyway
			waitTime = math.min(waitTime * 1.5, 10)
		end
	end)
end

return StateController
