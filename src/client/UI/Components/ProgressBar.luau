--!strict
-- Pill-shaped progress bar with an optional centred label and a sweet-spot band.
-- Vertical = true fills bottom -> top (the throw power meter); band and marker follow the same axis.
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Label = require(script.Parent:WaitForChild("Label"))

local ProgressBar = {}

export type BarProps = {
	Palette: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	LayoutOrder: number?,
	ZIndex: number?,
	Label: string?,
	Name: string?,
	Thin: boolean?,
	Vertical: boolean?,
}

export type BarHandle = {
	Root: Frame,
	Fill: Frame,
	Label: TextLabel?,
	Stroke: UIStroke,
	Band: Frame,
	Gradient: UIGradient,
	Vertical: boolean,
	SetFraction: (self: BarHandle, f: number) -> (),
	SetLabel: (self: BarHandle, text: string) -> (),
	SetBand: (self: BarHandle, from: number, to: number, color: Color3) -> (),
	SetMarker: (self: BarHandle, at: number?) -> (),
	SetColors: (self: BarHandle, top: Color3, bottom: Color3) -> (),
}

function ProgressBar.new(props: BarProps): BarHandle
	local palette = Theme.Palette[props.Palette or "Grass"] or Theme.Palette.Grass
	local vertical = props.Vertical == true
	local defaultThickness = if props.Thin then 12 else 24
	local root: Frame = Make("Frame", {
		Name = props.Name or "Bar",
		BackgroundColor3 = Theme.Color.Track,
		BorderSizePixel = 0,
		Size = props.Size or (if vertical then UDim2.new(0, defaultThickness, 1, 0) else UDim2.new(1, 0, 0, defaultThickness)),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 2,
		ClipsDescendants = true,
	})
	Decor.Corner(root, Theme.Radius.Pill)
	local stroke = Decor.Stroke(root, if props.Thin then 2 else Theme.Stroke.Panel)
	local band: Frame = Make("Frame", {
		Name = "Band",
		BackgroundColor3 = Theme.Palette.Tennis.Top,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Visible = false,
		ZIndex = root.ZIndex + 1,
		Parent = root,
	})
	local fill: Frame = Make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = if vertical then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 1),
		Position = if vertical then UDim2.fromScale(0, 1) else UDim2.new(),
		AnchorPoint = if vertical then Vector2.new(0, 1) else Vector2.new(),
		ZIndex = root.ZIndex + 2,
		Parent = root,
	})
	Decor.Corner(fill, Theme.Radius.Pill)
	local gradient = Decor.PaletteGradient(fill, palette)
	local marker: Frame = Make("Frame", {
		Name = "Marker",
		BackgroundColor3 = Theme.Color.Ink,
		BorderSizePixel = 0,
		Size = if vertical then UDim2.new(1, 0, 0, 3) else UDim2.new(0, 4, 1, 0),
		AnchorPoint = if vertical then Vector2.new(0, 0.5) else Vector2.new(0.5, 0),
		Visible = false,
		ZIndex = root.ZIndex + 3,
		Parent = root,
	})
	local label: TextLabel? = nil
	if props.Label then
		label = Label.Display({
			Text = props.Label,
			TextSize = if props.Thin then Theme.Text.Caption else Theme.Text.Body,
			Size = UDim2.fromScale(1, 1),
			XAlign = Enum.TextXAlignment.Center,
			ZIndex = root.ZIndex + 4,
			Parent = root,
		})
	end
	local handle = { Root = root, Fill = fill, Label = label, Stroke = stroke, Band = band, Gradient = gradient, Vertical = vertical } :: any
	function handle.SetFraction(_, f: number)
		local c = math.clamp(f, 0, 1)
		fill.Size = if vertical then UDim2.fromScale(1, c) else UDim2.fromScale(c, 1)
	end
	function handle.SetLabel(_, text: string)
		if label then
			label.Text = text
		end
	end
	function handle.SetBand(_, from: number, to: number, color: Color3)
		band.Visible = true
		band.BackgroundColor3 = color
		local a, b = math.clamp(from, 0, 1), math.clamp(to, 0, 1)
		if vertical then
			band.Position = UDim2.fromScale(0, 1 - b)
			band.Size = UDim2.fromScale(1, math.max(0, b - a))
		else
			band.Position = UDim2.fromScale(a, 0)
			band.Size = UDim2.fromScale(math.max(0, b - a), 1)
		end
	end
	function handle.SetMarker(_, at: number?)
		marker.Visible = at ~= nil
		if at then
			local c = math.clamp(at, 0, 1)
			marker.Position = if vertical then UDim2.fromScale(0, 1 - c) else UDim2.fromScale(c, 0)
		end
	end
	function handle.SetColors(_, top: Color3, bottom: Color3)
		gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(1, bottom) })
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: BarHandle
end

return ProgressBar
