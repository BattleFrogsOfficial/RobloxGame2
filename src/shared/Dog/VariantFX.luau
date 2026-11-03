--!strict
-- Runtime variant effects for ANY dog rig built by DogFactory. Variants are never baked into the roster;
-- one module turns any dog into its Gold / Shadow / Rainbow form:
--   Gold    : metallic gold coat + sparkle particles + warm light
--   Shadow  : black coat + purple smoke + glowing purple eyes
--   Rainbow : HSV-cycling coat (client, via Bind) + rainbow trail
--
-- VariantFX.Apply(model, variant)  static part (colours, materials, emitters). Safe on server or client;
--                                  it replicates when done on the server.
-- VariantFX.Bind(model, variant)   dynamic part (Rainbow hue cycling). CLIENT ONLY. Returns a cleanup fn.
--
-- Parts are found by attributes DogFactory sets: Coat = "Primary" | "Secondary", Eye = true.
local RunService = game:GetService("RunService")

local VariantFX = {}

VariantFX.Order = { "Gold", "Shadow", "Rainbow" }

VariantFX.Colors = {
	Gold = { Primary = Color3.fromRGB(255, 196, 48), Secondary = Color3.fromRGB(255, 232, 140), Badge = Color3.fromRGB(255, 205, 60) },
	Shadow = { Primary = Color3.fromRGB(22, 18, 30), Secondary = Color3.fromRGB(58, 36, 82), Eye = Color3.fromRGB(190, 90, 255),
		Badge = Color3.fromRGB(150, 80, 230) },
	Rainbow = { Badge = Color3.fromRGB(255, 120, 200) },
}

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function rainbowSequence(): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.85, 1)))
	end
	return ColorSequence.new(keys)
end

function VariantFX.BadgeColor(variant: string?): Color3
	local c = variant and (VariantFX.Colors :: any)[variant]
	if c then
		return c.Badge
	end
	return Color3.new(1, 1, 1)
end

-- Gradient used by UI badges (Rainbow gets a full spectrum).
function VariantFX.BadgeGradient(variant: string?): ColorSequence
	if variant == "Rainbow" then
		return rainbowSequence()
	end
	return ColorSequence.new(VariantFX.BadgeColor(variant))
end

local function coatParts(model: Model): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Coat") ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

local function torsoOf(model: Model): BasePart?
	local t = model:FindFirstChild("Torso", true)
	if t and t:IsA("BasePart") then
		return t
	end
	return model.PrimaryPart
end

local function clearFx(model: Model)
	for _, d in model:GetDescendants() do
		if d:GetAttribute("VariantFX") then
			d:Destroy()
		end
	end
end

local function tag<T>(inst: T): T
	local i: any = inst
	i:SetAttribute("VariantFX", true)
	return inst
end

function VariantFX.Apply(model: Model, variant: string?)
	if not variant or variant == "" or not (VariantFX.Colors :: any)[variant] then
		return
	end
	clearFx(model)
	model:SetAttribute("Variant", variant)
	local torso = torsoOf(model)
	local scale = model:GetScale()

	if variant == "Gold" then
		for _, p in coatParts(model) do
			p.Color = if p:GetAttribute("Coat") == "Secondary" then VariantFX.Colors.Gold.Secondary else VariantFX.Colors.Gold.Primary
			p.Material = Enum.Material.Foil
			p.Reflectance = 0.2
		end
		if torso then
			local e = tag(Instance.new("ParticleEmitter"))
			e.Name = "GoldSparkle"
			e.Texture = SPARKLE_TEX
			e.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
			e.LightEmission = 1
			e.Rate = 6
			e.Lifetime = NumberRange.new(0.6, 1.2)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.45 * scale),
				NumberSequenceKeypoint.new(1, 0) })
			e.Parent = torso
			local l = tag(Instance.new("PointLight"))
			l.Color = Color3.fromRGB(255, 210, 90)
			l.Brightness = 0.8
			l.Range = 8 * scale
			l.Parent = torso
		end
	elseif variant == "Shadow" then
		for _, p in coatParts(model) do
			p.Color = if p:GetAttribute("Coat") == "Secondary" then VariantFX.Colors.Shadow.Secondary else VariantFX.Colors.Shadow.Primary
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = 0
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Eye") then
				d.Color = VariantFX.Colors.Shadow.Eye
				d.Material = Enum.Material.Neon
			end
		end
		if torso then
			local e = tag(Instance.new("ParticleEmitter"))
			e.Name = "ShadowSmoke"
			e.Texture = SMOKE_TEX
			e.Color = ColorSequence.new(Color3.fromRGB(120, 50, 190), Color3.fromRGB(30, 10, 50))
			e.LightEmission = 0.3
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
			e.Rate = 10
			e.Lifetime = NumberRange.new(1, 1.8)
			e.Speed = NumberRange.new(0.3, 1)
			e.Acceleration = Vector3.new(0, 1.5, 0)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8 * scale), NumberSequenceKeypoint.new(1, 2 * scale) })
			e.Parent = torso
			local l = tag(Instance.new("PointLight"))
			l.Color = Color3.fromRGB(160, 70, 255)
			l.Brightness = 0.6
			l.Range = 7 * scale
			l.Parent = torso
		end
	elseif variant == "Rainbow" then
		local parts = coatParts(model)
		for i, p in parts do
			p.Color = Color3.fromHSV((i / math.max(1, #parts)) % 1, 0.75, 1)
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = 0.05
		end
		if torso then
			local half = torso.Size.Y * 0.35
			local a0 = tag(Instance.new("Attachment"))
			a0.Name = "TrailTop"
			a0.Position = Vector3.new(0, half, torso.Size.Z * 0.4)
			a0.Parent = torso
			local a1 = tag(Instance.new("Attachment"))
			a1.Name = "TrailBottom"
			a1.Position = Vector3.new(0, -half, torso.Size.Z * 0.4)
			a1.Parent = torso
			local trail = tag(Instance.new("Trail"))
			trail.Name = "RainbowTrail"
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = rainbowSequence()
			trail.LightEmission = 0.6
			trail.Lifetime = 0.6
			trail.MinLength = 0.05
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.Parent = torso
			local e = tag(Instance.new("ParticleEmitter"))
			e.Name = "RainbowSparkle"
			e.Texture = SPARKLE_TEX
			e.Color = rainbowSequence()
			e.LightEmission = 1
			e.Rate = 5
			e.Lifetime = NumberRange.new(0.8, 1.4)
			e.Speed = NumberRange.new(0.5, 1.2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.4 * scale),
				NumberSequenceKeypoint.new(1, 0) })
			e.Parent = torso
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Dynamic effects (client). One shared loop at ~15 Hz for every bound model.
----------------------------------------------------------------------------------------------------
type Bound = { Model: Model, Parts: { BasePart }, Offset: number }
local bound: { [Model]: Bound } = {}
local loopConn: RBXScriptConnection? = nil
local acc = 0

local function step(dt: number)
	acc += dt
	if acc < 1 / 15 then
		return
	end
	acc = 0
	local t = os.clock()
	for model, b in bound do
		if model.Parent == nil then
			bound[model] = nil
		else
			local n = #b.Parts
			for i, p in b.Parts do
				p.Color = Color3.fromHSV((t * 0.25 + b.Offset + i / math.max(1, n) * 0.5) % 1, 0.75, 1)
			end
		end
	end
	if next(bound) == nil and loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
end

function VariantFX.Bind(model: Model, variant: string?): () -> ()
	if variant ~= "Rainbow" or not RunService:IsClient() then
		return function() end
	end
	bound[model] = { Model = model, Parts = coatParts(model), Offset = math.random() }
	if not loopConn then
		loopConn = RunService.Heartbeat:Connect(step)
	end
	return function()
		bound[model] = nil
	end
end

return VariantFX
