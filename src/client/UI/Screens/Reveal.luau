--!strict
-- Reveal end card (the screenshot frame at the end of the cutscene; the cutscene itself is another module).
-- Shows: rarity-coloured flash, dog name, zone, rarity tag, variant badge, the income cascade, CAUGHT or
-- RAN OFF, and the whistle / keep prompts. Reveal.Show(result, opts) -> closes itself or on button.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))
local CutsceneConfig = require(Config:WaitForChild("Cutscene")) -- EndCard.AutoClose (also the server timeout)
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Icon = require(Components:WaitForChild("Icon"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))

local Reveal = {}

export type RevealOpts = {
	OnClose: (() -> ())?,
	OnWhistle: (() -> ())?, -- shown only when result.WhistleOwned and not Caught
	OnKeep: (() -> ())?, -- shown when IsDupe
	IsDupe: boolean?,
	AutoCloseSeconds: number?, -- default by rarity
	Spectator: boolean?, -- compact version for other players' throws
}

local function zoneName(id: string): string
	for _, z in Zones do
		if z.Id == id then
			return z.Name
		end
	end
	return id
end

function Reveal.new(parent: Instance)
	local root: Frame = Make("Frame", { Name = "Reveal", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 60, Parent = parent })
	local flash: Frame = Make("Frame", { Name = "Flash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = root })
	local card: Frame = Make("Frame", {
		Name = "Card",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(420, 300),
		Position = UDim2.fromScale(0.5, 0.46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 61,
		Parent = root,
	})
	Decor.Corner(card, Theme.Radius.Panel)
	local cardStroke = Decor.Stroke(card, 4)
	Decor.PaletteGradient(card, Theme.Palette.Paper)
	Decor.Shadow(card, "Soft")

	local band: Frame = Make("Frame", { Name = "Band", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 48), ZIndex = 62, Parent = card })
	Decor.TopCorners(band, Theme.Radius.Panel)
	local bandGradient = Decor.Gradient(band, Theme.Color.Track, Theme.Color.Track)
	local rarityTag = Label.Pixel({ Name = "RarityTag", Text = "COMMON", TextSize = 16, Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(Theme.Space.L, 0), ZIndex = 63, Parent = band })
	local variantIcon = Icon.new({ Name = "variant_gold", Size = 32, Position = UDim2.new(1, -Theme.Space.M, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 63, Parent = band })
	variantIcon.Name = "VariantIcon"
	local variantText = Label.Display({ Name = "VariantText", Text = "", TextSize = Theme.Text.Body, Size = UDim2.fromOffset(90, 48), Position = UDim2.new(1, -(Theme.Space.M + 36), 0, 0), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 63, Parent = band })

	local dogIcon = Icon.new({ Name = "dog", Size = 64, Position = UDim2.new(0, Theme.Space.L, 0, 64), ZIndex = 62, Parent = card })
	local nameLabel = Label.Display({ Name = "DogName", Text = "", TextSize = Theme.Text.H2, Color = Theme.Color.TextOnPaper, Stroke = false, Size = UDim2.new(1, -(Theme.Space.L * 2 + 80), 0, 32), Position = UDim2.fromOffset(Theme.Space.L + 80, 64), ZIndex = 62, Parent = card })
	local zoneLabel = Label.Caption({ Name = "Zone", Text = "", Size = UDim2.new(1, -(Theme.Space.L * 2 + 80), 0, 18), Position = UDim2.fromOffset(Theme.Space.L + 80, 98), ZIndex = 62, Font = Theme.Font.BodyBold, Parent = card })
	local cascade = Label.Body({ Name = "Cascade", Text = "", Size = UDim2.new(1, -Theme.Space.L * 2, 0, 20), Position = UDim2.fromOffset(Theme.Space.L, 140), ZIndex = 62, Parent = card })
	local total = Label.Display({ Name = "Total", Text = "", TextSize = Theme.Text.H1, Size = UDim2.new(1, -Theme.Space.L * 2, 0, 40), Position = UDim2.fromOffset(Theme.Space.L, 162), ZIndex = 62, Parent = card })
	local outcome = Label.Display({ Name = "Outcome", Text = "", TextSize = Theme.Text.H2, Size = UDim2.new(1, -Theme.Space.L * 2, 0, 32), Position = UDim2.new(0.5, 0, 0, 212), AnchorPoint = Vector2.new(0.5, 0), XAlign = Enum.TextXAlignment.Center, ZIndex = 62, Parent = card })
	local buttons: Frame = Make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, -Theme.Space.L * 2, 0, 44), Position = UDim2.new(0.5, 0, 1, -Theme.Space.M), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 62, Parent = card })
	Decor.List(buttons, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Center)

	local closeTimer = 0
	local handle = { Root = root } :: any

	local function clearButtons()
		for _, c in buttons:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	function handle.Hide()
		if not root.Visible then
			return
		end
		Motion.PanelClose(card, function()
			root.Visible = false
		end)
	end

	function handle.Show(_, result: any, opts: RevealOpts?)
		local o: RevealOpts = opts or {}
		closeTimer += 1
		local myTimer = closeTimer
		-- Every way out (OK, Whistle, Keep, the auto-close timer) hides the card and calls OnClose exactly once,
		-- so the cutscene waiting on it always gets its RETURN beat.
		local closed = false
		local function close()
			if closed then
				return
			end
			closed = true
			handle:Hide()
			if o.OnClose then
				o.OnClose()
			end
		end
		local def = DogCatalog.Get(result.DogId)
		local rarity = result.Rarity or (def and def.Rarity) or "Common"
		local color = Theme.RarityColor(rarity)
		local name = if def then def.Name else tostring(result.DogId)

		cardStroke.Color = color
		bandGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(1, color:Lerp(Theme.Color.Ink, 0.25)) })
		rarityTag.Text = string.upper(rarity)
		local vIcon = Icon.ForVariant(result.Variant)
		variantIcon.Visible = vIcon ~= nil
		variantText.Text = if result.Variant then string.upper(result.Variant) else ""
		if vIcon then
			Icon.Set(variantIcon, vIcon)
		end
		nameLabel.Text = name
		zoneLabel.Text = string.upper(zoneName(result.ZoneId or "")) .. "   " .. FormatNumber.Compact(result.Distance or 0) .. " studs"
		zoneLabel.TextColor3 = Theme.Color.TextMuted
		Icon.Set(dogIcon, "dog")

		local base = if def then def.Income else 0
		local vm = if result.Variant then ((Rarities.Variants :: any)[result.Variant].IncomeMult) else 1
		cascade.Text = string.format("%s base  x%s %s%s", FormatNumber.PerSecond(base), tostring((Rarities.Tiers :: any)[rarity].IncomeMult), string.lower(rarity), if vm ~= 1 then string.format("  x%d %s", vm, string.lower(result.Variant)) else "")
		local adult = if def then DogCatalog.AdultIncome(def, result.Variant) else 0
		total.Text = FormatNumber.PerSecond(adult)
		total.TextColor3 = color

		clearButtons()
		if result.Caught then
			outcome.Text = if result.LuckyStreakTriggered then "CAUGHT  (Lucky Streak)" elseif result.TreatPocketUsed then "CAUGHT  (Treat Pocket)" else "CAUGHT"
			outcome.TextColor3 = Theme.Palette.Grass.Top
			if o.IsDupe and o.OnKeep then
				Button.new({ Text = "Keep", Icon = "check", IconSize = 16, Palette = "Grass", Size = UDim2.fromOffset(140, 44), ZIndex = 63, Parent = buttons, OnClick = function()
					(o.OnKeep :: () -> ())()
					close()
				end })
			end
		else
			outcome.Text = "RAN OFF"
			outcome.TextColor3 = Theme.Palette.Danger.Top
			if result.WhistleOwned and o.OnWhistle and not o.Spectator then
				Button.new({ Text = "Whistle (" .. tostring(result.WhistleCount or 0) .. ")", Icon = "whistle", IconSize = 16, Palette = "Cash", Size = UDim2.fromOffset(180, 44), ZIndex = 63, Parent = buttons, OnClick = function()
					(o.OnWhistle :: () -> ())()
					close()
				end })
			end
		end
		Button.new({ Text = if o.Spectator then "Nice" else "OK", Palette = "Sky", Size = UDim2.fromOffset(110, 44), ZIndex = 63, Parent = buttons, OnClick = close })

		card.Size = if o.Spectator then UDim2.fromOffset(360, 260) else UDim2.fromOffset(420, 300)
		root.Visible = true
		Motion.PanelOpen(card)
		-- Rarity flash on Epic+
		local idx = table.find(Rarities.Order, rarity) or 1
		if idx >= 4 and not Motion.ReducedMotion then
			flash.BackgroundColor3 = color
			flash.BackgroundTransparency = 0.4
			Motion.Tween(flash, { BackgroundTransparency = 1 }, 0.5)
		end
		local ec = CutsceneConfig.EndCard
		local seconds = o.AutoCloseSeconds
			or (if o.Spectator then ec.SpectatorAutoClose else ((ec.AutoClose :: any)[rarity] or ec.AutoClose.Common))
		task.delay(seconds, function()
			if closeTimer == myTimer then
				close()
			end
		end)
	end

	return handle
end

return Reveal
