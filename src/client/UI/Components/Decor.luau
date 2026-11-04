--!strict
-- Surface helpers: corners, strokes, gradients, shadows, padding. One place so every surface matches.
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Make = require(script.Parent.Parent:WaitForChild("Make"))

local Decor = {}

local hasUIShadow = (function()
	local ok = pcall(function()
		local s = Instance.new("UIShadow")
		s:Destroy()
	end)
	return ok
end)()
Decor.HasUIShadow = hasUIShadow

local shadowCount = 0

function Decor.Corner(parent: Instance, radius: number?): UICorner
	return Make("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.Button), Parent = parent })
end

-- Header bands: rounded on top only.
function Decor.TopCorners(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	local ok = pcall(function()
		(c :: any).TopLeftRadius = UDim.new(0, radius);
		(c :: any).TopRightRadius = UDim.new(0, radius);
		(c :: any).BottomLeftRadius = UDim.new(0, 0);
		(c :: any).BottomRightRadius = UDim.new(0, 0)
	end)
	if not ok then
		c.CornerRadius = UDim.new(0, radius)
	end
	c.Parent = parent
	return c
end

function Decor.Stroke(parent: Instance, thickness: number?, color: Color3?, mode: Enum.ApplyStrokeMode?): UIStroke
	return Make("UIStroke", {
		Thickness = thickness or Theme.Stroke.Panel,
		Color = color or Theme.Color.Ink,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function Decor.TextStroke(parent: Instance, thickness: number?): UIStroke
	return Decor.Stroke(parent, thickness or Theme.Stroke.Text, Theme.Color.Ink, Enum.ApplyStrokeMode.Contextual)
end

function Decor.Gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Make("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(1, bottom) }),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function Decor.PaletteGradient(parent: Instance, palette: Theme.Palette): UIGradient
	return Decor.Gradient(parent, palette.Top, palette.Bottom)
end

-- Hard cartoon drop shadow (buttons, cards) or soft (modals). Silently no-ops past the on-screen budget
-- or on clients without UIShadow.
function Decor.Shadow(parent: Instance, kind: "Hard" | "Soft"?): Instance?
	if not hasUIShadow or shadowCount >= Theme.Shadow.MaxOnScreen then
		return nil
	end
	local spec = if kind == "Soft" then Theme.Shadow.Soft else Theme.Shadow.Hard
	local s = Instance.new("UIShadow") :: any
	s.BlurRadius = UDim.new(0, spec.Blur)
	s.Offset = UDim2.fromOffset(spec.Offset.X, spec.Offset.Y)
	s.Color = Theme.Color.Ink
	s.Transparency = spec.Transparency
	s.ZIndex = -1
	s.Parent = parent
	shadowCount += 1
	s.Destroying:Connect(function()
		shadowCount -= 1
	end)
	return s
end

function Decor.Padding(parent: Instance, all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Make("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		Parent = parent,
	})
end

function Decor.List(parent: Instance, direction: Enum.FillDirection, gap: number, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return Make("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

function Decor.Grid(parent: Instance, cell: Vector2, gap: number): UIGridLayout
	return Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

-- Diagonal highlight stripes (the panel header's shine): a full-size white overlay whose UIGradient
-- transparency alternates in bands, rotated so the bands run diagonally. No rotated frames, so clipping holds.
function Decor.Stripes(parent: GuiObject, opts: { Bands: number?, Strength: number?, Rotation: number?, ZIndex: number? }?): Frame
	local o = opts or {}
	local bands = math.clamp(o.Bands or 4, 1, 4) -- NumberSequence holds at most 20 keypoints
	local strength = o.Strength or 0.78 -- transparency of a band (1 = invisible)
	local f: Frame = Make("Frame", {
		Name = "Stripes",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = o.ZIndex or (parent.ZIndex + 1),
		Parent = parent,
	})
	local kps = { NumberSequenceKeypoint.new(0, 1) }
	-- bands sit in the right two thirds (the title stays clean on the left)
	local step = 0.62 / bands
	for i = 0, bands - 1 do
		local a = 0.34 + i * step
		local w = step * (if i % 2 == 0 then 0.55 else 0.3)
		table.insert(kps, NumberSequenceKeypoint.new(a, 1))
		table.insert(kps, NumberSequenceKeypoint.new(a + 0.001, strength))
		table.insert(kps, NumberSequenceKeypoint.new(a + w, strength))
		table.insert(kps, NumberSequenceKeypoint.new(a + w + 0.001, 1))
	end
	table.insert(kps, NumberSequenceKeypoint.new(1, 1))
	Make("UIGradient", { Transparency = NumberSequence.new(kps), Rotation = o.Rotation or 20, Parent = f })
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = f
	end
	return f
end

-- A plain gradient surface: Frame + corner + stroke + gradient (+ optional shadow).
function Decor.Surface(props: { Palette: Theme.Palette?, Radius: number?, Stroke: number?, Shadow: ("Hard" | "Soft")?, Size: UDim2?, Position: UDim2?, AnchorPoint: Vector2?, Parent: Instance?, Name: string?, LayoutOrder: number?, ZIndex: number? }): Frame
	local palette = props.Palette or Theme.Palette.Paper
	local f = Make("Frame", {
		Name = props.Name or "Surface",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(100, 40),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	Decor.Corner(f, props.Radius or Theme.Radius.Button)
	Decor.Stroke(f, props.Stroke or Theme.Stroke.Panel)
	Decor.PaletteGradient(f, palette)
	if props.Shadow then
		Decor.Shadow(f, props.Shadow)
	end
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

-- Product of every UIScale between `gui` and its ScreenGui. AbsoluteSize is post-scale; offsets are pre-scale,
-- so code that mixes the two (virtual grids) divides AbsoluteSize by this.
function Decor.EffectiveScale(gui: Instance): number
	local s = 1
	local p: Instance? = gui
	while p and not p:IsA("LayerCollector") do
		local us = p:FindFirstChildOfClass("UIScale")
		if us then
			s *= us.Scale
		end
		p = p.Parent
	end
	return s
end

return Decor
