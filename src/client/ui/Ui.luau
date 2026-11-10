-- Small UI toolkit in the game's chunky cartoon style: gradient buttons with
-- thick black outlines, Fredoka font, green-header windows.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Voxel = require(Shared.Voxel)
local Viewport = require(script.Parent.Viewport)

local Ui = {}

Ui.Font = Enum.Font.FredokaOne
Ui.Colors = {
	Blue = Color3.fromRGB(70, 195, 235),
	Brown = Color3.fromRGB(190, 155, 95),
	Orange = Color3.fromRGB(240, 110, 45),
	Green = Color3.fromRGB(95, 215, 75),
	Red = Color3.fromRGB(225, 60, 55),
	Purple = Color3.fromRGB(175, 95, 240),
	Yellow = Color3.fromRGB(255, 205, 55),
	Pink = Color3.fromRGB(250, 110, 190),
	Teal = Color3.fromRGB(40, 200, 190),
	Dark = Color3.fromRGB(38, 40, 48),
	Darker = Color3.fromRGB(26, 27, 33),
	Cash = Color3.fromRGB(120, 255, 90),
	White = Color3.new(1, 1, 1),
}

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent
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

function Ui.corner(parent: Instance, radius: number?)
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
end

function Ui.stroke(parent: Instance, thickness: number?, color: Color3?)
	return Ui.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Color3.fromRGB(15, 15, 20),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Ui.gradient(parent: Instance, color: Color3)
	return Ui.new("UIGradient", {
		Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.15)),
		Rotation = 90,
		Parent = parent,
	})
end

-- Text with a dark outline, scaled to fit.
function Ui.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Ui.Font,
		TextScaled = true,
		TextColor3 = Ui.Colors.White,
		TextStrokeTransparency = 1,
	}
	for k, v in props do
		if k ~= "StrokeThickness" then
			defaults[k] = v
		end
	end
	local label = Ui.new("TextLabel", defaults)
	Ui.new("UIStroke", { Thickness = props.StrokeThickness or 2, Color = Color3.fromRGB(15, 15, 20), Parent = label })
	return label
end

local clickSound: Sound
function Ui.click()
	if not clickSound then
		clickSound = Ui.new("Sound", { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Parent = SoundService })
	end
	clickSound:Play()
end

-- Chunky gradient button. Returns the TextButton (its label is .Label).
function Ui.button(props: { [string]: any }): TextButton
	local color = props.Color or Ui.Colors.Green
	local btn = Ui.new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(160, 50),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	Ui.corner(btn, props.Radius or 10)
	Ui.stroke(btn, props.Stroke or 3)
	local grad = Ui.gradient(btn, color)
	-- A soft shine stripe across the top half.
	local shine = Ui.new("Frame", {
		Visible = not props.NoShine,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		Size = UDim2.new(1, -8, 0.42, 0),
		Position = UDim2.fromOffset(4, 3),
		ZIndex = btn.ZIndex,
		Parent = btn,
	})
	Ui.corner(shine, 8)
	local label = Ui.text({
		Name = "Label",
		Text = props.Text or "",
		Size = props.Icon and UDim2.new(1, -8, 0.32, 0) or UDim2.new(1, -14, 0.78, 0),
		Position = props.Icon and UDim2.new(0.5, 0, 1, -4) or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.Icon and Vector2.new(0.5, 1) or Vector2.new(0.5, 0.5),
		ZIndex = btn.ZIndex + 1,
		StrokeThickness = props.TextStroke or 2.5,
		Parent = btn,
	})
	if props.Icon then
		local holder = Ui.new("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -10, 0.64, 0),
			Position = UDim2.new(0.5, 0, 0, 3),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = btn.ZIndex + 1,
			Parent = btn,
		})
		Ui.icon(holder, props.Icon)
	end
	local scale = Ui.new("UIScale", { Parent = btn })
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.05), { Scale = 0.94 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	if props.OnClick then
		btn.Activated:Connect(function()
			Ui.click()
			props.OnClick()
		end)
	end
	grad.Name = "Gradient"
	label.Name = "Label"
	return btn
end

-- Recolor a button made by Ui.button.
function Ui.setButtonColor(btn: GuiObject, c: Color3)
	local grad = btn:FindFirstChild("Gradient") :: UIGradient?
	if grad then
		grad.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.25), c:Lerp(Color3.new(0, 0, 0), 0.15))
	end
end

-- Set the text of a button made by Ui.button.
function Ui.setButtonText(btn: GuiObject, text: string)
	local label = btn:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = text
	end
end

-- A square tile button in the HUD style: the 3D icon is bigger than the
-- frame and spills out of its top, the label sits along the bottom, and an
-- optional tag ribbon ("NEW!", "FREE!") hangs off the top-right corner.
function Ui.tile(props: { [string]: any }): TextButton
	local color = props.Color or Ui.Colors.Blue
	local btn = Ui.new("TextButton", {
		Name = props.Name or "Tile",
		Size = props.Size or UDim2.fromOffset(88, 88),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	Ui.corner(btn, 10)
	Ui.stroke(btn, 4)
	local grad = Ui.gradient(btn, color)
	grad.Name = "Gradient"
	-- Inner darker panel, so the icon sits in a recessed frame.
	local inner = Ui.new("Frame", {
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.45),
		BackgroundTransparency = 0.35,
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		ZIndex = btn.ZIndex,
		Parent = btn,
	})
	Ui.corner(inner, 6)
	local holder = Ui.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(1.12, 1.0),
		ZIndex = btn.ZIndex + 1,
		Parent = btn,
	})
	Ui.icon(holder, props.Icon, { ZIndex = btn.ZIndex + 1 })
	local label = Ui.text({
		Name = "Label",
		Text = props.Text or "",
		Size = UDim2.new(1, -4, 0.3, 0),
		Position = UDim2.new(0.5, 0, 1, -3),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = btn.ZIndex + 2,
		StrokeThickness = 3,
		Parent = btn,
	})
	label.Name = "Label"
	if props.Tag then
		local tag = Ui.text({
			Name = "Tag",
			Text = props.Tag,
			Size = UDim2.fromScale(0.62, 0.24),
			Position = UDim2.new(1, 6, 0, -8),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = props.TagColor or Ui.Colors.Green,
			Rotation = 6,
			ZIndex = btn.ZIndex + 3,
			Parent = btn,
		})
		Ui.corner(tag, 5)
	end
	local scale = Ui.new("UIScale", { Parent = btn })
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.06 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.05), { Scale = 0.94 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	if props.OnClick then
		btn.Activated:Connect(function()
			Ui.click()
			props.OnClick()
		end)
	end
	return btn
end

-- A round red badge with a count or "!" in a button's top-left corner.
function Ui.countBadge(parent: GuiObject, text: string?): TextLabel
	local b = Ui.text({
		Name = "Badge",
		Text = text or "!",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(-10, -10),
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Colors.Red,
		ZIndex = 12,
		Visible = false,
		Parent = parent,
	})
	Ui.corner(b, 15)
	Ui.stroke(b, 3)
	return b
end

-- A picture made from a 3D model (see Voxel.icon), filling `parent`.
function Ui.icon(parent: Instance, name: string, props: { [string]: any }?): ViewportFrame
	return Viewport.show(parent, Voxel.icon(name), props)
end

-- A check mark drawn from two bars, centered in `parent`.
function Ui.check(parent: Instance, color: Color3?, zIndex: number?): Frame
	local holder = Ui.new("Frame", {
		Name = "Check",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = zIndex or 27,
		Parent = parent,
	})
	local c = color or Color3.fromRGB(120, 255, 120)
	for _, bar in { { 0.3, 0.62, 0.42, 45 }, { 0.6, 0.45, 0.78, -45 } } do
		local f = Ui.new("Frame", {
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(bar[1], bar[2]),
			Size = UDim2.fromScale(bar[3], 0.16),
			Rotation = bar[4],
			ZIndex = zIndex or 27,
			Parent = holder,
		})
		Ui.corner(f, 4)
		Ui.stroke(f, 2)
	end
	return holder
end

-- A red notification badge ("!" or a number) in a button's corner.
function Ui.badge(parent: GuiObject, text: string?): TextLabel
	local b = Ui.text({
		Name = "Badge",
		Text = text or "!",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -8, 0, -10),
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Colors.Red,
		ZIndex = 10,
		Visible = false,
		Parent = parent,
	})
	Ui.corner(b, 14)
	return b
end

----------------------------------------------------------------------------
-- Screens & windows
----------------------------------------------------------------------------
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

function Ui.screen(name: string, order: number?): ScreenGui
	local gui = Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order or 0,
		Parent = playerGui,
	})
	local scale = Ui.new("UIScale", { Parent = gui })
	local function fit()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.5, 1.2)
	end
	fit()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fit)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	return gui
end

local windows = {}
local openName: string? = nil

-- Big centered window with a colored header and a red X.
function Ui.window(gui: ScreenGui, name: string, title: string, color: Color3?, size: Vector2?, icon: string?)
	local sz = size or Vector2.new(760, 520)
	local frame = Ui.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(sz.X, sz.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Ui.Colors.Dark,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	Ui.corner(frame, 14)
	Ui.stroke(frame, 4)
	local header = Ui.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 21,
		Parent = frame,
	})
	Ui.corner(header, 14)
	Ui.stroke(header, 4)
	Ui.gradient(header, color or Ui.Colors.Green)
	if icon then
		local holder = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.fromOffset(12, 6),
			ZIndex = 22,
			Parent = header,
		})
		Ui.icon(holder, icon, { ZIndex = 22 })
	end
	Ui.text({
		Text = title,
		Size = UDim2.new(1, icon and -150 or -100, 0, 46),
		Position = UDim2.fromOffset(icon and 72 or 22, 9),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		StrokeThickness = 3,
		Parent = header,
	})
	local scaleObj = Ui.new("UIScale", { Parent = frame })
	local win = { frame = frame, name = name, body = nil :: Frame?, onOpen = nil, onClose = nil }
	Ui.button({
		Text = "X",
		Color = Ui.Colors.Red,
		Size = UDim2.fromOffset(52, 48),
		Position = UDim2.new(1, -62, 0, 8),
		ZIndex = 23,
		Parent = header,
		OnClick = function()
			Ui.close(name)
		end,
	})
	win.body = Ui.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 1, -84),
		Position = UDim2.fromOffset(14, 74),
		ZIndex = 21,
		Parent = frame,
	})
	win.pop = function()
		scaleObj.Scale = 0.85
		TweenService:Create(scaleObj, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	windows[name] = win
	return win
end

function Ui.open(name: string)
	if openName and openName ~= name then
		Ui.close(openName)
	end
	local w = windows[name]
	if not w then
		return
	end
	openName = name
	w.frame.Visible = true
	w.pop()
	if w.onOpen then
		w.onOpen()
	end
end

function Ui.close(name: string)
	local w = windows[name]
	if not w then
		return
	end
	w.frame.Visible = false
	if openName == name then
		openName = nil
	end
	if w.onClose then
		w.onClose()
	end
end

function Ui.toggle(name: string)
	if openName == name then
		Ui.close(name)
	else
		Ui.open(name)
	end
end

function Ui.isOpen(name: string): boolean
	return openName == name
end

-- Scrolling grid inside a window body.
function Ui.scrollGrid(parent: Instance, cellSize: Vector2, padding: number?): ScrollingFrame
	local sf = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = parent,
	})
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellSize.X, cellSize.Y),
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = sf,
	})
	Ui.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = sf })
	return sf
end

-- Dark card used in grids.
function Ui.card(parent: Instance, order: number?, color: Color3?): Frame
	local f = Ui.new("Frame", {
		BackgroundColor3 = color or Ui.Colors.Darker,
		LayoutOrder = order or 0,
		ZIndex = 22,
		Parent = parent,
	})
	Ui.corner(f, 10)
	Ui.stroke(f, 3)
	return f
end

return Ui
