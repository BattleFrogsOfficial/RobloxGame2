--!strict
-- Scrolling list of uniform rows (swatch | title + subtitle | action button) for short lists such as the
-- shop and the odds panel. Long lists (Kennel Book, Yard) use VirtualGrid instead.
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Create = require(script.Parent:WaitForChild("Create"))
local Button = require(script.Parent:WaitForChild("Button"))

local RowList = {}

export type RowProps = {
	Title: string,
	Subtitle: string?,
	Color: Color3?,
	SwatchText: string?,
	ButtonText: string?,
	ButtonColor: Color3?,
	OnClick: (() -> ())?,
	RichText: boolean?,
	Height: number?,
}

export type List = {
	Frame: ScrollingFrame,
	Clear: () -> (),
	Row: (RowProps) -> Frame,
	Header: (text: string) -> TextLabel,
	Text: (text: string, height: number?) -> TextLabel,
}

function RowList.new(parent: Instance, size: UDim2?, position: UDim2?): List
	local frame: ScrollingFrame = Create.New("ScrollingFrame", { Name = "RowList", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = size or UDim2.fromScale(1, 1), Position = position or UDim2.new(), ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Color.TextDim, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = parent })
	Create.List(Enum.FillDirection.Vertical, Theme.Spacing.S).Parent = frame
	Create.New("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4),
		Parent = frame })
	local order = 0
	local list: List
	list = {
		Frame = frame,
		Clear = function()
			for _, c in frame:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			order = 0
		end,
		Row = function(p: RowProps): Frame
			order += 1
			local h = p.Height or 56
			local row = Create.New("Frame", { Name = "Row", BackgroundColor3 = Theme.Color.PanelLight, BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, h), LayoutOrder = order, Parent = frame }, { Create.Corner(Theme.CornerSmall) })
			local swatch = Create.New("Frame", { Name = "Swatch", BackgroundColor3 = p.Color or Theme.Color.Info, Size = UDim2.new(0, h - 12, 0, h - 12),
				Position = UDim2.fromOffset(6, 6), Parent = row }, { Create.Corner(Theme.CornerSmall), Create.Stroke(nil, 2) })
			if p.SwatchText then
				Create.Label({ Text = p.SwatchText, TextColor3 = Theme.Color.TextDark, Size = UDim2.fromScale(0.8, 0.8),
					Position = UDim2.fromScale(0.1, 0.1), Parent = swatch }, 22)
			end
			local btnW = if p.ButtonText then 128 else 0
			local textW = -(h + 6 + btnW + 12)
			Create.Label({ Name = "Title", Text = p.Title, RichText = p.RichText == true, TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, textW, 0.52, -4), Position = UDim2.new(0, h + 4, 0, 4), Parent = row }, Theme.TextMax.Normal)
			if p.Subtitle then
				Create.Label({ Name = "Subtitle", Text = p.Subtitle, RichText = p.RichText == true, Font = Theme.Font.Body,
					TextColor3 = Theme.Color.TextDim, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, textW, 0.42, -4),
					Position = UDim2.new(0, h + 4, 0.55, 0), Parent = row }, Theme.TextMax.Small)
			end
			if p.ButtonText then
				Button.new({ Name = "Action", Text = p.ButtonText, Color = p.ButtonColor or Theme.Color.Accent, TextMax = 18,
					Size = UDim2.new(0, btnW, 1, -14), Position = UDim2.new(1, -7, 0, 7), AnchorPoint = Vector2.new(1, 0),
					OnClick = p.OnClick, Parent = row })
			end
			return row
		end,
		Header = function(text: string): TextLabel
			order += 1
			return Create.Label({ Name = "Header", Text = text, TextColor3 = Theme.Color.Accent, TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, Parent = frame }, Theme.TextMax.Normal)
		end,
		Text = function(text: string, height: number?): TextLabel
			order += 1
			return Create.Label({ Name = "Text", Text = text, RichText = true, Font = Theme.Font.Body, TextColor3 = Theme.Color.TextDim,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, height or 40),
				LayoutOrder = order, Parent = frame }, Theme.TextMax.Small)
		end,
	}
	return list
end

return RowList
