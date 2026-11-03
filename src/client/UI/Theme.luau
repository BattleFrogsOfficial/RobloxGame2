--!strict
-- One theme for the whole HUD: colours, fonts, corner radius, stroke, spacing. Cartoony + chunky.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Rarities"))

local Theme = {}

Theme.Font = {
	Title = Enum.Font.FredokaOne, -- headings, numbers, buttons
	Body = Enum.Font.GothamBold, -- small text
	Light = Enum.Font.GothamMedium,
}

Theme.Color = {
	Panel = Color3.fromRGB(38, 34, 60), -- dark plum panels
	PanelLight = Color3.fromRGB(56, 50, 86),
	PanelInset = Color3.fromRGB(28, 25, 46),
	Stroke = Color3.fromRGB(16, 13, 28),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(190, 185, 215),
	TextDark = Color3.fromRGB(30, 26, 40),
	Cash = Color3.fromRGB(110, 230, 110),
	Bones = Color3.fromRGB(245, 235, 205),
	Accent = Color3.fromRGB(255, 200, 60), -- primary call to action (yellow)
	Good = Color3.fromRGB(90, 210, 110),
	Bad = Color3.fromRGB(235, 80, 80),
	Info = Color3.fromRGB(80, 170, 255),
	Purple = Color3.fromRGB(160, 100, 240),
	Backdrop = Color3.fromRGB(0, 0, 0),
	MeterTrack = Color3.fromRGB(28, 25, 46),
	MeterOk = Color3.fromRGB(120, 120, 160),
	MeterGood = Color3.fromRGB(110, 220, 120),
	MeterPerfect = Color3.fromRGB(255, 205, 60),
	Needle = Color3.fromRGB(255, 255, 255),
}

Theme.Corner = 12 -- px at UI scale 1
Theme.CornerSmall = 8
Theme.StrokeThickness = 3
Theme.Spacing = { XS = 4, S = 6, M = 10, L = 16 }
Theme.BackdropTransparency = 0.45
Theme.TextMax = { Title = 36, Big = 28, Normal = 20, Small = 15, Tiny = 12 }
Theme.TextMin = 9

function Theme.Rarity(rarity: string?): Color3
	local t = rarity and (Rarities.Tiers :: any)[rarity]
	return if t then t.Color else Theme.Color.Text
end

function Theme.Lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

function Theme.Darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

return Theme
