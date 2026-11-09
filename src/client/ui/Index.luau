-- Index (collection book): every animal grouped by egg. Undiscovered ones
-- show as dark silhouettes; discovered ones pay a one-time cash reward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)
local State = require(script.Parent.Parent.State)

local Index = {}

local C = Ui.Colors
local list: ScrollingFrame
local header: TextLabel
local lastSig: string? = nil

local function render()
	local d = State.data
	if not d then
		return
	end
	local parts = {}
	for _, a in Config.Animals do
		table.insert(parts, tostring(d.index[a.id] or 0))
	end
	local sig = table.concat(parts)
	if sig == lastSig then
		return
	end
	lastSig = sig
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local found = 0
	for tier, egg in Config.Eggs do
		local rcolor = Config.Rarities[tier].color
		local section = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 0, 236),
			LayoutOrder = tier,
			ZIndex = 22,
			Parent = list,
		})
		local eggIcon = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), ZIndex = 23, Parent = section })
		Viewport.egg(eggIcon, egg.id, "Normal")
		Ui.text({
			Text = egg.name .. "   |   " .. egg.rarity,
			Size = UDim2.new(1, -60, 0, 32),
			Position = UDim2.fromOffset(48, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rcolor,
			ZIndex = 23,
			Parent = section,
		})
		local row = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 190),
			Position = UDim2.fromOffset(0, 44),
			ZIndex = 22,
			Parent = section,
		})
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = row,
		})
		for i, a in Config.AnimalsByEgg[egg.id] do
			local status = d.index[a.id]
			if status then
				found += 1
			end
			local card = Ui.card(row, i)
			card.Size = UDim2.fromOffset(220, 186)
			local holder = Ui.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -10, 0, 104),
				Position = UDim2.fromOffset(5, 4),
				ZIndex = 23,
				Parent = card,
			})
			Viewport.animal(holder, a.id, "Normal", status == nil)
			Ui.text({
				Text = status and a.name or "???",
				Size = UDim2.new(1, -10, 0, 24),
				Position = UDim2.fromOffset(5, 108),
				ZIndex = 24,
				Parent = card,
			})
			local reward = a.income * Config.IndexRewardSeconds
			if status == 1 then
				Ui.button({
					Text = "Claim " .. Format.cash(reward),
					Color = C.Green,
					Size = UDim2.new(1, -16, 0, 40),
					Position = UDim2.new(0, 8, 1, -46),
					ZIndex = 24,
					Parent = card,
					OnClick = function()
						State.action("ClaimIndex", a.id)
					end,
				})
			else
				Ui.text({
					Text = status == 2 and ("Claimed   " .. Format.cash(a.income) .. "/s") or ("Reward: " .. Format.cash(reward)),
					Size = UDim2.new(1, -10, 0, 22),
					Position = UDim2.new(0, 5, 1, -36),
					TextColor3 = status == 2 and C.Cash or Color3.fromRGB(170, 170, 180),
					ZIndex = 24,
					Parent = card,
				})
			end
		end
	end
	header.Text = string.format("Discovered %d / %d animals", found, #Config.Animals)
end

function Index.init(gui: ScreenGui)
	local win = Ui.window(gui, "Index", "Index", C.Blue, Vector2.new(760, 580), "book")
	header = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = C.Yellow,
		ZIndex = 23,
		Parent = win.body,
	})
	list = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -36),
		Position = UDim2.fromOffset(0, 36),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = win.body,
	})
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = list })
	win.onOpen = function()
		lastSig = nil
		render()
	end
	State.changed:Connect(function()
		if Ui.isOpen("Index") then
			render()
		end
	end)
end

return Index
