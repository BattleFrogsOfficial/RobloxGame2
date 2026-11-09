-- "Buy" window: Luck, heavier weights and base slots, plus a preview of what
-- your current Strength and Luck do to a split.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local State = require(script.Parent.Parent.State)

local Upgrades = {}

local C = Ui.Colors
local rows = {}
local statsLabel: TextLabel

local function row(parent: Instance, order: number, icon: string, title: string, color: Color3)
	local f = Ui.card(parent, order)
	f.Size = UDim2.new(1, 0, 0, 96)
	Ui.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = icon,
		TextScaled = true,
		Size = UDim2.fromOffset(70, 70),
		Position = UDim2.fromOffset(12, 13),
		ZIndex = 23,
		Parent = f,
	})
	Ui.text({
		Text = title,
		Size = UDim2.new(1, -420, 0, 34),
		Position = UDim2.fromOffset(94, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		ZIndex = 23,
		StrokeThickness = 2.5,
		Parent = f,
	})
	local desc = Ui.text({
		Text = "",
		Size = UDim2.new(1, -420, 0, 26),
		Position = UDim2.fromOffset(94, 52),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(215, 215, 225),
		ZIndex = 23,
		Parent = f,
	})
	return f, desc
end

local function render()
	local d = State.data
	if not d then
		return
	end
	-- Luck
	local luckMax = d.luckLevel >= Config.Luck.MaxLevel
	local nextLuck = Formulas.luck(d.luckLevel + 1, d.passes.DoubleLuck, d.boosts.luckUntil > d.osTime)
	rows.luckDesc.Text = luckMax and string.format("x%.2f Luck (max)", d.luck)
		or string.format("Level %d:  x%.2f → x%.2f Luck", d.luckLevel, d.luck, nextLuck)
	Ui.setButtonText(rows.luckBtn, luckMax and "MAX" or Format.cash(Formulas.luckCost(d.luckLevel)))
	rows.luckBtn5.Visible = not luckMax

	-- Weight
	local w = Config.Weights[d.weightTier]
	local nw = Config.Weights[d.weightTier + 1]
	rows.weightDesc.Text = nw and string.format("%s (+%d) → %s (+%d) per lift", w.name, w.gain, nw.name, nw.gain)
		or (w.name .. " (+" .. w.gain .. ") — heaviest!")
	Ui.setButtonText(rows.weightBtn, nw and Format.cash(nw.cost) or "MAX")

	-- Base
	local maxed = d.baseSlots >= Config.Base.MaxSlots
	rows.baseDesc.Text = maxed and (d.baseSlots .. " slots (max)") or string.format("%d → %d pen slots", d.baseSlots, d.baseSlots + Config.Base.SlotsPerLevel)
	Ui.setButtonText(rows.baseBtn, maxed and "MAX" or Format.cash(Formulas.baseCost(d.baseSlots)))

	-- What a fully charged split gives you right now.
	local sp = Formulas.splitParams(d.strength, 1)
	statsLabel.Text = string.format(
		"Full-charge split: %d studs deep  •  open %.1fs  •  carry %d egg%s  •  Strength %s",
		math.floor(sp.length),
		sp.openTime,
		d.carry,
		d.carry > 1 and "s" or "",
		Format.short(d.strength)
	)
end

function Upgrades.init(gui: ScreenGui)
	local win = Ui.window(gui, "Upgrades", "🛍️ Upgrades", C.Blue, Vector2.new(820, 470))
	local list = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 22, Parent = win.body })
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12), Parent = list })

	statsLabel = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Color3.fromRGB(150, 230, 255),
		LayoutOrder = 0,
		ZIndex = 23,
		Parent = list,
	})

	local f
	f, rows.luckDesc = row(list, 1, "🍀", "Luck", Color3.fromRGB(150, 255, 150))
	rows.luckBtn = Ui.button({ Text = "", Color = C.Green, Size = UDim2.fromOffset(170, 56), Position = UDim2.new(1, -196, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 24, Parent = f, OnClick = function()
		State.action("BuyLuck", 1)
	end })
	rows.luckBtn5 = Ui.button({ Text = "x5", Color = C.Teal, Size = UDim2.fromOffset(80, 56), Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 24, Parent = f, OnClick = function()
		State.action("BuyLuck", 5)
	end })

	f, rows.weightDesc = row(list, 2, "🏋️", "Heavier Weight", C.Yellow)
	rows.weightBtn = Ui.button({ Text = "", Color = C.Green, Size = UDim2.fromOffset(260, 56), Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 24, Parent = f, OnClick = function()
		State.action("BuyWeight")
	end })

	f, rows.baseDesc = row(list, 3, "🏡", "Bigger Base", C.Orange)
	rows.baseBtn = Ui.button({ Text = "", Color = C.Green, Size = UDim2.fromOffset(260, 56), Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 24, Parent = f, OnClick = function()
		State.action("UpgradeBase")
	end })

	Ui.text({
		Text = "Train on the pink pad in your base to gain Strength: deeper splits, longer open time.",
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Color3.fromRGB(200, 200, 210),
		LayoutOrder = 4,
		ZIndex = 23,
		Parent = list,
	})

	win.onOpen = render
	State.changed:Connect(function()
		if Ui.isOpen("Upgrades") then
			render()
		end
	end)
end

return Upgrades
