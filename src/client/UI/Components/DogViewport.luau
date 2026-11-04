--!strict
-- DogViewport: the live dog on the reveal card. ONE ViewportFrame + WorldModel holding the dog's real model
-- (DogFactory + VariantFX) standing on a round rarity pedestal, lit in the rarity colour (ViewportFrame
-- Ambient / LightColor / LightDirection), slowly turning, wagging and hopping (DogAnimator.Idle).
--
--   local stage = DogViewport.new({ Parent, Size, Position, AnchorPoint, ZIndex, Dog = def, Variant, Rarity, Caught })
--   stage.Root    the stage Frame (backdrop + viewport)      stage.Ok  true when the 3D dog was built
--   stage:Destroy()  disconnects everything, stops the idle loop, destroys the viewport
--
-- Turning is a camera ORBIT, not a model rotation: the dog + pedestal are rotation-symmetric for framing, so
-- orbiting the camera (and the light with it) looks the same as a turntable, costs one CFrame write per frame
-- and never fights the animator's joints.
-- Framing: the camera is fitted to the dog's TURNING cylinder (max horizontal radius of every visible part
-- corner around the turn axis, from the pedestal's foot to the dog's top + hop height), solved in closed form
-- for the viewport's aspect and FOV, so a toy dog and a giant dog fill the frame the same and never clip
-- while turning or hopping.
-- Never errors: any failure (DogFactory, a missing part, the animator) warns once and shows the pixel dog icon.
-- Timings / framing numbers: Config/Cutscene.luau EndCard.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local CutsceneConfig = require(Config:WaitForChild("Cutscene"))
local DogFolder = Shared:WaitForChild("Dog")

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Icon = require(script.Parent:WaitForChild("Icon"))

local DogViewport = {}

export type Props = {
	Parent: Instance?,
	Size: UDim2, -- offset size (the camera fit uses its aspect)
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	Dog: any?, -- DogCatalog def
	Variant: string?,
	Rarity: string?,
	Caught: boolean?,
	Name: string?,
	BottomReserve: number?, -- px at the bottom kept clear of the dog (an overlay, e.g. the CAUGHT stamp)
}

export type Handle = {
	Root: Frame,
	Viewport: ViewportFrame?,
	Ok: boolean,
	Destroy: (self: Handle) -> (),
}

local Stage = Theme.Stage
local STONE, STONE_DARK, GOLD, GOLD_LIGHT, NIGHT = Stage.Stone, Stage.StoneDark, Stage.Gold, Stage.GoldGlow, Stage.Night

local function tierIndex(rarity: string): number
	return table.find(Rarities.Order, rarity) or 1
end

-- Lazy requires so a broken Dog module can never stop the card from loading (pcall at use).
local function requireDog(name: string): any
	return require(DogFolder:WaitForChild(name) :: ModuleScript)
end

-- A vertical disc (Roblox cylinders run along X, so turn it upright).
local function disc(parent: Instance, name: string, radius: number, height: number, topY: number, color: Color3,
	material: Enum.Material, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = CFrame.new(0, topY - height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Horizontal turning radius and height of the dog's visible parts (corners), relative to the turn axis (x = z = 0).
local function turningCylinder(model: Model): (number, number)
	local r, top = 0.5, 0.5
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local h = d.Size * 0.5
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local w = d.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
						r = math.max(r, math.sqrt(w.X * w.X + w.Z * w.Z))
						top = math.max(top, w.Y)
					end
				end
			end
		end
	end
	return r, top
end

-- Closed-form camera fit: the smallest distance at which every sample point of the given horizontal rings
-- ({ R, Y } around the turn axis) projects inside `fill` of the frame, for a camera looking along
-- basis.LookVector at `target`. For each point q (relative to target) in camera axes (x, y, z):
-- |x| <= (D + z) * tanH  and  |y| <= (D + z) * tanV   =>   D >= |x| / tanH - z, |y| / tanV - z.
function DogViewport.FitDistance(rings: { { R: number, Y: number } }, target: Vector3, basis: CFrame, fovDeg: number,
	aspect: number, fill: number): number
	local tanV = math.tan(math.rad(fovDeg) / 2) * fill
	local tanH = tanV * aspect
	local right, up, look = basis.RightVector, basis.UpVector, basis.LookVector
	local D = 0
	for _, ring in rings do
		for i = 0, 23 do
			local a = i / 24 * math.pi * 2
			local q = Vector3.new(math.cos(a) * ring.R, ring.Y, math.sin(a) * ring.R) - target
			local x, y, z = q:Dot(right), q:Dot(up), q:Dot(look)
			D = math.max(D, math.abs(x) / tanH - z, math.abs(y) / tanV - z)
		end
	end
	return D
end

function DogViewport.new(props: Props): Handle
	local ec = CutsceneConfig.EndCard :: any
	local rarity = props.Rarity or (props.Dog and props.Dog.Rarity) or "Common"
	local tier = tierIndex(rarity)
	local caught = props.Caught ~= false
	local rc = Theme.RarityColor(rarity)
	local reduced = Motion.ReducedMotion
	local z = props.ZIndex or 1

	-- Stage: dark rarity-tinted backdrop (vertical, light on top) with a soft spotlight behind the dog.
	local root: Frame = Make("Frame", {
		Name = props.Name or "DogStage",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		ClipsDescendants = true,
		ZIndex = z,
	})
	Decor.Corner(root, Theme.Radius.Card)
	Decor.Stroke(root, Theme.Stroke.Panel)
	local top, bottom
	if not caught then
		top, bottom = NIGHT, Theme.Color.Ink
	elseif tier == 1 then
		top, bottom = Theme.Palette.Slate.Top, Theme.Palette.Slate.Bottom:Lerp(Theme.Color.Ink, 0.4)
	else
		top, bottom = rc:Lerp(Theme.Color.Ink, 0.35), rc:Lerp(Theme.Color.Ink, 0.78)
	end
	Decor.Gradient(root, top, bottom)

	local w, h = props.Size.X.Offset, props.Size.Y.Offset
	local glows: { Frame } = {}
	local glowColor = if caught then rc:Lerp(Theme.Color.White, 0.35) else rc:Lerp(Theme.Color.Ink, 0.55)
	for i, k in { 0.95, 0.68, 0.42 } do
		local d = math.floor(math.min(w, h) * k)
		local g: Frame = Make("Frame", {
			Name = "Spot" .. i,
			BackgroundColor3 = glowColor,
			BackgroundTransparency = if caught then 0.9 - i * 0.025 else 0.93,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(d, d),
			Position = UDim2.new(0.5, 0, 0.44, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 1,
			Parent = root,
		})
		Decor.Corner(g, 999)
		table.insert(glows, g)
	end

	local handle = { Root = root, Viewport = nil :: ViewportFrame?, Ok = false } :: any
	local conns: { RBXScriptConnection } = {}
	local idle: any = nil
	local unbindRainbow: (() -> ())? = nil
	local destroyed = false

	local function release()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		if idle then
			pcall(idle.Stop)
			idle = nil
		end
		if unbindRainbow then
			pcall(unbindRainbow)
			unbindRainbow = nil
		end
		if handle.Viewport then
			handle.Viewport:Destroy()
			handle.Viewport = nil
		end
	end

	local function fallbackIcon()
		Icon.new({ Name = "dog", Size = math.min(96, math.floor(math.min(w, h) * 0.45)), Position = UDim2.fromScale(0.5, 0.44),
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z + 3, Parent = root }).Name = "FallbackIcon"
	end

	if props.Parent then
		root.Parent = props.Parent -- in the DataModel before the model / animator start
	end
	local ok, err = pcall(function()
		local DogFactory = requireDog("DogFactory")
		local VariantFX = requireDog("VariantFX")
		local def = props.Dog
		assert(def ~= nil, "no dog definition")

		local vpf: ViewportFrame = Make("ViewportFrame", {
			Name = "DogViewport",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 2,
		})
		local world = Instance.new("WorldModel")
		world.Parent = vpf
		handle.Viewport = vpf
		local model: Model = DogFactory.Build(def, { Variant = props.Variant, NoVfx = true })
		model.Parent = world

		-- Stand the dog on the origin: feet at y = 0, bounding-box centre on the turn axis.
		local bbCf, bbSize = model:GetBoundingBox()
		local feet = bbCf.Position.Y - bbSize.Y / 2
		model:PivotTo(CFrame.new(-bbCf.Position.X, -feet, -bbCf.Position.Z) * model:GetPivot())
		local rDog, yDog = turningCylinder(model)
		local scale = model:GetScale()

		-- Pedestal (rarity look): disc + base step (+ rim, glow, aura).
		local R = rDog * (ec.PedestalMargin or 1.12)
		local discH = math.max(0.2, R * 0.16)
		local stepH = discH * 0.7
		local pedestal = Instance.new("Model")
		pedestal.Name = "Pedestal"
		pedestal.Parent = world
		local pulse: { { Part: BasePart, Base: number, Amp: number } } = {}
		local discColor, discMat, stepColor = STONE, Enum.Material.Slate, STONE_DARK
		if not caught then
			discColor, stepColor = NIGHT, Theme.Color.Ink
		elseif tier == 5 then
			discColor, discMat, stepColor = GOLD, Enum.Material.Foil, Stage.GoldDeep
		elseif tier == 6 then
			discColor, discMat, stepColor = rc:Lerp(Theme.Color.White, 0.25), Enum.Material.Glass, rc:Lerp(Theme.Color.Ink, 0.45)
		elseif tier >= 2 then
			stepColor = rc:Lerp(Theme.Color.Ink, 0.35)
		end
		local discPart = disc(pedestal, "Disc", R, discH, 0, discColor, discMat)
		if tier == 5 and caught then
			discPart.Reflectance = 0.25
		end
		disc(pedestal, "Step", R * 1.12, stepH, -discH, stepColor, if tier >= 5 and caught then Enum.Material.Metal else Enum.Material.Slate)
		if tier >= 2 or not caught then
			-- rarity rim on the disc's top edge (faint and dark for a missed dog)
			local rimColor = if caught then rc else rc:Lerp(Theme.Color.Ink, 0.6)
			disc(pedestal, "Rim", R * 1.03, discH * 0.35, -discH * 0.25, rimColor, if tier >= 4 and caught then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		end
		if caught and tier >= 5 then
			-- glow: a translucent Neon halo ring around the pedestal (ViewportFrames have no bloom or lights)
			local halo = disc(pedestal, "Glow", R * 1.3, discH * 0.25, -discH - stepH * 0.3, if tier == 5 then GOLD_LIGHT else rc, Enum.Material.Neon, 0.45)
			table.insert(pulse, { Part = halo, Base = 0.45, Amp = 0.25 })
		end
		local yTop = yDog + (ec.HopHeight or 0.5) * scale
		local motes: { { Part: BasePart, R: number, A: number, Phase: number } } = {}
		if caught and tier == 6 then
			-- aura: a translucent Neon column around the dog + floating motes (small Neon balls animated in code)
			local aura = Instance.new("Part")
			aura.Name = "Aura"
			aura.Shape = Enum.PartType.Cylinder
			aura.Size = Vector3.new(yTop * 1.15, R * 1.9, R * 1.9)
			aura.CFrame = CFrame.new(0, yTop * 1.15 / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			aura.Color = rc
			aura.Material = Enum.Material.Neon
			aura.Transparency = 0.86
			aura.Anchored = true
			aura.CanCollide = false
			aura.CastShadow = false
			aura.Parent = pedestal
			table.insert(pulse, { Part = aura, Base = 0.86, Amp = 0.06 })
			local rng = Random.new(7)
			for i = 1, (ec.MoteCount or 10) do
				local m = Instance.new("Part")
				m.Name = "Mote" .. i
				m.Shape = Enum.PartType.Ball
				local s = math.max(0.08, R * 0.07) * rng:NextNumber(0.7, 1.3)
				m.Size = Vector3.new(s, s, s)
				m.Color = if i % 3 == 0 then Theme.Color.White else rc:Lerp(Theme.Color.White, 0.4)
				m.Material = Enum.Material.Neon
				m.Anchored = true
				m.CanCollide = false
				m.CastShadow = false
				m.Parent = pedestal
				table.insert(motes, { Part = m, R = R * rng:NextNumber(0.45, 0.95), A = rng:NextNumber(0, math.pi * 2), Phase = (i - 1) / (ec.MoteCount or 10) })
			end
		end
		local function placeMotes(t: number)
			for _, mo in motes do
				local p = (mo.Phase + t / (ec.MoteRiseTime or 2.6)) % 1
				local a = mo.A + t * 0.6
				mo.Part.CFrame = CFrame.new(math.cos(a) * mo.R, p * yTop * 1.1, math.sin(a) * mo.R)
				mo.Part.Transparency = 0.15 + 0.85 * p * p
			end
		end
		placeMotes(0)

		-- Camera: fitted to the turning cylinder (pedestal foot .. dog top + hop), slight low angle.
		local camera = Instance.new("Camera")
		camera.FieldOfView = ec.CameraFov or 30
		camera.Parent = vpf
		vpf.CurrentCamera = camera
		local yBottom = -discH - stepH * 0.5
		local target = Vector3.new(0, (yBottom + yTop) / 2, 0)
		local pitch = math.rad(ec.CameraPitch or 7)
		-- yaw 0: the camera sits on the dog's front (-Z, its LookVector), looking back along +Z and slightly up
		local look0 = Vector3.new(0, math.sin(pitch), math.cos(pitch))
		local basis = CFrame.lookAt(Vector3.zero, look0)
		-- the dog's turning cylinder (feet .. top + hop) and the pedestal step's rim (wider, lower)
		-- (the pedestal's outer step and glow may run past the frame edge: the dog is what must fit)
		local rings = { { R = rDog, Y = 0 }, { R = rDog, Y = yTop }, { R = R * 0.9, Y = yBottom } }
		-- fit into the frame minus the bottom reserve: an equivalent narrower FOV for the fit, then tilt the
		-- camera down by the angle of half the reserve so the dog sits in the clear upper region
		local reserve = math.clamp(props.BottomReserve or 0, 0, h * 0.4)
		local fovV = math.rad(camera.FieldOfView)
		local focal = (h / 2) / math.tan(fovV / 2)
		local fitFov = math.deg(2 * math.atan(((h - reserve) / 2) / focal))
		local dist = DogViewport.FitDistance(rings, target, basis, fitFov, w / math.max(1, h - reserve), ec.FrameFill or 0.9)
		local tilt = math.atan((reserve / 2) / focal)
		local aim0 = Vector3.new(0, math.sin(pitch - tilt), math.cos(pitch - tilt))
		local lightDir0 = Vector3.new(0.55, -1, 0.75).Unit -- from the camera's upper left, toward the dog
		local function view(dogYawDeg: number)
			-- the dog appears turned by dogYawDeg = the camera orbits by -dogYawDeg (light orbits with it)
			local orbit = CFrame.Angles(0, -math.rad(dogYawDeg), 0)
			local pos = target - orbit:VectorToWorldSpace(look0) * dist
			camera.CFrame = CFrame.lookAt(pos, pos + orbit:VectorToWorldSpace(aim0))
			vpf.LightDirection = orbit:VectorToWorldSpace(if caught then lightDir0 else Vector3.new(-0.45, -1, 0.6).Unit)
		end

		-- Lighting in the rarity colour; a missed dog is lit cold and dim from behind (rim light).
		if not caught then
			vpf.Ambient = Stage.AmbientMissed
			vpf.LightColor = Stage.LightMissed:Lerp(rc, 0.15)
		elseif tier == 1 then
			vpf.Ambient = Stage.AmbientCommon
			vpf.LightColor = Stage.LightCommon
		else
			vpf.Ambient = Stage.Ambient:Lerp(rc, 0.3)
			vpf.LightColor = Theme.Color.White:Lerp(rc, 0.35)
		end
		local yaw0 = if caught then (ec.StartYaw or -35) else (ec.MissedYaw or 140)
		view(yaw0)

		vpf.Parent = root
		if props.Variant then
			local okBind, unbind = pcall(VariantFX.Bind, model, props.Variant)
			if okBind and type(unbind) == "function" then
				unbindRainbow = unbind
			end
		end

		-- Idle: wag + hop (caught) or the sad look back (missed). DogAnimator.Idle is the shared API; if it is
		-- missing or fails, fall back to the generic idle loop (wag only), and pose the sad head ourselves.
		local okAnim, DogAnimator = pcall(requireDog, "DogAnimator")
		if okAnim and DogAnimator then
			local opts = {
				WagHz = if reduced then 0 else (ec.WagHz or 6),
				HopEvery = if reduced or not caught then 0 else (ec.HopEvery or 3),
				HopHeight = ec.HopHeight or 0.5,
				Ears = not reduced,
				Mood = if caught then "Happy" else "Sad",
			}
			local okIdle, res = pcall(function()
				return if type(DogAnimator.Idle) == "function" then DogAnimator.Idle(model, opts) else nil
			end)
			if okIdle and type(res) == "table" and type(res.Stop) == "function" then
				idle = res
			elseif not reduced then
				local okNew, anim = pcall(DogAnimator.new, model, { AlwaysAnimate = true })
				if okNew and anim then
					pcall(anim.Play, anim, if caught then "idle" else "sit")
					idle = { Stop = function()
						pcall(anim.Destroy, anim)
					end }
				end
			end
		end

		if not reduced then
			local t = 0
			local startYaw = yaw0
			local turnPeriod = ec.TurnPeriod or 6
			local pulsePeriod = ec.GlowPulse or 1.6
			table.insert(conns, RunService.RenderStepped:Connect(function(dt)
				t += dt
				local okStep = pcall(function()
					if caught then
						view(startYaw + t / turnPeriod * 360)
					end
					placeMotes(t)
					local k = 0.5 + 0.5 * math.sin(t * math.pi * 2 / pulsePeriod)
					for _, pl in pulse do
						pl.Part.Transparency = pl.Base + pl.Amp * k
					end
					if caught and tier >= 5 then
						for i, g in glows do
							g.BackgroundTransparency = 0.88 - i * 0.025 + 0.05 * k
						end
					end
				end)
				if not okStep then
					for _, c in conns do
						c:Disconnect()
					end
					table.clear(conns)
				end
			end))
		end
		handle.Ok = true
	end)
	if not ok then
		warn("[Reveal] dog viewport fell back to the icon: " .. tostring(err))
		release()
		fallbackIcon()
	end

	function handle.Destroy(_self: Handle)
		if destroyed then
			return
		end
		destroyed = true
		release()
		root:Destroy()
	end

	return handle :: Handle
end

return DogViewport
