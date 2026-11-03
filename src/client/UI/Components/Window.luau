--!strict
-- Centred modal window: title bar, close button (top-right, inside the window), scrollable-friendly body.
-- The window fills its host frame (the HudLayout "Modal" rect, managed by UI/Windows).
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Create = require(script.Parent:WaitForChild("Create"))
local Button = require(script.Parent:WaitForChild("Button"))

local Window = {}

export type Window = {
	Frame: Frame,
	Title: TextLabel,
	Body: Frame,
	TitleBar: Frame,
	Close: TextButton,
}

-- titleHeight is a fraction of the window height (clamped by constraints below)
function Window.new(title: string, accent: Color3?, onClose: () -> ()): Window
	local frame = Create.Panel({ Name = "Window_" .. title, Size = UDim2.fromScale(1, 1), Visible = false,
		BackgroundColor3 = Theme.Color.Panel })
	local bar = Create.New("Frame", { Name = "TitleBar", BackgroundColor3 = accent or Theme.Color.PanelLight, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 44), Parent = frame }, { Create.Corner() })
	-- square off the bar's bottom corners
	Create.New("Frame", { BackgroundColor3 = accent or Theme.Color.PanelLight, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 1, -12), Parent = bar })
	local titleLabel = Create.Label({ Name = "Title", Text = title, Size = UDim2.new(1, -64, 1, -8), Position = UDim2.fromOffset(14, 4),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.5, ZIndex = 2, Parent = bar }, Theme.TextMax.Title)
	local close = Button.new({ Name = "Close", Text = "X", Color = Theme.Color.Bad, Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(1, -6, 0, 4), AnchorPoint = Vector2.new(1, 0), TextMax = 22, OnClick = onClose, Parent = bar, ZIndex = 3 })
	local body = Create.New("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, -58),
		Position = UDim2.fromOffset(10, 50), Parent = frame })
	-- short windows (phone landscape) get a slimmer title bar so the body keeps more room
	local function fit()
		local h = frame.AbsoluteSize.Y
		if h <= 0 then
			return
		end
		local barH = math.clamp(math.floor(h * 0.12), 34, 44)
		bar.Size = UDim2.new(1, 0, 0, barH)
		close.Size = UDim2.fromOffset(barH - 8, barH - 8)
		body.Position = UDim2.fromOffset(10, barH + 6)
		body.Size = UDim2.new(1, -20, 1, -(barH + 14))
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return { Frame = frame, Title = titleLabel, Body = body, TitleBar = bar, Close = close }
end

return Window
