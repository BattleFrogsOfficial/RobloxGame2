--!strict
-- Pill-shaped progress bar with an optional centred label and a sweet-spot band (throw meter).
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
}

export type BarHandle = {
	Root: Frame,
	Fill: Frame,
	Label: TextLabel?,
	SetFraction: (self: BarHandle, f: number) -> (),
	SetLabel: (self: BarHandle, text: string) -> (),
	SetBand: (self: BarHandle, from: number, to: number, color: Color3) -> (),
	SetMarker: (self: BarHandle, at: number?) -> (),
}

function ProgressBar.new(props: BarProps): BarHandle
	local palette = Theme.Palette[props.Palette or "Grass"] or Theme.Palette.Grass
	local root: Frame = Make("Frame", {
		Name = props.Name or "Bar",
		BackgroundColor3 = Theme.Color.Track,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, if props.Thin then 12 else 24),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 2,
		ClipsDescendants = true,
	})
	Decor.Corner(root, Theme.Radius.Pill)
	Decor.Stroke(root, if props.Thin then 2 else Theme.Stroke.Panel)
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
		Size = UDim2.fromScale(0, 1),
		ZIndex = root.ZIndex + 2,
		Parent = root,
	})
	Decor.Corner(fill, Theme.Radius.Pill)
	Decor.PaletteGradient(fill, palette)
	local marker: Frame = Make("Frame", {
		Name = "Marker",
		BackgroundColor3 = Theme.Color.Ink,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0),
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
	local handle = { Root = root, Fill = fill, Label = label } :: any
	function handle.SetFraction(_, f: number)
		fill.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1)
	end
	function handle.SetLabel(_, text: string)
		if label then
			label.Text = text
		end
	end
	function handle.SetBand(_, from: number, to: number, color: Color3)
		band.Visible = true
		band.BackgroundColor3 = color
		band.Position = UDim2.fromScale(math.clamp(from, 0, 1), 0)
		band.Size = UDim2.fromScale(math.clamp(to - from, 0, 1), 1)
	end
	function handle.SetMarker(_, at: number?)
		marker.Visible = at ~= nil
		if at then
			marker.Position = UDim2.fromScale(math.clamp(at, 0, 1), 0)
		end
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: BarHandle
end

return ProgressBar
