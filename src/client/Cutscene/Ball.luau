--!strict
-- The thrown ball (client-side, local only): Balls.ById[ballId].Color, a trail (off while it sits in the hand)
-- and a light for the glowing balls. Anchored and moved by whoever owns it (Rig while in the hand, then the
-- flight / bounce drivers). Lives under workspace.CutsceneBalls.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balls = require(Config:WaitForChild("Balls"))
local C = require(Config:WaitForChild("Cutscene"))

local Ball = {}

local function folder(): Folder
	local f = workspace:FindFirstChild("CutsceneBalls")
	if not f then
		f = Instance.new("Folder")
		f.Name = "CutsceneBalls"
		f.Parent = workspace
	end
	return f :: Folder
end

function Ball.Def(ballId: string?): any
	return Balls.ById[ballId or Balls.Default] or Balls.ById[Balls.Default]
end

function Ball.Make(ballId: string?): BasePart
	local def = Ball.Def(ballId)
	local size = C.Flight.BallSize
	local ball = Instance.new("Part")
	ball.Name = "ThrownBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * size
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = true
	ball.Massless = true
	ball.Color = def.Color
	ball.Material = if def.Id == "Glow" then Enum.Material.Neon
		elseif def.Id == "Golden" then Enum.Material.Foil
		else Enum.Material.SmoothPlastic
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.3, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.3, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(def.Color)
	trail.Lifetime = C.Flight.TrailLifetime
	trail.LightEmission = if def.Id == "Glow" then 1 else 0.4
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0.15)
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = ball
	if def.Id == "Glow" or def.Id == "Golden" then
		local light = Instance.new("PointLight")
		light.Color = def.Color
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = ball
	end
	ball.Parent = folder()
	return ball
end

function Ball.SetTrail(ball: BasePart, on: boolean)
	local t = ball:FindFirstChild("Trail")
	if t and t:IsA("Trail") then
		t.Enabled = on
	end
end

return Ball
