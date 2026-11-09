-- Playtime Rewards (12 gifts that unlock as you play; reset on leave) and the
-- Daily streak calendar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)
local Store = require(script.Parent.Store)
local State = require(script.Parent.Parent.State)

local RewardsUi = {}

local C = Ui.Colors

local function rewardTitle(r): string
	if r.kind == "cash" then
		return "Cash"
	elseif r.kind == "egg" then
		return Config.EggById[r.egg].name
	end
	return r.animal
end

local function rewardIcon(holder: Instance, r)
	if r.kind == "egg" then
		Viewport.egg(holder, r.egg, "Normal")
	elseif r.kind == "animal" then
		Viewport.animal(holder, r.animal, "Normal")
	else
		Ui.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = "💵",
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 24,
			Parent = holder,
		})
	end
end

local function cashAmount(r): number
	local inc = State.data and State.data.income or 0
	return math.max(r.cash, math.floor(inc * (r.incomeSeconds or 0)))
end

----------------------------------------------------------------------------
-- Playtime
----------------------------------------------------------------------------
local cells = {}

local function tickPlaytime()
	local d = State.data
	if not d then
		return
	end
	local elapsed = State.serverNow() - d.sessionStart
	for i, cell in cells do
		local r = Config.Playtime[i]
		local claimed = d.playtimeClaimed[tostring(i)] == true
		local left = r.minutes * 60 - elapsed
		cell.done.Visible = claimed
		if claimed then
			cell.status.Text = ""
		elseif left <= 0 then
			cell.status.Text = "Claim!"
			cell.status.TextColor3 = Color3.fromRGB(200, 255, 60)
		else
			cell.status.Text = Format.time(left)
			cell.status.TextColor3 = C.White
		end
		if r.kind == "cash" then
			cell.title.Text = Format.cash(cashAmount(r))
		end
	end
end

local function buildPlaytime(gui: ScreenGui)
	local win = Ui.window(gui, "Playtime", "Playtime Rewards", C.Green, Vector2.new(760, 600))
	local gridFrame = Ui.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(30, 31, 38),
		Size = UDim2.new(1, 0, 1, -80),
		ZIndex = 22,
		Parent = win.body,
	})
	Ui.corner(gridFrame, 10)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(166, 128),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gridFrame,
	})
	for i, r in Config.Playtime do
		local btn = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(18, 18, 22),
			LayoutOrder = i,
			ZIndex = 23,
			Parent = gridFrame,
		})
		Ui.stroke(btn, 2)
		local title = Ui.text({
			Text = rewardTitle(r),
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.fromOffset(4, 4),
			ZIndex = 25,
			Parent = btn,
		})
		local holder = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -30, 0, 66),
			Position = UDim2.fromOffset(15, 28),
			ZIndex = 24,
			Parent = btn,
		})
		rewardIcon(holder, r)
		local status = Ui.text({
			Text = "",
			Size = UDim2.new(1, -8, 0, 26),
			Position = UDim2.new(0, 4, 1, -30),
			ZIndex = 25,
			StrokeThickness = 2.5,
			Parent = btn,
		})
		local done = Ui.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(60, 140, 60),
			BackgroundTransparency = 0.35,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 26,
			Parent = btn,
		})
		Ui.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = "✅",
			TextScaled = true,
			Size = UDim2.fromScale(0.6, 0.6),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 27,
			Parent = done,
		})
		btn.Activated:Connect(function()
			Ui.click()
			State.action("ClaimPlaytime", i)
		end)
		cells[i] = { title = title, status = status, done = done }
	end
	Ui.text({
		Text = "Leaving Resets Progress!",
		Size = UDim2.new(0.6, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -58),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 90, 90),
		StrokeThickness = 3,
		ZIndex = 23,
		Parent = win.body,
	})
	local skip
	for _, p in Config.Products do
		if p.key == "SkipPlaytime" then
			skip = p
		end
	end
	Ui.text({
		Text = "Skip All!",
		Size = UDim2.fromOffset(180, 22),
		Position = UDim2.new(1, -10, 1, -76),
		AnchorPoint = Vector2.new(1, 0),
		TextColor3 = C.Yellow,
		ZIndex = 23,
		Parent = win.body,
	})
	Ui.button({
		Text = "R$ " .. skip.price,
		Color = C.Green,
		Size = UDim2.fromOffset(180, 50),
		Position = UDim2.new(1, -10, 1, -52),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 24,
		Parent = win.body,
		OnClick = function()
			Store.buy("product", skip)
		end,
	})
	win.onOpen = tickPlaytime
end

----------------------------------------------------------------------------
-- Daily
----------------------------------------------------------------------------
local daily = { cards = {} }

-- Which streak day is next (or claimed today), and whether it can be claimed.
local function dailyStatus(d): (number, boolean)
	local today = d.serverDay
	if d.daily.last == today then
		return d.daily.streak, false
	elseif d.daily.last == today - 1 then
		return d.daily.streak + 1, true
	end
	return 1, true
end

local function renderDaily()
	local d = State.data
	if not d then
		return
	end
	local day, canClaim = dailyStatus(d)
	local cycleDay = (day - 1) % #Config.Daily + 1
	for i, card in daily.cards do
		local claimed = i < cycleDay or (i == cycleDay and not canClaim)
		card.done.Visible = claimed
		card.frame.BackgroundColor3 = i == cycleDay and Color3.fromRGB(60, 90, 50) or C.Darker
		local r = Config.Daily[i]
		if r.kind == "cash" then
			card.amount.Text = Format.cash(cashAmount(r))
		end
	end
	daily.streak.Text = "🔥 Streak: " .. (canClaim and day - 1 or day) .. " day" .. ((canClaim and day - 1 or day) == 1 and "" or "s")
	if canClaim then
		Ui.setButtonText(daily.claim, "Claim Day " .. day .. "!")
		Ui.setButtonColor(daily.claim, C.Green)
	else
		local secs = 86400 - (os.time() % 86400)
		Ui.setButtonText(daily.claim, "Next in " .. Format.time(secs))
		Ui.setButtonColor(daily.claim, Color3.fromRGB(110, 110, 120))
	end
end

local function buildDaily(gui: ScreenGui)
	local win = Ui.window(gui, "Daily", "📅 Daily Rewards", C.Purple, Vector2.new(860, 440))
	local row = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 220),
		Position = UDim2.fromOffset(0, 40),
		ZIndex = 22,
		Parent = win.body,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i, r in Config.Daily do
		local f = Ui.card(row, i)
		f.Size = UDim2.fromOffset(108, 210)
		Ui.text({ Text = "Day " .. i, Size = UDim2.new(1, -8, 0, 28), Position = UDim2.fromOffset(4, 6), TextColor3 = C.Yellow, ZIndex = 24, Parent = f })
		local holder = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 90), Position = UDim2.fromOffset(8, 40), ZIndex = 23, Parent = f })
		rewardIcon(holder, r)
		local amount = Ui.text({
			Text = r.kind == "cash" and "" or rewardTitle(r),
			Size = UDim2.new(1, -8, 0, 40),
			Position = UDim2.fromOffset(4, 140),
			TextWrapped = true,
			ZIndex = 24,
			Parent = f,
		})
		local done = Ui.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(60, 140, 60),
			BackgroundTransparency = 0.35,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 26,
			Parent = f,
		})
		Ui.corner(done, 10)
		Ui.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = "✅",
			TextScaled = true,
			Size = UDim2.fromScale(0.6, 0.4),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 27,
			Parent = done,
		})
		daily.cards[i] = { frame = f, amount = amount, done = done }
	end
	daily.streak = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = C.Orange,
		ZIndex = 23,
		Parent = win.body,
	})
	daily.claim = Ui.button({
		Text = "",
		Color = C.Green,
		Size = UDim2.fromOffset(300, 56),
		Position = UDim2.new(0.5, 0, 1, -62),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 24,
		Parent = win.body,
		OnClick = function()
			State.action("ClaimDaily")
		end,
	})
	win.onOpen = renderDaily
end

function RewardsUi.init(gui: ScreenGui)
	buildPlaytime(gui)
	buildDaily(gui)
	State.changed:Connect(function()
		if Ui.isOpen("Playtime") then
			tickPlaytime()
		end
		if Ui.isOpen("Daily") then
			renderDaily()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Ui.isOpen("Playtime") then
				tickPlaytime()
			end
			if Ui.isOpen("Daily") then
				renderDaily()
			end
		end
	end)
end

return RewardsUi
