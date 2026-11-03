--!strict
-- Renders every throw's ball for everyone (thrower + spectators) on ThrowResult: a ball coloured per
-- Balls.ById[result.BallId].Color with a small trail, flown along the SAME arc the server timed
-- (Util/BallFlight.ForThrow(result.LaunchPos, result.LandPos)): it leaves the thrower's hand on the raised deck
-- (Y = 44) and lands on
-- the field (Y = 0) at the horizontal distance of the throw. Purely visual; the outcome is already decided.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Balls = require(Config:WaitForChild("Balls"))
local Layout = require(Config:WaitForChild("Layout"))
local Game = require(Config:WaitForChild("Game"))
local BallFlight = require(Util:WaitForChild("BallFlight"))

local BALL_SIZE = 1.2
local MAX_LATENCY_SKIP = 0.5 -- catch up at most this much of the flight for network delay

local folder = Instance.new("Folder")
folder.Name = "BallFlights"
folder.Parent = workspace

local function endpoints(result: any): (Vector3, Vector3)
	local launch = result.LaunchPos
	local land = result.LandPos
	if typeof(launch) ~= "Vector3" then
		local spot = Layout.Platform.ThrowSpot
		launch = Vector3.new(spot.X, spot.Y + Game.Throw.LaunchHeight, spot.Z)
	end
	if typeof(land) ~= "Vector3" then
		land = Vector3.new(launch.X, Layout.GroundY, Layout.DistanceToZ(tonumber(result.Distance) or 0))
	end
	return launch, land
end

local function makeBall(ballId: string?): BasePart
	local def = Balls.ById[ballId or Balls.Default] or Balls.ById[Balls.Default]
	local ball = Instance.new("Part")
	ball.Name = "ThrownBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * BALL_SIZE
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = true
	ball.Color = def.Color
	ball.Material = if def.Id == "Glow" then Enum.Material.Neon
		elseif def.Id == "Golden" then Enum.Material.Foil
		else Enum.Material.SmoothPlastic
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.35, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.35, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(def.Color)
	trail.Lifetime = 0.45
	trail.LightEmission = if def.Id == "Glow" then 1 else 0.4
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.FaceCamera = true
	trail.Parent = ball
	if def.Id == "Glow" or def.Id == "Golden" then
		local light = Instance.new("PointLight")
		light.Color = def.Color
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = ball
	end
	return ball
end

local function play(result: any)
	if type(result) ~= "table" then
		return
	end
	local launch, land = endpoints(result)
	local arc = BallFlight.ForThrow(launch, land)
	local lift = Vector3.new(0, BALL_SIZE / 2, 0)
	local ball = makeBall(result.BallId)
	ball.CFrame = CFrame.new(arc.Position(0) + lift)
	ball.Parent = folder

	local skip = 0
	local sent = tonumber(result.ServerTime)
	if sent then
		skip = math.clamp(workspace:GetServerTimeNow() - sent, 0, MAX_LATENCY_SKIP)
	end
	local t0 = os.clock() - skip
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local pos = arc.Position(t) + lift
		local vel = arc.VelocityAt(t)
		ball.CFrame = if vel.Magnitude > 1e-3 then CFrame.lookAt(pos, pos + vel) else CFrame.new(pos)
		if t >= arc.Duration then
			conn:Disconnect()
			local rest = land + lift
			ball.CFrame = CFrame.new(rest)
			local hop = TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
				{ CFrame = CFrame.new(rest + Vector3.new(0, 0, 2)) })
			hop:Play()
			task.delay(2.5, function()
				ball:Destroy()
			end)
		end
	end)
end

local throwResult = Remotes.Get("ThrowResult") :: RemoteEvent
throwResult.OnClientEvent:Connect(function(result: any)
	local ok, err = pcall(play, result)
	if not ok then
		warn("[BallFlight] " .. tostring(err))
	end
end)
