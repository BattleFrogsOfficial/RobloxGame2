--!strict
-- Grid card: rarity-framed preview area, name, subtitle, optional price button. Used by Shop, Dogs and Book.
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
	Subtitle: string?,
	Icon: string?, -- pixel icon shown in the preview area
	Rarity: string?, -- frames the preview in the rarity colour
	Variant: string?, -- badge in the preview corner
	Price: string?, -- button text; nil = no button
	PricePalette: string?,
	PriceIcon: string?,
	Size: UDim2?,
	Parent: Instance?,
	LayoutOrder: number?,
	ZIndex: number?,
	OnClick: (() -> ())?, -- whole card
	OnBuy: (() -> ())?, -- price button
	Locked: boolean?,
	Owned: boolean?,
	Silhouette: boolean?, -- unknown dog in the book
	Name: string?,
	Preview: Instance?, -- custom preview content (e.g. a ViewportFrame) instead of an icon
}

export type CardHandle = {
	Root: Frame,
	Preview: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Buy: Button.ButtonHandle?,
	SetPrice: (self: CardHandle, text: string?, enabled: boolean?) -> (),
	SetSubtitle: (self: CardHandle, text: string) -> (),
	SetSelected: (self: CardHandle, on: boolean) -> (),
}

Card.DefaultSize = UDim2.fromOffset(150, 224)

function Card.new(props: CardProps): CardHandle
	local size = props.Size or Card.DefaultSize
	local root: Frame = Make("Frame", {
		Name = props.Name or ("Card_" .. props.Title),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = size,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 53,
	})
	Decor.Corner(root, Theme.Radius.Card)
	local outer = Decor.Stroke(root, Theme.Stroke.Panel)
	Decor.PaletteGradient(root, Theme.Palette.Paper)
	local z = root.ZIndex + 1

	local pad = Theme.Space.S
	local previewH = math.floor(size.Y.Offset * 0.4)
	local preview: Frame = Make("Frame", {
		Name = "Preview",
		BackgroundColor3 = Theme.Color.PaperShade,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -pad * 2, 0, previewH),
		Position = UDim2.fromOffset(pad, pad),
		ZIndex = z,
		ClipsDescendants = true,
		Parent = root,
	})
	Decor.Corner(preview, Theme.Radius.Card - 2)
	local rarityColor = Theme.RarityColor(props.Rarity)
	Decor.Stroke(preview, 3, if props.Rarity then rarityColor else Theme.Color.Track)
	if props.Rarity then
		-- Soft tint of the rarity behind the preview
		Decor.Gradient(preview, Theme.Color.Paper, rarityColor:Lerp(Theme.Color.Paper, 0.6))
	end
	if props.Preview then
		props.Preview.Parent = preview
	elseif props.Icon then
		local iconPx = Icon.Snap(math.min(64, previewH - 16))
		Icon.new({
			Name = props.Icon,
			Size = iconPx,
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 1,
			Tint = if props.Silhouette then Theme.Color.Ink else nil,
			Parent = preview,
		})
	end
	local variantIcon = Icon.ForVariant(props.Variant)
	if variantIcon then
		Icon.new({ Name = variantIcon, Size = 16, Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), ZIndex = z + 2, Parent = preview })
	end
	if props.Locked then
		Icon.new({ Name = "lock", Size = 16, Position = UDim2.new(0, 4, 0, 4), ZIndex = z + 2, Parent = preview })
	end
	if props.Owned then
		Icon.new({ Name = "check", Size = 16, Position = UDim2.new(0, 4, 0, 4), ZIndex = z + 2, Parent = preview })
	end

	local textY = pad + previewH + Theme.Space.XS
	local title = Label.Display({
		Name = "Title",
		Text = props.Title,
		TextSize = Theme.Text.Caption,
		Color = Theme.Color.TextOnPaper,
		Stroke = false,
		Font = Theme.Font.BodyBold,
		Size = UDim2.new(1, -pad * 2, 0, 36),
		Position = UDim2.fromOffset(pad, textY),
		XAlign = Enum.TextXAlignment.Center,
		YAlign = Enum.TextYAlignment.Top,
		Wrap = true,
		ZIndex = z,
		Parent = root,
	})
	local subtitle = Label.Caption({
		Name = "Subtitle",
		Text = props.Subtitle or "",
		Color = if props.Rarity then rarityColor else Theme.Color.TextMuted,
		Size = UDim2.new(1, -pad * 2, 0, 34),
		Position = UDim2.fromOffset(pad, textY + 36),
		XAlign = Enum.TextXAlignment.Center,
		YAlign = Enum.TextYAlignment.Top,
		Wrap = true,
		TextSize = Theme.Text.Caption,
		ZIndex = z,
		Font = Theme.Font.BodyBold,
		Parent = root,
	})

	local buy: Button.ButtonHandle? = nil
	if props.Price then
		buy = Button.new({
			Text = props.Price,
			Icon = props.PriceIcon,
			IconSize = 16,
			Palette = props.PricePalette or "Grass",
			TextSize = Theme.Text.Caption + 2,
			Size = UDim2.new(1, -pad * 2, 0, 44),
			Position = UDim2.new(0, pad, 1, -pad),
			AnchorPoint = Vector2.new(0, 1),
			Shadow = false,
			ZIndex = z + 1,
			Parent = root,
			OnClick = props.OnBuy,
		})
	end

	if props.OnClick then
		Make("TextButton", {
			Name = "Click",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, if props.Price then -(44 + pad * 2) else 0),
			ZIndex = z + 2,
			Parent = root,
			Activated = function()
				Motion.Press(root)
				;(props.OnClick :: () -> ())()
			end,
		})
	end

	local handle = { Root = root, Preview = preview, Title = title, Subtitle = subtitle, Buy = buy } :: any
	function handle.SetPrice(_, text: string?, enabled: boolean?)
		if buy then
			buy:SetText(text or "")
			buy.Root.Visible = text ~= nil
			buy:SetEnabled(enabled ~= false)
		end
	end
	function handle.SetSubtitle(_, text: string)
		subtitle.Text = text
	end
	function handle.SetSelected(_, on: boolean)
		outer.Color = if on then Theme.Palette.Sky.Bottom else Theme.Color.Ink
		outer.Thickness = if on then 4 else Theme.Stroke.Panel
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return handle :: CardHandle
end

return Card
