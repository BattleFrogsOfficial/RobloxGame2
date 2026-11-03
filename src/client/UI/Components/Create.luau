--!strict
-- Small instance helpers every UI component uses (consistent corners, strokes, padding, text limits).
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local Create = {}

-- New("Frame", { Size = ..., Parent = ... }, { children }) ; Parent is applied last.
function Create.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Create.Corner(radius: number?): UICorner
	return Create.New("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) })
end

function Create.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Create.New("UIStroke", {
		Color = color or Theme.Color.Stroke,
		Thickness = thickness or Theme.StrokeThickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Create.Padding(all: number, horizontal: number?): UIPadding
	local hpad = horizontal or all
	return Create.New("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, hpad),
		PaddingRight = UDim.new(0, hpad),
	})
end

function Create.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?): UIListLayout
	return Create.New("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or Theme.Spacing.S),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Create.TextLimit(maxSize: number, minSize: number?): UITextSizeConstraint
	return Create.New("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = minSize or Theme.TextMin })
end

-- Text label with theme font, scaled text and a size cap.
function Create.Label(props: { [string]: any }, maxText: number?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font.Title,
		TextColor3 = Theme.Color.Text,
		TextScaled = true,
		TextWrapped = true,
		TextStrokeTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in props do
		base[k] = v
	end
	local l = Create.New("TextLabel", base)
	Create.TextLimit(maxText or Theme.TextMax.Normal).Parent = l
	return l
end

-- Rounded panel with the standard stroke.
function Create.Panel(props: { [string]: any }, children: { Instance }?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.Color.Panel,
		BorderSizePixel = 0,
	}
	for k, v in props do
		base[k] = v
	end
	local f = Create.New("Frame", base, children)
	Create.Corner().Parent = f
	Create.Stroke().Parent = f
	return f
end

return Create
