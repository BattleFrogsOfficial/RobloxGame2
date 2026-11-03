--!strict
-- Horizontal tab strip. Tabs.new(parent, {"Balls","Training",...}, onSelect) -> { Select(name), Buttons }
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Create = require(script.Parent:WaitForChild("Create"))
local Button = require(script.Parent:WaitForChild("Button"))

local Tabs = {}

export type Tabs = { Frame: Frame, Buttons: { [string]: TextButton }, Select: (name: string) -> (), Current: () -> string }

function Tabs.new(parent: Instance, names: { string }, onSelect: (string) -> (), height: number?): Tabs
	local frame = Create.New("ScrollingFrame", { Name = "Tabs", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or 34), ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Color.TextDim,
		AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), Parent = parent })
	Create.List(Enum.FillDirection.Horizontal, Theme.Spacing.S).Parent = frame
	local buttons: { [string]: TextButton } = {}
	local current = names[1]
	local function paint()
		for n, b in buttons do
			Button.SetColor(b, if n == current then Theme.Color.Accent else Theme.Color.PanelLight)
		end
	end
	local function selectTab(name: string)
		current = name
		paint()
		onSelect(name)
	end
	for i, n in names do
		local b = Button.new({ Name = n, Text = n, LayoutOrder = i, Size = UDim2.new(0, math.max(72, #n * 10 + 24), 1, -4),
			Color = Theme.Color.PanelLight, TextMax = 18, Parent = frame, OnClick = function()
				selectTab(n)
			end })
		buttons[n] = b
	end
	paint()
	return {
		Frame = frame,
		Buttons = buttons,
		Select = selectTab,
		Current = function()
			return current
		end,
	}
end

return Tabs
