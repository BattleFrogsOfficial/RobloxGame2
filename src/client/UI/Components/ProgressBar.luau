--!strict
-- Rounded progress bar with a centred caption. ProgressBar.new(parent, color) -> { Frame, Set(fraction, text?) }
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Create = require(script.Parent:WaitForChild("Create"))

local ProgressBar = {}

export type Bar = { Frame: Frame, Fill: Frame, Label: TextLabel, Set: (fraction: number, text: string?) -> () }

function ProgressBar.new(parent: Instance?, color: Color3?, props: { [string]: any }?): Bar
	local base: { [string]: any } = { Name = "ProgressBar", BackgroundColor3 = Theme.Color.PanelInset, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18) }
	for k, v in props or {} do
		base[k] = v
	end
	local frame = Create.New("Frame", base, { Create.Corner(Theme.CornerSmall), Create.Stroke(nil, 2) })
	local fill = Create.New("Frame", { Name = "Fill", BackgroundColor3 = color or Theme.Color.Good, BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1), Parent = frame }, { Create.Corner(Theme.CornerSmall) })
	local label = Create.Label({ Name = "Caption", Text = "", Font = Theme.Font.Body, TextStrokeTransparency = 0.4, ZIndex = 2,
		Size = UDim2.fromScale(1, 1), Parent = frame }, Theme.TextMax.Small)
	if parent then
		frame.Parent = parent
	end
	return {
		Frame = frame,
		Fill = fill,
		Label = label,
		Set = function(fraction: number, text: string?)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			fill.Visible = fraction > 0.001
			if text then
				label.Text = text
			end
		end,
	}
end

return ProgressBar
