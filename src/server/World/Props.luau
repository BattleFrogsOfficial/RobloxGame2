--!strict
-- Small, reusable chunky low-poly props. Every part is Anchored, smooth-surfaced and (by default)
-- non-colliding + non-touchable so decoration never snags players. Floors/walls opt in to collision.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any

local Props = {}

Props.PartCount = 0

local BASE: Enum.Material = WorldTheme.BaseMaterial
local NEON: Enum.Material = WorldTheme.AccentMaterial

export type PartOpts = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Collide: boolean?, -- default false
	Query: boolean?, -- default true
	Shadow: boolean?, -- default true
	Shape: Enum.PartType?,
	Parent: Instance,
}

local function finish(p: BasePart, o: PartOpts)
	p.Name = o.Name or "Part"
	p.Anchored = true
	p.Size = o.Size
	p.CFrame = o.CFrame
	p.Color = o.Color or Color3.new(1, 1, 1)
	p.Material = o.Material or BASE
	p.Transparency = o.Transparency or 0
	p.CanCollide = o.Collide == true
	p.CanTouch = false
	p.CanQuery = o.Query ~= false
	p.CastShadow = o.Shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = o.Parent
	Props.PartCount += 1
end

function Props.Part(o: PartOpts): Part
	local p = Instance.new("Part")
	if o.Shape then
		p.Shape = o.Shape
	end
	finish(p, o)
	return p
end

function Props.Wedge(o: PartOpts): WedgePart
	local p = Instance.new("WedgePart")
	finish(p, o)
	return p
end

-- Shorthand block. Position is the part centre.
function Props.Block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3,
	material: Enum.Material?, collide: boolean?): Part
	return Props.Part({ Parent = parent, Name = name, Size = size, CFrame = cf, Color = color,
		Material = material, Collide = collide })
end

-- Axis-aligned floor slab whose TOP surface sits at topY, covering [minX,maxX] x [minZ,maxZ].
function Props.Slab(parent: Instance, name: string, minX: number, maxX: number, minZ: number, maxZ: number,
	topY: number, thickness: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return Props.Part({
		Parent = parent, Name = name,
		Size = Vector3.new(maxX - minX, thickness, maxZ - minZ),
		CFrame = CFrame.new((minX + maxX) / 2, topY - thickness / 2, (minZ + maxZ) / 2),
		Color = color, Material = material, Collide = collide ~= false,
	})
end

-- Vertical cylinder standing on `base` (bottom centre).
function Props.Cylinder(parent: Instance, name: string, base: Vector3, height: number, diameter: number,
	color: Color3, material: Enum.Material?, collide: boolean?): Part
	return Props.Part({
		Parent = parent, Name = name, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color, Material = material, Collide = collide,
	})
end

function Props.Ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3,
	material: Enum.Material?): Part
	return Props.Part({ Parent = parent, Name = name, Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter), CFrame = CFrame.new(center), Color = color, Material = material })
end

-- Squashed/stretched sphere (SpecialMesh) for chunky round canopies, hills, clouds.
function Props.Ellipsoid(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3,
	material: Enum.Material?): Part
	local p = Props.Part({ Parent = parent, Name = name, Size = size, CFrame = cf, Color = color, Material = material })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

function Props.Model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Props.Folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Props.Tag(inst: Instance, tag: string, attrs: { [string]: any }?)
	CollectionService:AddTag(inst, tag)
	if attrs then
		for k, v in attrs do
			inst:SetAttribute(k, v)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------
export type LabelOpts = {
	Face: Enum.NormalId?, -- default Front
	LabelName: string?, -- default "Label"
	TextColor: Color3?,
	StrokeColor: Color3?,
	PixelsPerStud: number?,
	Font: Enum.Font?,
}

-- SurfaceGui + full-size TextLabel on one face of `part`. Glows (LightInfluence 0) so it reads far away.
function Props.Label(part: BasePart, text: string, o: LabelOpts?): TextLabel
	local opts: LabelOpts = o or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = opts.Face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 20
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.MaxDistance = 2000
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = opts.LabelName or "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.94, 0.9)
	label.Position = UDim2.fromScale(0.03, 0.05)
	label.Font = opts.Font or WorldTheme.Font
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = opts.TextColor or Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = opts.StrokeColor or Color3.fromRGB(20, 20, 35)
	stroke.Parent = label
	return label
end

-- Free-standing sign: board (facing `dir`, horizontal) on two posts. `bottomY` = board bottom height.
-- Returns the board part (tag it) and its TextLabel (nil when `text` is nil or "": a blank board).
-- World text rule: only zone-name arch boards, yard owner signs and the kennel count carry text.
function Props.Sign(parent: Instance, name: string, footCenter: Vector3, dir: Vector3, boardSize: Vector3,
	bottomY: number, boardColor: Color3, trimColor: Color3, text: string?, labelOpts: LabelOpts?): (Part, TextLabel?)
	local model = Props.Model(parent, name)
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local right = Vector3.new(-flat.Z, 0, flat.X)
	local boardCenter = footCenter + Vector3.new(0, bottomY + boardSize.Y / 2, 0)
	local board = Props.Part({ Parent = model, Name = "Board", Size = boardSize,
		CFrame = CFrame.lookAt(boardCenter, boardCenter + flat), Color = boardColor })
	-- neon trim frame behind the board (slightly larger)
	Props.Part({ Parent = model, Name = "Trim", Size = boardSize + Vector3.new(1.2, 1.2, -boardSize.Z * 0.5),
		CFrame = CFrame.lookAt(boardCenter - flat * (boardSize.Z * 0.3), boardCenter), Color = trimColor, Material = NEON })
	if bottomY > 0 then
		for _, side in { -1, 1 } do
			local foot = footCenter + right * side * (boardSize.X / 2 - 1.5) - flat * (boardSize.Z * 0.5 + 0.5)
			Props.Cylinder(model, "Post", foot, bottomY + boardSize.Y * 0.6, 1.2, Color3.fromRGB(60, 60, 75))
		end
	end
	model.PrimaryPart = board
	local label = if text and text ~= "" then Props.Label(board, text, labelOpts) else nil
	return board, label
end

----------------------------------------------------------------------------------------------------
-- Nature
----------------------------------------------------------------------------------------------------
function Props.Tree(parent: Instance, base: Vector3, scale: number, trunk: Color3, leaf: Color3): Model
	local m = Props.Model(parent, "Tree")
	local h = 7 * scale
	Props.Cylinder(m, "Trunk", base, h, 1.6 * scale, trunk)
	Props.Ellipsoid(m, "Canopy", CFrame.new(base + Vector3.new(0, h + 3 * scale, 0)),
		Vector3.new(10, 8, 10) * scale, leaf)
	Props.Ellipsoid(m, "Canopy2", CFrame.new(base + Vector3.new(1.5 * scale, h + 6.5 * scale, -1 * scale)),
		Vector3.new(6.5, 5.5, 6.5) * scale, leaf:Lerp(Color3.new(1, 1, 1), 0.12))
	return m
end

-- Chunky pine: three stacked, 45°-twisted blocks shrinking upward.
function Props.Pine(parent: Instance, base: Vector3, scale: number, leaf: Color3, trunk: Color3, snowCap: Color3?): Model
	local m = Props.Model(parent, "Pine")
	Props.Cylinder(m, "Trunk", base, 3 * scale, 1.4 * scale, trunk)
	local y = 3 * scale
	for i = 1, 3 do
		local w = (9 - i * 2.2) * scale
		local h = 3.2 * scale
		local c = if i % 2 == 0 then leaf:Lerp(Color3.new(0, 0, 0), 0.12) else leaf
		Props.Block(m, "Tier" .. i, Vector3.new(w, h, w),
			CFrame.new(base + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, math.rad(45 * i), 0), c)
		y += h * 0.8
	end
	if snowCap then
		Props.Block(m, "Snow", Vector3.new(2.2, 1.2, 2.2) * scale,
			CFrame.new(base + Vector3.new(0, y + 0.6 * scale, 0)) * CFrame.Angles(0, math.rad(20), 0), snowCap)
	end
	return m
end

function Props.Bush(parent: Instance, base: Vector3, scale: number, color: Color3): Part
	return Props.Ellipsoid(parent, "Bush", CFrame.new(base + Vector3.new(0, 1.6 * scale, 0)),
		Vector3.new(6, 4, 5) * scale, color)
end

function Props.Rock(parent: Instance, base: Vector3, scale: number, color: Color3, yaw: number): Part
	return Props.Block(parent, "Rock", Vector3.new(5, 3.2, 4) * scale,
		CFrame.new(base + Vector3.new(0, 1.2 * scale, 0)) * CFrame.Angles(math.rad(8), yaw, math.rad(-6)), color)
end

----------------------------------------------------------------------------------------------------
-- Street furniture
----------------------------------------------------------------------------------------------------
function Props.Bench(parent: Instance, base: Vector3, yaw: number, seat: Color3, leg: Color3): Model
	local m = Props.Model(parent, "Bench")
	local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	Props.Block(m, "Seat", Vector3.new(8, 0.6, 2.4), cf * CFrame.new(0, 2, 0), seat, nil, true)
	Props.Block(m, "Back", Vector3.new(8, 2, 0.5), cf * CFrame.new(0, 3.4, 1.1), seat)
	for _, x in { -3.2, 3.2 } do
		Props.Block(m, "Leg", Vector3.new(0.6, 2, 2.2), cf * CFrame.new(x, 1, 0), leg)
	end
	return m
end

function Props.Lamp(parent: Instance, base: Vector3, height: number, pole: Color3, glow: Color3, light: boolean): Model
	local m = Props.Model(parent, "Lamp")
	Props.Cylinder(m, "Pole", base, height, 0.9, pole)
	local bulb = Props.Ball(m, "Bulb", base + Vector3.new(0, height + 1, 0), 2.6, glow, NEON)
	if light then
		local pl = Instance.new("PointLight")
		pl.Range = 24
		pl.Brightness = 1.2
		pl.Color = glow
		pl.Shadows = false
		pl.Parent = bulb
	end
	return m
end

-- Rounded picket fence from a to b (same Y): cylinder posts with ball caps + two rails.
function Props.FenceLine(parent: Instance, a: Vector3, b: Vector3, spacing: number, height: number,
	color: Color3, collide: boolean): Model
	local m = Props.Model(parent, "Fence")
	local delta = b - a
	local len = delta.Magnitude
	if len < 0.5 then
		return m
	end
	local n = math.max(1, math.floor(len / spacing + 0.5))
	for i = 0, n do
		local p = a + delta * (i / n)
		Props.Cylinder(m, "Post", p, height, 1.1, color)
		Props.Ball(m, "Cap", p + Vector3.new(0, height, 0), 1.5, color)
	end
	local mid = (a + b) / 2
	local look = CFrame.lookAt(mid, b)
	for _, frac in { 0.35, 0.75 } do
		Props.Part({ Parent = m, Name = "Rail", Size = Vector3.new(0.5, 0.7, len),
			CFrame = look + Vector3.new(0, height * frac, 0), Color = color, Collide = collide })
	end
	return m
end

-- Archway across X at `center` (ground level), spanning `width` between pillar centres. Board text on both faces.
function Props.Arch(parent: Instance, name: string, center: Vector3, width: number, height: number,
	pillar: Color3, board: Color3, accent: Color3, text: string): (Model, Part)
	local m = Props.Model(parent, name)
	for _, side in { -1, 1 } do
		local base = center + Vector3.new(side * width / 2, 0, 0)
		Props.Block(m, "Pillar", Vector3.new(4, height, 4), CFrame.new(base + Vector3.new(0, height / 2, 0)), pillar)
		Props.Ball(m, "Orb", base + Vector3.new(0, height + 2.5, 0), 5, accent, NEON)
	end
	local boardH = math.max(8, height * 0.22)
	local boardPart = Props.Block(m, "Board", Vector3.new(width - 4, boardH, 2),
		CFrame.new(center + Vector3.new(0, height - boardH / 2, 0)), board)
	Props.Block(m, "Trim", Vector3.new(width - 3, boardH + 1.2, 1),
		CFrame.new(center + Vector3.new(0, height - boardH / 2, 0)), accent, NEON)
	Props.Label(boardPart, text, { Face = Enum.NormalId.Front, PixelsPerStud = 8 })
	Props.Label(boardPart, text, { Face = Enum.NormalId.Back, PixelsPerStud = 8 })
	-- arches are visual only: the board spans the field's centre lane, so it must never catch the
	-- cutscene's landing raycast (a dog would be stood on top of the arch) or any other query.
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
		end
	end
	m.PrimaryPart = boardPart
	return m, boardPart
end

-- Invisible collision wall (players only; never queried/touched).
function Props.Wall(parent: Instance, name: string, minX: number, maxX: number, minZ: number, maxZ: number,
	bottomY: number, height: number): Part
	local p = Props.Part({ Parent = parent, Name = name,
		Size = Vector3.new(math.max(1, maxX - minX), height, math.max(1, maxZ - minZ)),
		CFrame = CFrame.new((minX + maxX) / 2, bottomY + height / 2, (minZ + maxZ) / 2),
		Transparency = 1, Collide = true, Query = false, Shadow = false })
	return p
end

return Props
