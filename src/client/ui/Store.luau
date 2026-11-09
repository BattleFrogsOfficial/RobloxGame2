-- Robux shop: game passes and developer products.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Ui = require(script.Parent.Ui)
local State = require(script.Parent.Parent.State)

local Store = {}

local C = Ui.Colors
local player = Players.LocalPlayer
local passButtons = {}

-- Real purchase if the item has an ID, otherwise a free Studio test grant.
function Store.buy(kind: string, item)
	if item.id ~= 0 then
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, item.id)
		else
			MarketplaceService:PromptProductPurchase(player, item.id)
		end
	else
		State.action("StudioGrant", kind, item.key)
	end
end

local function card(parent: Instance, order: number, kind: string, item, color: Color3)
	local f = Ui.card(parent, order)
	local holder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(68, 68),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 23,
		Parent = f,
	})
	Ui.icon(holder, item.icon, { ZIndex = 23 })
	Ui.text({
		Text = item.name,
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 78),
		TextColor3 = color,
		ZIndex = 23,
		Parent = f,
	})
	Ui.text({
		Text = item.desc,
		Size = UDim2.new(1, -16, 0, 36),
		Position = UDim2.fromOffset(8, 106),
		TextColor3 = Color3.fromRGB(210, 210, 220),
		TextWrapped = true,
		StrokeThickness = 1.5,
		ZIndex = 23,
		Parent = f,
	})
	local btn = Ui.button({
		Text = "R$ " .. item.price,
		Color = C.Green,
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.new(0, 8, 1, -48),
		ZIndex = 24,
		Parent = f,
		OnClick = function()
			if kind == "pass" and State.data and State.data.passes[item.key] then
				return
			end
			Store.buy(kind, item)
		end,
	})
	if kind == "pass" then
		passButtons[item.key] = btn
	end
end

local function render()
	local d = State.data
	if not d then
		return
	end
	for key, btn in passButtons do
		local owned = d.passes[key] == true
		local item
		for _, p in Config.Passes do
			if p.key == key then
				item = p
			end
		end
		Ui.setButtonText(btn, owned and "Owned" or "R$ " .. item.price)
		Ui.setButtonColor(btn, owned and Color3.fromRGB(110, 110, 120) or C.Green)
	end
end

function Store.init(gui: ScreenGui)
	local win = Ui.window(gui, "Store", "Shop", C.Yellow, Vector2.new(880, 580), "chest")
	local sf = Ui.scrollGrid(win.body, Vector2.new(196, 210), 12)
	local order = 0
	for _, p in Config.Products do
		order += 1
		card(sf, order, "product", p, C.Yellow)
	end
	for _, p in Config.Passes do
		order += 1
		card(sf, order, "pass", p, Color3.fromRGB(150, 230, 255))
	end
	win.onOpen = render
	State.changed:Connect(render)
end

return Store
