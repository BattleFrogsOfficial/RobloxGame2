--!strict
-- Modal panel: scrim, centred paper surface, coloured header band with title, red close button, body frame.
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent.Parent:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Button = require(script.Parent:WaitForChild("Button"))
local Label = require(script.Parent:WaitForChild("Label"))
local Icon = require(script.Parent:WaitForChild("Icon"))

local Panel = {}

export type PanelProps = {
	Title: string,
	Icon: string?,
	Palette: string?, -- header band palette
	Parent: Instance,
	OnClose: (() -> ())?,
	Width: number?, -- max px, defaults Theme.Modal.MaxWidth
	Height: number?,
	Name: string?,
	Scrim: boolean?, -- default true
}

export type PanelHandle = {
	Root: Frame, -- the scrim (full screen) or the panel if Scrim = false
	Frame: Frame, -- the panel surface
	Header: Frame,
	Body: Frame,
	Title: TextLabel,
	Open: (self: PanelHandle) -> (),
	Close: (self: PanelHandle) -> (),
	IsOpen: (self: PanelHandle) -> boolean,
	Destroy: (self: PanelHandle) -> (),
}

Panel.HeaderHeight = 56

function Panel.new(props: PanelProps): PanelHandle
	local useScrim = props.Scrim ~= false
	local root: Frame = Make("Frame", {
		Name = props.Name or ("Panel_" .. props.Title),
		BackgroundColor3 = Theme.Color.Scrim,
		BackgroundTransparency = if useScrim then Theme.Modal.ScrimTransparency else 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 50,
	})
	-- Clicks on the scrim close the panel.
	if useScrim then
		Make("TextButton", {
			Name = "ScrimClick",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 50,
			Parent = root,
			Activated = function()
				if props.OnClose then
					props.OnClose()
				end
			end,
		})
	end

	local maxW = props.Width or Theme.Modal.MaxWidth
	local maxH = props.Height or Theme.Modal.MaxHeight
	local frame: Frame = Make("Frame", {
		Name = "Frame",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(Theme.Modal.WidthFrac, Theme.Modal.HeightFrac),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 51,
		Parent = root,
	})
	Make("UISizeConstraint", { MaxSize = Vector2.new(maxW, maxH), Parent = frame })
	Decor.Corner(frame, Theme.Radius.Panel)
	Decor.Stroke(frame, Theme.Stroke.Panel)
	Decor.PaletteGradient(frame, Theme.Palette.Paper)
	Decor.Shadow(frame, "Soft")

	local header: Frame = Make("Frame", {
		Name = "Header",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, Panel.HeaderHeight),
		ZIndex = 52,
		Parent = frame,
	})
	Decor.TopCorners(header, Theme.Radius.Panel)
	Decor.PaletteGradient(header, Theme.Palette[props.Palette or "Sky"] or Theme.Palette.Sky)
	-- Ink line under the header
	Make("Frame", {
		Name = "Rule",
		BackgroundColor3 = Theme.Color.Ink,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 53,
		Parent = header,
	})
	local titleX = Theme.Space.L
	if props.Icon then
		Icon.new({
			Name = props.Icon,
			Size = 32,
			Position = UDim2.new(0, Theme.Space.L, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 53,
			Parent = header,
		})
		titleX = Theme.Space.L + 32 + Theme.Space.S
	end
	local title = Label.Display({
		Name = "Title",
		Text = props.Title,
		TextSize = Theme.Text.H2,
		Size = UDim2.new(1, -(titleX + 60), 1, 0),
		Position = UDim2.new(0, titleX, 0, 0),
		ZIndex = 53,
		Parent = header,
	})

	local body: Frame = Make("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -Panel.HeaderHeight),
		Position = UDim2.new(0, 0, 0, Panel.HeaderHeight),
		ZIndex = 52,
		Parent = frame,
	})
	Decor.Padding(body, Theme.Space.L)

	Button.Close(frame, function()
		if props.OnClose then
			props.OnClose()
		end
	end)

	local handle = { Root = root, Frame = frame, Header = header, Body = body, Title = title } :: any
	function handle.Open()
		root.Visible = true
		Motion.PanelOpen(frame)
	end
	function handle.Close()
		Motion.PanelClose(frame, function()
			root.Visible = false
		end)
	end
	function handle.IsOpen(): boolean
		return root.Visible
	end
	function handle.Destroy()
		root:Destroy()
	end
	root.Parent = props.Parent
	return handle :: PanelHandle
end

-- A labelled section box inside a body: paper-deep background, small caption title.
function Panel.Section(parent: Instance, title: string, layoutOrder: number?): Frame
	local box: Frame = Make("Frame", {
		Name = "Section_" .. title,
		BackgroundColor3 = Theme.Color.PaperDeep,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 100),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder or 0,
		ZIndex = parent:IsA("GuiObject") and (parent :: GuiObject).ZIndex + 1 or 52,
		Parent = parent,
	})
	Decor.Corner(box, Theme.Radius.Card)
	Decor.Stroke(box, Theme.Stroke.Thin, Theme.Color.Track)
	Decor.Padding(box, Theme.Space.M)
	Decor.List(box, Enum.FillDirection.Vertical, Theme.Space.S)
	Label.Caption({ Text = string.upper(title), LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 16), ZIndex = box.ZIndex + 1, Parent = box, Font = Theme.Font.BodyBold })
	return box
end

return Panel
