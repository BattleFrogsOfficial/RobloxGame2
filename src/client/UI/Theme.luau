--!strict
-- Design tokens for the whole client UI. docs/UI_STYLE_GUIDE.md is the explanation; this file is the law.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))

local Theme = {}

local function rgb(hex: string): Color3
	local n = tonumber(string.sub(hex, 2), 16) :: number
	return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

Theme.Canvas = Vector2.new(1280, 720)
Theme.ScaleMin, Theme.ScaleMax = 0.75, 1.4

Theme.Color = {
	Ink = rgb("#1B1A26"),
	InkSoft = rgb("#2B2A3A"),
	Paper = rgb("#FFFDF7"),
	PaperShade = rgb("#EDE8DC"),
	PaperDeep = rgb("#DED7C6"),
	TextOnPaper = rgb("#2B2A3A"),
	TextMuted = rgb("#6E6A80"),
	White = Color3.new(1, 1, 1),
	Scrim = rgb("#0B0A12"),
	Track = rgb("#CFC9BC"),
}

-- Palettes: two-stop vertical gradients, light on top. Text on them is always white with an Ink stroke.
export type Palette = { Top: Color3, Bottom: Color3, Text: Color3 }
Theme.Palette = {
	Sky = { Top = rgb("#4FB3FF"), Bottom = rgb("#2F7FE0"), Text = Color3.new(1, 1, 1) },
	Grass = { Top = rgb("#7ED957"), Bottom = rgb("#3FA34D"), Text = Color3.new(1, 1, 1) },
	Tennis = { Top = rgb("#E5FF3D"), Bottom = rgb("#B8D400"), Text = rgb("#2B2A3A") },
	Cash = { Top = rgb("#FFD54A"), Bottom = rgb("#F4A000"), Text = Color3.new(1, 1, 1) },
	Bone = { Top = rgb("#F3EFE6"), Bottom = rgb("#CFC7B8"), Text = rgb("#2B2A3A") },
	Danger = { Top = rgb("#FF5A5A"), Bottom = rgb("#D32F2F"), Text = Color3.new(1, 1, 1) },
	Paper = { Top = rgb("#FFFDF7"), Bottom = rgb("#EDE8DC"), Text = rgb("#2B2A3A") },
	Slate = { Top = rgb("#6E6A80"), Bottom = rgb("#4A4860"), Text = Color3.new(1, 1, 1) },
	Purple = { Top = rgb("#C77DFF"), Bottom = rgb("#8E3FD6"), Text = Color3.new(1, 1, 1) },
	Robux = { Top = rgb("#6AD47A"), Bottom = rgb("#2E9E4A"), Text = Color3.new(1, 1, 1) },
} :: { [string]: Palette }

-- Rarity colours come from the shared config and are never redefined.
function Theme.RarityColor(rarity: string?): Color3
	local tier = rarity and (Rarities.Tiers :: any)[rarity]
	return if tier then tier.Color else Theme.Color.Track
end

Theme.Variant = {
	Gold = rgb("#FFD24A"),
	Shadow = rgb("#2A1B3D"),
	Rainbow = rgb("#FF6AD5"), -- base; animated by the Icon/Card components
}

Theme.Font = {
	Display = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	BodyBold = Enum.Font.GothamBold,
	Pixel = Enum.Font.Arcade, -- used only for pop numbers and the rarity tag on the reveal card
}

Theme.Text = { H1 = 32, H2 = 24, Button = 20, Currency = 22, Body = 16, Caption = 14, Min = 10 }

Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32, Edge = 16 }

Theme.Radius = { Panel = 12, Button = 10, Card = 10, Pill = 999 }

Theme.Stroke = { Panel = 3, Button = 3, Text = 2, Thin = 1 }

Theme.Shadow = {
	Hard = { Blur = 0, Offset = Vector2.new(0, 4), Transparency = 0.65 },
	Soft = { Blur = 24, Offset = Vector2.new(0, 8), Transparency = 0.6 },
	MaxOnScreen = 60,
}

-- Regions nothing of ours may cover (px at canvas scale 1). See the style guide, section 2.
Theme.Reserved = {
	TopBar = 60,
	TouchLeft = Vector2.new(180, 180),
	TouchRight = Vector2.new(200, 200),
	TopRight = Vector2.new(260, 60),
}

Theme.Touch = { MinTarget = 44, SideButton = 56, ThrowButton = 96 }

Theme.Modal = { MaxWidth = 900, MaxHeight = 560, WidthFrac = 0.9, HeightFrac = 0.84, ScrimTransparency = 0.6 }

-- Official Robux glyph (the only non-pixel icon allowed; Roblox requires the official mark for prices).
Theme.RobuxImage = "rbxasset://textures/ui/common/robux.png"

return Theme
