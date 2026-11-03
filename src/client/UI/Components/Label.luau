--!strict
-- Text helpers so every label carries the right font, size, stroke and truncation.
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Decor = require(script.Parent:WaitForChild("Decor"))

local Label = {}

export type LabelProps = {
	Text: string,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Color: Color3?,
	Font: Enum.Font?,
	XAlign: Enum.TextXAlignment?,
	YAlign: Enum.TextYAlignment?,
	Parent: Instance?,
	LayoutOrder: number?,
	ZIndex: number?,
	Wrap: boolean?,
	AutoSize: Enum.AutomaticSize?,
	Name: string?,
	Stroke: boolean?, -- force on/off; Display defaults on, Body defaults off
	RichText: boolean?,
}

local function base(props: LabelProps, font: Enum.Font, size: number, color: Color3, stroke: boolean): TextLabel
	local label = Make("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Text = props.Text,
		Font = props.Font or font,
		TextSize = props.TextSize or size,
		TextColor3 = props.Color or color,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrap == true,
		TextTruncate = if props.Wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		RichText = props.RichText == true,
		Size = props.Size or UDim2.new(1, 0, 0, size + 6),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		AutomaticSize = props.AutoSize or Enum.AutomaticSize.None,
	})
	-- Ink strokes only belong on light text; dark text on paper gets none even for Display labels.
	local c = label.TextColor3
	local light = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) > 0.6
	local useStroke = if props.Stroke ~= nil then props.Stroke else (stroke and light)
	if useStroke then
		Decor.TextStroke(label)
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

-- Big friendly type: titles, numbers, button text. White with an Ink stroke by default.
function Label.Display(props: LabelProps): TextLabel
	return base(props, Theme.Font.Display, Theme.Text.H2, Theme.Color.White, true)
end

-- Body copy on paper: dark text, no stroke.
function Label.Body(props: LabelProps): TextLabel
	return base(props, Theme.Font.Body, Theme.Text.Body, Theme.Color.TextOnPaper, false)
end

function Label.Caption(props: LabelProps): TextLabel
	local p = table.clone(props)
	p.TextSize = p.TextSize or Theme.Text.Caption
	p.Color = p.Color or Theme.Color.TextMuted
	return base(p, Theme.Font.Body, Theme.Text.Caption, Theme.Color.TextMuted, false)
end

-- Pixel font pop label (floating "+12", rarity tags). Always >= 14px.
function Label.Pixel(props: LabelProps): TextLabel
	local p = table.clone(props)
	p.TextSize = math.max(14, p.TextSize or 16)
	return base(p, Theme.Font.Pixel, 16, Theme.Color.White, true)
end

-- Estimated text width in px for layout decisions when TextBounds is not yet available.
function Label.EstimateWidth(text: string, textSize: number, font: Enum.Font?): number
	local k = if font == Theme.Font.Display then 0.56 elseif font == Theme.Font.Pixel then 1.0 else 0.6
	return #text * textSize * k
end

return Label
