--!strict
-- Other players' throws, for everyone watching: on every ThrowResult that is NOT ours, the thrower's avatar
-- plays the wind-up + overhand throw locally (procedural Motor6D changes never replicate, so each client
-- animates it) and the ball flies on the server's arc (Util/BallFlight.ForThrow(LaunchPos, LandPos)),
-- time-scaled exactly like the thrower's cutscene, bounces and rests. Spectators' cameras are never touched;
-- the UI shows its Spectator banner. Our OWN throws are drawn by the cutscene (src/client/Cutscene).
-- Purely visual; the outcome is already decided.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Spectator = require(script.Parent:WaitForChild("Cutscene"):WaitForChild("Spectator"))

local player = Players.LocalPlayer
local throwResult = Remotes.Get("ThrowResult") :: RemoteEvent
throwResult.OnClientEvent:Connect(function(result: any)
	if type(result) ~= "table" or result.ThrowerUserId == player.UserId then
		return
	end
	local ok, err = pcall(Spectator.Play, result)
	if not ok then
		warn("[BallFlight] " .. tostring(err))
	end
end)
