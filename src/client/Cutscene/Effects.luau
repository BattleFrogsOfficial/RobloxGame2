--!strict
-- Cutscene world effects (local only): per-zone touchdown burst (Config/Cutscene.ImpactFX), a sparkle burst
-- for the Lucky Streak / Treat Pocket flourish, and a ground probe so the ball and the dog sit on the real
-- field surface. Everything is handed to the caller's Janitor.
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Cutscene"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local Effects = {}

local function anchorPart(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name = "CutsceneFX"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace:FindFirstChild("CutsceneBalls") or workspace
	return p
end

local function burst(pos: Vector3, colors: { Color3 }, texture: string, count: number, speed: { number }, size: number,
	lifetime: number, gravity: number, janitor: any?)
	local holder = anchorPart(pos)
	local e = Instance.new("ParticleEmitter")
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
	end
	e.Color = ColorSequence.new(keys)
	e.Texture = texture
	e.Rate = 0
	e.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	e.Speed = NumberRange.new(speed[1], speed[2])
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, gravity, 0)
	e.Drag = 2
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.3) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Parent = holder
	e:Emit(count)
	if janitor then
		janitor:Add(holder)
	end
	Debris:AddItem(holder, lifetime + 1)
end

function Effects.Impact(zoneId: string, pos: Vector3, janitor: any?, silent: boolean?)
	local fx = (C.ImpactFX :: any)[zoneId] or C.ImpactFX.Backyard
	burst(pos, fx.Colors, fx.Texture, fx.Count, fx.Speed, fx.Size, fx.Lifetime, fx.Gravity, janitor)
	if fx.Sparks then
		burst(pos + Vector3.new(0, 0.3, 0), { Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 170, 60) },
			"rbxasset://textures/particles/sparkles_main.dds", math.floor(fx.Count * 0.6), { 14, 28 }, 0.25, 0.35, -60, janitor)
	end
	if not silent then
		Sfx.Play(fx.Sound, { Volume = 0.6, Pitch = fx.Pitch, Janitor = janitor })
	end
end

function Effects.Sparkle(pos: Vector3, color: Color3, janitor: any?)
	burst(pos, { color, Color3.new(1, 1, 1) }, "rbxasset://textures/particles/sparkles_main.dds", 30, { 4, 10 }, 0.6, 1.0, 6, janitor)
end

-- Top of the ground under (x, z) near `y`, ignoring characters and cutscene props. Falls back to y.
function Effects.GroundY(pos: Vector3, ignore: { Instance }?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = {}
	local balls = workspace:FindFirstChild("CutsceneBalls")
	if balls then
		table.insert(list, balls)
	end
	for _, p in game:GetService("Players"):GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, i in ignore or {} do
		table.insert(list, i)
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = false
	local probe = C.Landing.GroundProbe
	local hit = workspace:Raycast(pos + Vector3.new(0, probe, 0), Vector3.new(0, -2 * probe, 0), params)
	if hit then
		return hit.Position.Y
	end
	return pos.Y
end

return Effects
