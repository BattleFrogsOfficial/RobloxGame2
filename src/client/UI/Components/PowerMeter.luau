--!strict
-- Vertical throw power meter: a ProgressBar (Vertical) with 0/25/50/75/100 ticks on the left and the live
-- value riding the fill on the right. The look sells power: empty is thin, dim and desaturated; full is
-- thick, bright and glowing (outer glow frame + stroke + gradient) and pulses when it enters the Perfect band.
--   local m = PowerMeter.new({ Length = 190, Parent = cluster, Position = ..., AnchorPoint = ... })
--   m:SetFraction(0.73)   -- every frame while charging
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Label = require(script.Parent:WaitForChild("Label"))
local ProgressBar = require(script.Parent:WaitForChild("ProgressBar"))

local PowerMeter = {}

export type MeterProps = {
	Length: number?, -- bar length in canvas px (default 190)
	MinThickness: number?, -- width when empty (default 10)
	MaxThickness: number?, -- width when full (default 30)
	Ticks: { number }?, -- tick values 0..100 (default 0/25/50/75/100)
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	Parent: Instance?,
	Name: string?,
}

export type MeterHandle = {
	Root: Frame,
	Bar: ProgressBar.BarHandle,
	Glow: Frame,
	Value: TextLabel,
	Fraction: number,
	SetFraction: (self: MeterHandle, f: number) -> (),
}

local GLOW_MAX = 8
local TICK_W = 36
local VALUE_W = 56
local PAD_Y = 16

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Colour ramp: lime, desaturated and dark when empty -> saturated, bright gold when full.
local function rampColors(f: number): (Color3, Color3)
	local hue = lerp(0.21, 0.13, f)
	local sat = lerp(0.18, 0.95, f)
	local val = lerp(0.52, 1, f)
	return Color3.fromHSV(hue, sat * 0.75, math.min(1, val * 1.04)), Color3.fromHSV(hue - 0.02, sat, val * 0.8)
end

function PowerMeter.new(props: MeterProps): MeterHandle
	local length = props.Length or 190
	local minT = props.MinThickness or 10
	local maxT = props.MaxThickness or 30
	local z = props.ZIndex or 3
	local half = maxT / 2 + GLOW_MAX
	local width = 2 * (half + 8 + math.max(TICK_W, VALUE_W))
	local height = length + 2 * PAD_Y
	local barTop = PAD_Y

	local root: Frame = Make("Frame", {
		Name = props.Name or "PowerMeter",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		ZIndex = z,
	})

	-- Glow sits behind the bar and grows with the fill.
	local glow: Frame = Make("Frame", {
		Name = "Glow",
		BackgroundColor3 = Theme.Palette.Cash.Top,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(minT, length),
		Position = UDim2.fromOffset(width / 2, barTop + length / 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z,
		Parent = root,
	})
	Decor.Corner(glow, Theme.Radius.Pill)
	local glowGradient = Decor.Gradient(glow, Theme.Palette.Cash.Top, Theme.Palette.Cash.Bottom)
	local glowStroke = Decor.Stroke(glow, 0, Theme.Palette.Cash.Top)
	glowStroke.Transparency = 1

	local bar = ProgressBar.new({
		Name = "Bar",
		Vertical = true,
		Palette = "Tennis",
		Size = UDim2.fromOffset(minT, length),
		Position = UDim2.fromOffset(width / 2, barTop + length / 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 1,
		Parent = root,
	})
	bar.Root.BackgroundColor3 = Theme.Color.InkSoft
	bar.Root.BackgroundTransparency = 0.25
	bar.Band.BackgroundTransparency = 0.55
	bar:SetBand(Game.Meter.GoodMin, 1, Theme.Palette.Cash.Bottom)
	bar:SetMarker(Game.Meter.PerfectMin)
	bar.Stroke.Thickness = 2

	-- Ticks: label + a short mark, left of the bar.
	for _, v in props.Ticks or { 0, 25, 50, 75, 100 } do
		local y = barTop + length * (1 - v / 100)
		Make("Frame", {
			Name = "Mark_" .. v,
			BackgroundColor3 = Theme.Color.White,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(6, 2),
			Position = UDim2.fromOffset(width / 2 - maxT / 2 - 4, y),
			AnchorPoint = Vector2.new(1, 0.5),
			ZIndex = z + 2,
			Parent = root,
		})
		Label.Display({
			Name = "Tick_" .. v,
			Text = tostring(v),
			TextSize = Theme.Text.Caption,
			Size = UDim2.fromOffset(TICK_W, 16),
			Position = UDim2.fromOffset(width / 2 - maxT / 2 - 14, y),
			AnchorPoint = Vector2.new(1, 0.5),
			XAlign = Enum.TextXAlignment.Right,
			ZIndex = z + 2,
			Parent = root,
		})
	end

	-- Live value rides the top of the fill.
	local value = Label.Display({
		Name = "Value",
		Text = "0",
		TextSize = Theme.Text.H2,
		Size = UDim2.fromOffset(VALUE_W, 28),
		Position = UDim2.fromOffset(width / 2 + maxT / 2 + 10, barTop + length),
		AnchorPoint = Vector2.new(0, 0.5),
		XAlign = Enum.TextXAlignment.Left,
		ZIndex = z + 3,
		Parent = root,
	})

	local handle = { Root = root, Bar = bar, Glow = glow, Value = value, Fraction = 0 } :: any
	local wasPerfect = false
	function handle.SetFraction(self: MeterHandle, f: number)
		local c = math.clamp(f, 0, 1)
		self.Fraction = c
		local eased = c * c -- power builds late: most of the width and glow arrive near the top
		local thick = lerp(minT, maxT, c)
		bar.Root.Size = UDim2.fromOffset(thick, length)
		bar:SetFraction(c)
		local top, bottom = rampColors(c)
		bar:SetColors(top, bottom)
		bar.Stroke.Thickness = lerp(2, 3, c)
		bar.Root.BackgroundTransparency = lerp(0.35, 0.15, c)

		local pad = GLOW_MAX * eased
		glow.Size = UDim2.fromOffset(thick + 2 * pad, length + 2 * pad)
		glow.BackgroundTransparency = lerp(1, 0.45, eased)
		glowGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(1, bottom) })
		glowStroke.Color = top
		glowStroke.Thickness = lerp(0, 5, eased)
		glowStroke.Transparency = lerp(1, 0.35, eased)

		local pct = math.floor(c * 100 + 0.5)
		value.Text = tostring(pct)
		value.Position = UDim2.fromOffset(width / 2 + maxT / 2 + 10, barTop + length * (1 - c))
		value.TextColor3 = if c >= Game.Meter.PerfectMin then Theme.Palette.Cash.Top else Theme.Color.White

		local perfect = c >= Game.Meter.PerfectMin
		if perfect and not wasPerfect then
			Motion.Pulse(bar.Root, 1.08)
			Motion.Pulse(value, 1.15)
		end
		wasPerfect = perfect
	end
	handle:SetFraction(0)
	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: MeterHandle
end

return PowerMeter
