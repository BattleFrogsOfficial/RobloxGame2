--!nonstrict
-- leaderstats (Income $/s, Cash) and the plaza Leaderboard SurfaceGui (ScrollingFrame "List"):
-- players in this server ranked by total $/s with their rarest catch. Global boards are a v1.1 TODO.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Rarities = require(Config:WaitForChild("Rarities"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local Odds = require(Util:WaitForChild("Odds"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local DogService = require(script.Parent:WaitForChild("DogService"))

local LeaderboardService = {}

local function rarestCatch(state: any): string?
	local best, bestIdx = nil, 0
	for dogId in state.Book do
		local def = DogCatalog.Get(dogId)
		if def then
			local i = Odds.RarityIndex(def.Rarity)
			if i > bestIdx then
				best, bestIdx = def.Rarity, i
			end
		end
	end
	return best
end

local function makeStats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local inc = Instance.new("NumberValue")
	inc.Name = "$/s"
	inc.Parent = folder
	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Parent = folder
	folder.Parent = player
end

local function updateStats()
	for _, player in DataService.Players() do
		local state = DataService.Get(player)
		local ls = player:FindFirstChild("leaderstats")
		if state and ls then
			local inc = ls:FindFirstChild("$/s") :: NumberValue
			local cash = ls:FindFirstChild("Cash") :: NumberValue
			if inc then
				inc.Value = math.floor(DogService.CurrentIncome(player))
			end
			if cash then
				cash.Value = math.floor(state.Cash)
			end
		end
	end
end

local function row(parent: Instance, order: number, text: string, color: Color3)
	local t = Instance.new("TextLabel")
	t.Name = "Row"
	t.LayoutOrder = order
	t.Size = UDim2.new(1, -8, 0, 48)
	t.BackgroundTransparency = if order % 2 == 0 then 0.85 else 1
	t.BackgroundColor3 = Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color
	t.Text = text
	t.Parent = parent
end

local function updateBoards()
	local entries = {}
	for _, player in DataService.Players() do
		local state = DataService.Get(player)
		if state then
			table.insert(entries, { Name = player.DisplayName, Income = DogService.CurrentIncome(player),
				Rarest = rarestCatch(state) })
		end
	end
	table.sort(entries, function(a, b)
		return a.Income > b.Income
	end)
	for _, board in CollectionService:GetTagged("Leaderboard") do
		local list = board:FindFirstChild("List", true)
		if list and list:IsA("ScrollingFrame") then
			for _, c in list:GetChildren() do
				if c.Name == "Row" then
					c:Destroy()
				end
			end
			if not list:FindFirstChildWhichIsA("UIListLayout") then
				local layout = Instance.new("UIListLayout")
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Padding = UDim.new(0, 4)
				layout.Parent = list
			end
			list.AutomaticCanvasSize = Enum.AutomaticSize.Y
			list.CanvasSize = UDim2.new()
			if #entries == 0 then
				row(list, 1, "  Throw a ball to get on the board!", Color3.new(1, 1, 1))
			end
			for i, e in entries do
				local color = Color3.new(1, 1, 1)
				if e.Rarest then
					color = (Rarities.Tiers :: any)[e.Rarest].Color
				end
				local rarest = if e.Rarest then ("  •  best: %s"):format(e.Rarest) else ""
				row(list, i, ("  #%d  %s  —  %s%s"):format(i, e.Name, FormatNumber.PerSecond(e.Income), rarest), color)
			end
		end
	end
end

function LeaderboardService.Start()
	DataService.OnLoaded(function(player: Player)
		makeStats(player)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(updateBoards)
	end)
	task.spawn(function()
		local t = 0
		while true do
			task.wait(1)
			t += 1
			updateStats()
			if t % 5 == 1 then
				local ok, err = pcall(updateBoards)
				if not ok then
					warn("[LeaderboardService] " .. tostring(err))
				end
			end
		end
	end)
end

return LeaderboardService
