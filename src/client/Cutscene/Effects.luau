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
	lifetime: number, gravity: number, janitor: any?, tweak: ((ParticleEmitter) -> ())?, facing: Vector3?): Part
	local holder = anchorPart(pos)
	if facing and facing.Magnitude > 1e-3 then
		holder.CFrame = CFrame.lookAt(pos, pos + facing.Unit) -- Enum.NormalId.Front emits along the facing
	end
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
	if tweak then
		tweak(e)
	end
	e.Parent = holder
	e:Emit(count)
	if janitor then
		janitor:Add(holder)
	end
	Debris:AddItem(holder, lifetime + 1)
	return holder
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

-- Release speed lines: thin bright streaks shooting out of the hand along the throw direction.
function Effects.SpeedLines(pos: Vector3, dir: Vector3, janitor: any?)
	local I = C.Impact
	local d = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, 1)
	burst(pos, { Color3.new(1, 1, 1), Color3.fromRGB(220, 240, 255) }, "rbxasset://textures/particles/sparkles_main.dds",
		I.SpeedLines, I.SpeedLineSpeed, I.SpeedLineSize, I.SpeedLineLifetime, 0, janitor, function(e)
			e.EmissionDirection = Enum.NormalId.Front
			e.SpreadAngle = Vector2.new(I.SpeedLineSpread, I.SpeedLineSpread)
			e.Orientation = Enum.ParticleOrientation.VelocityParallel
			e.Squash = NumberSequence.new(-2.5) -- long thin streaks along the velocity
			e.LightEmission = 1
			e.Drag = 0
		end, d)
end

-- Victory confetti: one burst in the rarity colour (`count` particles) with the variant's colours on top.
function Effects.Confetti(pos: Vector3, color: Color3, count: number, variantColors: { Color3 }?, janitor: any?)
	local V = C.Victory
	local function confetti(e: ParticleEmitter)
		e.SpreadAngle = Vector2.new(55, 55)
		e.LightEmission = 0.4
		e.Drag = 1.2
	end
	burst(pos, { color, color:Lerp(Color3.new(1, 1, 1), 0.5), Color3.new(1, 1, 1) }, "rbxasset://textures/particles/sparkles_main.dds",
		count, V.ConfettiSpeed, V.ConfettiSize, V.ConfettiLifetime, -14, janitor, confetti)
	if variantColors and #variantColors > 0 then
		burst(pos + Vector3.new(0, 0.4, 0), variantColors, "rbxasset://textures/particles/sparkles_main.dds",
			math.max(1, math.floor(count * V.VariantConfetti)), V.ConfettiSpeed, V.ConfettiSize * 0.8, V.ConfettiLifetime, -10, janitor, confetti)
	end
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
