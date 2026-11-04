--!strict
-- Spectator banner: a one-line strip under the event banner for other players' notable throws.
-- "Aidan threw to the Beach... LEGENDARY Golden Retriever! CAUGHT" in rarity colour, 3.5 s.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local DogCatalog = require(Util:WaitForChild("DogCatalog"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Icon = require(Components:WaitForChild("Icon"))
local Label = require(Components:WaitForChild("Label"))

local Spectator = {}

function Spectator.new(parent: Instance, isTouch: boolean)
	local E = Theme.Space.Edge
	local root: Frame = Make("Frame", {
		Name = "SpectatorBanner",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(if isTouch then 260 else 460, 44),
		-- the HUD's event-banner slot (HUD: touch banner right edge = Edge + 150 + 8; height 48)
		Position = if isTouch then UDim2.new(1, -(Theme.Space.M + 150 + Theme.Space.S), 0, Theme.Space.M + 48 + Theme.Space.S) else UDim2.new(0.5, 0, 0, E + 48 + Theme.Space.S),
		AnchorPoint = if isTouch then Vector2.new(1, 0) else Vector2.new(0.5, 0),
		Visible = false,
		ZIndex = 39,
		Parent = parent,
	})
	Decor.Corner(root, Theme.Radius.Card)
	Decor.Stroke(root, Theme.Stroke.Panel)
	local gradient = Decor.PaletteGradient(root, Theme.Palette.Slate)
	local icon = Icon.new({ Name = "dog", Size = 32, Position = UDim2.new(0, Theme.Space.S, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 40, Parent = root })
	local text = Label.Display({ Text = "", TextSize = Theme.Text.Caption, Size = UDim2.new(1, -(Theme.Space.S + 32 + Theme.Space.M), 1, -4), Position = UDim2.fromOffset(Theme.Space.S + 32 + Theme.Space.S, 2), Wrap = true, ZIndex = 40, Parent = root })
	local serial = 0
	local handle = { Root = root } :: any
	function handle.Show(_, playerName: string, result: any, minRarityIndex: number?)
		local def = DogCatalog.Get(result.DogId)
		local rarity = result.Rarity or (def and def.Rarity) or "Common"
		local color = Theme.RarityColor(rarity)
		gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(1, color:Lerp(Theme.Color.Ink, 0.3)) })
		local v = Icon.ForVariant(result.Variant)
		Icon.Set(icon, v or "dog")
		local name = if def then def.Name else tostring(result.DogId)
		text.Text = string.format("%s: %s%s %s  %s", playerName, if result.Variant then string.upper(result.Variant) .. " " else "", string.upper(rarity), name, if result.Caught then "CAUGHT" else "RAN OFF")
		serial += 1
		local mine = serial
		root.Visible = true
		Motion.PanelOpen(root)
		task.delay(3.5, function()
			if serial == mine then
				Motion.PanelClose(root)
			end
		end)
	end
	return handle
end

return Spectator
