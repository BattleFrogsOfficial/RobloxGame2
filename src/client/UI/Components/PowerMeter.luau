--!strict
-- The throw bar (style guide section 2, "Throw bar"): a tall rounded capsule with a heavy Ink outline, filled
-- with a gradient from green at the TOP through yellow and orange to red at the BOTTOM, split into 5 segments by
-- Ink dividers, and a white pill marker (Ink outline) that rides up and down. Top = full power = Perfect (matches
-- Util/Meter: position 1 = top). The live value 0-100 rides next to the marker in the outlined Shout font.
--   local m = PowerMeter.new({ Length = 230, Parent = cluster, Position = ..., AnchorPoint = ... })
--   m:SetFraction(0.73)   -- every frame while the sweep runs
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Label = require(script.Parent:WaitForChild("Label"))

local PowerMeter = {}

export type MeterProps = {
	Length: number?, -- capsule height in canvas px (default 230)
	Thickness: number?, -- capsule width (default 56)
	Segments: number?, -- default 5
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	Parent: Instance?,
	Name: string?,
}

export type MeterHandle = {
	Root: Frame,
	Capsule: Frame,
	Marker: Frame,
	Value: TextLabel,
	Fraction: number,
	Width: number,
	Height: number,
	SetFraction: (self: MeterHandle, f: number) -> (),
}

-- Gradient stops, top -> bottom (UIGradient Rotation 90 runs top to bottom).
PowerMeter.Colors = {
	{ 0.0, Color3.fromRGB(92, 232, 84) }, -- green (Perfect)
	{ 0.32, Color3.fromRGB(196, 240, 70) },
	{ 0.55, Color3.fromRGB(255, 214, 58) }, -- yellow
	{ 0.78, Color3.fromRGB(255, 140, 40) }, -- orange
	{ 1.0, Color3.fromRGB(240, 64, 52) }, -- red
}

local MARKER_OVER = 14 -- the marker sticks out this far on each side
local MARKER_H = 18
local VALUE_W = 72

function PowerMeter.new(props: MeterProps): MeterHandle
	local length = props.Length or 230
	local thick = props.Thickness or 56
	local segments = props.Segments or 5
	local z = props.ZIndex or 3
	local width = thick + 2 * (MARKER_OVER + VALUE_W)
	local height = length + MARKER_H

	local root: Frame = Make("Frame", {
		Name = props.Name or "PowerMeter",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		ZIndex = z,
	})

	local capsule: Frame = Make("Frame", {
		Name = "Capsule",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(thick, length),
		Position = UDim2.new(0.5, 0, 0, MARKER_H / 2),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = z,
		Parent = root,
	})
	Decor.Corner(capsule, math.floor(thick / 2))
	Decor.Stroke(capsule, 5)
	local kps = {}
	for _, c in PowerMeter.Colors do
		table.insert(kps, ColorSequenceKeypoint.new(c[1], c[2]))
	end
	Make("UIGradient", { Color = ColorSequence.new(kps), Rotation = 90, Parent = capsule })
	-- vertical gloss stripe down the left of the capsule (the toy plastic shine)
	local gloss: Frame = Make("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Size = UDim2.new(0, math.max(6, math.floor(thick * 0.16)), 1, -thick),
		Position = UDim2.new(0, math.floor(thick * 0.2), 0, thick / 2),
		ZIndex = z + 1,
		Parent = capsule,
	})
	Decor.Corner(gloss, 999)
	-- segment dividers (Ink lines across the capsule)
	for i = 1, segments - 1 do
		Make("Frame", {
			Name = "Divider" .. i,
			BackgroundColor3 = Theme.Color.Ink,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 5),
			Position = UDim2.new(0, 0, i / segments, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = z + 2,
			Parent = capsule,
		})
	end

	-- the marker: a white pill wider than the capsule
	local marker: Frame = Make("Frame", {
		Name = "Marker",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(thick + 2 * MARKER_OVER, MARKER_H),
		Position = UDim2.new(0.5, 0, 0, height - MARKER_H / 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z + 4,
		Parent = root,
	})
	Decor.Corner(marker, 999)
	Decor.Stroke(marker, 4)
	Decor.Shadow(marker, "Hard")
	Make("Frame", {
		Name = "Shine",
		BackgroundColor3 = Theme.Color.Track,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -12, 0, 4),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = z + 5,
		Parent = marker,
	})
	local value = Label.Shout({
		Name = "Value",
		Text = "0",
		TextSize = 30,
		Size = UDim2.fromOffset(VALUE_W, 36),
		Position = UDim2.new(0.5, thick / 2 + MARKER_OVER + 8, 0, height - MARKER_H / 2),
		AnchorPoint = Vector2.new(0, 0.5),
		XAlign = Enum.TextXAlignment.Left,
		ZIndex = z + 4,
		Parent = root,
	})

	local handle = { Root = root, Capsule = capsule, Marker = marker, Value = value, Fraction = 0, Width = width, Height = height } :: any
	local wasPerfect = false
	function handle.SetFraction(_, f: number)
		local c = math.clamp(f, 0, 1)
		handle.Fraction = c
		local y = MARKER_H / 2 + (1 - c) * length
		marker.Position = UDim2.new(0.5, 0, 0, y)
		value.Position = UDim2.new(0.5, thick / 2 + MARKER_OVER + 8, 0, y)
		value.Text = tostring(math.floor(c * 100 + 0.5))
		local perfect = c >= Game.Meter.PerfectMin
		value.TextColor3 = if perfect then PowerMeter.Colors[1][2] else Theme.Color.White
		if perfect and not wasPerfect then
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
