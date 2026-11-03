--!strict
-- Settings: sound, motion, reveal skipping, Treat Pocket mode, keep-dupes per rarity.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local ShopConfig = require(Config:WaitForChild("Shop"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local State = require(UI:WaitForChild("State"))
local Motion = require(UI:WaitForChild("Motion"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Panel = require(Components:WaitForChild("Panel"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))

local Settings = {}

export type SettingsDeps = {
	Parent: Instance,
	OnClose: () -> (),
	SetServerSetting: ((key: string, value: any) -> ())?, -- forwards TreatPocketMode / KeepDupes if a remote exists
}

local function toggleRow(parent: Instance, order: number, text: string, icon: string, get: () -> boolean, set: (boolean) -> ()): Button.ButtonHandle
	local row: Frame = Make("Frame", { Name = "Row_" .. text, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = order, ZIndex = 55, Parent = parent })
	Label.Body({ Text = text, Size = UDim2.new(1, -120, 1, 0), ZIndex = 56, Parent = row, Font = Theme.Font.BodyBold })
	local b: Button.ButtonHandle
	b = Button.new({
		Text = if get() then "On" else "Off",
		Icon = icon,
		IconSize = 16,
		Palette = if get() then "Grass" else "Slate",
		Size = UDim2.fromOffset(110, 44),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = Theme.Text.Body,
		Shadow = false,
		ZIndex = 56,
		Parent = row,
		OnClick = function()
			local v = not get()
			set(v)
			b:SetText(if v then "On" else "Off")
			b:SetPalette(if v then "Grass" else "Slate")
		end,
	})
	return b
end

function Settings.new(deps: SettingsDeps)
	local panel = Panel.new({ Title = "Settings", Icon = "settings", Palette = "Slate", Parent = deps.Parent, OnClose = deps.OnClose, Name = "Settings", Width = 640 })
	local body = panel.Body
	local scroll: ScrollingFrame = Make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Color.Ink, ZIndex = 53, Parent = body })
	Decor.List(scroll, Enum.FillDirection.Vertical, Theme.Space.M)
	Make("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = scroll })

	local S = State.Settings
	local sound = Panel.Section(scroll, "Sound and motion", 1)
	toggleRow(sound, 1, "Music", "music", function()
		return S.Music
	end, function(v)
		State.SetSetting("Music", v)
	end)
	toggleRow(sound, 2, "Sound effects", "mute", function()
		return S.Sfx
	end, function(v)
		State.SetSetting("Sfx", v)
	end)
	toggleRow(sound, 3, "Reduced motion", "timer", function()
		return S.ReducedMotion
	end, function(v)
		State.SetSetting("ReducedMotion", v)
		Motion.ReducedMotion = v
	end)

	local reveals = Panel.Section(scroll, "Reveals", 2)
	toggleRow(reveals, 1, "Skip Common reveals", "skip", function()
		return S.HideCommonReveals
	end, function(v)
		State.SetSetting("HideCommonReveals", v)
	end)
	-- Treat Pocket mode cycles through the config list.
	local tpRow: Frame = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2, ZIndex = 55, Parent = reveals })
	Label.Body({ Text = "Use Treat Pockets", Size = UDim2.new(1, -160, 1, 0), ZIndex = 56, Parent = tpRow, Font = Theme.Font.BodyBold })
	local tpButton: Button.ButtonHandle
	local function tpLabel(mode: string): string
		return if mode == "Always" then "Always" elseif mode == "EpicPlus" then "Epic and up" else "Never"
	end
	tpButton = Button.new({ Text = tpLabel(S.TreatPocketMode), Icon = "treat", IconSize = 16, Palette = "Sky", Size = UDim2.fromOffset(150, 44), Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = Theme.Text.Body, Shadow = false, ZIndex = 56, Parent = tpRow, OnClick = function()
		local idx = table.find(ShopConfig.TreatPocketModes, S.TreatPocketMode) or 1
		local nextMode = ShopConfig.TreatPocketModes[idx % #ShopConfig.TreatPocketModes + 1]
		State.SetSetting("TreatPocketMode", nextMode)
		if deps.SetServerSetting then
			deps.SetServerSetting("TreatPocketMode", nextMode)
		end
		tpButton:SetText(tpLabel(nextMode))
	end })

	local dupes = Panel.Section(scroll, "Keep duplicate dogs instead of auto-selling", 3)
	for i, tier in Rarities.Order do
		toggleRow(dupes, i, tier, "dog", function()
			return S.KeepDupes[tier] == true
		end, function(v)
			S.KeepDupes[tier] = v
			State.SetSetting("KeepDupes", S.KeepDupes)
			if deps.SetServerSetting then
				deps.SetServerSetting("KeepDupes", S.KeepDupes)
			end
		end)
	end

	local handle = { Panel = panel } :: any
	function handle.Open()
		panel:Open()
	end
	function handle.Close()
		panel:Close()
	end
	function handle.Destroy()
		panel:Destroy()
	end
	return handle
end

return Settings
