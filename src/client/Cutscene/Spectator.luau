--!strict
-- Other players' throws, on every client: the thrower's avatar plays the wind-up + throw locally (procedural
-- C0 changes never replicate, so each client animates it from the ThrowResult) and the ball flies on the same
-- time-scaled arc as the thrower's cutscene, bounces and rests. No camera work (spectators keep their camera;
-- the UI shows its Spectator banner). Started from src/client/BallFlight.client.luau.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local CutsceneShared = Shared:WaitForChild("Cutscene")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Cutscene"))
local BallFlight = require(Util:WaitForChild("BallFlight"))
local Timeline = require(CutsceneShared:WaitForChild("Timeline"))
local Path = require(CutsceneShared:WaitForChild("Path"))

local Here = script.Parent
local Janitor = require(Here:WaitForChild("Janitor"))
local Ball = require(Here:WaitForChild("Ball"))
local Rig = require(Here:WaitForChild("Rig"))
local Effects = require(Here:WaitForChild("Effects"))

local Spectator = {}

local MAX_LATENCY_SKIP = 0.5 -- catch up at most this much for network delay

function Spectator.Play(result: any)
	local ok, r = Timeline.Validate(result)
	if not ok then
		return
	end
	local jan = Janitor.new()
	local launch, land = Path.Endpoints(r)
	local thrower = Players:GetPlayerByUserId(r.ThrowerUserId)
	local char = thrower and thrower.Character
	local cam = workspace.CurrentCamera
	if char and cam then
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) or (root.Position - cam.CFrame.Position).Magnitude > C.Spectator.MaxDistance then
			char = nil
		end
	end
	local ball = jan:Add(Ball.Make(r.BallId))
	ball.CFrame = CFrame.new(launch)
	local rig = Rig.Play(char, ball, launch, { Assets = false })
	jan:Add(function()
		rig:Stop()
	end)
	if thrower then
		jan:Add(thrower.CharacterRemoving:Connect(function()
			rig:Stop()
		end))
	end
	local skip = 0
	local sent = tonumber(r.ServerTime)
	if sent then
		skip = math.clamp(workspace:GetServerTimeNow() - sent, 0, MAX_LATENCY_SKIP)
	end
	local t0 = os.clock() - skip
	local arc = BallFlight.ForThrow(launch, land)
	local seconds = Timeline.FlightSeconds(tonumber(r.FlightTime) or arc.Duration)
	local flight: Path.FlightPath? = nil
	local bounces: Path.Bounces? = nil
	local lift = Vector3.new(0, C.Flight.BallSize / 2, 0)
	jan:Add(RunService.RenderStepped:Connect(function()
		local okStep, err = pcall(function()
			local t = os.clock() - t0
			if t < C.WindUp.ReleaseAt then
				return -- in the hand (Rig moves it)
			end
			if not flight then
				rig:Release()
				Ball.SetTrail(ball, true)
				flight = Path.Flight(arc, rig:HandPosition(), seconds)
			end
			local f = flight :: Path.FlightPath
			local ft = t - C.WindUp.ReleaseAt
			if ft < f.Duration then
				local p, v = f.Position(ft), f.Velocity(ft)
				ball.CFrame = if v.Magnitude > 1e-3 then CFrame.lookAt(p, p + v) else CFrame.new(p)
				return
			end
			if not bounces then
				bounces = Path.Bounces(land, Vector3.new(0, 0, 1))
				Effects.Impact(r.ZoneId, land, jan, true) -- spectators: dust only, no sound
			end
			local bt = ft - f.Duration
			ball.CFrame = CFrame.new(Path.BounceAt(bounces :: Path.Bounces, bt) + lift)
			if bt > C.Spectator.BallRest then
				jan:Clean()
			end
		end)
		if not okStep then
			warn("[Cutscene.Spectator] " .. tostring(err))
			jan:Clean()
		end
	end))
	-- hard stop in case nothing above ever ends it
	task.delay(C.WindUp.ReleaseAt + C.Flight.Max + C.Spectator.BallRest + 5, function()
		jan:Clean()
	end)
end

return Spectator
