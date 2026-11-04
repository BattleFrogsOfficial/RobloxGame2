--!strict
-- The one button. Text, icon, or both; palette gradient; stroke; hard shadow; press/hover motion; disabled state.
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent.Parent:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Icon = require(script.Parent:WaitForChild("Icon"))
local Label = require(script.Parent:WaitForChild("Label"))

local Button = {}

export type ButtonProps = {
	Text: string?,
	Icon: string?,
	IconSize: number?,
	Palette: string?, -- key of Theme.Palette
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	LayoutOrder: number?,
	ZIndex: number?,
	OnClick: (() -> ())?,
	TextSize: number?,
	Name: string?,
	Radius: number?,
	Shadow: boolean?,
	Badge: boolean?, -- small red notification dot
	Caption: string?, -- tiny label under an icon-only button (side menu)
	SoundOff: boolean?,
}

export type ButtonHandle = {
	Root: TextButton,
	Label: TextLabel?,
	Icon: Frame?,
	Badge: Frame?,
	SetEnabled: (self: ButtonHandle, enabled: boolean) -> (),
	SetText: (self: ButtonHandle, text: string) -> (),
	SetPalette: (self: ButtonHandle, palette: string) -> (),
	SetBadge: (self: ButtonHandle, on: boolean) -> (),
}

function Button.new(props: ButtonProps): ButtonHandle
	local palette = Theme.Palette[props.Palette or "Sky"] or Theme.Palette.Sky
	local size = props.Size or UDim2.fromOffset(160, 48)
	local root: TextButton = Make("TextButton", {
		Name = props.Name or ("Button_" .. (props.Text or props.Icon or "")),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	Decor.Corner(root, props.Radius or Theme.Radius.Button)
	Decor.Stroke(root, Theme.Stroke.Button)
	local gradient = Decor.PaletteGradient(root, palette)
	if props.Shadow ~= false then
		Decor.Shadow(root, "Hard")
	end
	-- toy gloss: a soft white band across the top half
	local gloss = Make("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -6, 0.42, -2),
		Position = UDim2.fromOffset(3, 3),
		ZIndex = (props.ZIndex or 1),
		Parent = root,
	})
	Decor.Corner(gloss, math.max(2, (props.Radius or Theme.Radius.Button) - 2))

	local iconFrame: Frame? = nil
	local label: TextLabel? = nil
	local z = root.ZIndex + 1

	if props.Icon and props.Text then
		local row = Make("Frame", {
			Name = "Row",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
			Parent = root,
		})
		Decor.Padding(row, 0, Theme.Space.S)
		Decor.List(row, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		iconFrame = Icon.new({ Name = props.Icon, Size = props.IconSize or 32, LayoutOrder = 1, ZIndex = z, Parent = row })
		label = Label.Display({
			Text = props.Text,
			TextSize = props.TextSize or Theme.Text.Button,
			Color = palette.Text,
			Size = UDim2.new(1, -((props.IconSize or 32) + Theme.Space.S), 1, 0),
			XAlign = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
			ZIndex = z,
			Parent = row,
		})
	elseif props.Icon then
		iconFrame = Icon.new({
			Name = props.Icon,
			Size = props.IconSize or 32,
			Position = UDim2.fromScale(0.5, if props.Caption then 0.36 else 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z,
			Parent = root,
		})
		if props.Caption then
			Label.Display({
				Name = "Caption",
				Text = props.Caption,
				TextSize = Theme.Text.Caption,
				Color = palette.Text,
				Size = UDim2.new(1, -4, 0, 16),
				Position = UDim2.new(0.5, 0, 1, -3),
				AnchorPoint = Vector2.new(0.5, 1),
				XAlign = Enum.TextXAlignment.Center,
				ZIndex = z,
				Parent = root,
			})
		end
	else
		label = Label.Display({
			Text = props.Text or "",
			TextSize = props.TextSize or Theme.Text.Button,
			Color = palette.Text,
			Size = UDim2.new(1, -Theme.Space.L, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			XAlign = Enum.TextXAlignment.Center,
			ZIndex = z,
			Parent = root,
		})
	end

	local badge: Frame? = nil
	local function makeBadge(): Frame
		local b = Make("Frame", {
			Name = "Badge",
			BackgroundColor3 = Theme.Palette.Danger.Top,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(1, 2, 0, -2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 2,
			Visible = false,
			Parent = root,
		})
		Decor.Corner(b, 999)
		Decor.Stroke(b, 2)
		return b
	end
	if props.Badge then
		badge = makeBadge()
		badge.Visible = true
	end

	local enabled = true
	root.MouseEnter:Connect(function()
		if enabled then
			Motion.Hover(root, true)
		end
	end)
	root.MouseLeave:Connect(function()
		if enabled then
			Motion.Hover(root, false)
		end
	end)
	root.Activated:Connect(function()
		if not enabled then
			return
		end
		Motion.Press(root)
		if props.OnClick then
			props.OnClick()
		end
	end)

	local handle = {
		Root = root,
		Label = label,
		Icon = iconFrame,
		Badge = badge,
	} :: any
	function handle.SetEnabled(_, on: boolean)
		enabled = on
		root.Active = on
		local t = if on then 0 else 0.5
		root.BackgroundTransparency = t
		for _, d in root:GetDescendants() do
			if d:IsA("TextLabel") then
				d.TextTransparency = t
			elseif d:IsA("Frame") and d.Name == "px" then
				d.BackgroundTransparency = t
			elseif d:IsA("UIStroke") then
				d.Transparency = t
			elseif d:IsA("Frame") and d.Name == "Gloss" then
				d.BackgroundTransparency = if on then 0.8 else 0.92
			end
		end
	end
	function handle.SetText(_, text: string)
		if label then
			label.Text = text
		end
	end
	function handle.SetPalette(_, key: string)
		local p = Theme.Palette[key] or Theme.Palette.Sky
		gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, p.Top), ColorSequenceKeypoint.new(1, p.Bottom) })
		if label then
			label.TextColor3 = p.Text
		end
	end
	function handle.SetBadge(_, on: boolean)
		if not badge then
			badge = makeBadge()
			handle.Badge = badge
		end
		badge.Visible = on
	end

	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: ButtonHandle
end

-- The square red close button with a heavy white X, inside the panel header's right end.
Button.CloseSize = 48
function Button.Close(parent: Instance, onClick: () -> ()): ButtonHandle
	return Button.new({
		Name = "Close",
		Icon = "close",
		IconSize = 32,
		Palette = "Danger",
		Size = UDim2.fromOffset(Button.CloseSize, Button.CloseSize),
		Position = UDim2.new(1, -10, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Radius = 8,
		ZIndex = 60,
		Parent = parent,
		OnClick = onClick,
	})
end

return Button
