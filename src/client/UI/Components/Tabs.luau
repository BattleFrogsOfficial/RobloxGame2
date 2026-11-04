--!strict
-- Horizontal tab strip. Items = { { Id, Text, Icon? } }. The selected tab is the warm Header gradient, the rest
-- dark charcoal; all text is outlined display type.
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Button = require(script.Parent:WaitForChild("Button"))

local Tabs = {}

export type TabItem = { Id: string, Text: string?, Icon: string? }
export type TabsProps = {
	Items: { TabItem },
	Selected: string?,
	OnSelect: (id: string) -> (),
	Parent: Instance?,
	Height: number?,
	Size: UDim2?,
	LayoutOrder: number?,
	ZIndex: number?,
	Scrollable: boolean?, -- horizontal scrolling strip for many tabs (zones)
}

export type TabsHandle = {
	Root: GuiObject,
	Select: (self: TabsHandle, id: string) -> (),
	Selected: () -> string?,
}

function Tabs.new(props: TabsProps): TabsHandle
	local h = props.Height or 44
	local root: GuiObject
	if props.Scrollable then
		root = Make("ScrollingFrame", {
			Name = "Tabs",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = props.Size or UDim2.new(1, 0, 0, h + 8),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Theme.Color.Ink,
			LayoutOrder = props.LayoutOrder or 0,
			ZIndex = props.ZIndex or 53,
		})
	else
		root = Make("Frame", {
			Name = "Tabs",
			BackgroundTransparency = 1,
			Size = props.Size or UDim2.new(1, 0, 0, h),
			LayoutOrder = props.LayoutOrder or 0,
			ZIndex = props.ZIndex or 53,
		})
	end
	Decor.List(root, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local buttons: { [string]: Button.ButtonHandle } = {}
	local selected: string? = props.Selected or (props.Items[1] and props.Items[1].Id)
	local handle = { Root = root } :: any
	local function paint()
		for id, b in buttons do
			b:SetPalette(if id == selected then "Header" else "Dark")
		end
	end
	function handle.Select(_, id: string)
		if not buttons[id] then
			return
		end
		selected = id
		paint()
		props.OnSelect(id)
	end
	function handle.Selected(): string?
		return selected
	end
	for i, item in props.Items do
		local text = item.Text
		local width = if text then math.max(88, 28 + #text * 11 + (if item.Icon then 36 else 0)) else h
		buttons[item.Id] = Button.new({
			Name = "Tab_" .. item.Id,
			Text = text,
			Icon = item.Icon,
			IconSize = 32,
			Palette = "Dark",
			TextSize = Theme.Text.Body,
			Size = UDim2.fromOffset(width, h),
			LayoutOrder = i,
			Shadow = false,
			ZIndex = root.ZIndex + 1,
			Parent = root,
			OnClick = function()
				handle:Select(item.Id)
			end,
		})
	end
	paint()
	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: TabsHandle
end

return Tabs
