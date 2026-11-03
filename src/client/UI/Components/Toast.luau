--!strict
-- Toast stack under the event banner. Max 3, newest at the bottom, 3.5 s each.
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent.Parent:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Icon = require(script.Parent:WaitForChild("Icon"))
local Label = require(script.Parent:WaitForChild("Label"))

local Toast = {}

export type ToastHandle = {
	Root: Frame,
	Show: (self: ToastHandle, text: string, icon: string?, palette: string?, seconds: number?) -> (),
}

Toast.Max = 3
Toast.Seconds = 3.5
Toast.Width = 360
Toast.Height = 44

function Toast.new(parent: Instance, position: UDim2, anchor: Vector2, max: number?, compact: boolean?): ToastHandle
	local maxLive = max or Toast.Max
	local height = if compact then 38 else Toast.Height
	local gap = if compact then 6 else Theme.Space.S
	local root: Frame = Make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Toast.Width, (height + gap) * maxLive),
		Position = position,
		AnchorPoint = anchor,
		ZIndex = 40,
		Parent = parent,
	})
	Decor.List(root, Enum.FillDirection.Vertical, gap, Enum.HorizontalAlignment.Center)
	local live: { Frame } = {}
	local counter = 0
	local handle = { Root = root } :: any
	function handle.Show(_, text: string, icon: string?, palette: string?, seconds: number?)
		counter += 1
		if #live >= maxLive then
			local old = table.remove(live, 1)
			if old then
				old:Destroy()
			end
		end
		local p = Theme.Palette[palette or "Slate"] or Theme.Palette.Slate
		local f: Frame = Make("Frame", {
			Name = "Toast",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = counter,
			ZIndex = 41,
			Parent = root,
		})
		Decor.Corner(f, Theme.Radius.Button)
		Decor.Stroke(f, Theme.Stroke.Panel)
		Decor.PaletteGradient(f, p)
		local textX = Theme.Space.M
		if icon then
			local iconPx = if compact then 16 else 32
			Icon.new({ Name = icon, Size = iconPx, Position = UDim2.new(0, Theme.Space.S, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 42, Parent = f })
			textX = Theme.Space.S + iconPx + Theme.Space.S
		end
		Label.Display({
			Text = text,
			TextSize = Theme.Text.Caption,
			Color = p.Text,
			Size = UDim2.new(1, -(textX + Theme.Space.M), 1, -4),
			Position = UDim2.fromOffset(textX, 2),
			Wrap = true,
			ZIndex = 42,
			Parent = f,
		})
		table.insert(live, f)
		Motion.PanelOpen(f)
		task.delay(seconds or Toast.Seconds, function()
			local i = table.find(live, f)
			if i then
				table.remove(live, i)
			end
			if f.Parent then
				Motion.PanelClose(f, function()
					f:Destroy()
				end)
			end
		end)
	end
	return handle :: ToastHandle
end

return Toast
