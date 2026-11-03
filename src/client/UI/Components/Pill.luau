--!strict
-- Currency / stat pill: icon on the left, value on the right, palette gradient, count-up on change.
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent.Parent:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Icon = require(script.Parent:WaitForChild("Icon"))
local Label = require(script.Parent:WaitForChild("Label"))

local Pill = {}

export type PillProps = {
	Icon: string,
	Palette: string?,
	Format: ((number) -> string)?,
	Width: number?,
	Height: number?,
	Parent: Instance?,
	LayoutOrder: number?,
	Name: string?,
	ZIndex: number?,
	Suffix: string?, -- static text after the number
	OnClick: (() -> ())?,
}

export type PillHandle = {
	Root: Frame,
	Value: TextLabel,
	Icon: Frame,
	Set: (self: PillHandle, n: number, animate: boolean?) -> (),
	SetText: (self: PillHandle, text: string) -> (),
}

function Pill.new(props: PillProps): PillHandle
	local palette = Theme.Palette[props.Palette or "Cash"] or Theme.Palette.Cash
	local h = props.Height or 40
	local iconSize = if h >= 40 then 32 else 16
	local root: Frame = Make("Frame", {
		Name = props.Name or ("Pill_" .. props.Icon),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(props.Width or 150, h),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 2,
	})
	Decor.Corner(root, Theme.Radius.Pill)
	Decor.Stroke(root, Theme.Stroke.Panel)
	Decor.PaletteGradient(root, palette)
	Decor.Shadow(root, "Hard")
	-- Icon sits in an ink-ringed circle hanging slightly off the left edge.
	local ring: Frame = Make("Frame", {
		Name = "Ring",
		BackgroundColor3 = Theme.Color.Paper,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(h, h),
		Position = UDim2.new(0, -4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = root.ZIndex + 1,
		Parent = root,
	})
	Decor.Corner(ring, Theme.Radius.Pill)
	Decor.Stroke(ring, Theme.Stroke.Panel)
	local iconFrame = Icon.new({ Name = props.Icon, Size = iconSize, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = root.ZIndex + 2, Parent = ring })
	local value = Label.Display({
		Name = "Value",
		Text = "0",
		TextSize = if h >= 40 then Theme.Text.Currency else Theme.Text.Body,
		Color = palette.Text,
		Size = UDim2.new(1, -(h + Theme.Space.M), 1, 0),
		Position = UDim2.new(0, h, 0, 0),
		XAlign = Enum.TextXAlignment.Left,
		ZIndex = root.ZIndex + 1,
		Parent = root,
	})
	if props.OnClick then
		Make("TextButton", {
			Name = "Click",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = root.ZIndex + 3,
			Parent = root,
			Activated = props.OnClick,
		})
	end
	local fmt = props.Format or function(n: number)
		return tostring(math.floor(n))
	end
	local current = 0
	local handle = { Root = root, Value = value, Icon = iconFrame } :: any
	function handle.Set(_, n: number, animate: boolean?)
		local suffix = props.Suffix or ""
		if animate == false or n == current then
			value.Text = fmt(n) .. suffix
		else
			Motion.CountUp(value, current, n, function(v)
				return fmt(v) .. suffix
			end)
			if n > current then
				Motion.Pulse(root)
			end
		end
		current = n
	end
	function handle.SetText(_, text: string)
		value.Text = text
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: PillHandle
end

return Pill
