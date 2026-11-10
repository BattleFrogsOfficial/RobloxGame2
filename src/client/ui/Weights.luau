-- The weights stall's menu: every barbell, which ones you own, and the next
-- one you can buy. Opened by the stall's prompt in your base.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Voxel = require(Shared.Voxel)

local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)
local State = require(script.Parent.Parent.State)

local Weights = {}

local C = Ui.Colors
local cards = {}
local info: TextLabel

local function render()
	local d = State.data
	if not d then
		return
	end
	local double = d.passes.DoubleStrength and 2 or 1
	for tier, card in cards do
		local w = Config.Weights[tier]
		card.gain.Text = "+" .. Format.short(w.gain * double) .. " Strength / rep"
		if tier <= d.weightTier then
			card.frame.BackgroundColor3 = tier == d.weightTier and Color3.fromRGB(46, 70, 44) or C.Darker
			card.state.Text = tier == d.weightTier and "IN USE" or "OWNED"
			card.state.TextColor3 = C.Cash
			card.state.Visible = true
			card.buy.Visible = false
		elseif tier == d.weightTier + 1 then
			card.frame.BackgroundColor3 = C.Darker
			card.state.Visible = false
			card.buy.Visible = true
			Ui.setButtonText(card.buy, Format.cash(w.cost))
			Ui.setButtonColor(card.buy, d.cash >= w.cost and C.Green or Color3.fromRGB(110, 110, 120))
		else
			card.frame.BackgroundColor3 = C.Darker
			card.state.Text = "LOCKED  " .. Format.cash(w.cost)
			card.state.TextColor3 = Color3.fromRGB(170, 170, 180)
			card.state.Visible = true
			card.buy.Visible = false
		end
	end
	local current = Config.Weights[d.weightTier]
	info.Text = string.format("Lifting the %s: +%s Strength every rep", current.name, Format.short(current.gain * double))
end

function Weights.init(gui: ScreenGui)
	local win = Ui.window(gui, "Weights", "Weights", C.Yellow, Vector2.new(860, 540), "strength")
	info = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		ZIndex = 23,
		Parent = win.body,
	})
	local holder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -36),
		Position = UDim2.fromOffset(0, 36),
		ZIndex = 22,
		Parent = win.body,
	})
	local grid = Ui.scrollGrid(holder, Vector2.new(194, 196), 12)
	for tier, w in Config.Weights do
		local frame = Ui.card(grid, tier)
		local art = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 84), Position = UDim2.fromOffset(5, 4), ZIndex = 23, Parent = frame })
		Viewport.show(art, Voxel.barbell(tier), { ZIndex = 23 })
		Ui.text({ Text = w.name, Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 90), ZIndex = 24, Parent = frame })
		local gain = Ui.text({ Text = "", Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 116), TextColor3 = C.Yellow, ZIndex = 24, Parent = frame })
		local state = Ui.text({ Text = "", Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -36), ZIndex = 24, Parent = frame })
		local buy = Ui.button({
			Text = "",
			Color = C.Green,
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.new(0, 8, 1, -48),
			ZIndex = 24,
			Visible = false,
			Parent = frame,
			OnClick = function()
				State.action("BuyWeight")
			end,
		})
		cards[tier] = { frame = frame, gain = gain, state = state, buy = buy }
	end
	win.onOpen = render
	State.changed:Connect(function()
		if Ui.isOpen("Weights") then
			render()
		end
	end)
end

return Weights
