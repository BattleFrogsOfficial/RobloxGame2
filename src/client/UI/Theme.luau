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

-- Dark-body palette (style guide section 4): panels have a near-black body, a warm header and saturated cards.
-- "Paper" tokens kept their names (older screens use them) but now mean the dark body surfaces; text on them is light.
Theme.Color = {
	Ink = rgb("#14131B"), -- outlines, text strokes, dividers
	InkSoft = rgb("#24232E"),
	Body = rgb("#22212B"), -- panel body
	BodyDeep = rgb("#18171F"), -- wells, slot backgrounds, scroll areas
	BodyRaised = rgb("#302F3C"), -- section boxes, rows
	Paper = rgb("#302F3C"),
	PaperShade = rgb("#2A2934"),
	PaperDeep = rgb("#302F3C"),
	TextOnPaper = rgb("#F7F5FF"), -- body copy on the dark body
	TextMuted = rgb("#B4B1C6"),
	White = Color3.new(1, 1, 1),
	Scrim = rgb("#0B0A12"),
	Track = rgb("#4A4858"),
	Strip = rgb("#000000"), -- the translucent stat strip on item cards (with Theme.StripTransparency)
	SlotSelected = Color3.new(1, 1, 1),
	Strength = rgb("#4FC3FF"), -- the strength number next to the flexed arm
}
Theme.StripTransparency = 0.55

-- Palettes: two-stop vertical gradients, light on top. Text on them is always white with an Ink stroke.
export type Palette = { Top: Color3, Bottom: Color3, Text: Color3 }
Theme.Palette = {
	Sky = { Top = rgb("#5CCBFF"), Bottom = rgb("#1F7FE6"), Text = Color3.new(1, 1, 1) },
	Grass = { Top = rgb("#8CEB4C"), Bottom = rgb("#36A12C"), Text = Color3.new(1, 1, 1) },
	Tennis = { Top = rgb("#EBFF52"), Bottom = rgb("#AECC00"), Text = Color3.new(1, 1, 1) },
	Cash = { Top = rgb("#FFE25C"), Bottom = rgb("#FF9A0A"), Text = Color3.new(1, 1, 1) },
	Header = { Top = rgb("#FFD15A"), Bottom = rgb("#FF8C1A"), Text = Color3.new(1, 1, 1) }, -- every panel header
	Bone = { Top = rgb("#F6F1E6"), Bottom = rgb("#C9C0AE"), Text = Color3.new(1, 1, 1) },
	Danger = { Top = rgb("#FF5C52"), Bottom = rgb("#C81E1E"), Text = Color3.new(1, 1, 1) },
	Paper = { Top = rgb("#33323F"), Bottom = rgb("#272632"), Text = Color3.new(1, 1, 1) },
	Slate = { Top = rgb("#9C9AAA"), Bottom = rgb("#5E5C6C"), Text = Color3.new(1, 1, 1) }, -- grey: cash prices, Equipped
	Dark = { Top = rgb("#3A3947"), Bottom = rgb("#24232E"), Text = Color3.new(1, 1, 1) }, -- unselected tabs, chips
	Purple = { Top = rgb("#C16BFF"), Bottom = rgb("#7B2FE0"), Text = Color3.new(1, 1, 1) },
	Robux = { Top = rgb("#C16BFF"), Bottom = rgb("#7B2FE0"), Text = Color3.new(1, 1, 1) }, -- Robux buttons are purple
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

-- Reveal card stage (Components/DogViewport): the 3D pedestal materials and the ViewportFrame lighting.
-- Rarity tints are mixed in at runtime from Theme.RarityColor; these are the neutral bases.
Theme.Stage = {
	Stone = rgb("#9E9A92"), -- Common..Epic pedestal disc (Slate)
	StoneDark = rgb("#706C66"), -- Common pedestal base step
	Gold = rgb("#FFC43C"), -- Legendary pedestal disc (Foil)
	GoldDeep = rgb("#CD8C1E"), -- Legendary base step (Metal)
	GoldGlow = rgb("#FFE282"), -- Legendary Neon glow ring
	Night = rgb("#2E2C3C"), -- missed: dark pedestal + stage backdrop top
	PipOff = rgb("#5A5864"), -- unlit rarity pip (star) tint
	Ambient = rgb("#96969C"), -- caught: ViewportFrame.Ambient (x rarity 30 %)
	AmbientCommon = rgb("#A5A5AA"), -- Common: plain studio light
	LightCommon = rgb("#F0ECE4"),
	AmbientMissed = rgb("#808298"), -- missed: cold, dim, from behind the camera's left
	LightMissed = rgb("#BEC0DC"),
}

Theme.Font = {
	Display = Enum.Font.FredokaOne, -- titles, names, prices, numbers, buttons: always with a heavy Ink stroke
	Shout = Enum.Font.LuckiestGuy, -- the loudest callouts only: TAP TO THROW!, the meter value, the strength number
	Body = Enum.Font.GothamBold, -- the rare paragraph (odds notes); light on the dark body, no stroke
	BodyBold = Enum.Font.GothamBlack,
	Pixel = Enum.Font.Arcade, -- legacy; not used by the overhauled screens
}

Theme.Text = { Title = 36, H1 = 32, H2 = 24, Button = 20, Currency = 24, Body = 16, Caption = 14, Min = 10 }

Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32, Edge = 16 }

Theme.Radius = { Panel = 14, Button = 8, Card = 8, Pill = 999, Slot = 6 }

Theme.Stroke = { Panel = 4, Button = 3, Card = 3, Text = 2, Thin = 2 }

-- Display text stroke grows with the type size: 2 px up to 16, 3 px to 28, 4 px above (canvas px).
function Theme.TextStrokeFor(size: number): number
	return if size >= 30 then 4 elseif size >= 18 then 3 else 2
end

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

Theme.Modal = { MaxWidth = 900, MaxHeight = 560, WidthFrac = 0.92, HeightFrac = 0.93, ScrimTransparency = 0.55 }

-- Official Robux glyph (the only non-pixel icon allowed; Roblox requires the official mark for prices).
Theme.RobuxImage = "rbxasset://textures/ui/common/robux.png"

return Theme
