--!strict
-- Chunky cartoony button: rounded, stroked, bounces on press. Returns the TextButton.
--   Button.new({ Text = "Buy", Color = Theme.Color.Accent, OnClick = fn, Size = ..., TextMax = 20 })
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Create = require(script.Parent:WaitForChild("Create"))
local TweenService = game:GetService("TweenService")

local Button = {}

export type Props = {
	Text: string?,
	Color: Color3?,
	TextColor: Color3?,
	OnClick: (() -> ())?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextMax: number?,
	LayoutOrder: number?,
	Name: string?,
	Parent: Instance?,
	Corner: number?,
	ZIndex: number?,
}

local function textColorFor(bg: Color3): Color3
	local lum = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return if lum > 0.6 then Theme.Color.TextDark else Theme.Color.Text
end

function Button.new(p: Props): TextButton
	local color = p.Color or Theme.Color.Accent
	local b: TextButton = Create.New("TextButton", {
		Name = p.Name or "Button",
		Text = p.Text or "",
		Font = Theme.Font.Title,
		TextScaled = true,
		TextColor3 = p.TextColor or textColorFor(color),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		LayoutOrder = p.LayoutOrder or 0,
		ZIndex = p.ZIndex or 1,
	})
	Create.Corner(p.Corner or Theme.CornerSmall).Parent = b
	Create.Stroke().Parent = b
	Create.Padding(3, 6).Parent = b
	Create.TextLimit(p.TextMax or Theme.TextMax.Normal).Parent = b
	local scale = Create.New("UIScale", { Parent = b })
	b:SetAttribute("BaseColor", color)
	local function baseColor(): Color3
		local c = b:GetAttribute("BaseColor")
		return if typeof(c) == "Color3" then c else color
	end
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = Theme.Lighten(baseColor(), 0.12)
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = baseColor()
		scale.Scale = 1
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.93 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	if p.OnClick then
		local fn = p.OnClick
		b.Activated:Connect(function()
			fn()
		end)
	end
	if p.Parent then
		b.Parent = p.Parent
	end
	return b
end

-- Recolour a button made by Button.new (keeps hover behaviour consistent).
function Button.SetColor(b: TextButton, color: Color3)
	b:SetAttribute("BaseColor", color)
	b.BackgroundColor3 = color
	b.TextColor3 = textColorFor(color)
end

return Button
