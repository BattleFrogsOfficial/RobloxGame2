--!strict
-- Cutscene screen overlay, built from the UI kit (Label / Icon / Button / Decor / Motion): the big
-- "1 out of N" odds counter, the dog's name + rarity tag + variant badge under it when it stops, the
-- Lucky Streak / Treat Pocket flourish line, the Skip button and the "ball rolled away" fallback text.
-- Pure GUI (no RunService): the cutscene drives it; tools/uicheck builds it in its scenarios.
--   local o = Overlay.new(ui.Root, isTouch)
--   o:ShowCounter() / o:SetCount(n, tier?, punch?) / o:SetStopped(name, rarity, variant?) / o:SetFlourish(text?)
--   o:SetSkip(visible, onSkip?) / o:ShowMessage(text?) / o:Hide() / o:Destroy()
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local C = require(Config:WaitForChild("Cutscene"))
local OddsCounter = require(Shared:WaitForChild("Cutscene"):WaitForChild("OddsCounter"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Icon = require(Components:WaitForChild("Icon"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))

local Overlay = {}

local Z = 45 -- above the HUD (1-40), below modals (50) and the Reveal card (60)

export type OverlayHandle = {
	Root: Frame,
	Count: TextLabel,
	ShowCounter: (self: OverlayHandle) -> (),
	SetCount: (self: OverlayHandle, n: number, tier: string?, punch: boolean?) -> (),
	SetStopped: (self: OverlayHandle, name: string, rarity: string, variant: string?) -> (),
	SetFlourish: (self: OverlayHandle, text: string?) -> (),
	SetSkip: (self: OverlayHandle, visible: boolean, onSkip: (() -> ())?) -> (),
	ShowMessage: (self: OverlayHandle, text: string?) -> (),
	Hide: (self: OverlayHandle) -> (),
	Destroy: (self: OverlayHandle) -> (),
}

function Overlay.new(parent: Instance, isTouch: boolean): OverlayHandle
	local E = if isTouch then Theme.Space.M else Theme.Space.Edge
	local root: Frame = Make("Frame", { Name = "CutsceneOverlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = parent })
	local flash: Frame = Make("Frame", { Name = "Flash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = root })

	-- Counter block, centred a little above the middle so the dog stays visible below it.
	local block: Frame = Make("Frame", { Name = "CounterBlock", BackgroundTransparency = 1, Size = UDim2.fromOffset(720, 220), Position = UDim2.fromScale(0.5, 0.34), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = Z + 1, Parent = root })
	local countHolder: Frame = Make("Frame", { Name = "CountHolder", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, C.Counter.TextSize + 24), ZIndex = Z + 1, Parent = block })
	local countScale: UIScale = Make("UIScale", { Name = "Punch", Scale = 1, Parent = countHolder })
	local count = Label.Display({ Name = "Count", Text = OddsCounter.Text(1), TextSize = C.Counter.TextSize, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = Z + 2, Parent = countHolder })
	local stroke = count:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3
	end

	local info: Frame = Make("Frame", { Name = "Info", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), Position = UDim2.fromOffset(0, C.Counter.TextSize + 28), Visible = false, ZIndex = Z + 1, Parent = block })
	local nameLabel = Label.Display({ Name = "DogName", Text = "", TextSize = Theme.Text.H2 + 4, Size = UDim2.new(1, -40, 0, 34), Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0), XAlign = Enum.TextXAlignment.Center, ZIndex = Z + 2, Parent = info })
	local tagRow: Frame = Make("Frame", { Name = "TagRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 40), ZIndex = Z + 2, Parent = info })
	Decor.List(tagRow, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local tag = Decor.Surface({ Name = "RarityTag", Palette = Theme.Palette.Slate, Radius = Theme.Radius.Pill, Size = UDim2.fromOffset(170, 36), LayoutOrder = 1, ZIndex = Z + 2, Parent = tagRow })
	local tagGradient = tag:FindFirstChildOfClass("UIGradient") :: UIGradient
	local tagText = Label.Pixel({ Name = "Text", Text = "COMMON", TextSize = 16, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = Z + 3, Parent = tag })
	local badge = Decor.Surface({ Name = "VariantBadge", Palette = Theme.Palette.Paper, Radius = Theme.Radius.Pill, Size = UDim2.fromOffset(150, 36), LayoutOrder = 2, ZIndex = Z + 2, Parent = tagRow })
	local badgeIcon = Icon.new({ Name = "variant_gold", Size = 16, Position = UDim2.new(0, Theme.Space.M, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = Z + 3, Parent = badge })
	local badgeText = Label.Display({ Name = "Text", Text = "GOLD", TextSize = Theme.Text.Body, Color = Theme.Color.TextOnPaper, Stroke = false, Size = UDim2.new(1, -(Theme.Space.M + 16 + Theme.Space.S + Theme.Space.M), 1, 0), Position = UDim2.fromOffset(Theme.Space.M + 16 + Theme.Space.S, 0), ZIndex = Z + 3, Parent = badge })
	local flourish = Label.Display({ Name = "Flourish", Text = "", TextSize = Theme.Text.Button, Color = Theme.Palette.Cash.Top, Size = UDim2.new(1, -40, 0, 28), Position = UDim2.new(0.5, 0, 0, 84), AnchorPoint = Vector2.new(0.5, 0), XAlign = Enum.TextXAlignment.Center, ZIndex = Z + 2, Parent = info })
	flourish.Visible = false

	local message = Label.Display({ Name = "Message", Text = "", TextSize = Theme.Text.H1, Size = UDim2.fromOffset(640, 44), Position = UDim2.fromScale(0.5, 0.4), AnchorPoint = Vector2.new(0.5, 0.5), XAlign = Enum.TextXAlignment.Center, ZIndex = Z + 2, Parent = root })
	message.Visible = false

	local skipConn: (() -> ())? = nil
	local skip = Button.new({ Name = "Skip", Text = "Skip", Icon = "skip", IconSize = 16, Palette = "Slate", Size = UDim2.fromOffset(140, 48), Position = UDim2.new(0.5, 0, 1, -E), AnchorPoint = Vector2.new(0.5, 1), TextSize = Theme.Text.Button, ZIndex = Z + 3, Parent = root, OnClick = function()
		if skipConn then
			skipConn()
		end
	end })
	skip.Root.Visible = false

	local handle = { Root = root, Count = count } :: any
	local punchSerial = 0

	local function punch(scale: number)
		punchSerial += 1
		if Motion.ReducedMotion and C.ReducedMotion.NoPop then
			return
		end
		countScale.Scale = scale
		Motion.Tween(countScale, { Scale = 1 }, C.Counter.PopTime, Enum.EasingStyle.Back)
	end

	local function flashOnce(color: Color3)
		if C.Counter.FlashTransparency >= 1 then
			return
		end
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = C.Counter.FlashTransparency
		task.defer(function()
			-- one frame later
			task.wait()
			flash.BackgroundTransparency = 1
		end)
	end

	function handle.ShowCounter()
		message.Visible = false
		block.Visible = true
		info.Visible = false
		flourish.Visible = false
		count.TextColor3 = Theme.Color.White
		count.Text = OddsCounter.Text(1)
		countScale.Scale = 1
	end

	local lastTier: string? = nil
	function handle.SetCount(_, n: number, tier: string?, doPunch: boolean?)
		count.Text = OddsCounter.Text(n)
		local color = if tier then Theme.RarityColor(tier) else Theme.Color.White
		count.TextColor3 = color
		if tier ~= lastTier then
			lastTier = tier
			if doPunch and tier then
				punch(C.Counter.PopScale)
				flashOnce(color)
			end
		end
	end

	function handle.SetStopped(_, name: string, rarity: string, variant: string?)
		local color = Theme.RarityColor(rarity)
		count.TextColor3 = color
		punch(C.Counter.StopPopScale)
		nameLabel.Text = name
		tagText.Text = string.upper(rarity)
		tagGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(1, color:Lerp(Theme.Color.Ink, 0.25)) })
		local vIcon = Icon.ForVariant(variant)
		badge.Visible = vIcon ~= nil
		if vIcon then
			Icon.Set(badgeIcon, vIcon)
			badgeText.Text = string.upper(variant :: string)
		end
		info.Visible = true
		if not Motion.ReducedMotion then
			Motion.PanelOpen(info)
		end
	end

	function handle.SetFlourish(_, text: string?)
		flourish.Text = text or ""
		flourish.Visible = text ~= nil and text ~= ""
		if flourish.Visible and not Motion.ReducedMotion then
			Motion.Pulse(flourish, 1.12)
		end
	end

	function handle.SetSkip(_, visible: boolean, onSkip: (() -> ())?)
		skipConn = onSkip
		skip.Root.Visible = visible
	end

	function handle.ShowMessage(_, text: string?)
		block.Visible = false
		skip.Root.Visible = false
		message.Text = text or ""
		message.Visible = text ~= nil
		if message.Visible then
			Motion.PanelOpen(message)
		end
	end

	function handle.Hide()
		block.Visible = false
		message.Visible = false
		skip.Root.Visible = false
		flash.BackgroundTransparency = 1
	end

	function handle.Destroy()
		skipConn = nil
		root:Destroy()
	end

	return handle :: OverlayHandle
end

return Overlay
