--!strict
-- Item card in the shop style (style guide section 5): a tall card whose BACKGROUND is its rarity colour, the name
-- big at the top, the rarity word under it in a rarity-tinted outlined font, a big icon in the middle, a dark
-- translucent stat strip ("x1.25 Range  +10% Luck"), then a bottom row: a grey cash price button and a purple Robux
-- button (Robux mark + number). Equipped = one full-width grey button. A small badge (owned count "x3") sits in the
-- top-right corner of the art. Used by the Shop; Dogs and the Kennel Book reuse Card.Paint for their pooled cells.
--   Card.new({ Title, Rarity?, Tag?, Color?, Icon, IconRecolor?, Stat?, Badge?, Price?, PriceEnabled?, OnBuy?,
--              Robux?, OnRobux?, Action?, ActionPalette?, OnAction?, Size?, Parent?, LayoutOrder? })
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent.Parent:WaitForChild("Motion"))
local Decor = require(script.Parent:WaitForChild("Decor"))
local Icon = require(script.Parent:WaitForChild("Icon"))
local Label = require(script.Parent:WaitForChild("Label"))
local Button = require(script.Parent:WaitForChild("Button"))

local Card = {}

export type CardProps = {
	Title: string,
	Rarity: string?, -- background colour + the tag word (unless Tag / Color say otherwise)
	Tag: string?, -- the word under the name (default: the rarity)
	Color: Color3?, -- background colour for things without a rarity (boosts, upgrades)
	Subtitle: string?, -- legacy alias for Stat
	Stat: string?, -- the dark stat strip
	Icon: string?,
	IconRecolor: { [string]: Color3 }?,
	IconTint: Color3?,
	Badge: string?, -- top-right corner of the art ("x3")
	Variant: string?, -- variant badge (top-left of the art)
	Price: string?, -- cash button text; nil = no cash button
	PriceIcon: string?, -- icon before the price (bones for cosmetics); cash prices are plain text like "$150"
	PricePalette: string?, -- default Slate (grey)
	PriceEnabled: boolean?,
	OnBuy: (() -> ())?,
	Robux: (number | string)?, -- Robux button (purple, Robux mark + number, or "Soon")
	OnRobux: (() -> ())?,
	Action: string?, -- one full-width button instead of the price row ("Equipped", "Equip", "Owned")
	ActionPalette: string?,
	OnAction: (() -> ())?,
	Size: UDim2?,
	Parent: Instance?,
	LayoutOrder: number?,
	ZIndex: number?,
	OnClick: (() -> ())?,
	Owned: boolean?,
	Locked: boolean?,
	Silhouette: boolean?,
	Name: string?,
	Preview: Instance?,
}

export type CardHandle = {
	Root: Frame,
	Preview: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Buy: Button.ButtonHandle?,
	RobuxButton: Button.ButtonHandle?,
	SetPrice: (self: CardHandle, text: string?, enabled: boolean?) -> (),
	SetSubtitle: (self: CardHandle, text: string) -> (),
	SetSelected: (self: CardHandle, on: boolean) -> (),
}

Card.Width = 210
Card.DefaultSize = UDim2.new(0, Card.Width, 1, -8)
Card.MaxHeight = 350
local BUTTON_H = 44
local STRIP_H = 34
local PAD = 6
local TOP = 58 -- name + tag block

Card.ArtSize = 128

-- Draw the card art as big as the box allows (multiples of 16 px, at most Card.ArtSize), redrawing when the box
-- size changes (short phone cards get a smaller icon; pixels stay whole).
function Card.FitArt(box: GuiObject, make: (px: number) -> GuiObject)
	local current: GuiObject? = nil
	local currentPx = 0
	local function fit()
		local es = Decor.EffectiveScale(box)
		local w, h = box.AbsoluteSize.X / es, box.AbsoluteSize.Y / es
		local px = Card.ArtSize
		if w > 0 and h > 0 then
			px = math.clamp(math.floor(math.min(w, h) / 16) * 16, 32, Card.ArtSize)
		end
		if px ~= currentPx then
			if current then
				current:Destroy()
			end
			currentPx = px
			current = make(px)
		end
	end
	box:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

-- Paint a frame as a rarity card: gradient of the colour (lighter top), Ink outline, rounded corners.
function Card.Paint(frame: GuiObject, color: Color3): UIGradient
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = frame:FindFirstChildOfClass("UIGradient")
	local seq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Theme.Color.White, 0.28)),
		ColorSequenceKeypoint.new(1, color:Lerp(Theme.Color.Ink, 0.12)),
	})
	if g then
		g.Color = seq
		return g
	end
	return Make("UIGradient", { Color = seq, Rotation = 90, Parent = frame })
end

-- The rarity word colour on its own card: the tier hue pushed bright (Common stays near-white).
function Card.TagColor(color: Color3): Color3
	return color:Lerp(Theme.Color.White, 0.55)
end

-- Fit a name to the card: largest of the steps whose estimated width fits.
function Card.FitSize(text: string, width: number, steps: { number }): number
	for _, s in steps do
		if Label.EstimateWidth(text, s, Theme.Font.Display) * 1.08 <= width then
			return s
		end
	end
	return steps[#steps]
end

function Card.new(props: CardProps): CardHandle
	local size = props.Size or Card.DefaultSize
	local color = props.Color or Theme.RarityColor(props.Rarity)
	local root: Frame = Make("Frame", {
		Name = props.Name or ("Card_" .. props.Title),
		BorderSizePixel = 0,
		Size = size,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 53,
	})
	Make("UISizeConstraint", { MaxSize = Vector2.new(10000, Card.MaxHeight), Parent = root })
	Decor.Corner(root, Theme.Radius.Card)
	local outer = Decor.Stroke(root, Theme.Stroke.Card)
	Card.Paint(root, color)
	local z = root.ZIndex + 1
	local innerW = (if size.X.Scale == 0 then size.X.Offset else Card.Width) - PAD * 2

	local title = Label.Display({
		Name = "Title",
		Text = props.Title,
		TextSize = Card.FitSize(props.Title, innerW, { 22, 20, 18, 16 }),
		Size = UDim2.new(1, -PAD * 2, 0, 30),
		Position = UDim2.fromOffset(PAD, 6),
		XAlign = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = root,
	})
	local tagText = props.Tag or props.Rarity or ""
	local subtitle = Label.Display({
		Name = "Tag",
		Text = tagText,
		TextSize = 16,
		Color = Card.TagColor(color),
		Size = UDim2.new(1, -PAD * 2, 0, 22),
		Position = UDim2.fromOffset(PAD, 34),
		XAlign = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = root,
	})

	local bottomH = (if props.Price or props.Robux or props.Action then BUTTON_H + PAD else 0) + PAD
	local stat = props.Stat or props.Subtitle
	local stripH = if stat and stat ~= "" then STRIP_H + PAD else 0
	local preview: Frame = Make("Frame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -PAD * 2, 1, -(TOP + bottomH + stripH)),
		Position = UDim2.fromOffset(PAD, TOP),
		ZIndex = z,
		Parent = root,
	})
	if props.Preview then
		props.Preview.Parent = preview
	elseif props.Icon then
		-- the art is drawn as big as the space allows (128 px on desktop, smaller on short phone cards)
		Card.FitArt(preview, function(px)
			return Icon.new({
				Name = props.Icon :: string,
				Size = px,
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = z + 1,
				Recolor = props.IconRecolor,
				Tint = if props.Silhouette then Theme.Color.Ink else props.IconTint,
				Parent = preview,
			})
		end)
	end
	if props.Badge then
		local badge: Frame = Make("Frame", {
			Name = "Badge",
			BackgroundColor3 = Theme.Color.Ink,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.max(40, 18 + #props.Badge * 11), 28),
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = z + 2,
			Parent = preview,
		})
		Decor.Corner(badge, 6)
		Decor.Stroke(badge, 2, Card.TagColor(color))
		Label.Display({ Name = "Text", Text = props.Badge, TextSize = 18, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = z + 3, Parent = badge })
	end
	local variantIcon = Icon.ForVariant(props.Variant)
	if variantIcon then
		Icon.new({ Name = variantIcon, Size = 32, Position = UDim2.fromOffset(0, 0), ZIndex = z + 2, Parent = preview })
	end
	if props.Locked then
		Icon.new({ Name = "lock", Size = 32, Position = UDim2.fromOffset(0, 0), ZIndex = z + 2, Parent = preview })
	end

	local statLabel: TextLabel? = nil
	if stripH > 0 then
		local strip: Frame = Make("Frame", {
			Name = "Stat",
			BackgroundColor3 = Theme.Color.Strip,
			BackgroundTransparency = Theme.StripTransparency,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -PAD * 2, 0, STRIP_H),
			Position = UDim2.new(0, PAD, 1, -bottomH),
			AnchorPoint = Vector2.new(0, 1),
			ZIndex = z,
			Parent = root,
		})
		Decor.Corner(strip, 6)
		Decor.Stroke(strip, 2)
		statLabel = Label.Display({
			Name = "Text",
			Text = stat :: string,
			TextSize = Card.FitSize(stat :: string, innerW - 8, { 18, 16, 14 }),
			Size = UDim2.new(1, -8, 1, 0),
			Position = UDim2.fromOffset(4, 0),
			XAlign = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
			Parent = strip,
		})
	end

	local buy: Button.ButtonHandle? = nil
	local robux: Button.ButtonHandle? = nil
	local rowY = UDim2.new(0, PAD, 1, -PAD)
	if props.Action then
		buy = Button.new({
			Name = "Action",
			Text = props.Action,
			Palette = props.ActionPalette or "Slate",
			TextSize = 20,
			Size = UDim2.new(1, -PAD * 2, 0, BUTTON_H),
			Position = rowY,
			AnchorPoint = Vector2.new(0, 1),
			Shadow = false,
			ZIndex = z + 1,
			Parent = root,
			OnClick = props.OnAction,
		})
	elseif props.Price or props.Robux then
		local both = props.Price ~= nil and props.Robux ~= nil
		if props.Price then
			buy = Button.new({
				Name = "Buy",
				Text = props.Price,
				Icon = props.PriceIcon,
				IconSize = 32,
				Palette = props.PricePalette or "Slate",
				TextSize = if #props.Price > 6 then 18 else 20,
				Size = if both then UDim2.new(0.5, -PAD - 2, 0, BUTTON_H) else UDim2.new(1, -PAD * 2, 0, BUTTON_H),
				Position = rowY,
				AnchorPoint = Vector2.new(0, 1),
				Shadow = false,
				ZIndex = z + 1,
				Parent = root,
				OnClick = props.OnBuy,
			})
			if props.PriceEnabled == false then
				buy:SetEnabled(false)
			end
		end
		if props.Robux then
			robux = Button.new({
				Name = "Robux",
				Text = tostring(props.Robux),
				Icon = "robux",
				IconSize = 32,
				Palette = "Robux",
				TextSize = 20,
				Size = if both then UDim2.new(0.5, -PAD - 2, 0, BUTTON_H) else UDim2.new(1, -PAD * 2, 0, BUTTON_H),
				Position = UDim2.new(1, -PAD, 1, -PAD),
				AnchorPoint = Vector2.new(1, 1),
				Shadow = false,
				ZIndex = z + 1,
				Parent = root,
				OnClick = props.OnRobux,
			})
		end
	end

	if props.OnClick then
		Make("TextButton", {
			Name = "Click",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -bottomH),
			ZIndex = z + 2,
			Parent = root,
			Activated = function()
				Motion.Press(root)
				;(props.OnClick :: () -> ())()
			end,
		})
	end

	local handle = { Root = root, Preview = preview, Title = title, Subtitle = subtitle, Buy = buy, RobuxButton = robux } :: any
	function handle.SetPrice(_, text: string?, enabled: boolean?)
		if buy then
			buy:SetText(text or "")
			buy.Root.Visible = text ~= nil
			buy:SetEnabled(enabled ~= false)
		end
	end
	function handle.SetSubtitle(_, text: string)
		if statLabel then
			statLabel.Text = text
		else
			subtitle.Text = text
		end
	end
	function handle.SetSelected(_, on: boolean)
		outer.Color = if on then Theme.Color.White else Theme.Color.Ink
		outer.Thickness = if on then 4 else Theme.Stroke.Card
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: CardHandle
end

return Card
